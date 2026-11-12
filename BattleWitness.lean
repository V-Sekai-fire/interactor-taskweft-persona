-- Copyright (c) 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: Apache-2.0 OR MIT
import Persona.Jsonld
import Lean.Data.Json

/-! The command battle's gate. It writes the battle domain and its first round's problem, simulates the
same rules on its own, and checks that the planner plays a whole run step for step as the simulator does.

  `lake exe persona_battle_witness`         checks, exit 0 and print "OK:" when every invariant holds
  `lake exe persona_battle_witness write`   writes domains/command-battle.jsonld and its round 1 problem
  `lake exe persona_battle_witness report`  prints each round of a normal, a plus and a weakened run -/

open Lean

namespace BattleWitness

structure Cfg where
  leadMax : Int := 300
  casterMax : Int := 200
  guardMax : Int := 400
  menderMax : Int := 220
  attack : Int := 45
  skill : Int := 110
  finisher : Int := 220
  cAttack : Int := 25
  release : Int := 130
  gAttack : Int := 30
  mAttack : Int := 20
  block : Int := 20
  heal : Int := 60
  heals : Int := 3
  gaugeStep : Int := 25
  gaugeFull : Int := 100
  skillCost : Int := 50
  skillReach : Int := 110
  castFloor : Int := 130
  foeHp0 : Int := 260
  foeHpStep : Int := 20
  foeAtk0 : Int := 40
  foeAtkStep : Int := 2

/-- The front party in seat order; the foe acts in seat 4. -/
def members : List String := ["lead", "caster", "guard", "mender"]
def seat (m : String) : Int := match m with | "lead" => 0 | "caster" => 1 | "guard" => 2 | _ => 3
/-- The order the mender looks for someone to heal. -/
def healOrder : List String := ["guard", "lead", "caster", "mender"]

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
def alive (who : String) : GM Json := bin "math/ge" (ptr s!"/{who}/hp") (lit 1)

/-- The seat the foe strikes: a taunting guard while it stands, else the first standing of lead, guard,
caster, mender. -/
def targetG : GM Json :=
  sel (bin "math/and" (bin "math/eq" (ptr "/guard/taunt") (lit 1)) (alive "guard")) (lit 2)
    (sel (alive "lead") (lit 0) (sel (alive "guard") (lit 2) (sel (alive "caster") (lit 1) (lit 3))))

def act (params : List String) (desc : String) (pre : List Json) (sets : List (String × Json)) : Json :=
  obj [("params", arr (params.map js)), ("description", js desc),
    ("body", arr (pre ++ sets.map fun (p, v) => obj [("pointer/set", js p), ("value", v)]))]

def alt (name : String) (check : List Json) (subtasks : List (List Json)) (graph : Option Json := none) : Json :=
  obj ([("name", js name), ("check", arr check), ("subtasks", arr (subtasks.map arr))] ++
    (match graph with | some g => [("graph", g)] | none => []))

def method (alts : List Json) : Json := obj [("params", arr []), ("alternatives", arr alts)]
def cmdM (check : List Json) (action : String) (outs : List String) (g : Json) : Json :=
  method [alt "go" check [js action :: outs.map par] (some g)]

def turnOf (who : String) : List Json := [eqC "/turn/slot" (seat who), geC s!"/{who}/hp" 1, geC "/foe/hp" 1]
def nextSeat (who : String) : Json := jn (seat who + 1)

def driver (name : String) (ends : Bool) : Json :=
  let downs := members.map fun m => alt s!"{m}-down" [eqC "/turn/slot" (seat m), eqC s!"/{m}/hp" 0] [[js s!"skip-{m}"], [js name]]
  let moves := if ends then members.map (fun m => alt m [eqC "/turn/slot" (seat m)] [[js s!"{m}-policy"], [js name]])
    else [alt "party-to-move" [] []]
  method ([alt "foe-down" [eqC "/foe/hp" 0] [[js "victory"]],
    alt "party-down" (members.map fun m => eqC s!"/{m}/hp" 0) [[js "defeat"]],
    alt "foe" [eqC "/turn/slot" 4] [[js "foe-turn"], [js name]]] ++ downs ++ moves)

