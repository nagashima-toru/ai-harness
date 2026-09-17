# ロードマップ：ルール拡張ポイント（`vault/rules/`）

インストール先ごとに用意した「ルール」（コーディングルール・開発標準・方式設計・テスト標準・テスト観点など）を、作成エージェント・verifier・planner に渡せるようにする。ハーネス側にルールは同梱しない。置き場と読み込み口だけを用意する。

このファイルは `/plan` に渡すゴール文の下書き集。各プランの「`/plan` に渡す文」をそのまま貼れば planner が P-xxx / T-xxxx を起こす。ID は planner が採番するので、ここでは順序（①〜⑧）で呼ぶ。

## 決定事項（人からの回答、2026-09-17）

1. ディレクトリ名は `common` / `creator` / `verifier`（+ `planner`）で確定
2. 置き場は `vault/rules/` で確定（`.claude/rules/` は Claude Code 本体がメインコンテキストへ自動で読み込む機能と衝突するため避ける）
3. ⑧ 通し検証は従来どおり `claude -p --model sonnet "/run-queue"` の子プロセスで行う
4. 当初「任意」としていた ⑦-a（planner にも渡す）と ⑦-b（改ざん防止フック）は**先に入れる**。以下 ⑤・⑥ として本編に組み込んだ

## 0. 全体設計

### 置き場と振り分け
```
vault/rules/
  README.md      # 書き方・振り分けの説明（install.sh が複製）
  common/        # 作成エージェント・verifier・planner の全員に渡す
  creator/       # 作成エージェントだけに渡す
  verifier/      # verifier だけに渡す
  planner/       # planner だけに渡す
```
- 「全員 / 作成のみ / 検証のみ / 計画のみ」の4パターンは**ディレクトリで振り分ける**。frontmatter や索引ファイルは持たない（迷いどころを減らす）
- ファイルは `*.md`、小文字ケバブケース。読み込み順は `common/` → 役割ディレクトリ、各ディレクトリ内はファイル名順（決定的にする）
- 「全員に渡す」を `both/` ではなく `common/` と呼ぶのは、2者限定ではなく役割が増えても意味が変わらないため

### なぜ `.claude/rules/` ではなく `vault/rules/` か
Claude Code 本体に `.claude/rules/*.md` を自動でメインコンテキストに載せる機能がある。それを使うと「verifier だけに渡す」「planner だけに渡す」ができず、開始時に読む量も膨らむ。ハーネスの「エージェントが読む情報は `vault/` に集約し、開始時に読むものは小さく保つ」方針に合わせ、`vault/rules/` に置き、**着手時・検証時・計画時にだけ**読む。

### 読み込みの一本化
`scripts/rules.sh <creator|verifier|planner>` が、その役割に渡すファイルのパスを決定的順序で列挙する。作成エージェント（run-queue）・verifier・planner はこのスクリプトの出力を読む。フックやテストも同じスクリプトを使うので、振り分けの正しさを smoke.sh で検査できる。

### verifier とルールの関係（原則を崩さない）
verifier の原則「受け入れ基準に無い観点で落とさない」は維持する。ルールは**新しい基準を増やすものではなく、基準の判定方法を与えるもの**。
- 例：受け入れ基準「`vault/rules/` のコーディングルールに従っている」→ verifier は `verifier/` と `common/` のルールを根拠に真偽を判定し、`note` に参照したルールファイル名を書く
- 受け入れ基準がルールに触れていなければ、ルールを理由に FAIL にしない
- 作成側だけに渡したルール（`creator/`）は verifier から見えないので、それを根拠に落とすこともない

### 改ざん防止（⑥ で機械的に強制する）
作成エージェントがタスク中に `vault/rules/` を書き換えると、verifier の判定基準を自分で緩められる。run-queue の注意（③）で「タスク中は編集しない」と明記するだけでなく、⑥ で `agent_write_guard.py` を拡張し、`todo.md` に `doing` / `review` の行がある間はエージェント種別を問わず `vault/rules/` への書き込みを拒否する。

