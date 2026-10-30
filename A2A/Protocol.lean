import Lean.Data.Json
import A2A.Agent

/-!
# The protocol

A2A v1.0 (https://a2a-protocol.org/latest/specification/) over JSON-RPC 2.0, as
text in and text out. This module opens no socket and reads no clock, so every
refusal it can make is testable; `A2A.Http` and `A2A.Stdio` carry it.

An agent here is stateless: it holds no task and streams nothing. Task and
streaming methods are refused by the code A2A names for them rather than
approximated.
-/

namespace A2A

open Lean

/-- The A2A protocol version this library speaks. -/
def protocolVersion : String := "1.0"

def Skill.toJson (s : Skill) : Json :=
  Json.mkObj
    [ ("id", Json.str s.id), ("name", Json.str s.name), ("description", Json.str s.description)
    , ("tags", Json.arr (s.tags.map Json.str).toArray)
    , ("examples", Json.arr (s.examples.map Json.str).toArray) ]

/-- The Agent Card a peer reads at `/.well-known/agent-card.json`. `url` is the
address the JSON-RPC endpoint is served on. -/
def agentCard (agent : Agent) (url : String) : Json :=
  Json.mkObj
    [ ("name", Json.str agent.name)
    , ("description", Json.str agent.description)
    , ("version", Json.str agent.version)
    , ("supportedInterfaces", Json.arr #[Json.mkObj
        [ ("url", Json.str url)
        , ("protocolBinding", Json.str "JSONRPC")
        , ("protocolVersion", Json.str protocolVersion) ]])
    , ("capabilities", Json.mkObj
        [ ("streaming", Json.bool false), ("pushNotifications", Json.bool false) ])
    , ("defaultInputModes", Json.arr (agent.inputModes.map Json.str).toArray)
    , ("defaultOutputModes", Json.arr (agent.outputModes.map Json.str).toArray)
    , ("skills", Json.arr (agent.skills.map Skill.toJson).toArray) ]

/-- A JSON-RPC success. -/
def rpcResult (id : Json) (result : Json) : Json :=
  Json.mkObj [("jsonrpc", Json.str "2.0"), ("id", id), ("result", result)]

/-- A JSON-RPC error. -/
def rpcError (id : Json) (code : Int) (message : String) : Json :=
  Json.mkObj
    [ ("jsonrpc", Json.str "2.0"), ("id", id)
    , ("error", Json.mkObj [("code", Json.num (JsonNumber.fromInt code)), ("message", Json.str message)]) ]

/-- The text of a message: its text parts joined, then trimmed. A part without
text (a file, or data) adds nothing; a message with no text part at all is
invalid. -/
def requestText (message : Json) : Option String :=
  match message.getObjVal? "parts" >>= Json.getArr? with
  | .error _ => none
  | .ok parts =>
    let texts := parts.toList.filterMap fun p => (p.getObjVal? "text" >>= Json.getStr?).toOption
    if texts.isEmpty then none else some (String.intercalate "" texts).trimAscii.toString

/-- A message id the reply can carry: the request's own id, rendered plain. -/
def replyId (id : Json) : String :=
  "a2a-" ++ match id with
    | .str s => s
    | .num n => toString n
    | _      => "0"

/-- `SendMessage`: the text in, the agent's answer out as a Message. -/
def send (agent : Agent) (id : Json) (req : Json) : Json :=
  match req.getObjVal? "params" >>= (·.getObjVal? "message") with
  | .error _ => rpcError id (-32602) "Invalid params: message is required"
  | .ok msg =>
    match requestText msg with
    | none => rpcError id (-32602) "Invalid params: message has no text part"
    | some text =>
      let context : List (String × Json) :=
        match msg.getObjVal? "contextId" >>= Json.getStr? with
        | .ok c    => [("contextId", Json.str c)]
        | .error _ => []
      rpcResult id <| Json.mkObj
        [("message", Json.mkObj <|
          [ ("messageId", Json.str (replyId id))
          , ("role", Json.str "ROLE_AGENT")
          , ("parts", Json.arr #[Json.mkObj [("text", Json.str (agent.answer text))]]) ]
          ++ context)]

/-- Methods that name a task: the agent holds none. -/
def taskMethods : List String := ["GetTask", "tasks/get", "CancelTask", "tasks/cancel"]

/-- Methods that need a stream or a stored task: refused as unsupported. -/
def unsupportedMethods : List String :=
  ["SendStreamingMessage", "message/stream", "SubscribeToTask", "tasks/resubscribe"]

/-- One request, one response. -/
def dispatch (agent : Agent) (req : Json) : Json :=
  let id := (req.getObjVal? "id").toOption.getD Json.null
  match req.getObjVal? "jsonrpc" >>= Json.getStr?, req.getObjVal? "method" >>= Json.getStr? with
  | .ok "2.0", .ok m =>
    if m == "SendMessage" || m == "message/send" then send agent id req
    else if taskMethods.contains m then rpcError id (-32001) "Task not found: this agent keeps no task"
    else if unsupportedMethods.contains m then rpcError id (-32004) s!"Unsupported operation: {m}"
    else rpcError id (-32601) s!"Method not found: {m}"
  | _, _ => rpcError id (-32600) "Invalid Request"

/-- The text surface: a request body in, a response body out. -/
def handle (agent : Agent) (body : String) : String :=
  match Json.parse body with
  | .error _ => (rpcError Json.null (-32700) "Parse error").compress
  | .ok req  => (dispatch agent req).compress

end A2A