def domain (c : Cfg) : Json :=
  let heals := members.map fun x => (s!"mender-heal-{x}", act ["v", "k"]
      s!"The mender heals the {x} for {c.heal}, up to its maximum; {c.heals} heals a round."
      (turnOf "mender" ++ [geC "/mender/heals" 1, geC s!"/{x}/hp" 1])
      [(s!"/{x}/hp", par "v"), ("/mender/heals", par "k"), ("/turn/slot", nextSeat "mender")])
  let strikes := members.map fun x => (s!"foe-strike-{x}", act ["h"]
      (if x == "guard" then s!"The foe strikes the guard, who blocks {c.block} of it." else s!"The foe strikes the {x}.")
      [eqC "/turn/slot" 4, geC "/foe/hp" 1, geC s!"/{x}/hp" 1] [(s!"/{x}/hp", par "h"), ("/turn/slot", jn 0)])
  let skips := members.map fun x => (s!"skip-{x}", act [] s!"A fallen {x} loses the turn."
      [eqC "/turn/slot" (seat x), eqC s!"/{x}/hp" 0] [("/turn/slot", nextSeat x)])
  let actions := [
    ("lead-attack", act ["h", "g"] s!"The lead attacks: {c.attack} damage, +{c.gaugeStep} gauge." (turnOf "lead")
      [("/foe/hp", par "h"), ("/lead/gauge", par "g"), ("/turn/slot", nextSeat "lead")]),
    ("lead-skill", act ["h", "g"] s!"The lead uses a skill: {c.skill} damage for {c.skillCost} gauge, on the same turn."
      (turnOf "lead" ++ [geC "/lead/gauge" c.skillCost]) [("/foe/hp", par "h"), ("/lead/gauge", par "g"), ("/turn/slot", nextSeat "lead")]),
    ("lead-finisher", act ["h"] s!"The lead's finisher: needs a full gauge, empties it, {c.finisher} damage."
      (turnOf "lead" ++ [geC "/lead/gauge" c.gaugeFull]) [("/foe/hp", par "h"), ("/lead/gauge", jn 0), ("/turn/slot", nextSeat "lead")]),
    ("caster-attack", act ["h"] s!"The caster attacks: {c.cAttack} damage." (turnOf "caster" ++ [eqC "/caster/charge" 0])
      [("/foe/hp", par "h"), ("/turn/slot", nextSeat "caster")]),
    ("caster-cast", act [] "The caster begins a spell; it lands on the caster's next turn." (turnOf "caster" ++ [eqC "/caster/charge" 0])
      [("/caster/charge", jn 1), ("/turn/slot", nextSeat "caster")]),
    ("caster-release", act ["h"] s!"The caster releases the spell: {c.release} damage." (turnOf "caster" ++ [eqC "/caster/charge" 1])
      [("/foe/hp", par "h"), ("/caster/charge", jn 0), ("/turn/slot", nextSeat "caster")]),
    ("guard-attack", act ["h"] s!"The guard attacks: {c.gAttack} damage." (turnOf "guard") [("/foe/hp", par "h"), ("/turn/slot", nextSeat "guard")]),
    ("guard-taunt", act [] "The guard taunts: the foe strikes the guard while it stands, this round." (turnOf "guard" ++ [eqC "/guard/taunt" 0])
      [("/guard/taunt", jn 1), ("/turn/slot", nextSeat "guard")]),
    ("mender-attack", act ["h"] s!"The mender attacks: {c.mAttack} damage." (turnOf "mender") [("/foe/hp", par "h"), ("/turn/slot", nextSeat "mender")])]
    ++ heals ++ strikes ++ skips ++ [
    ("victory", act [] "The foe is down: the round is won." [eqC "/foe/hp" 0] [("/result/won", jn 1)]),
    ("defeat", act [] "The party is down: the run ends." (members.map fun m => eqC s!"/{m}/hp" 0) [("/result/lost", jn 1)]),
    ("next-round", act ["r", "fh", "fa", "lh", "ch", "gh", "mh"]
      "The next round: a stronger foe, the party back to full, taunt and spell cleared, heals restored; the lead keeps its gauge."
      [eqC "/result/won" 1]
      [("/run/round", par "r"), ("/foe/hp", par "fh"), ("/foe/max", par "fh"), ("/foe/atk", par "fa"),
       ("/lead/hp", par "lh"), ("/caster/hp", par "ch"), ("/guard/hp", par "gh"), ("/mender/hp", par "mh"),
       ("/caster/charge", jn 0), ("/guard/taunt", jn 0), ("/mender/heals", jn c.heals), ("/turn/slot", jn 0), ("/result/won", jn 0)])]
  let strikeDmg (x : String) : GM Json :=
    if x == "guard" then bin "math/max" (bin "math/sub" (ptr "/guard/hp") (bin "math/max" (bin "math/sub" (ptr "/foe/atk") (lit c.block)) (lit 0))) (lit 0)
    else bin "math/max" (bin "math/sub" (ptr s!"/{x}/hp") (ptr "/foe/atk")) (lit 0)
  let healCmds := members.map fun x => (s!"cmd-mender-heal-{x}",
    cmdM (turnOf "mender" ++ [geC "/mender/heals" 1, geC s!"/{x}/hp" 1]) s!"mender-heal-{x}" ["v", "k"] (mkGraph do
      out "v" (bin "math/min" (bin "math/add" (ptr s!"/{x}/hp") (lit c.heal)) (ptr s!"/{x}/max"))
      out "k" (bin "math/sub" (ptr "/mender/heals") (lit 1))))
  let healPolicy := healOrder.map fun x => alt s!"heal-{x}" [geC "/mender/heals" 1, geC s!"/{x}/hp" 1, geC "/graph/need" 1]
    [[js s!"cmd-mender-heal-{x}"]]
    (some (mkGraph (out "need" (sel (bin "math/ge" (bin "math/sub" (ptr s!"/{x}/max") (ptr s!"/{x}/hp")) (lit c.heal)) (lit 1) (lit 0)))))
  let methods := [
    ("cmd-lead-attack", cmdM (turnOf "lead") "lead-attack" ["h", "g"] (mkGraph do
      out "h" (hit c.attack)
      out "g" (bin "math/min" (bin "math/add" (ptr "/lead/gauge") (lit c.gaugeStep)) (lit c.gaugeFull)))),
    ("cmd-lead-skill", cmdM (turnOf "lead" ++ [geC "/lead/gauge" c.skillCost]) "lead-skill" ["h", "g"] (mkGraph do
      out "h" (hit c.skill)
      out "g" (bin "math/sub" (ptr "/lead/gauge") (lit c.skillCost)))),
    ("cmd-lead-finisher", cmdM (turnOf "lead" ++ [geC "/lead/gauge" c.gaugeFull]) "lead-finisher" ["h"] (mkGraph (out "h" (hit c.finisher)))),
    ("cmd-caster-attack", cmdM (turnOf "caster" ++ [eqC "/caster/charge" 0]) "caster-attack" ["h"] (mkGraph (out "h" (hit c.cAttack)))),
    ("cmd-caster-cast", method [alt "go" (turnOf "caster" ++ [eqC "/caster/charge" 0]) [[js "caster-cast"]]]),
    ("cmd-caster-release", cmdM (turnOf "caster" ++ [eqC "/caster/charge" 1]) "caster-release" ["h"] (mkGraph (out "h" (hit c.release)))),
    ("cmd-guard-attack", cmdM (turnOf "guard") "guard-attack" ["h"] (mkGraph (out "h" (hit c.gAttack)))),
    ("cmd-guard-taunt", method [alt "go" (turnOf "guard" ++ [eqC "/guard/taunt" 0]) [[js "guard-taunt"]]]),
    ("cmd-mender-attack", cmdM (turnOf "mender") "mender-attack" ["h"] (mkGraph (out "h" (hit c.mAttack))))] ++ healCmds ++ [
    ("foe-turn", method (members.map fun x =>
      alt x [eqC "/turn/slot" 4, geC "/foe/hp" 1, eqC "/graph/t" (seat x)] [[js s!"foe-strike-{x}", par "h"]]
        (some (mkGraph do
          out "t" targetG
          out "h" (strikeDmg x))))),
    ("cmd-next-round", method [alt "go" [eqC "/result/won" 1, geC "/graph/more" 1]
      [[js "next-round", par "r", par "fh", par "fa", par "lh", par "ch", par "gh", par "mh"]]
      (some (mkGraph do
        out "r" (bin "math/add" (ptr "/run/round") (lit 1))
        out "fh" (bin "math/add" (bin "math/mul" (bin "math/add" (ptr "/run/round") (lit 1)) (lit c.foeHpStep)) (lit (c.foeHp0 - c.foeHpStep)))
        out "fa" (bin "math/add" (bin "math/mul" (bin "math/add" (ptr "/run/round") (lit 1)) (lit c.foeAtkStep)) (lit (c.foeAtk0 - c.foeAtkStep)))
        out "lh" (ptr "/lead/max")
        out "ch" (ptr "/caster/max")
        out "gh" (ptr "/guard/max")
        out "mh" (ptr "/mender/max")
        out "more" (sel (bin "math/gt" (ptr "/run/limit") (ptr "/run/round")) (lit 1) (lit 0))))]),
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
      alt "attack" [] [[js "cmd-caster-attack"]]]),
    ("guard-policy", method [
      alt "taunt" [eqC "/guard/taunt" 0] [[js "cmd-guard-taunt"]],
      alt "attack" [] [[js "cmd-guard-attack"]]]),
    ("mender-policy", method (healPolicy ++ [alt "attack" [] [[js "cmd-mender-attack"]]]))]
  obj [("@context", ctx), ("@type", js "domain:Definition"), ("name", js "command_battle"),
    ("source", js "interactor-taskweft-persona"), ("version", js "0.3.0"),
    ("description", js ("A turn-based command battle. A party of four (lead, caster, guard, mender) acts in seat order, then the foe. " ++
      "Attacks build the lead's gauge; a skill spends half of it; a full gauge allows a finisher; a spell takes a turn to cast; " ++
      "a taunting guard draws the foe's strikes and blocks part of each; the mender heals a few times a round. " ++
      "A run is 30 rounds (normal) or 60 (plus); the next-round method makes each foe stronger.")),
    ("variables", arr (["lead", "caster", "guard", "mender", "foe", "turn", "run", "result"].map fun v =>
      obj [("name", js v), ("type", js "int"), ("init", obj [])])),
    ("actions", obj actions), ("methods", obj methods)]

