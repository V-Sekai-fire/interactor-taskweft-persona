// Copyright (c) 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: Apache-2.0 OR MIT
// The persona navigator: pick an RFD, get the route to it from the persona planner.
// Surface level: a picker and the steps in order. Console level: the JSON-LD documents the
// planner reads, its raw answer and the refusal by name. The planner runs in this page as WebAssembly.
(async () => {
  const here = document.currentScript ? document.currentScript.src.replace(/[^/]*$/, "") : "assets/";
  const host = document.getElementById("navigator");
  if (!host) return;
  // The RFD site publishes the tree and the campus documents; this page is a separate site.
  const RFD = "https://v-sekai-fire.github.io/rfds/assets/";
  const data = await fetch(RFD + "campus.tree.json").then((r) => r.json()).catch(() => null);
  if (!data) {
    host.textContent = "The navigator could not load the RFD tree from " + RFD + ", so there is no route to show.";
    return;
  }
  const byN = new Map(data.nodes.map((n) => [n.n, n]));
  const tokenName = new Map([...data.tokens, ...data.boring].map((t) => [String(t.i), t.name]));
  const tokenRepo = new Map([...data.tokens, ...data.boring]
    .filter((t) => t.repos.length).map((t) => [String(t.i), t.repos.join(", ")]));
  const h = (tag, attrs = {}, text) => {
    const e = document.createElement(tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (text !== undefined) e.textContent = text;
    return e;
  };
  const REFUSALS = {
    bad_domain: "The domain document is not valid JSON-LD the planner can read.",
    bad_problem: "The problem document is not valid JSON-LD the planner can read.",
    no_goal: "The problem names no goal.",
    undeclared_goal: "No variable in the domain or problem declares that goal.",
    unreachable: "No method chain reaches that goal from the facts that hold. A token we neither own nor may use blocks a route.",
  };

  const state = { mod: null, domain: "", problem: "", goals: [], level: "surface", last: null };
  let engine = null;

  // The engine's own loader accepts a broken document as an empty one, so the page checks first.
  const parse = (text, why) => { try { return JSON.parse(text); } catch (e) { return why; } };
  function ask(goal) {
    const d = parse(state.domain, "bad_domain");
    if (typeof d === "string") return { refused: d };
    const p = parse(state.problem, "bad_problem");
    if (typeof p === "string") return { refused: p };
    const n = /^\/rfd\/(\d+)$/.exec(goal);
    if (!n) return { refused: "undeclared_goal" };
    p.todo_list = [["reach-rfd-" + n[1]]];
    const raw = engine(state.domain, JSON.stringify(p), "");
    state.last = raw;
    return JSON.parse(raw);
  }

  const ui = {
    status: h("p", { class: "nv-status", role: "status" }, "Loading the persona planner..."),
    pick: h("select", { id: "nv-pick", "aria-label": "RFD to plan a route to" }),
    toggle: h("button", { type: "button", class: "nv-toggle", "aria-pressed": "false" }, "Console"),
    out: h("div", { class: "nv-out", "aria-live": "polite" }),
    console: h("div", { class: "nv-console" }),
  };
  ui.console.hidden = true;
  ui.pick.disabled = true;

  const label = h("label", { for: "nv-pick" }, "Where do you want to get to?");
  const row = h("div", { class: "nv-row" });
  row.append(label, ui.pick, ui.toggle);
  host.replaceChildren(h("h2", { class: "nv-title" }, "Persona navigator"), row, ui.status, ui.out, ui.console);

  function stepNode(action, i) {
    const li = h("li");
    const settle = /^settle-(\d+)$/.exec(action);
    const token = /^acquire-token-(.+)-(owned|access)$/.exec(action);
    if (settle) {
      const n = byN.get(+settle[1]);
      const a = h("a", { href: n ? "#" + n.id : "#" }, "RFD66606-" + settle[1] + (n ? " " + n.t : ""));
      li.append("Settle ", a);
    } else if (token) {
      const repo = tokenRepo.get(token[1]);
      const how = token[2] === "owned" ? "ours" : "third party, we have access";
      li.append("Acquire " + (tokenName.get(token[1]) || "token " + token[1])
        + " (" + how + (repo ? ", from " + repo : "") + ")");
    } else {
      li.append(action);
    }
    return li;
  }

  function needs(goal, answer) {
    const n = /^\/rfd\/(\d+)$/.exec(goal);
    if (!n) return null;
    const cone = new Set();
    const queue = [+n[1]];
    while (queue.length) {
      const id = queue.pop();
      if (cone.has(id) || !byN.has(id)) continue;
      cone.add(id);
      queue.push(...byN.get(id).c);
    }
    const used = new Set();
    cone.forEach((id) => [...byN.get(id).k, ...byN.get(id).b].forEach((t) => used.add(String(t))));
    const all = [...data.tokens, ...data.boring];
    for (let grew = true; grew;) {
      grew = false;
      all.filter((t) => used.has(String(t.i))).forEach((t) => t.via.forEach((v) => {
        if (!used.has(String(v))) { used.add(String(v)); grew = true; }
      }));
    }
    const toks = all.filter((t) => used.has(String(t.i)));
    const names = (list) => list.map((t) => t.name + (t.repos.length ? " (" + t.repos.join(", ") + ")" : "")).join(", ") || "none";
    const todo = [...cone].filter((id) => byN.get(id).s !== "committed").sort((x, y) => x - y);
    const shown = todo.slice(0, 5).map((id) => "rfd-" + id).join(", ") + (todo.length > 5 ? ", and " + (todo.length - 5) + " more" : "");
    const taken = new Set(((answer && answer.steps) || []).map((st) => st.action));
    const options = Object.entries(data.caps || {})
      .filter(([, ps]) => ps.some((id) => cone.has(id)))
      .map(([token, ps]) => [
        "Options for " + token,
        ps.map((id) => "rfd-" + id + (taken.has("settle-" + id) ? " (taken)" : "")).join(" or "),
        false,
      ]);
    return [
      ...options,
      ["Capability tokens we still lack (each open RFD is one)", todo.length + " of " + cone.size + (todo.length ? ": " + shown : ""), false],
      ["Tokens we own", names(toks.filter((t) => t.own)), false],
      ["Third-party tokens we have access to", names(toks.filter((t) => !t.own && t.access)), false],
      ["Third-party tokens we do not have access to", names(toks.filter((t) => !t.own && !t.access)),
        toks.some((t) => !t.own && !t.access)],
    ];
  }

  function showNeeds(goal, answer) {
    const rows = needs(goal, answer);
    if (!rows) return;
    const ul = h("ul", { class: "nv-needs" });
    rows.forEach(([label, text, blocker]) => ul.append(h("li", blocker ? { class: "nv-refused" } : {}, label + ": " + text)));
    ui.out.append(ul);
  }

  function showSurface(answer, goal) {
    ui.out.replaceChildren();
    if (answer.refused) {
      ui.out.append(h("p", { class: "nv-refused" }, "Refused: " + (REFUSALS[answer.refused] || answer.refused)));
      showNeeds(goal, answer);
      return;
    }
    const steps = answer.steps || [];
    const settles = steps.filter((s) => /^settle-/.test(s.action)).length;
    const rn = /^\/rfd\/(\d+)$/.exec(goal);
    const node = rn ? byN.get(+rn[1]) : null;
    const name = rn ? "RFD66606-" + rn[1] + (node ? " " + node.t : "") : goal;
    // The destination is a real link, so it opens in place, in a new tab, or by middle click.
    const dest = node ? h("a", { href: "#" + node.id, class: "nv-dest" }, name) : name;
    const p = h("p");
    p.append(answer.reached ? "Reached " : "Did not reach ", dest,
      " in " + steps.length + " steps (" + settles + " RFDs to settle).");
    ui.out.append(p);
    showNeeds(goal, answer);
    const ol = h("ol", { class: "nv-steps" });
    steps.forEach((s, i) => ol.append(stepNode(s.action, i)));
    ui.out.append(ol);
  }

  // Built once, so a plan never collapses a panel or drops an edit that is still being typed.
  let rawBox = null;
  function showConsole() {
    if (rawBox) { rawBox.value = state.last === null ? "" : state.last; return; }
    const doc = (title, text, editable, key) => {
      const d = h("details", {});
      d.append(h("summary", {}, title));
      const t = h("textarea", { rows: "8", spellcheck: "false", "aria-label": title });
      t.value = text;
      t.readOnly = !editable;
      if (editable) t.addEventListener("change", () => { state[key] = t.value; refreshGoals(); plan(); });
      d.append(t);
      return [d, t];
    };
    const [dd] = doc("Domain (JSON-LD, editable)", state.domain, true, "domain");
    const [pd] = doc("Problem (JSON-LD, editable)", state.problem, true, "problem");
    const [rd, rt] = doc("Raw answer", state.last === null ? "" : state.last, false);
    rawBox = rt;
    const copy = h("button", { type: "button" }, "Copy answer");
    copy.addEventListener("click", () => navigator.clipboard && navigator.clipboard.writeText(rawBox.value));
    ui.console.append(dd, pd, rd, copy);
  }

  function refreshGoals() {
    const d = parse(state.domain, "bad_domain");
    const p = typeof d === "string" ? d : parse(state.problem, "bad_problem");
    const bad = typeof d === "string" ? d : typeof p === "string" ? p : null;
    if (bad) { ui.status.textContent = "Refused: " + REFUSALS[bad]; return; }
    ui.status.textContent = Object.keys(d.actions || {}).length + " actions and "
      + Object.keys(d.methods || {}).length + " methods; problem " + p.name + ". Planned by the RECTGTN planner, written in Lean.";
  }

  function fill() {
    ui.pick.replaceChildren();
    const open = data.nodes.filter((n) => n.s !== "committed").sort((a, b) => a.n - b.n);
    open.forEach((n) => ui.pick.append(h("option", { value: "/rfd/" + n.n }, "RFD66606-" + n.n + " " + n.t)));
    const goal = "/rfd/" + data.goal;
    if ([...ui.pick.options].some((o) => o.value === goal)) ui.pick.value = goal;
  }

  function plan() {
    const goal = ui.pick.value;
    state.last = "";
    const answer = ask(goal);
    if (answer.refused) state.last = JSON.stringify(answer);
    showSurface(answer, goal);
    if (state.level === "console") showConsole();
  }

  ui.pick.addEventListener("change", plan);
  ui.toggle.addEventListener("click", () => {
    state.level = state.level === "surface" ? "console" : "surface";
    ui.toggle.setAttribute("aria-pressed", String(state.level === "console"));
    ui.console.hidden = state.level !== "console";
    if (state.level === "console") showConsole();
  });

  Promise.all([
    import(here + "persona.mjs").then((m) => m.default({ locateFile: (f) => here + f })),
    fetch(RFD + "campus.domain.jsonld").then((r) => r.text()),
    fetch(RFD + "campus.problem.jsonld").then((r) => r.text()),
  ])
    .then(([mod, domain, problem]) => {
      if (mod._persona_init() !== 0) throw new Error("persona_init failed");
      state.mod = mod;
      state.domain = domain;
      state.problem = problem;
      engine = mod.cwrap("persona_plan_jsonld", "string", ["string", "string", "string"]);
      fill();
      refreshGoals();
      ui.pick.disabled = false;
      plan();
    })
    .catch((e) => {
      ui.status.textContent = "The persona planner did not load, so there is no route to show: " + e;
    });
})();
