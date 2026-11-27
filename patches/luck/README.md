# 运气补丁（luck）

> 第 16 项功能。三块：夜袭免战、潜入二次判定、伴侣供奉回运气。
> 生成时由 `build-module.ps1` 的 `Apply-Luck` 应用；参数在 `modpack\params.md` 的「运气参数」表。

## 一、机制背景（原版事实）

- 引擎变量 `g_player_luck`（Native variables.txt 第 884 行）初始 200，每 180 游戏小时 -1，**原版无任何恢复途径**。
- 永久受伤判定：战斗中被打倒时掷 1-100，大于当前 luck 则永久 -1 点属性（757.5 天后才有风险）。
- 夜袭（`mt_bandits_at_night`）在**夜晚 + 城镇/村庄有强盗**时触发，条件封装在脚本 `cf_enter_center_location_bandit_check`（Native 脚本索引 348），城镇与村庄的入口（城镇中心/酒馆/市场、村庄各入口）都调用它。
- 潜入判定在 `menu_castle_outside` 的 `mno_town_sneak` 选项动作里（menus.txt）。

## 二、改动

### 1. 夜袭：根源拦截

改 `cf_enter_center_location_bandit_check` 脚本体行，在「夜晚 + 有强盗」条件之后、设置战斗之前插入：

```
roll = rand(0..100)
chance = 满概率 * luck / 200
if roll < chance:   # 躲过
    display_message(提示)
    return 0        # 不触发战斗，菜单走正常入口
else:
    原逻辑（set_jump_mission / visitors / change_screen_mission）
```

- 城镇、村庄都生效（不额外判断地点类型）。
- 每次点入口都判定（不设次数限制）。
- 成功躲过后城镇强盗仍在，可再次触发。

### 2. 潜入：二次判定

在 `mno_town_sneak` 原判定 `rand > 阈值`（失败被抓）的分支里加：

```
roll = rand(0..100)
chance = 满概率 * luck / 200
if roll < chance:   # 躲过
    display_message(提示)
    跳 menu_sneak_into_town_suceeded（按潜入成功处理）
else:
    原失败流程（menu_sneak_into_town_caught）
```

### 3. 供奉：找伴侣对话（复用餐会物资判定）

流程：

1. 与配偶对话 →「供奉」选项（`dlga_spouse_talk` 状态 469 起）。
2. 评估：调 `internal_politics_rate_feast_to_s9(trp_household_possessions, 400, $players_kingdom, 0)`，显示 0-100 评分对应的等级（scant/meager/barely adequate/sufficient/bountiful/magnificent 六档）。
3. 确认供奉：同一脚本传 `consume_items=1` **自动扣 400 份物资**（食物/香料/油/葡萄酒/麦酒轮着各扣 1 件，宴会同款逻辑）→ 按评分档位恢复已损失 luck 的 10%–70% → 显示「供奉仪式已开始」→ `rest_for_hours 8`（等待界面）→ 显示「供奉仪式完成，恢复 X 点」→ 回大地图。

**不做的事（防宴会耦合）**：
- 不调用 `faction_conclude_feast`（该脚本会加声望、领主关系、婚礼等副作用）。
- 不碰 `qst_organize_feast` 任务。
- 不设 `slot_town_has_tournament`、不邀请领主、不改关系/声望。

## 三、参数（`params.md` 的「运气参数」表）

| 参数 | 默认 | 说明 |
|---|---|---|
| 夜袭满概率 | 70 | luck=200 时躲过夜袭的概率（%） |
| 潜入满概率 | 70 | luck=200 时躲过被抓的概率（%） |
| 供奉份数 | 400 | 供奉扣除的物资份数（同玩家主办宴会） |
| 供奉恢复-寒酸 | 10 | scant（0-19 分）恢复已损失 luck 的 % |
| 供奉恢复-微薄 | 20 | meager（20-39） |
| 供奉恢复-勉强 | 35 | barely adequate（40-59） |
| 供奉恢复-充足 | 50 | sufficient（60-79） |
| 供奉恢复-丰盛 | 60 | bountiful（80-99） |
| 供奉恢复-盛大 | 70 | magnificent（100） |
| 供奉停留小时 | 8 | 供奉后原地停留小时数 |

## 四、实现位置清单

| 文件 | 改动 |
|---|---|
| `scripts.txt` | 改 `cf_enter_center_location_bandit_check` 体行（夜袭幸运判定，78 条语句）；追加 `wb_luck_offering_eval` / `_do` 两个脚本 |
| `menus.txt` | 改 `menu_castle_outside` 的 `mno_town_sneak` 动作：失败分支插入二次幸运判定（成功进结果页，不再用浮动消息） |
| `conversation.txt` | 前部插入配偶「供奉」对话行（状态 9010-9014，确认后 close_window） |
| `strings.txt` | 追加 11 条（六档等级 + 完成/开始提示 + 夜袭/潜入躲过 + 潜入测试） |
| `languages\cns\*.csv` | 中文对话与字符串 |

## 五、测试点

1. 夜晚进有强盗的村庄（强盗一般挂在村庄，城镇没强盗就不触发），点酒馆/市场/村庄中心：好运时不进战斗、弹「你察觉到暗处的杀意，趁着夜色悄然脱身。」；低运时照常夜袭。
2. 潜入敌方城镇（选项「伪装潜入」）：原判定被抓时再掷幸运，好运直接按潜入成功进城镇并弹「你的伪装瞒过了守卫，不动声色地混进城中。」；低运时被抓。
3. 与配偶对话供奉：评估显示等级（寒酸…盛大）→ 确认后扣 400 份、弹「供奉仪式已开始，静候回应。」→ 等待界面 8 小时 → 回大地图 → 7 小时后弹「供奉完成，你的运气恢复了 X 点。」。确认**不加领主关系、不触发宴会**。
4. 旧档读取正常：只追加变量/字符串，菜单 ID 数量不变，`simple_triggers` 固定 115（含空占位）。
