# Security

frank_chat follows Paw's [GUI security guidelines](https://github.com/katzenpost/paw/blob/main/docs/GUI_SECURITY_GUIDELINES.md):
everything another member sends is untrusted.

- **One filter.** Text from elsewhere reaches a widget only as Paw's `SafeText` or `SafeName`,
  through `FrankChat.Display`. Control characters, invisible characters, private-use glyphs and line
  separators show as `�`; combining marks are capped at four a letter; a message shows at most 20
  lines and says how many more there were. Nothing is parsed as markup.
- **frank_chat decides who said what.** A member's chosen name is shown after `~`, ours as `me`. A
  name cannot hold bidi controls, joiners, badges, or frank_chat's own marks (`…`, `✓`), and is cut at
  30 characters. Names that look alike, names like ours and names mixing scripts show the start of
  the member's key, and are marked `(!)` among the members.
- **A message cannot pass for another.** A run of messages begins with a header frank_chat draws: the
  sender's name in bold, flush left, and the time. Every row of a message is indented under it,
  in regular weight, with our delivery mark in a column of its own, so no row of a message can
  look like a header. frank_chat's own notices are small, muted and centered, which no message is.
- **Authority follows the user's click.** The message box only sends text; everything else is a
  button. A dialog opens only from the user's click, never from the network, and its accept
  button takes no click in the half second after it appears. A member to remove is chosen from
  the list, by key. Copy writes the clipboard only for a click on it. A file is read only once
  you choose it and click Send, and one received is written outside the state directory only where
  you save it, never over a file already there. The microphone records only while you hold Hold
  to talk or Ctrl+Space, and what it recorded leaves only when you click Send. frank_chat asks for the
  clipboard and for running tasks, and for nothing else: no links, no notifications. The window's
  title is always "frank_chat".
- **Pictures.** A picture received is decoded by Paw, which takes only PNG and JPEG and refuses one
  larger than 8192 pixels a side or 64 MiB of pixels before decoding it. A file's name is cut to
  ASCII letters, digits and `._-+()[]` and spaces before it is shown or kept.
- **On disk.** The state directory is created 0700, `state.cbor`, `frank_chat.log` and received files
  0600. The log is
  filtered like the screen and holds no message text. `state.cbor` and `attachments/` are not encrypted:
  they hold your write caps and every message and file. Clear deletes a conversation's lines and
  files, Leave the group.
- **Leaving.** F10 blanks the window at once. SIGTERM, SIGHUP and SIGQUIT exit.
