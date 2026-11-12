-- Copyright (c) 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: Apache-2.0 OR MIT
import Persona.Jsonld
import Lean.Data.Json

/-! The command battle's gate. It writes the battle domain and its first round's problem, simulates the
same rules on its own, and checks that the planner plays every round of a run step for step as the
simulator does, carrying the lead's gauge between rounds the way the page does.

  `lake exe persona_battle_witness`        checks, exit 0 and print "OK:" when every invariant holds
  `lake exe persona_battle_witness write`  writes domains/command-battle.jsonld and its round 1 problem -/

open Lean

namespace BattleWitness

structure Cfg where
  leadMax : Int := 300
  casterMax : Int := 200
  attack : Int := 45
  skill : Int := 110
  finisher : Int := 220
  cAttack : Int := 25
  release : Int := 130
  gaugeStep : Int := 25
  gaugeFull : Int := 100
  skillCost : Int := 50
  skillReach : Int := 110
  castFloor : Int := 130

/-- The round's foe: hit points and the damage of a strike. -/
def foeFor (r : Nat) : Int × Int := (260 + 20 * ((r : Int) - 1), 40 + 2 * ((r : Int) - 1))

def jn (v : Int) : Json := toJson v
def js (s : String) : Json := Json.str s
def obj (kvs : List (String × Json)) : Json := Json.mkObj kvs
def arr (xs : List Json) : Json := Json.arr xs.toArray
def num (v : Int) : Json := obj [("type", jn 0), ("value", arr [jn v])]
def getP (p : String) : Json := obj [("type", js "pointer/get"), ("pointer", js p)]
def eqC (p : String) (v : Int) : Json := obj [("eval", obj [("type", js "math/eq"), ("a", getP p), ("b", jn v)])]
def geC (p : String) (v : Int) : Json := obj [("eval", obj [("type", js "math/ge"), ("a", getP p), ("b", jn v)])]
def par (x : String) : Json := obj [("param", js x)]
def ctx : Json := obj [("VSEKAI", js "https://v-sekai.org/"), ("domain", js "VSEKAI:planning/domain/")]

/-! A behavior graph, built node by node: node 0 starts it, and a last `variable/set` writes the outputs. -/
structure G where
  decl : Array String := #["event/onStart"]
  nodes : Array Json := #[]
  vars : Array Json := #[]
  outs : Array Json := #[]

abbrev GM := StateM G

def op (name : String) : GM Nat := do
  let g ← get
  match g.decl.findIdx? (· == name) with
  | some i => return i
  | none => set { g with decl := g.decl.push name }; return g.decl.size

def addNode (n : Json) : GM Json := do
  modify fun g => { g with nodes := g.nodes.push n }
  return obj [("node", jn ((← get).nodes.size : Int)), ("socket", js "value")]

def ptr (p : String) : GM Json := do
  let d ← op "pointer/get"
  addNode (obj [("declaration", jn d), ("configuration",
    obj [("pointer", obj [("value", arr [js p])]), ("type", obj [("value", arr [jn 0])])])])

def bin (o : String) (a b : GM Json) : GM Json := do
  let a ← a; let b ← b; let d ← op o
  addNode (obj [("declaration", jn d), ("values", obj [("a", a), ("b", b)])])

def sel (cnd a b : GM Json) : GM Json := do
  let cnd ← cnd; let a ← a; let b ← b; let d ← op "math/select"
  addNode (obj [("declaration", jn d), ("values", obj [("condition", cnd), ("a", a), ("b", b)])])

def out (k : String) (r : GM Json) : GM Unit := do
  let r ← r
  modify fun g => { g with vars := g.vars.push (obj [("id", js k), ("type", jn 0), ("value", arr [jn 0])]),
                           outs := g.outs.push r }

def finish : GM Json := do
  let d ← op "variable/set"
  let g ← get
  let n := g.vars.size
  let setter := obj [("declaration", jn d),
    ("configuration", obj [("variables", obj [("value", arr ((List.range n).map fun i => jn (Int.ofNat i)))])]),
    ("values", obj ((List.range n).map fun i => (toString i, g.outs[i]!)))]
  let all := g.nodes.push setter
  let start := obj [("declaration", jn 0), ("flows", obj [("out", obj [("node", jn (all.size : Int)), ("socket", js "in")])])]
  return obj [("types", arr [obj [("signature", js "int")], obj [("signature", js "bool")]]),
    ("variables", arr g.vars.toList), ("declarations", arr (g.decl.toList.map fun o => obj [("op", js o)])),
    ("nodes", arr (start :: all.toList))]

