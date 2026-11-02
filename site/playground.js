// Copyright (c) 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: Apache-2.0 OR MIT
// The persona playground: pick a sample domain and problem, edit them, and plan. The planner is the
// Lean RECTGTN planner running in this page as WebAssembly. Surface level: the steps in order.
// Console level: the two JSON-LD documents, editable, and the raw answer.
(() => {
  const here = document.currentScript ? document.currentScript.src.replace(/[^/]*$/, "") : "assets/";
  const base = here.replace(/assets\/$/, "");
  const host = document.getElementById("playground");
  if (!host) return;
  const G = "tests/gtpyhop/";
  const SAMPLES = [
    { name: "Campus, pointer shape", domain: "domains/campus-sample.jsonld", problem: "problems/campus-sample.jsonld" },
    { name: "Campus, reach-task shape", domain: "domains/campus-sample-reach.jsonld", problem: "problems/campus-sample-reach.jsonld" },
    { name: "GTPyhop blocks_gtn: the Sussman anomaly", domain: G + "blocks_gtn/domain.jsonld",
      problem: G + "blocks_gtn/sussman.problem.jsonld", expect: G + "blocks_gtn/sussman.expect" },
    { name: "GTPyhop blocks_gtn: goal1a, three blocks restacked", domain: G + "blocks_gtn/domain.jsonld",
      problem: G + "blocks_gtn/goal1a.problem.jsonld", expect: G + "blocks_gtn/goal1a.expect" },
    { name: "GTPyhop blocks_gtn: take a, put a on the table", domain: G + "blocks_gtn/domain.jsonld",
      problem: G + "blocks_gtn/take-a-put-a-table.problem.jsonld", expect: G + "blocks_gtn/take-a-put-a-table.expect" },
    { name: "GTPyhop blocks_gtn: pickup a, which fails", domain: G + "blocks_gtn/domain.jsonld",
      problem: G + "blocks_gtn/pickup-a.problem.jsonld", expect: G + "blocks_gtn/pickup-a.expect" },
    { name: "GTPyhop backtracking_htn: put_it then need1", domain: G + "backtracking_htn/domain.jsonld",
      problem: G + "backtracking_htn/put_it-need1.problem.jsonld", expect: G + "backtracking_htn/put_it-need1.expect" },
    { name: "Enums: members print as names", domain: "tests/enums/domain.jsonld",
      problem: "tests/enums/members-print-as-names.problem.jsonld", expect: "tests/enums/members-print-as-names.expect" },
    { name: "A graph decides the subtasks: first cell holding a 1", domain: "tests/graph/domain.jsonld",
      problem: "tests/graph/hit-in-the-middle.problem.jsonld", expect: "tests/graph/hit-in-the-middle.expect" },
    { name: "A problem's own codebook", domain: "tests/vocab/domain.jsonld",
      problem: "tests/vocab/names-print.problem.jsonld", expect: "tests/vocab/names-print.expect" },
  ];
  const REFUSALS = {
    bad_domain: "The domain document is not valid JSON-LD the planner can read.",
    bad_problem: "The problem document is not valid JSON-LD the planner can read.",
    no_goal: "The problem names no goal.",
    undeclared_goal: "No variable in the domain or problem declares that goal.",
    unreachable: "No method chain reaches the goal from the facts that hold.",
    limit: "No plan of the length tried reaches the goal.",
  };
  const h = (tag, attrs = {}, text) => {
    const e = document.createElement(tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (text !== undefined) e.textContent = text;
    return e;
  };
  const state = { domain: "", problem: "", level: "surface", last: "" };
  let plan = null;
  let shortest = null;
  let expected = null;
  const ui = {
    pick: h("select", { id: "pg-pick", "aria-label": "Sample" }),
    go: h("button", { type: "button" }, "Plan"),
    shortest: h("button", { type: "button" }, "Shortest"),
    toggle: h("button", { type: "button", "aria-pressed": "false" }, "Console"),
    status: h("p", { class: "pg-status", role: "status" }, "Loading the planner..."),
    out: h("div", { "aria-live": "polite" }),
    console: h("div", { class: "pg-console" }),
  };
  ui.console.hidden = true;
  ui.pick.disabled = ui.go.disabled = ui.shortest.disabled = true;
  SAMPLES.forEach((s, i) => ui.pick.append(h("option", { value: String(i) }, s.name)));
  const row = h("div", { class: "pg-row" });
  row.append(h("label", { for: "pg-pick" }, "Sample:"), ui.pick, ui.go, ui.shortest, ui.toggle);
  host.replaceChildren(h("h2", { class: "pg-title" }, "Persona playground"), row, ui.status, ui.out, ui.console);

  let boxes = null;
  function buildConsole() {
    const box = (title, key, editable) => {
      const d = h("details");
      d.append(h("summary", {}, title));
      const t = h("textarea", { rows: "9", spellcheck: "false", "aria-label": title });
      t.readOnly = !editable;
      if (editable) t.addEventListener("input", () => { state[key] = t.value; });
      d.append(t);
      return [d, t];
    };
    const [dd, dt] = box("Domain (JSON-LD, editable)", "domain", true);
    const [pd, pt] = box("Problem (JSON-LD, editable)", "problem", true);
    const [rd, rt] = box("Raw answer", "last", false);
    ui.console.append(dd, pd, rd);
    boxes = { domain: dt, problem: pt, last: rt };
  }
  function sync() {
    if (!boxes) return;
    boxes.domain.value = state.domain;
    boxes.problem.value = state.problem;
    boxes.last.value = state.last;
  }

  /** The plan as GTPyhop's expected lines, name(args), or REFUSED:why. */
  const lines = (answer) => answer.refused ? ["REFUSED:" + answer.refused]
    : (answer.steps || []).map((s) => s.action + (s.params && s.params.length ? "(" + s.params.join(",") + ")" : ""));

  function showExpected(answer) {
    if (!expected) return;
    const got = lines(answer);
    const same = got.length === expected.length && got.every((x, i) => x === expected[i]);
    ui.out.append(h("p", { class: same ? "pg-status" : "pg-refused" },
      (same ? "Matches the plan GTPyhop expects: " : "Differs from the plan GTPyhop expects: ") + expected.join(", ") + "."));
  }

  function show(answer) {
    ui.out.replaceChildren();
    if (answer.refused) {
      ui.out.append(h("p", { class: "pg-refused" }, "Refused: " + (REFUSALS[answer.refused] || answer.refused)));
      showExpected(answer);
      return;
    }
    const steps = answer.steps || [];
    const t = answer.temporal;
    ui.out.append(h("p", {}, (answer.reached ? "Reached the goal in " : "Did not reach the goal in ") + steps.length
      + " steps" + (t && t.total ? ", critical path " + t.total : "") + "."));
    const ol = h("ol", { class: "pg-steps" });
    steps.forEach((s) => {
      const when = s.start ? " (" + s.start + " to " + s.end + ", " + s.duration + ")" : s.duration ? " (" + s.duration + ")" : "";
      ol.append(h("li", {}, s.action + (s.params && s.params.length ? "(" + s.params.join(",") + ")" : "") + when));
    });
    ui.out.append(ol);
    if (answer.optimal) ui.out.append(h("p", { class: "pg-status" }, "A shortest plan: " + answer.length + " actions."));
    showExpected(answer);
  }

  async function load(i) {
    const s = SAMPLES[i];
    const [d, p] = await Promise.all([
      fetch(base + "samples/" + s.domain).then((r) => r.text()),
      fetch(base + "samples/" + s.problem).then((r) => r.text()),
    ]);
    expected = s.expect
      ? (await fetch(base + "samples/" + s.expect).then((r) => r.text())).split("\n").filter((x) => x !== "")
      : null;
    state.domain = d;
    state.problem = p;
    state.last = "";
    sync();
    ui.out.replaceChildren();
    ui.status.textContent = "Loaded " + s.name + ". Press Plan.";
  }
  function run() {
    try { JSON.parse(state.domain); } catch (e) { state.last = ""; show({ refused: "bad_domain" }); return; }
    try { JSON.parse(state.problem); } catch (e) { state.last = ""; show({ refused: "bad_problem" }); return; }
    state.last = plan(state.domain, state.problem, "");
    sync();
    show(JSON.parse(state.last));
  }

  ui.shortest.addEventListener("click", () => {
    try { JSON.parse(state.domain); JSON.parse(state.problem); } catch (e) { show({ refused: "bad_domain" }); return; }
    state.last = shortest(state.domain, state.problem, 40);
    sync();
    show(JSON.parse(state.last));
  });
  ui.pick.addEventListener("change", () => load(+ui.pick.value));
  ui.go.addEventListener("click", run);
  ui.toggle.addEventListener("click", () => {
    state.level = state.level === "surface" ? "console" : "surface";
    ui.toggle.setAttribute("aria-pressed", String(state.level === "console"));
    ui.console.hidden = state.level !== "console";
    if (!boxes) { buildConsole(); sync(); }
  });

  import(here + "persona.mjs")
    .then((m) => m.default({ locateFile: (f) => here + f }))
    .then((mod) => {
      if (mod._persona_init() !== 0) throw new Error("persona_init failed");
      plan = mod.cwrap("persona_plan_jsonld", "string", ["string", "string", "string"]);
      shortest = mod._persona_plan_shortest ? mod.cwrap("persona_plan_shortest", "string", ["string", "string", "number"]) : null;
      ui.pick.disabled = ui.go.disabled = false;
      ui.shortest.disabled = !shortest;
      return load(0);
    })
    .catch((e) => { ui.status.textContent = "The planner did not load: " + e; });
})();
