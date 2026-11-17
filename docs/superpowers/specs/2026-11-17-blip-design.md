# Blip: a pixel spaceship screen assistant for the Mac

Design, 2026-11-17. "Blip" is a working name for the project and the default
character name; the character's name is a setting.

Items marked **(owner)** were decided by the owner in conversation. Items
marked **(call)** are the designer's choices and can be overturned.

## Intent

Press a shortcut and a cute pixel creature flies up from the bottom of the
screen in a little spaceship, leaving an arcade-style trail. It hovers, and
you can ask it about whatever is on your screen by typing or talking. It
answers in texting-style bubbles. Press the shortcut again and it flies off.

The owner wants two things equally: an assistant that is quick and useful
for "what am I looking at?" questions, and an entrance that is fun to watch
every single time. The animation is not decoration; it is half the product.

## Goals

- The fly-in starts the instant the shortcut is pressed, every time.
- The look is retro arcade ("invaders style"): chunky pixels, limited
  palettes, stepped colors, frame-by-frame wiggles. Cool but cute.
- Answers arrive in a few seconds from a fast model that can see the screen.
- The owner can choose character, ship, trail, colors, personality and more
  from a settings page.
- It never gets in the way: everything behind it stays clickable.

## Non-goals

- The assistant does not click, type, or change anything on the computer.
  It only looks and answers.
- No memory between summons. Each time it leaves, the conversation is gone.
- No spoken replies. Voice is input only.
- One character on screen at a time.
- Personal use on the owner's Mac. No App Store, no notarization, no
  Windows.

## Anti-goals (failure even if it "works")

- A pause between the shortcut and the animation while something loads.
- The overlay eating clicks meant for the app underneath, or holding on to
  the keyboard after the owner has clicked back into another app.
- Choppy or blurry animation. It must hold 60 fps and stay pixel-crisp.
- The character or its chat appearing in the screenshot it takes.
- Sprites that copy a real game's characters. All art is original.
- Screenshots saved to disk or sent anywhere except with a question.

## The experience

1. **Summon.** The owner presses the shortcut (default Cmd+Esc **(owner)**,
   rebindable). The character appears on whichever display the mouse
   pointer is on **(call)**.
2. **Fly-in.** The ship rises from below the bottom edge to the middle of
   the screen **(owner)** over about 1.5 seconds, easing out, with its trail
   at full strength.
3. **Hover.** It bobs slowly in a figure 8 **(owner)**. The trail shrinks
   smoothly to a small idle version; it must never cut off abruptly
   **(owner)**.
4. **Chat.** A chat panel appears to the right of the ship **(owner)**: a
   text box with a microphone button on its right side **(owner)**, and
   bubbles above it. If the ship is dragged close to the right edge, the
   chat flips to the left side **(call)**.

   Keyboard **(call)**: summoning is a deliberate act, so the keyboard
   belongs to the character from the moment the shortcut is pressed.
   Anything typed during the fly-in is kept and shows up in the text box
   when it appears. Clicking any app behind it hands the keyboard back to
   that app without dismissing the character; clicking the text box takes
   it again. The app underneath is never brought forward, hidden or
   otherwise disturbed.
5. **Ask.** The owner types, or clicks the mic and talks. Spoken words land
   in the text box; nothing is sent until the owner presses Enter
   **(owner)**.
6. **Think.** While waiting, the aura pulses and a typing-dots bubble shows
   **(owner approved)**.
7. **Answer.** The reply streams into a bubble as it is written **(call)**.
   Follow-up questions keep the conversation going while the character is
   out.
8. **Move.** Everything behind the character stays clickable, and the
   character can be dragged out of the way; the chat follows it
   **(owner)**. It can be dragged anywhere, including onto another
   display, and the screenshot is always of the display it is on at the
   moment a question is sent. Its position is not remembered: every summon
   starts from the middle of the pointer's display **(call)**.
9. **Dismiss.** Pressing the shortcut again makes it fly off **(owner)**:
   it accelerates up and off the top of the screen in under a second with
   the trail at full strength **(call)**. The conversation is forgotten
   **(owner)**. Pressing the shortcut during the fly-in sends it straight
   back out **(call)**.

## The look

The approved reference is `docs/reference/mockup.html` in this project. Open
it in a browser to see the sprites, the six trails and the chat layout
moving. It is a sketch of the look, not code to port; the real app should
match its feel and add polish.

### Art rules

- Everything is drawn on a pixel grid and moves in whole-pixel steps.
- Sprites have dark outlines, a shade tone, a highlight tone, eye glints
  and blush. The owner asked for more detail than a first, simpler sketch;
  the reference is the minimum detail level.
