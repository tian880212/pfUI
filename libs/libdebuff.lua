-- 加载 pfUI 环境
setfenv(1, pfUI:GetEnvironment())

--[[ libdebuff - GetUnitField 版本 ]]--
-- 一个 pfUI 库，用于检测并保存所有玩家、NPC 和敌人的持续减益效果。
-- 
-- 重大重写：现在使用 GetUnitField 进行槽位映射，取代手动移位。
-- 关键洞察：GetUnitField 返回稳定的光环槽位（33-48），当减益效果消失时不会移位。
-- 只有显示槽位（UnitDebuff 返回的 1,2,3...）会被压缩。
--
-- 这消除了大约 400 行容易出错的移位逻辑，同时保持完整的多施法者追踪支持。
--
--  libdebuff:UnitDebuff(unit, id)
--    返回指定单位上指定效果的减益信息。
--    name, rank, texture, stacks, dtype, duration, timeleft, caster

-- 如果不是在经典客户端上则立即返回
if pfUI.client > 11200 then return end

-- 如果另一个 libdebuff 已经激活则立即返回
if pfUI.api.libdebuff then return end

-- 修复 ruRU 捕获索引中的拼写错误（缺少 $）
if GetLocale() == "ruRU" then
  SPELLREFLECTSELFOTHER = gsub(SPELLREFLECTSELFOTHER, "%%2s", "%%2%$s")
end

local libdebuff = CreateFrame("Frame", "pfdebuffsScanner", UIParent)
local scanner = libtipscan:GetScanner("libdebuff")
local _, class = UnitClass("player")
local lastspell

-- Nampower 支持
local hasNampower = false

-- 立即设置 hasNampower 以便功能正常
if GetNampowerVersion then
  local major, minor, patch = GetNampowerVersion()
  patch = patch or 0
  -- 最低要求版本：2.41.0（支持 CastSpellByName unitStr、SetMouseoverUnit）
  if major > 2 or (major == 2 and minor > 41) or (major == 2 and minor == 41 and patch >= 0) then
    hasNampower = true
  end
end

-- Nampower 启动检查：显示版本信息并确保 CVar 已设置。
-- 在 PLAYER_ENTERING_WORLD 后的第一个 OnUpdate 上运行，给 Nampower 初始化时间。

-- GetSpellDuration（Nampower v2.38+）：DBC 权威光环时长（含天赋修正，ms）。
-- 参考 SuperCleveRoidMacros：durationMs==0/缺失时的首选时长来源，远比静态名库准确。
-- ⚠️ 挂在 libdebuff 表上而非顶层 local：Lua 5.0 单闭包 upvalue 上限 32，
-- 主 OnEvent 闭包已接近上限，新增顶层 local 会令整文件加载失败（buff/debuff 全失效）
libdebuff.GetSpellDurationSec = function(spellId)
  -- 惰性版本检测（首次调用判定，缓存到函数属性，避免额外顶层 local）
  if libdebuff._gdsEnabled == nil then
    libdebuff._gdsEnabled = false
    if GetNampowerVersion and GetSpellDuration then
      local major, minor, patch = GetNampowerVersion()
      patch = patch or 0
      if major > 2 or (major == 2 and minor > 38) or (major == 2 and minor == 38 and patch >= 0) then
        libdebuff._gdsEnabled = true
      end
    end
    libdebuff._gdsCache = {}
  end
  if not libdebuff._gdsEnabled or not spellId or type(spellId) ~= "number" or spellId <= 0 then
    return nil
  end
  local cached = libdebuff._gdsCache[spellId]
  if cached then return cached end
  local ok, ms = pcall(GetSpellDuration, spellId)
  local dur = nil
  if ok and ms and type(ms) == "number" and ms > 0 then
    dur = ms / 1000
  end
  -- nil 说明该 spellId 无光环时长（瞬时法术）；同一 spellId 结果恒定，
  -- 用 false 缓存"确认无时长"防重复 DBC 查询
  libdebuff._gdsCache[spellId] = dur or false
  return dur
end
local nampowerCheckFrame = CreateFrame("Frame")
nampowerCheckFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
nampowerCheckFrame:SetScript("OnEvent", function()
  -- 推迟到下一帧，以便 Nampower 完全初始化
  this:SetScript("OnUpdate", function()
    this:SetScript("OnUpdate", nil)
    this:UnregisterAllEvents()
    this:SetScript("OnEvent", nil)

    if GetNampowerVersion then
      local major, minor, patch = GetNampowerVersion()
      patch = patch or 0
      local versionString = major .. "." .. minor .. "." .. patch

      if major > 3 or (major == 3 and minor > 0) or (major == 3 and minor == 0 and patch >= 0) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r 检测到 Nampower v" .. versionString .. " - GetUnitField 模式已启用！")

        if SetCVar and GetCVar then
          local cvarsToEnable = {
            "NP_EnableSpellStartEvents",
            "NP_EnableSpellGoEvents",
            "NP_EnableAuraCastEvents",
            "NP_EnableAutoAttackEvents",
            "NP_EnableSpellHealEvents", 
          }
          local enabledCount = 0
          local alreadyEnabledCount = 0
          local failedCount = 0

          for _, cvar in ipairs(cvarsToEnable) do
            local success, currentValue = pcall(GetCVar, cvar)
            if success and currentValue then
              if currentValue == "1" then
                alreadyEnabledCount = alreadyEnabledCount + 1
              else
                local setSuccess = pcall(SetCVar, cvar, "1")
                if setSuccess then enabledCount = enabledCount + 1
                else failedCount = failedCount + 1 end
              end
            else
              failedCount = failedCount + 1
            end
          end

          if enabledCount > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r 已启用 " .. enabledCount .. " 个 Nampower CVar")
          elseif alreadyEnabledCount == table.getn(cvarsToEnable) then
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r 所有必需的 Nampower CVar 均已启用")
          end
          if failedCount > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[libdebuff]|r 警告：无法检查/设置 " .. failedCount .. " 个 CVar")
          end
        end

      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[libdebuff] 减益追踪已禁用！请将 Nampower 更新到 v3.0.0 或更高版本。|r")
        StaticPopup_Show("LIBDEBUFF_NAMPOWER_UPDATE", versionString)
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r Nampower 未加载，已启用回退模式（经典事件扫描）。")
    end
  end)
end)

-- ============================================================================
-- 数据结构（简化 - 不再需要手动槽位追踪！）
-- ============================================================================

-- ownDebuffs: [targetGUID][spellName] = {startTime, duration, texture, rank}
-- 仅存储我们自己施放的减益计时数据
pfUI.libdebuff_own = pfUI.libdebuff_own or {}
local ownDebuffs = pfUI.libdebuff_own

-- allAuraCasts: [targetGUID][spellName][casterGuid] = {startTime, duration, rank}
-- 存储所有减益的计时数据（多施法者支持）
pfUI.libdebuff_all_auras = pfUI.libdebuff_all_auras or {}
local allAuraCasts = pfUI.libdebuff_all_auras

-- slotOwnership: [targetGUID][auraSlot] = {casterGuid, spellName, spellId}
-- 将真实光环槽位（33-48）映射到施法者信息 - 无需移位！
pfUI.libdebuff_slot_ownership = pfUI.libdebuff_slot_ownership or {}
local slotOwnership = pfUI.libdebuff_slot_ownership

-- displayToAura: [targetGUID][displaySlot] = auraSlot
-- 将显示槽位（1-16）映射到真实光环槽位（33-48），用于 DEBUFF_REMOVED 关联
pfUI.libdebuff_display_to_aura = pfUI.libdebuff_display_to_aura or {}
local displayToAura = pfUI.libdebuff_display_to_aura

-- pendingCasts: [targetGUID][spellName] = {casterGuid, rank, time}
-- 从 SPELL_GO 到 DEBUFF_ADDED 关联的临时存储
pfUI.libdebuff_pending = pfUI.libdebuff_pending or {}
local pendingCasts = pfUI.libdebuff_pending

-- 法术图标缓存：[spellId] = texture
pfUI.libdebuff_icon_cache = pfUI.libdebuff_icon_cache or {}
local iconCache = pfUI.libdebuff_icon_cache

-- 施法追踪：[casterGuid] = {spellID, spellName, icon, startTime, duration, endTime}
-- 与姓名版共享，用于施法条显示
pfUI.libdebuff_casts = pfUI.libdebuff_casts or {}
pfUI.libdebuff_item_icons = pfUI.libdebuff_item_icons or {}  -- [casterGuid] = icon（在 SPELL_GO 后持续存在）

-- Cleveroids API：[targetGUID][spellID] = {start, duration, caster, stacks}
pfUI.libdebuff_objects_guid = pfUI.libdebuff_objects_guid or {}
local objectsByGuid = pfUI.libdebuff_objects_guid

-- 遗留：为向后兼容保留（外部模块可能检查它们）
pfUI.libdebuff_own_slots = pfUI.libdebuff_own_slots or {}
pfUI.libdebuff_all_slots = pfUI.libdebuff_all_slots or {}

-- 去重：追踪最近的 AURA_CAST 事件，忽略重复
-- [targetGuid][spellName][casterGuid] = 时间戳
pfUI.libdebuff_recent_casts = pfUI.libdebuff_recent_casts or {}
local recentCasts = pfUI.libdebuff_recent_casts

