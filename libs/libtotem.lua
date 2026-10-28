-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libtotem ]]--
-- A pfUI library that tries to emulate the TotemAPI that was introduced in Patch 2.4.
-- It detects and saves all current totems of the player and returns information based
-- on the totem slot ID. The function GetTotemInfo is supposed to work as it would
-- on later expansions.
--
--  GetTotemInfo(id)
--    Returns totem informations on the givent totem slot
--    active, name, start, duration, icon

-- return instantly if we're not on a vanilla client
if pfUI.client > 11200 then return end

-- return instantly when another libtotem is already active
if pfUI.api.libtotem then return end

MAX_TOTEMS       = MAX_TOTEMS       or 4
FIRE_TOTEM_SLOT  = FIRE_TOTEM_SLOT  or 1
EARTH_TOTEM_SLOT = EARTH_TOTEM_SLOT or 2
WATER_TOTEM_SLOT = WATER_TOTEM_SLOT or 3
AIR_TOTEM_SLOT   = AIR_TOTEM_SLOT   or 4

local _, class = UnitClass("player")

-- Nampower detection (enhanced: also verify SpellInfo is available)
local hasNampower = false
if GetNampowerVersion then
    local major, minor, patch = GetNampowerVersion()
    patch = patch or 0
    if major > 2 or (major == 2 and minor > 41) or (major == 2 and minor == 41 and patch >= 0) then
        -- Extra safeguard: ensure SpellInfo is actually present
        if SpellInfo then
            hasNampower = true
        end
    end
end

local libtotem
local queue = { ["slot"] = nil, ["name"] = nil, ["start"] = nil, ["duration"] = nil, ["icon"] = nil }
local active = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }

-- 图腾掌握天赋倍数
local totemMasteryMultiplier = 1.0
local totemMasteryUpdater = nil   -- 轮询框架

-- 更新图腾掌握天赋倍数，返回是否成功
local function UpdateTotemMastery()
    -- 先确认天赋数据是否已加载（通过检查天赋标签页名称）
    local tabName = GetTalentTabInfo(3)
    if not tabName then
        return false    -- 数据未就绪
    end
    -- 图腾掌握天赋位于增强系(3)第8个天赋位，第五返回值为当前点数
    local _, _, _, _, rank = GetTalentInfo(3, 8)
    totemMasteryMultiplier = (rank and rank > 0) and 1.2 or 1.0
    return true
end

-- 启动轮询，直到成功获取天赋数据
local function StartTotemMasteryPolling()
    if totemMasteryUpdater then return end
    totemMasteryUpdater = CreateFrame("Frame")
    totemMasteryUpdater:SetScript("OnUpdate", function()
        if UpdateTotemMastery() then
            totemMasteryUpdater:SetScript("OnUpdate", nil)
            totemMasteryUpdater = nil
        end
    end)
end

-- 监听天赋更新事件
local talentFrame = CreateFrame("Frame")
talentFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
talentFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
talentFrame:SetScript("OnEvent", function()
    if not UpdateTotemMastery() then
        StartTotemMasteryPolling()
    end
end)

-- 文件加载时立即尝试一次，若失败则启动轮询
if not UpdateTotemMastery() then
    StartTotemMasteryPolling()
end

