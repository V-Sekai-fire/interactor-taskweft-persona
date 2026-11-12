// Copyright (c) 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: Apache-2.0 OR MIT
// The command battle: a lead and a caster against one foe a round, 30 rounds for a normal run and 60 for
// plus. The planner decides which commands are legal, what each one does and how the foe replies; the page
// only keeps the run between rounds. Round scaling and party maximums mirror tools/command_battle.py.
(() => {
  const here = document.currentScript ? document.currentScript.src.replace(/[^/]*$/, "") : "assets/";
  const host = document.getElementById("battle");
  if (!host) return;
  const DOMAIN_URL = new URL("../samples/domains/command-battle.jsonld", here).href;
  const CTX = { VSEKAI: "https://v-sekai.org/", domain: "VSEKAI:planning/domain/" };
  const foeFor = (r) => ({ hp: 260 + 20 * (r - 1), atk: 40 + 2 * (r - 1) });
  const COMMANDS = [
    [["cmd-lead-attack", "Attack"], ["cmd-lead-skill", "Skill"], ["cmd-lead-finisher", "Finisher"]],
    [["cmd-caster-attack", "Attack"], ["cmd-caster-cast", "Cast"], ["cmd-caster-release", "Release"]],
  ];
  const POLICY = ["lead-policy", "caster-policy"];
  const NAME = ["Lead", "Caster"];
  const SAY = {
    "lead-attack": (p) => `Lead attacks. Foe at ${p[0]} HP, gauge ${p[1]}.`,
    "lead-skill": (p) => `Lead uses a skill. Foe at ${p[0]} HP, gauge ${p[1]}.`,
    "lead-finisher": (p) => `Lead's finisher. Foe at ${p[0]} HP, gauge empty.`,
    "caster-attack": (p) => `Caster attacks. Foe at ${p[0]} HP.`,
    "caster-cast": () => "Caster begins a spell.",
    "caster-release": (p) => `Caster releases the spell. Foe at ${p[0]} HP.`,
    "foe-strike-lead": (p) => `Foe strikes the lead, down to ${p[0]} HP.`,
    "foe-strike-caster": (p) => `Foe strikes the caster, down to ${p[0]} HP.`,
    "skip-lead": () => "The lead is down and loses the turn.",
    "skip-caster": () => "The caster is down and loses the turn.",
  };
  const h = (tag, attrs = {}, text) => {
    const e = document.createElement(tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (text !== undefined) e.textContent = text;
    return e;
  };

  let plan = null, domainText = "", actions = {}, mode = 30, run = null, state = null;

  const fresh = (round, gauge) => {
    const f = foeFor(round);
    return { lead: { hp: 300, max: 300, gauge }, caster: { hp: 200, max: 200, charge: 0 },
      foe: { hp: f.hp, max: f.hp, atk: f.atk }, turn: { slot: 0 }, result: { won: 0, lost: 0 } };
  };
  function ask(todo) {
    const p = { "@context": CTX, "@type": "domain:Problem", name: "command_battle_round_" + run.round,
      domain: "command_battle", variables: Object.entries(state).map(([name, init]) => ({ name, type: "int", init })),
      todo_list: todo };
    return JSON.parse(plan(domainText, JSON.stringify(p), ""));
  }
  // Each step's effects come from the action's own pointer/set entries in the domain, not from this page.
  function apply(steps) {
    for (const s of steps) {
      const a = actions[s.action];
      if (!a) throw new Error("the plan names an action the domain lacks: " + s.action);
      const args = Object.fromEntries((a.params || []).map((p, i) => [p, Number(s.params[i])]));
      for (const b of a.body || []) {
        if (!("pointer/set" in b)) continue;
        const [, v, k] = b["pointer/set"].split("/");
        state[v][k] = typeof b.value === "object" ? args[b.value.param] : b.value;
      }
      const say = SAY[s.action];
      if (say) ui.log.prepend(h("li", {}, say(s.params || [])));
    }
    while (ui.log.children.length > 14) ui.log.lastChild.remove();
  }

  const ui = {
    run: h("p", { class: "bt-run" }),
    modes: h("div", { class: "bt-row" }),
    units: h("div", { class: "bt-units" }),
    status: h("p", { class: "bt-status", role: "status" }, "Loading the persona planner..."),
    cmds: h("div", { class: "bt-row bt-cmds" }),
    forecast: h("p", { class: "bt-forecast" }),
    log: h("ol", { class: "bt-log", "aria-live": "polite", reversed: "" }),
  };
  host.replaceChildren(h("h2", { class: "bt-title" }, "Command battle"), ui.run, ui.modes, ui.units, ui.status,
    ui.cmds, ui.forecast, ui.log);

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
  function newRun(m) {
    mode = m;
    run = { round: 1, limit: m };
    state = fresh(1, 0);
    ui.log.replaceChildren();
    render();
  }
  function act(todo) {
    const r = ask(todo);
    if (r.refused) { ui.status.textContent = "The planner refused that: " + r.refused + "."; return; }
    apply(r.steps || []);
    render();
  }
  function render() {
    const s = state;
    ui.run.textContent = `Round ${run.round} / ${run.limit}` + (run.limit === 60 ? " (plus)" : " (normal)");
    ui.modes.replaceChildren(
      button("New normal run (30)", () => newRun(30), true, mode === 30 ? "bt-on" : ""),
      button("New plus run (60)", () => newRun(60), true, mode === 60 ? "bt-on" : ""));
    ui.units.replaceChildren(
      bar("Lead", s.lead.hp, s.lead.max, `gauge ${s.lead.gauge}/100`),
      bar("Caster", s.caster.hp, s.caster.max, s.caster.charge ? "spell ready" : ""),
      bar("Foe", s.foe.hp, s.foe.max, `strikes for ${s.foe.atk}`));
    ui.cmds.replaceChildren();
    ui.forecast.textContent = "";
    if (s.foe.hp === 0) {
      if (run.round >= run.limit) { ui.status.textContent = `Run cleared: all ${run.limit} rounds won.`; return; }
      ui.status.textContent = `Round ${run.round} won. The party heals; the lead keeps its gauge.`;
      ui.cmds.append(button("Next round", () => { run.round += 1; state = fresh(run.round, s.lead.gauge); render(); }));
      return;
    }
    if (s.lead.hp === 0 && s.caster.hp === 0) {
      ui.status.textContent = `The party fell in round ${run.round} of ${run.limit}. The run is over.`;
      return;
    }
    const slot = s.turn.slot;
    if (slot !== 0 && slot !== 1) { ui.status.textContent = "The planner left the turn with the foe; this is a bug."; return; }
    ui.status.textContent = NAME[slot] + "'s turn. Pick a command.";
    for (const [id, label] of COMMANDS[slot]) {
      const legal = !ask([[id]]).refused;
      ui.cmds.append(button(label, () => act([[id], ["respond"]]), legal));
    }
    ui.cmds.append(button("Persona's choice", () => act([[POLICY[slot]], ["respond"]]), true, "bt-persona"));
    const f = ask([["play-out"]]);
    if (f.refused) ui.forecast.textContent = "The persona could not forecast this round: " + f.refused + ".";
    else {
      const steps = f.steps || [], end = steps.length ? steps[steps.length - 1].action : "";
      ui.forecast.textContent = "If the persona plays on from here, it " +
        (end === "victory" ? "wins" : end === "defeat" ? "loses" : "stops") + ` the round in ${steps.length - 1} steps.`;
    }
  }

  Promise.all([
    import(here + "persona.mjs").then((m) => m.default({ locateFile: (f) => here + f })),
    fetch(DOMAIN_URL).then((r) => { if (!r.ok) throw new Error("domain " + r.status); return r.text(); }),
  ])
    .then(([mod, text]) => {
      if (mod._persona_init() !== 0) throw new Error("persona_init failed");
      plan = mod.cwrap("persona_plan_jsonld", "string", ["string", "string", "string"]);
      domainText = text;
      actions = JSON.parse(text).actions;
      newRun(30);
    })
    .catch((e) => { ui.status.textContent = "The battle did not load: " + e; });
})();
