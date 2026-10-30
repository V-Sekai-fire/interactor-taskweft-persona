/-
Character domain — core types.

Pure Lean, no Mathlib. Geometry is `Float` (runtime-checked in the witness, as
`Float` is not kernel-reducible); structural invariants are `Nat`/`List` and are
`decide`/`simp`-checked.

The domain models the character work directly: a rig (skeleton) of bones, a skin
(vertex -> bone weights), a pose (per-bone local rotation), and the roll
orientation normalization used to put a bone's rest direction onto its bind
direction without introducing twist.
-/

namespace Character

/-- A 3-vector in world space. -/
structure Vec3 where
  x : Float
  y : Float
  z : Float
  deriving Repr, Inhabited

namespace Vec3

def add (a b : Vec3) : Vec3 := ⟨a.x + b.x, a.y + b.y, a.z + b.z⟩
def sub (a b : Vec3) : Vec3 := ⟨a.x - b.x, a.y - b.y, a.z - b.z⟩
def scale (s : Float) (a : Vec3) : Vec3 := ⟨s * a.x, s * a.y, s * a.z⟩
def dot (a b : Vec3) : Float := a.x * b.x + a.y * b.y + a.z * b.z
def cross (a b : Vec3) : Vec3 :=
  ⟨a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x⟩
def norm (a : Vec3) : Float := Float.sqrt (dot a a)
def normalize (a : Vec3) : Vec3 :=
  let n := norm a
  if n == 0.0 then a else scale (1.0 / n) a

/-- A vector is (numerically) a unit vector. -/
def isUnit (a : Vec3) : Bool := Float.abs (norm a - 1.0) < 1.0e-4

end Vec3

/-- A unit quaternion (rotation). -/
structure Quat where
  w : Float
  x : Float
  y : Float
  z : Float
  deriving Repr, Inhabited

namespace Quat

def norm (q : Quat) : Float := Float.sqrt (q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z)

def normalize (q : Quat) : Quat :=
  let n := norm q
  if n == 0.0 then ⟨1.0, 0.0, 0.0, 0.0⟩
  else ⟨q.w / n, q.x / n, q.y / n, q.z / n⟩

def conj (q : Quat) : Quat := ⟨q.w, -q.x, -q.y, -q.z⟩

/-- Hamilton product. -/
def mul (a b : Quat) : Quat :=
  ⟨a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z,
   a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
   a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
   a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w⟩

/-- Rotate a vector: q v q*. -/
def rotate (q : Quat) (v : Vec3) : Vec3 :=
  let qv : Quat := ⟨0.0, v.x, v.y, v.z⟩
  let r := mul (mul q qv) (conj q)
  ⟨r.x, r.y, r.z⟩

def isUnit (q : Quat) : Bool := Float.abs (norm q - 1.0) < 1.0e-4

end Quat

/-- The identity rotation. -/
def quatId : Quat := ⟨1.0, 0.0, 0.0, 0.0⟩

/-- A 180-degree rotation about an axis perpendicular to `b`. Used only in the
    degenerate antiparallel case of `shortestArc`. -/
def perpAxis (b : Vec3) : Vec3 :=
  if Float.abs b.x < 0.9 then Vec3.normalize (Vec3.cross b ⟨1.0, 0.0, 0.0⟩)
  else Vec3.normalize (Vec3.cross b ⟨0.0, 1.0, 0.0⟩)

/-- Roll orientation normalization: the canonical minimal-twist rotation that
    maps the bind direction `bind` onto the rest direction `rest` with **zero
    roll** about the bone axis.

    This is the rank-1 / shortest-arc completion (`rs_canon_completion`): the
    rotation whose axis is perpendicular to both directions, so no twist is
    introduced. It is the completion the pose pipeline requires, and the one
    LabRCSF's shoulder DOF (flexion + abduction, no roll) forces to zero.

    The shortest-arc quaternion is `normalize ⟨1 + b·r, b × r⟩`; it needs no
    trigonometry, so the whole function is core `Float` arithmetic. -/
def shortestArc (bind rest : Vec3) : Quat :=
  let b := Vec3.normalize bind
  let r := Vec3.normalize rest
  let c := Vec3.cross b r
  let w := 1.0 + Vec3.dot b r
  if Float.abs w < 1.0e-6 then
    -- antiparallel: any 180-degree rotation about a perpendicular axis maps b to r.
    let a := perpAxis b
    ⟨0.0, a.x, a.y, a.z⟩
  else
    Quat.normalize ⟨w, c.x, c.y, c.z⟩

/-- A bone of a rig. `parent` is the parent bone's name (none for the root). -/
structure Bone where
  name : String
  parent : Option String
  length : Float
  deriving Repr, Inhabited

/-- A rig: the skeleton of a character. -/
structure Rig where
  bones : List Bone
  deriving Repr, Inhabited

/-- One vertex-to-bone skin weight. -/
structure Weight where
  vertex : Nat
  bone : String
  w : Float
  deriving Repr, Inhabited

/-- A skin: the mesh's vertex -> bone weights. -/
structure Skin where
  weights : List Weight
  deriving Repr, Inhabited

/-- A character: an entity in the shared GTN space, with its rig and skin. -/
structure Character where
  id : String
  rig : Rig
  skin : Skin
  deriving Repr, Inhabited

/-- A pose: a local rotation per bone. -/
structure Pose where
  locals : List (String × Quat)
  deriving Repr, Inhabited

/-- A bone is skinned when some vertex binds to it with positive weight. -/
def BoneSkinned (sk : Skin) (name : String) : Bool :=
  sk.weights.any (fun w => w.bone == name && w.w > 0.0)

/-- The clean-rig invariant: every bone carries skin. A controller/harness bone
    is exactly one with zero skin weight, so this predicate is the bone-removal
    criterion the USD export needs. -/
def CleanRig (sk : Skin) (bones : List Bone) : Bool :=
  bones.all (fun b => BoneSkinned sk b.name)

/-- Bones with no skin weight: the harness/controller bones to remove. -/
def HarnessBones (sk : Skin) (bones : List Bone) : List Bone :=
  bones.filter (fun b => !(BoneSkinned sk b.name))

/-- Total weight bound to one vertex. -/
def VertexWeightSum (sk : Skin) (v : Nat) : Float :=
  (sk.weights.filter (fun w => w.vertex == v)).foldl (fun acc w => acc + w.w) 0.0

end Character
