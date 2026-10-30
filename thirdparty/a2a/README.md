# interactor-a2a

An [Agent2Agent (A2A) v1.0](https://a2a-protocol.org/latest/specification/)
server in Lean 4. An agent is a name, a list of skills, and a function from the
text of a message to the text of a reply. The library does the rest: the Agent
Card, JSON-RPC 2.0, the A2A error codes, and an HTTP/1.1 server with a bearer
token and a browser-origin check.

    lake build
    lake exe a2a_witness          # the gate: 46 invariants, positive and negative controls
    lake exe a2a_demo             # an echo agent on http://127.0.0.1:9900
    lake exe a2a_demo --stdio     # the same agent, one JSON-RPC request a line

## Use it

    import A2A

    def agent : A2A.Agent :=
      { name := "ask", description := "Answers a question.", version := "0.1.0"
      , skills := [{ id := "ask", name := "Ask", description := "Send a question." }]
      , answer := fun text => s!"you said: {text}" }

    def main (args : List String) : IO UInt32 := A2A.Serve.run agent args

Add it to a lakefile with `require a2a from git "https://github.com/V-Sekai-fire/interactor-a2a"`.

| Module | What it is |
| --- | --- |
| `A2A.Agent` | `Agent` and `Skill` |
| `A2A.Protocol` | `agentCard`, `handle`: JSON-RPC text in, text out. No socket, no clock. |
| `A2A.Http` | `route`: the decision for one HTTP request, as a pure function |
| `A2A.Serve` | `run`: those routes on `Std.Http`, HTTP/1.1 |
| `A2A.Stdio` | `run`: the same protocol on stdin and stdout |

## What it answers

| Request | Answer |
| --- | --- |
| `GET /.well-known/agent-card.json` (and the pre-1.0 `agent.json`) | the Agent Card |
| `POST /` with `SendMessage` (or `message/send`) | the agent's answer, as a Message |
| `GetTask`, `CancelTask` | `-32001`: the agent keeps no task |
| `SendStreamingMessage`, `SubscribeToTask` | `-32004`: nothing to stream |
| anything else | `-32601`; a malformed body is `-32700`, a message with no text part `-32602` |

An agent is stateless, so it holds no task and streams nothing. A JSON-RPC error
is still HTTP 200; the HTTP status carries only transport refusals.

## Security

HTTP/1.1 only, and no TLS in the process: put it behind something that
terminates TLS (Fly's edge, a reverse proxy, or the tailnet).

- **With `A2A_BEARER_TOKEN` set**, every `POST /` must carry `Authorization: Bearer <token>`
  (401 otherwise, compared without stopping at the first difference). The card
  stays readable so a peer can discover the agent.
- **Without a token** the server answers only a loopback `Host` (or the host of
  `--public-url`), refuses any request with an `Origin` header, and takes only
  `application/json`, so a web page on the same machine cannot send it a task or
  rebind a name to reach it.
- **A host other than loopback is refused at start** unless a token is set.
- Bodies are capped at 1 MiB.

Options: `--host` (an IPv4 address, default `127.0.0.1`), `--port` (default
`9900`), `--public-url` (what the card advertises).

## What it is not

Not a client, and not HTTP/2 or HTTP/3. Lean's `Std.Http` is HTTP/1.1, and
A2A's JSON-RPC binding needs nothing more.

## Licence

MIT.
