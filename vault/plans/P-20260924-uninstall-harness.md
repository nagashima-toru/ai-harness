---
id: P-20260924-uninstall-harness
status: approved
---
# ゴール

GitHub Issue #8。ハーネスを導入先から取り除く手順が無い（`scripts/install.sh` と `docs/install.md` には導入・更新手順はあるが、アンインストール手順が無い）。以下を実現する `scripts/uninstall.sh` と関連ドキュメントを作る。

- `.claude/harness-manifest.json`（配布物の sha256 を記録したもの）を使い、マニフェストに記録されていて、かつ現状のハッシュが記録値と一致する（＝未編集の）ファイルだけを削除する `scripts/uninstall.sh` を用意する
- `CLAUDE.md` はマーカーブロック（`<!-- ai-harness:begin v1 -->` 〜 `<!-- ai-harness:end -->`）のみを取り除く（`scripts/merge_claude_md.py` の逆処理）
- `.claude/settings.json` はハーネスが足した hooks / `permissions.deny` のエントリだけを取り除く（`scripts/merge_settings_json.py` の逆処理）
- `vault/` 配下の利用者資産（`plans/tasks/verdicts/log/designs/archive`、ドメイン固有の `vault/rules/`）には一切触れない
- `install.sh` の `copy` / `skip (exists)` / `skip (edited)` 表示と対称に、「自動で消した」「編集済みなので残した」「利用者資産なので触れない」を分けて報告する

## 分割方針

`scripts/merge_settings_json.py` の逆処理には「ハーネスが足した内容」の元データ（`src` の hooks / `permissions.deny`）が要る。しかし `scripts/uninstall.sh` は導入先リポジトリ単体で動く前提で、導入元の ai-harness クローンが手元に残っている保証は無い。そこで **契約を先に決める**：`scripts/install.sh` が書く `.claude/harness-manifest.json` に、`files` に加えて `settings_src` キー（インストール時点の ai-harness 側 `.claude/settings.json` の内容そのもの）を持たせる。`scripts/unmerge_settings_json.py` は `merge_settings_json.py` と対になる汎用スクリプトとして `<src_settings_json> <dst_settings_json>` を取り、`uninstall.sh` は `harness-manifest.json` の `settings_src` を一時ファイルに書き出して `src` として渡す。この契約により、`unmerge_settings_json.py`／`uninstall.sh` は `install.sh` の変更を待たずに実装・検証できる（テスト側で `settings_src` を持つ manifest を用意すればよい）。

- T-01・T-02：独立した逆処理スクリプト（`unmerge_claude_md.py` / `unmerge_settings_json.py`）を先に作る。どちらも汎用の `<src> <dst>` インターフェースで、`uninstall.sh` にも `install.sh` にも依存しない
- T-03：`scripts/uninstall.sh` 本体。T-01・T-02 を呼び出し、マニフェスト照合による削除ロジックと3種類の報告を実装する。`harness-manifest.json` の `settings_src` キーが無ければ settings.json の自動処理はスキップし、案内メッセージを出す
- T-04：`scripts/install.sh` を更新し、(a) 新規3ファイル（`uninstall.sh` / `unmerge_claude_md.py` / `unmerge_settings_json.py`）を配布対象（`manifest_paths()` と通常の複製ループ）に追加し、(b) マニフェスト書き出しに `settings_src` キーを足す。T-03 の後に置くのは、これらのファイルが実在してから `install.sh` の複製ループに加えないと `bash scripts/install.sh` 自体の受け入れ基準（複製できること）が壊れるため
- T-05：`docs/install.md` にアンインストール手順の節を追記。T-04 完了後の実際の出力文言・ファイル名を見てから書く方が精度が高い
- T-06：`scripts/smoke.sh` に uninstall.sh の回帰テストを追加。T-04 完了後（新規ファイルが `install.sh` で複製される状態）でないと install→uninstall の一連テストが組めない

依存に循環は無い（T-01, T-02 → T-03 → T-04 → {T-05, T-06}）。T-05 と T-06 は互いに依存しない。

## タスク表（状態の正本）
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | done | 1 | - | scripts/unmerge_claude_md.py を作る（CLAUDE.md からマーカーブロックのみ除去） | |
| T-02 | done | 1 | - | scripts/unmerge_settings_json.py を作る（settings.json からハーネス由来のエントリのみ除去） | |
| T-03 | done | 1 | T-01,T-02 | scripts/uninstall.sh を作る（マニフェスト照合削除 + 3種報告） | |
| T-04 | done | 1 | T-03 | scripts/install.sh を更新（新規3ファイルの配布対象追加 + manifest に settings_src を書く） | |
| T-05 | doing | 1 | T-04 | docs/install.md にアンインストール手順を追記する | |
| T-06 | doing | 1 | T-04 | scripts/smoke.sh に uninstall.sh の回帰テストを追加する | |

## 計画の受け入れ基準
- 各タスクに成果物と受け入れ基準が1つずつある
- 依存に循環がない（T-01, T-02 → T-03 → T-04 → {T-05, T-06}）
- 1タスクが1コンテキストで終わる粒度である
- 全タスク完了後、`bash scripts/smoke.sh` が全 PASS する
- `vault/` 配下の利用者資産（`plans/tasks/verdicts/log/designs/archive`、標準4本以外の `vault/rules/`）を書き換える成果物が無い
