/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Qrcode
import Camera
import FrankChat.Sound

/-! # Drivers for the tests

A speaker and a microphone in memory, for `FrankChat.Sound`'s glue with no sound hardware: a
loopback, which hears what was played and silence after it, and a noisy channel over it. And a
camera in memory, for `FrankChat.Scan`'s, which shows frames made up. -/

namespace FrankChat.Tests.Drivers

open FrankChat.Sound

/-- What is played is heard, at the one rate both run at, and silence after it. What was played
before listening began is heard too, so that a test can play first and listen after. -/
structure Loopback where
  rate : Nat
  air : IO.Ref FloatArray
  /-- How far the air has been heard. -/
  heard : IO.Ref Nat
  /-- The frame listened in, while listening. -/
  frame : IO.Ref (Option Nat)

instance : Nonempty Loopback :=
  ⟨⟨0, Classical.ofNonempty, Classical.ofNonempty, Classical.ofNonempty⟩⟩

def Loopback.new (rate : Nat := Sound.rate) : IO Loopback :=
  return ⟨rate, ← IO.mkRef .empty, ← IO.mkRef 0, ← IO.mkRef none⟩

/-- Forget what was played. -/
def Loopback.clear (l : Loopback) : IO Unit := do
  l.air.set .empty
  l.heard.set 0

def Loopback.atRate (l : Loopback) (r : Nat) : IO Unit :=
  unless r == l.rate do throw (IO.userError s!"the loopback runs at {l.rate} Hz, not {r}")

instance : AudioOut Loopback where
  play l r xs := do
    l.atRate r
    l.air.modify fun a => ⟨a.data ++ xs.data⟩

instance : AudioIn Loopback where
  start l r f := do
    l.atRate r
    if (← l.frame.get).isSome then throw (IO.userError "already listening")
    l.frame.set (some f)
  next l := do
    let some f ← l.frame.get | throw (IO.userError "not listening")
    let air ← l.air.get
    let at_ ← l.heard.modifyGet fun n => (n, n + f)
    let mut x := FloatArray.emptyWithCapacity f
    for i in [at_:at_ + f] do x := x.push (if h : i < air.size then air[i] else 0)
    return some x
  stop l := l.frame.set none

/-- A uniform number in (0, 1], from xorshift64. -/
def uniform (seed : IO.Ref UInt64) : IO Float := do
  let x ← seed.modifyGet fun s =>
    let s := s ^^^ (s <<< 13)
    let s := s ^^^ (s >>> 7)
    let s := s ^^^ (s <<< 17)
    (s, s)
  return ((x >>> 11).toFloat + 1) / 9007199254740992

/-- Gaussian noise of standard deviation `sd`, `n` samples, by Box-Muller. -/
def noise (seed : IO.Ref UInt64) (sd : Float) (n : Nat) : IO FloatArray := do
  let mut x := FloatArray.emptyWithCapacity n
  for _ in [0:n] do
    let (u, v) := (← uniform seed, ← uniform seed)
    x := x.push (sd * Float.sqrt (-2 * Float.log u) * Float.cos (6.283185307179586 * v))
  return x

def rms (x : FloatArray) : Float := Float.sqrt (x.foldl (fun s v => s + v * v) 0 / (max x.size 1).toFloat)

/-- A room over a loopback: what is played arrives `lead` seconds into what the microphone hears,
both under Gaussian noise `snr` dB below what was played. -/
structure Noisy where
  inner : Loopback
  snr : Float := 0
  lead : Float := 0.7
  seed : IO.Ref UInt64

instance : AudioOut Noisy where
  play n r xs := do
    let sd := rms xs * Float.pow 10 (-n.snr / 20)
    let xs : FloatArray := ⟨Array.replicate (n.lead * r.toFloat).toUInt64.toNat 0 ++ xs.data⟩
    let ns ← noise n.seed sd xs.size
    let mut out := FloatArray.emptyWithCapacity xs.size
    for i in [0:xs.size] do out := out.push (xs[i]! + ns[i]!)
    AudioOut.play n.inner r out

instance : AudioIn Noisy where
  start n := AudioIn.start n.inner
  next n := AudioIn.next n.inner
  stop n := AudioIn.stop n.inner

/-- A camera in memory: shows its frames one by one, then none; `fail` makes starting fail. -/
structure Shown where
  frames : IO.Ref (List Camera.Frame)
  log : IO.Ref (Array String)
  fail : IO.Ref (Option String)
  deriving Nonempty

def Shown.new : IO Shown := return { frames := ← IO.mkRef [], log := ← IO.mkRef #[], fail := ← IO.mkRef none }

def Shown.show (c : Shown) (fs : List Camera.Frame) : IO Unit := do
  c.frames.set fs
  c.log.set #[]
  c.fail.set none

instance : Camera.FrameSource Shown where
  start c := do
    if let some e ← c.fail.get then throw (IO.userError e)
    c.log.modify (·.push "start")
  next c ms := do
    match ← c.frames.modifyGet fun fs => (fs.head?, fs.drop 1) with
    | some f => return some f
    | none => IO.sleep (min ms 10).toUInt32; return none
  stop c := c.log.modify (·.push "stop")

/-- A `w` × `h` frame of `f x y`. -/
def frameOf (w h : Nat) (f : Nat → Nat → UInt8) : Camera.Frame :=
  ⟨w, h, ⟨Array.ofFn fun (i : Fin (w * h)) => f (i % w) (i / w)⟩, by simp [ByteArray.size]⟩

/-- `q` as a camera might see it: `scale` pixels to a module, dark 30 on light 220 give or take
`noise`, with its quiet zone of 4 modules, its top left at (`x`, `y`) of a light `w` × `h` frame. -/
def picture (q : Qrcode.QrCode) (w h scale x y : Nat) (noise : Nat := 0) : Camera.Frame :=
  frameOf w h fun px py =>
    let mx : Int := (px - x : Int) / scale - 4
    let my : Int := (py - y : Int) / scale - 4
    let dark := px ≥ x && py ≥ y && q.module mx my
    let jitter : Int := if noise == 0 then 0 else ((px * 7919 + py * 104729) * 2654435761 / 65536 % (2 * noise + 1) : Nat) - (noise : Int)
    (max 0 (min 255 ((if dark then 30 else 220) + jitter))).toNat.toUInt8

end FrankChat.Tests.Drivers