-- SpellID -> { slot, duration } mapping (优先使用)
local spellids = {
  -- FIRE (slot 1)
  [1535]  = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R1
  [8498]  = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R2
  [8499]  = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R3
  [11314] = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R4
  [11315] = { slot = FIRE_TOTEM_SLOT, duration = 5   }, -- Fire Nova Totem R5
  [8227]  = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Flametongue Totem R1
  [8249]  = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Flametongue Totem R2
  [10526] = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Flametongue Totem R3
  [16387] = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Flametongue Totem R4
  [8184]  = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Frost Resistance Totem R1
  [10478] = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Frost Resistance Totem R2
  [10479] = { slot = FIRE_TOTEM_SLOT, duration = 120 }, -- Frost Resistance Totem R3
  [8190]  = { slot = FIRE_TOTEM_SLOT, duration = 20  }, -- Magma Totem R1
  [10585] = { slot = FIRE_TOTEM_SLOT, duration = 20  }, -- Magma Totem R2
  [10586] = { slot = FIRE_TOTEM_SLOT, duration = 20  }, -- Magma Totem R3
  [10587] = { slot = FIRE_TOTEM_SLOT, duration = 20  }, -- Magma Totem R4
  [3599]  = { slot = FIRE_TOTEM_SLOT, duration = 30  }, -- Searing Totem R1
  [6363]  = { slot = FIRE_TOTEM_SLOT, duration = 35  }, -- Searing Totem R2
  [6364]  = { slot = FIRE_TOTEM_SLOT, duration = 40  }, -- Searing Totem R3
  [6365]  = { slot = FIRE_TOTEM_SLOT, duration = 45  }, -- Searing Totem R4
  [10437] = { slot = FIRE_TOTEM_SLOT, duration = 50  }, -- Searing Totem R5
  [10438] = { slot = FIRE_TOTEM_SLOT, duration = 55  }, -- Searing Totem R6

  -- EARTH (slot 2)
  [2484]  = { slot = EARTH_TOTEM_SLOT, duration = 45  }, -- Earthbind Totem
  [5730]  = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R1
  [6390]  = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R2
  [6391]  = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R3
  [6392]  = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R4
  [10427] = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R5
  [10428] = { slot = EARTH_TOTEM_SLOT, duration = 15  }, -- Stoneclaw Totem R6
  [8071]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R1
  [8154]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R2
  [8155]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R3
  [10406] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R4
  [10407] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R5
  [10408] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Stoneskin Totem R6
  [8075]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R1
  [8160]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R2
  [8161]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R3
  [10442] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R4
  [25361] = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Strength of Earth Totem R5
  [8143]  = { slot = EARTH_TOTEM_SLOT, duration = 120 }, -- Tremor Totem

  -- WATER (slot 3)
  [8170]  = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Disease Cleansing Totem
  [8185]  = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Fire Resistance Totem R1
  [10537] = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Fire Resistance Totem R2
  [10538] = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Fire Resistance Totem R3
  [5394]  = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R1
  [6375]  = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R2
  [6377]  = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R3
  [10462] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R4
  [10463] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Healing Stream Totem R5
  [5675]  = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Mana Spring Totem R1
  [10495] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Mana Spring Totem R2
  [10496] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Mana Spring Totem R3
  [10497] = { slot = WATER_TOTEM_SLOT, duration = 60  }, -- Mana Spring Totem R4
  [16190] = { slot = WATER_TOTEM_SLOT, duration = 12  }, -- Mana Tide Totem
  [8166]  = { slot = WATER_TOTEM_SLOT, duration = 120 }, -- Poison Cleansing Totem

  -- AIR (slot 4)
  [8835]  = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Grace of Air Totem R1
  [10627] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Grace of Air Totem R2
  [8177]  = { slot = AIR_TOTEM_SLOT, duration = 45  }, -- Grounding Totem
  [10595] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Nature Resistance Totem R1
  [10600] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Nature Resistance Totem R2
  [10601] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Nature Resistance Totem R3
  [25359] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Tranquil Air Totem
  [8512]  = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windfury Totem R1
  [10613] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windfury Totem R2
  [10614] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windfury Totem R3
  [15107] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windwall Totem R1
  [15421] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windwall Totem R2
  [15422] = { slot = AIR_TOTEM_SLOT, duration = 120 }, -- Windwall Totem R3
}

