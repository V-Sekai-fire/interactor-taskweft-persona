import Lean.Data.Json
import Persona.Guest

/-!
# Agent-to-Agent

The persona as an A2A v1.0 agent (https://hermes-agent.nousresearch.com/docs/user-guide/messaging/a2a).
A peer sends a goal as the text of a message; the reply is the persona's own
answer, byte for byte what `persona_ask` returns, in one text part.

This module is the protocol and nothing else: JSON-RPC 2.0 text in, JSON-RPC
2.0 text out. It opens no socket, so a host picks the transport (`persona_a2a`
speaks it over stdio, one request a line).

The persona keeps no state, so it holds no task and streams nothing. Those
methods are refused by the code A2A names for them rather than approximated.
-/

namespace Persona.A2A

open Lean

/-- The A2A protocol version this surface speaks. -/
def protocolVersion : String := "1.0"

/-- The Agent Card a peer reads at `/.well-known/agent-card.json`. `url` is the
address the host serves the JSON-RPC endpoint on. -/
def agentCard (url : String) : Json :=
  Json.mkObj
    [ ("name", Json.str "persona")
    , ("description", Json.str
        "Answers from a planning domain, not a neural network: a goal goes in, an exact plan comes out. A goal the domain does not declare or cannot reach is refused by name.")
    , ("version", Json.str Guest.versionText)
    , ("supportedInterfaces", Json.arr #[Json.mkObj
        [ ("url", Json.str url)
        , ("protocolBinding", Json.str "JSONRPC")
        , ("protocolVersion", Json.str protocolVersion) ]])
    , ("capabilities", Json.mkObj
        [ ("streaming", Json.bool false), ("pushNotifications", Json.bool false) ])
    , ("defaultInputModes", Json.arr #[Json.str "text/plain"])
    , ("defaultOutputModes", Json.arr #[Json.str "application/json"])
    , ("skills", Json.arr #[Json.mkObj
        [ ("id", Json.str "plan")
        , ("name", Json.str "Plan to a goal")
        , ("description", Json.str
            "Send a goal name as the message text (empty means the domain's default). The reply is the plan that reaches it, or the refusal.")
        , ("tags", Json.arr #[Json.str "planning", Json.str "taskweft"])
        , ("examples", Json.arr #[Json.str "delivered"]) ]]) ]

/-- A JSON-RPC success. -/
def rpcResult (id : Json) (result : Json) : Json :=
  Json.mkObj [("jsonrpc", Json.str "2.0"), ("id", id), ("result", result)]

/-- A JSON-RPC error. -/
def rpcError (id : Json) (code : Int) (message : String) : Json :=
  Json.mkObj
    [ ("jsonrpc", Json.str "2.0"), ("id", id)
    , ("error", Json.mkObj [("code", Json.num (JsonNumber.fromInt code)), ("message", Json.str message)]) ]

/-- The goal a message names: its text parts joined, then trimmed. A part
without text (a file, or data) adds nothing; a message with no text part at all
names no goal and is invalid. -/
def requestText (message : Json) : Option String :=
  match message.getObjVal? "parts" >>= Json.getArr? with
  | .error _ => none
  | .ok parts =>
    let texts := parts.toList.filterMap fun p => (p.getObjVal? "text" >>= Json.getStr?).toOption
    if texts.isEmpty then none else some (String.intercalate "" texts).trimAscii.toString

/-- A message id the reply can carry: the request's own id, rendered plain. -/
def replyId (id : Json) : String :=
  "persona-" ++ match id with
    | .str s => s
    | .num n => toString n
    | _      => "0"

/-- `SendMessage`: the goal in, the persona's answer out as a Message. -/
def send (id : Json) (req : Json) : Json :=
  match req.getObjVal? "params" >>= (·.getObjVal? "message") with
  | .error _ => rpcError id (-32602) "Invalid params: message is required"
  | .ok msg =>
    match requestText msg with
    | none => rpcError id (-32602) "Invalid params: message has no text part"
    | some goal =>
      let context : List (String × Json) :=
        match msg.getObjVal? "contextId" >>= Json.getStr? with
        | .ok c    => [("contextId", Json.str c)]
        | .error _ => []
      rpcResult id <| Json.mkObj
        [("message", Json.mkObj <|
          [ ("messageId", Json.str (replyId id))
          , ("role", Json.str "ROLE_AGENT")
          , ("parts", Json.arr #[Json.mkObj [("text", Json.str (Guest.answerJson goal))]]) ]
          ++ context)]

/-- Methods that name a task: the persona holds none. -/
def taskMethods : List String := ["GetTask", "tasks/get", "CancelTask", "tasks/cancel"]

/-- Methods that need a stream or a stored task: refused as unsupported. -/
def unsupportedMethods : List String :=
  ["SendStreamingMessage", "message/stream", "SubscribeToTask", "tasks/resubscribe"]

/-- One request, one response. -/
def dispatch (req : Json) : Json :=
  let id := (req.getObjVal? "id").toOption.getD Json.null
  match req.getObjVal? "jsonrpc" >>= Json.getStr?, req.getObjVal? "method" >>= Json.getStr? with
  | .ok "2.0", .ok m =>
    if m == "SendMessage" || m == "message/send" then send id req
    else if taskMethods.contains m then rpcError id (-32001) "Task not found: the persona keeps no task"
    else if unsupportedMethods.contains m then rpcError id (-32004) s!"Unsupported operation: {m}"
    else rpcError id (-32601) s!"Method not found: {m}"
  | _, _ => rpcError id (-32600) "Invalid Request"

/-- The text surface: a request body in, a response body out. -/
def handle (body : String) : String :=
  match Json.parse body with
  | .error _ => (rpcError Json.null (-32700) "Parse error").compress
  | .ok req  => (dispatch req).compress

end Persona.A2A
