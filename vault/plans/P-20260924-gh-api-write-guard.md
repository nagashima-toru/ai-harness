---
id: P-20260924-gh-api-write-guard
status: approved
---
# ゴール
`.claude/hooks/agent_write_guard.py` の `BASH_WRITE_PATTERNS`（`targets_vault_rules` が Bash 呼び出しに対して発火するかどうかを決めるパターン一覧）は、`rm`/`mv`/`cp`/`tee`/リダイレクト/`git ...`/`sed -i` 系のコマンド文字列にしか一致しない。`gh api -X PUT repos/<owner>/<repo>/contents/vault/rules/...` のように GitHub Contents API を直接叩けば、これらのパターンのどれにも一致せず `targets_vault_rules` の検査自体が呼ばれないため、`vault/rules/` への書き込み拒否（D-002 で導入した不変条件）をすり抜けられる（issue #6）。curl で GitHub API を直接叩く経路も同様の抜け穴になる。この計画では、`gh api` と GitHub API への直接 `curl` を新たに「リモート書き込みになり得るコマンド」として検知対象に加え、`docs/vault-spec.md` にその検知範囲と残存リスクを明記する。

## 分割方針
- issue #6 が挙げた3方向のうち、この計画は方向1（`gh api` 等をパターンに追加）と方向3（`curl` 等の直接 API 呼び出しも対象にする）を組み合わせた「拒否リスト方式の拡張」を採る。方向2（許可リスト方式への全面移行）は Bash 呼び出し全体の権限モデルを変える大きな設計変更であり、1計画5〜7タスク・1タスク1〜2時間の粒度に収まらないため、この計画のスコープ外とする（詳細は「人への質問」）。
- T-01（実装）：`targets_vault_rules` の Bash 分岐に `gh api` / GitHub API への直接 `curl` の検知を追加するコード変更と、対応する `scripts/smoke.sh` のケース追加は密結合（ケースを直さないと検知の正しさを確認できない）なので1タスクにまとめる（`P-20260924-rules-guard`/T-01 の前例に倣う）。
- T-02（仕様書、T-01 の後）：`docs/vault-spec.md` 第12節に、Bash 経由の検知範囲が `gh api`・GitHub API への直接 `curl` を含むことと、拒否リスト方式である以上コマンド経路を完全には列挙できないという残存リスクを明記する。実装が先に固まった方が、仕様書に書く関数名・挙動の記述がぶれない。
- `.claude/hooks/agent_write_guard.py` と `docs/vault-spec.md` はいずれも `vault/rules/` の外なので、提案ファイル方式（`vault/tasks/<計画ID>/<id>-proposal.md`）は使わず、実パスを直接編集する成果物にする。
- 2タスクとも成果物ファイルが異なり、T-02 は T-01 の実装内容を前提にするため `after: T-01` とする。循環はない。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | agent_write_guard.py に gh api / curl 経由の GitHub Contents API 直叩き検知を追加する | |
| T-02 | done | 1 | T-01 | vault-spec.md 12節に gh api / curl の検知範囲と残存リスクを明記する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
- `gh api -X PUT repos/<owner>/<repo>/contents/vault/rules/...` 相当の Bash コマンドが `agent_write_guard.py` によって拒否されることが `scripts/smoke.sh` で機械的に確認できる

## 人への質問
- issue #6 の検討方向2（拒否リスト方式から許可リスト方式への全面移行）はこの計画に含めていません。Bash 呼び出し全体の権限モデルを変える設計変更になるため、別途 `/design` でフェーズ分割を検討する想定でよいですか。それとも今回の拒否リスト拡張だけで一旦クローズしてよいですか。
- `gh repo edit`・`gh workflow` 等、リポジトリ設定を変更する `gh` サブコマンドは対象外としました（`vault/rules/` 配下ファイルの中身を直接書き換える経路ではないため）。この判断でよいですか。
