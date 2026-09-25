# T-01 提案：`.claude/settings.json` の `rm -rf` deny パターン見直し

対象：`.claude/settings.json` の `permissions.deny` にある以下の4行（60〜63行目）。

```json
"Bash(rm -rf *)",
"Bash(rm -fr *)",
"Bash(rm -r *)",
"Bash(rm -Rf *)",
```

この4行は `rm -rf` 系コマンドをリポジトリ内・外を問わず一律で拒否する。`permissions.allow` 側に
`/tmp` 用の `rm -rf` エントリは現状無いため、`vault/verdicts/P-20260925-vcs-finish-push-and-diff-criteria/T-01.json`
の各 `criteria[].note` に記録されている通り、`$(mktemp -d)` で作った使い捨てディレクトリを
`rm -rf` で後片付けする一般的なテストパターンすら実行できず、verifier は `$(mktemp -d)` をリポジトリ
内の固定パス（`/tmp/vftest_a` 等）に書き換え、事前クリーンアップの `rm -rf` を省略して回避してい
る。これは受け入れ基準の確認コマンドをverifierが原文と異なる形で実行していることになり、本来の
意図（誤字脱字なく確認コマンドをそのまま実行する）から外れる。

`.claude/settings.json` 自体は変更しない（決定済みの通り、どちらを採用するかは人が決める）。

## 案A

deny を絞る：リポジトリ内パスに限定するパターン群に置き換える。

```diff
     "deny": [
-      "Bash(rm -rf *)",
-      "Bash(rm -fr *)",
-      "Bash(rm -r *)",
-      "Bash(rm -Rf *)",
+      "Bash(rm -rf .)",
+      "Bash(rm -rf ./*)",
+      "Bash(rm -rf vault)",
+      "Bash(rm -rf vault/*)",
+      "Bash(rm -rf .claude)",
+      "Bash(rm -rf .claude/*)",
+      "Bash(rm -rf docs)",
+      "Bash(rm -rf docs/*)",
+      "Bash(rm -rf scripts)",
+      "Bash(rm -rf scripts/*)",
+      "Bash(rm -fr .)",
+      "Bash(rm -fr ./*)",
+      "Bash(rm -fr vault)",
+      "Bash(rm -fr vault/*)",
+      "Bash(rm -fr .claude)",
+      "Bash(rm -fr .claude/*)",
+      "Bash(rm -fr docs)",
+      "Bash(rm -fr docs/*)",
+      "Bash(rm -fr scripts)",
+      "Bash(rm -fr scripts/*)",
+      "Bash(rm -r .)",
+      "Bash(rm -r ./*)",
+      "Bash(rm -r vault)",
+      "Bash(rm -r vault/*)",
+      "Bash(rm -r .claude)",
+      "Bash(rm -r .claude/*)",
+      "Bash(rm -r docs)",
+      "Bash(rm -r docs/*)",
+      "Bash(rm -r scripts)",
+      "Bash(rm -r scripts/*)",
+      "Bash(rm -Rf .)",
+      "Bash(rm -Rf ./*)",
+      "Bash(rm -Rf vault)",
+      "Bash(rm -Rf vault/*)",
+      "Bash(rm -Rf .claude)",
+      "Bash(rm -Rf .claude/*)",
+      "Bash(rm -Rf docs)",
+      "Bash(rm -Rf docs/*)",
+      "Bash(rm -Rf scripts)",
+      "Bash(rm -Rf scripts/*)",
       "Bash(sudo *)",
```

### 説明
- `rm -rf` 系4パターンの一律 deny を、リポジトリのトップレベルディレクトリ（`.`・`vault/`・
  `.claude/`・`docs/`・`scripts/`）を明示的に指す相対パスへの `rm -rf`（および `-fr`/`-r`/`-Rf`
  各バリアント）だけを拒否するパターン群に置き換える。`.`（リポジトリルートそのもの）と
  `./*`（ルート直下すべて）、および4つのトップレベルディレクトリと配下（`vault/*` 等）への
  `rm -rf` は従来どおり拒否され続ける。つまり、このリポジトリで最も起きやすい事故（`rm -rf .`
  や `rm -rf vault/*` のような誤操作）は元の防止意図のまま防げる。
