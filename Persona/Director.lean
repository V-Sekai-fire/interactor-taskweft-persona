import Persona

namespace Persona.Director

open Persona

/-! docs/director.md -/

def established : StateVarID := 0
def unestablished : StateVarID := 1
def lit : StateVarID := 2
def unlit : StateVarID := 3
def framed : StateVarID := 4
def held : StateVarID := 5
def cut : StateVarID := 6
def staged : StateVarID := 7

def beats : List String := ["calm", "joke", "reveal", "threat", "hit"]
def moods : List String := ["dawn", "day", "dusk", "night"]

structure Request where
  beat      : String
  mood      : String
  samePlace : Bool
  litMood   : String
  deriving Repr

def field (words : List String) (key : String) : Option String :=
  (words.filterMap fun w =>
    match w.splitOn "=" with
    | [k, v] => if k == key then some v else none
    | _ => none).head?

def parse (text : String) : Option Request :=
  let words := (text.splitOn " ").filter (· ≠ "")
  match field words "beat", field words "mood" with
  | some beat, some mood =>
    if beats.contains beat && moods.contains mood then
      some { beat := beat, mood := mood
           , samePlace := field words "place" == some "same"
           , litMood := (field words "light").getD "" }
    else none
  | _, _ => none

def act (name : String) (writes : List (StateVarID × Int)) : Action :=
  ⟨name, [], writes.map fun w => (w.1, .number w.2)⟩

def establish : Action := act "establish-wide" [(established, 1), (unestablished, 0)]
def lightFor (mood : String) : Action := act s!"light-{mood}" [(lit, 1), (unlit, 0)]
def frame (name : String) : Action := act name [(framed, 1)]
def hold (name : String) : Action := act name [(held, 1)]
def cutWith (name : String) : Action := act name [(cut, 1)]
def endBeat : Action := act "end-beat" [(staged, 1)]

def need (vars : List StateVarID) : List (StateVarID × Int) := vars.map (·, 1)

/-- The grammar of a beat: its shots in the director's order of preference, what
each shot needs before it, and what the beat needs before it ends. -/
def grammar (r : Request) : List Action × List (String × List (StateVarID × Int)) :=
  let light := lightFor r.mood
  let gates := [("establish-wide", need [unestablished]), (light.name, need [unlit])]
  match r.beat with
  | "calm" =>
    ([establish, light, frame "medium-two-shot", hold "hold-long", cutWith "dissolve", endBeat],
     gates ++ [("medium-two-shot", need [established]), ("hold-long", need [framed]),
       ("dissolve", need [held]), ("end-beat", need [established, lit, framed, held, cut])])
  | "joke" =>
    ([frame "medium-two-shot", hold "hold-beat", cutWith "smash-cut", endBeat],
     gates ++ [("hold-beat", need [framed]), ("smash-cut", need [held]),
       ("end-beat", need [framed, held, cut])])
  | "reveal" =>
    ([establish, light, frame "close-up", hold "hold-beat", cutWith "push-in-reveal", endBeat],
     gates ++ [("close-up", need [established, lit]), ("hold-beat", need [framed]),
       ("push-in-reveal", need [held]), ("end-beat", need [established, lit, framed, held, cut])])
  | "threat" =>
    ([light, frame "low-angle", hold "hold-long", cutWith "hard-cut", endBeat],
     gates ++ [("low-angle", need [lit]), ("hold-long", need [framed]), ("hard-cut", need [held]),
       ("end-beat", need [lit, framed, held, cut])])
  | _ =>
    ([frame "over-shoulder", hold "impact-frame", cutWith "reaction-close", endBeat],
     gates ++ [("impact-frame", need [framed]), ("reaction-close", need [held]),
       ("end-beat", need [framed, held, cut])])

def bit (b : Bool) : Int := if b then 1 else 0

def persona (r : Request) : Persona :=
  let (actions, requires) := grammar r
  let isLit := r.litMood == r.mood
  { domain :=
      { variables :=
          [⟨established, bit r.samePlace⟩, ⟨unestablished, bit !r.samePlace⟩,
           ⟨lit, bit isLit⟩, ⟨unlit, bit !isLit⟩,
           ⟨framed, 0⟩, ⟨held, 0⟩, ⟨cut, 0⟩, ⟨staged, 0⟩]
      , codebook := { levels := [1] }
      , actions, requires } }

def goal : Goal := { node := .goal_geq staged 1 }

def quote (s : String) : String := "\"" ++ s ++ "\""

def shotName (e : PlanElement) : String :=
  match e with
  | .action n _  => n
  | .command n _ => n

def answerJson (text : String) : String :=
  match parse text with
  | none => "{\"refused\":\"undeclared_goal\"}"
  | some r =>
    let p := persona r
    match p.answer goal 10 with
    | none => "{\"beat\":" ++ quote r.beat ++ ",\"refused\":\"unreachable\"}"
    | some plan =>
      let reached := is_node_satisfied (p.domain.execute plan) goal.node
      "{\"beat\":" ++ quote r.beat ++ ",\"mood\":" ++ quote r.mood ++ ",\"plan\":["
        ++ String.intercalate "," (plan.map (quote ∘ shotName)) ++ "],\"reached\":"
        ++ (if reached then "true" else "false") ++ "}"

@[export persona_direct_json]
def direct (request : String) : String := answerJson request

end Persona.Director
