---
id: D-20261010-async-agent-wait
---
# ゴール
`run_in_background: false` を指定しても Agent 呼び出し（creator・planner・verifier）がバックグラウンドで起動する環境で、run・plan が完了を正しく待ち、ハングを一定の基準で見分けて復旧できるようにする。あわせて creator の worktree を `.claude/` の外（リポジトリの外）に置き、バックグラウンドの creator が worktree 内の Edit で止まる事象（#157 前半）の原因になりうる要素を取り除く。対象は Issue #147 と、トリアージで統合した #157 の前半。

## 決定事項
人に聞いて確定した回答。以降のフェーズはこれを前提にする。1件1行。

| 決めたこと | なぜ |
|---|---|
| 非同期化は環境変数（`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`）で前景に固定せず、run・plan の手順に「バックグラウンドに回った時の待ち方」を書いて対応する | 人の選択。公式ドキュメント上、対話セッションは fork モードが既定で subagent は常にバックグラウンドになり前景を要求できない。env で固定すると Bash の `run_in_background` など他のバックグラウンド機能も止まるため、手順側で吸収する |
| 待ち方は「ターンを終えて完了通知を待つ」を基本にする。Agent ツールの結果が「Async agent launched」等の起動通知だった時は、そのタスクの結果待ちとして扱い、完了通知が来るまで手順4（review）・手順6（verdict 判定）に進まない | 呼び出しが同期で返る前提の手順3・5を、非同期の時も同じ順序で通すため |
| stop_gate.py の判定は変えず、ブロック時のメッセージだけを変える。記録行（`- <日時> <id> worktree path=...`）の無い doing では「creator の完了通知を待っている場合は、そのままターンを終えて通知を待つ。待っていないなら verifier を実行する」旨の文面にする | 人の選択（推奨案）。記録行の無い doing は「creator 実行中」と「creator が中断して終わった」を区別できないため、ゲートは緩めない。対話実行では `stop_hook_active` で2回目の停止は許可されるので、待ちのターンが詰まることはない |
| バックグラウンドに回った creator・verifier のハングの基準は「出力ファイル（transcript）の最終更新から10分進まない」とする。同期で返らない呼び出しの既存の目安（15分、issue #48）は据え置く | 人の選択（推奨案）。#157 では4分・15分の停止が観測された。10分は確認コマンドの長い実行を誤判定しにくく、15分より早く復旧できる |
| ハングと判定したら TaskStop で止め、既存の「ハング時の復旧」と同じ手順（creator は worktree 破棄＋attempt+1、上限で blocked。verifier は worktree を残して再呼び出し、2回で blocked）で扱う。`--note` に「ハング」の語を含める | 復旧手順を2系統にしないため |
| creator の worktree を `.claude/` の外に置く。Claude Code の `WorktreeCreate`・`WorktreeRemove` フックで worktree の作成を置き換える | 人の選択。保護パス（`.claude/`）にかかわる権限確認の可能性を断つため。公式ドキュメント上 `.claude/worktrees/` は保護パスの例外だが、#157 で止まった原因を確定できていないので、置き場の側でも取り除く |
| worktree の置き場は既定で `~/.cache/ai-harness/worktrees/<リポジトリのディレクトリ名>-<リポジトリの絶対パスの sha1 先頭8桁>/<name>` とし、環境変数 `HARNESS_WORKTREE_ROOT` で `~/.cache/ai-harness/worktrees` の部分を差し替えられる | 公式ドキュメント上、フックで作る場所はどのリポジトリにも含まれない場所である必要がある。リポジトリごとに分けて名前の衝突を避ける |
| `.claude/settings.json` の `permissions.additionalDirectories` に `~/.cache/ai-harness/worktrees` を入れる | オーケストレーター・verifier が worktree のファイルを絶対パスで読む・creator が編集する時に、作業ディレクトリの外として権限確認が出ないようにするため |
| `WorktreeCreate` フックは `git -C <入力の cwd のリポジトリ> worktree add -b worktree-agent-<suffix> <パス> HEAD` で作り、パスだけを標準出力に出す（git の出力は標準エラーへ）。`<suffix>` は入力の `name` から先頭の `agent-` を除いたもの | フックを使うと `worktree.baseRef: "head"` は効かないため、フック自身が現在の HEAD（計画ブランチ）から分岐させる。ブランチ名は transition.py・discard_worktree.sh が検査する `worktree-agent-` 接頭辞にそろえる |
| `WorktreeRemove` フックは何も消さずに終了コード0で終わる | worktree の破棄は今どおり transition.py（done・FAIL の再試行・差分ゲートの差し戻し）と `scripts/discard_worktree.sh` が行う。Claude Code 側の自動削除で creator の成果物を失わないため |

## 依存関係
- フェーズ1 → フェーズ2（直列）
- フェーズ1は待ち方・ハング基準・stop_gate の文面だけで完結し、worktree の置き場には依存しない。フェーズ2は最終フェーズとして設計文書の削除を含むため後に置く

