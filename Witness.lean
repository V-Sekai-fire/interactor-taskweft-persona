import A2A

/-! The gate: a positive and a negative control per invariant. Exit 0 and print
"OK:" when every invariant holds. It asks the echo agent, so the answers it
expects are the library's own and not a domain's. -/

open Lean A2A

namespace Witness

structure Check where
  name : String
  ok : Bool

def agent : Agent := Echo.agent

def send (id : String) (text : String) (extra : String := "") : String :=
  s!"\{\"jsonrpc\":\"2.0\",\"id\":{id},\"method\":\"SendMessage\",\"params\":\{\"message\":\{\"messageId\":\"m1\",{extra}\"role\":\"ROLE_USER\",\"parts\":[\{\"text\":\"{text}\"}]}}}"

def call (method : String) : String :=
  s!"\{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"{method}\",\"params\":\{}}"

def rpc (body : String) : String := handle agent body

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

def hello : String := agent.answer "hello"
def other : String := agent.answer "other"

def responses : List String :=
  [ rpc (send "1" "hello"), rpc (send "1" ""), rpc "{not json", rpc (call "Nope"),
    rpc (call "GetTask"), rpc (call "SendStreamingMessage"),
    rpc "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"SendMessage\"}" ]

def card : Json := agentCard agent "http://127.0.0.1:9900"

/-! ## The HTTP routes -/

open A2A.Http

def url : String := "http://a2a.tail1234.ts.net:9900"
def open_ : Policy := { publicUrl := url }
def locked : Policy := { publicUrl := url, token := some "s3cret" }

def post (body : String) : Request :=
  { method := "POST", path := "/", host := some "127.0.0.1:9900",
    contentType := some "application/json", body }

def getCard : Request := { method := "GET", path := "/.well-known/agent-card.json", host := some "localhost:9900" }

def withToken (r : Request) (t : String) : Request := { r with authorization := some ("Bearer " ++ t) }

def status (p : Policy) (r : Request) : Nat := (route agent p r).status