-- 在 SPELL_GO_SELF 处理后触发的回调：fn(spellId, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
pfUI.libdebuff_spell_go_hooks = pfUI.libdebuff_spell_go_hooks or {}

-- 在 SPELL_GO_OTHER 处理后触发的回调：fn(spellId, casterGuid, targetGuid)
pfUI.libdebuff_spell_go_other_hooks = pfUI.libdebuff_spell_go_other_hooks or {}

-- 在 SPELL_START_SELF 处理后触发的回调：fn(spellId, casterGuid, targetGuid, castTime)
pfUI.libdebuff_spell_start_self_hooks = pfUI.libdebuff_spell_start_self_hooks or {}

-- 在 SPELL_START_OTHER 处理后触发的回调：fn(spellId, casterGuid, targetGuid, castTime)
pfUI.libdebuff_spell_start_other_hooks = pfUI.libdebuff_spell_start_other_hooks or {}

-- 在 SPELL_FAILED_OTHER 处理后触发的回调：fn(casterGuid, spellId)
pfUI.libdebuff_spell_failed_other_hooks = pfUI.libdebuff_spell_failed_other_hooks or {}

-- 在 AURA_CAST_ON_SELF 处理后触发的回调：fn(spellId, casterGuid, targetGuid)
pfUI.libdebuff_aura_cast_on_self_hooks = pfUI.libdebuff_aura_cast_on_self_hooks or {}

-- 在 AURA_CAST_ON_OTHER 处理后触发的回调：fn(spellId, casterGuid, targetGuid)
pfUI.libdebuff_aura_cast_on_other_hooks = pfUI.libdebuff_aura_cast_on_other_hooks or {}

-- 在 DEBUFF_ADDED_OTHER 处理后触发的回调：fn(guid, luaSlot, spellId, stackCount)
pfUI.libdebuff_debuff_added_other_hooks = pfUI.libdebuff_debuff_added_other_hooks or {}

-- 在 DEBUFF_REMOVED_OTHER 处理后触发的回调：fn(guid, luaSlot, spellId, stackCount)
pfUI.libdebuff_debuff_removed_other_hooks = pfUI.libdebuff_debuff_removed_other_hooks or {}

-- 在 UNIT_HEALTH 处理后触发的回调：fn(unitToken)
pfUI.libdebuff_unit_health_hooks = pfUI.libdebuff_unit_health_hooks or {}

-- 在 PLAYER_TARGET_CHANGED 处理后触发的回调：fn()
pfUI.libdebuff_player_target_changed_hooks = pfUI.libdebuff_player_target_changed_hooks or {}

-- 在 UNIT_DIED 处理后触发的回调：fn(guid)
pfUI.libdebuff_unit_died_hooks = pfUI.libdebuff_unit_died_hooks or {}

-- 在 SPELL_CAST_EVENT 处理后触发的回调：fn(success, spellId, castType, targetGuid)
pfUI.libdebuff_spell_cast_hooks = pfUI.libdebuff_spell_cast_hooks or {}
local AURA_CAST_DEDUPE_WINDOW = 0.1  -- 100ms 内的重复事件忽略

-- 从 SPELL_CAST_EVENT 捕获的连击点数（在客户端消耗之前）
-- SPELL_CAST_EVENT 在 UnitAura 更新之前触发，因此 GetComboPoints() 仍然有效
local capturedCP = nil

-- libpredict 的待处理施法信息（治疗预判目标追踪）
-- SPELL_CAST_EVENT 在 SPELLCAST_START 之前触发并带有 targetGuid，
-- 这使得 libpredict 能够知道队列中施法的正确目标。
-- 字段：{ spellId, spellName, targetGuid, time }
pfUI.libpredict_pending_cast = pfUI.libpredict_pending_cast or {}

-- ============================================================================
-- 静态弹出对话框
-- ============================================================================

StaticPopupDialogs["LIBDEBUFF_NAMPOWER_UPDATE"] = {
  text = "|cffff0000！！！警告！！！|r\n\n需要更新 Nampower！\n\n您当前的版本：%s\n所需版本：3.0.0+\n\n请更新 Nampower 以继续使用 pfUI！",
  button1 = "显示下载链接",
  button2 = "忽略",
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0,
  preferredIndex = 3,
  OnAccept = function()
    pfUI.chat.urlcopy.CopyText("https://www.123865.com/s/jQkDVv-jbK53?pwd=4352#")
  end,
}

StaticPopupDialogs["LIBDEBUFF_NAMPOWER_MISSING"] = {
  text = "|cffff0000！！！警告！！！|r\n\n未找到 Nampower！\n\npfUI 正常运行需要 Nampower 3.0.0+。\n\n请安装 Nampower！",
  button1 = "显示下载链接",
  button2 = "忽略",
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 0,
  preferredIndex = 3,
  OnAccept = function()
    pfUI.chat.urlcopy.CopyText("https://www.123865.com/s/jQkDVv-jbK53?pwd=4352#")
  end,
}

-- ============================================================================
-- 法术数据表（回退模式使用）
-- ============================================================================

-- 只有一个玩家可以拥有的减益（覆盖其他施法者）
local selfOverwriteDebuffs = {
  ["精灵之火"] = true,
  ["精灵之火（野性）"] = true,
  ["挫志怒吼"] = true,
  ["挫志咆哮"] = true,
  ["猎人印记"] = true,
  ["破甲攻击"] = true,
  ["雷霆一击"] = true,
  ["破甲"] = true,
  ["暗影易伤"] = true,
  ["虚弱诅咒"] = true,
  ["鲁莽诅咒"] = true,
  ["元素诅咒"] = true,
  ["暗影诅咒"] = true,
  ["语言诅咒"] = true,
  ["疲劳诅咒"] = true,
  ["智慧审判"] = true,
  ["光明审判"] = true,
  ["十字军审判"] = true,
  ["公正审判"] = true,
  ["暗影之波"] = true,
  ["深冬之寒"] = true,
}

-- 猎人陷阱效果列表（可根据实际客户端语言调整）
local trapDebuffs = {
    ["爆炸陷阱效果"] = true,
    ["冰霜陷阱光环"] = true,
    -- 其他陷阱效果可按需添加
}

-- 相互覆盖的减益对
local debuffOverwritePairs = {
  ["精灵之火"] = "精灵之火（野性）",
  ["精灵之火（野性）"] = "精灵之火",
  ["挫志怒吼"] = "挫志咆哮",
  ["挫志咆哮"] = "挫志怒吼",
}

-- 连击点技能：仅显示我们自己的施法计时器
local combopointAbilities = {
  -- Druid
  ["撕扯"] = { base = 8,  perCP = 2 },
  -- Rogue
  ["割裂"] = { base = 6, perCP = 2 },
  ["肾击"] = { base = 1, perCP = 1 },
  ["切割"] = { base = 9, perCP = 3 },
  ["破甲"] = { base = 30, perCP = 0 },  -- fixed 30s
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

-- Check if spell is a combo-point ability
local function IsComboPointAbility(spellName)
  if not spellName then return false end
  return combopointAbilities[spellName] ~= nil
end

-- Get combo-point spell data (base duration and per-CP bonus)
local function GetComboPointData(spellName)
    if not spellName then 
        return nil, nil 
    end
    local cpData = combopointAbilities[spellName]
    if cpData then
        if spellName == "割裂" then
            local _, _, _, _, count = GetTalentInfo(1, 10)
            if count and count > 0 then
                local base_Talent = cpData.base + 2 + count * 2
                return base_Talent, cpData.perCP
            else
                return cpData.base, cpData.perCP  
            end
        else
            return cpData.base, cpData.perCP
        end
    end
    return nil, nil
end

-- Player GUID Cache
local playerGUID = nil
local function GetPlayerGUID()
  if not playerGUID and UnitExists then
    local _, guid = UnitExists("player")
    playerGUID = guid
  end
  return playerGUID
end

-- Debug Stats
pfUI.libdebuff_debugstats = pfUI.libdebuff_debugstats or {
  enabled = false,
  trackAllUnits = false,
  aura_cast = 0,
  debuff_added = 0,
  debuff_removed = 0,
  getunitfield_calls = 0,
  -- buff 侧（GetBuffSlot）统计：专门给「取数函数到底被调了多少次」用。
  -- 与上面的 getunitfield_calls（只统计 GetDebuffSlotMap 的 debuff 槽映射）分开，
  -- 免得两条路径的数字混在一起没法定位。
  getbuffslot_calls = 0,       -- GetBuffSlot 被调用次数（含空槽）
  getbuffslot_fetches = 0,     -- 真正调用 GetUnitField(guid,"aura") 的次数（每次 = 一整份 48 项数组）
  getbuffslot_appfetches = 0,  -- 真正调用 GetUnitField(guid,"auraApplications") 的次数
  -- 溢出归类运行期开关（/libdebugstats overflow auto|always|never）：给"目标 debuff 在两行之间
  -- 跑动"这类现象做二分定位用。nil/"auto" = 按单调闩锁自动判定（正常值）。
  overflowMode = nil,
}
local debugStats = pfUI.libdebuff_debugstats

local function DebugGuid(guid)
  if not guid then return "nil" end
  local str = tostring(guid)
  if string.len(str) > 4 then
    return string.sub(str, -4)
  end
  return str
end

local function IsCurrentTarget(guid)
  if debugStats.trackAllUnits then return true end
  if not guid or not UnitExists then return false end
  local _, targetGuid = UnitExists("target")
  return targetGuid == guid
end

local function GetDebugTimestamp()
  return string.format("[%.3f]", GetTime())
end

-- Speichert die Ranks der zuletzt gecasteten Spells
pfUI.libdebuff_lastranks = pfUI.libdebuff_lastranks or {}
local lastCastRanks = pfUI.libdebuff_lastranks

-- Speichert Spells die gefailed sind
pfUI.libdebuff_lastfailed = pfUI.libdebuff_lastfailed or {}
local lastFailedSpells = pfUI.libdebuff_lastfailed

-- Get spell icon texture (with caching)
function libdebuff:GetSpellIcon(spellId)
  if not spellId or type(spellId) ~= "number" or spellId <= 0 then
    return "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  
  if iconCache[spellId] then
    return iconCache[spellId]
  end
  
  local texture = nil
  
  if GetSpellRecField and GetSpellIconTexture then
    local spellIconId = GetSpellRecField(spellId, "spellIconID")
    if spellIconId and type(spellIconId) == "number" and spellIconId > 0 then
      texture = GetSpellIconTexture(spellIconId)
      -- GetSpellIconTexture may return short name, needs full path for SetTexture
      if texture and not string.find(texture, "\\") then
        texture = "Interface\\Icons\\" .. texture
      end
    end
  end
  
  if not texture then
    texture = "Interface\\Icons\\INV_Misc_QuestionMark"
  end
  
  iconCache[spellId] = texture
  return texture
end

pfUI.libdebuff_GetSpellIcon = function(spellId)
  return libdebuff:GetSpellIcon(spellId)
end

function libdebuff:DidSpellFail(spell)
  if not spell then return false end
  local data = lastFailedSpells[spell]
  if data and (GetTime() - data.time) < 1 then
    return true
  end
  return false
end

-- ============================================================================
-- CORE: GetUnitField-based Slot Mapping (THE KEY INNOVATION!)
-- ============================================================================

-- Cache for GetDebuffSlotMap to reduce GetUnitField calls
-- [guid] = {map, timestamp}
local slotMapCache = {}
local SLOT_MAP_CACHE_DURATION = 0.05  -- 50ms cache (1-2 frames)

-- 🔴 溢出可能性「单调闩锁」：[guid] = true 表示**曾经**观察到该 guid 的 16 个 debuff 槽
-- (aura 33-48) 全满。
-- 为什么不塞进 slotMapCache（两个方案都试过，都会踩坑）：
--   ① 塞进 [guid] 条目 → 三处 `slotMapCache[guid] = nil`（DEBUFF_ADDED / DEBUFF_REMOVED / 切目标）
--      会把闩锁一起清掉，单调性当场失效；
--   ② 挂成兄弟键 slotMapCache.barWasFull → 任何 `for k in pairs(slotMapCache)` 的遍历都会把它
--      当成缓存条目（离线仿真第一版就是这么发现的：clearCache 把兄弟键清成 nil，下一句
--      `slotMapCache.barWasFull[guid] = true` 立刻报 "index a nil value"）。
-- 挂到 libdebuff 上，只借用 GetDebuffSlotMap 已有的 `libdebuff` upvalue ⇒ **upvalue 净增 0**。
-- 生命周期：纯内存态，重载即清（CreateFrame 会重建 libdebuff）；量级 = 一场战斗见过的 guid
-- 数（几百个布尔键），可忽略。
libdebuff.overflowLatch = libdebuff.overflowLatch or {}

-- ============================================================================
-- debuff 识别（2026-09-14 三次修复）：极性表 + 判定表，双权威来源
-- ============================================================================
-- 【为什么必须换判据】Turtle 服务端会把 NPC 第 17+ 个 debuff 塞进 buff 区（aura 1-32）。
-- 客户端判断"增益/减益"是**纯按槽位**做的（1-32 = 增益、33-48 = 减益），所以它自己也
-- 不知道塞进 buff 区的那个其实是减益 —— 不存在"问原生 API 一句就得到答案"这条路。
-- 【判据分档】① ② ②b 三档权威（与战斗状态无关 ⇒ 判定恒定，不会在两行之间翻转）：
--   ① slotOwnership 槽位归属（DEBUFF_ADDED_OTHER 写入，带 spellId 校验）—— 机制事实
--   ② 判定表：该法术**曾经**出现在 aura 33-48（客户端固定的减益区）⇒ 它必然是减益
--   ②b auraFlags 每槽 4bit 的"减益位"（实测 0x8）—— **客户端自己的判定**，默认开启
--   ③ 极性：Nampower 法术记录里的极性字段 —— ⚠ 实测无效（50+ 法术全部"无字段"，
--      GetSpellRec 暴露的键里没有正/负极性），保留但基本不会命中
--   ④ 名字库 L["debuffs"] —— 弱证据，只在"该目标曾出现过溢出"的闩锁开启时才采信
-- ①②②b 全部单调 ⇒「同一批图标在两行之间瞬移」从机制上消失。
--
-- 两张表都挂在 libdebuff 上而不是新增文件级 local —— 沿用 overflowLatch 的先例，
-- 让相关闭包（GetDebuffSlotMap / 主 OnEvent / 诊断命令）的 upvalue 净增保持 0。
libdebuff.auraPolarity  = libdebuff.auraPolarity  or {}  -- [spellId] = 1(减益) / 0(增益)  ← 单调结论
libdebuff.spellPolarity = libdebuff.spellPolarity or {}  -- [spellId] = 1 / 0 / -1(记录里没有该字段)

-- 判据②b：客户端自己的每槽光环标志位（GetUnitField(guid,"auraFlags")）。
-- ★2026-09-14 四修：结构与位义已从实战日志反推出来（此前以为"离线无法确认"，其实可以）★
--   · 结构：auraFlags 是 **6 个 uint32**，每块装 8 个槽位、每槽 4bit（每字节 2 槽，低半在前）。
--     证据：同一时刻第 7 块起恒为 nil（48/8=6）；把用户日志里三份快照的块值按此解码，
--     还原出的"占用槽位"与 GetUnitField aura 的非空槽位（含空洞位置）**逐一吻合、零例外**：
--       0x88088888 → 8,8,8,8,8,0,8,8  （槽 6 空）   ← 17:00:56 实测占用 1,2,3,4,5,7,8
--       0x88088808 → 8,0,8,8,8,0,8,8  （槽 2/6 空） ← 17:01:00 实测占用 1,3,4,5,7,8
--       0x08885888 → 8,8,8,8,8,8,8,0  （槽 8 空）   ← 17:01:33 实测占用 1,2,3,4,5,6,7
--     ⇒ 旧写法 `aflags[auraSlot]` 拿的是"第 auraSlot 个块"（一个块 = 8 个槽挤在一起），
--       根本不是该槽的值 —— 所以之前打出来的 0x88088888 看着像垃圾，判据自然全错。
--   · 位义：减益区 33-48 的 16 个槽**全部** = 0x8；buff 区里已确认为减益的溢出槽也全部 = 0x8；
--     而唯一一个确定友好的光环（命令战旗 47408）= 0x5 ⇒ **bit 0x8 = 客户端认定的"减益"**。
--     （0x5 的存在同时排除了"0x8 只是占用标记"这个读法：占用槽也会有 0x5。）
--   · 默认开启，`/libdebugstats flagbit 0` 随时关（/reload 后恢复默认）。
--     **不写入单调判定表**：位是槽级的、整个持续期恒定，本身就不会翻转；写进表反而是把一个
--     未 100% 确认的位永久固化，得不偿失（不写 ⇒ 填错只影响归类，复位即恢复）。
local FLAG_DEBUFF_BIT_DEFAULT = 8
if libdebuff.flagDebuffBit == nil then libdebuff.flagDebuffBit = FLAG_DEBUFF_BIT_DEFAULT end

-- 从 auraFlags 里取**单个槽位**的 4bit 值（slot = 1 起的原始槽位 1-48）。
-- 布局：块号 = (slot-1)/8 + 1；块内字节号 = ((slot-1) mod 8)/2；低半/高半由 (slot-1) mod 2 定；
--       字节在 uint32 里按小端排列。Lua 5.0 无位运算符 ⇒ 全用 math.floor / math.mod / `^`。
--       ⛔ 不要用 math.pow：它在 Lua 5.3 已移除（离线仿真是 5.3），而 `^` 在 5.0/5.3 都在。
function libdebuff.GetSlotFlag(flags, slot)
  if type(flags) ~= "table" or type(slot) ~= "number" or slot < 1 or slot > 48 then return nil end
  local v = flags[math.floor((slot - 1) / 8) + 1]
  if type(v) ~= "number" then return nil end
  local idx = math.mod(slot - 1, 8)
  v = math.floor(v / 256 ^ math.floor(idx / 2))          -- 先切到该槽所在的那一个字节
  if math.mod(idx, 2) == 0 then
    return math.mod(v, 16)                  -- 偶数槽 → 字节低半
  end
  return math.floor(math.mod(v, 256) / 16)  -- 奇数槽 → 字节高半
end

-- 从 Nampower 的法术记录里读「极性」。返回 1=减益 / 0=增益 / -1=记录里查不到。
-- 为什么不写死字段名：nampower.dll 里确实有 positive/negative 两个裸串，但**离线无法确认
-- 它挂在哪个键上**（用法串没暴露），写死一个猜的名字只会静默失效。改为**扫描整条记录**：
--   键名命中 negative/isNegative/harmful/isDebuff 且值为真 → 减益
--   键名命中 positive/isPositive/helpful/isBuff    且值为真 → 增益
--   任意键的**值**恰为字符串 "negative"/"positive"          → 直接采信（最可能的形态）
-- 成本：每个 spellId 只扫一次（GetSpellRec 返回 ~100 键的表，绝不能进热路径）。结果缓存，
-- 查不到也缓存 -1（否则每个新法术每次刷新都白扫一遍）。
function libdebuff:GetSpellPolarity(spellId)
  if not spellId or type(spellId) ~= "number" or spellId <= 0 then return -1 end
  local cache = libdebuff.spellPolarity
  local hit = cache[spellId]
  if hit ~= nil then return hit end

  local pol = -1
  if GetSpellRec then
    -- copy=1：取独立副本。Nampower 会复用同一张表，不复制就可能读到别人改过的内容。
    local ok, rec = pcall(GetSpellRec, spellId, 1)
    if ok and type(rec) == "table" then
      local neg, pos = false, false
      for k, v in pairs(rec) do
        if type(k) == "string" then
          local lk = string.lower(k)
          if v == "negative" or lk == "negative" or lk == "isnegative" or lk == "harmful" or lk == "isdebuff" then
            if v and v ~= false and v ~= 0 and v ~= "" then neg = true end
          elseif v == "positive" or lk == "positive" or lk == "ispositive" or lk == "helpful" or lk == "isbuff" then
            if v and v ~= false and v ~= 0 and v ~= "" then pos = true end
          end
        end
      end
      if neg then pol = 1 elseif pos then pol = 0 end
    end
  end

  cache[spellId] = pol
  return pol
end

-- 判定「buff 区（aura 1-32）某个槽位上的法术是不是溢出减益」。
-- 返回 isDebuff, sourceLabel（source 仅用于 /libdebugstats target 显示判定依据）。
-- 本函数是**唯一**的归类点：显示层（IsBuffSlotDebuff → map.overflowAuraSlots）与诊断命令
-- 都走这里 —— 两处各写一份逻辑迟早会分叉，然后出现"行里有图标、判定却说不该有"。
function libdebuff:ClassifyAuraSlot(guid, auraSlot, spellId, overflowPossible, auraFlag)
  if not spellId or type(spellId) ~= "number" or spellId <= 0 then return false, "空" end

  local verdict = libdebuff.auraPolarity

  -- ① 权威·机制：DEBUFF_ADDED_OTHER 写下的槽位归属（spellId 校验挡住槽位被复用的陈旧记录）
  local ownTbl = slotOwnership[guid]
  local own = ownTbl and ownTbl[auraSlot]
  if own and own.spellId == spellId then
    verdict[spellId] = 1
    return true, "归属"
  end

  -- ② 已下过结论（学习 / 极性）—— 单调，永不反转。这一档就是"不再跑动"的保证。
  local v = verdict[spellId]
  if v == 1 then return true, "已判·减益" end
  if v == 0 then return false, "已判·增益" end

  -- ②b 客户端标志位（**默认开启**，见 FLAG_DEBUFF_BIT_DEFAULT）。auraFlag 是**已解码**的单槽
  --     4bit 值（libdebuff.GetSlotFlag），不是打包块。为什么它是这里最强的判据：数组位置不可信
  --     （同一池子、槽位会换），而这一位由客户端自己按"该光环是增益还是减益"写，与槽满不满、
  --     与战斗状态都无关 ⇒ 恒定，不会翻转。**不写入判定表**：位是槽级的，写进表反而是把一个
  --     未 100% 确认的位永久固化 —— 不写 ⇒ 填错只影响归类，flagbit 0 立刻复位。
  --     故意**不**要求 overflowPossible 闩锁：闩锁是拿来给"弱证据"把门的，而这一位本身够强；
  --     挂上闩锁反而会让"刚进战斗、还没满过 16 槽"时漏判。
  local fbit = libdebuff.flagDebuffBit
  -- type 守卫不能省：flagDebuffBit 是**运行期**由斜杠命令写入的，一旦写进非数字
  -- （或模块表被 mock 出兜底值），下面的除法就会直接抛错 → 整条显示链崩掉。
  if type(fbit) == "number" and fbit > 0 and auraFlag and type(auraFlag) == "number" and auraFlag > 0 then
    if math.mod(math.floor(auraFlag / fbit), 2) == 1 then
      return true, "标志位"
    end
  end

  -- ③ 极性（权威，但要查一次法术记录 —— 已按 spellId 缓存）
  local pol = libdebuff:GetSpellPolarity(spellId)
  if pol == 1 then verdict[spellId] = 1; return true, "极性·减益" end
  if pol == 0 then verdict[spellId] = 0; return false, "极性·增益" end

  -- ④ 弱证据：名字库。该表实为「带时长光环」大杂烩（含 荆棘术/奥术智慧/卷轴 buff 等
  --    NPC 真 buff），所以必须由"该目标曾出现过溢出"的闩锁把门，否则 buff 会被推进 debuff 行。
  if overflowPossible then
    local nm = GetSpellRecField and GetSpellRecField(spellId, "name")
    if nm and L["debuffs"][nm] then return true, "名字库" end
  end

  return false, "buff"
end

-- Dispel type mapping: SpellRec.dispel index -> Blizzard DebuffTypeColor key
local dispelTypeMap = {
  [1] = "Magic",
  [2] = "Curse",
  [3] = "Disease",
  [4] = "Poison",
}

-- Get current debuff state directly from WoW via GetUnitField
-- Returns: { [displaySlot] = {auraSlot, spellId, spellName, stacks, texture, dtype} }
-- unitstr 为可选参数：提供时（且目标非玩家）会额外识别溢出 debuff（显示槽 17+）
local function GetDebuffSlotMap(guid, unitstr)
  if not guid or not GetUnitField then
    return nil
  end
  
  -- 本次调用能否算出"溢出识别"：只有拿到 unitstr 且目标不是玩家时才可能算出来。
  local wantsOverflow = (unitstr ~= nil) and (not UnitIsPlayer or not UnitIsPlayer(unitstr))

  -- Check cache first
  local now = GetTime()
  local cached = slotMapCache[guid]
  if cached and cached.map and (now - cached.timestamp) < SLOT_MAP_CACHE_DURATION then
    -- ⛔ 缓存必须按「这份地图含不含溢出信息」区分（2026-09-14 修复）：
    --    带 unitstr 的调用（显示层 UnitDebuff / IsBuffSlotDebuff）算得出溢出；
    --    不带 unitstr 的调用（DEBUFF_ADDED_OTHER 里按 displaySlot 反查 auraSlot）**算不出**。
    --    两者共用一份缓存时，显示层会拿到"无溢出版"地图 → 溢出 debuff 一边从 debuff 行消失、
    --    一边不再被 buff 行剔除 → 整批图标在两行之间瞬移。
    --    判据：调用方不需要溢出，或缓存本身就是带溢出的，才允许命中。
    if (not wantsOverflow) or cached.hasOverflow then
      return cached.map
    end
  end

  local auras = GetUnitField(guid, "aura")
  if not auras then return nil end
  
  -- Fetch stacks array (reusable reference - extract values immediately)
  local auraApps = GetUnitField(guid, "auraApplications")
  
  if debugStats.enabled then
    debugStats.getunitfield_calls = debugStats.getunitfield_calls + 1
  end
  
  local map = {}
  local displaySlot = 0
  
  -- Debuff aura slots are 33-48
  for auraSlot = 33, 48 do
    local spellId = auras[auraSlot]
    if spellId and spellId > 0 then
      -- 学习（判据②）：非玩家单位的 aura 33-48 是客户端**固定的减益区**，出现在这里的法术
      -- 必然是减益。写进单调判定表后，同一个法术下次溢出到 buff 区时结论已经定好、永不反转
      -- —— 这是"溢出 debuff 不会再被当成 buff"最根本的一条：它**一定**曾经在减益区出现过
      -- （服务端是先把 33-48 填满、溢出才发生），所以学习收敛只是时间问题，且收敛后恒定。
      -- 只在 wantsOverflow（已确认是非玩家单位）时学：玩家侧的 33-48 语义不同，别混。
      -- 只写不覆盖：第一条结论永久生效，避免"先学增益后学减益"这种自相矛盾。
      if wantsOverflow and libdebuff.auraPolarity[spellId] == nil then
        libdebuff.auraPolarity[spellId] = 1
      end

      displaySlot = displaySlot + 1
      local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
      local texture = libdebuff:GetSpellIcon(spellId)
      
      -- Get stacks from auraApplications (0-indexed, so +1 for display)
      local stacks = (auraApps and auraApps[auraSlot] or 0) + 1
      
      -- Get debuff type from SpellRec DBC
      local dtype = nil
      if GetSpellRecField then
        local dispelId = GetSpellRecField(spellId, "dispel")
        if dispelId and dispelId > 0 then
          dtype = dispelTypeMap[dispelId]
        end
      end
      
      map[displaySlot] = {
        auraSlot = auraSlot,
        spellId = spellId,
        spellName = spellName or "未知",
        stacks = stacks,
        texture = texture,
        dtype = dtype
      }
    end
  end

  -- 溢出 debuff 识别（显示槽 17+）：
  -- SuperWoW/Nampower 机制：NPC 目标 debuff 超过 16 个时，第 17+ 个 debuff 由服务器/客户端
  -- 放进 buff 区（GetUnitField aura 1-32），原生 UnitDebuff 对它们返回 nil，
  -- 原生 UnitBuff 会把它们当 buff 返回 —— 这就是"溢出 debuff 被显示成 buff"的根源。
  -- 为什么没有"第三方权威"可用（2026-09-14 实锤）：Nampower 的 BUFF_/DEBUFF_ADDED_OTHER 是
  -- 按「光环落在哪个数组」派生的（NampowerAPI.lua 第 2544 行：auraSlot 是 raw 0-based，
  -- debuff 事件的原始槽位注释写死是 32-47），溢出 debuff 落在 buff 区 → 走 BUFF_*_OTHER，
  -- 而本文件压根没注册 BUFF_ADDED_OTHER → slotOwnership 对溢出槽**天然永远没有记录**。
  -- 所以判别走四档递进（细节见 ClassifyAuraSlot）：
  --   1. slotOwnership：DEBUFF_ADDED_OTHER 写入的槽位归属（含 spellId 校验）→ **权威·机制**
  --   2. libdebuff.auraPolarity：单调判定表（曾在 33-48 出现 / 极性已判过）→ **权威·学习**
  --   3. GetSpellPolarity：Nampower 法术记录的极性字段（positive/negative）→ **权威·语义**
  --   4. L["debuffs"] 静态名称库 → **弱证据**，仅在闩锁（该目标曾溢出过）开启时才采信
  -- 玩家单位没有溢出机制（只有 16 个 debuff 槽），直接跳过
  --
  -- 🔴🔴 2026-09-14 二次修复 —— 这才是"目标 debuff 在 buff 区/debuff 区之间跑动"的真根因：
  -- 「16 个 debuff 槽全满」这个条件本身**是对的**（溢出只可能在满的时候发生），错的是
  -- **拿它当"此刻"的判据**。溢出一旦发生，客户端**不会**把那个 debuff 搬回 33-48，而
  -- 33-48 里的 DoT 会陆续到期留下空洞。实战日志（2026-09-14 10:58）就是活证据：
  -- buff 区已有 3 个溢出 debuff（点燃 / 生命虹吸 / 吸取灵魂），而 33-48 只占 14/16。
  -- 于是"满 / 不满"随战斗来回跳 ⇒ 门槛跳 ⇒ 同一批 debuff 一会儿进 debuff 行、一会儿进 buff 行
  -- （录屏逐帧统计：两行图标数此消彼长、总数守恒、一帧内跳 9 个）。
  -- 修法：把瞬时判据降级成**单调闩锁**（libdebuff.overflowLatch[guid]）—— 只要曾经见过全满
  -- 就永久为真、本次会话不再撤销，抖动从机制上不可能再发生。
  -- 已知副作用（可接受）：闩锁一旦打开，名字库对 buff 区就近乎无条件生效，而名字库实为
  -- 「所有带时长的光环」大杂烩（含 荆棘术/嗜血/狂暴/野性印记/卷轴 buff 等 NPC 真 buff，
  -- 见 env/locales_zhCN.lua 第 1447 行起的子表），所以 NPC 身上恰好与名字库重名的 buff
  -- 会被归进 debuff 行 —— 但它是**稳定**的（同名恒同判），不会再造成跑动。
  -- 要更准只能拿 DBC「负面法术」标志位，GetSpellRecField 未暴露该字段（dispel 对破甲/致死
  -- 这类无驱散类型的物理减益无效，不可用）。
  local debuffSlotsFull = true
  for _as = 33, 48 do
    local _asid = auras[_as]
    if not _asid or _asid <= 0 then debuffSlotsFull = false; break end
  end
  -- 单调闩锁：只置位、不清位（清位点只有重载/重进游戏）
  if debuffSlotsFull then
    libdebuff.overflowLatch[guid] = true
  end
  -- 运行期开关（debugStats 已是本函数的 upvalue，挂它不增 upvalue），供二分定位：
  --   overflow always → 强制把 buff 区可疑光环都当溢出 debuff（若强制后图标**不再**跑动，
  --                     即证明抖动来自归类翻转、而非显示层）
  --   overflow never  → 彻底关掉溢出识别（回到"溢出 debuff 显示在 buff 行"的基线）
  local overflowPossible = libdebuff.overflowLatch[guid] == true
  if debugStats and debugStats.overflowMode == "always" then
    overflowPossible = true
  elseif debugStats and debugStats.overflowMode == "never" then
    overflowPossible = false
  end
  -- 挂在地图上供 /libdebugstats target 显示。**无条件挂**：那条诊断命令不带 unitstr，
  -- 走不到下面的 overflowComputed 分支，只有挂在这里它才读得到。
  map.barWasFull = overflowPossible

  -- 记录"这份地图带不带溢出信息"，供缓存判据用（见函数开头的 wantsOverflow）
  local overflowComputed = false
  -- 判据②b 用的标志位数组：**惰性取**，整轮循环只取一次，且只有在 flagDebuffBit 打开时才取
  -- （关闭时零成本 —— 本客户端 GetUnitField 每次调用都要编组整份数组，不能白取）。
  local oflags
  if unitstr and UnitIsPlayer and not UnitIsPlayer(unitstr) then
    overflowComputed = true
    for auraSlot = 1, 32 do
      local spellId = auras[auraSlot]
      if spellId and spellId > 0 then
        local oflag
        if libdebuff.flagDebuffBit then
          -- `or false` 是哨兵：取不到就记成 false，别让 32 个槽各白取一次整份数组
          if oflags == nil then oflags = GetUnitField(guid, "auraFlags") or false end
          -- ⛔ 必须按槽解码（见 GetSlotFlag 的结构说明）：oflags 是 6 个 uint32 的**打包**数组，
          --    oflags[auraSlot] 拿到的是"第 auraSlot 个块"（8 个槽挤在一个数里）——拿它当单槽
          --    标志位用，判据必然乱判，这正是"标志位判据一直没用对"的原因。
          oflag = libdebuff.GetSlotFlag(oflags, auraSlot)
        end
        -- 归类全权交给 ClassifyAuraSlot（唯一归类点，四档递进）：
        --   归属事件 → 单调判定表（学习/极性）→ 极性探针 → 名字库（弱证据，闩锁把门）
        -- 前三档都单调 ⇒ 同一条目的归类不会再随"16 个减益槽满没满"来回翻。
        -- 注：本函数只取第一个返回值；source（判定依据）给 /libdebugstats target 用。
        local isDebuff = libdebuff:ClassifyAuraSlot(guid, auraSlot, spellId, overflowPossible, oflag)

        if isDebuff then
          displaySlot = displaySlot + 1
          local ovName = GetSpellRecField and GetSpellRecField(spellId, "name")
          local ovTexture = libdebuff:GetSpellIcon(spellId)

          -- Get debuff type from SpellRec DBC
          local ovDtype = nil
          if GetSpellRecField then
            local dispelId = GetSpellRecField(spellId, "dispel")
            if dispelId and dispelId > 0 then
              ovDtype = dispelTypeMap[dispelId]
            end
          end

          map[displaySlot] = {
            auraSlot = auraSlot,
            spellId = spellId,
            spellName = ovName or "未知",
            stacks = (auraApps and auraApps[auraSlot] or 0) + 1,
            texture = ovTexture,
            dtype = ovDtype,
            overflow = true
          }

          -- 记录溢出槽位，供显示层（buff 枚举）剔除
          map.overflowAuraSlots = map.overflowAuraSlots or {}
          map.overflowAuraSlots[auraSlot] = true

          if debugStats.enabled then
            debugStats.getunitfield_calls = debugStats.getunitfield_calls + 1
          end
        end
      end
    end
  end
  
  -- Cache the result (separate from buffMap to avoid cross-invalidation)
  if not slotMapCache[guid] then
    slotMapCache[guid] = { timestamp = now }
  end
  slotMapCache[guid].map = map
  slotMapCache[guid].timestamp = now
  -- 标记这份地图是否做过溢出扫描：不带 unitstr 的调用建出来的地图**没有**溢出信息，
  -- 不能被需要溢出的显示层复用（否则就是"图标在两行之间瞬移"的那个 bug）。
  slotMapCache[guid].hasOverflow = overflowComputed

  return map
end

-- 判断目标单位的某个 buff 槽位（1-32）上是否实际是溢出 debuff。
-- 目标（NPC）debuff 超过 16 个时，第 17+ 个 debuff 出现在 buff 槽位，
-- 原生 UnitBuff 会把它们当 buff 返回。显示层（unitframes / buff 模块）
-- 在枚举 buff 时调用本函数剔除，避免溢出 debuff 被显示成 buff。
function libdebuff:IsBuffSlotDebuff(unitstr, buffSlot)
  if not hasNampower or not GetUnitGUID then return false end
  if not unitstr or not buffSlot or buffSlot < 1 or buffSlot > 32 then return false end
  if UnitIsPlayer and UnitIsPlayer(unitstr) then return false end

  local guid = GetUnitGUID(unitstr)
  if not guid then return false end

  local slotMap = GetDebuffSlotMap(guid, unitstr)
  if not slotMap or not slotMap.overflowAuraSlots then return false end

  return slotMap.overflowAuraSlots[buffSlot] == true
end

-- 给显示层的地图条目访问器：返回 slotMap 的**原始条目**（含 .auraSlot / .overflow 标记）。
-- unitframes 在原生 UnitDebuff 断流时用它做"只追加溢出条目"的兜底——不能直接用 UnitDebuff：
-- 它不暴露 auraSlot，显示层无法区分「减益区条目」（原生必已显示，对位复用会出 A B A B
-- 重复图标）和「溢出条目」（原生定位不到，真正需要兜底的）。
function libdebuff:GetDebuffSlotEntry(unitstr, displaySlot)
  if not hasNampower or not GetUnitGUID then return nil end
  if not unitstr or not displaySlot then return nil end
  local guid = GetUnitGUID(unitstr)
  if not guid then return nil end
  local map = GetDebuffSlotMap(guid, unitstr)
  if not map then return nil end
  return map[displaySlot]
end

-- 空快照哨兵：GetAuraSnapshot 在"有权威源、但这会儿整份数组读不到"（guid 失效 / DLL 瞬时
-- 报空）时返回它而不是 nil —— 让 1..32 的循环**不必**逐槽回退重取（一次失效 = 32 次白取）。
-- 语义等价于"该单位当前没有任何可见光环"。
local EMPTY_AURAS = {}

-- ============================================================================
-- API: GetAuraSnapshot —— 一次性取齐整份光环数组，供 1..32 的循环复用
-- ============================================================================
-- 为什么必须单列一个函数：GetUnitField(guid,"aura") 每次调用都把**整份 48 项数组**编组给
-- Lua，取一个槽位也不例外。逐槽调用 = 32 倍放大 —— 实测（2026-09-13）42 秒战斗里
-- 4416 次取数，而同期光环事件只有 ~100 次，全是被 1..32 循环摊出来的。
-- 用法：循环外取一次 → 循环内把 auras / apps **透传**给 GetBuffSlot / GetBuffDisplayIndex。
-- 返回 nil = 没有权威源（无 Nampower）→ 调用方照旧走各自的降级路径，行为不变。
function libdebuff:GetAuraSnapshot(unitstr)
  if not hasNampower or not GetUnitField or not GetUnitGUID then return nil end
  if not unitstr then return nil end

  local guid = GetUnitGUID(unitstr)
  if not guid then return EMPTY_AURAS, EMPTY_AURAS end

  local auras = GetUnitField(guid, "aura")
  if debugStats and debugStats.enabled then
    debugStats.getbuffslot_fetches = (debugStats.getbuffslot_fetches or 0) + 1
  end
  if not auras then return EMPTY_AURAS, EMPTY_AURAS end

  local apps = GetUnitField(guid, "auraApplications")
  if debugStats and debugStats.enabled then
    debugStats.getbuffslot_appfetches = (debugStats.getbuffslot_appfetches or 0) + 1
  end
  return auras, apps or EMPTY_AURAS
end

-- ============================================================================
-- API: GetBuffSlot —— 读取任意单位的 buff 槽位（Nampower 权威源）
-- ============================================================================
-- 为什么必须有这个函数：1.12 香草客户端的原生 UnitBuff **只对 "player" 生效**，
-- 对 "target" / "pet" / "mouseover" 一律返回 nil（本机实测 UB 1..10 全 nil）。
-- 所以姓名板（走 libdebuff）能显示的光环，目标框（走 UnitBuff）一个都读不到。
-- Nampower 的 GetUnitField(guid,"aura") 是唯一能读任意单位的来源：
--   槽 1-32  = buff，槽 33-48 = debuff（该数组有空洞，不是紧凑索引）
-- 返回签名与 UnitDebuff 对齐，便于调用方成对替换：
--   name, rank, texture, stacks, dtype, duration, timeleft, caster, spellId
-- 可选入参 auras / apps = GetAuraSnapshot 的快照；**不给则本函数自己取一次**（向后兼容）。
function libdebuff:GetBuffSlot(unitstr, slot, auras, apps)
  if not hasNampower or not GetUnitField or not GetUnitGUID then return nil end
  if not unitstr or not slot or slot < 1 or slot > 32 then return nil end

  -- `debugStats and` 这个前置是给「单函数抽源码跑仿真」用的沙箱守卫（sim_targetbuff 会把本函数
  -- 抽出去在裸环境里跑，那时文件级 local debugStats 不存在）；真实环境里它恒非 nil。
  if debugStats and debugStats.enabled then
    debugStats.getbuffslot_calls = (debugStats.getbuffslot_calls or 0) + 1
  end

  local guid = GetUnitGUID(unitstr)
  if not guid then return nil end

  -- 快照入参给了就不再取数 —— 这是 P2 的全部意义：32 槽循环只对应 1 份数组。
  if not auras then
    auras = GetUnitField(guid, "aura")
    if not auras then return nil end

    -- 真正"贵"的就是上面这一句：GetUnitField 每次调用都要把**整份 48 项数组**编组给 Lua，
    -- 取单个槽位也不例外。空槽必须在取 auraApplications 之前就 return，否则成本再翻一倍。
    -- 计数放在这里而不是函数入口，就是为了让 /libdebugstats stats 里的数字**等于真实取数次数**。
    if debugStats and debugStats.enabled then
      debugStats.getbuffslot_fetches = (debugStats.getbuffslot_fetches or 0) + 1
    end
  end

  local spellId = auras[slot]
  if not spellId or type(spellId) ~= "number" or spellId <= 0 then return nil end

  -- 隐藏光环过滤：GetUnitField(guid,"aura") 返回的是客户端**真实**光环数组，里面包含
  -- SuperWoW/Nampower 的隐藏光环（IsAuraHidden=1）。这类光环原生 UnitBuff/UnitDebuff
  -- 根本不枚举给 Lua，不过滤就会在目标框 buff 行多出"幽灵图标"，还会把它后面的
  -- 真实 buff 图标挤位（表现为"buff 错位"）。注意 IsAuraHidden 未命中时返回 0，
  -- 0 在 Lua 里是**真值** → 绝不能直接 if IsAuraHidden(...) then。
  if IsAuraHidden then
    local hid = IsAuraHidden(spellId)
    if hid == 1 or hid == true or hid == "1" then return nil end
  end

  local name = GetSpellRecField and GetSpellRecField(spellId, "name")
  if not name then return nil end

  local texture = libdebuff:GetSpellIcon(spellId)
  -- apps 同样可来自快照；只有调用方没给才自己取（有快照时一整轮循环只取一次）
  local stacks
  if apps then
    stacks = (apps[slot] or 0) + 1
  else
    local fetched = GetUnitField(guid, "auraApplications")
    if debugStats and debugStats.enabled then
      debugStats.getbuffslot_appfetches = (debugStats.getbuffslot_appfetches or 0) + 1
    end
    stacks = (fetched and fetched[slot] or 0) + 1
  end

  local dtype = nil
  if GetSpellRecField then
    local dispelId = GetSpellRecField(spellId, "dispel")
    if dispelId and dispelId > 0 then dtype = dispelTypeMap[dispelId] end
  end

  -- 剩余时间：优先 AURA_CAST 施法记录（世界 buff 由 NPC 施放时同样能记录到），
  -- 拿不到就只给静态名库时长、不给 timeleft —— 没有起点就不编倒计时。
  local duration, timeleft, caster, rank
  local _, adur, atl, arank, acguid = libdebuff:GetBestAuraCast(guid, name)
  if atl and atl > 0 then
    duration, timeleft, rank = adur, atl, arank
    caster = (acguid and acguid == GetPlayerGUID()) and "player" or "other"
  else
    duration = libdebuff:GetDuration(name)
  end

  return name, rank, texture, stacks, dtype, duration, timeleft, caster, spellId
end

-- API: HasAuraSource —— 是否具备权威光环数据源（Nampower 的 GetUnitField）
-- 为什么调用方要区分：有权威源时"原始槽位取不到"只能等于"该槽位没有可显示的光环"（空槽/
-- 隐藏光环）→ 提示必须隐藏；**没有**权威源（无 DLL 降级）时数据来自 tooltip 猜测路径，
-- 那条路径的索引本身就是原生紧凑索引 → 提示应照旧走原生，不能被当成"幽灵槽"隐藏掉。
function libdebuff:HasAuraSource()
  if not hasNampower or not GetUnitField or not GetUnitGUID then return false end
  return true
end

-- API: GetBuffDisplayIndex —— 原始 aura 槽位 → 原生"紧凑索引"
-- 为什么需要：完整提示（名称 + 效果描述 + 数值）只有原生 GameTooltip:SetUnitBuff 能给出
-- （本机实测它对 target 出得了完整描述），但它要的是**原生紧凑索引**（隐藏光环根本不枚举给
-- Lua，可见光环被重新编号 1..N），而调用方手里是 **GetUnitField 的原始槽位**（带空洞）。
-- 直接把原始槽位喂进去 = 索引语义错位 → 提示里是**另一个** buff 的描述（错内容比没内容更糟）。
-- 返回 nil = 该原始槽位没有"可见"光环（空槽 / 隐藏光环）→ 调用方不得喂原生 API。
function libdebuff:GetBuffDisplayIndex(unitstr, slot, auras)
  if not hasNampower or not GetUnitField or not GetUnitGUID then return nil end
  if not unitstr or not slot or slot < 1 or slot > 32 then return nil end

  -- auras 是可选快照入参（见 GetAuraSnapshot）。不给就自己取**一次** —— 旧写法先调
  -- GetBuffSlot（内部取一份 aura）再自己取一份，同一个槽位白取两份数组。
  if not auras then
    local guid = GetUnitGUID(unitstr)
    if guid then
      auras = GetUnitField(guid, "aura")
      if debugStats and debugStats.enabled then
        debugStats.getbuffslot_fetches = (debugStats.getbuffslot_fetches or 0) + 1
      end
    end
  end
  if not auras then return nil end

  -- 该原始槽位必须存在"可见"光环（与 GetBuffSlot 同一口径：非空 + 非隐藏）。
  -- 判据不能分叉，否则会出现"行里有图标、悬浮却读不出紧凑索引"。
  local sid0 = auras[slot]
  if not sid0 or type(sid0) ~= "number" or sid0 <= 0 then return nil end
  if IsAuraHidden then
    local h0 = IsAuraHidden(sid0)
    if h0 == 1 or h0 == true or h0 == "1" then return nil end
  end

  -- 逐槽统计"可见"光环；到 slot 为止的可见数即该槽位的原生紧凑索引
  local visible = 0
  for i = 1, slot do
    local sid = auras[i]
    if sid and type(sid) == "number" and sid > 0 then
      local hid = IsAuraHidden and IsAuraHidden(sid)
      if not (hid == 1 or hid == true or hid == "1") then visible = visible + 1 end
    end
  end

  return visible > 0 and visible or nil
end

-- Get caster info for a specific aura slot
-- spellId 可选：提供时校验 ownership 是否为同一法术 —— 槽位被新 debuff 复用后
-- （DEBUFF_REMOVED 丢失时旧 ownership 残留），同名/异名旧归属不再被错误匹配
local function GetSlotCaster(guid, auraSlot, spellName, spellId)
  -- First check our ownership tracking
  if slotOwnership[guid] and slotOwnership[guid][auraSlot] then
    local ownership = slotOwnership[guid][auraSlot]
    -- Verify spell name matches (slot might have been reused)
    if ownership.spellName == spellName and (not spellId or not ownership.spellId or ownership.spellId == spellId) then
      return ownership.casterGuid, ownership.isOurs
    end
  end
  
  -- Fallback: Check ownDebuffs
  local myGuid = GetPlayerGUID()
  if ownDebuffs[guid] and ownDebuffs[guid][spellName] then
    return myGuid, true
  end
  
  -- Fallback: Check allAuraCasts for any caster
  if allAuraCasts[guid] and allAuraCasts[guid][spellName] then
    for casterGuid, data in pairs(allAuraCasts[guid][spellName]) do
      local timeleft = (data.startTime + data.duration) - GetTime()
      if timeleft > 0 then
        return casterGuid, (casterGuid == myGuid)
      end
    end
  end
  
  return nil, false
end

-- ============================================================================
-- CLEANUP FUNCTIONS
-- ============================================================================

local lastRangeCheck = 0

-- Recycled buffers for cleanup (avoids table creation per call)
local _cleanupBuf1 = {}
local _cleanupBuf2 = {}

local function CleanupUnit(guid)
  if not guid then return false end
  
  local cleaned = false
  
  if ownDebuffs[guid] then
    ownDebuffs[guid] = nil
    cleaned = true
  end
  
  if slotOwnership[guid] then
    slotOwnership[guid] = nil
    cleaned = true
  end
  
  if allAuraCasts[guid] then
    allAuraCasts[guid] = nil
    cleaned = true
  end
  
  if objectsByGuid[guid] then
    objectsByGuid[guid] = nil
    cleaned = true
  end
  
  if pendingCasts[guid] then
    pendingCasts[guid] = nil
    cleaned = true
  end
  
  if debugStats.enabled and cleaned and IsCurrentTarget(guid) then
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[清理]|r GUID %s", DebugGuid(guid)))
  end
  
  return cleaned
end

local function CleanupExpiredTimers(guid)
  local now = GetTime()
  
  -- Cleanup ownDebuffs
  if ownDebuffs[guid] then
    local n = 0
    for spellName, data in pairs(ownDebuffs[guid]) do
      local timeleft = (data.startTime + data.duration) - now
      if timeleft < -2 then -- Grace period
        n = n + 1
        _cleanupBuf1[n] = spellName
      end
    end
    for i = 1, n do
      ownDebuffs[guid][_cleanupBuf1[i]] = nil
      _cleanupBuf1[i] = nil
    end
  end
  
  -- Cleanup allAuraCasts
  if allAuraCasts[guid] then
    for spellName, casterTable in pairs(allAuraCasts[guid]) do
      local n2 = 0
      for casterGuid, data in pairs(casterTable) do
        local timeleft = (data.startTime + data.duration) - now
        if timeleft < -2 then
          n2 = n2 + 1
          _cleanupBuf2[n2] = casterGuid
        end
      end
      for i = 1, n2 do
        allAuraCasts[guid][spellName][_cleanupBuf2[i]] = nil
        _cleanupBuf2[i] = nil
      end
      -- Remove empty spell tables
      local hasCasters = false
      for _ in pairs(allAuraCasts[guid][spellName]) do
        hasCasters = true
        break
      end
      if not hasCasters then
        allAuraCasts[guid][spellName] = nil
      end
    end
  end
end

local function CleanupOutOfRangeUnits()
  local now = GetTime()
  if now - lastRangeCheck < 10 then return end
  lastRangeCheck = now
  
  local allGuids = {}
  for guid in pairs(ownDebuffs) do allGuids[guid] = true end
  for guid in pairs(slotOwnership) do allGuids[guid] = true end
  for guid in pairs(allAuraCasts) do allGuids[guid] = true end
  for guid in pairs(objectsByGuid) do allGuids[guid] = true end
  for guid in pairs(pendingCasts) do allGuids[guid] = true end
  
  for guid in pairs(allGuids) do
    local exists = UnitExists and UnitExists(guid)
    local isDead = UnitIsDead and UnitIsDead(guid)
    
    if not exists or isDead then
      CleanupUnit(guid)
    end
  end
  
  -- Cleanup old lastCastRanks
  for spell, data in pairs(lastCastRanks) do
    if now - data.time > 3 then
      lastCastRanks[spell] = nil
    end
  end
  
  -- Cleanup old lastFailedSpells
  for spell, data in pairs(lastFailedSpells) do
    if now - data.time > 2 then
      lastFailedSpells[spell] = nil
    end
  end
  
  -- Cleanup old pendingCasts
  for guid, spells in pairs(pendingCasts) do
    for spell, data in pairs(spells) do
      if now - data.time > 1 then
        pendingCasts[guid][spell] = nil
      end
    end
    local isEmpty = true
    for _ in pairs(pendingCasts[guid]) do
      isEmpty = false
      break
    end
    if isEmpty then
      pendingCasts[guid] = nil
    end
  end
end

-- ============================================================================
-- DURATION FUNCTIONS
-- ============================================================================

function libdebuff:GetDuration(effect, rank)
  if L["debuffs"][effect] then
    local rank = rank and tonumber((string.gsub(rank, RANK, ""))) or 0
    local rank = L["debuffs"][effect][rank] and rank or libdebuff:GetMaxRank(effect)
    local duration = L["debuffs"][effect][rank]

    if effect == L["dyndebuffs"]["Rupture"] then
      local cp = GetComboPoints() or 0
      duration = duration + cp*2
    elseif effect == L["dyndebuffs"]["Kidney Shot"] then
      local cp = GetComboPoints() or 0
      duration = duration + cp*1
    elseif effect == "撕扯" or effect == L["dyndebuffs"]["Rip"] then
      local cp = GetComboPoints() or 0
      duration = 8 + cp*2
    elseif effect == L["dyndebuffs"]["Demoralizing Shout"] then
      local _,_,_,_,count = GetTalentInfo(2,1)
      if count and count > 0 then duration = duration + ( duration / 100 * (count*10)) end
    elseif effect == L["dyndebuffs"]["Shadow Word: Pain"] then
      local _,_,_,_,count = GetTalentInfo(3,4)
      if count and count > 0 then duration = duration + count * 3 end
    elseif effect == L["dyndebuffs"]["Frostbolt"] then
      local _,_,_,_,count = GetTalentInfo(3,7)
      if count and count > 0 then duration = duration + count end
    elseif effect == L["dyndebuffs"]["Gouge"] then
      local _,_,_,_,count = GetTalentInfo(3,3)
      if count and count > 0 then duration = duration + (count*.5) end
    end
    return duration
  else
    return 0
  end
end

function libdebuff:GetMaxRank(effect)
  local max = 0
  for id in pairs(L["debuffs"][effect]) do
    if id > max then max = id end
  end
  return max
end

function libdebuff:UpdateDuration(unit, unitlevel, effect, duration)
  if not unit or not effect or not duration then return end
  unitlevel = unitlevel or 0

  if libdebuff.objects[unit] and libdebuff.objects[unit][unitlevel] and libdebuff.objects[unit][unitlevel][effect] then
    libdebuff.objects[unit][unitlevel][effect].duration = duration
  end
end

function libdebuff:UpdateUnits()
  if not pfUI.uf or not pfUI.uf.target then return end
  pfUI.uf:RefreshUnit(pfUI.uf.target, "aura")
end

-- ============================================================================
-- LEGACY API (for turtle-wow.lua compatibility)
-- ============================================================================

libdebuff.pending = {}
libdebuff.objects = {}

function libdebuff:AddPending(unit, unitlevel, effect, duration, caster, rank)
  if not unit or duration <= 0 then return end
  if not L["debuffs"][effect] then return end
  if libdebuff.pending[3] then return end

  libdebuff.pending[1] = unit
  libdebuff.pending[2] = unitlevel or 0
  libdebuff.pending[3] = effect
  libdebuff.pending[4] = duration
  libdebuff.pending[5] = caster
  libdebuff.pending[6] = rank

  QueueFunction(libdebuff.PersistPending)
end

function libdebuff:RemovePending()
  libdebuff.pending[1] = nil
  libdebuff.pending[2] = nil
  libdebuff.pending[3] = nil
  libdebuff.pending[4] = nil
  libdebuff.pending[5] = nil
  libdebuff.pending[6] = nil
end

function libdebuff:PersistPending(effect)
  if not libdebuff.pending[3] then return end

  if libdebuff.pending[3] == effect or ( effect == nil and libdebuff.pending[3] ) then
    local p1, p2, p3, p4, p5, p6 = libdebuff.pending[1], libdebuff.pending[2], libdebuff.pending[3], libdebuff.pending[4], libdebuff.pending[5], libdebuff.pending[6]
    libdebuff.AddEffect(libdebuff, p1, p2, p3, p4, p5, p6)
  end

  libdebuff:RemovePending()
end

function libdebuff:AddEffect(unit, unitlevel, effect, duration, caster, rank)
  if not rank and caster == "player" and effect then
    if libdebuff.pending[3] == effect and libdebuff.pending[6] then
      rank = libdebuff.pending[6]
    elseif lastCastRanks[effect] and (GetTime() - lastCastRanks[effect].time) < 2 then
      rank = lastCastRanks[effect].rank
    end
  end
  
  if not unit then return end
  unitlevel = unitlevel or 0
  
  -- Create tables if needed
  libdebuff.objects[unit] = libdebuff.objects[unit] or {}
  libdebuff.objects[unit][unitlevel] = libdebuff.objects[unit][unitlevel] or {}
  
  -- Get duration from spell database if not provided
  if not duration or duration == 0 then
    duration = libdebuff:GetDuration(effect, rank)
  end
  
  -- Store/update effect
  local now = GetTime()
  local existing = libdebuff.objects[unit][unitlevel][effect]
  
  if existing then
    existing.start = now
    existing.duration = duration
    existing.caster = caster
    existing.rank = rank
  else
    libdebuff.objects[unit][unitlevel][effect] = {
      start = now,
      duration = duration,
      caster = caster,
      rank = rank
    }
  end
  
  lastspell = libdebuff.objects[unit][unitlevel][effect]
end

-- ============================================================================
-- MAIN API: UnitDebuff (GetUnitField-based)
-- ============================================================================

local cache = {}

function libdebuff:UnitDebuff(unit, displaySlot)
  local unitname = UnitName(unit)
  local unitlevel = UnitLevel(unit)
  local duration, timeleft = nil, -1
  local rank = nil
  local caster = nil
  local effect = nil
  local texture = nil
  local stacks = 0
  local dtype = nil

  -- Nampower: Use GetUnitField for ALL debuff data (no Blizzard UnitDebuff needed)
  if hasNampower and GetUnitGUID then
    local guid = GetUnitGUID(unit)
    if not guid then
      -- Safety fallback: no GUID available (should not happen with Nampower)
      local bTexture, bStacks, bDtype = UnitDebuff(unit, displaySlot)
      if bTexture then
        scanner:SetUnitDebuff(unit, displaySlot)
        effect = scanner:Line(1) or ""
      end
      return effect, rank, bTexture, bStacks, bDtype, duration, timeleft, caster
    end
    
    -- Get current slot map from GetUnitField (cached 50ms)
    local slotMap = GetDebuffSlotMap(guid, unit)
    if not slotMap or not slotMap[displaySlot] then
      return nil
    end
    
    local slotData = slotMap[displaySlot]
    effect = slotData.spellName
    texture = slotData.texture
    stacks = slotData.stacks
    dtype = slotData.dtype
    local auraSlot = slotData.auraSlot
    
    -- Get caster info for this slot
    local slotCasterGuid, isOurs = GetSlotCaster(guid, auraSlot, effect, slotData.spellId)
    
    if isOurs then
      -- OUR debuff - get timer from ownDebuffs
      if ownDebuffs[guid] and ownDebuffs[guid][effect] then
        local data = ownDebuffs[guid][effect]
        local remaining = (data.startTime + data.duration) - GetTime()
        if remaining > 0 then
          duration = data.duration
          timeleft = remaining
          caster = "player"
          rank = data.rank
        elseif remaining > -1 then
          -- Grace period - show 0 timeleft
          duration = data.duration
          timeleft = 0
          caster = "player"
          rank = data.rank
        end
      end
    else
      -- OTHER player's debuff - get timer from allAuraCasts
      if slotCasterGuid and allAuraCasts[guid] and allAuraCasts[guid][effect] then
        local data = allAuraCasts[guid][effect][slotCasterGuid]
        if data then
          local remaining = (data.startTime + data.duration) - GetTime()
          if remaining > 0 and data.duration > 0 then
            duration = data.duration
            timeleft = remaining
            caster = "other"
            rank = data.rank
          end
        end
      end
      
      -- Fallback: Search all casters if specific one not found
      if not duration and allAuraCasts[guid] and allAuraCasts[guid][effect] then
        for anyCasterGuid, data in pairs(allAuraCasts[guid][effect]) do
          local remaining = (data.startTime + data.duration) - GetTime()
          if remaining > 0 and data.duration > 0 then
            duration = data.duration
            timeleft = remaining
            caster = "other"
            rank = data.rank
            break
          end
        end
      end
    end
    
    return effect, rank, texture, stacks, dtype, duration, timeleft, caster
  end


  -- ============================================================================
  -- FALLBACK: Legacy (non-Nampower) system
  -- ============================================================================
  
  local bTexture, bStacks, bDtype = UnitDebuff(unit, displaySlot)
  texture = bTexture
  stacks = bStacks
  dtype = bDtype
  
  if texture then
    scanner:SetUnitDebuff(unit, displaySlot)
    effect = scanner:Line(1) or ""
  end
  
  if effect and libdebuff.objects[unitname] then
    for level, effects in pairs(libdebuff.objects[unitname]) do
      if effects[effect] and effects[effect].duration then
        local timeleft = effects[effect].start and
          effects[effect].start + effects[effect].duration - GetTime()

        if timeleft and timeleft > 0 then
          return effect, effects[effect].rank, texture, stacks, dtype,
            effects[effect].duration, timeleft, effects[effect].caster
        end
      end
    end
  end

  return effect, rank, texture, stacks, dtype, duration, timeleft, caster
end

-- ============================================================================
-- API: UnitOwnDebuff (only OUR debuffs)
-- ============================================================================

-- Pre-defined sort function for UnitOwnDebuff (avoids closure creation per call)
local _ownDebuffSortFunc = function(a, b)
  if a.data.startTime == b.data.startTime then
    return a.spellName < b.spellName
  end
  return a.data.startTime < b.data.startTime
end

function libdebuff:UnitOwnDebuff(unit, id)
  if hasNampower and GetUnitGUID then
    local guid = GetUnitGUID(unit)
    if guid and ownDebuffs[guid] then
      -- Build sorted list of our active debuffs
      local sortedDebuffs = {}
      local now = GetTime()
      
      for spellName, data in pairs(ownDebuffs[guid]) do
        local timeleft = (data.startTime + data.duration) - now
        if timeleft > -1 then  -- Grace period
          local count = table.getn(sortedDebuffs) + 1
          sortedDebuffs[count] = {
            spellName = spellName,
            data = data,
            timeleft = timeleft
          }
        end
      end
      
      -- Sort by startTime (oldest first = lowest display slot)
      -- If startTime is equal (e.g. after Carnage refresh), use spellName for stable sorting
      table.sort(sortedDebuffs, _ownDebuffSortFunc)
      
      -- Return debuff at position 'id'
      if sortedDebuffs[id] then
        local entry = sortedDebuffs[id]
        local texture = entry.data.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
        local displayTimeleft = entry.timeleft > 0 and entry.timeleft or 0
        
        -- Get dtype from SpellRec DBC via stored spellId
        local entryDtype = nil
        if entry.data.spellId and GetSpellRecField then
          local dispelId = GetSpellRecField(entry.data.spellId, "dispel")
          if dispelId and dispelId > 0 then
            entryDtype = dispelTypeMap[dispelId]
          end
        end
        
        local stacks = entry.data.stacks or 1
        return entry.spellName, entry.data.rank, texture, stacks, entryDtype, entry.data.duration, displayTimeleft, "player"
      end
    end
    return nil
  end
  
  -- Fallback: Iterate through all debuffs and filter
  for k in pairs(cache) do cache[k] = nil end
  local count = 1
  for i=1,16 do
    local effect, rank, texture, stacks, dtype, duration, timeleft, caster = libdebuff:UnitDebuff(unit, i)
    if effect and not cache[effect] and caster and caster == "player" then
      cache[effect] = true
      if count == id then
        return effect, rank, texture, stacks, dtype, duration, timeleft, caster
      else
        count = count + 1
      end
    end
  end
end

-- ============================================================================
-- API: GetBestAuraCast (for libpredict HoT tracking)
-- ============================================================================

function libdebuff:GetBestAuraCast(guid, spellName)
  if not guid or not spellName then return nil end
  
  -- Check ownDebuffs first (for our casts)
  if ownDebuffs[guid] and ownDebuffs[guid][spellName] then
    local data = ownDebuffs[guid][spellName]
    local timeleft = (data.startTime + data.duration) - GetTime()
    if timeleft > 0 then
      return data.startTime, data.duration, timeleft, data.rank, GetPlayerGUID()
    end
  end
  
  -- Check allAuraCasts (for any caster)
  if allAuraCasts[guid] and allAuraCasts[guid][spellName] then
    local bestData = nil
    local bestCaster = nil
    local bestTimeleft = 0
    
    for casterGuid, data in pairs(allAuraCasts[guid][spellName]) do
      local timeleft = (data.startTime + data.duration) - GetTime()
      if timeleft > bestTimeleft then
        bestTimeleft = timeleft
        bestData = data
        bestCaster = casterGuid
      end
    end
    
    if bestData and bestTimeleft > 0 then
      return bestData.startTime, bestData.duration, bestTimeleft, bestData.rank, bestCaster
    end
  end
  
  return nil
end

-- ============================================================================
-- API: GetEnhancedDebuffs (for external modules)
-- ============================================================================

function libdebuff:GetEnhancedDebuffs(targetGUID)
  if not targetGUID then return nil end
  local result = {}
  
  if ownDebuffs[targetGUID] then
    local myGuid = GetPlayerGUID()
    for spellName, data in pairs(ownDebuffs[targetGUID]) do
      local timeleft = (data.startTime + data.duration) - GetTime()
      if timeleft > 0 then
        result[spellName] = result[spellName] or {}
        result[spellName][myGuid] = {
          startTime = data.startTime,
          duration = data.duration,
          texture = data.texture,
          rank = data.rank
        }
      end
    end
  end
  
  return result
end

-- ============================================================================
-- NAMPOWER EVENT HANDLING
-- ============================================================================

if hasNampower then
  -- Carnage Talent Rank
  local carnageRank = 0
  local function UpdateCarnageRank()
    if class ~= "DRUID" then return end
    local _, _, _, _, rank = GetTalentInfo(2, 17)
    carnageRank = rank or 0
  end
  
  -- Persistent Carnage check frame (reused instead of CreateFrame per Bite)
  local carnageState = nil  -- {targetGuid, checkTime}
  local carnageCheckFrame = CreateFrame("Frame")
  carnageCheckFrame:Hide()
  carnageCheckFrame:SetScript("OnUpdate", function()
    if not carnageState then
      this:Hide()
      return
    end
    if GetTime() < carnageState.checkTime then return end
    
    -- Check if we gained a combo point (indicates Carnage proc)
    local cp = GetComboPoints() or 0
    
    if cp > 0 then
      -- Carnage triggered! Refresh Rip & Rake
      local guid = carnageState.targetGuid
      local refreshTime = GetTime()
      local myGuid = GetPlayerGUID()
      
      -- Refresh in ownDebuffs
      if ownDebuffs[guid] then
        if ownDebuffs[guid]["Rip"] then
          ownDebuffs[guid]["Rip"].startTime = refreshTime
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[CARNAGE]|r Rip refreshed (CP detected)")
          end
        end
        if ownDebuffs[guid]["Rake"] then
          ownDebuffs[guid]["Rake"].startTime = refreshTime
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[CARNAGE]|r Rake refreshed (CP detected)")
          end
        end
      end
      
      -- Refresh in allAuraCasts
      if allAuraCasts[guid] then
        if allAuraCasts[guid]["Rip"] and allAuraCasts[guid]["Rip"][myGuid] then
          allAuraCasts[guid]["Rip"][myGuid].startTime = refreshTime
        end
        if allAuraCasts[guid]["Rake"] and allAuraCasts[guid]["Rake"][myGuid] then
          allAuraCasts[guid]["Rake"][myGuid].startTime = refreshTime
        end
      end
      
      -- Trigger UI updates
      if pfTarget and GetUnitGUID("target") then
        local currentTargetGuid = GetUnitGUID("target")
        if currentTargetGuid == guid then
          pfTarget.update_aura = true
        end
      end
      
      if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
        pfUI.nameplates:OnAuraUpdate(guid)
      end
    end
    
    carnageState = nil
    this:Hide()
  end)
  
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("PLAYER_TALENT_UPDATE")
  frame:RegisterEvent("PLAYER_LOGOUT")
  frame:RegisterEvent("SPELL_START_SELF")
  frame:RegisterEvent("SPELL_START_OTHER")
  frame:RegisterEvent("SPELL_GO_SELF")
  frame:RegisterEvent("SPELL_GO_OTHER")
  frame:RegisterEvent("SPELL_FAILED_OTHER")
  frame:RegisterEvent("UNIT_DIED")
  frame:RegisterEvent("SPELL_CAST_EVENT")
  frame:RegisterEvent("AURA_CAST_ON_SELF")
  frame:RegisterEvent("AURA_CAST_ON_OTHER")
  frame:RegisterEvent("DEBUFF_ADDED_OTHER")
  frame:RegisterEvent("DEBUFF_REMOVED_OTHER")
  frame:RegisterEvent("PLAYER_TARGET_CHANGED")
  frame:RegisterEvent("UNIT_HEALTH")
  -- Turtle 机制：审判 debuff 随骑士近战命中刷新（Nampower v2.24+，参考 SuperCleveRoidMacros）
  -- ⚠️ Nampower 的 AUTO_ATTACK_SELF/OTHER 事件名与语义实际是反的
  --（武藤纯子酱 2026.8.31 实测：玩家出刀的事件走 AUTO_ATTACK_SELF），
  -- 两个都注册，处理时统一按 attackerGuid==自己 判断，兼容任一语义。
  frame:RegisterEvent("AUTO_ATTACK_OTHER")
  frame:RegisterEvent("AUTO_ATTACK_SELF")

  -- 审判 debuff 名字表（按名匹配以覆盖 Turtle 自定义法术 ID，参考 judgementSpells）
  libdebuff.judgementNames = {
    ["智慧审判"] = true, ["光明审判"] = true, ["十字军审判"] = true, ["公正审判"] = true,
    ["Judgement of Wisdom"] = true, ["Judgement of Light"] = true,
    ["Judgement of the Crusader"] = true, ["Judgement of Justice"] = true,
  }

  -- 玩家机关/近战附带型 aura 归属兜底（DEBUFF_ADDED 时 AURA_CAST/SPELL_GO 均未追踪到
  -- 施法者的，视为玩家自己）。误判代价：他人的同类 debuff 也显示满时长倒计时。
  libdebuff.auraOwnerFallbacks = {
    -- 猎人陷阱（踩中时才挂 debuff，陷阱施放与 debuff 挂上相隔数秒，必然追不到）
    ["爆炸陷阱效果"] = true, ["Explosive Trap Effect"] = true,
    ["献祭陷阱效果"] = true, ["Immolation Trap Effect"] = true,
    ["冰霜陷阱光环"] = true, ["Frost Trap Aura"] = true,
    -- Turtle 猎人机制：猫鼬撕咬附带毒蛇钉刺（近战命中挂上，同审判类附带型）
    ["毒蛇钉刺"] = true, ["Serpent Sting"] = true,
    -- 圣骑士奉献（地面 AoE，敌人进入才挂，AURA_CAST/SPELL_GO 追不到归属；DBC 8s）
    ["奉献"] = true, ["Consecration"] = true,
    -- 法师 proc 叠加型 debuff（深冬之寒/强化灼烧）：法术命中几率附加，非施放动作，
    -- AURA_CAST 不追踪 → DEBUFF_ADDED 归属未知，视为自己（时长见 procDebuffDurations）
    ["深冬之寒"] = true, ["Winter's Chill"] = true,
    ["火焰易伤"] = true, ["Fire Vulnerability"] = true,
  }

  -- 深冬之寒/火焰易伤：叠加型 proc debuff 的权威时长（天赋 tooltip 实测值，
  -- 深冬之寒 15s 可叠 5 层；火焰易伤 30s 可叠 5 层）。proc 附加不走施放，
  -- AURA_CAST 不发事件；DBC 可能残留旧值，显示层时长以此表为准。
  libdebuff.procDebuffDurations = {
    ["深冬之寒"] = 15, ["Winter's Chill"] = 15,
    ["火焰易伤"] = 30, ["Fire Vulnerability"] = 30,
  }
  -- proc 触发法术名（zhCN/enUS）→ 刷新的叠加 debuff 名列表。
  -- 旧 debuff 未到期时叠层/续时只刷新不重挂 → Nampower 不发 DEBUFF_ADDED，
  -- 记录停留旧 startTime（倒计时虚少）→ 用触发法术命中（SPELL_GO）作刷新信号，
  -- 见 SPELL_GO 处理段。注意：深冬之寒为几率 proc（2/5 级 40%、3/5 级 60%），
  -- 未 proc 的命中也会触发刷新 → 显示剩余时间可能虚大 1~2 个施法周期，
  -- 真实到期时 DEBUFF_REMOVED 会纠正。火焰易伤 3/3 为 100% proc，信号精确。
  libdebuff.procRefreshSignals = {
    -- 火焰易伤：灼烧/火焰冲击 100% 附加（tooltip 实测）
    ["灼烧"] = { "火焰易伤" }, ["Scorch"] = { "Fire Vulnerability" },
    ["火焰冲击"] = { "火焰易伤" }, ["Fire Blast"] = { "Fire Vulnerability" },
    -- 深冬之寒：冰霜系伤害法术命中几率附加
    ["寒冰箭"] = { "深冬之寒" }, ["Frostbolt"] = { "Winter's Chill" },
    ["冰霜新星"] = { "深冬之寒" }, ["Frost Nova"] = { "Winter's Chill" },
    ["冰锥术"] = { "深冬之寒" }, ["Cone of Cold"] = { "Winter's Chill" },
    ["暴风雪"] = { "深冬之寒" }, ["Blizzard"] = { "Winter's Chill" },
    ["冰枪术"] = { "深冬之寒" }, ["Ice Lance"] = { "Winter's Chill" },
  }

  -- Turtle 猎人实测（2026-09-10 二次修正）：**仅猫鼬撕咬附带的毒蛇钉刺**实际持续 6s，
  -- 单独施放的毒蛇钉刺 15s 不变；爆炸陷阱效果/献祭陷阱为正常时长（DBC 20s/15s 正确），
  -- 不做覆盖。本表只影响「附带型」识别路径（归属兜底路径 / 1s 内有猫鼬撕咬命中），
  -- 正常施放的毒蛇钉刺走 AURA_CAST durationMs=15000，不受影响。
  libdebuff.trapDurations = {
    ["毒蛇钉刺"] = 6, ["Serpent Sting"] = 6,
  }
  -- 火焰陷阱触发法术名 → 目标身上的效果 debuff 名。
  -- 用途①：识别附带型毒蛇钉刺；用途②：陷阱重挂刷新（陷阱 CD 15s < 效果持续 20s，
  -- 第二个陷阱触发时旧 debuff 未到期，Nampower 不再发 DEBUFF_ADDED → 记录停留旧
  -- startTime 不刷新，需用触发 SPELL_GO 作刷新信号，见 SPELL_GO 处理段）。
  libdebuff.fireTrapEffectMap = {
    ["爆炸陷阱"] = "爆炸陷阱效果", ["Explosive Trap"] = "爆炸陷阱效果",
    ["爆炸陷阱效果"] = "爆炸陷阱效果", ["Explosive Trap Effect"] = "爆炸陷阱效果",
    ["献祭陷阱"] = "献祭陷阱效果", ["Immolation Trap"] = "献祭陷阱效果",
    ["献祭陷阱效果"] = "献祭陷阱效果", ["Immolation Trap Effect"] = "献祭陷阱效果",
  }
  -- 效果名去重列表（供毒蛇钉刺信号刷新用）
  libdebuff.fireTrapEffectNames = { "爆炸陷阱效果", "献祭陷阱效果" }

  -- 重置目标身上仍存活的火焰陷阱效果计时（startTime=now，只动自己的记录）。
  -- 陷阱 CD(15s) < 效果持续(20s)：重挂时旧效果未到期 → Nampower 不再发 DEBUFF_ADDED，
  -- 需要用替代信号刷新（SPELL_GO / 附带毒蛇钉刺挂上，见两处调用点）。
  -- 存活判定 >-1 宽限：旧效果已过期时会自然走 DEBUFF_ADDED 重挂，无需补建。
  function libdebuff.RefreshTrapEffect(guid, effName, now)
    if not guid or not effName or not now then return false end
    local my = GetPlayerGUID()
    local touched = false
    if allAuraCasts[guid] and allAuraCasts[guid][effName] then
      for cguid, d in pairs(allAuraCasts[guid][effName]) do
        if cguid == my and d.duration and d.duration > 0
           and (d.startTime + d.duration) - now > -1 then
          d.startTime = now
          touched = true
        end
      end
    end
    if ownDebuffs[guid] and ownDebuffs[guid][effName] then
      local d = ownDebuffs[guid][effName]
      if d.duration and d.duration > 0 and (d.startTime + d.duration) - now > -1 then
        d.startTime = now
        touched = true
      end
    end
    if objectsByGuid[guid] then
      for sid, rec in pairs(objectsByGuid[guid]) do
        local nm = SpellInfo and SpellInfo(sid)
        if nm == effName and rec.duration and rec.duration > 0
           and (rec.start + rec.duration) - now > -1 then
          rec.start = now
          touched = true
        end
      end
    end
    return touched
  end
  -- ===== 光环计时前移（消耗型机制）=====
  -- 术士「燃烧」命中时会消耗目标身上献祭的 3 秒持续时间（Turtle/TBC 机制，见技能说明
  -- 「消耗3秒的献祭效果」）。服务器确实会把献祭剩余时间减 3s（剩余不足 3s 则整个消耗掉），
  -- 但 1.12 客户端没有「剩余时长」查询接口 → 本地按施放时刻起算的推算剩余会比真实多 3 秒。
  -- 用自己燃烧命中的 SPELL_GO 作信号，把目标上的献祭记录整体**提前** seconds 秒。
  -- 只前移 startTime、不改 duration：所有读取点都是 (startTime + duration) - now，
  -- 一处修改即对姓名板 / 目标框 / 冷却环全部生效（环按新剩余 ÷ duration，与真实一致），
  -- 且不会误伤 UnitOwnDebuff 的字段语义。
  -- 剩余不足 seconds → clamp 到剩余 0（宽限期内显示 0 秒）；光环的去留仍完全由
  -- GetUnitField / DEBUFF_REMOVED 决定，本函数既不凭空造出也不删除 debuff。
  libdebuff.conflagrateConsume = {
    names = { "献祭", "Immolate" },
    seconds = 3,
  }

  function libdebuff.CutAuraTime(guid, effName, seconds, now)
    if not guid or not effName or not seconds or seconds <= 0 then return false end
    if not now then now = GetTime() end
    local cut = false
    local function cutOne(d)
      if not d or not d.duration or d.duration <= 0 then return false end
      local remaining = (d.startTime + d.duration) - now
      if remaining <= -2 then return false end        -- 已过期，交给清理逻辑
      if remaining <= seconds then
        d.startTime = now - d.duration                -- 剩余归零（宽限期内显示 0 秒）
      else
        d.startTime = d.startTime - seconds
      end
      return true
    end
    if ownDebuffs[guid] and ownDebuffs[guid][effName] then
      if cutOne(ownDebuffs[guid][effName]) then cut = true end
    end
    -- 献祭可被任意术士的燃烧消耗（不限施法者）→ 该光环的所有施法者记录一起提前
    if allAuraCasts[guid] and allAuraCasts[guid][effName] then
      for _, d in pairs(allAuraCasts[guid][effName]) do
        if cutOne(d) then cut = true end
      end
    end
    if objectsByGuid[guid] then
      for sid, rec in pairs(objectsByGuid[guid]) do
        local nm = SpellInfo and SpellInfo(sid)
        if nm == effName then
          local wrapped = { startTime = rec.start, duration = rec.duration }
          if cutOne(wrapped) then
            rec.start = wrapped.startTime
            cut = true
          end
        end
      end
    end
    return cut
  end

  -- ===== 圣骑士奉献（地面 AoE）=====
  -- 奉献是地面 AoE：敌人**进入范围那一刻**才被挂上 debuff，且施放时的 AURA_CAST 事件
  -- 追不到归属。若新进入的目标按 DEBUFF_ADDED 时刻起算，会错误地显示满 8s；正确行为
  -- 是继承 AoE 自身剩余时间（如 AoE 已释放 3s → 新目标显示剩余 5s）。
  -- 因此记录 AoE 自身起点 libdebuff.consecrationAoe，新挂 debuff 时以它为基准。
  libdebuff.consecrationAoe = nil  -- { startTime = t, duration = 8 }
  -- 设定/刷新 AoE 起点，并把已存在的奉献记录对齐到该起点（outGuids 收集被改动的 GUID）。
  libdebuff.SetConsecrationAoe = function(startTime, duration, outGuids)
    if not startTime then return 0 end
    -- ⚠️ Lua 里 0 为真值：必须显式判 <= 0，否则 duration=0 会让锚点永远「不活跃」
    if not duration or duration <= 0 then duration = 8 end
    libdebuff.consecrationAoe = { startTime = startTime, duration = duration }
    local my = GetPlayerGUID()
    local touched = 0
    for g, spells in pairs(ownDebuffs) do
      local d = spells["奉献"] or spells["Consecration"]
      if d and d.duration and d.duration > 0 and (d.startTime + d.duration) - startTime > -1 then
        d.startTime = startTime
        if outGuids then outGuids[g] = true end
        touched = touched + 1
      end
    end
    for g, spells in pairs(allAuraCasts) do
      local casters = spells["奉献"] or spells["Consecration"]
      local d = casters and my and casters[my]
      if d and d.duration and d.duration > 0 and (d.startTime + d.duration) - startTime > -1 then
        d.startTime = startTime
        if outGuids then outGuids[g] = true end
        touched = touched + 1
      end
    end
    return touched
  end
  -- 重挂刷新：只把已有记录对齐到当前 AoE 起点，**不移动起点**（避免 AoE 逐 tick 的
  -- SPELL_GO 把起点不断推后导致倒计时不减少）。
  libdebuff.RefreshConsecrationRecords = function(outGuids)
    local aoe = libdebuff.consecrationAoe
    if aoe and aoe.startTime then
      return libdebuff.SetConsecrationAoe(aoe.startTime, aoe.duration, outGuids)
    end
    return 0
  end

  -- （钉刺之毒）猫鼬撕咬附带毒蛇钉刺的**重挂刷新**：
  -- 旧钉刺未到期时服务器只刷新同法术光环（不移除再挂）→ Nampower 既不发 DEBUFF_ADDED，
  -- 也不发 AURA_CAST（近战触发不是「施法」）→ 记录停留旧 startTime，显示剩余 3s 而不是
  -- 新的 6s。改用猫鼬撕咬命中的 SPELL_GO 作刷新信号（每次命中恰好一次）。
  -- 只刷新「已是符文钉刺」的记录（duration ≤ 符文时长+0.5）：未装符文的猎人手动施放
  -- 15s 钉刺不会被误刷成 6s。
  function libdebuff.RefreshSerpentSting(guid, now)
    if not guid or not now then return false end
    local runeDur = (libdebuff.trapDurations and libdebuff.trapDurations["毒蛇钉刺"]) or 6
    local maxDur = runeDur + 0.5
    local my = GetPlayerGUID()
    local touched = false
    local function bump(data)
      if data and data.duration and data.duration > 0 and data.duration <= maxDur
         and (data.startTime + data.duration) - now > -1 then
        data.startTime = now
        touched = true
      end
    end
    if ownDebuffs[guid] and ownDebuffs[guid]["毒蛇钉刺"] then
      bump(ownDebuffs[guid]["毒蛇钉刺"])
    end
    if allAuraCasts[guid] and allAuraCasts[guid]["毒蛇钉刺"] then
      for cg, data in pairs(allAuraCasts[guid]["毒蛇钉刺"]) do
        if not my or cg == my then bump(data) end
      end
    end
    return touched
  end

  -- 猫鼬撕咬命中记录（spellId 可能是 Turtle 自定义 ID，按名匹配）。
  -- 符文「钉刺之毒」：猫鼬撕咬**和触发的火焰陷阱**都会施加最高等级毒蛇钉刺（-40% 时长→6s），
  -- 故火焰陷阱（含其效果法术）触发也要记录，供 AURA_CAST 时识别附带型毒蛇钉刺。
  libdebuff.mongooseBiteNames = {
    ["猫鼬撕咬"] = true, ["Mongoose Bite"] = true,
    ["爆炸陷阱"] = true, ["Explosive Trap"] = true, ["爆炸陷阱效果"] = true, ["Explosive Trap Effect"] = true,
    ["献祭陷阱"] = true, ["Immolation Trap"] = true, ["献祭陷阱效果"] = true, ["Immolation Trap Effect"] = true,
  }
  libdebuff.recentMongooseBite = {}
  
  frame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
      
    elseif event == "PLAYER_ENTERING_WORLD" then
      GetPlayerGUID()
      UpdateCarnageRank()
      
    elseif event == "PLAYER_TALENT_UPDATE" then
      UpdateCarnageRank()
      
    elseif event == "UNIT_HEALTH" then
      local guid = arg1
      if guid and UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
      end
      if pfUI.libdebuff_unit_health_hooks then
        for _, fn in pairs(pfUI.libdebuff_unit_health_hooks) do
          fn(arg1)
        end
      end

    elseif event == "AUTO_ATTACK_OTHER" or event == "AUTO_ATTACK_SELF" then
      -- Turtle 机制补偿：审判 debuff 随骑士近战命中刷新持续时间
      -- （智慧审判/光明审判等在骑士持续输出时不会按 10s 倒计时消失，
      --   参考 SuperCleveRoidMacros OnAutoAttackOther by 武藤纯子酱 2026.9.1）
      -- 参数：arg1=attackerGuid, arg2=targetGuid
      -- 注意：allAuraCasts / ownDebuffs / objectsByGuid 三处必须**独立**刷新——
      -- 审判可能只经 DEBUFF_ADDED 兜底写入 ownDebuffs（allAuraCasts 无记录），
      -- 若整块以 allAuraCasts[targetGuid] 存在为前提，ownDebuffs 永远不会被刷新
      local attackerGuid, targetGuid = arg1, arg2
      local myGuid = GetPlayerGUID()
      if attackerGuid and myGuid and attackerGuid == myGuid and targetGuid and targetGuid ~= "" then
        local now = GetTime()
        local refreshed = false
        if allAuraCasts[targetGuid] then
          for spellName, casters in pairs(allAuraCasts[targetGuid]) do
            if libdebuff.judgementNames[spellName] then
              local d = casters[myGuid]
              if d and d.duration and d.duration > 0 and (d.startTime + d.duration) - now > -1 then
                d.startTime = now
                refreshed = true
              end
            end
          end
        end
        -- 同步 ownDebuffs 与 CleveRoids objectsByGuid，保持各视图一致
        if ownDebuffs[targetGuid] then
          for spellName, data in pairs(ownDebuffs[targetGuid]) do
            if libdebuff.judgementNames[spellName] and data.duration and data.duration > 0
               and (data.startTime + data.duration) - now > -1 then
              data.startTime = now
              refreshed = true
            end
          end
        end
        if objectsByGuid[targetGuid] then
          for spellId, rec in pairs(objectsByGuid[targetGuid]) do
            local nm = SpellInfo and SpellInfo(spellId)
            if nm and libdebuff.judgementNames[nm] and rec.duration and rec.duration > 0
               and (rec.start + rec.duration) - now > -1 then
              rec.start = now
              refreshed = true
            end
          end
        end
        if refreshed then
          -- 刷新 UI（目标框 + 姓名板）
          if pfTarget and GetUnitGUID("target") == targetGuid then
            pfTarget.update_aura = true
          end
          if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
            pfUI.nameplates:OnAuraUpdate(targetGuid)
          end
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ffaa[JUDGE REFRESH]|r 近战命中刷新审判计时 target=%s", GetDebugTimestamp(), DebugGuid(targetGuid)))
          end
        end
      end

    elseif event == "SPELL_START_SELF" or event == "SPELL_START_OTHER" then
      local itemId = arg1
      local spellId = arg2
      local casterGuid = arg3
      local spellType = arg8 or 0  -- 0=Normal, 1=Channel, 2=Autorepeating
      local isChannel = spellType == 1
      local castTime = isChannel and arg7 or arg6  -- arg6=castTime (normal), arg7=duration (channel)
      
      if not casterGuid or not spellId then return end
      
      -- Get spell name via Nampower
      local spellName = nil
      if GetSpellRec then
        local rec = GetSpellRec(spellId)
        spellName = rec and rec.name or nil
      end
      if not spellName and SpellInfo then
        spellName = SpellInfo(spellId)
      end
      
      local icon = libdebuff:GetSpellIcon(spellId)
      
      -- 圣骑士奉献（冗余锚点）：SPELL_START_SELF 在本玩家开始施放时触发，与
      -- SPELL_CAST_EVENT 互为备份（任一先到即记录 AoE 起点），保证后进入范围的目标
      -- 能继承 AoE 剩余时间。
      if event == "SPELL_START_SELF" and casterGuid == GetPlayerGUID()
         and (spellName == "奉献" or spellName == "Consecration") then
        local sDur = libdebuff.GetSpellDurationSec(spellId) or 0
        if sDur <= 0 then sDur = libdebuff:GetDuration(spellName, 0) or 0 end
        if sDur <= 0 then sDur = 8 end
        libdebuff.SetConsecrationAoe(GetTime(), sDur)
      end
      
      -- Use item icon for item-triggered casts
      if itemId and itemId > 0 and GetItemStatsField and GetItemIconTexture then
        local displayInfoId = GetItemStatsField(itemId, "displayInfoID")
        if displayInfoId then
          local itemIcon = GetItemIconTexture(displayInfoId)
          if itemIcon then
            -- GetItemIconTexture returns short name (e.g. "INV_Gizmo_08"), needs full path
            if not string.find(itemIcon, "\\") then
              itemIcon = "Interface\\Icons\\" .. itemIcon
            end
            icon = itemIcon
          end
        end
        -- Store in persistent item icon cache (survives SPELL_GO clearing libdebuff_casts)
        pfUI.libdebuff_item_icons[casterGuid] = {
          icon = icon,
          name = GetItemStatsField and GetItemStatsField(itemId, "displayName") or nil
        }
      else
        pfUI.libdebuff_item_icons[casterGuid] = nil
      end
      
      pfUI.libdebuff_casts[casterGuid] = {
        spellID = spellId,
        itemID = itemId and itemId > 0 and itemId or nil,
        spellName = spellName,
        icon = icon,
        startTime = GetTime(),
        duration = castTime and castTime / 1000 or 0,
        endTime = castTime and (GetTime() + castTime / 1000) or nil,
        event = isChannel and "CHANNEL" or "START"
      }

      if event == "SPELL_START_SELF" and pfUI.libdebuff_spell_start_self_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_start_self_hooks) do
          fn(spellId, casterGuid, arg4, castTime)
        end
      elseif event == "SPELL_START_OTHER" and pfUI.libdebuff_spell_start_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_start_other_hooks) do
          fn(spellId, casterGuid, arg4, castTime)
        end
      end

    elseif event == "SPELL_GO_SELF" or event == "SPELL_GO_OTHER" then
      local itemId = arg1
      local spellId = arg2
      local casterGuid = arg3
      local targetGuid = arg4
      local numHit = arg6 or 0
      local numMissed = arg7 or 0
      
      -- Clear cast bar only if SPELL_GO matches the active cast
      -- (Reactive procs like Frost Armor trigger SPELL_GO but shouldn't clear the castbar)
      -- Don't clear channels on SPELL_GO - channels persist until duration expires or SPELL_FAILED
      if casterGuid and pfUI.libdebuff_casts[casterGuid] then
        if pfUI.libdebuff_casts[casterGuid].spellID == spellId and pfUI.libdebuff_casts[casterGuid].event ~= "CHANNEL" then
          pfUI.libdebuff_casts[casterGuid] = nil
        end
      end
      
      -- Fire registered SPELL_GO_SELF hooks BEFORE miss guard
      -- (Swingtimer needs to see ALL casts, even misses, for swing reset)
      if event == "SPELL_GO_SELF" and pfUI.libdebuff_spell_go_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_go_hooks) do
          fn(spellId, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        end
      end

      -- ⚠️ 圣骑士奉献的 AoE 起点必须在这里记录——**必须在下面 numHit==0 的 return 之前**。
      -- 空地施放时本次 SPELL_GO 的 numHit==0 会直接 return，锚点就永远建不起来；之后走进
      -- 范围的敌人只能按「进入那一刻」起算 → 显示满 8s（已释放 3s 也显示 8s 的根因）。
      -- 事件本身是 SPELL_GO_SELF（只可能是自己的施法），故不要求 casterGuid==自己
      -- （AoE 的 casterGuid 可能被解析成地面效果对象）。锚点仍活跃时不移动起点，
      -- 避免奉献逐 tick 的 SPELL_GO 把起点不断推后导致倒计时不减少。
      if event == "SPELL_GO_SELF" then
        local preName = nil
        if GetSpellRecField then
          preName = GetSpellRecField(spellId, "name")
        end
        if not preName and SpellInfo then
          preName = (SpellInfo(spellId))
        end
        if preName == "奉献" or preName == "Consecration" then
          local a = libdebuff.consecrationAoe
          local liveAoe = a and a.startTime
                          and (a.startTime + (a.duration or 8)) - GetTime() > -0.25
          if not liveAoe then
            local dur = (a and a.duration) or 0
            if dur <= 0 then dur = libdebuff.GetSpellDurationSec(spellId) or 0 end
            if dur <= 0 then dur = 8 end
            libdebuff.SetConsecrationAoe(GetTime(), dur)
            if debugStats.enabled then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffaa[CONS CAST]|r 奉献 AoE 起点（SPELL_GO），dur=%.1fs", dur))
            end
          end
        end
      end

      if numMissed > 0 or numHit == 0 then return end

      local spellName, spellRankString
      if SpellInfo then
        spellName, spellRankString = SpellInfo(spellId)
      elseif GetSpellRecField then
        spellName = GetSpellRecField(spellId, "name")
      end
      if not spellName then return end
      
      local castRank = 0
      if spellRankString and spellRankString ~= "" then
        castRank = tonumber((string.gsub(spellRankString, "Rank ", ""))) or 0
      end
      
      -- Store in pendingCasts for DEBUFF_ADDED correlation
      if targetGuid then
        pendingCasts[targetGuid] = pendingCasts[targetGuid] or {}
        pendingCasts[targetGuid][spellName] = {
          casterGuid = casterGuid,
          rank = castRank,
          time = GetTime()
        }
      end
      
      -- Store rank for our casts
      local myGuid = GetPlayerGUID()
      if casterGuid == myGuid then
        lastCastRanks[spellName] = {
          rank = castRank,
          time = GetTime()
        }
      end

      -- Turtle 符文「钉刺之毒」：记录猫鼬撕咬/火焰陷阱触发时间——二者都会施加
      -- 最高等级毒蛇钉刺且实际持续 6s（AURA_CAST 报告的 DBC 时长 15s 是假的，
      -- 需要在 AURA_CAST 时用本记录识别附带变体）
      if libdebuff.mongooseBiteNames and libdebuff.mongooseBiteNames[spellName] and casterGuid then
        libdebuff.recentMongooseBite[casterGuid] = GetTime()
      end

      -- （钉刺之毒）猫鼬撕咬附带毒蛇钉刺的重挂刷新：旧钉刺未到期 → 服务器只刷新不重挂
      -- （无 DEBUFF_ADDED，近战触发也无 AURA_CAST）→ 必须用本次命中作刷新信号，否则
      -- 显示停留旧剩余时间（3s）而不是新的 6s。目标取本次近战命中的 targetGuid。
      -- （用 event==SPELL_GO_SELF 兜底 casterGuid 解析异常：事件名本身即代表自己的施法）
      if (event == "SPELL_GO_SELF" or casterGuid == myGuid)
         and (spellName == "猫鼬撕咬" or spellName == "Mongoose Bite")
         and targetGuid and targetGuid ~= "" and targetGuid ~= "0x0000000000000000" then
        if libdebuff.RefreshSerpentSting(targetGuid, GetTime()) then
          if pfTarget and GetUnitGUID("target") == targetGuid then
            pfTarget.update_aura = true
          end
          if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
            pfUI.nameplates:OnAuraUpdate(targetGuid)
          end
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffaa[STING REFRESH]|r 猫鼬撕咬刷新毒蛇钉刺 target=%s", DebugGuid(targetGuid)))
          end
        end
      end

      -- Turtle 陷阱重挂刷新：陷阱 CD(15s) < 效果持续(20s)，第二个陷阱触发时旧 debuff
      -- 未到期 → Nampower 不再发 DEBUFF_ADDED（无移除重加）→ 记录停留第一次的 startTime，
      -- 显示旧剩余时间而非新满时长。用自己陷阱触发命中的 SPELL_GO 作可靠刷新信号：
      -- 重置目标上该效果记录（allAuraCasts/ownDebuffs/objectsByGuid 三处独立刷新，同审判块）。
      local trapEffectName = libdebuff.fireTrapEffectMap and libdebuff.fireTrapEffectMap[spellName]
      if trapEffectName and targetGuid and targetGuid ~= "" then
        -- 注意不要求 casterGuid==myGuid：陷阱触发的 SPELL_GO 可能报告陷阱对象 GUID
        -- 而非玩家 GUID（实测 [TRAP REFRESH] 从未触发）；helper 只动自己的记录，安全。
        local trapRefreshed = libdebuff.RefreshTrapEffect(targetGuid, trapEffectName, GetTime())
        if debugStats.enabled then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff88aaff[TRAP GO]|r %s target=%s hit=%d refreshed=%s",
            spellName, DebugGuid(targetGuid), numHit, tostring(trapRefreshed)))
        end
        if trapRefreshed then
          if pfTarget and GetUnitGUID("target") == targetGuid then
            pfTarget.update_aura = true
          end
          if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
            pfUI.nameplates:OnAuraUpdate(targetGuid)
          end
        end
      end

      -- 深冬之寒/火焰易伤：叠加型 proc debuff 重挂刷新。旧 debuff 未到期时叠层/续时
      -- 只刷新不重挂 → Nampower 不发 DEBUFF_ADDED（也无 AURA_CAST，proc 非施放动作）
      -- → 记录停留旧 startTime。用自己触发法术命中的 SPELL_GO 作刷新信号，重置
      -- 目标上仍存活的记录（复用 RefreshTrapEffect：只动自己的记录，三处表独立刷新）。
      local procTargets = libdebuff.procRefreshSignals and libdebuff.procRefreshSignals[spellName]
      if procTargets and targetGuid and targetGuid ~= "" and targetGuid ~= "0x0000000000000000"
         and (event == "SPELL_GO_SELF" or casterGuid == myGuid) then
        local nowProc = GetTime()
        for pi = 1, table.getn(procTargets) do
          local procRefreshed = libdebuff.RefreshTrapEffect(targetGuid, procTargets[pi], nowProc)
          if procRefreshed then
            if pfTarget and GetUnitGUID("target") == targetGuid then
              pfTarget.update_aura = true
            end
            if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
              pfUI.nameplates:OnAuraUpdate(targetGuid)
            end
            if debugStats.enabled then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffaa[PROC REFRESH]|r %s 命中刷新 %s target=%s",
                spellName, procTargets[pi], DebugGuid(targetGuid)))
            end
          end
        end
      end

      -- 术士「燃烧」：命中时消耗目标身上献祭的 3 秒持续时间（Turtle/TBC 机制）。
      -- 服务器会把献祭剩余时间减 3s（不足 3s 则整个消耗掉），客户端读不到剩余时长
      -- → 本地推算剩余会多 3 秒（倒计时偏长）。用自己燃烧命中的 SPELL_GO 作信号，
      -- 把目标上的献祭记录提前 3 秒。判据与刷新类机制一致：必须是自己的施法
      -- （event==SPELL_GO_SELF 兜底 AoE/解析异常）+ 目标 GUID 有效；
      -- 放在 numHit/numMissed 守卫之后 → 被抵抗/未命中的燃烧不会误扣献祭。
      if (spellName == "燃烧" or spellName == "Conflagrate")
         and (event == "SPELL_GO_SELF" or casterGuid == myGuid)
         and targetGuid and targetGuid ~= "" and targetGuid ~= "0x0000000000000000" then
        local cutConf = libdebuff.conflagrateConsume
        local nowCut = GetTime()
        local cutDone = false
        for ci = 1, table.getn(cutConf.names) do
          if libdebuff.CutAuraTime(targetGuid, cutConf.names[ci], cutConf.seconds, nowCut) then
            cutDone = true
            break
          end
        end
        if cutDone then
          if pfTarget and GetUnitGUID("target") == targetGuid then
            pfTarget.update_aura = true
          end
          if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
            pfUI.nameplates:OnAuraUpdate(targetGuid)
          end
          if debugStats.enabled then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[CONFLAGRATE]|r 献祭 -%ds target=%s",
              cutConf.seconds, DebugGuid(targetGuid)))
          end
        end
      end

      -- 圣骑士奉献：AoE 命中信号。两种职责——
      --   ① AoE 起点已存在且仍活跃 → 只把已有记录对齐到该起点（重挂刷新），**不移动起点**；
      --   ② 无起点（SPELL_CAST_EVENT 未触发）或已过期 → 以本次为准设定新起点。
      -- 只动自己的记录；误刷新（已走出范围的少量目标）会被 DEBUFF_REMOVED 纠正。
      -- （castGuid 不再强制 == 自己：AoE 的 casterGuid 可能是地面效果对象；SPELL_GO_SELF
      --   本身就代表自己的施法，上面守卫前那段已建好锚点，这里只做对齐。）
      if (spellName == "奉献" or spellName == "Consecration")
         and (event == "SPELL_GO_SELF" or casterGuid == myGuid) then
        local nowCons = GetTime()
        local cAoe = libdebuff.consecrationAoe
        local consGuids = {}
        local alive = cAoe and cAoe.startTime
                      and (cAoe.startTime + (cAoe.duration or 8)) - nowCons > 0
        if alive then
          libdebuff.RefreshConsecrationRecords(consGuids)
        else
          local dur = (cAoe and cAoe.duration) or 0
          if dur <= 0 then dur = libdebuff.GetSpellDurationSec(spellId) or 0 end
          if dur <= 0 then dur = 8 end
          libdebuff.SetConsecrationAoe(nowCons, dur, consGuids)
        end
        for g in pairs(consGuids) do
          if pfTarget and GetUnitGUID("target") == g then
            pfTarget.update_aura = true
          end
          if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
            pfUI.nameplates:OnAuraUpdate(g)
          end
        end
        if debugStats.enabled then
          local n = 0
          for _ in pairs(consGuids) do n = n + 1 end
          if n > 0 then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffaa[CONS REFRESH]|r 奉献 AoE 刷新，对齐 %d 个目标的计时", n))
          end
        end
      end
      
      -- CARNAGE TALENT: Ferocious Bite refreshes Rip & Rake
      -- Check for combo point gain after Bite (indicates Carnage proc)
      -- Carnage gives +1 CP immediately after Bite if it procs
      if class == "DRUID" and carnageRank >= 1 and spellName == "凶猛撕咬" and casterGuid == myGuid then
        if targetGuid and numHit > 0 then
          -- Schedule delayed check (50ms to allow CP to register)
          carnageState = {
            targetGuid = targetGuid,
            checkTime = GetTime() + 0.05
          }
          carnageCheckFrame:Show()
        end
      end

      -- Fire registered SPELL_GO_SELF hooks (only for own casts)
      if event == "SPELL_GO_SELF" and pfUI.libdebuff_spell_go_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_go_hooks) do
          fn(spellId, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
        end
      end

      -- Fire registered SPELL_GO_OTHER hooks
      if event == "SPELL_GO_OTHER" and pfUI.libdebuff_spell_go_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_go_other_hooks) do
          fn(spellId, casterGuid, targetGuid)
        end
      end

    elseif event == "UNIT_DIED" then
      if pfUI.libdebuff_unit_died_hooks then
        for _, fn in pairs(pfUI.libdebuff_unit_died_hooks) do
          fn(arg1)
        end
      end

    elseif event == "SPELL_FAILED_OTHER" then
      local casterGuid = arg1
      
      if casterGuid and pfUI.libdebuff_casts[casterGuid] then
        pfUI.libdebuff_casts[casterGuid] = nil
      end
      if pfUI.libdebuff_spell_failed_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_failed_other_hooks) do
          fn(casterGuid, arg2)
        end
      end

    elseif event == "SPELL_CAST_EVENT" then
      -- Capture combo points BEFORE they're consumed
      -- This event fires when YOU cast a spell (before server processes it)
      local success = arg1
      local spellId = arg2
      local castType = arg3
      local targetGuid = arg4
      
      if success ~= 1 or not spellId then return end
      
      -- Get spell name
      local spellName = nil
      if GetSpellRec then
        local rec = GetSpellRec(spellId)
        spellName = rec and rec.name or nil
      end
      if not spellName and SpellInfo then
        spellName = SpellInfo(spellId)
      end
      
      -- 圣骑士奉献：地面上 AoE 的**自身起点**在此刻确定（SPELL_CAST_EVENT 每次施放恰好
      -- 触发一次，是唯一可信的"一次施放一个起点"信号）。DEBUFF_ADDED 时才进入范围的敌人
      -- 用此起点起算，就能显示 AoE 的剩余时间而非满时长。
      if spellName == "奉献" or spellName == "Consecration" then
        local cAoe = libdebuff.consecrationAoe
        local cDur = (cAoe and cAoe.duration) or 0
        if cDur <= 0 then cDur = libdebuff.GetSpellDurationSec(spellId) or 0 end
        if cDur <= 0 then cDur = libdebuff:GetDuration(spellName, 0) or 0 end
        if cDur <= 0 then cDur = 8 end
        libdebuff.SetConsecrationAoe(GetTime(), cDur)
        if debugStats.enabled then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffaa[CONS CAST]|r 奉献 AoE 起点记录，dur=%.1fs", cDur))
        end
      end
      
      -- Store pending cast info for libpredict (heal prediction target tracking)
      -- This allows libpredict to resolve the correct target for Nampower queued casts,
      -- where CastSpellByName hook fires while current_cast is set and spell_queue
      -- cannot be updated. SPELL_CAST_EVENT fires right before SPELLCAST_START.
      if spellName and targetGuid and targetGuid ~= "" and targetGuid ~= "0x0000000000000000" then
        pfUI.libpredict_pending_cast.spellId = spellId
        pfUI.libpredict_pending_cast.spellName = spellName
        pfUI.libpredict_pending_cast.targetGuid = targetGuid
        pfUI.libpredict_pending_cast.time = GetTime()
      else
        -- No explicit target - clear pending so libpredict falls back to spell_queue
        pfUI.libpredict_pending_cast.spellId = nil
        pfUI.libpredict_pending_cast.spellName = nil
        pfUI.libpredict_pending_cast.targetGuid = nil
        pfUI.libpredict_pending_cast.time = nil
      end
      
      -- Only capture CPs for combo-point abilities
      if spellName and IsComboPointAbility(spellName) then
        capturedCP = GetComboPoints() or 0
      end

      -- Fire registered SPELL_CAST_EVENT hooks
      if pfUI.libdebuff_spell_cast_hooks then
        for _, fn in pairs(pfUI.libdebuff_spell_cast_hooks) do
          fn(success, spellId, castType, targetGuid)
        end
      end
      
    elseif event == "AURA_CAST_ON_SELF" or event == "AURA_CAST_ON_OTHER" then
      local spellId = arg1
      local casterGuid = arg2
      local targetGuid = arg3
      local effect = arg4
      local effectAuraName = arg5
      local effectAmplitude = arg6
      local effectMiscValue = arg7
      local durationMs = arg8
      local auraCapStatus = arg9
      
      if not spellId then return end
      if not targetGuid or targetGuid == "" or targetGuid == "0x0000000000000000" then return end
      
      local spellName = SpellInfo and SpellInfo(spellId) or (GetSpellRecField and GetSpellRecField(spellId, "name"))
      if not spellName then return end
      
      -- Deduplicate: Ignore if we processed this exact cast recently (within 100ms)
      -- Nampower fires multiple AURA_CAST events for multi-effect spells (e.g. Faerie Fire has 3 effects)
      recentCasts[targetGuid] = recentCasts[targetGuid] or {}
      recentCasts[targetGuid][spellName] = recentCasts[targetGuid][spellName] or {}
      
      local now = GetTime()
      local lastCastTime = recentCasts[targetGuid][spellName][casterGuid]
      
      if lastCastTime and (now - lastCastTime) < AURA_CAST_DEDUPE_WINDOW then
        return  -- Duplicate event, ignore
      end
      
      recentCasts[targetGuid][spellName][casterGuid] = now
      
      -- Rank aus spellId ermitteln
      local rankNum = 0
      local rankString = GetSpellRecField(spellId, "rank")
      if rankString and rankString ~= "" then
        rankNum = tonumber((string.gsub(rankString, "Rank ", ""))) or 0
      end
      
      local duration = durationMs and (durationMs / 1000) or 0
      local startTime = GetTime()
      local myGuid = GetPlayerGUID()
      local isOurs = (myGuid and casterGuid == myGuid)
      
      if debugStats.enabled and isOurs then
        debugStats.aura_cast = debugStats.aura_cast + 1
      end
      
      -- Combo-point abilities: Calculate duration based on CPs used
      if IsComboPointAbility(spellName) then
        if isOurs then
          -- OWN casts: use captured CPs from SPELL_CAST_EVENT (if available)
          local cp = capturedCP or 0
          local base, perCP = GetComboPointData(spellName)
          if base and perCP then
            duration = base + cp * perCP
          else
            -- Fallback to legacy database
            duration = libdebuff:GetDuration(spellName, rankNum)
          end
          capturedCP = nil  -- consumed
        else
          -- OTHER players: CP unknown, no timer (except Expose Armor = fixed 30s)
          local base, perCP = GetComboPointData(spellName)
          if perCP and perCP == 0 and base then
            duration = base  -- fixed duration (Expose Armor)
          else
            duration = 0  -- CP unknown for other players
          end
        end
      elseif duration == 0 then
        -- Non-CP managed spells: AURA_CAST returned 0 →
        -- 首选 Nampower DBC 权威时长（含天赋修正，按 spellId，参考 SuperCleveRoidMacros），
        -- 静态名库仅作兜底（他人 rank 未知/天赋无法修正时不再虚大）
        duration = libdebuff.GetSpellDurationSec(spellId) or libdebuff:GetDuration(spellName, rankNum) or 0
      end

      -- Turtle 符文「钉刺之毒」：猫鼬撕咬/火焰陷阱附带的毒蛇钉刺实际持续 6s（-40%），
      -- AURA_CAST 报告的 DBC 时长 15s 失真；1s 内该施法者刚猫鼬撕咬命中/陷阱触发即判定为附带变体
      if libdebuff.trapDurations and libdebuff.trapDurations[spellName]
         and casterGuid and libdebuff.recentMongooseBite[casterGuid]
         and (now - libdebuff.recentMongooseBite[casterGuid]) < 1 then
        duration = libdebuff.trapDurations[spellName]
      end

      -- 深冬之寒/火焰易伤：叠加型 proc debuff，时长以天赋 tooltip 实测值为准
      -- （DBC 可能残留改动前旧值，见 procDebuffDurations 注释）
      if libdebuff.procDebuffDurations and libdebuff.procDebuffDurations[spellName] then
        duration = libdebuff.procDebuffDurations[spellName]
      end
      
      -- 圣骑士奉献（地面 AoE）：AURA_CAST 报出来的施法者常是「地面效果对象」GUID 而非玩家
      -- （与陷阱同理），isOurs=false → 下面 ownDebuffs 的锚点覆盖走不到，allAuraCasts 会以
      -- 「进入范围那一刻」起算 → 中途进入的目标显示满 8s。故在写入 allAuraCasts 之前先对齐
      -- AoE 自身起点（锚点活跃才覆盖；锚点缺失时由 DEBUFF_ADDED 兜底建立）。
      local consAoeCast = libdebuff.consecrationAoe
      if (spellName == "奉献" or spellName == "Consecration")
         and consAoeCast and consAoeCast.duration and consAoeCast.duration > 0
         and (consAoeCast.startTime + consAoeCast.duration) - GetTime() > 0 then
        startTime = consAoeCast.startTime
        duration = consAoeCast.duration
        if debugStats.enabled then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffaa[CONS ALIGN]|r 奉献 AURA_CAST 对齐 AoE 起点，剩余 %.1fs", (startTime + duration) - GetTime()))
        end
      end

      -- Store in allAuraCasts
      if targetGuid and targetGuid ~= "" and targetGuid ~= "0x0000000000000000" then
        allAuraCasts[targetGuid] = allAuraCasts[targetGuid] or {}
        allAuraCasts[targetGuid][spellName] = allAuraCasts[targetGuid][spellName] or {}
        
        -- Downrank Protection: Check BEFORE clearing old casters!
        -- For selfOverwrite debuffs, check ALL existing casters
        if selfOverwriteDebuffs[spellName] then
          for otherCaster, existingData in pairs(allAuraCasts[targetGuid][spellName]) do
            if existingData.rank and rankNum and rankNum > 0 then
              local existingTimeleft = (existingData.startTime + existingData.duration) - GetTime()
              if existingTimeleft > 0 and rankNum < existingData.rank then
                -- Lower rank cannot overwrite higher rank - block the update
                if debugStats.enabled then
                  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[DOWNRANK BLOCKED]|r %s: Rank %d from %s cannot overwrite Rank %d from %s (%.1fs left)", 
                    spellName, rankNum, DebugGuid(casterGuid), existingData.rank, DebugGuid(otherCaster), existingTimeleft))
                end
                return
              end
            end
          end
        else
          -- For non-selfOverwrite: Check only same caster
          local existingData = allAuraCasts[targetGuid][spellName][casterGuid]
          if existingData and existingData.rank and rankNum and rankNum > 0 then
            local existingTimeleft = (existingData.startTime + existingData.duration) - GetTime()
            if existingTimeleft > 0 and rankNum < existingData.rank then
              if debugStats.enabled and isOurs then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[DOWNRANK BLOCKED]|r %s: Rank %d cannot overwrite Rank %d (%.1fs left)", 
                  spellName, rankNum, existingData.rank, existingTimeleft))
              end
              return
            end
          end
        end
        
        -- Handle self-overwrite debuffs (clear other casters)
        if selfOverwriteDebuffs[spellName] then
          local n = 0
          for otherCaster in pairs(allAuraCasts[targetGuid][spellName]) do
            if otherCaster ~= casterGuid then
              n = n + 1
              _cleanupBuf1[n] = otherCaster
            end
          end
          for i = 1, n do
            allAuraCasts[targetGuid][spellName][_cleanupBuf1[i]] = nil
            _cleanupBuf1[i] = nil
          end
          
          -- Clear from ownDebuffs if we're being overwritten
          if not isOurs and ownDebuffs[targetGuid] and ownDebuffs[targetGuid][spellName] then
            ownDebuffs[targetGuid][spellName] = nil
          end
        end
        
        -- Handle variant pairs (Faerie Fire <-> Faerie Fire (Feral))
        if debuffOverwritePairs[spellName] then
          local otherVariant = debuffOverwritePairs[spellName]
          if allAuraCasts[targetGuid][otherVariant] and allAuraCasts[targetGuid][otherVariant][casterGuid] then
            allAuraCasts[targetGuid][otherVariant][casterGuid] = nil
          end
        end
        
        -- Store timer data
        allAuraCasts[targetGuid][spellName][casterGuid] = {
          startTime = startTime,
          duration = duration,
          rank = rankNum
        }
        
        -- UPDATE slotOwnership for selfOverwrite refreshes
        -- (DEBUFF_ADDED doesn't fire on refresh, so we must update here!)
        if selfOverwriteDebuffs[spellName] and slotOwnership[targetGuid] then
          for auraSlot, ownership in pairs(slotOwnership[targetGuid]) do
            if ownership.spellName == spellName then
              -- Update the casterGuid and isOurs for this slot
              ownership.casterGuid = casterGuid
              ownership.isOurs = isOurs
              
              if debugStats.enabled and IsCurrentTarget(targetGuid) then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[SLOT UPDATED]|r aura=%d %s newCaster=%s isOurs=%s", 
                  auraSlot, spellName, DebugGuid(casterGuid), tostring(isOurs)))
              end
              break
            end
          end
        end
        
        if debugStats.enabled and IsCurrentTarget(targetGuid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ffff[AURA_CAST]|r %s target=%s caster=%s isOurs=%s dur=%.1fs", 
            GetDebugTimestamp(), spellName, DebugGuid(targetGuid), DebugGuid(casterGuid), tostring(isOurs), duration))
        end
      end
      
      -- Notify nameplates
        if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
          pfUI.nameplates:OnAuraUpdate(targetGuid)
        end
        
        -- Notify unitframes of debuff updates (UNIT_AURA doesn't fire on refreshes!)
        -- Check player
        if GetUnitGUID("player") then
          local playerGuid = GetUnitGUID("player")
          if playerGuid == targetGuid and pfPlayer then
            pfPlayer.update_aura = true
          end
        end
        
        -- Check target
        if GetUnitGUID("target") then
          local targetUnitGuid = GetUnitGUID("target")
          if targetUnitGuid == targetGuid and pfTarget then
            pfTarget.update_aura = true
          end
        end
      
      -- Only track in ownDebuffs if it's OUR debuff
      if not isOurs then return end
      if targetGuid == myGuid then return end  -- Skip self-buffs
      if not targetGuid or targetGuid == "" or targetGuid == "0x0000000000000000" then return end
      
      -- Get texture
      local texture = libdebuff:GetSpellIcon(spellId)
      
      -- Store in ownDebuffs
      ownDebuffs[targetGuid] = ownDebuffs[targetGuid] or {}
      
      if not ownDebuffs[targetGuid][spellName] then
        ownDebuffs[targetGuid][spellName] = {}
      end
      
      local data = ownDebuffs[targetGuid][spellName]
      if not data then return end  -- race condition: cleared by DEBUFF_REMOVED between init and use
      
      -- Downrank Protection: Check if existing debuff is still active and has higher rank
      if data.startTime and data.duration and data.rank and rankNum > 0 then
        local existingTimeleft = (data.startTime + data.duration) - GetTime()
        if existingTimeleft > 0 then
          -- Existing debuff is still active
          if rankNum < data.rank then
            -- Lower rank cannot overwrite higher rank - block the update
            if debugStats.enabled then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[DOWNRANK BLOCKED]|r %s: Rank %d cannot overwrite Rank %d (%.1fs left)", 
                spellName, rankNum, data.rank, existingTimeleft))
            end
            return
          end
        end
      end
      
      data.startTime = startTime
      data.duration = duration
      -- 圣骑士奉献：无论走 auraData 还是其它路径，都对齐 AoE 自身起点，
      -- 保证「中途进入范围」的目标显示 AoE 剩余时间而非满时长（并防逐 tick 刷新推后）。
      local consAoe2 = libdebuff.consecrationAoe
      if consAoe2 and (spellName == "奉献" or spellName == "Consecration")
         and consAoe2.duration and consAoe2.duration > 0
         and (consAoe2.startTime + consAoe2.duration) - GetTime() > 0 then
        data.startTime = consAoe2.startTime
        data.duration = consAoe2.duration
      end
      data.texture = texture
      data.rank = rankNum
      data.spellId = spellId
      data.stacks = 1   -- 初始设为 1，稍后由 DEBUFF_ADDED 更新
      
      -- Handle variant pairs for ownDebuffs
      if debuffOverwritePairs[spellName] then
        local otherVariant = debuffOverwritePairs[spellName]
        if ownDebuffs[targetGuid][otherVariant] then
          ownDebuffs[targetGuid][otherVariant] = nil
        end
      end
      
      -- Store for Cleveroids API
      objectsByGuid[targetGuid] = objectsByGuid[targetGuid] or {}
      objectsByGuid[targetGuid][spellId] = {
        start = startTime,
        duration = duration,
        caster = "player",
        stacks = 1
      }
      if event == "AURA_CAST_ON_SELF" and pfUI.libdebuff_aura_cast_on_self_hooks then
        for _, fn in pairs(pfUI.libdebuff_aura_cast_on_self_hooks) do
          fn(spellId, casterGuid, targetGuid)
        end
      elseif event == "AURA_CAST_ON_OTHER" and pfUI.libdebuff_aura_cast_on_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_aura_cast_on_other_hooks) do
          fn(spellId, casterGuid, targetGuid)
        end
      end

    elseif event == "DEBUFF_ADDED_OTHER" then
      local guid = arg1
      local displaySlot = arg2
      local spellId = arg3
      local stacks = arg4
      local auraSlot_0based = arg6

      local auraSlot = auraSlot_0based and (auraSlot_0based + 1) or nil

      slotMapCache[guid] = nil
      
      local spellName = GetSpellRecField and GetSpellRecField(spellId, "name")
      if not spellName then return end
      
      if debugStats.enabled then
        debugStats.debuff_added = debugStats.debuff_added + 1
      end
      
      if UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
        return
      end
      
      -- 获取 auraSlot
      if not auraSlot then
        local slotMap = GetDebuffSlotMap(guid)
        if slotMap and slotMap[displaySlot] then
          auraSlot = slotMap[displaySlot].auraSlot
        end
      end
      if not auraSlot then
        auraSlot = 32 + displaySlot
      end
      
      -- 尝试从 pendingCasts 获取施法者
      local casterGuid = nil
      if pendingCasts[guid] and pendingCasts[guid][spellName] then
        local pending = pendingCasts[guid][spellName]
        if GetTime() - pending.time < 0.5 then
          casterGuid = pending.casterGuid
          pendingCasts[guid][spellName] = nil
        end
      end
      
      -- 从 allAuraCasts 回退获取最近施法者
      -- 必须校验数据仍然有效（时长>0 且未过期）：DEBUFF_ADDED 表示 debuff 刚挂上，
      -- 若拿到早已过期的旧记录（如 AURA_CAST 事件丢失后的残留），timeleft 会虚大
      if not casterGuid and allAuraCasts[guid] and allAuraCasts[guid][spellName] then
        local now = GetTime()
        local mostRecent = nil
        local mostRecentTime = 0
        for casterId, data in pairs(allAuraCasts[guid][spellName]) do
          if data.duration and data.duration > 0 then
            local timeleft = (data.startTime + data.duration) - now
            if timeleft > 0 and data.startTime > mostRecentTime then
              mostRecentTime = data.startTime
              mostRecent = casterId
            end
          end
        end
        if mostRecent then
          casterGuid = mostRecent
        end
      end
      
      local myGuid = GetPlayerGUID()
      local isOurs = (myGuid and casterGuid == myGuid)
      
      -- 从 ownDebuffs 回退（刚施放不久）
      if not isOurs and not casterGuid then
        if ownDebuffs[guid] and ownDebuffs[guid][spellName] then
          local age = GetTime() - ownDebuffs[guid][spellName].startTime
          if age < 0.5 then
            isOurs = true
            casterGuid = myGuid
          end
        end
      end

      -- ========== 玩家机关/近战附带型 aura 特殊处理 ==========
      -- 陷阱 debuff（踩中时才挂上，与陷阱施放相隔数秒）与猫鼬撕咬附带的毒蛇钉刺
      -- （近战命中挂上）都可能不被 AURA_CAST/SPELL_GO 追踪 → 归属未知 → 全链路无计时。
      -- 归属未知时视为玩家自己的，时长由 ownDebuffs 兜底链补（DBC→静态库）。
      -- 名单见 libdebuff.auraOwnerFallbacks（含 DBC 实测时长注释）。
      if not casterGuid and libdebuff.auraOwnerFallbacks and libdebuff.auraOwnerFallbacks[spellName] then
          casterGuid = myGuid
          isOurs = true
          if debugStats.enabled then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99[OWNER FALLBACK]|r 将 %s 视为玩家自己的 debuff", spellName))
          end
      end
      -- 圣骑士奉献（地面 AoE）：施法者被解析成「地面效果对象」GUID 时既不是玩家也不是已知
      -- 单位 → isOurs=false → ownDebuffs 拿不到记录，显示退回 allAuraCasts 的「进入时刻」
      -- 起算（满 8s）。奉献只有骑士会放、AoE 锚点也只由本机施放信号写入，故直接认定为
      -- 自己的（与上面 auraOwnerFallbacks 相同的误判容忍度）。放在 slotOwnership 写入之前，
      -- 让 GetSlotCaster 也返回 isOurs=true，显示才会走 ownDebuffs 的对齐记录。
      if (spellName == "奉献" or spellName == "Consecration") and myGuid then
          casterGuid = myGuid
          isOurs = true
      end
      -- ============================================

      -- ========== 审判 debuff 特殊处理 ==========
      -- 审判随近战命中挂上/刷新，AURA_CAST/SPELL_GO 可能不追踪它（无法确认归属），
      -- 此时全链路无计时（ownDebuffs/allAuraCasts 均无记录）。归属未知时默认视为
      -- 玩家自己的审判并按静态库时长起算——只有骑士能挂审判，误判代价远小于无计时。
      if not casterGuid and myGuid and libdebuff.judgementNames[spellName] then
          casterGuid = myGuid
          isOurs = true
      end
      -- ============================================
      
      -- 存储槽位所有权
      slotOwnership[guid] = slotOwnership[guid] or {}
      slotOwnership[guid][auraSlot] = {
        casterGuid = casterGuid,
        spellName = spellName,
        spellId = spellId,
        isOurs = isOurs
      }
      
      displayToAura[guid] = displayToAura[guid] or {}
      displayToAura[guid][displaySlot] = auraSlot
      
      if debugStats.enabled and IsCurrentTarget(guid) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cff00ff00[DEBUFF_ADDED]|r display=%d aura=%d %s caster=%s isOurs=%s", 
          GetDebugTimestamp(), displaySlot, auraSlot, spellName, DebugGuid(casterGuid), tostring(isOurs)))
      end
      
      -- 更新 ownDebuffs（如果是我们的 debuff）
      if isOurs and casterGuid and myGuid and casterGuid == myGuid then
          -- 尝试从 allAuraCasts 获取计时数据
          local auraData = allAuraCasts[guid] and allAuraCasts[guid][spellName] and allAuraCasts[guid][spellName][casterGuid]
          local startTime, duration, rank
          if auraData then
              startTime = auraData.startTime
              duration = auraData.duration
              rank = auraData.rank or 0
          else
              -- 没有 AURA_CAST 数据（如陷阱 debuff、猫鼬撕咬附带的毒蛇钉刺）：
              -- 优先 Turtle 服务器实测时长覆盖（DBC 的 20s/15s 是服务端改动前的旧值），
              -- 再走 Nampower DBC 权威时长，静态名库兜底
              startTime = GetTime()
              duration = (libdebuff.trapDurations and libdebuff.trapDurations[spellName])
                or (libdebuff.procDebuffDurations and libdebuff.procDebuffDurations[spellName])
                or libdebuff.GetSpellDurationSec(spellId)
                or libdebuff:GetDuration(spellName, 0) or 0
              rank = 0
              if debugStats.enabled then
                  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffaa00[TRAP DURATION]|r %s 使用默认持续时间 %.1fs", spellName, duration))
              end
          end
          -- 圣骑士奉献：地面 AoE 上「中途进入范围」的目标必须继承 AoE 的剩余时间，
          -- 而不是从挂上那一刻起算满时长（否则 AoE 已释放 3s、剩 5s 时会误显示 8s）。
          -- 起点取施放奉献时记录的 AoE 自身起点；AoE 已结束则退回原值。
          -- 放在两个分支之后：无论走 auraData 还是兜底，只要是自己的奉献都对齐 AoE 起点。
          local consAoe = libdebuff.consecrationAoe
          if consAoe and (spellName == "奉献" or spellName == "Consecration")
             and consAoe.duration and consAoe.duration > 0
             and (consAoe.startTime + consAoe.duration) - GetTime() > 0 then
              startTime = consAoe.startTime
              duration = consAoe.duration
          elseif (spellName == "奉献" or spellName == "Consecration") then
              -- 兜底：所有施放信号（SPELL_GO/SPELL_CAST_EVENT/SPELL_START_SELF）都缺失导致
              -- 无锚点时，用本次挂上的时刻作 AoE 起点，供后续进入范围的目标继承。
              -- 时长必须 > 0（否则锚点永远「不活跃」，对齐逻辑全部失效）。
              if not duration or duration <= 0 then duration = 8 end
              libdebuff.consecrationAoe = { startTime = startTime, duration = duration }
          end
          local texture = libdebuff:GetSpellIcon(spellId)
          
          ownDebuffs[guid] = ownDebuffs[guid] or {}
          ownDebuffs[guid][spellName] = {
              startTime = startTime,
              duration = duration,
              texture = texture,
              rank = rank,
              spellId = spellId,
              stacks = stacks,
          }
          
          if debugStats.enabled and IsCurrentTarget(guid) then
              DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff00ff[OWNDEBUFF SYNC]|r %s from DEBUFF_ADDED (dur=%.1f)", spellName, duration))
          end

          -- （钉刺之毒）陷阱附带的毒蛇钉刺每次必达 DEBUFF_ADDED（钉刺 6s < 陷阱 CD 15s，
          -- 第二颗陷阱触发时旧钉刺必已过期），但同次触发的爆炸/献祭陷阱效果因旧效果
          -- 未到期拿不到 DEBUFF_ADDED → 用本钉刺挂上作可靠刷新信号，重置同目标上
          -- 仍存活的陷阱效果计时。门槛：毒蛇钉刺走归属兜底路径才进此块（正常施放
          -- 有 AURA_CAST 数据走 auraData 分支，不会误刷新）。
          if spellName == "毒蛇钉刺" or spellName == "Serpent Sting" then
            local nowS = GetTime()
            local effList = libdebuff.fireTrapEffectNames
            if effList then
              for idx = 1, table.getn(effList) do
                if libdebuff.RefreshTrapEffect(guid, effList[idx], nowS) then
                  if pfTarget and GetUnitGUID("target") == guid then
                    pfTarget.update_aura = true
                  end
                  if debugStats.enabled then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffaa[TRAP SYNC VIA SERPENT]|r %s 重置", effList[idx]))
                  end
                end
              end
            end
          end
      end
      
      -- 清理过期计时器
      CleanupExpiredTimers(guid)
      
      -- 通知姓名板
      if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
        pfUI.nameplates:OnAuraUpdate(guid)
      end
      if pfUI.libdebuff_debuff_added_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_debuff_added_other_hooks) do
          fn(arg1, arg2, arg3, arg4)
        end
      end

    elseif event == "DEBUFF_REMOVED_OTHER" then
      local guid = arg1
      local displaySlot = arg2  -- Display slot (1-16), compacted
      local spellId = arg3
      local auraSlot_0based = arg6  -- Nampower 2.29+: raw slot 0-based (32-47)

      -- Convert 0-based (Nampower event) to 1-based (Lua GetUnitField array)
      local auraSlot = auraSlot_0based and (auraSlot_0based + 1) or nil

      -- Invalidate slot map cache for this GUID
      slotMapCache[guid] = nil
      
      local spellName = (GetSpellRecField and GetSpellRecField(spellId, "name")) or "?"
      
      if debugStats.enabled then
        debugStats.debuff_removed = debugStats.debuff_removed + 1
        if IsCurrentTarget(guid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff9900[DEBUFF_REMOVED]|r display=%d aura=%d (0based=%d) %s", 
            GetDebugTimestamp(), displaySlot, auraSlot or -1, auraSlot_0based or -1, spellName))
        end
      end
      
      -- If unit is dead, cleanup all
      if UnitIsDead and UnitIsDead(guid) then
        CleanupUnit(guid)
        return
      end
      
      -- Get auraSlot from event parameter (Nampower 2.29+)
      -- Fallback to displayToAura mapping if not available
      local foundAuraSlot = auraSlot
      if not foundAuraSlot and displayToAura[guid] and displayToAura[guid][displaySlot] then
        foundAuraSlot = displayToAura[guid][displaySlot]
      end

      local wasOurs = false
      local removedCasterGuid = nil

      if foundAuraSlot then
        -- Get ownership info for this specific slot
        if slotOwnership[guid] and slotOwnership[guid][foundAuraSlot] then
          local ownership = slotOwnership[guid][foundAuraSlot]
          wasOurs = ownership.isOurs
          removedCasterGuid = ownership.casterGuid
        end
        
        -- Clear both mappings (with nil-checks)
        if slotOwnership[guid] then
          slotOwnership[guid][foundAuraSlot] = nil
        end
        if displayToAura[guid] then
          displayToAura[guid][displaySlot] = nil
        end
        
        if debugStats.enabled and IsCurrentTarget(guid) then
          DEFAULT_CHAT_FRAME:AddMessage(string.format("%s |cffff9900[SLOT CLEARED]|r aura=%d [arg6] %s wasOurs=%s caster=%s", 
            GetDebugTimestamp(), foundAuraSlot, spellName, tostring(wasOurs), DebugGuid(removedCasterGuid)))
        end
      end
      
      -- Remove from ownDebuffs if it was ours
      if wasOurs and ownDebuffs[guid] and ownDebuffs[guid][spellName] then
        local age = GetTime() - ownDebuffs[guid][spellName].startTime
        -- Only delete if not recently renewed
        if age > 1 then
          ownDebuffs[guid][spellName] = nil
        end
      end
      
      -- Remove from allAuraCasts
      if removedCasterGuid and allAuraCasts[guid] and allAuraCasts[guid][spellName] then
        if allAuraCasts[guid][spellName][removedCasterGuid] then
          local auraData = allAuraCasts[guid][spellName][removedCasterGuid]
          local age = GetTime() - auraData.startTime
          -- Only delete if not recently refreshed
          if age > 1 then
            allAuraCasts[guid][spellName][removedCasterGuid] = nil
          end
        end
      end
      
      -- Cleanup expired timers
      CleanupExpiredTimers(guid)
      
      -- Notify nameplates
      if pfUI.nameplates and pfUI.nameplates.OnAuraUpdate then
        pfUI.nameplates:OnAuraUpdate(guid)
      end
      if pfUI.libdebuff_debuff_removed_other_hooks then
        for _, fn in pairs(pfUI.libdebuff_debuff_removed_other_hooks) do
          fn(arg1, arg2, arg3, arg4)
        end
      end

    elseif event == "PLAYER_TARGET_CHANGED" then
      if not GetUnitGUID then return end
      local targetGuid = GetUnitGUID("target")
      
      if targetGuid and targetGuid ~= "" then
        -- Invalidate slot map cache on retarget
        -- Prevents stale slot mappings after untarget/retarget cycles
        slotMapCache[targetGuid] = nil
        -- Cleanup expired timers for new target
        CleanupExpiredTimers(targetGuid)
      end
      if pfUI.libdebuff_player_target_changed_hooks then
        for _, fn in pairs(pfUI.libdebuff_player_target_changed_hooks) do
          fn()
        end
      end
    end
    
    -- Periodic cleanup
    CleanupOutOfRangeUnits()
  end)
  
  -- Cleveroids API
  if CleveRoids then
    CleveRoids.libdebuff = libdebuff
    libdebuff.objects = objectsByGuid
  end
