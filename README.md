# Blip

Press a shortcut and a small pixel creature flies up from the bottom of your screen in a little
spaceship, trailing arcade fire. Ask it about whatever is on your screen, by typing or by talking,
and it answers in chat bubbles. Press the shortcut again and it flies off, forgetting the
conversation.

Blip is a menu-bar app for macOS 26. It never clicks or types anything for you: it only looks and
answers. A screenshot is taken only when you send a question, stays in memory, and is never saved
to disk.

## Build and install

You need Xcode 26 and a code-signing identity on this Mac (macOS keeps Blip's permissions across
rebuilds only while it is signed by the same identity).

```bash
scripts/build-app.sh            # builds, signs, installs to ~/Applications/Blip.app and opens it
scripts/build-app.sh --no-open  # the same, without opening it
swift test                      # the logic tests
```

Set `BLIP_SIGN_ID` to choose a signing identity; otherwise the first one found is used.

## Answers come from Claude Code

Blip asks its questions through the `claude` command-line tool, so it uses your Claude account.
Install Claude Code, then log in once:

```bash
claude auth login
```

Blip looks for `claude` in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and
`~/.claude/local`. If yours is somewhere else, set its path in Settings > Advanced.

## Using it

- **Cmd+Esc** summons Blip on the display your pointer is on, and sends it off again. The shortcut
  can be changed in Settings.
- Type a question and press Return, or press the mic and talk; nothing is sent until you press
  Return.
- Drag the ship anywhere, onto another display too. Everything behind it stays clickable.
- The sparkles icon in the menu bar has Summon, Settings and Quit.

## Permissions

Blip asks for three, each the first time it needs it:

| Permission | Why | When it is asked |
|---|---|---|
| Screen Recording | To see your screen when you ask a question | From the welcome window (Turn on), or the first question |
| Microphone | To hear a spoken question | The first time you press the mic |
| Speech Recognition | To turn speech into text, on this Mac | The first time you press the mic |

Each can be turned off in System Settings > Privacy & Security. To make macOS ask again from the
start, reset them:

```bash
tccutil reset ScreenCapture com.blip.assistant
tccutil reset Microphone com.blip.assistant
tccutil reset SpeechRecognition com.blip.assistant
```

To see the welcome window again and go back to the default settings:

```bash
defaults delete com.blip.assistant
```

## For development

- `swift run blip-snap --creature blob --ship rocket --trail lightning --color cyan --tick 60 --out frame.png`
  renders one animation frame to a PNG (`--dismiss <tick>` starts the fly-off at that tick).
- `BLIP_DEBUG=1` logs events, launches and sounds to stderr; `BLIP_NO_CLAUDE=1` runs without
  starting `claude`; `BLIP_CLAUDE_PATH=<path>` runs a different `claude`.
- `kill -USR1 $(pgrep -x Blip)` does what the shortcut does; `kill -USR2 $(pgrep -x Blip)` opens
  Settings.
- The design is in `docs/superpowers/specs/2026-11-17-blip-design.md`; the look comes from
  `docs/reference/mockup.html`.
