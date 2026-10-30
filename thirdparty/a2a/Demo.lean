import A2A

/-- `a2a_demo --stdio` speaks JSON-RPC on stdio; `a2a_demo --card [url]` prints the
card; otherwise it serves HTTP/1.1. -/
def main (args : List String) : IO UInt32 :=
  if args.contains "--stdio" || args.head? == some "--card" then
    A2A.Stdio.run A2A.Echo.agent (args.filter (· != "--stdio"))
  else
    A2A.Serve.run A2A.Echo.agent args
