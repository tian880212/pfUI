-- Lua 5.0 / WoW 1.12 safe: no '#' operator, no string instance methods,
-- table.getn() for lengths. Multi-return safe: UnitPowerType/UnitClass results
-- are captured into single locals before further use.

local function Clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function Round(v)
  if v >= 0 then return math.floor(v + 0.5) end
  return math.ceil(v - 0.5)
end

local function PushBounded(list, value, maxCount)
  table.insert(list, value)
  while table.getn(list) > maxCount do table.remove(list, 1) end
end

local function Median(values)
  local n = table.getn(values)
  if n == 0 then return 0 end
  local copy = {}
  local i
  for i = 1, n do copy[i] = values[i] end
  table.sort(copy)
  if (n - math.floor(n / 2) * 2) == 1 then return copy[(n + 1) / 2] end
  return (copy[n / 2] + copy[n / 2 + 1]) * 0.5
end

-- Turtle WoW 1.18 Blade Rush: 2.0s base energy tick, interval reduced by
-- 0.0006s * rank * agility (rank 2 = 0.0012s/agi).
local ENERGY_BASE_TICK_MS = 2000
local ENERGY_MIN_TICK_MS = 500
-- Upper bound allows a slowed cadence: Blade Flurry ("energy regeneration
-- reduced by 20%") may be implemented either as +16 per 2s tick (official
-- Mod Power Regen % behaviour) or as a 2.5s interval on some servers.
local ENERGY_MAX_TICK_MS = 2600
local ENERGY_REDUCTION_MS_PER_AGI_PER_RANK = 0.6
-- Natural Turtle energy ticks are +20 normally and +16 while regen is reduced
-- (e.g. Blade Flurry).  Restrict phase-locking to this window so instant
-- energy effects (Thistle Tea +100, Adrenaline Rush, procs) never move the
-- Spark.
local ENERGY_GAIN_MIN = 14
local ENERGY_GAIN_MAX = 22
local ENERGY_SAMPLE_MIN_MS = 350
local ENERGY_SAMPLE_MAX_MULT = 4.5
local ENERGY_SAMPLE_TOLERANCE_MIN_MS = 140
local ENERGY_SAMPLE_TOLERANCE_MAX_MS = 360
local ENERGY_SAMPLE_COUNT = 8

local function ClassToken()
  local _, token = UnitClass("player")
  return token or ""
end

local function TheoryEnergyTickMS()
  local tickMS = ENERGY_BASE_TICK_MS

  -- Combat spec Blade Rush talent (1.18.0). Use the locale-independent class
  -- token ("ROGUE") instead of the localized class name.
  if ClassToken() == "ROGUE" and type(GetTalentInfo) == "function" then
    local _, _, _, _, currRank = GetTalentInfo(2, 16)
    local bladeRushRank = tonumber(currRank) or 0
    if bladeRushRank > 0 then
      -- Capture only the first UnitStat return before calling tonumber:
      -- WoW 1.12 UnitStat returns (base, effective, posBuff, negBuff) and a
      -- bare nested call would pass them all to tonumber as (value, base).
      local rawAgi = UnitStat("player", 2)
      local agility = tonumber(rawAgi) or 0
      local reductionPerAgi = 0.0006 * bladeRushRank -- 0.0006 rank1, 0.0012 rank2
      tickMS = tickMS - agility * reductionPerAgi * 1000
    end
  end

  return Clamp(tickMS, ENERGY_MIN_TICK_MS, ENERGY_MAX_TICK_MS)
end

local function ResetEnergyRuntime(f)
  f.anchorMS = nil
  f.energyLastAcceptedGainMS = nil
  f.energyLastRejectedNormMS = nil
  f.energySamples = {}
  f.energyObservedTickMS = nil
end

