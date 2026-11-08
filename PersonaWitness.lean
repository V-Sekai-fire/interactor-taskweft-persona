import Persona.Demo
import Persona.Grid
import Persona.Jsonld
import Persona.Web
import Persona.Khr

open Persona
open Persona.Demo

namespace PersonaWitness

def distinct {α : Type} [DecidableEq α] : List α → Bool
  | []      => true
  | x :: xs => !(xs.any fun y => decide (y = x)) && distinct xs

structure Check where
  name : String
  ok : Bool

def stage : Codebook := { levels := [8, 8, 8, 8] }

def plan : Option (List PlanElement) := persona.answer delivered

def reached : Bool :=
  match plan with
  | some p => is_node_satisfied (domain.execute p) delivered.node
  | none   => false

def gridSpec : String := "skill 1 1\nskill 2 0 1\nskill 3 0 2 1\nskill 4 0 3\ngoal 4"

def gridOrdered : Bool :=
  Persona.Grid.planOf gridSpec == "{\"plan\":[\"activate-2\",\"activate-3\",\"activate-4\"],\"reached\":true}"

def checks : List Check :=
  [ { name := "codebook: eight levels over four dimensions is 4096 codes a stage",
      ok := stage.size == 4096 }
  , { name := "codebook: the basis is the prefix product",
      ok := stage.basis == [1, 8, 64, 512] }
  , { name := "codebook: a code's index is mixed-radix",
      ok := stage.index [1, 2, 3, 4] == 2257 }
  , { name := "codebook: four stages of 4096 codes is the whole vocabulary",
      ok := stage.vocabulary 4 == 281474976710656 }
  , { name := "codebook: a held code carries one digit a dimension, in range",
      ok := stage.holds [7, 7, 7, 7] }
  , { name := "codebook: a digit past its level is refused",
      ok := !(stage.holds [8, 0, 0, 0]) }
  , { name := "codebook: a code of the wrong arity is refused",
      ok := !(stage.holds [1, 2, 3]) }
  , { name := "answer: the goal is reached", ok := plan.isSome }
  , { name := "answer: the plan it composes executes to the goal", ok := reached }
  , { name := "answer: the plan does not repeat an action",
      ok := match plan with | some p => distinct p | none => false }
  , { name := "refusal: a goal the domain cannot reach",
      ok := (persona.answer { node := .goal_geq 2 2 }).isNone }
  , { name := "refusal: a variable the domain does not declare",
      ok := (persona.answer { node := .goal_geq 99 1 }).isNone }
  , { name := "refusal: zero fuel on an unmet goal",
      ok := (persona.answer delivered 0).isNone }
  , { name := "grid: a plan activates every skill after the skills it needs",
      ok := gridOrdered }
  , { name := "grid: a cycle of needs is refused as unreachable",
      ok := Persona.Grid.planOf "skill 1 0 2\nskill 2 0 1\ngoal 1" == "{\"refused\":\"unreachable\"}" }
  , { name := "grid: a goal the spec does not declare is refused",
      ok := Persona.Grid.planOf "skill 1 1\ngoal 9" == "{\"refused\":\"undeclared_goal\"}" }
  , { name := "domain: every action writes a variable the domain declares",
      ok := domain.actions.all (fun a =>
        a.writes.all fun w => domain.variables.any (fun sv => sv.id == w.1)) }
  , { name := "domain: every code an action writes is held by the codebook",
      ok := domain.actions.all (fun a => a.writes.all fun w => domain.accepts w.2) }
  ]

/-- A domain of `n` methods, each calling the next, and the last calling one action. -/
def chainDom (n : Nat) : String :=
  let ms := (List.range n).map fun i =>
    let next := if i + 1 == n then "act" else "c" ++ toString (i + 1)
    "\"c" ++ toString i ++ "\":{\"alternatives\":[{\"name\":\"go\",\"subtasks\":[[\"" ++ next ++ "\"]]}]}"
  "{\"name\":\"chain\",\"variables\":[],\"actions\":{\"act\":{\"body\":[{\"pointer/set\":\"/v/x\",\"value\":1}]}},\"methods\":{"
    ++ String.intercalate "," ms ++ "}}"

