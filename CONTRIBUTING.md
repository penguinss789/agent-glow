# Contributing

[English](CONTRIBUTING.md) · [简体中文](CONTRIBUTING.zh-CN.md)

Report bugs through GitHub Issues or submit a pull request.

## Reporting bugs

Include your macOS version, CPU architecture, client and version, triggering event, expected and actual behavior, and relevant logs with private information removed. Do not upload complete session transcripts, personal configurations, tokens, or private project content.

## Making and verifying changes

1. Keep Claude and Codex installations independent, and preserve unrelated hooks and user settings.
2. Add regression cases when changing event classification or configuration merging.
3. Run `make test` on macOS.
4. For animation or client integration changes, also manually verify all three effects, keyboard focus, and click-through behavior. Distinguish automated test results from manual verification in your PR.

Building and testing do not require changes to your real `~/.claude` or `~/.codex` configuration. Do not commit local backups, logs, build artifacts, or client configurations.

Keep the [English](README.md) and [Simplified Chinese](README.zh-CN.md) documentation consistent when documenting behavior changes.

By submitting a contribution, you agree to make it available under this project's MIT license.
