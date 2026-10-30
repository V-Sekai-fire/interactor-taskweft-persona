import A2A
import Persona.Peer

/-! The persona's A2A gate. The protocol and the routes have their own gate in
`thirdparty/a2a` (`lake exe a2a_witness`); this one asks what is the persona's:
that a peer's message reaches the planner and the planner's answer comes back
unchanged, refusals included. -/

open Lean A2A

namespace A2AWitness

structure Check where
  name : String
  ok : Bool

def send (text : String) : String :=
  s!"\{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"SendMessage\",\"params\":\{\"message\":\{\"messageId\":\"m\",\"role\":\"ROLE_USER\",\"parts\":[\{\"text\":\"{text}\"}]}}}"

def field (j : Json) (path : List String) : Option Json :=
  path.foldl (fun acc k => acc.bind fun v => (v.getObjVal? k).toOption) (some j)

def replyText (s : String) : Option String :=
  match field ((Json.parse s).toOption.getD Json.null) ["result", "message", "parts"] with
  | some (.arr parts) => parts[0]?.bind fun p => (field p ["text"]).bind fun t => t.getStr?.toOption
  | _ => none

def ask (text : String) : Option String := replyText (handle Persona.Peer.agent (send text))

def delivered : String := Persona.Guest.answerJson "delivered"
def refused : String := Persona.Guest.answerJson "teleport"

def has (s needle : String) : Bool := (s.splitOn needle).length == 2

open A2A.Http

def policy (token : Option String) : Policy := { publicUrl := "http://127.0.0.1:9900", token }
def post (body : String) : Request :=
  { method := "POST", path := "/", host := some "127.0.0.1:9900", contentType := some "application/json", body }

def checks : List Check :=
  [ { name := "peer: a goal name reaches the planner and its answer comes back unchanged",
      ok := ask "delivered" == some delivered }
  , { name := "peer: that answer reaches the goal", ok := has delivered "\"reached\":true" }
  , { name := "peer: an empty message asks for the domain's default goal",
      ok := ask "" == some delivered }
  , { name := "peer: a goal the domain does not declare is refused by name",
      ok := ask "teleport" == some refused && has refused "undeclared_goal" }
  , { name := "peer: the refusal is not the plan", ok := refused != delivered }
  , { name := "card: names the persona, its version and a skill that shows a goal",
      ok := (field (agentCard Persona.Peer.agent "http://127.0.0.1:9900") ["name"]) == some (Json.str "persona")
        && (field (agentCard Persona.Peer.agent "http://127.0.0.1:9900") ["version"]) == some (Json.str Persona.Guest.versionText)
        && has (agentCard Persona.Peer.agent "http://127.0.0.1:9900").compress "\"examples\":[\"delivered\"]" }
  , { name := "http: with a token, the planner answers the right bearer and nobody else",
      ok := (route Persona.Peer.agent (policy (some "t")) { post (send "delivered") with authorization := some "Bearer t" }).status == 200
        && (route Persona.Peer.agent (policy (some "t")) (post (send "delivered"))).status == 401 }
  , { name := "http: the HTTP answer is the same bytes as the stdio answer",
      ok := (route Persona.Peer.agent (policy none) (post (send "delivered"))).body
            == handle Persona.Peer.agent (send "delivered") }
  ]

def run : IO UInt32 := do
  for c in checks do
    IO.println s!"  [{if c.ok then "ok  " else "FAIL"}] {c.name}"
  let bad := checks.filter (fun c => !c.ok)
  if bad.isEmpty then
    IO.println s!"OK: persona A2A, {checks.length} invariants hold (the planner's answer reaches a peer unchanged)"
    return 0
  else
    IO.println s!"FAIL: {bad.length} of {checks.length} invariants failed"
    return 1

end A2AWitness

def main : IO UInt32 := A2AWitness.run