def chainProb (_n : Nat) : String :=
  "{\"name\":\"chain_problem\",\"variables\":[],\"todo_list\":[[\"c0\"]]}"

def stampPlus (s : String) (k : Nat) : String :=
  Persona.Jsonld.fmtStamp ((Persona.Jsonld.parseStamp s).getD 0 + k)

def tempProb (origin : String) : String :=
  "{\"name\":\"temporal_problem\",\"origin\":\"" ++ origin ++ "\",\"variables\":[],\"todo_list\":[[\"m\"]]}"

/-- Two independent actions of two and three days, and a third that needs both and takes one. -/
def tempDom : String :=
  let act := fun (n d v : String) (needs : List String) =>
    "\"" ++ n ++ "\":{\"duration\":\"" ++ d ++ "\",\"body\":["
      ++ String.intercalate "," (needs.map fun x =>
          "{\"eval\":{\"type\":\"math/ge\",\"a\":{\"type\":\"pointer/get\",\"pointer\":\"/v/" ++ x
            ++ "\"},\"b\":1}}" ++ "") ++ (if needs.isEmpty then "" else ",")
      ++ "{\"pointer/set\":\"/v/" ++ v ++ "\",\"value\":1}]}"
  "{\"name\":\"temporal\",\"variables\":[],\"actions\":{"
    ++ act "a" "P2D" "a" [] ++ "," ++ act "b" "P3D" "b" [] ++ "," ++ act "c" "PT24H" "c" ["a", "b"]
    ++ "},\"methods\":{\"m\":{\"alternatives\":[{\"name\":\"go\",\"subtasks\":[[\"a\"],[\"b\"],[\"c\"]]}]}}}"

/-- The same three actions under a composite task that plans them, then lists each step again. -/
def tempWinDom : String :=
  tempDom.replace "\"methods\":{" "\"methods\":{\"w\":{\"alternatives\":[{\"name\":\"win\",\"subtasks\":[[\"m\"],[\"a\"],[\"b\"],[\"c\"]]}]},"

def tempWinProb (origin : String) : String :=
  "{\"name\":\"window_problem\",\"origin\":\"" ++ origin ++ "\",\"variables\":[],\"todo_list\":[[\"w\"]]}"

/-- y can be made by going through x, which is listed first, or directly, which is listed second. -/
def gtnDom : String :=
  "{\"name\":\"shortcut\",\"variables\":[],\"actions\":{"
    ++ "\"a\":{\"body\":[{\"pointer/set\":\"/v/x\",\"value\":1}]},"
    ++ "\"b\":{\"body\":[{\"eval\":{\"type\":\"math/ge\",\"a\":{\"type\":\"pointer/get\",\"pointer\":\"/v/x\"},\"b\":1}},{\"pointer/set\":\"/v/y\",\"value\":1}]},"
    ++ "\"c\":{\"body\":[{\"pointer/set\":\"/v/y\",\"value\":1}]}},"
    ++ "\"methods\":{\"/v/y\":{\"alternatives\":[{\"name\":\"long\",\"subtasks\":[[\"goal\",\"/v/x\"],[\"b\"]]},{\"name\":\"short\",\"subtasks\":[[\"c\"]]}]},"
    ++ "\"/v/x\":{\"alternatives\":[{\"name\":\"do\",\"subtasks\":[[\"a\"]]}]}}}"

def gtnProb (goals : List String) : String :=
  "{\"name\":\"shortcut_problem\",\"variables\":[{\"name\":\"v\",\"init\":{\"x\":0,\"y\":0,\"p\":0,\"q\":0,\"r\":0}}],\"todo_list\":[{\"goal\":["
    ++ String.intercalate "," (goals.map fun g => "{\"pointer\":\"" ++ g ++ "\",\"eq\":1}") ++ "]}]}"

