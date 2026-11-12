/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Std.Sync.Mutex
import Paw
import Camera
import Qrcode.Decode
import FrankChat.Sound
import FrankChat.Voucher

/-! # Voucher codes by camera

A voucher's QR code, as `FrankChat.Voucher` draws it, read by a camera. The decoder, qrcode-lean's,
is pure; the camera is a driver behind `Camera.FrameSource`, `Camera.Native` here and in the tests
frames made up. A scan reads the newest frame, shows it, and stops at the first whose QR code
holds a voucher's code. -/

namespace FrankChat.Scan

open Camera

/-- What a frame shows. -/
inductive Sight
  | nothing
  /-- A QR code that does not hold a voucher's code. -/
  | other
  | voucher (v : ByteArray)

/-- The voucher whose code the QR code in `f` holds, read by the same parser as a code pasted. -/
def sight (f : Frame) : Sight :=
  match Qrcode.Decode.decodeGray f.width f.height f.pixels with
  | .error _ => .nothing
  | .ok payload => match (String.fromUTF8? payload).bind Voucher.bytes? with
    | some v => .voucher v
    | none => .other

/-- `f` made small enough to show in `w` × `h`, each pixel the one at its corner, as RGBA. -/
def preview (f : Frame) (w h : Nat) : Nat × Nat × ByteArray := Id.run do
  let k := max 1 (max ((f.width + w - 1) / max w 1) ((f.height + h - 1) / max h 1))
  let (pw, ph) := (f.width / k, f.height / k)
  let mut out := ByteArray.emptyWithCapacity (pw * ph * 4)
  for y in [0:ph] do
    for x in [0:pw] do
      let v := f.pixels.get! (y * k * f.width + x * k)
      out := ((out.push v).push v).push v |>.push 255
  return (pw, ph, out)

/-- The largest the camera's picture is shown. -/
def previewW : Nat := 320
def previewH : Nat := 240

/-- How long a scan looks for a voucher's QR code. -/
def scanMs : Nat := 30000

/-- What a scan saw in a frame, and the frame to show; none when no frame came. -/
structure Look where
  preview : Option Paw.Image := none
  sight : Sight := .nothing

/-- Scans over a camera, each by its number, on threads of their own, as they wait on it. -/
structure Scanner where
  /-- Start scan number `n`, stopping any before it. -/
  start (n : Nat) : IO Unit
  /-- The next frame of scan `n`; an error once it has looked for `scanMs`, or was stopped. -/
  look (n : Nat) : IO Look
  /-- Stop scan `n`, if it is the one under way, and let the camera go. -/
  stop (n : Nat) : IO Unit
  deriving Inhabited

/-- Scans over `a`, starting only once `cam` says the camera may be used. -/
def Scanner.over {α : Type} [FrameSource α] (a : α) (cam : IO Bool := pure true) (ms : Nat := scanMs) :
    IO Scanner := do
  -- The scan under way, 0 for none, and when it gives up.
  let lock ← Std.Mutex.new ((0, 0) : Nat × Nat)
  return {
    start := fun n => do
      unless ← cam do throw (IO.userError "allow frank_chat the camera, then choose Scan QR code again")
      Sound.dedicated <| lock.atomically do
        if (← get).1 != 0 then
          set ((0, 0) : Nat × Nat)
          FrameSource.stop a
        FrameSource.start a
        set (n, (← IO.monoMsNow) + ms)
    look := fun n => Sound.dedicated do
      let f ← lock.atomically do
        let (now, deadline) := (← IO.monoMsNow, (← get).2)
        if (← get).1 != n then throw (IO.userError "stopped")
        if now ≥ deadline then throw (IO.userError s!"saw no voucher code in {ms / 1000} s")
        FrameSource.next a 100
      let some f := f | return {}
      let (w, h, rgba) := preview f previewW previewH
      return { preview := (← Paw.Image.ofRgba w h rgba).toOption, sight := sight f }
    stop := fun n => Sound.dedicated <| lock.atomically do
      if (← get).1 == n then
        set ((0, 0) : Nat × Nat)
        FrameSource.stop a }

def Scanner.silent (why : String) : Scanner where
  start _ := throw (IO.userError why)
  look _ := throw (IO.userError why)
  stop _ := pure ()

end FrankChat.Scan
