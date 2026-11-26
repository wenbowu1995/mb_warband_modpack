# 巡逻队系统（一期）：城镇招募 / 拨兵 / 一键卖俘虏 / 定时巡检
# 用法：wb-asm.ps1 -AsmFile patches\patrol\patrol.asm -OutFile patches\patrol\scripts.txt
# {{...}} 占位符由生成器替换（槽位 / 模板 tag / 字符串 tag / 中心区间 / 参数 / 脚本 tag）
#
# 设计：
#   中心槽 {{SLOT_CENTER_PATROL}} 记录该城巡逻队 party id（0 = 无）
#   巡逻队 party 的 slot_party_ai_state(4)：4 = 巡逻中，15 = 追击，14 = 回城中
#   有效性判断 = party_is_active + party_get_template_id == {{PT_PATROL}}
#   队伍上限 = 玩家队伍人数的 70%；抽兵优先最高等级

# ---------- 内部：从城镇驻军抽兵到目标队伍（优先最高等级），need 传参数 3 ----------
: wb_patrol_take_troops
store_script_param :l0 1
store_script_param :l1 2
store_script_param :l2 3
assign reg0 0
try_begin
  gt :l2 0
  party_get_num_companion_stacks :l4 :l0
  gt :l4 0
  try_for_range :l5 0 :l2
    gt :l2 0
    # 第一优先：骑兵中等级最高
    assign :l6 -1
    assign :l7 0
    try_for_range :l8 0 :l4
      party_stack_get_troop_id :l9 :l0 :l8
      neg|troop_is_hero :l9
      party_stack_get_size :l10 :l0 :l8
      gt :l10 0
      troop_is_mounted :l9
      store_character_level :l11 :l9
      gt :l11 :l7
      assign :l7 :l11
      assign :l6 :l8
    try_end
    # 没有骑兵时：任意兵种中等级最高
    try_begin
      lt :l6 0
      try_for_range :l8 0 :l4
        party_stack_get_troop_id :l9 :l0 :l8
        neg|troop_is_hero :l9
        party_stack_get_size :l10 :l0 :l8
        gt :l10 0
        store_character_level :l11 :l9
        gt :l11 :l7
        assign :l7 :l11
        assign :l6 :l8
      try_end
    try_end
    gt :l6 0
    party_stack_get_troop_id :l9 :l0 :l6
    party_stack_get_size :l10 :l0 :l6
    try_begin
      lt :l10 :l2
      assign :l12 :l10
    else_try
      assign :l12 :l2
    try_end
    gt :l12 0
    party_remove_members :l0 :l9 :l12
    assign :l13 reg0
    gt :l13 0
    party_add_members :l1 :l9 :l13
    val_sub :l2 :l13
    val_add reg0 :l13
  try_end
try_end

# ---------- 内部：玩家拥有的第 index 个城镇（reg0；0 = 没有） ----------
: wb_patrol_owned_center
store_script_param :l0 1
assign reg0 0
assign :l1 0
try_for_range :l2 {{CENTERS_BEGIN}} {{CENTERS_END}}
  try_begin
    party_slot_eq :l2 7 trp_player
    try_begin
      eq :l1 :l0
      assign reg0 :l2
      assign :l1 99999
    else_try
      val_add :l1 1
    try_end
  try_end
try_end

# ---------- 招募：center -> spawn 巡逻队，从驻军抽最高等级兵（受 70% 上限） ----------
: wb_patrol_recruit
store_script_param :l0 1
try_begin
  party_slot_eq :l0 7 trp_player
  party_get_num_companions :l1 :l0
  ge :l1 {{RECRUIT_GARRISON}}
  party_get_slot :l1 :l0 {{SLOT_CENTER_PATROL}}
  assign :l9 0
  try_begin
    gt :l1 0
    party_is_active :l1
    party_get_template_id :l2 :l1
    eq :l2 {{PT_PATROL}}
    assign :l9 1
  try_end
  eq :l9 0
  # 上限 = 玩家队伍人数 × 70%
  call_script {{SCRIPT_COMPANION_LIMIT}}
  assign :l9 reg0
  val_mul :l9 70
  val_div :l9 100
  gt :l9 0
  assign :l3 {{RECRUIT_GARRISON}}
  try_begin
    lt :l9 :l3
    assign :l3 :l9
  try_end
  gt :l3 0
  spawn_around_party :l0 {{PT_PATROL}}
  assign :l2 reg0
  call_script {{SCRIPT_TAKE_TROOPS}} :l0 :l2 :l3
  assign :l4 reg0
  try_begin
    lt :l4 1
    remove_party :l2
  else_try
    party_set_faction :l2 fac_player_supporters_faction
    # 队伍类型设为「领主部队」（spt_kingdom_hero_party=13），让敌方 AI 把它当正规部队
    party_set_slot :l2 0 13
    str_store_party_name s1 :l0
    str_store_string s2 {{QSTR_PATROL_NAME}}
    str_store_string s3 {{QSTR_PATROL_JOIN}}
    party_set_name :l2 s3
    party_set_ai_behavior :l2 3
    party_set_ai_object :l2 :l0
    party_set_ai_patrol_radius :l2 {{PATROL_RADIUS_KM}}
    party_set_ai_initiative :l2 100
    party_set_flags :l2 65536 0
    party_set_slot :l2 4 4
    party_set_slot :l0 {{SLOT_CENTER_PATROL}} :l2
  try_end