local function RecomputeEnergyModel(f, force)
  local theoryMS = TheoryEnergyTickMS()
  local changed = force or f.energyTheoryTickMS == nil
    or math.abs((f.energyTheoryTickMS or theoryMS) - theoryMS) > 0.5

  if changed then
    local oldTheory = f.energyTheoryTickMS
    f.energyTheoryTickMS = theoryMS

    -- Samples gathered at a different agility/talent rank describe an old
    -- cadence: drop the interval estimate but keep the last phase anchor.
    -- The next real energy tick re-locks the phase immediately.
    if oldTheory and math.abs(oldTheory - theoryMS) > 0.5 then
      f.energySamples = {}
      f.energyObservedTickMS = nil
    end
  end

  if f.energyObservedTickMS then
    f.energyTickMS = Clamp(f.energyObservedTickMS, ENERGY_MIN_TICK_MS, ENERGY_MAX_TICK_MS)
  else
    f.energyTickMS = theoryMS
  end
  return f.energyTickMS
end

local function EffectiveEnergyTickMS(f)
  if not f.energyTickMS then return RecomputeEnergyModel(f, true) end
  return Clamp(f.energyTickMS, ENERGY_MIN_TICK_MS, ENERGY_MAX_TICK_MS)
end

-- Feed a natural-range energy gain (already filtered to +14..+22) into the
-- phase calibrator. Returns nothing; updates anchor/samples on the frame.
local function OnNaturalEnergyGain(f, timestampMS)
  local theory = RecomputeEnergyModel(f, false)
  local reference = EffectiveEnergyTickMS(f)
  local last = f.energyLastAcceptedGainMS

  if not last then
    f.energyLastAcceptedGainMS = timestampMS
    f.anchorMS = timestampMS
    return
  end

  local gap = timestampMS - last
  if gap < ENERGY_SAMPLE_MIN_MS then return end

  -- A tick can be invisible at/near the energy cap.  Normalize gaps close to
  -- 2x/3x/4x the expected period instead of losing phase lock.  A gap far
  -- beyond that (death, long cap time, loading) re-anchors without sampling
  -- so the calibrator can never deadlock on a stale anchor.
  if gap > reference * ENERGY_SAMPLE_MAX_MULT then
    f.energyLastAcceptedGainMS = timestampMS
    f.anchorMS = timestampMS
    f.energyLastRejectedNormMS = nil
    return
  end

  local n = Round(gap / reference)
  if n < 1 then n = 1 end
  if n > 4 then n = 4 end
  local normalized = gap / n

  local tolerance = Clamp(reference * 0.28, ENERGY_SAMPLE_TOLERANCE_MIN_MS, ENERGY_SAMPLE_TOLERANCE_MAX_MS)
  local theoryTolerance = Clamp(theory * 0.32, ENERGY_SAMPLE_TOLERANCE_MIN_MS, ENERGY_SAMPLE_TOLERANCE_MAX_MS)

  if math.abs(normalized - reference) <= tolerance or math.abs(normalized - theory) <= theoryTolerance then
    PushBounded(f.energySamples, normalized, ENERGY_SAMPLE_COUNT)
    if table.getn(f.energySamples) >= 2 then
      f.energyObservedTickMS = Median(f.energySamples)
    end
    RecomputeEnergyModel(f, false)
    f.energyLastAcceptedGainMS = timestampMS
    f.anchorMS = timestampMS
    f.energyLastRejectedNormMS = nil
    return
  end

  -- Cadence-change re-lock (e.g. Blade Flurry toggled on and the server
  -- implements it as a slower 2.5s tick instead of +16 per 2s tick): two
  -- consecutive natural-range gains rejected at a mutually consistent
  -- normalized gap mean the rhythm itself changed.  Adopt it as the new
  -- cadence instead of freezing on the old anchor and drifting forever.
  local lastRejected = f.energyLastRejectedNormMS
  if lastRejected and math.abs(normalized - lastRejected) <= tolerance then
    PushBounded(f.energySamples, normalized, ENERGY_SAMPLE_COUNT)
    if table.getn(f.energySamples) >= 2 then
      f.energyObservedTickMS = Median(f.energySamples)
    end
    RecomputeEnergyModel(f, false)
    f.energyLastAcceptedGainMS = timestampMS
    f.anchorMS = timestampMS
    f.energyLastRejectedNormMS = nil
  else
    f.energyLastRejectedNormMS = normalized
  end
