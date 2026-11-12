# Running frank_chat

frank_chat does not reach the mixnet itself. It talks to the Katzenpost client daemon, `kpclientd`,
which does the networking and the cryptography, so start the daemon first, with a client
configuration that says which mixnet to join.

This repository carries the configuration of the namenlos mixnet, in `config/client.toml`. It is
a configuration for `kpclientd`, not for frank_chat, which never reads it.

Build `kpclientd` from [katzenpost](https://github.com/katzenpost/katzenpost) with Go, of at least
the version its `go.mod` names, using the top-level Makefile:

    git clone https://github.com/katzenpost/katzenpost
    cd katzenpost
    make kpclientd

This puts the daemon at `cmd/kpclientd/kpclientd`. Run it with the configuration and leave it
running:

    cmd/kpclientd/kpclientd -c /path/to/frank_chat/config/client.toml

It logs to the terminal. Once it has fetched the mixnet's PKI document from the voting authorities
and connected to one of the gateways the file pins, frank_chat can use it. namenlos's gateways change
from time to time; if the daemon cannot connect to any of them, pull this repository for the
latest `config/client.toml`.

The file's `[Listen]` section says where frank_chat finds the daemon: `@katzenpost`, frank_chat's default.
Several frank_chat instances, jam and katzenqt can share one daemon. Then start frank_chat:

    .lake/build/bin/frank_chat --name alice

| Option | |
|---|---|
| `--daemon ADDR` | the daemon's socket: `@katzenpost` (the default), a path, or `HOST:PORT` |
| `--state DIR` | where frank_chat keeps its state and log; by default `$XDG_DATA_HOME/frank_chat/${FRANK_CHAT_STATE:-default}` |
| `--name NAME` | your display name, which others see; remembered after the first run |
| `--log FILE` | the log file, by default `frank_chat.log` in the state directory |
| `--offline` | show the saved state, without a daemon |
| `--wire-version 3\|4` | what frank_chat writes and mints: 3, the map forms, or 4 (the default), the compact arrays; it reads both |

`FRANK_CHAT_LOG` sets the log level: `critical`, `error`, `warning`, `notice`, `info` (the default) or
`debug`. frank_chat is dark by default; `PAW_THEME=light` gives the light theme, and
`PAW_REDUCE_MOTION=1` turns animations off.

## Starting a group and adding someone

A group is its members: each writes a stream of their own on the mixnet and reads everyone
else's. There are no accounts and no servers.

1. Alice clicks **New group** and names it.
2. Sam clicks **Join a group** and names it as it will be known on his screen. frank_chat mints a
   voucher, and its code appears at the top of the conversation, as text and as a QR code, with
   **Copy** and **Send by sound**. It is also written to `voucher-NAME.txt` in Sam's state
   directory. Sam gives Alice the code out of band.
3. Alice selects the group, clicks **Invite**, and pastes the code, clicks **Scan QR code** and
   holds Sam's screen up to her camera, or clicks **Listen** while Sam clicks **Send by sound**
   nearby; both screens then show the same four check digits. The
   QR code and the sound are the ones hushphone and the T-Deck use. Whoever holds a code reads
   everything said in the group from then on, so she takes it only from the person she means to
   add.
4. A few minutes later Alice sees `— added ~sam`, and Sam `— joined the group`.

Any member can add more people the same way, and everyone hears of them.

## Upgrading from glint

frank_chat was called glint until v0.2.0. On its first run it moves a state kept in
`$XDG_DATA_HOME/glint` to `$XDG_DATA_HOME/frank_chat`; `FRANK_CHAT_STATE` and `FRANK_CHAT_LOG`
replace `GLINT_STATE` and `GLINT_LOG`.
