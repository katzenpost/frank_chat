/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import FrankChat.Tests.App

/-! # Voucher codes as QR codes and by sound

The QR code against qrcodegen's, through qrcode-lean's voucher vectors; the sound glue end to end
over the loopback and noisy drivers, and against what C ggwave sends and the Rust crate hears,
through ggwave-lean's vectors; and Send by sound and Listen in the window. -/

namespace FrankChat.Tests.SoundTests

open FrankChat FrankChat.Tests FrankChat.Tests.AppTests FrankChat.Tests.Drivers FrankChat.Sound Paw
open GroupChatClient GroupChatClient.GroupChatKatzenqt1

/-- pigeonhole_reticulous's voucher vector, which the T-Deck's and hushphone's tests carry. -/
def vectorCode : String := "8so/D+D9qkFMnlXrzZVJXeAXJx8cBqVsihu/hWyubW8="
def vectorHex : String := "f2ca3f0fe0fdaa414c9e55ebcd95495de017271f1c06a56c8a1bbf856cae6d6f"

def vector : ByteArray := (Voucher.bytes? vectorCode).getD .empty

/-- What C ggwave sends in ggwave-lean's waveforms: Audible Fast, these 32 bytes, variable length. -/
def cPayload : String := "7a1f30d5ee83a4791237c8ed865b7c112acfe0855e731429c2e7b85d760b2cc1"

def waveforms : System.FilePath := ".lake/packages/ggwave/tests/vectors/waveforms"

/-- 16-bit little-endian samples. -/
def readI16 (path : System.FilePath) : IO (Array Int16) := do
  let b ← IO.FS.readBinFile path
  return (Array.range (b.size / 2)).map fun i => (b[2 * i]!.toUInt16 ||| (b[2 * i + 1]!.toUInt16 <<< 8)).toInt16

def toFloats (xs : Array Int16) : FloatArray := ⟨xs.map fun x => x.toInt.toFloat / 32768⟩

def slice (x : FloatArray) (start n : Nat) : FloatArray := ⟨x.data.extract start (start + n)⟩

