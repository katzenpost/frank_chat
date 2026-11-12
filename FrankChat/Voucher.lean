/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw
import Qrcode
import VCVio.Algorithms.Keccak
import GroupChatClient.Base64

/-! # Voucher codes

A voucher's code is its 32 bytes in base64. frank_chat shows it as text, as a QR code and, through
`FrankChat.Sound`, by sound, as hushphone, the T-Deck and katzenqt do; the QR code is the code's
text in byte mode at level M, the smallest version that holds it, with a quiet zone of 4 modules,
dark on light. -/

namespace FrankChat.Voucher

open Paw

/-- A voucher's length in bytes. -/
def size : Nat := 32

/-- The voucher a code stands for, when it is one. -/
def bytes? (code : String) : Option ByteArray :=
  (GroupChatClient.Base64.decode code).filter (·.size == size)

def code (v : ByteArray) : String := GroupChatClient.Base64.encode v

/-- The 4 digits both screens show for a voucher sent by sound, so that the two people can tell it
arrived whole: SHAKE256 of the voucher, its first 4 bytes big-endian, mod 10000, as hushphone's
`sound::check`. -/
def check (v : ByteArray) : String :=
  let n := (VCVio.Algorithms.Keccak.shake256 v 4).foldl (fun n b => n * 256 + b.toNat) 0 % 10000
  let s := toString n
  "".pushn '0' (4 - s.length) ++ s

def qr? (code : String) : Option Qrcode.QrCode :=
  (Qrcode.QrCode.encodeBytes code.toUTF8 .medium { boostEcl := false }).toOption

/-- The quiet zone around the symbol, in modules. -/
def border : Nat := 4

/-- The dark modules of `q`, a rectangle for each run of them along a row: its first module, its
row and its length. -/
def runs (q : Qrcode.QrCode) : List (Nat × Nat × Nat) := Id.run do
  let mut out := []
  for y in [0:q.size] do
    let mut x := 0
    while x < q.size do
      if q.module x y then
        let mut n := 1
        while x + n < q.size && q.module (x + n) y do n := n + 1
        out := (x, y, n) :: out
        x := x + n
      else x := x + 1
  return out.reverse

/-- `q` with its quiet zone, `scale` whole pixels to a module so that its edges fall on pixels,
black on white whatever the theme. -/
def qrWidget {Msg : Type} (q : Qrcode.QrCode) (scale : Nat) : Widget Msg :=
  let side := px ((q.size + 2 * border) * scale)
  let dark := runs q
  Widget.Spec.build (σ := NoState) {
    kind := "qr-code"
    init := {}
    sizeReq := fun _ _ => (SizeReq.fixedSize side.toNat, SizeReq.fixedSize side.toNat)
    render := fun _ _ v =>
      -- On the next whole pixel, as a layout can place the box between two; the quiet zone loses
      -- less than a pixel to the box's edge.
      let (x0, y0) := ((v.x0 + px 1 - 1) / px 1 * px 1, (v.y0 + px 1 - 1) / px 1 * px 1)
      let at_ (n : Nat) : Int := px ((n + border) * scale)
      Scene.inBox v (.fill ⟨x0, y0, x0 + side, y0 + side⟩ Color.white 0 :: dark.map fun (x, y, n) =>
        .fill ⟨x0 + at_ x, y0 + at_ y, x0 + at_ (x + n), y0 + at_ (y + 1)⟩ Color.black 0)
    render_within := fun _ _ v => Scene.inBox_within v _
    access := fun _ _ => some { role := .image, name := SafeText.trusted "voucher code as a QR code" } }

/-- A voucher code's QR code, built again only when the code changes. -/
structure Qr where
  code : String
  scale : Nat
  deriving BEq, TypeName

def qrView {Msg : Type} (q : Qr) : Node Msg :=
  match qr? q.code with
  | some s => Node.leaf (qrWidget s q.scale)
  | none => Ui.spacer

end FrankChat.Voucher