/-- p is made by u1, listed first, which leaves q unset, or by u2, which sets q; r needs both. -/
def backDom : String :=
  "{\"name\":\"back\",\"variables\":[],\"actions\":{"
    ++ "\"u1\":{\"body\":[{\"pointer/set\":\"/v/p\",\"value\":1}]},"
    ++ "\"u2\":{\"body\":[{\"pointer/set\":\"/v/p\",\"value\":1},{\"pointer/set\":\"/v/q\",\"value\":1}]},"
    ++ "\"w\":{\"body\":[{\"eval\":{\"type\":\"math/ge\",\"a\":{\"type\":\"pointer/get\",\"pointer\":\"/v/p\"},\"b\":1}},{\"eval\":{\"type\":\"math/ge\",\"a\":{\"type\":\"pointer/get\",\"pointer\":\"/v/q\"},\"b\":1}},{\"pointer/set\":\"/v/r\",\"value\":1}]}},"
    ++ "\"methods\":{\"/v/p\":{\"alternatives\":[{\"name\":\"first\",\"subtasks\":[[\"u1\"]]},{\"name\":\"second\",\"subtasks\":[[\"u2\"]]}]},"
    ++ "\"/v/r\":{\"alternatives\":[{\"name\":\"go\",\"subtasks\":[[\"w\"]]}]}}}"

