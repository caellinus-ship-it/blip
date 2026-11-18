# Blip

Press a shortcut and a small pixel creature flies up from the bottom of your screen in a little
spaceship, trailing arcade fire. Ask it about whatever is on your screen, by typing or by talking,
and it answers in chat bubbles. Press the shortcut again and it flies off, forgetting the
conversation.

Blip is a menu-bar app for macOS 26. It can also do small jobs on your Mac when you ask, such as
making a file on your Desktop or looking something up in your mail, and by default it asks before
every change.

This is a personal project, lightly tested on one Mac. Read [Before you run it](#before-you-run-it)
first, and use it at your own risk.

## What you can change

Everything is in Settings, with a live preview:

- **Creature:** blob, ghost, cat, alien, and a Christmas set of Santa, snowman and reindeer.
- **Ship:** rocket, saucer, bubble pod, star ship, sleigh.
- **Trail:** comet, flame, smoke rings, echoes, lightning, confetti, snow, in any color.
- **Flight:** how it arrives (comet, warp, sparkle, bubble), the path it takes, and how fast.
- **Behavior:** its eyes follow your pointer, it squints while it reads, hops when it finishes an
  answer, jumps when something goes wrong, and dozes off if you leave it alone. A scan line sweeps
  the screen whenever it actually takes a look, so you can tell when it did. Each can be turned off.
- **Assistant:** its name, personality, answer length and model.

## Before you run it

- **It uses your Claude account.** Blip runs the `claude` command-line tool with whatever account
  is logged in on your Mac. Every question spends that account's usage.
- **Your screen leaves your Mac when a question needs it.** When a question sounds like it is about
  the screen ("what is this?"), Blip takes a screenshot and sends it with the question to Claude,
  the same way any Claude request travels. The screenshot stays in memory on your Mac and is never
  saved to disk. A question like "what is 2+2" goes without one.
- **It can act on your Mac.** With "Use my Mac" on (the default), the assistant can read and write
  files, run terminal commands, search the web, and use the Gmail and Google Drive connectors of
  your Claude account if you have them. It cannot click or type in other apps.
- **It asks first.** "Ask first" is set to "Any change" by default: reading inside Desktop,
  Documents and Downloads, searching the web and reading mail happen without a question;
  everything else shows a "Can I do this?" bubble with Allow and Don't. "Risky only" asks less, and
  "Never" lets it act without asking at all. Leave it on "Any change" unless you know why you are
  changing it.
- **What it reads could try to steer it.** Text on your screen, in a file, in an email or on a web
  page might be written to trick an assistant. Blip is told to treat all of it as information and
  never as instructions, but that is a rule the model follows, not a wall. The "Can I do this?"
  bubble is the real safeguard, so read it before you press Allow.
- **It is not sandboxed.** Blip runs with your user account's access. Turn "Use my Mac" off in
  Settings to go back to an assistant that only looks and answers.
- **Not everything has been tried for real.** Sending email, Google Drive, the "Risky only" and
  "Never" levels, and voice input with a real microphone have not been tested end to end.

## Build and install

You need Xcode 26. There is no download: you build it yourself.

```bash
scripts/build-app.sh            # builds, signs, installs to ~/Applications/Blip.app and opens it
scripts/build-app.sh --no-open  # the same, without opening it
swift test                      # the logic tests
```

The script signs the app with the first code-signing identity it finds on your Mac, or with the one
named in `BLIP_SIGN_ID`. With no identity it signs ad hoc, which works, but macOS then treats every
rebuild as a new app and asks for Screen Recording again each time.

## Answers come from Claude Code

Blip asks its questions through the `claude` command-line tool, so it uses your Claude account.
Install Claude Code, then log in once:

```bash
claude auth login
```

Blip looks for `claude` in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` and
`~/.claude/local`. If yours is somewhere else, set it in Settings, in the App section, under
Path to claude.

## Using it

- **Cmd+Esc** summons Blip on the display your pointer is on, and sends it off again. The shortcut
  can be changed in Settings.
- Type a question and press Return, or press the mic and talk; nothing is sent until you press
  Return.
- The square on the left of the text box stops an answer that is on its way; so does Escape while
  the chat has the keyboard. What has already arrived stays, and Blip still remembers the
  conversation.
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
  renders one animation frame to a PNG (`--dismiss <tick>` starts the fly-off at that tick; run it
  with no arguments for the other options, such as `--mood`, `--look` and `--scan`).
- `BLIP_DEBUG=1` logs events, launches and sounds to stderr; `BLIP_NO_CLAUDE=1` runs without
  starting `claude`; `BLIP_CLAUDE_PATH=<path>` runs a different `claude`.
- `kill -USR1 $(pgrep -x Blip)` does what the shortcut does; `kill -USR2 $(pgrep -x Blip)` opens
  Settings.
- The design is in `docs/superpowers/specs/2026-11-17-blip-design.md`; the look comes from
  `docs/reference/mockup.html`. How acting on the Mac works is in
  `docs/superpowers/specs/2026-11-17-actions-notes.md`.

## License

MIT. See [LICENSE](LICENSE).