/-! The simulator: the same rules and the same policy, over the same pointers, without the planner. -/
abbrev St := List (String × Int)
def gv (s : St) (k : String) : Int := (s.lookup k).getD 0
def put (s : St) (k : String) (v : Int) : St :=
  if s.any (·.1 == k) then s.map (fun (a, b) => if a == k then (a, v) else (a, b)) else s ++ [(k, v)]

def init (c : Cfg) (limit : Nat) : St :=
  [("lead/hp", c.leadMax), ("lead/max", c.leadMax), ("lead/gauge", 0),
   ("caster/hp", c.casterMax), ("caster/max", c.casterMax), ("caster/charge", 0),
   ("guard/hp", c.guardMax), ("guard/max", c.guardMax), ("guard/taunt", 0),
   ("mender/hp", c.menderMax), ("mender/max", c.menderMax), ("mender/heals", c.heals),
   ("foe/hp", c.foeHp0), ("foe/max", c.foeHp0), ("foe/atk", c.foeAtk0),
   ("turn/slot", 0), ("run/round", 1), ("run/limit", limit), ("result/won", 0), ("result/lost", 0)]

def allDown (s : St) : Bool := members.all fun m => gv s s!"{m}/hp" == 0
def hitFoe (s : St) (amount : Int) : Int := max (gv s "foe/hp" - amount) 0

