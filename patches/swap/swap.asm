# 领土交换：交换玩家国内两处中心的领主，按损失类型扣玩家与领主的关系
# 用法：wb-asm.ps1 -AsmFile patches\swap\swap.asm -OutFile patches\swap\scripts.txt
# 占位符由生成器替换：
#   {{CHG}}            change_player_relation_with_troop 脚本 tag
#   {{UPD_CENTER}}     update_center_notes 脚本 tag
#   {{UPD_FACTION}}    update_faction_notes 脚本 tag
#   {{WB_MSG_TYPE}}    g_wb_msg_type 变量 token
#   {{WB_MSG_ARG1}}    g_wb_msg_arg1 变量 token
#   {{PENALTY_TOWN}}   城的关系惩罚（正数）
#   {{PENALTY_CASTLE}} 堡垒的关系惩罚（正数）

: wb_swap_do
store_script_param :l0 1
store_script_param :l1 2
party_get_slot :l2 :l0 7
party_get_slot :l3 :l1 7
try_begin
  neq :l2 :l3
  party_set_slot :l0 7 :l3
  party_set_slot :l1 7 :l2
  party_get_slot :l4 :l0 0
  party_get_slot :l5 :l1 0
  # 领地等级：城镇 3、堡垒 2、村庄 1
  assign :l6 1
  try_begin
    eq :l4 3
    assign :l6 3
  else_try
    eq :l4 2
    assign :l6 2
  try_end
  assign :l7 1
  try_begin
    eq :l5 3
    assign :l7 3
  else_try
    eq :l5 2
    assign :l7 2
  try_end
  # 领主1 失去更高价值的领地
  try_begin
    gt :l6 :l7
    ge :l2 0
    neq :l2 trp_player
    assign :l8 0
    try_begin
      eq :l4 3
      assign :l8 {{PENALTY_TOWN}}
    else_try
      eq :l4 2
      assign :l8 {{PENALTY_CASTLE}}
    try_end
    gt :l8 0
    assign {{WB_MSG_ARG1}} :l8
    assign {{WB_MSG_TYPE}} 23
    str_store_troop_name s61 :l2
    val_mul :l8 -1
    call_script {{CHG}} :l2 :l8
  else_try
    # 领主2 失去更高价值的领地
    gt :l7 :l6
    ge :l3 0
    neq :l3 trp_player
    assign :l9 0
    try_begin
      eq :l5 3
      assign :l9 {{PENALTY_TOWN}}
    else_try
      eq :l5 2
      assign :l9 {{PENALTY_CASTLE}}
    try_end
    gt :l9 0
    assign {{WB_MSG_ARG1}} :l9
    assign {{WB_MSG_TYPE}} 23
    str_store_troop_name s61 :l3
    val_mul :l9 -1
    call_script {{CHG}} :l3 :l9
  try_end
  call_script {{UPD_CENTER}} :l0
  call_script {{UPD_CENTER}} :l1
  call_script {{UPD_FACTION}} fac_player_supporters_faction
try_end