-- icon-based fallback table (用于非 Nampower 环境，或未知法术ID)
local totems = {
  [FIRE_TOTEM_SLOT] = {
    ["Spell_Fire_SealOfFire"] = {[-1] = 5},
    ["Spell_Nature_GuardianWard"] = {[-1] = 120},
    ["Spell_FrostResistanceTotem_01"] = {[-1] = 120},
    ["Spell_Fire_SelfDestruct"] = {[-1] = 20},
    ["Spell_Fire_SearingTotem"] = {[-1] = 55,[1] = 30,[2] = 35,[3] = 40,[4] = 45,[5] = 50,[6] = 55},
  },
  [EARTH_TOTEM_SLOT] = {
    ["Spell_Nature_StrengthOfEarthTotem02"] = {[-1] = 45},
    ["Spell_Nature_StoneClawTotem"] = {[-1] = 15},
    ["Spell_Nature_StoneSkinTotem"] = {[-1] = 120},
    ["Spell_Nature_EarthBindTotem"] = {[-1] = 120},
    ["Spell_Nature_TremorTotem"] = {[-1] = 120},
  },
  [WATER_TOTEM_SLOT] = {
    ["Spell_Nature_DiseaseCleansingTotem"] = {[-1] = 120},
    ["Spell_FireResistanceTotem_01"] = {[-1] = 120},
    ["INV_Spear_04"] = {[-1] = 60},
    ["Spell_Nature_ManaRegenTotem"] = {[-1] = 60},
    ["Spell_Frost_SummonWaterElemental"] = {[-1] = 12},
    ["Spell_Nature_PoisonCleansingTotem"] = {[-1] = 120},
  },
  [AIR_TOTEM_SLOT] = {
    ["Spell_Nature_InvisibilityTotem"] = {[-1] = 120},
    ["Spell_Nature_GroundingTotem"] = {[-1] = 45},
    ["Spell_Nature_NatureResistanceTotem"] = {[-1] = 120},
    ["Spell_Nature_Brilliance"] = {[-1] = 120},
    ["Spell_Nature_Windfury"] = {[-1] = 120},
    ["Spell_Nature_EarthBind"] = {[-1] = 120},
  },
}

GetTotemInfo = function(id)
  if not active[id] or not active[id].name then return end
  if active[id].start + active[id].duration - GetTime() < 0 then
    libtotem:Clean(id)
    return nil
  end

  return 1, active[id].name, active[id].start, active[id].duration, active[id].icon
end

if class ~= "SHAMAN" then return end

libtotem = CreateFrame("Frame")
libtotem:RegisterEvent("SPELLCAST_STOP")
libtotem:RegisterEvent("PLAYER_DEAD")
libtotem:SetScript("OnEvent", function()
  if event == "PLAYER_DEAD" then
    for i = 1,4 do
      libtotem:Clean(i)
    end
  elseif event == "SPELLCAST_STOP" then
    if queue.slot and queue.name then
      active[queue.slot].name = queue.name
      active[queue.slot].duration = queue.duration
      active[queue.slot].icon = queue.icon
      active[queue.slot].start = GetTime()
    end

    queue.slot = nil
    queue.name = nil
  end
end)

libtotem.totems = totems

libtotem.Clean = function(self, slot)
  active[slot].name = nil
  active[slot].start = nil
  active[slot].duration = nil
  active[slot].icon = nil
end

libtotem.CheckAddQueue = function(self, name, rank, icon)
  -- If Nampower is present, we don't use the queue – rely on SPELL_GO_SELF instead
  if hasNampower then return nil end

  for slot = 1, 4 do
    for texture, data in pairs(totems[slot]) do
      if string.find(icon, texture, 1) then
        if rank then -- try to obtain plain rank number
          _, _, rank = string.find(rank,"%s(%d+)")
        end

        queue.slot = slot
        queue.name = name
        queue.icon = icon
        if rank and tonumber(rank) and data[tonumber(rank)] then
          queue.duration = data[tonumber(rank)] * totemMasteryMultiplier
        else
          queue.duration = data[-1] * totemMasteryMultiplier
        end

        return true
      end
    end
  end

  return nil
end

-- 安全获取图标（防止无效 spellId 导致 GetSpellTexture 报错）
local function GetSpellIconSafe(spellId)
  if not spellId or type(spellId) ~= "number" or spellId <= 0 then
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end

  -- 尝试 Nampower 的 GetSpellTexture，用 pcall 避免报错
  if GetSpellTexture then
    local success, texture = pcall(GetSpellTexture, spellId)
    if success and texture and texture ~= "" then
      if not string.find(texture, "\\") then
        return "Interface\\Icons\\" .. texture
      end
      return texture
    end
  end

  -- 备选：通过 SpellRec 获取图标ID
  if GetSpellRecField and GetSpellIconTexture then
    local spellIconId = GetSpellRecField(spellId, "spellIconID")
    if spellIconId and spellIconId > 0 then
      local texture = GetSpellIconTexture(spellIconId)
      if texture and texture ~= "" then
        if not string.find(texture, "\\") then
          return "Interface\\Icons\\" .. texture
        end
        return texture
      end
    end
  end

  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- 如果 Nampower 可用，使用 SPELL_GO_SELF 直接记录图腾（优先基于 spellId）