/-- Domain, problem and plan are three documents. The plan is the gold value: the planner's
output for the domain and the problem must equal it, and a gold with one step changed must not. -/
def campusChecks (dom prob gold rdom rprob : String) : List Check :=
  let steps := fun (t : String) =>
    ((t.replace " " "").replace "\n" "").splitOn "\"action\":\"" |>.drop 1 |>.map (·.takeWhile (· != '"'))
  let ask := fun (pr : String) => Persona.Jsonld.planOf dom pr
  let swap := fun (t a b : String) => t.replace a b
  let held := swap prob "\"3\": 0,\n    \"B1\"" "\"3\": 1,\n    \"B1\""
  let solved := swap (swap prob "\"2\": 0,\n    \"3\": 0\n   }" "\"2\": 1,\n    \"3\": 1\n   }")
    "\"3\": 0,\n    \"B1\": 0" "\"3\": 1,\n    \"B1\": 1"
  [ { name := "campus: the planner's plan equals the gold plan",
      ok := (ask prob).trim == gold.trim }
  , { name := "campus: a gold plan with one step changed does not match",
      ok := (ask prob).trim != (swap gold "settle-2" "settle-9").trim }
  , { name := "campus: the plan names its domain and its problem",
      ok := (gold.splitOn "\"domain\":\"campus_sample\"").length == 2
        && (gold.splitOn "\"problem\":\"campus_sample_problem\"").length == 2 }
  , { name := "campus: the edited problems differ from the original, so their checks bite",
      ok := held != prob && solved != prob }
  , { name := "campus: a token already held is not acquired again",
      ok := !((ask held).contains "acquire-token-3") && (ask held).contains "settle-3" }
  , { name := "campus: a goal that already holds needs no step",
      ok := (ask solved).contains "\"steps\":[]" }
  , { name := "campus: a goal the problem does not declare is refused",
      ok := (ask (swap prob "/rfd/3" "/rfd/9")).contains "undeclared_goal" }
  , { name := "campus: a token that is never acquired leaves the goal unreachable",
      ok := (Persona.Jsonld.planOf (swap dom "\"pointer/set\": \"/token/3\""
        "\"pointer/set\": \"/token/9\"") prob).contains "unreachable" }
  , { name := "campus: a domain that is not JSON is refused",
      ok := (Persona.Jsonld.planOf "{" prob).contains "bad_domain" }
  , { name := "campus: a problem that is not JSON is refused",
      ok := (ask "{").contains "bad_problem" }
  , { name := "campus: a problem with no goal is refused",
      ok := (ask (swap prob "\"todo_list\"" "\"todos\"")).contains "no_goal" }
  , { name := "reach: the engine-shaped sample plans to the same steps as the pointer-shaped one",
      ok := steps (Persona.Jsonld.planOf rdom rprob) == steps gold }
  , { name := "reach: a task the domain does not name is refused",
      ok := (Persona.Jsonld.planOf rdom (rprob.replace "reach-rfd-3" "reach-rfd-9")).contains "undeclared_goal" }
  , { name := "reach: a goal already held by its first alternative needs no step",
      ok := (Persona.Jsonld.planOf rdom (rprob.replace "reach-rfd-3" "reach-rfd-1")).contains "\"steps\":[]" }
  , { name := "reach: a todo list with no entry is refused",
      ok := (Persona.Jsonld.planOf rdom (rprob.replace "reach-rfd-3" "")).contains "no_goal"
        || (Persona.Jsonld.planOf rdom (rprob.replace "\"todo_list\"" "\"todos\"")).contains "no_goal" }
  , { name := "reach: a chain of methods deeper than twelve still plans",
      ok := (Persona.Jsonld.planOf (chainDom 20) (chainProb 20)).contains "\"reached\":true" }
  , { name := "reach: the same chain with its action removed is refused",
      ok := (Persona.Jsonld.planOf ((chainDom 20).replace "\"act\":{" "\"actx\":{") (chainProb 20)).contains "unreachable" }
  , { name := "temporal: independent steps start together and the dependent one starts at the later end",
      ok := let t := Persona.Jsonld.planOf tempDom (tempProb "2026-11-02T00:00:00Z")
        t.contains "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-04T00:00:00Z\""
          && t.contains "\"action\":\"b\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-05T00:00:00Z\""
          && t.contains "\"action\":\"c\",\"params\":[],\"start\":\"2026-11-05T00:00:00Z\",\"end\":\"2026-11-06T00:00:00Z\"" }
  , { name := "temporal: the total is the critical path, not the sum, and is a duration",
      ok := (Persona.Jsonld.planOf tempDom (tempProb "2026-11-02T00:00:00Z")).contains "\"total\":\"P4D\""
        && !((Persona.Jsonld.planOf tempDom (tempProb "2026-11-02T00:00:00Z")).contains "\"total\":\"P6D\"") }
  , { name := "temporal: with no valid origin every start and end is unspecified and durations stay durations",
      ok := let t := Persona.Jsonld.planOf tempDom (tempProb "")
        t.contains "\"params\":[],\"duration\":\"P2D\"" && !(t.contains "\"start\"") && !(t.contains "\"end\":")
          && !((Persona.Jsonld.planOf tempDom (tempProb "2026-13-40T00:00:00Z")).contains "\"origin\"") }
  , { name := "temporal: an action that states no duration is instantaneous, so its start and end coincide and the total is zero",
      ok := let t := Persona.Jsonld.planOf ((tempDom.replace "\"duration\":\"P2D\"," "").replace "\"duration\":\"P3D\"," "" |>.replace "\"duration\":\"PT24H\"," "")
                (tempProb "2026-11-02T00:00:00Z")
        t.contains "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-02T00:00:00Z\",\"duration\":\"PT0S\""
          && t.contains "\"action\":\"c\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-02T00:00:00Z\",\"duration\":\"PT0S\""
          && t.contains "\"total\":\"PT0S\"" }
  , { name := "temporal: with no duration and no origin the start and end are unspecified and the duration is PT0S",
      ok := let t := Persona.Jsonld.planOf ((tempDom.replace "\"duration\":\"P2D\"," "").replace "\"duration\":\"P3D\"," "" |>.replace "\"duration\":\"PT24H\"," "")
                (tempProb "")
        t.contains "\"params\":[],\"duration\":\"PT0S\"" && !(t.contains "\"start\"") }
  , { name := "temporal: an action that states a start and an end has the end minus the start as its duration",
      ok := (Persona.Jsonld.planOf (tempDom.replace "\"duration\":\"P2D\"" "\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-04T00:00:00Z\"")
                (tempProb "")).contains "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-04T00:00:00Z\",\"duration\":\"P2D\"" }
  , { name := "temporal: a step the plan lists again is presented at its last possible time points",
      ok := let t := Persona.Jsonld.planOf tempWinDom (tempWinProb "2026-11-02T00:00:00Z")
        t.contains "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-04T00:00:00Z\""
          && t.contains "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-03T00:00:00Z\",\"end\":\"2026-11-05T00:00:00Z\""
          && t.contains "\"action\":\"b\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-05T00:00:00Z\""
          && t.contains "\"action\":\"c\",\"params\":[],\"start\":\"2026-11-05T00:00:00Z\",\"end\":\"2026-11-06T00:00:00Z\"" }
  , { name := "temporal: listing the steps again does not move the plan's total",
      ok := (Persona.Jsonld.planOf tempWinDom (tempWinProb "2026-11-02T00:00:00Z")).contains "\"total\":\"P4D\"" }
  , { name := "temporal: a start an action states is a release time, so it and the steps after it start no earlier",
      ok := let t := Persona.Jsonld.planOf (tempDom.replace "\"duration\":\"P2D\"" "\"start\":\"2026-11-05T00:00:00Z\",\"duration\":\"P2D\"")
                (tempProb "2026-11-02T00:00:00Z")
        t.contains "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-05T00:00:00Z\",\"end\":\"2026-11-07T00:00:00Z\""
          && t.contains "\"action\":\"c\",\"params\":[],\"start\":\"2026-11-07T00:00:00Z\",\"end\":\"2026-11-08T00:00:00Z\""
          && t.contains "\"total\":\"P6D\"" && t.contains "\"consistent\":true" }
  , { name := "temporal: an end an action states is a deadline, and a plan that misses it is not consistent",
      ok := (Persona.Jsonld.planOf (tempDom.replace "\"duration\":\"P2D\"" "\"end\":\"2026-11-03T00:00:00Z\",\"duration\":\"P2D\"")
                (tempProb "2026-11-02T00:00:00Z")).contains "\"consistent\":false"
        && (Persona.Jsonld.planOf (tempDom.replace "\"duration\":\"P2D\"" "\"end\":\"2026-11-04T00:00:00Z\",\"duration\":\"P2D\"")
                (tempProb "2026-11-02T00:00:00Z")).contains "\"consistent\":true" }
  , { name := "temporal: with no origin stated the plan starts at the earliest start an action states",
      ok := let t := Persona.Jsonld.planOf (tempDom.replace "\"duration\":\"P2D\"" "\"start\":\"2026-11-05T00:00:00Z\",\"duration\":\"P2D\"")
                (tempProb "")
        t.contains "\"origin\":\"2026-11-05T00:00:00Z\"" && t.contains "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-05T00:00:00Z\"" }
  , { name := "temporal: a datestamp carries across a month end, a leap day and a year end",
      ok := stampPlus "2026-02-27T12:00:00Z" 259200 == "2026-03-02T12:00:00Z"
        && stampPlus "2028-02-27T00:00:00Z" 172800 == "2028-02-29T00:00:00Z"
        && stampPlus "2026-12-31T23:59:59Z" 1 == "2027-01-01T00:00:00Z" }
  , { name := "temporal: a duration is written in its canonical ISO-8601 form",
      ok := Persona.Jsonld.fmtDur 0 == "PT0S" && Persona.Jsonld.fmtDur 90000 == "P1DT1H"
        && Persona.Jsonld.fmtDur 3661 == "PT1H1M1S" && Persona.Jsonld.fmtDur 259200 == "P3D" }
  , { name := "gtn: the first decomposition found takes the long way",
      ok := let t := Persona.Jsonld.planOf gtnDom (gtnProb ["/v/y"])
        t.contains "\"action\":\"b\"" && !(t.contains "\"action\":\"c\"") }
  , { name := "gtn: planning with a rising bound on the actions finds the plan with the fewest",
      ok := let t := Persona.Jsonld.shortestOf gtnDom (gtnProb ["/v/y"]) 10
        t.contains "\"length\":1" && t.contains "\"action\":\"c\"" && t.contains "\"optimal\":true" && !(t.contains "\"action\":\"b\"") }
  , { name := "gtn: a later goal that fails backtracks into the earlier goal's other alternative",
      ok := let t := Persona.Jsonld.planOf backDom (gtnProb ["/v/p", "/v/r"])
        t.contains "\"reached\":true" && t.contains "\"action\":\"u2\"" && !(t.contains "\"action\":\"u1\"") }
  , { name := "gtn: a goal no decomposition reaches keeps its refusal, and a bound too small says limit",
      ok := (Persona.Jsonld.shortestOf gtnDom (gtnProb ["/v/q"]) 10).contains "unreachable"
        && (Persona.Jsonld.shortestOf (gtnDom.replace "\"c\":{\"body\":[{\"pointer/set\":\"/v/y\",\"value\":1}]}" "\"c\":{\"body\":[{\"pointer/set\":\"/v/z\",\"value\":1}]}") (gtnProb ["/v/y"]) 1).contains "limit" }
  , { name := "web: the goals list names the goal the problem asks and declares it",
      ok := (Persona.Web.goalsOf dom prob).contains "\"goal\":\"/rfd/3\",\"declared\":true" }
  , { name := "web: a goal the problem holds already is reported held",
      ok := (Persona.Web.goalsOf dom held).contains "\"held\":false"
        && (Persona.Web.goalsOf dom solved).contains "\"held\":true" }
  , { name := "web: planning the one named goal equals planning all goals of a one-goal problem",
      ok := Persona.Web.planWith dom prob "/rfd/3" == ask prob
        && Persona.Web.planWith dom prob "" == ask prob }
  , { name := "web: a named goal no variable declares is refused",
      ok := (Persona.Web.planWith dom prob "/rfd/9").contains "undeclared_goal" }
  , { name := "web: the goals list of a domain that is not JSON is refused",
      ok := (Persona.Web.goalsOf "{" prob).contains "bad_domain" } ]