def target (s : St) : String :=
  if gv s "guard/taunt" == 1 && decide (gv s "guard/hp" ≥ 1) then "guard"
  else if gv s "lead/hp" ≥ 1 then "lead" else if gv s "guard/hp" ≥ 1 then "guard"
  else if gv s "caster/hp" ≥ 1 then "caster" else "mender"

def policy (c : Cfg) (m : String) (s : St) : St × String :=
  if m == "lead" then
    if gv s "lead/gauge" ≥ c.gaugeFull then
      let h := hitFoe s c.finisher; (put (put s "foe/hp" h) "lead/gauge" 0, s!"lead-finisher({h})")
    else if gv s "lead/gauge" ≥ c.skillCost ∧ gv s "foe/hp" ≤ c.skillReach then
      let h := hitFoe s c.skill; let g := gv s "lead/gauge" - c.skillCost
      (put (put s "foe/hp" h) "lead/gauge" g, s!"lead-skill({h},{g})")
    else
      let h := hitFoe s c.attack; let g := min (gv s "lead/gauge" + c.gaugeStep) c.gaugeFull
      (put (put s "foe/hp" h) "lead/gauge" g, s!"lead-attack({h},{g})")
  else if m == "caster" then
    if gv s "caster/charge" == 1 then
      let h := hitFoe s c.release; (put (put s "foe/hp" h) "caster/charge" 0, s!"caster-release({h})")
    else if gv s "foe/hp" ≥ c.castFloor then (put s "caster/charge" 1, "caster-cast")
    else let h := hitFoe s c.cAttack; (put s "foe/hp" h, s!"caster-attack({h})")
  else if m == "guard" then
    if gv s "guard/taunt" == 0 then (put s "guard/taunt" 1, "guard-taunt")
    else let h := hitFoe s c.gAttack; (put s "foe/hp" h, s!"guard-attack({h})")
  else
    let want (x : String) : Bool := decide (gv s "mender/heals" ≥ 1) && decide (gv s s!"{x}/hp" ≥ 1) &&
      decide (gv s s!"{x}/max" - gv s s!"{x}/hp" ≥ c.heal)
    match healOrder.find? want with
    | some x =>
      let v := min (gv s s!"{x}/hp" + c.heal) (gv s s!"{x}/max"); let k := gv s "mender/heals" - 1
      (put (put s s!"{x}/hp" v) "mender/heals" k, s!"mender-heal-{x}({v},{k})")
    | none => let h := hitFoe s c.mAttack; (put s "foe/hp" h, s!"mender-attack({h})")

