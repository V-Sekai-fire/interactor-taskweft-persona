import A2A.Agent
import Persona.Guest

/-!
# The persona as an A2A agent

The protocol, the routes and the servers are `thirdparty/a2a`. What is the
persona's is the card and the answer: a goal name goes in as the message text,
and the reply is exactly what `persona_ask` returns.
-/

namespace Persona.Peer

def agent : A2A.Agent :=
  { name := "persona"
  , description :=
      "Answers from a planning domain, not a neural network: a goal goes in, an exact plan comes out. A goal the domain does not declare or cannot reach is refused by name."
  , version := Persona.Guest.versionText
  , skills := [{ id := "plan", name := "Plan to a goal"
               , description :=
                   "Send a goal name as the message text (empty means the domain's default). The reply is the plan that reaches it, or the refusal."
               , tags := ["planning", "taskweft"], examples := ["delivered"] }]
  , answer := Persona.Guest.answerJson }

end Persona.Peer