/-- The names of the actions in a plan document, in order. -/
def actionsOf (t : String) : List String :=
  (t.splitOn "\"action\":\"").drop 1 |>.map (fun x => (x.takeWhile (· != '"')).toString)

/-- The steps of a plan document as `name(arguments)`, or `REFUSED:why` for a refusal. -/
def stepKeys (t : String) : List String :=
  if t.contains "\"refused\"" then ["REFUSED:" ++ ((((t.splitOn "\"refused\":\"").drop 1).headD "").takeWhile (· != '"')).toString]
  else
    (t.splitOn "\"action\":\"").drop 1 |>.map fun x =>
      let name := (x.takeWhile (· != '"')).toString
      let inner := ((((x.splitOn "\"params\":[").drop 1).headD "").takeWhile (· != ']')).toString.replace "\"" ""
      if inner == "" then name else name ++ "(" ++ inner ++ ")"

/-- Enums: named integers, resolved when the document is read and printed as names in the plan. -/
def enumChecks : IO (List Check) := do
  let dir := "tests/enums/"
  let dom ← IO.FS.readFile (dir ++ "domain.jsonld")
  let mut out : List Check := []
  for name in ["members-print-as-names", "member-as-a-value", "qualified-member", "ambiguous-member",
               "ambiguous-bare-refused", "unknown-member", "numbers-still-work"] do
    let prob ← IO.FS.readFile (dir ++ name ++ ".problem.jsonld")
    let expect := ((← IO.FS.readFile (dir ++ name ++ ".expect")).splitOn "\n").filter (· != "")
    out := out ++ [{ name := "enums: " ++ name, ok := stepKeys (Persona.Jsonld.planOf dom prob) == expect }]
  return out

