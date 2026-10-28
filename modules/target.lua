pfUI:RegisterModule("target", "vanilla:tbc", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  -- Hide Blizzard target frame and unregister all events to prevent it from popping up again
  TargetFrame:Hide()
  TargetFrame:UnregisterAllEvents()

  pfUI.uf.target = pfUI.uf:CreateUnitFrame("Target", nil, C.unitframes.target)
  pfUI.uf.target:UpdateFrameSize()
  pfUI.uf.target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", 75, 125)
  UpdateMovable(pfUI.uf.target)

  -- ============================================================================
  -- 仇恨显示框（参考姓名板仇恨显示）
  -- 一个可移动的仇恨百分比显示框，默认位于头像框左侧。
  -- 数据来源优先级：Nampower 原生 > CatThreatLite > TWT 单体 > ShaguDPS。
  -- ============================================================================

  -- 玩家在当前目标上的仇恨百分比（仅对 target 单位，故直接走单体源）
  local function GetTargetThreatPercent()
    if not UnitExists("target") or UnitIsDead("target") then return nil end

    -- 1) Nampower 原生威胁 API（按 GUID 精确，无需网络，最优先）
    if _G.GetUnitThreatPct and _G.GetUnitGUID then
      local guid = _G.GetUnitGUID("target")
      if guid then
        local pct = _G.GetUnitThreatPct(guid)
        if pct and pct > 0 then return pct end
      end
    end

    -- 2) CatThreatLite：轻量共享客户端（无完整 TWT 时覆盖）
    if _G.CatThreatLite then
      local pct = _G.CatThreatLite.GetPercent()
      if pct and pct > 0 then return pct end
    end

    -- 3) TWT 单体目标模式
    if _G.TWT and _G.TWT.threats then
      local entry = _G.TWT.threats[UnitName("player")]
      if entry and entry.perc and entry.perc > 0 then return entry.perc end
    end

    -- 4) ShaguDPS 仇恨表（回退）
    if _G.ShaguDPS and _G.ShaguDPS.data and _G.ShaguDPS.data.threat then
      local entry = _G.ShaguDPS.data.threat[UnitName("player")]
      if entry and entry.perc and entry.perc > 0 then return entry.perc end
    end

    return nil
  end

  -- 仇恨显示框本体（独立可移动顶层框，默认锚定在头像框左侧）
  local threat = CreateFrame("Frame", "pfTargetThreat", UIParent)
  CreateBackdrop(threat)
  threat:SetMovable(true)
  threat:EnableMouse(true)
  threat:RegisterForDrag("LeftButton")
  threat:SetScript("OnDragStart", function() threat:StartMoving() end)
  threat:SetScript("OnDragStop", function()
    threat:StopMovingOrSizing()
    SaveMovable(threat)
  end)

  -- 材质层（背景纹理，默认 pfUI-F，与头像/血条一致）
  threat.tex = threat:CreateTexture(nil, "ARTWORK")
  threat.tex:SetPoint("TOPLEFT", threat, "TOPLEFT", 0, 0)
  threat.tex:SetPoint("BOTTOMRIGHT", threat, "BOTTOMRIGHT", 0, 0)
  threat.tex:SetVertexColor(1, 1, 1, 1)

  threat.text = threat:CreateFontString(nil, "OVERLAY")
  threat.text:SetAllPoints(threat)
  threat.text:SetFont(pfUI.font_unit, tonumber(C.global.font_unit_size) or 12, "OUTLINE")
  threat.text:SetJustifyH("CENTER")
  threat.text:SetJustifyV("CENTER")
  threat.text:SetTextColor(1, 1, 1, 1)

  -- 应用材质/长宽配置（GUI 改动时实时回调此函数）
  local function ApplyThreatBoxStyle()
    local cfg = C.unitframes.target
    local w = tonumber(cfg.ligh) or tonumber(cfg.threatwidth) or 50
    local h = tonumber(cfg.lightH) or tonumber(cfg.threatheight) or 20
    threat:SetWidth(w)
    threat:SetHeight(h)
    local texpath = C.unitframes.target.threattexture
    if texpath and texpath ~= "" then
      pcall(function() threat.tex:SetTexture(pfUI.media[texpath]) end)
    end
  end
  ApplyThreatBoxStyle()
  pfUI.uf.target_threat_apply = ApplyThreatBoxStyle

  -- 默认位置：头像框左侧（未手动拖动前动态跟随目标框）
  threat:ClearAllPoints()
  threat:SetPoint("RIGHT", pfUI.uf.target, "LEFT", -5, 0)

  -- 注册到 pfUI.movables：解锁模式才会给它生成 dragger，右键 dock 才会显示坐标、
  -- 才能改。旧实现自己读 C.position 绕开 movables，结果仇恨框在解锁里既没有
  -- dragger（右键点不开）也不响应 dock 的坐标输入。初始锚点会被 LoadMovable
  -- 记进 posdata，没有存档时自动回落到「贴目标框左侧」。
  UpdateMovable(threat)
  threat:Hide()

  -- 驱动帧：始终可见（透明），用于按节流刷新仇恨框（隐藏的框不会触发 OnUpdate）
  local threatDriver = CreateFrame("Frame", "pfTargetThreatDriver", UIParent)
  threatDriver:SetScript("OnUpdate", function()
    if (this.tick or 0) > GetTime() then return end
    this.tick = GetTime() + 0.2

    local unlock = pfUI.unlock and pfUI.unlock:IsShown()
    local enabled = C.unitframes.target.showthreat ~= "0"

    -- 解锁模式下始终显示，按"安全绿"染色（避免某些角色看到白色底色卡片）
    if unlock then
      local r, g, b = 0.67, 0.83, 0.45 -- 安全绿，与 ≤60% 阈值一致
      threat.text:SetText("仇恨%")
      threat.text:SetTextColor(1, 1, 1, 1)
      if threat.backdrop then
        threat.backdrop:SetBackdropColor(r, g, b, 0.45)    -- 背景底色
        threat.backdrop:SetBackdropBorderColor(r, g, b, 1) -- 边框实色
      end
      if threat.tex then
        threat.tex:SetVertexColor(r, g, b, 1)              -- 材质层染色
      end
      threat:Show()
      return
    end

    if not enabled then
      threat:Hide()
      return
    end

    if not UnitExists("target") or UnitIsDead("target") then
      threat:Hide()
      return
    end

    local perc = GetTargetThreatPercent()
    if perc and perc > 0 then
      -- 底色用 TWT 仇恨小窗同款连续渐变（绿→黄→红），超过 100 按 100 截断
      if perc > 100 then perc = 100 end
      local r, g, b
      if perc < 50 then
        r, g, b = perc / 50, 1, 0
      else
        r, g, b = 1, 1 - (perc - 50) / 50, 0
      end
      -- 文字仅显示百分比，仇恨框（材质+背景+边框）按渐变着色
      threat.text:SetText(string.format("%.0f%%", perc))
      threat.text:SetTextColor(1, 1, 1, 1)
      if threat.backdrop then
        threat.backdrop:SetBackdropColor(r, g, b, 0.45)   -- 背景底色（半透，纹理透明处兜底）
        threat.backdrop:SetBackdropBorderColor(r, g, b, 1) -- 边框实色
      end
      if threat.tex then
        threat.tex:SetVertexColor(r, g, b, 1)             -- 材质层按阈值着色
      end
      threat:Show()
    else
      threat:Hide()
    end
  end)
end)
