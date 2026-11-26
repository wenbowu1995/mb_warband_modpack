#Requires -Version 5.1
<#
  骑砍战团 · 增强模块生成器（核心引擎）

  做的事：从「纯净 Native」复制一份 → 按勾选应用功能补丁 → 生成独立模块。
  原版 Native 一个字节都不动。

  功能：
    equip     一键换装功能（护甲 / 武器 / 坐骑）—— 新增「营地 → 换装备」菜单
    garrison  玩家攻城成功后，敌方俘虏自动变驻军
    lairlink  强盗巢穴任务地点可以在大地图指出
    lootchest 奇形宝箱 BUG 修复（日瓦车则隐藏宝箱给全 6 件）
    detail    人物详情显示优化
    fief      分封显示现有领地
    armyreward 跟随元帅任务优化（固定 3000 经验；完成支线即结束跟随）
        mentor    队伍等级高的 NPC 训练等级低 NPC（城镇 → 训练 → 传授经验）
    loan      本势力领主贷款（默认借款费用 10%、周息 4%、按财富 5% 还款、财富 20% ≥ 债务时一次还清、封顶 30000；参数见 params.md）
    fiefenvy  国王好感减免分封嫉妒（B 对 A 的关系 + 国王与 B 的关系/5，加成后封顶 16、只抬不压；参数见 params.md）
    reconcile 冰释前嫌（关系<0 时在「我问你些事」加选项：金币/货物换关系；参数见 params.md）
    dispute   调解领主纠纷优化（任务无 CD、推荐阈值 0、通知阈值 -5、说服显示概率、完成封顶 8、金钱选项）
    persuade  说服相关（领主招募显示支持度；同伴离队说服失败可花钱挽留）
    skills    技能相关优化（掠夺改智力 17→18、骑术改力量 1→0）
    learnskill 城镇训练，找 NPC 学习他们无法生效的技能（4 项，强制等 8 小时 +1 级）
    defeat    战败惩罚（同伴部分留队 / 物品缴获 / 被俘时长随等级；参数见 params.md）
    claim     宣称系统（失地记录原领主+势力；原势力夺回自动归还；停战按实际控制清空双方宣称；叛国/流放清理）
    lua       Lua 消息出口（WSE2 可选：Native 只写消息变量，lua/main.lua 读取并显示左下角提示）
    itemvalue 物品原始价值（物品详情框加一行灰字「原始价值：X」，商店/物品栏通用）
    patrol    友方巡逻队 + 村庄征募（城镇队伍管理：招募巡逻队/拨兵/解散/卖俘虏/征募村庄士兵）
    factionjoin 换国后与国王关系最低 0（原版 +5 保留，负关系抬到 0；切断流放连环；11-25 实测通过）
    swap      领土交换（大臣对话交换国内两处领地；失去更高价值领地的一方扣关系，城 -10 / 堡 -5）
    taxexempt 税收无效损失豁免（预算报告里玩家村庄不计入领地计数；11-25 实测通过）
    nofiefgood 无地好人性格领主惩罚（善良/正直领主没有领地时，也按周期与国王掉一点关系；参数见 params.md）
    drill     历练（原同伴领主在玩家王国的成长按原版本体；对话可随时归队并回收领地）
    sortitems 市场整理物品（城镇市场「评估本地价格」下新增「整理物品」：背包按书/马/货/武器/甲/其他分组，组内按市场价值降序）
    cheatlang 作弊菜单汉化（营地 → CHEAT MENU! 等 43 条文本写入 languages\cns\game_menus.csv；重复选项 ID 先唯一化）

  用法（命令行）：
    build-module.ps1                          # 不指定 = 全量（features.psd1 里的所有功能）
    build-module.ps1 -Groups equip,garrison   # 按组勾选（features.psd1 里的 Key）
    build-module.ps1 -Features equip,garrison # 直接点名功能（内部调试/兼容旧用法）
    再加 -ModuleName Native-Equip -DisplayName 换装版 可换模块名

  功能分组见 features.psd1（manager.ps1 也读它画界面）。耦合的功能合并成一个组，
  界面一个勾；当前唯一的硬耦合是 learnskill（城镇学习技能）依赖 mentor（训练菜单与变量），
  用 -Features 单独点名 learnskill 时这里会自动补上 mentor。
