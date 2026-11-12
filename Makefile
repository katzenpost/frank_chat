# SPDX-License-Identifier: AGPL-3.0-only

export PATH := $(HOME)/.cargo/bin:$(HOME)/.elan/bin:$(PATH)

# Paw's Rust crate pins this toolchain; the daemon socket's crate pins none. Both static libraries
# carry Rust's std, so they must be built by the same rustc or the link finds it twice.
export RUSTUP_TOOLCHAIN := 1.99.0

katzenpost_ref?=2405aa1119404b1e27cce0566729141102d769f0
katzenpost_dir?=.katzenpost

.PHONY: build release release-apk test run shots screenshot android-screenshot e2e e2e-offline e2e-wayland test-integration ci apk

build:
	lake exe cache get && lake build frank_chat

# The binary and its SHA256SUMS in dist/, the same bytes on every machine.
release:
	sh scripts/release-build.sh dist

release-apk:
	sh scripts/release-apk.sh dist

# In one process, with no daemon or window.
test:
	lake exe cache get && lake build frank_chat_test && lake exe frank_chat_test

run:
	lake exe frank_chat

# Pictures of the window, drawn offscreen, in shots/.
shots:
	lake build frank_chat_test && lake exe frank_chat_test --shot shots

# The README's picture: Alice's window after a conversation over the simulated Pigeonhole.
screenshot:
	lake build frank_chat_test && lake exe frank_chat_test --readme docs/screenshot.png

# The README's picture of frank_chat on a phone, taken on an Android emulator.
android-screenshot:
	lake build frank_chat_test && sh scripts/android-screenshot.sh

e2e: e2e-offline e2e-wayland

# A saved state shown in a real window on Xvfb, driven with xdotool.
e2e-offline:
	lake build frank_chat frank_chat_test && sh tests/e2e/offline.sh

# The same under a headless sway, driven with Paw's virtual pointer and wtype.
e2e-wayland:
	lake build frank_chat frank_chat_test
	cd .lake/packages/paw/rust && cargo build --quiet --release --example vpointer
	sh tests/e2e/wayland.sh

# Two windows over the docker mixnet's client daemon, as test-integration.sh starts it.
test-integration:
	lake build frank_chat && DAEMON=127.0.0.1:33399 N=3 MINUTES=30 sh tests/e2e/mixnet.sh

ci: test e2e

# frank_chat for Android, in .lake/android, built by Paw's Android build; see Paw's README for what
# it needs. ANDROID_ABI is arm64-v8a, for phones, or x86_64, for the emulator.
ANDROID_ABI ?= arm64-v8a

apk:
	lake exe cache get
	APP=$(CURDIR) EXE=frank_chat ROOT=FrankChat.Main NAME=org.katzenpost.frank_chat LABEL=frank_chat PERMISSIONS="RECORD_AUDIO CAMERA" \
	  ANDROID_ABI=$(ANDROID_ABI) sh .lake/packages/paw/android/build.sh