---

## フェーズ1 Agent 呼び出しが非同期になった時の待ち方とハング基準

### ゴール文
run・plan の Agent 呼び出し（creator・planner・verifier）が `run_in_background: false` を指定してもバックグラウンドで起動して即座に戻る場合の扱いを決める。`.claude/skills/run/SKILL.md` の手順3・手順5・「ハング時の復旧」と `.claude/skills/plan/SKILL.md` の手順4に、起動通知が返った時はターンを終えて完了通知を待ち、通知が来るまで後続の手順に進まないことと、出力ファイル（transcript）の最終更新から10分進まなければハングとみなして既存の復旧手順で扱うことを書く。`.claude/hooks/stop_gate.py` は判定を変えず、記録行の無い doing でブロックする時のメッセージを「creator の完了通知を待っているなら、そのままターンを終えて待つ」旨に変え、`docs/vault-spec.md` 9節の表と `scripts/smoke.sh` をそれに合わせる。設計文書は `vault/designs/D-20261010-async-agent-wait.md`。

### 受け入れ基準の候補
- `.claude/skills/run/SKILL.md` の手順3と手順5に、Agent ツールの結果が起動通知（バックグラウンド起動）だった時は完了通知が来るまで手順4・手順6に進まず、ターンを終えて待つことが書かれている（`grep -n "完了通知" .claude/skills/run/SKILL.md` が手順3・手順5の範囲にそれぞれ1行以上当たる）
- `.claude/skills/run/SKILL.md` の「ハング時の復旧」に、バックグラウンドの呼び出しは出力ファイルの最終更新から10分進まなければハングとみなし TaskStop で止めて既存の復旧手順で扱うこと、同期の呼び出しの目安15分は据え置くことが書かれている（`grep -n "10分" .claude/skills/run/SKILL.md` が1行以上）
- `.claude/skills/plan/SKILL.md` の planner 呼び出しの手順に、起動通知が返った時は完了通知を待ってから手順5以降に進むことが書かれている
- 記録行の無い doing・verdict 無しの時、`stop_gate.py` は今どおり block を返し、reason に「完了通知」の語を含む。記録行のある doing・review の verdict 無しの reason は今の文面のまま（`bash scripts/smoke.sh` が終了コード0で、この2通りを確かめるケースが含まれている）
- `docs/vault-spec.md` 9節の stop_gate の表で、「verdict が無い」行に記録行の無い doing の時のメッセージの違いが書かれている

### 決定済み
- 判定（block/allow）は1つも変えない。変えるのは reason の文面だけ。記録行の有無は `vault/log/<計画ID>.md` にその id の `- <日時> <id> worktree path=` で始まる行があるかで見る（書式の正本は `docs/vault-spec.md` 7節）。log が無い・読めない時は「記録行が無い」として扱う
- 記録行の無い doing の reason の例：「`[stop_gate] <計画ID>/<id> は doing で、まだ creator の記録行がありません。creator の完了通知を待っている場合は、そのままターンを終えて通知を待ってください（2回目の停止は許可されます）。待っていないなら creator・verifier を実行してください。`」。文言は多少変えてよいが「完了通知」の語を含める
- 環境変数 `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` は settings.json に入れない。手順にもそれを使う指示を書かない（決定事項）
- 起動通知の見分け方は、Agent ツールの結果に「Async agent launched」「バックグラウンド」等の起動を表す文言があり、成果物の完了報告（creator の「blocked: ...」や完了の要約）が無いこと、と書く。文言の完全一致に頼らない書き方にする
- 出力ファイルのパスは起動通知に含まれるものを使い、更新時刻は `stat` などで見る。パスが分からない時はハングを判定せず、人に状況を報告して待つ、と書く
- 無人実行（`scripts/run_unattended.py`）の扱いは変えない（`HARNESS_RUN_TIMEOUT` で止める既存の仕組みのまま）
- 手順の「`run_in_background: false` を指定する」は消さない（指定は残し、それでも非同期になった時の扱いを足す）

### 依存
-

---

## フェーズ2 worktree を `.claude/` の外に置く（最終フェーズ）

### ゴール文
creator の worktree を `.claude/worktrees/` ではなくリポジトリの外に作る。Claude Code の `WorktreeCreate` フック（新規スクリプト `.claude/hooks/worktree_create.py`）で `${HARNESS_WORKTREE_ROOT:-~/.cache/ai-harness/worktrees}/<リポジトリのディレクトリ名>-<リポジトリの絶対パスの sha1 先頭8桁>/<name>` に、現在の HEAD から `worktree-agent-<suffix>` ブランチで `git worktree add` し、パスだけを標準出力に出す。`WorktreeRemove` フック（`.claude/hooks/worktree_remove.py`）は何も消さずに終了コード0で終わる。`.claude/settings.json` にこの2つのフックと `permissions.additionalDirectories` の `~/.cache/ai-harness/worktrees` を足し、`scripts/merge_settings_json.py` がインストール先にもこれらを冪等に足せるようにする。`docs/vault-spec.md` の記録行の例のパスなど、`.claude/worktrees/` を前提にした記述を新しい置き場に合わせる。最後に、決定事項のうち docs に無いものを `docs/decisions.md` に追記し、設計文書 `vault/designs/D-20261010-async-agent-wait.md` を削除する。

