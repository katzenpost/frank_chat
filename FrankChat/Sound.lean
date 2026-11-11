/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Std.Sync.Mutex
import Ggwave
import RusticAudio
import FrankChat.Voucher

/-! # Voucher codes by sound

A voucher goes from the device joining to a member's by sound, as the T-Deck and hushphone send
and hear it (pigeonhole_reticulous's `docs/sound-vouchers.md`): ggwave's Audible Fast, variable
length, the voucher's 32 raw bytes, at volume 25, at 48 kHz in frames of 1024 samples.

The codec, ggwave-lean, is pure. The speaker and the microphone are drivers behind `AudioOut` and
`AudioIn`: Rustic Audio's engine here, and in the tests a loopback and a noisy channel. -/

namespace FrankChat.Sound

open Ggwave

/-- A speaker: plays mono samples in -1..1 at `rate` Hz, and returns once they have played. -/
class AudioOut (α : Type) where
  play : α → (rate : Nat) → FloatArray → IO Unit

/-- A microphone, heard mono at `rate` Hz in frames of `frame` samples. -/
class AudioIn (α : Type) where
  start : α → (rate frame : Nat) → IO Unit
  /-- The next frame heard, if one is ready. -/
  next : α → IO (Option FloatArray)
  /-- Stops listening, dropping what was heard and not read. -/
  stop : α → IO Unit

instance : AudioOut RusticAudio.Engine where
  play e rate xs := e.playSamples rate.toUInt32 xs

instance : AudioIn RusticAudio.Engine where
  start e rate frame := e.startListen rate.toUInt32 frame.toUInt32
  next e := e.readFrame
  stop e := e.stopListen

/-- ggwave's own rate and frame, whose 46.875 Hz bins the T-Deck's 24 kHz and 512 share. The
drivers resample to and from the devices' rates. -/
def rate : Nat := 48000
def frame : Nat := 1024

/-- The T-Deck's level (0-100): peaks at a quarter of full scale. -/
def volume : Nat := 25

/-- How long Listen listens, as on the T-Deck and hushphone. -/
def listenMs : Nat := 15000

/-- ggwave at 48 kHz in frames of 1024, heard or played at `fs`. -/
def params (fs : Nat) : Parameters := { sampleRateInp := fs.toFloat, sampleRateOut := fs.toFloat }

def quiet (n : Nat) : FloatArray := ⟨Array.replicate n 0⟩

/-- The voucher as the speaker plays it at `fs`: 0.2 s of quiet while it comes up, the 2.73 s
message, 0.3 s after. -/
def clip (v : ByteArray) (fs : Nat := rate) (volume : Nat := volume) : Except String FloatArray := do
  if v.size != Voucher.size then throw s!"a voucher is {Voucher.size} bytes, not {v.size}"
  let tones ← (encode (params fs) .audibleFast volume v).mapError toString
  return ⟨(quiet (fs / 5)).data ++ tones.data ++ (quiet (fs * 3 / 10)).data⟩

/-- Hears vouchers in samples at some rate: Audible Fast only, 32 bytes only. -/
structure Ear where
  s : DecoderState

def Ear.new (fs : Nat := rate) : Except String Ear :=
  (Decoder.init (params fs) [.audibleFast]).map Ear.mk |>.mapError toString

def Ear.push (e : Ear) (xs : FloatArray) : Ear × Option ByteArray :=
  let (s, v) := Decoder.step e.s xs
  (⟨s⟩, v.filter (·.size == Voucher.size))

/-- Play the voucher `v`; returns once it has played. -/
def send {α : Type} [AudioOut α] (a : α) (v : ByteArray) : IO Unit := do
  AudioOut.play a rate (← IO.ofExcept (clip v))

def dBFS (peak : Float) : Int := (20 * Float.log10 (max peak (1 / 32768))).round.toInt64.toInt

/-- Listen for a voucher until one is heard, `stop` says to stop (`none` then), or `ms` of sound
has been heard, or as long has passed with nothing heard: an error then, which says how loud the
microphone was. -/
def listen {α : Type} [AudioIn α] (a : α) (stop : IO Bool) (ms : Nat := listenMs) : IO (Option ByteArray) := do
  let mut ear ← IO.ofExcept (Ear.new rate)
  AudioIn.start a rate frame
  try
    let deadline := (← IO.monoMsNow) + ms
    let mut heard := 0
    let mut peak : Float := 0
    let most := rate * ms / 1000
    repeat
      if ← stop then return none
      match ← AudioIn.next a with
      | some x =>
        heard := heard + x.size
        peak := x.foldl (fun p s => max p s.abs) peak
        let (e, v) := ear.push x
        ear := e
        if let some v := v then return some v
        if heard ≥ most then break
      | none =>
        if (← IO.monoMsNow) ≥ deadline then break
        IO.sleep 20
    throw (IO.userError s!"heard no voucher in {ms / 1000} s (mic peak {dBFS peak} dBFS)")
  finally
    AudioIn.stop a

/-- Send and Listen over a driver, on threads of their own, as they wait on the devices. -/
structure Vouchers where
  send : ByteArray → IO Unit
  /-- Listen number `n`, which stops those before it; `none` once stopped. -/
  listen (n : Nat) : IO (Option ByteArray)
  /-- Stop Listen number `n` and those before it, whether or not it has begun. -/
  stopListen (n : Nat) : IO Unit

def dedicated {β : Type} (io : IO β) : IO β := do IO.ofExcept (← IO.wait (← IO.asTask io .dedicated))

/-- Vouchers by sound over `a`, listening only once `mic` says the microphone may be used. A
Listen waits until the one before has let the microphone go. -/
def Vouchers.over {α : Type} [AudioOut α] [AudioIn α] (a : α) (mic : IO Bool := pure true) : IO Vouchers := do
  let stopped ← IO.mkRef 0
  let mic1 ← Std.Mutex.new ()
  return {
    send := fun v => dedicated (Sound.send a v)
    listen := fun n => do
      unless ← mic do throw (IO.userError "allow frank_chat the microphone, then choose Listen again")
      stopped.modify (max · (n - 1))
      dedicated (mic1.atomically (Sound.listen a (return (← stopped.get) ≥ n)))
    stopListen := fun n => stopped.modify (max · n) }

def Vouchers.silent (why : String) : Vouchers where
  send _ := throw (IO.userError why)
  listen _ := throw (IO.userError why)
  stopListen _ := pure ()

end FrankChat.Sound
