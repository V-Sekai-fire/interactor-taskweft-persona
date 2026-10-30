/-
Character domain — the self-test gate.

One positive and one negative control per invariant, the same shape as the
RECTGTN domain's `mcp_auth_witness` / `khr_tier1_witness`: exit 0 and print
"OK:" when every invariant holds, exit 1 on a refusal. `Float` is not
kernel-reducible, so the geometry is checked here at run time; the structural
facts are also proved in `Character.Properties`.
-/

import Character

open Character

namespace CharacterWitness

/-- `a` is within `tol` of `b`. -/
def approx (a b : Float) (tol : Float := 1.0e-4) : Bool :=
  Float.abs (a - b) < tol

def approxV (a b : Vec3) (tol : Float := 1.0e-4) : Bool :=
  approx a.x b.x tol && approx a.y b.y tol && approx a.z b.z tol

/-- The demo character: a skinned rig plus one zero-weight harness bone. -/
def demoBones : List Bone :=
  [ ⟨"root", none, 0.0⟩
  , ⟨"spine_01", some "root", 0.2⟩
  , ⟨"arm_l", some "spine_01", 0.3⟩
  , ⟨"arm_r", some "spine_01", 0.3⟩
  , ⟨"c_shoulder_l", some "spine_01", 0.1⟩ ]   -- harness: zero skin weight

def demoSkinnedBones : List Bone :=
  demoBones.filter (fun b => b.name != "c_shoulder_l")

def demoSkin : Skin :=
  { weights :=
      [ ⟨0, "root", 1.0⟩
      , ⟨1, "spine_01", 0.5⟩, ⟨1, "arm_l", 0.5⟩
      , ⟨2, "arm_l", 1.0⟩
      , ⟨3, "arm_r", 1.0⟩ ] }

def demoCharacter : Character :=
  { id := "elaina", rig := { bones := demoSkinnedBones }, skin := demoSkin }

structure Check where
  name : String
  ok : Bool

/-- Every invariant, each with its positive and negative control. -/
def checks : List Check :=
  [ { name := "cleanRig: a fully-skinned rig is clean", ok := CleanRig demoSkin demoSkinnedBones }
  , { name := "cleanRig: the harness bone makes the rig unclean", ok := !(CleanRig demoSkin demoBones) }
  , { name := "harnessBones: exactly the zero-weight bone is removed",
      ok := (HarnessBones demoSkin demoBones).map (·.name) == ["c_shoulder_l"] }
  , { name := "harnessBones: the removal set is disjoint from the skinned set",
      ok := (HarnessBones demoSkin demoBones).all (fun b => !(BoneSkinned demoSkin b.name)) }
  , { name := "weights: vertex 1 sums to 1.0", ok := approx (VertexWeightSum demoSkin 1) 1.0 }
  -- roll orientation normalization (rank-1 / shortest-arc completion)
  , { name := "rollNormalize: maps bind (1,0,0) onto rest (0,1,0)",
      ok := approxV (Quat.rotate (shortestArc ⟨1.0,0.0,0.0⟩ ⟨0.0,1.0,0.0⟩) ⟨1.0,0.0,0.0⟩) ⟨0.0,1.0,0.0⟩ }
  , { name := "rollNormalize: bind == rest is the identity (no twist introduced)",
      ok := approxV (Quat.rotate (shortestArc ⟨0.0,0.0,1.0⟩ ⟨0.0,0.0,1.0⟩) ⟨1.0,0.0,0.0⟩) ⟨1.0,0.0,0.0⟩ }
  , { name := "rollNormalize: result is a unit quaternion",
      ok := Quat.isUnit (shortestArc ⟨1.0,2.0,3.0⟩ ⟨3.0,-1.0,0.5⟩) }
  , { name := "rollNormalize: antiparallel case still maps bind onto rest",
      ok := approxV (Quat.rotate (shortestArc ⟨0.0,0.0,1.0⟩ ⟨0.0,0.0,-1.0⟩) ⟨0.0,0.0,1.0⟩) ⟨0.0,0.0,-1.0⟩ }
  -- the union with RECTGTN: a character goal is a GTN task node
  , { name := "union: cleanRig lifts to the GTN task \"char.cleanRig\"",
      ok := GTN.toGTN GTN.CharGoal.cleanRig == RECTGTNNode.task "char.cleanRig" [] }
  , { name := "union: the character is an entity in the shared space",
      ok := GTN.entityOf demoCharacter == "elaina" }
  ]

def run : IO UInt32 := do
  for c in checks do
    let tag := if c.ok then "ok  " else "FAIL"
    IO.println s!"  [{tag}] {c.name}"
  let bad := checks.filter (fun c => !c.ok)
  if bad.isEmpty then
    IO.println s!"OK: character domain — {checks.length} invariants hold (union with RECTGTN verified)"
    return 0
  else
    IO.println s!"FAIL: {bad.length} of {checks.length} invariants failed"
    return 1

end CharacterWitness

def main : IO UInt32 := CharacterWitness.run
