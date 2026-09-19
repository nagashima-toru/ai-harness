# Vault 仕様（正本）

> この仕様はフェーズ3〜4の実装が完了するまで未適用。
> 実際の運用は現時点では `.claude/skills/run-queue/SKILL.md` に従う。
> （D-001 フェーズ4の完了時にこの注記を削除する）

エージェントと人が共有する状態はすべて `vault/` 配下のファイルに置く。この文書が命名・状態遷移の正本であり、CLAUDE.md や各スキルはここを参照する。

## 1. ディレクトリ

| パス | 内容 |
|---|---|
| `vault/plans/<計画ID>.md` | 計画票（テンプレート：`vault/templates/plan.md`）。**タスクの状態の正本**。キューと呼ぶのはこの票のタスク表のこと |
| `vault/tasks/<計画ID>/T-01.md` | タスク票（テンプレート：`vault/templates/task.md`） |
| `vault/verdicts/<計画ID>/T-01.json` | 検証結果。最新のみ、上書き |
| `vault/log/<計画ID>.md` | その計画の追記専用ログ |
| `vault/designs/D-001.md` | 設計文書（テンプレート：`vault/templates/design.md`）。`/plan` に渡す前の下ごしらえ |
| `vault/rules/` | 作成エージェント・verifier・planner に渡すルール（「ルール（`vault/rules/`）」の節を見る） |
| `vault/archive/` | done になった計画一式を月次でまとめる先 |

計画をまたぐキューは持たない。**1セッション = 1計画 = 1ブランチ**で、計画の作成から実行・PR までを1本のブランチに閉じる。状態ファイルが計画ごとに分かれるので、複数のエージェントセッションが別々の計画を同時に進めても競合しない。

「自分のブランチの計画票」は `vault/plans/*.md` を走査し、frontmatter の `status` が `approved` のものを取る。2つ以上 `approved` があるのは異常（1ブランチ1計画の不変条件）。

証跡は3層で残る。`vault/log/<計画ID>.md`（状態遷移）・`vault/verdicts/<計画ID>/T-01.json`（判定の根拠）・git のステップごとのコミットと PR。どれも計画のブランチ内に閉じるので、セッション間で競合しない。

## 2. 状態（5つで固定、英小文字）

| status | 意味 | 誰が付けるか |
|---|---|---|
| `todo` | 着手可。上から順に取る | planner / 人 |
| `doing` | 作業中。**計画内で常に1件だけ** | 作成エージェント |
| `review` | 作成完了、検証待ち | 作成エージェント |
| `blocked` | 人の判断待ち。question 必須 | 作成エージェント / フック |
| `done` | 完了。以後編集禁止 | 作成エージェント（verdict が PASS の時のみ） |

この5つは計画票のタスク表の中の状態で、状態を数える単位もその表の中に閉じる。別のブランチで別の計画が `doing` のタスクを持っていても干渉しない。

遷移：`todo→doing→review→(done | doing[attempt+1] | blocked)`。`blocked→todo` は人のみ。

`attempt` は「現在の試行回数」。`todo→doing` で 1 になり、`review→doing`（FAIL 後の再試行）で +1 する。上限は環境変数 `HARNESS_MAX_ATTEMPTS`（既定 3）。上限に達して FAIL なら `blocked` にする。

## 3. ID・ファイル名・ブランチ名

| 種別 | 形式 | 例 |
|---|---|---|
| 計画 ID | `P-YYYYMMDD-<slug>` | `P-20260919-git-ops` |
| タスク ID | 計画スコープの `T-` + 2桁 | `T-01` |
| ブランチ名 | 計画 ID を英小文字にして `work/` を付ける | `work/p-20260919-git-ops` |
| 設計文書 ID | `D-` + 3桁 | `D-001` |

- 計画 ID は日付とスラッグから作るので**採番が要らない**。並行するセッションが同時に計画を作っても衝突しない
- スラッグは英小文字・ハイフン区切り。人が計画を識別できればよく、生成アルゴリズムは規定しない
- タスク ID は計画の中で `T-01` から振る。計画が違えば同じ `T-01` があってよい
- 計画をまたいでタスクを一意に指す時は `<計画ID>/T-01` と書く（verdict の `task` もこの形式）
- 設計文書 ID だけは `vault/designs/` 内の既存の最大値 +1 で採番する。欠番は許容、再利用は禁止
- ディレクトリ・その他ファイルは小文字ケバブケース
- 日時は `YYYY-MM-DD HH:MM`（JST）。取得例：`TZ=Asia/Tokyo date '+%Y-%m-%d %H:%M'`

