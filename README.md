# frank_chat

A desktop and Android group chat over the [Katzenpost](https://github.com/katzenpost) mixnet,
for people who want to talk in a small group without accounts or servers. It speaks
[katzenqt](https://github.com/katzenpost/katzenqt)'s group chat, so a frank_chat member, a
[jam](https://github.com/katzenpost/jam) member and a katzenqt member can be in one group.

![frank_chat: groups on the left, a conversation with delivery marks in the middle, members with the start of their keys on the right](docs/screenshot.png)

frank_chat sends text, files up to 16 MB and voice notes. It does not reach the mixnet itself:
it talks to the client daemon, `kpclientd`, which does the networking and must be running first.
For a terminal client, use jam.

## Quick start

Download `frank_chat-<version>-x86_64-linux`, or the Android APK, from the
[releases](https://github.com/katzenpost/frank_chat/releases), or build it with Lean (through
elan), Rust 1.99.0 (through rustup) and the packages
[docs/building.md](docs/building.md) lists:

    git clone https://github.com/katzenpost/frank_chat
    cd frank_chat
    make build

Start `kpclientd`, built from [katzenpost](https://github.com/katzenpost/katzenpost) as
[docs/running.md](docs/running.md) shows, with this repository's namenlos configuration, and
leave it running. Then start frank_chat:

    /path/to/kpclientd -c config/client.toml
    .lake/build/bin/frank_chat --name alice

On Android, frank_chat connects to a `kpclientd` on the phone at `127.0.0.1:64331`, such as
[kpclientd-android](https://github.com/bfix/kpclientd-android).

To join a group, click **Join a group** and give the voucher code it shows to a member, who
pastes it under **Invite**.

## Documentation

- [docs/building.md](docs/building.md): what the build needs, verifying a reproducible release, Android.
- [docs/running.md](docs/running.md): building and running `kpclientd`, options, starting a group.
- [docs/using.md](docs/using.md): the buttons, files, voice notes and keys.
- [docs/security.md](docs/security.md): how frank_chat treats what other members send.
- [docs/testing.md](docs/testing.md): the test, end-to-end and mixnet targets.

## What is here

- [`FrankChat/Main.lean`](FrankChat/Main.lean): the program; [`Args.lean`](FrankChat/Args.lean), its command line.
- [`FrankChat/App.lean`](FrankChat/App.lean): the window, drawn with [Paw](https://github.com/katzenpost/paw).
- [`FrankChat/Command.lean`](FrankChat/Command.lean): what each action asks of the client core, [group_chat_client](https://github.com/katzenpost/group_chat_client).
- [`FrankChat/Display.lean`](FrankChat/Display.lean), [`Presentation.lean`](FrankChat/Presentation.lean): what may reach the screen, and how it is worded.
- [`FrankChat/Voucher.lean`](FrankChat/Voucher.lean), [`Sound.lean`](FrankChat/Sound.lean), [`Voice.lean`](FrankChat/Voice.lean): voucher codes as QR codes and by sound, and voice notes.
- [`FrankChat/Tests`](FrankChat/Tests), [`tests/e2e`](tests/e2e): the tests.
- [`config/client.toml`](config/client.toml): `kpclientd`'s configuration for the namenlos mixnet.

## Status

Version 0.4.2 in `lakefile.toml`; the latest release is v0.4.1, built reproducibly. The group
chat protocol is Cryptlib's katzenqt member state machine, with its proofs. frank_chat writes
wire version 4 by default (`--wire-version 3` for the older map forms) and reads both.

## Testing and licence

`make test` runs the tests in one process, with no daemon or window; see
[docs/testing.md](docs/testing.md) for the rest. frank_chat is licensed under the
[AGPL-3.0](LICENSE).
