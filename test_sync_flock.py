"""sync-from-ssot.sh の flock 排他テスト（2026-08-28・バックログL40）.

durable cron は並行セッションが同一時刻に独立発火する（08-22 3回・08-27 4回の実測）。
両者が同時に hash 判定を通過すると同一内容の commit が2本立つ（08-23 実績）。
先着1実行のみ継続し、他は即 skip（reason=flock_busy）することを検証する。

テストは dry-run / ロック競合のみで検証し、git commit・push 系は踏まない。
LOCK_FILE / LOG_FILE は env（SYNC_LOCK_FILE / SYNC_LOG_FILE）で一時パスに上書きし、
実運用の state を汚さない。
"""

import json
import os
import pathlib
import fcntl
import subprocess

SCRIPT = pathlib.Path(__file__).resolve().parent / "scripts" / "sync-from-ssot.sh"


def _run_script(lock_path: str, log_path: str) -> subprocess.CompletedProcess:
    """スクリプトを dry-run で実行し、lock/log を一時パスに向ける."""
    env = dict(os.environ)
    env["SYNC_LOCK_FILE"] = lock_path
    env["SYNC_LOG_FILE"] = log_path
    return subprocess.run(
        ["bash", str(SCRIPT), "--dry-run"],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )


def test_flock_held_second_instance_skips(tmp_path):
    """他インスタンスがロック保持中は即 exit 0 + flock_busy ログ（08-23重複commitの再現封じ）."""
    lock = tmp_path / "sync.lock"
    log = tmp_path / "sync.jsonl"

    with open(lock, "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            proc = _run_script(str(lock), str(log))
        finally:
            fcntl.flock(fh, fcntl.LOCK_UN)

    assert proc.returncode == 0, f"stderr: {proc.stderr}"
    assert "flock排他" in proc.stdout
    # ログに skip/flock_busy が1行記録されている
    lines = log.read_text().strip().splitlines()
    assert len(lines) >= 1
    rec = json.loads(lines[-1])
    assert rec["action"] == "skip"
    assert rec["reason"] == "flock_busy"


def test_lock_released_next_instance_proceeds(tmp_path):
    """ロック解放後は次の実行が通常経路へ（dry-run なので書き込みなしで完了）."""
    lock = tmp_path / "sync.lock"
    log = tmp_path / "sync.jsonl"

    # 一度ロックを取って即解放（lockファイル存在下での通常実行）
    with open(lock, "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(fh, fcntl.LOCK_UN)

    proc = _run_script(str(lock), str(log))

    assert proc.returncode == 0, f"stderr: {proc.stderr}"
    assert "flock排他" not in proc.stdout
    assert "DRY-RUN" in proc.stdout
    lines = log.read_text().strip().splitlines()
    assert lines, "dry-run 完了ログが記録されていること"
    rec = json.loads(lines[-1])
    assert rec["action"] == "preview"


def test_lock_file_leftover_is_harmless(tmp_path):
    """lockファイルが残置していてもロック保持がいなければ通常実行される（自己解放の確認）."""
    lock = tmp_path / "sync.lock"
    log = tmp_path / "sync.jsonl"
    lock.write_text("")  # 前回実行の残置を模擬（中身は空・ロックは誰も保持していない）

    proc = _run_script(str(lock), str(log))

    assert proc.returncode == 0, f"stderr: {proc.stderr}"
    assert "flock排他" not in proc.stdout