def mkGraph (b : GM Unit) : Json := (b *> finish).run' {}
def lit (v : Int) : GM Json := pure (num v)
def hit (amount : Int) : GM Json := bin "math/max" (bin "math/sub" (ptr "/foe/hp") (lit amount)) (lit 0)

def act (params : List String) (desc : String) (pre : List Json) (sets : List (String × Json)) : Json :=
  obj [("params", arr (params.map js)), ("description", js desc),
    ("body", arr (pre ++ sets.map fun (p, v) => obj [("pointer/set", js p), ("value", v)]))]

def alt (name : String) (check : List Json) (subtasks : List (List Json)) (graph : Option Json := none) : Json :=
  obj ([("name", js name), ("check", arr check), ("subtasks", arr (subtasks.map arr))] ++
    (match graph with | some g => [("graph", g)] | none => []))

def method (alts : List Json) : Json := obj [("params", arr []), ("alternatives", arr alts)]
def cmdM (check : List Json) (action : String) (outs : List String) (g : Json) : Json :=
  method [alt "go" check [js action :: outs.map par] (some g)]

def leadTurn : List Json := [eqC "/turn/slot" 0, geC "/lead/hp" 1, geC "/foe/hp" 1]
def casterTurn : List Json := [eqC "/turn/slot" 1, geC "/caster/hp" 1, geC "/foe/hp" 1]

def driver (name : String) (ends : Bool) : Json :=
  let base := [
    alt "foe-down" [eqC "/foe/hp" 0] (if ends then [[js "victory"]] else []),
    alt "party-down" [eqC "/lead/hp" 0, eqC "/caster/hp" 0] (if ends then [[js "defeat"]] else []),
    alt "foe" [eqC "/turn/slot" 2] [[js "foe-turn"], [js name]],
    alt "lead-down" [eqC "/turn/slot" 0, eqC "/lead/hp" 0] [[js "skip-lead"], [js name]],
    alt "caster-down" [eqC "/turn/slot" 1, eqC "/caster/hp" 0] [[js "skip-caster"], [js name]]]
  let rest := if ends then
      [alt "lead" [eqC "/turn/slot" 0] [[js "lead-policy"], [js name]],
       alt "caster" [eqC "/turn/slot" 1] [[js "caster-policy"], [js name]]]
    else [alt "party-to-move" [] []]
  method (base ++ rest)

