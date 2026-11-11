# Claude Glow / Codex Glow

用屏幕边缘光效提醒你：**任务完成、等待决定、方案就绪**。

A lightweight, native macOS screen-edge notification tool for Claude Code and Codex, written in Swift and AppKit.

[MIT License](LICENSE) · [贡献指南](CONTRIBUTING.md)

## 效果

| 状态 | 光效 | 标签 | 时长 |
|---|---|---|---|
| `done` | 绿色淡入、淡出 | ✓ 完成 · 项目名 | 2.0 秒 |
| `decision` | 琥珀色呼吸两次 | ? 等你决定 · 项目名 | 2.8 秒 |
| `plan` | 蓝紫色光带扫过顶边，再淡出 | ✦ 方案就绪 · 项目名 | 2.6 秒 |

- 鼠标穿透、不抢键盘焦点，不打断输入。
- 使用临时透明窗口绘制，不经过通知中心。
- 没有常驻守护进程；hook 负责分类，独立进程播放动画后退出。
- Claude 和 Codex 独立安装，可以同时使用。
- Claude 默认只在主屏幕显示，且 Claude 桌面 App 在前台时静默；Codex 在所有连接的屏幕上显示，也不因处于前台而静默。
- 界面标签目前为中文，可在 Swift 源码的 `Kind.title` 中修改。

## 环境要求

- macOS 图形桌面环境，依赖系统 AppKit；不支持 Linux、Windows 或无桌面的服务器。
- Swift 编译器：安装 Xcode Command Line Tools 或 Xcode。
- Python 3：用于合并 JSON hook 配置和运行测试，无第三方 Python 依赖。
- 对应客户端需支持本文列出的 hook 事件。不同客户端版本的 hook 覆盖范围可能不同。

```bash
xcode-select --install
swiftc --version
python3 --version
```

程序在本机编译为当前架构，不需要下载预编译二进制。当前本地构建验证环境为 Apple Silicon；GitHub Actions 使用 `macos-latest`。

## 安装

从本仓库的 GitHub 页面克隆仓库或下载 ZIP，解压并进入项目目录。按需执行：

```bash
# Claude Code（包括支持 Code hooks 的桌面端 Code 会话）
./install.sh

# Codex
./install-codex.sh
```

无需 `sudo`。安装脚本会先校验配置，再编译程序，并合并本项目的 hook；保留其他设置、同组内的其他 handler，以及另一个客户端的 hook。重复安装可更新程序和 hook，不重复添加条目。

| 客户端 | 二进制 | 修改的配置 | 状态与日志目录 |
|---|---|---|---|
| Claude | `~/.claude/glow/claude-glow` | `~/.claude/settings.json` | `~/.claude/glow/` |
| Codex | `~/.codex/glow/codex-glow` | `~/.codex/hooks.json` | `~/.codex/glow/` |

已有配置和二进制在更新前会生成带时间戳的 `.bak.*` 备份。安装后新建会话以加载 hook。

**Codex 还需要在 `/hooks` 中检查并信任更新后的定义。** 安装脚本不修改信任记录，也不修改 `config.toml`。客户端未提供事件、未信任 hook 或未加载配置时，程序不会收到提醒事件。

## 手动预览

```bash
~/.claude/glow/claude-glow show done "My Project"
~/.claude/glow/claude-glow show decision "My Project"
~/.claude/glow/claude-glow show plan "My Project"

~/.codex/glow/codex-glow show done "My Project"
~/.codex/glow/codex-glow show decision "My Project"
~/.codex/glow/codex-glow show plan "My Project"
```

`show` 直接播放动画，不受 Claude 前台静默规则影响。第三个参数为可选标签；由 hook 触发时，标签取事件 `cwd` 的最后一级目录名。

## 触发规则

### Claude Code

| 事件 | 行为 |
|---|---|
| `Stop` | 默认绿色；存在等待决定标记，或最后回复以 `?` / `？` 结尾时显示琥珀色 |
| `PreToolUse: AskUserQuestion` | 琥珀色 |
| `PreToolUse: ExitPlanMode` | 蓝紫色，并短暂抑制后续重复的方案审批通知 |
| `PreToolUse: mcp__ccd_turn__wrap_up` | 有 `ask` 时记录等待决定标记，供 `Stop` 使用 |
| `Notification` | 非 `idle_prompt` 通知显示琥珀色；方案后的重复通知除外 |

Claude 桌面 App 在前台时，hook 仍更新状态，但不播放动画。若需始终提醒，可在 `settings.json` 的 Glow hook 命令前添加 `CLAUDE_GLOW_ALWAYS=1`；重新安装会重置本项目的 hook 命令。

