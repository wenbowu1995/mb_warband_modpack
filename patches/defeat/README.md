# defeat 补丁 · 战败惩罚（同伴去留 / 物品缴获 / 关押时长）

> 生成器函数：`build-module.ps1` 的 `Apply-Defeat`。参数见 `params.md` 的「战败惩罚参数（defeat）」表。
> 背景与完整机制见 [战斗失败惩罚专题](../../../../docs/warband-defeat-penalty.md)。

## 现在的规则（2026-11-21 第二版）

| 项 | 原版 | 现在 |
|---|---|---|
| 同伴战败去留 | 50% 留队；50% 离队（有敌方城镇时 75% 关地牢、25% 散落酒馆） | **75% 留队；25% 离队**。离队者只要附近有敌方城镇就**必被关**（找赎金经纪人花钱赎回）；**被中立势力（盗贼/逃兵等非王国）打败时同伴全部留队**（离队判定前先校验击败方阵营，不在王国区间就跳过整个分支） |
| 背包物品 | 按类别逐件缴：杂货 20%、马 15%、武器 5%、护甲/靴/盾 5% | **背包每件 50%**；**书籍一律不缴**；**身上装备（武器/护甲/马）完全不缴** |
| 装备栏 | 含在遍历范围内、会被缴 | 跳过（槽 0-9 不动） |
| 玩家被俘关押时长 | 野外 18-30h / 城堡 16-22h | **小时数 - 玩家等级/3，下限 4h**（等级 20→约 -6h，30→-10h，35→-11h）；`关押时长等级除数` 填 0 恢复原版 |
| 金币损失 | 10%~20% | 保持原版 |
| 永久属性伤害 | 按运气判定 | 保持原版 |
| 士气离队 | `<20` 时触发对话 | 保持原版（可说服/花钱挽留） |

## 实现（token 级，脚本只加语句不改结构；菜单行同步语句数）

### 1) `party_remove_all_companions`（scripts.txt，262 → 271 tokens，语句数 67 → 69）

- 外层离队判定：原版 `2136 3 <var> 0 2` + `neq <var> 0`（random≠0 就离队 = 50%）→ 改为 `2136 3 <var> 0 100` + `lt <var, 25>`（random(0,100) < 25 → **25% 离队，75% 留队**）。参数「同伴离队概率（%）」直接就是百分比，0 = 永不离队
- **中立势力全留**：在离队判定后插入 2 条语句——`store_faction_of_party <enemy_faction> $g_enemy_party` + `is_between <enemy_faction> kingdoms_begin kingdoms_end`；被中立单位（阵营不在王国区间）打败时条件失败，直接跳过整个离队分支 → 同伴全部留队
- 内层关押判定：`2136 3 <var> 0 4` → `1 2`（随机值恒 1 + `neq 0` 恒真 → 有敌方城镇就必关）

### 2) `loot_player_items`（scripts.txt，186 → 205 tokens，语句数 46 → 51）

按 token 位置插入三段（生成器会先校验 token 数与旧值，结构不符直接 throw）：

- `(ge, ":i_slot", 10)` —— 跳过装备栏（0-9）
- `(assign, ":randomness", 50)` —— 未分类物品（食物/箭等）也按 50%，顺带修掉原版「残留值」bug
- 书分支（插在第一个 `try_begin` 之后）：`is_between(item, itm_book_tactics, itm_spice)` → `randomness = 0`
- 4 个类别概率值 20/15/5/5 → 50/50/50/50

### 3) 被俘关押时长（menus.txt，5 行）

每处 `store_random_in_range <var> lo hi` 之后插入 4 条语句：

```
store_character_level <tmp> trp_player
store_div <tmp> <tmp> $levelDiv
val_sub <var> <tmp>
val_max <var> $hoursMin
```

并同步语句数：野外选项 7→11、城堡/营救选项 6→10、拒绝赎金选项 5→9、地牢等待菜单 10→14。
`levelDiv = 0` 时整段跳过，保持原版。

## 风险与注意

- `menus.txt` 的动作语句数**引擎会校验**、但 `check-module.ps1` 不校验 → 生成器里对 5 行做了「定位串 + 期望次数」双重校验，改错会直接 throw
- **`neq 0` 的坑**：原版 `random(0,N)` + `neq 0` 的离队概率是 (N-1)/N，不是 1/N。曾把 `0,2` 改成 `0,4` 以为得到 25%，实际变成 75% 离队（进游戏实测才发现）。现在改用 `random(0,100) < 概率`，语义直白
- 菜单动作里用的局部变量：野外/城堡用 r13 当 tmp、拒绝赎金用 r12、地牢等待用 r14，均不与原语句冲突
- 被中立势力（盗贼/逃兵/无主军队，阵营不在 `kingdoms_begin..kingdoms_end`）打败时，同伴**全部留队**，不走离队/散落/关押逻辑（避免去酒馆找人浪费时间）
- 王国区间用 `kingdoms_begin = fac_player_supporters_faction(14)` 到 `kingdoms_end = fac_kingdoms_end(21)`；`fac_commoners(1)`、`fac_outlaws(2)`、`fac_dark_knights(6)` 等中立阵营都在区间外
- 书类边界用 `itm_book_tactics`（可读）到 `itm_spice`（杂货起点），覆盖全部可读/参考书
- 旧档兼容：只影响之后发生的战败；同伴赎回/再招募路径不变
