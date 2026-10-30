import Std.Http
import A2A.Http

/-!
# A2A over HTTP/1.1, on `Std.Http`

HTTP/1.1 only: no TLS, no HTTP/2, no HTTP/3. A peer on another machine reaches
the server through the tailnet or a reverse proxy that terminates TLS.

    --host 127.0.0.1   an IPv4 address to bind (default loopback)
    --port 9900
    --public-url URL   what the Agent Card advertises

`A2A_BEARER_TOKEN` in the environment sets the bearer credential. A host other
than loopback is refused without one.
-/

namespace A2A.Serve

open Std Http Async
open A2A.Http

/-- `a.b.c.d` as an IPv4 address. -/
def parseIPv4 (s : String) : Option Net.IPv4Addr :=
  match (s.splitOn ".").map String.toNat? with
  | [some a, some b, some c, some d] =>
    if a < 256 && b < 256 && c < 256 && d < 256 then
      some (Net.IPv4Addr.ofParts a.toUInt8 b.toUInt8 c.toUInt8 d.toUInt8)
    else none
  | _ => none

def methodName : Method → String
  | .get  => "GET"
  | .post => "POST"
  | _     => "OTHER"

def statusOf : Nat → Status
  | 200 => .ok
  | 401 => .unauthorized
  | 403 => .forbidden
  | 404 => .notFound
  | 405 => .methodNotAllowed
  | 415 => .unsupportedMediaType
  | _   => .internalServerError

/-- The request, reduced to what the routes read. -/
def toRequest (req : Std.Http.Request Body.Stream) (body : String) : A2A.Http.Request :=
  let header (n : Header.Name) : Option String := (req.line.headers.get? n).map (·.value)
  { method := methodName req.line.method
  , path := match req.line.uri with
      | .originForm p _ => toString p
      | _               => ""
  , host := header Header.Name.host
  , origin := header Header.Name.origin
  , contentType := header Header.Name.contentType
  , authorization := header Header.Name.authorization
  , body }

/-- One handler: read the body only for the route that takes one, then decide. -/
def handler (agent : Agent) (policy : Policy) : Server.StatelessHandler where
  onRequest req := do
    let body : String ←
      if req.line.method == .post then req.body.readAll (maximumSize := some 1048576) else pure ""
    let out := route agent policy (toRequest req body)
    let response ← (Std.Http.Response.withStatus (statusOf out.status)).json out.body
    return response

/-- The value after `--flag`. -/
def option (args : List String) (flag : String) : Option String :=
  match args.dropWhile (· != flag) with
  | _ :: v :: _ => some v
  | _           => none

/-- Serve `agent` until the process is stopped. -/
def run (agent : Agent) (args : List String) : IO UInt32 := do
  let host := (option args "--host").getD "127.0.0.1"
  let port := ((option args "--port").bind String.toNat?).getD 9900
  let token := (← IO.getEnv "A2A_BEARER_TOKEN").filter (!·.isEmpty)
  let some ip := parseIPv4 host
    | IO.eprintln s!"a2a: --host must be an IPv4 address, got '{host}'"; return 2
  if token.isNone && !isLoopbackName host then
    IO.eprintln "a2a: a host other than loopback needs A2A_BEARER_TOKEN"
    return 2
  let publicUrl := (option args "--public-url").getD s!"http://{host}:{port}"
  let policy : Policy := { publicUrl, token }
  IO.println s!"a2a: {agent.name} on http://{host}:{port} (HTTP/1.1, token {if token.isSome then "required" else "none"})"
  (← IO.getStdout).flush
  Async.block do
    let server ← Std.Http.Server.serve (.v4 ⟨ip, port.toUInt16⟩) (handler agent policy)
      { maxBodySize := 1048576 }
    server.waitShutdown
  return 0

end A2A.Serve