### 依存関係
```
① 仕様と置き場（common/creator/verifier/planner + テンプレ）
   ├─▶ ② rules.sh（3ロール対応）
   │     ├─▶ ③ run-queue（作成エージェント）─┐
   │     ├─▶ ④ verifier                    ─┼─▶ ⑦ install.sh と README ─▶ ⑧ 通し検証
   │     └─▶ ⑤ planner                     ─┘
   └─▶ ⑥ 改ざん防止フック（agent_write_guard.py 拡張）──────────────▶ ⑦
```
①→②→(③,④,⑤)→⑦→⑧ が主経路。⑥ は ① だけに依存し、②〜⑤ と並行して進めてよい。③④⑤ は互いに独立で順不同。

---

## ① 仕様と置き場を決める（契約）

**目的**：`vault/rules/` の仕様を `docs/vault-spec.md` に書き、空の置き場と説明 README、ルールファイルの雛形を用意する。コードは変えない。

**成果物**：`docs/vault-spec.md` の新節「ルール（`vault/rules/`）」（付随：`vault/rules/README.md`、`vault/rules/{common,creator,verifier,planner}/.gitkeep`、`vault/templates/rule.md`）

**`/plan` に渡す文**
```
/plan インストール先ごとに用意するルール（コーディングルール・開発標準・方式設計・テスト標準・テスト観点など）を作成エージェント・verifier・planner に渡す拡張ポイント「vault/rules/」の仕様を決め、置き場を作る。docs/vault-spec.md に新節「ルール（vault/rules/）」を追加し、以下を定める：(1) ディレクトリは vault/rules/common/（全員に渡す）・creator/（作成エージェントのみ）・verifier/（verifierのみ）・planner/（plannerのみ）の4つで、振り分けはディレクトリだけで行い frontmatter や索引は持たない、(2) ファイルは *.md・小文字ケバブケース、読み込み順は common/ → 役割ディレクトリ、各ディレクトリ内はファイル名順、(3) ルールは受け入れ基準を増やすものではなく基準の判定方法を与えるものであり、verifier は受け入れ基準がルールを参照する時だけルールを根拠にする、(4) 1ファイルは100行以内を目安にし話題ごとに分ける、(5) ハーネスはルールを同梱せずインストール先で書く、(6) doing/review 中のタスクがある間は vault/rules/ への書き込みをフックで拒否する（詳細は別タスクで実装するが仕様として明記する）。あわせて vault/rules/README.md（書き方・振り分け・例を20行以内）、vault/rules/common/.gitkeep・creator/.gitkeep・verifier/.gitkeep・planner/.gitkeep、vault/templates/rule.md（見出し：目的 / ルール / 確認方法 の3つ）を作る。このプランではスクリプト・スキル・エージェント定義・install.sh・README.md は変更しない。
```

**受け入れ基準の候補**
- `docs/vault-spec.md` に `vault/rules/` の節があり、`common` / `creator` / `verifier` / `planner` の4語を含む（`grep -c 'vault/rules/' docs/vault-spec.md` ≥ 1）
- `vault/rules/README.md` が存在し20行以内
- `vault/rules/common/.gitkeep`、`creator/.gitkeep`、`verifier/.gitkeep`、`planner/.gitkeep` が存在する
- `vault/templates/rule.md` が存在し、見出しが `目的 / ルール / 確認方法` の3つ
- `bash scripts/smoke.sh | tail -1` が `fail=0` を含む（既存の検証が壊れていない）

**決定済みにしておくこと**
- ディレクトリ名は `common` / `creator` / `verifier` / `planner` で固定
- 索引ファイル・frontmatter は作らない
- 100行の目安は仕様に書くだけで、機械的には強制しない
- 改ざん防止フックの実装は⑥で行う。ここでは仕様に「doing/review 中は書き込み拒否」と明記するだけでよい

---

## ② ルール解決スクリプト `scripts/rules.sh`

**目的**：役割名を受け取り、渡すべきルールファイルのパスを決定的順序で標準出力に列挙する。作成側・verifier・planner・テストが同じ出力を使う。

**成果物**：`scripts/rules.sh`（付随：`scripts/smoke.sh` にケース追加）

