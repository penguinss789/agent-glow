# AgentGlow

[English](README.md) · [简体中文](README.zh-CN.md)

Native macOS screen-edge glow notifications for **completed tasks, decisions that need your input, and plans ready for review** in Claude Code and Codex.

Built with Swift and AppKit. [MIT License](LICENSE) · [Contributing](CONTRIBUTING.md)

## Effects

| State | Effect | On-screen label | Duration |
|---|---|---|---|
| `done` | Green fade in and out | ✓ 完成 · project name | 2.0 seconds |
| `decision` | Two amber pulses | ? 等你决定 · project name | 2.8 seconds |
| `plan` | A blue-purple sweep along the top edge, followed by a fade | ✦ 方案就绪 · project name | 2.6 seconds |

- Click-through overlays that never take keyboard focus or interrupt typing.
- Temporary transparent windows, independent of Notification Center.
- No persistent daemon: a hook classifies the event, then a separate process plays the animation and exits.
- Independent Claude and Codex installations that can run alongside each other.
- Claude uses the primary display and stays quiet when the Claude desktop app is in the foreground. Codex uses all connected displays and also shows effects when it is in the foreground.
- On-screen labels are currently in Chinese. Edit `Kind.title` in the Swift sources to change them.

## Requirements

- A macOS graphical desktop session. AppKit is required; Linux, Windows, and headless servers are not supported.
- A Swift compiler from Xcode Command Line Tools or Xcode.
- Python 3 for merging JSON hook configurations and running tests. No third-party Python packages are required.
- A client that supports the hook events listed below. Hook coverage may vary between client versions.

```bash
xcode-select --install
swiftc --version
python3 --version
```

The executables are compiled locally for your machine's architecture; no prebuilt binaries are downloaded. Local builds have been verified on Apple Silicon. GitHub Actions uses `macos-latest`.

## Installation

Clone this repository or download and extract its ZIP archive, then enter the project directory. Install either or both integrations:

```bash
# Claude Code, including desktop Code sessions that support Code hooks
./install.sh

# Codex
./install-codex.sh
```

No `sudo` is required. The installer validates the configuration, compiles the executable, and merges this project's hooks. It preserves other settings, unrelated handlers in the same hook group, and the other client's hooks. Reinstalling updates the executable and hooks without adding duplicate entries.

| Client | Executable | Configuration modified | State and log directory |
|---|---|---|---|
| Claude | `~/.claude/glow/claude-glow` | `~/.claude/settings.json` | `~/.claude/glow/` |
| Codex | `~/.codex/glow/codex-glow` | `~/.codex/hooks.json` | `~/.codex/glow/` |

Existing configurations and executables are backed up with timestamped `.bak.*` suffixes before being updated. Start a new session after installation to load the hooks.

**For Codex, review and trust the updated definitions in `/hooks`.** The installer does not modify trust records or `config.toml`. Notifications require the client to emit the relevant events, trust the hooks, and load the configuration.

## Manual preview

```bash
~/.claude/glow/claude-glow show done "My Project"
~/.claude/glow/claude-glow show decision "My Project"
~/.claude/glow/claude-glow show plan "My Project"

~/.codex/glow/codex-glow show done "My Project"
~/.codex/glow/codex-glow show decision "My Project"
~/.codex/glow/codex-glow show plan "My Project"
```

`show` plays an animation directly, bypassing Claude's foreground suppression. The third argument is an optional label. When triggered by a hook, the label is the last directory component of the event's `cwd`.

## Trigger rules

### Claude Code

| Event | Behavior |
|---|---|
| `Stop` | Green by default; amber if a pending-decision marker exists or the final reply ends in `?` / `？` |
| `PreToolUse: AskUserQuestion` | Amber |
| `PreToolUse: ExitPlanMode` | Blue-purple; briefly suppresses the subsequent duplicate plan-approval notification |
| `PreToolUse: mcp__ccd_turn__wrap_up` | Records a pending-decision marker for `Stop` when `ask` is present |
| `Notification` | Amber for notifications other than `idle_prompt`, except duplicate notifications following a plan |

When the Claude desktop app is in the foreground, hooks still update state but do not play animations. To always show effects, prefix the Glow hook commands in `settings.json` with `CLAUDE_GLOW_ALWAYS=1`. Reinstalling resets this project's hook commands.

### Codex

