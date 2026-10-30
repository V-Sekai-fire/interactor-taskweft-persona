import A2A
import Persona.Peer

/-- `persona_a2a` serves the persona over HTTP/1.1 (`--host`, `--port`, `--public-url`;
`A2A_BEARER_TOKEN` sets the bearer credential). `--stdio` speaks JSON-RPC on stdin and
stdout instead, and `--card [url]` prints the Agent Card. -/
def main (args : List String) : IO UInt32 :=
  if args.contains "--stdio" || args.head? == some "--card" then
    A2A.Stdio.run Persona.Peer.agent (args.filter (· != "--stdio"))
  else
    A2A.Serve.run Persona.Peer.agent args