/-- The steps of a round played to its end, whether it was won, and the state it ends in. -/
def sim (c : Cfg) : Nat → St → Array String → Array String × Bool × St
  | 0, s, acc => (acc.push "NO-END", false, s)
  | fuel + 1, s, acc =>
    if gv s "foe/hp" == 0 then (acc.push "victory", true, put s "result/won" 1)
    else if allDown s then (acc.push "defeat", false, put s "result/lost" 1)
    else
      let slot := gv s "turn/slot"
      if slot == 4 then
        let t := target s
        let dmg := if t == "guard" then max (gv s "foe/atk" - c.block) 0 else gv s "foe/atk"
        let h := max (gv s s!"{t}/hp" - dmg) 0
        sim c fuel (put (put s s!"{t}/hp" h) "turn/slot" 0) (acc.push s!"foe-strike-{t}({h})")
      else
        let m := members[slot.toNat]!
        if gv s s!"{m}/hp" == 0 then sim c fuel (put s "turn/slot" (slot + 1)) (acc.push s!"skip-{m}")
        else
          let (s2, step) := policy c m s
          sim c fuel (put s2 "turn/slot" (slot + 1)) (acc.push step)

def nextRound (c : Cfg) (s : St) : St × String :=
  let r := gv s "run/round" + 1
  let fh := c.foeHp0 + c.foeHpStep * (r - 1)
  let fa := c.foeAtk0 + c.foeAtkStep * (r - 1)
  let maxes := members.map fun m => gv s s!"{m}/max"
  let s2 := ([("run/round", r), ("foe/hp", fh), ("foe/max", fh), ("foe/atk", fa)] ++
    (members.zip maxes).map (fun (p : String × Int) => (s!"{p.1}/hp", p.2)) ++
    [("caster/charge", 0), ("guard/taunt", 0), ("mender/heals", c.heals), ("turn/slot", 0), ("result/won", 0)]).foldl
    (fun a (k, v) => put a k v) s
  (s2, s!"next-round({r},{fh},{fa}," ++ ",".intercalate (maxes.map toString) ++ ")")

