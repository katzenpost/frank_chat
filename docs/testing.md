# Testing frank_chat

    make test          # in one process: what reaches the screen, each action, the window
                       # driven by clicks and keys, and two members each with a shell and a window
    make e2e           # a saved state in a real window on Xvfb, driven with xdotool
    make shots         # pictures of the window, drawn offscreen, in shots/
    make screenshot    # docs/screenshot.png, from a conversation over the simulated Pigeonhole
    make android-screenshot   # docs/android.png, the same conversation on an Android emulator
    N=5 DAEMON=@katzenpost sh tests/e2e/mixnet.sh   # N windows (2 to 8) in one group, against a running kpclientd
    ./test-integration.sh                       # the same over the docker mixnet

The client core, its saved state and its scenarios are tested in
[group_chat_client](https://github.com/katzenpost/group_chat_client), which frank_chat shares with jam.
