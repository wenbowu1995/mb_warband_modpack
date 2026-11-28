# 换装功能脚本源码（由 wb-asm.ps1 编译成 patches/equip/scripts.txt）
#
# 占位符：{{S0}}..{{S10}} 由 build-module.ps1 替换成实际脚本索引，
#         顺序必须与下面脚本出现顺序一致：
#   0  wb_modifier_bonus          护甲前缀 -> 防御加成（x1000）
#   1  wb_modifier_value          武器/马前缀 -> 价值权重（价格倍数 x50）
#   2  wb_modifier_requirement    前缀 -> 装备要求增量（力量/强弓/骑术）
#   3  wb_item_score              物品基础分（x1000），同时按 kind 做类型筛选
#   4  wb_find_best_for_troop     在背包里找某类最适合该同伴的一件
#   5  wb_equip_slot_for_troop    单人单槽：比当前好才换，旧装备退回背包
#   6  wb_clear_slot_if_invalid   该槽装备类型不符就清空（副手可空）
#   7  wb_equip_slot_for_all      全队单槽
#   8  wb_auto_equip_armor        护甲入口（头/身/腿/手）
#   9  wb_auto_equip_weapon       武器入口（按强弓技能分弓兵/骑兵，各配 4 格）
#   10 wb_auto_equip_horse        坐骑入口（排除瘸腿）
#
# kind 编号（wb_item_score / wb_find_best_for_troop 第二参数）：
#   0 头盔   1 身甲   2 腿甲   3 手甲
#   4 任意近战（单手/双手/长杆）  5 马
#   6 双手武器      7 弓      8 箭      9 单手或单双手（长武器优先，没有长的退到短的）
#   10 盾          11 短单手（范围<80）  12 长杆（高级骑兵主流长杆优先，其次任意长杆）
#
# req 编号（wb_find_best_for_troop 第三参数 / wb_modifier_requirement 第二参数）：
#   0 力量（护甲/近战/盾/箭）  1 骑术（马）  2 强弓（弓）

: wb_modifier_bonus
# reg0 = 护甲前缀的防御加成 x1000（与 item_score 的 x1000 同量纲）
store_script_param :l0 1
assign reg0 0
try_begin
eq :l0 1
assign reg0 -4000
end_try
try_begin
eq :l0 2
assign reg0 -3000
end_try
try_begin
eq :l0 5
assign reg0 -2000
end_try
try_begin
eq :l0 21
assign reg0 -2000
end_try
try_begin
eq :l0 22
assign reg0 -2000
end_try
try_begin
eq :l0 7
assign reg0 -1000
end_try
try_begin
eq :l0 24
assign reg0 1000
end_try
try_begin
eq :l0 25
assign reg0 2000
end_try
try_begin
eq :l0 26
assign reg0 3000
end_try
try_begin
eq :l0 27
assign reg0 4000
end_try
try_begin
eq :l0 29
assign reg0 6000
end_try

