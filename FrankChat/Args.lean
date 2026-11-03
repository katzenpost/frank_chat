/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import Paw.Linux
import Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member.Gcm

/-! # frank_chat's command line -/

open Cryptlib.Protocols.GroupComm.GroupChatKatzenqt1.Member

structure Config where
  /-- The daemon's socket: a path, `@name` for an abstract one, or `HOST:PORT` over TCP. On Android
  the daemon is another app's, which apps reach over TCP on the device. -/
  daemon : String := if Paw.Linux.onAndroid then "127.0.0.1:64331" else "@katzenpost"
  stateDir : Option System.FilePath := none
  logFile : Option System.FilePath := none
  name : Option String := none
  /-- Show the saved state, without a daemon. -/
  offline : Bool := false
  /-- What we write and mint: 3, the map forms, or 4, the arrays. Both are read. -/
  wireVersion : Nat := Gcm.currentVersion

def usage : String :=
  "usage: frank_chat [--daemon @katzenpost | PATH | HOST:PORT] [--state DIR] [--name NAME] [--log FILE] [--offline] [--wire-version 3|4]
The wire version, 4 by default, is what frank_chat writes and mints; it reads both.
The daemon is @katzenpost by default, and on Android 127.0.0.1:64331.
The state directory is $XDG_DATA_HOME/frank_chat/$FRANK_CHAT_STATE (default: default).
The log level is FRANK_CHAT_LOG: critical, error, warning, notice, info (the default) or debug."

def parseArgs : Config → List String → Except String Config
  | c, [] => pure c
  | c, "--daemon" :: d :: rest => parseArgs { c with daemon := d } rest
  | c, "--state" :: d :: rest => parseArgs { c with stateDir := some d } rest
  | c, "--log" :: f :: rest => parseArgs { c with logFile := some f } rest
  | c, "--name" :: n :: rest => parseArgs { c with name := some n } rest
  | c, "--offline" :: rest => parseArgs { c with offline := true } rest
  | c, "--wire-version" :: v :: rest =>
    if v == "3" || v == "4" then parseArgs { c with wireVersion := v.toNat! } rest
    else throw s!"the wire version is 3 or 4, not {v}"
  | _, a :: _ => throw s!"unknown argument: {a}"
