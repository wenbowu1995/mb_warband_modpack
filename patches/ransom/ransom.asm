# 领主赎金：玩家参与的战斗中，战败方领主损失当前金币 {{LOSS}}%
# 由 game_event_battle_end 开头调用（只在玩家胜利、g_battle_result == 1 时处理）。
# 战斗结束时 g_encountered_party 可能已被引擎清成无效值（领主逃离等场景会报
# Invalid Party ID），所以先判 party_is_active，无效时退回战斗用的 g_enemy_party。
# 对手为城镇/城堡 → 取 slot_town_lord；对手为领主部队 → 取成员里 occupation == 2 的英雄。
# 村庄 / 商队 / 强盗等不处理；AI 之间的模拟战斗不经过本脚本。
# 占位符由生成器替换：
#   {{G_BATTLE_RESULT}}     g_battle_result 变量 token
#   {{G_ENCOUNTERED_PARTY}} g_encountered_party 变量 token
#   {{G_ENEMY_PARTY}}       g_enemy_party 变量 token
#   {{LOSS}}                战败损失百分比（整数）

: wb_ransom_battle_end
try_begin
  eq {{G_BATTLE_RESULT}} 1
  assign :l9 -1
  try_begin
    gt {{G_ENCOUNTERED_PARTY}} 0
    party_is_active {{G_ENCOUNTERED_PARTY}}
    assign :l9 {{G_ENCOUNTERED_PARTY}}
  else_try
    gt {{G_ENEMY_PARTY}} 0
    party_is_active {{G_ENEMY_PARTY}}
    assign :l9 {{G_ENEMY_PARTY}}
  end_try
  gt :l9 0
  party_get_slot :l0 :l9 0
  assign :l1 -1
  try_begin
    eq :l0 3
    party_get_slot :l1 :l9 7
  else_try
    eq :l0 2
    party_get_slot :l1 :l9 7
  else_try
    eq :l0 13
    party_get_num_companion_stacks :l2 :l9
    try_for_range :l3 0 :l2
      party_stack_get_troop_id :l4 :l9 :l3
      try_begin
        troop_slot_eq :l4 2 2
        assign :l1 :l4
      end_try
    end_try
  end_try
  try_begin
    gt :l1 0
    store_troop_gold :l5 :l1
    val_div :l5 100
    val_mul :l5 {{LOSS}}
    troop_remove_gold :l1 :l5
  end_try
end_try
