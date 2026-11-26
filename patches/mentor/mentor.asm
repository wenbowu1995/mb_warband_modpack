# 师徒指导（mentor）五个脚本源码 —— 由 wb-asm.ps1 汇编成 patches\mentor\script_def.txt
# 占位符：{{VAR_T}}=受指导者 {{VAR_C}}=列表人数 {{VAR_TOWN}}=所在据点 {{EP}}=遭遇据点
#         {{NOTICE}}=提示去重 {{TICKSEEN}}=心跳标志 {{ACT_MENU}}/{{NONE_MENU}}=确认页/无人可教菜单 {{MSG_T}}/{{MSG_A}}=Lua 消息
# 设计：列表只列“能教的人”（排除队里经验最高者），满编 16 人时正好 15 人 + 返回 = 菜单一屏 16 项。
#       结算只在“非自由地图 + 仍在原据点”时进行；回大地图清空状态。
# 经验 = (导师经验 - 受指导者经验) * N / 1000（N = params.md「传授经验比例（千分之几）」，默认 3 = 0.3%），最少 1 点。

: wb_mentor_list
assign {{VAR_T}} 0
assign {{VAR_TOWN}} 0
assign {{NOTICE}} 0
assign {{TICKSEEN}} 0
str_clear 1
str_clear 2
str_clear 61
party_get_num_companion_stacks :l5 party
assign :l1 -1
assign :l10 0
try_for_range :l2 0 :l5
  party_stack_get_troop_id :l3 party :l2
  try_begin
    troop_is_hero :l3
    neq :l3 trp_player
    troop_get_xp :l4 :l3
    try_begin
      gt :l4 :l1
      assign :l1 :l4
      assign :l10 :l3
    try_end
  try_end
try_end
assign :l0 0
try_for_range :l2 0 :l5
  party_stack_get_troop_id :l3 party :l2
  try_begin
    troop_is_hero :l3
    neq :l3 trp_player
    neq :l3 :l10
    val_add :l0 1
    try_begin
      eq :l0 1
      str_store_troop_name 1 :l3
    else_try
      eq :l0 2
      str_store_troop_name 2 :l3
    else_try
      eq :l0 3
      str_store_troop_name 3 :l3
    else_try
      eq :l0 4
      str_store_troop_name 4 :l3
    else_try
      eq :l0 5
      str_store_troop_name 5 :l3
    else_try
      eq :l0 6
      str_store_troop_name 6 :l3
    else_try
      eq :l0 7
      str_store_troop_name 7 :l3
    else_try
      eq :l0 8
      str_store_troop_name 8 :l3
    else_try
      eq :l0 9
      str_store_troop_name 9 :l3
    else_try
      eq :l0 10
      str_store_troop_name 10 :l3
    else_try
      eq :l0 11
      str_store_troop_name 11 :l3
    else_try
      eq :l0 12
      str_store_troop_name 12 :l3
    else_try
      eq :l0 13
      str_store_troop_name 13 :l3
    else_try
      eq :l0 14
      str_store_troop_name 14 :l3
    else_try
      eq :l0 15
      str_store_troop_name 15 :l3
    try_end
  try_end
try_end
assign {{VAR_C}} :l0

: wb_mentor_pick
store_script_param :l0 1
party_get_num_companion_stacks :l3 party
assign :l1 -1
assign :l10 0
try_for_range :l4 0 :l3
  party_stack_get_troop_id :l5 party :l4
  try_begin
    troop_is_hero :l5
    neq :l5 trp_player
    troop_get_xp :l6 :l5
    try_begin
      gt :l6 :l1
      assign :l1 :l6
      assign :l10 :l5
    try_end
  try_end
try_end
assign :l1 0
assign :l2 -1
try_for_range :l4 0 :l3
  party_stack_get_troop_id :l5 party :l4
  try_begin
    troop_is_hero :l5
    neq :l5 trp_player
    neq :l5 :l10
    val_add :l1 1
    try_begin
      eq :l1 :l0
      assign :l2 :l5
    try_end
  try_end
try_end
try_begin
  gt :l2 0
  assign {{VAR_T}} :l2
  assign {{VAR_TOWN}} {{EP}}
  assign {{NOTICE}} 0
  assign {{TICKSEEN}} 0
  troop_get_xp :l6 :l10
  troop_get_xp :l7 :l2
  store_sub :l8 :l6 :l7
  try_begin
    gt :l8 0
    jump_to_menu {{ACT_MENU}}
  else_try
    str_store_troop_name 61 :l2
    jump_to_menu {{NONE_MENU}}
  try_end
