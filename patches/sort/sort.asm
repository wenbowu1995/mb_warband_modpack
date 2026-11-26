# 市场「整理物品」：调用引擎自带的 troop_sort_inventory（1511）。
# 实测：1511 会按物品市场价值从高到低整理玩家背包（不分类型）。
# 游戏有 4 种商店，按类型分组意义不大，所以直接用引擎的按价排序。
# 用法：wb-asm.ps1 -AsmFile patches\sort\sort.asm -OutFile patches\sort\scripts.txt
: wb_sort_items
troop_sort_inventory trp_player