end

-- ============================================================================
-- 回退模式：当 Nampower 未加载时，使用经典事件扫描（与 libdebuff1 兼容）
-- ============================================================================

if not hasNampower then
  -- 回退事件处理所需列表
  libdebuff.rp = { SPELLIMMUNESELFOTHER, IMMUNEDAMAGECLASSSELFOTHER,
    SPELLMISSSELFOTHER, SPELLRESISTSELFOTHER, SPELLEVADEDSELFOTHER,
    SPELLDODGEDSELFOTHER, SPELLDEFLECTEDSELFOTHER, SPELLREFLECTSELFOTHER,
    SPELLPARRIEDSELFOTHER, SPELLLOGABSORBSELFOTHER, SPELLFAILCASTSELF }

  local fallbackFrame = CreateFrame("Frame", "pfdebuffsFallback", UIParent)
  fallbackFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE")
  fallbackFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
  fallbackFrame:RegisterEvent("CHAT_MSG_SPELL_FAILED_LOCALPLAYER")
  fallbackFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
  fallbackFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
  fallbackFrame:RegisterEvent("SPELLCAST_STOP")
  fallbackFrame:RegisterEvent("UNIT_AURA")

  if class == "PALADIN" then
    fallbackFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
  end

  fallbackFrame:SetScript("OnEvent", function()
    -- paladin seal refresh
    if event == "CHAT_MSG_COMBAT_SELF_HITS" then
      local hit = cmatch(arg1, COMBATHITSELFOTHER)
      local crit = cmatch(arg1, COMBATHITCRITSELFOTHER)
      if hit or crit then
        for seal in L["judgements"] do
          local name = UnitName("target")
          local level = UnitLevel("target")
          if name and libdebuff.objects[name] then
            if level and libdebuff.objects[name][level] and libdebuff.objects[name][level][seal] then
              libdebuff:AddEffect(name, level, seal)
            elseif libdebuff.objects[name][0] and libdebuff.objects[name][0][seal] then
              libdebuff:AddEffect(name, 0, seal)
            end
          end
        end
      end

    -- Add Combat Log
    elseif event == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" or event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then
      local unit, effect = cmatch(arg1, AURAADDEDOTHERHARMFUL)
      if unit and effect then
        local unitlevel = UnitName("target") == unit and UnitLevel("target") or 0
        if not libdebuff.objects[unit] or not libdebuff.objects[unit][unitlevel] or not libdebuff.objects[unit][unitlevel][effect] then
          libdebuff:AddEffect(unit, unitlevel, effect)
        end
      end

    -- Add Missing Buffs by Iteration
    elseif ( event == "UNIT_AURA" and arg1 == "target" ) or event == "PLAYER_TARGET_CHANGED" then
      for i=1, 16 do
        local effect, rank, texture, stacks, dtype, duration, timeleft = libdebuff:UnitDebuff("target", i)
        if not texture then return end
        if texture and effect and effect ~= "" then
          local unitlevel = UnitLevel("target") or 0
          local unit = UnitName("target")
          if not libdebuff.objects[unit] or not libdebuff.objects[unit][unitlevel] or not libdebuff.objects[unit][unitlevel][effect] then
            libdebuff:AddEffect(unit, unitlevel, effect, duration)
          end
        end
      end

    -- Update Pending Spells
    elseif event == "CHAT_MSG_SPELL_FAILED_LOCALPLAYER" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
      for _, msg in pairs(libdebuff.rp) do
        local effect = cmatch(arg1, msg)
        if effect and libdebuff.pending[3] == effect then
          libdebuff:RemovePending()
          return
        elseif effect and lastspell and lastspell.start_old and lastspell.effect == effect then
          libdebuff:RevertLastAction()
          return
        end
      end
    elseif event == "SPELLCAST_STOP" then
      libdebuff:PersistPending()
    end
  end)

  -- 回退模式下也启用钩子（确保手动施法能被捕获）
  -- 注意：这些钩子已在全局定义过，但为了保险，再定义一次（不会重复）
  -- 实际上上面的钩子已经存在，但为了清晰，此处不再重复。