end

pfUI:RegisterModule("energytick", "vanilla:tbc", function()
  if not pfUI.uf or not pfUI.uf.player then
    return
  end

  local energytick = CreateFrame("Frame", nil, pfUI.uf.player.power.bar)
  energytick:SetAllPoints(pfUI.uf.player.power.bar)
  energytick:RegisterEvent("PLAYER_ENTERING_WORLD")
  energytick:RegisterEvent("UNIT_DISPLAYPOWER")
  energytick:RegisterEvent("UNIT_ENERGY")
  energytick:RegisterEvent("UNIT_MANA")
  energytick:RegisterEvent("UNIT_STATS")
  energytick:RegisterEvent("CHARACTER_POINTS_CHANGED")
  energytick:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
  energytick:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")

  energytick:SetScript("OnEvent", function()
    -- Capture only the first UnitPowerType return before comparing: WoW 1.12
    -- / Turtle may return multiple values and some bridges behave oddly when
    -- the raw call is used inside expressions.
    local rawPowerType = UnitPowerType("player")
    local powerType = tonumber(rawPowerType) or 0

    -- mode 与「是否显示」解耦：能量条（modules/energybar.lua）也要复用这套
    -- 相位，所以即便头像 tick 在配置里关掉了，mode/anchor 仍然要照常维护，
    -- 否则 energybar 那边会拿不到进度、退回自己那套粗算。
    if powerType == 0 then
      this.mode = "MANA"
    elseif powerType == 3 then
      this.mode = "ENERGY"
    else
      this.mode = nil
    end

    local wantShow = false
    if powerType == 0 and C.unitframes.player.manatick == "1" then
      wantShow = true
    elseif powerType == 3 and C.unitframes.player.energy == "1" then
      wantShow = true
    end

    if wantShow then
      this:Show()
    else
      this:Hide()
    end

    -- Filter known instant energy gains from talents/buffs (extra guard on
    -- top of the delta window; also works for effects the delta window
    -- alone could miss on laggy event batching).
    if event == "CHAT_MSG_SPELL_SELF_BUFF" or event == "CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS" then
      if string.find(arg1, "You gain") and string.find(arg1, "Energy from") then
        this.ignoreNextGain = true
      end
      return
    end

    if event == "PLAYER_ENTERING_WORLD" then
      this.lastMana = UnitMana("player")
      ResetEnergyRuntime(this)
      RecomputeEnergyModel(this, true)
      return
    end

    if event == "UNIT_STATS" or event == "CHARACTER_POINTS_CHANGED" then
      if this.mode == "ENERGY" then RecomputeEnergyModel(this, true) end
      return
    end

    if (event == "UNIT_MANA" or event == "UNIT_ENERGY") and arg1 == "player" then
      this.currentMana = UnitMana("player")
      local diff = 0
      if this.lastMana then
        diff = this.currentMana - this.lastMana
      end

      if this.mode == "MANA" and diff < 0 then
        this.target = 5
      elseif this.mode == "MANA" and diff > 0 then
        if UnitMana("player") >= UnitManaMax("player") then
          this.start = nil
          this.spark:SetAlpha(0)
          this:Hide()
        elseif this.max ~= 5 and diff > (this.badtick and this.badtick * 1.2 or 5) then
          this.target = 2
        else
          this.badtick = diff
        end
      elseif this.mode == "ENERGY" and diff >= 0 then
        -- Only natural periodic gains (+14..+22, i.e. +20 / reduced +16) are
        -- accepted as tick evidence.  Instant effects (+25/+40/+100) never
        -- move the Spark; the phase keeps running from the calibrated anchor.
        if not this.ignoreNextGain and diff >= ENERGY_GAIN_MIN and diff <= ENERGY_GAIN_MAX then
          OnNaturalEnergyGain(this, GetTime() * 1000)
        end
        this.ignoreNextGain = false
      end
      this.lastMana = this.currentMana
    end
  end)

  energytick:SetScript("OnUpdate", function()
    -- Throttle for performance
    if (this.tick or 0) > GetTime() then
      return
    end
    this.tick = GetTime() + 0.020  -- ~50 FPS

    if this.target then
      this.start, this.max = GetTime(), this.target
      this.target = nil
      this.spark:SetAlpha(1)
      this:Show()
    end

    if this.mode == "ENERGY" then
      -- Energy Spark: phase-driven, not loop-driven.  Position is derived
      -- from the calibrated anchor so a real +20 tick snaps the Spark back
      -- to the left edge on the exact event frame, while predicted ticks in
      -- between keep it travelling smoothly.
      if not this.anchorMS or not C.unitframes.player.pheight then
        return
      end

      local nowMS = GetTime() * 1000
      local period = EffectiveEnergyTickMS(this)
      local n = math.floor((nowMS - this.anchorMS) / period) + 1
      if n < 0 then n = 0 end
      local nextTick = this.anchorMS + n * period
      while nextTick <= nowMS do nextTick = nextTick + period end

      local remain = nextTick - nowMS
      local frac = 1 - Clamp(remain / period, 0, 1)

      local width = (C.unitframes.player.pwidth ~= "-1" and C.unitframes.player.pwidth or C.unitframes.player.width)
      local pos = width * frac
      this.spark:SetPoint("LEFT", pos - ((C.unitframes.player.pheight + 5) / 2), 0)
      return
    end

    if not this.start then
      return
    end

    this.current = GetTime() - this.start

    if this.current > this.max then
      -- Don't restart tick timer if mana is full
      if this.mode == "MANA" and UnitMana("player") >= UnitManaMax("player") then
        this.start = nil
        this.spark:SetAlpha(0)
        return
      end
      this.start, this.max, this.current = GetTime(), 2, 0
    end

    local pos = (C.unitframes.player.pwidth ~= "-1" and C.unitframes.player.pwidth or C.unitframes.player.width)
        * (this.current / this.max)
    if not C.unitframes.player.pheight then
      return
    end
    this.spark:SetPoint("LEFT", pos - ((C.unitframes.player.pheight + 5) / 2), 0)
  end)

  energytick.spark = energytick:CreateTexture(nil, "OVERLAY")
  energytick.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
  energytick.spark:SetHeight(C.unitframes.player.pheight + 15)
  energytick.spark:SetWidth(C.unitframes.player.pheight + 5)
  energytick.spark:SetBlendMode("ADD")

  local hookUpdateConfig = pfUI.uf.player.UpdateConfig
  function pfUI.uf.player.UpdateConfig()
    energytick.spark:SetHeight(C.unitframes.player.pheight + 15)
    energytick.spark:SetWidth(C.unitframes.player.pheight + 5)
    hookUpdateConfig(pfUI.uf.player)
  end

  -- 供能量条（modules/energybar.lua）复用**同一套**回能相位，避免两处各算一套
  -- 导致光点不同步。返回 0..1 的「本次回能进度」：
  --   nil = 非能量形态，或还没吃到过一次自然回能（anchorMS 尚未校准）
  -- 算法与上面 OnUpdate 的 ENERGY 分支完全一致（含 Blade Rush 敏捷修正）。
  function energytick:EnergyProgress()
    if energytick.mode ~= "ENERGY" then return nil end

    local anchor = energytick.anchorMS
    if not anchor then return nil end

    local period = EffectiveEnergyTickMS(energytick)
    if not period or period <= 0 then return nil end

    local nowMS = GetTime() * 1000
    local n = math.floor((nowMS - anchor) / period) + 1
    if n < 0 then n = 0 end

    local nextTick = anchor + n * period
    while nextTick <= nowMS do nextTick = nextTick + period end

    return 1 - Clamp((nextTick - nowMS) / period, 0, 1)
  end

  -- 暴露给其它模块（不要覆盖 pfUI.module.energytick，那是注册函数）
  pfUI.energytick = energytick
end)
