# 领主赎金：战斗结束结算（简化版：只看战斗对手 $g_enemy_party，取不到就不扣）
# 由 game_event_battle_end 开头调用（玩家胜利、且本场未处理过时）。
# 占位符由生成器替换：
#   {{G_BATTLE_RESULT}}  g_battle_result 变量 token
#   {{G_ENEMY_PARTY}}    g_enemy_party 变量 token
#   {{G_RANSOM_AMOUNT}}  g_wb_ransom_amount 变量 token
#   {{G_RANSOM_OK}}      g_wb_ransom_ok 变量 token
#   {{G_RANSOM_DONE}}    g_wb_ransom_done 变量 token
#   {{TROOP_END}}        troop 遍历上界（360287970189639680 + troops 数量）
#   {{LOSS}} {{PCT}} {{MIN}}  参数
#   {{DBG_CALC}}         calc 调试字符串 tag

: wb_ransom_battle_end
try_begin
  neq {{G_RANSOM_DONE}} 1
  eq {{G_BATTLE_RESULT}} 1
  gt {{G_ENEMY_PARTY}} 0
  party_is_active {{G_ENEMY_PARTY}}
  assign :l9 -1
  party_get_slot :l0 {{G_ENEMY_PARTY}} 0
  try_begin
    eq :l0 3
    party_get_slot :l9 {{G_ENEMY_PARTY}} 7
  else_try
    eq :l0 2
    party_get_slot :l9 {{G_ENEMY_PARTY}} 7
  else_try
    eq :l0 13
    try_for_range :l4 360287970189639680 {{TROOP_END}}
      try_begin
        troop_slot_eq :l4 10 {{G_ENEMY_PARTY}}
        assign :l9 :l4
      end_try
    end_try
  end_try
  try_begin
    gt :l9 0
    # 战团领主的财富在 troop slot 11（slot_troop_wealth）
    troop_get_slot :l5 :l9 11
    assign :l7 :l5
    val_div :l7 100
    val_mul :l7 {{LOSS}}
    val_sub :l5 :l7
    troop_set_slot :l9 11 :l5
    try_begin
      ge :l5 {{MIN}}
      assign :l6 :l5
      val_div :l6 100
      val_mul :l6 {{PCT}}
      try_begin
        lt :l6 {{MIN}}
        assign :l6 {{MIN}}
      end_try
      try_begin
        gt :l6 :l5
        assign :l6 :l5
      end_try
      assign {{G_RANSOM_OK}} 1
      assign {{G_RANSOM_AMOUNT}} :l6
    else_try
      assign {{G_RANSOM_OK}} 0
      assign {{G_RANSOM_AMOUNT}} 0
    end_try
  else_try
    assign :l5 0
    assign {{G_RANSOM_OK}} 0
    assign {{G_RANSOM_AMOUNT}} 0
  end_try
  try_begin
    gt :l9 0
    str_store_troop_name s1 :l9
  else_try
    str_clear s1
  end_try
  assign reg0 :l9
  assign reg1 :l5
  assign reg2 {{G_RANSOM_OK}}
  assign reg3 {{G_RANSOM_AMOUNT}}
  display_message {{DBG_CALC}}
  assign {{G_RANSOM_DONE}} 1
end_try