try_end

: wb_mentor_info
party_get_num_companion_stacks :l0 party
assign :l1 -1
assign :l2 0
try_for_range :l3 0 :l0
  party_stack_get_troop_id :l4 party :l3
  try_begin
    troop_is_hero :l4
    neq :l4 trp_player
    neq :l4 {{VAR_T}}
    troop_get_xp :l5 :l4
    try_begin
      gt :l5 :l1
      assign :l1 :l5
      assign :l2 :l4
    try_end
  try_end
try_end
try_begin
  gt {{VAR_T}} 0
  str_store_troop_name 1 {{VAR_T}}
  try_begin
    gt :l2 0
    str_store_troop_name 2 :l2
  try_end
  str_store_troop_name 61 {{VAR_T}}
else_try
  str_clear 1
  str_clear 2
  str_clear 61
try_end

: wb_mentor_tick
try_begin
  map_free
  try_begin
    gt {{VAR_T}} 0
    try_begin
      neq {{NOTICE}} 4
      assign {{NOTICE}} 4
      assign {{MSG_T}} 20
    try_end
  try_end
  assign {{VAR_T}} 0
  assign {{VAR_TOWN}} 0
  str_clear 1
  str_clear 2
  str_clear 61
try_end
try_begin
  gt {{VAR_T}} 0
  neg|map_free
  eq {{EP}} {{VAR_TOWN}}
  party_get_num_companion_stacks :l0 party
  assign :l1 -1
  assign :l2 0
  assign :l3 0
  try_for_range :l4 0 :l0
    party_stack_get_troop_id :l5 party :l4
    try_begin
      troop_is_hero :l5
      neq :l5 trp_player
      try_begin
        eq :l5 {{VAR_T}}
        assign :l3 1
      try_end
      neq :l5 {{VAR_T}}
      troop_get_xp :l6 :l5
      try_begin
        gt :l6 :l1
        assign :l1 :l6
        assign :l2 :l5
      try_end
    try_end
  try_end
  try_begin
    eq :l3 1
    try_begin
      gt :l2 0
      troop_get_xp :l6 {{VAR_T}}
      store_sub :l7 :l1 :l6
    else_try
      assign :l7 0
    try_end
    try_begin
      gt :l7 0
      val_mul :l7 3
      val_div :l7 1000
      try_begin
        eq :l7 0
        assign :l7 1
      try_end
      add_xp_to_troop :l7 {{VAR_T}}
      str_store_troop_name 61 {{VAR_T}}
      assign {{MSG_T}} 13
      assign {{MSG_A}} :l7
      assign {{NOTICE}} 0
    else_try
      try_begin
        neq {{NOTICE}} 1
        assign {{NOTICE}} 1
        str_store_troop_name 61 {{VAR_T}}
        assign {{MSG_T}} 17
      try_end
    try_end
  else_try
    try_begin
      neq {{NOTICE}} 2
      assign {{NOTICE}} 2
      assign {{MSG_T}} 18
    try_end
    assign {{VAR_T}} 0
    assign {{VAR_TOWN}} 0
    str_clear 1
    str_clear 2
    str_clear 61
  try_end
try_end

: wb_mentor_start
try_begin
  gt {{VAR_T}} 0
  party_get_num_companion_stacks :l0 party
  assign :l1 -1
  assign :l2 0
  try_for_range :l3 0 :l0
    party_stack_get_troop_id :l4 party :l3
    try_begin
      troop_is_hero :l4
      neq :l4 trp_player
      neq :l4 {{VAR_T}}
      troop_get_xp :l5 :l4
      try_begin
        gt :l5 :l1
        assign :l1 :l5
        assign :l2 :l4
      try_end
    try_end
  try_end
  try_begin
    gt :l2 0
    troop_get_xp :l5 {{VAR_T}}
    store_sub :l6 :l1 :l5
  else_try
    assign :l6 0
  try_end
  try_begin
    gt :l6 0
    assign {{TICKSEEN}} 0
    str_store_troop_name 61 {{VAR_T}}
    assign {{MSG_T}} 15
    rest_for_hours_interactive 1000 5 0
    change_screen_return
  else_try
    str_store_troop_name 61 {{VAR_T}}
    jump_to_menu {{NONE_MENU}}
  try_end
try_end