end

-- ============================================================================
-- 钩子（无论是否使用 Nampower，都确保手动施法能被捕获）
-- 注：这些钩子在文件前面已经定义过，但为了避免被覆盖，我们保留原样。
-- 实际上，它们已经在文件前面被定义（在 Nampower 事件块之前），所以无需重复。
-- ============================================================================

-- 钩子已经在前面的“公共钩子”部分定义，无需再次定义。

-- ============================================================================
-- 将 libdebuff 添加到 pfUI API
-- ============================================================================

pfUI.api.libdebuff = libdebuff

-- Expose debugStats for external access
libdebuff.debugStats = debugStats

-- ============================================================================
-- DEBUG COMMANDS
-- ============================================================================

_G.SLASH_LIBDEBUGSTATS1 = "/libdebugstats"
_G.SlashCmdList["LIBDEBUGSTATS"] = function(msg)
  msg = string.lower(msg or "")
  
  if msg == "start" then
    debugStats.enabled = true
    debugStats.trackAllUnits = false
    debugStats.aura_cast = 0
    debugStats.debuff_added = 0
    debugStats.debuff_removed = 0
    debugStats.getunitfield_calls = 0
    debugStats.getbuffslot_calls = 0
    debugStats.getbuffslot_fetches = 0
    debugStats.getbuffslot_appfetches = 0
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[libdebuff]|r Debug tracking STARTED")
    
  elseif msg == "stop" then
    debugStats.enabled = false
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r Debug tracking STOPPED")

  -- 溢出归类开关（给"目标 debuff 在两行之间跑动"做运行期二分定位，见 GetDebuffSlotMap 注释）
  elseif msg == "overflow" or msg == "overflow auto" then
    debugStats.overflowMode = nil
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[libdebuff]|r 溢出归类：auto（单调闩锁，正常模式）")

  elseif msg == "overflow always" then
    debugStats.overflowMode = "always"
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r 溢出归类：always —— buff 区可疑光环**全**当溢出 debuff。若图标不再跑动，即证明抖动来自归类翻转。")

  elseif msg == "overflow never" then
    debugStats.overflowMode = "never"
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r 溢出归类：never —— 彻底关闭溢出识别（溢出 debuff 会显示在 buff 行）。")

  elseif msg == "stats" then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff=== LIBDEBUFF STATS (GetUnitField Edition) ===|r")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("AURA_CAST events: %d", debugStats.aura_cast))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("DEBUFF_ADDED events: %d", debugStats.debuff_added))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("DEBUFF_REMOVED events: %d", debugStats.debuff_removed))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("GetUnitField calls: %d", debugStats.getunitfield_calls))
    -- buff 侧：calls 是"被调用次数"（含空槽），fetches 才是"真正取数组的次数"（= 跨 C 边界成本）。
    -- 没有快照时 calls ≈ fetches（每槽各取一份）；传了快照后 fetches 应塌到"每轮循环一次" ——
    -- 两者拉开的倍数就是"逐槽取数"的放大倍数，也是快照优化最直接的读数。
    DEFAULT_CHAT_FRAME:AddMessage(string.format("GetBuffSlot calls: %d", debugStats.getbuffslot_calls or 0))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("GetBuffSlot aura fetches: %d", debugStats.getbuffslot_fetches or 0))
    DEFAULT_CHAT_FRAME:AddMessage(string.format("GetBuffSlot apps fetches: %d", debugStats.getbuffslot_appfetches or 0))
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00No manual slot shifting needed!|r")
    
  elseif msg == "target" then
    if not GetUnitGUID("target") then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[libdebuff]|r No target!")
      return
    end
    
    local guid = GetUnitGUID("target")
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff=== TARGET DEBUFF STATE ===|r")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("GUID: %s", tostring(guid)))
    
    -- Show GetUnitField slot map
    -- ⛔ 必须带 unitstr（本命令永远看目标）：不带时 wantsOverflow=false，缓存里任何一份"无溢出"
    --    地图都会命中 —— 打印出来的 Display 列表会**缺掉溢出的那些槽**，让人误判成"显示层没算出来"。
    --    （2026-09-14 实战日志就踩了这个：同一时刻"剔除=true"却列不出对应的溢出槽。）
    local slotMap = GetDebuffSlotMap(guid, "target")
    if slotMap then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00GetUnitField Slots:|r")
      -- ⚠ 必须按数字序 + 类型过滤：地图上除数字显示槽外还挂着 overflowAuraSlots（表）与
      -- barWasFull（布尔）两个元数据键，用 pairs 遍历会把它们也当"槽"读，
      -- 旧写法 `data.auraSlot` 对布尔值/表都会拿到 nil → 打印出 "Display /nil/ nil" 之类的垃圾行。
      for displaySlot = 1, 64 do
        local data = slotMap[displaySlot]
        if type(data) == "table" then
          local casterGuid, isOurs = GetSlotCaster(guid, data.auraSlot, data.spellName, data.spellId)
          DEFAULT_CHAT_FRAME:AddMessage(string.format("  Display %d (aura %d): %s [caster=%s, ours=%s]", 
            displaySlot, data.auraSlot, data.spellName, DebugGuid(casterGuid), tostring(isOurs)))
        end
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900No debuffs via GetUnitField|r")
    end
    
    -- Show ownDebuffs
    if ownDebuffs[guid] then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ownDebuffs:|r")
      for spell, data in pairs(ownDebuffs[guid]) do
        local timeleft = (data.startTime + data.duration) - GetTime()
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s: dur=%.1f left=%.1f", spell, data.duration, timeleft))
      end
    end

    -- 溢出识别状态（2026-09-14）：溢出 debuff 究竟被归进哪一行，这里一眼可见。
    -- 用途：修"目标 debuff 在 buff 区 / debuff 区之间跑动"后，用来确认归类是否稳定。
    --   ① debuff 槽(33-48) 占用数 —— 旧版就是拿"=16 全满"当硬门槛才导致图标瞬移
    --   ② buff 区(1-32) 逐槽：归属事件是否匹配（权威）/ 名字库是否命中 / 最终归类
    --   ③ 原生 UnitBuff/UnitDebuff 的非 nil 个数 —— 用于判断"客户端自己是否也把它当 buff"
    local tauras = GetUnitField and GetUnitField(guid, "aura")
    if tauras then
      local occ33 = 0
      for i = 33, 48 do
        local sid = tauras[i]
        if sid and sid > 0 then occ33 = occ33 + 1 end
      end
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00溢出识别:|r debuff 槽(33-48) 占用 %d/16", occ33))
      -- 闩锁状态：auto 模式下它一旦为 true 就永不再变 —— 这是"不再跑动"的直接证据。
      -- 显示当前标志位判据（同样带 type 守卫：非数字一律按"关"显示，绝不让格式化抛错）
      local fbit = pfUI.api.libdebuff.flagDebuffBit
      local fbitTxt = "关"
      if type(fbit) == "number" and fbit > 0 then fbitTxt = string.format("0x%X", fbit) end
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00溢出闩锁:|r 可能溢出=%s  模式=%s  标志位=%s",
        tostring(slotMap and slotMap.barWasFull == true), tostring(debugStats.overflowMode or "auto"), fbitTxt))
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00buff 区(1-32):|r")
      local any = false
      local latch = slotMap and slotMap.barWasFull == true
      -- 走 pfUI.api.libdebuff 而不是文件级 local libdebuff —— 诊断命令不该给这个闭包 +1 upvalue
      local lib = pfUI.api.libdebuff
      -- auraFlags：Nampower 的每槽 4bit 标志数组。★结构已从实战日志实测解出★：
      --   6 个 uint32，每块装 8 槽、每槽 4bit（每字节 2 槽、低半在前）
      --   ⇒ **必须按槽解码**（libdebuff.GetSlotFlag）。早先这里打的是 `aflags[i]`，拿到的是
      --   "第 i 个块"（8 个槽挤在一个数里）—— 所以 0x88088888 看着像垃圾，判据也就全错。
      local aflags = GetUnitField and GetUnitField(guid, "auraFlags")
      local nblk = 0
      if type(aflags) == "table" then for _ in pairs(aflags) do nblk = nblk + 1 end end
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00auraFlags:|r 类型=%s 块数=%d（应为 6 = 48槽/8）  判据位=%s",
        tostring(aflags and type(aflags)), nblk, fbitTxt))
      -- 逐槽的"解码位"与"归类"，普查（下面）要用
      local flBySlot, slotInfo = {}, {}
      for i = 1, 32 do
        local sid = tauras[i]
        if sid and sid > 0 then
          any = true
          local nm = (GetSpellRecField and GetSpellRecField(sid, "name")) or "?"
          -- 直接问**唯一**的归类点要结论 + 依据（绝不在这里重写一遍判据，否则两处迟早分叉）
          local isDbf, src = lib:ClassifyAuraSlot(guid, i, sid, latch)
          local tag
          if isDbf then
            tag = "|cffff9900DEBUFF(" .. src .. ")|r"
          else
            tag = "|cff999999buff(" .. src .. ")|r"
          end
          -- 🔴🔴 关键交叉验证：「归类」与「实际显示层会不会剔除」是两条路。
          --   归类=DEBUFF 而 剔除=否 ⇒ 管道问题（缓存/索引/调用点）
          --   归类=buff     而 剔除=否 ⇒ 判据问题（极性/名字库都没覆盖这个法术）
          -- 两种问题的修法完全不同，所以必须分开打印，不能只看归类。
          local exclude = false
          if lib.IsBuffSlotDebuff then
            exclude = lib:IsBuffSlotDebuff("target", i) == true
          end
          -- 隐藏光环（Nampower IsAuraHidden）：隐藏光环原生不枚举，会污染位普查 —— 单独标出。
          local hid = "-"
          if IsAuraHidden then
            local h = IsAuraHidden(sid)
            if h == 1 or h == true or h == "1" then hid = "|cffff0000是|r" else hid = "否" end
          end
          -- 该槽解码后的 4bit 位值（见 GetSlotFlag；旧的 aflags[i] 是打包块，不要再用）
          local fl = lib.GetSlotFlag and lib.GetSlotFlag(aflags, i)
          flBySlot[i] = fl
          slotInfo[i] = isDbf and 1 or 0
          -- 位判据是否**改变了结论**：把 auraFlag 拿掉再问一次。只在位真的决定了结论时才多问一次
          -- （诊断不在热路径）。这是"位义对不对"最直接的证据：若它把已知真 buff 也翻成 DEBUFF，
          -- 就证明这位不是极性位 —— 立刻 /libdebugstats flagbit 0。
          local flipTxt = ""
          if src == "标志位" then
            local alt, altSrc = lib:ClassifyAuraSlot(guid, i, sid, latch)
            flipTxt = "  |cffff0000仅靠位|r(关掉位则=" .. (alt and "DEBUFF/" or "buff/") .. altSrc .. ")"
          end
          DEFAULT_CHAT_FRAME:AddMessage(string.format("  aura %d: id=%d %s [%s] 位=%s 剔除=%s 隐藏=%s%s",
            i, sid, nm, tag, (fl and string.format("0x%X", fl) or "-"), tostring(exclude), hid, flipTxt))
        end
      end
      if not any then
        DEFAULT_CHAT_FRAME:AddMessage("  (空)")
      end
      -- ★标志位普查★ —— "位义"的判定依据，一次运行就能定案：
      --   若 0x8 真是减益位，应当看到「减益区33-48 全是 0x8」+「buff区·判减益 也是 0x8」
      --   且「buff区·判增益 **不含** 0x8」。
      --   若两边都出现 0x8（尤其是"判增益"里也有），说明它只是占用/其它标记、不是极性位
      --   ⇒ 立刻关掉位判据：/libdebugstats flagbit 0
      local hist, order = {}, {}
      local bump = function(key)
        if hist[key] == nil then hist[key] = 0; table.insert(order, key) end
        hist[key] = hist[key] + 1
      end
      if type(aflags) == "table" then
        for i = 33, 48 do
          if tauras[i] and tauras[i] > 0 then
            local f = lib.GetSlotFlag and lib.GetSlotFlag(aflags, i)
            bump("减益区33-48=" .. (f and string.format("0x%X", f) or "-"))
          end
        end
      end
      for i = 1, 32 do
        if slotInfo[i] ~= nil then
          bump("buff区." .. (slotInfo[i] == 1 and "判减益" or "判增益") .. "="
            .. (flBySlot[i] and string.format("0x%X", flBySlot[i]) or "-"))
        end
      end
      table.sort(order)
      local parts = {}
      for _, k in ipairs(order) do table.insert(parts, k .. "×" .. hist[k]) end
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00标志位普查:|r " .. table.concat(parts, "   "))
      -- 单调判定表的规模：某个法术一旦进了这张表，归类就永久固定 —— 这就是"不再跑动"的读数。
      local vcount = 0
      for _ in pairs(lib.auraPolarity) do vcount = vcount + 1 end
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00判定表:|r 已定论 %d 个法术（单调，只写一次永不反转）", vcount))
      -- 原生枚举实测：UnitDebuff 的 17-48 索引到底能不能读到东西？
      -- CleveRoid 注释称 17+ 是"溢出索引"（buff 区里的真 buff 会被过滤成 nil），本机待证；
      -- 若 nd2 > 0，说明客户端自己就给了溢出通道，可再省掉一层推断。
      local nb, nd1, nd2, ndmax = 0, 0, 0, 0
      for i = 1, 32 do if UnitBuff("target", i) then nb = nb + 1 end end
      for i = 1, 16 do if UnitDebuff("target", i) then nd1 = nd1 + 1; ndmax = i end end
      for i = 17, 48 do if UnitDebuff("target", i) then nd2 = nd2 + 1; ndmax = i end end
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00原生枚举:|r UnitBuff(1-32)=%d  UnitDebuff(1-16)=%d  UnitDebuff(17-48)=%d（最大非空 %d）", nb, nd1, nd2, ndmax))
    end

  -- /libdebugstats spell <spellId>：把 Nampower 的法术记录整条摊开打印。
  -- 为什么需要它：判据③（极性）依赖法术记录里的**某个字段**，但这个字段名无法离线确认
  -- （nampower.dll 里确实有裸串 positive/negative，紧邻 GetSpellRecField 的字段区，可用法串
  -- 没暴露它挂在哪个键上）。与其猜一个名字写死、失效了还查不出来，不如把整条记录摊开 ——
  -- 命中率 100%，而且将来 Nampower 改了名字也能一眼看出来。
  -- 用法：/libdebugstats spell 12654   （12654 = 点燃，典型的溢出减益）
  elseif string.find(msg, "^spell ") == 1 then
    local sid = tonumber(string.sub(msg, 7))
    if not sid then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r 用法：/libdebugstats spell <spellId>（数字，如 12654）")
    elseif not GetSpellRec then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r 本客户端没有 GetSpellRec（需要 Nampower 2.8+）")
    else
      local ok, rec = pcall(GetSpellRec, sid, 1)
      if not ok or type(rec) ~= "table" then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[libdebuff]|r 法术 %d 取不到记录", sid))
      else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff=== SPELL REC %d (%s) ===|r", sid,
          tostring(GetSpellRecField and GetSpellRecField(sid, "name"))))
        -- 必须收集 key 后排序：直接 pairs 的顺序每次都不一样，两次调用对不上就没法比对
        local keys = {}
        for k in pairs(rec) do
          if type(k) == "string" then table.insert(keys, k) end
        end
        table.sort(keys)
        local buf, n = "", 0
        for _, k in ipairs(keys) do
          local v = rec[k]
          local vs = type(v) == "table" and "<table>" or tostring(v)
          buf = buf .. k .. "=" .. vs .. "   "
          n = n + 1
          -- 每 3 个一行：法术记录 ~100 个键，一行一个会把聊天框刷爆
          -- ⛔ 用 math.mod 而不是二元 % —— Lua 5.0 不支持取模运算符
          if math.mod(n, 3) == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("  " .. buf); buf = ""
          end
        end
        if buf ~= "" then DEFAULT_CHAT_FRAME:AddMessage("  " .. buf) end
      end
    end

  -- /libdebugstats probe <debuffId> <buffId>：两条法术记录逐字段对比，**自动挑出区分字段**。
  -- 为什么比 spell 好用：单条记录 ~100 个字段，两条各刷 35 行，靠肉眼找差异极易漏。
  -- 这里直接把"减益有、增益没有（或值不同）"的字段全部打出来，一次命令就定位到
  -- 真正的判据字段（attributes / attributesEx 之类的位域），不用猜字段名、不用来回试。
  -- 用法：/libdebugstats probe 12654 1459   （12654=点燃 减益，1459=奥术智慧 增益）
  elseif string.find(msg, "^probe") == 1 then
    local _, _, pa, pb = string.find(msg, "^probe%s+(%d+)%s+(%d+)")
    if not pa or not pb then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r 用法：/libdebugstats probe <debuffId> <buffId>（两个数字）")
    elseif not GetSpellRec then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r 本客户端没有 GetSpellRec（需要 Nampower 2.8+）")
    else
      -- 取一条记录（copy=1）；纯全局调用，不给本闭包添 upvalue
      local function recOf(id)
        local ok, r = pcall(GetSpellRec, id, 1)
        if ok and type(r) == "table" then return r end
        return nil
      end
      -- 值转文本：表只报元素个数（记录里很多是数组，逐元素打印会刷爆聊天框；
      -- 而且 table.concat 遇到 nil/布尔会直接抛错）
      local function tv(v)
        if type(v) == "table" then
          local c = 0
          for _ in pairs(v) do c = c + 1 end
          return "<table " .. c .. ">"
        end
        return tostring(v)
      end
      -- "D 有而 B 没有"的位（只对位域字段有意义）。Lua 5.0 没有位运算，用除 2 取余手算。
      local function bitonly(x, y)
        if type(x) ~= "number" or type(y) ~= "number" then return "" end
        local s, v = "", 1
        for _ = 1, 32 do
          local xb = math.mod(math.floor(x / v), 2)
          local yb = math.mod(math.floor(y / v), 2)
          if xb == 1 and yb == 0 then s = s .. string.format("%X ", v) end
          v = v * 2
        end
        if s == "" then return "" end
        return "(D独有位 " .. s .. ")"
      end
      local rd, rb = recOf(tonumber(pa)), recOf(tonumber(pb))
      if not rd or not rb then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[libdebuff]|r 至少一条记录取不到（%s / %s）",
          tostring(rd ~= nil), tostring(rb ~= nil)))
      else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff=== PROBE %s(减益) vs %s(增益) ===|r",
          tostring(GetSpellRecField and GetSpellRecField(tonumber(pa), "name")),
          tostring(GetSpellRecField and GetSpellRecField(tonumber(pb), "name"))))
        local seen = {}
        for k in pairs(rd) do if type(k) == "string" then seen[k] = true end end
        for k in pairs(rb) do if type(k) == "string" then seen[k] = true end end
        local list = {}
        for k in pairs(seen) do table.insert(list, k) end
        table.sort(list)
        local buf, ndiff, nnum = "", 0, 0
        for _, k in ipairs(list) do
          local vd, vb = rd[k], rb[k]
          local diff = false
          if type(vd) ~= type(vb) then
            diff = true
          elseif type(vd) == "table" then
            local cd, cb = 0, 0
            if type(vd) == "table" then for _ in pairs(vd) do cd = cd + 1 end end
            if type(vb) == "table" then for _ in pairs(vb) do cb = cb + 1 end end
            diff = (cd ~= cb)
          else
            diff = (vd ~= vb)
          end
          if diff then
            ndiff = ndiff + 1
            if type(vd) == "number" and type(vb) == "number" then nnum = nnum + 1 end
            -- 位域字段额外给出"减益独占位"，这是最有价值的一行 —— 找到就用它做判据
            local extra = ""
            if string.find(k, "attributes") == 1 then extra = bitonly(vd, vb) end
            buf = buf .. k .. ": D=" .. tv(vd) .. " B=" .. tv(vb) .. extra .. "   "
            -- 每 2 个一行
            if math.mod(ndiff, 2) == 0 then DEFAULT_CHAT_FRAME:AddMessage("  " .. buf); buf = "" end
          end
        end
        if buf ~= "" then DEFAULT_CHAT_FRAME:AddMessage("  " .. buf) end
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00差异字段 %d 个（其中数值 %d 个）|r —— 重点看 attributes* 的 D独有位",
          ndiff, nnum))
      end
    end

  -- /libdebugstats fields <spellId>：把一批"候选极性字段名"逐个丢给 GetSpellRecField 试探测。
  -- 背景：nampower.dll 的字符串表里确实有裸串 positive / negative（第 2946-2947 项），但它挂在
  -- 哪个键上**离线无法确认**，而这正是判据③（极性）的正解所在。本命令用控制组（一个必定不
  -- 存在的字段名）判断"非法字段名"是报错还是返回 nil，再逐个试候选名 —— 一次运行就能把
  -- "哪个字段名是真的"钉死，不用猜、不用改代码反复进游戏。
  -- 用法：/libdebugstats fields 12654
  elseif string.find(msg, "^fields") == 1 then
    local fid = tonumber(string.sub(msg, 8))
    if not fid then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r 用法：/libdebugstats fields <spellId>")
    elseif not GetSpellRecField then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r 本客户端没有 GetSpellRecField（需要 Nampower 2.8+）")
    else
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff=== FIELD PROBE %d (%s) ===|r", fid,
        tostring(GetSpellRecField(fid, "name"))))
      -- 控制组：这个名字必定不存在。ok=false ⇒ "非法字段名 = 报错"，于是 ok=true 就等于"字段存在"。
      -- ok=true 且 v=nil ⇒ "非法字段名 = 静默返回 nil"，此时只能靠"有没有值"来判断（价值低一档）。
      local okbad, vbad = pcall(GetSpellRecField, fid, "__no_such_field_zzz__")
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00控制组|r __no_such_field_zzz__ -> ok=%s v=%s",
        tostring(okbad), tostring(vbad)))
      local cands = {
        "positive", "negative", "polarity", "isPositive", "isNegative",
        "harmful", "helpful", "isDebuff", "isBuff", "debuff", "buff",
        "auraType", "spellType", "buffType", "targetType", "attributes",
      }
      local n = 0
      for _, k in ipairs(cands) do
        local ok, v = pcall(GetSpellRecField, fid, k)
        n = n + 1
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s -> ok=%s v=%s", k, tostring(ok), tostring(v)))
      end
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00试测 %d 个候选字段名完成|r", n))
    end

  -- /libdebugstats flagbit <hex|0>：设置/清除"标志位判据"（判据②b）。
  -- 现状（2026-09-14 四修后）：**默认就是 0x8** —— 已从实战日志实测出来：减益区 33-48 的 16 个槽
  -- 全部是 0x8，buff 区里已确认为减益的溢出槽也全部是 0x8，而唯一一个确定友好的（命令战旗）是 0x5。
  -- 所以这个命令现在主要用来**关掉**它（验证位义）或换成别的位：
  --   /libdebugstats flagbit 0     关掉位判据（回到 归属→判定表→极性→名字库）
  --   /libdebugstats flagbit 0x8   重新开启（等价于默认）
  -- 判据是否可信看 `/libdebugstats target` 尾部的「标志位普查」行：判增益的槽里一旦出现 0x8，
  -- 说明这位不是极性位 ⇒ 立刻 flagbit 0。填错只会"归类不对"，不会污染单调判定表。
  elseif string.find(msg, "^flagbit") == 1 then
    local arg = string.sub(msg, 9)
    arg = string.gsub(arg, "^%s+", "")
    arg = string.gsub(arg, "%s+$", "")
    if arg == "" then
      local cur = pfUI.api.libdebuff.flagDebuffBit
      DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[libdebuff]|r 标志位判据 = %s（默认 0x8；用法：/libdebugstats flagbit 0x8 | flagbit 0）",
        (type(cur) == "number" and cur > 0) and string.format("0x%X", cur) or "关"))
    else
      local v = tonumber(arg)
      if not v and string.find(arg, "^0[xX]") then v = tonumber(string.sub(arg, 3), 16) end
      if not v then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[libdebuff]|r 无法解析：" .. arg .. "（示例 0x8 / 8 / 0）")
      elseif v == 0 then
        pfUI.api.libdebuff.flagDebuffBit = nil
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[libdebuff]|r 标志位判据已关闭（回到 归属→判定表→极性→名字库）")
      else
        pfUI.api.libdebuff.flagDebuffBit = v
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[libdebuff]|r 标志位判据已开启：解码后的 4bit 位值 & 0x%X != 0 ⇒ 判为溢出减益", v))
      end
    end

  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[libdebuff] GetUnitField Edition - Commands:|r")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats start - Start debug tracking")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats stop  - Stop debug tracking")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats stats - Show statistics")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats target - Show target debuff state")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats overflow auto|always|never - 溢出归类开关（默认 auto）")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats spell <spellId> - 摊开打印法术记录（查极性字段名）")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats probe <debuffId> <buffId> - 两条记录自动对比，挑出区分字段")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats fields <spellId> - 试探测极性字段名（positive/negative 等）")
    DEFAULT_CHAT_FRAME:AddMessage("  /libdebugstats flagbit 0x8|0 - 设/清 auraFlags「减益位」判据（默认 0x8，实测值）")
    DEFAULT_CHAT_FRAME:AddMessage("  /pfdbcal - Calibrate target debuff durations (event vs DBC vs static)")
  end
