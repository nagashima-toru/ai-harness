## 目的
planner / creator（run の作成エージェント）/ verifier の間で、誰の出力が誰の入力になるかを定める。
状態遷移・計画票のタスク表の列構成・各ファイルの形式は `docs/vault-spec.md` を正本とし、ここでは繰り返さない。

## ルール

### 人 → planner
- 人が渡すのはゴール（と、あれば `vault/designs/D-xxx.md`）。planner はそれ以外を要求として補わない。
- planner の出力が人の承認を受けて初めて計画票（`vault/plans/<計画ID>.md`）の `status` が `approved` になる。承認前の draft を creator は取らない。

### planner → creator
- 渡すのは `vault/tasks/<id>.md` の6見出しだけ。タスク票に書かれていないことは、計画票や会話ではなく「決定済み」に追記されるまで存在しないものとして扱う。
- creator は「決定済み」を人の回答として最優先する。そこに答えが無い判断が出たら、自分で決めず status を `blocked` にして question に書く。
- 受け入れ基準は creator が満たすべき契約であると同時に verifier の判定項目そのもの。creator は基準を読み替えない・増減させない。

### creator → verifier
- 渡すのは成果物と、タスク票の受け入れ基準に併記された確認コマンドだけ。verifier の呼び出しにはタスク ID 以外を書かない。
- 作業の経緯・苦労・言い訳・「ここは基準を満たせなかったが実質同じ」といった説明を渡さない。
- verifier はタスク票の「進捗」や creator の説明文を判定の根拠にしない。根拠にできるのは成果物のファイルと自分で実行したコマンドの出力だけ。

### verifier → creator / 人
- 渡すのは `vault/verdicts/<id>.json` の `result` / `reasons` / `criteria[].note` だけ。verdict ファイルが唯一の判定結果で、返答文は控えに過ぎない。
- creator は verifier の返答文ではなく verdict ファイルを読んで次の行動（done / attempt+1 / blocked）を決める。
- FAIL の時、creator が修正の手がかりにできるのは `reasons` と該当する `criteria[].note`。そこに書かれていない不満は無かったものとして扱う。
- `attempt` が計画票のタスク表と一致しない verdict は受け取らない（古い結果で done にしない）。

### creator → 人
- 渡すのは `blocked` にした行の question 1つ。question は人が1回で答えられる形にし、判断待ちの間に推測で作業を進めない。

## 確認方法
- verdict の `criteria[].note` に、成果物のパスと実行したコマンド・出力だけが書かれているか。creator の説明を引き写した note は受け渡し違反。
- `blocked` の question が、タスク票の「決定済み」に無い事項について書かれているか。既に答えがあるのに聞いていないか。
- FAIL 後の修正が `reasons` に対応しているか。`reasons` に無い箇所まで書き換えていないか。
- タスク票の「決定済み」に、会話でしか決まっていない事項が残っていないか（残っていれば planner → creator の受け渡しが漏れている）。
