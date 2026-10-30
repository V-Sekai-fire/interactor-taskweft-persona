import Lean.Data.Json
import A2A.Protocol

/-!
# A2A over HTTP/1.1: the routes

An agent served over HTTP/1.1, and nothing else. This module is the
decision a server makes for one request, as a pure function: which route, which
status, and whether the caller may pass. It opens no socket, so the gate can
test every refusal; `A2A.Serve` puts `Std.Http` under it.

| Route | Answer |
| --- | --- |
| `GET /.well-known/agent-card.json` (and `agent.json`) | the Agent Card |
| `POST /` | the JSON-RPC answer from `A2A.handle` |

Without a bearer token the server answers only a loopback name, takes no
browser-originated request, and takes only a JSON body, so a web page on the
same machine cannot send it a task. With a token every `POST /` must carry it.
-/

namespace A2A.Http

open Lean

/-- One request, reduced to what the decision reads. Header values are raw. -/
structure Request where
  method        : String
  path          : String
  host          : Option String := none
  origin        : Option String := none
  contentType   : Option String := none
  authorization : Option String := none
  body          : String := ""

/-- One response: a status and a JSON body. -/
structure Response where
  status : Nat
  body   : String
  deriving DecidableEq

/-- What the server is configured with. `publicUrl` is advertised on the card;
`token`, when set, is the bearer credential every `POST /` must carry. -/
structure Policy where
  publicUrl : String
  token     : Option String := none

def cardPaths : List String := ["/.well-known/agent-card.json", "/.well-known/agent.json"]

/-- An error as a JSON body. -/
def failure (status : Nat) (message : String) : Response :=
  { status, body := (Json.mkObj [("error", Json.str message)]).compress }

/-- The host name of a `Host` header value, port dropped: `[::1]:9900` is `[::1]`. -/
def hostName (h : String) : String :=
  if h.startsWith "[" then
    match h.splitOn "]" with
    | first :: _ => first ++ "]"
    | []         => h
  else
    (h.splitOn ":").headD h

/-- The host of an absolute URL: `http://a.b:9900/x` is `a.b`. -/
def urlHost (url : String) : String :=
  match url.splitOn "://" with
  | [_, rest] => hostName ((rest.splitOn "/").headD rest)
  | _         => ""

/-- A loopback name: `localhost`, `127.x.x.x` or `[::1]`. -/
def isLoopbackName (name : String) : Bool :=
  let n := name.toLower
  n == "localhost" || n == "[::1]" || (n.startsWith "127." && (n.splitOn ".").length == 4)

/-- Equal strings, compared without stopping at the first difference. -/
def constantTimeEq (a b : String) : Bool :=
  let x := a.toUTF8.toList
  let y := b.toUTF8.toList
  x.length == y.length && (x.zip y).foldl (fun acc p => acc ||| (p.1 ^^^ p.2)) 0 == 0

/-- `application/json`, with or without parameters such as `; charset=utf-8`. -/
def isJson (contentType : Option String) : Bool :=
  match contentType with
  | none   => false
  | some c =>
    let mediaType := ((c.toLower.splitOn ";").headD "").trimAscii.toString
    mediaType == "application/json"

/-- A caller without a token is held to a loopback name, or the public URL's host. -/
def hostAllowed (p : Policy) (r : Request) : Bool :=
  match r.host with
  | none   => false
  | some h =>
    let name := hostName h
    isLoopbackName name || (urlHost p.publicUrl != "" && name.toLower == (urlHost p.publicUrl).toLower)

/-- Whether the credential on a `POST /` passes. With a token it must match;
without one, a browser-originated request is refused. -/
def authorized (p : Policy) (r : Request) : Bool :=
  match p.token with
  | some t => match r.authorization with
              | some a => constantTimeEq a ("Bearer " ++ t)
              | none   => false
  | none   => r.origin.isNone

/-- The decision for one request. -/
def route (agent : Agent) (p : Policy) (r : Request) : Response :=
  let known := r.path == "/" || cardPaths.contains r.path
  if !known then failure 404 "not found"
  else if p.token.isNone && !hostAllowed p r then
    failure 403 "host must be a loopback name or the public URL's host when no token is set"
  else if cardPaths.contains r.path then
    if r.method == "GET" then { status := 200, body := (agentCard agent p.publicUrl).compress }
    else failure 405 "the card is read with GET"
  else if r.method != "POST" then failure 405 "send JSON-RPC with POST"
  else if !authorized p r then
    (if p.token.isSome then failure 401 "missing or wrong bearer token"
     else failure 403 "browser-originated request refused")
  else if !isJson r.contentType then failure 415 "content-type must be application/json"
  else { status := 200, body := handle agent r.body }

end A2A.Http