### Codex

安装以下事件：`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`PermissionRequest`、`Stop`。

| 条件 | 行为 |
|---|---|
| 用户轮次中有有效最终回复的普通 `Stop` | 绿色 |
| 提问工具 `request_user_input` / `request_user_input_async` 的 `PreToolUse` | 琥珀色 |
| `PermissionRequest` | 琥珀色 |
| 最终回复以 `?` / `？` 结尾 | 琥珀色 |
| 最终回复含完整、非占位的 `<proposed_plan>…</proposed_plan>` | 蓝紫色 |

启动事件、空回复、仅 `/` 的回复不会显示完成。提问工具尚未返回时，普通 `Stop` 不显示绿色；`PostToolUse` 或新用户轮次清除等待状态。同一轮的重复 `Stop` 只提醒一次。

若 `Stop.last_assistant_message` 为空，程序尝试从 `transcript_path` 读取相同会话、相同轮次的最终回复。处于 Plan Mode 本身不代表方案已提交。Codex hook 返回 `{}`，不批准或拒绝工具调用。

## 卸载

```bash
./uninstall.sh        # Claude
./uninstall-codex.sh  # Codex
```

卸载会先备份配置，再删除本客户端的 Glow hook，并删除对应 `glow/` 目录（含日志、状态和二进制备份）。其他 hook 与设置保留，配置备份保留在配置文件旁。已有会话可能缓存旧 hook，卸载后请新建会话。

## 日志与排障

```bash
tail -n 50 ~/.claude/glow/glow.log
tail -n 50 ~/.codex/glow/glow.log
```

- **编译失败**：检查 `swiftc --version`，确认已安装并选中有效的 Xcode / Command Line Tools。
- **预览正常，会话中没有提醒**：检查配置是否包含 Glow hook，并新建会话；Codex 还需检查 `/hooks` 信任状态。
- **Claude 没有光效**：切换到其他 App 后触发事件；默认会抑制 Claude 桌面 App 前台提醒。
- **Codex 方案未显示紫色**：检查日志中的 `classification` 和 `reason`；需要完整方案文本，或可读取且身份匹配的 transcript。
- **配置 JSON 损坏**：安装会停止并保留原文件；修正 JSON 后重新安装。

Codex 日志区分收到事件、分类、进程启动、窗口显示和播放结束。Claude 日志中的 `shown` 表示已尝试启动播放进程，不能单凭这一行确认动画可见。

本项目没有网络请求或遥测。日志包含事件、工具名和状态信息，不复制提示词、回复正文或工具参数。Codex 在本地读取 transcript 以恢复最终回复；标签可能显示项目目录名。分享日志前请自行检查内容。Claude 日志保留约 300 行，Codex 日志持续追加，可按需清理。

## 开发与测试

```bash
make build  # 构建 build/claude-glow 和 build/codex-glow，不安装 hook
make test   # 构建两者，运行配置测试和 Codex hook 回归测试，不播放光效
make clean  # 删除 build/
```

也可单独构建：

```bash
bash scripts/build.sh claude
bash scripts/build.sh codex
```

测试使用临时目录。Codex 回归测试设置 `CODEX_GLOW_HOME` 和 `CODEX_GLOW_DRY_RUN=1`，验证启动过滤、方案恢复、轮次隔离、去重和等待状态，不接触已安装的 Codex 状态。配置测试覆盖混合 handler 保留、重复安装、路径转义、备份及无效配置。

这两项环境变量仅影响 Codex 程序；安装、卸载仍使用上表的默认目录。Swift 源码中的 `Kind`、`GlowView`、`edgeIntensity` 和 `sweep` 控制颜色、标签、时长、亮度和动画。修改后重新构建或安装。

```text
ClaudeGlow.swift          Claude 光效和事件分类
CodexGlow.swift           Codex 光效、事件分类和轮次状态
install*.sh              安装入口
uninstall*.sh            卸载入口
scripts/build.sh         编译及嵌入 LSUIElement 元数据
scripts/manage.sh        安装、卸载流程
scripts/hooks.py         JSON 配置合并与备份
tests/                   回归测试
.github/workflows/ci.yml macOS 构建与测试
```

自动测试不验证真实客户端事件投递或窗口的视觉效果；发布前应在目标客户端手动触发三类提醒，并检查焦点、全屏及多显示器表现。

## 许可证

[MIT](LICENSE)。本项目为独立社区工具，与 Anthropic 或 OpenAI 无隶属关系。