end

-- /pfdbcal：目标 debuff 时长校准——打印事件层/DBC/静态库三个来源的时长与当前剩余
-- 用于实测定位「时间不准」发生在哪个环节（Nampower 事件值、DBC 值、静态库值）
_G.SLASH_PFDBCAL1 = "/pfdbcal"
_G.SlashCmdList["PFDBCAL"] = function()
  if not GetUnitGUID or not GetUnitGUID("target") then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[pfdbcal]|r 无目标")
    return
  end
  local guid = GetUnitGUID("target")
  local now = GetTime()
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff=== pfdbcal 目标 debuff 时长校准 ===|r")

  -- 1) 事件层数据（AURA_CAST 记录）
  local casts = allAuraCasts[guid]
  if not casts then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900事件层：|r 无 AURA_CAST 记录（debuff 可能非你/队友施放）")
  end

  -- 2) 逐显示槽（含溢出）列出实际挂在目标上的 debuff
  local slotMap = GetDebuffSlotMap(guid, "target")
  if not slotMap then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900槽位层：|r 目标无 debuff")
  end

  -- 静态库时长查询（用 libdebuff:GetDuration 语义：rank 缺失用 [0]）
  local function StaticDur(name, rank)
    local db = L["debuffs"]
    if not db or not db[name] then return nil end
    return db[name][rank] or db[name][0]
  end

  local seen = {}
  if slotMap then
    for displaySlot, data in pairs(slotMap) do
      local name = data.spellName
      if not seen[name] then
        seen[name] = true
        local dbc = libdebuff.GetSpellDurationSec(data.spellId)
        local stat = StaticDur(name, 0)
        local ev = ""
        if casts and casts[name] then
          for caster, d in pairs(casts[name]) do
            local left = d.duration and ((d.startTime + d.duration) - now) or -1
            ev = string.format("%s[caster=%s dur=%.1fs left=%.1fs]", ev, DebugGuid(caster), d.duration or 0, left)
          end
        end
        if ev == "" then ev = "[无事件记录]" end
        DEFAULT_CHAT_FRAME:AddMessage(string.format(
          "|cff00ff00%s|r id=%d  DBC=%s  静态库=%s  %s",
          name, data.spellId or 0,
          dbc and string.format("%.1fs", dbc) or "-",
          stat and string.format("%.1fs", stat) or "-",
          ev))
      end
    end
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff用法：实测 debuff 实际消失时刻 vs 各来源时长，偏差即根因|r")
end

