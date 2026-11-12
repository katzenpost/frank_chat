/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import FrankChat.Tests.Sound
import Camera.Native

/-! # Voucher codes by camera

The decode path end to end, from the QR code one frank_chat draws to the voucher another reads;
the scan glue over a camera in memory; and Scan QR code in the Invite dialog. -/

namespace FrankChat.Tests.ScanTests

open FrankChat FrankChat.Tests FrankChat.Tests.AppTests FrankChat.Tests.Drivers FrankChat.Tests.SoundTests Paw
open GroupChatClient GroupChatClient.GroupChatKatzenqt1

def blank : Camera.Frame := frameOf 640 480 fun _ _ => 200

def isVoucher (v : ByteArray) : Scan.Sight → Bool
  | .voucher w => w.data == v.data
  | _ => false

def isNothing : Scan.Sight → Bool
  | .nothing => true
  | _ => false

def isOther : Scan.Sight → Bool
  | .other => true
  | _ => false

def errorOf {α : Type} (io : IO α) : IO String := do
  match ← io.toBaseIO with
  | .ok _ => return ""
  | .error e => return toString e

/-- The QR code one frank_chat shows, read from frames as another's camera gives them. -/
def decode : TestM Unit := do
  let some q := Voucher.qr? vectorCode | check "the vector has a QR code" false
  check "a voucher's QR code as frank_chat draws it, 4 pixels a module, is read"
    (isVoucher vector (Scan.sight (picture q 640 480 4 100 60)))
  check "and smaller, off center and noisy"
    (isVoucher vector (Scan.sight (picture q 640 480 3 300 220 (noise := 40))))
  check "a frame with no QR code shows nothing" (isNothing (Scan.sight blank))
  let some o := Voucher.qr? "SGVsbG8=" | check "a short code has a QR code" false
  check "a QR code of what is not a voucher's code is no voucher" (isOther (Scan.sight (picture o 640 480 4 100 60)))
  let (w, h, rgba) := Scan.preview (picture q 640 480 4 0 0) Scan.previewW Scan.previewH
  check "a frame is shown halved, to fit" (w == 320 && h == 240 && rgba.size == 320 * 240 * 4)
  check "gray and opaque" (rgba[0]! == rgba[1]! && rgba[1]! == rgba[2]! && rgba[3]! == 255 && rgba[0]! == 220)

/-- Looks of scan `n` until one fails, at most `k`. -/
def lookUntilError (s : Scan.Scanner) (n : Nat) : Nat → IO String
  | 0 => return ""
  | k + 1 => do
    match ← (s.look n).toBaseIO with
    | .ok _ => lookUntilError s n k
    | .error e => return toString e

def glue : TestM Unit := do
  let some q := Voucher.qr? vectorCode | check "the vector has a QR code" false
  let cam ← Shown.new
  let s ← Scan.Scanner.over cam (ms := 1000)
  cam.show [blank, picture q 640 480 4 100 60]
  s.start 1
  let l ← s.look 1
  check "each frame is shown as it comes" (l.preview.isSome && isNothing l.sight)
  check "until one holds a voucher" (isVoucher vector (← s.look 1).sight)
  checkEq "another scan's look is refused" "stopped" (← errorOf (s.look 2))
  s.stop 2
  checkEq "and its Stop leaves the camera on" #["start"] (← cam.log.get)
  s.stop 1
  checkEq "Stop lets the camera go" #["start", "stop"] (← cam.log.get)
  checkEq "and looks no more" "stopped" (← errorOf (s.look 1))
  cam.show []
  s.start 3
  s.start 4
  checkEq "a scan started stops the one before" #["start", "stop", "start"] (← cam.log.get)
  checkEq "with nothing seen, a scan gives up" "saw no voucher code in 1 s" (← lookUntilError s 4 1000)
  s.stop 4
  let denied ← Scan.Scanner.over cam (pure false)
  cam.show []
  checkEq "without the camera allowed, it says so"
    "allow frank_chat the camera, then choose Scan QR code again" (← errorOf (denied.start 1))
  checkEq "and does not start it" #[] (← cam.log.get)
  cam.fail.set (some "/dev/video0: No such file or directory")
  checkEq "with no camera, the driver's reason" "/dev/video0: No such file or directory" (← errorOf (s.start 5))

variable {sent : Sent}

/-- A click whose tasks are left to run: `click` runs them all. -/
def tap (r : Run sent) (k : String) : IO (Run sent) := do
  let p := at_ r k
  let now := r.now + 600
  let (rt, o1) := r.rt.step (.input { kind := .press p .primary, time := now }) now
  let now := now + 50
  let (rt, o2) := rt.step (.input { kind := .release p .primary, time := now }) now
  return { rt, outs := r.outs ++ o1 ++ o2, now }

/-- Run the tasks waiting, once, and not those they start. -/
def once (r : Run sent) (reverse : Bool := false) : IO (Run sent) := do
  let tasks := r.outs.filterMap fun | .task io => some io | _ => none
  let mut r := { r with outs := r.outs.filter fun | .task _ => false | _ => true }
  for io in if reverse then tasks.reverse else tasks do
    let (rt, o) := r.rt.taskResult (← io) r.now
    r := { r with rt, outs := r.outs ++ o }
  return r

