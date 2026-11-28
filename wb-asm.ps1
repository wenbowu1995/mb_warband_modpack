#Requires -Version 5.1
<#
  骑砍战团脚本汇编器（把助记符源码编译成 scripts.txt 的 token 流）

  为什么要它：scripts.txt 的体行是「语句数 + opcode + nargs + 参数」的扁平 token 流，
  手写容易数错 nargs 或漏改语句数（错一处就 Loading scripts 阶段 OOM）。
  这里按「每条语句一行」写源码，由脚本查 opcode 编号和固定参数个数。

  用法：
    wb-asm.ps1 -AsmFile equip.asm -OutFile patches\equip\scripts.txt

  源码语法（每个脚本以 ": 脚本名" 开始）：
    : wb_item_score
    store_script_param :l0 1
    assign reg0 0
    try_begin
    eq :l0 1
    ...
    end_try

  - 以 # 开头或空行忽略
  - 参数可以是数字、regN、:lN、符号（见 $script:Sym）
  - call_script 的参数个数自动算（第一个参数之外都算 nargs）
  - opcode 支持 neg| / this_or_next| 前缀
  - {{S0}} 这类占位符原样保留，由生成器替换为实际脚本索引
#>
param(
    [Parameter(Mandatory = $true)][string]$AsmFile,
    [string]$OutFile
)
$ErrorActionPreference = 'Stop'

# opcode 名 -> 固定参数个数
$script:OpArity = @{
    'try_begin' = 0; 'else_try' = 0; 'else_try_begin' = 0; 'end_try' = 0; 'try_end' = 0
    'try_for_range' = 3; 'call_script' = -1
    'store_script_param' = 2; 'assign' = 2; 'val_add' = 2; 'val_sub' = 2; 'val_mul' = 2; 'val_div' = 2
    'eq' = 2; 'gt' = 2; 'ge' = 2; 'lt' = 2; 'le' = 2; 'neq' = 2
    'is_between' = 3; 'store_relation' = 3; 'set_relation' = 3
    'troop_is_mounted' = 1
    'troop_is_hero' = 1
    'map_free' = 0; 'troop_get_xp' = 2; 'add_xp_to_troop' = 2
    'str_store_troop_name' = 2; 'store_sub' = 3
    'rest_for_hours_interactive' = 3; 'rest_for_hours' = 3; 'change_screen_return' = 0
    'jump_to_menu' = 1
    'str_clear' = 1
    'troop_get_inventory_capacity' = 2; 'troop_get_inventory_slot' = 3
    'troop_sort_inventory' = 1; 'troop_clear_inventory' = 1
    'troop_add_items' = 3
    'troop_inventory_slot_get_item_amount' = 3; 'troop_inventory_slot_set_item_amount' = 3
    'troop_inventory_slot_get_item_max_amount' = 3
    'store_item_value' = 2
    'troop_get_inventory_slot_modifier' = 3; 'troop_set_inventory_slot' = 3
    'troop_set_inventory_slot_modifier' = 3; 'troop_add_item' = 3
    'party_get_num_companion_stacks' = 2; 'party_stack_get_troop_id' = 3
    'store_skill_level' = 3; 'store_attribute_level' = 3
    'item_get_type' = 2; 'item_get_value' = 2; 'item_get_difficulty' = 2
    'item_get_head_armor' = 2; 'item_get_body_armor' = 2; 'item_get_leg_armor' = 2
    'item_get_weapon_length' = 2; 'item_has_property' = 2
    'item_get_speed_rating' = 2; 'item_get_thrust_damage' = 2
    # 巡逻队系统（patrol）
    'store_character_level' = 2
    'party_get_slot' = 3; 'party_set_slot' = 3; 'party_slot_eq' = 3
    'store_troop_faction' = 2; 'troop_slot_eq' = 3; 'faction_slot_eq' = 3
    'troop_set_note_available' = 2; 'troop_set_auto_equip' = 2
    'store_random_in_range' = 3; 'game_get_reduce_campaign_ai' = 1
    'hero_can_join' = 1
    'troop_set_faction' = 2; 'faction_get_slot' = 3; 'str_store_faction_name' = 2
    'party_get_num_companions' = 2; 'party_stack_get_size' = 3
    'party_remove_members' = 3; 'party_add_members' = 3
    'store_troop_gold' = 2; 'troop_remove_gold' = 2; 'troop_add_gold' = 2
    'spawn_around_party' = 2; 'party_set_faction' = 2; 'party_set_name' = 2
    'str_store_string' = 2
    'party_set_ai_behavior' = 2; 'party_set_ai_object' = 2
    'party_set_ai_patrol_radius' = 2; 'party_set_ai_target_position' = 2
    'party_get_position' = 2; 'map_get_random_position_around_position' = 3
    'get_distance_between_positions_in_meters' = 3
    'party_get_template_id' = 2; 'party_is_active' = 1; 'remove_party' = 1
    'party_is_in_town' = 2; 'party_detach' = 1
    'party_get_num_prisoners' = 2; 'party_get_num_prisoner_stacks' = 2
    'party_prisoner_stack_get_troop_id' = 3; 'party_prisoner_stack_get_size' = 3
    'party_remove_prisoners' = 3; 'party_add_prisoners' = 3
    'store_add' = 3; 'store_mul' = 3; 'store_div' = 3
    'party_set_flags' = 3; 'party_set_ai_initiative' = 2
    'store_faction_of_party' = 2; 'str_store_party_name' = 2; 'try_for_parties' = 1
    # 村庄征募（villagerecruit）
    'party_get_free_companions_capacity' = 2; 'party_slot_ge' = 3
    'str_store_troop_name_by_count' = 3; 'val_min' = 2
}

