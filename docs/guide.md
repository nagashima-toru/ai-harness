# やりたいこと別ガイド

やりたいことから探すための入口です。ここには最小の例だけを載せ、手順の本文は「詳しく」のリンク先にあります。
環境変数の設定のしかた（`export`・`env 変数=値 …`・`.claude/settings.json` の `env`）は [`docs/configuration.md`](configuration.md) の「設定のしかた」を見てください。

## 初めて使う（インストールして最初の PR まで）

導入先にインストールして動作を確かめ、最初のゴールを入れます。PR ができたら、人が確認してマージします。

すること：
```bash
bash /path/to/ai-harness/scripts/install.sh /path/to/your-project
bash scripts/smoke.sh
/plan <ゴール>
```
詳しく：[`docs/install.md`](install.md) の「パターン1: まっさらな環境にインストールする」・[`docs/install.md`](install.md) の「パターン2: 既存リポジトリに追加する」・[`docs/install.md`](install.md) の「インストール後の次の一歩」・[`docs/runbook.md`](runbook.md) の「1. ゴールを入れる」

## 大きなゴールを設計してから進める

強いモデルのセッションで実行します。できた `vault/designs/D-<YYYYMMDD>-<スラッグ>.md` のフェーズのゴール文を、1つずつ `/plan` に渡します。

すること：
```text
/design <ゴール>
```
詳しく：[`docs/runbook.md`](runbook.md) の「0. 大きなゴールは先に設計する」

## main 以外のブランチをベースにする

`HARNESS_BASE_BRANCH` が未設定か空なら `main` です。

すること：
```json
"env": { "HARNESS_BASE_BRANCH": "develop" }
```
詳しく：[`docs/install.md`](install.md) の「main 以外のブランチをベースにする（任意）」・[`docs/configuration.md`](configuration.md) の「利用者が設定する変数」

## クラウドセッション（push 先が指定される環境）で使う

エージェントには `/plan <ゴール>` を打たせ、実行環境が指定した push 先のブランチ名を伝えます。`HARNESS_PUSH_BRANCH` が環境変数に無ければ、オーケストレーターが `env HARNESS_PUSH_BRANCH=<指定ブランチ> …` で `/plan`・`/design` の開始条件の確認と `vcs_finish.sh` に渡します。
`HARNESS_PUSH_BRANCH` で指定ブランチに push する場合、ローカルでは `work/<計画ID>` で作業し、push 先と PR の head が指定ブランチになります。実行環境が指定ブランチ以外への push を許すなら `HARNESS_PUSH_BRANCH` を設定せず、ベースブランチに切り替えてから `/plan` を打ちます（設定せず指定ブランチの上で `/plan` を打つと、開始条件を満たさず止まります。`.claude/skills/plan/SKILL.md` 手順2）。この場合、push 先と PR の head は `work/<計画ID>` になります。

すること：
```bash
env HARNESS_PUSH_BRANCH=<指定ブランチ> bash scripts/vcs_finish.sh
```
詳しく：[`docs/runbook.md`](runbook.md) の「10. push 先が決められている環境（クラウドセッション）」・[`docs/configuration.md`](configuration.md) の「利用者が設定する変数」

## 安いモデルで creator を回す

`HARNESS_CREATOR_MODEL` はセッションの起動時に設定します（起動後に変えたら起動し直す）。verifier・planner のモデルは変わりません。

すること：
```bash
HARNESS_CREATOR_MODEL=haiku claude
```
詳しく：[`docs/runbook.md`](runbook.md) の「8. creator のモデルを比べる」・[`docs/configuration.md`](configuration.md) の「利用者が設定する変数」

## 無人で回す

cron・CI から定期実行できます。`HARNESS_RUN_TIMEOUT` のほか `HARNESS_RUN_CMD`・`HARNESS_STRICT_STOP`（ラッパー経由では未設定なら `1`）も効きます。初回は対話で起動してフォルダを信頼しておきます。

すること：
```bash
python3 scripts/run_unattended.py
env HARNESS_RUN_TIMEOUT=7200 python3 scripts/run_unattended.py
```
詳しく：[`docs/runbook.md`](runbook.md) の「3. キューを回す」・[`docs/configuration.md`](configuration.md) の「利用者が設定する変数」

## blocked に答えて再開する

計画票のタスク表の `question` を読んでから答えます。1回で1行だけ解除されるので、続けて `/run` で再開します。

すること：
```text
/plan unblock <計画ID> <id> [回答]
```
詳しく：[`docs/runbook.md`](runbook.md) の「4. blocked に答えて戻す」

## 再試行の上限・並列数を変える

`HARNESS_MAX_ATTEMPTS` と `HARNESS_MAX_PARALLEL` はどちらも既定 `3` です。変えたらセッションを起動し直します。

すること：
```bash
export HARNESS_MAX_ATTEMPTS=5
export HARNESS_MAX_PARALLEL=1
```
詳しく：[`docs/configuration.md`](configuration.md) の「設定のしかた」・[`docs/configuration.md`](configuration.md) の「利用者が設定する変数」

## ルールを足す

受け入れ基準からルールファイルを名指しすると、verifier がそれを根拠に判定します。

すること：
```text
vault/rules/common/<名前>.md   全員に渡す
vault/rules/creator/<名前>.md  creator だけに渡す
```
詳しく：[`docs/runbook.md`](runbook.md) の「6. ルールを足す」

## ハーネスを更新する・取り外す

編集したファイルは上書き・削除されず、`skip (edited)` と報告されます。

すること：
```bash
bash /path/to/ai-harness/scripts/install.sh --update /path/to/your-project
bash scripts/uninstall.sh /path/to/your-project
```
詳しく：[`docs/install.md`](install.md) の「ハーネスを更新する（2回目以降）」・[`docs/install.md`](install.md) の「アンインストール」・[`docs/runbook.md`](runbook.md) の「7. ハーネス自体の更新を取り込む」

## マージ済みの計画を片づける

`--apply` は人だけが実行します。`--report` を見て Issue 化してから `--apply` し、作業用のブランチで実行してコミット・PR にします。

すること：
```bash
bash scripts/purge_plan.sh --merged --list
bash scripts/purge_plan.sh --merged --report
bash scripts/purge_plan.sh --merged --apply
```
詳しく：[`docs/runbook.md`](runbook.md) の「5. 一括削除の手順」
