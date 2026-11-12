// Copyright (c) 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: Apache-2.0 OR MIT
// The command battle: a party of four (lead, caster, guard, mender) against one foe a round, 30 rounds for a
// normal run and 60 for plus. BattleWitness.lean generates the domain and the first problem; the planner
// decides which commands are legal, what each does, how the foe replies and what the next round is. This page
// reads the roster and the commands from those files and applies each step from the action's pointer/set
// entries, so no rule lives here.
(() => {
  const here = document.currentScript ? document.currentScript.src.replace(/[^/]*$/, "") : "assets/";
  const host = document.getElementById("battle");
  if (!host) return;
  const SAMPLES = new URL("../samples/", here).href;
  const NOT_UNITS = new Set(["foe", "turn", "run", "result"]);
  const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
  const h = (tag, attrs = {}, text) => {
    const e = document.createElement(tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (text !== undefined) e.textContent = text;
    return e;
  };

  let plan = null, domainText = "", domain = null, start = null, members = [], cmds = {};
  let mode = 30, state = null;
  // What the console shows: the exact text sent to the planner and the exact text it answered, for the
  // command the player picked and for the forecast. Legality probes for the buttons are not recorded.
  const seen = { command: null, forecast: null };

  const copy = (o) => JSON.parse(JSON.stringify(o));
  function ask(todo, tag) {
    const p = Object.assign(copy(start.problem), {
      variables: Object.entries(state).map(([name, init]) => ({ name, type: "int", init })), todo_list: todo });
    const request = JSON.stringify(p), raw = plan(domainText, request, "");
    if (tag) seen[tag] = { request, raw };
    return JSON.parse(raw);
  }
  // Each step's effects come from the action's own pointer/set entries in the domain, not from this page.
  function apply(steps) {
    for (const s of steps) {
      const a = domain.actions[s.action];
      if (!a) throw new Error("the plan names an action the domain lacks: " + s.action);
      const args = Object.fromEntries((a.params || []).map((p, i) => [p, Number(s.params[i])]));
      for (const b of a.body || []) {
        if (!("pointer/set" in b)) continue;
        const ptr = b["pointer/set"];
        if (ptr.includes("[")) throw new Error("templated pointer " + ptr + " is not applied by this page");
        const [, v, k] = ptr.split("/");
        const val = typeof b.value === "object" ? args[b.value.param] : b.value;
        if (!Number.isFinite(val)) throw new Error(s.action + " sets " + ptr + " to " + val);
        state[v][k] = val;
      }
      ui.log.prepend(h("li", {}, say(s)));
    }
    while (ui.log.children.length > 16) ui.log.lastChild.remove();
  }
  function say(s) {
    const p = s.params || [];
    const [who, ...rest] = s.action.split("-");
    const what = rest.join(" ");
    if (s.action.startsWith("foe-strike-")) return `Foe strikes the ${s.action.slice(11)}, down to ${p[0]} HP.`;
    if (s.action.startsWith("mender-heal-")) return `Mender heals the ${s.action.slice(12)} to ${p[0]} HP (${p[1]} heals left).`;
    if (s.action.startsWith("skip-")) return `The ${s.action.slice(5)} is down and loses the turn.`;
    if (s.action === "next-round") return `Round ${p[0]}: a foe with ${p[1]} HP that strikes for ${p[2]}. The party is back to full.`;
    if (s.action === "victory") return "The foe is down.";
    if (s.action === "defeat") return "The whole party is down.";
    return `${cap(who)} ${what}` + (p.length ? ` (foe at ${p[0]} HP)` : "") + ".";
  }

  const ui = {
    run: h("p", { class: "bt-run" }),
    modes: h("div", { class: "bt-row" }),
    units: h("div", { class: "bt-units" }),
    status: h("p", { class: "bt-status", role: "status" }, "Loading the persona planner..."),
    cmds: h("div", { class: "bt-row bt-cmds" }),
    forecast: h("p", { class: "bt-forecast" }),
    log: h("ol", { class: "bt-log", "aria-live": "polite", reversed: "" }),
    toggle: h("button", { type: "button", class: "bt-toggle", "aria-pressed": "false", "aria-controls": "bt-console" }, "Console"),
    console: h("div", { class: "bt-console", id: "bt-console" }),
  };
  ui.console.hidden = true;
  const panes = {};
  for (const [key, title] of [["domain", "Domain (JSON-LD)"], ["problem", "Problem sent with the last command (JSON-LD)"],
    ["answer", "Planner's answer to the last command"], ["forecast", "Planner's answer to the forecast (play-out)"]]) {
    const ta = h("textarea", { rows: "10", readonly: "", spellcheck: "false", wrap: "off", "aria-label": title });
    ui.console.append(h("label", { class: "bt-pane" }, title), ta);
    panes[key] = ta;
  }
  const pretty = (s) => { try { return JSON.stringify(JSON.parse(s), null, 1); } catch (e) { return s; } };
  function fillConsole() {
    if (ui.console.hidden) return;
    if (!panes.domain.value) panes.domain.value = pretty(domainText);
    panes.problem.value = seen.command ? pretty(seen.command.request) : "No command yet. Pick one, or press Persona's choice.";
    panes.answer.value = seen.command ? pretty(seen.command.raw) : "";
    panes.forecast.value = seen.forecast ? pretty(seen.forecast.raw) : "No forecast for this state.";
  }
  ui.toggle.addEventListener("click", () => {
    ui.console.hidden = !ui.console.hidden;
    ui.toggle.setAttribute("aria-pressed", String(!ui.console.hidden));
    fillConsole();
  });
  const head = h("div", { class: "bt-head" });
  head.append(h("h2", { class: "bt-title" }, "Command battle"), ui.toggle);
  host.replaceChildren(head, ui.run, ui.modes, ui.units, ui.status, ui.cmds, ui.forecast, ui.log, ui.console);

  function bar(label, hp, max, extra) {
    const row = h("div", { class: "bt-unit" + (hp === 0 ? " bt-down" : "") });
    row.append(h("span", { class: "bt-name" }, label));
    const b = h("span", { class: "bt-bar", role: "meter", "aria-valuemin": "0", "aria-valuemax": String(max),
      "aria-valuenow": String(hp), "aria-label": label + " HP" });
    const fill = h("span", { class: "bt-fill" });
    fill.style.width = (max ? (100 * hp) / max : 0) + "%";
    b.append(fill);
    row.append(b, h("span", { class: "bt-num" }, `${hp}/${max}` + (extra ? "  " + extra : "")));
    return row;
  }
  function button(label, onClick, enabled = true, cls = "") {
    const b = h("button", { type: "button", class: cls }, label);
    b.disabled = !enabled;
    b.addEventListener("click", onClick);
    return b;
  }
  function extra(m) {
    const u = state[m];
    if ("gauge" in u) return `gauge ${u.gauge}/100`;
    if ("charge" in u) return u.charge ? "spell ready" : "";
    if ("taunt" in u) return u.taunt ? "taunting" : "";
    if ("heals" in u) return `${u.heals} heals`;
    return "";
  }
  function newRun(m) {
    mode = m;
    state = Object.fromEntries(start.problem.variables.map((v) => [v.name, copy(v.init)]));
    state.run.limit = m;
    seen.command = null;
    ui.log.replaceChildren();
    render();
  }
  function act(todo) {
    const r = ask(todo, "command");
    if (r.refused) { ui.status.textContent = "The planner refused that: " + r.refused + "."; return; }
    apply(r.steps || []);
    render();
  }
  function render() {
    seen.forecast = null;
    draw();
    fillConsole();
  }
  function draw() {
    const s = state, round = s.run.round, limit = s.run.limit;
    ui.run.textContent = `Round ${round} / ${limit}` + (limit === 60 ? " (plus)" : " (normal)");
    ui.modes.replaceChildren(
      button("New normal run (30)", () => newRun(30), true, mode === 30 ? "bt-on" : ""),
      button("New plus run (60)", () => newRun(60), true, mode === 60 ? "bt-on" : ""));
    ui.units.replaceChildren(...members.map((m) => bar(cap(m), s[m].hp, s[m].max, extra(m))),
      bar("Foe", s.foe.hp, s.foe.max, `strikes for ${s.foe.atk}`));
    ui.cmds.replaceChildren();
    ui.forecast.textContent = "";
    if (s.foe.hp === 0) {
      const next = ask([["cmd-next-round"]]);
      if (next.refused) { ui.status.textContent = `Run cleared: all ${limit} rounds won.`; return; }
      ui.status.textContent = `Round ${round} won. The party heals; the lead keeps its gauge.`;
      ui.cmds.append(button("Next round", () => act([["cmd-next-round"]])));
      return;
    }
    if (members.every((m) => s[m].hp === 0)) {
      ui.status.textContent = `The party fell in round ${round} of ${limit}. The run is over.`;
      return;
    }
    const m = members[s.turn.slot];
    if (!m) { ui.status.textContent = "The planner left the turn with the foe; this is a bug."; return; }
    ui.status.textContent = cap(m) + "'s turn. Pick a command.";
    for (const [id, label] of cmds[m]) {
      const legal = !ask([[id]]).refused;
      ui.cmds.append(button(label, () => act([[id], ["respond"]]), legal));
    }
    ui.cmds.append(button("Persona's choice", () => act([[m + "-policy"], ["respond"]]), true, "bt-persona"));
    const f = ask([["play-out"]], "forecast");
    if (f.refused) ui.forecast.textContent = "The persona could not forecast this round: " + f.refused + ".";
    else {
      const steps = f.steps || [], end = steps.length ? steps[steps.length - 1].action : "";
      ui.forecast.textContent = "If the persona plays on from here, it " +
        (end === "victory" ? "wins" : end === "defeat" ? "loses" : "stops") + ` the round in ${steps.length - 1} steps.`;
    }
  }

  const text = (u) => fetch(u).then((r) => { if (!r.ok) throw new Error(u + " " + r.status); return r.text(); });
  Promise.all([
    import(here + "persona.mjs").then((m) => m.default({ locateFile: (f) => here + f })),
    text(SAMPLES + "domains/command-battle.jsonld"),
    text(SAMPLES + "problems/command-battle-round-1.jsonld"),
  ])
    .then(([mod, d, p]) => {
      if (mod._persona_init() !== 0) throw new Error("persona_init failed");
      plan = mod.cwrap("persona_plan_jsonld", "string", ["string", "string", "string"]);
      domainText = d;
      domain = JSON.parse(d);
      start = { problem: JSON.parse(p) };
      members = start.problem.variables.map((v) => v.name).filter((n) => !NOT_UNITS.has(n));
      for (const m of members) {
        cmds[m] = Object.keys(domain.methods).filter((k) => k.startsWith("cmd-" + m + "-"))
          .map((k) => [k, cap(k.slice(5 + m.length).replace(/-/g, " "))]);
      }
      newRun(30);
    })
    .catch((e) => { ui.status.textContent = "The battle did not load: " + e; });
})();
