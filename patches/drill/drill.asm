# 历练（drill）：原同伴领主的派出与归队。
# 成长按「原版本体」：原版 48h 触发器对玩家王国领主本来就会给 31% 基础经验（无难度倍率），
# 本功能不额外加经验。
# 流程：
#   1) 队伍对话「我想让你去别的国家闯一闯」→ 选一个关系>10 的国王 → wb_outland_send：
#      同伴离队、加入目标国成为领主、与国王好感 +20、生成领主部队；
#   2) 与任意势力的原同伴领主对话 → wb_drill_return：归队，其领地在自家王国回收给玩家、
#      在别国设为未分封，并恢复同伴身份。
# 注意：归队对话只写 pending，由 1 小时触发器执行真正归队（避免遭遇菜单引用已删部队）。
# 占位符由生成器替换：
#   {{PLAYERS_KINGDOM}}  $players_kingdom 变量 token
#   {{DRILL_PENDING}}    g_wb_drill_pending 变量 token
#   {{DRILL_RETURN}}     wb_drill_return 脚本 tag
#   {{WB_MSG_TYPE}}      g_wb_msg_type 变量 token
#   {{WB_MSG_ARG1}}      g_wb_msg_arg1 变量 token
#   {{REL_CHG}}          troop_change_relation_with_troop 脚本 tag
#   {{CREATE_HERO}}      create_kingdom_hero_party 脚本 tag
#   {{OUT_FACTION}}      g_wb_outland_faction 变量 token

: wb_drill_can_return
store_script_param :l0 1
# 原同伴（trp_npc1..trp_npc16）：兼容 token/裸索引两种取值
assign :l2 0
try_begin
  is_between :l0 144115188075856066 144115188075856082
  assign :l2 1
else_try
  is_between :l0 194 210
  assign :l2 1
try_end
eq :l2 1
# 当前是领主（任意势力）
troop_slot_eq :l0 2 2
# 玩家队伍能容纳他
hero_can_join p_main_party

: wb_drill_return
store_script_param :l0 1
# 回收领地：自家王国给玩家；其他国家设未分封
try_for_parties :l1
  party_slot_eq :l1 7 :l0
  store_faction_of_party :l3 :l1
  try_begin
    eq :l3 {{PLAYERS_KINGDOM}}
    party_set_slot :l1 7 trp_player
  else_try
    party_set_slot :l1 7 -1
  try_end
try_end
# 解散他的领主部队
troop_get_slot :l2 :l0 10
try_begin
  party_is_active :l2
  neq :l2 p_main_party
  remove_party :l2
try_end
# 无论部队是否还活跃，领队槽一律清空
assign :l2 -1
troop_set_slot :l0 10 :l2
# 变回同伴并加入玩家队伍
troop_set_faction :l0 fac_player_supporters_faction
troop_set_slot :l0 2 5
troop_set_slot :l0 12 -1
troop_set_auto_equip :l0 0
party_add_members p_main_party :l0 1
troop_set_note_available :l0 1

: wb_drill_finish
# 对话只设了 pending；触发器只在大地图跑（菜单中时间暂停），这里直接执行归队。
# 写 Lua 消息：type 24 = 归队完成，type 25 = 暂缓（该同伴已不是领主状态）
try_begin
  gt {{DRILL_PENDING}} 0
  str_store_troop_name s61 {{DRILL_PENDING}}
  troop_slot_eq {{DRILL_PENDING}} 2 2
  call_script {{DRILL_RETURN}} {{DRILL_PENDING}}
  assign {{DRILL_PENDING}} 0
  assign {{WB_MSG_TYPE}} 24
else_try
  gt {{DRILL_PENDING}} 0
  str_store_troop_name s61 {{DRILL_PENDING}}
  assign {{WB_MSG_ARG1}} 1
  assign {{WB_MSG_TYPE}} 25
try_end

: wb_outland_send
store_script_param :l0 1
store_script_param :l1 2
# 离开玩家队伍
party_remove_members p_main_party :l0 1
# 加入目标国、成为领主
troop_set_faction :l0 :l1
troop_set_slot :l0 2 2
troop_set_slot :l0 12 -1
troop_set_slot :l0 10 -1
# 与目标国王好感 +20
faction_get_slot :l2 :l1 11
call_script {{REL_CHG}} :l2 :l0 20
# 给点启动资金，让 create_kingdom_hero_party 能雇到人
troop_set_slot :l0 11 2000
# 出生点：目标国任一城镇；没有就用玩家队伍位置
assign :l3 p_main_party
try_for_range :l4 648518346341351445 648518346341351625
  store_faction_of_party :l5 :l4
  eq :l5 :l1
  try_begin
    eq :l3 p_main_party
    assign :l3 :l4
  try_end
try_end
call_script {{CREATE_HERO}} :l0 :l3
# Lua 消息：type 26 = 已派出
str_store_troop_name s61 :l0
str_store_faction_name s62 :l1
faction_get_slot :l2 :l1 11
str_store_troop_name s63 :l2
assign {{WB_MSG_TYPE}} 26

: wb_outland_probe
# 判断"这个对话者是不是原同伴"（同伴 1..16 或裸 troop 索引 194..210）
store_script_param :l0 1
assign :l1 0
try_begin
  is_between :l0 144115188075856066 144115188075856082
  assign :l1 1
else_try
  is_between :l0 194 210
  assign :l1 1
try_end
eq :l1 1