**`/plan` に渡す文**
```
/plan scripts/rules.sh を新規作成する。使い方は `bash scripts/rules.sh <creator|verifier|planner>`。docs/vault-spec.md の「ルール（vault/rules/）」節に従い、vault/rules/common/*.md をファイル名順に列挙し、続けて vault/rules/<役割>/*.md をファイル名順に列挙して、1行1パス（リポジトリルートからの相対パス）で標準出力に出す。該当ファイルが無ければ何も出さず exit 0。引数が無い・creator/verifier/planner 以外なら usage を標準エラーに出して exit 2。vault/rules/ 自体が無くても exit 0。CLAUDE_PROJECT_DIR があればそれをルートに、無ければスクリプト自身の位置から求める。scripts/smoke.sh に「== rules.sh ==」節を追加し、(a) common と creator にファイルを置いて creator を呼ぶと common→creator の順で列挙される、(b) verifier を呼ぶと creator/ のファイルが含まれない、(c) planner を呼ぶと common/ のファイルは含まれるが creator/・verifier/ は含まれない、(d) 空なら無出力 exit 0、(e) 不正な引数で exit 2、の5件を検査する。既存のテストは変更しない。
```

**受け入れ基準の候補**
- `bash scripts/rules.sh creator` が `common/` → `creator/` の順で列挙する（smoke のケース (a) が ok）
- `bash scripts/rules.sh verifier` の出力に `creator/` が含まれない（ケース (b)）
- `bash scripts/rules.sh planner` の出力に `common/` は含まれ `creator/`・`verifier/` は含まれない（ケース (c)）
- ルールが無い時は無出力で exit 0（ケース (d)）
- 引数不正で exit 2（ケース (e)）
- `bash scripts/smoke.sh | tail -1` が `fail=0` を含み pass 件数が既存より増えている

**決定済みにしておくこと**
- 出力は相対パスのみ。内容の連結（cat）はしない。読む側が Read する
- `find` ではなく glob（`for f in dir/*.md`）で済ませ、サブディレクトリは辿らない

**依存**：①

---

## ③ 作成エージェントにルールを渡す（run-queue）

**目的**：run-queue の「2. 作る」で、着手時に `scripts/rules.sh creator` の出力を読んでから成果物を作る。

**成果物**：`.claude/skills/run-queue/SKILL.md`（付随：`CLAUDE.md` の「役割」に1行）

**`/plan` に渡す文**
```
/plan run-queue スキル（.claude/skills/run-queue/SKILL.md）に、作成エージェントがルールを読む手順を追加する。「## 2. 作る」の手順1の直後に、`bash scripts/rules.sh creator` を実行して列挙されたファイルをすべて読み、以降の成果物作成でそれに従うことを追加する。列挙が空なら何もしない。「## 注意」に「タスク中は vault/rules/ を編集しない（verifier の判定基準を自分で変えないため。フックでも拒否される）」を追加する。タスク票の「進捗」に読んだルールファイル名を1行書く手順も加える。CLAUDE.md の「## 役割」の作成エージェントの行に、着手時に vault/rules/（common, creator）を読む旨を追記し、全体を60行以内に保つ。verifier.md・planner.md・フック・install.sh・README.md は変更しない。
```

**受け入れ基準の候補**
- `SKILL.md` の「## 2. 作る」に `rules.sh creator` を含む行がある（`grep -c 'rules.sh creator' .claude/skills/run-queue/SKILL.md` ≥ 1）
- 「## 注意」に `vault/rules/` を編集しない旨の行がある
- `CLAUDE.md` に `vault/rules/` の記述があり、全体が60行以内
- `bash scripts/smoke.sh | tail -1` が `fail=0` を含む

**決定済みにしておくこと**
- ルールを読むタイミングは「タスク票を読んだ直後」。セッション開始時には読まない（開始時の読み物を増やさない）
- 進捗への記録は「読んだルール: a.md, b.md」の1行で十分

**依存**：②

---

## ④ verifier にルールを渡す

**目的**：verifier が `scripts/rules.sh verifier` の出力を「読むもの」に加え、受け入れ基準がルールを参照する時の判定根拠にする。原則「基準に無い観点で落とさない」は維持する。

**成果物**：`.claude/agents/verifier.md`（付随：`docs/vault-spec.md` の verdict 節に note の書き方を1〜2行）

**`/plan` に渡す文**
```
/plan verifier エージェント定義（.claude/agents/verifier.md）にルールの読み込みを追加する。「## 読むもの（これだけ）」に「`bash scripts/rules.sh verifier` が列挙するルールファイル（無ければ読まない）」を1項目追加する。「## 手順」に、受け入れ基準がルール（vault/rules/ 配下のファイル名や「コーディングルールに従う」等）を参照している行は、該当ルールファイルを根拠に真偽を判定し、note に参照したルールファイルのパスを書くことを追加する。「## 禁止」に「受け入れ基準がルールを参照していない行を、ルールを理由に FAIL にすること」を追加する。docs/vault-spec.md の verdict.json 節の note の説明に、ルールを根拠にした場合は参照ファイルを書く旨を1〜2行追記する。run-queue・planner・フック・install.sh・README.md は変更しない。
```

