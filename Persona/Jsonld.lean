import Persona.Guest
import Lean.Data.Json
import Planner.Iso8601Duration
import Persona.Khr

namespace Persona.Jsonld

open Lean Persona

inductive Task where
  | goal : String → Task
  /-- A named task: a method when the domain has one by that name, an action otherwise. -/
  | call : String → List String → Task

/-- What a document names: its codebook, the interned string list in which a name is its index, and its
enums, each a name with named integer members. A member is written as `enum.member`, or as `member` alone
when no other enum has it. -/
structure Vocab where
  names : List String := []
  enums : List (String × List (String × Int)) := []

structure Act where
  vocab : Vocab
  name  : String
  /-- The parameters the action names, replaced in its body by the arguments of a call. -/
  params : List String
  /-- The enum each parameter is typed by, for printing its argument as a name. -/
  paramEnums : List (Option String)
  /-- The action as written, kept so a call can replace its parameters before it is read. -/
  raw   : Json
  dur   : Nat
  /-- A start the action states, as seconds since the epoch. -/
  statedStart : Option Nat
  /-- An end the action states, as seconds since the epoch. -/
  statedEnd : Option Nat
  evals : List (String × String × String)
  holds : List (String × Int)
  /-- Facts that must be exactly a value: `math/eq` over a `pointer/get`. -/
  eqs   : List (String × Int)
  sets  : List (String × Int)

/-- A method alternative: the facts that must hold for it to apply, then its subtasks in order. -/
structure Alt where
  vocab : Vocab
  eqs : List (String × Int)
  /-- A KHR_interactivity graph, run on the current state before the alternative is read. -/
  graph : Option Json
  params : List String
  raw    : Json
  checks : List (String × Int)
  tasks  : List Task

structure Spec where
  acts    : List Act
  methods : List (String × List Alt)
  init    : List (String × Int)
  edges   : List (String × String × String)

structure St where
  vals  : List (String × Int)
  edges : List (String × String × String)
  plan  : List String

def entries (j : Json) : List (String × Json) :=
  match j.getObj? with
  | .ok o => o.toList
  | .error _ => []

def items (j : Json) : List Json :=
  match j.getArr? with
  | .ok a => a.toList
  | .error _ => []

def str (j : Json) : String := (j.getStr?.toOption).getD ""

def codebookOf (j : Json) : List String :=
  (items (j.getObjValD "codebook")).filterMap fun x => x.getStr?.toOption

/-- An enum is an object of members with their integers, or an array of members numbered from zero. -/
def enumsOf (j : Json) : List (String × List (String × Int)) :=
  (entries (j.getObjValD "enums")).map fun (k, v) =>
    (k, match v.getArr? with
      | .ok a => (a.toList.filterMap fun x => x.getStr?.toOption).zipIdx.map fun (m, i) => (m, (i : Int))
      | .error _ => (entries v).filterMap fun (m, x) => x.getInt?.toOption.map (m, ·))

def vocabOf (j : Json) : Vocab := { names := codebookOf j, enums := enumsOf j }

/-- A problem's own codebook, when it has one, replaces the domain's: the order of a codebook is the order of
its entries, so a problem can fix the numbering a loop over its blocks follows. Enums add up. -/
def mergeVocab (d p : Vocab) : Vocab :=
  { names := if p.names.isEmpty then d.names else p.names, enums := d.enums ++ p.enums }

def vocabText (text : String) : Vocab :=
  match Json.parse text with
  | .ok j => vocabOf j
  | .error _ => {}

/-- A key of a variable's initial values: an entry of the codebook is its index. -/
def keyOf (v : Vocab) (k : String) : String :=
  match v.names.findIdx? (· == k) with
  | some i => toString i
  | none => k

/-- The integer an enum member names, written `enum.member` or, when no other enum has it, `member`. -/
def memberOf (v : Vocab) (s : String) : Option Int :=
  match s.splitOn "." with
  | [e, m] => ((v.enums.find? (·.1 == e)).bind fun en => (en.2.find? (·.1 == m)).map (·.2))
  | [m] =>
    match v.enums.filterMap fun en => (en.2.find? (·.1 == m)).map (·.2) with
    | [i] => some i
    | _ => none
  | _ => none