try_end

# ---------- 拨兵：把驻军里最高等级的兵拨给该城巡逻队（受 70% 上限） ----------
: wb_patrol_refill
store_script_param :l0 1
try_begin
  party_slot_eq :l0 7 trp_player
  party_get_slot :l1 :l0 {{SLOT_CENTER_PATROL}}
  gt :l1 0
  party_is_active :l1
  party_get_template_id :l2 :l1
  eq :l2 {{PT_PATROL}}
  party_get_num_companions :l2 :l0
  ge :l2 {{REFILL_GARRISON}}
  # 剩余容量 = 上限 - 当前人数
  call_script {{SCRIPT_COMPANION_LIMIT}}
  assign :l9 reg0
  val_mul :l9 70
  val_div :l9 100
  party_get_num_companions :l2 :l1
  val_sub :l9 :l2
  gt :l9 0
  assign :l3 {{REFILL_GARRISON}}
  try_begin
    lt :l9 :l3
    assign :l3 :l9
  try_end
  gt :l3 0
  call_script {{SCRIPT_TAKE_TROOPS}} :l0 :l1 :l3
try_end

# ---------- 一键卖出俘虏（玩家队伍俘虏 + 该城俘虏，英雄除外） ----------
: wb_sell_prisoners
store_script_param :l0 1
try_begin
  party_slot_eq :l0 7 trp_player
  assign :l2 0
  party_get_num_prisoner_stacks :l1 p_main_party
  assign :l3 :l1
  try_for_range :l4 0 :l1
    val_sub :l3 1
    party_prisoner_stack_get_troop_id :l5 p_main_party :l3
    party_prisoner_stack_get_size :l6 p_main_party :l3
    neg|troop_is_hero :l5
    gt :l6 0
    store_character_level :l7 :l5
    store_add :l7 :l7 10
    val_mul :l7 :l7
    val_div :l7 6
    val_mul :l7 :l6
    val_add :l2 :l7
    party_remove_prisoners p_main_party :l5 :l6
  try_end
  party_get_num_prisoner_stacks :l1 :l0
  assign :l3 :l1
  try_for_range :l4 0 :l1
    val_sub :l3 1
    party_prisoner_stack_get_troop_id :l5 :l0 :l3
    party_prisoner_stack_get_size :l6 :l0 :l3
    neg|troop_is_hero :l5
    gt :l6 0
    store_character_level :l7 :l5
    store_add :l7 :l7 10
    val_mul :l7 :l7
    val_div :l7 6
    val_mul :l7 :l6
    val_add :l2 :l7
    party_remove_prisoners :l0 :l5 :l6
  try_end
  gt :l2 0
  troop_add_gold trp_player :l2
try_end

# ---------- 解散该城巡逻队（兵力与俘虏回城） ----------
: wb_patrol_dismiss
store_script_param :l0 1
try_begin
  party_slot_eq :l0 7 trp_player
  party_get_slot :l1 :l0 {{SLOT_CENTER_PATROL}}
  gt :l1 0
  party_is_active :l1
  party_get_template_id :l2 :l1
  eq :l2 {{PT_PATROL}}
  party_get_num_companion_stacks :l3 :l1
  assign :l4 :l3
  try_for_range :l5 0 :l3
    val_sub :l4 1
    party_stack_get_troop_id :l6 :l1 :l4
    party_stack_get_size :l7 :l1 :l4
    gt :l7 0
    party_remove_members :l1 :l6 :l7
    party_add_members :l0 :l6 :l7
  try_end
  party_get_num_prisoner_stacks :l3 :l1
  assign :l4 :l3
  try_for_range :l5 0 :l3
    val_sub :l4 1
    party_prisoner_stack_get_troop_id :l6 :l1 :l4
    party_prisoner_stack_get_size :l7 :l1 :l4
    gt :l7 0
    party_remove_prisoners :l1 :l6 :l7
    party_add_prisoners :l0 :l6 :l7
  try_end
  remove_party :l1
  party_set_slot :l0 {{SLOT_CENTER_PATROL}} 0
