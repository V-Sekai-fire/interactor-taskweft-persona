import A2A.Agent
import Lean.Data.Json

/-!
# An echo agent

Replies with what it was sent, as JSON. It runs the library end to end and gives
the gate something to ask; a real agent is an `A2A.Agent` whose `answer` does
the work.
-/

namespace A2A.Echo

open Lean

def agent : Agent :=
  { name := "echo"
  , description := "Replies with the text it was sent, as JSON."
  , version := "0.1.0"
  , skills := [{ id := "echo", name := "Echo", description := "Send any text; the reply carries it back.",
                 tags := ["demo"], examples := ["hello"] }]
  , answer := fun text => (Json.mkObj [("echo", Json.str text)]).compress }

end A2A.Echo
