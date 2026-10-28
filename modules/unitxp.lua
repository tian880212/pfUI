-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

pfUI:RegisterModule("unitxp", "vanilla", function ()
  -- 简易距离检测（无 UnitXP 时基于动作条技能与 CheckInteractDistance 估算）
  local function SetupSimpleDistanceIndicator()
    local uc = C.unitframes
    if uc.distance_indicator == nil then uc.distance_indicator = "0" end
    if uc.distance_indicator_font_size == nil then uc.distance_indicator_font_size = 13 end
    if uc.distance_indicator_update_interval == nil then uc.distance_indicator_update_interval = "0.1" end
    if uc.distance_indicator_use_gradient == nil then uc.distance_indicator_use_gradient = "1" end
    if uc.distance_indicator_show_prefix == nil then uc.distance_indicator_show_prefix = "1" end

    if uc.distance_indicator ~= "1" then return end

    -- 渐变色表（与 UnitXP 模式保持一致）
    local thresholds = {
      {  5, 0.3, 0.5, 1.0 },
      {  8, 0.4, 0.7, 1.0 },
      { 20, 0.4, 0.9, 1.0 },
      { 30, 0.0, 1.0, 0.0 },
      { 35, 0.8, 1.0, 0.0 },
      { 41, 1.0, 1.0, 0.0 },
      { 999, 1.0, 1.0, 1.0 },
    }

    -- 各职业技能距离表（来源于 tooltip 显示的码数）
    local detectRangeSpells = {
      ["HUNTER"] = {
        ["摔绊"] = { yards = "5", t = "ATTACK" },
        ["猫鼬撕咬"] = { yards = "5", t = "ATTACK" },
        ["切碎"] = { yards = "5", t = "ATTACK" },
        ["投掷"] = { yards = "8-30", t = "ATTACK" },
        ["驱散射击"] = { yards = "15-1", t = "ATTACK" },
        ["毒蛇钉刺"] = { yards = "8-35-1", t = "ATTACK" },
        ["蝰蛇钉刺"] = { yards = "8-35-1", t = "ATTACK" },
        ["毒蝎钉刺"] = { yards = "8-35-1", t = "ATTACK" },
        ["宁神射击"] = { yards = "8-35-1", t = "ATTACK" },
        ["奥术射击"] = { yards = "8-35-1", t = "ATTACK" },
        ["多重射击"] = { yards = "8-35-1", t = "ATTACK" },
        ["瞄准射击"] = { yards = "8-35-1", t = "ATTACK" },
        ["稳固射击"] = { yards = "8-35-1", t = "ATTACK" },
        ["震荡射击"] = { yards = "8-35-1", t = "ATTACK" },
      },
      ["MAGE"] = {
        ["火焰冲击"] = { yards = "20", t = "ATTACK" },
        ["法术反制"] = { yards = "30", t = "ATTACK" },
        ["法术偷取"] = { yards = "30", t = "ATTACK" },
        ["奥术溃裂"] = { yards = "30", t = "ATTACK" },
        ["奥术飞弹"] = { yards = "30", t = "ATTACK" },
        ["奥术涌动"] = { yards = "30", t = "ATTACK" },
        ["奥术智慧"] = { yards = "30", t = "ASSIST" },
        ["解除次级诅咒"] = { yards = "30", t = "ASSIST" },
        ["魔法增效"] = { yards = "30", t = "ALL" },
        ["魔法抑制"] = { yards = "30", t = "ALL" },
        ["灼烧"] = { yards = "30-1", t = "ATTACK" },
        ["火球术"] = { yards = "35", t = "ATTACK" },
        ["炎爆术"] = { yards = "35", t = "ATTACK" },
        ["寒冰箭"] = { yards = "30-2", t = "ATTACK" },
        ["冰柱"] = { yards = "30-2", t = "ATTACK" },
        ["侦测魔法"] = { yards = "40", t = "ATTACK" },
      },
      ["DRUID"] = {
        ["捶击"] = { yards = "5", t = "ATTACK" },
        ["挥击"] = { yards = "5", t = "ATTACK" },
        ["低吼"] = { yards = "5", t = "ATTACK" },
        ["重击"] = { yards = "5", t = "ATTACK" },
        ["扫击"] = { yards = "5", t = "ATTACK" },
        ["爪击"] = { yards = "5", t = "ATTACK" },
        ["撕碎"] = { yards = "5", t = "ATTACK" },
        ["毁灭"] = { yards = "5", t = "ATTACK" },
        ["突袭"] = { yards = "5", t = "ATTACK" },
        ["撕扯"] = { yards = "5", t = "ATTACK" },
        ["凶猛撕咬"] = { yards = "5", t = "ATTACK" },
        ["畏缩"] = { yards = "5", t = "ATTACK" },
        ["割伤"] = { yards = "5", t = "ATTACK" },
        ["斜掠"] = { yards = "5", t = "ATTACK" },
        ["横扫"] = { yards = "5", t = "ATTACK" },
        ["割裂"] = { yards = "5", t = "ATTACK" },
        ["野性冲锋"] = { yards = "8-25", t = "ATTACK" },
        ["愤怒"] = { yards = "30-1", t = "ATTACK" },
        ["月火术"] = { yards = "30-1", t = "ATTACK" },
        ["星火术"] = { yards = "30-1", t = "ATTACK" },
        ["纠缠根须"] = { yards = "30-1", t = "ATTACK" },
        ["精灵之火"] = { yards = "30-1", t = "ATTACK" },
        ["虫群"] = { yards = "30-1", t = "ATTACK" },
        ["野性印记"] = { yards = "30", t = "ASSIST" },
        ["废毒术"] = { yards = "30", t = "ASSIST" },
        ["驱毒术"] = { yards = "30", t = "ASSIST" },
        ["解除诅咒"] = { yards = "30", t = "ASSIST" },
        ["消毒术"] = { yards = "30", t = "ASSIST" },
        ["荆棘术"] = { yards = "30-1", t = "ASSIST" },
        ["激活"] = { yards = "30-1", t = "ASSIST" },
        ["愈合"] = { yards = "40", t = "ASSIST" },
        ["治疗之触"] = { yards = "40", t = "ASSIST" },
        ["回春术"] = { yards = "40", t = "ASSIST" },
      },
      ["PRIEST"] = {
        ["沉默"] = { yards = "20", t = "ATTACK" },
        ["神圣之火"] = { yards = "30-1", t = "ATTACK" },
        ["惩击"] = { yards = "30-1", t = "ATTACK" },
        ["精神鞭笞"] = { yards = "20-2", t = "ATTACK" },
        ["暗言术：痛"] = { yards = "30-2", t = "ATTACK" },
        ["心灵震爆"] = { yards = "30-2", t = "ATTACK" },
        ["噬灵瘟疫"] = { yards = "30-2", t = "ATTACK" },
        ["暗言术：灭"] = { yards = "30-2", t = "ATTACK" },
        ["吸血鬼之触"] = { yards = "30-2", t = "ATTACK" },
        ["法力燃烧"] = { yards = "30", t = "ATTACK" },
        ["真言术：韧"] = { yards = "30", t = "ASSIST" },
        ["神圣精神"] = { yards = "30", t = "ASSIST" },
        ["驱散魔法"] = { yards = "30", t = "ASSIST" },
        ["祛病术"] = { yards = "30", t = "ASSIST" },
        ["驱除疾病"] = { yards = "30", t = "ASSIST" },
        ["神圣之灵"] = { yards = "30", t = "ASSIST" },
        ["暗影防护"] = { yards = "30", t = "ASSIST" },
        ["防护恐惧结界"] = { yards = "30", t = "ASSIST" },
        ["治疗术"] = { yards = "40", t = "ASSIST" },
        ["次级治疗术"] = { yards = "40", t = "ASSIST" },
        ["快速治疗"] = { yards = "40", t = "ASSIST" },
        ["强效治疗术"] = { yards = "40", t = "ASSIST" },
        ["恢复"] = { yards = "40", t = "ASSIST" },
        ["治疗之环"] = { yards = "40", t = "ASSIST" },
        ["联结治疗"] = { yards = "40", t = "ASSIST" },
      },
      ["WARLOCK"] = {
        ["恐惧"] = { yards = "20-1", t = "ATTACK" },
        ["虚弱诅咒"] = { yards = "30-1", t = "ATTACK" },
        ["腐蚀术"] = { yards = "30-1", t = "ATTACK" },
        ["痛苦诅咒"] = { yards = "30-1", t = "ATTACK" },
        ["吸取灵魂"] = { yards = "30-1", t = "ATTACK" },
        ["鲁莽诅咒"] = { yards = "30-1", t = "ATTACK" },
        ["舌之诅咒"] = { yards = "30-1", t = "ATTACK" },
        ["生命虹吸"] = { yards = "30-1", t = "ATTACK" },
        ["元素诅咒"] = { yards = "30-1", t = "ATTACK" },
        ["死亡缠绕"] = { yards = "30-1", t = "ATTACK" },
        ["阴影诅咒"] = { yards = "30-1", t = "ATTACK" },
        ["吸取生命"] = { yards = "30-1", t = "ATTACK" },
        ["吸取法力"] = { yards = "30-1", t = "ATTACK" },
        ["腐蚀之种"] = { yards = "30-1", t = "ATTACK" },
        ["痛苦无常"] = { yards = "30-1", t = "ATTACK" },
        ["暗影燃烧"] = { yards = "20-2", t = "ATTACK" },
        ["暗影灼烧"] = { yards = "20-2", t = "ATTACK" },
        ["暗影箭"] = { yards = "30-2", t = "ATTACK" },
        ["献祭"] = { yards = "30-2", t = "ATTACK" },
        ["灼热之痛"] = { yards = "30-2", t = "ATTACK" },
        ["灵魂之火"] = { yards = "30-2", t = "ATTACK" },
        ["燃烧"] = { yards = "30-2", t = "ATTACK" },
        ["烧尽"] = { yards = "30-2", t = "ATTACK" },
        ["无尽呼吸"] = { yards = "30", t = "ASSIST" },
        ["侦测次极隐形"] = { yards = "30", t = "ASSIST" },
        ["侦测隐形"] = { yards = "30", t = "ASSIST" },
        ["侦测高级隐形"] = { yards = "30", t = "ASSIST" },
      },
      ["SHAMAN"] = {
        ["闪电链"] = { yards = "30-1", t = "ATTACK" },
        ["闪电箭"] = { yards = "30-1", t = "ATTACK" },
        ["地震术"] = { yards = "20-1", t = "ATTACK" },
        ["烈焰震击"] = { yards = "20", t = "ATTACK" },
        ["冰霜震击"] = { yards = "20", t = "ATTACK" },
        ["净化术"] = { yards = "30", t = "ATTACK" },
        ["消毒术"] = { yards = "30", t = "ATTACK" },
        ["祛病术"] = { yards = "30", t = "ATTACK" },
        ["水下呼吸"] = { yards = "30", t = "ATTACK" },
        ["水上行走"] = { yards = "30", t = "ATTACK" },
        ["先祖之魂"] = { yards = "30", t = "ATTACK" },
        ["治疗波"] = { yards = "40", t = "ATTACK" },
        ["次级治疗波"] = { yards = "40", t = "ATTACK" },
        ["治疗链"] = { yards = "40", t = "ATTACK" },
        ["大地之盾"] = { yards = "40", t = "ATTACK" },
      },
      ["PALADIN"] = {
        ["制裁之锤"] = { yards = "10", t = "ATTACK" },
        ["审判"] = { yards = "10", t = "ATTACK" },
        ["神圣震击"] = { yards = "20", t = "ALL" },
        ["清洁术"] = { yards = "30", t = "ASSIST" },
        ["纯净术"] = { yards = "30", t = "ASSIST" },
        ["力量祝福"] = { yards = "30", t = "ASSIST" },
        ["智慧祝福"] = { yards = "30", t = "ASSIST" },
        ["庇护祝福"] = { yards = "30", t = "ASSIST" },
        ["自由祝福"] = { yards = "30", t = "ASSIST" },
        ["光明祝福"] = { yards = "30", t = "ASSIST" },
        ["王者祝福"] = { yards = "30", t = "ASSIST" },
        ["圣光术"] = { yards = "40", t = "ASSIST" },
        ["圣疗术"] = { yards = "40", t = "ASSIST" },
        ["圣光闪现"] = { yards = "40", t = "ASSIST" },
        ["十字军打击"] = { yards = "5", t = "ATTACK" },
      },
      ["WARRIOR"] = {
        ["致死打击"] = { yards = "5", t = "ATTACK" },
        ["破甲攻击"] = { yards = "5", t = "ATTACK" },
        ["断筋"] = { yards = "5", t = "ATTACK" },
        ["嘲讽"] = { yards = "5", t = "ATTACK" },
        ["压制"] = { yards = "5", t = "ATTACK" },
        ["盾击"] = { yards = "5", t = "ATTACK" },
        ["复仇"] = { yards = "5", t = "ATTACK" },
        ["惩戒痛击"] = { yards = "5", t = "ATTACK" },
        ["缴械"] = { yards = "5", t = "ATTACK" },
        ["斩杀"] = { yards = "5", t = "ATTACK" },
        ["盾牌猛击"] = { yards = "5", t = "ATTACK" },
        ["撕裂"] = { yards = "5", t = "ATTACK" },
        ["拳击"] = { yards = "5", t = "ATTACK" },
        ["嗜血"] = { yards = "5", t = "ATTACK" },
        ["震荡猛击"] = { yards = "5", t = "ATTACK" },
        ["猛击"] = { yards = "5", t = "ATTACK" },
        ["破胆怒吼"] = { yards = "10", t = "ATTACK" },
        ["冲锋"] = { yards = "8-25", t = "ATTACK" },
        ["拦截"] = { yards = "8-25", t = "ATTACK" },
        ["援护"] = { yards = "8-25", t = "ASSIST" },
        ["枪械射击"] = { yards = "8-30", t = "ATTACK" },
        ["弓射击"] = { yards = "8-30", t = "ATTACK" },
        ["弩射击"] = { yards = "8-30", t = "ATTACK" },
      },
      ["ROGUE"] = {
        ["割裂"] = { yards = "5", t = "ATTACK" },
        ["邪恶攻击"] = { yards = "5", t = "ATTACK" },
        ["背刺"] = { yards = "5", t = "ATTACK" },
        ["脚踢"] = { yards = "5", t = "ATTACK" },
        ["凿击"] = { yards = "5", t = "ATTACK" },
        ["刺骨"] = { yards = "5", t = "ATTACK" },
        ["锁喉"] = { yards = "5", t = "ATTACK" },
        ["绞杀"] = { yards = "5", t = "ATTACK" },
        ["偷袭"] = { yards = "5", t = "ATTACK" },
        ["卸甲"] = { yards = "5", t = "ATTACK" },
        ["破甲"] = { yards = "5", t = "ATTACK" },
        ["佯攻"] = { yards = "5", t = "ATTACK" },
        ["肾击"] = { yards = "5", t = "ATTACK" },
        ["伏击"] = { yards = "5", t = "ATTACK" },
        ["出血"] = { yards = "5", t = "ATTACK" },
        ["放血"] = { yards = "5", t = "ATTACK" },
        ["还击"] = { yards = "5", t = "ATTACK" },
        ["鬼魅攻击"] = { yards = "5", t = "ATTACK" },
        ["致盲"] = { yards = "10", t = "ATTACK" },
        ["枪械射击"] = { yards = "8-30", t = "ATTACK" },
        ["弓射击"] = { yards = "8-30", t = "ATTACK" },
        ["弩射击"] = { yards = "8-30", t = "ATTACK" },
        ["投掷"] = { yards = "8-30-1", t = "ATTACK" },
        ["致命投掷"] = { yards = "8-30-1", t = "ATTACK" },
      },
    }

    local otherDetectRangeActions = {
      ["地精火箭头盔"] = { yards = "30", t = "ATTACK" },
      ["侏儒撒网器"] = { yards = "30", t = "ATTACK" },
      ["侏儒缩小射线"] = { yards = "30", t = "ATTACK" },
      ["雪球"] = { yards = "30", t = "ALL" },
      ["亚麻绷带"] = { yards = "15", t = "ASSIST" },
      ["厚亚麻绷带"] = { yards = "15", t = "ASSIST" },
      ["绒线绷带"] = { yards = "15", t = "ASSIST" },
      ["厚绒线绷带"] = { yards = "15", t = "ASSIST" },
      ["丝质绷带"] = { yards = "15", t = "ASSIST" },
      ["厚丝质绷带"] = { yards = "15", t = "ASSIST" },
      ["魔纹绷带"] = { yards = "15", t = "ASSIST" },
      ["厚魔纹绷带"] = { yards = "15", t = "ASSIST" },
      ["符文布绷带"] = { yards = "15", t = "ASSIST" },
      ["厚符文布绷带"] = { yards = "15", t = "ASSIST" },
    }

    -- 状态变量
    local DW_MELEE_MODIFYER = 0
    local DW_RANGE_MODIFYER = 0
    local _, DW_PLAYER_CLASS = UnitClass("player")
    local distState = { min = 0, max = 200 }
    local scanSlots = {}

    -- 用于读取动作条技能 tooltip 的 GameTooltip
    local scanTip = CreateFrame("GameTooltip", "pfUIDistanceScanTooltip", UIParent, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")

    local function getActionSpellInfo(slot)
      scanTip:ClearLines()
      for i = 1, 30 do
        local rfs = getglobal(scanTip:GetName() .. "TextRight" .. i)
        if rfs then rfs:SetText("") end
      end
      scanTip:SetAction(slot)
      local fontstring = getglobal(scanTip:GetName() .. "TextLeft1")
      local spellName, ranges
      if fontstring then
        spellName = fontstring:GetText()
        if not spellName then return end

        if otherDetectRangeActions[spellName] then
          return spellName, { tonumber(otherDetectRangeActions[spellName].yards) },
              otherDetectRangeActions[spellName].t, otherDetectRangeActions[spellName].yards
        end

        local detectSpellInfo = detectRangeSpells[DW_PLAYER_CLASS] and detectRangeSpells[DW_PLAYER_CLASS][spellName]
        if not detectSpellInfo then return end

        for i = 1, 30 do
          local rightFontstring = getglobal(scanTip:GetName() .. "TextRight" .. i)
          if rightFontstring then
            local rightText = rightFontstring:GetText()
            if rightText then
              local _, _, a, b = string.find(rightText, "(%d+)%s*-%s*(%d+)码距离")
              if a then
                ranges = { tonumber(b), tonumber(a) }
                break
              else
                _, _, a = string.find(rightText, "(%d+)%s*码距离")
                if a then
                  ranges = { tonumber(a) }
                  break
                end
              end
            end
          end

          local leftFontstring = getglobal(scanTip:GetName() .. "TextLeft" .. i)
          if leftFontstring then
            local leftText = leftFontstring:GetText()
            if leftText then
              local _, _, a, b = string.find(leftText, "(%d+)%s*-%s*(%d+)码距离")
              if a then
                ranges = { tonumber(b), tonumber(a) }
                break
              else
                _, _, a = string.find(leftText, "(%d+)%s*码距离")
                if a then
                  ranges = { tonumber(a) }
                  break
                end
              end
            end
          end
        end

        return spellName, ranges, detectSpellInfo.t, detectSpellInfo.yards
      end
    end

    local function testSlot(slot)
      local ico = GetActionTexture(slot)
      local lab = GetActionText(slot)
      if not ico or lab then
        scanSlots[slot] = nil
        return
      end
      local spellName, ranges, t, yards = getActionSpellInfo(slot)
      if spellName and ranges then
        scanSlots[slot] = { spellName = spellName, ranges = ranges, t = t, yards = yards }
      else
        scanSlots[slot] = nil
      end
    end

    local function testAllSlots()
      for i = 1, 120 do
        testSlot(i)
      end
    end

    local function getDistanceColor(maxdis)
      if uc.distance_indicator_use_gradient == "1" then
        for i = 1, table.getn(thresholds) do
          if maxdis <= thresholds[i][1] then
            return thresholds[i][2], thresholds[i][3], thresholds[i][4]
          end
        end
      end
      return 1, 1, 1
    end

    -- 创建距离指示器框架（与 UnitXP 模式共用 pfDistanceIndicator 名称，保持可拖动一致）
    if pfUI.distanceIndicator then
      pfUI.distanceIndicator:SetScript("OnUpdate", nil)
      pfUI.distanceIndicator:Hide()
      pfUI.distanceIndicator = nil
    end

    local frame = CreateFrame("Frame", "pfDistanceIndicator", UIParent)
    frame:SetWidth(90)
    frame:SetHeight(30)
    frame:SetPoint("CENTER", UIParent, "CENTER", 200, -30)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetFont(pfUI.font_default, tonumber(uc.distance_indicator_font_size) or 13, "OUTLINE")
    frame.text:SetPoint("CENTER", frame, "CENTER")
    frame.text:SetTextColor(1, 1, 1, 1)
    frame.text:SetText("")

    pfUI.distanceIndicator = frame
    pfUI.movables["pfDistanceIndicator"] = frame
    UpdateMovable(frame)

    -- 事件框架：进入世界、目标变化、动作条变化
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
    eventFrame:SetScript("OnEvent", function()
      if event == "PLAYER_ENTERING_WORLD" then
        _, DW_PLAYER_CLASS = UnitClass("player")
        testAllSlots()
      elseif event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") then
          local melee_mod1, melee_mod2, range_mod1, range_mod2
          if UnitIsPlayer("target") then
            if UnitRace("target") == "牛头人" then
              melee_mod1, range_mod1 = 2.4, 3.4
            else
              melee_mod1, range_mod1 = 0, 1
            end
            if UnitRace("player") == "牛头人" then
              melee_mod2, range_mod2 = 2.4, 3.4
            else
              melee_mod2, range_mod2 = 0, 1
            end
          else
            melee_mod1, range_mod1, melee_mod2, range_mod2 = 0, 0, 0, 0
          end
          DW_MELEE_MODIFYER = melee_mod1 + melee_mod2
          DW_RANGE_MODIFYER = range_mod1 + range_mod2
        else
          DW_MELEE_MODIFYER = 0
          DW_RANGE_MODIFYER = 0
          frame.text:SetText("")
        end
      elseif event == "ACTIONBAR_SLOT_CHANGED" then
        if DW_PLAYER_CLASS then testSlot(arg1 or 1) end
      elseif event == "SPELLS_CHANGED" or event == "CHARACTER_POINTS_CHANGED" then
        if DW_PLAYER_CLASS then testAllSlots() end
      end
    end)

    -- OnUpdate：节流执行距离检测
    local lastCheck = 0
    local lastRescan = 0
    frame:SetScript("OnUpdate", function()
      local now = GetTime()
      local interval = tonumber(uc.distance_indicator_update_interval) or 0.1
      if now - lastCheck < interval then return end
      lastCheck = now

      -- 定期重新扫描动作条，防止漏掉事件
      if now - lastRescan > 5 then
        lastRescan = now
        if DW_PLAYER_CLASS then testAllSlots() end
      end

      -- SetFont rebuilds the FontString, so only apply it when the size changes
      local diFontSize = tonumber(uc.distance_indicator_font_size) or 13
      if this._diFontSize ~= diFontSize then
        this._diFontSize = diFontSize
        this.text:SetFont(pfUI.font_default, diFontSize, "OUTLINE")
      end

      if not UnitExists("target") then
        this.text:SetText("")
        return
      end

      -- 先确认大致范围
      if CheckInteractDistance("target", 3) then
        distState.min = 0
        distState.max = 10
      elseif CheckInteractDistance("target", 2) then
        distState.min = 10
        distState.max = 11
      elseif CheckInteractDistance("target", 4) then
        distState.min = 11
        distState.max = 30
      else
        distState.min = 30
        distState.max = 200
      end

      if distState.max < 200 then
        if (distState.max - DW_RANGE_MODIFYER <= 5) then
          distState.max = distState.max - DW_MELEE_MODIFYER
        else
          distState.max = distState.max - DW_RANGE_MODIFYER
        end
      end
      if (distState.min - DW_RANGE_MODIFYER <= 5) then
        distState.min = distState.min - DW_MELEE_MODIFYER
      else
        distState.min = distState.min - DW_RANGE_MODIFYER
      end

      local canAttack = UnitCanAttack("player", "target")
      local canAssist = UnitCanAssist("player", "target")
      local tested = {}

      for slot, options in pairs(scanSlots) do
        local inRange = IsActionInRange(slot)
        local isRange = table.getn(options.ranges) == 2

        if not tested[options.yards] and (
              (canAttack and (options.t == "ATTACK" or options.t == "ALL"))
              or
              (canAssist and (options.t == "ASSIST" or options.t == "ALL"))
            ) and (isRange or options.ranges[1] < distState.max) then
          tested[options.yards] = 1
          if inRange then
            if inRange == 1 then
              if isRange then
                if distState.max > options.ranges[1] then
                  distState.max = options.ranges[1]
                end
                if distState.min > options.ranges[2] then
                  distState.min = options.ranges[2]
                end
              else
                if distState.max > options.ranges[1] then
                  distState.max = options.ranges[1]
                end
              end
            else
              if isRange then
                if distState.min >= options.ranges[2] and distState.min < options.ranges[1] then
                  distState.min = options.ranges[1]
                end
                if distState.max <= options.ranges[1] and distState.max > options.ranges[2] then
                  distState.max = options.ranges[2]
                end
              else
                if distState.min < options.ranges[1] then
                  distState.min = options.ranges[1]
                end
              end
            end
          end
        end
      end

      -- 显示距离
      local showPrefix = uc.distance_indicator_show_prefix == "1"
      local text
      if distState.min == 0 then
        text = "< " .. distState.max
      elseif distState.min == distState.max then
        text = distState.max .. "码"
      elseif distState.max > 41 then
        text = "> " .. distState.min
      else
        text = distState.min .. " - " .. distState.max
      end
      this.text:SetText(text)

      local r, g, b = getDistanceColor(distState.max)
      this.text:SetTextColor(r, g, b, 1)
    end)

    -- 退出时清理
    local cleanup = CreateFrame("Frame")
    cleanup:RegisterEvent("PLAYER_LOGOUT")
    cleanup:SetScript("OnEvent", function()
      if pfUI.distanceIndicator then
        pfUI.distanceIndicator:SetScript("OnUpdate", nil)
        pfUI.distanceIndicator = nil
      end
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
    end)
  end

  -- Check if UnitXP is available
  local hasUnitXP = pcall(UnitXP, "nop", "nop")
  if not hasUnitXP then
    -- UnitXP 未加载，启用简易距离检测
    SetupSimpleDistanceIndicator()
    return
  end

  local rawborder, border = GetBorderSize()

  -- 设置默认配置（若不存在）
  local uc = C.unitframes
  if uc.distance_indicator_font_size == nil then uc.distance_indicator_font_size = 13 end
  if uc.distance_indicator_face_color == nil then uc.distance_indicator_face_color = "1,0.3,0.3,1" end
  if uc.distance_indicator_back_color == nil then uc.distance_indicator_back_color = "0,1,0,1" end
  if uc.distance_indicator_deadzone_color == nil then uc.distance_indicator_deadzone_color = "1,1,0,1" end
  if uc.distance_indicator_outsight_color == nil then uc.distance_indicator_outsight_color = "0.66,0.66,0.66,1" end
  if uc.distance_indicator_outsight_icon == nil then uc.distance_indicator_outsight_icon = "1" end
  if uc.distance_indicator_sound == nil then uc.distance_indicator_sound = "1" end
  if uc.distance_indicator_sound_cooldown == nil then uc.distance_indicator_sound_cooldown = 2 end
  if uc.mouseover_tooltip_distance == nil then uc.mouseover_tooltip_distance = "0" end

  -- 鼠标悬停距离变色配置
  if uc.mouseover_distance_linear_color == nil then uc.mouseover_distance_linear_color = "0" end
  if uc.mouseover_distance_linear_from == nil then uc.mouseover_distance_linear_from = 0 end
  if uc.mouseover_distance_linear_to == nil then uc.mouseover_distance_linear_to = 40 end
  if uc.mouseover_distance_linear_color_from == nil then uc.mouseover_distance_linear_color_from = "0,1,0" end
  if uc.mouseover_distance_linear_color_to == nil then uc.mouseover_distance_linear_color_to = "1,0,0" end
  if uc.mouseover_distance_use_outsight == nil then uc.mouseover_distance_use_outsight = "0" end
  if uc.mouseover_distance_outsight_color == nil then uc.mouseover_distance_outsight_color = "0.66,0.66,0.66" end

  -- 距离指示器前缀文字开关
  if uc.distance_indicator_show_prefix == nil then uc.distance_indicator_show_prefix = "1" end

  -- 距离渐变开关
  if uc.distance_indicator_use_gradient == nil then uc.distance_indicator_use_gradient = "1" end

  -- 宠物距离显示配置
  if uc.distance_indicator_pet_mode == nil then uc.distance_indicator_pet_mode = "2" end
  if uc.distance_indicator_pet_font_size == nil then uc.distance_indicator_pet_font_size = "13" end
  if uc.distance_indicator_pet_color == nil then uc.distance_indicator_pet_color = "0,1,0,1" end
  if uc.distance_indicator_pet_offset_y == nil then uc.distance_indicator_pet_offset_y = "-20" end

  -- 新增：更新间隔配置
  if uc.distance_indicator_update_interval == nil then uc.distance_indicator_update_interval = "0.1" end
  if uc.mouseover_tooltip_update_interval == nil then uc.mouseover_tooltip_update_interval = "0.1" end

  -- 静态阈值表
  local thresholds = {
    {  5, 0.3, 0.5, 1.0 },
    {  8, 0.4, 0.7, 1.0 },
    { 20, 0.4, 0.9, 1.0 },
    { 30, 0.0, 1.0, 0.0 },
    { 35, 0.8, 1.0, 0.0 },
    { 41, 1.0, 1.0, 0.0 },
    { 999, 1.0, 1.0, 1.0 },
  }

  -- ---------- 配置缓存 ----------
  local cachedConfig = {
    font_size = 13,
    face_color = {1,0.3,0.3,1},
    back_color = {0,1,0,1},
    deadzone_color = {1,1,0,1},
    outsight_color = {0.66,0.66,0.66,1},
    show_outsight_icon = true,
    play_sound = true,
    sound_only_group = false,
    sound_cooldown = 2,
    show_prefix = true,
    use_gradient = true,
    pet_mode = 0,
    pet_color = {0,1,0,1},
    pet_font_size = 13,
    pet_offset_y = -20,
    distance_indicator_update_interval = 0.2,
    mouseover_tooltip_update_interval = 0.1,
  }

  -- 解析配置函数
  local function updateCachedConfig()
    cachedConfig.font_size = tonumber(C.unitframes.distance_indicator_font_size) or 13
    cachedConfig.face_color = {strsplit(",", C.unitframes.distance_indicator_face_color or "1,0.3,0.3,1")}
    cachedConfig.back_color = {strsplit(",", C.unitframes.distance_indicator_back_color or "0,1,0,1")}
    cachedConfig.deadzone_color = {strsplit(",", C.unitframes.distance_indicator_deadzone_color or "1,1,0,1")}
    cachedConfig.outsight_color = {strsplit(",", C.unitframes.distance_indicator_outsight_color or "0.66,0.66,0.66,1")}
    cachedConfig.show_outsight_icon = C.unitframes.distance_indicator_outsight_icon == "1"
    cachedConfig.play_sound = C.unitframes.distance_indicator_sound == "1"
    cachedConfig.sound_only_group = C.unitframes.distance_indicator_sound_only_group == "1"
    cachedConfig.sound_cooldown = tonumber(C.unitframes.distance_indicator_sound_cooldown) or 2
    cachedConfig.show_prefix = C.unitframes.distance_indicator_show_prefix == "1"
    cachedConfig.use_gradient = C.unitframes.distance_indicator_use_gradient == "1"
    cachedConfig.pet_mode = tonumber(C.unitframes.distance_indicator_pet_mode) or 0
    cachedConfig.pet_color = {strsplit(",", C.unitframes.distance_indicator_pet_color or "0,1,0,1")}
    cachedConfig.pet_font_size = tonumber(C.unitframes.distance_indicator_pet_font_size) or 13
    cachedConfig.pet_offset_y = tonumber(C.unitframes.distance_indicator_pet_offset_y) or -20
    -- 新增：读取更新间隔
    cachedConfig.distance_indicator_update_interval = tonumber(C.unitframes.distance_indicator_update_interval) or 0.2
    cachedConfig.mouseover_tooltip_update_interval = tonumber(C.unitframes.mouseover_tooltip_update_interval) or 0.1
  end

  -- 第一次解析
  updateCachedConfig()

  -- 周期性刷新配置（每2秒）
  local lastConfigRefresh = 0
  local CONFIG_REFRESH_INTERVAL = 2

  -- ---------- 野兽之眼检测辅助函数 ----------
  local function IsBeastEyeActive()
    if UnitClass("player") ~= "HUNTER" and UnitClass("player") ~= "猎人" then
      return false
    end
    if not UnitExists("pet") then
      return false
    end
    -- 检查野兽之眼Buff（图标：Ability_EyeOfTheOwl）
    for i = 1, 32 do
      local buff = UnitBuff("player", i)
      if not buff then break end
      if buff == "Interface\\Icons\\Ability_EyeOfTheOwl" then
        return true
      end
    end
    return false
  end

  -- ---------- 根据野兽之眼状态获取参考单位 ----------
  local function GetReferenceUnit()
    if IsBeastEyeActive() and UnitExists("pet") then
      return "pet"
    end
    return "player"
  end

  -- ---------- 独立距离指示器（可移动框架）----------
  local function CreateIndependentIndicators()
    if not pfUI.uf or not pfUI.uf.target then return false end

    if C.unitframes.distance_indicator == "1" then
      -- 清理旧框架
      if pfUI.distanceIndicator then
        pfUI.distanceIndicator:SetScript("OnUpdate", nil)
        pfUI.distanceIndicator:Hide()
        pfUI.distanceIndicator = nil
      end

      local frame = CreateFrame("Frame", "pfDistanceIndicator", UIParent)
      frame:SetWidth(90)
      frame:SetHeight(30)
      frame:SetPoint("CENTER", UIParent, "CENTER", 200, -30)

      -- 主文本
      frame.text = frame:CreateFontString(nil, "OVERLAY")
      frame.text:SetFont(pfUI.font_default, cachedConfig.font_size, "OUTLINE")
      frame.text:SetPoint("CENTER", frame, "CENTER")
      frame.text:SetTextColor(1, 1, 1, 1)
      frame.text:SetText("")

      -- 宠物距离文本
      frame.petText = frame:CreateFontString(nil, "OVERLAY")
      frame.petText:SetFont(pfUI.font_default, cachedConfig.pet_font_size, "OUTLINE")
      frame.petText:SetPoint("TOP", frame.text, "BOTTOM", 0, cachedConfig.pet_offset_y)
      frame.petText:SetTextColor(1, 1, 1, 1)
      frame.petText:Hide()

      -- 视野图标
      local icon = frame:CreateTexture(nil, "OVERLAY")
      icon:SetPoint("RIGHT", frame.text, "LEFT", -2, 0)
      local iconSize = tonumber(C.unitframes.distance_indicator_icon_size) or 20
      icon:SetWidth(iconSize)
      icon:SetHeight(iconSize)
      icon:Hide()
      frame.icon = icon

      local INSIGHT_TEXTURE = pfUI.media["img:oeye"]
      local OUTSIGHT_TEXTURE = pfUI.media["img:ceye"]

      local nextSoundPlayTime = 0
      local playerClass = UnitClass("player")
      local isHunter = (playerClass == "HUNTER" or playerClass == "猎人")

      local lastCheck = 0
      frame:SetScript("OnUpdate", function()
        local now = GetTime()
        if now - lastCheck < cachedConfig.distance_indicator_update_interval then return end
        lastCheck = now

        -- 定期刷新配置
        if now - lastConfigRefresh >= CONFIG_REFRESH_INTERVAL then
          updateCachedConfig()
          lastConfigRefresh = now
        end

        this:Show()

        -- 应用缓存的字体和位置
        -- SetFont rebuilds the FontString, so only reapply on actual change
        if this._fontSize ~= cachedConfig.font_size then
          this._fontSize = cachedConfig.font_size
          this.text:SetFont(pfUI.font_default, cachedConfig.font_size, "OUTLINE")
        end
        if this._petFontSize ~= cachedConfig.pet_font_size then
          this._petFontSize = cachedConfig.pet_font_size
          this.petText:SetFont(pfUI.font_default, cachedConfig.pet_font_size, "OUTLINE")
        end
        if this._petOffsetY ~= cachedConfig.pet_offset_y then
          this._petOffsetY = cachedConfig.pet_offset_y

          -- 间距变了：作废「宠物行排布」缓存，让下面那段按新高度重排一次
          -- （贴底模式下间距是通过框高度体现的，这里重设会打乱排布）
          this._petLayout = nil

          if not this.petText:IsShown() then
            this.petText:ClearAllPoints()
            this.petText:SetPoint("TOP", this.text, "BOTTOM", 0, cachedConfig.pet_offset_y)
          end
        end

        if UnitExists("target") then
          -- 获取参考单位（玩家或宠物）
          local refUnit = GetReferenceUnit()
          -- 目标距离
          local successDist, distance = pcall(UnitXP, "distanceBetween", refUnit, "target")
          if successDist and distance then
            -- 视线检测
            local successL, inSight = pcall(UnitXP, "inSight", refUnit, "target")
            local outSight = (successL and inSight == false)

            -- 处理图标
            if cachedConfig.show_outsight_icon then
              this.icon:SetTexture(outSight and OUTSIGHT_TEXTURE or INSIGHT_TEXTURE)
              this.icon:SetVertexColor(1, 1, 1)
              this.icon:Show()
            else
              this.icon:Hide()
            end

            local prefix = ""
            local r, g, b
            local meleeRange = false
            local behind = false

            -- 判断近战范围（使用参考单位）
            local successMelee, meleeDist = pcall(UnitXP, "distanceBetween", refUnit, "target", "meleeAutoAttack")
            if successMelee and meleeDist and meleeDist == 0 then
              meleeRange = true
              local successBehind, behindStatus = pcall(UnitXP, "behind", refUnit, "target")
              if successBehind then behind = behindStatus end

              if behind then
                prefix = cachedConfig.show_prefix and "近战\n" or ""
                r, g, b = cachedConfig.back_color[1], cachedConfig.back_color[2], cachedConfig.back_color[3]
              else
                prefix = cachedConfig.show_prefix and "打脸\n" or ""
                r, g, b = cachedConfig.face_color[1], cachedConfig.face_color[2], cachedConfig.face_color[3]

                -- 语音提醒（仅当参考单位是玩家时才触发，即未使用野兽之眼）
                if cachedConfig.play_sound and UnitAffectingCombat("player") and refUnit == "player" then
                  if not cachedConfig.sound_only_group or GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then
                    local ttime = GetTime()
                    if ttime > nextSoundPlayTime then
                      PlaySoundFile(pfUI.media["img:warn.ogg"])
                      nextSoundPlayTime = ttime + cachedConfig.sound_cooldown
                    end
                  end
                end
              end
            elseif isHunter and distance < 8 then
              prefix = cachedConfig.show_prefix and "盲区\n" or ""
              r, g, b = cachedConfig.deadzone_color[1], cachedConfig.deadzone_color[2], cachedConfig.deadzone_color[3]
            end

            -- 距离渐变（如果未设置特殊颜色）
            if not r then
              if cachedConfig.use_gradient then
                for i = 1, table.getn(thresholds) do
                  if distance <= thresholds[i][1] then
                    r, g, b = thresholds[i][2], thresholds[i][3], thresholds[i][4]
                    break
                  end
                end
              else
                r, g, b = 1, 1, 1
              end
            end

            -- 视野外强制使用配置颜色
            if outSight then
              r, g, b = cachedConfig.outsight_color[1], cachedConfig.outsight_color[2], cachedConfig.outsight_color[3]
            end

            this.text:SetTextColor(r, g, b, 1)
            this.text:SetText(prefix .. string.format("%.1f", distance))
          else
            this.icon:Hide()
            this.text:SetText("")
            this.text:SetTextColor(1, 1, 1, 1)
          end
        else
          this.icon:Hide()
          this.text:SetText("")
          this.text:SetTextColor(1, 1, 1, 1)
        end

        -- 宠物距离处理（实时检测野兽之眼，不再依赖事件）
        local showPetDistance = false
        if isHunter and cachedConfig.pet_mode > 0 and UnitExists("pet") then
          if cachedConfig.pet_mode == 1 then
            showPetDistance = true
          elseif cachedConfig.pet_mode == 2 then
            -- 实时检查野兽之眼 Buff
            local hasEotB = false
            for i = 1, 32 do
              local buff = UnitBuff("player", i)
              if not buff then break end
              if buff == "Interface\\Icons\\Ability_EyeOfTheOwl" then
                hasEotB = true
                break
              end
            end
            showPetDistance = hasEotB
          end
        end

        if showPetDistance then
          local success, petDist = pcall(UnitXP, "distanceBetween", "player", "pet")
          if success and petDist then
            this.petText:SetText(string.format("%.1f", petDist))
            this.petText:SetTextColor(cachedConfig.pet_color[1], cachedConfig.pet_color[2], cachedConfig.pet_color[3], cachedConfig.pet_color[4] or 1)
            this.petText:Show()
          else
            this.petText:Hide()
          end
        else
          this.petText:Hide()
        end

        -- 动态调整框架高度
        local totalHeight = 0
        local textShown = this.text:GetText() and this.text:GetText() ~= ""
        local petShown = this.petText:IsShown()

        if textShown then
          totalHeight = totalHeight + this.text:GetHeight()
        end
        if petShown then
          totalHeight = totalHeight + math.abs(cachedConfig.pet_offset_y) + this.petText:GetHeight()
        end

        if totalHeight > 0 then
          this:SetHeight(totalHeight)
        else
          this:SetHeight(30)
        end

        -- 宠物行开启时的排布：主文本顶对齐 + 宠物文本贴底。
        -- ⛔ 原来主文本是 CENTER、宠物文本挂在它下方，而框只向下长一半，
        --    所以宠物行会溢出框的底边，压到下方的东西上（能量条/连击点叠在一起）。
        --    只在「开/关宠物行」切换时重设，避免每帧 ClearAllPoints 抖动。
        local petLayout = petShown and true or false

        if this._petLayout ~= petLayout then
          this._petLayout = petLayout

          this.text:ClearAllPoints()
          this.petText:ClearAllPoints()

          if petLayout then
            this.text:SetPoint("TOP", this, "TOP", 0, -(this.text:GetHeight() or 0) / 2 - 1)
            this.petText:SetPoint("BOTTOM", this, "BOTTOM", 0, 1)
          else
            this.text:SetPoint("CENTER", this, "CENTER")
            this.petText:SetPoint("TOP", this.text, "BOTTOM", 0, cachedConfig.pet_offset_y)
          end
        end
      end)

      pfUI.distanceIndicator = frame
      pfUI.movables["pfDistanceIndicator"] = frame
      UpdateMovable(frame)
    end

    return true
  end

  -- 鼠标悬停距离颜色函数（使用缓存配置）
  local function GetMouseoverDistanceColor(distance, unit)
    local r, g, b = 1, 1, 1

    if C.unitframes.mouseover_distance_use_outsight == "1" then
      local refUnit = GetReferenceUnit()
      local success, inSight = pcall(UnitXP, "inSight", refUnit, unit or "mouseover")
      if success and inSight == false then
        local outColor = {strsplit(",", C.unitframes.mouseover_distance_outsight_color)}
        return tonumber(outColor[1]) or 0.66, tonumber(outColor[2]) or 0.66, tonumber(outColor[3]) or 0.66
      end
    end

    if C.unitframes.mouseover_distance_linear_color == "1" then
      local fromDist = tonumber(C.unitframes.mouseover_distance_linear_from) or 0
      local toDist = tonumber(C.unitframes.mouseover_distance_linear_to) or 40
      local fromColor = {strsplit(",", C.unitframes.mouseover_distance_linear_color_from or "0,1,0")}
      local toColor = {strsplit(",", C.unitframes.mouseover_distance_linear_color_to or "1,0,0")}

      local clampedDist = math.min(math.max(distance, fromDist), toDist)
      local t = (clampedDist - fromDist) / (toDist - fromDist)
      r = tonumber(fromColor[1]) + (tonumber(toColor[1]) - tonumber(fromColor[1])) * t
      g = tonumber(fromColor[2]) + (tonumber(toColor[2]) - tonumber(fromColor[2])) * t
      b = tonumber(fromColor[3]) + (tonumber(toColor[3]) - tonumber(fromColor[3])) * t
    end

    return r, g, b
  end

  -- 鼠标悬停距离提示设置（增加节流，使用可配置间隔）
  local function SetupMouseoverTooltip()
    if C.unitframes.mouseover_tooltip_distance ~= "1" then return end

    local origOnShow = GameTooltip:GetScript("OnShow")
    GameTooltip:SetScript("OnShow", function()
        if type(origOnShow) == "function" then origOnShow() end

        if not UnitExists("mouseover") then return end
        local refUnit = GetReferenceUnit()
        local success, dist = pcall(UnitXP, "distanceBetween", refUnit, "mouseover")
        if not success or not dist then return end

        local unitSuffix = GetLocale() == "zhCN" and "码" or "yd"
        local newText = string.format("%.1f %s", dist, unitSuffix)
        local r, g, b = GetMouseoverDistanceColor(dist, "mouseover")

        for i = 1, GameTooltip:NumLines() do
            local textObj = _G["GameTooltipTextLeft" .. i]
            if textObj then
                local text = textObj:GetText() or ""
                if string.find(text, "%d+%.?%d*%s*[码yd]+$") then
                    textObj:SetText(newText)
                    textObj:SetTextColor(r, g, b)
                    return
                end
            end
        end

        local line = GameTooltip:NumLines() + 1
        GameTooltip:AddLine(newText, r, g, b)
        local newTextObj = _G["GameTooltipTextLeft" .. line]
        if newTextObj then
            GameTooltip:SetHeight(GameTooltip:GetHeight() + newTextObj:GetHeight())
        end
    end)

    -- 创建节流的更新器（使用可配置间隔）
    if not pfUI.mouseoverTooltipUpdater then
        local updater = CreateFrame("Frame", nil, UIParent)
        local lastUpdate = 0
        updater:SetScript("OnUpdate", function()
            local now = GetTime()
            if now - lastUpdate < cachedConfig.mouseover_tooltip_update_interval then return end
            lastUpdate = now

            if C.unitframes.mouseover_tooltip_distance ~= "1" then return end
            if not GameTooltip:IsVisible() then return end
            if not UnitExists("mouseover") then return end

            local refUnit = GetReferenceUnit()
            local success, dist = pcall(UnitXP, "distanceBetween", refUnit, "mouseover")
            if not success or not dist then return end

            local unitSuffix = GetLocale() == "zhCN" and "码" or "yd"
            local newText = string.format("%.1f %s", dist, unitSuffix)
            local r, g, b = GetMouseoverDistanceColor(dist, "mouseover")

            for i = 1, GameTooltip:NumLines() do
                local textObj = _G["GameTooltipTextLeft" .. i]
                if textObj then
                    local text = textObj:GetText() or ""
                    if string.find(text, "%d+%.?%d*%s*[码yd]+$") then
                        textObj:SetText(newText)
                        textObj:SetTextColor(r, g, b)
                        break
                    end
                end
            end
        end)
        pfUI.mouseoverTooltipUpdater = updater
    end
  end

  -- ---------- 初始化 ----------
  CreateIndependentIndicators()

  -- 事件管理：确保退出时清理
  local initFrame = CreateFrame("Frame")
  initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  initFrame:RegisterEvent("PLAYER_LOGOUT")
  initFrame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      -- 停止所有 OnUpdate 脚本，防止内存残留
      if pfUI.distanceIndicator then
        pfUI.distanceIndicator:SetScript("OnUpdate", nil)
        pfUI.distanceIndicator = nil
      end
      if pfUI.mouseoverTooltipUpdater then
        pfUI.mouseoverTooltipUpdater:SetScript("OnUpdate", nil)
        pfUI.mouseoverTooltipUpdater = nil
      end
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
    end

    CreateIndependentIndicators()
    SetupMouseoverTooltip()
    this:UnregisterAllEvents()
  end)

  -- Enhanced Distance API (修改后支持野兽之眼)
  pfUI.api.GetPreciseDistance = function(unit1, unit2)
    if not unit2 then
      unit2 = unit1
      unit1 = "player"
    end
    -- 如果第一个单位是"player"且野兽之眼激活，则替换为"pet"
    if unit1 == "player" and IsBeastEyeActive() and UnitExists("pet") then
      unit1 = "pet"
    end
    local success, distance = pcall(UnitXP, "distanceBetween", unit1, unit2)
    if success then return distance end
    return nil
  end

  pfUI.api.IsInMeleeRange = function(unit)
    local refUnit = (unit == "player" and IsBeastEyeActive() and UnitExists("pet")) and "pet" or "player"
    local success, distance = pcall(UnitXP, "distanceBetween", refUnit, unit, "meleeAutoAttack")
    if success and distance then
      return distance <= 5
    end
    return nil
  end

  pfUI.api.GetAoEDistance = function(unit1, unit2)
    if not unit2 then
      unit2 = unit1
      unit1 = "player"
    end
    if unit1 == "player" and IsBeastEyeActive() and UnitExists("pet") then
      unit1 = "pet"
    end
    local success, distance = pcall(UnitXP, "distanceBetween", unit1, unit2, "AoE")
    if success then return distance end
    return nil
  end

  pfUI.api.TargetNearestEnemy = function()
    local success, found = pcall(UnitXP, "target", "nearestEnemy")
    return success and found
  end

  pfUI.api.TargetHighestHP = function()
    local success, found = pcall(UnitXP, "target", "mostHP")
    return success and found
  end

  pfUI.api.TargetNextEnemy = function()
    local success, found = pcall(UnitXP, "target", "nextEnemyInCycle")
    return success and found
  end

  pfUI.api.TargetPreviousEnemy = function()
    local success, found = pcall(UnitXP, "target", "previousEnemyInCycle")
    return success and found
  end

  pfUI.api.TargetNextMarked = function(order)
    local success, found = pcall(UnitXP, "target", "nextMarkedEnemyInCycle", order)
    return success and found
  end

  pfUI.api.UnitInLineOfSight = function(unit1, unit2)
    if not unit2 then
      unit2 = unit1
      unit1 = "player"
    end
    if unit1 == "player" and IsBeastEyeActive() and UnitExists("pet") then
      unit1 = "pet"
    end
    local success, inSight = pcall(UnitXP, "inSight", unit1, unit2)
    if success then return inSight end
    return nil
  end

  pfUI.api.UnitIsBehind = function(unit1, unit2)
    if not unit2 then
      unit2 = unit1
      unit1 = "player"
    end
    if unit1 == "player" and IsBeastEyeActive() and UnitExists("pet") then
      unit1 = "pet"
    end
    local success, behind = pcall(UnitXP, "behind", unit1, unit2)
    if success then return behind end
    return nil
  end

  -- 将野兽之眼检测函数暴露给API
  pfUI.api.IsBeastEyeActive = IsBeastEyeActive
end)