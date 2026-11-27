# 市场「整理物品」补丁（sortitems）

> **状态（2026-11-27）：已启用（直接重排背包槽位版，实测通过）。**
> 最终实现 = 4 个脚本：`wb_sort_items`（选择排序）+ `wb_sort_key`（排序键：类别×1e7 + (1e6 − 基础价值×前缀档位/100)）+ `wb_sort_weight`（前缀价格档位）+ `wb_swap_slots`（物品/前缀/数量三合一换槽）。
> 菜单走「跳转菜单 + on_init」链路（选项动作里直接 call_script 会被执行成 game_start 或加载崩溃）。
>
> **依赖：WSE2 1.1.5.6+**。旧版 WSE2（如 1.174 1146 / 2026-04）下 `troop_set_inventory_slot` 写玩家背包槽会卡死；1.1.5.6 已修复（CHANGELOG 1.1.5.5「Fix crash when hovering an item with corrupted modifier」）。

## 做什么

城镇市场菜单 `menu_town_trade` 在「评估本地价格」下面加「整理物品」选项：点击后在「整理完成」页面**直接重排玩家背包槽位**——

- 分组：`书（type 20）→ 马（1）→ 货物（11）→ 装备（武器 2-10、护甲 12-15、火器 16-18）→ 其他`；
- 类内按「基础价值 × 前缀价格档位」从高到低，空槽沉底（键 999999999）；
- **不改物品数量/前缀/格数**，只交换槽位。

## 文件

| 文件 | 说明 |
|---|---|
| `sort.asm` | 源码（wb-asm 汇编） |
| `scripts.txt` | 汇编产物（生成器读取） |
| `lang_entries.csv` | 中文菜单词条 |

改源码后重新汇编，再跑生成器：

```powershell
powershell -File ..\..\wb-asm.ps1 -AsmFile patches\sort\sort.asm -OutFile patches\sort\scripts.txt
```

## 前缀价格档位（wb_sort_weight）

`store_item_value(item) × 档位 / 100`；`store_item_value` 是引擎的「物品价值」，不含前缀，所以同种物品靠档位区分：

| 档位 | imod 值 | 说明 |
|---|---|---|
| 50 | 1-5、21-23、30、40-41 | 生锈/弯曲/破损/陈旧等（坏） |
| 90 | 6-9、31-34、38-39 | 粗糙/便宜/胆怯等（旧） |
| 100 | 0 | 普通 |
| 190 | 10-16、24-27、35、37、42 | 好/坚硬/加固/精神/新鲜/一大袋 |
| 350 | 17 | 极品（masterwork） |
| 650 | 18-20 | 重/强壮/强大 |
| 1450 | 28-29、36 | 顶级/领主/冠军 |

想调档位直接改 `wb_sort_weight` 再汇编。

## 踩坑记录（为什么不用「清空+重建」）

11-27 试过「临时部队中转 + 清空玩家背包 + 按顺序搬回」的路线，全部因引擎 inventory 行为失败：

1. `troop_add_item` 循环加数量 → 加回玩家背包不合并 / 超上限截断；
2. 加 1 件 + `troop_inventory_slot_set_item_amount` 写数量 → 超上限截断（98→50）；
3. 循环写「剩余」→ 引擎不新建格，永远写回同一格；
4. `troop_add_items` 批量加 → 重复堆叠；
5. 结论：**脚本层没有「加指定物品 N 个、按上限拆格」的安全 opcode**。

最终靠「直接重排槽位」绕过全部数量问题——但要 **WSE2 1.1.5.6+**。

完整过程见 `docs/warband-inventory-sort-attempt.md`。