- Animation is frame-by-frame at a low frame rate (blink, seat bob, feet
  or tentacle wiggle) while movement and trails update at 60 fps.
- Colors step through a short ramp instead of fading smoothly. Old trail
  pixels break up in a checker pattern instead of going transparent.
- Reference sizes: creature 16×13 pixels, ship 24 pixels wide, drawn at 3
  screen points per pixel. Size is a setting (small, medium, large)
  **(call)**.

### Cast (starting set)

- **Creatures** **(owner: entirely different creatures, not recolors)**:
  blob (default), ghost, cat, one-eyed alien. Each has its own body color
  and an aura in a lighter tint.
- **Ships**: rocket (default), saucer with blinking lights, bubble pod
  with a glass dome, star ship with swept wings. Ship trim takes the trail
  color.
- The creature stays in the ship the whole time **(owner)**, sitting in the
  cockpit with its lower body hidden behind the hull.
- Adding a creature or ship later should mean adding sprite data, not new
  code paths.

### Aura

A double ring of blinking pixels around the creature that rotates in steps.
It pulses faster and brighter while the assistant is thinking. Aura color is
a setting; by default it matches the creature.

### Trails

The owner rejected a scattered-particle trail and asked for styles that
behave differently, not just color changes. Six styles, all selectable:

| Style | Behavior |
|---|---|
| Comet | A solid ribbon that follows the ship's path and tapers in steps |
| Flame | A flickering engine flame with a white core and stray sparks |
| Smoke rings | Rings puffed out at intervals that widen as they fall |
| Echoes | Fading ghost copies of the whole ship left behind |
| Lightning | Three forking bolts: a thick middle bolt with a white core and two thinner ones fanning outward, each re-forking on its own timing **(owner: more than one bolt)** |
| Confetti | Tumbling hearts, stars and diamonds |

Every style has a strong version for fly-in and fly-off and a small version
for hovering, with a smooth transition between them. Trail color is picked
by the owner **(owner)**: presets (fire, pink, cyan, lime, violet) plus a
custom color **(call)**. Each color expands to a four-step ramp: white,
light, main, dark.

Default combination: blob in the rocket with cyan lightning **(call)**.

### Chat

Looks like texting **(owner)**: rounded rectangles, the owner's messages on
the right in a strong color, replies on the left in a neutral one. Bubble
color is a setting. Replies are plain text **(call)**. Long conversations
scroll inside a panel of limited height.

### Sound

Short chiptune effects for launch, reply and fly-off, with one on/off
switch **(owner)**. Default on **(call)**.

## How it sees the screen

- A screenshot is taken at the moment a question is sent, never before
  **(call)**.
- By default it is the whole display the character is on **(owner)**, with
  the app's own windows left out.
