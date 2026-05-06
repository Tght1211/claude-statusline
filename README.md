# claude-statusline

为 [Claude Code](https://github.com/anthropics/claude-code) 定制的两行 statusline，一眼看到模型、上下文、会话/今日费用、5h 和 7d 用量。

## 效果

```
Opus 4.7 | 93k/1m (9%) | $3.34 | 32m
5h ██░░░░░░░░ 22% ↻2h30m | 7d ░░░░░░░░░░ 1% ↻6d5h | $46.93 | 16m
```

- 第一行：**模型** | **上下文 used/total (pct%)** | **当前会话花费 $** | **当前会话时长**
- 第二行：**5h 进度条 + 重置倒计时** | **7d 进度条 + 重置倒计时** | **今日总花费 $** | **今日总 tokens**

`↻` 后面是距离配额重置的剩余时间，常见格式：`45m`、`2h30m`、`6d5h`。

进度条按用量阶梯换色：绿（<50%）→ 黄（≥50%）→ 橙（≥70%）→ 红（≥90%）。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Tght1211/claude-statusline/main/install.sh | bash
```

执行完 **重启 Claude Code** 即可。

安装脚本会：
1. 把 `statusline.sh` 放到 `~/.claude/statusline/`
2. 用 `jq` 更新 `~/.claude/settings.json` 的 `statusLine` 字段（保留你的其他配置）

## 依赖

- `bash`、`jq`、`curl`（macOS 上 `curl` 自带，`jq` 用 `brew install jq` 安装）
- Claude Code 已登录（5h / 7d 数据由 Claude Code 注入到 statusline，仅 Pro/Max 订阅可见）

## 显示内容来源

| 字段 | 来源 |
| --- | --- |
| 模型 / 上下文 | Claude Code 注入的 status JSON (`model.display_name`, `context_window`) |
| 会话 $ / 时长 | `cost.total_cost_usd`, `cost.total_duration_ms` |
| 5h / 7d 用量 | `rate_limits.five_hour`, `rate_limits.seven_day`（首次 API 请求后才会出现） |
| 今日 $ / tokens | 聚合 `~/.claude/projects/*/*.jsonl` 中今日 assistant 消息，按模型分别套用 Opus / Sonnet / Haiku 单价计算，缓存 60 秒 |

## 手动安装

```bash
git clone https://github.com/Tght1211/claude-statusline.git ~/.claude/statusline-repo
cp ~/.claude/statusline-repo/statusline.sh ~/.claude/statusline/statusline.sh
chmod +x ~/.claude/statusline/statusline.sh
```

然后在 `~/.claude/settings.json` 中加入：
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline/statusline.sh",
    "padding": 0
  }
}
```

## 更新

```bash
curl -fsSL https://raw.githubusercontent.com/Tght1211/claude-statusline/main/install.sh | bash
```

重新跑一次安装命令即可（会覆盖 `statusline.sh`，不影响你 settings.json 里的其他字段）。

## 卸载

把 `~/.claude/settings.json` 里的 `statusLine` 字段去掉或改回原来的命令，删除 `~/.claude/statusline/` 目录即可。

## 鸣谢

基于 [daniel3303/ClaudeCodeStatusLine](https://github.com/daniel3303/ClaudeCodeStatusLine) 修改。原作者实现了核心的速率限制读取、缓存、跨平台 OAuth 取 token、版本检查等逻辑。本仓库只是改了显示形式（两行布局、进度条、去掉 cwd、加上会话/今日费用聚合）。详见 [`NOTICE`](./NOTICE)。
