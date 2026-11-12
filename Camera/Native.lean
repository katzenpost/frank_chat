/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Camera

/-! # The device's camera

The drivers are C in `c/`: `camera_v4l2.c` reads a V4L2 device on Linux desktop, and
`camera_android.c` the back camera through the NDK's camera API. Each gives the luma of what the
camera streams, the Android one turned upright. -/

namespace Camera.Native

opaque Handle.Pointed : NonemptyType
def Handle : Type := Handle.Pointed.type
instance : Nonempty Handle := Handle.Pointed.property

/-- Opens and starts the camera, asking for `w` × `h`: the V4L2 device `dev`, or on Android the
back camera. -/
@[extern "frank_camera_open"] opaque openRaw (dev : @& String) (w h : UInt32) : IO Handle

@[extern "frank_camera_next"]
opaque nextRaw (c : @& Handle) (ms : UInt32) : IO (Option (UInt32 × UInt32 × ByteArray))

/-- Stops the camera and lets it go. -/
@[extern "frank_camera_close"] opaque closeRaw (c : @& Handle) : IO Unit

/-- The camera, open while started. -/
structure Device where
  dev : String
  open_ : IO.Ref (Option Handle)

/-- The camera at `dev`, a V4L2 device; on Android the back camera, whatever `dev`. -/
def Device.new (dev : String := "/dev/video0") : IO Device := return { dev, open_ := ← IO.mkRef none }

/-- What it asks the camera for; a camera may give another size. -/
def width : UInt32 := 640
def height : UInt32 := 480

instance : FrameSource Device where
  start d := do
    if let some h ← d.open_.modifyGet (·, none) then closeRaw h
    d.open_.set (some (← openRaw d.dev width height))
  next d ms := do
    let some h ← d.open_.get | throw (IO.userError "the camera is not started")
    let some (w, ht, px) ← nextRaw h ms.toUInt32 | return none
    match Frame.of? w.toNat ht.toNat px with
    | some f => return some f
    | none => throw (IO.userError "the camera's driver gave a frame of the wrong size")
  stop d := do
    if let some h ← d.open_.modifyGet (·, none) then closeRaw h

end Camera.Native