# 别名（header 里写成表达式而不是数字的）
$script:OpAlias = @{
    'lt' = @('ge', 2147483648)
    'le' = @('gt', 2147483648)
    'neq' = @('eq', 2147483648)
}

# 符号常量
$script:Sym = @{
    'trp_player' = [uint64]360287970189639680
    'trp_find_item_cheat' = [uint64]360287970189639684   # troops.txt 索引 4（作弊物品查找的临时部队）
    'trp_temp_troop' = [uint64]360287970189639683   # troops.txt 索引 3（战利品临时部队）
    'party' = [uint64]648518346341351424
    'itp_couchable' = [int64]-2147483648
    'fac_player_supporters_faction' = [uint64]432345564227567630
    'fac_player_faction' = [uint64]432345564227567629
    'p_main_party' = [uint64]648518346341351424
}

function Resolve-Value([string]$v, [int]$lineNo) {
    if ($v -match '^\{\{.+\}\}$') { return $v }
    if ($v -match '^-?\d+$') { return $v }
    if ($v -match '^reg(\d+)$') { return [string]([uint64]72057594037927936 + [uint64]$Matches[1]) }
    if ($v -match '^s(\d+)$') { return [string]$Matches[1] }
    if ($v -match '^pos(\d+)$') { return [string]$Matches[1] }
    if ($v -match '^:l(\d+)$') { return [string]([uint64]1224979098644774912 + [uint64]$Matches[1]) }
    if ($v -match '^skl_(\w+)$') {
        $skl = @{ 'trade' = 0; 'leadership' = 1; 'prisoner_management' = 2; 'persuasion' = 7; 'engineer' = 8;
            'first_aid' = 9; 'surgery' = 10; 'wound_treatment' = 11; 'inventory_management' = 12; 'spotting' = 13;
            'pathfinding' = 14; 'tactics' = 15; 'tracking' = 16; 'trainer' = 17; 'looting' = 22;
            'horse_archery' = 23; 'riding' = 24; 'athletics' = 25; 'shield' = 26; 'weapon_master' = 27;
            'power_draw' = 33; 'power_throw' = 34; 'power_strike' = 35; 'ironflesh' = 36 }
        $k = $Matches[1]
        if (-not $skl.ContainsKey($k)) { throw "第 $lineNo 行：未知技能 skl_$k" }
        return [string]([uint64]1369094286720630784 + [uint64]$skl[$k])
    }
    if ($script:Sym.ContainsKey($v)) { return [string]$script:Sym[$v] }
    throw "第 $lineNo 行：无法解析的值 '$v'"
}

