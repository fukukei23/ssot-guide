# 03 Claude Code統合 — SSOTをClaude Codeと接続する

> CLAUDE.md・settings.json・Hooksを使ってSSOTをAIの「長期記憶」にする

---

## 3層設定アーキテクチャ

```
Layer 1: グローバル設定
~/.claude/CLAUDE.md          ← 全プロジェクト共通のルール
~/.claude/settings.json      ← Hooks・権限・環境変数

Layer 2: プロジェクト設定
<repo>/CLAUDE.md             ← このプロジェクト固有のルール

Layer 3: ディレクトリ設定
<repo>/<dir>/CLAUDE.md       ← 特定ディレクトリのルール（必要時のみ）
```

**重要**: 下位レイヤーが上位レイヤーを上書きする（Layer 3 > Layer 2 > Layer 1）

---

## CLAUDE.mdの設計

### グローバルCLAUDE.mdに書くべきこと

```markdown
# グローバル設定

## 基本ルール
- 日本語で回答する
- コードは変更前に既存実装を理解してから変更する

## LLM利用ポリシー
- デフォルト: Sonnet（バランス型）
- 大量処理: Haiku に自動委譲

## セキュリティ
- APIキー値を会話・ファイルに書き込まない
- 詳細: ~/projects/ssot/security-policy.md

## SSOT参照
- 設計哲学: ~/projects/ssot/00_SYSTEM/チャーター.md
- ルール: ~/projects/ssot/00_SYSTEM/共通ルール/ルール.md
```

### プロジェクトCLAUDE.mdに書くべきこと

```markdown
# プロジェクトA固有設定

## 技術スタック
- Python 3.12 + FastAPI
- PostgreSQL（Supabase）
- テスト: pytest

## ブランチ運用
- main直接コミット
- PRは外部公開機能のみ

## 禁止事項
- `rm -rf` 系コマンド
- 本番DBへの直接接続
```

---

## Hooks設計

4種のHookでClaude Codeを自動化：

| Hook | タイミング | 用途 |
|---|---|---|
| `PreToolUse` | ツール実行前 | 危険コマンドのブロック |
| `PostToolUse` | ツール実行後 | ログ記録・通知 |
| `SessionStart` | セッション開始時 | 前回引継ぎ・バックログ表示 |
| `Stop` | セッション終了時 | 日記の自動更新 |

### PreToolUseで危険コマンドをブロック

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "python3 ~/.claude/scripts/check-command-safety.py"
      }]
    }]
  }
}
```

```python
# check-command-safety.py（概念）
import json, sys

BLOCKED = ["rm -rf", "DROP TABLE", "git push --force", "sudo"]

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")

for pattern in BLOCKED:
    if pattern in cmd:
        print(json.dumps({"decision": "block", "reason": f"危険コマンド: {pattern}"}))
        sys.exit(0)

print(json.dumps({"decision": "allow"}))
```

### SessionStartで前回引継ぎを表示

```bash
#!/bin/bash
# session-start.sh

# 最新の引継ぎファイルを表示
HANDOFF="$HOME/.claude/state/handoff.md"
if [ -f "$HANDOFF" ]; then
    echo "=== 前回の引継ぎ ==="
    cat "$HANDOFF"
    echo ""
fi

# 今日の日付と作業カウント
echo "📅 $(date +%Y-%m-%d) | セッション開始"
```

### Stopでセッション終了を記録

```bash
#!/bin/bash
# session-stop.sh

DAILY_DIR="$HOME/projects/ssot/10_DAILY"
TODAY=$(date +%Y-%m-%d)
DAILY_FILE="$DAILY_DIR/$TODAY.md"