try_end

# ---------- 定时巡检（每 1 小时）：解散/俘虏回城/到城交俘虏 ----------
: wb_patrol_tick
try_for_range :l0 {{CENTERS_BEGIN}} {{CENTERS_END}}
  party_get_slot :l1 :l0 {{SLOT_CENTER_PATROL}}
  try_begin
    gt :l1 0
    party_is_active :l1
    party_get_template_id :l2 :l1
    eq :l2 {{PT_PATROL}}
    party_get_slot :l3 :l1 4
    try_begin
      eq :l3 4
      try_begin
        party_is_in_town :l1 :l0
        party_detach :l1
      try_end
      party_set_ai_behavior :l1 3
      party_set_ai_object :l1 :l0
      party_set_ai_patrol_radius :l1 {{PATROL_RADIUS_KM}}
      party_set_ai_initiative :l1 100
      party_set_flags :l1 65536 0
    try_end
    # 扫描附近敌对队伍（与玩家队伍势力关系 < 0），实力不劣才追击
    store_faction_of_party :l10 p_main_party
    party_get_slot :l11 :l1 4
    try_begin
      this_or_next|eq :l11 4
      eq :l11 15
      assign :l12 -1
      assign :l13 9999999
      try_for_parties :l14
        neg|eq :l14 :l1
        neg|eq :l14 p_main_party
        neg|is_between :l14 {{CENTERS_BEGIN}} {{CENTERS_END}}
        party_get_slot :l15 :l14 0
        neq :l15 18
        party_is_active :l14
        store_faction_of_party :l15 :l14
        store_relation :l16 :l15 :l10
        lt :l16 0
        party_get_position pos1 :l14
        party_get_position pos2 :l1
        get_distance_between_positions_in_meters :l16 pos1 pos2
        lt :l16 {{PURSUE_DIST_M}}
        call_script {{SCRIPT_CALC_STRENGTH}} :l1 0
        assign :l17 reg0
        call_script {{SCRIPT_CALC_STRENGTH}} :l14 0
        assign :l18 reg0
        ge :l17 :l18
        lt :l16 :l13
        assign :l13 :l16
        assign :l12 :l14
      try_end
      try_begin
        gt :l12 0
        party_set_ai_behavior :l1 4
        party_set_ai_object :l1 :l12
        party_set_slot :l1 4 15
      else_try
        try_begin
          eq :l11 15
          party_set_ai_behavior :l1 3
          party_set_ai_object :l1 :l0
          party_set_ai_patrol_radius :l1 {{PATROL_RADIUS_KM}}
          party_set_slot :l1 4 4
        try_end
      try_end
    try_end
    party_get_num_companions :l3 :l1
    try_begin
      le :l3 0
      remove_party :l1
      party_set_slot :l0 {{SLOT_CENTER_PATROL}} 0
    else_try
      party_get_num_prisoners :l3 :l1
      gt :l3 {{PRISONER_THRESHOLD}}
      try_begin
        party_is_in_town :l1 :l0
        party_get_num_prisoner_stacks :l4 :l1
        assign :l5 :l4
        try_for_range :l6 0 :l4
          val_sub :l5 1
          party_prisoner_stack_get_troop_id :l7 :l1 :l5
          party_prisoner_stack_get_size :l8 :l1 :l5
          neg|troop_is_hero :l7
          gt :l8 0
          party_remove_prisoners :l1 :l7 :l8
          party_add_prisoners :l0 :l7 :l8
        try_end
        party_detach :l1
        party_set_ai_behavior :l1 3
        party_set_ai_object :l1 :l0
        party_set_ai_patrol_radius :l1 {{PATROL_RADIUS_KM}}
        party_set_slot :l1 4 4
      else_try
        party_set_ai_behavior :l1 1
        party_set_ai_object :l1 :l0
        party_set_slot :l1 4 14
      try_end
    try_end
  try_end
try_end