/-- An integer, written as a number or as an enum member. glTF interactivity has numerics and pointers
and no strings, so the planner sees only numbers: a name is resolved when the document is read. -/
def intOf (v : Vocab) (j : Json) : Option Int :=
  match j.getInt? with
  | .ok i => some i
  | .error _ =>
    match j.getBool? with
    | .ok b => some (if b then 1 else 0)
    | .error _ =>
      (j.getStr?.toOption).bind fun s => (memberOf v s).orElse fun _ => (v.names.findIdx? (· == s)).map (fun i => (i : Int))

/-- An argument as the text of its number: an integer, an enum member, or a string that is an entry of
the codebook, which is its index. A string that is none of these is not an argument. -/
def argNum (v : Vocab) (j : Json) : Option String :=
  match intOf v j with
  | some i => some (toString i)
  | none =>
    match j.getStr? with
    | .ok s => (v.names.findIdx? (· == s)).map toString
    | .error _ => none

/-- The task a call to nothing stands for, which no method or action answers to. -/
def noTask : String := "no-numeric-argument"

def parseTask (v : Vocab) (j : Json) : Task :=
  match items j with
  | s :: p :: rest =>
    if str s == "goal" then .goal (str p)
    else
      let args := (p :: rest).map (argNum v)
      if args.all Option.isSome then .call (str s) (args.filterMap id) else .call noTask []
  | s :: _ => .call (str s) []
  | [] => .call "" []

/-- A fact that must be at least a value: `pointer/ge`, or `math/ge` over a `pointer/get`. -/
def holdOf (v : Vocab) (e : Json) : Option (String × Int) :=
  if str (e.getObjValD "type") == "pointer/ge" then
    some (str (e.getObjValD "pointer"), (intOf v (e.getObjValD "value")).getD 1)
  else if str (e.getObjValD "type") == "math/ge" then
    some (str ((e.getObjValD "a").getObjValD "pointer"), (intOf v (e.getObjValD "b")).getD 1)
  else none

/-- A fact that must be exactly a value: `math/eq` over a `pointer/get` and a number. -/
def eqOf (v : Vocab) (e : Json) : Option (String × Int) :=
  if str (e.getObjValD "type") == "math/eq" then
    some (str ((e.getObjValD "a").getObjValD "pointer"), (intOf v (e.getObjValD "b")).getD 0)
  else none

/-- Days since 1970-01-01 of a civil date (year 1970 or later). -/
def daysFromCivil (y0 m d : Int) : Int :=
  let y := if m ≤ 2 then y0 - 1 else y0
  let era := y / 400
  let yoe := y - era * 400
  let mp := (m + 9) % 12
  let doy := (153 * mp + 2) / 5 + d - 1
  let doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468

def civilFromDays (z0 : Int) : Int × Int × Int :=
  let z := z0 + 719468
  let era := z / 146097
  let doe := z - era * 146097
  let yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y := yoe + era * 400
  let doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp := (5 * doy + 2) / 153
  let d := doy - (153 * mp + 2) / 5 + 1
  let m := if mp < 10 then mp + 3 else mp - 9
  ((if m ≤ 2 then y + 1 else y), m, d)

def pad (n w : Nat) : String :=
  let t := toString n
  String.mk (List.replicate (w - t.length) '0') ++ t

/-- A datestamp `YYYY-MM-DDTHH:MM:SSZ` as seconds since the epoch, or none when it is not one. -/
def parseStamp (s : String) : Option Nat :=
  let c := s.toList
  let num := fun (a b : Nat) => (String.mk ((c.drop a).take (b - a))).toNat?
  if c.length != 20 then none
  else
    match num 0 4, num 5 7, num 8 10, num 11 13, num 14 16, num 17 19 with
    | some y, some mo, some d, some h, some mi, some se =>
      if c[4]? == some '-' && c[7]? == some '-' && c[10]? == some 'T' && c[13]? == some ':'
          && c[16]? == some ':' && c[19]? == some 'Z' && y ≥ 1970 && 1 ≤ mo && mo ≤ 12
          && 1 ≤ d && d ≤ 31 && h < 24 && mi < 60 && se < 60 then
        some ((daysFromCivil y mo d).toNat * 86400 + h * 3600 + mi * 60 + se)
      else none
    | _, _, _, _, _, _ => none

