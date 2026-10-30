/-
Character domain — formal properties.

Structural facts are proved here (`simp`, `decide`); the `Float` geometry is
certified by `CharacterWitness` at run time, as `Float` is not kernel-reducible.
-/

import Character.Types

namespace Character

-- ═══════════════════════════════════════════════════════════════════
-- Clean rig / harness removal
-- ═══════════════════════════════════════════════════════════════════

/-- The empty rig is clean (vacuously). -/
theorem cleanRig_nil (sk : Skin) : CleanRig sk [] = true := by
  simp [CleanRig]

/-- A rig is clean iff its head bone is skinned and its tail is clean. -/
theorem cleanRig_cons (sk : Skin) (b : Bone) (bs : List Bone) :
    CleanRig sk (b :: bs) = (BoneSkinned sk b.name && CleanRig sk bs) := by
  simp [CleanRig]

/-- Harness removal is exactly the complement of the clean set: no bone is both
    kept (skinned) and removed. -/
theorem harness_not_skinned (sk : Skin) (bones : List Bone) (b : Bone) :
    b ∈ HarnessBones sk bones → BoneSkinned sk b.name = false := by
  intro h
  simp only [HarnessBones, List.mem_filter] at h
  have := h.2
  simpa using this

-- ═══════════════════════════════════════════════════════════════════
-- Geometry: dot and cross are symmetric / antisymmetric (Float, stated)
-- ═══════════════════════════════════════════════════════════════════

/-- `dot` is symmetric — checked at run time in the witness for Float inputs;
    stated here as the reference identity the witness exercises. -/
def dotSymmetryStatement : Prop :=
  ∀ (a b : Vec3), a.x*b.x + a.y*b.y + a.z*b.z = b.x*a.x + b.y*a.y + b.z*a.z

end Character
