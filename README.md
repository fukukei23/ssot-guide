# ssot-guide

> AIと人間が協働するためのSSOT知識管理システム設計・運用ガイド

[![GitHub Pages](https://img.shields.io/badge/GitHub%20Pages-live-green)](https://fukukei23.github.io/ssot-guide/) [![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## 概要

**SSOT（Single Source of Truth）** を使ったAI協働開発の知識管理ノウハウをまとめたガイドサイトです。

Claude Code等のAIエージェントと長期的に協働するための：
- ディレクトリ設計（vault構造）
- LLMルーティング設計
- Hooks・CLAUDE.md統合
- 自律開発ループ
- 記録・ドキュメント管理

を実践的に解説します。

---

## サイト構成

| 章 | タイトル | 内容 |
|---|---|---|
| 00 | 概要 | SSOTとは・設計の3原則 |
| 01 | ディレクトリ設計 | vault階層構造・MOC・チャーター |
| 02 | LLMルーティング | 複数LLMの使い分け・ローカルプロキシ |
| 03 | Claude Code統合 | CLAUDE.md・Hooks・Memoryシステム |
| 04 | 自律開発ループ | Cron連動・自律実装・完了通知 |
| 05 | 記録・ドキュメント | 決定ログ・日記・MOC |
| 06 | 開発手法カタログ | TDD・BDD・DDD等のレシピ |
| 07 | キャリア戦略 | AIネイティブ開発者の戦略 |
| 08 | プロジェクト紹介 | 公開リポジトリ一覧 |

---

## 技術スタック

- 静的HTML（依存ゼロ）
- Tokyo Night テーマ（ダークモード対応）
- Markdown → HTML変換スクリプト（Python）
- GitHub Pages ホスティング

---

## ローカル確認

```bash
git clone https://github.com/fukukei23/ssot-guide
cd ssot-guide
python3 -m http.server 8080 --directory docs
# → http://localhost:8080 で確認
```

## コンテンツ更新

```bash
# 1. source/*.md を編集
# 2. HTMLを再生成
python3 convert.py

# 3. コミット & プッシュ
git add -A && git commit -m "docs: update content"
git push
```

---

## 関連リポジトリ

- [claude-code-guide](https://github.com/fukukei23/claude-code-guide) — Claude Code CLI 完全ガイド
- [guides](https://github.com/fukukei23/guides) — 開発者向けクイックリファレンス集（50冊）
- [obsidian-ssot](https://github.com/fukukei23/obsidian-ssot) — 知識ベース（非公開）