def fmtStamp (t : Nat) : String :=
  let (y, m, d) := civilFromDays (t / 86400 : Nat)
  pad y.toNat 4 ++ "-" ++ pad m.toNat 2 ++ "-" ++ pad d.toNat 2 ++ "T" ++ pad (t % 86400 / 3600) 2
    ++ ":" ++ pad (t % 3600 / 60) 2 ++ ":" ++ pad (t % 60) 2 ++ "Z"

/-- An action's own duration in seconds. It is the ISO-8601 `duration` the action states, or else the
end minus the start when it states both, and an action that states neither is instantaneous. -/
def durOf (j : Json) : Nat :=
  match Iso8601Duration.parse (str (j.getObjValD "duration")) with
  | .ok cs => Iso8601Duration.totalSeconds cs
  | .error _ =>
    match parseStamp (str (j.getObjValD "start")), parseStamp (str (j.getObjValD "end")) with
    | some a, some b => b - a
    | _, _ => 0

/-- A parameter is written as its name, or as an object with its name and the enum that types it. -/
def paramName (j : Json) : String :=
  match j.getStr? with
  | .ok s => s
  | .error _ => str (j.getObjValD "name")

def paramEnum (j : Json) : Option String :=
  match (j.getObjValD "enum").getStr? with
  | .ok e => some e
  | .error _ => none

def parseAct (v : Vocab) (name : String) (j : Json) : Act :=
  let body := items (j.getObjValD "body")
  { vocab := v
  , name := name
  , params := (items (j.getObjValD "params")).map paramName
  , paramEnums := (items (j.getObjValD "params")).map paramEnum
  , raw := j
  , dur := durOf j
  , statedStart := parseStamp (str (j.getObjValD "start"))
  , statedEnd := parseStamp (str (j.getObjValD "end"))
  , evals := body.filterMap fun b =>
      let e := b.getObjValD "eval"
      if str (e.getObjValD "type") == "rebac/check" then
        some (str (e.getObjValD "subject"), str (e.getObjValD "rel"), str (e.getObjValD "object"))
      else none
  , holds := body.filterMap fun b => holdOf v (b.getObjValD "eval")
  , eqs := body.filterMap fun b => eqOf v (b.getObjValD "eval")
  , sets := body.filterMap fun b =>
      match b.getObjVal? "pointer/set" with
      | .ok p => some (str p, (intOf v (b.getObjValD "value")).getD 0)
      | .error _ => none }

def substStr (env : List (String × String)) (s : String) : String :=
  env.foldl (fun acc (k, v) => acc.replace ("[" ++ k ++ "]") v) s

/-- A JSON value with `{name}` replaced by its argument in every string. -/
partial def substJson (env : List (String × String)) (j : Json) : Json :=
  match j with
  | .str s => .str (substStr env s)
  | .arr a => .arr (a.map (substJson env))
  | .obj _ =>
    match entries j with
    | [("param", p)] =>
      match (env.find? (·.1 == str p)).bind (·.2.toInt?) with
      | some i => Json.num (JsonNumber.fromInt i)
      | none => j
    | es => Json.mkObj (es.map fun (k, v) => (k, substJson env v))
  | _ => j

def parseAlt (v : Vocab) (params : List String) (alt : Json) : Alt :=
  { vocab := v, graph := (alt.getObjVal? "graph").toOption
  , eqs := (items (alt.getObjValD "check")).filterMap fun c => eqOf v (c.getObjValD "eval"), params := params, raw := alt
  , checks := (items (alt.getObjValD "check")).filterMap fun c => holdOf v (c.getObjValD "eval")
  , tasks := (items (alt.getObjValD "subtasks")).map (parseTask v) }

/-- The action with its arguments in place of its parameters; none when the arity is wrong. -/
def instAct (a : Act) (args : List String) : Option Act :=
  if a.params.length != args.length then none
  else if a.params.isEmpty then some a
  else some (parseAct a.vocab a.name (substJson (a.params.zip args) a.raw))