# ---------- 每周工资：按巡逻队人数扣玩家金币 ----------
: wb_patrol_wage
assign :l0 0
try_for_range :l1 {{CENTERS_BEGIN}} {{CENTERS_END}}
  party_get_slot :l2 :l1 {{SLOT_CENTER_PATROL}}
  try_begin
    gt :l2 0
    party_is_active :l2
    party_get_template_id :l3 :l2
    eq :l3 {{PT_PATROL}}
    party_get_num_companions :l4 :l2
    val_mul :l4 {{WAGE_PER_MAN}}
    val_add :l0 :l4
  try_end
try_end
try_begin
  gt :l0 0
  troop_remove_gold trp_player :l0
  assign {{MSG_T}} 21
  assign {{MSG_A}} :l0
try_end

# ---------- 巡逻队状态标记（供菜单条件用，纯读） ----------
: wb_patrol_status
store_script_param :l0 1
assign reg0 0
party_get_slot :l2 :l0 {{SLOT_CENTER_PATROL}}
try_begin
  gt :l2 0
  party_is_active :l2
  party_get_template_id :l3 :l2
  eq :l3 {{PT_PATROL}}
  assign reg0 1
try_end

# ============================================================
# 村庄征募（城镇队伍管理 → 征募村庄士兵）
#   城镇的下属村庄 = slot_village_bound_center(120) == 城镇
#   每个村庄的志愿兵在 slot_center_volunteer_troop_type(92) /
#   slot_center_volunteer_troop_amount(93)，原版每天刷新一次
#   规则照原版：每名 {{VR_COST}} 第纳尔，受队伍空位与金币限制，
#   招过后数量置 -1（原版语义：本批招空，次日刷新）
# ============================================================

# ---------- 内部：找出城镇下属、可征募的第 k 个村庄（reg0；0 = 没有） ----------
: wb_vr_pick
store_script_param :l0 1
store_script_param :l1 2
assign reg0 0
assign :l2 0
try_for_range :l3 {{VILLAGES_BEGIN}} {{VILLAGES_END}}
  party_slot_eq :l3 120 :l0
  party_get_slot :l4 :l3 35
  neg|eq :l4 1
  neg|eq :l4 2
  party_get_slot :l4 :l3 39
  eq :l4 0
  party_get_slot :l4 :l3 93
  gt :l4 0
  party_get_slot :l5 :l3 92
  gt :l5 0
  val_add :l2 1
  eq :l2 :l1
  assign reg0 :l3
  assign :l2 99999
try_end

# ---------- 菜单 A 初始化：正文 s1 + 按钮文本 s2..s9 ----------
# {{VR_DEBUG}} = 1 时，不满足条件的下属村庄也会在正文里列出原因（默认 0 不显示）
: wb_vr_list
store_script_param :l0 1
assign {{VAR_VR_COUNT}} 0
str_store_party_name s0 :l0
str_store_string s1 {{QSTR_VR_TITLE}}
try_begin
  gt {{VAR_VR_LAST}} 0
  assign reg5 {{VAR_VR_LAST}}
  str_store_string s1 {{QSTR_VR_LAST}}
  assign {{VAR_VR_LAST}} 0
try_end
assign :l1 0
try_for_range :l2 {{VILLAGES_BEGIN}} {{VILLAGES_END}}
  party_slot_eq :l2 120 :l0
  # 逐村判定：0 = 可征募；1 = 袭掠中；2 = 已掠夺；3 = 有强盗；4 = 无志愿兵；5 = 兵种无效
  party_get_slot :l3 :l2 93
  party_get_slot :l4 :l2 92
  party_get_slot :l5 :l2 35
  party_get_slot :l6 :l2 39
  assign :l7 0
  try_begin
    eq :l5 1
    assign :l7 1
  else_try
    eq :l5 2
    assign :l7 2
  else_try
    gt :l6 0
    assign :l7 3
  else_try
    le :l3 0
    assign :l7 4
  else_try
    le :l4 0
    assign :l7 5
  try_end
  try_begin
    eq :l7 0
    lt :l1 8
    str_store_party_name s0 :l2
    str_store_troop_name s10 :l4
    assign reg5 :l3
    store_mul reg6 :l3 {{VR_COST}}
    try_begin
      eq :l1 0
      str_store_string s2 {{QSTR_VR_LINE}}
    else_try
      eq :l1 1
      str_store_string s3 {{QSTR_VR_LINE}}
    else_try
      eq :l1 2
      str_store_string s4 {{QSTR_VR_LINE}}
    else_try
      eq :l1 3
      str_store_string s5 {{QSTR_VR_LINE}}
    else_try
      eq :l1 4
      str_store_string s6 {{QSTR_VR_LINE}}
    else_try
      eq :l1 5
      str_store_string s7 {{QSTR_VR_LINE}}
    else_try
      eq :l1 6
      str_store_string s8 {{QSTR_VR_LINE}}
    else_try
      eq :l1 7
      str_store_string s9 {{QSTR_VR_LINE}}
    try_end
    val_add :l1 1
    val_add {{VAR_VR_COUNT}} 1
  else_try
    gt {{VR_DEBUG}} 0
    str_store_party_name s0 :l2
    assign reg5 :l3
    try_begin
      eq :l7 1
      str_store_string s1 {{QSTR_VR_SKIP_RAIDED}}
    else_try
      eq :l7 2
      str_store_string s1 {{QSTR_VR_SKIP_LOOTED}}
    else_try
      eq :l7 3
      str_store_string s1 {{QSTR_VR_SKIP_BANDIT}}
    else_try
      eq :l7 4
      str_store_string s1 {{QSTR_VR_SKIP_NONE}}
    else_try
      eq :l7 5
      str_store_string s1 {{QSTR_VR_SKIP_TROOP}}
    try_end
  try_end
