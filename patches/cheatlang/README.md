# 作弊菜单汉化（cheatlang）

> **状态（2026-11-27）：已接入生成器，待进游戏实测。**

## 做什么

把战团内置作弊菜单（营地 → `CHEAT MENU!`，以及物品查找、天气、阵营命令、城堡攻城、训练场、人物报告等处的 `CHEAT` 项）的英文文本写入中文语言包，共 **52 条词条**（3 条菜单标题 + 49 条选项 key；「返回营地菜单」两个子菜单共用 1 条）。

这些文本原本只存在于 `menus.txt` 里，官方中文语言包没有对应词条，所以游戏里一直是英文。

## 原理

- 战团支持模块内 `languages\cns\game_menus.csv` 按菜单 ID / 选项 ID 覆盖菜单文本（`key|译文`，如 `mno_xxx|中 文`）。
- 同一个菜单里原名重复的选项（原版 `mno_continue` ×6、`mno_cheat_faction_orders` ×3、`mno_camp_cheat_find_item` ×2、`mno_camp_action_4` ×2）在语言文件里无法分别翻译，所以生成器先把它们改成唯一 ID：

| 位置 | 原 ID | 新 ID |
| --- | --- | --- |
| `menu_camp_cheat` | `mno_camp_cheat_find_item`（第 2 次，Change weather） | `mno_camp_cheat_change_weather` |
| `menu_camp_cheat` | `mno_cheat_faction_orders` ×3（三条调试消息） | `mno_camp_cheat_debug_all` / `_econ` / `_political` |
| `menu_character_report` | `mno_continue` ×5（前五个作弊项） | `mno_cheat_inc_rtor` / `_relation` / `_honor` / `_renown` / `_persuasion` |
| `menu_cheat_find_item` | `mno_camp_action_4`（返回） | `mno_cheat_back_camp` |
| `menu_cheat_change_weather` | `mno_camp_action_4`（返回） | `mno_cheat_back_camp` |

- 只改写选项 ID，不动选项动作和条件；`menu_character_report` 里第 6 个 `mno_continue`（普通「继续……」）保留原名，走官方翻译。
- 语言条目追加到模块的 `languages\cns\game_menus.csv`（BOM + CRLF），与其它补丁一致。

## 文件

| 文件 | 说明 |
| --- | --- |
| `lang_menus.csv` | 中文词条（`key|译文`，UTF-8 无 BOM） |
| `README.md` | 本说明 |

## 词条清单（52 条）

菜单标题 3 条：`menu_camp_cheat`（选择一项作弊：）、`menu_cheat_find_item`（当前物品范围）、`menu_cheat_change_weather`（当前云量 / 当前雾浓度）。

选项 49 条：营地作弊菜单 12 项、物品查找 3 项、天气调节 5 项、营地菜单 2 项、报告菜单 2 项（阵营命令入口 + NPC 状态检查）、阵营命令 11 项（3 条作弊 + 8 条势力调试：选择下一个势力 / 强制防守 / 强制宴会 / 强制集结 / 进攻时间延后 24 小时 / 强制重新考虑 / 全体重新考虑 / 初始化经济数据）、人物报告 5 项、城堡/攻城 6 项、训练场 2 项、修改旗帜 1 项、教程 1 项（其中「返回营地菜单」两个子菜单共用 `mno_cheat_back_camp`）。

文案按项目规范：汉字间空格、全角标点、`{!}` 黄色前缀保留、`{reg}`/`{s}` 占位符原样。

## 注意

- 语言文件里的 `{!}` 前缀沿用原菜单文本，若进游戏发现显示成字面 `{!}`，去掉译文里的 `{!}` 即可（4 条：物品查找/天气/城堡/训练场等）。
- 只写了简体 `cns`；用 `cnt`（繁体）启动游戏时这些条目仍显示英文。
- 测试入口：营地 → `CHEAT MENU!`（需先开作弊模式：启动器勾 Enable Cheats 或大地图 `Ctrl+~` 输入 `cheatmenu`）；阵营命令菜单（报告 → 阵营命令）标题是动态的「选择的阵营是：…」，其下 12 项全部中文。