: wb_modifier_value
# reg0 = 武器/马前缀的价值权重（价格倍数 x50，素色=50，极品=875），默认 50
store_script_param :l0 1
assign reg0 50
try_begin
eq :l0 1
assign reg0 35
end_try
try_begin
eq :l0 2
assign reg0 30
end_try
try_begin
eq :l0 3
assign reg0 38
end_try
try_begin
eq :l0 4
assign reg0 40
end_try
try_begin
eq :l0 5
assign reg0 35
end_try
try_begin
eq :l0 6
assign reg0 25
end_try
try_begin
eq :l0 7
assign reg0 20
end_try
try_begin
eq :l0 8
assign reg0 40
end_try
try_begin
eq :l0 9
assign reg0 45
end_try
try_begin
eq :l0 10
assign reg0 95
end_try
try_begin
eq :l0 11
assign reg0 100
end_try
try_begin
eq :l0 12
assign reg0 160
end_try
try_begin
eq :l0 13
assign reg0 175
end_try
try_begin
eq :l0 14
assign reg0 335
end_try
try_begin
eq :l0 15
assign reg0 300
end_try
try_begin
eq :l0 16
assign reg0 700
end_try
try_begin
eq :l0 17
assign reg0 875
end_try
try_begin
eq :l0 18
assign reg0 95
end_try
try_begin
eq :l0 19
assign reg0 245
end_try
try_begin
eq :l0 20
assign reg0 350
end_try
try_begin
eq :l0 21
assign reg0 35
end_try
try_begin
eq :l0 22
assign reg0 38
end_try
try_begin
eq :l0 23
assign reg0 43
end_try
try_begin
eq :l0 24
assign reg0 85
end_try
try_begin
eq :l0 25
assign reg0 130
end_try
try_begin
eq :l0 26
assign reg0 195
end_try
try_begin
eq :l0 27
assign reg0 325
end_try
try_begin
eq :l0 28
assign reg0 200
end_try
try_begin
eq :l0 29
assign reg0 575
end_try
try_begin
eq :l0 30
assign reg0 30
end_try
try_begin
eq :l0 31
assign reg0 30
end_try
try_begin
eq :l0 32
assign reg0 45
end_try
try_begin
eq :l0 33
assign reg0 90
end_try
try_begin
eq :l0 34
assign reg0 45
end_try
try_begin
eq :l0 35
assign reg0 325
end_try
try_begin
eq :l0 36
assign reg0 725
end_try
try_begin
eq :l0 38
assign reg0 45
end_try
try_begin
eq :l0 39
assign reg0 40
end_try
try_begin
eq :l0 40
assign reg0 35
end_try
try_begin
eq :l0 41
assign reg0 25
end_try
try_begin
eq :l0 42
assign reg0 95
end_try

: wb_modifier_requirement
# reg0 = 前缀带来的能力要求增量。
#   力量/强弓（req 0/2）：极品 +4、坚硬 +2、重 +1
#   骑术（req 1）：一流 +2、倔犟 +1、胆小 -1
# 前缀会改物品要求，item_get_difficulty 只给基础值，必须加上这一项再比。
store_script_param :l0 1
store_script_param :l1 2
assign reg0 0
try_begin
eq :l1 1
try_begin
eq :l0 36
assign reg0 2
end_try
try_begin
eq :l0 32
assign reg0 1
end_try
try_begin
eq :l0 33
assign reg0 -1
end_try
else_try_begin
try_begin
eq :l0 17
assign reg0 4
end_try
try_begin
eq :l0 19
assign reg0 2
end_try
try_begin
eq :l0 18
assign reg0 1
end_try
end_try