try_end

# ---------- 菜单 B 初始化：确认页正文 s1（k 由 {{VAR_VR_K}} 传入） ----------
: wb_vr_info
store_script_param :l0 1
call_script {{SCRIPT_VR_PICK}} :l0 {{VAR_VR_K}}
assign :l3 reg0
assign {{VAR_VR_OK}} 0
str_store_string s1 {{QSTR_VR_NONE}}
try_begin
  gt :l3 0
  party_get_slot :l5 :l3 93
  party_get_slot :l6 :l3 92
  party_get_free_companions_capacity :l7 p_main_party
  store_troop_gold :l8 trp_player
  store_div :l9 :l8 {{VR_COST}}
  val_min :l5 :l7
  val_min :l5 :l9
  try_begin
    gt :l5 0
    str_store_party_name s0 :l3
    str_store_troop_name s10 :l6
    assign reg5 :l5
    store_mul reg6 :l5 {{VR_COST}}
    str_store_string s1 {{QSTR_VR_CONFIRM}}
    assign {{VAR_VR_OK}} 1
  else_try
    str_store_string s1 {{QSTR_VR_NOFIT}}
  try_end
try_end

# ---------- 征募一个村庄（town 参数 1，序号参数 2） ----------
: wb_vr_do
store_script_param :l0 1
store_script_param :l1 2
call_script {{SCRIPT_VR_PICK}} :l0 :l1
assign :l3 reg0
try_begin
  gt :l3 0
  party_get_slot :l5 :l3 93
  party_get_slot :l6 :l3 92
  party_get_free_companions_capacity :l7 p_main_party
  store_troop_gold :l8 trp_player
  store_div :l9 :l8 {{VR_COST}}
  val_min :l5 :l7
  val_min :l5 :l9
  try_begin
    gt :l5 0
    party_add_members p_main_party :l6 :l5
    party_set_slot :l3 93 -1
    store_mul :l10 :l5 {{VR_COST}}
    troop_remove_gold trp_player :l10
    assign {{VAR_VR_LAST}} :l5
    str_store_party_name s55 :l3
    assign {{MSG_T}} 28
    assign {{MSG_A}} :l5
  try_end
try_end

# ---------- 征募全部下属村庄（按容量与金币逐个结算） ----------
: wb_vr_recruit_all
store_script_param :l0 1
assign :l20 0
try_for_range :l3 {{VILLAGES_BEGIN}} {{VILLAGES_END}}
  party_slot_eq :l3 120 :l0
  party_get_slot :l4 :l3 35
  neg|eq :l4 1
  neg|eq :l4 2
  party_get_slot :l4 :l3 39
  eq :l4 0
  party_get_slot :l5 :l3 93
  gt :l5 0
  party_get_slot :l6 :l3 92
  gt :l6 0
  party_get_free_companions_capacity :l7 p_main_party
  gt :l7 0
  store_troop_gold :l8 trp_player
  store_div :l9 :l8 {{VR_COST}}
  gt :l9 0
  val_min :l5 :l7
  val_min :l5 :l9
  gt :l5 0
  party_add_members p_main_party :l6 :l5
  party_set_slot :l3 93 -1
  store_mul :l10 :l5 {{VR_COST}}
  troop_remove_gold trp_player :l10
  val_add :l20 :l5
try_end
try_begin
  gt :l20 0
  assign {{VAR_VR_LAST}} :l20
  assign {{MSG_T}} 29
  assign {{MSG_A}} :l20
try_end