/-- The alternative as written, without its graph: a graph's `[name]` are its own input sockets, which a
parameter must not replace. -/
def withoutGraph (j : Json) : Json := Json.mkObj ((entries j).filter (·.1 != "graph"))

def withGraph (g : Option Json) (j : Json) : Json :=
  match g with
  | some x => Json.mkObj ((entries j) ++ [("graph", x)])
  | none => j

def instAlt (a : Alt) (args : List String) : Option Alt :=
  if a.params.length != args.length then none
  else if a.params.isEmpty then some a
  else some (parseAlt a.vocab [] (substJson (a.params.zip args) (withoutGraph a.raw) |> withGraph a.graph))

/-- A plan step is its action's name, or the name and its arguments as `name(a,b)`. -/
def stepKey (n : String) (args : List String) : String :=
  if args.isEmpty then n else n ++ "(" ++ String.intercalate "," args ++ ")"

def splitKey (k : String) : String × List String :=
  match k.splitOn "(" with
  | n :: rest =>
    if rest.isEmpty then (k, []) else (n, ((String.intercalate "(" rest).dropRight 1).splitOn ",")
  | [] => (k, [])

/-- A domain document: actions, methods, and the variables it declares with their defaults. -/
def parse (text : String) : Except String Spec := do
  let j ← Json.parse text
  let voc := vocabOf j
  let init := (items (j.getObjValD "variables")).flatMap fun v =>
    (entries (v.getObjValD "init")).map fun (k, x) =>
      ("/" ++ str (v.getObjValD "name") ++ "/" ++ keyOf voc k, (intOf voc x).getD 0)
  return { acts := (entries (j.getObjValD "actions")).map fun (n, a) => parseAct voc n a
         , methods := (entries (j.getObjValD "methods")).map fun (p, m) =>
             (p, (items (m.getObjValD "alternatives")).map
               (parseAlt voc ((items (m.getObjValD "params")).map paramName)))
         , init, edges := [] }

structure Problem where
  name  : String
  init  : List (String × Int)
  edges : List (String × String × String)
  goals : List String
  /-- The todo list's named tasks, in order: `["reach-rfd-3"]`. -/
  calls : List (String × List String)
  /-- The plan origin as an ISO-8601 datestamp. A problem that states none, or one that is not a
datestamp, takes the earliest start an action states, and with none leaves every start and end
unspecified. -/
  origin : String

/-- A problem document: the facts that hold at the start, the graph edges, and the goals. -/
def parseProblem (text : String) (voc : Vocab := {}) : Except String Problem := do
  let j ← Json.parse text
  let init := (items (j.getObjValD "variables")).flatMap fun v =>
    (entries (v.getObjValD "init")).map fun (k, x) =>
      ("/" ++ str (v.getObjValD "name") ++ "/" ++ keyOf voc k, (intOf voc x).getD 0)
  let edges := (items (((j.getObjValD "capabilities").getObjValD "graph").getObjValD "edges")).map
    fun e => (str (e.getObjValD "subject"), str (e.getObjValD "rel"), str (e.getObjValD "object"))
  let goals := (items (j.getObjValD "todo_list")).flatMap fun t =>
    (items (t.getObjValD "goal")).map fun g => str (g.getObjValD "pointer")
  let todo := items (j.getObjValD "todo_list")
  let calls := todo.filterMap fun t =>
    match items t with
    | s :: rest =>
      let args := rest.map (argNum voc)
      if args.all Option.isSome then some (str s, args.filterMap id) else some (noTask, [])
    | [] => none
  return { name := str (j.getObjValD "name"), init, edges, goals, calls
         , origin := str (j.getObjValD "origin") }

def lookup (vals : List (String × Int)) (p : String) : Int :=
  ((vals.find? (·.1 == p)).map (·.2)).getD 0

def store (vals : List (String × Int)) (p : String) (v : Int) : List (String × Int) :=
  if vals.any (·.1 == p) then vals.map fun x => if x.1 == p then (p, v) else x else vals ++ [(p, v)]

