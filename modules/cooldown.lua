pfUI:RegisterModule("cooldown", "vanilla:tbc", function ()
  -- cache values
  local lowcolor    = {strsplit(",", C.appearance.cd.lowcolor)}
  local normalcolor = {strsplit(",", C.appearance.cd.normalcolor)}
  local minutecolor = {strsplit(",", C.appearance.cd.minutecolor)}
  local hourcolor   = {strsplit(",", C.appearance.cd.hourcolor)}
  local daycolor    = {strsplit(",", C.appearance.cd.daycolor)}

  -- 冷却文字刷新：原来是**每个冷却文本帧各挂一个 OnUpdate**，帧体第一句才是
  -- `this.tick > GetTime()` 的 0.1s 早退。也就是说每个可见冷却文本每帧都要付一次
  -- C→Lua 派发 + GetTime 比较（动作条 + 单位框 + 姓名板叠加可达上百个，285fps 下是纯浪费）。
  -- 现在：帧自己不带脚本，由文件末尾的一个 0.1s 订阅统一遍历（详见 CooldownTextTick）。
  -- 形参特意仍叫 this ⇒ 原函数体除节流三行外逐字未改，便于和改动前逐行对照。
  local parent
  local function pfCooldownUpdate(this)
    parent = this:GetParent()
    if not parent then this:Hide() return end

    -- avoid to set cooldowns on invalid frames
    -- PERF: cdRef is cached at creation (pfCreateCoolDown), so this used to
    -- pay a string concat + _G hash lookup per frame even when throttled out.
    if this.cdRef and not this.cdRef:IsShown() then
      this:Hide()
      return
    end

    -- fix own alpha value (should be inherited, but somehow isn't always)
    if this:GetAlpha() ~= parent:GetAlpha() then
      this:SetAlpha(parent:GetAlpha())
    end

    if this.start < GetTime() then
      -- calculating remaining time as it should be
      local remaining = this.duration - (GetTime() - this.start)
      if remaining >= 0 then
        this.text:SetText(GetColoredTimeString(remaining))
      else
        this:Hide()
      end
    else
      -- I have absolutely no idea, but it works:
      -- https://github.com/Stanzilla/WoWUIBugs/issues/47
      local time = time()
      local startupTime = time - GetTime()
      -- just a simplification of: ((2^32) - (start * 1000)) / 1000
      local cdTime = (2 ^ 32) / 1000 - this.start
      local cdStartTime = startupTime - cdTime
      local cdEndTime = cdStartTime + this.duration
      local remaining = cdEndTime - time

      if remaining >= 0 then
        this.text:SetText(GetColoredTimeString(remaining))
      else
        this:Hide()
      end
    end
  end

  -- 登记表：只装 pfCreateCoolDown 建出来的文本帧，创建时登记一次、**永不摘除**。
  -- ⛔ 不能"Hide 时摘除、Show 时重登"：`api/unitframes.lua` 会直接 Show/Hide 这些
  --    pfCooldownText（buff/debuff 图标倒计时），而重登点只有 SetCooldown，两者不同步
  --    就会漏登记 ⇒ 该帧数字永久冻住。隐藏帧由 tick 里的 IsShown 跳过，代价只是一次调用。
  local active = {}

  local function CooldownTextTick()
    for i = 1, table.getn(active) do
      local f = active[i]
      if f:IsShown() then
        pfCooldownUpdate(f)
      end
    end
  end

  -- 返回 false = 没有可用的 ticker，调用方退回逐帧 OnUpdate（不该发生，但别让功能停摆）
  local function CooldownRegister(f)
    local ticker = pfUI.api.libticker
    if not ticker or not ticker.Add then return false end

    active[table.getn(active) + 1] = f
    if table.getn(active) == 1 then
      ticker:Add("cooldown.text", CooldownTextTick, 0.1)
    end
    return true
  end

  -- 退化路径：1.12 的脚本处理器从全局 this 取帧，这里还原原来的逐帧节流
  local function pfCooldownOnUpdate()
    local now = GetTime()
    if (this.tick or 0) > now then return end
    this.tick = now + 0.1
    pfCooldownUpdate(this)
  end

  local height, size
  local function pfCreateCoolDown(cooldown, start, duration)
    cooldown.pfCooldownText = CreateFrame("Frame", "pfCooldownFrame", cooldown:GetParent())
    -- PERF: cache the cooldown frame reference for the hidden-check
    -- (replaces per-frame _G[parent_name .. "Cooldown"] string + hash lookup)
    cooldown.pfCooldownText.cdRef = cooldown
    cooldown.pfCooldownText:SetAllPoints(cooldown)
    cooldown.pfCooldownText:SetFrameLevel(cooldown:GetParent():GetFrameLevel() + 2)
    cooldown.pfCooldownText.text = cooldown.pfCooldownText:CreateFontString("pfCooldownFrameText", "OVERLAY")

    if not cooldown.pfCooldownType then
      size = tonumber(C.appearance.cd.font_size_foreign)
    elseif cooldown.pfCooldownType == "BLIZZARD" then
      size = tonumber(C.appearance.cd.font_size_blizz)
    elseif cooldown.pfCooldownSize then
      size = tonumber(cooldown.pfCooldownSize)
    else
      size = tonumber(C.appearance.cd.font_size)
    end

    -- enforce dynamic font size
    if C.appearance.cd.dynamicsize == "1" and cooldown.GetParent then
      height = cooldown:GetParent() and cooldown:GetParent():GetHeight() or cooldown:GetHeight() or 0
      size = math.max((height > 0 and height * .64 or 16), size)
    end

    cooldown.pfCooldownText.text:SetFont(pfUI.media[C.appearance.cd.font], size, "OUTLINE")
    cooldown.pfCooldownText.text:SetPoint("CENTER", cooldown.pfCooldownText, "CENTER", 0, 0)
    if not CooldownRegister(cooldown.pfCooldownText) then
      cooldown.pfCooldownText:SetScript("OnUpdate", pfCooldownOnUpdate)
    end
  end

  -- hook
  local function SetCooldown(this, start, duration, enable)
    -- abort on unknown frames
    if C.appearance.cd.foreign == "0" and not this.pfCooldownType then
      return
    end

    -- add support for omnicc's disable flag
    if this.noCooldownCount then
      return
    end

    -- realign cooldown frames
    local parent = this.GetParent and this:GetParent()
    if parent and parent:GetWidth() / 36 > 0 then
      this:SetScale(parent:GetWidth() / 36)
      this:SetPoint("TOPLEFT", parent, "TOPLEFT", -1, 1)
      this:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 1, -1)
    end

    -- don't draw global cooldowns
    if this.pfCooldownType == "NOGCD" and duration < tonumber(C.appearance.cd.threshold) then
      start, duration = 0, 0
    end

    -- disable GCDs on non pfUI frames
    if not this.pfCooldownType and duration < tonumber(C.appearance.cd.threshold) then
      start, duration = 0, 0
    end

    -- hide animation
    if this.pfCooldownStyleAnimation == 0 then
      this:SetAlpha(0)
    elseif not this.pfCooldownStyleAnimation and C.appearance.cd.hideanim == "1" then
      this:SetAlpha(0)
    end

    -- print time as text on cooldown frames
    if ( not this.pfCooldownStyleText or this.pfCooldownStyleText == 1)
    and start > 0 and duration > 0 and (not enable or enable > 0) then
      if( not this.pfCooldownText ) then
        pfCreateCoolDown(this, start, duration)
      end

      this.pfCooldownText.start = start
      this.pfCooldownText.duration = duration
      this.pfCooldownText:Show()
    elseif(this.pfCooldownText) then
      this.pfCooldownText:Hide()
    end
  end

  if pfUI.expansion == "vanilla" then
    -- vanilla does not have a cooldown frame type, so we hook the
    -- regular SetTimer function that each one is calling.
    hooksecurefunc("CooldownFrame_SetTimer", SetCooldown)
  else
    -- tbc and later expansion have a cooldown frametype, so we can
    -- hook directly into the frame creation and add our function there.
    local methods = getmetatable(CreateFrame('Cooldown', nil, nil, 'CooldownFrameTemplate')).__index
    hooksecurefunc(methods, 'SetCooldown', SetCooldown)
  end
end)