def domain (c : Cfg) : Json :=
  let actions := [
    ("lead-attack", act ["h", "g"] s!"The lead attacks: {c.attack} damage, +{c.gaugeStep} gauge." leadTurn
      [("/foe/hp", par "h"), ("/lead/gauge", par "g"), ("/turn/slot", jn 1)]),
    ("lead-skill", act ["h", "g"] s!"The lead uses a skill: {c.skill} damage for {c.skillCost} gauge, on the same turn."
      (leadTurn ++ [geC "/lead/gauge" c.skillCost]) [("/foe/hp", par "h"), ("/lead/gauge", par "g"), ("/turn/slot", jn 1)]),
    ("lead-finisher", act ["h"] s!"The lead's finisher: needs a full gauge, empties it, {c.finisher} damage."
      (leadTurn ++ [geC "/lead/gauge" c.gaugeFull]) [("/foe/hp", par "h"), ("/lead/gauge", jn 0), ("/turn/slot", jn 1)]),
    ("caster-attack", act ["h"] s!"The caster attacks: {c.cAttack} damage." (casterTurn ++ [eqC "/caster/charge" 0])
      [("/foe/hp", par "h"), ("/turn/slot", jn 2)]),
    ("caster-cast", act [] "The caster begins a spell; it lands on the caster's next turn." (casterTurn ++ [eqC "/caster/charge" 0])
      [("/caster/charge", jn 1), ("/turn/slot", jn 2)]),
    ("caster-release", act ["h"] s!"The caster releases the spell: {c.release} damage." (casterTurn ++ [eqC "/caster/charge" 1])
      [("/foe/hp", par "h"), ("/caster/charge", jn 0), ("/turn/slot", jn 2)]),
    ("foe-strike-lead", act ["h"] "The foe strikes the lead." [eqC "/turn/slot" 2, geC "/foe/hp" 1, geC "/lead/hp" 1]
      [("/lead/hp", par "h"), ("/turn/slot", jn 0)]),
    ("foe-strike-caster", act ["h"] "The foe strikes the caster, once the lead is down."
      [eqC "/turn/slot" 2, geC "/foe/hp" 1, eqC "/lead/hp" 0, geC "/caster/hp" 1] [("/caster/hp", par "h"), ("/turn/slot", jn 0)]),
    ("skip-lead", act [] "A fallen lead loses the turn." [eqC "/turn/slot" 0, eqC "/lead/hp" 0] [("/turn/slot", jn 1)]),
    ("skip-caster", act [] "A fallen caster loses the turn." [eqC "/turn/slot" 1, eqC "/caster/hp" 0] [("/turn/slot", jn 2)]),
    ("victory", act [] "The foe is down: the round is won." [eqC "/foe/hp" 0] [("/result/won", jn 1)]),
    ("defeat", act [] "The party is down: the run ends." [eqC "/lead/hp" 0, eqC "/caster/hp" 0] [("/result/lost", jn 1)])]
  let foeHit (who : String) : Json := mkGraph (out "h" (bin "math/max" (bin "math/sub" (ptr s!"/{who}/hp") (ptr "/foe/atk")) (lit 0)))
  let methods := [
    ("cmd-lead-attack", cmdM leadTurn "lead-attack" ["h", "g"] (mkGraph do
      out "h" (hit c.attack)
      out "g" (bin "math/min" (bin "math/add" (ptr "/lead/gauge") (lit c.gaugeStep)) (lit c.gaugeFull)))),
    ("cmd-lead-skill", cmdM (leadTurn ++ [geC "/lead/gauge" c.skillCost]) "lead-skill" ["h", "g"] (mkGraph do
      out "h" (hit c.skill)
      out "g" (bin "math/sub" (ptr "/lead/gauge") (lit c.skillCost)))),
    ("cmd-lead-finisher", cmdM (leadTurn ++ [geC "/lead/gauge" c.gaugeFull]) "lead-finisher" ["h"] (mkGraph (out "h" (hit c.finisher)))),
    ("cmd-caster-attack", cmdM (casterTurn ++ [eqC "/caster/charge" 0]) "caster-attack" ["h"] (mkGraph (out "h" (hit c.cAttack)))),
    ("cmd-caster-cast", method [alt "go" (casterTurn ++ [eqC "/caster/charge" 0]) [[js "caster-cast"]]]),
    ("cmd-caster-release", cmdM (casterTurn ++ [eqC "/caster/charge" 1]) "caster-release" ["h"] (mkGraph (out "h" (hit c.release)))),
    ("foe-turn", method [
      alt "lead" [eqC "/turn/slot" 2, geC "/foe/hp" 1, geC "/lead/hp" 1] [[js "foe-strike-lead", par "h"]] (some (foeHit "lead")),
      alt "caster" [eqC "/turn/slot" 2, geC "/foe/hp" 1, eqC "/lead/hp" 0, geC "/caster/hp" 1]
        [[js "foe-strike-caster", par "h"]] (some (foeHit "caster"))]),
    ("respond", driver "respond" false),
    ("play-out", driver "play-out" true),
    ("lead-policy", method [
      alt "finisher" [geC "/lead/gauge" c.gaugeFull] [[js "cmd-lead-finisher"]],
      alt "skill" [geC "/lead/gauge" c.skillCost, geC "/graph/near" 1] [[js "cmd-lead-skill"]]
        (some (mkGraph (out "near" (sel (bin "math/le" (ptr "/foe/hp") (lit c.skillReach)) (lit 1) (lit 0))))),
      alt "attack" [] [[js "cmd-lead-attack"]]]),
    ("caster-policy", method [
      alt "release" [eqC "/caster/charge" 1] [[js "cmd-caster-release"]],
      alt "cast" [eqC "/caster/charge" 0, geC "/foe/hp" c.castFloor] [[js "cmd-caster-cast"]],
      alt "attack" [] [[js "cmd-caster-attack"]]])]
  obj [("@context", ctx), ("@type", js "domain:Definition"), ("name", js "command_battle"),
    ("source", js "interactor-taskweft-persona"), ("version", js "0.2.0"),
    ("description", js ("A turn-based command battle. A lead and a caster act in a fixed turn order, then the foe. " ++
      "Attacks build a gauge; a skill spends half of it on the same turn; a full gauge allows a finisher; " ++
      "a spell takes a turn to cast. The page plays one round at a time: 30 rounds for a normal run, 60 for plus.")),
    ("variables", arr (["lead", "caster", "foe", "turn", "result"].map fun v =>
      obj [("name", js v), ("type", js "int"), ("init", obj [])])),
    ("actions", obj actions), ("methods", obj methods)]

/-! The simulator: the same rules and the same policy, written without the planner. -/
structure St where
  lead : Int
  leadMax : Int
  gauge : Int
  caster : Int
  casterMax : Int
  charge : Int
  foe : Int
  foeMax : Int
  atk : Int
  slot : Int

