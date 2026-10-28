pfUI:RegisterModule("swingtimer", "vanilla:tbc", function()
  local L = pfUI.L or (pfUI_translation and pfUI_translation[GetLocale()]) or {}

  -- ============================================================
  -- CONSTANTS
  -- ============================================================
  local CONST = {
    HITINFO_LEFTSWING  = 4,
    HITINFO_NOACTION   = 65536,
    ON_SWING_QUEUED    = 0,
    ON_SWING_QUEUE_POPPED = 1,
    ATTR_ON_NEXT_SWING = 4,
    GRACE              = 0.15,
    RANGED_WARN_THRESHOLD = 0.65,
  }

  -- ============================================================
  -- SPELL LISTS
  -- ============================================================
  local SPELLS = {
    RANGED = { [75] = true, [2764] = true },
    SLAM = { [1464] = true, [8820] = true, [11604] = true, [11605] = true },
    HEROIC_STRIKE = {
      [78] = true, [284] = true, [285] = true, [1608] = true,
      [11564] = true, [11565] = true, [11566] = true, [11567] = true,
    },
    CLEAVE = {
      [845] = true, [7369] = true, [11608] = true, [11609] = true, [20569] = true,
    },
  }

  local OH_WEAPON_TYPES = { [13] = true, [21] = true }

  -- ============================================================
  -- CONFIG
  -- ============================================================
  if C.unitframes.swingtimer == "0" then return end

  local CFG = {
    width     = tonumber(C.unitframes.swingtimerwidth) or 200,
    height    = tonumber(C.unitframes.swingtimerheight) or 12,
    texture   = C.unitframes.swingtimertexture or "Interface\\AddOns\\pfUI\\img\\bar",
    showText  = C.unitframes.swingtimertext ~= "0",
    showLabel = C.unitframes.swingtimerlabel ~= "0",
    showOH    = C.unitframes.swingtimeroffhand ~= "0",
    showRanged = C.unitframes.swingtimerranged ~= "0",
    showTarget = C.unitframes.swingtimertarget ~= "0",
    fontSize  = tonumber(C.unitframes.swingtimerfontsize) or 12,
    hsQueue   = C.unitframes.swingtimerhsqueue ~= "0",
    showSpeed = C.unitframes.swingtimerattackspeed == "1",
    rangeIndicator = C.unitframes.swingtimerrangeindicator == "1",
  }

  local WINGCLIP_ID = 2974
  local ARCANESHOT_ID = 3044
  local _, playerClass = UnitClass("player")

  -- ============================================================
  -- DLL DETECTION (three-tier fallback)
  -- ============================================================
  -- Nampower provides the precise swing APIs: UnitAttackSpeed,
  -- AUTO_ATTACK_SELF/OTHER, START/STOP_AUTOATTACK and SPELL_QUEUE_EVENT.
  -- SuperWoW provides UNIT_CASTEVENT (swing detection) and UnitExists GUID.
  -- With neither DLL, fall back to vanilla combat-log + tooltip speed.
  local hasNampower = GetNampowerVersion and true or false
  local hasSuperWoW = SUPERWOW_VERSION and true or false

  -- ============================================================
  -- COLOR PARSER
  -- ============================================================
  local function ParseColor(str, dr, dg, db, da)
    if not str or str == "" then return dr, dg, db, da end
    local _, _, r, g, b, a = string.find(str, "([%d%.]+),([%d%.]+),([%d%.]+),([%d%.]+)")
    if r then
      return tonumber(r) or dr, tonumber(g) or dg, tonumber(b) or db, tonumber(a) or da
    end
    return dr, dg, db, da
  end

  local COLORS = {
    mh = { ParseColor(C.unitframes.swingtimermhcolor, 0.8, 0.3, 0.3, 1) },
    oh = { ParseColor(C.unitframes.swingtimerohcolor, 0.3, 0.8, 0.3, 1) },
    ranged = { 0.0, 1.0, 0.0, 1 },
    rangedWarn = { ParseColor(C.unitframes.swingtimerrangedwarncolor, 0.9, 0.0, 0.0, 1) },
  }

  -- ============================================================
  -- STATE
  -- ============================================================
  local S = {
    -- Main Hand
    mhTimer = 0,
    mhTimerMax = 1,
    mhSpeed = 0,
    mhActive = false,
    mhStartTime = 0,
    mhEndTime = 0,
    mhFrozenAt = nil,
    lastMhMarkerX = -1,

    -- Off Hand
    ohTimer = 0,
    ohTimerMax = 1,
    ohSpeed = 0,
    ohActive = false,
    ohStartTime = 0,
    ohEndTime = 0,
    lastOhMarkerX = -1,

    -- Ranged
    raTimer = 0,
    raTimerMax = 1,
    raSpeed = 0,
    raActive = false,
    raStartTime = 0,
    raEndTime = 0,

    -- Target (enemy swing timer)
    targetTimer = 0,
    targetTimerMax = 1,
    targetSpeed = 0,
    targetActive = false,
    targetStartTime = 0,
    targetEndTime = 0,
    targetLastHit = 0,
    lastTargetMarkerX = -1,

    -- Combat State
    autoAttackActive = false,
    inCombat = false,

    -- HS/Cleave Queue
    hsQueued = false,
    cleaveQueued = false,
    useSpellQueueEvent = false,
    cachedHSSlots = {},
    cachedCleaveSlots = {},

    -- Misc
    isWarrior = false,
    playerGUID = nil,
    pendingCastSpellId = nil,
    onSwingCache = {},
    graceAt = { mh = nil, oh = nil },
    mhConsec = 0,
    ohConsec = 0,
  }

  -- ============================================================
  -- HELPERS
  -- ============================================================
  local function IsOnSwingSpell(spellId)
    if S.onSwingCache[spellId] ~= nil then
      return S.onSwingCache[spellId]
    end
    local result = false
    if GetSpellRec then
      local rec = GetSpellRec(spellId)
      result = rec and bit.band(rec.attributes, CONST.ATTR_ON_NEXT_SWING) ~= 0 or false
    end
    S.onSwingCache[spellId] = result
    return result
  end

  -- ============================================================
  -- WEAPON SPEED FALLBACK (no Nampower)
  -- ============================================================
  -- Reads the base weapon speed from the equipped item tooltip. Slots:
  -- 16 = main hand, 17 = off hand. Only returns the base speed (no haste).
  local scanCache = { [16] = nil, [17] = nil }

  local SPEED_PATTERNS = {
    "Speed%s*(%d+%.?%d*)",
    "速度%s*(%d+%.?%d*)",
    "Tempo%s*(%d+%.?%d*)",
    "Vitesse%s*(%d+%.?%d*)",
  }

  local function ExtractWeaponSpeed(line)
    for _, pattern in ipairs(SPEED_PATTERNS) do
      local speed = string.match(line, pattern)
      if speed then
        speed = tonumber(speed)
        if speed and speed >= 0.5 and speed <= 6 then
          return speed
        end
      end
    end
    return nil
  end

  local function ScanWeaponSpeed(slot)
    if scanCache[slot] then return scanCache[slot] end

    local speed = nil
    if libtipscan then
      local scanner = libtipscan:GetScanner("swingtimer")
      scanner:SetInventoryItem("player", slot)
      for i = 1, scanner:NumLines() do
        local left, right = scanner:Line(i)
        speed = ExtractWeaponSpeed((left or "") .. " " .. (right or ""))
        if speed then break end
      end
    end

    scanCache[slot] = speed
    return speed
  end

  local function UpdateWeaponSpeeds()
    if hasNampower and UnitAttackSpeed then
      local ms, os = UnitAttackSpeed("player")
      S.mhSpeed = (ms and ms > 0) and ms or S.mhSpeed
      S.ohSpeed = (os and os > 0) and os or 0
    else
      -- Fallback: base weapon speed from tooltip (no haste accounted)
      S.mhSpeed = ScanWeaponSpeed(16) or S.mhSpeed
      S.ohSpeed = ScanWeaponSpeed(17) or 0
    end

    -- Ranged speed: 1st return value of UnitRangedDamage is the attack speed
    local rs = UnitRangedDamage("player")
    S.raSpeed = (rs and rs > 0) and rs or 0
  end

  -- ============================================================
  -- TIMER MANAGEMENT
  -- ============================================================
  local function StartMH()
    if S.mhFrozenAt then S.mhFrozenAt = nil end
    S.graceAt.mh = nil
    UpdateWeaponSpeeds()

    local now = GetTime()
    S.mhStartTime = now
    S.mhEndTime = now + S.mhSpeed
    S.mhTimerMax = S.mhSpeed
    S.mhTimer = S.mhSpeed
    S.mhActive = true

    pfUI.swingtimer.mainhand:Show()
    pfUI.swingtimer:Show()
  end

  local function StartOH()
    UpdateWeaponSpeeds()
    if S.ohSpeed <= 0 then return end

    S.graceAt.oh = nil
    local now = GetTime()
    S.ohStartTime = now
    S.ohEndTime = now + S.ohSpeed
    S.ohTimerMax = S.ohSpeed
    S.ohTimer = S.ohSpeed
    S.ohActive = true

    if CFG.showOH then
      pfUI.swingtimer.offhand:Show()
    end
    pfUI.swingtimer:Show()
  end

  local function StartRanged()
    if not CFG.showRanged then return end
    UpdateWeaponSpeeds()
    if S.raSpeed <= 0 then return end

    local now = GetTime()
    S.raStartTime = now
    S.raEndTime = now + S.raSpeed
    S.raTimerMax = S.raSpeed
    S.raTimer = S.raSpeed
    S.raActive = true

    -- Reset ranged bar visuals
    local ranged = pfUI.swingtimer.ranged
    ranged.left:ClearAllPoints()
    ranged.left:SetPoint("TOPLEFT", ranged, "TOPLEFT", 0, 0)
    ranged.left:SetWidth(1)
    ranged.left:SetTexCoord(0, 0.01, 0, 1)
    ranged.left:SetVertexColor(COLORS.ranged[1], COLORS.ranged[2], COLORS.ranged[3], COLORS.ranged[4])
    ranged.left:Show()
    ranged.right:Hide()
    ranged.warn:Hide()

    pfUI.swingtimer.mainhand:Hide()
    ranged:Show()
    pfUI.swingtimer:Show()
  end

  local function StopAll()
    S.mhActive = false
    S.ohActive = false
    S.raActive = false
    S.targetActive = false
    S.mhTimer = 0
    S.ohTimer = 0
    S.raTimer = 0
    S.targetTimer = 0
    S.graceAt.mh = nil
    S.graceAt.oh = nil

    pfUI.swingtimer.mainhand:Hide()
    pfUI.swingtimer.offhand:Hide()
    pfUI.swingtimer.ranged:Hide()
    if pfUI.swingtimer.target then pfUI.swingtimer.target:Hide() end
    pfUI.swingtimer:Hide()
  end

  -- ============================================================
  -- HS/CLEAVE QUEUE
  -- ============================================================
  local function RebuildQueueSlotCache()
    if not S.isWarrior or not CFG.hsQueue or S.useSpellQueueEvent then
      return
    end

    S.cachedHSSlots = {}
    S.cachedCleaveSlots = {}

    for slot = 1, 120 do
      local tex = GetActionTexture(slot)
      local name = GetActionText(slot)

      if tex then
        if string.find(tex, "Ability_Rogue_Ambush") then
          table.insert(S.cachedHSSlots, slot)
        elseif string.find(tex, "Ability_Warrior_Cleave") then
          table.insert(S.cachedCleaveSlots, slot)
        end
      end

      if name then
        local lower = string.lower(name)
        if lower == "heroic strike" or lower == "heroicstrike" or lower == "hs" then
          table.insert(S.cachedHSSlots, slot)
        elseif lower == "cleave" then
          table.insert(S.cachedCleaveSlots, slot)
        end
      end
    end
  end

  local function CheckQueuedAction(slotList)
    for _, slot in ipairs(slotList) do
      if IsCurrentAction(slot) then
        return true
      end
    end
    return false
  end

  local function IsHSOrCleaveQueued()
    if not CFG.hsQueue or not S.isWarrior then
      return false, false
    end

    if S.useSpellQueueEvent then
      return S.hsQueued, S.cleaveQueued
    end

    return CheckQueuedAction(S.cachedHSSlots), CheckQueuedAction(S.cachedCleaveSlots)
  end

  -- ============================================================
  -- UI CREATION
  -- ============================================================
  local function CreateTimerBar(parent, name, labelText, color)
    local bar = CreateFrame("StatusBar", name, UIParent)
    bar:SetWidth(CFG.width)
    bar:SetHeight(CFG.height)
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar:SetStatusBarTexture(CFG.texture)
    bar:SetStatusBarColor(color[1], color[2], color[3], color[4])
    bar:Hide()

    -- Text (center)
    bar.text = bar:CreateFontString(nil, "DIALOG", "GameFontNormal")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text:SetFont(pfUI.font_default, CFG.fontSize, "OUTLINE")
    bar.text:SetTextColor(1, 1, 1, 1)
    if not CFG.showText then bar.text:Hide() end

    -- Label (left)
    bar.label = bar:CreateFontString(nil, "DIALOG", "GameFontNormal")
    bar.label:SetPoint("RIGHT", bar, "LEFT", -4, 0)
    bar.label:SetFont(pfUI.font_default, CFG.fontSize, "OUTLINE")
    bar.label:SetTextColor(0.8, 0.8, 0.8, 1)
    bar.label:SetText(CFG.showLabel and labelText or "")

    -- Speed (right)
    bar.speed = bar:CreateFontString(nil, "DIALOG", "GameFontNormal")
    bar.speed:SetPoint("LEFT", bar, "RIGHT", 4, 0)
    bar.speed:SetFont(pfUI.font_default, CFG.fontSize, "OUTLINE")
    bar.speed:SetTextColor(0.8, 0.8, 0.8, 1)
    if not CFG.showSpeed then bar.speed:Hide() end

    -- Marker
    bar.marker = bar:CreateTexture(nil, "OVERLAY")
    bar.marker:SetTexture(1, 1, 1, 1.0)
    bar.marker:SetWidth(2)
    bar.marker:SetHeight(CFG.height)
    bar.marker:Hide()

    -- Marker glow left
    bar.markerGlowL = bar:CreateTexture(nil, "OVERLAY")
    bar.markerGlowL:SetTexture(1, 1, 1, 1)
    bar.markerGlowL:SetGradientAlpha("HORIZONTAL", 1, 1, 1, 0, 1, 1, 1, 0.35)
    bar.markerGlowL:SetWidth(10)
    bar.markerGlowL:SetHeight(CFG.height)
    bar.markerGlowL:Hide()

    -- Marker glow right
    bar.markerGlowR = bar:CreateTexture(nil, "OVERLAY")
    bar.markerGlowR:SetTexture(1, 1, 1, 1)
    bar.markerGlowR:SetGradientAlpha("HORIZONTAL", 1, 1, 1, 0.35, 1, 1, 1, 0)
    bar.markerGlowR:SetWidth(10)
    bar.markerGlowR:SetHeight(CFG.height)
    bar.markerGlowR:Hide()

    CreateBackdrop(bar)
    CreateBackdropShadow(bar)

    return bar
  end

  local function CreateRangedBar()
    local frame = CreateFrame("Frame", "pfSwingTimerRanged", UIParent)
    frame:SetWidth(CFG.width)
    frame:SetHeight(CFG.height)
    frame:Hide()

    -- Main fill texture
    frame.left = frame:CreateTexture(nil, "ARTWORK")
    frame.left:SetTexture(CFG.texture)
    frame.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.left:SetHeight(CFG.height)
    frame.left:SetWidth(1)
    frame.left:SetTexCoord(0, 0.01, 0, 1)
    frame.left:SetVertexColor(COLORS.ranged[1], COLORS.ranged[2], COLORS.ranged[3], COLORS.ranged[4])

    -- Warning threshold marker (2px white, no glow)
    frame.warnMarker = frame:CreateTexture(nil, "OVERLAY")
    frame.warnMarker:SetTexture(1, 1, 1, 1.0)
    frame.warnMarker:SetWidth(2)
    frame.warnMarker:SetHeight(CFG.height)
    frame.warnMarker:Hide()

    -- Legacy (unused but kept for compatibility)
    frame.right = frame:CreateTexture(nil, "ARTWORK")
    frame.right:SetTexture(CFG.texture)
    frame.right:Hide()

    frame.warn = frame:CreateTexture(nil, "ARTWORK")
    frame.warn:SetTexture(CFG.texture)
    frame.warn:Hide()

    -- Text (center)
    frame.text = frame:CreateFontString(nil, "DIALOG", "GameFontNormal")
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetFont(pfUI.font_default, CFG.fontSize, "OUTLINE")
    frame.text:SetTextColor(1, 1, 1, 1)
    if not CFG.showText then frame.text:Hide() end

    -- Label (left)
    frame.label = frame:CreateFontString(nil, "DIALOG", "GameFontNormal")
    frame.label:SetPoint("RIGHT", frame, "LEFT", -4, 0)
    frame.label:SetFont(pfUI.font_default, CFG.fontSize, "OUTLINE")
    frame.label:SetTextColor(0.8, 0.8, 0.8, 1)
    frame.label:SetText(CFG.showLabel and L["Ra"] or "")

    -- Speed (right)
    frame.speed = frame:CreateFontString(nil, "DIALOG", "GameFontNormal")
    frame.speed:SetPoint("LEFT", frame, "RIGHT", 4, 0)
    frame.speed:SetFont(pfUI.font_default, CFG.fontSize, "OUTLINE")
    frame.speed:SetTextColor(0.8, 0.8, 0.8, 1)
    if not CFG.showSpeed then frame.speed:Hide() end

    CreateBackdrop(frame)
    CreateBackdropShadow(frame)

    return frame
  end

  -- Create main container
  pfUI.swingtimer = CreateFrame("Frame", "pfSwingTimer", UIParent)
  pfUI.swingtimer:SetFrameStrata("MEDIUM")
  pfUI.swingtimer:Hide()

  -- Create bars
  pfUI.swingtimer.mainhand = CreateTimerBar(
    pfUI.swingtimer, "pfSwingTimerMainhand", L["MH"], COLORS.mh
  )
  pfUI.swingtimer.mainhand:SetPoint("CENTER", UIParent, "CENTER", 0, -100)

  pfUI.swingtimer.offhand = CreateTimerBar(
    pfUI.swingtimer, "pfSwingTimerOffhand", L["OH"], COLORS.oh
  )
  pfUI.swingtimer.offhand:SetPoint("TOP", pfUI.swingtimer.mainhand, "BOTTOM", 0, -4)

  pfUI.swingtimer.ranged = CreateRangedBar()
  pfUI.swingtimer.ranged:SetPoint("CENTER", UIParent, "CENTER", 0, -120)

  if CFG.showTarget then
    pfUI.swingtimer.target = CreateTimerBar(
      pfUI.swingtimer, "pfSwingTimerTarget", L["Target"] or "Target", {0.9, 0.2, 0.2, 1}
    )
    pfUI.swingtimer.target:SetPoint("TOP", pfUI.swingtimer.ranged, "BOTTOM", 0, -4)
    UpdateMovable(pfUI.swingtimer.target)
  end

  UpdateMovable(pfUI.swingtimer.mainhand)
  UpdateMovable(pfUI.swingtimer.ranged)

  -- ============================================================
  -- RANGE INDICATOR
  -- ============================================================
  -- IsSpellInRange(spellId) is injected by Nampower. Creating the indicator
  -- without it would spam "attempt to call global" from the OnUpdate below.
  if CFG.rangeIndicator and IsSpellInRange then
    local ZONES_HUNTER = {
      melee    = { "Melee",     0.13, 0.55, 0.13 },
      range    = { "In Range",  0.10, 0.30, 0.60 },
      deadzone = { "Dead Zone", 0.45, 0.25, 0.05 },
      outrange = { "Out of Range", 0.55, 0.10, 0.10 },
    }
    local ZONES_DEFAULT = {
      melee    = { "Melee",     0.13, 0.55, 0.13 },
      deadzone = { "Dead Zone", 0.45, 0.25, 0.05 },
    }
    local ZONES = playerClass == "HUNTER" and ZONES_HUNTER or ZONES_DEFAULT

    local ri = CreateFrame("Frame", "pfSwingTimerRangeIndicator", UIParent)
    ri:SetWidth(120)
    ri:SetHeight(20)
    ri:SetPoint("CENTER", UIParent, "CENTER", 0, -140)
    ri:Hide()

    CreateBackdrop(ri)
    CreateBackdropShadow(ri)

    ri.label = ri:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ri.label:SetAllPoints()
    ri.label:SetFont(pfUI.font_default, CFG.fontSize, "OUTLINE")
    ri.label:SetJustifyH("CENTER")
    ri.label:SetJustifyV("MIDDLE")

    UpdateMovable(ri)

    local function SetRangeZone(zone)
      if ri.zone == zone then return end
      ri.zone = zone
      local z = ZONES[zone]
      if not z then return end
      ri.label:SetText(z[1])
      ri.backdrop:SetBackdropColor(z[2], z[3], z[4], 0.85)
      ri.backdrop:SetBackdropBorderColor(z[2] * 2, z[3] * 2, z[4] * 2, 1)
    end

    local riUpdater = CreateFrame("Frame")
    riUpdater:SetScript("OnUpdate", function()
      local now = GetTime()
      if (this.tick or 0) > now then return end
      this.tick = now + 0.1

      if pfUI.unlock and pfUI.unlock:IsShown() then return end

      local hasTarget = UnitExists("target")
        and UnitCanAttack("player", "target")
        and not UnitIsDead("target")

      if not hasTarget then
        ri:Hide()
        return
      end

      ri:Show()
      local melee = IsSpellInRange(WINGCLIP_ID, "target")

      if playerClass == "HUNTER" then
        local ranged = IsSpellInRange(ARCANESHOT_ID, "target")
        if melee == 1 then
          SetRangeZone("melee")
        elseif ranged == 1 then
          SetRangeZone("range")
        elseif CheckInteractDistance("target", 4) then
          SetRangeZone("deadzone")
        else
          SetRangeZone("outrange")
        end
      else
        -- Non-hunters have no ranged spell, so IsSpellInRange(ARCANESHOT_ID)
        -- returns nil and any "ranged == 0" test is never true. ZONES_DEFAULT
        -- only carries melee/deadzone anyway, so decide on melee alone.
        if melee == 1 then
          SetRangeZone("melee")
        else
          SetRangeZone("deadzone")
        end
      end
    end)

    pfUI.swingtimer.rangeindicator = ri
  end

  -- ============================================================
  -- UPDATE FUNCTIONS
  -- ============================================================
  local function UpdateTimerBar(bar, timer, timerMax, speed, lastMarkerX, colorR, colorG, colorB, colorA)
    if timer <= 0 then
      if lastMarkerX ~= -1 then
        bar.marker:Hide()
        bar.markerGlowL:Hide()
        bar.markerGlowR:Hide()
      end
      return -1
    end

    local progress = 1 - (timer / timerMax)
    bar:SetValue(progress)

    local markerX = progress * CFG.width
    if markerX < 1 then markerX = 1 end
    if markerX > CFG.width - 2 then markerX = CFG.width - 2 end

    if markerX ~= lastMarkerX then
      bar.marker:SetPoint("LEFT", bar, "LEFT", markerX - 1, 0)
      bar.markerGlowL:SetPoint("RIGHT", bar.marker, "LEFT", 0, 0)
      bar.markerGlowR:SetPoint("LEFT", bar.marker, "RIGHT", 0, 0)
      bar.marker:Show()
      bar.markerGlowL:Show()
      bar.markerGlowR:Show()
    end

    return markerX
  end

  local function UpdateRangedBar()
    local remaining = S.raTimer
    local total = S.raTimerMax
    local progress = 1 - (remaining / total)

    local w = CFG.width * progress
    if w < 1 then w = 1 end

    local bar = pfUI.swingtimer.ranged

    -- Update fill
    bar.left:Show()
    bar.left:SetWidth(w)
    bar.left:SetTexCoord(0, progress, 0, 1)

    -- ABAR style: whole bar changes color at threshold
    if remaining <= CONST.RANGED_WARN_THRESHOLD then
      bar.left:SetVertexColor(COLORS.rangedWarn[1], COLORS.rangedWarn[2], COLORS.rangedWarn[3], COLORS.rangedWarn[4])
    else
      bar.left:SetVertexColor(COLORS.ranged[1], COLORS.ranged[2], COLORS.ranged[3], COLORS.ranged[4])
    end

    -- Warning threshold marker (2px white, no glow)
    local thresholdProgress = 1 - (CONST.RANGED_WARN_THRESHOLD / total)
    local markerX = thresholdProgress * CFG.width
    if markerX > 1 and markerX < CFG.width - 1 then
      bar.warnMarker:SetPoint("LEFT", bar, "LEFT", markerX - 1, 0)
      bar.warnMarker:Show()
    else
      bar.warnMarker:Hide()
    end

    -- Text
    if CFG.showText then
      bar.text:SetText(string.format("%.1f", remaining))
    end

    if CFG.showSpeed and S.raSpeed > 0 then
      bar.speed:SetText(string.format("%.1f", S.raSpeed))
    end
  end

  -- ============================================================
  -- ONUPDATE
  -- ============================================================
  pfUI.swingtimer:SetScript("OnUpdate", function()
    local anyActive = false
    local now = GetTime()

    -- ==========================================================
    -- UPDATE MAIN HAND
    -- ==========================================================
    if S.mhActive then
      S.mhTimer = S.mhEndTime - now

      if S.mhTimer <= 0 then
        S.mhTimer = 0

        if not S.mhFrozenAt then
          if not S.graceAt.mh then
            S.graceAt.mh = GetTime() + CONST.GRACE
          elseif GetTime() >= S.graceAt.mh then
            S.graceAt.mh = nil
            if not S.inCombat or not S.autoAttackActive then
              S.mhActive = false
              pfUI.swingtimer.mainhand:Hide()
              S.lastMhMarkerX = -1
              pfUI.swingtimer.mainhand.marker:Hide()
              pfUI.swingtimer.mainhand.markerGlowL:Hide()
              pfUI.swingtimer.mainhand.markerGlowR:Hide()
            end
          end
        end
      end

      -- HS/Cleave color
      local r, g, b = COLORS.mh[1], COLORS.mh[2], COLORS.mh[3]
      if CFG.hsQueue and S.isWarrior then
        local hs, cl = IsHSOrCleaveQueued()
        if cl then
          r, g, b = 0.2, 0.9, 0.2
        elseif hs then
          r, g, b = 0.9, 0.9, 0.2
        end
      end

      if S.mhTimer > 0 then
        S.lastMhMarkerX = UpdateTimerBar(
          pfUI.swingtimer.mainhand,
          S.mhTimer, S.mhTimerMax, S.mhSpeed,
          S.lastMhMarkerX,
          r, g, b, COLORS.mh[4]
        )
        pfUI.swingtimer.mainhand:SetStatusBarColor(r, g, b, COLORS.mh[4])
      end

      if CFG.showText and S.mhTimer > 0 then
        pfUI.swingtimer.mainhand.text:SetText(string.format("%.1f", S.mhTimer))
      end

      if CFG.showSpeed and S.mhSpeed > 0 then
        pfUI.swingtimer.mainhand.speed:SetText(string.format("%.1f", S.mhSpeed))
      end

      anyActive = true
    end

    -- ==========================================================
    -- UPDATE OFF HAND
    -- ==========================================================
    if CFG.showOH and S.ohActive then
      S.ohTimer = S.ohEndTime - now

      if S.ohTimer <= 0 then
        S.ohTimer = 0

        if not S.graceAt.oh then
          S.graceAt.oh = GetTime() + CONST.GRACE
        elseif GetTime() >= S.graceAt.oh then
          S.graceAt.oh = nil
          if not S.inCombat or not S.autoAttackActive then
            S.ohActive = false
            pfUI.swingtimer.offhand:Hide()
            S.lastOhMarkerX = -1
            pfUI.swingtimer.offhand.marker:Hide()
            pfUI.swingtimer.offhand.markerGlowL:Hide()
            pfUI.swingtimer.offhand.markerGlowR:Hide()
          end
        end
      end

      if S.ohTimer > 0 then
        S.lastOhMarkerX = UpdateTimerBar(
          pfUI.swingtimer.offhand,
          S.ohTimer, S.ohTimerMax, S.ohSpeed,
          S.lastOhMarkerX,
          COLORS.oh[1], COLORS.oh[2], COLORS.oh[3], COLORS.oh[4]
        )
      end

      if CFG.showText and S.ohTimer > 0 then
        pfUI.swingtimer.offhand.text:SetText(string.format("%.1f", S.ohTimer))
      end

      if CFG.showSpeed and S.ohSpeed > 0 then
        pfUI.swingtimer.offhand.speed:SetText(string.format("%.1f", S.ohSpeed))
      end

      anyActive = true
    elseif not CFG.showOH then
      pfUI.swingtimer.offhand:Hide()
    end

    -- ==========================================================
    -- UPDATE RANGED
    -- ==========================================================
    if CFG.showRanged and S.raActive then
      S.raTimer = S.raTimer - (arg1 or 0)

      if S.raTimer <= 0 then
        S.raTimer = 0
        S.raActive = false
        pfUI.swingtimer.ranged:Hide()
      else
        UpdateRangedBar()
        anyActive = true
      end
    elseif not CFG.showRanged then
      pfUI.swingtimer.ranged:Hide()
    end

    -- ==========================================================
    -- UPDATE TARGET (enemy swing timer)
    -- ==========================================================
    if CFG.showTarget and S.targetActive and pfUI.swingtimer.target then
      S.targetTimer = S.targetEndTime - now

      if S.targetTimer <= 0 then
        S.targetTimer = 0
        S.targetActive = false
        S.lastTargetMarkerX = -1
        pfUI.swingtimer.target:Hide()
      else
        S.lastTargetMarkerX = UpdateTimerBar(
          pfUI.swingtimer.target,
          S.targetTimer, S.targetTimerMax, S.targetSpeed,
          S.lastTargetMarkerX,
          0.9, 0.2, 0.2, 1
        )
        if CFG.showText then
          pfUI.swingtimer.target.text:SetText(string.format("%.1f", S.targetTimer))
        end
        anyActive = true
      end
    end

    -- Hide container if nothing is active
    if not anyActive then
      if not pfUI.swingtimer.mainhand:IsShown()
        and not pfUI.swingtimer.offhand:IsShown()
        and not pfUI.swingtimer.ranged:IsShown() then
        this:Hide()
      end
    end
  end)

  -- ============================================================
  -- EVENT HANDLERS
  -- ============================================================
  local StartTargetSwing

  local function HandleSpellStart()
    if arg1 and arg1 > 0 then
      S.pendingCastSpellId = arg1
    end
  end

  local function HandleSpellGo(spellId)
    if SPELLS.RANGED[spellId] then
      StartRanged()
      S.pendingCastSpellId = nil
      return
    end

    if SPELLS.SLAM[spellId] then
      S.pendingCastSpellId = nil
      return
    end

    if SPELLS.HEROIC_STRIKE[spellId] or IsOnSwingSpell(spellId) or SPELLS.CLEAVE[spellId] then
      S.hsQueued = false
      S.cleaveQueued = false
      StartMH()
      S.pendingCastSpellId = nil
      return
    end

    local rec = GetSpellRec and GetSpellRec(spellId) or nil
    if rec and rec.interruptFlags and rec.interruptFlags > 0 then
      if S.mhActive and S.mhSpeed > 0 then
        UpdateWeaponSpeeds()
        S.mhTimerMax = S.mhSpeed
        S.mhTimer = S.mhSpeed
      end
    end

    S.pendingCastSpellId = nil
  end

  local function HandleSpellCastEvent(success, spellId)
    if success ~= 1 then return end

    if SPELLS.HEROIC_STRIKE[spellId] then
      S.hsQueued = true
      S.cleaveQueued = false
    elseif SPELLS.CLEAVE[spellId] then
      S.cleaveQueued = true
      S.hsQueued = false
    end
  end

  local function HandleSpellQueueEvent()
    local eventCode = arg1 or -1
    local spellId = arg2 or 0

    if eventCode == CONST.ON_SWING_QUEUED then
      S.useSpellQueueEvent = true
      if SPELLS.HEROIC_STRIKE[spellId] then
        S.hsQueued = true
        S.cleaveQueued = false
      elseif SPELLS.CLEAVE[spellId] then
        S.cleaveQueued = true
        S.hsQueued = false
      end
    elseif eventCode == CONST.ON_SWING_QUEUE_POPPED then
      S.hsQueued = false
      S.cleaveQueued = false
    end
  end

  local function HandleAutoAttackSelf()
    local hitInfo = arg4 or 0
    local isOffhand = bit.band(hitInfo, CONST.HITINFO_LEFTSWING) ~= 0
    local noAction = bit.band(hitInfo, CONST.HITINFO_NOACTION) ~= 0

    if noAction then
      if (isOffhand and S.ohActive) or (not isOffhand and S.mhActive) then
        return
      end
    end

    if isOffhand then
      StartOH()
    else
      StartMH()
    end
  end

  local function HandleAutoAttackOther()
    local attackerGuid = arg1
    local victimGuid = arg2
    if not victimGuid or not S.playerGUID or victimGuid ~= S.playerGUID then
      return
    end

    -- 当前目标在平砍我：Nampower GUID 精确匹配
    if CFG.showTarget and hasNampower and attackerGuid and GetUnitGUID("target") == attackerGuid then
      StartTargetSwing()
    end

    -- 自己受到额外攻击（风怒/乱舞）：修正 mh/oh 计时器
    local victimState = arg5 or 0
    if victimState == 3 then
      if S.ohActive and S.ohSpeed > 0 and (S.ohTimer / S.ohTimerMax) < (S.mhTimer / S.mhTimerMax) then
        local minimum = S.ohSpeed * 0.20
        if S.ohTimer > minimum then
          S.ohTimer = S.ohTimer - S.ohSpeed * 0.40
          if S.ohTimer < minimum then S.ohTimer = minimum end
        end
      elseif S.mhActive and S.mhSpeed > 0 then
        local minimum = S.mhSpeed * 0.20
        if S.mhTimer > minimum then
          S.mhTimer = S.mhTimer - S.mhSpeed * 0.40
          if S.mhTimer < minimum then S.mhTimer = minimum end
        end
      end
    end
  end

  local function HandleUnitInventoryChanged()
    if arg1 and arg1 ~= "player" then return end

    -- invalidate tooltip speed cache so new weapons are re-scanned
    scanCache[16] = nil
    scanCache[17] = nil

    local oldOhSpeed = S.ohSpeed
    UpdateWeaponSpeeds()

    if S.ohSpeed == 0 then
      S.ohActive = false
      pfUI.swingtimer.offhand:Hide()
    elseif oldOhSpeed == 0 and S.ohSpeed > 0 and S.autoAttackActive and S.inCombat then
      StartOH()
    end

    if S.raSpeed == 0 then
      S.raActive = false
      pfUI.swingtimer.ranged:Hide()
    end
  end

  -- ============================================================
  -- COMBAT LOG FALLBACK (no DLL at all)
  -- ============================================================
  -- Vanilla-standard swing detection via combat log events. Works without
  -- any DLL, but timing is heuristic (MH/OH decided by elapsed time; no
  -- hitInfo / extra-attack handling).

  -- True when a "self hit/miss" combat line is a plain melee swing
  -- (spells, reflected/incoming damage and ranged shots are filtered out).
  local function IsMeleeSwingMessage(msg)
    if not msg or msg == "" then return false end

    -- reflected / incoming damage
    if string.find(msg, "掉落") or string.find(msg, "你受到") then return false end

    -- spell damage (zhCN): "你的<法术>对/击中/被/没有击中..."
    if string.find(msg, "你的(.+)对")
      or string.find(msg, "你的(.+)击中")
      or string.find(msg, "你的(.+)被")
      or string.find(msg, "你的(.+)没有击中") then
      return false
    end

    -- spell damage (enUS): "Your <spell> hits/crits/is/misses..."
    if string.find(msg, "Your (.+) hits")
      or string.find(msg, "Your (.+) crits")
      or string.find(msg, "Your (.+) is")
      or string.find(msg, "Your (.+) misses") then
      return false
    end

    return true
  end

  -- A melee swing happened: decide main-hand vs off-hand by elapsed-time
  -- closeness to each weapon speed, then (re)start the matching bar.
  local function HandleCombatLogSwing()
    S.autoAttackActive = true
    UpdateWeaponSpeeds()

    local mhSpeed = S.mhSpeed
    local ohSpeed = S.ohSpeed

    if ohSpeed <= 0 then
      StartMH()
      return
    end

    local now = GetTime()
    local lastMH = S.mhStartTime or 0
    local lastOH = S.ohStartTime or 0

    if ((math.abs((now - lastMH) - mhSpeed) <= math.abs((now - lastOH) - ohSpeed))
        and not (S.mhConsec <= ohSpeed / mhSpeed))
        or S.ohConsec >= mhSpeed / ohSpeed then
      S.mhConsec = S.mhConsec + 1
      S.ohConsec = 0
      StartMH()
    else
      S.ohConsec = S.ohConsec + 1
      S.mhConsec = 0
      StartOH()
    end
  end

  -- Auto-shot / ranged shot detection from spell self-damage combat lines.
  local function HandleCombatLogAutoShot(msg)
    if not msg or msg == "" then return end
    if string.find(msg, "自动射击") or string.find(msg, "Auto Shot")
      or string.find(msg, "射击") or string.find(msg, "Shoot") then
      S.autoAttackActive = true
      StartRanged()
    end
  end

  -- ============================================================
  -- TARGET (ENEMY) SWING TIMER
  -- ============================================================
  -- Primary: Nampower AUTO_ATTACK_OTHER + GUID match (exact).
  -- Fallback (no Nampower): vanilla combat-log name match.

  local function GetAttackerName(msg)
    if not msg or msg == "" then return nil end
    return string.match(msg, "(.+)击中你")
      or string.match(msg, "(.+)的致命一击对你")
      or string.match(msg, "(.+)没有击中你")
      or string.match(msg, "(.+)发起了攻击。你")
      or string.match(msg, "(.+) hits you")
      or string.match(msg, "(.+) crits you")
      or string.match(msg, "(.+) misses you")
      or string.match(msg, "(.+) attacks. You")
  end

  StartTargetSwing = function()
    if not CFG.showTarget or not pfUI.swingtimer.target then return end

    local now = GetTime()
    local speed = 0

    -- exact weapon speed when Nampower is available
    if hasNampower and UnitAttackSpeed then
      local ts = UnitAttackSpeed("target")
      if ts and ts > 0 then speed = ts end
    end

    if speed <= 0 then
      -- no DLL: self-calibrate from the interval between target hits
      if S.targetLastHit > 0 then
        speed = now - S.targetLastHit
        if speed < 0.5 or speed > 10 then speed = 2 end
      else
        speed = 2 -- default until the first interval is measured
      end
    end

    S.targetLastHit = now
    S.targetSpeed = speed
    S.targetTimerMax = speed
    S.targetTimer = speed
    S.targetStartTime = now
    S.targetEndTime = now + speed
    S.targetActive = true

    pfUI.swingtimer.target:SetStatusBarColor(0.9, 0.2, 0.2, 1)
    if CFG.showSpeed then
      pfUI.swingtimer.target.speed:SetText(string.format("%.1f", speed))
    end
    pfUI.swingtimer.target:Show()
    pfUI.swingtimer:Show()
  end

  -- ============================================================
  -- MAIN EVENT FRAME
  -- ============================================================
  local events = CreateFrame("Frame")
  events:RegisterEvent("AUTO_ATTACK_SELF")
  events:RegisterEvent("AUTO_ATTACK_OTHER")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:RegisterEvent("UNIT_INVENTORY_CHANGED")
  events:RegisterEvent("PLAYER_REGEN_DISABLED")
  events:RegisterEvent("PLAYER_REGEN_ENABLED")
  events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
  events:RegisterEvent("UNIT_DIED")
  events:RegisterEvent("SPELL_QUEUE_EVENT")
  events:RegisterEvent("START_AUTOATTACK")
  events:RegisterEvent("STOP_AUTOATTACK")
  events:RegisterEvent("SPELL_START_SELF")
  -- SuperWoW fallback: swing detection when Nampower is absent
  if not hasNampower then
    events:RegisterEvent("UNIT_CASTEVENT")
  end
  -- No-DLL fallback: vanilla combat-log swing detection
  if not hasNampower and not hasSuperWoW then
    events:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
    events:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
    events:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
  end
  -- Target (enemy) swing timer fallback (no Nampower): combat-log name match
  if CFG.showTarget and not hasNampower then
    events:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
    events:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES")
    events:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")
    events:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES")
  end

  events:SetScript("OnEvent", function()
    if event == "AUTO_ATTACK_SELF" then
      HandleAutoAttackSelf()
    elseif event == "AUTO_ATTACK_OTHER" then
      HandleAutoAttackOther()
    elseif event == "UNIT_CASTEVENT" then
      -- SuperWoW fallback swing detection (no Nampower).
      -- arg1 = casterGUID, arg3 = "MAINHAND" / "OFFHAND".
      if not hasNampower and S.playerGUID and arg1 == S.playerGUID then
        if arg3 == "MAINHAND" then
          S.autoAttackActive = true
          StartMH()
        elseif arg3 == "OFFHAND" then
          S.autoAttackActive = true
          StartOH()
        end
      end
    elseif event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
      -- No-DLL fallback: vanilla combat-log swing detection
      if IsMeleeSwingMessage(arg1) then
        HandleCombatLogSwing()
      end
    elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
      HandleCombatLogAutoShot(arg1)
    elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS"
        or event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_MISSES"
        or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS"
        or event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES" then
      -- target (enemy) swing timer fallback: combat-log name match
      local attacker = GetAttackerName(arg1)
      if attacker and attacker == UnitName("target") then
        StartTargetSwing()
      end
    elseif event == "SPELL_START_SELF" then
      HandleSpellStart()
    elseif event == "SPELL_QUEUE_EVENT" then
      HandleSpellQueueEvent()
    elseif event == "START_AUTOATTACK" then
      S.autoAttackActive = true
      if S.mhSpeed > 0 then StartMH() end
      if S.ohSpeed > 0 and CFG.showOH then StartOH() end
      if S.raSpeed > 0 and CFG.showRanged then StartRanged() end
    elseif event == "STOP_AUTOATTACK" then
      S.autoAttackActive = false
    elseif event == "PLAYER_ENTERING_WORLD" then
      local _, class = UnitClass("player")
      S.isWarrior = (class == "WARRIOR")
      -- 兼容性 GUID 获取（修复 GetUnitGUID 不存在的问题）
      local function GetPlayerGUID()
        if UnitGUID then
          return UnitGUID("player")
        elseif GetUnitGUID then
          return GetUnitGUID("player")
        else
          -- SuperWoW: UnitExists returns the GUID as its 2nd return value
          local _, guid = UnitExists("player")
          return guid
        end
      end
      S.playerGUID = GetPlayerGUID()
      UpdateWeaponSpeeds()
      RebuildQueueSlotCache()
    elseif event == "UNIT_INVENTORY_CHANGED" then
      HandleUnitInventoryChanged()
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
      RebuildQueueSlotCache()
    elseif event == "PLAYER_REGEN_DISABLED" then
      S.inCombat = true
      UpdateWeaponSpeeds()
    elseif event == "PLAYER_REGEN_ENABLED" then
      S.inCombat = false
      S.hsQueued = false
      S.cleaveQueued = false
      S.autoAttackActive = false
      -- reset combat-log heuristic state for the next combat
      S.mhStartTime = 0
      S.ohStartTime = 0
      S.mhConsec = 0
      S.ohConsec = 0
      -- reset target (enemy) swing timer state
      S.targetLastHit = 0
      S.targetActive = false
      S.targetTimer = 0
      if pfUI.swingtimer.target then pfUI.swingtimer.target:Hide() end
    elseif event == "UNIT_DIED" then
      if arg1 and arg1 == S.playerGUID then
        StopAll()
      end
    end
  end)

  -- ============================================================
  -- SPELL HOOKS
  -- ============================================================
  pfUI.libdebuff_spell_go_hooks = pfUI.libdebuff_spell_go_hooks or {}
  pfUI.libdebuff_spell_go_hooks["swingtimer"] = HandleSpellGo

  pfUI.libdebuff_spell_cast_hooks = pfUI.libdebuff_spell_cast_hooks or {}
  pfUI.libdebuff_spell_cast_hooks["swingtimer"] = HandleSpellCastEvent

  -- ============================================================
  -- INIT
  -- ============================================================
  UpdateWeaponSpeeds()

  -- ============================================================
  -- PUBLIC API
  -- ============================================================
  pfUI.swingtimer.api = {
    GetMHTimer = function() return S.mhTimer end,
    GetOHTimer = function() return S.ohTimer end,
    GetRangedTimer = function() return S.raTimer end,
    GetMHSpeed = function() return S.mhSpeed end,
    GetOHSpeed = function() return S.ohSpeed end,
    GetRangedSpeed = function() return S.raSpeed end,
    IsMHActive = function() return S.mhActive end,
    IsOHActive = function() return S.ohActive end,
    IsRangedActive = function() return S.raActive end,
    GetMHProgress = function()
      return S.mhActive and S.mhTimerMax > 0 and (1 - S.mhTimer / S.mhTimerMax) or 0
    end,
    GetOHProgress = function()
      return S.ohActive and S.ohTimerMax > 0 and (1 - S.ohTimer / S.ohTimerMax) or 0
    end,
    GetRangedProgress = function()
      return S.raActive and S.raTimerMax > 0 and (1 - S.raTimer / S.raTimerMax) or 0
    end,
    IsHSQueued = function() return S.hsQueued end,
    IsCleaveQueued = function() return S.cleaveQueued end,
  }
end)
