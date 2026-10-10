# ai-harness

AI の作業を「作成 → 検証」の二段構成にし、検証が PASS しない限り完了できないようにする Claude Code 用ハーネス。
このリポジトリ自体が雛形であり、自分自身で動作確認する場でもある。
実行を安いモデルに任せても成果が安定する汎用のタスク実行基盤です。目的・原則・非ゴールは [docs/vision.md](docs/vision.md) を参照。

## 目的
- 作成エージェントの成果物を、別コンテキストの検証エージェント（verifier）が受け入れ基準に照らして採点し `verdict.json` を書く
- Stop フックが verdict を見て、PASS でなければ作業を終わらせない（リトライ上限あり、超過時は人へ引き継ぐ）
- エージェントが読む情報を `vault/` に集約し、開始時に読むものを小さく保つ
- 状態をすべてファイルに置き、セッションが切れても新セッションが続きから拾える

## セットアップ
前提：`claude`（Claude Code）、`git`、`python3` が使える。

他のプロジェクトへの組み込み・更新・取り外しは [docs/install.md](docs/install.md) の「パターン2: 既存リポジトリに追加する」「ハーネスを更新する（2回目以降）」を参照（更新は `bash scripts/install.sh --update <組み込み先>`）。

## クイックスタート
最初の PR をマージするまでの最小手順。

1. リポジトリを取得する：`git clone git@github.com:nagashima-toru/ai-harness.git && cd ai-harness`
2. フックの動作を確かめる：`bash scripts/smoke.sh`（最終行が `fail=0` なら OK）
3. `claude` を起動し、ゴールを渡して計画を作る：`/plan <ゴール>`
4. 粒度の確認を通ると自動で approved になり、続けて `/run` が走って PR までできる（planner の質問があれば、答えるまで止まる）
5. PR ができたら、人が内容を確認してマージする：`gh pr merge`（エージェントはマージしない）

## 使い方
| コマンド | 何をするか |
|---|---|
| `/design <ゴール>` | 大きなゴールを調査し、人に質問し、決定事項を固めた設計文書 `vault/designs/D-<YYYYMMDD>-<スラッグ>.md` を作る |
| `/plan <ゴール>` | 計画 ID を決めてブランチ（`work/<計画ID>`）を切り、planner がタスクに分割して draft を作る。粒度の確認を通ったら approved にしてコミットし、続けて `/run` を実行する（planner の質問があれば、解消するまで止まる） |
| `/run` | 自分のブランチの承認済み計画の取れるタスクを、全部 done になるまで処理し、PR を作る（creator → verifier → done / 再試行 / blocked） |
| `python3 scripts/run_unattended.py` | 同じことを無人（非対話）で行う（タイムアウト付きのラッパー。中で `claude -p "/run"` を実行する） |

`/design` と `/plan` の使い分け：受け入れ基準が7行に収まらない・成果物が複数ファイルにまたがる・人に聞くことがある、のいずれかに当てはまる大きなゴールは `/design` から始める。設計文書のフェーズを1つずつ `/plan` に渡す。小さい要求は `/plan` に直行する。

- 人が日々やることは `docs/runbook.md`、Vault の仕様は `docs/vault-spec.md` を参照
- 無人で回す場合は `python3 scripts/run_unattended.py` を cron や CI から定期実行する（手順は `docs/runbook.md`）
- 1セッション=1計画=1ブランチ。複数の計画を並行して進めたい時は、計画ごとに別のセッション（別のブランチ／worktree）を使う

## 拡張ポイント（ルール）
ハーネスは標準ルールを同梱しない。planner / creator / verifier の役割定義は `.claude/agents/creator.md`・`.claude/agents/verifier.md`・`.claude/agents/planner.md` にある。「ルール」を作成エージェント・verifier・planner に渡せる拡張ポイントとして、コーディングルール・開発標準・方式設計・テスト観点などは導入先で `vault/rules/` に書く。

| ディレクトリ | 渡す相手 |
|---|---|
| `vault/rules/common/` | 全員（作成エージェント・verifier・planner） |
| `vault/rules/creator/` | 作成エージェントのみ |
| `vault/rules/verifier/` | verifier のみ |
| `vault/rules/planner/` | planner のみ |

- 読み込みは `bash scripts/rules.sh <creator|verifier|planner>` で一本化（`common/` → 役割ディレクトリの順、ファイル名順）
- 受け入れ基準からルールファイルを名指しして参照する（例：「`vault/rules/common/naming.md` の命名規則に従っている」）と、verifier がそのファイルを根拠に判定する
- フックは `vault/rules/` への書き込みを止めない。タスクの「成果物」に宣言すれば変えられ、宣言の無い変更は差分ゲート `scripts/diff_gate.py` が差し戻す。変更は PR の差分で見える
- 導入先で積む拡張の例（導入先で書くルールの例）：開発案件なら、型・API・テスト雛形などの「契約」タスクを先に切り、実装タスクを `after` でそれに依存させる、というルールを `vault/rules/planner/` に置く

## 仕組み
```
 人                      オーケストレーター（メイン）           verifier（別コンテキスト）
 │ /plan <ゴール>          │                                       │
 ├──────────────────────▶ ブランチ work/<計画ID> を作成             │
 │                        │ planner が計画票 <計画ID>.md / タスク票を draft │
 │                        │ 粒度の確認後、status を approved に（自動）  │
 │                        │ 続けて /run の手順を実行                   │
 │                        │ todo→doing → creator が worktree で作る → review ──▶ 受け入れ基準を照合
 │                        │                                       │ verdicts/<計画ID>/<id>.json
 │                        │ ◀─────────────────────────────────────┘
 │                        │ PASS → done / FAIL → doing(attempt+1) / 上限 → blocked
 │                        │ 全タスク done → status を done にし vcs_finish.sh で PR
 │                        ▼
 │               Stop フック（stop_gate.py）
 │               計画票のタスク表と verdict を照合し、整合しない終了をブロック
 │ blocked に答えて戻す・PR をマージ
 └──────────────────────▶ vault/plans/<計画ID>.md（状態の正本）  vault/log/<計画ID>.md（追記ログ）
```
PR ができたら、人が内容を確認して `gh pr merge` でマージする（コンフリクトがあれば計画のブランチ上で人が解決する。エージェント（オーケストレーター）は `bash scripts/vcs_finish.sh` で PR を作るまでしか行わない）。

## 構成
```
.claude/   settings.json（hooks・許可）、agents/（creator, verifier, planner）、hooks/、skills/（design, plan, run）
vault/     plans/（計画票=状態の正本）、tasks/、designs/（設計文書）、verdicts/、log/、templates/、rules/（拡張ポイント。vault/rules/ 配下）
docs/      vault-spec.md（仕様の正本）、install.md（インストール手順）、runbook.md、vision.md、decisions.md
scripts/   smoke.sh（フック検証）、install.sh・uninstall.sh（他プロジェクトへの複製と取り外し）、rules.sh（ルール解決）、current_plan.sh（承認済みの計画の特定）、transition.py（状態遷移）、diff_gate.py（差分ゲート）、vcs_finish.sh（PR 作成）、discard_worktree.sh（worktree の破棄）、run_unattended.py（無人実行のラッパー）、purge_plan.sh（計画一式の除去とマージ済みの一括削除）
```

## ライセンス
このリポジトリは `MIT License` の下で公開しています。詳細は [LICENSE](LICENSE) を参照してください。
