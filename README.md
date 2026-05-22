# claude-statusline

为 [Claude Code](https://github.com/anthropics/claude-code) 定制的两行 statusline，一眼看到模型、上下文、会话/今日费用、5h 和 7d 用量。

## 效果

```
Opus 4.7 | 93k/1m (9%) | 本次 $3.34 | 用时 32m
5h ██░░░░░░░░ 22% ↻2h30m | 7d ░░░░░░░░░░ 1% ↻6d5h | 今日 $56.38 / 20.3m 词元
```

- 第一行：**模型** | **上下文 used/total (pct%)** | **本次会话花费** | **本次会话用时**
- 第二行：**5h 进度条 + 重置倒计时** | **7d 进度条 + 重置倒计时** | **今日总花费 / 今日总词元数**

- `↻` 后面是配额重置剩余时间，格式 `45m` / `2h30m` / `6d5h`
- "用时" 单位是分钟（如 `32m`）；"词元" 数量按百万缩写（如 `20.3m`）

进度条**按格分段着色**：≤50% 段绿、50-70% 段黄、70-90% 段橙、>90% 段红，未填充格 dim 灰。例如 95% 用量看起来是 `█████ ██ ██ █ ░`（绿绿绿绿绿 / 黄黄 / 橙橙 / 红 / 空），一眼就能看出已经踩进红区。百分比数字也按整体阶梯换色（绿→黄→橙→红）。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/Tght1211/claude-statusline/main/install.sh | bash
```

执行完 **重启 Claude Code** 即可。

安装脚本会：
1. 把 `statusline.sh` 放到 `~/.claude/statusline/`
2. 用 `jq` 更新 `~/.claude/settings.json` 的 `statusLine` 字段（保留你的其他配置）

## 第三方 Anthropic 供应商

把 Claude Code 接到第三方供应商（设置了 `ANTHROPIC_BASE_URL`）时，官方的 5h / 7d
用量接口不再适用。此时 statusline 会**自动隐藏 5h / 7d**，第一行和「今日 $ / 词元」
照常保留：

```
Opus 4.7 1M | 0/1m (0%) | 本次 $0.00 | 用时 0s
次数 ░░░░░░░░░░ 2% 89/4000 | 额度 ░░░░░░░░░░ 3% ¥45.03/¥1200 | 今日 $53.62 / 21.4m 词元
```

第二行的供应商用量来自**可插拔的 provider 插件**。仓库内置了阿里 IdeaLab「MO计划」
的参考实现（`providers/idealab-mo/`）。接入其它供应商：自己写一个插件本地导入即可，
开发规范见 [`PROVIDERS.md`](./PROVIDERS.md)，也可让 Claude Code 用 `statusline-provider`
skill 帮你脚手架。

管理插件：

```bash
statusline-provider list                       # 列出已安装插件
statusline-provider test <id>                  # 试跑并校验某插件
statusline-provider export <id> [--with-secrets]  # 导出分享
statusline-provider import <bundle.tgz>        # 导入同事的插件
```

启用 MO计划：复制 `~/.claude/statusline/providers/idealab-mo/config.example.json`
为 `config.json`，把浏览器对 `idealab.alibaba-inc.com` 的 Cookie 整段粘进去即可。

## 依赖

- `bash`、`jq`、`curl`（macOS 上 `curl` 自带，`jq` 用 `brew install jq` 安装）
- Claude Code 已登录（官方 5h / 7d 数据由 Claude Code 注入到 statusline，仅 Pro/Max 订阅可见）

## 显示内容来源

| 字段 | 来源 |
| --- | --- |
| 模型 / 上下文 | Claude Code 注入的 status JSON (`model.display_name`, `context_window`) |
| 会话 $ / 时长 | `cost.total_cost_usd`, `cost.total_duration_ms` |
| 5h / 7d 用量 | `rate_limits.five_hour`, `rate_limits.seven_day`（首次 API 请求后才会出现；第三方供应商下隐藏） |
| 第三方供应商用量 | provider 插件 `~/.claude/statusline/providers/<id>/fetch.sh` 的输出，按 `cacheTtl` 缓存 |
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