**受け入れ基準の候補**
- `verifier.md` の「読むもの」に `rules.sh verifier` を含む行がある
- `verifier.md` の「禁止」に、ルールを参照しない基準をルールで落とさない旨の行がある
- `docs/vault-spec.md` の verdict 節に、ルール参照時の note の書き方が追記されている（`grep -c 'vault/rules' docs/vault-spec.md` が①より増える）
- `bash scripts/smoke.sh | tail -1` が `fail=0` を含む

**決定済みにしておくこと**
- verifier はルールを Bash で cat せず Read で読む（agent_write_guard の Bash 判定と無関係だが、作法を揃える）
- `creator/` のルールは verifier に見せない。見えないものを根拠にできないのが振り分けの意味

**依存**：②（③・⑤とは独立。順不同）

---

## ⑤ planner にルールを渡す

**目的**：planner が `scripts/rules.sh planner` の出力を「読むもの」に加え、タスク分割・受け入れ基準の下書きに方式設計やテスト観点のルールを反映する。

**成果物**：`.claude/agents/planner.md`（付随：`docs/vault-spec.md` の粒度基準節に1〜2行）

**`/plan` に渡す文**
```
/plan planner エージェント定義（.claude/agents/planner.md）にルールの読み込みを追加する。「## 読むもの」に「`bash scripts/rules.sh planner` が列挙するルールファイル（無ければ読まない。common/ と planner/ のみで、creator/・verifier/ は読まない）」を1項目追加する。「## 手順」に、タスク票の「受け入れ基準」や「決定済み」を書く際、読んだルールに具体的な基準（命名規則・方式設計・テスト観点など）があれば反映すること、ルールの内容を要約するだけで受け入れ基準の行数上限（3〜7行）を超やさないことを追加する。「## 禁止」の既存項目はそのまま維持し、新たに「ルールに無い内容を勝手に基準へ追加すること」は禁止しない（ルールは参考情報であり、ゴールから外れない限り反映してよい）旨を明確にする一文を添える。docs/vault-spec.md の「9. 粒度の基準」に、ルールがある場合は受け入れ基準に反映する旨を1〜2行追記する。run-queue・verifier・フック・install.sh・README.md は変更しない。
```

**受け入れ基準の候補**
- `planner.md` の「読むもの」に `rules.sh planner` を含む行がある
- `planner.md` の「手順」に、読んだルールを受け入れ基準へ反映する旨の記述がある
- `docs/vault-spec.md` の「9. 粒度の基準」に `vault/rules` への言及がある（`grep -c 'vault/rules' docs/vault-spec.md` が④より増える）
- `bash scripts/smoke.sh | tail -1` が `fail=0` を含む

**決定済みにしておくこと**
- planner が読むのは `common/` と `planner/` のみ。`creator/`・`verifier/` は読まない（役割分離を保つ）
- ルール反映によって受け入れ基準が3〜7行を超えそうな場合は、既存の粒度基準を優先し、ルールの反映は要約に留める

**依存**：②（③・④とは独立。順不同）

---

## ⑥ 改ざん防止フック（`agent_write_guard.py` 拡張）

**目的**：`doing` / `review` 中のタスクがある間、エージェント種別を問わず（メインエージェントを含む）`vault/rules/` への書き込みをフックで拒否し、verifier の判定基準をタスク中に緩められないようにする。

**成果物**：`.claude/hooks/agent_write_guard.py`（既存の verifier/planner 向け制限は変更しない。付随：`scripts/smoke.sh` にケース追加、`docs/vault-spec.md` に判定表を1節追加）