## 4. 計画票の形式

計画票（`vault/plans/<計画ID>.md`）は、その計画のゴールと**タスクの状態**を持つ。テンプレートは `vault/templates/plan.md`。

frontmatter は `id` と `status` の2つ。

| status | 意味 |
|---|---|
| `draft` | planner が作った直後。人の承認待ちで、まだ着手しない |
| `approved` | 人が承認した。このブランチで進行中の計画 |
| `done` | 全タスクが `done` になり `gh pr create` 済み |

`done` は **PR 作成済み**という意味で、main へのマージは含まない。マージは人が行い、エージェントは `gh pr create` までで `gh pr merge` は実行しない。

本文は `ゴール / 分割方針 / タスク一覧 / 計画の受け入れ基準`。このうち「タスク一覧」の表が状態の正本で、次の形にする。

```markdown
| id | status | attempt | after | title | question |
|---|---|---|---|---|---|
| T-01 | todo | 0 | - | ハーネスの動作確認 | |
```

- 列の順序・列名・見出し名は変えない（フックがこの表を解析する）
- `after`：依存タスク ID。未完了なら飛ばす。複数はカンマ区切り。無ければ `-`
- `question`：`blocked` の時に人へ聞くこと（必須）
- `after` が指せるのは同じ計画内のタスクだけ。表が計画ごとに分かれているため、計画をまたぐ依存は書けない

## 5. タスク票（`vault/templates/task.md`）

見出しは `目的 / 入力 / 成果物 / 受け入れ基準 / 決定済み / 進捗` の6つで固定。順序も変えない。

- 受け入れ基準は3〜7行。各行は真偽で判定できる文にし、機械で確認できるものは確認コマンドを併記する
- 進捗は doing 中に作成エージェントが追記する。セッションが切れた時はここから再開する

## 6. verdict.json

```json
{
  "task": "P-20260919-git-ops/T-01",
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
- `task` は `<計画ID>/T-01` 形式。verdict 単体でどの計画のタスクかが分かるようにする
- `attempt` は計画票のタスク表の attempt と一致させる。一致しない verdict は「無い」ものとして扱う（古い verdict で done にしない）
- `criteria` は受け入れ基準と同じ行数・同じ順序
- `note` は必須（空にしない）。確認に使ったコマンド（または確認方法）と出力の要点を1〜3行で書く。人が verdict だけを読んで判定の根拠を追えるようにする
  - 書式の例：`実行コマンド: \`<command>\` / 出力: <判定に使った部分の要点>`
  - 確認コマンドが実行できなかった場合（権限拒否・ツール不足など）は、その旨と代替の確認方法、その結果をセットで書く。例：`\`awk ...\` は権限拒否で実行不可。代替として README.md を Read で確認し、使い方節に cron の行が1行あった`
  - 受け入れ基準がルールを根拠にした場合（`vault/rules/` 配下のファイル名や「コーディングルールに従う」等を参照する行）は、参照したルールファイルのパスを `note` に書く

## 7. ログ `vault/log/<計画ID>.md`

計画ごとに1ファイル。追記のみ。1行 = `- YYYY-MM-DD HH:MM T-01 doing→review attempt=1 補足`

ファイル名で計画が特定できるので、行の中のタスク ID は計画スコープの短い形（`T-01`）でよい。計画のブランチ内に閉じるので、並行するセッションの追記と競合しない。

## 8. 粒度の基準（planner と人が共有する）

- 受け入れ基準が3〜7行で書ける
- 成果物が1つに特定できる（「〜を改善」は不可）
- 1コンテキストで終わる（目安：人手で1〜2時間相当）
- 開発案件では、型・API・テスト雛形などの「契約」タスクを先に切り、実装タスクはそれに依存させる
- run で必ず変わるファイル（計画票のタスク表、`vault/log/<計画ID>.md`、タスク票の「進捗」）を「変更していない」と差分で検査する受け入れ基準は書かない。形式の不変を見たい時は見出し行・列構成に限定した確認コマンドにする（例：`git diff -- vault/plans/<計画ID>.md | grep -E '^[+-](## |\| id )'`）
- `vault/rules/`（common・planner）にルールがある場合は、その具体的な基準を受け入れ基準や決定済みに反映する。ただし受け入れ基準3〜7行の上限は優先し、超えそうな場合は要約に留める

