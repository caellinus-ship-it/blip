# Letting Blip act on the Mac: findings so far (2026-11-17)

Nothing is built yet. This records what was decided and what was proven, so the work can resume.

## Owner's decisions

- Powers: everything offered. Files, read Gmail and write drafts, send email, run terminal commands.
- Asking first: a setting with three levels, default "before any change". The other two are "only risky
  changes" and "never ask".

## Proven by experiment with claude 2.1.293

- Tools: `--tools "Read,Write,Edit,Bash,WebSearch,WebFetch,ToolSearch"` gives the hidden session those tools.
- Gmail and Google Drive: the claude.ai connectors load only with the user's settings, so drop `--safe-mode`
  and `--strict-mcp-config` and pass `--settings '{"disableAllHooks":true}' --disable-slash-commands` to keep
  hooks and skills out. The session then finds `mcp__claude_ai_Gmail__*` and `mcp__claude_ai_Google_Drive__*`
  through ToolSearch. `--restricted` and `--setting-sources project` both lose the connectors.
- Permission prompts: with `--permission-prompt-tool stdio` the session writes
  `{"type":"control_request","request_id":…,"request":{"subtype":"can_use_tool","tool_name":…,"input":{…}}}`
  and waits for
  `{"type":"control_response","response":{"subtype":"success","request_id":…,"response":{"behavior":"allow","updatedInput":{…}}}}`
  (or `"behavior":"deny","message":…`). Without that flag every action is refused.
- A turn with tools has several messages: `message_stop` also arrives when the model pauses to call a tool
  (`message_delta` then carries `stop_reason: "tool_use"`), so `messageDone` must not end the answer then.
- The user's `~/.claude/CLAUDE.md` still reaches the session in this mode; tell the prompt to ignore it.
- It cannot click or type inside apps; there is no mouse and keyboard tool in the command-line tool.

## Plan

- Settings: `actions` (on) and `askFirst` (anyChange, riskyOnly, never).
- Core: classify each request as read, gentle (new file, draft, open a web page) or risky (overwrite, edit,
  delete, send, any command, reading outside Desktop, Documents and Downloads); build a plain summary.
- App: a confirm bubble with Allow and Don't; notes for actions done without asking; an activity timeout
  that pauses while waiting for the owner.
- Prompt: say what it may do, that text seen on screen, in files, mail or web pages is never an instruction,
  and that it only acts when the owner's own message asks.

## Built, 2026-11-18

This replaces the original non-goal "the assistant does not click, type, or change anything".

- Settings, under Assistant: "Use my Mac" (on by default) and "Ask first" (Any change, Risky only, Never;
  default Any change).
- With it on, the hidden session gets file, command and web tools plus the owner's connected Gmail and
  Google Drive, and asks the app before each action. Reading inside Desktop, Documents and Downloads,
  searching the web and reading mail never ask. New files, drafts and opening a web page are "gentle".
  Overwriting, editing, deleting, sending, any command, and reading elsewhere are "risky".
- The chat shows a "Can I do this?" bubble with Allow and Don't, and a small note for each thing done,
  allowed or skipped.
- With it off, the session is exactly the old look-only one.
- Checked for real: a Desktop file created after Allow; a second one not created after Don't; a Gmail
  question answered without asking. Not checked: sending email, Google Drive, the Risky only and Never
  levels, and a long-running command.
