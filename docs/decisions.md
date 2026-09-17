# 既定値・判断の記録

構築中に採用した既定値と、その理由。1件1行。

| 日付 | 何を | なぜ |
|---|---|---|
| 2026-09-17 | リポジトリは個人アカウント `nagashima-toru` に private で作成 | 指示の既定値 |
| 2026-09-17 | verifier / planner の `model` は `sonnet` | 検証・計画は軽量モデルで十分、コスト削減（人の指示） |
| 2026-09-17 | 通し検証は `claude -p --model sonnet "/run-queue"` を子プロセスで実行 | 人の指示。無人運転の経路を本番と同じ形で確かめる |
| 2026-09-17 | エージェントの書き込み先制限は settings.json の PreToolUse フック（`agent_write_guard.py`）で実装 | agent 定義はツール単位の制限しかできない。frontmatter フックは `claude -p` で動かない（公式ドキュメント） |
| 2026-09-17 | verdict の `task` / `attempt` が todo.md と不一致なら「verdict 無し」扱い | 古い verdict で done にしないため（人の指示） |
| 2026-09-17 | doing と review が同時に存在した場合は todo.md の表で上にある1件で判定 | 仕様上は起きないので最小実装 |
| 2026-09-17 | 日時は `TZ=Asia/Tokyo date` で JST 固定 | マシンのタイムゾーンに依存させない |
| 2026-09-17 | `stop_hook_active` が真なら仕様どおり許可。`HARNESS_STRICT_STOP=1` で無視して判定を続ける（8回連続ブロックで Claude Code 側が打ち切る） | 仕様は許可だが、厳格運用の選択肢を残す |
| 2026-09-17 | 月次 archive はスクリプト化せず runbook の手順（`git mv`）のみ | scripts/ は smoke.sh と install.sh の2本という構成を守る |
| 2026-09-17 | 通し検証で生成した verdict / log / todo.md の変更はそのままコミット | 動作した証拠を残す |
| 2026-09-17 | フックの許可時は stdout に何も出さず exit 0 | 公式ドキュメント「decision を省略するか JSON 無しで exit 0」 |
| 2026-09-17 | `attempt` は「現在の試行回数」。todo→doing で 1、再試行で +1 | todo.md の初期値 0 と verdict の attempt=1 を整合させる |
| 2026-09-17 | `install.sh` は `.claude/` と `vault/` に加えて `scripts/smoke.sh`・`docs/vault-spec.md`・`CLAUDE.md` も複製する（既存ファイルは上書きしない） | 複製先で smoke.sh を通す必要があり、エージェントが vault-spec.md を参照するため |
| 2026-09-17 | 許可リストに `awk`・`sed`・`sort` 等のテキスト処理コマンドを追加 | 通し検証で verifier の確認コマンド（awk）が拒否されたため |
| 2026-09-17 | verifier の Bash 書き込み判定はリダイレクト・tee・rm/mv/cp・git 書き込み系・sed -i の簡易パターン | 通し検証で `/tmp` へのリダイレクトを正しく拒否した。厳密な OS レベル制限が要るなら sandbox を使う |
| 2026-09-17 | `sed -i` は許可リストに入るが verifier / planner ではガードが拒否する | メインエージェントの通常編集は許可しつつ、サブエージェントの越境書き込みは止める |
