-- ============================================================
-- 骑砍战团「原版增强」Lua 消息出口
-- 位置：Modules\<模块名>\lua\main.lua
-- 作用：读取 Native 写入的消息类型（g_wb_msg_*）与名字字符串
--       （sreg[60] 中心名单、sreg[61] 领主名），左下角显示。
-- 依赖：WSE2（没有 WSE2 时本文件不运行，游戏功能不受影响）
-- 注意：party/troop 等大 ID 不要经过 Lua 数字（双精度会溢出），
--       名字一律由 Native 预先 str_store 到字符串寄存器。
-- 文风：书面、简练、古朴，句末统一全角句号；数字后直接接中文单位。
-- ============================================================

-- 战团的中文字体要求「字间加空格」，否则字符会挤在一起
local function sp(s)
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        if b >= 0xE0 then
            out[#out + 1] = s:sub(i, i + 2)
            out[#out + 1] = " "
            i = i + 3
        elseif b >= 0xC0 then
            out[#out + 1] = s:sub(i, i + 1)
            i = i + 2
        else
            out[#out + 1] = s:sub(i, i)
            i = i + 1
        end
    end
    local r = table.concat(out)
    r = r:gsub("  +", " ")
    return r
end

local function show(msg, color)
    if color then
        game.display_message(sp(msg), color)
    else
        game.display_message(sp(msg))
    end
end

local function flush_message()
    local t = game.gvar.g_wb_msg_type
    if t == nil or t == 0 then
        return
    end
    game.gvar.g_wb_msg_type = 0

    local lord = game.sreg[61] or ""
    local list = game.sreg[60] or ""
    local faction = game.sreg[62] or ""
    local king = game.sreg[63] or ""
    local center = game.sreg[55] or ""

    if t == 1 then
        show(faction .. " 攻占了 " .. center .. "，旧主的宣称已被记下。", 0xFF6600)
        game.sreg[60] = ""
    elseif t == 2 then
        show(faction .. " 收复失地 " .. center .. "，领地已归还原主。", 0x00CC00)
        game.sreg[60] = ""
    elseif t == 3 then
        show("两国缔结停战之约，" .. game.gvar.g_wb_msg_count .. " 处领土宣称就此作废。", 0x00CCFF)
    elseif t == 4 then
        local sid = game.gvar.g_wb_msg_arg1
        local names = { [1] = "统御", [2] = "俘虏管理", [7] = "说服力", [12] = "物品管理" }
        show("你向同伴讨教诀窍，渐渐摸到门道，" .. (names[sid] or "技能") .. "技能 +1。")
    elseif t == 6 then
        show(lord .. " 还清了借款，计 " .. game.gvar.g_wb_msg_arg1 .. " 第纳尔。")
    elseif t == 7 then
        show(lord .. " 濒临破产，或可资助一二。")
    elseif t == 8 then
        show("你借给 " .. lord .. " " .. game.gvar.g_wb_msg_arg1 .. " 第纳尔。")
    elseif t == 9 then
        show("你在神龛前献上供品，静候命运回应。")
    elseif t == 10 then
        show("祈运完毕，运气回升 " .. game.gvar.g_wb_msg_arg1 .. " 点。")
    elseif t == 11 then
        local luck = game.gvar.g_wb_msg_arg1
        if luck >= 91 then
            show("近来诸事不顺（运气 " .. luck .. "），或该去神龛前求个转机。")
        elseif luck >= 81 then
            show("近来运势低迷（运气 " .. luck .. "），该想些法子补一补了。")
        elseif luck >= 71 then
            show("近来时运不济（运气 " .. luck .. "），诸事多有阻滞。")
        elseif luck >= 61 then
            show("近来厄运缠身（运气 " .. luck .. "），祸事一桩接着一桩。")
        else
            show("近来灾厄连连（运气 " .. luck .. "），福祸难料。")
        end
    elseif t == 12 then
        show("强盗设伏于道，你抢在合围之前脱身了。")
    elseif t == 13 then
                show(lord .. " 从专门指导中获得 " .. game.gvar.g_wb_msg_arg1 .. " 经验。")
    elseif t == 15 then
        show("传授开始：在据点等待时每小时结算。")
    elseif t == 17 then
        show(lord .. " 已是队中经验最高者，暂时无人可教。")
    elseif t == 18 then
        show("受指导者已不在队伍中，传授停止。")
    elseif t == 21 then
        show("巡逻队本周工资 " .. game.gvar.g_wb_msg_arg1 .. " 第纳尔。")
    elseif t == 23 then
        show(lord .. " 因领地交换受了损失，与你的关系 -" .. game.gvar.g_wb_msg_arg1 .. "。")
    elseif t == 24 then
        show(lord .. " 已回到你的队伍。", 0x00CC00)
    elseif t == 25 then
        show("归队暂缓：" .. lord .. " 当前已不是领主状态。", 0xFFAA00)
    elseif t == 26 then
        show(lord .. " 已动身前往 " .. faction .. "，投奔 " .. king .. " 麾下。", 0x00CC00)
    elseif t == 27 then
        local ok = game.gvar.g_wb_msg_arg1
        local occ = game.gvar.g_wb_msg_arg2
        show("调试·派出选项：同伴判断=" .. (ok == 1 and "是" or "否") .. "，occupation=" .. occ, 0xFF00FF)
    elseif t == 28 then
        show("从 " .. center .. " 征募了 " .. game.gvar.g_wb_msg_arg1 .. " 名志愿兵。")
    elseif t == 29 then
        show("共征募 " .. game.gvar.g_wb_msg_arg1 .. " 名志愿兵。")
    elseif t == 20 then
        show("传授停止。")
    end
end

-- 自动热加载
local last_content = nil
local function check_reload()
    local f = io.open("main.lua", "r")
    if not f then return end
    local c = f:read("*a")
    f:close()
    if last_content == nil then
        last_content = c
        return
    end
    if c ~= last_content then
        last_content = c
        dofile("main.lua")
    end
end

game.OnGameLoad = function()
    flush_message()
end

game.OnLoadSave = function()
    flush_message()
end

game.OnWorldTrigger = function(date)
    check_reload()
    flush_message()
end