structure RunOut where
  steps : Array String
  rounds : Nat
  cleared : Bool
  longest : Nat
  perRound : Array (Nat × Bool × Nat × String)

def simRun (c : Cfg) (limit : Nat) : RunOut := Id.run do
  let mut s := init c limit
  let mut acc : Array String := #[]
  let mut longest := 0
  let mut per : Array (Nat × Bool × Nat × String) := #[]
  for r in [1:limit + 1] do
    let (st, won, s1) := sim c 100000 s #[]
    acc := acc ++ st
    longest := max longest st.size
    per := per.push (r, won, st.size, ",".intercalate (members.map fun m => s!"{m} {gv s1 s!"{m}/hp"}"))
    if !won then return { steps := acc, rounds := r, cleared := false, longest, perRound := per }
    if r == limit then return { steps := acc, rounds := r, cleared := true, longest, perRound := per }
    let (s2, step) := nextRound c s1
    acc := acc.push step
    s := s2
  return { steps := acc, rounds := limit, cleared := true, longest, perRound := per }

def groups : List String := ["lead", "caster", "guard", "mender", "foe", "turn", "run", "result"]

def problem (c : Cfg) (s : St) (todo : List (List String)) : Json :=
  let v (name : String) : Json := obj [("name", js name), ("type", js "int"),
    ("init", obj ((s.filter (fun (k, _) => k.startsWith (name ++ "/"))).map fun (k, x) => ((k.drop (name.length + 1)).toString, jn x)))]
  obj [("@context", ctx), ("@type", js "domain:Problem"), ("name", js "command_battle_run"),
    ("domain", js "command_battle"), ("source", js "interactor-taskweft-persona"), ("version", js "0.3.0"),
    ("description", js s!"The start of a run: round 1, a full party of four, {c.heals} heals. The page sets run/limit to 30 or 60."),
    ("variables", arr (groups.map v)),
    ("todo_list", arr (todo.map fun t => arr (t.map js)))]

/-- The steps of a plan document as `name(arguments)`, or `REFUSED:why` for a refusal. -/
def stepKeys (t : String) : List String :=
  if t.contains "\"refused\"" then ["REFUSED:" ++ ((((t.splitOn "\"refused\":\"").drop 1).headD "").takeWhile (· != '"')).toString]
  else
    (t.splitOn "\"action\":\"").drop 1 |>.map fun x =>
      let name := (x.takeWhile (· != '"')).toString
      let inner := ((((x.splitOn "\"params\":[").drop 1).headD "").takeWhile (· != ']')).toString.replace "\"" ""
      if inner == "" then name else name ++ "(" ++ inner ++ ")"

