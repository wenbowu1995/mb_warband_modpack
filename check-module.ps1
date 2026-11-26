#Requires -Version 5.1
<#
  骑砍战团模块数据文件校验（防 OOM 崩溃）

  用法：
    powershell -ExecutionPolicy Bypass -File check-module.ps1 -ModuleDir "D:\SteamLibrary\steamapps\common\MountBlade Warband\Modules\Native-Enhanced"

  重点校验 scripts.txt：每个脚本 2 行（名字行 + 体行），体行首 token 必须等于实际语句数，
  逐条按 opcode 的参数个数推进后必须正好读完。语句数/参数数错位就是 Loading scripts 时
  报 EXCEPTION_OUT_OF_MEMORY 的根因。
  其余文件校验数量行与实际条目数一致，另外扫一遍中文本地化的 GBK 乱码。
#>
param(
    [Parameter(Mandatory = $true)][string]$ModuleDir
)
$ErrorActionPreference = 'Stop'
$enc = [Text.Encoding]::GetEncoding(28591)
$fail = 0

function Report([bool]$ok, [string]$msg) {
    if ($ok) { Write-Host "[OK] $msg" }
    else { Write-Host "[X]  $msg"; $script:fail++ }
}

# 读文本，按 CRLF 分割，去掉末尾空项
function Read-Rows([string]$path) {
    $rows = [IO.File]::ReadAllText($path, $enc) -split "`r`n"
    while ($rows.Count -ge 1 -and $rows[$rows.Count - 1] -eq '') { $rows = @($rows[0..($rows.Count - 2)]) }
    return , $rows
}

function Check-Scripts([string]$dir) {
    $p = Join-Path $dir 'scripts.txt'
    $rows = Read-Rows $p
    $n = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { Report $false 'scripts.txt 第 2 行不是脚本数量'; return }
    Report ($rows.Count -eq (2 + 2 * $n)) "scripts.txt：行数 $($rows.Count)，应为 $((2 + 2 * $n))（脚本 $n 个）"
    if ($rows.Count -ne (2 + 2 * $n)) { return }
    $bad = 0
    for ($i = 2; $i -lt $rows.Count; $i += 2) {
        $name = $rows[$i]
        $body = $rows[$i + 1]
        if ($name -eq '' -or $body -eq '') { $bad++; Write-Host "  [X] 第 $i 行：脚本名或体为空。"; continue }
        $t = $body.Trim().Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
        $decl = 0
        if (-not [int]::TryParse($t[0], [ref]$decl)) { $bad++; Write-Host "  [X] $name：体行首 token 不是语句数。"; continue }
        $pos = 1; $cnt = 0; $ok = $true
        while ($pos -lt $t.Count) {
            if ($pos + 1 -ge $t.Count) { $ok = $false; break }
            $na = 0
            if (-not [int]::TryParse($t[$pos + 1], [ref]$na)) { $ok = $false; break }
            $pos = $pos + 2 + $na
            $cnt++
        }
        if (-not $ok -or $pos -ne $t.Count -or $cnt -ne $decl) {
            $bad++
            Write-Host "  [X] $name：声明 $decl 条，实际 $cnt 条，token 停在 $pos/$($t.Count)。"
        }
    }
    Report ($bad -eq 0) "scripts.txt 逐脚本解析（$n 个，异常 $bad）"
}

function Check-Strings([string]$dir) {
    $p = Join-Path $dir 'strings.txt'
    $rows = Read-Rows $p
    $n = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { Report $false 'strings.txt 第 2 行不是字符串数量'; return }
    Report ($rows.Count -eq (2 + $n)) "strings.txt：行数 $($rows.Count)，应为 $((2 + $n))"
}

function Check-Trigs([string]$dir) {
    $p = Join-Path $dir 'simple_triggers.txt'
    $rows = Read-Rows $p
    $n = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { Report $false 'simple_triggers.txt 第 2 行不是数量'; return }
    Report ($rows.Count -eq (2 + $n)) "simple_triggers.txt：行数 $($rows.Count)，应为 $((2 + $n))"
}

function Check-Menus([string]$dir) {
    $p = Join-Path $dir 'menus.txt'
    $rows = Read-Rows $p
    $n = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { Report $false 'menus.txt 第 2 行不是菜单数量'; return }
    $menuRows = @($rows | Where-Object { $_ -match '^menu_' })
    Report ($menuRows.Count -eq $n) "menus.txt：菜单 $($menuRows.Count) 个，应为 $n 个"
}

function Check-Vars([string]$dir) {
    $p = Join-Path $dir 'variables.txt'
    $rows = Read-Rows $p
    $empty = @($rows | Where-Object { $_.Trim() -eq '' })
    Report ($empty.Count -eq 0) "variables.txt：变量 $($rows.Count) 个，空行 $($empty.Count) 个"
}

