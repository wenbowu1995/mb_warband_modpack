# 市场「整理物品」：直接重排玩家背包槽位（不搬出/不清空/不加回）。
# 顺序：书（20）→ 马（1）→ 货物（11）→ 装备（武器 2-10、护甲 12-15、火器 16-18）→ 其他；
# 类内按「基础价值 × 前缀价格档位」从高到低（极品/坚硬等前缀会加分）。空槽沉到末尾。
# 依赖：WSE2 1.1.5.6+（旧版写背包槽会卡死）。
# 用法：wb-asm.ps1 -AsmFile patches\sort\sort.asm -OutFile patches\sort\scripts.txt
: wb_sort_items
troop_get_inventory_capacity :l0 trp_player
store_sub :l1 :l0 1
try_for_range :l2 10 :l1
call_script {{SORT_KEY}} :l2
assign :l3 :l2
assign :l4 reg0
store_add :l5 :l2 1
try_for_range :l6 :l5 :l1
call_script {{SORT_KEY}} :l6
try_begin
lt reg0 :l4
assign :l4 reg0
assign :l3 :l6
end_try
end_try
try_begin
neq :l3 :l2
call_script {{SORT_SWAP}} :l2 :l3
end_try
end_try
assign reg0 1

: wb_sort_key
# wb_sort_key(slot) -> reg0：空槽 999999999（沉底）；有物品 = 类别*10000000 + (1000000-价值×前缀档位/100)
store_script_param :l0 1
troop_get_inventory_slot :l1 trp_player :l0
assign reg0 999999999
try_begin
gt :l1 0
item_get_type :l2 :l1
assign :l3 5
try_begin
eq :l2 20
assign :l3 1
else_try_begin
eq :l2 1
assign :l3 2
else_try_begin
eq :l2 11
assign :l3 3
else_try_begin
is_between :l2 2 10
assign :l3 4
else_try_begin
is_between :l2 12 18
assign :l3 4
end_try
troop_get_inventory_slot_modifier :l5 trp_player :l0
call_script {{SORT_WEIGHT}} :l5
assign :l6 reg0
store_item_value :l4 :l1
try_begin
lt :l4 0
assign :l4 0
end_try
store_mul :l4 :l4 :l6
store_div :l4 :l4 100
store_sub :l4 1000000 :l4
store_mul reg0 :l3 10000000
val_add reg0 :l4
end_try

: wb_sort_weight
# wb_sort_weight(modifier) -> reg0：前缀价格档位（千分比，近似战团 imod 价格倍数）
store_script_param :l0 1
assign reg0 100
try_begin
lt :l0 0
assign reg0 100
else_try_begin
le :l0 0
assign reg0 100
else_try_begin
le :l0 5
assign reg0 50
else_try_begin
le :l0 9
assign reg0 90
else_try_begin
le :l0 16
assign reg0 190
else_try_begin
le :l0 17
assign reg0 350
else_try_begin
le :l0 20
assign reg0 650
else_try_begin
le :l0 23
assign reg0 50
else_try_begin
le :l0 27
assign reg0 190
else_try_begin
le :l0 29
assign reg0 1450
else_try_begin
le :l0 30
assign reg0 50
else_try_begin
le :l0 34
assign reg0 90
else_try_begin
le :l0 35
assign reg0 190
else_try_begin
le :l0 36
assign reg0 1450
else_try_begin
le :l0 37
assign reg0 190
else_try_begin
le :l0 39
assign reg0 90
else_try_begin
le :l0 41
assign reg0 50
else_try_begin
le :l0 42
assign reg0 190
end_try

: wb_swap_slots
# 交换两个背包槽（物品/前缀/数量三合一）；空槽只写物品号，不写前缀/数量
store_script_param :l0 1
store_script_param :l1 2
troop_get_inventory_slot :l2 trp_player :l0
troop_get_inventory_slot_modifier :l3 trp_player :l0
troop_inventory_slot_get_item_amount :l4 trp_player :l0
troop_get_inventory_slot :l5 trp_player :l1
troop_get_inventory_slot_modifier :l6 trp_player :l1
troop_inventory_slot_get_item_amount :l7 trp_player :l1
try_begin
lt :l3 0
assign :l3 0
end_try
try_begin
lt :l4 1
assign :l4 1
end_try
try_begin
lt :l6 0
assign :l6 0
end_try
try_begin
lt :l7 1
assign :l7 1
end_try
troop_set_inventory_slot trp_player :l0 :l5
try_begin
gt :l5 0
troop_set_inventory_slot_modifier trp_player :l0 :l6
troop_inventory_slot_set_item_amount trp_player :l0 :l7
end_try
troop_set_inventory_slot trp_player :l1 :l2
try_begin
gt :l2 0
troop_set_inventory_slot_modifier trp_player :l1 :l3
troop_inventory_slot_set_item_amount trp_player :l1 :l4
end_try
assign reg0 1
