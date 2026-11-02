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
  const SAMPLES = [
    { name: "Campus, pointer shape", domain: "campus-sample.jsonld", problem: "campus-sample.jsonld" },
    { name: "Campus, reach-task shape", domain: "campus-sample-reach.jsonld", problem: "campus-sample-reach.jsonld" },
  ];
  const REFUSALS = {
    bad_domain: "The domain document is not valid JSON-LD the planner can read.",
    bad_problem: "The problem document is not valid JSON-LD the planner can read.",
    no_goal: "The problem names no goal.",
    undeclared_goal: "No variable in the domain or problem declares that goal.",
    unreachable: "No method chain reaches the goal from the facts that hold.",
  };
  const h = (tag, attrs = {}, text) => {
    const e = document.createElement(tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (text !== undefined) e.textContent = text;
    return e;
  };
  const state = { domain: "", problem: "", level: "surface", last: "" };
  let plan = null;
  const ui = {
    pick: h("select", { id: "pg-pick", "aria-label": "Sample" }),
    go: h("button", { type: "button" }, "Plan"),
    toggle: h("button", { type: "button", "aria-pressed": "false" }, "Console"),
    status: h("p", { class: "pg-status", role: "status" }, "Loading the planner..."),
    out: h("div", { "aria-live": "polite" }),
    console: h("div", { class: "pg-console" }),
  };
  ui.console.hidden = true;
  ui.pick.disabled = ui.go.disabled = true;
  SAMPLES.forEach((s, i) => ui.pick.append(h("option", { value: String(i) }, s.name)));
  const row = h("div", { class: "pg-row" });
  row.append(h("label", { for: "pg-pick" }, "Sample:"), ui.pick, ui.go, ui.toggle);
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

  function show(answer) {
    ui.out.replaceChildren();
    if (answer.refused) {
      ui.out.append(h("p", { class: "pg-refused" }, "Refused: " + (REFUSALS[answer.refused] || answer.refused)));
      return;
    }
    const steps = answer.steps || [];
    const t = answer.temporal;
    ui.out.append(h("p", {}, (answer.reached ? "Reached the goal in " : "Did not reach the goal in ") + steps.length
      + " steps" + (t && t.total ? ", critical path " + t.total : "") + "."));
    const ol = h("ol", { class: "pg-steps" });
    steps.forEach((s) => {
      const when = s.start ? " (" + s.start + " to " + s.end + ", " + s.duration + ")" : s.duration ? " (" + s.duration + ")" : "";
      ol.append(h("li", {}, s.action + when));
    });
    ui.out.append(ol);
  }

  async function load(i) {
    const s = SAMPLES[i];
    const [d, p] = await Promise.all([
      fetch(base + "samples/domains/" + s.domain).then((r) => r.text()),
      fetch(base + "samples/problems/" + s.problem).then((r) => r.text()),
    ]);
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
      ui.pick.disabled = ui.go.disabled = false;
      return load(0);
    })
    .catch((e) => { ui.status.textContent = "The planner did not load: " + e; });
})();