#>
param(
    [string]$GameDir,
    [string]$ModuleName = 'Native-Enhanced',
    [string]$DisplayName = '原版增强',
    # 要生成的功能（逗号分隔或数组）；留空 = 全量
    [string[]]$Features = @(),
    # 要生成的组（features.psd1 的 Key，逗号分隔或数组）；与 -Features 可叠加
    [string[]]$Groups = @(),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
# 兼容两种传法：-Features equip,garrison（单个字符串）和 -Features @('equip','garrison')
$Features = @($Features | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$Groups = @($Groups | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# ---- 功能分组：features.psd1 是唯一来源（组 = 界面上一个勾）----
$featureSpecPath = Join-Path $PSScriptRoot 'features.psd1'
if (-not (Test-Path $featureSpecPath)) { throw '缺少 features.psd1（功能分组定义），无法确定要生成哪些功能' }
$featureSpec = Import-PowerShellDataFile $featureSpecPath
$allFeatures = @($featureSpec.Groups | ForEach-Object { $_.Features } | ForEach-Object { $_ } | Select-Object -Unique)
$groupKeys = @($featureSpec.Groups | ForEach-Object { $_.Key })
foreach ($gk in $Groups) {
    if ($groupKeys -notcontains $gk) { throw "未知功能组：$gk（可用：$($groupKeys -join ', ')）" }
    foreach ($g in $featureSpec.Groups) {
        if ($g.Key -eq $gk) { $Features += @($g.Features); break }
    }
}
if ($Features.Count -eq 0) { $Features = @($allFeatures) }
# -Features 里混进组名也认（组名 = 组内全部功能），方便命令行手写
$expandedFeatures = @()
foreach ($f in $Features) {
    if ($groupKeys -contains $f) {
        foreach ($g in $featureSpec.Groups) {
            if ($g.Key -eq $f) {
                Write-Host "[i] '$f' 是组名，展开为 $($g.Features -join ' + ')"
                $expandedFeatures += @($g.Features)
                break
            }
        }
    } else {
        $expandedFeatures += $f
    }
}
$Features = @($expandedFeatures | Where-Object { $_ } | Select-Object -Unique)
foreach ($f in $Features) {
    if ($allFeatures -notcontains $f) { throw "未知功能：$f（可用：$($allFeatures -join ', ')）" }
}
# 耦合兜底：目前没有必须绑定的功能（原来 learnskill → mentor 的依赖已由「训练菜单骨架」解决）。
# 以后如果出现非菜单类硬依赖（共享变量/脚本），在这里登记：@{ 'A' = @('B') }。
$featureDeps = @{}
$autoAddedDeps = @()
foreach ($f in @($Features)) {
    foreach ($d in @($featureDeps[$f])) {
        if ($d -and $Features -notcontains $d) { $Features += $d; $autoAddedDeps += "$f → $d" }
    }
}
if ($autoAddedDeps.Count -gt 0) { Write-Host "[i] 自动补齐耦合功能：$($autoAddedDeps -join '；')" }
$TAG_SCRIPT = 936748722493063168   # tag_script(13) << 56
$TAG_MENU   = 864691128455135232   # tag_menu(12) << 56
$TAG_STRING = 216172782113783808   # tag_string(3) << 56

function Read-TextNoBom([string]$path) {
    $bytes = [IO.File]::ReadAllBytes($path)
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $offset = 3 }
    return [Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
}
function Save-TextNoBom([string]$path, [string]$text) {
    $tmp = "$path.new"
    [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding($false)))
    Move-Item $tmp $path -Force
}
function Save-TextWithBom([string]$path, [string]$text) {
    $tmp = "$path.new"
    [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding($true)))
    Move-Item $tmp $path -Force
}

# 读 item_kinds1.txt，返回 物品名(itm_xxx) -> 索引（0 起，即游戏里的物品 ID）
# 文件头两行是版本行和数量行；每个物品从「 itm_xxx 」那行开始，后面还跟着若干续行（数字），
# 所以只认行首 token 是 itm_ 的行，按出现顺序编号。
function Get-ItemIdMap([string]$modDir) {
    $p = Join-Path $modDir 'item_kinds1.txt'
    if (-not (Test-Path $p)) { throw "找不到 item_kinds1.txt: $p" }
    $enc = [Text.Encoding]::GetEncoding(28591)
    $rows = [IO.File]::ReadAllText($p, $enc) -split "\r?\n"
    $declared = 0
    if ($rows.Count -gt 1) { $null = [int]::TryParse($rows[1].Trim(), [ref]$declared) }
    $map = @{}
    $idx = 0
    for ($i = 2; $i -lt $rows.Count; $i++) {
        $t = $rows[$i].Trim()
        if (-not $t.StartsWith('itm_')) { continue }
        $nm = ($t -split '\s+')[0]
        $map[$nm] = $idx
        $idx++
    }
    if ($declared -gt 0 -and $idx -ne $declared) {
        throw "item_kinds1.txt 物品数对不上：声明 $declared，实际解析 $idx"
    }
    return $map
}

# 把一行文本里「菜单索引 >= $m0」的菜单 ID 整体 +1（新增菜单插在它们前面）
function Remap-MenuLine([string]$line, [int]$m0) {
    if ($m0 -le 0) { return $line }
    if (-not $line) { return $line }
    $script:RemapM0 = $m0
    $ev = {
        param($mm)
        $v = [uint64]$mm.Value
        $base = [uint64]864691128455135232
        if ($v -ge $base -and $v -lt ($base + [uint64]900)) {
            $idx = $v - $base
            if ($idx -ge [uint64]$script:RemapM0) { return [string]($base + $idx + [uint64]1) }
        }
        return $mm.Value
    }
    return [regex]::Replace($line, '\b\d{10,}\b', $ev)
}

function Find-WarbandDir {
    $cands = New-Object System.Collections.Generic.List[string]
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $cands.Add((Join-Path $steam 'steamapps\common\MountBlade Warband'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            $content = Get-Content $vdf -Raw -Encoding UTF8
            foreach ($m in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
                $lib = $m.Groups[1].Value -replace '\\\\', '\'
                $cands.Add((Join-Path $lib 'steamapps\common\MountBlade Warband'))
            }
        }
    }
    $cands.Add('D:\SteamLibrary\steamapps\common\MountBlade Warband')
    $cands.Add('E:\SteamLibrary\steamapps\common\MountBlade Warband')
    $cands.Add('C:\Program Files (x86)\Steam\steamapps\common\MountBlade Warband')
    foreach ($c in $cands) {
        if ($c -and (Test-Path (Join-Path $c 'mb_warband.exe'))) { return $c }
    }
    return $null
}

# ---------- 换装 ----------
function Apply-Equip([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\equip'

    # 1) scripts：追加 10 个脚本
    $sPath = Join-Path $modDir 'scripts.txt'
    $text = Read-TextNoBom $sPath
    if ($text -match 'wb_equip_slot_for_all') { throw '这个模块里已经有换装功能了' }
    $lines = $text -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($lines[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    $patchLines = @((Read-TextNoBom (Join-Path $pd 'scripts.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($patchLines.Count -ne 22) { throw "换装脚本补丁应 22 行（11 个脚本 ×2），实际 $($patchLines.Count)" }
    for ($k = 0; $k -lt 11; $k++) {
        $patchLines = $patchLines -replace [regex]::Escape("{{S$k}}"), [string]($TAG_SCRIPT + $n + $k)
    }
    # 长杆兵器的「主流」白名单：按物品名取 ID（MOD 换了物品顺序也照样对得上）
    $itemIds = Get-ItemIdMap $modDir
    foreach ($nm in @('itm_heavy_lance', 'itm_lance', 'itm_light_lance', 'itm_great_lance')) {
        if (-not $itemIds.ContainsKey($nm)) { throw "item_kinds1.txt 里找不到 $nm（换装的长杆白名单需要它）" }
        $tok = '{{I_' + ($nm -replace '^itm_', '').ToUpper() + '}}'
        $patchLines = $patchLines -replace [regex]::Escape($tok), [string]$itemIds[$nm]
    }
    # 弓兵双手武器要避开的「长柄斧双手版」：名字不在就注入 -1（条件永不成立，等于不排除）
    foreach ($nm in @('itm_long_axe_alt', 'itm_long_axe_b_alt', 'itm_long_axe_c_alt')) {
        $tok = '{{I_' + ($nm -replace '^itm_', '').ToUpper() + '}}'
        $val = if ($itemIds.ContainsKey($nm)) { $itemIds[$nm] } else { -1 }
        $patchLines = $patchLines -replace [regex]::Escape($tok), [string]$val
    }
    $body = @($lines | Select-Object -SkipLast 1)
    $body[0] = 'scriptsfile version 1'
    $body[1] = [string]($n + 11)
    Save-TextNoBom $sPath (((($body + $patchLines) -join "`r`n")) + "`r`n")

    # 2) menus：全局重映射 + 插入 wb_equip + camp 加选项
    $mPath = Join-Path $modDir 'menus.txt'
    $mlines = @((Read-TextNoBom $mPath) -split "\r?\n")
    $ci = -1
    for ($i = 0; $i -lt $mlines.Count; $i++) { if ($mlines[$i].StartsWith('menu_camp ')) { $ci = $i; break } }
    if ($ci -lt 0) { throw '这个模块的 menus.txt 里没有 menu_camp' }
    $m0 = [int](($ci - 2) / 2)
    $m1 = $m0 + 1
    $script:MenuShiftDone = $true
    $script:MenuShiftM0 = $m0

    # 全模块菜单 ID 重映射：新菜单插在 camp 前，索引 >= m0 的引用整体 +1
    # （scripts.txt 里也有跳转菜单的 ID，只改 menus 会错位）
    for ($i = 0; $i -lt $mlines.Count; $i++) { $mlines[$i] = Remap-MenuLine $mlines[$i] $m0 }
    $enc28591 = [Text.Encoding]::GetEncoding(28591)
    foreach ($f in Get-ChildItem $modDir -Filter '*.txt' -File) {
        if ($f.Name -eq 'menus.txt') { continue }
        $ftxt = $enc28591.GetString([IO.File]::ReadAllBytes($f.FullName))
        if ($ftxt.IndexOf('864691128455135') -lt 0) { continue }
        $fnew = Remap-MenuLine $ftxt $m0
        if ($fnew -ne $ftxt) { [IO.File]::WriteAllBytes($f.FullName, $enc28591.GetBytes($fnew)) }
    }

    # 插入 menu_wb_equip 两行到 camp 之前
    $wbe = @((Read-TextNoBom (Join-Path $pd 'menu_wb_equip.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($wbe.Count -ne 2) { throw "menu_wb_equip 补丁应 2 行，实际 $($wbe.Count)" }
    for ($k = 0; $k -lt 11; $k++) { $wbe = $wbe -replace [regex]::Escape("{{S$k}}"), [string]($TAG_SCRIPT + $n + $k) }
    $wbe = $wbe -replace [regex]::Escape('{{M0}}'), [string]($TAG_MENU + $m0)
    $wbe = $wbe -replace [regex]::Escape('{{M1}}'), [string]($TAG_MENU + $m1)

    $out = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $mlines.Count; $i++) {
        if ($i -eq $ci) { foreach ($w in $wbe) { $out.Add($w) } }
        $out.Add($mlines[$i])
    }
    $mlines = $out.ToArray()

    # camp 现在在 ci+2，它的选项行在 ci+3
    $campIdx = $ci + 2
    $optIdx = $campIdx + 1
    $frag = (Read-TextNoBom (Join-Path $pd 'camp_option.txt')).TrimEnd()
    $frag = $frag -replace [regex]::Escape('{{M0}}'), [string]($TAG_MENU + $m0)

    $toks = $mlines[$campIdx].TrimEnd() -split ' '
    $oc = 0
    if (-not [int]::TryParse($toks[-1], [ref]$oc)) { throw 'menu_camp 行尾选项数解析失败' }
    $toks[-1] = [string]($oc + 1)
    $mlines[$campIdx] = $toks -join ' '
    # 选项插到原版 mno_camp_wait_here 之前（与源码里的顺序一致）
    $opt = $mlines[$optIdx]
    $pos = $opt.IndexOf('mno_camp_wait_here')
    if ($pos -lt 0) { $pos = $opt.Length }
    $mlines[$optIdx] = $opt.Substring(0, $pos) + $frag + '  ' + $opt.Substring($pos)

    # 菜单数量 +1（保留第 2 行的前导空格）
    $mc = 0
    if (-not [int]::TryParse($mlines[1].Trim(), [ref]$mc)) { throw 'menus.txt 第 2 行不是菜单数量' }
    $mlines[1] = $mlines[1] -replace '\d+', [string]($mc + 1)

    Save-TextNoBom $mPath ($mlines -join "`r`n")

    # 3) 语言词条
    $langPath = Join-Path $modDir 'languages\cns\game_menus.csv'
    if (Test-Path $langPath) {
        $langText = Read-TextNoBom $langPath
        $entries = (Read-TextNoBom (Join-Path $pd 'lang_entries.csv')).TrimEnd()
        Save-TextWithBom $langPath ($langText.TrimEnd() + "`r`n" + $entries + "`r`n")
    }
    Write-ModpackLog "[equip] 11 个脚本 + 2 个菜单 + 6 条中文词条"
}

# ---------- 驻军 ----------
function Apply-Garrison([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\garrison'
    $sPath = Join-Path $modDir 'scripts.txt'
    $mPath = Join-Path $modDir 'menus.txt'
    $vPath = Join-Path $modDir 'variables.txt'

    $text = Read-TextNoBom $sPath
    if ($text -match 'stash_rescuable_prisoners') { throw '这个模块里已经有驻军功能了' }
    $lines = $text -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($lines[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    $s0 = $TAG_SCRIPT + $n
    $s1 = $s0 + 1
    $patchLines = @((Read-TextNoBom (Join-Path $pd 'garrison_scripts.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($patchLines.Count -ne 4) { throw "驻军脚本补丁应 4 行，实际 $($patchLines.Count)" }
    $patchLines = $patchLines -replace [regex]::Escape('{{S0}}'), [string]$s0 -replace [regex]::Escape('{{S1}}'), [string]$s1

    # 驻军脚本里的变量 tag 是早期硬编码（索引 1259-1323）；后来 Apply-MsgVars 在前面插了 7 个消息变量，
    # 导致这些 tag 实际指向 g_wb_msg_type 等变量（冲突）。这里按当前变量表末尾重映射：
    # garrison 的 65 个变量（g_rescue_stash_count + 32 troop + 32 size）追加到变量表末尾，
    # 脚本里的 tag 从 base 起重新编号（一次性正则替换，避免链式覆盖）。
    $vNow = @((Read-TextNoBom $vPath) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $vBase = $vNow.Count
    $tagEv = {
        param($m)
        $v = [int]$m.Groups[1].Value
        if ($v -ge 131 -and $v -le 195) { return [string]([int64]144115188075855872 + [int64]$vBase + [int64]($v - 131)) }
        return $m.Value
    }
    $patchLines = @($patchLines | ForEach-Object { [regex]::Replace($_, '144115188075857(\d{3})', $tagEv) })
    $body = @($lines | Select-Object -SkipLast 1)
    $body[0] = 'scriptsfile version 1'
    $body[1] = [string]($n + 2)
    Save-TextNoBom $sPath (((($body + $patchLines) -join "`r`n")) + "`r`n")

    $mlines = @((Read-TextNoBom $mPath) -split "\r?\n")
    $exIdx = -1; $ctIdx = -1
    for ($i = 0; $i -lt $mlines.Count; $i++) {
        if ($mlines[$i].Contains('2050 1 648518346341351425')) { $exIdx = $i; break }
    }
    for ($i = 0; $i -lt $mlines.Count; $i++) {
        if ($mlines[$i].StartsWith('menu_castle_taken ')) { $ctIdx = $i; break }
    }
    if ($exIdx -lt 0 -or $ctIdx -lt 0) { throw "menus.txt 定位失败（exchange=$exIdx, castle_taken=$ctIdx）" }
    $newEx = (Read-TextNoBom (Join-Path $pd 'exchange_line.txt')) -replace [regex]::Escape('{{S0}}'), [string]$s0 -replace [regex]::Escape('{{S1}}'), [string]$s1
    $newCt = (Read-TextNoBom (Join-Path $pd 'castle_taken_line.txt')) -replace [regex]::Escape('{{S0}}'), [string]$s0 -replace [regex]::Escape('{{S1}}'), [string]$s1
    # 如果换装已经先插入了菜单，这些行里的菜单引用要跟着 +1
    if ($script:MenuShiftDone) {
        $newEx = Remap-MenuLine $newEx $script:MenuShiftM0
        $newCt = Remap-MenuLine $newCt $script:MenuShiftM0
    }
    $mlines[$exIdx] = $newEx.TrimEnd("`r", "`n")
    $mlines[$ctIdx] = $newCt.TrimEnd("`r", "`n")
    Save-TextNoBom $mPath ($mlines -join "`r`n")

    $vtext = Read-TextNoBom $vPath
    $addList = @((Read-TextNoBom (Join-Path $pd 'variables_add.txt')) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    Save-TextNoBom $vPath ($vtext.TrimEnd() + "`r`n" + ($addList -join "`r`n") + "`r`n")
    Write-ModpackLog "[garrison] 2 个脚本 + 2 处菜单 + $($addList.Count) 个全局变量"
}

# ---------- 巢穴链接 ----------
function Apply-Lairlink([string]$modDir) {
    $WARLINK_TAG = 'dlga_merchant_quest_track_bandit_lair_choice:merchant_quest_destroy_lair_brief'
    $enc = [Text.Encoding]::GetEncoding(28591)
    $conv = Join-Path $modDir 'conversation.txt'
    $text = $enc.GetString([IO.File]::ReadAllBytes($conv))
    $idx = $text.IndexOf($WARLINK_TAG)
    if ($idx -lt 0) { throw 'conversation.txt 里没找到巢穴任务对话' }
    $lineEnd = $text.IndexOf("`r`n", $idx)
    if ($lineEnd -lt 0) { $lineEnd = $text.Length }
    $line = $text.Substring($idx, $lineEnd - $idx)
    if ($line -match '1097 2') { throw '已经改过了' }
    $newLine = [regex]::Replace($line, '2330 2 9 (\d+)', '2342 2 9 $1 1097 2 $1 1')
    if ($newLine -eq $line) { throw '没找到 2330 2 9 语句' }
    $newLine = [regex]::Replace($newLine, "(Aye,_I'll_do_it\.\s+\d+\s+)(\d+)(\s)", {
        param($m) $m.Groups[1].Value + ([int]$m.Groups[2].Value + 1) + $m.Groups[3].Value
    })
    $newText = $text.Substring(0, $idx) + $newLine + $text.Substring($lineEnd)
    [IO.File]::WriteAllBytes($conv, $enc.GetBytes($newText))
    Write-ModpackLog '[lairlink] conversation 一行（链接 + 笔记开放）'
}

# ---------- 人物详情 ----------
function Apply-Detail([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\detail'
    $enc = [Text.Encoding]::GetEncoding(28591)

    # 1) strings.txt：追加 22 条
    $sPath = Join-Path $modDir 'strings.txt'
    $sLines = [IO.File]::ReadAllText($sPath, $enc) -split "\r?\n"
    $nStr = 0
    if (-not [int]::TryParse($sLines[1].Trim(), [ref]$nStr)) { throw 'strings.txt 第 2 行不是字符串数量' }
    if ($sLines -match 'str_detail_stats') { throw '这个模块里已经有人物详情了' }
    $add = @((Read-TextNoBom (Join-Path $pd 'strings_add.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($add.Count -ne 18) { throw "详情字符串补丁应 18 条，实际 $($add.Count)" }
    $sLines[1] = [string]($nStr + 18)
    $sBody = @($sLines | Select-Object -SkipLast 1)
    [IO.File]::WriteAllText($sPath, ((($sBody + $add) -join "`r`n") + "`r`n"), $enc)

    # 2) scripts.txt：新增独立脚本 + 在 game_get_troop_note 里插入调用
    #    插入 4 条语句：try_begin / eq(note_index,0) / call_script(troop) / try_end
    #    —— 语句数必须 +4；变量从脚本参数里取，不能留 {{...}} 占位符
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    if (($scLines -join "`n") -match 'troop_detail_note') { throw '这个模块里已经有人物详情了' }

    $nameIdx = -1
    for ($i = 0; $i -lt $scLines.Count; $i++) {
        if ($scLines[$i] -like 'game_get_troop_note *') { $nameIdx = $i; break }
    }
    if ($nameIdx -lt 0) { throw 'scripts.txt 里没有 game_get_troop_note' }
    $bodyIdx = $nameIdx + 1
    $toks = @($scLines[$bodyIdx].Trim() -split '\s+')
    # 脚本参数变量：21 1 <troop> / 22 1 <note_index>
    $troopVar = ''; $noteVar = ''
    for ($i = 0; $i -lt $toks.Count - 2; $i++) {
        if (-not $troopVar -and $toks[$i] -eq '21' -and $toks[$i + 1] -eq '1') { $troopVar = $toks[$i + 2] }
        if (-not $noteVar -and $toks[$i] -eq '22' -and $toks[$i + 1] -eq '1') { $noteVar = $toks[$i + 2] }
    }
    if (-not $troopVar -or -not $noteVar) { throw 'game_get_troop_note 里找不到参数变量' }
    $anchor = -1
    for ($i = 0; $i -lt $toks.Count - 3; $i++) {
        if ($toks[$i] -eq '2075' -and $toks[$i + 1] -eq '1' -and $toks[$i + 2] -eq '0') { $anchor = $i; break }
    }
    if ($anchor -lt 0) { throw 'game_get_troop_note 里找不到 2075 1 0 锚点' }
    $sv = [string]($TAG_SCRIPT + $n)
    $insert = @('4', '0', '31', '2', $noteVar, '0', '1', '2', $sv, $troopVar, '3', '0')
    # 体行第一个 token 是「语句数」，插入 4 条必须同步 +4
    $declared = [int]$toks[0]
    $newToks = @([string]($declared + 4)) + @($toks[1..($anchor + 2)]) + $insert + @($toks[($anchor + 3)..($toks.Count - 1)])
    $scLines[$bodyIdx] = ' ' + ($newToks -join ' ')

    # 关系值后缀：在「他非常尊敬你」那句（s59 的最后一次赋值）之后追加「（关系 X）」
    # 只在关系描述会显示时执行（原生逻辑在 try 块里），中立关系不追加
    $scriptIdx2 = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $nm = ($scLines[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm) { $scriptIdx2[$nm] = $i }
    }
    if (-not $scriptIdx2.ContainsKey('troop_get_player_relation')) { throw 'scripts.txt 里没有 troop_get_player_relation' }
    $relCallTag = [string]($TAG_SCRIPT + $scriptIdx2['troop_get_player_relation'])

    $toks2 = @($scLines[$bodyIdx].Trim() -split '\s+')
    $decl2 = [int]$toks2[0]
    $st2 = New-Object System.Collections.Generic.List[object]
    $p2 = 1
    while ($p2 -lt $toks2.Count) {
        $opv = [long]$toks2[$p2]
        $nav = [int]$toks2[$p2 + 1]
        $av = @()
        for ($k = 0; $k -lt $nav; $k++) { $av += $toks2[$p2 + 2 + $k] }
        $st2.Add([pscustomobject]@{ op = $opv; na = $nav; args = $av })
        $p2 += 2 + $nav
    }
    if ($p2 -ne $toks2.Count) { throw 'game_get_troop_note 体行解析不完整' }

    $relVar = $null
    for ($i = 0; $i -lt $st2.Count - 1; $i++) {
        if ($st2[$i].op -eq 1 -and $st2[$i].na -eq 2 -and $st2[$i].args[0] -eq $relCallTag -and $st2[$i + 1].op -eq 2133) {
            $relVar = $st2[$i + 1].args[0]
            break
        }
    }
    if (-not $relVar) { throw 'game_get_troop_note 里找不到玩家关系变量' }
    $s59At = -1
    for ($i = 0; $i -lt $st2.Count; $i++) {
        if ($st2[$i].op -eq 2320 -and $st2[$i].na -eq 2 -and $st2[$i].args[0] -eq '59') { $s59At = $i }
    }
    if ($s59At -lt 0) { throw 'game_get_troop_note 里找不到关系描述字符串的赋值' }

    $suffixTag = [string]($TAG_STRING + $nStr + 16)
    $ins2 = @('2133', '2', '72057594037927937', $relVar, '2320', '2', '59', $suffixTag)
    $out2 = New-Object System.Collections.Generic.List[string]
    $out2.Add([string]($decl2 + 2))
    for ($i = 0; $i -lt $st2.Count; $i++) {
        $out2.Add([string]$st2[$i].op)
        $out2.Add([string]$st2[$i].na)
        foreach ($x in $st2[$i].args) { $out2.Add($x) }
        if ($i -eq $s59At) { foreach ($x in $ins2) { $out2.Add($x) } }
    }
    $scLines[$bodyIdx] = ' ' + ($out2 -join ' ')

    $def = @((Read-TextNoBom (Join-Path $pd 'script_def.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($def.Count -ne 2) { throw "新脚本补丁应 2 行，实际 $($def.Count)" }
    for ($k = 0; $k -lt 18; $k++) {
        $def = $def -replace [regex]::Escape("{{S$k}}"), [string]($TAG_STRING + $nStr + $k)
    }
    $scBody = @($scLines | Select-Object -SkipLast 1)
    $scBody[1] = [string]($n + 1)
    [IO.File]::WriteAllText($scPath, ((($scBody + $def) -join "`r`n") + "`r`n"), $enc)

    # 3) 中文词条（清理旧 str_detail_ 条目后重写，避免旧乱码残留）
    $langPath = Join-Path $modDir 'languages\cns\game_strings.csv'
    if (Test-Path $langPath) {
        $langText = Read-TextNoBom $langPath
        $langLines = @($langText -split "\r?\n" | Where-Object { $_ -notmatch '^str_detail_' })
        $entries = (Read-TextNoBom (Join-Path $pd 'lang_entries.csv')).TrimEnd()
        Save-TextWithBom $langPath ((@($langLines) -join "`r`n").TrimEnd() + "`r`n" + $entries + "`r`n")
    }
    Write-ModpackLog "[detail] 新增脚本 troop_detail_note + 24 条字符串（人物详情笔记）"
}


# ---------- 物品原始价值（物品详情框额外一行） ----------
# 引擎在显示物品属性时调用 game_get_item_extra_text（extra_text_id 0-7，原版只用了 0/1：
# 食物士气、书的智力要求与阅读进度），这里占用 2 号行显示「原始价值：{reg1}」。
# 物品栏、商店、战利品等所有物品详情框通用；item_get_value 返回物品基础价值（不含前缀加成）。
function Apply-ItemValue([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $sPath = Join-Path $modDir 'scripts.txt'
    $rows = [IO.File]::ReadAllText($sPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }

    $scriptIdx = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $nm = ($rows[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm) { $scriptIdx[$nm] = $i }
    }
    if (-not $scriptIdx.ContainsKey('game_get_item_extra_text')) { throw 'scripts.txt 里没有 game_get_item_extra_text' }
    $gIdx = $scriptIdx['game_get_item_extra_text']
    $bodyRow = 2 + 2 * $gIdx + 1
    $t = $rows[$bodyRow].Trim() -split '\s+'
    $decl = [int]$t[0]

    # 已打过补丁？
    $qPath = Join-Path $modDir 'quick_strings.txt'
    $qRows = [IO.File]::ReadAllText($qPath, $enc) -split "\r?\n"
    if (($qRows -join "`n") -match 'qstr_wb_item_value') { throw '这个模块里已经有物品原始价值功能了' }
    $qn = 0
    if (-not [int]::TryParse($qRows[0].Trim(), [ref]$qn)) { throw 'quick_strings.txt 第 1 行不是数量' }

    # 头部三条 store_script_param：:item_no 1 / :extra_text_id 2 / :item_modifier 3
    if ($t[1] -ne '23' -or $t[5] -ne '23' -or $t[9] -ne '23' -or $t[4] -ne '1' -or $t[8] -ne '2' -or $t[12] -ne '3') {
        throw 'game_get_item_extra_text 头部参数格式不符'
    }
    $itemVar = $t[3]
    $etidVar = $t[7]

    # 新 quick_string（英文；中文在 languages\cns\quick_strings.csv；索引 = 追加前数量）
    $qId = [string]([uint64]1585267068834414592 + [uint64]$qn)
    $qRows[0] = [string]($qn + 1)
    $qBody = @($qRows | Select-Object -SkipLast 1)
    $qBody += 'qstr_wb_item_value Original_value:_{reg1}'
    [IO.File]::WriteAllText($qPath, ((($qBody -join "`r`n")) + "`r`n"), $enc)

    # 体行末尾追加 6 条语句：
    #   try_begin / eq :extra_text_id 2 / item_get_value reg1 :item_no /
    #   set_result_string qstr / set_trigger_result 0x999999 / try_end
    $insert = @(
        '4', '0',
        '31', '2', $etidVar, '2',
        '2701', '2', '72057594037927937', $itemVar,
        '60', '1', $qId,
        '2075', '1', '10066329',
        '3', '0'
    )
    $newToks = @($t) + $insert
    $newToks[0] = [string]($decl + 6)
    $rows[$bodyRow] = ' ' + ($newToks -join ' ')

    $body = @($rows | Select-Object -SkipLast 1)
    [IO.File]::WriteAllText($sPath, ((($body -join "`r`n")) + "`r`n"), $enc)

    # 中文（物品详情框额外行；字间空格是战团字体要求）
    $cnsPath = Join-Path $modDir 'languages\cns\quick_strings.csv'
    if (Test-Path $cnsPath) {
        $cnsText = Read-TextNoBom $cnsPath
        if ($cnsText -notmatch 'qstr_wb_item_value') {
            Save-TextWithBom $cnsPath ($cnsText.TrimEnd() + "`r`n" + 'qstr_wb_item_value|原 始 价 值 ： {reg1}' + "`r`n")
        }
    }
    Write-ModpackLog '[itemvalue] 物品详情框加「原始价值」行（extra_text_id=2）'
}

# ---------- 友方巡逻队（patrol，一期） ----------
# 城镇菜单：招募巡逻队（金币 + 驻军）/ 给巡逻队拨兵 / 卖出全部俘虏；
# 触发器每 2 小时巡检：打光解散、俘虏超量回城、到城转移俘虏。
# 脚本源码在 patches\patrol\patrol.asm，由 wb-asm.ps1 汇编成 scripts.txt。
function Apply-Patrol([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $pd = Join-Path $PSScriptRoot 'patches\patrol'
    $asmPatch = Join-Path $pd 'scripts.txt'
    if (-not (Test-Path $asmPatch)) { throw 'patches\patrol\scripts.txt 缺失（先跑 wb-asm.ps1 汇编 patrol.asm）' }

    # 参数（params.md 巡逻队参数表）
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    $cost = 5000; $garrisonRecruit = 50; $refill = 20; $threshold = 20; $slotCenter = 238; $wage = 10; $wageHour = 168; $vrCost = 10; $vrDebug = 0
    $patrolRadius = 5; $pursueDist = 5400
    foreach ($line in ($md -split "\r?\n")) {
        if ($line -match '^\|\s*巡逻队招募花费\s*\|\s*(\d+)\s*\|') { $cost = [int]$Matches[1] }
        if ($line -match '^\|\s*巡逻队招募抽兵数\s*\|\s*(\d+)\s*\|') { $garrisonRecruit = [int]$Matches[1] }
        if ($line -match '^\|\s*巡逻队拨兵数\s*\|\s*(\d+)\s*\|') { $refill = [int]$Matches[1] }
        if ($line -match '^\|\s*巡逻队俘虏阈值\s*\|\s*(\d+)\s*\|') { $threshold = [int]$Matches[1] }
        if ($line -match '^\|\s*巡逻队中心槽位\s*\|\s*(\d+)\s*\|') { $slotCenter = [int]$Matches[1] }
        if ($line -match '^\|\s*巡逻队每人每周工资\s*\|\s*(\d+)\s*\|') { $wage = [int]$Matches[1] }
        if ($line -match '^\|\s*巡逻队工资触发器小时\s*\|\s*(\d+)\s*\|') { $wageHour = [int]$Matches[1] }
        if ($line -match '^\|\s*巡逻队巡逻半径\s*\|\s*(\d+)\s*\|') { $patrolRadius = [int]$Matches[1] }
        if ($line -match '^\|\s*巡逻队追击距离\s*\|\s*(\d+)\s*\|') { $pursueDist = [int]$Matches[1] }
        if ($line -match '^\|\s*村庄征募每名费用\s*\|\s*(\d+)\s*\|') { $vrCost = [int]$Matches[1] }
        if ($line -match '^\|\s*村庄征募调试\s*\|\s*(\d+)\s*\|') { $vrDebug = [int]$Matches[1] }
    }

    # 消息变量（g_wb_msg_type / g_wb_msg_arg1，由 Apply-MsgVars 建好，Lua 显示巡逻队工资）
    $vPath2 = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath2, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $msgIdx = @{}
    foreach ($vn in @('g_wb_msg_type', 'g_wb_msg_arg1')) {
        $found = -1
        for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq $vn) { $found = $i; break } }
        if ($found -lt 0) { throw "variables.txt 里没有 $vn（先跑 Apply-MsgVars）" }
        $msgIdx[$vn] = $found
    }
    $TAG_VAR = [int64]144115188075855872
    $r15 = '1224979098644774915'; $r16 = '1224979098644774916'; $r17 = '1224979098644774917'
    $msgT = [string]($TAG_VAR + $msgIdx['g_wb_msg_type'])
    $msgA = [string]($TAG_VAR + $msgIdx['g_wb_msg_arg1'])

    # 村庄征募变量（计数/选中序号/上次征募人数/可征募标记）
    $vrIdx = @{}
    foreach ($vn in @('g_wb_vr_count', 'g_wb_vr_k', 'g_wb_vr_last', 'g_wb_vr_ok')) {
        $found = -1
        for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq $vn) { $found = $i; break } }
        if ($found -lt 0) { $found = $varList.Count; $varList += $vn }
        $vrIdx[$vn] = $found
    }
    [IO.File]::WriteAllText($vPath2, (($varList -join "`r`n") + "`r`n"), $enc)
    $vrCountVar = [string]($TAG_VAR + $vrIdx['g_wb_vr_count'])
    $vrKVar = [string]($TAG_VAR + $vrIdx['g_wb_vr_k'])
    $vrLastVar = [string]($TAG_VAR + $vrIdx['g_wb_vr_last'])
    $vrOkVar = [string]($TAG_VAR + $vrIdx['g_wb_vr_ok'])

    # 1) party_templates.txt 追加空模板
    $ptPath = Join-Path $modDir 'party_templates.txt'
    $ptRows = [IO.File]::ReadAllText($ptPath, $enc) -split "\r?\n"
    $ptn = 0
    if (-not [int]::TryParse($ptRows[1].Trim(), [ref]$ptn)) { throw 'party_templates.txt 第 2 行不是数量' }
    if (($ptRows -join "`n") -match 'pt_wb_patrol') { throw '这个模块里已经有巡逻队模板了' }
    $ptTag = [string]([uint64]576460752303423488 + [uint64]$ptn)   # tag_party_tpl(8) << 56
    $ptRows[1] = [string]($ptn + 1)
    $ptBody = @($ptRows | Select-Object -SkipLast 1)
    $ptBody += 'pt_wb_patrol Patrol 2 0 1 7 -1 -1 -1 -1 -1 -1 '
    [IO.File]::WriteAllText($ptPath, ((($ptBody -join "`r`n")) + "`r`n"), $enc)

    # 2) quick_strings.txt：巡逻队名 + 「城名+巡逻队」拼接串 + 村庄征募文案
    #    （strings.txt 追加区有 WSE2 加载上限，名字改走 quick_strings，itemvalue 已验证加载正常）
    $qPath = Join-Path $modDir 'quick_strings.txt'
    $qRows = [IO.File]::ReadAllText($qPath, $enc) -split "\r?\n"
    $qn = 0
    if (-not [int]::TryParse($qRows[0].Trim(), [ref]$qn)) { throw 'quick_strings.txt 第 1 行不是数量' }
    if (($qRows -join "`n") -match 'qstr_wb_patrol_name') { throw '这个模块里已经有巡逻队名字了' }
    $QSTR_TAG = [uint64]1585267068834414592
    $qNameId = [string]($QSTR_TAG + [uint64]$qn)
    $qJoinId = [string]($QSTR_TAG + [uint64]($qn + 1))
    $qDbgId = [string]($QSTR_TAG + [uint64]($qn + 2))
    $qVrTitleId = [string]($QSTR_TAG + [uint64]($qn + 3))
    $qVrLineId = [string]($QSTR_TAG + [uint64]($qn + 4))
    $qVrConfirmId = [string]($QSTR_TAG + [uint64]($qn + 5))
    $qVrNoneId = [string]($QSTR_TAG + [uint64]($qn + 6))
    $qVrNofitId = [string]($QSTR_TAG + [uint64]($qn + 7))
    $qVrLastId = [string]($QSTR_TAG + [uint64]($qn + 8))
    $qVrSkipRaidedId = [string]($QSTR_TAG + [uint64]($qn + 9))
    $qVrSkipLootedId = [string]($QSTR_TAG + [uint64]($qn + 10))
    $qVrSkipBanditId = [string]($QSTR_TAG + [uint64]($qn + 11))
    $qVrSkipNoneId = [string]($QSTR_TAG + [uint64]($qn + 12))
    $qVrSkipTroopId = [string]($QSTR_TAG + [uint64]($qn + 13))
    $qRows[0] = [string]($qn + 14)
    $qBody = @($qRows | Select-Object -SkipLast 1)
    $qBody += 'qstr_wb_patrol_name Patrol'
    $qBody += 'qstr_wb_patrol_join {s1}{s2}'
    $qBody += 'qstr_wb_wage_dbg patrol_wage:_{reg1}'
    $qBody += ('qstr_wb_vr_title Recruit_volunteers_from_the_villages_of_{s0}._' + [string]$vrCost + '_denars_per_man.')
    $qBody += 'qstr_wb_vr_line {s0}:_{reg5}_{s10}_({reg6}_denars)'
    $qBody += 'qstr_wb_vr_confirm {s0}_can_send_{reg5}_{s10}_to_follow_you_({reg6}_denars).'
    $qBody += 'qstr_wb_vr_none No_volunteers_in_this_village_right_now.'
    $qBody += 'qstr_wb_vr_nofit Your_party_is_full_or_you_lack_denars.'
    $qBody += 'qstr_wb_vr_last ^^{reg5}_volunteers_joined_your_party.'
    $qBody += 'qstr_wb_vr_skip_raided {s1}^{s0}:_{raided,_cannot_recruit}.'
    $qBody += 'qstr_wb_vr_skip_looted {s1}^{s0}:_{looted,_cannot_recruit}.'
    $qBody += 'qstr_wb_vr_skip_bandit {s1}^{s0}:_{bandits,_cannot_recruit}.'
    $qBody += 'qstr_wb_vr_skip_none {s1}^{s0}:_{no_volunteers}_{reg5}.'
    $qBody += 'qstr_wb_vr_skip_troop {s1}^{s0}:_{invalid_volunteer_troop}.'
    [IO.File]::WriteAllText($qPath, ((($qBody -join "`r`n")) + "`r`n"), $enc)

    # 3) scripts.txt 追加 5 个脚本（替换占位符）
    $scPath = Join-Path $modDir 'scripts.txt'
    $scRows = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($scRows[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是数量' }
    $patchRows = @([IO.File]::ReadAllText($asmPatch, $enc) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($patchRows.Count % 2 -ne 0) { throw 'patrol scripts.txt 行数不是偶数' }
    $scriptNames = @()
    for ($i = 0; $i -lt $patchRows.Count; $i += 2) { $scriptNames += (($patchRows[$i].Trim() -split '\s+')[0]) }
    $tagOf = @{}
    for ($k = 0; $k -lt $scriptNames.Count; $k++) { $tagOf[$scriptNames[$k]] = [string]([uint64]936748722493063168 + [uint64]($n + $k)) }
    # 原生脚本 party_calculate_strength 的 tag（追击前比实力）
    $calcIdx = -1
    for ($i = 0; $i -lt $n; $i++) {
        if (($scRows[2 + 2 * $i].Trim() -split "\s+")[0] -eq 'party_calculate_strength') { $calcIdx = $i; break }
    }
    if ($calcIdx -lt 0) { throw 'scripts.txt 里没有 party_calculate_strength' }
    $calcTag = [string]([uint64]936748722493063168 + [uint64]$calcIdx)
    # 原生脚本 game_get_party_companion_limit 的 tag（队伍上限 × 70%）
    $limitIdx = -1
    for ($i = 0; $i -lt $n; $i++) {
        if (($scRows[2 + 2 * $i].Trim() -split "\s+")[0] -eq 'game_get_party_companion_limit') { $limitIdx = $i; break }
    }
    if ($limitIdx -lt 0) { throw 'scripts.txt 里没有 game_get_party_companion_limit' }
    $limitTag = [string]([uint64]936748722493063168 + [uint64]$limitIdx)
    foreach ($need in @('wb_patrol_recruit', 'wb_patrol_refill', 'wb_sell_prisoners', 'wb_patrol_tick', 'wb_patrol_dismiss', 'wb_patrol_wage', 'wb_patrol_status', 'wb_patrol_take_troops', 'wb_patrol_owned_center', 'wb_vr_pick', 'wb_vr_list', 'wb_vr_info', 'wb_vr_do', 'wb_vr_recruit_all')) {
        if (-not $tagOf.ContainsKey($need)) { throw "patrol 补丁缺脚本 $need" }
    }
    $repl = @{
        '{{PT_PATROL}}' = $ptTag
        '{{QSTR_PATROL_NAME}}' = $qNameId
        '{{QSTR_PATROL_JOIN}}' = $qJoinId
        '{{QSTR_WAGE_DBG}}' = $qDbgId
        '{{QSTR_VR_TITLE}}' = $qVrTitleId
        '{{QSTR_VR_LINE}}' = $qVrLineId
        '{{QSTR_VR_CONFIRM}}' = $qVrConfirmId
        '{{QSTR_VR_NONE}}' = $qVrNoneId
        '{{QSTR_VR_NOFIT}}' = $qVrNofitId
        '{{QSTR_VR_LAST}}' = $qVrLastId
        '{{QSTR_VR_SKIP_RAIDED}}' = $qVrSkipRaidedId
        '{{QSTR_VR_SKIP_LOOTED}}' = $qVrSkipLootedId
        '{{QSTR_VR_SKIP_BANDIT}}' = $qVrSkipBanditId
        '{{QSTR_VR_SKIP_NONE}}' = $qVrSkipNoneId
        '{{QSTR_VR_SKIP_TROOP}}' = $qVrSkipTroopId
        '{{VR_DEBUG}}' = [string]$vrDebug
        '{{SCRIPT_TAKE_TROOPS}}' = $tagOf['wb_patrol_take_troops']
        '{{SCRIPT_CALC_STRENGTH}}' = $calcTag
        '{{SCRIPT_COMPANION_LIMIT}}' = $limitTag
        '{{SCRIPT_VR_PICK}}' = $tagOf['wb_vr_pick']
        '{{VAR_VR_COUNT}}' = $vrCountVar
        '{{VAR_VR_K}}' = $vrKVar
        '{{VAR_VR_LAST}}' = $vrLastVar
        '{{VAR_VR_OK}}' = $vrOkVar
        '{{MSG_T}}' = $msgT
        '{{MSG_A}}' = $msgA
        '{{SLOT_CENTER_PATROL}}' = [string]$slotCenter
        '{{RECRUIT_COST}}' = [string]$cost
        '{{WAGE_PER_MAN}}' = [string]$wage
        '{{PATROL_RADIUS_KM}}' = [string]$patrolRadius
        '{{PURSUE_DIST_M}}' = [string]$pursueDist
        '{{RECRUIT_GARRISON}}' = [string]$garrisonRecruit
        '{{REFILL_GARRISON}}' = [string]$refill
        '{{PRISONER_THRESHOLD}}' = [string]$threshold
        '{{VR_COST}}' = [string]$vrCost
        '{{CENTERS_BEGIN}}' = '648518346341351445'
        '{{CENTERS_END}}' = '648518346341351625'
        '{{VILLAGES_BEGIN}}' = '648518346341351515'
        '{{VILLAGES_END}}' = '648518346341351625'
    }
    $outLines = New-Object System.Collections.Generic.List[string]
    foreach ($row in $patchRows) {
        $line = $row
        foreach ($k in @($repl.Keys)) { $line = $line.Replace($k, $repl[$k]) }
        if ($line -match '\{\{') { throw "占位符没替换干净: $line" }
        $outLines.Add($line)
    }
    $scBody = @($scRows | Select-Object -SkipLast 1)
    $scBody[1] = [string]($n + $scriptNames.Count)
    [IO.File]::WriteAllText($scPath, ((($scBody + $outLines) -join "`r`n") + "`r`n"), $enc)

    # 4) menus.txt：城镇菜单加「队伍管理」入口；追加「队伍管理」子菜单（只走城镇菜单，不加营地）
    $mPath = Join-Path $modDir 'menus.txt'
    $mRows = [IO.File]::ReadAllText($mPath, $enc) -split "\r?\n"
    $mCount = 0
    if (-not [int]::TryParse($mRows[1].Trim(), [ref]$mCount)) { throw 'menus.txt 第 2 行不是数量' }
    $townLine = -1; $townIdx = -1; $mi = 0
    for ($i = 0; $i -lt $mRows.Count; $i++) {
        if ($mRows[$i] -match '^menu_') {
            if ($mRows[$i] -like 'menu_town *') { $townLine = $i; $townIdx = $mi }
            $mi++
        }
    }
    if ($townLine -lt 0) { throw 'menus.txt 里没有 menu_town' }
    if ($mRows[$townLine] -match 'mno_wb_patrol_mgmt') { throw '这个模块里已经有巡逻队菜单项了' }
    $TAG_MENU = [uint64]864691128455135232
    $cityTag = [string]($TAG_MENU + [uint64]$mCount)
    $townTag = [string]($TAG_MENU + [uint64]$townIdx)
    $townVar = '144115188075856213'
    $TRP = '360287970189639680'
    $REG0 = '72057594037927936'
    $l0 = '1224979098644774912'; $l1 = '1224979098644774913'; $l2 = '1224979098644774914'; $l3 = '1224979098644774915'
    $stTag = $tagOf['wb_patrol_status']

    # 4.1) menu_town 选项数 +1，追加「队伍管理」
    $t = $mRows[$townLine].Trim() -split '\s+'
    $optCount = 0
    if (-not [int]::TryParse($t[$t.Count - 1], [ref]$optCount)) { throw 'menu_town 行末不是选项数' }
    $mRows[$townLine] = (($t[0..($t.Count - 2)] -join ' ') + ' ' + [string]($optCount + 1))
    $mgmtOpt = 'mno_wb_patrol_mgmt 1 541 3 ' + $townVar + ' 7 ' + $TRP + ' Patrol_management 1 2060 1 ' + $cityTag + ' .'
    $optLine = $mRows[$townLine + 1]
    # 锚点优先级：训练入口（骨架的 mno_town_training）→ 旧版 mentor 的 mno_town_mentor →
    # 原生「在这里休息」（mno_castle_wait）。这样勾不勾训练功能都能找到插入位置。
    $anchorName = ''
    $anchorIdx = -1
    foreach ($cand in @('mno_town_training', 'mno_town_mentor', 'mno_castle_wait')) {
        $anchorIdx = $optLine.IndexOf($cand)
        if ($anchorIdx -ge 0) { $anchorName = $cand; break }
    }
    if ($anchorIdx -lt 0) { throw 'menu_town 里找不到锚点选项（mno_town_training / mno_town_mentor / mno_castle_wait）' }
    $dot = $optLine.IndexOf(' . ', $anchorIdx)
    if ($dot -lt 0) { throw "找不到 $anchorName 选项结束标记" }
    $mRows[$townLine + 1] = $optLine.Substring(0, $dot + 3) + ' ' + $mgmtOpt + $optLine.Substring($dot + 3)

    # 4.2) 子菜单 menu_wb_patrol_city：招募 / 拨兵 / 解散 / 卖俘虏 / 征募村庄士兵 / 返回
    #      init 用 2330（str_store_party_name）把城名写进 s1（旧版写 2322 troop_name，对 party 不保险）
    $cityDef = 'menu_wb_patrol_city 0 {s1} none 1 2330 2 1 ' + $townVar + ' 6'
    $cityOpts = New-Object System.Collections.Generic.List[string]
    $c1 = @(
        @('541', '3', $townVar, '7', $TRP),
        @('1601', '2', $l2, $townVar),
        @('30', '2', $l2, [string]$garrisonRecruit),
        @('1', '2', $stTag, $townVar),
        @('31', '2', $REG0, '0')
    )
    $a1 = '1 2 ' + $tagOf['wb_patrol_recruit'] + ' ' + $townVar
    $cityOpts.Add('mno_wb_patrol_recruit ' + $c1.Count + ' ' + (($c1 | ForEach-Object { $_ -join ' ' }) -join ' ') + ' Recruit_a_patrol_' + $garrisonRecruit + '_garrison 1 ' + $a1 + ' .')
    $c2 = @(
        @('541', '3', $townVar, '7', $TRP),
        @('1', '2', $stTag, $townVar),
        @('31', '2', $REG0, '1'),
        @('1601', '2', $l2, $townVar),
        @('30', '2', $l2, [string]$refill)
    )
    $a2 = '1 2 ' + $tagOf['wb_patrol_refill'] + ' ' + $townVar
    $cityOpts.Add('mno_wb_patrol_refill ' + $c2.Count + ' ' + (($c2 | ForEach-Object { $_ -join ' ' }) -join ' ') + ' Replenish_patrol_' + $refill + '_garrison 1 ' + $a2 + ' .')
    $c3 = @(
        @('541', '3', $townVar, '7', $TRP),
        @('1', '2', $stTag, $townVar),
        @('31', '2', $REG0, '1')
    )
    $a3 = '1 2 ' + $tagOf['wb_patrol_dismiss'] + ' ' + $townVar
    $cityOpts.Add('mno_wb_patrol_dismiss ' + $c3.Count + ' ' + (($c3 | ForEach-Object { $_ -join ' ' }) -join ' ') + ' Disband_patrol 1 ' + $a3 + ' .')
    $c4 = @(
        @('541', '3', $townVar, '7', $TRP),
        @('1602', '2', $l2, '648518346341351424'),
        @('1602', '2', $l3, $townVar),
        @('1073741856', '2', $l2, '0'),
        @('32', '2', $l3, '0')
    )
    $a4 = '1 2 ' + $tagOf['wb_sell_prisoners'] + ' ' + $townVar
    $cityOpts.Add('mno_wb_sell_prisoners ' + $c4.Count + ' ' + (($c4 | ForEach-Object { $_ -join ' ' }) -join ' ') + ' Sell_all_prisoners 1 ' + $a4 + ' .')

    # 4.2b) 村庄征募入口 + 两个子菜单（列表 / 确认）
    #      菜单 A 的正文 s1 与按钮 s2..s9 由 wb_vr_list 在 init 里生成（同 mentor 列表的做法）
    $vrListTag = [string]($TAG_MENU + [uint64]($mCount + 1))
    $vrConfirmTag = [string]($TAG_MENU + [uint64]($mCount + 2))
    $c5 = @('541', '3', $townVar, '7', $TRP)
    $cityOpts.Add('mno_wb_vr_open 1 ' + ($c5 -join ' ') + ' Recruit_from_villages 1 2060 1 ' + $vrListTag + ' .')
    $cityOpts.Add('mno_wb_patrol_back 0 Back 1 2060 1 ' + $townTag + ' .')

    $vrListDef = 'menu_wb_village_recruit 0 {s1} none 1 1 2 ' + $tagOf['wb_vr_list'] + ' ' + $townVar + ' 10'
    $vrListOpts = New-Object System.Collections.Generic.List[string]
    for ($k = 1; $k -le 8; $k++) {
        $sReg = '{s' + [string]($k + 1) + '}'
        $vrListOpts.Add('mno_wb_vr_' + $k + ' 1 30 2 ' + $vrCountVar + ' ' + [string]$k + ' ' + $sReg + ' 2 2133 2 ' + $vrKVar + ' ' + [string]$k + ' 2060 1 ' + $vrConfirmTag + ' .')
    }
    $vrListOpts.Add('mno_wb_vr_all 1 32 2 ' + $vrCountVar + ' 0 Recruit_all_village_volunteers 2 1 2 ' + $tagOf['wb_vr_recruit_all'] + ' ' + $townVar + ' 2060 1 ' + $vrListTag + ' .')
    $vrListOpts.Add('mno_wb_vr_back 0 Back 1 2060 1 ' + $cityTag + ' .')

    $vrConfirmDef = 'menu_wb_vr_confirm 0 {s1} none 1 1 2 ' + $tagOf['wb_vr_info'] + ' ' + $townVar + ' 2'
    $vrConfirmOpts = @(
        ('mno_wb_vr_yes 1 30 2 ' + $vrOkVar + ' 1 Recruit_them 2 1 3 ' + $tagOf['wb_vr_do'] + ' ' + $townVar + ' ' + $vrKVar + ' 2060 1 ' + $vrListTag + ' .'),
        ('mno_wb_vr_cancel 0 Forget_it 1 2060 1 ' + $vrListTag + ' .')
    )

    $mBody = @($mRows | Select-Object -SkipLast 1)
    $mBody += @($cityDef, (' ' + ($cityOpts -join ' ')))
    $mBody += @($vrListDef, (' ' + ($vrListOpts -join ' ')))
    $mBody += @($vrConfirmDef, (' ' + ($vrConfirmOpts -join ' ')))
    $mBody[1] = [string]($mCount + 3)
    [IO.File]::WriteAllText($mPath, ((($mBody -join "`r`n")) + "`r`n"), $enc)

    # 5) simple_triggers.txt：插到前部（WSE2 不执行末尾行），数量 +1
    $trPath = Join-Path $modDir 'simple_triggers.txt'
    $trRows = [IO.File]::ReadAllText($trPath, $enc) -split "\r?\n"
    $tn = 0
    if (-not [int]::TryParse($trRows[1].Trim(), [ref]$tn)) { throw 'simple_triggers.txt 第 2 行不是数量' }
    if (($trRows -join "`n") -match 'wb_patrol_tick') { throw '这个模块里已经有巡逻队触发器了' }
    $trRest = @($trRows[2..($trRows.Count - 1)] | Where-Object { $_ -ne '' })
    $trNew = '1.000000 1 1 1 ' + $tagOf['wb_patrol_tick']
    $trNew2 = [string]$wageHour + '.000000 1 1 1 ' + $tagOf['wb_patrol_wage']
    $trOut = @($trRows[0], [string]($tn + 2), $trNew, $trNew2) + $trRest
    [IO.File]::WriteAllText($trPath, ((($trOut -join "`r`n")) + "`r`n"), $enc)

    # 6) 中文词条（菜单项 + 巡逻队名 + 村庄征募）
    $gm = Join-Path $modDir 'languages\cns\game_menus.csv'
    if (Test-Path $gm) {
        $t2 = Read-TextNoBom $gm
        if ($t2 -notmatch 'mno_wb_patrol_recruit') {
            $add = @(
                ('mno_wb_patrol_recruit|招 募 巡 逻 队 （{0} 名 驻 军）' -f $garrisonRecruit),
                ('mno_wb_patrol_refill|给 巡 逻 队 拨 兵 （{0} 名 驻 军）' -f $refill),
                'mno_wb_sell_prisoners|卖 出 全 部 俘 虏',
                'mno_wb_patrol_dismiss|解 散 巡 逻 队',
                'mno_wb_patrol_mgmt|队 伍 管 理',
                'mno_wb_patrol_back|返 回',
                'mno_wb_vr_open|征 募 村 庄 士 兵',
                'mno_wb_vr_all|征 募 全 部 可 招 士 兵',
                'mno_wb_vr_back|返 回',
                'mno_wb_vr_yes|征 募 他 们',
                'mno_wb_vr_cancel|算 了'
            )
            # 8 个村庄按钮的文本由 wb_vr_list 动态写进 s2..s9，这里只登记占位
            for ($k = 1; $k -le 8; $k++) { $add += ('mno_wb_vr_' + [string]$k + '|{s' + [string]($k + 1) + '}') }
            $add += 'menu_wb_village_recruit|{s1}'
            $add += 'menu_wb_vr_confirm|{s1}'
            Save-TextWithBom $gm ($t2.TrimEnd() + "`r`n" + ($add -join "`r`n") + "`r`n")
        }
    }
    $qs = Join-Path $modDir 'languages\cns\quick_strings.csv'
    if (Test-Path $qs) {
        $t3 = Read-TextNoBom $qs
        if ($t3 -notmatch 'qstr_wb_patrol_name') {
            $addQ = @(
                'qstr_wb_patrol_name|巡 逻 队',
                ('qstr_wb_vr_title|从 城 镇 {s0} 的 下 属 村 庄 征 募 士 兵 ， 每 名 ' + [string]$vrCost + ' 第纳尔 。'),
                'qstr_wb_vr_line|{s0} ： {reg5} 名 {s10} ， 费 用 {reg6} 第纳尔 。',
                'qstr_wb_vr_confirm|{s0} 可 派 {reg5} 名 {s10} 跟 随 你 ， 费 用 {reg6} 第纳尔 。',
                'qstr_wb_vr_none|这 个 村 庄 暂 无 可 征 募 的 士 兵 。',
                'qstr_wb_vr_nofit|你 的 队 伍 已 满 或 第 纳 尔 不 足 。',
                'qstr_wb_vr_last|^^{reg5} 名 村 民 加 入 了 你 的 队 伍 。',
                'qstr_wb_vr_skip_raided|{s1}^{s0}：正 被 袭 掠 ， 无 法 征 募 。',
                'qstr_wb_vr_skip_looted|{s1}^{s0}：已 被 掠 夺 ， 无 法 征 募 。',
                'qstr_wb_vr_skip_bandit|{s1}^{s0}：有 强 盗 盘 踞 ， 无 法 征 募 。',
                'qstr_wb_vr_skip_none|{s1}^{s0}：本 日 无 志 愿 兵 （ 数 量 {reg5} ） 。',
                'qstr_wb_vr_skip_troop|{s1}^{s0}：志 愿 兵 兵 种 异 常 。'
            )
            Save-TextWithBom $qs ($t3.TrimEnd() + "`r`n" + ($addQ -join "`r`n") + "`r`n")
        }
    }

    Write-ModpackLog ("[patrol] 巡逻队：招募 {0} 第纳尔 + {1} 驻军；拨兵 {2}；俘虏阈值 {3}；中心槽 {4}；村庄征募 {5} 第纳尔/名" -f $cost, $garrisonRecruit, $refill, $threshold, $slotCenter, $vrCost)
}

# ---------- 领主贷款 ----------
# 把 conversation.txt 每行的 output_state 加 delta（新状态插到 dialog_states 前面时用）
function Remap-ConversationStates([string[]]$lines, [int]$delta, [int]$minState) {
    $script:ConvRemapFailed = 0
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -notmatch '^dlga_') { $out.Add($line); continue }
        $t = @($line -split '\s+')
        if ($t.Count -lt 4) { $script:ConvRemapFailed++; $out.Add($line); continue }
        # 行格式：dlga_from:to <flags> <state> <cond_n> <conds...> <text> <act_n> <acts...>
        $state = 0
        if (-not [int]::TryParse($t[2], [ref]$state)) { $script:ConvRemapFailed++; $out.Add($line); continue }
        if ($state -ge $minState) { $t[2] = [string]($state + $delta) }
        $out.Add(($t -join ' '))
    }
    return $out.ToArray()
}

function Apply-Loan([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\loan'
    $enc = [Text.Encoding]::GetEncoding(28591)

    # 读取 params.md 的贷款参数（用户只改「值」列）
    function Get-LoanParam([string]$name, [int]$default) {
        $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
        foreach ($line in ($md -split "\r?\n")) {
            if ($line -match ('^\|\s*' + [regex]::Escape($name) + '\s*\|\s*(\d+)\s*\|')) { return [int]$Matches[1] }
        }
        return $default
    }
    $feePct   = Get-LoanParam '借款费用（%）' 10
    $ratePct  = Get-LoanParam '周利息（%）' 4
    $repayPct = Get-LoanParam '周还款（财富%）' 5
    $clearPct = Get-LoanParam '一次还清阈值（财富%）' 20
    $capDenar = Get-LoanParam '债务封顶' 30000
    $trHours  = Get-LoanParam '触发器小时' 168

    # 1) 字符串：贷款提示改走 Lua 消息变量，不再追加字符串

    # 2) scripts.txt：追加 2 个脚本
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    if (($scLines -join "`n") -match 'wb_lord_loan_weekly') { throw '这个模块里已经有领主贷款功能了' }
    $def = @((Read-TextNoBom (Join-Path $pd 'script_def.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($def.Count -ne 4) { throw "贷款脚本补丁应 4 行，实际 $($def.Count)" }
    # 消息变量占位 → 实际变量 tag
    $vPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $msgMap = @{ '{{MSG_T}}' = 'g_wb_msg_type'; '{{MSG_A}}' = 'g_wb_msg_arg1' }
    foreach ($ph in $msgMap.Keys) {
        $vn = $msgMap[$ph]
        $found = -1
        for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq $vn) { $found = $i; break } }
        if ($found -lt 0) { throw "variables.txt 里没有 $vn（先跑 Apply-MsgVars）" }
        $def = $def -replace [regex]::Escape($ph), [string]([int64]144115188075855872 + [int64]$found)
    }
    $def = $def -replace '\{\{LOAN_FEE\}\}', [string](100 + $feePct)
    $def = $def -replace '\{\{LOAN_RATE\}\}', [string]$ratePct
    $def = $def -replace '\{\{LOAN_REPAY\}\}', [string]$repayPct
    $def = $def -replace '\{\{LOAN_CLEAR\}\}', [string]$clearPct
    $def = $def -replace '\{\{LOAN_CAP\}\}', [string]$capDenar
    if (($def -join "`n") -match '\{\{') { throw '贷款补丁还有未替换的占位符' }
    $scBody = @($scLines | Select-Object -SkipLast 1)
    $scBody[1] = [string]($n + 2)
    [IO.File]::WriteAllText($scPath, ((($scBody + $def) -join "`r`n") + "`r`n"), $enc)

    # 3) 不新增对话状态（WSE2 下 dialog_states 末尾追加不加载、插入中部会打乱原对话）

    # 4) conversation.txt：3 行资助选项插到文件前部（text_index 非 0，避免被当自动行）
    $convPath = Join-Path $modDir 'conversation.txt'
    $convLines = [IO.File]::ReadAllText($convPath, $enc) -split "\r?\n"
    $cCount = 0
    if (-not [int]::TryParse($convLines[1].Trim(), [ref]$cCount)) { throw 'conversation.txt 第 2 行不是对话数量' }
    $dAdd = @((Read-TextNoBom (Join-Path $pd 'dialogs_add.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($dAdd.Count -ne 7) { throw "对话补丁应 7 行，实际 $($dAdd.Count)" }
    $dAdd = $dAdd -replace [regex]::Escape('{{LOAN_GIVE}}'), [string]($TAG_SCRIPT + $n + 1)
    $convLines[1] = [string]($cCount + 7)
    $convBody = @($convLines | Select-Object -SkipLast 1)
    $insertAt = 8
    $convBody = @($convBody[0..($insertAt - 1)]) + $dAdd + @($convBody[$insertAt..($convBody.Count - 1)])
    [IO.File]::WriteAllText($convPath, ((($convBody -join "`r`n")) + "`r`n"), $enc)
    # 5) simple_triggers.txt：追加 1 行每周触发器
    $tPath = Join-Path $modDir 'simple_triggers.txt'
    $tLines = [IO.File]::ReadAllText($tPath, $enc) -split "\r?\n"
    $nTr = 0
    if (-not [int]::TryParse($tLines[1].Trim(), [ref]$nTr)) { throw 'simple_triggers.txt 第 2 行不是数量' }
    $trAdd = (Read-TextNoBom (Join-Path $pd 'trigger_add.txt')).TrimEnd()
    $trAdd = $trAdd.Replace('{{LOAN_WEEKLY}}', [string]($TAG_SCRIPT + $n))
    $trAdd = $trAdd.Replace('168.000000', ([string]$trHours + '.000000'))
    $tBody = @($tLines | Select-Object -SkipLast 1)
    $tBody[1] = [string]($nTr + 1)
    # 插到第一条触发器位置（末尾追加在 WSE2 下疑似不执行，调试用）
    $tBody = @($tBody[0], $tBody[1], $trAdd) + @($tBody[2..($tBody.Count - 1)])
    [IO.File]::WriteAllText($tPath, (($tBody -join "`r`n") + "`r`n"), $enc)

    $dl = Join-Path $modDir 'languages\cns\dialogs.csv'
    if (Test-Path $dl) {
        $txt = Read-TextNoBom $dl
        # 清掉旧贷款对话条目，再写入当前版本的条目（幂等，避免旧 tag 的中文残留）
        $lines = @($txt -split "\r?\n" | Where-Object { $_ -notmatch 'wb_loan|wb_lord_loan' })
        $entries = (Read-TextNoBom (Join-Path $pd 'dialogs_lang.csv')).TrimEnd()
        Save-TextWithBom $dl ((@($lines) -join "`r`n").TrimEnd() + "`r`n" + $entries + "`r`n")
    }
    Write-ModpackLog ("[loan] 本势力领主贷款：借款费用 {0}%、周息 {1}%、每周还财富 {2}%、财富 {3}% >= 债务时一次还清、封顶 {4}" -f $feePct, $ratePct, $repayPct, $clearPct, $capDenar)
}

# ---------- 分封嫉妒减免（国王好感） ----------
# 改 give_center_to_lord 里「嫉妒」段：计算 B 对 A 的关系时，临时加上「国王与 B 的关系 / 除数」，
# 加成后封顶（只抬不压：原本就超过封顶值的关系保持不动）。
# 效果：国王与某个领主关系好，分封领地时该领主少嫉妒、少扣与国王的关系。
function Apply-FiefEnvy([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $sPath = Join-Path $modDir 'scripts.txt'
    $rows = [IO.File]::ReadAllText($sPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }

    # 参数（params.md，用户只改「值」列）
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    $div = 5
    $cap = 16
    foreach ($line in ($md -split "\r?\n")) {
        if ($line -match '^\|\s*国王好感除数\s*\|\s*(\d+)\s*\|') { $div = [int]$Matches[1] }
        if ($line -match '^\|\s*减免后关系封顶\s*\|\s*(\d+)\s*\|') { $cap = [int]$Matches[1] }
    }
    if ($div -lt 1) { throw '国王好感除数必须 ≥1' }

    $scriptIdx = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $nm = ($rows[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm) { $scriptIdx[$nm] = $i }
    }
    if (-not $scriptIdx.ContainsKey('give_center_to_lord')) { throw 'scripts.txt 里没有 give_center_to_lord' }
    if (-not $scriptIdx.ContainsKey('troop_get_relation_with_troop')) { throw 'scripts.txt 里没有 troop_get_relation_with_troop' }
    if (-not $scriptIdx.ContainsKey('troop_change_relation_with_troop')) { throw 'scripts.txt 里没有 troop_change_relation_with_troop' }
    $gcIdx = $scriptIdx['give_center_to_lord']
    $relTag = $TAG_SCRIPT + $scriptIdx['troop_get_relation_with_troop']
    $chgTag = $TAG_SCRIPT + $scriptIdx['troop_change_relation_with_troop']

    $bodyRow = 2 + 2 * $gcIdx + 1
    $t = $rows[$bodyRow].Trim() -split '\s+'
    $decl = [int]$t[0]
    $REG0 = '72057594037927936'

    # 解析成语句
    $st = New-Object System.Collections.Generic.List[object]
    $pos = 1
    while ($pos -lt $t.Count) {
        $op = [uint64]$t[$pos]
        $na = [int]$t[$pos + 1]
        $args = @()
        for ($k = 0; $k -lt $na; $k++) { $args += $t[$pos + 2 + $k] }
        $st.Add([pscustomobject]@{ op = $op; na = $na; args = $args })
        $pos += 2 + $na
    }
    if ($pos -ne $t.Count) { throw 'give_center_to_lord 体行 token 解析不完整' }

    # 已打过补丁？（插入的 store_div 特征）
    $marker = '2123 3 1224979098644774938 1224979098644774937'
    if (($t -join ' ').Contains($marker)) { throw '这个模块里已经有分封嫉妒功能了' }

    # 找插入点：call_script(relation, B, A) → assign(:AB, reg0) → store_div(:x, :AB, 8)
    $at = -1
    for ($i = 0; $i -lt $st.Count - 2; $i++) {
        $s = $st[$i]
        if ($s.op -ne 1 -or $s.na -ne 3 -or $s.args[0] -ne [string]$relTag) { continue }
        $a1 = $st[$i + 1]
        $a2 = $st[$i + 2]
        if ($a1.op -ne 2133 -or $a1.na -ne 2 -or $a1.args[1] -ne $REG0) { continue }
        if ($a2.op -ne 2123 -or $a2.na -ne 3 -or $a2.args[1] -ne $a1.args[0]) { continue }
        $at = $i + 2
        break
    }
    if ($at -lt 0) { throw 'give_center_to_lord 里找不到嫉妒段插入点' }

    $callStmt = $st[$at - 2]
    $B = $callStmt.args[1]
    $AB = $st[$at - 1].args[0]

    # 国王变量：从后面的 troop_change_relation_with_troop(B, 国王, AB变化) 里取
    $KING = $null
    for ($i = $at; $i -lt $st.Count; $i++) {
        $s = $st[$i]
        if ($s.op -eq 1 -and $s.na -eq 4 -and $s.args[0] -eq [string]$chgTag -and $s.args[1] -eq $B) {
            $KING = $s.args[2]
            break
        }
    }
    if (-not $KING) { throw 'give_center_to_lord 里找不到国王变量' }

    # 12 条语句：try_begin / call_script / assign / gt / store_div / lt / val_add / val_min / else / gt / val_add / end_try
    $kv = '1224979098644774937'   # :l25
    $bv = '1224979098644774938'   # :l26
    $insert = @(
        '4 0',
        ("1 3 {0} {1} {2}" -f $relTag, $B, $KING),
        ("2133 2 {0} {1}" -f $kv, $REG0),
        ("32 2 {0} 0" -f $kv),
        ("2123 3 {0} {1} {2}" -f $bv, $kv, $div),
        ("2147483678 2 {0} {1}" -f $AB, $cap),
        ("2105 2 {0} {1}" -f $AB, $bv),
        ("2110 2 {0} {1}" -f $AB, $cap),
        '5 0',
        ("32 2 {0} 0" -f $kv),
        ("2105 2 {0} {1}" -f $AB, $bv),
        '3 0'
    )

    $out = New-Object System.Collections.Generic.List[string]
    $out.Add([string]($decl + $insert.Count))
    for ($i = 0; $i -lt $st.Count; $i++) {
        if ($i -eq $at) { foreach ($x in $insert) { $out.Add($x) } }
        $out.Add([string]$st[$i].op)
        $out.Add([string]$st[$i].na)
        foreach ($a in $st[$i].args) { $out.Add($a) }
    }
    $rows[$bodyRow] = ' ' + ($out -join ' ')

    $body = @($rows | Select-Object -SkipLast 1)
    [IO.File]::WriteAllText($sPath, ((($body -join "`r`n")) + "`r`n"), $enc)
    Write-ModpackLog ("[fiefenvy] 国王好感减免分封嫉妒：B对A关系 + 国王与B关系/{0}，加成后封顶 {1}（只抬不压）" -f $div, $cap)
}

# ---------- 冰释前嫌（花钱/送礼改善与领主的关系） ----------
# 与领主关系为负时，「我问你些事」子菜单（状态 491）多一个选项；领主回答后给出一组礼物选项，
# 金币/货物换关系。不改脚本、不加菜单，只加对话行（前部插入，WSE2 才加载）。
function Apply-Reconcile([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\reconcile'
    $enc = [Text.Encoding]::GetEncoding(28591)

    # 参数（params.md，用户只改「值」列）
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    function Get-ReconParam([string]$name, [int]$default) {
        foreach ($line in ($md -split "\r?\n")) {
            if ($line -match ('^\|\s*' + [regex]::Escape($name) + '\s*\|\s*(\d+)\s*\|')) { return [int]$Matches[1] }
        }
        return $default
    }
    $goldCost = Get-ReconParam '冰释前嫌金币' 1000
    $goldRel = Get-ReconParam '金币关系加成' 1
    $velvetRel = Get-ReconParam '天鹅绒关系加成' 2
    $spiceRel = Get-ReconParam '香料关系加成' 2
    $toolsRel = Get-ReconParam '工具关系加成' 1
    $oilRel = Get-ReconParam '油关系加成' 1
    $silkRel = Get-ReconParam '生丝关系加成' 1
    if ($goldCost -lt 1) { throw '冰释前嫌金币必须 ≥1' }

    $convPath = Join-Path $modDir 'conversation.txt'
    $convLines = [IO.File]::ReadAllText($convPath, $enc) -split "\r?\n"
    $cCount = 0
    if (-not [int]::TryParse($convLines[1].Trim(), [ref]$cCount)) { throw 'conversation.txt 第 2 行不是对话数量' }
    if (($convLines -join "`n") -match 'wb_reconcile') { throw '这个模块里已经有冰释前嫌功能了' }

    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    $scriptIdx = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $nm = ($scLines[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm) { $scriptIdx[$nm] = $i }
    }
    if (-not $scriptIdx.ContainsKey('troop_get_relation_with_troop')) { throw 'scripts.txt 里没有 troop_get_relation_with_troop' }
    if (-not $scriptIdx.ContainsKey('change_player_relation_with_troop')) { throw 'scripts.txt 里没有 change_player_relation_with_troop' }
    $relTag = [string]($TAG_SCRIPT + $scriptIdx['troop_get_relation_with_troop'])
    $chgTag = [string]($TAG_SCRIPT + $scriptIdx['change_player_relation_with_troop'])

    $itemIds = Get-ItemIdMap $modDir
    $itemMap = [ordered]@{
        '{{I_VELVET}}' = 'itm_velvet'; '{{I_SPICE}}' = 'itm_spice'; '{{I_TOOLS}}' = 'itm_tools'
        '{{I_OIL}}' = 'itm_oil'; '{{I_RAW_SILK}}' = 'itm_raw_silk'
    }
    $dAdd = @((Read-TextNoBom (Join-Path $pd 'dialogs_add.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($dAdd.Count -ne 11) { throw "冰释前嫌对话补丁应 11 行，实际 $($dAdd.Count)" }

    $dAdd = $dAdd -replace [regex]::Escape('{{REL}}'), $relTag
    $dAdd = $dAdd -replace [regex]::Escape('{{CHG}}'), $chgTag
    $dAdd = $dAdd -replace [regex]::Escape('{{GOLD_COST}}'), [string]$goldCost
    $dAdd = $dAdd -replace [regex]::Escape('{{GOLD_REL}}'), [string]$goldRel
    $dAdd = $dAdd -replace [regex]::Escape('{{REL_VELVET}}'), [string]$velvetRel
    $dAdd = $dAdd -replace [regex]::Escape('{{REL_SPICE}}'), [string]$spiceRel
    $dAdd = $dAdd -replace [regex]::Escape('{{REL_TOOLS}}'), [string]$toolsRel
    $dAdd = $dAdd -replace [regex]::Escape('{{REL_OIL}}'), [string]$oilRel
    $dAdd = $dAdd -replace [regex]::Escape('{{REL_SILK}}'), [string]$silkRel
    foreach ($k in $itemMap.Keys) {
        $nm = $itemMap[$k]
        if (-not $itemIds.ContainsKey($nm)) { throw "item_kinds1.txt 里找不到 $nm（冰释前嫌需要它）" }
        $dAdd = $dAdd -replace [regex]::Escape($k), [string]$itemIds[$nm]
    }
    if (($dAdd -join "`n") -match '\{\{') { throw '冰释前嫌对话还有未替换的占位符' }

    $convLines[1] = [string]($cCount + $dAdd.Count)
    $convBody = @($convLines | Select-Object -SkipLast 1)
    $insertAt = 8
    if ($convBody.Count -le $insertAt) { throw 'conversation.txt 行数不足，无法前插' }
    $convBody = @($convBody[0..($insertAt - 1)]) + $dAdd + @($convBody[$insertAt..($convBody.Count - 1)])
    [IO.File]::WriteAllText($convPath, ((($convBody -join "`r`n")) + "`r`n"), $enc)

    # 中文（对话文本走 dialogs.csv，先清旧条目再加）
    $dl = Join-Path $modDir 'languages\cns\dialogs.csv'
    if (Test-Path $dl) {
        $txt = Read-TextNoBom $dl
        $lines = @($txt -split "\r?\n" | Where-Object { $_ -notmatch 'wb_reconcile' })
        $entries = (Read-TextNoBom (Join-Path $pd 'dialogs_lang.csv')).TrimEnd()
        Save-TextWithBom $dl ((@($lines) -join "`r`n").TrimEnd() + "`r`n" + $entries + "`r`n")
    }
    Write-ModpackLog ("[reconcile] 冰释前嫌：关系<0 时加选项；{0} 金 +{1}、天鹅绒 +{2}、香料 +{3}、工具 +{4}、油 +{5}、生丝 +{6}" -f $goldCost, $goldRel, $velvetRel, $spiceRel, $toolsRel, $oilRel, $silkRel)
}

# ---------- 调解领主纠纷优化（dispute） ----------
# 1) get_political_quest：去掉任务的「结束后 N 天不再给」CD；大臣推荐阈值 -5 → 0
# 2) cf_random_political_event：玩家当国王时每日触发通知的阈值 -10 → -5（不动 AI 国王自动和解那条）
# 3) 对话：说服选项显示成功率（含说服技能加成）；完成时两个领主关系增长封顶 8；加「花钱贿赂」选项
function Apply-Dispute([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    $bribe = 2000
    foreach ($line in ($md -split "\r?\n")) {
        if ($line -match '^\|\s*调解贿赂金币\s*\|\s*(\d+)\s*\|') { $bribe = [int]$Matches[1] }
    }

    # ---------- 脚本 ----------
    $sPath = Join-Path $modDir 'scripts.txt'
    $rows = [IO.File]::ReadAllText($sPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    $idxOf = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $nm = ($rows[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm) { $idxOf[$nm] = $i }
    }
    foreach ($nm in @('get_political_quest', 'cf_random_political_event', 'troop_get_relation_with_troop')) {
        if (-not $idxOf.ContainsKey($nm)) { throw "scripts.txt 里没有 $nm（调解优化需要它）" }
    }
    $relTag = [string]($TAG_SCRIPT + $idxOf['troop_get_relation_with_troop'])

    # qst_resolve_dispute 的 quest tag（tag_quest = 7，索引按 quests.txt 顺序）
    $qRows = [IO.File]::ReadAllText((Join-Path $modDir 'quests.txt'), $enc) -split "\r?\n"
    $qIdx = -1
    $k = 0
    for ($qi = 2; $qi -lt $qRows.Count; $qi++) {
        $qn = ($qRows[$qi].Trim() -split '\s+')[0]
        if (-not $qn) { continue }
        if ($qn -eq 'qst_resolve_dispute') { $qIdx = $k; break }
        $k++
    }
    if ($qIdx -lt 0) { throw 'quests.txt 里没有 qst_resolve_dispute' }
    $qstTag = [string]([uint64]504403158265495552 + [uint64]$qIdx)

    # (1) get_political_quest：lt -5 → lt 0，并把 CD 检查换恒真
    $gRow = 2 + 2 * $idxOf['get_political_quest'] + 1
    if ($rows[$gRow] -match 'wb_dispute') { throw '这个模块里已经有调解优化了' }
    $gT = @($rows[$gRow].Trim() -split '\s+')
    $hit5 = -1
    for ($j = 4; $j -lt $gT.Count; $j++) {
        if ($gT[$j] -eq '-5' -and $gT[$j - 3] -eq '2147483678') { $hit5 = $j; break }
    }
    if ($hit5 -lt 0) { throw 'get_political_quest 里找不到 lt(x, -5) 阈值' }
    $gT[$hit5] = '0'
    # CD：调解分支里 neg|quest_slot_ge(qst, 25, 1)，位于阈值之前
    $cdAt = -1
    for ($j = 4; $j -lt $hit5; $j++) {
        if ($gT[$j] -eq '2147484214' -and ($j + 4) -lt $gT.Count -and $gT[$j + 1] -eq '3' -and $gT[$j + 3] -eq '25' -and $gT[$j + 4] -eq '1') { $cdAt = $j }
    }
    if ($cdAt -lt 0) { throw 'get_political_quest 里找不到调解任务的 CD 检查' }
    # 换成恒真 ge(0,0)：4 个 token
    $gT2 = @($gT[0..($cdAt - 1)]) + @('30', '2', '0', '0') + @($gT[($cdAt + 5)..($gT.Count - 1)])
    $rows[$gRow] = ' ' + ($gT2 -join ' ')

    # (2) cf_random_political_event：第二处 lt(:l6, -10) → lt(:l6, -5)（第一处是 AI 国王自动和解，不动）
    $cRow = 2 + 2 * $idxOf['cf_random_political_event'] + 1
    $cT = @($rows[$cRow].Trim() -split '\s+')
    $ten = @()
    for ($j = 4; $j -lt $cT.Count; $j++) {
        if ($cT[$j] -eq '-10' -and $cT[$j - 3] -eq '2147483680' -and $cT[$j - 2] -eq '2') { $ten += $j }
    }
    if ($ten.Count -lt 2) { throw "cf_random_political_event 里找到 $($ten.Count) 处 lt(x,-10)，期望 2 处" }
    $cT[$ten[1]] = '-5'
    $rows[$cRow] = ' ' + ($cT -join ' ')
    $scBody = @($rows | Select-Object -SkipLast 1)
    [IO.File]::WriteAllText($sPath, ((($scBody -join "`r`n")) + "`r`n"), $enc)

    # ---------- 对话 ----------
    $vPath = Join-Path $modDir 'conversation.txt'
    $rowsV = [IO.File]::ReadAllText($vPath, $enc) -split "\r?\n"
    $cCount = 0
    if (-not [int]::TryParse($rowsV[1].Trim(), [ref]$cCount)) { throw 'conversation.txt 第 2 行不是对话数量' }

    # 概率计算（6 条）：reg1 = (clamp(effective_relation,0,20)+1)*100/21
    $prob = @(
        '2133', '2', '72057594037927937', '144115188075855991',
        '2111', '2', '72057594037927937', '0',
        '2110', '2', '72057594037927937', '20',
        '2105', '2', '72057594037927937', '1',
        '2107', '2', '72057594037927937', '100',
        '2106', '2', '72057594037927937', '21'
    )

    # 解析对话行
    function Split-Dlg([string]$line) {
        $t = @($line.Trim() -split '\s+')
        $cc = [int]$t[3]
        $p = 4
        $conds = @()
        for ($k = 0; $k -lt $cc; $k++) { $na = [int]$t[$p + 1]; $ar = if ($na -gt 0) { $t[($p + 2)..($p + 1 + $na)] } else { @() }; $conds += , @($t[$p], $t[$p + 1], $ar); $p += 2 + $na }
        $text = $t[$p]; $target = $t[$p + 1]; $ec = [int]$t[$p + 2]
        $p += 3
        $effs = @()
        for ($k = 0; $k -lt $ec; $k++) { $na = [int]$t[$p + 1]; $ar = if ($na -gt 0) { $t[($p + 2)..($p + 1 + $na)] } else { @() }; $effs += , @($t[$p], $t[$p + 1], $ar); $p += 2 + $na }
        $voice = if ($p -lt $t.Count) { ($t[$p..($t.Count - 1)] -join ' ') } else { '' }
        return [pscustomobject]@{ head = $t[0]; flags = $t[1]; src = $t[2]; conds = $conds; text = $text; target = $target; effs = $effs; voice = $voice }
    }
    function Flat($stmts) {
        $out = @()
        foreach ($s in $stmts) { $out += $s[0]; $out += $s[1]; foreach ($a in $s[2]) { $out += $a } }
        return $out
    }

    $probDone = 0
    $capDone = 0
    for ($i = 2; $i -lt $rowsV.Count; $i++) {
        $ln = $rowsV[$i]
        if (-not $ln) { continue }
        # (3) 说服选项显示概率
        if ($ln -match '^\s*dlga_lord_quarrel_intervention_2:lord_quarrel_intervention_3b(\.1)? ') {
            $d = Split-Dlg $ln
            $d.conds = @(
                @('2133', '2', @('72057594037927937', '144115188075855991')),
                @('2111', '2', @('72057594037927937', '0')),
                @('2110', '2', @('72057594037927937', '20')),
                @('2105', '2', @('72057594037927937', '1')),
                @('2107', '2', @('72057594037927937', '100')),
                @('2108', '2', @('72057594037927937', '21'))
            ) + $d.conds
            $d.text = $d.text + '_({reg1}%)'
            $st = @($d.head, $d.flags, $d.src, [string]$d.conds.Count) + (Flat $d.conds) + @($d.text, $d.target, [string]$d.effs.Count) + (Flat $d.effs)
            if ($d.voice) { $st += $d.voice }
            $rowsV[$i] = ' ' + ($st -join ' ') + ' '
            $probDone++
            continue
        }
        # (4) 完成时关系增长封顶 8
        if ($ln -match '^\s*dlga_lord_quarrel_intervention_4:lord_pretalk ' -and $ln -match 'Let_it_be_as_though') {
            $d = Split-Dlg $ln
            $e = $d.effs[0]
            if ($e[0] -ne '1' -or $e[1] -ne '4' -or $e[2][3] -ne '20') { throw '调解完成对话的效果块结构与预期不符' }
            $talk = $e[2][1]; $other = $e[2][2]; $chg = $e[2][0]
            $newEff = @(
                @('1', '3', @($relTag, $talk, $other)),
                @('2121', '3', @('1224979098644774912', '8', '72057594037927936')),
                @('2110', '2', @('1224979098644774912', '20')),
                @('4', '0', @()),
                @('32', '2', @('1224979098644774912', '0')),
                @('1', '4', @($chg, $talk, $other, '1224979098644774912')),
                @('3', '0', @())
            )
            $d.effs = $newEff + @($d.effs[1..($d.effs.Count - 1)])
            $st = @($d.head, $d.flags, $d.src, [string]$d.conds.Count) + (Flat $d.conds) + @($d.text, $d.target, [string]$d.effs.Count) + (Flat $d.effs)
            if ($d.voice) { $st += $d.voice }
            $rowsV[$i] = ' ' + ($st -join ' ') + ' '
            $capDone++
            continue
        }
    }
    if ($probDone -lt 2) { throw "说服选项概率插入应 2 处，实际 $probDone" }
    if ($capDone -lt 1) { throw '找不到调解完成对话的封顶插入点' }

    # (5) 金钱选项（插在 3b 选项之前）
    $moneyLine = 'dlga_lord_quarrel_intervention_2:lord_quarrel_intervention_4 69631 385 2 2149 2 72057594037927936 360287970189639680 32 2 72057594037927936 ' + [string]$bribe + ' Here,_take_' + [string]$bribe + '_denars._Let_us_settle_this.  388  8 1529 2 360287970189639680 ' + [string]$bribe + ' 4 0 546 3 ' + $qstTag + ' 2 144115188075855987 506 3 ' + $qstTag + ' 16 1 5 0 546 3 ' + $qstTag + ' 4 144115188075855987 506 3 ' + $qstTag + ' 17 1 3 0 NO_VOICEOVER'
    $insAt = -1
    for ($i = 2; $i -lt $rowsV.Count; $i++) {
        if ($rowsV[$i] -match '^\s*dlga_lord_quarrel_intervention_2:lord_quarrel_intervention_3b ') { $insAt = $i; break }
    }
    if ($insAt -lt 0) { throw '找不到 lord_quarrel_intervention_2 的 3b 选项行' }
    $rowsV[1] = [string]($cCount + 1)
    $bodyV = @($rowsV | Select-Object -SkipLast 1)
    $bodyV = @($bodyV[0..($insAt - 1)]) + @($moneyLine) + @($bodyV[$insAt..($bodyV.Count - 1)])
    [IO.File]::WriteAllText($vPath, ((($bodyV -join "`r`n")) + "`r`n"), $enc)

    # (6) 中文：改两条加概率、加一条金钱选项
    $dl = Join-Path $modDir 'languages\cns\dialogs.csv'
    if (Test-Path $dl) {
        $txt = Read-TextNoBom $dl
        $lines = @($txt -split "\r?\n")
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^dlga_lord_quarrel_intervention_2:lord_quarrel_intervention_3b\|') { $lines[$i] = 'dlga_lord_quarrel_intervention_2:lord_quarrel_intervention_3b|不 管 你 们 有 什 么 过 节 ， 我 要 你 们 就 此 了 结 。 （ 成 功 率 {reg1}% ）' }
            if ($lines[$i] -match '^dlga_lord_quarrel_intervention_2:lord_quarrel_intervention_3b\.1\|') { $lines[$i] = 'dlga_lord_quarrel_intervention_2:lord_quarrel_intervention_3b.1|你 能 想 办 法 消 弭 你 们 之 间 的 分 歧 么 ？ （ 成 功 率 {reg1}% ）' }
        }
        $lines += ('dlga_lord_quarrel_intervention_2:lord_quarrel_intervention_4|这 ' + [string]$bribe + ' 第 纳 尔 请 收 下 ， 这 事 就 此 了 结 。')
        Save-TextWithBom $dl ((@($lines | Where-Object { $_ -ne '' }) -join "`r`n") + "`r`n")
    }
    Write-ModpackLog ("[dispute] 调解纠纷：任务无 CD、推荐阈值 -5→0、通知阈值 -10→-5、说服显示概率、完成关系封顶 8、可花 {0} 金贿赂" -f $bribe)
}

# ---------- 说服相关（persuade） ----------
# 1) 领主招募「是你做决定的时候了」显示支持度 %（$pledge_chance，前面分析时已算好）
# 2) 同伴闹离队、说服失败后可以花钱挽留（扣钱 + 惩罚减半，效果同说服成功）
function Apply-Persuade([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    $bribe = 2000
    foreach ($line in ($md -split "\r?\n")) {
        if ($line -match '^\|\s*同伴挽留金币\s*\|\s*(\d+)\s*\|') { $bribe = [int]$Matches[1] }
    }
    if ($bribe -lt 1) { throw '同伴挽留金币必须 ≥1' }

    $varPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($varPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $boIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_comp_bribe_ok') { $boIdx = $i; break } }
    if ($boIdx -lt 0) { $boIdx = $varList.Count; $varList += 'g_comp_bribe_ok' }
    [IO.File]::WriteAllText($varPath, (($varList -join "`r`n") + "`r`n"), $enc)
    $bribeOk = [string](144115188075855872 + $boIdx)

    $vPath = Join-Path $modDir 'conversation.txt'
    $rows = [IO.File]::ReadAllText($vPath, $enc) -split "\r?\n"
    $cCount = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$cCount)) { throw 'conversation.txt 第 2 行不是对话数量' }
    if (($rows -join "`n") -match 'Give_him_\d+_denars') { throw '这个模块里已经有说服优化了' }

    $PV = '144115188075856059'   # $pledge_chance
    $REG1 = '72057594037927937'
    $changed = 0
    $insertAt = -1
    $srcState = '241'
    $persuadeVar = $null
    $persuadeState = $null
    $resetDone = 0

    for ($i = 2; $i -lt $rows.Count; $i++) {
        $ln = $rows[$i]
        if (-not $ln) { continue }
        # 1) 支持度显示
        if ($ln -match '^\s*dlga_lord_recruit_6:lord_recruit_6_reaction ') {
            $t = @($ln.Trim() -split '\s+')
            $new = @($t[0], $t[1], $t[2], '1', '2133', '2', $REG1, $PV) +
                   @('It_is_time_for_you_to_make_a_decision._({reg1}%)') +
                   @($t[5..($t.Count - 1)])
            $rows[$i] = ' ' + ($new -join ' ') + ' '
            $changed++
            continue
        }
        # 2) 找同伴离队选项区，记录 source_state 和插入位置
        if ($ln -match '^\s*dlga_companion_quitting_response:companion_quitting_yes ') {
            $t = @($ln.Trim() -split '\s+')
            $srcState = $t[2]
            $insertAt = $i
        }
        # 2b) 从「也许我能劝你改变主意」取 $player_can_persuade_npc 的编码
        #     （进离队对话时置 1、说服后置 0，用来只在说服失败后显示挽留）
        if ($ln -match '^\s*dlga_companion_quitting_response:companion_quitting_persuasion ') {
            $t = @($ln.Trim() -split '\s+')
            if ($t[4] -eq '31' -and $t[5] -eq '2') { $persuadeVar = $t[6] }
        }
        # 2c) 原版挽留状态数字（成功行 dlga_companion_quitting_persuasion:close_window 的 state 字段）
        #     给钱后直接跳这个状态，复用原版判定与台词
        if ($ln -match '^\s*dlga_companion_quitting_persuasion:close_window ') {
            $t = @($ln.Trim() -split '\s+')
            $persuadeState = $t[2]
        }
        # 2d) （保留位置，不再需要「已给钱」标记：失败后允许继续给钱）
    }
    if ($changed -lt 1) { throw '找不到「是你做决定的时候了」对话行' }
    if ($insertAt -lt 0) { throw '找不到同伴离队选项行' }
    if (-not $persuadeVar) { throw '找不到 $player_can_persuade_npc 的编码' }

    # 3) 同伴挽留选项：条件=钱够 且 已经试过说服（$player_can_persuade_npc == 0）
    #    效果：扣钱 + 两个惩罚各减半，与说服成功一致
    $bribeLine = 'dlga_companion_quitting_response:wb_bribe_reply 69631 ' + $srcState +
        ' 3 2149 2 72057594037927936 360287970189639680 32 2 72057594037927936 ' + [string]$bribe +
        ' 31 2 ' + $persuadeVar + ' 0' +
        ' Give_him_' + [string]$bribe + '_denars._I_know_your_mind_is_made_up._Take_this_money_and_reconsider.  9030  9' +
        ' 1529 2 360287970189639680 ' + [string]$bribe +
        ' 2136 3 1224979098644774912 -2 13' +
        ' 2170 3 1224979098644774913 7 360287970189639680' +
        ' 4 0 2147483680 2 1224979098644774912 1224979098644774913' +
        ' 2133 2 ' + $bribeOk + ' 1' +
        ' 5 0' +
        ' 2133 2 ' + $bribeOk + ' 0' +
        ' 3 0' +
        ' NO_VOICEOVER'
    $replyOkLine = 'dlga_wb_bribe_reply:close_window 4095 9030 1 31 2 ' + $bribeOk +
        ' 1  If_you_do_that,_I_suppose_I_can_stay_a_while_longer,_see_if_things_improve.  6  6' +
        ' 520 3 1224979098644774914 144115188075856024 69 2108 2 1224979098644774914 2 500 3 144115188075856024 69 1224979098644774914' +
        ' 520 3 1224979098644774915 144115188075856024 77 2108 2 1224979098644774915 2 500 3 144115188075856024 77 1224979098644774915' +
        ' NO_VOICEOVER'
    $replyFailLine = 'dlga_wb_bribe_reply:companion_quitting_response 4095 9030 1 31 2 ' + $bribeOk +
        ' 0  I_appreciate_the_offer,_but_I_still_choose_to_leave.  ' + $srcState + '  0  NO_VOICEOVER'

    $rows[1] = [string]($cCount + 3)
    $body = @($rows | Select-Object -SkipLast 1)
    $body = @($body[0..$insertAt]) + @($bribeLine) + @($replyOkLine) + @($replyFailLine) + @($body[($insertAt + 1)..($body.Count - 1)])
    [IO.File]::WriteAllText($vPath, ((($body -join "`r`n")) + "`r`n"), $enc)

    # 4) 中文
    $dl = Join-Path $modDir 'languages\cns\dialogs.csv'
    if (Test-Path $dl) {
        $txt = Read-TextNoBom $dl
        $lines = @($txt -split "\r?\n")
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^dlga_lord_recruit_6:lord_recruit_6_reaction\|') { $lines[$i] = 'dlga_lord_recruit_6:lord_recruit_6_reaction|是 时 候 做 出 决 断 了 。 （ 支 持 度 {reg1}% ）' }
        }
        $lines += ('dlga_companion_quitting_response:wb_bribe_reply|（ 给 他 ' + [string]$bribe + ' 第 纳 尔 ） 我 知 你 心 意 已 决 ， 这 笔 钱 先 收 下 ， 你 可 愿 再 考 虑 ？')
        $lines += 'dlga_wb_bribe_reply:close_window|如 果 你 这 样 做 ， 我 似 乎 可 以 再 待 一 阵 子 ， 看 看 情 况 会 不 会 好 转 。'
        $lines += 'dlga_wb_bribe_reply:companion_quitting_response|你 的 好 意 我 心 领 了 ， 但 我 依 然 选 择 离 开 。'
        Save-TextWithBom $dl ((@($lines | Where-Object { $_ -ne '' }) -join "`r`n") + "`r`n")
    }
    Write-ModpackLog ("[persuade] 领主招募显示支持度；同伴离队说服失败后可花 {0} 金挽留" -f $bribe)
}

# ---------- 游戏参数（params.md） ----------
function Apply-Params([string]$modDir) {
    $mdPath = Join-Path $PSScriptRoot 'params.md'
    if (-not (Test-Path $mdPath)) { return }
    $enc = [Text.Encoding]::GetEncoding(28591)
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $md = Read-TextNoBom $mdPath
    $rows = @($md -split "\r?\n" | Where-Object {
        $_ -match '^\|' -and $_ -notmatch '^\|\s*参数' -and $_ -notmatch '^\|[\s\-|]+\|?\s*$'
    })
    $applied = 0
    foreach ($row in $rows) {
        $cols = @($row.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
        if ($cols.Count -lt 5) { continue }
        $pname = $cols[0]; $pval = $cols[1]; $script = $cols[2]; $match = $cols[3]
        $expect = 0
        if (-not [int]::TryParse($cols[4], [ref]$expect)) { continue }
        if ($pval -eq '' -or $pval -eq '-') { continue }
        $nameIdx = -1
        for ($i = 0; $i -lt $scLines.Count; $i++) {
            if ($scLines[$i] -like "$script *") { $nameIdx = $i; break }
        }
        if ($nameIdx -lt 0) { Write-ModpackLog "[params] [?] 找不到脚本 $script（$pname）"; continue }
        $bodyIdx = $nameIdx + 1
        $pat = [regex]::Escape($match) + '\s+(\d+)'
        $hits = [regex]::Matches(($scLines[$bodyIdx].Trim()), $pat)
        if ($hits.Count -ne $expect) {
            Write-ModpackLog "[params] [!] $pname：$script 里匹配 $($hits.Count) 处（期望 $expect），跳过"
            continue
        }
        $newBody = [regex]::Replace($scLines[$bodyIdx].Trim(), $pat, "$match $pval")
        $scLines[$bodyIdx] = ' ' + $newBody
        $applied++
        Write-ModpackLog "[params] $pname = $pval（$script）"
    }
    if ($applied -gt 0) {
        [IO.File]::WriteAllText($scPath, ($scLines -join "`r`n"), $enc)
        Write-ModpackLog "[params] 共应用 $applied 个参数"
    }
}

# ---------- 分封显示已有领地 ----------
function Apply-Fief([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $conv = Join-Path $modDir 'conversation.txt'
    $text = $enc.GetString([IO.File]::ReadAllBytes($conv))
    $tag = 'dlga_minister_grant_fief_select_recipient_choice:minister_grant_fief_complete'
    $idx = $text.IndexOf($tag)
    if ($idx -lt 0) { throw 'conversation.txt 里没找到大臣分封对话' }
    $lineEnd = $text.IndexOf("`r`n", $idx)
    if ($lineEnd -lt 0) { $lineEnd = $text.Length }
    $line = $text.Substring($idx, $lineEnd - $idx)
    if ($line -match '936748722493063349') { Write-ModpackLog '[fief] 该对话已有改动，跳过'; return }
    $toks = @($line -split '\s+')
    $n = [int]$toks[3]
    # 在第 6 条语句（str_store_troop_name s1, X）之后插入
    $pos = -1
    for ($i = 0; $i -lt $toks.Count - 5; $i++) {
        if ($toks[$i] -eq '2322' -and $toks[$i + 1] -eq '2' -and $toks[$i + 2] -eq '1') { $pos = $i; break }
    }
    if ($pos -lt 0) { throw '没找到插入点（str_store_troop_name）' }
    $var = $toks[$pos + 3]

    # 动态选项（repeat_for_troops）只渲染 {s1}，所以按原版做法：cond 里把领地拼进 s1
    #   1) 调脚本 → s0 = 城列表, reg0 = 数量
    #   2) s0 = "(no fiefs)" 或 "(fiefs: {s0})"
    #   3) s1 = "{s1} {s0}"   ← 需要一条拼接用 quick_string
    $qPath = Join-Path $modDir 'quick_strings.txt'
    $qRows = [IO.File]::ReadAllText($qPath, $enc) -split "\r?\n"
    $qn = 0
    if (-not [int]::TryParse($qRows[0].Trim(), [ref]$qn)) { throw 'quick_strings.txt 第 1 行不是数量' }
    if (($qRows -join "`n") -match 'qstr_wb_fiefs_join') { throw '这个模块里已经有分封领地拼接串了' }
    $joinId = [string]([uint64]1585267068834414592 + [uint64]$qn)   # tag 22 (quick_strings) | 新索引
    $qRows[0] = [string]($qn + 1)
    $qBody = @($qRows | Select-Object -SkipLast 1)
    $qBody += 'qstr_wb_fiefs_join {s1}_{s0}'
    [IO.File]::WriteAllText($qPath, ((($qBody -join "`r`n")) + "`r`n"), $enc)

    $insert = @(
        '1', '2', '936748722493063349', $var,               # call print_troop_owned_centers_in_numbers_to_s0
        '4', '0', '31', '2', '72057594037927936', '0',      # try_begin  eq reg0 0
        '2320', '2', '0', '1585267068834415175',            #   str_store_string s0, "(no fiefs)"
        '5', '0', '2320', '2', '0', '1585267068834415176',  # else_try  str_store_string s0, "(fiefs: {s0})"
        '3', '0',                                           # try_end
        '2320', '2', '1', $joinId                           # str_store_string s1, "{s1} {s0}"
    )
    if ($insert.Count -ne 26) { throw "插入语句数异常：$($insert.Count)" }
    $toks[3] = [string]($n + 8)
    $newToks = @($toks[0..($pos + 3)]) + $insert + @($toks[($pos + 4)..($toks.Count - 1)])
    $line2 = ($newToks -join ' ')
    $text = $text.Substring(0, $idx) + $line2 + $text.Substring($lineEnd)
    [IO.File]::WriteAllBytes($conv, $enc.GetBytes($text))
    Write-ModpackLog '[fief] 大臣分封对话加「已有领地」显示'
}

# ---------- 跟随元帅任务奖励 ----------
# 1) 战役结束结算：50 * (小时 / 10 + 1) → 固定 3000
# 2) 送牛 / 侦察 领奖对话：不再重新挂跟随任务，直接给 3000
function Apply-ArmyReward([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)

    # 1) scripts.txt：check_and_finish_active_army_quests_for_faction
    #    公式 50*(小时/10+1) → 固定 assign 3000（与原版任务一样只给玩家）
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    $nameIdx = -1
    for ($i = 0; $i -lt $scLines.Count; $i++) {
        if ($scLines[$i] -like 'check_and_finish_active_army_quests_for_faction *') { $nameIdx = $i; break }
    }
    if ($nameIdx -lt 0) { throw 'scripts.txt 里没有 check_and_finish_active_army_quests_for_faction' }
    $bodyIdx = $nameIdx + 1
    $body = $scLines[$bodyIdx].Trim()
    $m = [regex]::Match($body, '2122 3 (\d+) \d+ 5 2108 2 \1 50 2107 2 \1 50 2105 2 \1 50')
    if ($m.Success) {
        $reg = $m.Groups[1].Value
        $declared = [int](($body -split '\s+')[0])
        # 4 条（乘 5 / 除 50 / 乘 50 / 加 50）→ 1 条 assign 3000，语句数 -3
        $newBody = $body.Remove($m.Index, $m.Length).Insert($m.Index, "2133 2 $reg 3000")
        $newBody = [regex]::Replace($newBody, '^\d+', [string]($declared - 3))
        $scLines[$bodyIdx] = ' ' + $newBody
        [IO.File]::WriteAllText($scPath, ($scLines -join "`r`n"), $enc)
        Write-ModpackLog '[armyreward] 战役结束奖励：固定 3000 经验'
    } elseif ($body -match '2133 2 \d+ 3000') {
        Write-ModpackLog '[armyreward] 战役结算已经是 3000，跳过'
    } else {
        throw '战役结算脚本里没找到经验公式 token（版本不符）'
    }

    # 2) conversation.txt：送牛 / 侦察 领奖对话
    $conv = Join-Path $modDir 'conversation.txt'
    $lines = [IO.File]::ReadAllText($conv, $enc) -split "\r?\n"

    $sLines = [IO.File]::ReadAllText((Join-Path $modDir 'strings.txt'), $enc) -split "\r?\n"
    $sfb2 = -1
    for ($i = 2; $i -lt $sLines.Count; $i++) {
        if ($sLines[$i] -match '^str_follow_army_quest_brief_2\b') { $sfb2 = $i - 2; break }
    }
    if ($sfb2 -lt 0) { throw 'strings.txt 里没有 str_follow_army_quest_brief_2' }
    $sfb2Tag = [string](216172782113783808 + $sfb2)

    $changed = 0
    for ($li = 0; $li -lt $lines.Count; $li++) {
        $line = $lines[$li]
        if (-not $line.StartsWith('dlga_lord_start:')) { continue }
        if (-not $line.Contains($sfb2Tag)) { continue }
        $toks = @($line -split '\s+')
        # 重挂段：setup_quest_text / str_store_string(brief_2) / start_quest / assign warnings 0
        $seg = -1
        for ($k = 0; $k -le $toks.Count - 16; $k++) {
            if ($toks[$k] -eq '1290' -and $toks[$k + 1] -eq '1' -and
                $toks[$k + 3] -eq '2320' -and $toks[$k + 4] -eq '2' -and $toks[$k + 5] -eq '2' -and
                $toks[$k + 6] -eq $sfb2Tag -and
                $toks[$k + 7] -eq '1' -and $toks[$k + 8] -eq '3' -and
                $toks[$k + 10] -eq $toks[$k + 2] -and
                $toks[$k + 12] -eq '2133' -and $toks[$k + 13] -eq '2' -and $toks[$k + 15] -eq '0') {
                $seg = $k
                break
            }
        }
        if ($seg -lt 0) { continue }
        # 文本 token 之后两个数字 = output_state、结果语句数
        $textIdx = -1
        for ($k = 1; $k -lt $toks.Count; $k++) { if ($toks[$k] -notmatch '^\d+$') { $textIdx = $k; break } }
        if ($textIdx -lt 0) { throw "conversation 第 $li 行找不到文本 token" }
        $rcIdx = $textIdx + 2
        if ($rcIdx -lt 0 -or $rcIdx -ge $toks.Count) { throw "conversation 第 $li 行结果语句数位置异常" }
        $rc = [int]$toks[$rcIdx]
        $stmtStart = $rcIdx + 1
        $stmtEnd = $toks.Count - 2      # 最后一个是 NO_VOICEOVER
        if ($seg -lt $stmtStart -or ($seg + 15) -gt $stmtEnd) { throw "conversation 第 $li 行重挂段跨界" }
        $before = @()
        if ($seg -gt $stmtStart) { $before = @($toks[$stmtStart..($seg - 1)]) }
        $after = @()
        if (($seg + 16) -le $stmtEnd) { $after = @($toks[($seg + 16)..$stmtEnd]) }
        $newStmts = $before + @('1064', '1', '3000') + $after
        $newToks = @($toks[0..$rcIdx]) + $newStmts + @($toks[$toks.Count - 1])
        $newToks[$rcIdx] = [string]($rc - 3)
        $lines[$li] = ($newToks -join ' ')
        $changed++
    }
    if ($changed -gt 0) {
        [IO.File]::WriteAllText($conv, ($lines -join "`r`n"), $enc)
        Write-ModpackLog "[armyreward] 支线完成对话 $changed 处：给 3000 经验，不再续挂跟随"
    } else {
        Write-ModpackLog '[armyreward] 没找到可改的支线完成对话（可能已改过）'
    }
}

# ---------- 公用菜单注册表（多个功能共用一个菜单时用） ----------
# 思路：菜单骨架（入口 + 空菜单 + 返回项）归生成器所有，功能只往里追加选项。
# 这样任何功能都能独立勾选：勾 A+B 时一个入口两个选项，只勾 B 时一个入口一个选项，都不勾就不出现。
# 以后要共用菜单的功能照抄三行：
#   Register-Menu  建骨架并登记索引（已存在则复用）
#   Get-MenuTag    取菜单 tag（菜单 ID 集中分配，谁先应用都不影响）
#   Add-MenuOption 往骨架里加自己的选项（插到返回项前面）
$script:MenuRegistry = @{}

function Find-MenuIndex([string]$modDir, [string]$menuName) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $rows = [IO.File]::ReadAllText((Join-Path $modDir 'menus.txt'), $enc) -split "\r?\n"
    $mi = 0
    for ($i = 0; $i -lt $rows.Count; $i++) {
        if ($rows[$i] -match '^menu_') {
            if (($rows[$i] -split '\s+')[0] -eq $menuName) { return $mi }
            $mi++
        }
    }
    return -1
}

function Register-Menu([string]$modDir, [string]$menuName, [string]$defLine, [string]$optLine) {
    $idx = Find-MenuIndex $modDir $menuName
    if ($idx -ge 0) { $script:MenuRegistry[$menuName] = $idx; return $idx }
    $enc = [Text.Encoding]::GetEncoding(28591)
    $p = Join-Path $modDir 'menus.txt'
    $rows = [IO.File]::ReadAllText($p, $enc) -split "\r?\n"
    while ($rows.Count -ge 1 -and $rows[$rows.Count - 1] -eq '') { $rows = @($rows[0..($rows.Count - 2)]) }
    $n = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { throw 'menus.txt 第 2 行不是菜单数量' }
    $rows[1] = [string]($n + 1)
    $rows += $defLine
    $rows += $optLine
    [IO.File]::WriteAllText($p, ((($rows -join "`r`n")) + "`r`n"), $enc)
    $script:MenuRegistry[$menuName] = $n
    return $n
}

function Get-MenuTag([string]$menuName) {
    if (-not $script:MenuRegistry.ContainsKey($menuName)) { throw "菜单 $menuName 还没注册（先 Register-Menu）" }
    return [string](864691128455135232 + $script:MenuRegistry[$menuName])
}

# 往菜单追加一个选项：插到锚点选项（一般是 Back）前面；选项文本要带结尾的 ' .'
function Add-MenuOption([string]$modDir, [string]$menuName, [string]$optText, [string]$beforeOption) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $p = Join-Path $modDir 'menus.txt'
    $rows = [IO.File]::ReadAllText($p, $enc) -split "\r?\n"
    $defIdx = -1
    for ($i = 0; $i -lt $rows.Count; $i++) {
        if ($rows[$i].StartsWith($menuName + ' ')) { $defIdx = $i; break }
    }
    if ($defIdx -lt 0) { throw "menus.txt 里没有菜单 $menuName（先 Register-Menu）" }
    $t = $rows[$defIdx].Trim() -split '\s+'
    $oc = 0
    if (-not [int]::TryParse($t[$t.Count - 1], [ref]$oc)) { throw "$menuName 定义行末尾不是选项数" }
    $t[$t.Count - 1] = [string]($oc + 1)
    $rows[$defIdx] = $t -join ' '
    $optLine = $rows[$defIdx + 1]
    $pos = $optLine.IndexOf($beforeOption)
    if ($pos -lt 0) { throw "$menuName 里找不到锚点选项 $beforeOption" }
    $rows[$defIdx + 1] = $optLine.Substring(0, $pos) + $optText + '  ' + $optLine.Substring($pos)
    [IO.File]::WriteAllText($p, ((($rows -join "`r`n")) + "`r`n"), $enc)
}

# ---------- 训练菜单骨架：mentor（传授经验）与 learnskill（学习技能）共用 ----------
# 骨架 = menu_town 里的「训练」入口 + 空的 menu_training（只有返回项）。
# mentor 追加「传授经验」选项、learnskill 追加「学习技能」选项；两者可以各自勾选。
function Apply-TrainingHost([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $existing = Find-MenuIndex $modDir 'menu_training'
    if ($existing -ge 0) {
        $script:MenuRegistry['menu_training'] = $existing
        Write-ModpackLog '[training] 训练菜单骨架已存在，复用'
    } else {
        $p = Join-Path $modDir 'menus.txt'
        $rows = [IO.File]::ReadAllText($p, $enc) -split "\r?\n"
        while ($rows.Count -ge 1 -and $rows[$rows.Count - 1] -eq '') { $rows = @($rows[0..($rows.Count - 2)]) }
        $n = 0
        if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { throw 'menus.txt 第 2 行不是菜单数量' }
        $townLine = -1
        for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i].StartsWith('menu_town ')) { $townLine = $i; break } }
        if ($townLine -lt 0) { throw 'menus.txt 里没有 menu_town' }
        $townIdx = [int](($townLine - 2) / 2)
        $townTag = [string](864691128455135232 + $townIdx)
        $trainingIdx = $n
        $trainingTag = [string](864691128455135232 + $trainingIdx)
        # menu_town 入口：城镇归属势力与玩家支持者势力关系 >= 0（与旧版「训练」入口条件一致）
        $frag = 'mno_town_training  3  2204 2 1224979098644774912 144115188075856213  2190 3 1224979098644774913 1224979098644774912 432345564227567630  30 2 1224979098644774913 0  Training.  1  2060 1 ' + $trainingTag + '  .'
        $t = $rows[$townLine].TrimEnd() -split ' '
        $oc = 0
        if (-not [int]::TryParse($t[$t.Count - 1], [ref]$oc)) { throw 'menu_town 行尾选项数解析失败' }
        $t[$t.Count - 1] = [string]($oc + 1)
        $rows[$townLine] = $t -join ' '
        $opt = $rows[$townLine + 1]
        $pos = $opt.IndexOf('mno_castle_wait')
        if ($pos -ge 0) {
            $e = $opt.IndexOf(' . ', $pos)
            if ($e -ge 0) { $pos = $e + 3 }
        } else { $pos = $opt.Length }
        $rows[$townLine + 1] = $opt.Substring(0, $pos) + '  ' + $frag + '  ' + $opt.Substring($pos)
        $rows[1] = [string]($n + 1)
        $rows += 'menu_training 4096 Training. none 0 1'
        $rows += ' mno_training_back  0  Back.  1  2060 1 ' + $townTag + '  .'
        [IO.File]::WriteAllText($p, ((($rows -join "`r`n")) + "`r`n"), $enc)
        $script:MenuRegistry['menu_training'] = $trainingIdx
        Write-ModpackLog '[training] 训练菜单骨架：menu_town 入口 + menu_training（返回项）'
    }
    $gm = Join-Path $modDir 'languages\cns\game_menus.csv'
    if (Test-Path $gm) {
        $txt = Read-TextNoBom $gm
        $lines = @($txt -split "\r?\n" | Where-Object { $_ -notmatch '^(mno_town_training|menu_training|mno_training_back)\|' })
        $entries = @('mno_town_training|训 练', 'menu_training|训 练', 'mno_training_back|返 回')
        Save-TextWithBom $gm ((@($lines) -join "`r`n").TrimEnd() + "`r`n" + ($entries -join "`r`n") + "`r`n")
    }
}

# ---------- 城里的「指导伙伴」 ----------
# 城镇菜单「训练」→「传授经验」→ 同伴列表菜单（每人一项 + 返回）→ 选定后进确认菜单（开始传授/返回）
# 开始传授 = rest_for_hours_interactive 在据点等待时间流逝；每小时触发器给目标补（导师经验 - 受指导者经验）* 0.3%（最少 1 点），提示走 Lua
function Apply-Mentor([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $pd = Join-Path $PSScriptRoot 'patches\mentor'

    # 传授经验比例（千分之几，默认 3 = 0.3%），params.md 可调
    $mentorPermille = 3
    $mdMentor = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    foreach ($ln in ($mdMentor -split "\r?\n")) {
        if ($ln -match '^\|\s*传授经验比例（千分之几）\s*\|\s*(\d+)\s*\|') { $mentorPermille = [int]$Matches[1] }
    }
    if ($mentorPermille -lt 0) { $mentorPermille = 0 }

    # 1) variables.txt：target + count
    $vPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $tIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_companion_mentor_target') { $tIdx = $i; break } }
    if ($tIdx -lt 0) { $tIdx = $varList.Count; $varList += 'g_companion_mentor_target' }
    $cIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_companion_mentor_count') { $cIdx = $i; break } }
    if ($cIdx -lt 0) { $cIdx = $varList.Count; $varList += 'g_companion_mentor_count' }
    $mIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_companion_mentor_town') { $mIdx = $i; break } }
    if ($mIdx -lt 0) { $mIdx = $varList.Count; $varList += 'g_companion_mentor_town' }
    $ntIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_companion_mentor_notice') { $ntIdx = $i; break } }
    if ($ntIdx -lt 0) { $ntIdx = $varList.Count; $varList += 'g_companion_mentor_notice' }
    $tsIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_mentor_tick_seen') { $tsIdx = $i; break } }
    if ($tsIdx -lt 0) { $tsIdx = $varList.Count; $varList += 'g_mentor_tick_seen' }
    [IO.File]::WriteAllText($vPath, (($varList -join "`r`n") + "`r`n"), $enc)
    $varT = [string](144115188075855872 + $tIdx)
    $varC = [string](144115188075855872 + $cIdx)
    $varM = [string](144115188075855872 + $mIdx)
    $varN = [string](144115188075855872 + $ntIdx)
    $varS = [string](144115188075855872 + $tsIdx)

    $epIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_encountered_party') { $epIdx = $i; break } }
    if ($epIdx -lt 0) { throw 'variables.txt 里没有 g_encountered_party' }
    $epTag = [string](144115188075855872 + $epIdx)

    # 2) 训练提示改走 Lua 消息变量（不再追加 str_mentor_gain）
    $msgTIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_wb_msg_type') { $msgTIdx = $i; break } }
    if ($msgTIdx -lt 0) { throw 'variables.txt 里没有 g_wb_msg_type（先跑 Apply-MsgVars）' }
    $msgAIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_wb_msg_arg1') { $msgAIdx = $i; break } }
    if ($msgAIdx -lt 0) { throw 'variables.txt 里没有 g_wb_msg_arg1' }
    $msgTag = [string](144115188075855872 + $msgTIdx)
    $msgArg = [string](144115188075855872 + $msgAIdx)

    # 3) scripts.txt：list / pick / tick 三个脚本
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $nSc = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$nSc)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    $listTag = [string]($TAG_SCRIPT + $nSc)
    $pickTag = [string]($TAG_SCRIPT + $nSc + 1)
    $infoTag = [string]($TAG_SCRIPT + $nSc + 2)
    $tickTag = [string]($TAG_SCRIPT + $nSc + 3)
    $startTag = [string]($TAG_SCRIPT + $nSc + 4)
    $mTmp = [IO.File]::ReadAllText((Join-Path $modDir 'menus.txt'), $enc) -split "\r?\n"
    $nMenuTmp = 0
    $null = [int]::TryParse($mTmp[1].Trim(), [ref]$nMenuTmp)
    $actMenuTag = [string]($TAG_MENU + $nMenuTmp + 1)
    $noneMenuTag = [string]($TAG_MENU + $nMenuTmp + 2)
    $def = @((Read-TextNoBom (Join-Path $pd 'script_def.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($def.Count -ne 10) { throw "mentor 脚本补丁应 10 行（5 个脚本），实际 $($def.Count)" }
    for ($i = 0; $i -lt $def.Count; $i++) {
        $def[$i] = $def[$i].Replace('{{VAR_T}}', $varT).Replace('{{VAR_C}}', $varC).Replace('{{VAR_TOWN}}', $varM).Replace('{{EP}}', $epTag).Replace('{{MSG_T}}', $msgTag).Replace('{{MSG_A}}', $msgArg).Replace('{{NOTICE}}', $varN).Replace('{{TICKSEEN}}', $varS).Replace('{{NONE_MENU}}', $noneMenuTag).Replace('{{ACT_MENU}}', $actMenuTag)
    }
    # 传授经验比例：tick 脚本里 val_mul x 3 / 1000 → 用 params.md 的值
    for ($i = 0; $i -lt $def.Count; $i++) {
        $def[$i] = [regex]::Replace($def[$i], '2107 2 (\d+) 3 2108 2 \1 1000', '2107 2 $1 ' + $mentorPermille + ' 2108 2 $1 1000')
    }
    $scBody = @($scLines | Select-Object -SkipLast 1)
    $scBody[1] = [string]($nSc + 5)
    [IO.File]::WriteAllText($scPath, ((($scBody + $def) -join "`r`n") + "`r`n"), $enc)

    # 4) simple_triggers.txt：每小时 tick
    $tPath = Join-Path $modDir 'simple_triggers.txt'
    $tLines = [IO.File]::ReadAllText($tPath, $enc) -split "\r?\n"
    $nTr = 0
    if (-not [int]::TryParse($tLines[1].Trim(), [ref]$nTr)) { throw 'simple_triggers.txt 第 2 行不是数量' }
    $tBody = @($tLines | Select-Object -SkipLast 1)
    $tBody[1] = [string]($nTr + 1)
    # 触发器必须插在文件前部：WSE2 不执行 simple_triggers 末尾追加的行（踩过，见坑.md）
    $tBody = @($tBody[0], $tBody[1], ('1.000000 1 1 1 ' + $tickTag)) + @($tBody[2..($tBody.Count - 1)])
    [IO.File]::WriteAllText($tPath, (($tBody -join "`r`n") + "`r`n"), $enc)

    # 5) menus.txt：往「训练」菜单骨架追加「传授经验」选项 + 两个子菜单（列表/确认）
    #    骨架（menu_town 入口 + menu_training + 返回）由 Apply-TrainingHost 建，这里只管自己的选项
    $mPath = Join-Path $modDir 'menus.txt'
    $mLines = [IO.File]::ReadAllText($mPath, $enc) -split "\r?\n"
    $nMenu = 0
    if (-not [int]::TryParse($mLines[1].Trim(), [ref]$nMenu)) { throw 'menus.txt 第 2 行不是菜单数量' }
    $listMenuId = $nMenu
    $actMenuId = $nMenu + 1
    $listMenuTag = [string]($TAG_MENU + $listMenuId)
    $actMenuTag = [string]($TAG_MENU + $actMenuId)
    $noneMenuTag = [string]($TAG_MENU + $nMenu + 2)
    $trainingTag = Get-MenuTag 'menu_training'

    # 5a) 追加 menu_mentor_list / menu_mentor_act / menu_wb_mentor_none（返回都回训练菜单）
    $listLine1 = 'menu_mentor_list 0 Choose_a_companion. none 1 1 1 ' + $listTag + ' 16'
    $listOpts = ''
    for ($n = 1; $n -le 15; $n++) {
        $listOpts += 'mno_mentor_pick' + $n + '  1  30 2 ' + $varC + ' ' + $n + '  {s' + $n + '}  1  1 2 ' + $pickTag + ' ' + $n + '  .  '
    }
    $listOpts += 'mno_mentor_list_back  0  Back.  1  2060 1 ' + $trainingTag + '  .'
    $listLine2 = ' ' + $listOpts
    $actLine1 = 'menu_mentor_act 0 {s2}_shares_his_experience_with_{s1}. none 1 1 1 ' + $infoTag + ' 2'
    $actLine2 = ' mno_mentor_start  0  Begin_sharing.  1  1 1 ' + $startTag + '  .  mno_mentor_back  0  Back.  1  2060 1 ' + $listMenuTag + '  .'
    $mLines[1] = $mLines[1] -replace '\d+', [string]($nMenu + 3)
    $mBody = @($mLines | Select-Object -SkipLast 1)
    $mBody += $listLine1
    $mBody += $listLine2
    $mBody += $actLine1
    $mBody += $actLine2
    $mBody += 'menu_wb_mentor_none 0 {s61}_already_knows_best. none 0 1'
    $mBody += ' mno_wb_mentor_none_back  0  Back.  1  2060 1 ' + $listMenuTag + '  .'
    [IO.File]::WriteAllText($mPath, (($mBody -join "`r`n") + "`r`n"), $enc)

    # 5b) 往训练菜单骨架加「传授经验」（只在玩家自己的城镇显示）
    $mentorOpt = 'mno_training_mentor  1  541 3 ' + $epTag + ' 7 360287970189639680  Share_experience.  1  2060 1 ' + $listMenuTag + '  .'
    Add-MenuOption $modDir 'menu_training' $mentorOpt 'mno_training_back'

    # 6) 语言 CSV（训练入口/菜单名由骨架写；这里只写自己的选项）
    $gm = Join-Path $modDir 'languages\cns\game_menus.csv'
    if (Test-Path $gm) {
        $txt = Read-TextNoBom $gm
        if ($txt -notmatch 'mno_training_mentor') {
            $clean = @($txt -split "\r?\n" | Where-Object { $_ -notmatch '^mno_town_mentor\|' })
            $entries = @(
                'mno_training_mentor|传 授 经 验',
                'menu_mentor_list|选 择 同 伴',
                'menu_mentor_act|{s2} 以 过 来 人 的 身 份 ， 将 历 练 所 得 一 一 说 与 {s1} 听 。',
                'mno_mentor_start|开 始 传 授',
                'mno_mentor_list_back|返 回',
                'mno_mentor_back|返 回',
                'menu_wb_mentor_none|{s61} 已 是 队 中 经 验 最 高 者 ， 暂 时 无 人 可 教 。',
                'mno_wb_mentor_none_back|返 回'
            ) -join "`r`n"
            Save-TextWithBom $gm ((@($clean) -join "`r`n").TrimEnd() + "`r`n" + $entries + "`r`n")
        }
    }
    # 中文 CSV：训练提示已改走 Lua，不再需要 str_mentor_gain 词条
        Write-ModpackLog "[mentor] 队伍等级高的 NPC 训练等级低 NPC（城镇 → 训练 → 传授经验）：每小时补 (导师经验 - 受指导者经验) × $($mentorPermille)‰，最少 1 点；导师排除受指导者本人；无人可教走 menu_wb_mentor_none 界面；含首次 tick 心跳消息（21）用于排查"
}

# ---------- 技能调整 ----------
function Apply-Skills([string]$modDir) {
    $enc = New-Object Text.UTF8Encoding($false)
    # skills.txt：掠夺 敏捷 → 智力（仍是队伍技能；属性只影响面板图标与加点门槛，效果不变）
    $f = Join-Path $modDir 'skills.txt'
    $text = [IO.File]::ReadAllText($f, $enc)
    $pairs = @(
        @('skl_looting Looting 17 10', 'skl_looting Looting 18 10', '掠夺'),
        @('skl_riding Riding 1 10', 'skl_riding Riding 0 10', '骑术')
    )
    foreach ($p in $pairs) {
        if ($text.Contains($p[1])) { throw "这个模块里$($p[2])已经改过了" }
        if (-not $text.Contains($p[0])) { throw "skills.txt 里没找到$($p[2])行" }
        $text = $text.Replace($p[0], $p[1])
    }
    [IO.File]::WriteAllText($f, $text, $enc)
    Write-ModpackLog '[skills] 掠夺：敏捷 → 智力（仍是队伍技能，效果不变）'
}

# ---------- 城镇「训练」→「学习技能」 ----------
function Apply-LearnSkill([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\learnskill'
    $enc = [Text.Encoding]::GetEncoding(28591)

    # 1) 变量：g_learn_done（学习完成时间）/ g_learn_skill_id（正在学的技能）
    #    g_companion_mentor_target 与 mentor 共用，单独勾「学习技能」时在这里补建
    $vPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    foreach ($vn in @('g_learn_done', 'g_learn_skill_id', 'g_companion_mentor_target')) {
        $found = -1
        for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq $vn) { $found = $i; break } }
        if ($found -lt 0) { $varList += $vn }
    }
    [IO.File]::WriteAllText($vPath, (($varList -join "`r`n") + "`r`n"), $enc)
    $varIdx = @{}
    for ($i = 0; $i -lt $varList.Count; $i++) { $varIdx[$varList[$i].Trim()] = $i }
    $learnVar = [string](144115188075855872 + $varIdx['g_learn_done'])
    $skillIdTag = [string](144115188075855872 + $varIdx['g_learn_skill_id'])
    $mTag = [string](144115188075855872 + $varIdx['g_companion_mentor_target'])
    if (-not $varIdx.ContainsKey('g_encountered_party')) { throw 'variables.txt 里没有 g_encountered_party（版本可能变了）' }
    $epTag = [string](144115188075855872 + $varIdx['g_encountered_party'])
    $msgT = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_wb_msg_type') { $msgT = $i; break } }
    if ($msgT -lt 0) { throw 'variables.txt 里没有 g_wb_msg_type（先跑 Apply-MsgVars）' }
    $msgTag = [string](144115188075855872 + $msgT)
    $msgA = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_wb_msg_arg1') { $msgA = $i; break } }
    if ($msgA -lt 0) { throw 'variables.txt 里没有 g_wb_msg_arg1' }
    $msgArgTag = [string](144115188075855872 + $msgA)

    # 2) 学习提示改走 Lua 消息变量；原生字符串 100/101 保持原版内容（不再修改）
    # 2b) 不再追加 str_wb_learn_* 字符串

    # 3) scripts：追加 wb_learn_skill
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $nSc = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$nSc)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    if (($scLines -join "`n") -match 'wb_learn_skill') { throw '这个模块里已经有学习技能功能了' }
    $def = @((Read-TextNoBom (Join-Path $pd 'script_def.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($def.Count -ne 2) { throw "脚本补丁应 2 行，实际 $($def.Count)" }
    $mTmpL = [IO.File]::ReadAllText((Join-Path $modDir 'menus.txt'), $enc) -split "\r?\n"
    $nMenuTmpL = 0
    $null = [int]::TryParse($mTmpL[1].Trim(), [ref]$nMenuTmpL)
    # 学习菜单是第 nMenuTmpL 个、无人可教界面是第 nMenuTmpL+1 个（本功能只追加这两个菜单）
    $learnNoneTag = [string]($TAG_MENU + $nMenuTmpL + 1)
    $def[1] = $def[1].Replace('{{LEARN_VAR}}', $learnVar).Replace('{{MENTOR_T}}', $mTag).Replace('{{MSG_T}}', $msgTag).Replace('{{SKILL_ID}}', $skillIdTag).Replace('{{LEARN_NONE}}', $learnNoneTag)
    $scBody = @($scLines | Select-Object -SkipLast 1)
    $scBody[1] = [string]($nSc + 1)
    [IO.File]::WriteAllText($scPath, ((($scBody + $def) -join "`r`n") + "`r`n"), $enc)
    $scriptTag = [string]($TAG_SCRIPT + $nSc)

    # 4) simple_triggers：空占位 + 每小时学习完成检查
    $tPath = Join-Path $modDir 'simple_triggers.txt'
    $tLines = [IO.File]::ReadAllText($tPath, $enc) -split "\r?\n"
    $nTr = 0
    if (-not [int]::TryParse($tLines[1].Trim(), [ref]$nTr)) { throw 'simple_triggers.txt 第 2 行不是数量' }
    $tBody = @($tLines | Select-Object -SkipLast 1)
    $addTr = @()
    if (($tLines -join "`n") -notmatch '^0\.000000  0 $') { $addTr += '0.000000  0 ' }
    $addTr += ('1.000000  7 4 0 32 2 ' + $learnVar + ' 0 2270 1 1224979098644774912 30 2 1224979098644774912 ' + $learnVar + ' 2133 2 ' + $msgArgTag + ' ' + $skillIdTag + ' 2133 2 ' + $msgTag + ' 4 2133 2 ' + $learnVar + ' 0 3 0')
    $tBody[1] = [string]($nTr + $addTr.Count)
    $tBody = @($tBody[0], $tBody[1]) + $addTr + @($tBody[2..($tBody.Count - 1)])
    [IO.File]::WriteAllText($tPath, (($tBody -join "`r`n") + "`r`n"), $enc)

    # 5) menus：学习菜单 + 无人可教界面；「学习技能」入口挂到训练菜单骨架
    $mPath = Join-Path $modDir 'menus.txt'
    $mLines = [IO.File]::ReadAllText($mPath, $enc) -split "\r?\n"
    $nMenu = 0
    if (-not [int]::TryParse($mLines[1].Trim(), [ref]$nMenu)) { throw 'menus.txt 第 2 行不是菜单数量' }
    if (($mLines -join "`n") -match 'mno_training_skill') { throw '这个模块里已经有学习技能功能了' }
    $learnTag = [string]($TAG_MENU + $nMenu)
    $trainingTag = Get-MenuTag 'menu_training'
    $learnLines = @((Read-TextNoBom (Join-Path $pd 'menu_def.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($learnLines.Count -ne 2) { throw "学习菜单补丁应 2 行，实际 $($learnLines.Count)" }
    for ($k = 0; $k -lt 2; $k++) {
        $learnLines[$k] = $learnLines[$k].Replace('{{SCRIPT}}', $scriptTag).Replace('{{TRAINING}}', $trainingTag)
    }
    $mBody = @($mLines | Select-Object -SkipLast 1)
    $mBody[1] = [string]($nMenu + 2)
    $mBody += $learnLines
    $mBody += 'menu_wb_learn_none 0 No_one_can_teach_you. none 0 1'
    $mBody += ' mno_wb_learn_none_back  0  Back.  1  2060 1 ' + $learnTag + '  .'
    [IO.File]::WriteAllText($mPath, (($mBody -join "`r`n") + "`r`n"), $enc)

    # 5b) 往训练菜单骨架加「学习技能」
    $skillOpt = 'mno_training_skill  0  Learn_a_skill.  1  2060 1 ' + $learnTag + '  .'
    Add-MenuOption $modDir 'menu_training' $skillOpt 'mno_training_back'

    # 6) 中文菜单词条（训练入口/菜单名由骨架写；这里写学习菜单和自己那一条选项）
    $gm = Join-Path $modDir 'languages\cns\game_menus.csv'
    if (Test-Path $gm) {
        $txt = Read-TextNoBom $gm
        if ($txt -notmatch 'mno_training_skill') {
            # 清掉旧键（旧的入口名 / 旧的训练菜单选项名），避免同 key 两条
            $clean = @($txt -split "\r?\n" | Where-Object { $_ -notmatch '^(mno_town_mentor|mno_training_companion)\|' })
            $entries = (Read-TextNoBom (Join-Path $pd 'lang_menus.csv')).TrimEnd() -replace "\r?\n", "`r`n"
            Save-TextWithBom $gm ((@($clean) -join "`r`n").TrimEnd() + "`r`n" + $entries + "`r`n")
        }
    }

    # 7) 追加区字符串重排（WSE2 不加载末尾 2 条）
    Reorder-AppendStrings $modDir
    Write-ModpackLog '[learnskill] 城镇 → 训练 → 学习技能：强制等待 8 小时（7 小时后提示），每次 +1 级'
}
# 追加区字符串重排：WSE2 不加载 strings.txt 追加区末尾的字符串（原生数 + 29 之后），
# 把「显示用」的串（detail 关系后缀 / 与君主关系）前移，其余字符串后移并重算所有引用。
function Reorder-AppendStrings([string]$modDir) {
    $sPath = Join-Path $modDir 'strings.txt'
    $enc = [Text.Encoding]::GetEncoding(28591)
    $rows = [IO.File]::ReadAllText($sPath, $enc) -split "\r?\n"
    while ($rows.Count -ge 1 -and $rows[$rows.Count - 1] -eq '') { $rows = @($rows[0..($rows.Count - 2)]) }
    $start = -1
    for ($i = 2; $i -lt $rows.Count; $i++) {
        if ($rows[$i] -match '^(str_wb_loan_repaid|str_detail_stats|str_wb_learn_gain|str_mentor_gain) ') { $start = $i; break }
    }
    if ($start -lt 0) { return }
    $append = @($rows[$start..($rows.Count - 1)])
    # WSE2 加载不了追加区的末尾/后段字符串：把「显示用」的字符串前置，把纯调试串挪到最后
    $moveNames = @()
    $frontNames = @('str_detail_relation_suffix', 'str_detail_king_relation')
    $front = @(); $keep = @(); $moved = @()
    foreach ($r in $append) {
        $nm = ($r -split ' ')[0]
        if ($frontNames -contains $nm) { $front += $r }
        elseif ($moveNames -contains $nm) { $moved += $r }
        else { $keep += $r }
    }
    if ($front.Count -eq 0 -and $moved.Count -eq 0) { return }
    $newAppend = @($front) + @($keep) + @($moved)
    $base = $start - 2
    $map = @{}
    for ($i = 0; $i -lt $newAppend.Count; $i++) { $nm = ($newAppend[$i] -split ' ')[0]; $map[$nm] = $base + $i }
    $oldToNew = @{}
    for ($i = 0; $i -lt $append.Count; $i++) { $nm = ($append[$i] -split ' ')[0]; $oldToNew[$base + $i] = $map[$nm] }
    foreach ($f in @('scripts.txt', 'conversation.txt', 'menus.txt')) {
        $p = Join-Path $modDir $f
        if (-not (Test-Path $p)) { continue }
        $t = [IO.File]::ReadAllText($p, $enc)
        $ev = {
            param($mm)
            $v = [uint64]$mm.Value
            if ($v -ge $TAG_STRING -and $v -lt ($TAG_STRING + [uint64]4096)) {
                $idx = [int]($v - $TAG_STRING)
                if ($oldToNew.ContainsKey($idx)) { return [string]($TAG_STRING + [uint64]$oldToNew[$idx]) }
            }
            return $mm.Value
        }
        $t = [regex]::Replace($t, '\d{18,19}', $ev)
        [IO.File]::WriteAllText($p, $t, $enc)
    }
    $newRows = @($rows[0..($start - 1)]) + $newAppend
    [IO.File]::WriteAllText($sPath, (($newRows -join "`r`n") + "`r`n"), $enc)
}

# ---------- 运气：夜袭免战 + 伴侣供奉 ----------
function Apply-Luck([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\luck'
    $enc = [Text.Encoding]::GetEncoding(28591)

    # 参数（params.md 的「运气参数」表，用户只改「值」列）
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    function Get-LuckParam([string]$name, [int]$default) {
        foreach ($line in ($md -split "\r?\n")) {
            if ($line -match ('^\|\s*' + [regex]::Escape($name) + '\s*\|\s*(\d+)\s*\|')) { return [int]$Matches[1] }
        }
        return $default
    }
    $nightPct = Get-LuckParam '夜袭满概率' 70
    $sneakPct = Get-LuckParam '潜入满概率' 70
    $luckThresh = Get-LuckParam '供奉开启阈值' 100
    $decayH = Get-LuckParam '运气额外下降间隔（小时）' 156
    $luckJump = Get-LuckParam '运气每跳下降' 1
    $offerN = Get-LuckParam '供奉份数' 400
    $g1 = Get-LuckParam '供奉恢复-寒酸' 10
    $g2 = Get-LuckParam '供奉恢复-微薄' 20
    $g3 = Get-LuckParam '供奉恢复-勉强' 35
    $g4 = Get-LuckParam '供奉恢复-充足' 50
    $g5 = Get-LuckParam '供奉恢复-丰盛' 60
    $g6 = Get-LuckParam '供奉恢复-盛大' 70
    $restH = Get-LuckParam '供奉停留小时' 8

    # 1) 变量：g_player_luck（原生已有，初始 200，每 180 小时 -1）+ 供奉计时/比例
    $vPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $luckIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_player_luck') { $luckIdx = $i; break } }
    if ($luckIdx -lt 0) { $luckIdx = $varList.Count; $varList += 'g_player_luck' }
    $endIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_luck_offering_end') { $endIdx = $i; break } }
    if ($endIdx -lt 0) { $endIdx = $varList.Count; $varList += 'g_luck_offering_end' }
    $pctIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_luck_offering_pct') { $pctIdx = $i; break } }
    if ($pctIdx -lt 0) { $pctIdx = $varList.Count; $varList += 'g_luck_offering_pct' }
    $totalIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_luck_offering_total') { $totalIdx = $i; break } }
    if ($totalIdx -lt 0) { $totalIdx = $varList.Count; $varList += 'g_luck_offering_total' }
    $hoursIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_luck_hours') { $hoursIdx = $i; break } }
    if ($hoursIdx -lt 0) { $hoursIdx = $varList.Count; $varList += 'g_luck_hours' }
    $noticeIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_luck_notice') { $noticeIdx = $i; break } }
    if ($noticeIdx -lt 0) { $noticeIdx = $varList.Count; $varList += 'g_luck_notice' }
    [IO.File]::WriteAllText($vPath, (($varList -join "`r`n") + "`r`n"), $enc)
    $luckTag = [string]([int64]144115188075855872 + [int64]$luckIdx)
    $endVar = [string]([int64]144115188075855872 + [int64]$endIdx)
    $pctVar = [string]([int64]144115188075855872 + [int64]$pctIdx)
    $totalVar = [string]([int64]144115188075855872 + [int64]$totalIdx)
    $hoursVar = [string]([int64]144115188075855872 + [int64]$hoursIdx)
    $noticeVar = [string]([int64]144115188075855872 + [int64]$noticeIdx)
    $msgTIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_wb_msg_type') { $msgTIdx = $i; break } }
    if ($msgTIdx -lt 0) { throw 'variables.txt 里没有 g_wb_msg_type（先跑 Apply-MsgVars）' }
    $msgAIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_wb_msg_arg1') { $msgAIdx = $i; break } }
    if ($msgAIdx -lt 0) { throw 'variables.txt 里没有 g_wb_msg_arg1' }
    $msgTag = [string]([int64]144115188075855872 + [int64]$msgTIdx)
    $msgArg = [string]([int64]144115188075855872 + [int64]$msgAIdx)

    # 2) 字符串：11 条（宴会等级 6 + 供奉完成/开始 + 夜袭/潜入躲过 + 潜入测试）
    $sPath = Join-Path $modDir 'strings.txt'
    $sLines = [IO.File]::ReadAllText($sPath, $enc) -split "\r?\n"
    while ($sLines.Count -ge 1 -and $sLines[$sLines.Count - 1] -eq '') { $sLines = @($sLines[0..($sLines.Count - 2)]) }
    $nStr = 0
    if (-not [int]::TryParse($sLines[1].Trim(), [ref]$nStr)) { throw 'strings.txt 第 2 行不是字符串数量' }
    $sAdd = @((Read-TextNoBom (Join-Path $pd 'strings_add.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($sAdd.Count -ne 6) { throw "运气字符串补丁应 6 行（仅宴会档位名），实际 $($sAdd.Count)" }
    if (-not (($sLines -join "`n") -match 'str_wb_luck_grade_1')) {
        $sLines[1] = [string]($nStr + $sAdd.Count)
        [IO.File]::WriteAllText($sPath, ((($sLines + $sAdd) -join "`r`n") + "`r`n"), $enc)
        $strGrade1 = [string]([int64]216172782113783808 + [int64]$nStr)
    } else {
        $strGrade1 = ''
        for ($i = 2; $i -lt $sLines.Count; $i++) {
            if ($sLines[$i] -match '^str_wb_luck_grade_1\b') { $strGrade1 = [string]([int64]216172782113783808 + [int64]($i - 2)); break }
        }
        if (-not $strGrade1) { throw 'strings.txt 里找不到 str_wb_luck_grade_1' }
    }
    # 供奉/档位/夜袭提示改走 Lua 消息变量（不再追加对应字符串）


    # 3) scripts.txt：索引表 + 脚本 ID
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    if (($scLines -join "`n") -match 'wb_luck_offering') { throw '这个模块里已经有运气功能了' }
    $nSc = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$nSc)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    $scIdx = @{}
    for ($i = 0; $i -lt $nSc; $i++) {
        $nm = ($scLines[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm) { $scIdx[$nm] = $i }
    }
    if (-not $scIdx.ContainsKey('internal_politics_rate_feast_to_s9')) { throw 'scripts.txt 里没有 internal_politics_rate_feast_to_s9' }
    if (-not $scIdx.ContainsKey('cf_enter_center_location_bandit_check')) { throw 'scripts.txt 里没有 cf_enter_center_location_bandit_check' }
    $feastTag = [string]($TAG_SCRIPT + $scIdx['internal_politics_rate_feast_to_s9'])
    # 宴会评分修复：原版 total 里油/香料加的是"份量"（数量/(人数/12)，几乎不加分），改成 percentage（0-100）
    $feastIdx = $scIdx['internal_politics_rate_feast_to_s9']
    $fb = $scLines[3 + 2 * $feastIdx]
    $fb2 = $fb.Replace('2105 2 1224979098644774942 1224979098644774931', '2105 2 1224979098644774942 1224979098644774932').Replace('2105 2 1224979098644774942 1224979098644774933', '2105 2 1224979098644774942 1224979098644774934')
    if ($fb2 -eq $fb) { throw '宴会评分补丁：脚本里没找到 total 的油/香料加项（可能已被改过）' }
    $scLines[3 + 2 * $feastIdx] = $fb2
    $evalTag = [string]($TAG_SCRIPT + $nSc)
    $doTag = [string]($TAG_SCRIPT + $nSc + 1)
    $tickTag = [string]($TAG_SCRIPT + $nSc + 2)
    $decayTag = [string]($TAG_SCRIPT + $nSc + 3)

    # 3a) 夜袭：根本拦截。在「夜晚 + 有强盗」条件之后插入幸运判定，成功则显示提示并返回 0（不进战斗）
    $cfIdx = $scIdx['cf_enter_center_location_bandit_check']
    $cfBody = $scLines[3 + 2 * $cfIdx].TrimStart()
    $cfPrefix = '2147483679 2 144115188075856244 0 561 3 144115188075856213 155 1 31 2 144115188075856236 0 31 2 144115188075856215 0'
    if (-not $cfBody.StartsWith('68 ' + $cfPrefix + ' 4 0 ')) { throw 'cf_enter_center_location_bandit_check 体行开头与预期不符（可能已被其它补丁改过），拒绝插入' }
    $cfRest = $cfBody.Substring(3 + $cfPrefix.Length + 1)
    $cfInsert = "2133 2 1224979098644774950 0 2136 3 1224979098644774951 0 100 2122 3 1224979098644774952 $luckTag $nightPct 2108 2 1224979098644774952 200 4 0 2147483678 2 1224979098644774951 1224979098644774952 2133 2 1224979098644774950 1 2133 2 $msgTag 12 3 0 31 2 1224979098644774950 0"
    $scLines[3 + 2 * $cfIdx] = "78 $cfPrefix $cfInsert $cfRest"

    # 3b) 追加供奉脚本（评估 + 供奉 + 到时结算）
    $def = @((Read-TextNoBom (Join-Path $pd 'script_def.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($def.Count -ne 8) { throw "运气脚本补丁应 8 行，实际 $($def.Count)" }
    for ($i = 0; $i -lt $def.Count; $i++) {
        $def[$i] = $def[$i].Replace('{{FEAST}}', $feastTag).Replace('{{LUCK}}', $luckTag).Replace('{{OFFERING_N}}', [string]$offerN)
        $def[$i] = $def[$i].Replace('{{STR_GRADE1}}', $strGrade1).Replace('{{TOTAL_VAR}}', $totalVar)
        $def[$i] = $def[$i].Replace('{{MSG_T}}', $msgTag).Replace('{{MSG_A}}', $msgArg)
        $def[$i] = $def[$i].Replace('{{HOURS}}', $hoursVar).Replace('{{NOTICE}}', $noticeVar).Replace('{{DECAY_H}}', [string]$decayH).Replace('{{THRESH}}', [string]$luckThresh).Replace('{{JUMP}}', [string]$luckJump)
        $def[$i] = $def[$i].Replace('{{GRADE1}}', [string]$g1).Replace('{{GRADE2}}', [string]$g2).Replace('{{GRADE3}}', [string]$g3)
        $def[$i] = $def[$i].Replace('{{GRADE4}}', [string]$g4).Replace('{{GRADE5}}', [string]$g5).Replace('{{GRADE6}}', [string]$g6)
        $def[$i] = $def[$i].Replace('{{REST_H}}', [string]$restH).Replace('{{END_VAR}}', $endVar).Replace('{{PCT_VAR}}', $pctVar)
    }
    if (($def -join "`n") -match '\{\{') { throw '运气脚本还有未替换的占位符' }
    $scBody = @($scLines | Select-Object -SkipLast 1)
    $scBody[1] = [string]($nSc + 4)
    $scBody += $def
    [IO.File]::WriteAllText($scPath, ((($scBody) -join "`r`n") + "`r`n"), $enc)

    # 3d) 潜入：mno_town_sneak 失败分支插入二次幸运判定（含临时测试提示）
    $mPath = Join-Path $modDir 'menus.txt'
    $mLines = [IO.File]::ReadAllText($mPath, $enc) -split "\r?\n"
    $menuIdx = @{}
    $mi = 0
    for ($i = 2; $i + 1 -lt $mLines.Count; $i += 2) {
        $ln = $mLines[$i].Trim()
        if ($ln -match '^menu_') { $nm = ($ln -split '\s+')[0]; $menuIdx[$nm] = $mi; $mi++ }
    }
    if (-not $menuIdx.ContainsKey('menu_sneak_into_town_suceeded')) { throw 'menus.txt 里没有 menu_sneak_into_town_suceeded' }
    if (-not $menuIdx.ContainsKey('menu_sneak_into_town_caught')) { throw 'menus.txt 里没有 menu_sneak_into_town_caught' }
    $siTag = [string]($TAG_MENU + $menuIdx['menu_sneak_into_town_suceeded'])
    $caughtTag = [string]($TAG_MENU + $menuIdx['menu_sneak_into_town_caught'])
    if (-not $menuIdx.ContainsKey('menu_town')) { throw 'menus.txt 里没有 menu_town' }
    $townMenuTag = [string]($TAG_MENU + $menuIdx['menu_town'])
    $luckOkMenuId = $mi
    $luckOkMenuTag = [string]($TAG_MENU + $luckOkMenuId)
    $waitMenuId = $mi + 1
    $waitMenuTag = [string]($TAG_MENU + $waitMenuId)
    $ci = -1
    for ($i = 0; $i -lt $mLines.Count; $i++) { if ($mLines[$i].StartsWith('menu_castle_outside ')) { $ci = $i; break } }
    if ($ci -lt 0) { throw 'menus.txt 里没有 menu_castle_outside' }
    $opt = $mLines[$ci + 1]
    $pos = $opt.IndexOf('mno_town_sneak ')
    if ($pos -lt 0) { throw 'menu_castle_outside 里没有 mno_town_sneak' }
    $e2 = $opt.IndexOf(' . ', $pos)
    if ($e2 -lt 0) { throw 'mno_town_sneak 选项没有结束符' }
    $seg = $opt.Substring($pos, $e2 - $pos)
    $tail = '5 0 2060 1 ' + $caughtTag + ' 3 0'
    if (-not $seg.Contains($tail)) { throw 'mno_town_sneak 失败分支结构不符（可能已被其它补丁改过）' }
    $insert = "2136 3 1224979098644774917 0 100 2122 3 1224979098644774918 $luckTag $sneakPct 2108 2 1224979098644774918 200 4 0 2147483678 2 1224979098644774917 1224979098644774918 2133 2 144115188075856221 0 2133 2 144115188075856215 1 2133 2 144115188075856216 1 2060 1 $luckOkMenuTag 2133 2 144115188075856156 1 5 0 2060 1 $caughtTag 3 0 3 0"
    $seg = $seg.Replace($tail, '5 0 ' + $insert)
    $mt = [regex]::Match($seg, 'sneak_into_the_\{s7\}\s+(\d+)\s+')
    if (-not $mt.Success) { throw '找不到 mno_town_sneak 动作语句数' }
    $seg = $seg.Substring(0, $mt.Groups[1].Index) + '31' + $seg.Substring($mt.Groups[1].Index + $mt.Groups[1].Length)
    $mLines[$ci + 1] = $opt.Substring(0, $pos) + $seg + $opt.Substring($e2)
    # 追加「幸运潜入成功」结果板（黄色菜单，带继续按钮），不再用浮动消息
    $mpBody = @($mLines | Select-Object -SkipLast 1)
    $mpBody[1] = [string]($mi + 2)
    $mpBody += 'menu_wb_luck_sneak_ok 512 The_guards_notice_you,_but_your_luck_holds_-_you_slip_away_before_they_close_in. none 0 1'
    $mpBody += ' mno_wb_luck_sneak_go  0  Continue...  1  2060 1 ' + $townMenuTag + '  .'
    $mpBody += 'menu_wb_luck_wait 0 Luck_offering_started. none 0 1'
    $mpBody += ' mno_wb_luck_wait_go  0  Continue...  2  1030 3 8 4 0  2052 0  .'
    [IO.File]::WriteAllText($mPath, ((($mpBody) -join "`r`n") + "`r`n"), $enc)

    # 4) conversation.txt：配偶「供奉」对话（前部插入，末尾不加载）
    $convPath = Join-Path $modDir 'conversation.txt'
    $convLines = [IO.File]::ReadAllText($convPath, $enc) -split "\r?\n"
    $cCount = 0
    if (-not [int]::TryParse($convLines[1].Trim(), [ref]$cCount)) { throw 'conversation.txt 第 2 行不是对话数量' }
    $dAdd = @((Read-TextNoBom (Join-Path $pd 'dialogs_add.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($dAdd.Count -ne 7) { throw "运气对话补丁应 7 行，实际 $($dAdd.Count)" }
    for ($i = 0; $i -lt $dAdd.Count; $i++) {
        $dAdd[$i] = $dAdd[$i].Replace('{{EVAL}}', $evalTag).Replace('{{DO}}', $doTag).Replace('{{TOTAL_VAR}}', $totalVar).Replace('{{LUCK}}', $luckTag).Replace('{{THRESH}}', [string]$luckThresh).Replace('{{WAIT_MENU}}', $waitMenuTag)
    }
    if (($dAdd -join "`n") -match '\{\{') { throw '运气对话还有未替换的占位符' }
    $askLine = $dAdd[0]
    $restAdd = @($dAdd[1..($dAdd.Count - 1)])
    $convLines[1] = [string]($cCount + $dAdd.Count)
    $convBody = @($convLines | Select-Object -SkipLast 1)
    $insertAt = 8
    if ($convBody.Count -le $insertAt) { throw 'conversation.txt 行数不足，无法前插' }
    $convBody = @($convBody[0..($insertAt - 1)]) + $restAdd + @($convBody[$insertAt..($convBody.Count - 1)])
    # 「我的妻子…」选项放进配偶对话菜单，排在「举办宴会」之前
    $cw = -1
    for ($i = 0; $i -lt $convBody.Count; $i++) {
        if ($convBody[$i] -match '^dlga_spouse_talk:spouse_organize_feast 69631 469 ') { $cw = $i; break }
    }
    if ($cw -lt 0) { throw 'conversation.txt 里找不到 spouse_talk 的 organize_feast 选项' }
    $convBody = @($convBody[0..($cw - 1)]) + @($askLine) + @($convBody[$cw..($convBody.Count - 1)])
    [IO.File]::WriteAllText($convPath, ((($convBody -join "`r`n")) + "`r`n"), $enc)

    # 5) 中文
    $dl = Join-Path $modDir 'languages\cns\dialogs.csv'
    if (Test-Path $dl) {
        $txt = Read-TextNoBom $dl
        $lines = @($txt -split "\r?\n" | Where-Object { $_ -notmatch 'wb_luck_offering' })
        $entries = (Read-TextNoBom (Join-Path $pd 'dialogs_lang.csv')).TrimEnd()
        Save-TextWithBom $dl ((@($lines) -join "`r`n").TrimEnd() + "`r`n" + $entries + "`r`n")
    }
    $gs = Join-Path $modDir 'languages\cns\game_strings.csv'
    if (Test-Path $gs) {
        $txt = Read-TextNoBom $gs
        if ($txt -notmatch 'str_wb_luck_grade_1') {
            $entries = (Read-TextNoBom (Join-Path $pd 'lang_entries.csv')).TrimEnd()
            Save-TextWithBom $gs ($txt.TrimEnd() + "`r`n" + $entries + "`r`n")
        }
    }
    $gm = Join-Path $modDir 'languages\cns\game_menus.csv'
    if (Test-Path $gm) {
        $txt = Read-TextNoBom $gm
        if ($txt -notmatch 'menu_wb_luck_sneak_ok') {
            $entries = "menu_wb_luck_sneak_ok|守 卫 险 些 觉 察 ， 幸 亏 你 运 气 不 差 ， 抢 在 他 们 合 围 之 前 脱 了 身 。`r`nmno_wb_luck_sneak_go|继 续`r`nmenu_wb_luck_wait|祈 运 仪 式 已 开 始`r`nmno_wb_luck_wait_go|继 续"
            Save-TextWithBom $gm ($txt.TrimEnd() + "`r`n" + $entries + "`r`n")
        }
    }
    Write-ModpackLog '[luck] 夜袭免战（城镇/村庄，每次入口判定）+ 伴侣供奉（宴会评估/扣 400 份，六级恢复，最高 70%）'
}

# ---------- 运气：供奉完成计时（挂在学习技能触发器上，不新增触发器行，旧档可读） ----------
function Apply-LuckTrigger([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $vPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $endIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_luck_offering_end') { $endIdx = $i; break } }
    if ($endIdx -lt 0) { throw 'variables.txt 里没有 g_luck_offering_end（先应用 luck）' }
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $nSc = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$nSc)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    $tickIdx = -1
    for ($i = 0; $i -lt $nSc; $i++) {
        $nm = ($scLines[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm -eq 'wb_luck_offering_tick') { $tickIdx = $i; break }
    }
    if ($tickIdx -lt 0) { throw 'scripts.txt 里没有 wb_luck_offering_tick' }
    $endVar = [string]([int64]144115188075855872 + [int64]$endIdx)
    $msgIdxL = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_wb_msg_type') { $msgIdxL = $i; break } }
    if ($msgIdxL -lt 0) { throw 'variables.txt 里没有 g_wb_msg_type（先选 claim 功能）' }
    $msgTagL = [string]([int64]144115188075855872 + [int64]$msgIdxL)
    $msgArgIdxL = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_wb_msg_arg1') { $msgArgIdxL = $i; break } }
    $msgArgTagL = [string]([int64]144115188075855872 + [int64]$msgArgIdxL)
    $skillIdxL = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'g_learn_skill_id') { $skillIdxL = $i; break } }
    $skillTagL = [string]([int64]144115188075855872 + [int64]$skillIdxL)
    $tickTag = [string]($TAG_SCRIPT + $tickIdx)
    $decayIdx = -1
    for ($i = 0; $i -lt $nSc; $i++) {
        $nm = ($scLines[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm -eq 'wb_luck_decay_tick') { $decayIdx = $i; break }
    }
    if ($decayIdx -lt 0) { throw 'scripts.txt 里没有 wb_luck_decay_tick' }
    $decayTag = [string]($TAG_SCRIPT + $decayIdx)
    $tPath = Join-Path $modDir 'simple_triggers.txt'
    $tLines = @([IO.File]::ReadAllText($tPath, $enc) -split "\r?\n")
    $ti = -1
    for ($i = 0; $i -lt $tLines.Count; $i++) {
        if ($tLines[$i] -match '^1\.000000\s+7\s+4 0 32 2 (\d+) 0 ') { $ti = $i; break }
    }
    if ($ti -ge 0) {
        # 选了「训练与学习」：供奉计时 + 运气衰减合并进学习技能的每小时触发器（不新增行）
        $lv = [regex]::Match($tLines[$ti], '^1\.000000\s+7\s+4 0 32 2 (\d+) 0 ').Groups[1].Value
        $newLine = '1.000000  ' + [string](15) + ' 4 0 32 2 ' + $lv + ' 0 2270 1 1224979098644774912 30 2 1224979098644774912 ' + $lv + ' 2133 2 ' + $msgArgTagL + ' ' + $skillTagL + ' 2133 2 ' + $msgTagL + ' 4 2133 2 ' + $lv + ' 0 3 0 4 0 32 2 ' + $endVar + ' 0 2270 1 1224979098644774912 30 2 1224979098644774912 ' + $endVar + ' 1 1 ' + $tickTag + ' 3 0 1 1 ' + $decayTag
        $tLines[$ti] = $newLine
        $luckTrigNote = '[luck] 供奉完成计时挂到学习技能触发器 + 空触发器补到 115（兼容旧档）'
    } else {
        # 没选「训练与学习」：运气单独一条每小时触发器（插到前部，WSE2 不执行末尾行）
        $cntAll = 0
        if (-not [int]::TryParse($tLines[1].Trim(), [ref]$cntAll)) { throw 'simple_triggers.txt 第 2 行不是数量' }
        $luckLine = '1.000000  ' + [string](7) + ' 4 0 32 2 ' + $endVar + ' 0 2270 1 1224979098644774912 30 2 1224979098644774912 ' + $endVar + ' 1 1 ' + $tickTag + ' 3 0 1 1 ' + $decayTag
        $tLines[1] = [string]($cntAll + 1)
        $tLines = @($tLines[0], $tLines[1], $luckLine) + @($tLines[2..($tLines.Count - 1)])
        $luckTrigNote = '[luck] 供奉完成计时用独立每小时触发器（本次未生成「训练与学习」）'
    }
    while ($tLines.Count -ge 1 -and $tLines[$tLines.Count - 1] -eq '') { $tLines = @($tLines[0..($tLines.Count - 2)]) }
    # 存档兼容：曾经用过 115 个触发器的模块存档，这里补空占位补到 115（声明与行数必须一致，按差额补）
    $cntNow = 0
    if ([int]::TryParse($tLines[1].Trim(), [ref]$cntNow) -and $cntNow -lt 115) {
        $needRows = 115 - $cntNow
        $tLines[1] = '115'
        for ($k = 0; $k -lt $needRows; $k++) { $tLines += '0.000000  0 ' }
    }
    [IO.File]::WriteAllText($tPath, ((($tLines) -join "`r`n") + "`r`n"), $enc)
    Write-ModpackLog $luckTrigNote
}

# ---------- 战败惩罚（同伴部分留队 / 背包物品缴获 / 被俘时长随等级） ----------
function Apply-Defeat([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    function Get-DefeatParam([string]$name, [int]$default) {
        foreach ($line in ($md -split "\r?\n")) {
            if ($line -match ('^\|\s*' + [regex]::Escape($name) + '\s*\|\s*(\d+)\s*\|')) { return [int]$Matches[1] }
        }
        return $default
    }
    $leavePct  = Get-DefeatParam '同伴离队概率（%）' 25
    $lootPct   = Get-DefeatParam '背包物品缴获率（%）' 50
    $lootEquip = Get-DefeatParam '装备缴获' 0
    $levelDiv  = Get-DefeatParam '关押时长等级除数' 3
    $hoursMin  = Get-DefeatParam '关押时长下限（小时）' 4
    if ($leavePct -lt 0)   { $leavePct = 0 }
    if ($leavePct -gt 100) { $leavePct = 100 }
    if ($lootPct -lt 0 -or $lootPct -gt 100) { throw "背包物品缴获率超出 0-100：$lootPct" }
    if ($lootEquip -ne 0 -and $lootEquip -ne 1) { throw "装备缴获只能是 0（不缴）或 1（按背包概率缴）：$lootEquip" }
    if ($hoursMin -lt 1) { $hoursMin = 1 }

    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $R_iSlot = '1224979098644774914'   # :i_slot
    $R_item  = '1224979098644774915'   # :item_id
    $R_rand  = '1224979098644774917'   # :randomness

    # ---- 1) 同伴：random(0,100) < leavePct 才离队（离队者必被关）；中立势力打败全留 ----
    $nameIdx = -1
    for ($i = 0; $i -lt $scLines.Count - 1; $i++) { if ($scLines[$i] -like 'party_remove_all_companions *') { $nameIdx = $i; break } }
    if ($nameIdx -lt 0) { throw 'scripts.txt 里找不到脚本 party_remove_all_companions' }
    $toks = @($scLines[$nameIdx + 1].Trim() -split '\s+')
    if ($toks.Count -ne 262) { throw "party_remove_all_companions 体行 token 数 $($toks.Count)（期望 262），Native 结构变了，别硬改" }
    if ($toks[45] -ne '2136' -or $toks[46] -ne '3' -or $toks[47] -ne '1224979098644774917' -or $toks[48] -ne '0' -or $toks[49] -ne '2') { throw 'party_remove_all_companions 的离队判定结构变了（期望 store_random_in_range r17 0 2）' }
    $toks[49] = '100'
    if ($toks[50] -ne '2147483679' -or $toks[51] -ne '2' -or $toks[52] -ne '1224979098644774917' -or $toks[53] -ne '0') { throw 'party_remove_all_companions 的离队比较结构变了（期望 neq r17 0）' }
    $toks[50] = '2147483678'   # neq → lt：random(0,100) < leavePct 才离队
    $toks[53] = [string]$leavePct
    if ($toks[115] -ne '0' -or $toks[116] -ne '4') { throw "party_remove_all_companions 内层关押判定 token 是 $($toks[115]) $($toks[116])（期望 0 4），结构变了" }
    $toks[115] = '1'; $toks[116] = '2'
    # 中立势力（盗贼/逃兵，非王国）打败：在离队判定后立刻校验击败方阵营，不在王国区间就跳过整个离队分支 → 同伴全留
    $fragFaction = @('2204', '2', '1224979098644774918', '144115188075856188', '33', '3', '1224979098644774918', '432345564227567630', '432345564227567637')
    $toks = @($toks[0..53]) + $fragFaction + @($toks[54..($toks.Count - 1)])
    if ($toks[0] -ne '67') { throw "party_remove_all_companions 语句数 token 是 $($toks[0])（期望 67）" }
    $toks[0] = '69'
    $scLines[$nameIdx + 1] = ' ' + ($toks -join ' ')
    Write-ModpackLog "[defeat] 同伴离队概率 = $leavePct%（离队即被关；被中立盗贼/逃兵打败全部留队）"

    # ---- 2) 物品：默认只处理背包（i_slot>=10 跳过装备栏），背包每件 lootPct% 被缴；书一律不缴 ----
    $itemMap = Get-ItemIdMap $modDir
    foreach ($n in @('itm_book_tactics', 'itm_spice')) {
        if (-not $itemMap.ContainsKey($n)) { throw "item_kinds1.txt 里找不到 $n（书类边界）" }
    }
    $booksBegin = [string]([int64]288230376151711744 + [int64]$itemMap['itm_book_tactics'])
    $booksEnd   = [string]([int64]288230376151711744 + [int64]$itemMap['itm_spice'])
    $nameIdx = -1
    for ($i = 0; $i -lt $scLines.Count - 1; $i++) { if ($scLines[$i] -like 'loot_player_items *') { $nameIdx = $i; break } }
    if ($nameIdx -lt 0) { throw 'scripts.txt 里找不到脚本 loot_player_items' }
    $toks = @($scLines[$nameIdx + 1].Trim() -split '\s+')
    if ($toks.Count -ne 186) { throw "loot_player_items 体行 token 数 $($toks.Count)（期望 186），Native 结构变了，别硬改" }
    if ($toks[0] -ne '46') { throw "loot_player_items 语句数 token 是 $($toks[0])（期望 46）" }
    if ($toks[19] -ne '30' -or $toks[22] -ne '0') { throw 'loot_player_items 的 item_id>=0 判断结构变了' }
    if ($toks[23] -ne '1542') { throw 'loot_player_items 的 modifier 读取结构变了' }
    if ($toks[28] -ne '4' -or $toks[29] -ne '0') { throw 'loot_player_items 的 try_begin 结构变了' }
    if ($toks[38] -ne '20' -or $toks[57] -ne '15' -or $toks[73] -ne '5' -or $toks[93] -ne '5') { throw 'loot_player_items 的类别概率结构变了' }
    $toks[38] = [string]$lootPct; $toks[57] = [string]$lootPct; $toks[73] = [string]$lootPct; $toks[93] = [string]$lootPct
    # 书分支：插在第一个 try_begin 之后（先判书，命中则不缴）
    $bookFrag = @('33', '3', $R_item, $booksBegin, $booksEnd, '2133', '2', $R_rand, '0', '5', '0')
    $toks = @($toks[0..29]) + $bookFrag + @($toks[30..($toks.Count - 1)])
    # 默认概率：插在 modifier 读取之后、try_begin 之前（食物/箭等未分类物品也按该概率）
    $defFrag = @('2133', '2', $R_rand, [string]$lootPct)
    $toks = @($toks[0..27]) + $defFrag + @($toks[28..($toks.Count - 1)])
    $stmtAdd = 4
    if ($lootEquip -eq 0) {
        # 只处理背包：i_slot >= 10（0-9 是装备栏，不缴）
        $geFrag = @('30', '2', $R_iSlot, '10')
        $toks = @($toks[0..22]) + $geFrag + @($toks[23..($toks.Count - 1)])
        $stmtAdd++
    }
    $toks[0] = [string](46 + $stmtAdd)
    $scLines[$nameIdx + 1] = ' ' + ($toks -join ' ')
    if ($lootEquip -eq 0) {
        Write-ModpackLog "[defeat] 背包物品缴获率 = $lootPct%（书不缴；身上装备不缴）"
    } else {
        Write-ModpackLog "[defeat] 物品缴获率 = $lootPct%（含装备栏；书不缴）"
    }
    [IO.File]::WriteAllText($scPath, ($scLines -join "`r`n"), $enc)

    # ---- 3) 被俘关押时长：小时数 - 玩家等级/levelDiv（下限 hoursMin）；levelDiv=0 保持原版 ----
    if ($levelDiv -le 0) {
        Write-ModpackLog '[defeat] 关押时长等级除数 = 0，保持原版时长'
        return
    }
    $mPath = Join-Path $modDir 'menus.txt'
    $mLines = [IO.File]::ReadAllText($mPath, $enc) -split "\r?\n"
    $mApplied = 0
    for ($i = 0; $i -lt $mLines.Count; $i++) {
        $line = $mLines[$i]

        # 野外被俘：random(18,30)，选项语句数 7 → 11
        if ($line.Contains('2136 3 1224979098644774912 18 30 ')) {
            $frag = "2171 2 1224979098644774913 360287970189639680 2123 3 1224979098644774913 1224979098644774913 $levelDiv 2106 2 1224979098644774912 1224979098644774913 2111 2 1224979098644774912 $hoursMin"
            if (-not $line.Contains('mno_continue  0  Continue...  7 ')) { throw '野外被俘菜单：选项语句数定位失败（期望 7）' }
            $line = $line.Replace('2136 3 1224979098644774912 18 30 ', '2136 3 1224979098644774912 18 30 ' + $frag + ' ')
            $line = $line.Replace('mno_continue  0  Continue...  7 ', 'mno_continue  0  Continue...  11 ')
            $mApplied++
            $mLines[$i] = $line
            continue
        }
        # 城堡 / 营救领主被俘：random(16,22)，选项语句数 6 → 10（两行相同）
        if ($line.Contains('2136 3 1224979098644774912 16 22 ')) {
            $frag = "2171 2 1224979098644774913 360287970189639680 2123 3 1224979098644774913 1224979098644774913 $levelDiv 2106 2 1224979098644774912 1224979098644774913 2111 2 1224979098644774912 $hoursMin"
            if (-not $line.Contains('mno_continue  0  Continue...  6 ')) { throw '城堡被俘菜单：选项语句数定位失败（期望 6）' }
            $line = $line.Replace('2136 3 1224979098644774912 16 22 ', '2136 3 1224979098644774912 16 22 ' + $frag + ' ')
            $line = $line.Replace('mno_continue  0  Continue...  6 ', 'mno_continue  0  Continue...  10 ')
            $mApplied++
            $mLines[$i] = $line
            continue
        }
        # 拒绝赎金继续关：random(16,22)，语句数 5 → 9（全局变量 g_...）
        if ($line.Contains('2136 3 72057594037927944 16 22 ')) {
            $frag = "2171 2 1224979098644774912 360287970189639680 2123 3 1224979098644774912 1224979098644774912 $levelDiv 2106 2 72057594037927944 1224979098644774912 2111 2 72057594037927944 $hoursMin"
            if (-not $line.Contains('Refuse_him,_wait_for_something_better.  5 ')) { throw '拒绝赎金菜单：选项语句数定位失败（期望 5）' }
            $line = $line.Replace('2136 3 72057594037927944 16 22 ', '2136 3 72057594037927944 16 22 ' + $frag + ' ')
            $line = $line.Replace('Refuse_him,_wait_for_something_better.  5 ', 'Refuse_him,_wait_for_something_better.  9 ')
            $mApplied++
            $mLines[$i] = $line
            continue
        }
        # 地牢等待（castle_remain 菜单定义行）：random(16,22)，语句数 10 → 14
        if ($line.Contains('2136 3 1224979098644774913 16 22 ')) {
            $frag = "2171 2 1224979098644774914 360287970189639680 2123 3 1224979098644774914 1224979098644774914 $levelDiv 2106 2 1224979098644774913 1224979098644774914 2111 2 1224979098644774913 $hoursMin"
            if (-not $line.Contains('none 10 1506 2')) { throw '地牢等待菜单：语句数定位失败（期望 none 10）' }
            $line = $line.Replace('2136 3 1224979098644774913 16 22 ', '2136 3 1224979098644774913 16 22 ' + $frag + ' ')
            $line = $line.Replace('none 10 1506 2', 'none 14 1506 2')
            $mApplied++
            $mLines[$i] = $line
            continue
        }
    }
    if ($mApplied -ne 5) { throw "被俘关押时长：改了 $mApplied 处（期望 5：野外/城堡/营救/拒绝赎金/地牢等待），中止" }
    [IO.File]::WriteAllText($mPath, ($mLines -join "`r`n"), $enc)
    Write-ModpackLog "[defeat] 被俘关押时长：小时 - 等级/$levelDiv，下限 $hoursMin（改了 $mApplied 处）"
}

# ---------- 消息变量（Native 写、Lua 读） ----------
function Apply-MsgVars([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $vPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $names = @('g_wb_msg_type', 'g_wb_msg_count', 'g_wb_msg_arg1', 'g_wb_msg_arg2')
    foreach ($vn in $names) {
        $found = -1
        for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq $vn) { $found = $i; break } }
        if ($found -lt 0) { $varList += $vn }
    }
    [IO.File]::WriteAllText($vPath, (($varList -join "`r`n") + "`r`n"), $enc)
    Write-ModpackLog '[msg] 消息变量就绪（g_wb_msg_type/center/lord/count/arg1/arg2）'
}

# ---------- 换国后国王关系下限（防刚加入就被反复流放） ----------
function Apply-FactionJoin([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $nameIdx = -1
    for ($i = 2; $i -lt $scLines.Count - 1; $i += 2) {
        if ($scLines[$i] -like 'change_troop_faction *') { $nameIdx = $i; break }
    }
    if ($nameIdx -lt 0) { throw '找不到 change_troop_faction 脚本' }
    $body = $scLines[$nameIdx + 1].Trim()
    if ($body.Contains('2121 3 1224979098644774914 1224979098644774914 1224979098644774913')) {
        Write-ModpackLog '[factionjoin] 已应用过，跳过'
        return
    }
    $t = @($body -split '\s+' | Where-Object { $_ -ne '' })
    # 定位原版「新国王关系 +5」：call_script(troop_change_relation_with_troop, liege, troop, 5)
    $pos = -1
    for ($j = 0; $j -lt $t.Count - 5; $j++) {
        if ($t[$j] -eq '1' -and $t[$j + 1] -eq '4' -and $t[$j + 2] -eq '936748722493063669' -and $t[$j + 5] -eq '5') { $pos = $j; break }
    }
    if ($pos -lt 0) { throw 'change_troop_faction 里找不到「新国王关系 +5」调用（版本可能变了）' }
    $liege = $t[$pos + 3]
    $troop = $t[$pos + 4]
    # r1 = 当前关系，r2 = 目标值；目标 = max(关系+5, 0)，增量 = 目标 - 关系
    $ins = @(
        '1', '3', '936748722493063670', $liege, $troop,
        '2133', '2', '1224979098644774913', '72057594037927936',
        '2120', '3', '1224979098644774914', '1224979098644774913', '5',
        '4', '0',
        '2147483680', '2', '1224979098644774914', '0',
        '2133', '2', '1224979098644774914', '0',
        '3', '0',
        '2121', '3', '1224979098644774914', '1224979098644774914', '1224979098644774913'
    )
    $call = @('1', '4', '936748722493063669', $liege, $troop, '1224979098644774914')
    $new = @($t[0..($pos - 1)]) + $ins + $call + @($t[($pos + 6)..($t.Count - 1)])
    $new[0] = [string]([int]$new[0] + 8)
    $scLines[$nameIdx + 1] = ' ' + ($new -join ' ')
    [IO.File]::WriteAllText($scPath, ($scLines -join "`r`n"), $enc)
    Write-ModpackLog '[factionjoin] 换国后与国王关系最低 0（原 +5 保留）'
}

# ---------- 领土交换（大臣处交换国内两处领地） ----------
function Apply-Swap([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\swap'
    $enc = [Text.Encoding]::GetEncoding(28591)

    # 参数（params.md，两列表）
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    $penTown = 10
    $penCastle = 5
    foreach ($ln in ($md -split "\r?\n")) {
        if ($ln -match '^\|\s*城换村关系惩罚\s*\|\s*(\d+)\s*\|') { $penTown = [int]$Matches[1] }
        if ($ln -match '^\|\s*堡换村关系惩罚\s*\|\s*(\d+)\s*\|') { $penCastle = [int]$Matches[1] }
    }

    # 变量
    $vPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    foreach ($vn in @('g_wb_swap_a', 'g_wb_swap_b', 'g_wb_swap_castle')) {
        if (-not ($varList -contains $vn)) { $varList += $vn }
    }
    [IO.File]::WriteAllText($vPath, (($varList -join "`r`n") + "`r`n"), $enc)
    $TAG_VAR = [int64]144115188075855872
    $varA = [string]($TAG_VAR + [array]::IndexOf($varList, 'g_wb_swap_a'))
    $varB = [string]($TAG_VAR + [array]::IndexOf($varList, 'g_wb_swap_b'))
    $varCastle = [string]($TAG_VAR + [array]::IndexOf($varList, 'g_wb_swap_castle'))
    $varType = [string]($TAG_VAR + [array]::IndexOf($varList, 'g_wb_msg_type'))
    $varArg1 = [string]($TAG_VAR + [array]::IndexOf($varList, 'g_wb_msg_arg1'))
    if ($varType -eq '' -or $varArg1 -eq '') { throw '缺少 g_wb_msg_type / g_wb_msg_arg1（先跑 Apply-MsgVars）' }

    # 脚本
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是数量' }
    $idxOf = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $nm = ($scLines[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm) { $idxOf[$nm] = $i }
    }
    foreach ($need in @('change_player_relation_with_troop', 'update_center_notes', 'update_faction_notes')) {
        if (-not $idxOf.ContainsKey($need)) { throw "缺少脚本 $need" }
    }
    $chgTag = [string]($TAG_SCRIPT + $idxOf['change_player_relation_with_troop'])
    $updCTag = [string]($TAG_SCRIPT + $idxOf['update_center_notes'])
    $updFTag = [string]($TAG_SCRIPT + $idxOf['update_faction_notes'])
    $swapTag = [string]($TAG_SCRIPT + $n)

    $body = @((Read-TextNoBom (Join-Path $pd 'scripts.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($body.Count -ne 2) { throw "swap/scripts.txt 应为 2 行，实际 $($body.Count)" }
    if (($body -join "`n") -match '\{\{') {
        $body[1] = $body[1].Replace('{{CHG}}', $chgTag).Replace('{{UPD_CENTER}}', $updCTag).Replace('{{UPD_FACTION}}', $updFTag).Replace('{{WB_MSG_TYPE}}', $varType).Replace('{{WB_MSG_ARG1}}', $varArg1).Replace('{{PENALTY_TOWN}}', [string]$penTown).Replace('{{PENALTY_CASTLE}}', [string]$penCastle)
    }
    while ($scLines.Count -ge 1 -and $scLines[$scLines.Count - 1] -eq '') { $scLines = $scLines[0..($scLines.Count - 2)] }
    $scLines[1] = [string]($n + 1)
    $scLines += $body[0]
    $scLines += $body[1]
    [IO.File]::WriteAllText($scPath, (($scLines -join "`r`n") + "`r`n"), $enc)

    # 对话
    $convPath = Join-Path $modDir 'conversation.txt'
    $convLines = [IO.File]::ReadAllText($convPath, $enc) -split "\r?\n"
    $cCount = 0
    if (-not [int]::TryParse($convLines[1].Trim(), [ref]$cCount)) { throw 'conversation.txt 第 2 行不是对话数量' }
    if (($convLines -join "`n") -match 'wb_swap') { throw '这个模块里已经有领土交换功能了' }
    $dAdd = @((Read-TextNoBom (Join-Path $pd 'dialogs_add.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($dAdd.Count -ne 13) { throw "领土交换对话补丁应 13 行，实际 $($dAdd.Count)" }
    $dAdd = $dAdd -replace '\{\{VAR_A\}\}', $varA -replace '\{\{VAR_B\}\}', $varB -replace '\{\{VAR_CASTLE\}\}', $varCastle -replace '\{\{SWAP\}\}', $swapTag -replace '\{\{UNASSIGNED\}\}', '216172782113786968'
    if (($dAdd -join "`n") -match '\{\{') { throw '领土交换对话还有未替换的占位符' }
    $convLines[1] = [string]($cCount + $dAdd.Count)
    $convBody = @($convLines | Select-Object -SkipLast 1)
    $insertAt = 8
    if ($convBody.Count -le $insertAt) { throw 'conversation.txt 行数不足，无法前插' }
    $convBody = @($convBody[0..($insertAt - 1)]) + $dAdd + @($convBody[$insertAt..($convBody.Count - 1)])
    [IO.File]::WriteAllText($convPath, ((($convBody -join "`r`n")) + "`r`n"), $enc)

    # 中文
    $dl = Join-Path $modDir 'languages\cns\dialogs.csv'
    if (Test-Path $dl) {
        $txt = Read-TextNoBom $dl
        $lines = @($txt -split "\r?\n" | Where-Object { $_ -notmatch 'wb_swap' })
        $entries = (Read-TextNoBom (Join-Path $pd 'dialogs_lang.csv')).TrimEnd()
        Save-TextWithBom $dl ((@($lines) -join "`r`n").TrimEnd() + "`r`n" + $entries + "`r`n")
    }
    Write-ModpackLog ("[swap] 领土交换：大臣对话入口；城 -{0}、堡 -{1}（只扣失去高价值领地的领主）" -f $penTown, $penCastle)
}

# ---------- 税收无效损失豁免（玩家村庄不计入） ----------
function Apply-TaxExempt([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $p = Join-Path $modDir 'presentations.txt'
    $lines = [IO.File]::ReadAllText($p, $enc) -split "\r?\n"
    $nameIdx = -1
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i] -like 'prsnt_budget_report *') { $nameIdx = $i; break }
    }
    if ($nameIdx -lt 0) { throw 'presentations.txt 里找不到 prsnt_budget_report' }
    $t = @($lines[$nameIdx + 1].Trim() -split '\s+' | Where-Object { $_ -ne '' })
    # 定位原版「拥有中心 → num_lines+1、num_owned+1」序列
    $pos = -1
    $center = ''
    $owned = ''
    for ($j = 0; $j -lt $t.Count - 12; $j++) {
        if ($t[$j] -eq '541' -and $t[$j + 1] -eq '3' -and $t[$j + 3] -eq '7' -and $t[$j + 4] -eq '360287970189639680' -and $t[$j + 5] -eq '2105' -and $t[$j + 6] -eq '2' -and $t[$j + 8] -eq '1' -and $t[$j + 9] -eq '2105' -and $t[$j + 10] -eq '2' -and $t[$j + 12] -eq '1' -and $t[$j + 7] -ne $t[$j + 11]) {
            $pos = $j
            $center = $t[$j + 2]
            $owned = $t[$j + 11]
            break
        }
    }
    if ($pos -lt 0) { throw '预算报告里找不到「拥有中心 → 计数 +1、城镇 +1」序列（版本可能变了）' }
    # 第一次 val_add 改为「非村庄才计数」：try_begin; if type == village 跳过; else_try 计数; try_end
    $ins = @('4', '0', '541', '3', $center, '0', '4', '5', '0', '2105', '2', $owned, '1', '3', '0')
    $new = @($t[0..($pos + 8)]) + $ins + @($t[($pos + 13)..($t.Count - 1)])
    $new[1] = [string]([int]$new[1] + 4)
    $lines[$nameIdx + 1] = ($new -join ' ')
    [IO.File]::WriteAllText($p, ($lines -join "`r`n"), $enc)
    Write-ModpackLog '[taxexempt] 预算报告：玩家村庄不计入税收无效损失（村庄收入照常）'
}

# ---------- 无地好人性格领主惩罚（goodnatured / upstanding 也按周期掉关系） ----------
# 原版 0.5h 触发器（每轮处理 1 个领主，约 60h 轮到同一人）只惩罚 lrep 1~5：
# 好战(1) -2、暴躁/自大/狡猾/放荡(2~5) -4；善良(6)、正直(7) 完全免罚。
# 这里给 6/7 补一个 else_try 分支，按 params.md 里的「好人性格无地关系惩罚」扣关系。
function Apply-NoFiefGood([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $p = Join-Path $modDir 'simple_triggers.txt'
    $rows = [IO.File]::ReadAllText($p, $enc) -split "\r?\n"
    $pen = 1
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    foreach ($ln in ($md -split "\r?\n")) {
        if ($ln -match '^\|\s*好人性格无地关系惩罚\s*\|\s*(\d+)\s*\|') { $pen = [int]$Matches[1] }
    }
    if ($pen -le 0) {
        Write-ModpackLog '[nofiefgood] 参数 ≤ 0，保持原版（好人性格无地免罚）'
        return
    }
    $hit = -1
    for ($i = 2; $i -lt $rows.Count; $i++) {
        if ($rows[$i] -match ' 4 0 31 2 1224979098644774913 -1 2173 2 1224979098644774915 1224979098644774912 522 3 1224979098644774916 1224979098644774915 11 520 3 1224979098644774917 1224979098644774912 52 ') { $hit = $i; break }
    }
    if ($hit -lt 0) { throw 'simple_triggers.txt 里找不到无地惩罚触发器（版本可能变了）' }
    $t = @($rows[$hit].Trim() -split '\s+' | Where-Object { $_ -ne '' })
    if (($t -join ' ') -match '1073741855 2 1224979098644774917 6') {
        Write-ModpackLog '[nofiefgood] 已应用过，跳过'
        return
    }
    # 定位 lrep_martial 分支的 val_add（最后一处 `2105 2 $total_no_fief_changes -2`）
    $pos = -1
    for ($j = $t.Count - 4; $j -ge 0; $j--) {
        if ($t[$j] -eq '2105' -and $t[$j + 1] -eq '2' -and $t[$j + 2] -eq '144115188075857006' -and $t[$j + 3] -eq '-2') { $pos = $j; break }
    }
    if ($pos -lt 0) { throw '无地惩罚触发器里找不到 lrep_martial 分支（版本可能变了）' }
    if ($pos + 6 -ge $t.Count) { throw '无地惩罚触发器结构异常（martial 分支后没有收尾语句）' }
    # else_try + (this_or_next|eq 6) + (eq 7) + call_script + val_add = 5 条语句
    $ins = @(
        '5', '0',
        '1073741855', '2', '1224979098644774917', '6',
        '31', '2', '1224979098644774917', '7',
        '1', '4', '936748722493063669', '1224979098644774912', '1224979098644774916', ('-' + $pen),
        '2105', '2', '144115188075857006', ('-' + $pen)
    )
    $new = @($t[0..($pos + 3)]) + $ins + @($t[($pos + 4)..($t.Count - 1)])
    # simple_triggers 行格式：<间隔小时> <语句数> <tokens...>，语句数是第 2 个 token
    $new[1] = [string]([int]$new[1] + 5)
    $rows[$hit] = ' ' + ($new -join ' ')
    [IO.File]::WriteAllText($p, ($rows -join "`r`n"), $enc)
    Write-ModpackLog "[nofiefgood] 无地的好人性格领主（善良/正直）每轮与国王关系 -$pen"
}

# ---------- 历练（分封的原同伴在本国成长；对话归队并回收领地） ----------
# 原版 48h 触发器对玩家王国领主只给基础 31%，难度倍率段被 neq $players_kingdom 跳过。
# 本功能单独加一条 48h 触发器：玩家王国的原同伴领主（trp_npc1..trp_npc16）按与敌国相同的
# 难度概率/倍率获得 add_xp_to_troop 个人经验，等价于「不用出国也能历练」。
function Apply-Drill([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\drill'
    $enc = [Text.Encoding]::GetEncoding(28591)

    # 变量：g_wb_drill_pending（待归队）、g_wb_outland_faction（派出目标国）、g_wb_outland_last（调试去重）
    $vPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    foreach ($vn in @('g_wb_drill_pending', 'g_wb_outland_faction', 'g_wb_outland_last')) {
        if (-not ($varList -contains $vn)) { $varList += $vn }
    }
    [IO.File]::WriteAllText($vPath, (($varList -join "`r`n") + "`r`n"), $enc)
    $idx = @{}
    for ($i = 0; $i -lt $varList.Count; $i++) { $idx[$varList[$i].Trim()] = $i }
    foreach ($need in @('players_kingdom', 'g_leave_encounter', 'g_wb_drill_pending', 'g_wb_outland_faction', 'g_wb_outland_last', 'g_wb_msg_type', 'g_wb_msg_arg1', 'g_wb_msg_arg2')) {
        if (-not $idx.ContainsKey($need)) { throw "variables.txt 里没有 $need（版本可能变了）" }
    }
    $varPK = [string]([int64]144115188075855872 + $idx['players_kingdom'])
    $varLeave = [string]([int64]144115188075855872 + $idx['g_leave_encounter'])
    $varPending = [string]([int64]144115188075855872 + $idx['g_wb_drill_pending'])
    $varOutland = [string]([int64]144115188075855872 + $idx['g_wb_outland_faction'])
    $varOutLast = [string]([int64]144115188075855872 + $idx['g_wb_outland_last'])
    $varMsgT = [string]([int64]144115188075855872 + $idx['g_wb_msg_type'])
    $varMsgA = [string]([int64]144115188075855872 + $idx['g_wb_msg_arg1'])
    $varMsgA2 = [string]([int64]144115188075855872 + $idx['g_wb_msg_arg2'])

    # 对话状态：lord_talk（归队入口）、member_question_2（同伴"我想问你些事"之后的选项）
    $dsPath = Join-Path $modDir 'dialog_states.txt'
    if (-not (Test-Path $dsPath)) { throw '模块里缺 dialog_states.txt' }
    $ds = @([IO.File]::ReadAllText($dsPath, $enc) -split "\r?\n")
    $lordTalk = -1; $memberQ2 = -1
    for ($i = 0; $i -lt $ds.Count; $i++) {
        if ($ds[$i].Trim() -eq 'lord_talk') { $lordTalk = $i }
        if ($ds[$i].Trim() -eq 'member_question_2') { $memberQ2 = $i }
    }
    if ($lordTalk -lt 0) { throw 'dialog_states.txt 里找不到 lord_talk' }
    if ($memberQ2 -lt 0) { throw 'dialog_states.txt 里找不到 member_question_2' }

    # 脚本索引：换国关系、生成领主部队
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是数量' }
    $idxOf = @{}
    for ($i = 0; $i -lt $n; $i++) {
        $nm = ($scLines[2 + 2 * $i].Trim() -split '\s+')[0]
        if ($nm) { $idxOf[$nm] = $i }
    }
    foreach ($need in @('troop_change_relation_with_troop', 'troop_get_relation_with_troop', 'create_kingdom_hero_party')) {
        if (-not $idxOf.ContainsKey($need)) { throw "缺少脚本 $need" }
    }
    $relTag = [string]($TAG_SCRIPT + $idxOf['troop_change_relation_with_troop'])
    $relGetTag = [string]($TAG_SCRIPT + $idxOf['troop_get_relation_with_troop'])
    $createTag = [string]($TAG_SCRIPT + $idxOf['create_kingdom_hero_party'])

    # 脚本：追加 5 个（can_return / return / finish / outland_send / outland_probe）
    $body = @((Read-TextNoBom (Join-Path $pd 'scripts.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($body.Count -ne 10) { throw "drill/scripts.txt 应为 10 行（5 个脚本），实际 $($body.Count)" }
    $canTag = [string]($TAG_SCRIPT + $n)
    $retTag = [string]($TAG_SCRIPT + $n + 1)
    $finTag = [string]($TAG_SCRIPT + $n + 2)
    $sendTag = [string]($TAG_SCRIPT + $n + 3)
    $probeTag = [string]($TAG_SCRIPT + $n + 4)
    $body = $body -replace '\{\{PLAYERS_KINGDOM\}\}', $varPK -replace '\{\{DRILL_PENDING\}\}', $varPending -replace '\{\{DRILL_RETURN\}\}', $retTag -replace '\{\{WB_MSG_TYPE\}\}', $varMsgT -replace '\{\{WB_MSG_ARG1\}\}', $varMsgA -replace '\{\{WB_MSG_ARG2\}\}', $varMsgA2 -replace '\{\{REL_CHG\}\}', $relTag -replace '\{\{CREATE_HERO\}\}', $createTag -replace '\{\{OUT_LAST\}\}', $varOutLast
    if (($body -join "`n") -match '\{\{') { throw '历练脚本还有未替换的占位符' }
    while ($scLines.Count -ge 1 -and $scLines[$scLines.Count - 1] -eq '') { $scLines = $scLines[0..($scLines.Count - 2)] }
    $scLines[1] = [string]($n + 5)
    $scLines += $body
    [IO.File]::WriteAllText($scPath, (($scLines -join "`r`n") + "`r`n"), $enc)

    # 对话：插到 conversation.txt 前部
    $convPath = Join-Path $modDir 'conversation.txt'
    $convLines = [IO.File]::ReadAllText($convPath, $enc) -split "\r?\n"
    $cCount = 0
    if (-not [int]::TryParse($convLines[1].Trim(), [ref]$cCount)) { throw 'conversation.txt 第 2 行不是对话数量' }
    if (($convLines -join "`n") -match 'wb_(drill|outland)') { throw '这个模块里已经有历练功能了' }
    $dAdd = @((Read-TextNoBom (Join-Path $pd 'dialogs_add.txt')) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($dAdd.Count -ne 12) { throw "历练对话补丁应 12 行，实际 $($dAdd.Count)" }
    $dAdd = $dAdd -replace '\{\{LORD_TALK\}\}', [string]$lordTalk -replace '\{\{MEMBER_QUESTION2\}\}', [string]$memberQ2 -replace '\{\{DRILL_CAN\}\}', $canTag -replace '\{\{DRILL_RETURN\}\}', $retTag -replace '\{\{DRILL_PENDING\}\}', $varPending -replace '\{\{LEAVE_ENC\}\}', $varLeave -replace '\{\{REL_GET\}\}', $relGetTag -replace '\{\{SEND\}\}', $sendTag -replace '\{\{PROBE\}\}', $probeTag -replace '\{\{OUT_FACTION\}\}', $varOutland
    if (($dAdd -join "`n") -match '\{\{') { throw '历练对话还有未替换的占位符' }
    $convLines[1] = [string]($cCount + $dAdd.Count)
    $convBody = @($convLines | Select-Object -SkipLast 1)
    $insertAt = 8
    if ($convBody.Count -le $insertAt) { throw 'conversation.txt 行数不足，无法前插' }
    $convBody = @($convBody[0..($insertAt - 1)]) + $dAdd + @($convBody[$insertAt..($convBody.Count - 1)])
    [IO.File]::WriteAllText($convPath, ((($convBody -join "`r`n")) + "`r`n"), $enc)

    # 中文对话
    $dl = Join-Path $modDir 'languages\cns\dialogs.csv'
    if (Test-Path $dl) {
        $txt = Read-TextNoBom $dl
        if ($txt -notmatch 'wb_outland') {
            $entries = (Read-TextNoBom (Join-Path $pd 'dialogs_lang.csv')).TrimEnd()
            Save-TextWithBom $dl ($txt.TrimEnd() + "`r`n" + $entries + "`r`n")
        }
    }

    # 1 小时触发器：执行 pending 归队（此时玩家多半已离开遭遇，删除部队不会再触发菜单引用）
    $trPath = Join-Path $modDir 'simple_triggers.txt'
    $trRows = [IO.File]::ReadAllText($trPath, $enc) -split "\r?\n"
    $tn = 0
    if (-not [int]::TryParse($trRows[1].Trim(), [ref]$tn)) { throw 'simple_triggers.txt 第 2 行不是数量' }
    if (($trRows -join "`n") -match 'wb_drill_finish') { throw '这个模块里已经有历练触发器了' }
    $trRest = @($trRows[2..($trRows.Count - 1)] | Where-Object { $_ -ne '' })
    $trNew = '1.000000 1 1 1 ' + $finTag
    $trOut = @($trRows[0], [string]($tn + 1), $trNew) + $trRest
    [IO.File]::WriteAllText($trPath, ((($trOut -join "`r`n")) + "`r`n"), $enc)

    Write-ModpackLog '[drill] 历练：同伴可派往关系>10 的国王处当领主（与国王好感 +20）；任意势力的原同伴领主可对话归队（别国领地设未分封，自家王国领地收回给玩家）；成长按原版本体'
}

# ---------- 宣称（失地自动归还 / 停战清算 / 叛国清理） ----------
function Apply-Claim([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $scPath = Join-Path $modDir 'scripts.txt'
    $scLines = [IO.File]::ReadAllText($scPath, $enc) -split "\r?\n"
    $n = 0
    if (-not [int]::TryParse($scLines[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是数量' }

    # 参数：宣称调试提示（1 = 写入消息变量，由 Lua 统一显示）
    $md = Read-TextNoBom (Join-Path $PSScriptRoot 'params.md')
    $dbg = 1
    foreach ($ln in ($md -split "\r?\n")) {
        if ($ln -match '^\|\s*宣称调试提示\s*\|\s*(\d+)\s*\|') { $dbg = [int]$Matches[1] }
    }
    # 参数：宣称队列调试（1 = 每次攻占重复入队 3 条，验证队列逐条显示）
    $qdbg = 1
    foreach ($ln in ($md -split "\r?\n")) {
        if ($ln -match '^\|\s*宣称队列调试\s*\|\s*(\d+)\s*\|') { $qdbg = [int]$Matches[1] }
    }
    # 消息变量由 Apply-MsgVars 统一初始化，这里只取 tag
    $vPath = Join-Path $modDir 'variables.txt'
    $varList = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $msgVars = @('g_wb_msg_type', 'g_wb_msg_count')
    $msgIdx = @{}
    foreach ($vn in $msgVars) {
        $found = -1
        for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq $vn) { $found = $i; break } }
        if ($found -lt 0) { throw "variables.txt 里没有 $vn（先跑 Apply-MsgVars）" }
        $msgIdx[$vn] = $found
    }
    $TAG_VAR = [int64]144115188075855872
    # 宣称消息队列变量（type/center/faction 各 4 槽 + 计数 + 出队后的类型），末尾追加，旧存档兼容
    $qVarNames = @('g_wb_claim_q_n', 'g_wb_claim_q_type')
    for ($qi = 1; $qi -le 8; $qi++) { $qVarNames += "g_wb_claim_q_c$qi" }
    for ($qi = 1; $qi -le 8; $qi++) { $qVarNames += "g_wb_claim_q_f$qi" }
    for ($qi = 1; $qi -le 8; $qi++) { $qVarNames += "g_wb_claim_q_t$qi" }
    foreach ($vn in $qVarNames) {
        if (-not ($varList -contains $vn)) { $varList += $vn }
    }
    [IO.File]::WriteAllText($vPath, (($varList -join "`r`n") + "`r`n"), $enc)
    $qIdx = @{}
    for ($qi = 0; $qi -lt $varList.Count; $qi++) { $qIdx[$varList[$qi].Trim()] = $qi }
    foreach ($vn in $qVarNames) { if (-not $qIdx.ContainsKey($vn)) { throw "variables.txt 里没有 $vn" } }
    # 原版 players_kingdom 变量（索引跟 Native 变量表走，别硬编码）
    $pkIdx = -1
    for ($i = 0; $i -lt $varList.Count; $i++) { if ($varList[$i].Trim() -eq 'players_kingdom') { $pkIdx = $i; break } }
    if ($pkIdx -lt 0) { throw 'variables.txt 里没有 players_kingdom' }
    $varPK = [string]($TAG_VAR + $pkIdx)
    $r12 = '1224979098644774912'; $r13 = '1224979098644774913'; $r14 = '1224979098644774914'
    $r15 = '1224979098644774915'; $r16 = '1224979098644774916'; $r17 = '1224979098644774917'
    $msgTypeVar = [string]($TAG_VAR + $msgIdx['g_wb_msg_type'])
    $msgCountVar = [string]($TAG_VAR + $msgIdx['g_wb_msg_count'])
    # 队列变量 tag
    $qNVar = [string]($TAG_VAR + $qIdx['g_wb_claim_q_n'])
    $qTypeVar = [string]($TAG_VAR + $qIdx['g_wb_claim_q_type'])
    $qCVar = @{}; $qFVar = @{}; $qTVar = @{}
    for ($qi = 1; $qi -le 8; $qi++) {
        $qCVar[$qi] = [string]($TAG_VAR + $qIdx["g_wb_claim_q_c$qi"])
        $qFVar[$qi] = [string]($TAG_VAR + $qIdx["g_wb_claim_q_f$qi"])
        $qTVar[$qi] = [string]($TAG_VAR + $qIdx["g_wb_claim_q_t$qi"])
    }

    $TAG = [int64]936748722493063168   # tag_script(13) << 56
    # 取已存在脚本的 tag（give_center_to_lord 等）
    $idxOf = @{}
    $line = 2
    for ($i = 2; $i -lt $scLines.Count - 1; $i += 2) {
        $nm = ($scLines[$i].Trim() -split '\s+')[0]
        if ($nm -and -not $idxOf.ContainsKey($nm)) { $idxOf[$nm] = [int64](($i - 2) / 2) }
    }
    if (-not $idxOf.ContainsKey('give_center_to_lord')) { throw '找不到 give_center_to_lord 脚本' }
    if (-not $idxOf.ContainsKey('give_center_to_faction_aux')) { throw '找不到 give_center_to_faction_aux 脚本' }
    $gclTag = [string]($TAG + $idxOf['give_center_to_lord'])
    $auxTag = [string]($TAG + $idxOf['give_center_to_faction_aux'])

    # 新脚本 tag
    $markTag    = [string]($TAG + $n)
    $settleOneTag = [string]($TAG + ($n + 1))
    $settleTag  = [string]($TAG + ($n + 2))
    $peaceTag   = [string]($TAG + ($n + 3))
    $purgeTag   = [string]($TAG + ($n + 4))
    $qPushTag   = [string]($TAG + ($n + 5))
    $qPopTag    = [string]($TAG + ($n + 6))

    $r12 = '1224979098644774912'; $r13 = '1224979098644774913'; $r14 = '1224979098644774914'
    $r15 = '1224979098644774915'; $r16 = '1224979098644774916'; $r17 = '1224979098644774917'
    $centersBegin = '648518346341351445'; $centersEnd = '648518346341351625'
    $facBegin = '432345564227567630'; $facEnd = '432345564227567637'
    # 宣称槽位：168-233 全被原版占用（含 trade_route 190-204、生产建筑 205-233），
    # 空闲只有 234-239。旧版误用 200-203（trade_route_11-14）→ 贸易脚本报 Invalid Party ID。
    $slClaimLord = '234'
    $slClaimFaction = '235'
    $slPending = '236'
    $slPendingLord = '237'

    # 1) mark：中心易手时记录/更新宣称（在 give_center_to_faction_aux 里调用）
    $mark = @(
        '23','2',$r12,'1',
        '23','2',$r13,'2',
        '23','2',$r14,'3',
        '4','0',
        '2147483679','2',$r13,$r14,
        '521','3',$r15,$r12,'7',
        '32','2',$r15,'0',
        '33','3',$r13,$facBegin,$facEnd,
        '521','3',$r16,$r12,$slClaimLord,
        '521','3',$r17,$r12,$slClaimFaction,
        '4','0',
        '2147483679','2',$r17,'0',
        '4','0',
        '31','2',$r17,$r14,
        '501','3',$r12,$slPending,'1',
        '501','3',$r12,$slPendingLord,$r16,
        '5','0',
        '3','0',
        '5','0',
        '501','3',$r12,$slClaimLord,$r15,
        '501','3',$r12,$slClaimFaction,$r13
    )
    if ($dbg -eq 1) {
        # 攻占消息入队（type 1），由 Lua 每帧逐条取出显示，避免同帧多条互相覆盖
        $mark += @('1','4',$qPushTag,'1',$r12,$r14)
        if ($qdbg -eq 1) {
            # 调试：同一条消息再多入队 2 次（共 3 条），攻城一次就能看到队列逐条打印
            $mark += @('1','4',$qPushTag,'1',$r12,$r14,'1','4',$qPushTag,'1',$r12,$r14)
        }
    }
    $mark += @('501','3',$r12,$slPending,'0','3','0','3','0')

    # 2) settle_one：处理单块中心的待归还
    #    只有 236=1（本次易手正是「原势力收复」）才处理：校验原领主仍属宣称势力、仍是领主，
    #    归还中心与其附属村庄，然后清 234/235 宣称并清 236 标记。
    #    没有待归还（236≠1）时**什么也不做**——绝不能动 234/235，否则 mark 刚记下的宣称会被当场清掉。
    $settleOne = @(
        '23','2',$r12,'1',
        '521','3',$r13,$r12,'236',
        '4','0',
        '31','2',$r13,'1',
        '521','3',$r14,$r12,'237',
        '4','0',
        '32','2',$r14,'0',
        '2173','2',$r15,$r14,
        '521','3',$r16,$r12,'235',
        '31','2',$r15,$r16,
        '540','3',$r14,'2','2',
        '1','4',$gclTag,$r12,$r14,'1',
        '6','3','1224979098644774918','648518346341351445','648518346341351625',
        '541','3','1224979098644774918','120',$r12,
        '1','4',$gclTag,'1224979098644774918',$r14,'1',
        '3','0',
        '1095','2',$r12,'1',
        '4','0','31','2',$r16,$varPK,
        '4','0','33','3',$r12,'648518346341351445','648518346341351467',
        '2133','2','72057594037927936','3000',
        '5','0',
        '2133','2','72057594037927936','2000',
        '3','0',
        '6','3','1224979098644774919','648518346341351445','648518346341351625',
        '521','3','1224979098644774920','1224979098644774919','120',
        '31','2','1224979098644774920',$r12,
        '2105','2','72057594037927936','500',
        '3','0',
        '1528','2','360287970189639680','72057594037927936',
        '3','0'
    ) + $(if ($dbg -eq 1) { @('1','4',$qPushTag,'2',$r12,$r16) } else { @() }) + @(
        '501','3',$r12,'234','0',
        '501','3',$r12,'235','0',
        '3','0',
        '501','3',$r12,'236','0',
        '3','0'
    )
    # 3) settle：城 + 附属村庄
    $settle = @(
        '23','2',$r12,'1',
        '1','2',$settleOneTag,$r12,
        '6','3',$r13,$centersBegin,$centersEnd,
        '541','3',$r13,'120',$r12,
        '1','2',$settleOneTag,$r13,
        '3','0'
    )
    # 4) peace：A、B 停战时按实际控制清空互相宣称
    $peace = @(
        '23','2',$r12,'1',
        '23','2',$r13,'2',
        '6','3',$r14,$centersBegin,$centersEnd,
        '2204','2',$r15,$r14,
        '4','0',
        '31','2',$r15,$r12,
        '521','3',$r16,$r14,$slClaimFaction,
        '31','2',$r16,$r13,
        '501','3',$r14,$slClaimLord,'0',
        '501','3',$r14,$slClaimFaction,'0',
        '5','0',
        '31','2',$r15,$r13,
        '521','3',$r16,$r14,$slClaimFaction,
        '31','2',$r16,$r12,
        '501','3',$r14,$slClaimLord,'0',
        '501','3',$r14,$slClaimFaction,'0',
        '3','0',
        '3','0'
    )
    # 5) purge：每周清理叛国/流放领主的宣称
    if ($dbg -eq 1) {
        $ps = $peace -join ' '
        $ps = $ps.Replace("23 2 $r12 1 23 2 $r13 2", "23 2 $r12 1 23 2 $r13 2 2133 2 $r17 0")
        $ps = $ps.Replace("501 3 $r14 $slClaimLord 0 501 3 $r14 $slClaimFaction 0", "501 3 $r14 $slClaimLord 0 501 3 $r14 $slClaimFaction 0 2105 2 $r17 1")
        $ps = $ps + " 4 0 32 2 $r17 0 2133 2 $msgTypeVar 3 2133 2 $msgCountVar $r17 3 0"
        $peace = $ps -split ' '
    }
    $purge = @(
        '6','3',$r12,$centersBegin,$centersEnd,
        '6','3',$r16,'200','204',
        '521','3',$r17,$r12,$r16,
        '4','0',
        '2147483679','2',$r17,'0',
        '2147483678','2',$r17,'648518346341351424',
        '501','3',$r12,$r16,'0',
        '3','0',
        '3','0',
        '521','3',$r13,$r12,$slClaimLord,
        '4','0',
        '32','2',$r13,'0',
        '521','3',$r14,$r12,$slClaimFaction,
        '2173','2',$r15,$r13,
        '4','0',
        '2147483679','2',$r15,$r14,
        '501','3',$r12,$slClaimLord,'0',
        '501','3',$r12,$slClaimFaction,'0',
        '5','0',
        '2147484188','3',$r13,'2','2',
        '501','3',$r12,$slClaimLord,'0',
        '501','3',$r12,$slClaimFaction,'0',
        '3','0',
        '3','0',
        '3','0'
    )

    # 6) 消息队列：入队（type, center, faction；最多 8 条，满了直接丢弃新消息）
    $qPush = @(
        '23','2',$r12,'1',
        '23','2',$r13,'2',
        '23','2',$r14,'3',
        '2133','2',$r15,$qNVar
    )
    for ($qi = 0; $qi -lt 8; $qi++) {
        if ($qi -eq 0) { $qPush += @('4','0','31','2',$r15,'0') }
        else { $qPush += @('5','0','31','2',$r15,[string]$qi) }
        $k = $qi + 1
        $qPush += @('2133','2',$qTVar[$k],$r12,
            '2133','2',$qCVar[$k],$r13,
            '2133','2',$qFVar[$k],$r14,
            '2133','2',$qNVar,[string]$k)
    }
    $qPush += @('3','0')

    # 7) 消息出队：把队首写进 s55（中心名）/ s62（势力名）+ 类型变量，供 Lua 读取显示
    $qPop = @(
        '2133','2',$r15,$qNVar,
        '4','0',
        '32','2',$r15,'0',
        '2133','2',$qTypeVar,$qTVar[1],
        '2330','2','55',$qCVar[1],
        '2335','2','62',$qFVar[1]
    )
    for ($qi = 1; $qi -lt 8; $qi++) {
        $a = $qi; $b = $qi + 1
        $qPop += @('2133','2',$qTVar[$a],$qTVar[$b],
            '2133','2',$qCVar[$a],$qCVar[$b],
            '2133','2',$qFVar[$a],$qFVar[$b])
    }
    $qPop += @('2133','2',$qTVar[8],'0',
        '2133','2',$qCVar[8],'0',
        '2133','2',$qFVar[8],'0',
        '2106','2',$qNVar,'1',
        '3','0')

    $scripts = @(
        @('wb_claim_mark', $mark),
        @('wb_claim_settle_one', $settleOne),
        @('wb_claim_settle', $settle),
        @('wb_claim_peace', $peace),
        @('wb_claim_purge', $purge),
        @('wb_claim_q_push', $qPush),
        @('wb_claim_q_pop', $qPop)
    )
    # 追加脚本：名字行 + 体行（体行首 token = 语句数）
    while ($scLines.Count -ge 1 -and $scLines[$scLines.Count - 1] -eq '') { $scLines = @($scLines[0..($scLines.Count - 2)]) }
    $addRows = New-Object System.Collections.Generic.List[string]
    foreach ($s in $scripts) {
        $body = [string[]]$s[1]
        # 语句数 = token 组数（按 opcode 参数解析验证）
        $stmt = 0; $p = 0
        while ($p -lt $body.Count) {
            $na = [int]$body[$p + 1]
            $p += 2 + $na
            $stmt++
        }
        if ($p -ne $body.Count) { throw "脚本 $($s[0]) token 结构错位（$p/$($body.Count)）" }
        $addRows.Add("$($s[0]) -1")
        $addRows.Add(' ' + $stmt + ' ' + ($body -join ' '))
    }
    $scLines[1] = [string]($n + $scripts.Count)
    $scLines = @($scLines) + @($addRows)
    [IO.File]::WriteAllText($scPath, ((($scLines) -join "`r`n") + "`r`n"), $enc)
    Write-ModpackLog "[claim] 追加 7 个脚本（mark/settle_one/settle/peace/purge/q_push/q_pop）"

    # 钩子 1：aux 里 party_set_faction 之后调用 mark
    $auxIdx = -1
    for ($i = 2; $i -lt $scLines.Count - 1; $i += 2) {
        if ($scLines[$i] -like 'give_center_to_faction_aux *') { $auxIdx = $i; break }
    }
    if ($auxIdx -lt 0) { throw '找不到 give_center_to_faction_aux 名字行' }
    $auxToks = @($scLines[$auxIdx + 1].Trim() -split '\s+')
    if ($auxToks.Count -ne 112 -or $auxToks[0] -ne '30') { throw "give_center_to_faction_aux 体行结构变了（$($auxToks.Count) tokens / $($auxToks[0]) stmts）" }
    $hookMark = @('1','4',$markTag,$r12,$r14,$r13)
    $auxNew = @($auxToks[0..14]) + $hookMark + @($auxToks[15..($auxToks.Count - 1)])
    $auxNew[0] = '31'
    $scLines[$auxIdx + 1] = ' ' + ($auxNew -join ' ')

    # 钩子 2：give_center_to_faction 在 aux 调用之后调用 settle
    $gcfIdx = -1
    for ($i = 2; $i -lt $scLines.Count - 1; $i += 2) {
        if ($scLines[$i] -like 'give_center_to_faction *') { $gcfIdx = $i; break }
    }
    if ($gcfIdx -lt 0) { throw '找不到 give_center_to_faction 名字行' }
    $gcfToks = @($scLines[$gcfIdx + 1].Trim() -split '\s+')
    if ($gcfToks.Count -ne 151 -or $gcfToks[0] -ne '42') { throw "give_center_to_faction 体行结构变了（$($gcfToks.Count) tokens / $($gcfToks[0]) stmts）" }
    $auxCallFrag = @('1','3',$auxTag,$r12,$r13)
    $hookSettle = @('1','2',$settleTag,$r12)
    $pos = -1
    for ($i = 0; $i -le $gcfToks.Count - 5; $i++) {
        if ($gcfToks[$i] -eq '1' -and $gcfToks[$i+1] -eq '3' -and $gcfToks[$i+2] -eq $auxTag -and $gcfToks[$i+3] -eq $r12 -and $gcfToks[$i+4] -eq $r13) { $pos = $i; break }
    }
    if ($pos -lt 0) { throw 'give_center_to_faction 里找不到 aux 调用' }
    $gcfNew = @($gcfToks[0..($pos + 4)]) + $hookSettle + @($gcfToks[($pos + 5)..($gcfToks.Count - 1)])
    $gcfNew[0] = '43'
    $scLines[$gcfIdx + 1] = ' ' + ($gcfNew -join ' ')

    # 钩子 2b：give_center_to_faction_while_maintaining_lord（玩家攻城归属）同样挂 mark + settle
    $kmlIdx = -1
    for ($i = 2; $i -lt $scLines.Count - 1; $i += 2) {
        if ($scLines[$i] -like 'give_center_to_faction_while_maintaining_lord *') { $kmlIdx = $i; break }
    }
    if ($kmlIdx -lt 0) { throw '找不到 give_center_to_faction_while_maintaining_lord 名字行' }
    $kmlToks = @($scLines[$kmlIdx + 1].Trim() -split '\s+')
    $kmlDecl = [int]$kmlToks[0]
    $kmlPos = -1
    $p2 = 1
    while ($p2 -lt $kmlToks.Count) {
        $op2 = [long]$kmlToks[$p2]; $na2 = [int]$kmlToks[$p2 + 1]
        if ($op2 -eq 1620 -and $na2 -eq 2 -and $kmlToks[$p2 + 2] -eq $r12 -and $kmlToks[$p2 + 3] -eq $r13) { $kmlPos = $p2; break }
        $p2 += 2 + $na2
    }
    if ($kmlPos -lt 0) { throw 'maintaining_lord 里找不到城市 party_set_faction 语句' }
    $kmlHook = @('1','4',$markTag,$r12,$r14,$r13)
    $insAt = $kmlPos + 4
    $kmlNew = @($kmlToks[0..($insAt - 1)]) + $kmlHook + @($kmlToks[$insAt..($kmlToks.Count - 1)])
    $kmlNew = $kmlNew + @('1','2',$settleTag,$r12)
    $kmlNew[0] = [string]($kmlDecl + 2)
    $scLines[$kmlIdx + 1] = ' ' + ($kmlNew -join ' ')

    # 钩子 3：diplomacy_start_peace_between_kingdoms 开头调用 peace
    $peaceIdx = -1
    for ($i = 2; $i -lt $scLines.Count - 1; $i += 2) {
        if ($scLines[$i] -like 'diplomacy_start_peace_between_kingdoms *') { $peaceIdx = $i; break }
    }
    if ($peaceIdx -lt 0) { throw '找不到 diplomacy_start_peace_between_kingdoms 名字行' }
    $pTok = @($scLines[$peaceIdx + 1].Trim() -split '\s+')
    if ($pTok.Count -ne 271 -or $pTok[0] -ne '67') { throw "diplomacy_start_peace_between_kingdoms 体行结构变了（$($pTok.Count) tokens / $($pTok[0]) stmts）" }
    $hookPeace = @('1','3',$peaceTag,$r12,$r13)
    $pNew = @($pTok[0..12]) + $hookPeace + @($pTok[13..($pTok.Count - 1)])
    $pNew[0] = '68'
    $scLines[$peaceIdx + 1] = ' ' + ($pNew -join ' ')

    [IO.File]::WriteAllText($scPath, ((($scLines) -join "`r`n") + "`r`n"), $enc)

    # 钩子 4：48 小时越狱触发器追加 purge（清理叛国宣称 + 旧版 200-203 脏槽，48h 一次尽快修复）
    $tPath = Join-Path $modDir 'simple_triggers.txt'
    $tLines = [IO.File]::ReadAllText($tPath, $enc) -split "\r?\n"
    while ($tLines.Count -ge 1 -and $tLines[$tLines.Count - 1] -eq '') { $tLines = @($tLines[0..($tLines.Count - 2)]) }
    $hit = -1
    for ($i = 0; $i -lt $tLines.Count; $i++) {
        if ($tLines[$i] -like '48.000000  56 *') { $hit = $i; break }
    }
    if ($hit -lt 0) { throw 'simple_triggers.txt 里找不到 48 小时越狱触发器（56 语句）' }
    $tLines[$hit] = $tLines[$hit].TrimEnd() + ' 1 1 ' + $purgeTag
    $tLines[$hit] = $tLines[$hit].Replace('48.000000  56 ', '48.000000  57 ')
    [IO.File]::WriteAllText($tPath, ((($tLines) -join "`r`n") + "`r`n"), $enc)
    Write-ModpackLog '[claim] 钩子已挂：中心易手（mark）、归属落定（settle）、停战（peace）、48h 清理（purge）'

}

# 宣称队列变量重排：Apply-Claim 运行时变量追加在当时的位置，后面的功能还会追加变量，
# 会让「后续功能变量」整体位移（旧存档按索引读 → 错位）。这里把队列变量移到末尾，
# 其余变量保持原顺序 → 索引与「没有队列变量时」一致；再把所有数据文件里的变量 tag 重算。
function Finalize-ClaimVars([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $TAG_VAR = [int64]144115188075855872
    $vPath = Join-Path $modDir 'variables.txt'
    $names = @([IO.File]::ReadAllText($vPath, $enc) -split "\r?\n" | Where-Object { $_.Trim() -ne '' })
    $qNames = @('g_wb_claim_q_n', 'g_wb_claim_q_type')
    for ($i = 1; $i -le 8; $i++) { $qNames += "g_wb_claim_q_c$i" }
    for ($i = 1; $i -le 8; $i++) { $qNames += "g_wb_claim_q_f$i" }
    for ($i = 1; $i -le 8; $i++) { $qNames += "g_wb_claim_q_t$i" }
    $pos = @{}
    for ($i = 0; $i -lt $names.Count; $i++) { if ($qNames -contains $names[$i]) { $pos[$names[$i]] = $i } }
    if ($pos.Count -ne $qNames.Count) { throw "变量表里没有完整的宣称队列变量（$($pos.Count)/$($qNames.Count)）" }
    $oldCount = $names.Count
    # 已经在末尾则不动
    $atTail = $true
    for ($i = 0; $i -lt $qNames.Count; $i++) {
        if ($names[$oldCount - $qNames.Count + $i] -ne $qNames[$i]) { $atTail = $false; break }
    }
    if ($atTail) { return }
    $nonQ = @($names | Where-Object { $qNames -notcontains $_ })
    $qOrdered = @($names | Where-Object { $qNames -contains $_ })
    $newNames = @($nonQ) + @($qOrdered)
    $newIdx = @{}
    for ($i = 0; $i -lt $newNames.Count; $i++) { $newIdx[$newNames[$i]] = $i }
    $files = @('scripts.txt', 'conversation.txt', 'menus.txt', 'simple_triggers.txt', 'triggers.txt',
        'mission_templates.txt', 'presentations.txt', 'quests.txt', 'info_pages.txt', 'party_templates.txt')
    $texts = @{}
    foreach ($f in $files) {
        $p = Join-Path $modDir $f
        if (Test-Path $p) { $texts[$f] = [IO.File]::ReadAllText($p, $enc) }
    }
    # 两步替换：先换成占位符，再换成新 tag，避免旧/新索引区间重叠时链式误替换
    for ($i = 0; $i -lt $oldCount; $i++) {
        if ($i -eq [int]$newIdx[$names[$i]]) { continue }
        $oldTag = [string]($TAG_VAR + $i)
        $ph = "@@VB$i@@"
        foreach ($f in @($texts.Keys)) { $texts[$f] = $texts[$f].Replace($oldTag, $ph) }
    }
    for ($i = 0; $i -lt $oldCount; $i++) {
        $newI = [int]$newIdx[$names[$i]]
        if ($i -eq $newI) { continue }
        $ph = "@@VB$i@@"
        $newTag = [string]($TAG_VAR + $newI)
        foreach ($f in @($texts.Keys)) { $texts[$f] = $texts[$f].Replace($ph, $newTag) }
    }
    [IO.File]::WriteAllText($vPath, (($newNames -join "`r`n") + "`r`n"), $enc)
    foreach ($f in @($texts.Keys)) { [IO.File]::WriteAllText((Join-Path $modDir $f), $texts[$f], $enc) }
    Write-ModpackLog "[claim] 队列变量已移到变量表末尾（共 $oldCount 个）"
}

# ---------- Lua 消息出口（WSE2 可选增强） ----------
function Apply-Lua([string]$modDir) {
    $pd = Join-Path $PSScriptRoot 'patches\lua'
    if (-not (Test-Path (Join-Path $pd 'main.lua'))) { throw 'patches\lua\main.lua 缺失' }
    $luaDir = Join-Path $modDir 'lua'
    New-Item -ItemType Directory -Path $luaDir -Force | Out-Null
    Copy-Item (Join-Path $pd 'main.lua') (Join-Path $luaDir 'main.lua') -Force

    # msfiles：WSE2 Lua 靠这些 header 文件解析 opcode 名与常量
    # 优先用本目录自带的 patches\lua\ms（整个目录拷到别的电脑也能直接生成）；
    # 没有内置副本时回退到工作区 tmp\warband\ms（旧布局兼容）。
    $msSrc = Join-Path $pd 'ms'
    if (-not (Test-Path $msSrc)) {
        $msSrc = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\tmp\warband\ms\Module_system 1.171'))
    }
    if (Test-Path $msSrc) {
        $msDst = Join-Path $luaDir 'msfiles'
        New-Item -ItemType Directory -Path $msDst -Force | Out-Null
        $files = Get-ChildItem $msSrc -File | Where-Object { $_.Name -match '^(header_|ID_).*\.py$' }
        foreach ($f in $files) { Copy-Item $f.FullName (Join-Path $msDst $f.Name) -Force }
        # WSE2 SDK 的扩展操作/常量追加到对应 header（字节级追加，避免编码转换）
        $gameRoot = Split-Path (Split-Path $modDir -Parent) -Parent
        $sdk = Join-Path $gameRoot 'WSE2 SDK'
        $appendPairs = @(
            @('header_operations_addon.py', 'header_operations.py'),
            @('header_triggers_addon.py', 'header_triggers.py'),
            @('header_common_addon.py', 'header_common.py')
        )
        foreach ($pair in $appendPairs) {
            $addonPath = Join-Path $sdk $pair[0]
            $targetPath = Join-Path $msDst $pair[1]
            if ((Test-Path $addonPath) -and (Test-Path $targetPath)) {
                $bytes = [IO.File]::ReadAllBytes($targetPath)
                $a = [IO.File]::ReadAllBytes($addonPath)
                $all = New-Object byte[] ($bytes.Length + 2 + $a.Length)
                [Array]::Copy($bytes, 0, $all, 0, $bytes.Length)
                $all[$bytes.Length] = 13
                $all[$bytes.Length + 1] = 10
                [Array]::Copy($a, 0, $all, $bytes.Length + 2, $a.Length)
                [IO.File]::WriteAllBytes($targetPath, $all)
            }
        }
        Write-ModpackLog "[lua] main.lua + msfiles（$($files.Count) 个 header/ID 文件，含 WSE2 addon）"
    } else {
        Write-ModpackLog "[lua] 警告：找不到 msfiles 源（patches\lua\ms 或工作区 tmp\warband\ms），只写了 main.lua（Lua 会因缺 msfiles 无法解析 opcode）"
    }
}

# ---------- 奇形宝箱 ----------
# ---------- 市场「整理物品」（sortitems） ----------
# 玩家背包按 书籍 / 马匹 / 货物 / 武器 / 护甲 / 其他 分组，组内按市场价值降序；
# 菜单选项插在城镇市场「评估本地价格」下面。脚本源码在 patches\sort\sort.asm，由 wb-asm.ps1 汇编。
function Apply-SortItems([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $pd = Join-Path $PSScriptRoot 'patches\sort'
    $asmPatch = Join-Path $pd 'scripts.txt'
    if (-not (Test-Path $asmPatch)) { throw 'patches\sort\scripts.txt 缺失（先跑 wb-asm.ps1 汇编 sort.asm）' }

    # 1) scripts.txt 追加 1 个脚本（wb_sort_items：调用引擎 troop_sort_inventory）
    $sPath = Join-Path $modDir 'scripts.txt'
    $scRows = [IO.File]::ReadAllText($sPath, $enc) -split "\r?\n"
    if (($scRows -join "`n") -match 'wb_sort_items') { throw '这个模块里已经有物品排序功能了' }
    $n = 0
    if (-not [int]::TryParse($scRows[1].Trim(), [ref]$n)) { throw 'scripts.txt 第 2 行不是脚本数量' }
    $patchRows = @([IO.File]::ReadAllText($asmPatch, $enc) -split "\r?\n" | Where-Object { $_ -ne '' })
    if ($patchRows.Count -ne 2) { throw "排序脚本补丁应 2 行（1 个脚本 ×2），实际 $($patchRows.Count)" }
    $scriptNames = @()
    for ($i = 0; $i -lt $patchRows.Count; $i += 2) { $scriptNames += (($patchRows[$i].Trim() -split '\s+')[0]) }
    $tagOf = @{}
    for ($k = 0; $k -lt $scriptNames.Count; $k++) { $tagOf[$scriptNames[$k]] = [string]([uint64]936748722493063168 + [uint64]($n + $k)) }
    foreach ($need in @('wb_sort_items')) {
        if (-not $tagOf.ContainsKey($need)) { throw "sort 补丁缺脚本 $need" }
    }
    $repl = @{}
    $outLines = New-Object System.Collections.Generic.List[string]
    foreach ($row in $patchRows) {
        $line = $row
        foreach ($k in @($repl.Keys)) { $line = $line.Replace($k, $repl[$k]) }
        if ($line -match '\{\{') { throw "占位符没替换干净: $line" }
        $outLines.Add($line)
    }
    $scBody = @($scRows | Select-Object -SkipLast 1)
    $scBody[1] = [string]($n + $scriptNames.Count)
    [IO.File]::WriteAllText($sPath, ((($scBody + $outLines) -join "`r`n") + "`r`n"), $enc)

    # 2) menus.txt：menu_town_trade 选项数 +1，「整理物品」插在「评估本地价格」后面
    $mPath = Join-Path $modDir 'menus.txt'
    $mRows = [IO.File]::ReadAllText($mPath, $enc) -split "\r?\n"
    $tradeLine = -1
    for ($i = 0; $i -lt $mRows.Count; $i++) {
        if ($mRows[$i] -match '^menu_town_trade ') { $tradeLine = $i; break }
    }
    if ($tradeLine -lt 0) { throw 'menus.txt 里没有 menu_town_trade' }
    if ($mRows[$tradeLine] -match 'mno_wb_sort_items') { throw '这个模块里已经有物品排序菜单项了' }
    $t = $mRows[$tradeLine].Trim() -split '\s+'
    $optCount = 0
    if (-not [int]::TryParse($t[$t.Count - 1], [ref]$optCount)) { throw 'menu_town_trade 行末不是选项数' }
    $mRows[$tradeLine] = (($t[0..($t.Count - 2)] -join ' ') + ' ' + [string]($optCount + 1))
    $optLine = $mRows[$tradeLine + 1]
    $anchor = $optLine.IndexOf('mno_assess_prices')
    if ($anchor -lt 0) { throw 'menu_town_trade 里找不到 mno_assess_prices' }
    $dot = $optLine.IndexOf(' . ', $anchor)
    if ($dot -lt 0) { throw '找不到 mno_assess_prices 选项结束标记' }
    # 菜单项改为跳转「整理中」菜单（选项动作里的 call_script 会被引擎执行成 game_start，
    # 改用菜单的初始化动作来调排序脚本；那条链路有 Native 先例）
    $mCount = 0
    if (-not [int]::TryParse($mRows[1].Trim(), [ref]$mCount)) { throw 'menus.txt 第 2 行不是数量' }
    $tradeIdx = -1; $mi = 0
    for ($i = 0; $i -lt $mRows.Count; $i++) {
        if ($mRows[$i] -match '^menu_') {
            if ($mRows[$i] -like 'menu_town_trade *') { $tradeIdx = $mi }
            $mi++
        }
    }
    $TAG_MENU = [uint64]864691128455135232
    $doneTag = [string]($TAG_MENU + [uint64]$mCount)
    $tradeTag = [string]($TAG_MENU + [uint64]$tradeIdx)
    $newOpt = 'mno_wb_sort_items 0 Sort_the_items. 1 2060 1 ' + $doneTag + ' .'
    $mRows[$tradeLine + 1] = $optLine.Substring(0, $dot + 3) + ' ' + $newOpt + $optLine.Substring($dot + 3)
    # 追加「整理中」菜单（菜单行 + 继续选项）：菜单初始化里调排序脚本，追加末尾不影响已有菜单 ID
    $mRows += 'menu_wb_sort_done 18374686479671624192 Sort_done. none 1 1 1 ' + $tagOf['wb_sort_items'] + ' 1'
    $mRows += 'mno_wb_sort_continue 0 Continue... 1 2060 1 ' + $tradeTag + ' .'
    $mRows[1] = [string]($mCount + 1)
    [IO.File]::WriteAllText($mPath, ($mRows -join "`r`n"), $enc)

    # 3) 语言词条
    $langPath = Join-Path $modDir 'languages\cns\game_menus.csv'
    if (Test-Path $langPath) {
        $langText = Read-TextNoBom $langPath
        $entries = (Read-TextNoBom (Join-Path $pd 'lang_entries.csv')).TrimEnd()
        Save-TextWithBom $langPath ($langText.TrimEnd() + "`r`n" + $entries + "`r`n")
    }
    Write-ModpackLog "[sortitems] 1 个脚本（troop_sort_inventory）+ 市场菜单 1 项 + 3 条中文词条"
}

# ---------- 作弊菜单汉化（cheatlang） ----------
# 战团内置作弊菜单（营地 → CHEAT MENU!，以及物品查找 / 天气 / 城堡攻城 / 训练场 / 人物报告 /
# 阵营命令 / 教程等处的 CHEAT 项）的文本只存在于 menus.txt，官方中文语言包没有词条。
# 本补丁：
#   1) 把重复的选项 ID 改成唯一 ID（语言文件按 ID 查表，同名选项无法分别翻译）；
#   2) 把 patches\cheatlang\lang_menus.csv 的词条追加到模块的 languages\cns\game_menus.csv。
# 只改选项 ID，不动选项的条件与动作；第 6 个「继续……」保留原名走官方翻译。
function Apply-CheatLang([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $pd = Join-Path $PSScriptRoot 'patches\cheatlang'
    $mPath = Join-Path $modDir 'menus.txt'
    $rows = [IO.File]::ReadAllText($mPath, $enc) -split "\r?\n"
    if (($rows -join "`n") -match 'mno_camp_cheat_change_weather') {
        throw '这个模块里已经应用过作弊菜单汉化'
    }

    # 菜单 → 原选项 ID → 按出现顺序依次替换成的新 ID（'': 保留原名）
    $renames = @{
        'menu_camp_cheat' = @{
            'mno_camp_cheat_find_item' = @('mno_camp_cheat_find_item', 'mno_camp_cheat_change_weather')
            'mno_cheat_faction_orders' = @('mno_camp_cheat_debug_all', 'mno_camp_cheat_debug_econ', 'mno_camp_cheat_debug_political')
        }
        'menu_character_report' = @{
            'mno_continue' = @('mno_cheat_inc_rtor', 'mno_cheat_inc_relation', 'mno_cheat_inc_honor', 'mno_cheat_inc_renown', 'mno_cheat_inc_persuasion')
        }
        'menu_cheat_find_item' = @{
            'mno_camp_action_4' = @('mno_cheat_back_camp')
        }
        'menu_cheat_change_weather' = @{
            'mno_camp_action_4' = @('mno_cheat_back_camp')
        }
    }

    $cur = ''
    $map = @{}
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($row in $rows) {
        if ($row -match '^(menu_\S+)') {
            $cur = $Matches[1]
            $map = @{}
            if ($renames.ContainsKey($cur)) {
                foreach ($oldId in $renames[$cur].Keys) {
                    $q = [System.Collections.Generic.Queue[string]]::new()
                    foreach ($nw in $renames[$cur][$oldId]) { $q.Enqueue($nw) }
                    $map[$oldId] = $q
                }
            }
            $out.Add($row)
            continue
        }
        if ($map.Count -gt 0 -and $row -match '(?<!\S)mno_') {
            $row = [regex]::Replace($row, '(?<!\S)mno_[A-Za-z0-9_]+(?=\s)', {
                param($m)
                if ($map.ContainsKey($m.Value) -and $map[$m.Value].Count -gt 0) {
                    return $map[$m.Value].Dequeue()
                }
                return $m.Value
            })
        }
        $out.Add($row)
    }

    # 校验：目标菜单块内选项 ID 不能重复
    $seen = @{}
    $cur = ''
    foreach ($row in $out) {
        if ($row -match '^(menu_\S+)') { $cur = $Matches[1]; continue }
        if (-not $renames.ContainsKey($cur)) { continue }
        foreach ($m in [regex]::Matches($row, '(?<!\S)mno_[A-Za-z0-9_]+(?=\s)')) {
            $k = "$cur|$($m.Value)"
            if ($seen.ContainsKey($k)) { throw "选项 ID 重复：$($m.Value)（菜单 $cur）" }
            $seen[$k] = 1
        }
    }
    [IO.File]::WriteAllText($mPath, ($out -join "`r`n"), $enc)
    Write-ModpackLog '[cheatlang] 重复选项 ID 已唯一化（8 处）'

    # 语言词条：追加到模块 cns 语言包，先去掉同名 key 的旧行（幂等）
    $langPath = Join-Path $modDir 'languages\cns\game_menus.csv'
    if (-not (Test-Path $langPath)) { throw "缺少 languages\cns\game_menus.csv：$langPath" }
    $entries = (Read-TextNoBom (Join-Path $pd 'lang_menus.csv')).TrimEnd()
    $entries = ($entries -replace "\r?\n", "`r`n")
    $entryLines = @($entries -split "\r?\n")
    $newKeys = @{}
    foreach ($el in $entryLines) {
        $k = ($el -split '\|', 2)[0]
        if ($k) { $newKeys[$k] = 1 }
    }
    $keep = @()
    foreach ($ll in @((Read-TextNoBom $langPath).TrimEnd() -split "\r?\n")) {
        $k = ($ll -split '\|', 2)[0]
        if (-not $newKeys.ContainsKey($k)) { $keep += $ll }
    }
    Save-TextWithBom $langPath ((@($keep) -join "`r`n").TrimEnd() + "`r`n" + $entries + "`r`n")
    Write-ModpackLog "[cheatlang] 作弊菜单中文词条 $($entryLines.Count) 条"
}

function Apply-Lootchest([string]$modDir) {
    $enc = [Text.Encoding]::GetEncoding(28591)
    $f = Join-Path $modDir 'troops.txt'
    $text = $enc.GetString([IO.File]::ReadAllBytes($f))
    $old = '564 0 569 0 -1 0 -1 0 -1 0 -1 0'
    $new = '564 0 565 0 566 0 567 0 568 0 569 0'
    if ($text.Contains($new)) { throw '宝箱已经是 6 件了' }
    if (-not $text.Contains($old)) { throw 'troops.txt 里没找到宝箱库存行' }
    [IO.File]::WriteAllBytes($f, $enc.GetBytes($text.Replace($old, $new)))
    Write-ModpackLog '[lootchest] 奇形宝箱库存 2 件 → 6 件'
}

function Write-ModpackLog([string]$msg) {
    Write-Host "  $msg"
}

# ================= 主流程 =================
if (-not $GameDir) { $GameDir = Find-WarbandDir }
if (-not $GameDir -or -not (Test-Path (Join-Path $GameDir 'mb_warband.exe'))) {
    throw "没找到战团安装目录（-GameDir 指定）: $GameDir"
}
$native = Join-Path $GameDir 'Modules\Native'
if (-not (Test-Path (Join-Path $native 'scripts.txt'))) { throw "找不到源模块: $native" }
$target = Join-Path $GameDir "Modules\$ModuleName"
if ((Test-Path $target) -and -not $Force) { throw "目标模块已存在: $target（换 -ModuleName 或加 -Force）" }

$running = Get-Process -Name 'mb_warband*', 'wse2*' -ErrorAction SilentlyContinue
if ($running) { throw '游戏正在运行，先退出游戏' }

Write-Host "[i] 源模块: $native"
Write-Host "[i] 目标模块: $target"
$selectedGroups = @()
foreach ($g in $featureSpec.Groups) {
    foreach ($f in $g.Features) { if ($Features -contains $f) { $selectedGroups += $g.Title; break } }
}
Write-Host "[i] 分组（$($selectedGroups.Count) 组）: $($selectedGroups -join ' / ')"
Write-Host "[i] 功能（$($Features.Count) 项）: $($Features -join ', ')"

# 1) 复制
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
$null = robocopy $native $target /E /XD '_backup_garrison' '_backup_lairlink' '_backup_autoequip' /XF 'conversation - 副本.txt' 'scripts - 副本.txt' /NFL /NDL /NJH /NJS /NP
if ($LASTEXITCODE -ge 8) { throw "复制失败（robocopy $LASTEXITCODE）" }
Write-Host '[i] 已从 Native 复制'

# 2) 应用功能（顺序：equip → garrison → detail → lairlink → lootchest → fief → armyreward）
#    换装先做（它会新增菜单并重映射全模块菜单 ID），驻军随后替换的两行会跟着重映射
Apply-MsgVars $target
if ($Features -contains 'equip')      { Apply-Equip $target }
# 训练菜单骨架（mentor / learnskill 共用）：放在换装之后，避免被换装的「菜单 ID 全体 +1」重映射带偏
if ($Features -contains 'mentor' -or $Features -contains 'learnskill') { Apply-TrainingHost $target }
if ($Features -contains 'garrison')   { Apply-Garrison $target }
if ($Features -contains 'loan')        { Apply-Loan $target }
if ($Features -contains 'fiefenvy')    { Apply-FiefEnvy $target }
if ($Features -contains 'reconcile')   { Apply-Reconcile $target }
if ($Features -contains 'dispute')     { Apply-Dispute $target }
if ($Features -contains 'persuade')    { Apply-Persuade $target }
if ($Features -contains 'luck')        { Apply-Luck $target }
if ($Features -contains 'detail')     { Apply-Detail $target }
if ($Features -contains 'itemvalue') { Apply-ItemValue $target }
if ($Features -contains 'lairlink')   { Apply-Lairlink $target }
if ($Features -contains 'lootchest')  { Apply-Lootchest $target }
if ($Features -contains 'skills')     { Apply-Skills $target }
if ($Features -contains 'fief')       { Apply-Fief $target }
if ($Features -contains 'armyreward') { Apply-ArmyReward $target }
if ($Features -contains 'mentor')      { Apply-Mentor $target }
if ($Features -contains 'claim')      { Apply-Claim $target }
if ($Features -contains 'factionjoin') { Apply-FactionJoin $target }
if ($Features -contains 'swap')       { Apply-Swap $target }
if ($Features -contains 'taxexempt')  { Apply-TaxExempt $target }
if ($Features -contains 'nofiefgood') { Apply-NoFiefGood $target }
if ($Features -contains 'lua')        { Apply-Lua $target }
if ($Features -contains 'learnskill') { Apply-LearnSkill $target }
if ($Features -contains 'luck')      { Apply-LuckTrigger $target }
if ($Features -contains 'defeat')     { Apply-Defeat $target }
if ($Features -contains 'drill')      { Apply-Drill $target }
if ($Features -contains 'patrol')     { Apply-Patrol $target }
if ($Features -contains 'sortitems')  { Apply-SortItems $target }
if ($Features -contains 'cheatlang')  { Apply-CheatLang $target }

# 变量重排：宣称队列变量移到变量表末尾（其余变量索引与旧存档保持一致）
if ($Features -contains 'claim') { Finalize-ClaimVars $target }

# 3) 应用游戏参数（params.md 里填的）
Apply-Params $target

# 3) 模块名（GBK 写入 module.ini）
$ini = Join-Path $target 'module.ini'
$enc = [Text.Encoding]::GetEncoding(28591)
$iniText = $enc.GetString([IO.File]::ReadAllBytes($ini))
$gbk = [Text.Encoding]::GetEncoding(936)
$gbkAsLatin1 = $enc.GetString($gbk.GetBytes($DisplayName))
$iniText = [regex]::Replace($iniText, 'module_name = [^\r\n]*', 'module_name = ' + $gbkAsLatin1)
[IO.File]::WriteAllBytes($ini, $enc.GetBytes($iniText))
Write-Host "[i] 模块显示名: $DisplayName"

# 4) 校验
$sCnt = (Get-Content (Join-Path $target 'scripts.txt') -TotalCount 2)[1]
$mCnt = (Get-Content (Join-Path $target 'menus.txt') -TotalCount 2)[1]

# 4.1) 中文乱码自检：典型 GBK 误读 UTF-8 的字符，发现即中止（避免生成出乱码模块）
$badPattern = '[锛缁绱鎴浣鐨閿鍦绋闄銆绌鍐閲閬鎰剰鍚璇鎵澶鐢鍙杩闅浠鏄鐜鎻鍙鑰]'
foreach ($csvName in @('game_strings.csv', 'dialogs.csv', 'game_menus.csv')) {
    $csvPath = Join-Path $target ("languages\cns\" + $csvName)
    if (Test-Path $csvPath) {
        $csvText = [IO.File]::ReadAllText($csvPath, (New-Object Text.UTF8Encoding($false)))
        if ($csvText -match $badPattern) {
            throw "中文乱码自检失败：$csvName 里检测到 GBK 乱码字符，检查 patches 下对应中文补丁文件的编码（用 write 工具或 UTF-8 写入，别用 Get-Content 改）"
        }
    }
}

Write-Host ("[OK] 生成完成：scripts $sCnt 个，menus $mCnt 个")

# 5) 结构自检（防 OOM）：scripts/strings/menus/触发器数量与行数必须一致，脚本逐条按语句数+nargs 解析
$checker = Join-Path $PSScriptRoot 'check-module.ps1'
if (Test-Path $checker) {
    $checkOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $checker -ModuleDir $target 2>&1
    $checkOut | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw '模块结构自检失败（见上方 [X]），模块文件已写出但不要进游戏' }
}
