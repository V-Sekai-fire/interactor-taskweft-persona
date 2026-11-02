// Copyright (c) 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: Apache-2.0 OR MIT
// PARKED. A reference for the MiniZinc Challenge blocks-world work: an instance generator, an independent breadth-first
// minimum, and a replay of a plan against blocks.mzn rules. It calls persona_plan_shortest on a flat action encoding from a
// breadth-first entry point that was not merged (PR 17, closed); the merged persona_plan_shortest needs methods.
// Blocks world of the MiniZinc Challenge 2022 (blocks.mzn): n cubes, at most k piles, minimise moves.
const out = process.argv[2], K = +process.argv[3] || 3, NMAX = +process.argv[4] || 8, PER = +process.argv[5] || 4, LIMIT = +process.argv[6] || 300000;
const mod = await (await import(out + "/persona.mjs")).default({ locateFile: (f) => out + "/" + f });
mod._persona_init();
const shortest = mod.cwrap("persona_plan_shortest", "string", ["string", "string", "number"]);
let seed = 12345; const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
// a state is below[c-1] = cube c rests on cube x, 0 = table
function randomState(n, k) {
  const order = [...Array(n).keys()].map((i) => i + 1).sort(() => rnd() - 0.5);
  const piles = Array.from({ length: k }, () => []);
  order.forEach((c) => piles[Math.floor(rnd() * k)].push(c));
  const below = Array(n).fill(0);
  piles.forEach((p) => p.forEach((c, i) => (below[c - 1] = i ? p[i - 1] : 0)));
  return below;
}
const clearOf = (below, n) => { const has = new Set(below); return [...Array(n).keys()].map((i) => i + 1).filter((c) => !has.has(c)); };
const tableCount = (below) => below.filter((x) => x === 0).length;
function neighbours(below, n, k) {
  const out = [];
  const clr = clearOf(below, n);
  for (const c of clr) for (const y of [0, ...clr]) {
    if (y === c || y === below[c - 1]) continue;
    if (y === 0 && tableCount(below) >= k) continue;
    const b = below.slice(); b[c - 1] = y; out.push([b, [c, below[c - 1], y]]);
  }
  return out;
}
function refShortest(start, goal, n, k) {
  const key = (b) => b.join(","), g = key(goal), seen = new Map([[key(start), 0]]); let frontier = [start], d = 0;
  while (frontier.length) {
    if (frontier.some((b) => key(b) === g)) return d;
    const next = []; d++;
    for (const b of frontier) for (const [nb] of neighbours(b, n, k)) { const kk = key(nb); if (!seen.has(kk)) { seen.set(kk, d); next.push(nb); } }
    frontier = next;
  }
  return null;
}
function persona(start, goal, n, k) {
  const A = {}, on = {}, clr = {}, tc = {};
  for (let c = 1; c <= n; c++) for (let x = 0; x <= n; x++) if (x !== c) on[c + "_" + x] = 0;
  const has = new Set(start); for (let c = 1; c <= n; c++) clr[c] = has.has(c) ? 0 : 1;
  for (let j = 0; j <= k; j++) tc[j] = 0; tc[tableCount(start)] = 1;
  start.forEach((x, i) => (on[i + 1 + "_" + x] = 1));
  const ge = (p) => ({ eval: { type: "math/ge", a: { type: "pointer/get", pointer: p }, b: 1 } });
  const set = (p, v) => ({ "pointer/set": p, value: v });
  for (let c = 1; c <= n; c++) for (let x = 0; x <= n; x++) for (let y = 0; y <= n; y++) {
    if (x === c || y === c || x === y) continue;
    if (x === 0 && y === 0) continue;
    const base = [ge(`/on/${c}_${x}`), ge(`/clr/${c}`)];
    const eff = [set(`/on/${c}_${x}`, 0), set(`/on/${c}_${y}`, 1)];
    if (x !== 0) eff.push(set(`/clr/${x}`, 1));
    if (y !== 0) { base.push(ge(`/clr/${y}`)); eff.push(set(`/clr/${y}`, 0)); }
    if (y === 0) for (let j = 0; j < k; j++) A[`mv-${c}-${x}-0-${j}`] = { body: [...base, ge(`/tc/${j}`), ...eff, set(`/tc/${j}`, 0), set(`/tc/${j + 1}`, 1)] };
    else if (x === 0) for (let j = 1; j <= k; j++) A[`mv-${c}-0-${y}-${j}`] = { body: [...base, ge(`/tc/${j}`), ...eff, set(`/tc/${j}`, 0), set(`/tc/${j - 1}`, 1)] };
    else A[`mv-${c}-${x}-${y}`] = { body: [...base, ...eff] };
  }
  const dom = { name: "blocks", variables: [], actions: A, methods: {} };
  const prob = { name: "blocks_problem", variables: [{ name: "on", init: on }, { name: "clr", init: clr }, { name: "tc", init: tc }],
    todo_list: [{ goal: goal.map((x, i) => ({ pointer: `/on/${i + 1}_${x}`, eq: 1 })) }] };
  const t = Date.now();
  const a = JSON.parse(shortest(JSON.stringify(dom), JSON.stringify(prob), LIMIT));
  return { a, ms: Date.now() - t, actions: Object.keys(A).length };
}
function replay(start, plan, goal, n, k) {
  let b = start.slice();
  for (const name of plan) {
    const [, c, x, y] = name.match(/^mv-(\d+)-(\d+)-(\d+)/).map(Number);
    if (b[c - 1] !== x || !clearOf(b, n).includes(c) || (y !== 0 && !clearOf(b, n).includes(y)) || (y === 0 && tableCount(b) >= k)) return false;
    b[c - 1] = y;
  }
  return b.join(",") === goal.join(",");
}
console.log("n k | cubes instance results (persona length = reference length, valid replay, ms, expanded)");
for (let n = 3; n <= NMAX; n++) {
  const rows = []; let failed = 0;
  for (let i = 0; i < PER; i++) {
    const start = randomState(n, K), goal = randomState(n, K);
    const ref = n <= 7 ? refShortest(start, goal, n, K) : null;
    const { a, ms, actions } = persona(start, goal, n, K);
    if (a.refused) { rows.push(`refused:${a.refused} ${ms}ms`); failed++; continue; }
    const plan = a.steps.map((s) => s.action), valid = replay(start, plan, goal, n, K);
    rows.push(`${a.length}${ref === null ? "" : ref === a.length ? "=" : "!=" + ref}${valid ? "" : " INVALID"} ${ms}ms e${a.expanded}`);
    if (!valid || (ref !== null && ref !== a.length)) failed++;
  }
  console.log(`n=${n} k=${K}: ${rows.join(" | ")}`);
  if (rows.every((r) => r.startsWith("refused"))) { console.log("frontier: every instance at n=" + n + " hit the limit"); break; }
}