def seenOf (r : Run sent) : String := "".intercalate (textsOf r "seen")

def window : TestM Unit := do
  let sent ← IO.mkRef #[]
  let some q := Voucher.qr? vectorCode | check "the vector has a QR code" false
  let some o := Voucher.qr? "SGVsbG8=" | check "a short code has a QR code" false
  let r ← state (begin sent) { me := "alice", chats := [chatWith "g" []] }
  let r ← click r "invite"
  checkEq "Invite offers Scan QR code" ["Scan QR code"] (textsOf r "scan-qr")
  shown.show [blank, picture o 640 480 4 100 60, picture q 640 480 4 100 60]
  let r ← click r "scan-qr"
  checkEq "Scan QR code reads it into the field" vectorCode ((r.rt.model.dialog.map (·.field)).getD "")
  checkEq "with the check digits, to compare"
    "Scanned a voucher code, check 1939. If their screen shows the same, choose Invite." (seenOf r)
  check "and lets the camera go" (r.rt.model.scanning.isNone && !has r "scan-preview" &&
    textsOf r "scan-qr" == ["Scan QR code"]) fun _ => toString (textsOf r "scan-qr")
  checkEq "once" #["start", "stop"] (← shown.log.get)
  let r ← click r "accept"
  check "Invite invites the voucher scanned, as one pasted" (match (← sent.get).back? with
    | some (.induct "g" code) => code == vectorCode
    | _ => false)
  let r ← click r "invite"
  shown.show [blank]
  let r ← tap r "scan-qr"
  checkEq "the camera starting says so" "Starting the camera…" (seenOf r)
  let r ← once (← once r)
  check "while it scans, what the camera sees is shown, and Stop"
    (has r "scan-preview" && textsOf r "scan-qr" == ["Stop"] && seenOf r == "Hold their QR code up to the camera.")
    fun _ => s!"{textsOf r "scan-qr"} {seenOf r}"
  let r ← click r "scan-qr"
  check "Stop stops it" (r.rt.model.scanning.isNone && !has r "scan-preview" && seenOf r == "" &&
    (← shown.log.get) == #["start", "stop"])
  shown.show []
  let r ← click r "scan-qr"
  check "nothing seen says so" ((seenOf r).startsWith "Not scanned: saw no voucher code in 1 s") fun _ => seenOf r
  checkEq "and the camera is let go" #["start", "stop"] (← shown.log.get)
  shown.fail.set (some "/dev/video0: No such file or directory")
  let r ← click r "scan-qr"
  checkEq "no camera says why, and offers the others"
    "Not scanned: /dev/video0: No such file or directory. Paste the code, or choose Listen." (seenOf r)
  check "which still work" (textsOf r "listen" == ["Listen"] && r.rt.model.scanning.isNone)
  let r ← click r "dialog-field"
  let r ← typeText r vectorCode
  checkEq "pasting still does" vectorCode ((r.rt.model.dialog.map (·.field)).getD "")
  let r ← click r "cancel"
  let r ← click r "invite"
  shown.show [blank]
  let r ← once (← once (← tap r "scan-qr"))
  let r ← click r "cancel"
  check "Cancel stops the scan" (r.rt.model.scanning.isNone && r.rt.model.dialog.isNone &&
    (← shown.log.get) == #["start", "stop"])
  let r ← click r "invite"
  shown.show [blank]
  let r ← tap r "scan-qr"
  let r ← tap r "cancel"
  -- The Stop runs before the start it stops: the start, once done, is stopped again.
  let r ← settle (← once r (reverse := true))
  checkEq "a scan cancelled as it starts lets the camera go" #["start", "stop"] (← shown.log.get)
  let r ← click r "invite"
  let r ← other r .scanQr
  check "Scan QR code of origin other does nothing" r.rt.model.scanning.isNone
  let r ← other r (.looked 99 (.ok { sight := .voucher vector }))
  checkEq "what a scan stopped sees is dropped" "" ((r.rt.model.dialog.map (·.field)).getD "")

/-- A scan of the camera `dev` as frank_chat runs it, for trying a camera by hand: what it saw. -/
def camera (dev : String) : IO UInt32 := do
  let s ← Scan.Scanner.over (← Camera.Native.Device.new dev) (ms := 20000)
  let frames ← IO.mkRef 0
  try
    s.start 1
    repeat
      let l ← s.look 1
      if let some img := l.preview then
        if (← frames.modifyGet fun n => (n + 1, n + 1)) == 1 then IO.println s!"first frame, shown {img.w}×{img.h}"
      match l.sight with
      | .voucher v =>
        IO.println s!"read a voucher code after {← frames.get} frames: {Voucher.code v}, check {Voucher.check v}"
        return 0
      | .other => IO.println "a QR code that holds no voucher code"
      | .nothing => pure ()
    return 1
  catch e =>
    IO.println s!"{e}, after {← frames.get} frames"
    return 1
  finally s.stop 1

def tests : TestM Unit := do
  decode
  glue
  window

end FrankChat.Tests.ScanTests
