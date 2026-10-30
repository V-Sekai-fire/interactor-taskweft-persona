import A2A.Protocol

/-!
# A2A over stdio

One JSON-RPC request a line in, one response a line out, until the input ends.
`--card [url]` prints the Agent Card instead.
-/

namespace A2A.Stdio

partial def loop (agent : Agent) (stdin stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let body := line.trimAscii.toString
  if !body.isEmpty then
    stdout.putStrLn (handle agent body)
    stdout.flush
  loop agent stdin stdout

def run (agent : Agent) (args : List String) : IO UInt32 := do
  match args with
  | "--card" :: rest =>
    IO.println (agentCard agent (rest.headD "http://127.0.0.1:9900")).compress
    return 0
  | _ =>
    loop agent (← IO.getStdin) (← IO.getStdout)
    return 0

end A2A.Stdio
