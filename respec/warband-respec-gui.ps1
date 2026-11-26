#Requires -Version 5.1
<#
 骑砍战团 · 同伴洗点工具（GUI）
 - 自动扫描存档定位 16 个同伴（不写死偏移）
 - 每个同伴在存档里有两份记录（ns=256 领主版 + ns=0 当前版），两份一起改
 - 可勾选单个/多个同伴，可只洗属性或只洗技能
 - 执行前自动备份
#>
param(
    [string]$SavePath,
    [switch]$Silent,
    [switch]$Apply,
    [switch]$OnlyAttr,
    [switch]$OnlySkill
)

$ErrorActionPreference = 'Stop'

# ============ 内置招募基线（可读副本：本目录 npc-baseline.xlsx） ============
# 数据来自原版 Native 16 名同伴的招募瞬间数值；改基线要同步改这里和 npc-baseline.xlsx
# 顺序 = troops.txt 中 npc1..npc16
$script:Base = @(
    @{ name='波尔查';  lvl=3;  attr=@(8,7,12,7);   sk=@{36=1;35=1;27=1;25=2;24=2;16=3;14=3;13=2;12=2} }
    @{ name='马尼德';  lvl=1;  attr=@(7,7,11,6);   sk=@{36=1;27=1;25=2;24=2;12=3;11=1;9=1;1=1;0=3} }
    @{ name='雅米拉';  lvl=1;  attr=@(6,9,11,6);   sk=@{25=1;24=3;12=3;11=1;10=1;9=3;0=3} }
    @{ name='罗尔夫';  lvl=10; attr=@(10,9,13,10); sk=@{36=1;35=2;34=2;27=2;26=1;25=3;24=2;15=2;12=2;10=1;9=1;1=2} }
    @{ name='贝克图尔';lvl=5;  attr=@(9,9,12,7);   sk=@{36=1;35=2;33=3;27=3;26=1;25=1;24=2;23=3;12=2;1=2} }
    @{ name='法提斯';  lvl=6;  attr=@(10,12,10,5); sk=@{36=1;35=2;27=2;26=1;25=3;24=2;17=1;12=2;1=1} }
    @{ name='德赛维';  lvl=2;  attr=@(8,9,10,6);   sk=@{36=1;33=2;27=1;25=2;16=2;14=3;13=3;12=2} }
    @{ name='马蒂尔德';lvl=7;  attr=@(9,10,9,10);  sk=@{36=1;35=2;27=3;26=1;25=3;24=2;15=1;12=2;1=3} }
    @{ name='艾雷恩';  lvl=2;  attr=@(11,8,7,8);   sk=@{36=1;35=3;27=3;26=1;25=1;24=3;15=1;12=2;1=1} }
    @{ name='班达克';  lvl=9;  attr=@(12,8,9,11);  sk=@{36=3;35=2;27=3;26=1;25=1;24=2;17=2;15=1;12=2;9=2;1=1} }
    @{ name='凯特琳';  lvl=8;  attr=@(8,11,10,10); sk=@{36=3;27=1;24=2;12=7;10=1;0=3} }
    @{ name='杰姆斯';  lvl=4;  attr=@(8,7,13,7);   sk=@{36=1;35=1;24=2;12=3;11=3;10=4;9=3;0=3} }
    @{ name='尼扎';    lvl=3;  attr=@(7,7,12,8);   sk=@{36=3;35=3;27=3;26=1;25=3;24=2;12=2;1=2} }
    @{ name='雷萨里特';lvl=5;  attr=@(9,8,11,8);   sk=@{36=1;35=3;27=3;26=1;25=1;24=2;17=4;12=2;1=2} }
    @{ name='亚提曼';  lvl=7;  attr=@(9,9,12,8);   sk=@{36=1;35=2;27=2;26=1;25=1;24=2;16=1;15=2;13=1;12=2;8=4;0=3} }
    @{ name='克雷斯';  lvl=2;  attr=@(7,11,8,7);   sk=@{36=1;35=1;34=3;27=1;25=2;16=2;14=2;13=2;12=2} }
)

