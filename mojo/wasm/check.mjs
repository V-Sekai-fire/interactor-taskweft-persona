// SPDX-License-Identifier: MIT
// The gate for persona.mjs: the Mojo guest under libriscv in WebAssembly answers what Lean answers.
//   node check.mjs <dir with persona.mjs and persona.wasm> <repo root>
// Every check has a control that must fail: a changed plan, a wrong domain, a wrong version.
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

const [dir, root] = process.argv.slice(2);
const read = (p) => fs.readFileSync(path.join(root, p), "utf8");
const mod = await (await import(pathToFileURL(path.resolve(dir, "persona.mjs")).href)).default({
  locateFile: (f) => path.resolve(dir, f),
});
let bad = 0, n = 0;
const check = (name, ok, why = "") => { n++; if (!ok) bad++; console.log((ok ? "ok   " : "FAIL ") + name + (ok ? "" : "  " + why)); };
const refused = (name, ok, why = "") => check("control: " + name, ok, why);

check("persona_init returns 0", mod._persona_init() === 0);
const str = (name, args) => mod.cwrap(name, "string", args);
const plan = str("persona_plan_jsonld", ["string", "string", "string"]);
const goals = str("persona_goals", ["string", "string"]);
const shortest = str("persona_plan_shortest", ["string", "string", "number"]);
const ask = str("persona_ask", ["string"]);
const version = str("persona_version", []);
const grid = str("persona_plan", ["string"]);

const hash = mod._persona_translation_hash();
check("the guest runs on binary translation, not the interpreter", hash !== 0, "hash " + hash);
check("persona_version is 0.1.0", version() === "0.1.0", version());
refused("another version is refused", version() !== "0.0.0");

// What the Lean persona_goals answers for each problem (read off the Lean build). The battle's problem
// asks tasks, not goals, so its list is empty.
const cases = [
  ["campus sample", "domains/campus-sample.jsonld", "problems/campus-sample.jsonld", "plans/campus-sample.jsonld",
    '{"problem":"campus_sample_problem","actions":4,"methods":4,"goals":[{"goal":"/rfd/3","declared":true,"held":false}]}'],
  ["command battle", "domains/command-battle.jsonld", "problems/command-battle-start.jsonld", "plans/command-battle-run.jsonld",
    '{"problem":"command_battle_run","actions":24,"methods":21,"goals":[]}'],
];
for (const [name, d, p, g, lean_goals] of cases) {
  const dom = read(d), prob = read(p), gold = read(g).trim();
  const got = plan(dom, prob, "");
  check(`${name}: the plan equals the gold Lean wrote`, got.trim() === gold, got.slice(0, 120));
  check(`${name}: a second call gives the same bytes`, plan(dom, prob, "") === got);
  const changed = gold.replace('"reached":true', '"reached":false');
  refused(`${name}: a plan with reached changed does not match`, changed !== gold && got.trim() !== changed);
  check(`${name}: persona_goals equals the Lean answer`, goals(dom, prob) === lean_goals, goals(dom, prob));
  refused(`${name}: persona_goals is not the other problem's answer`, goals(dom, prob) !== cases.find((c) => c[0] !== name)[4]);
}

const dom = read(cases[0][1]), prob = read(cases[0][2]);
check("an undeclared goal is refused by name", JSON.parse(plan(dom, prob, "no-such-goal-xyzzy")).refused === "undeclared_goal");
check("a domain that is not JSON is refused by name", JSON.parse(plan("not json", prob, "")).refused === "bad_domain");
check("a problem that is not JSON is refused by name", JSON.parse(plan(dom, "not json", "")).refused === "bad_problem");
refused("the undeclared goal's answer is not taken for the plan", plan(dom, prob, "no-such-goal-xyzzy").trim() !== read(cases[0][3]).trim());
const sh = JSON.parse(shortest(dom, prob, 8));
check("persona_plan_shortest reaches the goal", sh.reached === true, JSON.stringify(sh).slice(0, 100));
check("persona_ask('') is the delivery plan", ask("") === '{"goal":"delivered","plan":["recharge","move_to_storage","pickup","move_to_shipping","dropoff"],"reached":true}', ask(""));
check("persona_ask refuses an undeclared goal", ask("no-such-goal-xyzzy") === '{"refused":"undeclared_goal"}');
check("persona_plan reads a skill grid", JSON.parse(grid("skill 1 0\nskill 2 0 1\ngoal 2")).reached === true, grid("skill 1 0\nskill 2 0 1\ngoal 2"));

console.log(`${n - bad} of ${n} checks pass`);
process.exit(bad ? 1 : 0);