### 受け入れ基準の候補
- 一時ディレクトリに作った git リポジトリで、`{"cwd": "<リポジトリ>", "name": "agent-abc123"}` を標準入力に渡して `python3 .claude/hooks/worktree_create.py` を `HARNESS_WORKTREE_ROOT=<一時ディレクトリ>` 付きで実行すると、終了コード0で、標準出力の1行が `<HARNESS_WORKTREE_ROOT>/` の下のパスで、そのパスが `git -C <リポジトリ> worktree list` に `worktree-agent-abc123` ブランチで現れ、その HEAD が元のリポジトリの HEAD と一致する（`bash scripts/smoke.sh` にこのケースがあり終了コード0）
- `python3 .claude/hooks/worktree_remove.py` は worktree を消さずに終了コード0で終わる（smoke.sh にケースがある）
- `.claude/settings.json` に `hooks.WorktreeCreate`・`hooks.WorktreeRemove` と `permissions.additionalDirectories` の `~/.cache/ai-harness/worktrees` がある（`jq -e '.hooks.WorktreeCreate and .hooks.WorktreeRemove and (.permissions.additionalDirectories|index("~/.cache/ai-harness/worktrees"))' .claude/settings.json` が終了コード0）
- `scripts/merge_settings_json.py` で既存の settings.json にマージすると上の2フックと `additionalDirectories` の値が足され、2回目は `skip` になる（smoke.sh にケースがある）
- `transition.py`・`scripts/discard_worktree.sh` が、新しい置き場に作った worktree（`worktree-agent-` ブランチ）を今どおり受け付ける（smoke.sh の既存の transition.py のケースが新しい置き場でも通る、または新しい置き場で review→done を通すケースがある）
- 決定事項のうち docs に無いものを `docs/decisions.md` に追記し、設計文書を削除する（`test ! -e vault/designs/D-20261010-async-agent-wait.md`）

### 決定済み
- フックの入力 JSON の `cwd` からリポジトリのルートを `git rev-parse --show-toplevel` で求める。worktree の中から呼ばれた時も、`git rev-parse --git-common-dir` からメインのリポジトリを求め、そのディレクトリ名と絶対パスの sha1 で置き場を決める
- `<suffix>` は入力の `name` から先頭の `agent-` を1回だけ除いたもの。`name` が無い・空の時は終了コード1で失敗させる（Claude Code が作成失敗として扱う）
- 置き場の親ディレクトリは `mkdir -p` 相当で作る。同じパスが既にある時は終了コード1で失敗させる（上書きしない）
- `.worktreeinclude` はこのリポジトリに無いので、フックでのファイルのコピーは実装しない
- `WorktreeRemove` は入力を読み捨てて終了コード0。標準出力に何も出さない
- `.gitignore` の `.claude/worktrees/` と、`scripts/install.sh`・`scripts/smoke.sh` の `.claude/worktrees` の除外は、旧い worktree が残る導入先のために残す
- `scripts/merge_settings_json.py` の docstring の「足すのは次の3つだけ」を、`permissions.additionalDirectories`（src にあって dst に無い文字列だけを末尾に追加）を含めた形に直す。`hooks.<EventName>` は既存の汎用処理で足されるので、新しい EventName でも動くことを smoke.sh で確かめる
- `worktree.baseRef: "head"` は settings.json に残す（フックが失敗した環境や、フックを入れていない導入先のため）
- docs の更新は `docs/vault-spec.md`（記録行の例のパス、worktree の置き場の説明）と `docs/install.md`（`HARNESS_WORKTREE_ROOT` と置き場の説明）に限る
- 設計文書の削除は creator がタスクの成果物として行う（成果物に `vault/designs/` を宣言する。差分ゲートの禁止対象ではない）。このタスクは設計文書を読む他のタスクすべての後に `after` で依存させて置く

### 依存
フェーズ1

---

## 今回やらないこと
- `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` による subagent の前景固定（決定事項で不採用）
- stop_gate.py の判定の変更（記録行の無い doing を許可する案は不採用。文面の変更だけ行う）
- `.claude/worktrees/` に残った旧い worktree の移行・自動削除（人が `git worktree list` を見て片付ける）
- #157 後半（旧形式検出の正規表現）。#150・#153 前半とまとめて別の `/plan` で扱う（トリアージ済み）
- バックグラウンドの subagent が権限確認で止まる事象の、置き場以外の原因の調査（フェーズ2の後も再発したら別 Issue にする）