# ============ C# 核心：扫描与写回 ============
$cs = @'
using System;
using System.Collections.Generic;
using System.Text;

public class Rec {
    public int Start, NumSlots, AttrPos, SkOff, Level, SP, AP, PP;
    public int[] Attrs = new int[4];
    public int[] Skills = new int[48];
}

public static class RParser {
    public const ulong TF_HERO = 0x10000000UL;

    public static Rec TryParse(byte[] b, int pos) {
        int n = b.Length;
        if (pos < 0 || pos + 80 > n) return null;
        int ns = BitConverter.ToInt32(b, pos);
        if (ns < 0 || ns > 300) return null;
        int q = pos + 4 + ns * 8;
        if (q + 44 > n) return null;
        int[] at = new int[4];
        int sum = 0;
        for (int i = 0; i < 4; i++) {
            at[i] = BitConverter.ToInt32(b, q + 4 * i);
            if (at[i] < 1 || at[i] > 80) return null;
            sum += at[i];
        }
        if (sum > 300) return null;
        q += 16;
        for (int i = 0; i < 7; i++) {
            float f = BitConverter.ToSingle(b, q + 4 * i);
            if (f < 0f || f >= 1000f) return null;
        }
        q += 28;
        int skOff = q;
        int[] sk = new int[48];
        for (int k = 0; k < 24; k++) {
            sk[k * 2] = b[q + k] & 0xF;
            sk[k * 2 + 1] = (b[q + k] >> 4) & 0xF;
        }
        q += 24;
        for (int i = 0; i < 16; i++) {
            if (q + 4 > n) return null;
            int ln = BitConverter.ToInt32(b, q);
            if (ln < 0 || ln > 3000) return null;
            q += 4 + ln + 4 + 4 + 1;
            if (q > n) return null;
        }
        if (q + 24 > n) return null;
        ulong flags = BitConverter.ToUInt64(b, q);
        if ((flags & TF_HERO) == 0) return null;
        q += 8 + 4;
        if (q + 16 > n) return null;
        int sp = BitConverter.ToInt32(b, q); q += 4;
        int ap = BitConverter.ToInt32(b, q); q += 4;
        int pp = BitConverter.ToInt32(b, q); q += 4;
        int lv = BitConverter.ToInt32(b, q); q += 4;
        if (lv < 1 || lv > 60) return null;
        if (sp < 0 || sp > 300 || ap < 0 || ap > 300) return null;
        Rec r = new Rec();
        r.Start = pos; r.NumSlots = ns; r.AttrPos = pos + 4 + ns * 8;
        r.SkOff = skOff; r.Attrs = at; r.Skills = sk;
        r.SP = sp; r.AP = ap; r.PP = pp; r.Level = lv;
        return r;
    }

    public static List<Rec> Scan(byte[] b) {
        List<Rec> list = new List<Rec>();
        int n = b.Length;
        for (int pos = 0; pos + 80 < n; pos++) {
            Rec r = TryParse(b, pos);
            if (r != null) { list.Add(r); pos += 3; }
        }
        list.Sort((x, y) => x.Start.CompareTo(y.Start));
        return list;
    }

    // 找连续 16 对（32 条）的同伴簇：每对 = ns>0 的主记录 + ns==0 的当前记录
    public static List<List<Rec>> FindCompanionPairs(byte[] b) {
        List<Rec> all = Scan(b);
        List<List<Rec>> pairs = new List<List<Rec>>();
        List<Rec> cur = new List<Rec>();
        for (int i = 0; i < all.Count; i++) {
            cur.Add(all[i]);
        }
        // 先按"相邻间隔<4000"聚簇
        List<List<Rec>> clusters = new List<List<Rec>>();
        List<Rec> c = new List<Rec>();
        for (int i = 0; i < all.Count; i++) {
            if (c.Count == 0) { c.Add(all[i]); continue; }
            if (all[i].Start - c[c.Count - 1].Start < 4000) c.Add(all[i]);
            else { clusters.Add(c); c = new List<Rec>(); c.Add(all[i]); }
        }
        if (c.Count > 0) clusters.Add(c);

        // 取长度最接近 32 的簇，两两配对
        List<Rec> best = null;
        foreach (List<Rec> cl in clusters) {
            if (cl.Count < 2) continue;
            if (best == null || Math.Abs(cl.Count - 32) < Math.Abs(best.Count - 32)) best = cl;
        }
        if (best == null) return pairs;
        for (int i = 0; i + 1 < best.Count; i += 2) {
            List<Rec> p = new List<Rec>();
            p.Add(best[i]); p.Add(best[i + 1]);
            pairs.Add(p);
        }
        return pairs;
    }

