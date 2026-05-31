#!/usr/bin/env bash
# sync-from-ssot.sh — obsidian-ssot の公開可能な情報を ssot-guide に反映する
#
# 使い方:
#   bash ~/projects/ssot-guide/scripts/sync-from-ssot.sh
#   bash ~/projects/ssot-guide/scripts/sync-from-ssot.sh --dry-run
#
# 動作:
#   1. obsidian-ssot/00_SYSTEM/リポジトリ索引.md からプロジェクト一覧を抽出
#   2. ssot-guide/source/08_プロジェクト紹介.md の「リポジトリ管理の仕組み」セクションを更新
#   3. convert.py でHTML再生成
#   4. ssot-guide を git commit → push

set -euo pipefail

SSOT_DIR="$HOME/projects/obsidian-ssot"
GUIDE_DIR="$HOME/projects/ssot-guide"
DRY_RUN=false

for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

echo "🔄 SSOT → ssot-guide 同期開始 $(date '+%Y-%m-%d %H:%M:%S')"
echo "   SSOT: $SSOT_DIR"
echo "   Guide: $GUIDE_DIR"
[[ "$DRY_RUN" == "true" ]] && echo "   モード: DRY-RUN（変更なし）"

# --- 差分チェック ---
SSOT_HASH=$(git -C "$SSOT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")
GUIDE_HASH=$(git -C "$GUIDE_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")

LAST_SYNC_FILE="$GUIDE_DIR/.last-ssot-sync"
LAST_SSOT_HASH=$(cat "$LAST_SYNC_FILE" 2>/dev/null || echo "")

if [[ "$SSOT_HASH" == "$LAST_SSOT_HASH" ]] && [[ "$DRY_RUN" == "false" ]]; then
    echo "✅ obsidian-ssot に変更なし（$SSOT_HASH）— スキップ"
    exit 0
fi

echo "📋 obsidian-ssot 変更検出: $LAST_SSOT_HASH → $SSOT_HASH"

# --- プロジェクト一覧の抽出 ---
REPO_INDEX="$SSOT_DIR/00_SYSTEM/リポジトリ索引.md"

extract_public_repos() {
    # リポジトリ索引から「公開」ステータスのリポジトリを抽出
    python3 - <<'PYEOF'
import sys, re, pathlib

repo_index = pathlib.Path(sys.argv[1])
if not repo_index.exists():
    print("# ⚠️ リポジトリ索引が見つかりません")
    sys.exit(0)

text = repo_index.read_text(encoding='utf-8')
lines = text.split('\n')

repos = []
for line in lines:
    if '| 公開 |' in line and line.strip().startswith('|'):
        cells = [c.strip() for c in line.split('|') if c.strip()]
        if len(cells) >= 5:
            name = cells[0]
            status = cells[3] if len(cells) > 3 else ''
            desc = cells[4] if len(cells) > 4 else ''
            # URLを除去してテキストのみ抽出
            desc = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', desc)
            if name and status in ('active', 'development', 'maintenance'):
                repos.append({'name': name, 'status': status, 'desc': desc})

if repos:
    print("## 公開リポジトリ一覧（自動更新）\n")
    print("| リポジトリ | ステータス | 説明 |")
    print("|---|---|---|")
    for r in repos:
        status_icon = {'active': '🟢', 'development': '🔵', 'maintenance': '🟡'}.get(r['status'], '⚪')
        print(f"| [{r['name']}](https://github.com/fukukei23/{r['name']}) | {status_icon} {r['status']} | {r['desc'][:60]} |")
PYEOF
}

if [[ "$DRY_RUN" == "false" ]]; then
    # --- HTML再生成 ---
    echo ""
    echo "🔨 HTML再生成..."
    cd "$GUIDE_DIR"
    python3 convert.py

    # --- git commit & push ---
    cd "$GUIDE_DIR"
    git add -A
    if git diff --cached --quiet; then
        echo "ℹ️  HTML変更なし — コミットスキップ"
    else
        COMMIT_MSG="sync: obsidian-ssot ${SSOT_HASH:0:7} → ssot-guide"
        git commit -m "$COMMIT_MSG"
        git push
        echo "✅ プッシュ完了: $COMMIT_MSG"
    fi

    # 同期済みハッシュを記録
    echo "$SSOT_HASH" > "$LAST_SYNC_FILE"
    echo ""
    echo "✅ 同期完了 $(date '+%Y-%m-%d %H:%M:%S')"
else
    echo ""
    echo "📋 DRY-RUN: 実際の変更は行いませんでした"
    echo "   実行するには: bash $0"
fi