: wb_item_score
# reg0 = 该物品在 kind 类别下的基础分（护甲=防御x1000，武器/马=价值x1000）；不适合该 kind 返回 0
store_script_param :l0 1
store_script_param :l1 2
store_script_param :l5 3
assign reg0 0
item_get_type :l2 :l0
try_begin
eq :l1 0
eq :l2 12
item_get_head_armor reg0 :l0
val_mul reg0 1000
else_try_begin
eq :l1 1
eq :l2 13
# 身甲评分 = 身体护甲 + 该甲自带的腿部护甲（部分身甲覆盖腿部，如板甲类）
item_get_body_armor reg0 :l0
item_get_leg_armor :l4 :l0
val_add reg0 :l4
val_mul reg0 1000
else_try_begin
eq :l1 2
eq :l2 14
item_get_leg_armor reg0 :l0
val_mul reg0 1000
else_try_begin
eq :l1 3
eq :l2 15
item_get_body_armor reg0 :l0
val_mul reg0 1000
else_try_begin
eq :l1 4
this_or_next|eq :l2 2
this_or_next|eq :l2 3
eq :l2 4
item_get_value reg0 :l0
val_mul reg0 1000
else_try_begin
eq :l1 5
eq :l2 1
item_get_value reg0 :l0
val_mul reg0 1000
else_try_begin
eq :l1 6
eq :l2 3
# 避开长柄斧的三个「双手版」（Long Axe / Long War Axe / Great Long Axe）：
# 它们和 polearm 版是同一把长杆兵器，注册成了 type 3，弓兵背弓时不适合拿。
# 名字注入失败时占位符会变成 -1，eq 永不成立，等于不排除。
assign :l4 0
try_begin
this_or_next|eq :l0 {{I_LONG_AXE_ALT}}
this_or_next|eq :l0 {{I_LONG_AXE_B_ALT}}
eq :l0 {{I_LONG_AXE_C_ALT}}
assign :l4 1
end_try
eq :l4 0
item_get_value reg0 :l0
val_mul reg0 1000
else_try_begin
eq :l1 7
eq :l2 8
# 弓：基础属性 + 前缀属性，再按（速度 + 3×伤害）算分（Native 弓只有 4 种前缀）
item_get_speed_rating reg0 :l0
item_get_thrust_damage :l4 :l0
try_begin
eq :l5 1
val_sub :l4 5
else_try_begin
eq :l5 3
val_sub :l4 3
val_sub reg0 3
else_try_begin
eq :l5 19
val_add :l4 3
val_sub reg0 3
else_try_begin
eq :l5 17
val_add :l4 5
val_add reg0 1
end_try
val_mul :l4 3
val_add reg0 :l4
val_mul reg0 1000
else_try_begin
eq :l1 8
eq :l2 5
item_get_value reg0 :l0
val_mul reg0 1000
else_try_begin
eq :l1 9
this_or_next|eq :l2 2
eq :l2 3
item_get_value reg0 :l0
val_mul reg0 1000
# 主武器优先够长的（长度 > 94）；背包里没有长的才退到短武器
try_begin
item_get_weapon_length :l3 :l0
gt :l3 94
val_add reg0 100000000
end_try
else_try_begin
eq :l1 10
eq :l2 7
item_get_value reg0 :l0
val_mul reg0 1000
else_try_begin
eq :l1 11
eq :l2 2
item_get_weapon_length :l3 :l0
lt :l3 80
item_get_value reg0 :l0
val_mul reg0 1000
else_try_begin
eq :l1 12
eq :l2 4
# 长杆兵器：优先各国高级骑兵的主流长杆（重骑枪/骑枪），其次任意长杆。
# 主流判断用物品 ID 白名单（{{I_*}} 由生成器按名字从 item_kinds1.txt 注入），
# 加分偏移让「主流」永远排在「任意长杆」前面，同一档内再按价值排序。
item_get_value reg0 :l0
val_mul reg0 1000
try_begin
this_or_next|eq :l0 {{I_HEAVY_LANCE}}
this_or_next|eq :l0 {{I_LANCE}}
this_or_next|eq :l0 {{I_LIGHT_LANCE}}
eq :l0 {{I_GREAT_LANCE}}
val_add reg0 100000000
end_try
end_try

: wb_find_best_for_troop
# wb_find_best_for_troop(troop, kind, req) -> reg0=item(找不到为 -1) reg1=总分 reg2=背包槽 reg3=modifier
store_script_param :l0 1
store_script_param :l1 2
store_script_param :l2 3
assign :l3 -1
assign :l4 0
assign :l5 -1
assign :l6 0
try_begin
eq :l2 0
store_attribute_level :l7 :l0 0
else_try_begin
eq :l2 1
store_skill_level :l7 skl_riding :l0
else_try_begin
eq :l2 2
store_skill_level :l7 skl_power_draw :l0
end_try
troop_get_inventory_capacity :l8 trp_player
try_for_range :l9 10 :l8
troop_get_inventory_slot :l10 trp_player :l9
ge :l10 1
troop_get_inventory_slot_modifier :l13 trp_player :l9
call_script {{S3}} :l10 :l1 :l13
assign :l11 reg0
ge :l11 1000
# 有效要求 = 基础难度 + 前缀要求增量（极品 +4 / 坚硬 +2 / 重 +1 等）
call_script {{S2}} :l13 :l2
assign :l16 reg0
item_get_difficulty :l12 :l10
val_add :l12 :l16
ge :l7 :l12
# 瘸腿的马直接跳过
assign :l15 0
try_begin
eq :l1 5
eq :l13 30
assign :l15 1
end_try
eq :l15 0
# 护甲用防御加成；弓用前缀属性（速度+3×伤害）；其他武器/马用价值权重
try_begin
le :l1 3
call_script {{S0}} :l13
assign :l14 reg0
else_try_begin
eq :l1 7
# 弓的分数已在 wb_item_score 里按「基础属性 + 前缀属性」算好，这里不再加
assign :l14 0
else_try_begin
call_script {{S1}} :l13
assign :l14 reg0
end_try
val_add :l11 :l14
gt :l11 :l4
assign :l4 :l11
assign :l3 :l10
assign :l5 :l9
assign :l6 :l13
end_try
assign reg0 :l3
assign reg1 :l4
assign reg2 :l5
assign reg3 :l6