    public static void WriteAttrs(byte[] b, Rec r, int[] attr, int newAP) {
        for (int i = 0; i < 4; i++) {
            byte[] t = BitConverter.GetBytes(attr[i]);
            Array.Copy(t, 0, b, r.AttrPos + 4 * i, 4);
        }
        byte[] ap = BitConverter.GetBytes(newAP);
        Array.Copy(ap, 0, b, r.AttrPos + 292, 4);
    }

    public static void WriteSkills(byte[] b, Rec r, int[] sk42, int newSP) {
        byte[] raw = new byte[24];
        Array.Copy(b, r.SkOff, raw, 0, 24);
        for (int sid = 0; sid < 42; sid++) {
            int v = sk42[sid] & 0xF;
            int bi = sid / 2;
            if (sid % 2 == 0) raw[bi] = (byte)((raw[bi] & 0xF0) | v);
            else raw[bi] = (byte)((raw[bi] & 0x0F) | (v << 4));
        }
        Array.Copy(raw, 0, b, r.SkOff, 24);
        byte[] sp = BitConverter.GetBytes(newSP);
        Array.Copy(sp, 0, b, r.AttrPos + 288, 4);
    }
}
'@

Add-Type -TypeDefinition $cs -Language CSharp

# ============ 定位存档 ============
function Find-SaveDir {
    $cands = New-Object System.Collections.Generic.List[string]
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ($docs) {
        $cands.Add((Join-Path $docs 'Mount&Blade Warband WSE2\Native\Savegames'))
        $cands.Add((Join-Path $docs 'Mount&Blade Warband\Native\Savegames'))
    }
    foreach ($p in @(
        'E:\Users\Administrator\Documents\Mount&Blade Warband WSE2\Native\Savegames'
    )) { $cands.Add($p) }
    foreach ($c in $cands) { if (Test-Path $c) { return $c } }
    return $null
}

function Read-Header([byte[]]$b) {
    $pos = 12
    $len = [BitConverter]::ToInt32($b, $pos); $pos += 4
    $saveName = [Text.Encoding]::UTF8.GetString($b, $pos, $len); $pos += $len
    $len2 = [BitConverter]::ToInt32($b, $pos); $pos += 4
    $player = [Text.Encoding]::UTF8.GetString($b, $pos, $len2); $pos += $len2
    $lvl = [BitConverter]::ToInt32($b, $pos)
    return @{ SaveName = $saveName; Player = $player; Level = $lvl }
}

# ============ 主逻辑 ============
if (-not $SavePath) {
    $dir = Find-SaveDir
    if (-not $dir) {
        Write-Host '未找到存档目录，请用 -SavePath 指定 .sav 文件。'
        exit 1
    }
    $saves = Get-ChildItem $dir -Filter '*.sav' | Sort-Object LastWriteTime -Descending
    if (-not $saves) { Write-Host '存档目录中没有 .sav 文件。'; exit 1 }
    $SavePath = $saves[0].FullName
}

if (-not (Test-Path $SavePath)) { Write-Host "存档不存在：$SavePath"; exit 1 }

