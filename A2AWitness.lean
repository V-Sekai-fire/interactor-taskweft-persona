import Persona.A2A

/-! The A2A gate: a positive and a negative control per invariant. Exit 0 and
print "OK:" when every invariant holds. -/

open Lean Persona

namespace A2AWitness

structure Check where
  name : String
  ok : Bool

def send (id : String) (text : String) (extra : String := "") : String :=
  s!"\{\"jsonrpc\":\"2.0\",\"id\":{id},\"method\":\"SendMessage\",\"params\":\{\"message\":\{\"messageId\":\"m1\",{extra}\"role\":\"ROLE_USER\",\"parts\":[\{\"text\":\"{text}\"}]}}}"

def call (method : String) : String :=
  s!"\{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"{method}\",\"params\":\{}}"

def parsed (s : String) : Json := (Json.parse s).toOption.getD Json.null

def field (j : Json) (path : List String) : Option Json :=
  path.foldl (fun acc k => acc.bind fun v => (v.getObjVal? k).toOption) (some j)

def errorCode (s : String) : Option Int :=
  (field (parsed s) ["error", "code"]).bind fun c => (c.getInt?).toOption

def replyText (s : String) : Option String :=
  match field (parsed s) ["result", "message", "parts"] with
  | some (.arr parts) => parts[0]?.bind fun p => (field p ["text"]).bind fun t => t.getStr?.toOption
  | _ => none

/-- Exactly one of result and error is present. -/
def oneOutcome (s : String) : Bool :=
  let j := parsed s
  (field j ["result"]).isSome != (field j ["error"]).isSome

def delivered : String := Persona.Guest.answerJson "delivered"
def refused : String := Persona.Guest.answerJson "teleport"

def responses : List String :=
  [ Persona.A2A.handle (send "1" "delivered"), Persona.A2A.handle (send "1" ""),
    Persona.A2A.handle "{not json", Persona.A2A.handle (call "Nope"),
    Persona.A2A.handle (call "GetTask"), Persona.A2A.handle (call "SendStreamingMessage"),
    Persona.A2A.handle "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"SendMessage\"}",
    Persona.A2A.handle (send "1" "teleport") ]

def card : Json := Persona.A2A.agentCard "http://127.0.0.1:9900"

def checks : List Check :=
  [ { name := "card: names a v1.0 JSONRPC interface at the url it was given",
      ok := (field card ["supportedInterfaces"]).any fun i => match i with
        | .arr xs => xs.any fun x =>
            (field x ["url"]) == some (Json.str "http://127.0.0.1:9900")
            && (field x ["protocolBinding"]) == some (Json.str "JSONRPC")
            && (field x ["protocolVersion"]) == some (Json.str "1.0")
        | _ => false }
  , { name := "card: declares no streaming and no push",
      ok := (field card ["capabilities", "streaming"]) == some (Json.bool false)
        && (field card ["capabilities", "pushNotifications"]) == some (Json.bool false) }
  , { name := "card: lists a skill",
      ok := match field card ["skills"] with | some (.arr xs) => !xs.isEmpty | _ => false }
  , { name := "send: the goal's reply is exactly what persona_ask answers",
      ok := replyText (Persona.A2A.handle (send "1" "delivered")) == some delivered }
  , { name := "send: that answer reaches the goal",
      ok := (delivered.splitOn "\"reached\":true").length == 2 }
  , { name := "send: an empty message asks for the domain's default goal",
      ok := replyText (Persona.A2A.handle (send "1" "")) == some delivered }
  , { name := "send: the pre-1.0 method name answers the same",
      ok := replyText (Persona.A2A.handle ((send "1" "delivered").replace "SendMessage" "message/send"))
            == some delivered }
  , { name := "send: the reply is an agent message",
      ok := field (parsed (Persona.A2A.handle (send "1" "delivered"))) ["result", "message", "role"]
            == some (Json.str "ROLE_AGENT") }
  , { name := "send: the request's number id comes back",
      ok := field (parsed (Persona.A2A.handle (send "41" "delivered"))) ["id"] == some (Json.num 41) }
  , { name := "send: the request's string id comes back",
      ok := field (parsed (Persona.A2A.handle (send "\"abc\"" "delivered"))) ["id"] == some (Json.str "abc") }
  , { name := "send: the context id comes back",
      ok := field (parsed (Persona.A2A.handle (send "1" "delivered" "\"contextId\":\"ctx-9\","))) ["result", "message", "contextId"]
            == some (Json.str "ctx-9") }
  , { name := "refusal: a goal the domain does not declare is refused by name",
      ok := (refused.splitOn "undeclared_goal").length == 2
        && replyText (Persona.A2A.handle (send "1" "teleport")) == some refused }
  , { name := "refusal: the refusal is not the plan",
      ok := refused != delivered }
  , { name := "error: malformed JSON is -32700",
      ok := errorCode (Persona.A2A.handle "{not json") == some (-32700) }
  , { name := "error: a request that is not JSON-RPC 2.0 is -32600",
      ok := errorCode (Persona.A2A.handle "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"SendMessage\"}") == some (-32600) }
  , { name := "error: an unknown method is -32601",
      ok := errorCode (Persona.A2A.handle (call "Nope")) == some (-32601) }
  , { name := "error: a message with no params is -32602",
      ok := errorCode (Persona.A2A.handle (call "SendMessage")) == some (-32602) }
  , { name := "error: a message with no text part is -32602",
      ok := errorCode (Persona.A2A.handle
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"SendMessage\",\"params\":{\"message\":{\"messageId\":\"m\",\"role\":\"ROLE_USER\",\"parts\":[{\"data\":{}}]}}}")
        == some (-32602) }
  , { name := "error: a task method is -32001, the persona holds no task",
      ok := errorCode (Persona.A2A.handle (call "GetTask")) == some (-32001)
        && errorCode (Persona.A2A.handle (call "CancelTask")) == some (-32001) }
  , { name := "error: a streaming method is -32004",
      ok := errorCode (Persona.A2A.handle (call "SendStreamingMessage")) == some (-32004) }
  , { name := "shape: every response carries exactly one of result and error",
      ok := responses.all oneOutcome }
  , { name := "shape: every response names jsonrpc 2.0",
      ok := responses.all fun r => field (parsed r) ["jsonrpc"] == some (Json.str "2.0") }
  ]

def run : IO UInt32 := do
  for c in checks do
    let tag := if c.ok then "ok  " else "FAIL"
    IO.println s!"  [{tag}] {c.name}"
  let bad := checks.filter (fun c => !c.ok)
  if bad.isEmpty then
    IO.println s!"OK: persona A2A, {checks.length} invariants hold (card, send, refusals and errors verified)"
    return 0
  else
    IO.println s!"FAIL: {bad.length} of {checks.length} invariants failed"
    return 1

end A2AWitness

def main : IO UInt32 := A2AWitness.run
