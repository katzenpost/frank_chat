# Using frank_chat

The groups are on the left, the selected conversation in the middle, and on the right everyone
who reads what is written there, with the start of each member's key. Messages are grouped: one
sender's messages a few minutes apart sit under one header with their name and the time they were
said or read here. The log is hidden until F2 shows it.

| Button | |
|---|---|
| New group | start a group of your own |
| Join a group | join someone else's group: frank_chat shows a voucher code to give one of its members |
| Invite | let the person whose voucher code you were given into the selected group |
| Remove member | stop reading a member and delete what they sent; they can still read the group |
| Rename | call the selected group something else here; the other members keep their own names for it |
| Clear | delete the selected conversation's lines here |
| Scan | look again for messages a member's stream skipped |
| Leave | stop reading and writing the group and delete it here, once you type its name |
| Attach… | choose a file and send it to the selected group |
| View, Save… | beside a file received: see a picture large, or copy the file out |
| Hold to talk | record a voice note while you hold it, to play, discard or send |
| Play, Stop | beside a voice note: play it, or stop |

The **Send** button names the group the message goes to, and how many lines it is.

## Files

Files travel as katzenqt's do, so frank_chat, jam and katzenqt members can send each other files. A file,
or any message too long for one box, is written to a stream of its own, a box at a time, and the
group's stream then names that stream; members read it before what comes after it. A file can be
up to 16 MB, but each box takes a trip across the mixnet, so a large file takes a long time: its
line says how far it has gone. PNG and JPEG pictures are shown in the conversation, at most
320 × 240, and large with View; other files show their name and size. Received files are kept in
`attachments/` in the state directory, and Save… copies one out.

## Voice notes

Hold **Hold to talk**, or Ctrl+Space, while you speak, and let go. The voice note waits above the
message box, to Play, Discard, or Send to the group; nothing is sent until you click Send. A
voice note is Ogg Opus, 48 kHz mono at 12 kb/s, about 1.5 kB a second, recorded and played by
Rustic Audio through ALSA's default devices. It is sent as katzenqt sends one: a file of type
`audio/opus` named by its SHA-256, so that its name tells nothing of when it was recorded.
Voice notes received show Play and Stop. If frank_chat cannot reach the sound system, Hold to talk is
greyed out and says why.

| Key | |
|---|---|
| Ctrl+Enter | send |
| Ctrl+Space, held | record a voice note |
| Ctrl+PageUp, Ctrl+PageDown | the previous or next group |
| F2 | show or hide the log |
| F10 | blank the window at once, and bring it back |
| Ctrl+Q | quit |

Your own messages are marked `…` until written, `✓` once written, and `✓✓` once a member
acknowledges reading them.
