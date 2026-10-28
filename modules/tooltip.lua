pfUI:RegisterModule("tooltip", "vanilla", function ()
  local rawborder, default_border = GetBorderSize()
  local barheight = tonumber(C.tooltip.barheight) or 12

  pfUI.tooltip = CreateFrame('Frame', "pfTooltip", GameTooltip)
  pfUI.tooltip.anchorframe = CreateFrame('Frame', "pfTooltipAnchor", UIParent)
  pfUI.tooltip.anchorframe:SetWidth(128)
  pfUI.tooltip.anchorframe:SetHeight(72)
  pfUI.tooltip.anchorframe:SetPoint("TOP", UIParent, "TOP", 0, -50)
  pfUI.tooltip.anchorframe:Hide()
  UpdateMovable(pfUI.tooltip.anchorframe)

  function pfUI.tooltip:GetAnchorPoint()
    local prefix = "TOP"
    local suffix = "RIGHT"
    local px, py = UIParent:GetCenter()
    local tx, ty = this.anchorframe:GetCenter()
    if (tx < px) then
      suffix = "LEFT"
    end
    if (ty < py) then
      prefix = "BOTTOM"
    end
    return prefix..suffix
  end

  -- ===============================================
  -- 3D 模型（人物像）功能
  -- ===============================================
  -- 色盲模式：装备品质文字标记（开启后在物品名字后追加 [精良]/[史诗] 等标签，
  -- 让色觉障碍玩家无需依赖颜色即可分辨品质）
  local colorblind_labels = {
    [0] = "劣质",   -- 灰色
    [1] = "普通",   -- 白色
    [2] = "优秀",   -- 绿色
    [3] = "精良",   -- 蓝色
    [4] = "史诗",   -- 紫色
    [5] = "传说",   -- 橙色
    [6] = "神器",   -- 神器色
    [7] = "传家宝", -- 传家宝色
  }
  -- 从名字行的 |cffRRGGBB 颜色反推品质（不依赖 GetItemInfo 缓存/链接格式，最稳）
  local function colorblind_quality_from_text(text)
    if not text then return nil end
    local hex = string.match(text, "|cff(%x%x%x%x%x%x)")
    if hex and ITEM_QUALITY_COLORS then
      local r = tonumber(string.sub(hex,1,2),16)/255
      local g = tonumber(string.sub(hex,3,4),16)/255
      local b = tonumber(string.sub(hex,5,6),16)/255
      local best, bestd = nil, 1
      for q=0,7 do
        local c = ITEM_QUALITY_COLORS[q]
        if c and c.r then
          local d = math.abs(c.r-r)+math.abs(c.g-g)+math.abs(c.b-b)
          if d < bestd then bestd, best = d, q end
        end
      end
      if best and bestd < 0.1 then return best end
    end
    return nil
  end
  -- 用于精确测量追加标签宽度的隐藏 FontString（避免在 SetText 后立即读取 GetStringWidth 可能滞后的问题）
  local colorblind_measure = GameTooltip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  colorblind_measure:Hide()

  local modelFrame = nil
  local modelRotationEnabled = false
  local modelRotationSpeed = 0
  local modelLastUpdate = 0

  -- 创建模型框架
  local function Create3DModelFrame()
    if modelFrame then return end
    modelFrame = CreateFrame("PlayerModel", "pfTooltipModel", GameTooltip)
    modelFrame:SetWidth(tonumber(C.tooltip.modelsize))
    modelFrame:SetHeight(tonumber(C.tooltip.modelsize))
    modelFrame:SetFrameStrata("TOOLTIP")
    modelFrame:SetFrameLevel(GameTooltip:GetFrameLevel() + 1)
    modelFrame:SetAlpha(0.9)
    modelFrame:Hide()

    -- 鼠标旋转支持
    if C.tooltip.modelrotation == "1" then
      modelFrame:EnableMouse(true)
      -- ⛔ 1.12 引擎只给 OnUpdate 传一个参数 elapsed ⇒ 不能写 function(self, elapsed)
      --   （self 会吃掉 elapsed，self:GetFacing() 变成对数字取索引、每帧报错）。
      --   按注意事项第 10 条：直接引用闭包里已创建的 frame 对象 modelFrame，不用 self。
      modelFrame:SetScript("OnUpdate", function(elapsed)
        elapsed = elapsed or 0.016
        modelLastUpdate = modelLastUpdate + elapsed
        if modelLastUpdate >= 0.016 then
          if modelRotationEnabled and modelRotationSpeed ~= 0 then
            local facing = modelFrame:GetFacing()
            modelFrame:SetFacing(facing + modelRotationSpeed * 0.1)
          end
          modelLastUpdate = 0
        end
      end)
      modelFrame:SetScript("OnEnter", function() modelRotationEnabled = true end)
      modelFrame:SetScript("OnLeave", function() modelRotationEnabled = false end)
    end
  end

  -- 更新模型位置（根据配置附着到 GameTooltip 的边缘）
  local function UpdateModelPosition()
    if not modelFrame or not modelFrame:IsShown() then return end
    local pos = C.tooltip.modelposition
    local offX = tonumber(C.tooltip.modeloffsetx)
    local offY = tonumber(C.tooltip.modeloffsety)
    local attachPoint = pos
    local relativePoint = pos
    local anchorParent = GameTooltip

    if pos == "RIGHT" then
      attachPoint = "LEFT"
      relativePoint = "RIGHT"
    elseif pos == "LEFT" then
      attachPoint = "RIGHT"
      relativePoint = "LEFT"
    elseif pos == "TOP" then
      attachPoint = "BOTTOM"
      relativePoint = "TOP"
    elseif pos == "BOTTOM" then
      attachPoint = "TOP"
      relativePoint = "BOTTOM"
    else
      attachPoint = pos
      relativePoint = pos
    end

    modelFrame:ClearAllPoints()
    modelFrame:SetPoint(attachPoint, anchorParent, relativePoint, offX, offY)

    -- 边缘定位（可选，避免模型超出屏幕）
    if C.tooltip.modeledge == "1" then
      local screenWidth, screenHeight = GetScreenWidth(), GetScreenHeight()
      local left, right, bottom, top = modelFrame:GetLeft(), modelFrame:GetRight(), modelFrame:GetBottom(), modelFrame:GetTop()
      if left and right and bottom and top then
        local offsetX, offsetY = 0, 0
        if left < 0 then offsetX = -left + 5 end
        if right > screenWidth then offsetX = screenWidth - right - 5 end
        if bottom < 0 then offsetY = -bottom + 5 end
        if top > screenHeight then offsetY = screenHeight - top - 5 end
        if offsetX ~= 0 or offsetY ~= 0 then
          modelFrame:SetPoint(attachPoint, anchorParent, relativePoint, offX + offsetX, offY + offsetY)
        end
      end
    end
  end

  -- 显示模型
  local function ShowModelForUnit(unit)
    if C.tooltip.show3dmodel ~= "1" then return end
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then
      if modelFrame then modelFrame:Hide() end
      return
    end

    if not modelFrame then
      Create3DModelFrame()
    end

    if modelFrame and UnitIsVisible(unit) then
      modelFrame:SetUnit(unit)
      modelFrame:SetFacing(0)
      modelFrame:SetWidth(tonumber(C.tooltip.modelsize))
      modelFrame:SetHeight(tonumber(C.tooltip.modelsize))
      modelFrame:Show()
      UpdateModelPosition()
    else
      if modelFrame then modelFrame:Hide() end
    end
  end

  -- 隐藏模型
  local function HideModel()
    if modelFrame then
      modelFrame:Hide()
      modelFrame:ClearModel()
    end
  end

  -- 更新模型位置（供 OnUpdate 调用）
  local function OnTooltipUpdate()
    if modelFrame and modelFrame:IsShown() then
      UpdateModelPosition()
    end
  end
  -- ===============================================

  if C.tooltip.position == "cursor" then
    function _G.GameTooltip_SetDefaultAnchor(tooltip, parent)
      tooltip:SetOwner(parent, "ANCHOR_CURSOR")
      if C.tooltip.cursoralign ~= "native" then
        -- create mouse follow frame
        if not tooltip.cursor then
          tooltip.cursor = CreateFrame("Frame", nil, UIParent)
          tooltip.cursor:SetWidth(tonumber(C.tooltip.cursoroffset) * 2)
          tooltip.cursor:SetHeight(tonumber(C.tooltip.cursoroffset) * 2)
          tooltip.cursor:SetScript("OnUpdate", function()
            -- throttle - cursor following doesn't need to be every frame
            if (this.tick or 0) > GetTime() then return end
            this.tick = GetTime() + (pfUI.throttle and pfUI.throttle:Get("tooltip_cursor") or 0.1)

            local scale = UIParent:GetScale()
            local x, y = GetCursorPosition()
            this:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x/scale, y/scale)
            if C.tooltip.cursoralign == "top" then
              tooltip.cursor:SetWidth(tooltip:GetWidth())
            end
          end)
        end

        -- adjust tooltip to mouse frame
        if C.tooltip.cursoralign == "top" then
          tooltip:SetPoint("BOTTOMLEFT", tooltip.cursor, "TOPLEFT", 0, 0)
        elseif C.tooltip.cursoralign == "left" then
          tooltip:SetPoint("BOTTOMRIGHT", tooltip.cursor, "LEFT", 0, 0)
        elseif C.tooltip.cursoralign == "right" then
          tooltip:SetPoint("BOTTOMLEFT", tooltip.cursor, "RIGHT", 0, 0)
        end
      end
    end
  end

  local units = { "mouseover", "player", "pet", "target", "party", "partypet", "raid", "raidpet" }
  function pfUI.tooltip:GetUnit()
    pfUI.tooltip.unit = "none"

    for i, unit in pairs(units) do
      if unit == "party" or unit == "partypet" then
        for i=1,4 do
          if UnitExists(unit .. i) and ( UnitName(unit .. i) == GameTooltipTextLeft1:GetText() or UnitPVPName(unit .. i) == GameTooltipTextLeft1:GetText() ) then
            pfUI.tooltip.unit = unit .. i
            return pfUI.tooltip.unit
          end
        end
      elseif unit == "raid" or unit == "raidpet" then
        for i=1,40 do
          if UnitExists(unit .. i) and ( UnitName(unit .. i) == GameTooltipTextLeft1:GetText() or UnitPVPName(unit .. i) == GameTooltipTextLeft1:GetText() ) then
            pfUI.tooltip.unit = unit .. i
            return pfUI.tooltip.unit
          end
        end
      else
        if UnitExists(unit) and ( UnitName(unit) == GameTooltipTextLeft1:GetText() or UnitPVPName(unit) == GameTooltipTextLeft1:GetText() ) then
          pfUI.tooltip.unit = unit
          return pfUI.tooltip.unit
        end
      end
    end
    return pfUI.tooltip.unit
  end

  pfUI.tooltip.dodge = {
    "pfPanelRight", "pfChatRight"
  }

  if C.appearance.bags.movable == "0" then
    table.insert(pfUI.tooltip.dodge, "pfBag")
  end

  pfUI.tooltip:SetAllPoints()
  pfUI.tooltip:SetScript("OnShow", function()
      pfUI.tooltip:Update()
      if GameTooltip:GetAnchorType() == "ANCHOR_NONE" then
        GameTooltip:ClearAllPoints()
        if C.tooltip.position == "bottom" then
          if pfUI.panel and pfUI.panel.right:IsShown() then
            GameTooltip:SetPoint("BOTTOMRIGHT", pfUI.panel.right, "TOPRIGHT", 0, default_border*2)
          else
            GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -5, 5)
          end
        elseif C.tooltip.position == "chat" then
          local anchor = nil

          for _, frame in pairs(pfUI.tooltip.dodge) do
            if _G[frame] and _G[frame]:IsShown() then
              anchor = _G[frame]
            end
          end

          if anchor then
            GameTooltip:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, default_border*3)
          else
            GameTooltip:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -5, 5)
          end
        elseif C.tooltip.position == "free" then
          local point = this:GetAnchorPoint()
          if point then
            GameTooltip:SetPoint(point, this.anchorframe, point, 0, 0)
          end
        end
      end
    end)

  pfUI.tooltipStatusBar = CreateFrame('Frame', nil, GameTooltipStatusBar)
  -- 文字覆盖整条并居中（与法力条统一：文本置于生命条内部，避免与上方法力条重叠）
  pfUI.tooltipStatusBar:SetAllPoints()
  pfUI.tooltipStatusBar:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  pfUI.tooltipStatusBar:SetScript("OnEvent", function()
    this.name = UnitName("mouseover")
    this.level = UnitLevel("mouseover")
  end)

  pfUI.tooltipStatusBar.text = CreateFrame("Frame", nil, pfUI.tooltipStatusBar)
  pfUI.tooltipStatusBar.text:SetFrameLevel(16)
  pfUI.tooltipStatusBar.text:SetAllPoints()

  pfUI.tooltipStatusBar.HP = pfUI.tooltipStatusBar.text:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  -- 文字覆盖整条宽度，垂直位置随 bar_text_offy 偏移（相对条中心）
  pfUI.tooltipStatusBar.HP:SetPoint("LEFT", pfUI.tooltipStatusBar.text, "LEFT", 4, tonumber(C.tooltip.bar_text_offy) or 0)
  pfUI.tooltipStatusBar.HP:SetPoint("RIGHT", pfUI.tooltipStatusBar.text, "RIGHT", -4, tonumber(C.tooltip.bar_text_offy) or 0)
  pfUI.tooltipStatusBar.HP:SetJustifyH("CENTER")
  pfUI.tooltipStatusBar.HP:SetJustifyV("MIDDLE")
  pfUI.tooltipStatusBar.HP:SetNonSpaceWrap(false)
  pfUI.tooltipStatusBar.HP:SetFontObject(GameFontWhite)
  pfUI.tooltipStatusBar.HP:SetFont(C.tooltip.font_tooltip, tonumber(C.tooltip.bar_font_size) or 11, "OUTLINE")

  if GameTooltip.SetClampRectInsets then
    -- 上下方各预留状态条高度 + 边框，避免贴顶/贴底时被裁掉（关闭能量条时只留一条）
    local barCount = C.tooltip.manabar == "1" and 2 or 1
    local inset = math.ceil(barheight * barCount + default_border * 2)
    if C.tooltip.barpos == "BOTTOM" then
      GameTooltip:SetClampRectInsets(0, 0, 0, inset)
    else
      GameTooltip:SetClampRectInsets(0, 0, inset, 0)
    end
  else
    GameTooltipStatusBar:SetClampedToScreen(true)
    pfUI.tooltipStatusBar:SetClampedToScreen(true)
  end

  pfUI.tooltipStatusBar:SetScript("OnUpdate", function()
    local hp = GameTooltipStatusBar:GetValue()
    local _, hpmax = GameTooltipStatusBar:GetMinMaxValues()
    local rhp, rhpmax, estimated

    if hpmax > 100 or (round(hpmax/100*hp) ~= hp) then
      rhp, rhpmax = hp, hpmax
    elseif pfUI.libhealth and pfUI.libhealth.enabled then
      rhp, rhpmax, estimated = pfUI.libhealth:GetUnitHealthByName(this.name, this.level, tonumber(hp), tonumber(hpmax))
    elseif MobHealthFrame then
      local index = (this.name or "") .. ":" .. (this.level or "")
      local ppp = MobHealth_PPP(index)
      if perc and ppp and ppp > 0 and not UnitIsUnit("mouseover", "pet") then
        rhp = round(hp * ppp)
        rhpmax = round(100 * ppp)
        estimated = true
      end
    end

    local hpText
    if C.tooltip.alwaysperc == "0" and ( estimated or hpmax > 100 or round(hpmax/100*hp) ~= hp ) then
      hpText = string.format("%s / %s", Abbreviate(rhp), Abbreviate(rhpmax))
    elseif hpmax > 0 then
      hpText = string.format("%s%%", ceil(hp/hpmax*100))
    else
      hpText = ""
    end
    if this._lastHPText ~= hpText then
      this._lastHPText = hpText
      pfUI.tooltipStatusBar.HP:SetText(hpText)
    end
  end)

  GameTooltipStatusBar:SetHeight(barheight)
  GameTooltipStatusBar:ClearAllPoints()

  GameTooltipPowerBar = CreateFrame("StatusBar", "GameTooltipPowerBar", GameTooltip)
  GameTooltipPowerBar:SetHeight(barheight)
  GameTooltipPowerBar:SetStatusBarTexture(pfUI.media[C.tooltip.statusbar.texture])
  GameTooltipPowerBar:ClearAllPoints()
  GameTooltipPowerBar:Hide()

  -- 整组锚定：生命始终在能量上方；按 barpos 决定整组贴提示框的上方还是下方，
  -- 避免贴顶时能量条向提示框内探入造成重叠。关闭能量条时生命条直接贴提示框，不留空隙。
  if C.tooltip.manabar ~= "1" then
    -- 不显示能量条：生命条直接贴提示框上/下
    if C.tooltip.barpos == "BOTTOM" then
      GameTooltipStatusBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -default_border)
      GameTooltipStatusBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, -default_border)
    else
      GameTooltipStatusBar:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, default_border)
      GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", GameTooltip, "TOPRIGHT", 0, default_border)
    end
    GameTooltipPowerBar:Hide()
  elseif C.tooltip.barpos == "BOTTOM" then
    -- 生命条贴提示框下方，能量条贴生命条下方（整组在提示框外、向下生长）
    GameTooltipStatusBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -default_border)
    GameTooltipStatusBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, -default_border)
    GameTooltipPowerBar:SetPoint("TOPLEFT", GameTooltipStatusBar, "BOTTOMLEFT", 0, 0)
    GameTooltipPowerBar:SetPoint("TOPRIGHT", GameTooltipStatusBar, "BOTTOMRIGHT", 0, 0)
  else
    -- 能量条贴提示框上方，生命条贴能量条上方（整组在提示框外、向上生长，能量条不再压住提示框顶部）
    GameTooltipPowerBar:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, default_border)
    GameTooltipPowerBar:SetPoint("BOTTOMRIGHT", GameTooltip, "TOPRIGHT", 0, default_border)
    GameTooltipStatusBar:SetPoint("BOTTOMLEFT", GameTooltipPowerBar, "TOPLEFT", 0, 0)
    GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", GameTooltipPowerBar, "TOPRIGHT", 0, 0)
  end
  GameTooltipStatusBar:SetStatusBarTexture(pfUI.media[C.tooltip.statusbar.texture])
  CreateBackdrop(GameTooltipStatusBar, nil, nil, tonumber(C.tooltip.alpha))
  CreateBackdrop(GameTooltipPowerBar, nil, nil, tonumber(C.tooltip.alpha))

  pfUI.tooltipPower = CreateFrame('Frame', nil, GameTooltipPowerBar)
  -- 文字覆盖整条并居中（参考 zTip：文本置于条内，而非浮在条上方）
  pfUI.tooltipPower:SetAllPoints()

  pfUI.tooltipPower.text = CreateFrame("Frame", nil, pfUI.tooltipPower)
  pfUI.tooltipPower.text:SetFrameLevel(16)
  pfUI.tooltipPower.text:SetAllPoints()

  pfUI.tooltipPower.MP = pfUI.tooltipPower.text:CreateFontString("Status", "OVERLAY", "GameFontNormal")
  -- 文字覆盖整条宽度，垂直位置随 bar_text_offy 偏移（相对条中心）
  pfUI.tooltipPower.MP:SetPoint("LEFT", pfUI.tooltipPower.text, "LEFT", 4, tonumber(C.tooltip.bar_text_offy) or 0)
  pfUI.tooltipPower.MP:SetPoint("RIGHT", pfUI.tooltipPower.text, "RIGHT", -4, tonumber(C.tooltip.bar_text_offy) or 0)
  pfUI.tooltipPower.MP:SetJustifyH("CENTER")
  pfUI.tooltipPower.MP:SetJustifyV("MIDDLE")
  pfUI.tooltipPower.MP:SetNonSpaceWrap(false)
  pfUI.tooltipPower.MP:SetFontObject(GameFontWhite)
  pfUI.tooltipPower.MP:SetFont(C.tooltip.font_tooltip, tonumber(C.tooltip.bar_font_size) or 11, "OUTLINE")
  pfUI.tooltipPower.MP:SetText("")

  -- 实时刷新法力值（与生命值 OnUpdate 同机制，单位无效或无法力时静默跳过）
  GameTooltipPowerBar:SetScript("OnUpdate", function()
    local unit = this.unit
    if not unit or not UnitExists(unit) then return end
    local mp = UnitMana(unit)
    local mpm = UnitManaMax(unit)
    if not mpm or mpm <= 0 then return end
    GameTooltipPowerBar:SetMinMaxValues(0, mpm)
    GameTooltipPowerBar:SetValue(mp)
    local mpText
    if C.tooltip.manaperc == "1" then
      mpText = string.format("%s%%", ceil(mp / mpm * 100))
    else
      mpText = string.format("%s / %s", Abbreviate(mp), Abbreviate(mpm))
    end
    if this._lastMPText ~= mpText then
      this._lastMPText = mpText
      pfUI.tooltipPower.MP:SetText(mpText)
    end
  end)
  -- ===============================================

  GameTooltipStatusBar.SetStatusBarColor_orig = GameTooltipStatusBar.SetStatusBarColor
  GameTooltipStatusBar.SetStatusBarColor = function() return end

  -- 根据是否真正显示能量条重新锚定生命条：
  -- 显示能量条时生命条压在其上（整组在提示框外）；不显示时生命条直接贴提示框，
  -- 消除「无能量的怪物/NPC/物品提示」在能量条位置留下的空白空隙。
  function pfUI.tooltip:LayoutBars(showPower)
    if pfUI.tooltip._powerLayout == (showPower and "on" or "off") then return end
    pfUI.tooltip._powerLayout = showPower and "on" or "off"
    GameTooltipStatusBar:ClearAllPoints()
    if showPower and C.tooltip.barpos ~= "BOTTOM" then
      -- 贴顶且显示能量条：生命条压在能量条上（能量条贴顶、生命在其上）
      GameTooltipStatusBar:SetPoint("BOTTOMLEFT", GameTooltipPowerBar, "TOPLEFT", 0, 0)
      GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", GameTooltipPowerBar, "TOPRIGHT", 0, 0)
    else
      -- 其余情况（贴底 / 不显示能量条）：生命条直接贴提示框上或下
      if C.tooltip.barpos == "BOTTOM" then
        GameTooltipStatusBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 0, -default_border)
        GameTooltipStatusBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", 0, -default_border)
      else
        GameTooltipStatusBar:SetPoint("BOTTOMLEFT", GameTooltip, "TOPLEFT", 0, default_border)
        GameTooltipStatusBar:SetPoint("BOTTOMRIGHT", GameTooltip, "TOPRIGHT", 0, default_border)
      end
    end
  end

  -- ===============================================
  -- 能量条（法力/怒气/能量）：显隐 + 数值刷新（幂等）
  -- ===============================================
  -- 参考 Automatonex 的 zTip：条的显隐**不能只在提示框 OnShow 里决定**。
  -- ⛔ 引擎在「单位提示 → 非单位提示（招牌 / 信箱 / 物品 / 别的单位）」之间经常**不重新触发 OnShow**
  --    ⇒ pfUI.tooltip:Update() 根本跑不到 ⇒ 上一个单位的法力条会一直挂在物体提示上
  --    （2026-09-13 录屏实测：招牌「维勒武器店」上挂着玩家/单位的 4772 / 4772 蓝条，且此后一直残留）。
  -- 所以把这段抽成**可反复调用**的 UpdateBars：Update()（OnShow）与 OnUpdate 的内容签名守门都调它。
  function pfUI.tooltip:UpdateBars(unit)
    if not unit or unit == "none" or not UnitExists(unit) then
      GameTooltipPowerBar:Hide()
      pfUI.tooltipPower:Hide()
      pfUI.tooltipPower.MP:SetText("")
      -- ⛔ 归属必须一起清掉：留着旧 unit 时，OnUpdate 的取数脚本会继续按旧单位刷新数值
      GameTooltipPowerBar.unit = nil
      pfUI.tooltip:LayoutBars(false)
      return
    end

    local mp = UnitMana(unit)
    local mpm = UnitManaMax(unit)
    local showPower = C.tooltip.manabar == "1" and mp and mpm and mpm > 0
    if showPower then
      local pColorTable = ManaBarColor or PowerBarColor
      local pColor = pColorTable and pColorTable[UnitPowerType(unit)] or { r = .3, g = .45, b = 1 }
      GameTooltipPowerBar:SetStatusBarColor(pColor.r, pColor.g, pColor.b)
      GameTooltipPowerBar:SetMinMaxValues(0, mpm)
      GameTooltipPowerBar:SetValue(mp)
      if C.tooltip.manaperc == "1" then
        pfUI.tooltipPower.MP:SetText(string.format("%s%%", ceil(mp / mpm * 100)))
      else
        -- 用 Abbreviate 而非手写 "k"：尊重默认「缩写数字格式」
        pfUI.tooltipPower.MP:SetText(string.format("%s / %s", Abbreviate(mp), Abbreviate(mpm)))
      end
      GameTooltipPowerBar:Show()
      pfUI.tooltipPower:Show()
      GameTooltipPowerBar.unit = unit
    else
      GameTooltipPowerBar:Hide()
      pfUI.tooltipPower:Hide()
      pfUI.tooltipPower.MP:SetText("")
      GameTooltipPowerBar.unit = nil
    end
    -- 按是否显示能量条重新锚定生命条，消除无能量时的空白空隙
    pfUI.tooltip:LayoutBars(showPower)
  end

  -- 提示框当前展示的**还是不是**这个单位的提示：第一行文本不再以该单位名开头 ⇒ 已经换成别的东西了。
  -- 兼容 pfUI 给玩家姓名前插的行内颜色码（rgbhex → "|cAARRGGBB名字"），所以先剥掉行首颜色码再比。
  local function TooltipStillOwnedBy(unit)
    if not unit or not UnitExists(unit) then return nil end
    local name = UnitName(unit)
    local line = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
    if not name or not line or line == "" then return nil end
    line = string.gsub(line, "^|c%x%x%x%x%x%x%x%x", "")
    return string.find(line, name, 1, true) == 1
  end

  function pfUI.tooltip:Update()
      local unit = pfUI.tooltip:GetUnit()
      if unit == "none" then
        -- process item tooltips
        if C.tooltip.itemid == "1" and libtooltip:GetItemID() then
          GameTooltip:AddLine(T["ItemID"] .. ": " .. libtooltip:GetItemID(), .25,.5,1)
          GameTooltip:Show()
        end
        -- 色盲模式：在装备名字后追加品质文字标记（如 [史诗]）
        if C.global.colorblind == "1" or C.global.colorblind == true then
          local text = GameTooltipTextLeft1:GetText()
          -- 优先从名字行颜色反推品质；拿不到再用数字 itemID 取（兼容 GetText 去色等极端情况）
          local quality = colorblind_quality_from_text(text)
          if not quality then
            local id = libtooltip:GetItemID()
            if id then
              local _, _, q = GetItemInfo(id)
              quality = q
            end
          end
          local label = quality and colorblind_labels[quality]
          if label and text and not string.find(text, "%[" .. label .. "%]") then
            local labelText = " |cffFFFFFF[" .. label .. "]|r"
            -- 用独立 FontString 精确测量追加宽度，避免 SetText 后立即读取宽度滞后的问题
            colorblind_measure:SetText(labelText)
            local addw = colorblind_measure:GetStringWidth()
            local namew = GameTooltipTextLeft1:GetStringWidth()
            local maxw = namew + addw
            for i = 2, GameTooltip:NumLines() do
              local l = getglobal("GameTooltipTextLeft" .. i)
              local r = getglobal("GameTooltipTextRight" .. i)
              if l and l:IsShown() then maxw = max(maxw, l:GetStringWidth()) end
              if r and r:IsShown() then maxw = max(maxw, r:GetStringWidth()) end
            end
            GameTooltip:SetWidth(maxw + 25)
            GameTooltipTextLeft1:SetText(text .. labelText)
          end
        end
        -- 隐藏模型（非玩家单位）
        HideModel()
        -- 非单位提示（物品 / 招牌 / 信箱…）：收起能量条并让生命条贴回提示框
        pfUI.tooltip:UpdateBars(nil)
        return
      end

      local pvpname = UnitPVPName(unit)
      local name = UnitName(unit)
      local target = UnitName(unit .. "target")
      local _, targetClass = UnitClass(unit .. "target")
      local targetReaction = UnitReaction("player",unit .. "target")
      local _, class = UnitClass(unit)
      local guild, rankstr, rankid = GetGuildInfo(unit)
      local reaction = UnitReaction(unit, "player")
      local pvptitle = gsub(gsub(pvpname or name, name, "", 1), "^%s*(.-)%s*$", "%1")
      local hp = UnitHealth(unit)
      local hpm = UnitHealthMax(unit)

      if name then
        if UnitIsPlayer(unit) and class then
          local color = RAID_CLASS_COLORS[class]
          GameTooltipStatusBar:SetStatusBarColor_orig(color.r, color.g, color.b)
          GameTooltip:SetBackdropBorderColor(color.r, color.g, color.b)
          if color and color.r then
            GameTooltipTextLeft1:SetText(rgbhex(color.r, color.g, color.b, color.a) .. name)
          else
            GameTooltipTextLeft1:SetText("|cff999999" .. name)
          end
        elseif reaction then
          local color = UnitReactionColor[reaction]
          GameTooltipStatusBar:SetStatusBarColor_orig(color.r, color.g, color.b)
          GameTooltip:SetBackdropBorderColor(color.r, color.g, color.b)
        end
        if pvptitle ~= name and pvptitle ~= "" then
          GameTooltip:AppendText(" |cff666666["..pvptitle.."]|r")
        end
      end

      if guild then
        local rank = ""
        local lead = ""
        if C.tooltip.extguild == "1" then
          if rankstr then rank = " |cffaaaaaa(" .. rankstr .. ")"  end
          if rankid and rankid == 0 then lead = "|cffffcc00*|r" end
        end

        GameTooltip:AddLine("<" .. guild .. ">" .. lead .. rank, 0.3, 1, 0.5)
      end

      if target then
        if UnitName(unit .. "target")==UnitName("player") then
          GameTooltip:AddLine("你", 1, 0, 0)
        elseif UnitIsPlayer(unit .. "target") and targetClass then
          local color = RAID_CLASS_COLORS[targetClass]
          GameTooltip:AddLine(target, color.r, color.g, color.b)
        elseif targetReaction then
          local color = UnitReactionColor[targetReaction]
          if color then
            GameTooltip:AddLine(target, color.r, color.g, color.b)
          else
            GameTooltip:AddLine(target, .5, .5, .5)
          end
        end
      end

      if hp and hpm then
        if C.tooltip.alwaysperc ~= "1" then
          -- 用 Abbreviate 而非手写 "k"：尊重默认「缩写数字格式」（与法力值分支一致）
          hp = Abbreviate(hp)
          hpm = Abbreviate(hpm)
          pfUI.tooltipStatusBar.HP:SetText(hp .. " / " .. hpm)
        end
        -- 这里绕过了 OnUpdate 的 _lastHPText 缓存直接写文本；必须清掉缓存，
        -- 否则 OnUpdate 算出的百分比与旧缓存相同时会跳过 SetText，
        -- 「始终以百分比显示生命值」就被这条旧文本挡住（2026-10-02 修复）
        pfUI.tooltipStatusBar._lastHPText = nil
      end

      -- 能量条：显隐 + 数值（逻辑抽到 UpdateBars，供 OnUpdate 的内容签名守门复用）
      pfUI.tooltip:UpdateBars(unit)

      -- 显示 3D 模型（人物像）
      ShowModelForUnit(unit)

      GameTooltip:Show()
    end

  -- 添加 OnUpdate 钩子，实时更新模型位置
  local originalOnUpdate = GameTooltip:GetScript("OnUpdate")
  -- 第一行文本的"签名"：它一变，就说明提示框内容已被换掉，需要重新确认能量条的归属
  local lastTipSig
  -- ⛔ 1.12 OnUpdate 只有一个参数 elapsed，不能写 function(self, elapsed)
  --  （self=elapsed、elapsed=nil）。原链调用改为只透传 elapsed（与引擎行为一致）。
  GameTooltip:SetScript("OnUpdate", function(elapsed)
    if originalOnUpdate then
      originalOnUpdate(elapsed)
    end
    OnTooltipUpdate()

    -- ⛔ 残余能量条守门（2026-09-13，症状见本文件 UpdateBars 上方注释）：
    --   引擎在「单位提示 → 非单位提示」之间常常不重新触发 OnShow ⇒ Update() 跑不到 ⇒ 旧的蓝条留下来。
    --   做法：只在**第一行文本变化**时判定一次「条还属不属于这个单位」——属于就刷新数值，不属于就收起。
    --   只做"收"，不放"显示"（显示仍由 Update() 负责），因此对正常路径零影响。
    local sig = GameTooltipTextLeft1 and GameTooltipTextLeft1:GetText()
    if sig ~= lastTipSig then
      lastTipSig = sig
      local owner = GameTooltipPowerBar.unit
      if owner then
        if TooltipStillOwnedBy(owner) then
          pfUI.tooltip:UpdateBars(owner)
        else
          pfUI.tooltip:UpdateBars(nil)
        end
      end
    end
  end)

  -- 添加 OnHide 钩子，隐藏模型
  local originalOnHide = GameTooltip:GetScript("OnHide")
  GameTooltip:SetScript("OnHide", function(self)
    if originalOnHide then
      originalOnHide(self)
    end
    HideModel()
  end)

end)