function Parse-Save([string]$path) {
    if (-not (Test-Path $path)) { throw "存档不存在：$path" }
    $b = [IO.File]::ReadAllBytes($path)
    $h = Read-Header $b
    $pr = [RParser]::FindCompanionPairs($b)
    if ($pr.Count -eq 0) { throw '未能识别出同伴记录（可能不是战团 Native 存档）。' }
    $rs = @()
    for ($i = 0; $i -lt $pr.Count -and $i -lt $script:Base.Count; $i++) {
        $p = $pr[$i]
        $main = $p[0]                 # ns>0 主记录
        $cur = if ($p[1].NumSlots -eq 0) { $p[1] } else { $p[0] }
        $b0 = $script:Base[$i]
        $attrSum = ($cur.Attrs | Measure-Object -Sum).Sum
        $baseSum = ($b0.attr | Measure-Object -Sum).Sum
        $skSum = 0; for ($s = 0; $s -lt 42; $s++) { $skSum += $cur.Skills[$s] }
        $rs += [pscustomobject]@{
            Index      = $i
            Name       = $b0.name
            Level      = $cur.Level
            Attrs      = ($cur.Attrs -join '/')
            AttrGain   = ($attrSum - $baseSum)
            SkillSum   = $skSum
            SkillGain  = ($cur.Level - $b0.lvl)
            MainStart  = $main.Start
            CurStart   = $cur.Start
            CurAP      = $cur.AP
            CurSP      = $cur.SP
            RecMain    = $main
            RecCur     = $cur
        }
    }
    return @{ Path = $path; Bytes = $b; Header = $h; Pairs = $pr; Rows = $rs }
}

$state = Parse-Save $SavePath
$bytes = $state.Bytes
$hdr   = $state.Header
$pairs = $state.Pairs
$rows  = $state.Rows

# 在子进程里跑：-Silent 只打印结果（供命令行验证）
if ($Silent) {
    Write-Host ("存档：{0}  主角：{1} L{2}" -f (Split-Path $SavePath -Leaf), $hdr.Player, $hdr.Level)
    Write-Host ("识别同伴：{0} 个" -f $rows.Count)
    $rows | Format-Table Name, Level, Attrs, AttrGain, SkillSum, SkillGain, CurAP, CurSP -AutoSize | Out-String -Width 120 | Write-Host
    exit 0
}

# 无界面执行（用于测试/脚本化）：-Apply [-OnlyAttr | -OnlySkill]
if ($Apply) {
    $g = Get-Process -Name 'mb_warband*','wse2*' -ErrorAction SilentlyContinue
    if ($g) { Write-Host '游戏正在运行，拒绝执行。'; exit 1 }
    $doAttr = -not $OnlySkill
    $doSkill = -not $OnlyAttr
    if (-not $doAttr -and -not $doSkill) { Write-Host '未指定要重置的内容。'; exit 1 }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bk = Join-Path (Split-Path $script:SavePath -Parent) ("_respec_backup_" + (Split-Path $script:SavePath -Leaf) + "." + $stamp)
    Copy-Item $SavePath $bk -Force
    $buf = [IO.File]::ReadAllBytes($SavePath)
    $done = 0
    foreach ($t in $rows) {
        $b0 = $script:Base[$t.Index]
        $recs = @($t.RecCur, $t.RecMain)
        if ($doAttr) {
            $baseSum = ($b0.attr | Measure-Object -Sum).Sum
            foreach ($rec in $recs) {
                $curSum = ($rec.Attrs | Measure-Object -Sum).Sum
                [RParser]::WriteAttrs($buf, $rec, $b0.attr, ($rec.AP + ($curSum - $baseSum)))
            }
        }
        if ($doSkill) {
            $vec = New-Object 'int[]' 42
            foreach ($k in $b0.sk.Keys) { $vec[$k] = $b0.sk[$k] }
            $skBase = ($b0.sk.Values | Measure-Object -Sum).Sum
            foreach ($rec in $recs) {
                $curSk = 0
                for ($s = 0; $s -lt 42; $s++) { $curSk += $rec.Skills[$s] }
                [RParser]::WriteSkills($buf, $rec, $vec, ($rec.SP + ($curSk - $skBase)))
            }
        }
        $done += 1
    }
    [IO.File]::WriteAllBytes($SavePath, $buf)
    Write-Host ("完成：{0} 个同伴  属性={1} 技能={2}" -f $done, $doAttr, $doSkill)
    Write-Host ("备份：{0}" -f $bk)
    exit 0
}