/-- The tasks an alternative gives on the state `vals`, or none when it does not apply. An alternative with a
graph runs it first: the graph's variables are readable by the checks as the pointers `/graph/<id>`, and by
the subtasks as `[id]` in a string and `{"param": id}` for a number. A graph that cannot run, because it is
rejected or spends its fuel, makes the alternative not apply. -/
def expandAlt (alt0 : Alt) (args : List String) (vals : List (String × Int)) : Option (List Task) := do
  let alt ← instAlt alt0 args
  match alt.graph with
  | none =>
    if alt.checks.all (fun h => lookup vals h.1 ≥ h.2) && alt.eqs.all (fun h => lookup vals h.1 == h.2)
    then some alt.tasks else none
  | some g =>
    let inputs := alt0.params.zip args |>.filterMap fun (p, a) => a.toInt?.map (p, ·)
    match Khr.runGraph g vals inputs with
    | .error _ => none
    | .ok gv =>
      let valsG := vals ++ gv.map (fun (k, v) => ("/graph/" ++ k, v))
      let env := gv.map (fun (k, v) => (k, toString v))
      let alt2 := parseAlt alt.vocab [] (substJson env (withoutGraph alt.raw))
      if alt2.checks.all (fun h => lookup valsG h.1 ≥ h.2) && alt2.eqs.all (fun h => lookup valsG h.1 == h.2)
      then some alt2.tasks else none

/-- Decompose a task: a goal already held is no step, a goal is met by the first method
alternative whose subtasks all succeed in order, and an action fails when the graph does
not hold an edge it checks. -/
partial def run (sp : Spec) (bound : Nat) : List (Task × Nat) → St → Option St
  | [], s => some s
  | (t, fuel) :: rest, s =>
    match t with
    | .call n args =>
      match sp.methods.find? (·.1 == n) with
      | some m =>
        match fuel with
        | 0 => none
        | f + 1 =>
          m.2.findSome? fun alt0 =>
            match expandAlt alt0 args s.vals with
            | none => none
            | some tasks => run sp bound (tasks.map (fun u => (u, f)) ++ rest) s
      | none =>
        match (sp.acts.find? (·.name == n)).bind (fun a0 => instAct a0 args) with
        | none => none
        | some a =>
          if s.plan.length < bound && a.evals.all (fun e => s.edges.contains e)
              && a.holds.all (fun h => lookup s.vals h.1 ≥ h.2)
              && a.eqs.all (fun h => lookup s.vals h.1 == h.2) then
            run sp bound rest { s with vals := a.sets.foldl (fun v w => store v w.1 w.2) s.vals,
                                       plan := s.plan ++ [stepKey n args] }
          else none
    | .goal p =>
      if lookup s.vals p ≥ 1 then run sp bound rest s
      else
        match fuel with
        | 0 => none
        | f + 1 =>
          match sp.methods.find? (·.1 == p) with
          | none => none
          | some m =>
            m.2.findSome? fun alt0 =>
              match expandAlt alt0 [] s.vals with
              | none => none
              | some tasks => run sp bound (tasks.map (fun u => (u, f)) ++ rest) s

/-- Seconds as a canonical ISO-8601 duration: `PT0S`, `P3D`, `P1DT2H30M`. -/
def fmtDur (s : Nat) : String :=
  let d := s / 86400
  let h := s % 86400 / 3600
  let m := s % 3600 / 60
  let x := s % 60
  if s == 0 then "PT0S"
  else
    "P" ++ (if d > 0 then toString d ++ "D" else "")
      ++ (if h + m + x > 0 then
            "T" ++ (if h > 0 then toString h ++ "H" else "") ++ (if m > 0 then toString m ++ "M" else "")
              ++ (if x > 0 then toString x ++ "S" else "")
          else "")

/-- A start or an end: the datestamp at `offset` seconds from the origin, and none when the problem
states no origin, so the start or end is unspecified. -/
def stampAt (origin : Option Nat) (offset : Nat) : Option String :=
  origin.map fun o => fmtStamp (o + offset)

/-- A field of a step or of the plan, written only when it is specified. -/
def field (name : String) (value : Option String) : String :=
  match value with
  | some v => ",\"" ++ name ++ "\":" ++ Guest.quote v
  | none => ""

