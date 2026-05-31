#!/usr/bin/env bash
# install-hooks.sh — obsidian-ssot に ssot-guide 同期フックをインストールする
#
# 使い方: bash ~/projects/ssot-guide/scripts/install-hooks.sh

set -euo pipefail

SSOT_DIR="$HOME/projects/obsidian-ssot"
GUIDE_DIR="$HOME/projects/ssot-guide"
HOOK_FILE="$SSOT_DIR/.git/hooks/post-commit"

echo "📦 ssot-guide 同期フックをインストール中..."
echo "   対象: $HOOK_FILE"

# バックアップ
if [[ -f "$HOOK_FILE" ]]; then
    cp "$HOOK_FILE" "${HOOK_FILE}.backup"
    echo "   既存フックをバックアップ: ${HOOK_FILE}.backup"
fi

cat > "$HOOK_FILE" << HOOKEOF
#!/usr/bin/env bash
# post-commit hook: ssot-guide を自動同期
# インストール: bash ~/projects/ssot-guide/scripts/install-hooks.sh

GUIDE_SYNC="$GUIDE_DIR/scripts/sync-from-ssot.sh"

if [[ -f "\$GUIDE_SYNC" ]]; then
    # バックグラウンドで同期（コミットを遅延させない）
    bash "\$GUIDE_SYNC" >> "$HOME/.claude/logs/ssot-guide-sync.log" 2>&1 &
fi
HOOKEOF

chmod +x "$HOOK_FILE"
echo "✅ フックインストール完了: $HOOK_FILE"
echo ""
echo "次の obsidian-ssot コミット時に自動的に ssot-guide が同期されます"
echo "ログ: $HOME/.claude/logs/ssot-guide-sync.log"
