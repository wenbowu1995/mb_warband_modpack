# 市场「整理物品」补丁（sortitems）

> **状态（2026-11-26）：已启用（1511 版）。** 最终实现 = 脚本 `wb_sort_items` 一条语句 `troop_sort_inventory trp_player`：实测引擎会按市场价值从高到低整理背包（不分类型，4 种商店场景够用）。菜单走「跳转菜单 + on_init」链路（选项动作里直接 call_script 会被执行成 game_start 或加载崩溃）。下面的「问题记录」保留了自研两条路线失败的原因，作参考。

## 做什么（原设计）

城镇市场菜单 `menu_town_trade` 在「评估本地价格」下面加「整理物品」选项：玩家背包按
`书籍 → 马匹 → 货物 → 武器 → 护甲 → 其他` 分组，组内按市场价值从高到低。

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

## 市场价值口径

`store_item_value(item) × 前缀价格档位 / 100`，档位表在 `sort.asm` 的 `wb_item_weight`
（坏 50 / 旧 90 / 普通 100 / 好 190 / 很好 350 / 极好 650 / 顶级 1450）。
`store_item_value` 是引擎的「物品价值」，不含前缀，所以同种物品靠档位区分；
不同物品按 价值 × 档位 比较。

## 问题记录（为什么回退）

尝试过两条路线，都在战团 1.174 + WSE2 上失败：

1. **直接重排背包槽位**（`troop_get_inventory_slot` / `troop_set_inventory_slot` 读改写）：
   - 往背包槽（10+）写物品后，打开物品栏/商店会**卡死**（引擎内部物品列表/索引不同步）；
   - 中途还会**丢物品**、前缀与数量错乱。
   - 注意：`troop_set_inventory_slot` 只适合「写装备槽 0-9」和「写 -1 清空」，**不适合往背包槽写有效物品**（自动换装就是这么用的，实测安全）。
2. **清空背包 + `troop_add_item` 重建**：
   - 清空时如果正序写 -1，物品列表压缩会让后面的槽前移、**漏清**（残留物品 + 重建物品 = 重复、满栏）；
   - 改成倒序清空后仍丢物品：临时容器（`trp_multiplayer_data`）里，`troop_get_inventory_slot_modifier` 读出的 **-1 前缀被 `troop_add_item` 当成“随机前缀”**，同种物品不再合并、一件占一格，容器塞满后后面的物品加不进去；
   - 修了 -1→0 后仍出现数量异常。
   - 结论：战团 troop inventory 的读写组合在 WSE2 下不够可控，脚本级重建不靠谱。

**复用建议**：如果以后要再做，优先考虑 WSE2 的 Lua 侧直接操作（可用完整数组/排序），或等引擎/插件提供 inventory 排序 API；不要在 Native 脚本里反复写背包槽位。
