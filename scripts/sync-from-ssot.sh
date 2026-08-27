#!/usr/bin/env bash
# sync-from-ssot.sh — obsidian-ssot の公開可能な情報を ssot-guide に反映する
#
# 使い方:
#   bash ~/projects/ssot-guide/scripts/sync-from-ssot.sh
#   bash ~/projects/ssot-guide/scripts/sync-from-ssot.sh --dry-run
#
# 2026-08-18 改修（マルチLLMレビュー反映・レビュー正典:
#   obsidian-ssot/00_SYSTEM/マルチLLMレビュー/2026-08-18_sync-from-ssot実行判断とスクリプト安全性レビュー/）:
#   C-1: git add -A をスコープ限定addへ変更 + 想定外の作業ツリー汚れで中断（並行セッション巻き込み防止）
#   C-2: セクションマーカーを共通変数化（grep「リポ一覧」≠実見出し「リポジトリ一覧」の不一致で
#        常時append分岐に入り見出しが二重化する潜在バグの修正）+ 二重化ガード
#   M-1: skip/実行/中断をJSON Linesログに記録（cron死活監視・REPO_TABLE成否観測=V-1）
#   M-2: dry-run/実行時に前回同期以降のobsidian-ssot commit一覧を表示（stale検知・取りこぼし可視化）
#   M-3: rev-parse HEAD 失敗時に unknown で「常時変更あり」誤判定させず中断
# 2026-08-28 追加（バックログL40・P1）:
#   F-1: flock排他 — durable cron は並行セッションが同一時刻に独立発火する
#        （08-22 3回・08-23 done×2・08-27 4回の実測）。両者が同時にhash判定を
#        通過すると同一内容のcommitが2本立つ（08-23実績）。先着1実行のみ継続し、
#        他は即skip（lockはプロセス終了で自動解除・ファイル残置は無害）。
#        LOCK_FILE/LOG_FILE は SYNC_LOCK_FILE/SYNC_LOG_FILE で上書き可能（テスト用）。

set -euo pipefail

SSOT_DIR="$HOME/projects/obsidian-ssot"
GUIDE_DIR="$HOME/projects/ssot-guide"
DRY_RUN=false
MARKER="公開リポジトリ一覧（自動更新）"
LOG_FILE="${SYNC_LOG_FILE:-$HOME/.claude/state/ssot-guide-sync.jsonl}"
LOCK_FILE="${SYNC_LOCK_FILE:-$HOME/.claude/state/ssot-guide-sync.lock}"
SOURCE_08_REL="source/08_プロジェクト紹介.md"

for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

MODE=$([[ "$DRY_RUN" == "true" ]] && echo dryrun || echo run)

# M-1: 構造化ログ（k=v 引数群をJSON 1行で追記）
log_json() {
    python3 - "$@" "$LOG_FILE" <<'PYEOF'
import json, sys, time, os
rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z")}
for kv in sys.argv[1:-1]:
    if "=" in kv:
        k, v = kv.split("=", 1)
        rec[k] = v
path = sys.argv[-1]
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
PYEOF
}

echo "🔄 SSOT → ssot-guide 同期開始 $(date '+%Y-%m-%d %H:%M:%S')"
[[ "$DRY_RUN" == "true" ]] && echo "   モード: DRY-RUN（ファイル書き込みなし）"

# --- F-1: flock排他（多重発火対策・先着1実行のみ継続） ---
mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "⏭️  他のsync-from-ssot実行中（flock排他）— スキップ"
    log_json "mode=$MODE" "action=skip" "reason=flock_busy"
    exit 0
fi

# --- 差分チェック（M-3: 取得失敗は中断・誤動作させない） ---
if ! SSOT_HASH=$(git -C "$SSOT_DIR" rev-parse HEAD 2>/dev/null); then
    echo "❌ obsidian-ssot の HEAD 取得失敗 — 中断" >&2
    log_json "mode=$MODE" "action=abort" "reason=rev_parse_fail"
    exit 1
fi
LAST_SYNC_FILE="$HOME/.claude/state/ssot-guide-last-sync"
LAST_SSOT_HASH=$(cat "$LAST_SYNC_FILE" 2>/dev/null || true)

# 本番実行のみスキップ（dry-runは常に続行して何が起きるか見せる）
if [[ "$SSOT_HASH" == "$LAST_SSOT_HASH" && "$DRY_RUN" == "false" ]]; then
    echo "✅ obsidian-ssot に変更なし（${SSOT_HASH:0:7}）— スキップ"
    log_json "mode=run" "action=skip" "reason=hash_match" "ssot_hash=${SSOT_HASH:0:7}"
    exit 0
fi

PREV="${LAST_SSOT_HASH:0:7}"
echo "📋 変更: ${PREV:-なし} → ${SSOT_HASH:0:7}"

# M-2: 前回同期以降のobsidian-ssot commit一覧（取りこぼし可視化）
if [[ -n "$LAST_SSOT_HASH" ]]; then
    echo "   前回同期以降の obsidian-ssot commit:"
    git -C "$SSOT_DIR" log --oneline "${LAST_SSOT_HASH}..${SSOT_HASH}" 2>/dev/null | head -10 | sed 's/^/     /' || true
fi

# --- リポジトリ索引から公開リポ一覧テーブルを生成（読み取りのみ）---
REPO_INDEX="$SSOT_DIR/00_SYSTEM/リポジトリ索引.md"