function Check-Csv([string]$dir) {
    $badPattern = '[锛缁绱鎴浣鐨閿鍦绋闄銆绌鍐閲閬鎰剰鍚璇鎵澶鐢鍙杩闅浠鏄鐜鎻鍙鑰]'
    foreach ($csv in @('game_strings.csv', 'game_menus.csv', 'dialogs.csv', 'skills.csv')) {
        $p = Join-Path $dir ("languages\cns\" + $csv)
        if (-not (Test-Path $p)) { continue }
        $t = [IO.File]::ReadAllText($p, [Text.Encoding]::UTF8)
        Report (-not ($t -match $badPattern)) "languages\cns\$csv：无 GBK 乱码"
    }
}

# 引用索引越界检查：数据文件里的 tag（脚本/菜单/字符串/变量/快速字符串）索引必须落在目标模块的数量内。
# 拆分生成（只勾一部分功能）最容易在这一步出错：新增的菜单/脚本/字符串 ID 按错误的数量算，进游戏后
# 指向别的对象或越界崩溃。这里把所有 .txt 里 15~19 位的大整数按基址归类，逐个对数量。
function Get-CountLine([string]$path, [int]$lineIndex) {
    if (-not (Test-Path $path)) { return 0 }
    $rows = Read-Rows $path
    $n = 0
    if ($rows.Count -gt $lineIndex -and [int]::TryParse($rows[$lineIndex].Trim(), [ref]$n)) { return $n }
    return 0
}

function Check-Refs([string]$dir) {
    $varRows = Read-Rows (Join-Path $dir 'variables.txt')
    $counts = [ordered]@{
        script       = (Get-CountLine (Join-Path $dir 'scripts.txt') 1)
        menu         = (Get-CountLine (Join-Path $dir 'menus.txt') 1)
        string       = (Get-CountLine (Join-Path $dir 'strings.txt') 1)
        variable     = $varRows.Count
        quick_string = (Get-CountLine (Join-Path $dir 'quick_strings.txt') 0)
    }
    $bases = [ordered]@{
        script       = [uint64]936748722493063168
        menu         = [uint64]864691128455135232
        string       = [uint64]216172782113783808
        variable     = [uint64]144115188075855872
        quick_string = [uint64]1585267068834414592
    }
    $bad = 0
    foreach ($f in Get-ChildItem $dir -Filter '*.txt' -File) {
        $text = [IO.File]::ReadAllText($f.FullName, $enc)
        foreach ($m in [regex]::Matches($text, '\b\d{15,19}\b')) {
            $v = [uint64]$m.Value
            foreach ($k in @('script', 'menu', 'string', 'variable', 'quick_string')) {
                $b = $bases[$k]
                if ($v -ge $b -and $v -lt ($b + [uint64]1000000)) {
                    $idx = $v - $b
                    if ($idx -ge [uint64]$counts[$k]) {
                        $bad++
                        Write-Host ("  [X] {0}：{1} 引用越界（index {2} ≥ 数量 {3}）" -f $f.Name, $k, $idx, $counts[$k])
                    }
                }
            }
        }
    }
    Report ($bad -eq 0) "引用索引：脚本/菜单/字符串/变量/快速字符串 tag 均未越界（异常 $bad）"
}

# conversation.txt 每行的条件/执行块是「语句列表」，每条语句 = opcode + nargs + 参数。
# 只数行数不够：漏写 opcode 会让 nargs 变成大整数，进游戏 Loading conversations 报 Unexpected End of File。
function Check-Conversation([string]$dir) {
    $p = Join-Path $dir 'conversation.txt'
    $rows = Read-Rows $p
    $n = 0
    if (-not [int]::TryParse($rows[1].Trim(), [ref]$n)) { Report $false 'conversation.txt 第 2 行不是对话数量'; return }
    Report ($rows.Count -eq (2 + $n)) "conversation.txt：行数 $($rows.Count)，应为 $((2 + $n))（对话 $n 条）"
    if ($rows.Count -ne (2 + $n)) { return }
    $bad = 0
    for ($i = 2; $i -lt $rows.Count; $i++) {
        $line = $rows[$i]
        if ($line.Trim() -eq '') { $bad++; Write-Host "  [X] 第 $i 行：空行"; continue }
        $t = @($line.Trim() -split '\s+' | Where-Object { $_ -ne '' })
        if ($t.Count -lt 6) { $bad++; Write-Host "  [X] 第 $i 行：字段不足"; continue }
        $pos = 4
        $cond = 0
        if (-not [int]::TryParse($t[3], [ref]$cond)) { $bad++; Write-Host "  [X] 第 $i 行（$($t[0])）：条件块数不是整数"; continue }
        $ok = $true
        for ($k = 0; $k -lt $cond; $k++) {
            $na = 0
            if ($pos + 1 -ge $t.Count -or -not [int]::TryParse($t[$pos + 1], [ref]$na)) { $ok = $false; break }
            $pos = $pos + 2 + $na
        }
        if (-not $ok -or $pos -ge $t.Count) { $bad++; Write-Host "  [X] 第 $i 行（$($t[0])）：条件块越界"; continue }
        $pos++   # 对话文本
        $pos++   # 结束状态
        $exec = 0
        if ($pos -ge $t.Count -or -not [int]::TryParse($t[$pos], [ref]$exec)) { $bad++; Write-Host "  [X] 第 $i 行（$($t[0])）：执行块数不是整数"; continue }
        $pos++
        for ($k = 0; $k -lt $exec; $k++) {
            $na = 0
            if ($pos + 1 -ge $t.Count -or -not [int]::TryParse($t[$pos + 1], [ref]$na)) { $ok = $false; break }
            $pos = $pos + 2 + $na
        }
        # 末尾允许 1 个 voiceover 占位（NO_VOICEOVER 或空）
        if (-not $ok -or $pos -gt $t.Count -or ($t.Count - $pos) -gt 1) {
            $bad++
            Write-Host "  [X] 第 $i 行（$($t[0])）：执行块越界或行尾多余字段（token $pos/$($t.Count)）"
        }
    }
    Report ($bad -eq 0) "conversation.txt 逐行解析（$n 条，异常 $bad）"
}

Write-Host "校验模块：$ModuleDir"
Check-Scripts $ModuleDir
Check-Conversation $ModuleDir
Check-Strings $ModuleDir
Check-Trigs $ModuleDir
Check-Menus $ModuleDir
Check-Vars $ModuleDir
Check-Csv $ModuleDir
Check-Refs $ModuleDir
if ($fail -gt 0) {
    Write-Host "`n[X] 共 $fail 项未通过。修好之前不要进游戏。"
    exit 1
}
Write-Host "`n[OK] 全部通过。"
