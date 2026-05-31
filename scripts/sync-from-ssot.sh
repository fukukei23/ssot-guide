#!/usr/bin/env bash
# sync-from-ssot.sh — obsidian-ssot の公開可能な情報を ssot-guide に反映する
#
# 使い方:
#   bash ~/projects/ssot-guide/scripts/sync-from-ssot.sh
#   bash ~/projects/ssot-guide/scripts/sync-from-ssot.sh --dry-run

set -euo pipefail

SSOT_DIR="$HOME/projects/obsidian-ssot"
GUIDE_DIR="$HOME/projects/ssot-guide"
DRY_RUN=false

for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

echo "🔄 SSOT → ssot-guide 同期開始 $(date '+%Y-%m-%d %H:%M:%S')"
[[ "$DRY_RUN" == "true" ]] && echo "   モード: DRY-RUN（ファイル書き込みなし）"

# --- 差分チェック ---
SSOT_HASH=$(git -C "$SSOT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
LAST_SYNC_FILE="$HOME/.claude/state/ssot-guide-last-sync"
LAST_SSOT_HASH=$(cat "$LAST_SYNC_FILE" 2>/dev/null || echo "")

# 本番実行のみスキップ（dry-runは常に続行して何が起きるか見せる）
if [[ "$SSOT_HASH" == "$LAST_SSOT_HASH" && "$DRY_RUN" == "false" ]]; then
    echo "✅ obsidian-ssot に変更なし（${SSOT_HASH:0:7}）— スキップ"
    exit 0
fi

PREV="${LAST_SSOT_HASH:0:7}"
echo "📋 変更: ${PREV:-なし} → ${SSOT_HASH:0:7}"

# --- リポジトリ索引から公開リポ一覧テーブルを生成（読み取りのみ）---
REPO_INDEX="$SSOT_DIR/00_SYSTEM/リポジトリ索引.md"
SOURCE_08="$GUIDE_DIR/source/08_プロジェクト紹介.md"

REPO_TABLE=""
if [[ -f "$REPO_INDEX" ]]; then
    REPO_TABLE=$(python3 - "$REPO_INDEX" <<'PYEOF'
import sys, re, pathlib

repo_index = pathlib.Path(sys.argv[1])
text = repo_index.read_text(encoding='utf-8')

repos = []
for line in text.split('\n'):
    if '| 公開 |' in line and line.strip().startswith('|'):
        cells = [c.strip() for c in line.split('|') if c.strip()]
        if len(cells) >= 5:
            name = cells[0]
            status = cells[3] if len(cells) > 3 else ''
            desc = cells[4] if len(cells) > 4 else ''
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

# --- DRY-RUNはここで終了（ファイルを一切書き換えない）---
if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    if [[ -n "$REPO_TABLE" ]]; then
        echo "📋 DRY-RUN: source/08 の更新予定内容（先頭5行）:"
        echo "$REPO_TABLE" | head -5
    fi
    echo ""
    echo "✅ DRY-RUN完了: ファイルへの書き込みは行いませんでした"
    exit 0
fi

# --- ここから実際の変更（dry-runでは絶対に到達しない）---

# source/08 を更新
if [[ -n "$REPO_TABLE" ]]; then
    if grep -q "公開リポジトリ一覧（自動更新）" "$SOURCE_08" 2>/dev/null; then
        python3 - "$SOURCE_08" "$REPO_TABLE" <<'PYEOF'
import sys, re, pathlib

src = pathlib.Path(sys.argv[1])
new_table = sys.argv[2]
text = src.read_text(encoding='utf-8')
pattern = r'## 公開リポジトリ一覧（自動更新）\n\n.*?(?=\n## |\Z)'
replacement = f'## 公開リポジトリ一覧（自動更新）\n\n{new_table}'
updated = re.sub(pattern, replacement, text, flags=re.DOTALL)
src.write_text(updated, encoding='utf-8')
PYEOF
    else
        printf "\n\n## 公開リポジトリ一覧（自動更新）\n\n%s\n" "$REPO_TABLE" >> "$SOURCE_08"
    fi
    echo "📋 source/08_プロジェクト紹介.md を更新"
fi

# --- HTML再生成 ---
echo ""
echo "🔨 HTML再生成..."
cd "$GUIDE_DIR"
python3 convert.py

# --- git commit & push ---
git add -A
if git diff --cached --quiet; then
    echo "ℹ️  変更なし — コミットスキップ"
else
    git commit -m "sync: obsidian-ssot ${SSOT_HASH:0:7} → ssot-guide"
    git push
    echo "✅ プッシュ完了"
fi

# 同期済みハッシュを記録（リポ外のstateディレクトリに保存）
mkdir -p "$(dirname "$LAST_SYNC_FILE")"
echo "$SSOT_HASH" > "$LAST_SYNC_FILE"
echo ""
echo "✅ 同期完了 $(date '+%Y-%m-%d %H:%M:%S')"
