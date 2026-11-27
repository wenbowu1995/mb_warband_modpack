# 领主赎金：记录 / 结算两个脚本
# 占位符由生成器替换：
#   {{G_BATTLE_RESULT}}     g_battle_result 变量 token
#   {{G_ENCOUNTERED_PARTY}} g_encountered_party 变量 token
#   {{G_RANSOM_LORD}}       g_wb_ransom_lord 变量 token
#   {{G_RANSOM_AMOUNT}}     g_wb_ransom_amount 变量 token
#   {{G_RANSOM_OK}}         g_wb_ransom_ok 变量 token
#   {{LOSS}}                战败损失百分比
#   {{PCT}}                 赎金比例
#   {{MIN}}                 赎金下限

# 遭遇时记录敌方领主（此时 g_encountered_party 一定有效；战斗结束再用就可能失效）。
# 中心（城镇 3 / 城堡 2）取 slot_town_lord；领主部队（13）取成员里 occupation == 2 的英雄。
: wb_ransom_encounter
try_begin
  gt {{G_ENCOUNTERED_PARTY}} 0
  party_is_active {{G_ENCOUNTERED_PARTY}}
  party_get_slot :l0 {{G_ENCOUNTERED_PARTY}} 0
  assign :l1 -1
  try_begin
    eq :l0 3
    party_get_slot :l1 {{G_ENCOUNTERED_PARTY}} 7
  else_try
    eq :l0 2
    party_get_slot :l1 {{G_ENCOUNTERED_PARTY}} 7
  else_try
    eq :l0 13
    # 反查真正带这支部队的领主：遍历 troop 的 slot_troop_leaded_party（槽 10）== party
    try_for_range :l4 360287970189639680 {{TROOP_END}}
      try_begin
        troop_slot_eq :l4 10 {{G_ENCOUNTERED_PARTY}}
        assign :l1 :l4
      end_try
    end_try
  end_try
  try_begin
    gt :l1 0
    # 规范化：party_stack_get_troop_id 可能返回裸索引，统一补上 troop tag（360287970189639680）
    try_begin
      lt :l1 360287970189639680
      assign :l6 360287970189639680
      val_add :l6 :l1
      assign :l1 :l6
    end_try
  end_try
  assign {{G_RANSOM_LORD}} :l1
  try_begin
    gt :l1 0
    str_store_troop_name s1 :l1
    troop_get_slot :l7 :l1 11
    assign reg0 :l1
    assign reg1 {{G_ENCOUNTERED_PARTY}}
    assign reg2 :l0
    assign reg3 :l7
    display_message {{DBG_ENC}}
  end_try
else_try
  assign {{G_RANSOM_LORD}} -1
end_try

# 战斗结束时结算：玩家胜利 → 记录领主扣 {{LOSS}}%（找不到记录时用现场 party 兜底），
# 同时算好赎金（当前金币的 {{PCT}}%，最低 {{MIN}}）供求饶对话使用，最后清空记录。
: wb_ransom_battle_end
assign {{G_RANSOM_OK}} 0
assign {{G_RANSOM_AMOUNT}} 0
try_begin
  eq {{G_BATTLE_RESULT}} 1
  assign :l9 {{G_RANSOM_LORD}}
  assign reg0 {{G_BATTLE_RESULT}}
  assign reg1 {{G_ENCOUNTERED_PARTY}}
  assign reg2 {{G_RANSOM_LORD}}
  display_message {{DBG_BE}}
  try_begin
    gt :l9 0
  else_try
    gt {{G_ENCOUNTERED_PARTY}} 0
    party_is_active {{G_ENCOUNTERED_PARTY}}
    party_get_slot :l0 {{G_ENCOUNTERED_PARTY}} 0
    try_begin
      eq :l0 3
      party_get_slot :l9 {{G_ENCOUNTERED_PARTY}} 7
    else_try
      eq :l0 2
      party_get_slot :l9 {{G_ENCOUNTERED_PARTY}} 7
    else_try
      eq :l0 13
      try_for_range :l4 360287970189639680 {{TROOP_END}}
        try_begin
          troop_slot_eq :l4 10 {{G_ENCOUNTERED_PARTY}}
          assign :l9 :l4
        end_try
      end_try
    end_try
  end_try
  try_begin
    gt :l9 0
    try_begin
      lt :l9 360287970189639680
      assign :l6 360287970189639680
      val_add :l6 :l9
      assign :l9 :l6
    end_try
  end_try
  try_begin
    gt :l9 0
    # 战团领主的财富在 troop slot 11（slot_troop_wealth），不是 store_troop_gold 的 gold 字段
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
  str_store_troop_name s1 :l9
  assign reg0 :l9
  assign reg1 :l5
  assign reg2 {{G_RANSOM_OK}}
  assign reg3 {{G_RANSOM_AMOUNT}}
  display_message {{DBG_CALC}}
end_try
assign {{G_RANSOM_LORD}} -1