# ============ WinForms UI ============
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object Windows.Forms.Form
$form.Text = '骑砍战团 · 同伴洗点'
$form.Size = New-Object Drawing.Size(920, 620)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Microsoft YaHei UI', 9)

$top = New-Object Windows.Forms.Panel
$top.Dock = 'Top'
$top.Height = 56
$form.Controls.Add($top)

$lblSave = New-Object Windows.Forms.Label
$lblSave.AutoSize = $true
$lblSave.Location = New-Object Drawing.Point(12, 10)
$lblSave.Text = ("存档：{0}   主角：{1} L{2}" -f (Split-Path $SavePath -Leaf), $hdr.Player, $hdr.Level)
$top.Controls.Add($lblSave)

$lblHint = New-Object Windows.Forms.Label
$lblHint.AutoSize = $true
$lblHint.Location = New-Object Drawing.Point(12, 32)
$lblHint.ForeColor = [Drawing.Color]::DimGray
$lblHint.Text = "勾选同伴 → 勾选要重置的项目 → 点「执行洗点」（自动备份，需先退出游戏）"
$top.Controls.Add($lblHint)

$btnPick = New-Object Windows.Forms.Button
$btnPick.Text = '选择存档...'
$btnPick.Size = New-Object Drawing.Size(100, 26)
$btnPick.Anchor = ([Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right)
$btnPick.Location = New-Object Drawing.Point(($top.Width - 112), 8)
$top.Controls.Add($btnPick)

$btnReload = New-Object Windows.Forms.Button
$btnReload.Text = '刷新'
$btnReload.Size = New-Object Drawing.Size(64, 26)
$btnReload.Anchor = ([Windows.Forms.AnchorStyles]::Top -bor [Windows.Forms.AnchorStyles]::Right)
$btnReload.Location = New-Object Drawing.Point(($top.Width - 182), 8)
$top.Controls.Add($btnReload)

$grid = New-Object Windows.Forms.DataGridView
$grid.Dock = 'Fill'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.AutoSizeColumnsMode = 'Fill'
$grid.ScrollBars = 'Both'
$grid.ColumnHeadersVisible = $true
$grid.ColumnHeadersHeightSizeMode = 'AutoSize'
$grid.BackgroundColor = [Drawing.Color]::White
$form.Controls.Add($grid)

$cSel = New-Object Windows.Forms.DataGridViewCheckBoxColumn
$cSel.Name = 'Sel'; $cSel.HeaderText = '洗'; $cSel.FillWeight = 8
$grid.Columns.Add($cSel) | Out-Null
foreach ($c in @(
    @{n='Name';   h='同伴';     w=14},
    @{n='Level';  h='等级';     w=8},
    @{n='Attrs';  h='当前四维';  w=18},
    @{n='AttrGain'; h='可洗属性点'; w=14},
    @{n='SkillSum'; h='技能和';   w=10},
    @{n='SkillGain'; h='可洗技能点'; w=14},
    @{n='CurAP';  h='现有属性点'; w=13},
    @{n='CurSP';  h='现有技能点'; w=13}
)) {
    $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
    $col.Name = $c.n; $col.HeaderText = $c.h; $col.FillWeight = $c.w
    $col.ReadOnly = $true
    $grid.Columns.Add($col) | Out-Null
}

foreach ($r in $rows) {
    $idx = $grid.Rows.Add()
    $grid.Rows[$idx].Cells['Sel'].Value = $false
    foreach ($f in @('Name','Level','Attrs','AttrGain','SkillSum','SkillGain','CurAP','CurSP')) {
        $grid.Rows[$idx].Cells[$f].Value = $r.$f
    }
}

$bottom = New-Object Windows.Forms.Panel
$bottom.Dock = 'Bottom'
$bottom.Height = 96
$form.Controls.Add($bottom)

$chkAttr = New-Object Windows.Forms.CheckBox
$chkAttr.Text = '洗属性'
$chkAttr.Checked = $true
$chkAttr.AutoSize = $true
$chkAttr.Location = New-Object Drawing.Point(12, 12)
$bottom.Controls.Add($chkAttr)

$chkSkill = New-Object Windows.Forms.CheckBox
$chkSkill.Text = '洗技能'
$chkSkill.Checked = $true
$chkSkill.AutoSize = $true
$chkSkill.Location = New-Object Drawing.Point(110, 12)
$bottom.Controls.Add($chkSkill)

$btnAll = New-Object Windows.Forms.Button
$btnAll.Text = '全选'
$btnAll.Location = New-Object Drawing.Point(220, 10)
$btnAll.Size = New-Object Drawing.Size(70, 26)
$bottom.Controls.Add($btnAll)

$btnNone = New-Object Windows.Forms.Button
$btnNone.Text = '全不选'
$btnNone.Location = New-Object Drawing.Point(298, 10)
$btnNone.Size = New-Object Drawing.Size(70, 26)
$bottom.Controls.Add($btnNone)

$btnRun = New-Object Windows.Forms.Button
$btnRun.Text = '执行洗点'
$btnRun.Location = New-Object Drawing.Point(700, 8)
$btnRun.Size = New-Object Drawing.Size(190, 32)
$btnRun.BackColor = [Drawing.Color]::FromArgb(0, 120, 215)
$btnRun.ForeColor = [Drawing.Color]::White
$btnRun.FlatStyle = 'Flat'
$bottom.Controls.Add($btnRun)

$status = New-Object Windows.Forms.Label
$status.AutoSize = $false
$status.Location = New-Object Drawing.Point(12, 50)
$status.Size = New-Object Drawing.Size(870, 40)
$status.Text = '就绪'
$bottom.Controls.Add($status)

$btnAll.Add_Click({
    foreach ($r in $grid.Rows) { $r.Cells['Sel'].Value = $true }
})
$btnNone.Add_Click({
    foreach ($r in $grid.Rows) { $r.Cells['Sel'].Value = $false }
})

$btnRun.Add_Click({
    $btnRun.Enabled = $false
    try {
        $running = Get-Process -Name 'mb_warband*','wse2*' -ErrorAction SilentlyContinue
        if ($running) {
            [Windows.Forms.MessageBox]::Show('游戏正在运行，请先退出游戏再执行。', '无法执行', 'OK', 'Warning') | Out-Null
            return
        }
        $doAttr  = $chkAttr.Checked
        $doSkill = $chkSkill.Checked
        if (-not $doAttr -and -not $doSkill) {
            [Windows.Forms.MessageBox]::Show('至少勾选「洗属性」或「洗技能」。', '提示', 'OK', 'Information') | Out-Null
            return
        }
        $targets = @()
        for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
            $cell = $grid.Rows[$i].Cells['Sel']
            if ($cell.Value -eq $true -or "$($cell.Value)" -eq 'True') { $targets += $script:rows[$i] }
        }
        if ($targets.Count -eq 0) {
            [Windows.Forms.MessageBox]::Show('未勾选任何同伴。', '提示', 'OK', 'Information') | Out-Null
            return
        }
        $ans = [Windows.Forms.MessageBox]::Show(
            ("将重置 {0} 个同伴（{1}{2}）。会先自动备份，是否继续？" -f $targets.Count,
             $(if($doAttr){'属性 '}else{''}), $(if($doSkill){'技能'}else{''})),
            '确认', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }

        # 备份
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $bk = Join-Path (Split-Path $script:SavePath -Parent) ("_respec_backup_" + (Split-Path $script:SavePath -Leaf) + "." + $stamp)
        Copy-Item $script:SavePath $bk -Force

        $buf = [IO.File]::ReadAllBytes($script:SavePath)
        $done = 0
        foreach ($t in $targets) {
            $b0 = $script:Base[$t.Index]
            $recs = @($t.RecCur, $t.RecMain)
            if ($doAttr) {
                $baseSum = ($b0.attr | Measure-Object -Sum).Sum
                foreach ($rec in $recs) {
                    $curSum = ($rec.Attrs | Measure-Object -Sum).Sum
                    $gain = $curSum - $baseSum
                    $newAP = $rec.AP + $gain
                    [RParser]::WriteAttrs($buf, $rec, $b0.attr, $newAP)
                }
            }
            if ($doSkill) {
                $vec = New-Object 'int[]' 42
                foreach ($k in $b0.sk.Keys) { $vec[$k] = $b0.sk[$k] }
                $skBase = ($b0.sk.Values | Measure-Object -Sum).Sum
                foreach ($rec in $recs) {
                    $curSk = 0
                    for ($s = 0; $s -lt 42; $s++) { $curSk += $rec.Skills[$s] }
                    [RParser]::WriteSkills($buf, $rec, $vec, ($rec.SP + ($curSk - $skBase)))
                }
            }
            $done += 1
        }
        [IO.File]::WriteAllBytes($script:SavePath, $buf)
        $status.Text = ("已完成 {0} 个同伴。备份：{1}" -f $done, (Split-Path $bk -Leaf))
        [Windows.Forms.MessageBox]::Show(
            ("完成，已处理 {0} 个同伴。`r`n备份文件：{1}" -f $done, $bk),
            '成功', 'OK', 'Information') | Out-Null
    } catch {
        $status.Text = '出错：' + $_.Exception.Message
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, '出错', 'OK', 'Error') | Out-Null
    } finally {
        $btnRun.Enabled = $true
    }
})