## 9. Stop フックの判定

`.claude/hooks/stop_gate.py` は、自分のブランチの承認済み計画票のタスク表と verdict を読んで判定だけを行い、状態は書き換えない。

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

## 10. plan_guard フックの判定

`.claude/hooks/plan_guard.py` は PostToolUse（`Write|Edit|MultiEdit|Bash`）で、自分のブランチの計画票のタスク表を検査し、doing が2件以上・blocked なのに question が空・status が5値以外・id の重複・データ行の列数が6でない、のいずれかならブロックして直し方を示す。計画票が無い場合とデータ行が無い場合は何もしない。

## 11. ルール（`vault/rules/`）

「ルール」を作成エージェント・verifier・planner に渡す拡張ポイント。ハーネスは planner / creator / verifier の役割定義を標準ルールとして同梱する（`common/roles.md`・`creator/creator.md`・`verifier/verifier.md`・`planner/planner.md`）。コーディングルール・開発標準・方式設計・テスト標準・テスト観点などドメイン固有のルールは、置き場と読み込み口だけを用意し、インストール先で書く。

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
`doing` / `review` 中のタスクがある間は、`vault/rules/` への書き込みをフックで拒否する（実装は `.claude/hooks/agent_write_guard.py`）。作成エージェントがタスク中にルールを書き換え、verifier の判定基準を自分で緩めることを防ぐ。詳細は「12. agent_write_guard フックの改ざん防止判定」。

## 12. agent_write_guard フックの改ざん防止判定

`.claude/hooks/agent_write_guard.py` は verifier / planner 向けの書き込み先制限（本節冒頭）とは別に、`agent_type` を問わず（メインエージェント含む）適用する判定を持つ。自分のブランチの計画票のタスク表を簡易的に解析し（plan_guard.py の raw_rows と同じ規則をこのファイル内にコピーして使う。import はしない）、以下のとおり判定する。

| 状況 | 判定 |
|---|---|
| `doing` / `review` の行が無い | 許可（この判定は素通り。既存の verifier/planner 向け判定へ進む） |
| `doing` / `review` の行が1件以上あり、対象が `vault/rules/` 配下への書き込み（Write/Edit/MultiEdit/NotebookEdit の `file_path`、または Bash のリダイレクト・`tee`・`sed -i`・`rm`/`mv`/`cp` 等） | ブロック：`doing/review 中は vault/rules/ を編集できません` と対象タスク ID を reason に含める |
| 上記に該当するが、環境変数 `HARNESS_ALLOW_RULES_WRITE` に `doing`/`review` の ID がすべて含まれる | 許可（明示解除。下記参照） |
| 上記に該当しない（`vault/rules/` 以外への書き込み） | 許可（この判定は素通り。既存の verifier/planner 向け判定へ進む） |

この判定は既存の verifier/planner 向け `ALLOWED` 判定より前に実行される。verifier・planner が `vault/rules/` に書こうとした場合も、doing/review 中ならこの判定で先に拒否される。

### 明示解除（ルール自体を変更するタスク用）

ルールファイルそのものを成果物とするタスクは、この判定に阻まれて1行も書けない。その場合だけ、人が起動時に環境変数で解除する。

```
HARNESS_ALLOW_RULES_WRITE=T-01 claude
```

- 値は解除を許すタスク ID の列（カンマまたは空白区切り）。`doing`/`review` の ID がすべて含まれる時だけ解除される
- 未設定・空・不一致、および `1` / `true` のような ID でない値では解除しない
- フックは Claude Code プロセスの環境を継承するため、作成エージェントが Bash 内で `export` しても届かない。実質的に人だけが解除できる
- 解除しても verifier・planner は `vault/rules/` に書けない（後段の `ALLOWED` 判定で拒否される）

## 13. 設計文書（`vault/designs/`）

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