# 終了時刻を記録
echo "" >> "$DAILY_FILE"
echo "---" >> "$DAILY_FILE"
echo "セッション終了: $(date +%H:%M)" >> "$DAILY_FILE"
```

---

## Memoryシステム

Claude Codeには4種のメモリタイプがある：

```
~/.claude/projects/<project-hash>/memory/
├── user_role.md          ← ユーザーの役割・専門知識
├── feedback_*.md         ← 過去の指摘・好みのパターン
├── project_*.md          ← 現在進行中のタスク・決定
└── MEMORY.md             ← メモリインデックス（自動ロード）
```

| タイプ | 内容 | 更新タイミング |
|---|---|---|
| `user` | 役割・知識レベル・好み | 初回セッション時 |
| `feedback` | 指摘された問題・確認された方法 | 修正指示があった時 |
| `project` | 現在の意思決定・背景 | プロジェクトの方針変更時 |
| `reference` | 外部システムの場所 | 参照先が決まった時 |

---

## SSOT + Claude Code の統合フロー

```
セッション開始
    ↓
SessionStart Hook
    ├── 前回handoff.md を表示
    ├── バックログを確認
    └── INDEX drift警告を出力
    ↓
作業中
    ├── CLAUDE.md のルールに従って実装
    ├── 決定ファイルを 01_DECISIONS/ に作成
    └── git commit時に自動でSSOT記録を要求
    ↓
セッション終了
    ├── Stop Hook が日記に終了時刻を記録
    └── handoff.md を更新（次のセッションへ）
```

---

## settings.jsonテンプレート

```json
{
  "defaultMode": "acceptEdits",
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:8787"
  },
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(python3 *)",
      "Bash(npm *)"
    ],
    "deny": [
      "Bash(rm -rf *)",
      "Bash(sudo *)"
    ]
  },
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{"type": "command", "command": "~/.claude/scripts/check-safety.sh"}]
    }],
    "SessionStart": [{"type": "command", "command": "~/.claude/scripts/session-start.sh"}],
    "Stop": [{"type": "command", "command": "~/.claude/scripts/session-stop.sh"}]
  }
}
```

---

## スキル管理体系

Claude Codeのスキル（~/.claude/skills/）を管理し、SSOTとの同期を確保する。

### 既存スキル一覧

| スキル名 | トリガー | 用途 |
|---|---|---|
| **ssot-record** | 「記録して」「保存して」等 | SSOTへの記録・振り分けの自動化 |
| **ssot-search** | 「SSOTから探して」等 | SSOT内を検索 |
| **ssot-sync** | 「SSOT整合性チェックして」「整理して」等 | SSOTと実態の乖離をチェック・修正 |
| **teian** | 「提案して」「どう思う」等 | 軽量提案（brainstormingへの誘導も） |
| **record-decision** | 「判断を記録して」等 | 技術決定の記録 |
| **update-guide** | 「/update-guide」 | ガイドサイトの更新キュー処理 |

### ssot-sync スキル（整合性チェック）

**トリガーワード**:
- 「SSOT整合性チェックして」「SSOT整理して」「SSOT同期して」
- 「SSOTのズレを直して」「00_SYSTEM更新して」「乖離を修正して」
- `/ssot-sync`

**チェック対象**:
- `00_SYSTEM/自動化.md` — hooks/cron/スクリプトの記載漏れ
- `00_SYSTEM/repo-index.yaml` — リポジトリ数・visibility・last_updated
- `00_SYSTEM/MCPツール使い分けガイド.md` — 有効サーバー数
- `00_SYSTEM/全体マップ_MOC.md` — リポジトリ数・プロジェクト一覧
- `00_SYSTEM/チャーター.md` — 禁止操作リスト

### スキル追加時のルール

新しいスキルを ~/.claude/skills/ に作成した時は:

1. **01_DECISIONS/claude-code/_INDEX.md** に記録
2. **ssot-guide** のこのセクションに追記
3. 自動化関連なら **00_SYSTEM/自動化.md** も更新

### ssot-record と ssot-sync の使い分け

| 状況 | スキル |
|---|---|
| 作業内容を記録したい | `ssot-record`（「記録して」） |
| SSOTの情報が古いか確認したい | `ssot-sync`（「SSOT整理して」） |
| SSOTから情報を探したい | `ssot-search`（「SSOTから探して」） |
