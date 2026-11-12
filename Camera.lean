/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

/-! # A camera, as a source of grayscale frames

What reads a picture, such as a QR decoder, is pure and takes a `Frame`. The camera is a driver
behind `FrameSource`, as the speaker and the microphone are behind `FrankChat.Sound`'s classes:
`Camera.Native` on V4L2 and Android, and in the tests frames made up. -/

namespace Camera

/-- A grayscale picture, `width` × `height` bytes row by row, 0 black and 255 white. -/
structure Frame where
  width : Nat
  height : Nat
  pixels : ByteArray
  size_eq : pixels.size = width * height

instance : Inhabited Frame := ⟨⟨0, 0, .empty, rfl⟩⟩

/-- The frame of these pixels, when there are `width` × `height` of them. -/
def Frame.of? (width height : Nat) (pixels : ByteArray) : Option Frame :=
  if h : pixels.size = width * height then some ⟨width, height, pixels, h⟩ else none

/-- A camera: started, read, and stopped, which lets the device go. -/
class FrameSource (α : Type) where
  start : α → IO Unit
  /-- The newest frame since the last read, waiting up to `ms` milliseconds for one. -/
  next : α → (ms : Nat) → IO (Option Frame)
  stop : α → IO Unit

end Camera