/-- A problem's own codebook, names that key the initial state, equality preconditions and names in plan steps. -/
def vocabChecks : IO (List Check) := do
  let dir := "tests/vocab/"
  let dom ← IO.FS.readFile (dir ++ "domain.jsonld")
  let mut out : List Check := []
  for name in ["names-print", "order-is-the-problems", "equality-refuses", "name-not-in-codebook"] do
    let prob ← IO.FS.readFile (dir ++ name ++ ".problem.jsonld")
    let expect := ((← IO.FS.readFile (dir ++ name ++ ".expect")).splitOn "\n").filter (· != "")
    out := out ++ [{ name := "vocab: " ++ name, ok := stepKeys (Persona.Jsonld.planOf dom prob) == expect }]
  return out

/-- The cases ported from GTPyhop's `blocks_gtn` and `blocks_htn` (the same states and plans, with the top task named achieve): the failures, the simple successes, the two multigoals and the
Sussman anomaly, each with the plan GTPyhop expects. -/
def blocksChecks (case : String) : IO (List Check) := do
  let dir := "tests/gtpyhop/" ++ case ++ "/"
  let dom ← IO.FS.readFile (dir ++ "domain.jsonld")
  let mut out : List Check := []
  for name in ["pickup-a", "pickup-b", "take-b", "pickup-c", "take-a", "take-c", "take-a-put-a-table",
               "goal1a", "goal1b", "sussman", "goal2a", "goal2b", "goal2b-done", "goal3"] do
    let prob ← IO.FS.readFile (dir ++ name ++ ".problem.jsonld")
    let expect := ((← IO.FS.readFile (dir ++ name ++ ".expect")).splitOn "\n").filter (· != "")
    out := out ++ [{ name := "gtpyhop " ++ case ++ ": " ++ name, ok := stepKeys (Persona.Jsonld.planOf dom prob) == expect }]
  let sus ← IO.FS.readFile (dir ++ "sussman.problem.jsonld")
  let best := Persona.Jsonld.shortestOf dom sus 40
  out := out ++ [{ name := "gtpyhop " ++ case ++ ": the shortest plan for the Sussman anomaly has six actions",
                   ok := best.contains "\"length\":6" && best.contains "\"optimal\":true" }
                , { name := "gtpyhop " ++ case ++ ": a bound of five is refused as limit, since the top task is not done while a block can move",
                    ok := (Persona.Jsonld.shortestOf dom sus 5).contains "limit" }]
  return out

