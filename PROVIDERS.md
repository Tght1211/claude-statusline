# 第三方供应商插件规范 (Provider Plugin Spec)

claude-statusline 默认从 Anthropic 官方 OAuth 接口读取 5h / 7d 用量。当你把 Claude Code
接到**第三方 Anthropic 供应商**时，官方接口不再适用 —— statusline 会自动隐藏 5h / 7d，
并尝试加载一个 **provider 插件** 来展示该供应商自己的用量配额。

第一行（模型 / 上下文 / 本次会话 $ / 用时）和「今日 $ / 词元」始终保留，与供应商无关。

## 1. 何时进入第三方模式

statusline 通过环境变量 `ANTHROPIC_BASE_URL` 判断：

- 未设置，或包含 `anthropic.com` → **官方模式**，行为不变。
- 设置成其它地址 → **第三方模式**，隐藏 5h / 7d，加载 provider 插件。
- 设置 `STATUSLINE_PROVIDER=<id>` 可强制使用指定插件（无视 base URL）。

`ANTHROPIC_BASE_URL` 既可来自 shell 环境，也可来自 `~/.claude/settings.json` 的 `env` 字段。

## 2. 插件目录结构

每个插件是 `~/.claude/statusline/providers/<id>/` 下的一个目录：

```
~/.claude/statusline/providers/
  <id>/
    manifest.json          # 必填，插件元数据
    fetch.sh               # 必填，拉取用量并输出 JSON
    config.example.json    # 建议，凭据模板
    config.json            # 可选，用户真实凭据（不进 git，不默认导出）
```

`<id>` 目录名必须与 `manifest.json` 里的 `id` 一致。

## 3. manifest.json

```json
{
  "id": "idealab-mo",
  "name": "MO计划 (IdeaLab)",
  "version": "1.0.0",
  "description": "一句话说明这个供应商",
  "match": ["idealab.alibaba-inc.com", "idealab"],
  "cacheTtl": 120,
  "fetch": "fetch.sh"
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 唯一标识，小写短横线；须等于目录名 |
| `name` | 是 | 展示名 |
| `version` | 是 | 语义化版本 |
| `description` | 否 | 简介 |
| `match` | 是 | 字符串数组；任一项作为子串命中 `ANTHROPIC_BASE_URL` 即选用该插件 |
| `cacheTtl` | 否 | 插件输出缓存秒数，默认 `120` |
| `fetch` | 否 | 拉取脚本文件名，默认 `fetch.sh` |

## 4. fetch.sh 契约

statusline 会按 `cacheTtl` 节流调用 `fetch.sh`（多个终端面板共享缓存、有防并发锁）。

**输入：**

- 标准输入：Claude Code 注入的 status JSON（与 statusline 收到的相同）。
- 环境变量：
  - `STATUSLINE_PROVIDER_DIR` — 插件自身目录的绝对路径
  - `STATUSLINE_PROVIDER_CONFIG` — `config.json` 的绝对路径（文件不一定存在）
  - `STATUSLINE_PROVIDER_BASE` — 当前的 `ANTHROPIC_BASE_URL`

**输出：** 向标准输出打印**一个 JSON 对象**，二选一：

成功 —— 一组用量分段：

```json
{
  "segments": [
    { "label": "次数", "used": 89,     "limit": 4000 },
    { "label": "额度", "used": 45.028, "limit": 1200, "unit": "¥", "decimals": 2 }
  ]
}
```

失败 —— 一条错误信息（会以暗色显示在第二行）：

```json
{ "error": "MO计划: 登录态失效，请更新 cookie" }
```

`segment` 字段：

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `label` | 是 | 短标签，如 `次数` / `额度` |
| `used` | 是 | 已用量，数字 |
| `limit` | 否 | 上限；省略或为 0 时只显示 `used`，不画进度条 |
| `unit` | 否 | 单位符号，如 `¥` `$`；默认空 |
| `unitPos` | 否 | `prefix`（默认）或 `suffix`，单位放数字前/后 |
| `decimals` | 否 | 小数位数，默认 `0` |

每个 segment 渲染为 `标签 进度条 百分比% 已用/上限`，进度条按阈值分段着色，
与 5h / 7d 完全一致。

**约定：**

- 永远输出合法 JSON，**不要**非零退出来表达业务错误 —— 用 `{"error":...}`。
- 网络请求务必设 `--max-time`；statusline 另有 12s 硬超时。
- 不要自己做缓存或 sleep，节流由 statusline 负责。
- 凭据只从 `config.json` 读取，不要硬编码进 `fetch.sh`。

## 5. 开发与调试

```bash
# 校验并试跑插件，美化打印其输出
statusline-provider test <id>

# 列出已安装插件
statusline-provider list
```

也可手动跑：

```bash
STATUSLINE_PROVIDER_DIR=~/.claude/statusline/providers/<id> \
STATUSLINE_PROVIDER_CONFIG=~/.claude/statusline/providers/<id>/config.json \
bash ~/.claude/statusline/providers/<id>/fetch.sh <<< '{}' | jq .
```

## 6. 导入 / 导出（分享给同事）

插件是自包含目录，可打包分享：

```bash
# 导出（默认不含 config.json 凭据）
statusline-provider export <id>
statusline-provider export <id> mo.tgz --with-secrets   # 连凭据一起导出

# 导入
statusline-provider import mo.statusline-provider.tgz
```

导入会校验 manifest 合法性；若本地已存在同名插件，会保留你原有的 `config.json`。

## 7. 参考实现

`providers/idealab-mo/` 是阿里 IdeaLab「MO计划」的完整参考实现，可直接照搬改造：
复制整个目录、改 `manifest.json` 的 `id` / `match`、把 `fetch.sh` 换成你的供应商接口即可。