_G.SLASH_MEMCHECK1 = "/memcheck"
_G.SlashCmdList["MEMCHECK"] = function()
  local function countTable(t)
    local count = 0
    if not t then return 0 end
    for _ in pairs(t) do count = count + 1 end
    return count
  end
  
  local function countNestedEntries(t)
    local total = 0
    if not t then return 0 end
    for _, nested in pairs(t) do
      if type(nested) == "table" then
        total = total + countTable(nested)
      end
    end
    return total
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff========== LIBDEBUFF MEMORY (GetUnitField Edition) ==========|r")
  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00Primary Tables:|r"))
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  ownDebuffs: %d GUIDs, %d debuffs", countTable(ownDebuffs), countNestedEntries(ownDebuffs)))
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  slotOwnership: %d GUIDs, %d slots", countTable(slotOwnership), countNestedEntries(slotOwnership)))
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  allAuraCasts: %d GUIDs", countTable(allAuraCasts)))
  DEFAULT_CHAT_FRAME:AddMessage(string.format("  pendingCasts: %d GUIDs", countTable(pendingCasts)))
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00No ownSlots/allSlots (eliminated by GetUnitField approach!)|r")
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff============================================================|r")
end

DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libdebuff]|r GetUnitField Edition loaded! (Nampower: " .. (hasNampower and "启用" or "回退模式") .. ")")