**`/plan` に渡す文**
```
/plan .claude/hooks/agent_write_guard.py（PreToolUse フック）に、エージェント種別に関わらず適用する新しい判定を追加する：vault/todo.md の「## タスク」表に status が doing または review の行が1件でもあれば、Write/Edit/MultiEdit/NotebookEdit で file_path が vault/rules/ 配下、または Bash コマンドが vault/rules/ 配下へのリダイレクト・tee・sed -i・rm/mv/cp 等の書き込み操作を含む場合、既存の verifier/planner 向け ALLOWED 判定より前にこの判定を行い、agent_type を問わず deny する（reason に「doing/review 中は vault/rules/ を編集できません」と対象タスク ID を含める）。todo.md の解析は .claude/hooks/todo_guard.py の raw_rows/parse_tasks と同じ規則をこのファイル内に簡潔にコピーして使う（import はしない。他のフックは変更しない）。todo.md が存在しない、または doing/review の行が無ければ、この新判定は素通りし既存の verifier/planner 向け判定に進む。scripts/smoke.sh の「== agent_write_guard.py ==」節に、(a) doing 中に agent_type 無し（メインエージェント）で vault/rules/ 配下へ Write → 拒否、(b) doing/review が無い時にメインエージェントが vault/rules/ 配下へ Write → 許可、(c) doing 中に verifier が vault/verdicts/ へ Write（従来どおり）→ 許可、の3件を追加する。docs/vault-spec.md に、この新しい判定を1節（表形式で可）追記する。
```

**受け入れ基準の候補**
- doing 中にメインエージェント（`agent_type` 無し）が `vault/rules/` 配下へ Write すると deny になる（smoke ケース (a) が ok）
- doing/review が無い時は同じ Write が許可される（ケース (b)）
- 既存の verifier/planner 向け判定（doing の有無に関わらず動く従来の制限）が壊れていない（ケース (c) および既存ケース全件）
- `docs/vault-spec.md` に新しい判定の説明節がある（`grep -c 'agent_write_guard' docs/vault-spec.md` ≥ 1）
- `bash scripts/smoke.sh | tail -1` が `fail=0` を含み pass 件数が既存より増えている

**決定済みにしておくこと**
- todo.md 解析ロジックのコピーは `todo_guard.py` が `stop_gate.py` からコピーした前例（決定記録済み）と同じやり方でよい
- Bash コマンドの書き込み判定は既存の `BASH_WRITE_PATTERNS` を再利用してよい。対象パスの抽出（リダイレクト先）も既存の正規表現を流用する
- 新判定は「既存の ALLOWED 判定より前に」実行する（verifier が `vault/verdicts/` に書く分には影響しないが、verifier・planner が `vault/rules/` に書こうとした場合も doing/review 中ならこの新判定で先に deny されてよい。二重に拒否されても実害は無い）

**依存**：①（②〜⑤とは独立。並行して進めてよい）

---

## ⑦ install.sh と README（拡張ポイントを配る・説明する）

**目的**：インストール先に `vault/rules/` の雛形（4ディレクトリ）と `scripts/rules.sh` が届き、README に拡張ポイントの使い方が書いてある状態にする。

**成果物**：2タスクに分ける
- T-a：`scripts/install.sh`（`vault/rules/README.md`・4つの `.gitkeep`・`vault/templates/rule.md`・`scripts/rules.sh` を複製。既存は上書きしない）
- T-b：`README.md` に「## 拡張ポイント（ルール）」節（付随：`docs/runbook.md` に「ルールを足す」手順）

**`/plan` に渡す文**
```
/plan ルール拡張ポイントをインストール先に配り、README で説明する。2タスクに分ける。T-a：scripts/install.sh を更新し、vault/rules/README.md、vault/rules/common/.gitkeep・creator/.gitkeep・verifier/.gitkeep・planner/.gitkeep、vault/templates/rule.md、scripts/rules.sh を複製対象に加える（既存ファイルは上書きしない方針を維持し、copy_if_absent を使う）。scripts/smoke.sh には手を入れず、受け入れ基準では一時ディレクトリへ install.sh を実行して上記ファイルが存在すること・2回目の実行で skip になることを確認する。T-b（after=T-a）：README.md に「## 拡張ポイント（ルール）」節を追加し、(1) vault/rules/common・creator・verifier・planner の4ディレクトリと「全員／作成のみ／検証のみ／計画のみ」の対応、(2) インストール先で書く前提でありハーネスはルールを同梱しないこと、(3) 受け入れ基準からルールを参照する書き方の例を1つ、(4) doing/review 中はルールを編集できない（フックで拒否される）こと、を25行以内で書く。「## 構成」のツリーに vault/rules/ と scripts/rules.sh を加える。docs/runbook.md に「ルールを足す」手順（ファイルを置く→どのディレクトリか決める→受け入れ基準から参照する）を5行以内で追加する。
```

