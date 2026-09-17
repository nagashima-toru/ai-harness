# キューログ（追記専用）

形式：`- YYYY-MM-DD HH:MM T-0001 doing→review attempt=1 補足`

- 2026-09-17 16:21 P-001 draft→approved tasks=T-0001 人が直接登録（初期構築）
- 2026-09-17 16:22 T-0001 todo→doing attempt=1
- 2026-09-17 16:22 T-0001 doing→review attempt=1
- 2026-09-17 16:23 T-0001 review→done attempt=1
- 2026-09-17 16:51 P-002 draft→approved tasks=T-0002
- 2026-09-17 16:52 T-0002 todo→doing attempt=1
- 2026-09-17 16:53 T-0002 doing→blocked attempt=1 受け入れ基準5が確認コマンドの性質上満たせない（todo.md は状態遷移で必ず変わる）
- 2026-09-17 16:54 T-0002 blocked→todo 回答を決定済みに追記（基準5を形式チェックに差し替え）
- 2026-09-17 16:54 T-0002 todo→doing attempt=1 再開（成果物は作成済み）
- 2026-09-17 16:54 T-0002 doing→review attempt=1
- 2026-09-17 16:55 T-0002 review→done attempt=1 verdict PASS、6件すべて note あり
- 2026-09-17 17:00 P-003 draft→approved tasks=T-0003
- 2026-09-17 17:00 T-0003 todo→doing attempt=1
- 2026-09-17 17:00 T-0003 doing→review attempt=1
- 2026-09-17 17:01 T-0003 review→done attempt=1 verdict PASS。ただし note が全件空（このセッションの verifier 定義が T-0002 更新前のまま読み込まれていたため）
- 2026-09-17 21:44 P-004 draft→approved tasks=T-0004
- 2026-09-17 21:45 T-0004 todo→doing attempt=1
- 2026-09-17 21:46 T-0004 doing→review attempt=1
- 2026-09-17 21:47 T-0004 review→done attempt=1 verdict PASS、6件すべて note あり。新しい形式検証を通過
