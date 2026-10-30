namespace A2A

/-- One thing an agent says it can do, as the Agent Card lists it. -/
structure Skill where
  id          : String
  name        : String
  description : String
  tags        : List String := []
  examples    : List String := []

/-- An agent a peer can talk to: what it is called, what it can do, and how it
answers. `answer` takes the text of a message and returns the text of the reply;
everything else in A2A (cards, JSON-RPC, errors, HTTP) is this library's job. -/
structure Agent where
  name        : String
  description : String
  version     : String
  skills      : List Skill
  answer      : String → String
  inputModes  : List String := ["text/plain"]
  outputModes : List String := ["application/json"]

end A2A