if hasNampower then
  local nampowerFrame = CreateFrame("Frame")
  nampowerFrame:RegisterEvent("SPELL_GO_SELF")
  nampowerFrame:SetScript("OnEvent", function()
    if event == "SPELL_GO_SELF" then
      local itemId = arg1
      local spellId = arg2
      local casterGuid = arg3
      local targetGuid = arg4
      local numHit = arg6 or 0
      local numMissed = arg7 or 0

      -- 只处理成功施法
      if numMissed > 0 or numHit == 0 then return end
      if not spellId or spellId <= 0 then return end

      -- 获取法术名称和等级（安全）
      local name, rankString
      local icon = GetSpellIconSafe(spellId)

      -- 优先使用 SpellInfo (Nampower 提供)，若不可用则尝试 libspell
      if SpellInfo then
        name, rankString = SpellInfo(spellId)
      elseif libspell and libspell.GetSpellInfo then
        -- libspell.GetSpellInfo 需要 spellId 和书类型，这里传入 BOOKTYPE_SPELL（常量）
        name, rankString, _ = libspell.GetSpellInfo(spellId, BOOKTYPE_SPELL)
      end

      -- 如果仍然获取不到名称，放弃该事件（避免崩溃）
      if not name then return end

      -- 提取等级数字
      local rank = nil
      if rankString then
        _, _, rank = string.find(rankString, "%s(%d+)")
      end

      -- 第一步：通过 spellId 直接查找槽位和持续时间
      local spellData = spellids[spellId]
      if spellData then
        local slot = spellData.slot
        local duration = spellData.duration * totemMasteryMultiplier
        active[slot].name = name
        active[slot].duration = duration
        active[slot].icon = icon
        active[slot].start = GetTime()
        return
      end

      -- 第二步：如果 spellId 不在映射表中，回退到图标匹配（兼容未收录的法术）
      for slot = 1, 4 do
        for texture, data in pairs(totems[slot]) do
          if icon and string.find(icon, texture, 1, true) then
            local duration
            if rank and tonumber(rank) and data[tonumber(rank)] then
              duration = data[tonumber(rank)] * totemMasteryMultiplier
            else
              duration = data[-1] * totemMasteryMultiplier
            end
            active[slot].name = name
            active[slot].duration = duration
            active[slot].icon = icon
            active[slot].start = GetTime()
            return
          end
        end
      end
    end
  end)
end

-- assign library to global space
pfUI.api.libtotem = libtotem

-- 钩子函数（仅在无 Nampower 时工作）
hooksecurefunc("CastSpell", function(id, bookType)
  if not id or not bookType then return end
  if bookType ~= BOOKTYPE_SPELL and bookType ~= BOOKTYPE_PET then return end
  -- 修复：接收完整的 9 个返回值（新增第7、8扩展字段，原 spellId 变为第9）
  local name, rank, icon, _, _, _, _, _, spellId = libspell.GetSpellInfo(id, bookType)
  if not name then return end
  libtotem:CheckAddQueue(name, rank, icon, spellId)
end)

hooksecurefunc("CastSpellByName", function(effect, target)
  if hasNampower then return end
  local name, rank, icon = libspell.GetSpellInfo(effect)
  if not name then return end
  if libtotem:CheckAddQueue(name, rank, icon) then return end
end)

local scanner = libtipscan:GetScanner("prediction")
hooksecurefunc("UseAction", function(slot, target, selfcast)
  if hasNampower then return end
  if GetActionText(slot) or not IsCurrentAction(slot) then return end
  scanner:SetAction(slot)
  local name, rank = scanner:Line(1)
  local icon = GetActionTexture(slot)
  if not name then return end
  if libtotem:CheckAddQueue(name, rank, icon) then return end
end)