/-! Stand-in for qrcode-lean's decoder, with its signature, until it lands; then this goes. -/

namespace Qrcode.Decode

def decodeGray (width height : Nat) (pixels : ByteArray) : Except String ByteArray :=
  let _ := (width, height, pixels)
  .error "no QR decoder yet"

end Qrcode.Decode