/-- The cases ported from GTPyhop's unigoal domains (`blocks_hgn`, `blocks_goal_splitting`): every problem listed in
the case's `cases` file plans to the actions GTPyhop 2.0.2 returned, or is refused, as recorded. -/
def unigoalChecks (case : String) : IO (List Check) := do
  let dir := "tests/gtpyhop/" ++ case ++ "/"
  let dom ← IO.FS.readFile (dir ++ "domain.jsonld")
  let names := ((← IO.FS.readFile (dir ++ "cases")).splitOn "\n").filter (· != "")
  let mut out : List Check := []
  for name in names do
    let prob ← IO.FS.readFile (dir ++ name ++ ".problem.jsonld")
    let expect := ((← IO.FS.readFile (dir ++ name ++ ".expect")).splitOn "\n").filter (· != "")
    out := out ++ [{ name := "gtpyhop " ++ case ++ ": " ++ name, ok := stepKeys (Persona.Jsonld.planOf dom prob) == expect }]
  if case == "blocks_goal_splitting" then
    -- goal splitting's plan for goal1a is not blocks_gtn's: the encoding is not the moveblocks graph in disguise
    let gtn := ((← IO.FS.readFile "tests/gtpyhop/blocks_gtn/goal1a.expect").splitOn "\n").filter (· != "")
    let gs := ((← IO.FS.readFile (dir ++ "goal1a.expect")).splitOn "\n").filter (· != "")
    out := out ++ [{ name := "gtpyhop blocks_goal_splitting: goal1a is not the blocks_gtn plan", ok := gs != gtn && gs.length > gtn.length }]
  return out

/-- A method alternative with a graph: the graph runs on the state and its variables decide the subtasks. -/
def graphChecks : IO (List Check) := do
  let dir := "tests/graph/"
  let dom ← IO.FS.readFile (dir ++ "domain.jsonld")
  let mut out : List Check := []
  for name in ["hit-in-the-middle", "first-hit-wins", "last-cell", "no-hit-falls-back"] do
    let prob ← IO.FS.readFile (dir ++ name ++ ".problem.jsonld")
    let expect := ((← IO.FS.readFile (dir ++ name ++ ".expect")).splitOn "\n").filter (· != "")
    out := out ++ [{ name := "graph method: " ++ name, ok := stepKeys (Persona.Jsonld.planOf dom prob) == expect }]
  return out

/-- The KHR_interactivity subset: each graph runs and its variables end at the values expected, or it is
refused for the reason expected. -/
def khrChecks : IO (List Check) := do
  let dir := "tests/khr/"
  let mut out : List Check := []
  for name in ["for-sums", "for-empty", "for-end-read-each-pass", "branch-true", "branch-false", "branch-needs-bool", "while-counts", "select", "math-switch", "math-switch-default", "int-wraps", "eq-one-type", "pointer-valid", "sequence-string-order", "variable-set-two", "variable-out-of-range", "float-type", "unbuilt-node", "fuel"] do
    let g ← IO.FS.readFile (dir ++ name ++ ".graph.json")
    let expect := ((← IO.FS.readFile (dir ++ name ++ ".expect")).splitOn "\n").filter (· != "")
    let fuel := ((← IO.FS.readFile (dir ++ name ++ ".fuel")).trim.toNat?).getD 100000
    let got := match Lean.Json.parse g with
      | .error e => ["ERROR:" ++ e]
      | .ok j =>
        match Persona.Khr.runGraph j [] [] fuel with
        | .error e => ["ERROR:" ++ e]
        | .ok vs => vs.map fun (k, v) => k ++ "=" ++ toString v
    let ok := match expect with
      | [e] => if e.startsWith "ERROR:" then got.any (fun x => x.startsWith "ERROR:" && (x.splitOn (e.drop 6).toString).length > 1) else got == expect
      | _ => got == expect
    out := out ++ [{ name := "khr: " ++ name, ok := ok }]
  return out

