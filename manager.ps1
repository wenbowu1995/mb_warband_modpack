#Requires -Version 5.1
<#
  骑砍战团 · 增强模块生成器（GUI）

  从「纯净 Native」复制 → 按勾选（按组勾、组内功能一起生成）应用补丁 → 生成独立模块。
  功能分组定义在 features.psd1；生成逻辑全部在 build-module.ps1 里，这里只负责收参数、显示日志。
#>
param()

$ErrorActionPreference = 'Stop'

# 出错时留下日志，别让窗口一闪就没
trap {
    $msg = ($_ | Out-String) + "`r`n" + ($_.InvocationInfo.PositionMessage) + "`r`n" + $_.ScriptStackTrace
    $logPath = Join-Path $PSScriptRoot 'startup-error.txt'
    try { [IO.File]::WriteAllText($logPath, $msg) } catch {}
    Write-Host $msg
    exit 1
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$here = $PSScriptRoot
$buildScript = Join-Path $here 'build-module.ps1'
if (-not (Test-Path $buildScript)) {
[System.Windows.Forms.MessageBox]::Show("未找到 build-module.ps1。", '错误') | Out-Null
    exit 1
}

function Find-WarbandDir {
    $cands = New-Object System.Collections.Generic.List[string]
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $cands.Add((Join-Path $steam 'steamapps\common\MountBlade Warband'))
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw -Encoding UTF8), '"path"\s+"([^"]+)"')) {
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

$form = New-Object System.Windows.Forms.Form
$form.Text = '骑砍战团 · 增强模块生成器'
$form.Size = New-Object System.Drawing.Size(640, 828)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

# ---- 游戏目录 ----
$lbl1 = New-Object System.Windows.Forms.Label
$lbl1.Text = '游戏目录'
$lbl1.Location = New-Object System.Drawing.Point(16, 18)
$lbl1.AutoSize = $true
$form.Controls.Add($lbl1)

$txtGame = New-Object System.Windows.Forms.TextBox
$txtGame.Location = New-Object System.Drawing.Point(90, 15)
$txtGame.Size = New-Object System.Drawing.Size(430, 24)
$auto = Find-WarbandDir
if ($auto) { $txtGame.Text = $auto }
$form.Controls.Add($txtGame)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '浏览...'
$btnBrowse.Location = New-Object System.Drawing.Point(528, 14)
$btnBrowse.Size = New-Object System.Drawing.Size(80, 26)
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '选择 MountBlade Warband 安装目录'
    if ($dlg.ShowDialog() -eq 'OK') { $txtGame.Text = $dlg.SelectedPath }
})
$form.Controls.Add($btnBrowse)

# ---- 模块名 ----
$lbl2 = New-Object System.Windows.Forms.Label
$lbl2.Text = '模块文件夹'
$lbl2.Location = New-Object System.Drawing.Point(16, 52)
$lbl2.AutoSize = $true
$form.Controls.Add($lbl2)

$txtMod = New-Object System.Windows.Forms.TextBox
$txtMod.Location = New-Object System.Drawing.Point(90, 49)
$txtMod.Size = New-Object System.Drawing.Size(200, 24)
$txtMod.Text = 'Native-Enhanced'
$form.Controls.Add($txtMod)
$lbl2b = New-Object System.Windows.Forms.Label
$lbl2b.Text = '（英文，即 Modules 下的文件夹名）'
$lbl2b.ForeColor = [System.Drawing.Color]::Gray
$lbl2b.Location = New-Object System.Drawing.Point(296, 52)
$lbl2b.AutoSize = $true
$form.Controls.Add($lbl2b)

$lbl3 = New-Object System.Windows.Forms.Label
$lbl3.Text = '启动器显示名'
$lbl3.Location = New-Object System.Drawing.Point(16, 86)
$lbl3.AutoSize = $true
$form.Controls.Add($lbl3)

$txtDisp = New-Object System.Windows.Forms.TextBox
$txtDisp.Location = New-Object System.Drawing.Point(90, 83)
$txtDisp.Size = New-Object System.Drawing.Size(200, 24)
$txtDisp.Text = '原版增强'
$form.Controls.Add($txtDisp)