- 一方でこの方式は **パターンの列挙に依存する** ため、以下は拒否対象から漏れる（元の一律 deny
  より保護範囲が狭くなる）。
  - 上記5パターン以外のリポジトリ内パス（例：将来追加される新しいトップレベルディレクトリ、
    `vault/tasks/<id>/` のような深いネストパスを直接指定した `rm -rf`）
  - リポジトリを絶対パスで指した `rm -rf`（例：`rm -rf /Users/xxx/.../ai-harness/vault`）
  - `../` を含む相対パス（例：`rm -rf ../ai-harness`）
  - リポジトリ外の一般的な `rm -rf`（例：`rm -rf /tmp/xxx` や `rm -rf ~/somewhere`）は今回の
    目的どおり許可されるようになるが、副作用として「リポジトリ外なら何でも `rm -rf` できる」
    状態になる（`/etc` 等のシステムパスも技術的には対象外にはならないが、少なくとも deny の
    対象外になる点は元の一律ブロックより緩い）
  - 運用上、リポジトリ構成が変わるたびにこの deny リストのメンテナンスが必要になる

## 案B

allow を足す：`permissions.allow` に `/tmp` 用エントリを追加し、deny は現状維持する。

```diff
       "Bash(env *)"
+      ,"Bash(rm -rf /tmp/*)"
+      ,"Bash(rm -fr /tmp/*)"
+      ,"Bash(rm -r /tmp/*)"
+      ,"Bash(rm -Rf /tmp/*)"
     ],
     "deny": [
       "Bash(rm -rf *)",
       "Bash(rm -fr *)",
       "Bash(rm -r *)",
       "Bash(rm -Rf *)",
```
（実際に反映する際は末尾カンマの位置を通常の JSON 整形に合わせること。上のdiffは追加行の内容を
示すためのもので、カンマの付け方はそのまま貼らずに整形し直す想定）

### 説明
- `permissions.deny` の `Bash(rm -rf *)` / `Bash(rm -fr *)` / `Bash(rm -r *)` / `Bash(rm -Rf *)`
  の4行は変更しない。`permissions.allow` に `/tmp/` 配下だけを対象にした `rm -rf` 系4パターンを
  追加し、「`/tmp` の使い捨てディレクトリだけ片付けてよい」という意図を allow 側で明示しようとする
  案。
- deny を触らないため、`vault/`・`.claude/`・`docs/`・`scripts/` を含むリポジトリ内パスへの
  `rm -rf` は元の4行がそのまま残り、案A同様、従来どおり一律拒否され続ける（案Aのような
  パターン列挙の漏れは発生しない）。
- ただし下記「検証結果」の通り、**この案は本リポジトリの現行環境では機能しないことを実機確認済み**。
  `permissions.deny` に一致するコマンドは、たとえ `permissions.allow` に同じコマンドに一致する
  より具体的なパターンを追加しても拒否され続ける（deny が allow に優先する）。したがって案Bの
  ままでは `/tmp` 配下の `rm -rf` は許可されず、当初の目的（`$(mktemp -d)` の後片付けを通す）を
  達成できない。案Bを採用する場合は、単純な allow 追加ではなく deny 側のパターンそのものを
  変更する必要があり、実質的に案Aと同じ変更が要ることになる。

## 検証結果

Claude Code の `permissions.allow`/`permissions.deny` の優先順位（allow が deny に勝てるか）を、
このワークツリーの `.claude/settings.json` を一時的に書き換えて実機で検証した（検証後は
元の内容に戻し、`git status --porcelain -- .claude/settings.json` が空であることを確認済み）。

1. 変更前（現行の deny のみ）で `rm -rf /tmp/<使い捨てディレクトリ>` を実行 → 拒否された
   （`Permission to use Bash with command ... has been denied.`）。これは deny がそのまま効いて
   いる現状のベースライン。
2. `permissions.allow` に `"Bash(rm -rf /tmp/*)"` を一時的に追加し、`rm -rf /tmp/<使い捨て
   ディレクトリ>` を再実行 → **それでも拒否された**（同じ文言のエラー）。`&&` で連結した複合コマンド
   でも、単独の `rm -rf /tmp/xxx` 単体でも同じ結果だった。
3. 検証後、追加した allow エントリを削除して元の `.claude/settings.json` に戻し、
   `git status --porcelain -- .claude/settings.json` の出力が空であることを確認した。

**結論**：この環境（このリポジトリ・このバージョンの Claude Code）では、`permissions.deny` に
一致するコマンドは、より具体的な `permissions.allow` のパターンが追加されていても拒否される。
つまり **deny が allow に優先する**。この結果、案Bは「`permissions.deny` を変更しない」という
前提のままでは目的を達成できない。`rm -rf` の誤検知（false positive）を解消するには、案Aのように
`permissions.deny` 側のパターンそのものを狭める変更が必須である。