: wb_equip_slot_for_troop
# wb_equip_slot_for_troop(troop, slot, kind, req) -> reg0=1 表示换了
store_script_param :l0 1
store_script_param :l1 2
store_script_param :l2 3
store_script_param :l3 4
assign reg0 0
call_script {{S4}} :l0 :l2 :l3
assign :l4 reg0
assign :l5 reg1
assign :l6 reg2
assign :l7 reg3
try_begin
ge :l4 1
troop_get_inventory_slot :l8 :l0 :l1
troop_get_inventory_slot_modifier :l9 :l0 :l1
assign :l10 -1
try_begin
ge :l8 1
call_script {{S3}} :l8 :l2 :l9
assign :l10 reg0
try_begin
le :l2 3
call_script {{S0}} :l9
assign :l11 reg0
else_try_begin
eq :l2 7
# 弓的前缀属性已在 wb_item_score 里算过，这里不再加价值权重
assign :l11 0
else_try_begin
call_script {{S1}} :l9
assign :l11 reg0
end_try
val_add :l10 :l11
end_try
gt :l5 :l10
troop_set_inventory_slot :l0 :l1 :l4
troop_set_inventory_slot_modifier :l0 :l1 :l7
troop_set_inventory_slot trp_player :l6 -1
try_begin
ge :l8 1
troop_add_item trp_player :l8 :l9
end_try
assign reg0 1
end_try

: wb_clear_slot_if_invalid
# wb_clear_slot_if_invalid(troop, slot, kind)：该槽现有装备不符合 kind 就清空（旧装备退回背包）
# 用来实现「副手短武器可以空」：没有合格短武器时不强留一把长武器在那里
store_script_param :l0 1
store_script_param :l1 2
store_script_param :l2 3
assign reg0 0
troop_get_inventory_slot :l3 :l0 :l1
try_begin
ge :l3 1
troop_get_inventory_slot_modifier :l5 :l0 :l1
call_script {{S3}} :l3 :l2 :l5
assign :l4 reg0
eq :l4 0
troop_set_inventory_slot :l0 :l1 -1
troop_add_item trp_player :l3 :l5
assign reg0 1
end_try

: wb_equip_slot_for_all
# wb_equip_slot_for_all(slot, kind, req)：全队英雄（跳过玩家）逐个换同一槽
store_script_param :l0 1
store_script_param :l1 2
store_script_param :l2 3
party_get_num_companion_stacks :l3 party
try_for_range :l4 0 :l3
party_stack_get_troop_id :l5 party :l4
troop_is_hero :l5
neg|eq :l5 trp_player
call_script {{S5}} :l5 :l0 :l1 :l2
end_try

: wb_auto_equip_armor
call_script {{S7}} 4 0 0
call_script {{S7}} 5 1 0
call_script {{S7}} 6 2 0
call_script {{S7}} 7 3 0

: wb_auto_equip_weapon
# 有强弓（>=1）= 弓兵：双手武器 / 弓 / 箭 / 箭
# 无强弓      = 骑兵：单手或单双手 / 盾 / 短单手(<80) / 骑枪
party_get_num_companion_stacks :l0 party
try_for_range :l1 0 :l0
party_stack_get_troop_id :l2 party :l1
troop_is_hero :l2
neg|eq :l2 trp_player
store_skill_level :l3 skl_power_draw :l2
try_begin
ge :l3 1
call_script {{S5}} :l2 0 6 0
call_script {{S5}} :l2 1 7 2
call_script {{S5}} :l2 2 8 0
call_script {{S5}} :l2 3 8 0
else_try_begin
call_script {{S5}} :l2 0 9 0
call_script {{S5}} :l2 1 10 0
call_script {{S5}} :l2 2 11 0
call_script {{S6}} :l2 2 11
call_script {{S5}} :l2 3 12 0
end_try
end_try

: wb_auto_equip_horse
call_script {{S7}} 8 5 1
