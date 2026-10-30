import Persona.A2A

/-! The persona over stdio: one JSON-RPC request a line in, one response a line
out, until the input ends. `--card [url]` prints the Agent Card instead. -/

partial def serve (stdin stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return
  let body := line.trimAscii.toString
  if !body.isEmpty then
    stdout.putStrLn (Persona.A2A.handle body)
    stdout.flush
  serve stdin stdout

def main (args : List String) : IO UInt32 := do
  match args with
  | "--card" :: rest =>
    let url := rest.headD "http://127.0.0.1:9900"
    IO.println (Persona.A2A.agentCard url).compress
    return 0
  | _ =>
    serve (← IO.getStdin) (← IO.getStdout)
    return 0
