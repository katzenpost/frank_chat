# Building frank_chat

frank_chat is Lean, with small Rust libraries underneath it: Paw's, for the window, one for the
daemon's unix socket, [lean_os](https://github.com/katzenpost/lean_os), for saving the state to
the disk whole, and [rustic_audio_lean](https://github.com/katzenpost/rustic_audio_lean), for
voice notes. You need:

- **Lean**, through [elan](https://github.com/leanprover/elan), which installs the toolchain
  named in `lean-toolchain` by itself.
- **Rust**, through [rustup](https://rustup.rs). Lake runs `cargo` itself while building, so
  `cargo` only has to be on the `PATH`.
- On Debian or Ubuntu, `libxkbcommon-x11-0` to open a window on X11, and `libasound2-dev` and
  `pkg-config` for sound.
- **git**, and about 8 GB of disk.

Then:

    git clone https://github.com/katzenpost/frank_chat
    cd frank_chat
    make build

`make build` runs `lake exe cache get`, which fetches the dependencies and Mathlib's compiled
files (several GB, which Cryptlib needs), then `lake build frank_chat`. The program is
`.lake/build/bin/frank_chat`.

## Verifying a release

The binaries on the [releases](https://github.com/katzenpost/frank_chat/releases) page are
reproducible: the same tag built anywhere with the toolchains it pins gives the same bytes. Each
release is built twice, on two runner images, and published only if both agree. To check one
yourself, with what the section above lists and Rust 1.99.0 (`rustup toolchain install 1.99.0`):

    git clone https://github.com/katzenpost/frank_chat
    cd frank_chat
    git checkout v0.4.1
    FROM_SOURCE=1 make release
    curl -fsSL https://github.com/katzenpost/frank_chat/releases/download/v0.4.1/SHA256SUMS | grep linux | diff - dist/SHA256SUMS

No output from `diff` means your build and the release match. `FROM_SOURCE=1` skips
`lake exe cache get` and builds Mathlib too, so nothing you run was compiled by someone else; it
takes a few hours. Without it, `make release` is quicker and trusts
Mathlib's downloaded files. Either way, `gh attestation verify frank_chat-v0.4.1-x86_64-linux --repo
katzenpost/frank_chat` checks that a downloaded binary was built by this repository's release workflow.

The APK is reproducible before it is signed: `make release-apk`, with what [Android](#android)
needs and the NDK, build-tools and `android.jar` the release workflow pins, builds it unsigned, and
its hash is the one in the release's `UNSIGNED-SHA256SUMS`. The release workflow signs it with
frank_chat's key, whose certificate has the SHA-256 fingerprint

    06a3810adabecdaa8eafb6d965b9a8ba41df3c9cded125d9ca9c49e7d647e1f8

as the "certificate SHA-256 digest" `apksigner verify --print-certs` shows for a downloaded APK.

## Android

<img src="android.png" width="320" alt="frank_chat on an Android phone: a conversation in a group of three, with the message box and the Send button below it">

Each release has an APK for phones, `frank_chat-<version>-arm64.apk`, which `adb install -r`
installs, or the phone itself once it is downloaded there. Every release is signed with the same
key, so one installs over the last and keeps your groups.

`make apk` builds frank_chat for Android phones as `.lake/android/frank_chat-arm64-v8a.apk`, and
`make apk ANDROID_ABI=x86_64` for the emulator, with
[Paw's Android build](https://github.com/katzenpost/paw#android), which lists what it needs. The
APK is large, about 200 MB, as it holds Lean's runtime and the Lean and Mathlib code frank_chat
uses.

On Android frank_chat needs a `kpclientd` instance running on the phone, and connects to it at
`127.0.0.1:64331`. frank_chat has been tested with
[kpclientd-android](https://github.com/bfix/kpclientd-android), an app that runs `kpclientd` there
and listens at that address.
