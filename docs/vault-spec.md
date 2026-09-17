# Vault 仕様（正本）

エージェントと人が共有する状態はすべて `vault/` 配下のファイルに置く。この文書が命名・状態遷移の正本であり、CLAUDE.md や各スキルはここを参照する。

## 1. ディレクトリ

| パス | 内容 |
|---|---|
| `vault/todo.md` | キュー。タスクと計画の状態の正本 |
| `vault/tasks/T-0001.md` | タスク票（テンプレート：`vault/templates/task.md`） |
| `vault/plans/P-001.md` | 計画票（テンプレート：`vault/templates/plan.md`） |
| `vault/designs/D-001.md` | 設計文書（テンプレート：`vault/templates/design.md`）。`/plan` に渡す前の下ごしらえ |
| `vault/verdicts/T-0001.json` | 検証結果。最新のみ、上書き |
| `vault/log/queue.md` | 追記専用ログ |
| `vault/archive/` | done を月次で移す先（`vault/archive/YYYY-MM/T-0001.md`） |

## 2. 状態（5つで固定、英小文字）

| status | 意味 | 誰が付けるか |
|---|---|---|
| `todo` | 着手可。上から順に取る | planner / 人 |
| `doing` | 作業中。**常に1件だけ** | 作成エージェント |
| `review` | 作成完了、検証待ち | 作成エージェント |
| `blocked` | 人の判断待ち。question 必須 | 作成エージェント / フック |
| `done` | 完了。以後編集禁止 | 作成エージェント（verdict が PASS の時のみ） |

遷移：`todo→doing→review→(done | doing[attempt+1] | blocked)`。`blocked→todo` は人のみ。

`attempt` は「現在の試行回数」。`todo→doing` で 1 になり、`review→doing`（FAIL 後の再試行）で +1 する。上限は環境変数 `HARNESS_MAX_ATTEMPTS`（既定 3）。上限に達して FAIL なら `blocked` にする。

## 3. ID・ファイル名

- タスク：`T-` + 4桁ゼロ埋め（`T-0001`）。計画：`P-` + 3桁（`P-001`）。設計文書：`D-` + 3桁（`D-001`）
- 採番は既存（archive 含む）の最大値 +1。欠番は許容、再利用は禁止。3系列は互いに独立して採番する
- ディレクトリ・その他ファイルは小文字ケバブケース
- 日時は `YYYY-MM-DD HH:MM`（JST）。取得例：`TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'`

## 4. todo.md の形式

```markdown
## タスク
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-0001 | todo | 0 | - | ハーネスの動作確認 | |

## 計画
| id | status | title |
|---|---|---|
| P-001 | approved | 初期構築 |
```

- `after`：依存タスク ID。未完了なら飛ばす。複数はカンマ区切り。無ければ `-`
- `question`：blocked の時に人へ聞くこと（必須）
- 計画の status は `draft` / `approved` の2つ。approved になるまでタスクは todo.md に登録しない
- 列の順序・見出し名は変えない（Stop フックがこの表を解析する）

## 5. タスク票（`vault/templates/task.md`）

見出しは `目的 / 入力 / 成果物 / 受け入れ基準 / 決定済み / 進捗` の6つで固定。順序も変えない。

- 受け入れ基準は3〜7行。各行は真偽で判定できる文にし、機械で確認できるものは確認コマンドを併記する
- 進捗は doing 中に作成エージェントが追記する。セッションが切れた時はここから再開する

## 6. 計画票（`vault/templates/plan.md`）

frontmatter に `id` と `status`（`draft` / `approved`）。本文は `ゴール / 分割方針 / タスク一覧 / 計画の受け入れ基準`。

## 7. verdict.json

```json
{
  "task": "T-0001",
  "attempt": 1,
  "result": "PASS",
  "checked_at": "2026-09-16 10:00",
  "criteria": [
    {"text": "受け入れ基準の1行目", "ok": true, "note": "実行コマンド: `bash scripts/smoke.sh | tail -1` / 出力: smoke: pass=18 fail=0"}
  ],
  "reasons": ["FAIL の理由。PASS なら空配列"]
}
```