def fresh (c : Cfg) (r : Nat) (gauge : Int) : St :=
  let (h, a) := foeFor r
  { lead := c.leadMax, leadMax := c.leadMax, gauge, caster := c.casterMax, casterMax := c.casterMax, charge := 0,
    foe := h, foeMax := h, atk := a, slot := 0 }

/-- The steps of a round played to its end, whether it was won, and the state it ends in. -/
def sim (c : Cfg) : Nat → St → Array String → Array String × Bool × St
  | 0, s, acc => (acc.push "NO-END", false, s)
  | fuel + 1, s, acc =>
    if s.foe == 0 then (acc.push "victory", true, s)
    else if s.lead == 0 && s.caster == 0 then (acc.push "defeat", false, s)
    else if s.slot == 2 then
      if s.lead ≥ 1 then let h := max (s.lead - s.atk) 0; sim c fuel { s with lead := h, slot := 0 } (acc.push s!"foe-strike-lead({h})")
      else let h := max (s.caster - s.atk) 0; sim c fuel { s with caster := h, slot := 0 } (acc.push s!"foe-strike-caster({h})")
    else if s.slot == 0 && s.lead == 0 then sim c fuel { s with slot := 1 } (acc.push "skip-lead")
    else if s.slot == 1 && s.caster == 0 then sim c fuel { s with slot := 2 } (acc.push "skip-caster")
    else if s.slot == 0 then
      if s.gauge ≥ c.gaugeFull then
        let h := max (s.foe - c.finisher) 0; sim c fuel { s with foe := h, gauge := 0, slot := 1 } (acc.push s!"lead-finisher({h})")
      else if s.gauge ≥ c.skillCost ∧ s.foe ≤ c.skillReach then
        let h := max (s.foe - c.skill) 0; let g := s.gauge - c.skillCost
        sim c fuel { s with foe := h, gauge := g, slot := 1 } (acc.push s!"lead-skill({h},{g})")
      else
        let h := max (s.foe - c.attack) 0; let g := min (s.gauge + c.gaugeStep) c.gaugeFull
        sim c fuel { s with foe := h, gauge := g, slot := 1 } (acc.push s!"lead-attack({h},{g})")
    else
      if s.charge == 1 then
        let h := max (s.foe - c.release) 0; sim c fuel { s with foe := h, charge := 0, slot := 2 } (acc.push s!"caster-release({h})")
      else if s.foe ≥ c.castFloor then sim c fuel { s with charge := 1, slot := 2 } (acc.push "caster-cast")
      else let h := max (s.foe - c.cAttack) 0; sim c fuel { s with foe := h, slot := 2 } (acc.push s!"caster-attack({h})")

def problem (r : Nat) (s : St) (todo : List (List String)) : Json :=
  let v (name : String) (kvs : List (String × Int)) : Json :=
    obj [("name", js name), ("type", js "int"), ("init", obj (kvs.map fun (k, x) => (k, jn x)))]
  obj [("@context", ctx), ("@type", js "domain:Problem"), ("name", js s!"command_battle_round_{r}"),
    ("domain", js "command_battle"), ("source", js "interactor-taskweft-persona"), ("version", js "0.2.0"),
    ("description", js s!"Round {r}: a fresh party against the round's foe. The persona plays the whole round."),
    ("variables", arr [v "lead" [("hp", s.lead), ("max", s.leadMax), ("gauge", s.gauge)],
      v "caster" [("hp", s.caster), ("max", s.casterMax), ("charge", s.charge)],
      v "foe" [("hp", s.foe), ("max", s.foeMax), ("atk", s.atk)], v "turn" [("slot", s.slot)],
      v "result" [("won", 0), ("lost", 0)]]),
    ("todo_list", arr (todo.map fun t => arr (t.map js)))]

/-- The steps of a plan document as `name(arguments)`, or `REFUSED:why` for a refusal. -/
def stepKeys (t : String) : List String :=
  if t.contains "\"refused\"" then ["REFUSED:" ++ ((((t.splitOn "\"refused\":\"").drop 1).headD "").takeWhile (· != '"')).toString]
  else
    (t.splitOn "\"action\":\"").drop 1 |>.map fun x =>
      let name := (x.takeWhile (· != '"')).toString
      let inner := ((((x.splitOn "\"params\":[").drop 1).headD "").takeWhile (· != ']')).toString.replace "\"" ""
      if inner == "" then name else name ++ "(" ++ inner ++ ")"

def ask (dom : String) (r : Nat) (s : St) (todo : List (List String)) : List String :=
  stepKeys (Persona.Jsonld.planOf dom (problem r s todo).compress)