def checkDigits : TestM Unit := do
  checkEq "the vector's code is its 32 bytes" vectorHex (Display.hex vector)
  checkEq "its check digits are the T-Deck's and hushphone's" "1939" (Voucher.check vector)
  check "a code that is not 32 bytes is not a voucher" (Voucher.bytes? "SGVsbG8=").isNone
  check "nor is one that is not base64" (Voucher.bytes? "not a code!").isNone
  checkEq "check digits keep their leading zeros" 4 (Voucher.check (ByteArray.mk #[0])).length

/-- `q`'s modules packed row-major, most significant bit first, as qrcode-lean's vectors give them. -/
def pack (q : Qrcode.QrCode) : ByteArray := Id.run do
  let n := q.size
  let mut out := ByteArray.mk (Array.replicate ((n * n + 7) / 8) 0)
  for i in [0:n * n] do
    if q.module (i % n) (i / n) then out := out.set! (i / 8) (out[i / 8]! ||| (0x80 >>> (i % 8).toUInt8))
  return out

def qrCode : TestM Unit := do
  -- qrcode-lean's tests/vectors/vouchers: the symbol qrcodegen, hushphone, the T-Deck and katzenqt draw.
  let code := "cvV8Q1uGC31DYm4pNGXfCg8ihJA1Pj7sYkyK/eBIP28="
  let want := "fe74f93fc10fa5106eaf5c2bb75771f5dbabd20aec17ae7107faaaaafe01f20c00be1de13e7c15c7034dee6920438063c4e1ae9245692a1e7c0e6cf8db14405579cf4ae6d3cc4c3e3d039588708848846c1a777399e5c7e68b2e06db46b23d32420bdc9b474efb805ed6c4ff8fcb6ad05f83d1fbaaa24ff5d4be5846ebc8cbd104dd7a04fed4169100"
  let some q := Voucher.qr? code | check "the voucher's QR code" false
  check "version 4 at level M, mask 2, as qrcodegen's" (q.version.val == 4 && toString q.ecc == "M" && q.mask.val == 2)
  checkEq "module for module qrcodegen's" want (Display.hex (pack q))
  let runs := Voucher.runs q
  let inRun (x y : Nat) := runs.any fun (rx, ry, n) => ry == y && rx ≤ x && x < rx + n
  check "its runs are its dark modules" ((List.range q.size).all fun y => (List.range q.size).all fun x =>
    inRun x y == q.module x y)

def sendAndHear {α : Type} [AudioOut α] [AudioIn α] (name : String) (a : α) (v : ByteArray) : TestM Unit := do
  let r ← (do send a v; listen a (pure false) 6000 : IO _).toBaseIO
  match r with
  | .ok heard => check name (heard.map (·.data) == some v.data) fun _ => s!"heard {heard.map Display.hex}"
  | .error e => check name false fun _ => toString e

/-- A microphone with nothing heard yet. -/
structure Waiting where

instance : AudioOut Waiting := ⟨fun _ _ _ => pure ()⟩
instance : AudioIn Waiting := ⟨fun _ _ _ => pure (), fun _ => pure none, fun _ => pure ()⟩

def overDrivers : TestM Unit := do
  let l ← Loopback.new
  sendAndHear "a voucher sent over the loopback is heard" l vector
  let n := (← l.air.get).size
  check "taking 3.23 s: quiet, the 2.73 s message, quiet" (n == 155072) fun _ => s!"{n} samples"
  let peak := (← l.air.get).foldl (fun p s => max p s.abs) 0
  check "at volume 25: peaks at a quarter of full scale" (peak > 0.2 && peak ≤ 0.25) fun _ => s!"{peak}"
  for (snr, seed) in [(10, 1), (0, 2)] do
    let room : Noisy := { inner := ← Loopback.new, snr, seed := ← IO.mkRef (UInt64.ofNat seed * 0x9e3779b97f4a7c15) }
    let v := ByteArray.mk ((Array.range 32).map fun i => (i * 37 + seed).toUInt8)
    sendAndHear s!"and over a noisy room at {snr} dB SNR, arriving 0.7 s in" room v
  let l ← Loopback.new
  let r ← (listen l (pure false) 1000 : IO _).toBaseIO
  check "silence is not heard, and says how loud it was"
    (match r with | .error e => toString e == "heard no voucher in 1 s (mic peak -90 dBFS)" | _ => false)
    fun _ => match r with | .error e => toString e | .ok _ => "heard something"
  let r ← (listen l (pure true) : IO _).toBaseIO
  check "a Listen stopped hears nothing" (match r with | .ok none => true | _ => false)
  check "and stops the microphone" (← l.frame.get).isNone
  let other (p : Ggwave.Protocol) (v : ByteArray) : IO (Option ByteArray) := do
    let l ← Loopback.new
    AudioOut.play l rate (← IO.ofExcept (Ggwave.encode (params rate) p volume v))
    listen l (pure false) 4000 <|> pure none
  check "only 32 bytes are taken" (← other .audibleFast (ByteArray.mk (Array.replicate 31 7))).isNone
  check "only Audible Fast is heard" (← other .audibleNormal vector).isNone
  check "a voucher that is not 32 bytes is not sent" ((clip (ByteArray.mk #[1, 2])).toOption.isNone)
  let vs ← Vouchers.over (← Loopback.new)
  vs.send vector
  check "Send and Listen on threads of their own" (((← vs.listen 1).map (·.data)) == some vector.data)
  vs.stopListen 2
  check "Stop stops a Listen not yet begun" (match ← (vs.listen 2).toBaseIO with | .ok none => true | _ => false)
  let quiet ← Vouchers.over Waiting.mk
  let t ← IO.asTask (quiet.listen 1)
  IO.sleep 100
  quiet.stopListen 1
  let got ← IO.wait t
  check "and one listening" (match got with | .ok none => true | _ => false)
    fun _ => match got with | .ok v => s!"{v.map Display.hex}" | .error e => toString e
  -- Faster than the microphone hears, or Listen falls behind it.
  let l ← Loopback.new
  AudioOut.play l rate (← noise (← IO.mkRef 7) 0.05 (rate * 10))
  let t0 ← IO.monoMsNow
  discard <| (listen l (pure false) 10000 : IO _).toBaseIO
  let ms := (← IO.monoMsNow) - t0
  IO.println s!"  10 s of noise heard in {ms} ms"
  check "Listen hears faster than the microphone" (ms < 10000)
  let r ← ((← Vouchers.over (← Loopback.new) (pure false)).listen 1).toBaseIO
  check "without the microphone, Listen asks for it"
    (match r with | .error e => toString e == "allow frank_chat the microphone, then choose Listen again" | _ => false)

/-- What C ggwave sends, as hushphone's Rust and the T-Deck send it. -/
def interop : TestM Unit := do
  -- C ggwave at 48 kHz, volume 50: the waveform hushphone's test hears with the Rust crate.
  let c ← readI16 (waveforms / "p1-var-32-48000.i16")
  let l ← Loopback.new
  AudioOut.play l rate (toFloats c)
  let heard ← (listen l (pure false) 6000 : IO _).toBaseIO
  checkEq "Listen hears C ggwave's" (some cPayload) (match heard with | .ok v => v.map Display.hex | _ => none)
  -- The same at the T-Deck's rate and frame, 24 kHz in 512, at volume 25.
  let t ← readI16 (waveforms / "p1-var-32-24000-512.i16")
  let some ear := (Ear.new 24000).toOption | check "an ear at 24 kHz" false
  let (_, got) := (List.range (t.size / 512 + 1)).foldl (fun (e, got) i =>
    if got.isSome then (e, got) else e.push (slice (toFloats t) (i * 512) 512)) (ear, none)
  checkEq "and C ggwave's at the T-Deck's 24 kHz" (some cPayload) (got.map Display.hex)
  -- What frank_chat plays is C's, sample for sample: so the Rust crate hears it as it hears C's.
  let payload := ByteArray.mk ((Array.range 32).map fun i => ((i * 37 + 32) % 256).toUInt8 ^^^ 0x5a)
  checkEq "the payload is the vectors'" cPayload (Display.hex payload)
  match clip payload rate 50 with
  | .ok x =>
    let tones := Ggwave.toI16 (slice x (rate / 5) c.size)
    check "frank_chat sends what C ggwave does, sample for sample" (tones == c)
    check "with quiet before and after" (x.size == rate / 5 + c.size + rate * 3 / 10 &&
      (slice x 0 (rate / 5)).data.all (· == 0) && (slice x (rate / 5 + c.size) (rate * 3 / 10)).data.all (· == 0))
  | .error e => check "clip" false fun _ => e

variable {sent : Sent}

def has (r : Run sent) (k : String) : Bool := (r.rt.tree.findKey? k).isSome

/-- The QR code as drawn: white with its quiet zone, a dark module a whole number of pixels square. -/
def drawn (r : Run sent) (q : Qrcode.QrCode) : TestM Unit := do
  let some n := r.rt.tree.findKey? "voucher-qr" | check "the QR code is drawn" false
  let draws := (n.render r.rt.env).items.map (·.2)
  let side := (q.size + 8) * 4
  let v := n.viewport
  check s!"{side} pixels square, 4 to a module, with a quiet zone of 4"
    (v.width == px side && v.height == px side) fun _ => s!"{v.width / px 1}×{v.height / px 1}"
  let black := draws.filterMap fun | .fill r c _ => if c == Color.black then some r else none | _ => none
  let some (.fill o _ _) := draws.head? | check "white behind" false
  check "white behind, on a whole pixel within a pixel of its box"
    (draws.head? == some (.fill o Color.white 0) && o.width == v.width && o.height == v.height &&
      o.x0 % px 1 == 0 && o.y0 % px 1 == 0 && v.x0 ≤ o.x0 && o.x0 < v.x0 + px 1 && v.y0 ≤ o.y0 && o.y0 < v.y0 + px 1)
  check "each dark module 4 whole pixels square"
    (black.all fun b => [b.x0 - o.x0, b.y0 - o.y0, b.x1 - o.x0, b.y1 - o.y0].all (· % px 4 == 0) && b.y1 - b.y0 == px 4)
  let dark (x y : Int) := black.any fun b =>
    let (cx, cy) := (o.x0 + px (4 * (x + 4) + 2), o.y0 + px (4 * (y + 4) + 2))
    b.x0 ≤ cx && cx < b.x1 && b.y0 ≤ cy && cy < b.y1
  let all := (List.range (q.size + 8)).all fun y => (List.range (q.size + 8)).all fun x =>
    dark (x - 4 : Int) (y - 4 : Int) == q.module (x - 4 : Int) (y - 4 : Int)
  check "each module as the symbol has it, the quiet zone light" all

def window : TestM Unit := do
  let sent ← IO.mkRef #[]
  air.clear
  let theirs : Chat := { name := "theirs", joining := some (.awaiting vectorCode .empty .empty .empty true) }
  let r ← state (begin sent) { me := "alice", chats := [theirs, chatWith "g" []] }
  let r ← click r "group:theirs"
  check "the voucher code is shown as a QR code beside its text" (has r "voucher-qr" && has r "voucher-code")
  if let some q := Voucher.qr? vectorCode then drawn r q
  checkEq "with Send by sound and its check digits" ["check 1939"] (textsOf r "voucher-check")
  let r ← click r "send-sound"
  check "Send by sound plays it" ((← air.air.get).size > 0 && !r.rt.model.sendingSound)
  let r ← click r "group:g"
  let r ← click r "invite"
  check "Invite offers Listen" (textsOf r "listen" == ["Listen"])
  let r ← click r "listen"
  checkEq "Listen hears it into the field" vectorCode ((r.rt.model.dialog.map (·.field)).getD "")
  checkEq "with the check digits, to compare"
    "Heard a voucher code, check 1939. If their screen shows the same, choose Invite." ("".intercalate (textsOf r "heard"))
  check "and listens no more" (r.rt.model.listening.isNone && textsOf r "listen" == ["Listen"])
  let r ← click r "accept"
  check "Invite invites the voucher heard" (match (← sent.get).back? with
    | some (.induct "g" code) => code == vectorCode
    | _ => false)
  let r ← click r "invite"
  let r ← click r "listen"
  check "nothing heard says so" ((textsOf r "heard").any (·.startsWith "Not heard: heard no voucher in 4 s"))
    fun _ => toString (textsOf r "heard")
  let r ← other r (.heard 99 (.ok (some vector)))
  checkEq "what a Listen stopped hears is dropped" "" ((r.rt.model.dialog.map (·.field)).getD "")
  let r ← other r .listen
  check "Listen of origin other does nothing" r.rt.model.listening.isNone
  let joining : Chat := { name := "short", joining := some (.awaiting "SGVsbG8=" .empty .empty .empty true) }
  let r ← state r { me := "alice", chats := [joining] }
  let r ← click r "cancel"
  let r ← click r "group:short"
  check "a code that is not a voucher has a QR code but no Send by sound" (has r "voucher-qr" && !has r "send-sound")

def tests : TestM Unit := do
  checkDigits
  qrCode
  overDrivers
  interop
  window

end FrankChat.Tests.SoundTests
