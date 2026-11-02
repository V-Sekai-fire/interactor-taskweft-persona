import Persona.Jsonld
import Std.Data.HashSet

/-! A shortest plan by breadth-first search. The domain's actions are searched as they are, with no
methods: a state is the value of every variable, a state seen before is not expanded again, and the
first state that holds every goal is reached by the fewest actions. -/

namespace Persona.Search

open Lean Persona Jsonld

structure Node where
  state : List Int
  plan  : List String
  deriving Inhabited

def keysOf (sp : Spec) (init : List (String × Int)) (goals : List String) : List String :=
  let ks := init.map (·.1) ++ goals ++ sp.acts.flatMap (fun a => a.sets.map (·.1))
    ++ sp.acts.flatMap (fun a => a.holds.map (·.1))
  ks.foldl (fun acc k => if acc.contains k then acc else acc ++ [k]) []

def applicable (a : Act) (edges : List (String × String × String)) (vals : List (String × Int)) : Bool :=
  a.evals.all (fun e => edges.contains e) && a.holds.all (fun h => lookup vals h.1 ≥ h.2)

def applyAct (a : Act) (vals : List (String × Int)) : List (String × Int) :=
  a.sets.foldl (fun v w => store v w.1 w.2) vals

/-- The queue is read from `head`; `fuel` bounds the states expanded. The error says whether the search ran
out of states, so the goal is unreachable, or ran out of fuel. -/
partial def bfs (sp : Spec) (keys : List String) (edges : List (String × String × String))
    (goals : List String) (queue : Array Node) (head : Nat) (seen : Std.HashSet (List Int))
    (fuel : Nat) : Except Bool (List String × Nat) :=
  if head ≥ queue.size then .error true
  else if fuel == 0 then .error false
  else
    let node := queue[head]!
    let vals := keys.zip node.state
    if goals.all (fun g => lookup vals g ≥ 1) then .ok (node.plan.reverse, head)
    else
      let (q, s) := sp.acts.foldl (fun (acc : Array Node × Std.HashSet (List Int)) a =>
        if applicable a edges vals then
          let st := keys.map (lookup (applyAct a vals))
          if acc.2.contains st then acc else (acc.1.push ⟨st, a.name :: node.plan⟩, acc.2.insert st)
        else acc) (queue, seen)
      bfs sp keys edges goals q (head + 1) s (fuel - 1)

/-- The shortest plan that makes every goal of the problem hold, or the refusal by name. `limit` bounds
the states expanded, and a search that reaches it refuses as `limit`, not as `unreachable`. -/
def shortestOf (domain problem : String) (limit : Nat) : String :=
  let dn := docName domain
  let pn := docName problem
  match parse domain, parseProblem problem with
  | .error _, _ => refusal dn pn "bad_domain"
  | _, .error _ => refusal dn pn "bad_problem"
  | .ok sp, .ok pb =>
    if pb.goals.isEmpty then refusal dn pn "no_goal"
    else
      let start := pb.init.foldl (fun v w => store v w.1 w.2) sp.init
      let keys := keysOf sp start pb.goals
      let st0 := keys.map (lookup start)
      match bfs sp keys pb.edges pb.goals #[⟨st0, []⟩] 0 ((∅ : Std.HashSet (List Int)).insert st0) limit with
      | .ok (plan, expanded) =>
        let steps := plan.map fun n => "{\"action\":" ++ Guest.quote n ++ ",\"params\":[]}"
        "{" ++ vsekai ++ ",\"@type\":\"domain:Plan\",\"name\":" ++ Guest.quote (pn ++ "_plan")
          ++ ",\"domain\":" ++ Guest.quote dn ++ ",\"problem\":" ++ Guest.quote pn
          ++ ",\"reached\":true,\"optimal\":true,\"length\":" ++ toString plan.length
          ++ ",\"expanded\":" ++ toString expanded ++ ",\"steps\":[" ++ String.intercalate "," steps ++ "]}"
      | .error true => refusal dn pn "unreachable"
      | .error false => refusal dn pn "limit"

end Persona.Search
