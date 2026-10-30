import Planner.Types
import Planner.BlocksWorld

namespace Persona

/-- A codebook: one level count per dimension, packed mixed-radix, the shape
residual FSQ stacks its stages in. -/
structure Codebook where
  levels : List Nat
  deriving DecidableEq, Repr

/-- Codes a stage holds: the product of the levels. -/
def Codebook.size (c : Codebook) : Nat :=
  c.levels.foldl (fun acc l => acc * l) 1

/-- The mixed-radix basis: the prefix product before each dimension. -/
def Codebook.basis (c : Codebook) : List Nat :=
  (c.levels.foldl (fun acc l => (acc.1 ++ [acc.2], acc.2 * l)) ([], 1)).1

/-- The index a code names, mixed-radix. -/
def Codebook.index (c : Codebook) (code : List Nat) : Nat :=
  (c.basis.zip code).foldl (fun acc p => acc + p.2 * p.1) 0

/-- A code is held when it carries one digit per dimension, each one in range. -/
def Codebook.holds (c : Codebook) (code : List Nat) : Bool :=
  code.length == c.levels.length && (c.levels.zip code).all (fun p => decide (p.2 < p.1))

/-- The codes a persona may name when its item is `stages` codes long. -/
def Codebook.vocabulary (c : Codebook) (stages : Nat) : Nat := c.size ^ stages

theorem held_code_has_one_digit_a_dimension (cb : Codebook) (code : List Nat)
    (h : cb.holds code = true) : code.length = cb.levels.length := by
  simp only [Codebook.holds, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1

/-- A value a persona accepts: a code of the domain's codebook, or a number. -/
inductive Value where
  | code   : List Nat → Value
  | number : Int → Value
  deriving DecidableEq, Repr

/-- One action: its name, the parameters a call binds, and what it writes. -/
structure Action where
  name   : String
  params : List String
  writes : List (StateVarID × Value)
  deriving DecidableEq, Repr

/-- What a persona knows: the state variables, the codebook, and the actions. -/
structure Domain where
  variables : List StateVar
  codebook  : Codebook
  actions   : List Action
  deriving Repr

/-- What a persona is asked: one node of the planner's own GTN space. -/
structure Goal where
  node : RECTGTNNode
  deriving DecidableEq, Repr

/-- A persona is a domain, and the answer it composes from that domain. -/
structure Persona where
  domain : Domain
  deriving Repr

/-- A code resolves through the codebook; a number is itself. -/
def Domain.resolve (d : Domain) (v : Value) : Int :=
  match v with
  | .number n => n
  | .code c   => if d.codebook.holds c then (d.codebook.index c : Int) else 0

/-- A number is always accepted; a code only when the codebook holds it. -/
def Domain.accepts (d : Domain) (v : Value) : Bool :=
  match v with
  | .number _ => true
  | .code c   => d.codebook.holds c

theorem undeclared_code_is_refused (d : Domain) (c : List Nat)
    (h : d.codebook.holds c = false) : d.accepts (.code c) = false := by
  simp [Domain.accepts, h]

/-- The plan element an action leaves in the trace. -/
def Action.element (a : Action) : PlanElement := .action a.name []

/-- An action applied to a state: every variable it writes takes its value. -/
def Action.apply (d : Domain) (a : Action) (st : GTNState) : GTNState :=
  { st with
    variables := st.variables.map fun sv =>
      match a.writes.find? (fun w => w.1 == sv.id) with
      | some w => ⟨sv.id, d.resolve w.2⟩
      | none   => sv,
    executable_trace := st.executable_trace ++ [a.element] }

/-- The state a persona starts from: the domain's declared values, and no trace. -/
def Domain.initial (d : Domain) : GTNState :=
  { variables := d.variables, executable_trace := [] }

/-- Execute a plan over a domain, in the order the persona composed it. -/
def Domain.execute (d : Domain) (plan : List PlanElement) : GTNState :=
  plan.foldl
    (fun st e =>
      match e with
      | .action name _ => (d.actions.find? (fun a => a.name == name)).map (fun a => a.apply d st) |>.getD st
      | .command _ _   => st)
    d.initial

/-- The answer: a plan, or nothing. An action already tried on this branch is
blacklisted, so the search does not repeat itself. -/
partial def Persona.answerFrom (p : Persona) (g : Goal) (blacklist : List PlanElement)
    (st : GTNState) (fuel : Nat) : Option (List PlanElement) :=
  if is_node_satisfied st g.node then
    some []
  else
    match fuel with
    | 0 => none
    | fuel + 1 =>
      (p.domain.actions.filter (fun a => !(blacklist.any fun e => decide (e = a.element)))).foldl
        (fun found a =>
          match found with
          | some plan => some plan
          | none =>
            match p.answerFrom g (blacklist ++ [a.element]) (a.apply p.domain st) fuel with
            | some rest => some (a.element :: rest)
            | none      => none)
        none

/-- Ask a persona. The fuel bounds the longest plan it composes. -/
def Persona.answer (p : Persona) (g : Goal) (fuel : Nat := 8) : Option (List PlanElement) :=
  p.answerFrom g [] p.domain.initial fuel

/-- A goal over a variable the domain does not declare is refused, not approximated. -/
theorem answer_refuses_undeclared_variable (d : Domain) (var_id : StateVarID) (thr : Int)
    (h : d.variables.find? (fun sv => sv.id == var_id) = none) :
    is_node_satisfied d.initial (.goal_geq var_id thr) = false := by
  simp [Domain.initial, is_node_satisfied, h]

end Persona
