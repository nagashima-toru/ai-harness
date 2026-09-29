---
id: P-20260929-done-guard-git-staging
status: approved
---
# ゴール
`.claude/hooks/agent_write_guard.py` の done タスク書き込み拒否判定（`find_done_task_write` / `plan_task_status`、P-20260927-done-write-guard で追加）が、`.claude/skills/run/SKILL.md` 手順6.3.4 の done 遷移手順（計画票のタスク表を done に更新 → log 追記 → 計画票・log・`vault/verdicts/<計画ID>/<id>.json` を `git add` → コミット）と衝突している問題を、フック側で解消する（issue #84）。

計画票を done にした後の `git add vault/verdicts/<計画ID>/<id>.json` が、done 判定（計画票のディスク上の内容を見る）で拒否され、全計画の全タスクの done 遷移で毎回起きる。人と合意した方針は次のとおり。

- **Bash コマンドの書き込み動詞が `git add` / `git commit` だけの場合は、done 判定の対象外にする**。ステージ・コミットはファイル内容を変えず、内容の改変（Write/Edit/リダイレクト/`cp`/`mv`/`rm`/`sed -i`/`tee`/`git rm` など）は従来どおり done 判定で拒否する
- `agent_type` では判定しない（メインセッションでも creator でも同じ挙動）
- `git add ... && echo x > <done verdict>` のように他の書き込み動詞が混ざる場合は従来どおり拒否する（すり抜けを作らない）
- `.claude/skills/run/SKILL.md` の手順は変更しない（手順の並べ替えは採らない）。`.claude/ai-harness.md` も変更しない

## 分割方針
- T-01（`agent_write_guard.py` の実装 + `scripts/smoke.sh` の回帰テスト追加）を先に切る。実装とその回帰テストは関連する2ファイルの1PR分の変更として1タスクにまとめる（P-20260927-done-write-guard/T-01 と同じ扱い）。判定の実装位置・混在時の扱い・commit メッセージ中のパス文字列の扱いはこのタスクで確定する
- T-02（`docs/vault-spec.md` 12節の done 判定の行に「`git add` / `git commit` のみのコマンドは対象外」を足す）は、T-01 の実装した挙動を正確に記述する必要があるため T-01 に `after` で依存させる
- 2タスクとも成果物が特定でき、粒度基準（1計画5〜7タスク以内）に収まる。次フェーズの候補は無い

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | review | 1 | - | agent_write_guard.py の done 判定から git add / git commit のみのコマンドを除外し smoke.sh にテストを足す | |
| T-02 | todo | 0 | T-01 | vault-spec.md 12節の done 判定の行に git add / git commit のみは対象外である旨を足す | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 人への質問
- なし（判断が必要だった次の2点は、既定を決めてタスク票の「決定済み」に書いた。違う方針が良ければ承認前に指示してください）
  - `git -C <dir> add ...` や `git add` に `2>&1` を付けた形など、`git` 直後が `add`/`commit` でない・リダイレクト風トークンを含む形は除外の対象にしない（従来どおり判定する＝拒否側に倒れる）。run/SKILL.md 手順6.3.4 が実際に使う形（メインリポジトリで `git add <パス>...`、`git commit -m "..."`）だけを除外すれば issue #84 は解消するため
  - commit メッセージ中に done のパス文字列（例：`vault/verdicts/<計画ID>/<id>.json`）が書かれていても、引用符内の文字列は書き込み対象とみなさず許可する