**受け入れ基準の候補（T-a）**
- `bash scripts/install.sh <一時dir>` 後に `vault/rules/README.md`、4つの `.gitkeep`、`vault/templates/rule.md`、`scripts/rules.sh` が存在する
- 同じ一時 dir にもう一度実行すると、それらが `skip` になる
- `bash scripts/smoke.sh | tail -1` が `fail=0` を含む

**受け入れ基準の候補（T-b）**
- `README.md` に `## 拡張ポイント` の見出しがあり、節が25行以内で `common` / `creator` / `verifier` / `planner` を含む
- `README.md` の構成ツリーに `vault/rules/` と `rules.sh` がある
- `docs/runbook.md` に「ルールを足す」の手順がある

**決定済みにしておくこと**
- README の節の位置は「## 使い方」と「## 仕組み」の間
- install.sh は `vault/rules/` の中身（ユーザーが書いたルール）を絶対に上書きしない。README.md と .gitkeep だけ配る

**依存**：③・④・⑤・⑥

---

## ⑧ 通し検証（一時インストール先でルールと改ざん防止フックが効くことを確かめる）

**目的**：ハーネス本体にルールを置かず、一時ディレクトリに install して仮のルールを置き、`claude -p "/run-queue"` で作成側・verifier・planner がルールを参照したこと、および doing 中に `vault/rules/` への書き込みが拒否されることを確認する。結果を `docs/decisions.md` に記録する。

**成果物**：`docs/decisions.md` への追記（通し検証の結果と、判明した既定値）

**`/plan` に渡す文**
```
/plan ルール拡張ポイントの通し検証を行い docs/decisions.md に記録する。手順：(1) mktemp -d した一時ディレクトリに bash scripts/install.sh で複製し git init する、(2) vault/rules/common/naming.md（例：シェルスクリプトの関数名は snake_case）と vault/rules/verifier/check.md（例：確認観点）を仮に置く、(3) そこで小さなタスク（例：scripts/hello.sh を作る。受け入れ基準に「vault/rules/common/naming.md に従っている」を含める）を todo.md に直接登録し、claude -p --model sonnet "/run-queue" を子プロセスで実行する、(4) タスク票の進捗に読んだルールが記録され、verdict.json の該当 criteria の note にルールファイルのパスが書かれていることを確認する、(5) 別途 doing 中の todo.md を用意し、agent_write_guard.py に vault/rules/ 配下への Write を試して deny されることを直接確認する（フック単体呼び出しでよい）、(6) 結果・所要時間・気付いた既定値を docs/decisions.md に1件1行で追記する。一時ディレクトリはコミットしない。ハーネス本体の vault/rules/ にはファイルを置かない。
```

**受け入れ基準の候補**
- `docs/decisions.md` に通し検証の行が追記されている（`grep -c 'vault/rules' docs/decisions.md` ≥ 1）
- 検証で得た verdict の note に `vault/rules/` のパスが含まれていた（決定済みに証拠の貼り方を書く：decisions.md の行に note を引用）
- doing 中の `vault/rules/` への Write が deny されたことを確認した記録が decisions.md にある
- ハーネス本体の `vault/rules/{common,creator,verifier,planner}/` に `.gitkeep` 以外のファイルが無い
- `bash scripts/smoke.sh | tail -1` が `fail=0` を含む

**決定済みにしておくこと**
- 一時インストール先は `claude -p` の前に一度対話起動して信頼する必要がある。無人で通らない場合は手順を decisions.md に書いて blocked にしてよい
- 通し検証の生成物（一時 dir）は残さない

**依存**：⑦

---

## 任意：さらに後で足すもの（⑧ の後に必要なら）

必要になったときに `/plan` に渡す。今は起こさない。

| 候補 | 何を | 何のために |
|---|---|---|
| a. タスク単位の絞り込み | タスク票の「入力」に `rules: a.md, b.md` と書けばそのファイルだけ渡す | ルールが増えた時に読む量を抑える |
| b. フックで自動注入 | `SessionStart` / `SubagentStart` フックの `additionalContext` で `rules.sh` の出力を注入し、「読み忘れ」を無くす | 指示ベースの読み込みを機械化する。SubagentStart でコンテキスト注入できるかは要調査 |
| c. サイズ警告 | `rules.sh` に合計行数を数えて目安超過で標準エラーに警告 | 開始時の読み物を小さく保つ方針の維持 |