# ---- 功能（按组勾选：组内功能耦合，一个勾一起生成） ----
$specPath = Join-Path $here 'features.psd1'
if (-not (Test-Path $specPath)) {
    [System.Windows.Forms.MessageBox]::Show('未找到 features.psd1（功能分组定义）。', '错误') | Out-Null
    exit 1
}
$featureSpec = Import-PowerShellDataFile $specPath

$grp = New-Object System.Windows.Forms.GroupBox
$grp.Text = '包含的功能（每项一个勾，可多选；全选 = 全部 29 项）'
$grp.Location = New-Object System.Drawing.Point(16, 116)
$grp.Size = New-Object System.Drawing.Size(592, 404)
$form.Controls.Add($grp)

$panelFeat = New-Object System.Windows.Forms.Panel
$panelFeat.Location = New-Object System.Drawing.Point(8, 18)
$panelFeat.Size = New-Object System.Drawing.Size(576, 344)
$panelFeat.AutoScroll = $true
$grp.Controls.Add($panelFeat)

$tip = New-Object System.Windows.Forms.ToolTip
$chkList = New-Object System.Collections.Generic.List[object]
$chkByKey = @{}
$rowY = 2
foreach ($g in $featureSpec.Groups) {
    $chk = New-Object System.Windows.Forms.CheckBox
    $chk.Text = $g.Title
    $chk.Location = New-Object System.Drawing.Point(4, ($rowY + 8))
    $chk.Size = New-Object System.Drawing.Size(228, 24)
    $chk.Checked = $true
    $chk.Tag = $g.Key
    $panelFeat.Controls.Add($chk)
    $chkList.Add($chk)
    $chkByKey[$g.Key] = $chk

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $g.Desc
    $lbl.Location = New-Object System.Drawing.Point(238, ($rowY + 9))
    $lbl.Size = New-Object System.Drawing.Size(318, 34)
    $lbl.ForeColor = [System.Drawing.Color]::DimGray
    $panelFeat.Controls.Add($lbl)

    $tip.SetToolTip($chk, $g.Desc)
    $tip.SetToolTip($lbl, $g.Desc)
    $rowY += 44
}

function Get-SelectedFeatures {
    $feats = New-Object System.Collections.Generic.List[string]
    foreach ($g in $featureSpec.Groups) {
        $chk = $chkByKey[$g.Key]
        if ($chk -and $chk.Checked) {
            foreach ($f in $g.Features) { if (-not $feats.Contains($f)) { $feats.Add($f) } }
        }
    }
    # 必须返回字符串数组（ToArray）；返回 List 对象本身会在拼接 -Features 时变成类型名
    return $feats.ToArray()
}

$btnAll = New-Object System.Windows.Forms.Button
$btnAll.Text = '全选'
$btnAll.Location = New-Object System.Drawing.Point(8, 368)
$btnAll.Size = New-Object System.Drawing.Size(64, 26)
$grp.Controls.Add($btnAll)

$btnNone = New-Object System.Windows.Forms.Button
$btnNone.Text = '全不选'
$btnNone.Location = New-Object System.Drawing.Point(78, 368)
$btnNone.Size = New-Object System.Drawing.Size(64, 26)
$grp.Controls.Add($btnNone)

$lblPick = New-Object System.Windows.Forms.Label
$lblPick.Location = New-Object System.Drawing.Point(154, 374)
$lblPick.AutoSize = $true
$lblPick.ForeColor = [System.Drawing.Color]::DimGray
$grp.Controls.Add($lblPick)

function Update-FeatCount {
    $feats = Get-SelectedFeatures
    $groupCount = 0
    foreach ($g in $featureSpec.Groups) {
        $chk = $chkByKey[$g.Key]
        if ($chk -and $chk.Checked) { $groupCount++ }
    }
    $lblPick.Text = "已选 $groupCount 组 / $($feats.Count) 项功能"
    $btnBuild.Enabled = ($feats.Count -gt 0)
}

$btnAll.Add_Click({ foreach ($c in $chkList) { $c.Checked = $true }; Update-FeatCount })
$btnNone.Add_Click({ foreach ($c in $chkList) { $c.Checked = $false }; Update-FeatCount })
foreach ($c in $chkList) { $c.Add_Click({ Update-FeatCount }) }

