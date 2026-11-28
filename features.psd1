@{
    # 模块生成器的功能分组（界面按「组」勾选；同一组内的功能耦合，必须一起生成）。
    # 本文件是唯一来源：manager.ps1 读它画界面，build-module.ps1 读它展开与校验。
    # 新增功能时：加一个组，Features 里写 build-module.ps1 认的功能名。
    # 共用同一个菜单的功能**不必并组**：菜单骨架由生成器建（Apply-TrainingHost 是范例），
    # 各功能自己 Add-MenuOption 加选项即可，谁勾选都行。
    Version = 1
    Groups = @(
        @{
            Key      = 'equip'
            Title    = '一键换装'
            Desc     = '营地 → 换装备：护甲 / 按兵种配武器 / 坐骑（弓兵、骑兵各四格）'
            Features = @('equip')
        }
        @{
            Key      = 'garrison'
            Title    = '攻城俘虏变驻军'
            Desc     = '攻城得手后，可招募的敌方俘虏直接编入驻军'
            Features = @('garrison')
        }
        @{
            Key      = 'lairlink'
            Title    = '巢穴地点可在大地图指出'
            Desc     = '「摧毁强盗老巢」任务笔记里的据点名可点击，点一下在大地图定位'
            Features = @('lairlink')
        }
        @{
            Key      = 'lootchest'
            Title    = '奇形宝箱 BUG 修复'
            Desc     = '日瓦车则隐藏宝箱一次给全部 6 件'
            Features = @('lootchest')
        }
        @{
            Key      = 'detail'
            Title    = '人物详情显示优化'
            Desc     = '人物笔记补等级、四维、技能、性格、金钱、同派系关系、当前位置'
            Features = @('detail')
        }
        @{
            Key      = 'itemvalue'
            Title    = '物品原始价值'
            Desc     = '物品详情框多一行灰字「原始价值：X」，商店与物品栏通用'
            Features = @('itemvalue')
        }
        @{
            Key      = 'fief'
            Title    = '分封显示现有领地'
            Desc     = '大臣分封对话里，每个领主名字后面标注他已有的领地'
            Features = @('fief')
        }
        @{
            Key      = 'armyreward'
            Title    = '跟随元帅任务优化'
            Desc     = '战役结算固定 3000 经验，支线做完即结束跟随'
            Features = @('armyreward')
        }
        @{
            Key      = 'mentor'
            Title    = '传授经验'
            Desc     = '城镇 → 训练 → 传授经验：高等级同伴指点低等级同伴（与「学习技能」共用训练菜单，可各自勾选）'
            Features = @('mentor')
        }
        @{
            Key      = 'learnskill'
            Title    = '学习技能'
            Desc     = '城镇 → 训练 → 学习技能：向同伴讨教 5 项技能（统御 / 俘虏管理 / 说服力 / 物品管理 / 急救；与「传授经验」共用训练菜单，可各自勾选）'
            Features = @('learnskill')
        }
        @{
            Key      = 'loan'
            Title    = '本势力领主贷款'
            Desc     = '借款费用 10%、周息 4%、按财富 5% 还款、财富够时一次还清、封顶 30000'
            Features = @('loan')
        }
        @{
            Key      = 'skills'
            Title    = '技能相关优化'
            Desc     = '掠夺改智力、骑术改力量（只影响面板图标与加点门槛）'
            Features = @('skills')
        }
        @{
            Key      = 'fiefenvy'
            Title    = '国王好感减免分封嫉妒'
            Desc     = '国王与某领主关系越好，分封时该领主越少嫉妒国王'
            Features = @('fiefenvy')
        }
        @{
            Key      = 'reconcile'
            Title    = '冰释前嫌'
            Desc     = '与领主关系为负时，可用金币或货物换取关系'
            Features = @('reconcile')
        }
        @{
            Key      = 'dispute'
            Title    = '调解领主纠纷优化'
            Desc     = '任务无冷却、阈值放宽、显示成功率、完成时关系补到 8、可花钱了结'
            Features = @('dispute')
        }
        @{
            Key      = 'persuade'
            Title    = '说服相关'
            Desc     = '领主招募显示支持度；同伴离队说服失败后可用钱挽留'
            Features = @('persuade')
        }
        @{
            Key      = 'luck'
            Title    = '运气'
            Desc     = '夜袭免战、潜入脱身、配偶处供奉祈运；城镇有夜行强盗时，市长任务优先给「处理夜行强盗」（不限等级）'
            Features = @('luck')
        }
        @{
            Key      = 'defeat'
            Title    = '战败惩罚'
            Desc     = '同伴 25% 离队；背包物品半数缴获；身上装备不缴；被俘时长随等级缩短'
            Features = @('defeat')
        }
        @{
            Key      = 'claim'
            Title    = '宣称系统'
            Desc     = '失地记录原主与势力；原势力收复自动归还；停战按实际控制清空；叛国流放清理'
            Features = @('claim')
        }
        @{
            Key      = 'lua'
            Title    = 'Lua 消息出口'
            Desc     = '提示文字放 lua/main.lua，需 WSE2 才显示；没装 WSE2 也能正常游玩'
            Features = @('lua')
        }
        @{
            Key      = 'patrol'
            Title    = '友方巡逻队'
            Desc     = '城镇招募巡逻队、拨兵、解散、卖俘虏；队伍管理里还可征募下属村庄士兵'
            Features = @('patrol')
        }
        @{
            Key      = 'factionjoin'
            Title    = '换国关系下限'
            Desc     = '领主加入新国家后与该国国王关系最低 0，原 +5 保留，防刚换国就被反复流放'
            Features = @('factionjoin')
        }
        @{
            Key      = 'swap'
            Title    = '领土交换'
            Desc     = '大臣对话调换国内两处领地；失去更高价值领地的一方扣关系（城 -10、堡 -5）'
            Features = @('swap')
        }
        @{
            Key      = 'taxexempt'
            Title    = '税收无效损失豁免'
            Desc     = '预算报告里玩家村庄不计入税收无效损失，村庄收入照常'
            Features = @('taxexempt')
        }
        @{
            Key      = 'nofiefgood'
            Title    = '无地好人性格领主惩罚'
            Desc     = '善良 / 正直领主没有领地时，也按周期与国王掉 1 点关系'
            Features = @('nofiefgood')
        }
        @{
            Key      = 'drill'
            Title    = '历练'
            Desc     = '同伴可派往别国当领主；任意势力的原同伴领主可对话召回，领地自动收回'
            Features = @('drill')
        }
        @{
            Key      = 'sortitems'
            Title    = '市场整理物品'
            Desc     = '城镇市场「整理物品」：按市场价从高到低整理背包（调用引擎 troop_sort_inventory）'
            Features = @('sortitems')
        }
        @{
            Key      = 'cheatlang'
            Title    = '作弊菜单汉化'
            Desc     = '战团内置作弊菜单（营地 CHEAT MENU! / 物品查找 / 天气 / 城堡攻城 / 训练场等）的 43 条文本写入中文语言包'
            Features = @('cheatlang')
        }
        @{
            Key      = 'ransom'
            Title    = '领主赎金'
            Desc     = '领主重建队伍时损失 30% 财富；抓获/放走领主时可索要其财富的 10%（最低 1500）'
            Features = @('ransom')
        }
    )
}