The installer registers `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, and `Stop`.

| Condition | Behavior |
|---|---|
| An ordinary `Stop` with a valid final reply in a user-started turn | Green |
| `PreToolUse` for `request_user_input` / `request_user_input_async` | Amber |
| `PermissionRequest` | Amber |
| A final reply ending in `?` / `？` | Amber |
| A final reply containing a complete, non-placeholder `<proposed_plan>…</proposed_plan>` | Blue-purple |

Startup events, empty replies, and replies containing only `/` do not trigger completion effects. While a question tool is still waiting for a response, an ordinary `Stop` does not show green. `PostToolUse` or a new user turn clears the pending state. Duplicate `Stop` events trigger only one notification per turn.

If `Stop.last_assistant_message` is empty, the program attempts to recover the final reply from `transcript_path`, matching both the session and turn. Being in Plan Mode alone does not mean a plan has been submitted. Codex hooks return `{}` and do not approve or reject tool calls.

## Uninstallation

```bash
./uninstall.sh        # Claude
./uninstall-codex.sh  # Codex
```

Uninstallation backs up the configuration, removes this client's Glow hooks, and deletes its `glow/` directory, including logs, state, and executable backups. Other hooks and settings are preserved. Configuration backups remain next to the configuration file. Start a new session afterward, as existing sessions may cache the old hooks.

## Logs and troubleshooting

```bash
tail -n 50 ~/.claude/glow/glow.log
tail -n 50 ~/.codex/glow/glow.log
```

- **Build fails:** check `swiftc --version` and confirm that a valid Xcode or Command Line Tools installation is installed and selected.
- **Previews work, but session events produce no effects:** check the Glow hook configuration and start a new session. In Codex, also check trust in `/hooks`.
- **Claude shows no effect:** switch to another app before triggering the event. Effects are suppressed while the Claude desktop app is in the foreground by default.
- **A Codex plan does not show purple:** inspect `classification` and `reason` in the log. A complete plan is required, either in the event or in a readable transcript with matching session and turn identities.
- **Configuration JSON is invalid:** installation stops and preserves the original file. Fix the JSON and run the installer again.

Codex logs distinguish event receipt, classification, process launch, window display, and playback completion. Claude's `shown` log entry means the program attempted to launch the animation process; it does not confirm that the animation was visible.

The project makes no network requests and includes no telemetry. Logs contain event names, tool names, and status information, without copying prompts, reply text, or tool arguments. Codex reads transcripts locally to recover final replies, and labels may display project directory names. Review logs before sharing them. Claude keeps roughly 300 log lines; Codex appends to its log, which you can clear as needed.

## Development and testing

```bash
make build  # Build build/claude-glow and build/codex-glow without installing hooks
make test   # Build both and run configuration and Codex hook regression tests without overlays
make clean  # Remove build/
```

To build one integration:

```bash
bash scripts/build.sh claude
bash scripts/build.sh codex
```

Tests use temporary directories. Codex regression tests set `CODEX_GLOW_HOME` and `CODEX_GLOW_DRY_RUN=1` to verify startup filtering, plan recovery, turn isolation, deduplication, and pending-question state without touching installed Codex state. Configuration tests cover preservation of mixed handlers, repeated installation, path quoting, backups, and invalid configurations.

These two environment variables affect only the Codex executable. Installation and uninstallation still use the default paths listed above. `Kind`, `GlowView`, `edgeIntensity`, and `sweep` in the Swift sources control colors, labels, timing, brightness, and animation. Rebuild or reinstall after changing them.

```text
ClaudeGlow.swift          Claude effects and event classification
CodexGlow.swift           Codex effects, event classification, and turn state
install*.sh              Installation entry points
uninstall*.sh            Uninstallation entry points
scripts/build.sh         Compilation and embedded LSUIElement metadata
scripts/manage.sh        Installation and uninstallation workflow
scripts/hooks.py         JSON configuration merging and backups
tests/                   Regression tests
.github/workflows/ci.yml macOS builds and tests
```

Automated tests do not verify real client event delivery or visual appearance. Before releasing, manually trigger all three effects in the target client and check focus, full-screen behavior, and multiple displays.

**AI disclosure:** This project's code and documentation were generated by AI coding agents under human direction.

## License

[MIT](LICENSE). This is an independent community project, unaffiliated with Anthropic or OpenAI.