- The owner can ask about one window in plain words ("look at the Safari
  window") **(owner)**. Mechanism **(call)**: each question is sent with a
  numbered list of the open windows (app name and title). If the assistant
  needs a sharper look at one, it replies with a single marker line naming
  the number; the app captures that window alone, sends it as a follow-up,
  and shows only the final answer. This also covers small text that a
  whole-screen image makes unreadable.
- Images are scaled so normal on-screen text stays readable while keeping
  the request small. Exact sizes are the builder's to tune.
- Screenshots stay in memory, are never written to disk, and go only to
  the assistant's model **(call)**.

## The brain

The owner asked for the assistant to run off a Claude session in the
background on a fast model **(owner)**.

- The app runs the `claude` command-line tool as a hidden child process in
  streaming mode, using the Claude login on this Mac. No API key and no
  separate bill.
- Model is a setting: fastest (Haiku, default) or smarter but slower
  (Sonnet).
- The process runs with no tools at all, with the owner's Claude
  customizations switched off, and with nothing saved to disk. Flags
  confirmed to exist in the installed version (2.1.293): `-p`, `--model`,
  `--safe-mode`, `--strict-mcp-config`, `--tools ""`,
  `--no-session-persistence`, `--system-prompt`, `--input-format
  stream-json`, `--output-format stream-json`, `--verbose`,
  `--include-partial-messages`.
- **Staying fast.** Starting the tool takes about 2 seconds (measured), so
  the app always keeps one fresh process waiting. A conversation uses it
  while the character is out. On dismissal that process is ended, which is
  what "forgetting" means, and a new one is started right away for next
  time. Changing the model, name, personality or answer length also swaps
  in a fresh process.
- **Instructions.** The app writes the assistant's instructions from the
  settings: its name, its personality, short or detailed answers, plain
  text only, and the fact that each message comes with a picture of the
  owner's screen.
- **Finding the tool.** Apps started from the Finder do not see the
  terminal's search path. The app looks in the usual places
  (`~/.local/bin/claude` on this Mac) and has a setting to point at it.

### Proven by test (2026-11-17)

A script drove one hidden session with the flags above, sending a test
image inline (base64 inside the streamed message, nothing on disk) and
asking three questions in a row. All three were answered correctly.

| | First words appear | Reply finished |
|---|---|---|
| First question, including starting the tool | 2.9 s | 5.0 s |
| Follow-up without an image | 0.6 s | 2.7 s |
| Follow-up with a new image | 0.7 s | 2.5 s |

Notes for the builder:

- The tool only reports itself ready after the first message is sent, so
  keeping a process waiting saves the launch time but not all of the
  first-question delay.
- The final "result" line arrives about 2 seconds after the last words.
  The app should treat the end of the streamed message as "done" and not
  wait for that line before letting the owner type again.
- The test image was small (1200×700). Timing with a full-screen capture
  still needs measuring during the build.
- Speed target **(call)**: first words within about 3 seconds on the first
  question and about 1 second on follow-ups, on Haiku. If full-screen
  images miss that, shrink the image before changing anything else; the
  window close-up covers small text.
- The owner logged the terminal tool in on 2026-11-17 (`claude auth
  login`); before that the same test failed with an expired-login error,
  which is the "not logged in" case below.

### When things go wrong

Each of these shows a friendly bubble from the character, never a crash or
silence: not logged in (says to run `claude auth login`), the tool is
missing, a permission is missing (with a button to the right System
Settings page), no reply within a time limit, usage limit reached.

## Settings

A small icon in the menu bar **(owner: "top dock")** opens a menu with
Summon, Settings and Quit. The settings window has a live animated preview
of the current character **(call)** and these options **(owner approved the
list)**:

- **Character:** name, creature, ship, size
- **Look:** trail style, trail color, aura color, bubble color
- **Motion:** figure 8, simple bob, or still
- **Personality:** playful, plain, or the owner's own description
  **(owner: variable in settings)**
- **Answers:** short or detailed
- **Brain:** fastest or smarter
- **Sounds:** on or off
- **Shortcut:** recorder, default Cmd+Esc
- **Start at login:** on or off, default on **(call)**
- **Advanced:** location of the `claude` tool

Changes apply immediately, without restarting.

## Permissions and first run

The app needs Screen Recording, Microphone and Speech Recognition. On first
run it explains each in the character's voice and asks for them one at a
time; microphone and speech are only requested the first time the mic is
used **(call)**. The app is signed with the signing identity already on
this Mac so macOS keeps the permissions across rebuilds.

## Constraints

- Native Mac app in Swift **(owner)**, built with the Xcode already
  installed (Xcode 26.6, Swift 6.3, macOS 26.2). It only needs to run on
  this version of macOS.
- Not sandboxed, because it must start the `claude` tool.
- Cmd+Esc is also the shortcut that opens Claude Code inside some code
  editors; a global shortcut takes it over. The owner was told and kept it.
- The overlay must appear over full-screen apps and on every Space.

## Approaches considered

| | Electron | Native Swift | Tauri |
|---|---|---|---|
| Animation | Reuse a web trail component | Written from scratch | Reuse a web trail component |
| Click-through overlay | Proven | Built in | Fiddly on the Mac |
| Voice and screen capture | Needs a native helper | Built in | Needs native code |
| Weight | Heavy | Light | Light |

Electron was the designer's first recommendation, because the owner had
shown a web trail component as a reference. The owner then chose **native**
and clarified that the web component was only a general example and the
trail should be arcade style instead. That removed Electron's one
advantage: a blocky arcade trail is simple to write natively, and voice,
screen capture and the overlay are all first-class there.

## Left to the builder

- How the animation is drawn (for example SpriteKit or plain layers), as
  long as it is crisp, 60 fps and transparent.
- Which Apple speech API to use; it should work on-device.
- How sounds are made (synthesized or small bundled files).
- Extra sprite frames and polish beyond the reference: launch shake,
  squash on arrival, fly-off flourish.
- Exact timings, distances, image sizes, time limits and the wording of
  the marker line.
- Project layout, settings storage and test structure.

## How it will be checked

- The parts that are pure logic get automated tests: trail and motion
  stepping, the parser for the hidden session's output, the instruction
  builder, the window close-up exchange.
- The look is checked by eye against the reference mockup.
- An end-to-end run on this Mac: summon, ask about the screen by typing and
  by voice, ask about one window, drag, dismiss, summon again and confirm
  it has forgotten.