def ask (c : Cfg) (dom : String) (s : St) (todo : List (List String)) : List String :=
  stepKeys (Persona.Jsonld.planOf dom (problem c s todo).compress)

def runTodo (rounds : Nat) : List (List String) :=
  [["play-out"]] ++ (List.replicate (rounds - 1) [["cmd-next-round"], ["play-out"]]).foldl (· ++ ·) []

/-- The planner's whole run against the simulator's: the planner's steps, and whether they are the same. -/
def compareRun (c : Cfg) (dom : String) (limit : Nat) : RunOut × List String × Bool :=
  let r := simRun c limit
  let got := ask c dom (init c limit) (runTodo r.rounds)
  (r, got, got == r.steps.toList)

structure Check where
  name : String
  ok : Bool

def run (args : List String) : IO UInt32 := do
  let c : Cfg := {}
  let weak : Cfg := { c with heals := 0, block := 0, leadMax := 100, casterMax := 70, guardMax := 130, menderMax := 70 }
  if args == ["write"] then
    IO.FS.writeFile "domains/command-battle.jsonld" ((domain c).pretty ++ "\n")
    IO.FS.writeFile "problems/command-battle-round-1.jsonld" ((problem c (init c 30) [["play-out"]]).pretty ++ "\n")
    IO.println "wrote domains/command-battle.jsonld and problems/command-battle-round-1.jsonld"
    return 0
  if args == ["report"] then
    for (label, k, lim) in ([("normal", c, 30), ("plus", c, 60), ("weakened", weak, 30)] : List (String × Cfg × Nat)) do
      let r := simRun k lim
      IO.println s!"{label}: {if r.cleared then "cleared" else "falls in round " ++ toString r.rounds}, longest round {r.longest} steps"
      for (rd, won, n, hp) in r.perRound do
        IO.println s!"  round {rd}: {if won then "won " else "LOST"} in {n} steps; {hp}"
    return 0
  let committed ← IO.FS.readFile "domains/command-battle.jsonld"
  let committedP ← IO.FS.readFile "problems/command-battle-round-1.jsonld"
  let same (t : String) (j : Json) : Bool := match Json.parse t with | .ok x => x.compress == j.compress | .error _ => false
  let off : Cfg := { c with attack := c.attack + 1 }
  let (nR, nGot, nSame) := compareRun c committed 30
  let (pR, pGot, pSame) := compareRun c committed 60
  let (wR, _, wSame) := compareRun weak (domain weak).compress 30
  let s1 := init c 30
  let at4 (s : St) : St := put s "turn/slot" 4
  let won30 := put (put (put (init c 30) "foe/hp" 0) "result/won" 1) "run/round" 30
  let checks : List Check := [
    { name := "the committed domain is the one this gate generates", ok := same committed (domain c) },
    { name := "a domain with one constant changed is not the committed one", ok := (domain off).compress != (domain c).compress },
    { name := "the committed round 1 problem is the one this gate generates", ok := same committedP (problem c s1 [["play-out"]]) },
    { name := s!"normal run: the planner plays all {nR.rounds} rounds ({nGot.length} steps) exactly as the simulator does", ok := nSame },
    { name := "normal run: the persona's own play clears all 30 rounds, and its last step is victory",
      ok := nR.cleared && nR.rounds == 30 && nGot.getLast? == some "victory" },
    { name := s!"plus run: the planner plays all {pR.rounds} rounds exactly as the simulator does", ok := pSame },
    { name := s!"plus run: the persona's own play ends as pinned ({if pR.cleared then "cleared" else "falls in round " ++ toString pR.rounds})",
      ok := !pR.cleared && pR.rounds == 57 },
    { name := s!"weakened party (a third of the HP, no heals, no block): the planner matches the simulator and falls in round {wR.rounds}",
      ok := wSame && !wR.cleared && wR.rounds < 30 },
    { name := s!"no play-out is refused, and the longest round ({max nR.longest pR.longest} steps) stays under 400",
      ok := !(nGot ++ pGot).any (·.startsWith "REFUSED") && max nR.longest pR.longest < 400 },
    { name := "a domain whose attack is 1 stronger does not play round 1 as the simulator does",
      ok := ask c (domain off).compress s1 [["play-out"]] != (sim c 100000 s1 #[]).1.toList },
    { name := "the foe strikes a taunting guard, who blocks 20: 400 - (40 - 20) = 380",
      ok := ask c committed (put (at4 s1) "guard/taunt" 1) [["foe-turn"]] == ["foe-strike-guard(380)"] },
    { name := "without a taunt the foe strikes the lead for the full 40",
      ok := ask c committed (at4 s1) [["foe-turn"]] == ["foe-strike-lead(260)"] },
    { name := "with the lead and a taunting guard down, the foe strikes the caster",
      ok := ask c committed (put (put (put (at4 s1) "guard/taunt" 1) "guard/hp" 0) "lead/hp" 0) [["foe-turn"]] == ["foe-strike-caster(160)"] },
    { name := "a heal stops at the maximum: 280 + 60 caps at 300, and a heal is spent",
      ok := ask c committed (put (put s1 "turn/slot" 3) "lead/hp" 280) [["cmd-mender-heal-lead"]] == ["mender-heal-lead(300,2)"] },
    { name := "a fallen member cannot be healed",
      ok := ask c committed (put (put s1 "turn/slot" 3) "lead/hp" 0) [["cmd-mender-heal-lead"]] == ["REFUSED:unreachable"] },
    { name := "with no heals left, the heal is refused",
      ok := ask c committed (put (put (put s1 "turn/slot" 3) "lead/hp" 100) "mender/heals" 0) [["cmd-mender-heal-lead"]] == ["REFUSED:unreachable"] },
    { name := "a fallen lead loses its turn, and respond stops at the caster",
      ok := ask c committed (put s1 "lead/hp" 0) [["respond"]] == ["skip-lead"] },
    { name := "the lead's finisher on an empty gauge is refused", ok := ask c committed s1 [["cmd-lead-finisher"]] == ["REFUSED:unreachable"] },
    { name := "the lead's finisher on a full gauge lands", ok := ask c committed (put s1 "lead/gauge" 100) [["cmd-lead-finisher"]] == ["lead-finisher(40)"] },
    { name := "a caster command on the lead's turn is refused", ok := ask c committed s1 [["cmd-caster-cast"]] == ["REFUSED:unreachable"] },
    { name := "after the lead attacks, respond stops at the caster's turn",
      ok := ask c committed s1 [["cmd-lead-attack"], ["respond"]] == ["lead-attack(215,25)"] },
    { name := "the next round is refused before the foe is down", ok := ask c committed s1 [["cmd-next-round"]] == ["REFUSED:unreachable"] },
    { name := "the next round is refused after round 30 of 30", ok := ask c committed won30 [["cmd-next-round"]] == ["REFUSED:unreachable"] },
    { name := "after a won round 1, the next round is round 2 with a stronger foe and a full party",
      ok := ask c committed (put (put s1 "foe/hp" 0) "result/won" 1) [["cmd-next-round"]] == ["next-round(2,280,42,300,200,400,220)"] }]
  for k in checks do
    IO.println s!"  [{if k.ok then "ok  " else "FAIL"}] {k.name}"
  let bad := checks.filter (!·.ok)
  if bad.isEmpty then
    IO.println s!"OK: command battle, {checks.length} invariants hold"
    return 0
  IO.println s!"FAIL: {bad.length} of {checks.length} invariants failed"
  return 1

end BattleWitness

def main (args : List String) : IO UInt32 := BattleWitness.run args
