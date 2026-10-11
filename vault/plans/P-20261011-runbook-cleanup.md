---
id: P-20261011-runbook-cleanup
status: approved
---
# ゴール
D-20261011-user-guide フェーズ3（最終）：`docs/runbook.md` を「人が日々やること」に絞る。エージェントが内部でやること（transition.py・スキルの手順の中身など）の説明は、`docs/vault-spec.md` やスキルに同じ内容があれば runbook から削ってリンクに置き換え、runbook にしか無い内部仕様は `docs/vault-spec.md` に移す。環境変数の説明は `docs/configuration.md` へのリンクにする。古くなった記述（例：「`/run` は1件処理して報告」）を今の動作に直す。`docs/guide.md` のリンク先の節がずれたら直す。最後に決定事項を `docs/decisions.md` に取り出し、この設計文書を削除する。

## 分割方針
- 情報を失わないために、先に runbook にしか無い内部仕様を `docs/vault-spec.md` へ移し（T-01）、その後で runbook から削ってリンクに置き換える（T-02・T-03）。
- 今の runbook と `docs/vault-spec.md`・スキルを突き合わせた結果、runbook にしか無い内部仕様は2つだけだった：無人実行ラッパー `scripts/run_unattended.py` の動作（SIGTERM→10秒→SIGKILL・終了コード等）と、「困ったとき」の後の段落（作業ブランチ上の git の復旧と `permissions.deny` の範囲）。前者は vault-spec の新しい14節に、後者は12節の小見出しに移す。それ以外の内部の記述は vault-spec かスキルに同じ内容がある（各タスク票の「決定済み」に移し先を書いた）。
- runbook は同じファイルなので、前半（冒頭・0〜3節）と後半（4〜10節・困ったとき）に分けて直列にする（設計の決定済み「7タスクを超えそうなら前半・後半に分ける」に合わせ、1タスクの量を抑える）。
- runbook の `## ` 見出し（節番号と文言）は変えない。`docs/guide.md` の「詳しく」・`docs/configuration.md`・`docs/vault-spec.md` からの「runbook N節」の参照を壊さないため。`###` の小見出しは足してよい。
- T-04 で、runbook の整理で詳しい説明の場所が変わった参照（`docs/configuration.md` の「詳しく」列など）を直し、リポジトリ全体の runbook 参照を確かめる。`docs/install.md` は整理しないが、runbook の冒頭と同じ古い記述（「月次で片づける」）の1か所だけはそろえる。
- 最終フェーズなので、T-05 で設計文書の決定事項を `docs/decisions.md` に取り出し、設計文書を削除する。設計文書を読む全タスクの後に置く。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | doing | 1 | - | runbook にしか無い内部仕様を docs/vault-spec.md に移す | |
| T-02 | todo | 0 | T-01 | runbook の冒頭と0〜3節を人向けに整理する | |
| T-03 | todo | 0 | T-02 | runbook の4〜10節と「困ったとき」を人向けに整理する | |
| T-04 | todo | 0 | T-03 | runbook の整理に合わせて他の文書からの参照を直す | |
| T-05 | todo | 0 | T-01,T-02,T-03,T-04 | 決定事項を docs/decisions.md に取り出し設計文書を削除する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である