/-- Rounds played, rounds whose plan matched the simulator, the first mismatch, and how the run ended.
With `carry`, the lead keeps its gauge between rounds and a defeat ends the run, as on the page. -/
def playRun (dom : String) (c : Cfg) (limit : Nat) (carry : Bool) : Nat × Nat × String × String := Id.run do
  let mut gauge : Int := 0
  let mut played := 0
  let mut matched := 0
  let mut first := ""
  let mut ending := s!"cleared all {limit} rounds"
  for r in [1:limit + 1] do
    let s0 := fresh c r (if carry then gauge else 0)
    let (want, won, s1) := sim c 100000 s0 #[]
    let got := ask dom r s0 [["play-out"]]
    played := played + 1
    if got == want.toList then matched := matched + 1
    else if first == "" then first := s!"round {r}: got {got.take 4}, want {want.toList.take 4}"
    if !won && ending.startsWith "cleared" then ending := s!"falls in round {r}"
    if carry then
      if !won then break
      gauge := s1.gauge
  return (played, matched, first, ending)

structure Check where
  name : String
  ok : Bool

def run (args : List String) : IO UInt32 := do
  let c : Cfg := {}
  if args == ["write"] then
    IO.FS.writeFile "domains/command-battle.jsonld" ((domain c).pretty ++ "\n")
    IO.FS.writeFile "problems/command-battle-round-1.jsonld" ((problem 1 (fresh c 1 0) [["play-out"]]).pretty ++ "\n")
    IO.println "wrote domains/command-battle.jsonld and problems/command-battle-round-1.jsonld"
    return 0
  let gen := (domain c).compress
  let committed ← IO.FS.readFile "domains/command-battle.jsonld"
  let committedP ← IO.FS.readFile "problems/command-battle-round-1.jsonld"
  let same (t : String) (j : Json) : Bool := match Json.parse t with | .ok x => x.compress == j.compress | .error _ => false
  let off : Cfg := { c with attack := c.attack + 1 }
  let (nPlayed, nMatched, nFirst, nEnd) := playRun committed c 30 true
  let (pPlayed, pMatched, pFirst, pEnd) := playRun committed c 60 true
  let (iPlayed, iMatched, iFirst, _) := playRun committed c 60 false
  let (_, oMatched, _, _) := playRun (domain off).compress c 1 false
  let s1 := fresh c 1 0
  let checks : List Check := [
    { name := "the committed domain is the one this gate generates", ok := same committed (domain c) },
    { name := "a domain with one constant changed is not the committed one", ok := (domain off).compress != gen },
    { name := "the committed round 1 problem is the one this gate generates", ok := same committedP (problem 1 s1 [["play-out"]]) },
    { name := s!"normal run, gauge carried: the planner plays each of {nPlayed} rounds as the simulator does ({nFirst})",
      ok := nPlayed > 0 && nMatched == nPlayed },
    { name := s!"plus run, gauge carried: the planner plays each of {pPlayed} rounds as the simulator does ({pFirst})",
      ok := pPlayed > 0 && pMatched == pPlayed },
    { name := s!"rounds 1 to 60 from an empty gauge: {iMatched} of {iPlayed} plans match the simulator ({iFirst})",
      ok := iPlayed == 60 && iMatched == 60 },
    { name := "a domain whose attack is 1 stronger does not play round 1 as the simulator does", ok := oMatched == 0 },
    { name := "the lead's finisher on an empty gauge is refused", ok := ask committed 1 s1 [["cmd-lead-finisher"]] == ["REFUSED:unreachable"] },
    { name := "the lead's finisher on a full gauge lands", ok := ask committed 1 { s1 with gauge := 100 } [["cmd-lead-finisher"]] == ["lead-finisher(40)"] },
    { name := "a caster command on the lead's turn is refused", ok := ask committed 1 s1 [["cmd-caster-cast"]] == ["REFUSED:unreachable"] },
    { name := "after the lead attacks, respond stops at the caster's turn",
      ok := ask committed 1 s1 [["cmd-lead-attack"], ["respond"]] == ["lead-attack(215,25)"] }]
  for k in checks do
    IO.println s!"  [{if k.ok then "ok  " else "FAIL"}] {k.name}"
  IO.println s!"  persona's own play: normal run {nEnd}; plus run {pEnd}"
  let bad := checks.filter (!·.ok)
  if bad.isEmpty then
    IO.println s!"OK: command battle, {checks.length} invariants hold"
    return 0
  IO.println s!"FAIL: {bad.length} of {checks.length} invariants failed"
  return 1

end BattleWitness

def main (args : List String) : IO UInt32 := BattleWitness.run args