# ---- 修正 Dock 布局顺序 ----
# WinForms 按 Controls 索引逆序排布：Fill 控件必须最后排（索引最小），
# 否则它会先占满整个客户区，把 Dock=Top/Bottom 的面板压住（表头被顶部面板盖住就是这个原因）
$form.Controls.Clear()
$form.Controls.Add($grid)     # Fill —— 最后填充剩余空间
$form.Controls.Add($top)      # Top
$form.Controls.Add($bottom)   # Bottom

# ---- 切换/重载存档 ----
function Update-FromSave([string]$path) {
    $st = Parse-Save $path
    $script:SavePath = $path
    $script:bytes    = $st.Bytes
    $script:hdr      = $st.Header
    $script:pairs    = $st.Pairs
    $script:rows     = $st.Rows
    $lblSave.Text = ("存档：{0}   主角：{1} L{2}" -f (Split-Path $path -Leaf), $st.Header.Player, $st.Header.Level)
    $grid.Rows.Clear()
    foreach ($r in $st.Rows) {
        $idx = $grid.Rows.Add()
        $grid.Rows[$idx].Cells['Sel'].Value = $false
        foreach ($f in @('Name','Level','Attrs','AttrGain','SkillSum','SkillGain','CurAP','CurSP')) {
            $grid.Rows[$idx].Cells[$f].Value = $r.$f
        }
    }
    $status.Text = ("已加载 {0} 个同伴。" -f $st.Rows.Count)
}

$btnPick.Add_Click({
    $dlg = New-Object Windows.Forms.OpenFileDialog
    $dlg.Title = '选择战团存档'
    $dlg.Filter = '战团存档 (*.sav)|*.sav|所有文件 (*.*)|*.*'
    try { $dlg.InitialDirectory = Split-Path $script:SavePath -Parent } catch {}
    if ($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
        try {
            Update-FromSave $dlg.FileName
            $status.Text = "已切换存档：" + (Split-Path $dlg.FileName -Leaf)
        } catch {
            [Windows.Forms.MessageBox]::Show($_.Exception.Message, '加载失败', 'OK', 'Error') | Out-Null
            $status.Text = '加载失败：' + $_.Exception.Message
        }
    }
})

$btnReload.Add_Click({
    try {
        Update-FromSave $script:SavePath
        $status.Text = '已刷新（' + (Split-Path $script:SavePath -Leaf) + '）'
    } catch {
        [Windows.Forms.MessageBox]::Show($_.Exception.Message, '刷新失败', 'OK', 'Error') | Out-Null
    }
})

$form.Add_Shown({ $form.Activate() })
[void]$form.ShowDialog()
