import Persona.Jsonld

/-! The browser entries: a RECTGTN JSON-LD domain and problem in, an answer out.
`persona_goals_text` lists what the problem asks and `persona_plan_jsonld_text` plans it,
all goals or the one the caller picked. -/

namespace Persona.Web

open Persona Jsonld

/-- The goals a problem declares, and the actions and methods its domain holds, as one JSON object.
A document that does not parse is refused by name. -/
def goalsOf (domain problem : String) : String :=
  match parse domain, parseProblem problem with
  | .error _, _ => "{\"refused\":\"bad_domain\"}"
  | _, .error _ => "{\"refused\":\"bad_problem\"}"
  | .ok sp, .ok pb =>
    let known := sp.init ++ pb.init
    let goal := fun (g : String) =>
      "{\"goal\":" ++ Guest.quote g ++ ",\"declared\":"
        ++ (if known.any (·.1 == g) then "true" else "false")
        ++ ",\"held\":" ++ (if lookup (sp.init ++ pb.init) g ≥ 1 then "true" else "false") ++ "}"
    "{\"problem\":" ++ Guest.quote pb.name ++ ",\"actions\":" ++ toString sp.acts.length
      ++ ",\"methods\":" ++ toString sp.methods.length
      ++ ",\"goals\":[" ++ String.intercalate "," (pb.goals.map goal) ++ "]}"

/-- Plan every goal of the problem, or only `goal` when it is not empty. -/
def planWith (domain problem goal : String) : String :=
  planOf domain problem (if goal == "" then none else some goal)

@[export persona_goals_text]
def goalsText (domain problem : String) : String := goalsOf domain problem

@[export persona_plan_jsonld_text]
def planJsonldText (domain problem goal : String) : String := planWith domain problem goal

end Persona.Web