- `result` は `PASS` / `FAIL` の2値
- `attempt` は todo.md の attempt と一致させる。一致しない verdict は「無い」ものとして扱う（古い verdict で done にしない）
- `criteria` は受け入れ基準と同じ行数・同じ順序
- `note` は必須（空にしない）。確認に使ったコマンド（または確認方法）と出力の要点を1〜3行で書く。人が verdict だけを読んで判定の根拠を追えるようにする
  - 書式の例：`実行コマンド: \`<command>\` / 出力: <判定に使った部分の要点>`
  - 確認コマンドが実行できなかった場合（権限拒否・ツール不足など）は、その旨と代替の確認方法、その結果をセットで書く。例：`\`awk ...\` は権限拒否で実行不可。代替として README.md を Read で確認し、使い方節に cron の行が1行あった`
  - 受け入れ基準がルールを根拠にした場合（`vault/rules/` 配下のファイル名や「コーディングルールに従う」等を参照する行）は、参照したルールファイルのパスを `note` に書く

## 8. ログ `vault/log/queue.md`

追記のみ。1行 = `- YYYY-MM-DD HH:MM T-0001 doing→review attempt=1 補足`

## 9. 粒度の基準（planner と人が共有する）

- 受け入れ基準が3〜7行で書ける
- 成果物が1つに特定できる（「〜を改善」は不可）
- 1コンテキストで終わる（目安：人手で1〜2時間相当）
- 開発案件では、型・API・テスト雛形などの「契約」タスクを先に切り、実装タスクはそれに依存させる
- run-queue で必ず変わるファイル（`vault/todo.md`、`vault/log/queue.md`、タスク票の「進捗」）を「変更していない」と差分で検査する受け入れ基準は書かない。形式の不変を見たい時は見出し行・列構成に限定した確認コマンドにする
- `vault/rules/`（common・planner）にルールがある場合は、その具体的な基準を受け入れ基準や決定済みに反映する。ただし受け入れ基準3〜7行の上限は優先し、超えそうな場合は要約に留める

## 10. Stop フックの判定

`.claude/hooks/stop_gate.py` は todo.md と verdict を読んで判定だけを行い、状態は書き換えない。

| 状況 | 判定 |
|---|---|
| `stop_hook_active` が真 | 許可（`HARNESS_STRICT_STOP=1` なら無視して判定を続ける） |
| doing / review のタスクが無い | 許可 |
| verdict が無い、または task / attempt が不一致 | ブロック：verifier を実行して verdict を書く |
| verdict が不正（result が PASS/FAIL 以外、criteria の要素に text/ok/note が無い、criteria の行数がタスク票の受け入れ基準の行数と不一致、note が空、reasons が配列でない） | ブロック：何が不正かを示し、verifier を再実行して書き直す |
| FAIL かつ attempt < 上限 | ブロック：doing に戻し attempt を +1 して修正 |
| FAIL かつ attempt ≥ 上限 | ブロック：blocked にし question を書く（既に blocked なら許可） |
| PASS だが status が done でない | ブロック：done にし log に追記 |
| PASS かつ done | 許可 |

## 11. todo_guard フックの判定

`.claude/hooks/todo_guard.py` は PostToolUse（`Write|Edit|MultiEdit|Bash`）で `vault/todo.md` を検査し、doing が2件以上・blocked なのに question が空・status が5値以外・id の重複・データ行の列数が6でない、のいずれかならブロックして直し方を示す。todo.md が無い場合とデータ行が無い場合は何もしない。

## 12. ルール（`vault/rules/`）

インストール先ごとに用意する「ルール」（コーディングルール・開発標準・方式設計・テスト標準・テスト観点など）を、作成エージェント・verifier・planner に渡す拡張ポイント。ハーネス本体はルールを同梱しない。置き場と読み込み口だけを用意し、実ルールはインストール先で書く。

### ディレクトリと振り分け
```
vault/rules/
  README.md      # 書き方・振り分けの説明（install.sh が複製）
  common/        # 作成エージェント・verifier・planner の全員に渡す
  creator/       # 作成エージェントだけに渡す
  verifier/      # verifier だけに渡す
  planner/       # planner だけに渡す
```
- 「全員 / 作成のみ / 検証のみ / 計画のみ」の4パターンはディレクトリだけで振り分ける。frontmatter や索引ファイルは持たない
- ファイルは `*.md`、小文字ケバブケース。読み込み順は `common/` → 役割ディレクトリ、各ディレクトリ内はファイル名順（決定的にする）
- 1ファイルは100行以内を目安に、話題ごとに分ける（機械的な強制はしない）
- 雛形は `vault/templates/rule.md`（見出し：目的 / ルール / 確認方法）