/-- A step's arguments as they read: the name of the enum member a typed parameter has, else the number. -/
def readable (sp : Spec) (names : List String) (k : String) : List String :=
  let (n, args) := splitKey k
  match sp.acts.find? (·.name == n) with
  | none => args
  | some a =>
    (args.zip (a.paramEnums ++ args.map (fun _ => none))).map fun (x, e) =>
      match e, x.toInt? with
      | some "codebook", some i => (names[i.toNat]?).getD x
      | some en, some i =>
        match (a.vocab.enums.find? (·.1 == en)).bind (fun m => m.2.find? (·.2 == i)) with
        | some (name, _) => name
        | none => x
      | _, _ => x

/-- The action a plan step names, with its arguments in place. -/
def actOfKey (sp : Spec) (k : String) : Option Act :=
  let (n, args) := splitKey k
  (sp.acts.find? (·.name == n)).bind fun a => instAct a args

/-- Each step of the plan starts when every earlier step that sets a fact it needs has ended, so
independent steps overlap. The plan's total is the latest end. -/
def schedule (sp : Spec) (origin : Option Nat) (plan : List String) : List (String × Nat × Nat) × Nat :=
  let slots := plan.foldl (fun (acc : List (String × Nat × Nat)) n =>
    match actOfKey sp n with
    | none => acc ++ [(n, 0, 0)]
    | some a =>
      let release := match origin, a.statedStart with
        | some o, some st => st - o
        | _, _ => 0
      let start := acc.foldl (fun t (m, _, e) =>
        match actOfKey sp m with
        | some b => if b.sets.any (fun w => (a.holds ++ a.eqs).any (·.1 == w.1)) then max t e else t
        | none => t) release
      acc ++ [(n, start, start + a.dur)]) []
  (slots, slots.foldl (fun t (_, _, e) => max t e) 0)

/-- The last possible start and end of each step that still lets the plan finish at `total`: a step
must end by the latest start of every later step that needs a fact it sets, and the last step by the
plan's end. -/
def latestTimes (sp : Spec) (origin : Option Nat) (plan : List String) (total : Nat) :
    List (Nat × Nat) :=
  let acts := (plan.map fun nm => actOfKey sp nm).toArray
  let n := acts.size
  let res := (List.range n).reverse.foldl (fun (res : Array (Nat × Nat)) i =>
    let d := ((acts[i]!).map (·.dur)).getD 0
    let fin := (List.range n).foldl (fun t k =>
      if k > i then
        match acts[i]!, acts[k]! with
        | some a, some b =>
          if a.sets.any (fun w => b.holds.any (·.1 == w.1)) then min t (res[k]!).1 else t
        | _, _ => t
      else t) (match origin, (acts[i]!).bind (·.statedEnd) with
        | some o, some e => min total (e - o)
        | _, _ => total)
    res.set! i (fin - d, fin)) (Array.replicate n (0, 0))
  res.toList

/-- A plan's steps with each name once, in the order they first appear. -/
def firstOccurrences (plan : List String) : List String :=
  plan.foldl (fun acc n => if acc.contains n then acc else acc ++ [n]) []

def docName (text : String) : String :=
  match Json.parse text with
  | .ok j => str (j.getObjValD "name")
  | .error _ => ""

def vsekai : String := "\"@context\":{\"VSEKAI\":\"https://v-sekai.org/\",\"domain\":\"VSEKAI:planning/domain/\"}"

def refusal (domain problem why : String) : String :=
  "{" ++ vsekai ++ ",\"@type\":\"domain:Plan\",\"domain\":" ++ Guest.quote domain
    ++ ",\"problem\":" ++ Guest.quote problem ++ ",\"refused\":" ++ Guest.quote why ++ "}"

