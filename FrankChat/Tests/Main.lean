/-
SPDX-FileCopyrightText: Copyright (C) 2026 David Stainton
SPDX-License-Identifier: AGPL-3.0-only
-/

import FrankChat.Tests.Display
import FrankChat.Tests.Command
import FrankChat.Tests.State
import FrankChat.Tests.App
import FrankChat.Tests.Shot
import FrankChat.Tests.Members
import FrankChat.Tests.Files
import FrankChat.Tests.Voice
import FrankChat.Tests.Phone
import FrankChat.Tests.Sound
import FrankChat.Args
import FrankChat.Presentation

/-! # frank_chat's tests, in one process, with no daemon or window -/

open FrankChat.Tests

namespace FrankChat.Tests.ArgsTests

open FrankChat FrankChat.Tests GroupChatClient.GroupChatKatzenqt1

/-- `--wire-version` reaches the core that `resume` makes. -/
def tests : TestM Unit := do
  let wv (args : List String) := (parseArgs {} args).toOption.map (·.wireVersion)
  check "the wire version is 4 by default" (wv [] == some 4)
  check "--wire-version 3 picks the map forms" (wv ["--wire-version", "3"] == some 3)
  check "--wire-version 4 picks the arrays" (wv ["--offline", "--wire-version", "4"] == some 4)
  check "other wire versions are refused" (wv ["--wire-version", "5"] == none && wv ["--wire-version"] == none)
  let core (v : Nat) := (resume presentation { me := "a" } 1530 (wireVersion := v)).1
  check "the core writes in the version asked for"
    ((core 3).wireVersion == 3 && (core 4).wireVersion == 4)

end FrankChat.Tests.ArgsTests

def main (args : List String) : IO UInt32 := do
  if let ["--shot", dir] := args then
    Shot.shots dir
    return 0
  if let ["--readme", path] := args then
    Shot.readme path
    return 0
  if let ["--readme-state", dir] := args then
    Shot.readmeStateFile dir
    return 0
  if let ["--fixture", dir] := args then
    Shot.fixture dir
    return 0
  let mut ok := true
  for (name, t) in [("args", FrankChat.Tests.ArgsTests.tests), ("display", DisplayTests.tests),
      ("command", CommandTests.tests), ("state", StateTests.tests), ("app", AppTests.tests), ("members", Members.tests),
      ("files", FilesTests.tests), ("voice", VoiceTests.tests), ("phone", PhoneTests.tests),
      ("sound", SoundTests.tests)] do
    ok := (← runSuite name t) && ok
  -- Tasks of the shells may still be asleep; they would keep the process alive.
  IO.Process.exit (if ok then 0 else 1)