### ルールと受け入れ基準の関係
ルールは受け入れ基準を増やすものではなく、**基準の判定方法を与えるもの**。受け入れ基準が `vault/rules/` のルールを参照する時（例：「コーディングルールに従っている」）だけ、verifier はルールを根拠に真偽を判定する。受け入れ基準がルールに触れていなければ、ルールを理由に FAIL にしない。作成側だけに渡した `creator/` のルールは verifier から見えないため、それを根拠に落とすこともない。

### 改ざん防止
`doing` / `review` 中のタスクがある間は、`vault/rules/` への書き込みをフックで拒否する（実装は `.claude/hooks/agent_write_guard.py`）。作成エージェントがタスク中にルールを書き換え、verifier の判定基準を自分で緩めることを防ぐ。詳細は「13. agent_write_guard フックの改ざん防止判定」。

## 13. agent_write_guard フックの改ざん防止判定

`.claude/hooks/agent_write_guard.py` は verifier / planner 向けの書き込み先制限（本節冒頭）とは別に、`agent_type` を問わず（メインエージェント含む）適用する判定を持つ。`vault/todo.md` の「## タスク」表を簡易的に解析し（`.claude/hooks/todo_guard.py` の `raw_rows` と同じ規則をこのファイル内にコピーして使う。import はしない）、以下のとおり判定する。

| 状況 | 判定 |
|---|---|
| `doing` / `review` の行が無い | 許可（この判定は素通り。既存の verifier/planner 向け判定へ進む） |
| `doing` / `review` の行が1件以上あり、対象が `vault/rules/` 配下への書き込み（Write/Edit/MultiEdit/NotebookEdit の `file_path`、または Bash のリダイレクト・`tee`・`sed -i`・`rm`/`mv`/`cp` 等） | ブロック：`doing/review 中は vault/rules/ を編集できません` と対象タスク ID を reason に含める |
| 上記に該当しない（`vault/rules/` 以外への書き込み） | 許可（この判定は素通り。既存の verifier/planner 向け判定へ進む） |

この判定は既存の verifier/planner 向け `ALLOWED` 判定より前に実行される。verifier・planner が `vault/rules/` に書こうとした場合も、doing/review 中ならこの判定で先に拒否される。

## 14. 設計文書（`vault/designs/`）

大きなゴールを `/plan` に渡す前に、調査と人への質問を済ませて決定事項を固めるための文書。`/design` スキルが `vault/designs/D-001.md` に書く。テンプレートは `vault/templates/design.md`。

### ID と採番
- `D-` + 3桁（`D-001`）。採番は `vault/designs/` 内の既存ファイルの最大値 +1。タスク・計画とは独立した系列
- frontmatter は `id` のみ。`status` は持たない。設計文書は一度提示して終わる読み物であり、5状態遷移の対象ではない

### 形式
本文は「決定事項」（人に聞いて確定した回答）と、フェーズごとの4点セットの繰り返しで構成する。4点セットの見出しは以下に固定する。

| 見出し | 内容 |
|---|---|
| ゴール文 | `/plan` にそのまま貼れる自然文。1フェーズ分のゴール |
| 受け入れ基準の候補 | planner が受け入れ基準に起こす叩き台。3〜7行 |
| 決定済み | 作成エージェントが聞きそうなことへの先回りの回答 |
| 依存 | 先に終えているべきフェーズ |

### `/plan` との関係
- `/design` は planner サブエージェントを呼ばない。設計文書を書いて提示し、そこで止まる
- 人が設計文書を確認してから、フェーズのゴール文を1つずつ `/plan` に渡す
- 使うのは、受け入れ基準が7行に収まらない・成果物が複数ファイルにまたがる・人に聞くことがある、のいずれかに当てはまる時だけ。小さい要求は `/plan` に直行する