/-- The plan document: the domain and the problem it answers, the steps in order, and whether the
planner's own goal test holds on the final state for every goal of the problem. -/
def planOf (domain problem : String) (only : Option String := none) (bound : Nat := 1000000) : String :=
  let dn := docName domain
  let pn := docName problem
  let voc := mergeVocab (vocabText domain) (vocabText problem)
  match parse domain, parseProblem problem voc with
  | .error _, _ => refusal dn pn "bad_domain"
  | _, .error _ => refusal dn pn "bad_problem"
  | .ok sp, .ok pb0 =>
    -- `only` narrows the problem to one goal; a goal no variable declares meets `undeclared_goal` below.
    let pb := match only with
      | none => pb0
      | some g => { pb0 with goals := [g] }
    let known := sp.init ++ pb.init
    let named := fun (n : String) => sp.methods.any (·.1 == n) || sp.acts.any (·.name == n)
    if pb.goals.isEmpty && pb.calls.isEmpty then refusal dn pn "no_goal"
    else if pb.goals.any (fun g => !(known.any (·.1 == g))) || pb.calls.any (fun c => !named c.1) then
      refusal dn pn "undeclared_goal"
    else
      let start : St := { vals := pb.init.foldl (fun v w => store v w.1 w.2) sp.init
                        , edges := pb.edges, plan := [] }
      let fuel := sp.methods.length + 1000
      let tasks := pb.goals.map (fun g => (Task.goal g, fuel)) ++ pb.calls.map (fun c => (Task.call c.1 c.2, fuel))
      match run sp bound tasks start with
      | none => refusal dn pn "unreachable"
      | some s =>
        let st : GTNState := { variables := s.vals.mapIdx fun i x => ⟨i, x.2⟩
                             , executable_trace := [] }
        let ok := pb.goals.all fun g =>
          is_node_satisfied st (.goal_geq ((s.vals.findIdx? (·.1 == g)).getD 0) 1)
        let firsts := firstOccurrences s.plan
        let stated := firsts.filterMap fun n => (actOfKey sp n).bind (·.statedStart)
        let origin := match parseStamp pb.origin with
          | some o => some o
          | none => stated.min?
        let (slots, total) := schedule sp origin firsts
        let late := (firsts.zip (latestTimes sp origin firsts total))
        let holds := firsts.all fun n =>
          match origin, (actOfKey sp n).bind (·.statedEnd), slots.find? (·.1 == n) with
          | some o, some e, some (_, _, fin) => fin + o ≤ e
          | _, _, _ => true
        let rows := s.plan.foldl (fun (acc : List String × List String) n =>
          let (seen, out) := acc
          let (b, e) :=
            if seen.contains n then ((late.find? (·.1 == n)).map (·.2) |>.getD (0, 0))
            else ((slots.find? (·.1 == n)).map (fun (_, b, e) => (b, e)) |>.getD (0, 0))
          (seen ++ [n], out ++ ["{\"action\":" ++ Guest.quote (splitKey n).1 ++ ",\"params\":["
            ++ String.intercalate "," (readable sp voc.names n |>.map Guest.quote) ++ "]"
            ++ field "start" (stampAt origin b) ++ field "end" (stampAt origin e)
            ++ ",\"duration\":" ++ Guest.quote (fmtDur (e - b)) ++ "}"])) ([], [])
        let steps := rows.2
        "{" ++ vsekai ++ ",\"@type\":\"domain:Plan\",\"name\":" ++ Guest.quote (pn ++ "_plan")
          ++ ",\"domain\":" ++ Guest.quote dn ++ ",\"problem\":" ++ Guest.quote pn
          ++ ",\"reached\":" ++ (if ok then "true" else "false")
          ++ ",\"temporal\":{\"consistent\":" ++ (if holds then "true" else "false") ++ field "origin" (stampAt origin 0) ++ ",\"total\":" ++ Guest.quote (fmtDur total) ++ "}"
          ++ ",\"steps\":[" ++ String.intercalate "," steps ++ "]}"

/-- The plan with the fewest actions. The decomposition backtracks over method alternatives, so planning
with a bound on the number of actions and raising the bound until a plan is found gives a plan of
the minimum length. A goal no decomposition reaches keeps its own refusal, and one that is reached only
by a plan longer than `maxBound`, or that no plan of that length reaches, is refused as `limit`. -/
def shortestOf (domain problem : String) (maxBound : Nat) : String :=
  let reaches := fun (r : String) => !(r.contains "\"refused\"") && r.contains "\"reached\":true"
  let free := planOf domain problem
  if free.contains "\"refused\"" then free
  else
    match (List.range (maxBound + 1)).find? (fun b => reaches (planOf domain problem none b)) with
    | some b => ((planOf domain problem none b).dropRight 1) ++ ",\"optimal\":true,\"length\":" ++ toString b ++ "}"
    | none => refusal (docName domain) (docName problem) "limit"

end Persona.Jsonld