def checks : List Check :=
  [ -- card
    { name := "card: names a v1.0 JSONRPC interface at the url it was given",
      ok := (field card ["supportedInterfaces"]).any fun i => match i with
        | .arr xs => xs.any fun x =>
            (field x ["url"]) == some (Json.str "http://127.0.0.1:9900")
            && (field x ["protocolBinding"]) == some (Json.str "JSONRPC")
            && (field x ["protocolVersion"]) == some (Json.str "1.0")
        | _ => false }
  , { name := "card: declares no streaming and no push",
      ok := (field card ["capabilities", "streaming"]) == some (Json.bool false)
        && (field card ["capabilities", "pushNotifications"]) == some (Json.bool false) }
  , { name := "card: carries the agent's name, version and skills",
      ok := (field card ["name"]) == some (Json.str "echo")
        && (field card ["version"]) == some (Json.str "0.1.0")
        && (match field card ["skills"] with | some (.arr xs) => xs.size == 1 | _ => false) }
    -- send
  , { name := "send: the reply is exactly the agent's answer",
      ok := replyText (rpc (send "1" "hello")) == some hello }
  , { name := "send: a different text gets a different answer",
      ok := replyText (rpc (send "1" "other")) == some other && hello != other }
  , { name := "send: the text is trimmed before the agent sees it",
      ok := replyText (rpc (send "1" "  hello  ")) == some hello }
  , { name := "send: an empty message reaches the agent as an empty text",
      ok := replyText (rpc (send "1" "")) == some (agent.answer "") }
  , { name := "send: the pre-1.0 method name answers the same",
      ok := replyText (rpc ((send "1" "hello").replace "SendMessage" "message/send")) == some hello }
  , { name := "send: the reply is an agent message",
      ok := field (parsed (rpc (send "1" "hello"))) ["result", "message", "role"] == some (Json.str "ROLE_AGENT") }
  , { name := "send: the request's number id comes back",
      ok := field (parsed (rpc (send "41" "hello"))) ["id"] == some (Json.num 41) }
  , { name := "send: the request's string id comes back",
      ok := field (parsed (rpc (send "\"abc\"" "hello"))) ["id"] == some (Json.str "abc") }
  , { name := "send: the context id comes back",
      ok := field (parsed (rpc (send "1" "hello" "\"contextId\":\"ctx-9\","))) ["result", "message", "contextId"]
            == some (Json.str "ctx-9") }
    -- errors
  , { name := "error: malformed JSON is -32700", ok := errorCode (rpc "{not json") == some (-32700) }
  , { name := "error: a request that is not JSON-RPC 2.0 is -32600",
      ok := errorCode (rpc "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"SendMessage\"}") == some (-32600) }
  , { name := "error: an unknown method is -32601", ok := errorCode (rpc (call "Nope")) == some (-32601) }
  , { name := "error: a message with no params is -32602", ok := errorCode (rpc (call "SendMessage")) == some (-32602) }
  , { name := "error: a message with no text part is -32602",
      ok := errorCode (rpc
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"SendMessage\",\"params\":{\"message\":{\"messageId\":\"m\",\"role\":\"ROLE_USER\",\"parts\":[{\"data\":{}}]}}}")
        == some (-32602) }
  , { name := "error: a task method is -32001, the agent holds no task",
      ok := errorCode (rpc (call "GetTask")) == some (-32001) && errorCode (rpc (call "CancelTask")) == some (-32001) }
  , { name := "error: a streaming method is -32004", ok := errorCode (rpc (call "SendStreamingMessage")) == some (-32004) }
  , { name := "shape: every response carries exactly one of result and error", ok := responses.all oneOutcome }
  , { name := "shape: every response names jsonrpc 2.0",
      ok := responses.all fun r => field (parsed r) ["jsonrpc"] == some (Json.str "2.0") }
    -- helpers
  , { name := "host: the port is dropped, brackets kept",
      ok := hostName "a.b:9900" == "a.b" && hostName "[::1]:9900" == "[::1]" && hostName "a.b" == "a.b" }
  , { name := "host: loopback names are loopback, others are not",
      ok := isLoopbackName "localhost" && isLoopbackName "127.0.0.1" && isLoopbackName "[::1]"
        && !isLoopbackName "evil.example" && !isLoopbackName "127.evil.example" && !isLoopbackName "0.0.0.0" }
  , { name := "token: equal strings match, a last-character or length difference does not",
      ok := constantTimeEq "abc" "abc" && !constantTimeEq "abc" "abd" && !constantTimeEq "abc" "abcd" }
  , { name := "content type: JSON with parameters passes, other types do not",
      ok := isJson (some "application/json") && isJson (some "Application/JSON; charset=utf-8")
        && !isJson (some "text/plain") && !isJson (some "application/x-www-form-urlencoded") && !isJson none }
    -- http: routes
  , { name := "http: the card is served and equals agentCard",
      ok := (route agent open_ getCard).status == 200
        && (route agent open_ getCard).body == (agentCard agent url).compress }
  , { name := "http: the pre-1.0 card path answers the same",
      ok := (route agent open_ { getCard with path := "/.well-known/agent.json" }).body == (agentCard agent url).compress }
  , { name := "http: POST / returns exactly what handle returns",
      ok := (route agent open_ (post (send "1" "hello"))).body == rpc (send "1" "hello")
        && status open_ (post (send "1" "hello")) == 200 }
  , { name := "http: a JSON-RPC error is still HTTP 200",
      ok := status open_ (post "{not json") == 200 }
  , { name := "http: an unknown path is 404", ok := status open_ { getCard with path := "/nope" } == 404 }
  , { name := "http: GET / is 405", ok := status open_ { post "" with method := "GET" } == 405 }
  , { name := "http: POST to the card is 405", ok := status open_ { getCard with method := "POST" } == 405 }
  , { name := "http: every refusal is a JSON body naming the error",
      ok := [ route agent open_ { getCard with path := "/nope" }, route agent open_ { getCard with method := "POST" },
              route agent open_ { post "" with host := some "evil.example" } ].all fun r =>
        (field (parsed r.body) ["error"]).isSome }
    -- http: no token
  , { name := "http, no token: a loopback Host passes (name, address and bracketed v6)",
      ok := ["localhost:9900", "127.0.0.1:9900", "[::1]:9900"].all fun h =>
        status open_ { post (send "1" "hello") with host := some h } == 200 }
  , { name := "http, no token: another Host is 403",
      ok := status open_ { post (send "1" "hello") with host := some "evil.example" } == 403
        && status open_ { getCard with host := some "evil.example" } == 403 }
  , { name := "http, no token: a missing Host is 403", ok := status open_ { post (send "1" "hello") with host := none } == 403 }
  , { name := "http, no token: the public URL's host passes",
      ok := status open_ { post (send "1" "hello") with host := some "a2a.tail1234.ts.net:9900" } == 200 }
  , { name := "http, no token: a browser-originated POST is 403",
      ok := status open_ { post (send "1" "hello") with origin := some "https://evil.example" } == 403 }
  , { name := "http, no token: a form content type is 415",
      ok := status open_ { post (send "1" "hello") with contentType := some "text/plain" } == 415
        && status open_ { post (send "1" "hello") with contentType := none } == 415 }
  , { name := "http, no token: JSON with a charset passes",
      ok := status open_ { post (send "1" "hello") with contentType := some "application/json; charset=utf-8" } == 200 }
    -- http: token
  , { name := "http, token: no Authorization is 401", ok := status locked (post (send "1" "hello")) == 401 }
  , { name := "http, token: a wrong token is 401",
      ok := status locked (withToken (post (send "1" "hello")) "nope") == 401
        && status locked { post (send "1" "hello") with authorization := some "s3cret" } == 401 }
  , { name := "http, token: the right token passes", ok := status locked (withToken (post (send "1" "hello")) "s3cret") == 200 }
  , { name := "http, token: the right token passes from any Host and Origin",
      ok := status locked (withToken { post (send "1" "hello") with host := some "evil.example", origin := some "https://x" } "s3cret") == 200 }
  , { name := "http, token: a form content type is still 415",
      ok := status locked (withToken { post (send "1" "hello") with contentType := some "text/plain" } "s3cret") == 415 }
  , { name := "http, token: the card stays readable without it",
      ok := status locked { getCard with host := some "evil.example" } == 200 }
  ]

def run : IO UInt32 := do
  for c in checks do
    let tag := if c.ok then "ok  " else "FAIL"
    IO.println s!"  [{tag}] {c.name}"
  let bad := checks.filter (fun c => !c.ok)
  if bad.isEmpty then
    IO.println s!"OK: a2a, {checks.length} invariants hold (card, send, errors and HTTP routes verified)"
    return 0
  else
    IO.println s!"FAIL: {bad.length} of {checks.length} invariants failed"
    return 1

end Witness

def main : IO UInt32 := Witness.run