# ---- 按钮 ----
$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = '生成模块'
$btnBuild.Location = New-Object System.Drawing.Point(16, 526)
$btnBuild.Size = New-Object System.Drawing.Size(120, 34)
$btnBuild.BackColor = [System.Drawing.Color]::FromArgb(220, 240, 220)
$form.Controls.Add($btnBuild)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(148, 534)
$lblStatus.Size = New-Object System.Drawing.Size(460, 22)
$lblStatus.Text = '勾选要包含的功能，点「生成模块」开始；原版 Native 不会被改动。'
$lblStatus.ForeColor = [System.Drawing.Color]::DimGray
$form.Controls.Add($lblStatus)

# ---- 日志 ----
$log = New-Object System.Windows.Forms.RichTextBox
$log.Location = New-Object System.Drawing.Point(16, 570)
$log.Size = New-Object System.Drawing.Size(592, 230)
$log.ReadOnly = $true
$log.Font = New-Object System.Drawing.Font('Consolas', 8.5)
$log.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
$form.Controls.Add($log)

function Add-Log([string]$s) {
    $log.AppendText($s + "`r`n")
    $log.SelectionStart = $log.Text.Length
    $log.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# ---- 生成 ----
$btnBuild.Add_Click({
    $game = $txtGame.Text.Trim()
    $mod = $txtMod.Text.Trim()
    $disp = $txtDisp.Text.Trim()
    if (-not $game -or -not (Test-Path (Join-Path $game 'mb_warband.exe'))) {
        [System.Windows.Forms.MessageBox]::Show('游戏目录无效：未找到 mb_warband.exe。', '提示') | Out-Null
        return
    }
    if (-not $mod -or $mod -notmatch '^[A-Za-z0-9_\-]+$') {
        [System.Windows.Forms.MessageBox]::Show('模块文件夹名只能包含英文字母、数字、下划线和连字符。', '提示') | Out-Null
        return
    }
    $feat = @(Get-SelectedFeatures)
    if ($feat.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('请至少勾选一个功能。', '提示') | Out-Null
        return
    }
    $running = Get-Process -Name 'mb_warband*', 'wse2*' -ErrorAction SilentlyContinue
    if ($running) {
        [System.Windows.Forms.MessageBox]::Show('游戏正在运行。请退出游戏后再生成。', '提示') | Out-Null
        return
    }
    $target = Join-Path $game "Modules\$mod"
    if (Test-Path $target) {
        $r = [System.Windows.Forms.MessageBox]::Show("模块已存在：`n$target`n`n继续将重新生成并替换旧模块，是否继续？", '确认', 'YesNo', 'Warning')
        if ($r -ne 'Yes') { return }
    }

    $btnBuild.Enabled = $false
    $lblStatus.Text = '正在生成（需复制约 80MB，请稍候）...'
    Add-Log "=== 开始生成 $(Get-Date -Format 'HH:mm:ss') ==="
    Add-Log "目标：$target"
    Add-Log "功能（$($feat.Count) 项）：$($feat -join ', ')"
    try {
        $psArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$buildScript,
                    '-GameDir',$game,'-ModuleName',$mod,'-DisplayName',$disp,
                    '-Features',($feat -join ','),'-Force')
        $out = & powershell @psArgs 2>&1
        foreach ($line in $out) { Add-Log "$line" }
        $ok = ($out -join "`n") -match '\[OK\] 生成完成'
        if ($ok) {
            $lblStatus.Text = '生成完成。请在启动器中选择「' + $disp + '」'
            Add-Log ''
            Add-Log '提示：在启动器中选择该模块；原版存档可复制到新模块的 Savegames 目录。'
            Add-Log '提示：换一组功能重新生成时，触发器数量会变，旧存档可能读不出来；建议换模块名或开新档。'
        } else {
            $lblStatus.Text = '生成失败，请查看日志'
        }
    } catch {
        Add-Log ("[X] " + $_.Exception.Message)
        $lblStatus.Text = '生成失败，请查看日志'
    } finally {
        Update-FeatCount
    }
})

Update-FeatCount
[void]$form.ShowDialog()
