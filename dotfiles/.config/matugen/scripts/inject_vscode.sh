#!/usr/bin/env bash
# matugen -> VS Code 颜色注入
# 设计要点:
#   - settings.json 为空 / 非法 JSON / JSONC(带注释) 都能兜底, 不再整体失败
#   - 每次注入前备份, 保留最近 N 份, 出问题可回滚
#   - 只接管颜色相关 key, 个人设置原样保留
set -uo pipefail

VSCODE_SETTINGS="${VSCODE_SETTINGS:-$HOME/.config/Code/User/settings.json}"
GENERATED_COLORS="${GENERATED_COLORS:-$HOME/.cache/matugen_vscode_inject.json}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.cache/matugen/vscode-backups}"
KEEP_BACKUPS="${KEEP_BACKUPS:-10}"

log()  { printf '[inject_vscode] %s\n' "$*"; }
fail() { printf '[inject_vscode] ❌ %s\n' "$*" >&2; exit 1; }

# 0. 前置检查
command -v jq >/dev/null 2>&1 || fail "缺少 jq"
pacman -Qq visual-studio-code-bin >/dev/null 2>&1 \
  || pacman -Qq code >/dev/null 2>&1 \
  || { log "未安装 VS Code, 跳过"; exit 0; }
[ -s "$GENERATED_COLORS" ] || fail "颜色文件缺失或为空: $GENERATED_COLORS"
jq -e . "$GENERATED_COLORS" >/dev/null 2>&1 || fail "颜色文件不是合法 JSON: $GENERATED_COLORS"

mkdir -p "$(dirname "$VSCODE_SETTINGS")" "$BACKUP_DIR"

# 1. 读取现有 settings, 逐级降级兜底
#    a) 合法 JSON -> 直接用
#    b) JSONC(注释/尾逗号) -> python 清洗后再试
#    c) 空文件 / 彻底解析不了 -> 用 {} , 并把原文件另存为 .broken 保命
base_json=""
if [ -s "$VSCODE_SETTINGS" ]; then
    if base_json=$(jq -e . "$VSCODE_SETTINGS" 2>/dev/null); then
        :
    elif base_json=$(python3 - "$VSCODE_SETTINGS" <<'PY' 2>/dev/null
import json, re, sys
raw = open(sys.argv[1], encoding='utf-8').read()
# 去掉 // 与 /* */ 注释(跳过字符串内部), 再去尾逗号
out, i, n = [], 0, len(raw)
while i < n:
    c = raw[i]
    if c == '"':
        j = i + 1
        while j < n:
            if raw[j] == '\\': j += 2; continue
            if raw[j] == '"': break
            j += 1
        out.append(raw[i:j+1]); i = j + 1
    elif raw.startswith('//', i):
        i = raw.find('\n', i);  i = n if i == -1 else i
    elif raw.startswith('/*', i):
        j = raw.find('*/', i); i = n if j == -1 else j + 2
    else:
        out.append(c); i += 1
cleaned = re.sub(r',(\s*[}\]])', r'\1', ''.join(out))
json.dump(json.loads(cleaned), sys.stdout)
PY
    ); then
        log "⚠ settings.json 是 JSONC(含注释), 已清洗解析 —— 注意注释会在写回时丢失"
    else
        base_json='{}'
        cp -a "$VSCODE_SETTINGS" "$BACKUP_DIR/settings-broken-$(date +%Y%m%d-%H%M%S).json"
        log "⚠ settings.json 无法解析, 已另存到 $BACKUP_DIR, 本次以空配置为基底"
    fi
else
    base_json='{}'
    [ -e "$VSCODE_SETTINGS" ] && log "⚠ settings.json 为空文件, 以空配置为基底"
fi

# 2. 备份 + 轮转
if [ -s "$VSCODE_SETTINGS" ]; then
    cp -a "$VSCODE_SETTINGS" "$BACKUP_DIR/settings-$(date +%Y%m%d-%H%M%S).json"
    ls -1t "$BACKUP_DIR"/settings-2*.json 2>/dev/null \
      | tail -n +$((KEEP_BACKUPS + 1)) | xargs -r rm -f
fi

# 3. 合并: 个人设置保留, 颜色 key 由 matugen 覆盖
tmp=$(mktemp "${VSCODE_SETTINGS}.XXXXXX") || fail "mktemp 失败"
trap 'rm -f "$tmp"' EXIT
if printf '%s' "$base_json" \
   | jq -s --slurpfile colors "$GENERATED_COLORS" '.[0] * $colors[0]' > "$tmp" \
   && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    cat "$tmp" > "$VSCODE_SETTINGS"      # 保留原 inode/权限, 避免 VS Code 丢监听
    log "✅ VS Code 颜色已更新"
else
    fail "合并失败, settings.json 未改动"
fi