# opcode 名 -> id
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$hdr = Join-Path $root 'tmp\warband\ms\Module_system 1.171\header_operations.py'
if (-not (Test-Path $hdr)) { throw "找不到 header_operations.py: $hdr" }
$opName2Id = @{}
foreach ($line in [IO.File]::ReadAllLines($hdr, [Text.Encoding]::UTF8)) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(\d+)') {
        $opName2Id[$Matches[1]] = [int]$Matches[2]
    }
}

$out = New-Object System.Collections.Generic.List[string]
$pendingName = $null
$tokens = New-Object System.Collections.Generic.List[string]
$stmtCount = 0
$lineNo = 0

function Flush-Script() {
    if (-not $script:pendingName) { return }
    if ($script:tokens.Count -eq 0) { throw "脚本 $($script:pendingName) 没有任何语句" }
    $out.Add("$($script:pendingName) -1")
    $out.Add(' ' + $script:stmtCount + ' ' + ($script:tokens -join ' '))
}

foreach ($raw in [IO.File]::ReadAllLines($AsmFile, [Text.Encoding]::UTF8)) {
    $lineNo++
    $line = $raw.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    if ($line.StartsWith(':')) {
        Flush-Script
        $script:pendingName = $line.Substring(1).Trim()
        $script:tokens = New-Object System.Collections.Generic.List[string]
        $script:stmtCount = 0
        continue
    }
    if (-not $script:pendingName) { throw "第 $lineNo 行：第一条语句前没有 ': 脚本名'" }

    $parts = @($line -split '\s+' | Where-Object { $_ -ne '' })
    $opRaw = $parts[0]
    $args = @($parts | Select-Object -Skip 1)

    # 前缀处理
    $prefixAdd = 0
    $opName = $opRaw
    while ($opName -match '^(neg|this_or_next)\|(.+)$') {
        if ($Matches[1] -eq 'neg') { $prefixAdd += 2147483648 } else { $prefixAdd += 1073741824 }
        $opName = $Matches[2]
    }

    $nArgs = $null
    if ($script:OpAlias.ContainsKey($opName) -and $prefixAdd -eq 0) {
        $alias = $script:OpAlias[$opName]
        $opName = $alias[0]
        $prefixAdd += $alias[1]
    }
    if ($opName -eq 'call_script') {
        $id = 1
        $nArgs = $args.Count
    }
    elseif ($script:OpArity.ContainsKey($opName)) {
        if (-not $opName2Id.ContainsKey($opName)) { throw "第 $lineNo 行：header 里没有 opcode $opName" }
        $id = $opName2Id[$opName]
        $nArgs = $script:OpArity[$opName]
    }
    else { throw "第 $lineNo 行：未登记的 opcode '$opRaw'" }

    if ($args.Count -ne $nArgs) { throw "第 $lineNo 行：$opRaw 需要 $nArgs 个参数，实际 $($args.Count)" }

    $script:tokens.Add([string]($id + $prefixAdd))
    $script:tokens.Add([string]$nArgs)
    foreach ($a in $args) { $script:tokens.Add((Resolve-Value $a $lineNo)) }
    $script:stmtCount++
}
Flush-Script

$text = ($out -join "`r`n") + "`r`n"
if ($OutFile) {
    [IO.File]::WriteAllText($OutFile, $text, (New-Object Text.UTF8Encoding($false)))
    $scripts = @($out | Where-Object { $_ -match '^\s+-1$' }).Count
    Write-Host "[OK] 已写出 $OutFile"
    Write-Host "     脚本 $scripts 个，共 $(($out.Count - $scripts)) 条语句"
}
else { $text }