REPO_TABLE=""
if [[ -f "$REPO_INDEX" ]]; then
    REPO_TABLE=$(python3 - "$REPO_INDEX" <<'PYEOF'
import sys, re, pathlib

repo_index = pathlib.Path(sys.argv[1])
text = repo_index.read_text(encoding='utf-8')

repos = []
for line in text.split('\n'):
    if '🌐 public' in line and line.strip().startswith('|'):
        cells = [c.strip() for c in line.split('|') if c.strip()]
        if len(cells) >= 4:
            name = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', cells[0])
            status = cells[2] if len(cells) > 2 else ''
            desc = cells[3] if len(cells) > 3 else ''
            desc = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', desc)[:60]
            if name and status in ('active', 'development', 'maintenance'):
                repos.append((name, status, desc))

if not repos:
    sys.exit(0)

icon = {'active': '🟢', 'development': '🔵', 'maintenance': '🟡'}
print("| リポジトリ | ステータス | 説明 |")
print("|---|---|---|")
for name, status, desc in repos:
    print(f"| [{name}](https://github.com/fukukei23/{name}) | {icon.get(status,'⚪')} {status} | {desc} |")
PYEOF
    )
fi

# V-1観測: cron実行環境でのREPO_TABLE成否と言語環境を可視化
TABLE_ROWS=0
if [[ -n "$REPO_TABLE" ]]; then
    TABLE_ROWS=$(printf '%s\n' "$REPO_TABLE" | grep -c '^| \[' || true)
fi
echo "   REPO_TABLE: ${TABLE_ROWS}行（LANG=${LANG:-unset}）"

# --- DRY-RUNはここで終了（ファイルを一切書き換えない）---
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    if [[ -n "$REPO_TABLE" ]]; then
        echo "📋 DRY-RUN: source/08 の更新予定内容（先頭5行）:"
        echo "$REPO_TABLE" | head -5
    fi
    echo ""
    echo "✅ DRY-RUN完了: ファイルへの書き込みは行いませんでした"
    log_json "mode=dryrun" "action=preview" "ssot_hash=${SSOT_HASH:0:7}" "table_rows=$TABLE_ROWS" "lang=${LANG:-unset}"
    exit 0
fi

# --- ここから実際の変更（dry-runでは絶対に到達しない）---

# C-1: 想定外の作業ツリー汚れがあれば中断（docs/・VERSION・source/ 以外の変更は巻き込み対象）
cd "$GUIDE_DIR"
UNEXPECTED=$(git status --porcelain | awk '$2 !~ /^docs\// && $2 != "VERSION" && $2 !~ /^source\//' || true)
if [[ -n "$UNEXPECTED" ]]; then
    echo "⚠️  ssot-guide に想定外の作業ツリー変更あり — 巻き込み防止のため中断:" >&2
    printf '%s\n' "$UNEXPECTED" | sed 's/^/     /' >&2
    log_json "mode=run" "action=abort" "reason=dirty_tree" "ssot_hash=${SSOT_HASH:0:7}" "table_rows=$TABLE_ROWS"
    exit 1
fi

# source/08 を更新（C-2: MARKER共通化 + 二重化ガード）
if [[ -n "$REPO_TABLE" ]]; then
    MARKER_COUNT=$(grep -c "^## ${MARKER}" "$SOURCE_08_REL" 2>/dev/null || true)
    MARKER_COUNT=${MARKER_COUNT:-0}
    if [[ "$MARKER_COUNT" -ge 2 ]]; then
        echo "❌ セクション見出しが既に${MARKER_COUNT}重化 — 中断（手動修复が必要）" >&2
        log_json "mode=run" "action=abort" "reason=marker_duplicated" "count=$MARKER_COUNT"
        exit 1
    elif [[ "$MARKER_COUNT" -eq 1 ]]; then
        python3 - "$SOURCE_08_REL" "$MARKER" "$REPO_TABLE" <<'PYEOF'
import re, pathlib, sys

src = pathlib.Path(sys.argv[1])
marker = sys.argv[2]
new_table = sys.argv[3]
text = src.read_text(encoding='utf-8')
pattern = re.escape(f'## {marker}') + r'\n\n.*?(?=\n## |\Z)'
replacement = f'## {marker}\n\n{new_table}'
updated = re.sub(pattern, replacement, text, flags=re.DOTALL)
src.write_text(updated, encoding='utf-8')
PYEOF
    else
        printf "\n\n## %s\n\n%s\n" "$MARKER" "$REPO_TABLE" >> "$SOURCE_08_REL"
    fi
    echo "📋 ${SOURCE_08_REL} を更新"
fi

# --- HTML再生成 ---
echo ""
echo "🔨 HTML再生成..."
python3 convert.py

# --- git commit & push（C-1: スコープ限定add + stage内容ログ） ---
echo "📋 stage 内容:"
git add VERSION docs "$SOURCE_08_REL"
git diff --cached --name-status | sed 's/^/     /'
if git diff --cached --quiet; then
    echo "ℹ️  変更なし — コミットスキップ"
    log_json "mode=run" "action=no_commit" "ssot_hash=${SSOT_HASH:0:7}" "table_rows=$TABLE_ROWS" "lang=${LANG:-unset}"
else
    git commit -m "sync: obsidian-ssot ${SSOT_HASH:0:7} → ssot-guide"
    git push
    echo "✅ プッシュ完了"
fi

# 同期済みハッシュを記録（リポ外のstateディレクトリに保存）
mkdir -p "$(dirname "$LAST_SYNC_FILE")"
echo "$SSOT_HASH" > "$LAST_SYNC_FILE"
log_json "mode=run" "action=done" "ssot_hash=${SSOT_HASH:0:7}" "table_rows=$TABLE_ROWS" "lang=${LANG:-unset}"
echo ""
echo "✅ 同期完了 $(date '+%Y-%m-%d %H:%M:%S')"
