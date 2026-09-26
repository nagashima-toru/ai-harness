# ai-harness

AI の作業を「作成 → 検証」の二段構成にし、検証が PASS しない限り完了できないようにする Claude Code 用ハーネス。
このリポジトリ自体が雛形であり、自分自身で動作確認する場でもある。

## 目的
- 作成エージェントの成果物を、別コンテキストの検証エージェント（verifier）が受け入れ基準に照らして採点し `verdict.json` を書く
- Stop フックが verdict を見て、PASS でなければ作業を終わらせない（リトライ上限あり、超過時は人へ引き継ぐ）
- エージェントが読む情報を `vault/` に集約し、開始時に読むものを小さく保つ
- 状態をすべてファイルに置き、セッションが切れても新セッションが続きから拾える

ハーネス全体の目的・原則・非ゴールは [docs/vision.md](docs/vision.md) にまとめている。

## セットアップ
前提：`claude`（Claude Code）、`git`、`python3` が使える。

```bash
# このリポジトリで試す
git clone git@github.com:nagashima-toru/ai-harness.git && cd ai-harness
bash scripts/smoke.sh        # フックの動作検証
```

他のプロジェクトへ組み込む場合（まっさらな新規ディレクトリ／既存リポジトリのどちらでも）は `docs/install.md` を参照。組み込んだ後にハーネス側が更新されたら `bash scripts/install.sh --update <組み込み先>` で取り込む。未編集のファイルだけが最新化され、組み込み先で編集したファイルは `skip (edited)` として報告されるだけで上書きされない。

ハーネスのルール本文は `.claude/ai-harness.md` にあり、`CLAUDE.md` はそれを `@` で読み込むマーカー付きの4行ブロックだけを持つ。既存リポジトリに入れる時は `install.sh` がこのブロックだけを既存の `CLAUDE.md` にマージする（既存本文は残り、書き換え時は `CLAUDE.md.bak-<日時>` ができる）。`--no-claude-md` で抑止できる。

## 使い方
| コマンド | 何をするか |
|---|---|
| `/design <ゴール>` | 大きなゴールを調査し、人に質問し、決定事項を固めた設計文書 `vault/designs/D-xxx.md` を作る |
| `/plan <ゴール>` | 計画 ID を決めてブランチ（`work/<計画ID>`）を切り、planner がタスクに分割して draft を作る。`/plan approve <計画ID>` で承認 |
| `/run` | 自分のブランチの承認済み計画を1タスク処理する（作成 → verifier → done / 再試行 / blocked） |
| `claude -p "/run"` | 同じことを無人（非対話）で行う |

`/design` と `/plan` の使い分け：受け入れ基準が7行に収まらない・成果物が複数ファイルにまたがる・人に聞くことがある、のいずれかに当てはまる大きなゴールは `/design` から始める。設計文書のフェーズを1つずつ `/plan` に渡す。小さい要求は `/plan` に直行する。

- 人が日々やることは `docs/runbook.md`、Vault の仕様は `docs/vault-spec.md` を参照
- 無人で回す場合は `claude -p "/run"` を cron や CI から定期実行する
- 1セッション=1計画=1ブランチ。複数の計画を並行して進めたい時は、計画ごとに別のセッション（別のブランチ／worktree）を使う

## 拡張ポイント（ルール）
「ルール」を作成エージェント・verifier・planner に渡せる。ハーネスは planner / creator / verifier の役割定義を標準ルールとして同梱する（`vault/rules/common/roles.md`、`vault/rules/creator/creator.md`、`vault/rules/verifier/verifier.md`、`vault/rules/planner/planner.md`）。コーディングルール・開発標準・方式設計・テスト観点などドメイン固有のルールはインストール先で書く。

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
 ├──────────────────────▶ ブランチ work/<計画ID> を作成             │
 │                        │ planner が計画票 <計画ID>.md / タスク票を draft │
 │ /plan approve <計画ID>  │                                       │
 ├──────────────────────▶ 計画票の status を approved に            │
 │ /run                    │                                       │
 ├──────────────────────▶ todo→doing → 成果物を作る → review ──▶ 受け入れ基準を照合
 │                        │                                       │ verdicts/<計画ID>/<id>.json
 │                        │ ◀─────────────────────────────────────┘
 │                        │ PASS → done / FAIL → doing(attempt+1) / 上限 → blocked
 │                        │ 全タスク done → status を done にし gh pr create
 │                        ▼
 │               Stop フック（stop_gate.py）
 │               計画票のタスク表と verdict を照合し、整合しない終了をブロック
 │ blocked に答えて戻す・PR をマージ
 └──────────────────────▶ vault/plans/<計画ID>.md（状態の正本）  vault/log/<計画ID>.md（追記ログ）
```
PR ができたら、人が内容を確認して `gh pr merge` でマージする（コンフリクトがあれば計画のブランチ上で人が解決する。エージェントは `gh pr create` までしか行わない）。

## 構成
```
.claude/   settings.json（hooks・許可）、agents/（verifier, planner）、hooks/、skills/（design, plan, run）
vault/     plans/（計画票=状態の正本）、tasks/、designs/（設計文書）、verdicts/、log/、templates/、archive/、rules/（拡張ポイント。vault/rules/ 配下）
docs/      vault-spec.md（仕様の正本）、install.md（インストール手順）、runbook.md、decisions.md
scripts/   smoke.sh（フック検証）、install.sh（他プロジェクトへ複製）、rules.sh（ルール解決）
```

## ライセンス
このリポジトリは `MIT License` の下で公開しています。詳細は [LICENSE](LICENSE) を参照してください。
