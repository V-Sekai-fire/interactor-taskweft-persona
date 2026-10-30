import Persona

namespace Persona.Demo

open Persona

/-- The delivery domain: a robot at a dock, a package in storage, a delivered
flag. The three locations are codes of a four-level, two-dimension codebook. -/
def domain : Domain :=
  { variables := [⟨0, 0⟩, ⟨1, 0⟩, ⟨2, 0⟩]
  , codebook := { levels := [4, 4] }
  , actions :=
      [ ⟨"recharge", ["agent"], [(0, .code [0, 0])]⟩
      , ⟨"move_to_storage", ["agent"], [(0, .code [1, 0])]⟩
      , ⟨"pickup", ["agent", "pkg"], [(1, .number 1)]⟩
      , ⟨"move_to_shipping", ["agent"], [(0, .code [2, 0])]⟩
      , ⟨"dropoff", ["agent", "pkg"], [(2, .number 1), (1, .number 0)]⟩ ] }

def persona : Persona := { domain := domain }

def delivered : Goal := { node := .goal_geq 2 1 }

def value (v : Value) : String :=
  match v with
  | .code c   => s!"code {c}"
  | .number n => s!"number {n}"

end Persona.Demo