/-- Actions, methods and tasks that take parameters. -/
def paramChecks : IO (List Check) := do
  let dir := "tests/params/"
  let dom ← IO.FS.readFile (dir ++ "domain.jsonld")
  let mut out : List Check := []
  for name in ["finish-two", "use-without-mark", "value-reaches", "value-falls-short", "missing-argument", "finish-name", "finish-name-and-number", "name-not-interned", "digits-as-string"] do
    let prob ← IO.FS.readFile (dir ++ name ++ ".problem.jsonld")
    let expect := ((← IO.FS.readFile (dir ++ name ++ ".expect")).splitOn "\n").filter (· != "")
    out := out ++ [{ name := "params: " ++ name ++ " gives the expected steps", ok := stepKeys (Persona.Jsonld.planOf dom prob) == expect }]
  return out

/-- The cases ported from GTPyhop's `backtracking_htn`: each problem's plan is the one GTPyhop expects. -/
def gtpyhopChecks : IO (List Check) := do
  let dir := "tests/gtpyhop/backtracking_htn/"
  let dom ← IO.FS.readFile (dir ++ "domain.jsonld")
  let mut out : List Check := []
  for name in ["put_it-need0", "put_it-need01", "put_it-need10", "put_it-need1"] do
    let prob ← IO.FS.readFile (dir ++ name ++ ".problem.jsonld")
    let expect := ((← IO.FS.readFile (dir ++ name ++ ".expect")).splitOn "\n").filter (· != "")
    let got := actionsOf (Persona.Jsonld.planOf dom prob)
    out := out ++ [{ name := "gtpyhop backtracking_htn: " ++ name ++ " plans to the expected actions"
                   , ok := got == expect }
                  , { name := "gtpyhop backtracking_htn: " ++ name ++ " is not GTPyhop's other expected plan"
                    , ok := got != (if expect == ["putv-0", "getv-0", "getv-0"] then ["putv-1", "getv-1", "getv-1"]
                                    else ["putv-0", "getv-0", "getv-0"]) }]
  return out

def run : IO UInt32 := do
  let dom ← IO.FS.readFile "domains/campus-sample.jsonld"
  let prob ← IO.FS.readFile "problems/campus-sample.jsonld"
  let gold ← IO.FS.readFile "plans/campus-sample.jsonld"
  let rdom ← IO.FS.readFile "domains/campus-sample-reach.jsonld"
  let rprob ← IO.FS.readFile "problems/campus-sample-reach.jsonld"
  let g ← gtpyhopChecks
  let pc ← paramChecks
  let kc ← khrChecks
  let ec ← enumChecks
  let gc ← graphChecks
  let vc ← vocabChecks
  let bc ← blocksChecks "blocks_gtn"
  let bh ← blocksChecks "blocks_htn"
  let uh ← unigoalChecks "blocks_hgn"
  let ug ← unigoalChecks "blocks_goal_splitting"
  let checks := checks ++ campusChecks dom prob gold rdom rprob ++ g ++ pc ++ kc ++ ec ++ gc ++ vc ++ bc ++ bh ++ uh ++ ug
  for c in checks do
    let tag := if c.ok then "ok  " else "FAIL"
    IO.println s!"  [{tag}] {c.name}"
  let bad := checks.filter (fun c => !c.ok)
  if bad.isEmpty then
    IO.println s!"OK: persona, {checks.length} invariants hold (codebook, answer and refusals verified)"
    return 0
  else
    IO.println s!"FAIL: {bad.length} of {checks.length} invariants failed"
    return 1

end PersonaWitness

def main : IO UInt32 := PersonaWitness.run
