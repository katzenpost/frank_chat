import Lake
open Lake DSL System

package frank_chat where
  version := v!"0.4.2"
  description := "A desktop group chat over the Katzenpost mixnet, in Lean, on Paw and cryptlib"
  keywords := #["chat", "gui", "mixnet", "katzenpost", "privacy"]
  license := "AGPL-3.0-only"
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩]

require paw from git "https://github.com/katzenpost/paw.git" @ "v0.3.0"
require Logger from git "https://github.com/katzenpost/Logger.git" @ "51313822f6db9ff091f3b2a3e6298e1066ebea5d"
require thinclient from git "https://github.com/katzenpost/thin_client.git" @ "98ff985ad348156eccbe7d3f4c4849a47041f2d3"
require lean_unix_socket from git "https://github.com/katzenpost/lean_unix_socket.git" @ "v0.1.0"
require group_chat_client from git
  "https://github.com/katzenpost/group_chat_client.git" @ "001196f63f168f5fe82703584d934be682ea8b2f"
-- katzenpost/rustic_audio_lean#4: raw samples, for ggwave.
require rustic_audio_lean from git
  "https://github.com/katzenpost/rustic_audio_lean.git" @ "e91452fd65a05ba567766410daa735f058ad339d"
-- katzenpost/qrcode-lean#3: the decoder.
require qrcode from git "https://github.com/katzenpost/qrcode-lean.git" @ "9c1e7a6b50f2c87e464875d4a240530166fdd6e9"
-- katzenpost/ggwave-lean#1.
require ggwave from git "https://github.com/katzenpost/ggwave-lean.git" @ "86a3310e45c17e56f0179512ead7fc5b8af17f0d"
-- Last, so that its pin wins over the older ones its dependents carry.
require cryptlib from git "https://github.com/katzenpost/cryptlib.git" @ "6d8c31e81fc187f24c80257f5a96689d3ba0fc5e"

/-- The camera's drivers, `Camera.Native`: C in `c/`. Here V4L2's; Paw's Android build compiles
`c/` itself, where only the NDK's driver is not empty. -/
extern_lib frank_camera pkg := do
  let src ← inputTextFile (pkg.dir / "c" / "camera_v4l2.c")
  let o ← buildO (pkg.buildDir / "c" / "camera_v4l2.o") src
    #["-I", (← getLeanIncludeDir).toString, "-fPIC"] #["-O2", "-Wall"]
  buildStaticLib (pkg.staticLibDir / nameToStaticLib "frank_camera") #[o]

/-- A frame source and its drivers, apart from the chat, so that they could move to a repository
of their own as Rustic Audio's did. -/
lean_lib Camera

lean_lib FrankChat

@[default_target]
lean_exe frank_chat where
  root := `FrankChat.Main
  -- -s drops the symbol table and debug info, a third of the binary; frank_chat_test keeps them.
  moreLinkArgs := #["-Wl,--allow-shlib-undefined", "/usr/lib/x86_64-linux-gnu/libasound.so.2", "-Wl,-s"]

lean_exe frank_chat_test where
  root := `FrankChat.Tests.Main
  moreLinkArgs := #["-Wl,--allow-shlib-undefined", "/usr/lib/x86_64-linux-gnu/libasound.so.2"]
