---
id: P-20261012-install-harness-only-files
status: approved
---
# ゴール
GitHub Issue #200「install.sh を導入済みリポジトリから実行すると、配布元の業務用 Skill まで導入先に複製されマニフェストに記録される」を解決する。`scripts/install.sh` が配る `.claude/` 配下のファイル（と、マニフェストに記録するファイル）をハーネス本体の固定リストに限り、配布元が独自に置いた Skill・agent・hook・テンプレートが導入先に複製されず、マニフェストにも載らないようにする。smoke に「配布元に独自の Skill がある状態で install しても導入先に届かない」ケースを足し、利用者向けの説明（`docs/install.md`）を実装に合わせる。

## 分割方針
- T-01 で `scripts/install.sh` の修正と smoke のケース追加を同じタスクにする。install.sh の振る舞いを確かめるには一時ディレクトリへ実際に install する必要があり、verifier が repo の外へ書く確認コマンドは権限判定で止まりうるため、smoke（スクリプトの中で一時ディレクトリを作る）を機能確認の手段にする。主な成果物は `scripts/install.sh` で、`scripts/smoke.sh` はその確認用の付随ファイル。
- T-02 で `docs/install.md` の「複製されるもの」の説明を固定リストに合わせる。説明は T-01 の実装（固定リストの中身・旧版で配られた独自ファイルの扱い）に合わせて書くので、`after` で T-01 に依存させる。
- `scripts/uninstall.sh` はマニフェストの `files` だけを見て消すので、マニフェストに独自ファイルが載らなくなれば変更は要らない（変えない）。`docs/vault-spec.md` には配布ファイルの一覧が無いので変えない。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | install.sh の .claude/ の複製とマニフェスト記録をハーネス本体の固定リストに限り、smoke にケースを足す | |
| T-02 | done | 1 | T-01 | docs/install.md の「複製されるもの」を固定リストに合わせる | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない
- 1タスクが1コンテキストで終わる粒度である

## 次フェーズの候補（票は起こさない）
- `scripts/` 直下の配布も検索方式（`scripts_list` が `scripts/*.sh`・`scripts/*.py` を検索し、除外リスト `SCRIPTS_EXCLUDE` だけを除く）なので、配布元が `scripts/` に独自のスクリプトを置くと導入先に複製されマニフェストに載る。Issue #200 は `.claude/` 配下の Skill を対象にしており、`docs/install.md` も scripts を「検索方式で配布する」と明記しているため、この計画では変えない。固定リストにするかは別 Issue で判断する。
