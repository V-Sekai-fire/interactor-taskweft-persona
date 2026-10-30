import Persona.Demo

namespace Persona.Guest

open Persona

/-- The goal a request names. A name the guest does not declare is refused
rather than approximated, which is what keeps the answer exact. -/
def goalOf (request : String) : Option Goal :=
  if request == "" || request == "delivered" then some Demo.delivered else none

/-- A JSON string holding `s`, with the two characters that could end it early
escaped. Action names are the domain's identifiers; the escape is here so a
domain that declares one anyway cannot forge the rest of the answer. -/
def quote (s : String) : String :=
  let esc (c : Char) : String :=
    if c == '"' then "\\\"" else if c == '\\' then "\\\\" else String.ofList [c]
  "\"" ++ String.join (s.toList.map esc) ++ "\""

/-- The plan as a JSON array of the action names it applies. -/
def planJson (plan : List PlanElement) : String :=
  let name (e : PlanElement) : String :=
    match e with
    | .action n _  => n
    | .command n _ => n
  "[" ++ String.intercalate "," (plan.map (fun e => quote (name e))) ++ "]"

/-- The answer: the plan that reaches the goal and whether executing it lands
there, or the refusal by name. -/
def answerJson (request : String) : String :=
  match goalOf request with
  | none => "{\"refused\":\"undeclared_goal\"}"
  | some g =>
    match Demo.persona.answer g with
    | none => "{\"goal\":\"delivered\",\"refused\":\"unreachable\"}"
    | some plan =>
      let reached := is_node_satisfied (Demo.persona.domain.execute plan) g.node
      "{\"goal\":\"delivered\",\"plan\":" ++ planJson plan
        ++ ",\"reached\":" ++ (if reached then "true" else "false") ++ "}"

/-- The version of the C-ABI surface this guest implements. -/
def versionText : String := "0.1.0"

/-- The guest entry the C shim calls: one request in, one answer out. -/
@[export persona_ask_json]
def personaAsk (request : String) : String := answerJson request

/-- The version, as a Pascal string the host reads. -/
@[export persona_version_text]
def personaVersion (_request : String) : String := versionText

end Persona.Guest
