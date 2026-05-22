---
name: statusline-provider
description: 为 claude-statusline 开发第三方 Anthropic 供应商插件（provider plugin），用于在状态栏展示该供应商自己的用量配额。当用户想接入新的第三方供应商、让 statusline 显示某供应商的次数/额度/配额，或提到 provider 插件、ANTHROPIC_BASE_URL 第三方供应商、statusline 用量时触发。
---

# 开发 claude-statusline 第三方供应商插件

帮助用户为 [claude-statusline](https://github.com/Tght1211/claude-statusline) 接入一个新的
第三方 Anthropic 供应商，使状态栏第二行展示该供应商的用量配额（次数 / 金额 / 等）。

完整规范见仓库根目录的 `PROVIDERS.md`，本 skill 是其操作化流程。

## 触发场景

- 「帮我接入 XXX 供应商的用量」「让 statusline 显示我在 XXX 的配额」
- 用户给出某供应商的用量查询接口（curl / API 文档）
- 提到 provider 插件、第三方供应商状态栏

## 一个插件 = 一个目录

```
~/.claude/statusline/providers/<id>/
  manifest.json          # 元数据 + 匹配规则
  fetch.sh               # 拉用量 → 输出 JSON
  config.example.json    # 凭据模板
  config.json            # 用户真实凭据（勿提交、勿默认导出）
```

## 开发流程

1. **确认接口**：先和用户拿到该供应商「查用量」的真实请求（curl 优先）。
   实际调用一次，确认响应里哪些字段是「已用量 / 上限」。不要凭猜测写字段名。

2. **选 id**：小写短横线，如 `idealab-mo`、`openrouter`。目录名必须 == manifest 的 `id`。

3. **写 manifest.json**：
   - `match` 填能命中该供应商 `ANTHROPIC_BASE_URL` 的子串数组。
   - `cacheTtl` 一般 120（秒）。

4. **写 fetch.sh** —— 严格遵守契约：
   - 从 `$STATUSLINE_PROVIDER_CONFIG`（config.json）读凭据，**不要硬编码**。
   - 请求带 `--max-time`。
   - 成功输出 `{"segments":[{"label":..,"used":..,"limit":..}]}`。
   - 失败输出 `{"error":"一句话原因"}`，并**正常退出**（不要靠非零退出码报错）。
   - 不要自己缓存 / sleep，节流由 statusline 负责。

5. **写 config.example.json**：列出所需凭据字段，附获取方式注释。

6. **本地校验**：`statusline-provider test <id>`，确认输出是合法 JSON 且无 error。

7. **参考实现**：仓库 `providers/idealab-mo/` 是完整可照搬的样例。

## segment 字段速查

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `label` | 是 | 短标签（次数 / 额度…） |
| `used` | 是 | 已用量，数字 |
| `limit` | 否 | 上限；省略则只显示 used，不画进度条 |
| `unit` | 否 | 单位符号（¥ / $） |
| `unitPos` | 否 | `prefix`(默认) / `suffix` |
| `decimals` | 否 | 小数位，默认 0 |

## fetch.sh 骨架

```bash
#!/bin/bash
set -f
config="${STATUSLINE_PROVIDER_CONFIG:-$STATUSLINE_PROVIDER_DIR/config.json}"
err() { jq -cn --arg m "$1" '{error:$m}'; exit 0; }

[ -f "$config" ] || err "未配置 config.json"
token=$(jq -r '.token // empty' "$config") || true
[ -n "$token" ] || err "config.json 缺少 token"

resp=$(curl -s --max-time 10 -H "Authorization: Bearer $token" \
  'https://供应商/usage/endpoint' 2>/dev/null)
[ -n "$resp" ] || err "请求无响应"

echo "$resp" | jq -c '{
  segments: [
    { label: "次数", used: (.calls_used // 0), limit: (.calls_limit // 0) }
  ]
}'
```

## 分享给同事

```bash
statusline-provider export <id>                 # 不含凭据
statusline-provider export <id> x.tgz --with-secrets
statusline-provider import x.statusline-provider.tgz
```

## 收尾

写完后告诉用户：
- 需把 `ANTHROPIC_BASE_URL` 设为能被 `match` 命中的地址（或设 `STATUSLINE_PROVIDER=<id>`）。
- 复制 `config.example.json` 为 `config.json` 并填凭据。
- 重启 Claude Code 查看效果。
