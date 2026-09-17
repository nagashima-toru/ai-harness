# ai-harness

AI の作業を「作成 → 検証」の二段構成にし、検証が PASS しない限り完了できないようにする Claude Code 用ハーネス。
このリポジトリ自体が雛形であり、自分自身で動作確認する場でもある。

## 目的
- 作成エージェントの成果物を、別コンテキストの検証エージェント（verifier）が受け入れ基準に照らして採点し `verdict.json` を書く
- Stop フックが verdict を見て、PASS でなければ作業を終わらせない（リトライ上限あり、超過時は人へ引き継ぐ）
- エージェントが読む情報を `vault/` に集約し、開始時に読むものを小さく保つ
- 状態をすべてファイルに置き、セッションが切れても新セッションが続きから拾える

## セットアップ
前提：`claude`（Claude Code）、`git`、`python3` が使える。

```bash
# このリポジトリで試す
git clone git@github.com:nagashima-toru/ai-harness.git && cd ai-harness
bash scripts/smoke.sh        # フックの動作検証

# 開発プロジェクトに組み込む（.claude/ と vault/ と scripts/smoke.sh を複製）
bash scripts/install.sh /path/to/your-project
cd /path/to/your-project && claude   # 一度対話起動してフォルダを信頼する（settings.json の許可を有効にするため）
```

## 使い方
| コマンド | 何をするか |
|---|---|
| `/plan <ゴール>` | planner がゴールをタスクに分割して draft を作る。`/plan approve P-001` で承認し todo.md に登録 |
| `/run-queue` | todo.md の先頭タスクを1件処理する（作成 → verifier → done / 再試行 / blocked） |
| `claude -p "/run-queue"` | 同じことを無人（非対話）で行う |

- 人が日々やることは `docs/runbook.md`、Vault の仕様は `docs/vault-spec.md` を参照
- 無人で回す場合は `claude -p "/run-queue"` を cron や CI から定期実行する

## 拡張ポイント（ルール）
インストール先ごとの「ルール」（コーディングルール・開発標準・方式設計・テスト標準・テスト観点など）を、作成エージェント・verifier・planner に渡せる。ハーネス本体はルールを同梱しない。書くのはインストール先の仕事。

| ディレクトリ | 渡す相手 |
|---|---|
| `vault/rules/common/` | 全員（作成エージェント・verifier・planner） |
| `vault/rules/creator/` | 作成エージェントのみ |
| `vault/rules/verifier/` | verifier のみ |
| `vault/rules/planner/` | planner のみ |

- 読み込みは `bash scripts/rules.sh <creator|verifier|planner>` で一本化（`common/` → 役割ディレクトリの順、ファイル名順）
- 受け入れ基準からルールファイルを名指しして参照する（例：「`vault/rules/common/naming.md` の命名規則に従っている」）と、verifier がそのファイルを根拠に判定する
- `doing`/`review` 中のタスクがある間は `vault/rules/` を編集できない（`agent_write_guard.py` がフックで拒否する）

## 仕組み
```
 人                      作成エージェント（メイン）              verifier（別コンテキスト）
 │ /plan <ゴール>          │                                       │
 ├──────────────────────▶ planner が P-xxx / T-xxxx を draft      │
 │ /plan approve P-xxx     │                                       │
 ├──────────────────────▶ todo.md に登録（status=todo）            │
 │ /run-queue              │                                       │
 ├──────────────────────▶ todo→doing → 成果物を作る → review ──▶ 受け入れ基準を照合
 │                        │                                       │ verdicts/T-xxxx.json
 │                        │ ◀─────────────────────────────────────┘
 │                        │ PASS → done / FAIL → doing(attempt+1) / 上限 → blocked
 │                        ▼
 │               Stop フック（stop_gate.py）
 │               todo.md と verdict を照合し、整合しない終了をブロック
 │ blocked に答えて todo に戻す
 └──────────────────────▶ vault/todo.md（状態の正本）  vault/log/queue.md（追記ログ）
```

## 構成
```
.claude/   settings.json（hooks・許可）、agents/（verifier, planner）、hooks/、skills/（run-queue, plan）
vault/     todo.md（正本）、tasks/、plans/、verdicts/、log/queue.md、templates/、archive/、rules/（拡張ポイント。vault/rules/ 配下）
docs/      vault-spec.md（仕様の正本）、runbook.md、decisions.md
scripts/   smoke.sh（フック検証）、install.sh（他プロジェクトへ複製）、rules.sh（ルール解決）
```
