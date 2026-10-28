pfUI:RegisterModule("nameplates", "vanilla", function ()
  -- disable original castbars
  pcall(SetCVar, "ShowVKeyCastbar", 0)

  -- Local function references for performance
  local pfGetCastInfo = pfGetCastInfo    -- provided by libcast for vanilla
  local pfGetChannelInfo = pfGetChannelInfo  -- provided by libcast for vanilla
  local GetTime = GetTime
  local UnitExists = UnitExists
  local UnitName = UnitName
  local UnitClass = UnitClass
  local UnitLevel = UnitLevel
  local UnitIsPlayer = UnitIsPlayer
  local UnitIsDead = UnitIsDead
  local UnitAffectingCombat = UnitAffectingCombat
  local UnitIsUnit = UnitIsUnit
  local UnitCanAssist = UnitCanAssist
  local UnitHealth = UnitHealth
  local UnitHealthMax = UnitHealthMax
  local UnitMana = UnitMana
  local UnitManaMax = UnitManaMax
  local pairs = pairs
  local tonumber = tonumber
  local strlower = strlower
  local strfind = strfind
  -- 控制技能清单（参考 EN_UnitFrames / En_LoseControl.lua 的 local spellIds 写法）
  -- 在此表添加/删除中文技能名即可生效（判定为精确匹配）
  local spellIds = {
    ["猫头鹰凝视"] = true,
    ["法力涌动"] = true,
    ["奥术超载"] = true,
    ["麦迪文的腐化"] = true,
    ["黑暗屈从"] = true,
    ["烈焰笼罩"] = true,
    ["魅惑之心"] = true,
    ["军团镣铐"] = true,
    ["休眠"] = true,
    ["星火昏迷"] = true,
    ["纠缠根须"] = true,
    ["重击"] = true,
    ["血袭"] = true,
    ["野性冲锋效果"] = true,
    ["胁迫"] = true,
    ["恐吓野兽"] = true,
    ["驱散射击"] = true,
    ["强化震荡射击"] = true,
    ["震荡射击"] = true,
    ["冰冻陷阱效果"] = true,
    ["冰冻陷阱"] = true,
    ["冰霜陷阱光环"] = true,
    ["冰霜陷阱"] = true,
    ["诱捕"] = true,
    ["翼龙钉刺"] = true,
    ["反击"] = true,
    ["强化摔绊"] = true,
    ["摔绊"] = true,
    ["野猪冲撞"] = true,
    ["变形术"] = true,
    ["变形术：龟"] = true,
    ["变形术：猪"] = true,
    ["变形术：奶牛"] = true,
    ["变形术：鸡"] = true,
    ["法术反制 - 沉默"] = true,
    ["冲击"] = true,
    ["冲击波"] = true,
    ["霜寒刺骨"] = true,
    ["冰霜新星"] = true,
    ["寒冰箭"] = true,
    ["冰锥术"] = true,
    ["冰冻"] = true,
    ["制裁之锤"] = true,
    ["忏悔"] = true,
    ["精神控制"] = true,
    ["心灵尖啸"] = true,
    ["昏阙"] = true,
    ["沉默"] = true,
    ["精神鞭笞"] = true,
    ["致盲"] = true,
    ["偷袭"] = true,
    ["凿击"] = true,
    ["肾击"] = true,
    ["闷棍"] = true,
    ["脚踢 - 沉默"] = true,
    ["致残毒药"] = true,
    ["死亡缠绕"] = true,
    ["恐惧术"] = true,
    ["恐惧嚎叫"] = true,
    ["疲劳诅咒"] = true,
    ["火焰冲撞"] = true,
    ["清算"] = true,
    ["诱惑"] = true,
    ["法术封锁"] = true,
    ["地狱火效果"] = true,
    ["地狱火"] = true,
    ["残废术"] = true,
    ["冲锋击昏"] = true,
    ["断筋"] = true,
    ["拦截昏迷"] = true,
    ["破胆怒吼"] = true,
    ["复仇昏迷"] = true,
    ["震荡猛击"] = true,
    ["刺耳怒吼"] = true,
    ["盾击 - 沉默"] = true,
    ["冰封武器"] = true,
    ["冰霜震击"] = true,
    ["地缚术"] = true,
    ["地缚图腾"] = true,
    ["战争践踏"] = true,
    ["潮汐咒符"] = true,
    ["锤击昏迷效果"] = true,
    ["昏迷"] = true,
    ["侏儒洗脑帽"] = true,
    ["无畏冲锋"] = true,
    ["催眠术"] = true,
    ["冰冻术"] = true,
    ["寒冷"] = true,
    ["冲锋"] = true,
    ["冰爆术"] = true,
    ["蹬踏"] = true,
    ["鞭笞"] = true,
    ["水晶凝视"] = true,
    ["蛛网"] = true,
    ["恐吓"] = true,
    ["恐吓尖啸"] = true,
    ["投网"] = true,
    ["钩网"] = true,
    ["裂筋"] = true,
    ["扫荡"] = true,
    ["包围之风"] = true,
    ["音素爆破"] = true,
    ["减速毒药"] = true,
    ["覆体之网"] = true,
    ["包围之网"] = true,
    ["蛛网爆炸"] = true,
    ["盾牌猛击"] = true,
    ["烟雾弹"] = true,
    ["毁灭"] = true,
    ["飞扑"] = true,
    ["击倒"] = true,
    ["斯卡尔德"] = true,
    ["震耳尖啸"] = true,
    ["阵风"] = true,
    ["猛踢"] = true,
    ["冰霜速冻"] = true,
  }

  -- 全局判定函数：查表判断是否为控制技能
  -- OnDataChanged 调用它不新增 upvalue（全局访问），spellIds 只被本函数捕获
  function pfUI_IsCCSpell(name)
    return spellIds[name] == true
  end

  -- 全局函数：隐藏姓名板全部元素（黑名单单位复用，三处调用点统一走这里）
  -- 同 pfUI_IsCCSpell 模式：定义为全局函数，OnDataChanged 通过环境访问调用它，
  -- 零新增 upvalue（OnDataChanged 闭包已贴着 5.0 的 upvalue 上限 32，任何对
  -- 文件级 local / nameplates 的引用都会令整文件编译失败）。本函数内部只依赖
  -- 参数 + 环境全局（C / tonumber），不捕获文件级 local，故自身 upvalue 也几乎为零。
  function pfUI_HidePlateElements(nameplate)
    nameplate.level:Hide()
    nameplate.name:Hide()
    nameplate.health:Hide()
    nameplate.guild:Hide()
    nameplate.targetname:Hide()
    nameplate.totem:Hide()
    nameplate.glow:Hide()
    if nameplate.hatred then nameplate.hatred:Hide() end
    for i = 1, 16 do
      if nameplate.debuffs[i] then nameplate.debuffs[i]:Hide() end
    end
    for i = 1, (tonumber(C.nameplates.ccmax) or 4) do
      if nameplate.ccdebuffs and nameplate.ccdebuffs[i] then nameplate.ccdebuffs[i]:Hide() end
    end
    if nameplate.cccontainer then nameplate.cccontainer:Hide() end
    for i = 1, 5 do
      nameplate.combopoints[i]:Hide()
    end
    nameplate.castbar:Hide()
    if nameplate.cluster then nameplate.cluster:Hide() end
  end

  local strlen = strlen
  local floor = floor
  local ceil = ceil
  local abs = abs
  local mathmod = math.mod

  -- 单位类型颜色：GUI「单位颜色」可自定义，配置值为 "r,g,b,a" 字符串
  -- 作用于两处：① 框体轮廓边框色（outenemy/outneutral/outfriendlynpc/outfriendly）
  --             ② 血条颜色（未启用职业色/战斗状态覆盖时）
  local unitcolors = {
    ["ENEMY_NPC"] = { .9, .2, .3, .8 },
    ["NEUTRAL_NPC"] = { 1, 1, .3, .8 },
    ["FRIENDLY_NPC"] = { .6, 1, 0, .8 },
    ["ENEMY_PLAYER"] = { .9, .2, .3, .8 },
    ["FRIENDLY_PLAYER"] = { .2, .6, 1, .8 },

    -- 自定义 NPC 颜色（GUI「自定义NPC颜色」）。刻意挂在本表字段而**不新增顶层 local**：
    -- 本文件的 OnDataChanged 闭包已贴着 5.0 的 upvalue 上限 32，多引一个 local 就
    -- "too many upvalues (limit=32)"，整文件不加载（姓名板全失效、且客户端只在
    -- Logs/FrameXML.log 记一行，游戏内无任何提示）。
    --   _custom    : nameLower -> {r,g,b,a}
    --   _customdef : 名单里「纯名字」条目使用的统一颜色
    _custom = {},
    _customdef = { 1, .2, .2, 1 }
  }

  -- 从配置刷新 unitcolors；配置缺失或不合法时保留默认值
  local function RefreshUnitColors()
    local map = {
      ["ENEMY_NPC"]       = "unitcolor_enemynpc",
      ["NEUTRAL_NPC"]     = "unitcolor_neutralnpc",
      ["FRIENDLY_NPC"]    = "unitcolor_friendlynpc",
      ["ENEMY_PLAYER"]    = "unitcolor_enemyplayer",
      ["FRIENDLY_PLAYER"] = "unitcolor_friendlyplayer"
    }
    for unittype, key in pairs(map) do
      local r, g, b, a = GetStringColor(C.nameplates[key] or "")
      r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
      if r and g and b and a then
        local c = unitcolors[unittype]
        c[1], c[2], c[3], c[4] = r, g, b, a
      end
    end

    -- ========== 自定义 NPC 颜色：按 NPC 名字覆盖颜色 ==========
    -- unitcolor_custom 为 "#" 分隔的条目列表，条目两种写法：
    --   名字             → 使用统一颜色 unitcolor_customcolor
    --   名字=r,g,b,a     → 使用该 NPC 专属颜色
    -- 名字匹配忽略大小写，与本文件黑名单使用同一名字来源
    unitcolors._custom = {}

    local dr, dg, db, da = GetStringColor(C.nameplates.unitcolor_customcolor or "")
    dr, dg, db, da = tonumber(dr), tonumber(dg), tonumber(db), tonumber(da)
    if dr and dg and db and da then
      unitcolors._customdef[1], unitcolors._customdef[2] = dr, dg
      unitcolors._customdef[3], unitcolors._customdef[4] = db, da
    end

    local raw = C.nameplates.unitcolor_custom
    if raw and type(raw) == "string" and raw ~= "" then
      for _, entry in pairs({strsplit("#", raw)}) do
        if entry and entry ~= "" then
          -- 没有 "=" 时 strsplit 返回整串，colorstr 为 nil
          local npcname, colorstr = strsplit("=", entry)
          if npcname and npcname ~= "" then
            local color = unitcolors._customdef
            if colorstr and colorstr ~= "" then
              local cr, cg, cb, ca = GetStringColor(colorstr)
              cr, cg, cb, ca = tonumber(cr), tonumber(cg), tonumber(cb), tonumber(ca)
              if cr and cg and cb and ca then
                color = { cr, cg, cb, ca }
              end
            end
            unitcolors._custom[strlower(npcname)] = color
          end
        end
      end
    end
  end

  RefreshUnitColors()

  local offtanks = {}

  -- ========== 新增：黑名单单位配置 ==========
  local blacklistUnits = {}

  -- 初始化黑名单缓存
  local function RefreshBlacklistCache()
    blacklistUnits = {}
    local blacklistStr = C.nameplates.blacklist or ""
    for _, unitName in pairs({strsplit("#", blacklistStr)}) do
      if unitName and unitName ~= "" then
        blacklistUnits[strlower(unitName)] = true
      end
    end
  end
  local combatstate = {
    -- gets overwritten by user config
    ["OFFTANK"]  = { r = .7, g = .4, b = .2, a = 1 },
    ["NOTHREAT"] = { r = .7, g = .7, b = .2, a = 1 },
    ["THREAT"]   = { r = .7, g = .2, b = .2, a = 1 },
    ["CASTING"]  = { r = .7, g = .2, b = .7, a = 1 },
    ["STUN"]     = { r = .2, g = .7, b = .7, a = 1 },
    ["NONE"]     = { r = .2, g = .2, b = .2, a = 1 },
  }

  local elitestrings = {
    ["elite"] = "+",
    ["rareelite"] = "R+",
    ["rare"] = "R",
    ["boss"] = "B"
  }

  -- catch all nameplates
  local childs = {}  -- PERF: Reuse table instead of creating new one each scan
  local plate
  local initialized = 0
  
  -- Friendly zone nameplate disable state
  local savedHostileState = nil
  local savedFriendlyState = nil
  local inFriendlyZone = false
  local parentcount = 0
  local platecount = 0
  local registry = {}
  local visiblePlates = {}   -- 可见血条表，优化遍历
  local hiddenPlates = {}    -- 隐藏血条表

  -- ============================================================================
  -- OPTIMIZATION: GUID-based registries for O(1) lookups
  -- ============================================================================
  local guidRegistry = {}   -- guid -> plate (for direct event routing)
  local raidGuidCache = {}  -- guid -> name (rebuilt on RAID_ROSTER_UPDATE/PARTY_MEMBERS_CHANGED)
  
  -- Helper function to safely access libdebuff cast data
  local function GetCastInfo(guid)
    return pfUI.libdebuff_casts and pfUI.libdebuff_casts[guid]
  end
  
  local debuffCache = {}    -- guid -> { [spellID] = { start, duration } }
  -- Reusable per-plate debuff display buffer (avoid GC churn from per-call table creation)
  local debuffDisplayBuf = {}  -- [i] = { effect, texture, stacks, dtype, duration, timeleft, effectLower }
  for i = 1, 16 do debuffDisplayBuf[i] = {} end
  local threatMemory = {}   -- guid -> true if mob had player targeted
  -- threatCache：每帧由 TWT.tankModeThreats 重建一次的 guid->percent 查找表，
  -- 把“每个姓名板都 pairs 遍历整张威胁表”降为 O(1) 查表，消除帧级热点。
  local threatCache = {}    -- guid -> threatPercent (来源：TWT.tankModeThreats，按帧重建)
  local threatCacheFrame = -1  -- 记录最近一次重建所用的 frameState.now，确保每帧只重建一次
  local debuffSeen = {}     -- reusable table for debuff tracking (avoid GC churn)

  -- PERF: Module-level IterDebuffs callback to avoid closure allocation per call
  local _iterDebuffCount = 0
  local function iterDebuffCallback(auraSlot, spellId, effect, texture, stacks, dtype, duration, timeleft)
    if not texture or string.find(texture, "QuestionMark") then return end
    _iterDebuffCount = _iterDebuffCount + 1
    if _iterDebuffCount > 16 then return end
    local b = debuffDisplayBuf[_iterDebuffCount]
    b.effect = effect
    b.texture = texture
    b.stacks = stacks
    b.dtype = dtype
    b.duration = duration
    b.timeleft = timeleft
    b.effectLower = effect and strlower(effect)  -- 预计算小写用于过滤
  end

  -- PERF: Track visible plate count for adaptive throttling
  local visiblePlateCount = 0
  local lastVisibleCheck = 0

  -- wipe polyfill (仅保留一个)
  local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end end

  -- Player GUID for filtering
  local PlayerGUID = GetUnitGUID and GetUnitGUID("player")

  -- ============================================================================
  -- OPTIMIZATION: Config caching
  -- ============================================================================
  local cfg = {}
  local function CacheConfig()
    cfg.showcastbar = C.nameplates["showcastbar"] == "1"
    cfg.targetcastbar = C.nameplates["targetcastbar"] == "1"
    cfg.notargalpha = tonumber(C.nameplates.notargalpha) or 0.5
    if cfg.notargalpha > 1 then cfg.notargalpha = cfg.notargalpha / 100 end
    -- Clamp to 0.99 so non-target plates never reach 1.0 (used for target detection)
    if cfg.notargalpha > 0.99 then cfg.notargalpha = 0.99 end
    cfg.namefightcolor = C.nameplates.namefightcolor == "1"
    cfg.spellname = C.nameplates.spellname == "1"
    cfg.showhp = C.nameplates.showhp == "1"
    cfg.showdebuffs = C.nameplates["showdebuffs"] == "1"
    cfg.showdebuffs_hostile = C.nameplates["showdebuffs_hostile"] == "1"
    cfg.showdebuffs_friendly = C.nameplates["showdebuffs_friendly"] == "1"
    cfg.showdebuffs_targetonly = C.nameplates["showdebuffs_targetonly"] == "1"
    cfg.targetzoom = C.nameplates.targetzoom == "1"
    cfg.zoomval = (tonumber(C.nameplates.targetzoomval) or 0.4) + 1
    cfg.width = tonumber(C.nameplates.width) or 120
    cfg.heighthealth = tonumber(C.nameplates.heighthealth) or 8
    cfg.targetglow = C.nameplates.targetglow == "1"
    cfg.targethighlight = C.nameplates.targethighlight == "1"
    cfg.outcombatstate = C.nameplates.outcombatstate == "1"
    cfg.barcombatstate = C.nameplates.barcombatstate == "1"
    cfg.ccombatcasting = C.nameplates.ccombatcasting == "1"
    cfg.ccombatthreat = C.nameplates.ccombatthreat == "1"
    cfg.ccombatnothreat = C.nameplates.ccombatnothreat == "1"
    cfg.ccombatstun = C.nameplates.ccombatstun == "1"
    cfg.ccombatofftank = C.nameplates.ccombatofftank == "1"
    cfg.use_unitfonts = C.nameplates.use_unitfonts == "1"
    cfg.font_size = cfg.use_unitfonts and C.global.font_unit_size or C.global.font_size
    cfg.hptextformat = C.nameplates.hptextformat
    -- NEW: Cache debuff config
    cfg.debufftimers = C.nameplates.debufftimers == "1"
    cfg.debuffanim = tonumber(C.nameplates.debuffanim) or 0
    cfg.debufftext = tonumber(C.nameplates.debufftext) or 1
    -- NEW: Cache quest icon and target name config
    cfg.questicon = C.nameplates.questicon == "1"
    -- NEW: Cache blacklist config
    cfg.blacklist = C.nameplates.blacklist or ""
    cfg.hideblacklist = C.nameplates.hideblacklist == "1"
    cfg.selfdebuff = C.nameplates.selfdebuff == "1"
    cfg.showhatred = C.nameplates.showhatred == "1"   -- 新增

    -- NEW: Cache control-skill (CC) config
    cfg.ccenabled = C.nameplates.ccenabled == "1"
    cfg.ccposition = C.nameplates.ccposition
    cfg.ccoffx = tonumber(C.nameplates.ccoffx) or 0
    cfg.ccoffy = tonumber(C.nameplates.ccoffy) or 2
    cfg.ccmax = tonumber(C.nameplates.ccmax) or 4
    cfg.cctimers = C.nameplates.cctimers == "1"
    cfg.ccsize = tonumber(C.nameplates.ccsize) or 28
    -- 控制技能附加清单：用户自定义（ccfilter，以 # 分隔），与内置 local spellIds 表叠加
    -- 解析为小写 key 表，作为公共变量 cfg.ccspells 单次构建、显示循环复用
    cfg.ccspells = {}
    local ccraw = C.nameplates.ccfilter
    if ccraw and type(ccraw) == "string" and ccraw ~= "" then
      for _, v in pairs({strsplit("#", ccraw)}) do
        if v and v ~= "" then cfg.ccspells[strlower(v)] = true end
      end
    end


    -- 刷新自定义单位类型颜色（GUI「单位颜色」）
    RefreshUnitColors()

    -- Rebuild offtanks lookup table
    offtanks = {}
    for k, v in pairs({strsplit("#", C.nameplates.combatofftanks)}) do
      if v ~= "" then offtanks[string.lower(v)] = true end
    end
  end

  local function RebuildOfftanks()
    offtanks = {}
    for k, v in pairs({strsplit("#", C.nameplates.combatofftanks)}) do
      if v ~= "" then offtanks[string.lower(v)] = true end
    end
  end
  RebuildOfftanks()

  -- ============================================================================
  -- OPTIMIZATION: Frame state cache
  -- ============================================================================
  local frameState = {
    now = 0,
    hasTarget = false,
    targetGuid = nil,
    hasMouseover = false,
  }

  -- cache default border color
  local er, eg, eb, ea = GetStringColor(pfUI_config.appearance.border.color)

  -- Vanilla Lua 5.0 bitwise check: math.mod(math.floor(value / flag), 2) ~= 0
  local function HasFlag(flags, flag)
    return math.mod(math.floor(flags / flag), 2) ~= 0
  end

  local UNIT_FLAG_IN_COMBAT = 524288  -- 0x00080000
  local NULL_GUID           = "0x0000000000000000"

  local function RebuildRaidGuidCache()
    if not GetUnitGUID then return end
    for k in pairs(raidGuidCache) do raidGuidCache[k] = nil end
    for i = 1, GetNumRaidMembers() do
      local g = GetUnitGUID("raid"..i)
      if g then raidGuidCache[g] = UnitName("raid"..i) end
    end
    for i = 1, GetNumPartyMembers() do
      local g = GetUnitGUID("party"..i)
      if g then raidGuidCache[g] = UnitName("party"..i) end
    end
    local pg = GetUnitGUID("player")
    if pg then raidGuidCache[pg] = UnitName("player") end
  end

  local combatColorCache = {}  -- guid -> { color, expires }

  local function GetCombatStateColor(guid)
    -- PERF: Quick exit if player not in combat
    if not UnitAffectingCombat("player") then return false end
    if UnitCanAssist("player", guid) then return false end

    -- PERF: 0.2s throttle per guid - color changes are not time-critical
    local now = frameState.now
    local cached = combatColorCache[guid]
    if cached and cached.expires > now then
      return cached.color
    end

    local flags = GetUnitField and GetUnitField(guid, "flags")
    if not flags then return false end
    if not HasFlag(flags, UNIT_FLAG_IN_COMBAT) then return false end

    local mobTargetGuid = GetUnitField and GetUnitField(guid, "target")
    local hasTarget = mobTargetGuid and mobTargetGuid ~= NULL_GUID

    local target = guid.."target"
    local color = false

    local castInfo = GetCastInfo(guid)
    local isCasting = castInfo and castInfo.endTime and now < castInfo.endTime
    local targetingPlayer = hasTarget and UnitIsUnit(target, "player")

    if targetingPlayer then
      threatMemory[guid] = true
    elseif hasTarget and not isCasting then
      threatMemory[guid] = nil
    end

    -- PERF: O(1) GUID lookup via raidGuidCache instead of O(40) loop
    local targetName = hasTarget and (UnitName(target) or raidGuidCache[mobTargetGuid])

    if cfg.ccombatcasting and isCasting then
      color = combatstate.CASTING
    elseif cfg.ccombatthreat and (targetingPlayer or threatMemory[guid]) then
      color = combatstate.THREAT
    elseif cfg.ccombatofftank and targetName and offtanks[strlower(targetName)] then
      color = combatstate.OFFTANK
    elseif cfg.ccombatofftank and pfUI.uf and pfUI.uf.raid and targetName and pfUI.uf.raid.tankrole[targetName] then
      color = combatstate.OFFTANK
    elseif cfg.ccombatnothreat and hasTarget then
      color = combatstate.NOTHREAT
    elseif cfg.ccombatstun and not hasTarget then
      color = combatstate.STUN
    end

    combatColorCache[guid] = combatColorCache[guid] or {}
    combatColorCache[guid].color = color
    combatColorCache[guid].expires = now + 0.2

    return color
  end

  -- ============================================================================
  -- CatThreatLite：可嵌入的轻量仇恨共享客户端（全局单例）。
  -- 与 TWT 威胁服务端（TWThreat 协议 v4）通信，仅在队伍/团体内轮询，
  -- 返回“当前目标”上玩家自身的仇恨百分比，带 0.75s 节流与 2s 缓存。
  -- 多个插件各自携带本文件时，全局只存在一个实例与一个事件框架（原地升级逻辑见下）。
  -- 即使未安装完整 TWT 插件，只要团内有威胁服务端且任一插件携带本客户端即可取数。
  -- ============================================================================
  local CatThreatLite
  do
    local globals = _G or getfenv()
    local MODULE_REVISION = 10001
    local service = globals.CatThreatLite

    if type(service) == "table" and (tonumber(service.revision) or 0) >= MODULE_REVISION then
      -- 相同或更新版本已由其他插件加载，直接共享现有实例。
      CatThreatLite = service
    else
      if type(service) ~= "table" then
        service = {}
        globals.CatThreatLite = service
      elseif service._eventFrame then
        -- 较新副本可以原地升级共享表；先停掉旧事件框架，避免留下重复监听。
        if service._eventFrame.UnregisterAllEvents then
          service._eventFrame:UnregisterAllEvents()
        end
        if service._eventFrame.SetScript then
          service._eventFrame:SetScript("OnEvent", nil)
        end
      end

      local QUERY_PREFIX = "TWT_UDTSv4"
      local RESPONSE_MARKER = "TWTv4="
      local QUERY_INTERVAL = 0.75
      local RESPONSE_TTL = 2
      local TARGET_CHANGE_GRACE = 0.25

      local cachedPercent = nil
      local lastQueryAt = -100
      local lastResponseAt = -100
      local ignorePacketsUntil = 0
      local targetKey = nil

      local function GetGroupChannel()
        if GetNumRaidMembers() > 0 then
          return "RAID"
        end
        if GetNumPartyMembers() > 0 then
          return "PARTY"
        end
        return nil
      end

      local function GetTargetKey()
        local exists, guid = UnitExists("target")
        if not exists then
          return nil
        end
        if guid then
          return tostring(guid)
        end
        return tostring(UnitName("target") or "") .. ":" .. tostring(UnitLevel("target") or "")
      end

      local function ResetTargetState()
        local now = GetTime()
        targetKey = GetTargetKey()
        cachedPercent = nil
        lastResponseAt = -100
        lastQueryAt = now
        -- Threat API 的返回包不带目标 GUID。切换目标后短暂丢弃旧包，避免串目标。
        ignorePacketsUntil = now + TARGET_CHANGE_GRACE
      end

      local function EnsureTargetState()
        local currentKey = GetTargetKey()
        if currentKey ~= targetKey then
          ResetTargetState()
        end
      end

      local function CanQueryThreat()
        if not UnitExists("target") or UnitIsDead("target") then
          return false
        end
        if UnitIsPlayer("target") or not UnitCanAttack("player", "target") then
          return false
        end
        if not UnitAffectingCombat("target") then
          return false
        end
        return GetGroupChannel() ~= nil
      end

      local function FindPlayerPercent(packet)
        local markerStart = string.find(packet, RESPONSE_MARKER, 1, true)
        if not markerStart then
          return nil, false
        end

        local payload = string.sub(packet, markerStart + string.len(RESPONSE_MARKER))
        local tankModeStart = string.find(payload, "#", 1, true)
        if tankModeStart then
          payload = string.sub(payload, 1, tankModeStart - 1)
        end

        local playerName = UnitName("player")
        local entryStart = 1
        local payloadLength = string.len(payload)
        while entryStart <= payloadLength do
          local separator = string.find(payload, ";", entryStart, true)
          local entryEnd = separator and (separator - 1) or payloadLength
          local entry = string.sub(payload, entryStart, entryEnd)

          -- 返回格式：姓名:坦克标记:仇恨值:百分比:近战标记[:其他字段]
          local first = string.find(entry, ":", 1, true)
          local second = first and string.find(entry, ":", first + 1, true)
          local third = second and string.find(entry, ":", second + 1, true)
          local fourth = third and string.find(entry, ":", third + 1, true)
          if fourth and string.sub(entry, 1, first - 1) == playerName then
            return tonumber(string.sub(entry, third + 1, fourth - 1)), true
          end

          if not separator then
            break
          end
          entryStart = separator + 1
        end

        -- 服务端只返回限制数量内的成员；当前玩家不在列表时按 0% 处理。
        return 0, true
      end

      local function HandleThreatPacket(packet)
        if type(packet) ~= "string" or GetTime() < ignorePacketsUntil then
          return
        end
        EnsureTargetState()
        if not CanQueryThreat() then
          return
        end

        local percent, isThreatPacket = FindPlayerPercent(packet)
        if not isThreatPacket then
          return
        end
        cachedPercent = math.max(0, tonumber(percent) or 0)
        lastResponseAt = GetTime()
      end

      function service.GetPercent()
        EnsureTargetState()
        if not CanQueryThreat() then
          cachedPercent = nil
          return nil
        end

        local now = GetTime()
        if now - lastQueryAt >= QUERY_INTERVAL then
          local channel = GetGroupChannel()
          if channel then
            -- 单条请求、最多 12 名；与 TWThreat 的双请求和完整团队模型相比开销很小。
            pcall(SendAddonMessage, QUERY_PREFIX, "limit=12", channel)
            lastQueryAt = now
          end
        end

        if cachedPercent ~= nil and now - lastResponseAt <= RESPONSE_TTL then
          return cachedPercent
        end
        return nil
      end

      local eventFrame = CreateFrame("Frame")
      eventFrame:RegisterEvent("CHAT_MSG_ADDON")
      eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
      eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
      eventFrame:SetScript("OnEvent", function()
        if event == "CHAT_MSG_ADDON" then
          HandleThreatPacket(arg2)
        else
          ResetTargetState()
        end
      end)

      -- 元数据最后写入，避免文件加载中途失败时留下一个看似可用的半成品版本。
      service.name = "CatThreatLite"
      service.revision = MODULE_REVISION
      service.protocolVersion = 4
      service.queryInterval = QUERY_INTERVAL
      service._eventFrame = eventFrame

      CatThreatLite = service
    end
  end

  -- 增强版仇恨百分比获取（优化版）：
  -- 优先级 ① Nampower 原生 API（按 GUID 精确，无网络，最优）
  --       ② TWT 多目标坦克模式 > ShaguDPS 坦克模式（按 GUID，每帧只重建一次查找表）
  --       ③ 仅“当前目标”姓名板：CatThreatLite > TWT 单体 > ShaguDPS（均为当前目标数据）
  local function GetThreatPercent(guid)
    if not guid or guid == "" or UnitIsUnit(guid, "player") then
      return nil
    end

    -- 1) Nampower 原生威胁 API（4.5+ 支持，按 GUID 精确，无需网络，最优先）
    if GetUnitThreatPct then
      local threatPct = GetUnitThreatPct(guid)
      if threatPct and threatPct > 0 then
        return threatPct
      end
    end

    -- 2) 多目标坦克模式：每个 GUID 独立百分比。
    --    每帧只重建一次 guid->percent 查找表（threatCache），避免对每个姓名板都做 pairs 遍历。
    --    数据源：TWT.tankModeThreats 优先；ShaguDPS 坦克模式（TMTv1，条目自带 guid）补位，
    --    仅填充 TWT 未覆盖的 GUID，不覆盖已有值。
    if frameState.now ~= threatCacheFrame then
      wipe(threatCache)
      if TWT and TWT.tankModeThreats then
        for _, v in pairs(TWT.tankModeThreats) do
          if v.guid and v.perc then threatCache[v.guid] = v.perc end
        end
      end
      if ShaguDPS and ShaguDPS.data and ShaguDPS.data.tank_mode then
        for _, v in pairs(ShaguDPS.data.tank_mode) do
          if v.guid and v.perc and not threatCache[v.guid] then
            threatCache[v.guid] = v.perc
          end
        end
      end
      threatCacheFrame = frameState.now
    end
    local pct = threatCache[guid]
    if pct and pct > 0 then
      return pct
    end

    -- 3) 仅对“当前目标”的姓名板，使用单目标仇恨源（这些源只提供当前目标数据）。
    if UnitIsUnit("target", guid) then
      -- 3a) CatThreatLite：轻量共享客户端，0.75s 轮询 + 2s 缓存，覆盖无完整 TWT 的场景。
      if CatThreatLite then
        local ctlPct = CatThreatLite.GetPercent()
        if ctlPct and ctlPct > 0 then
          return ctlPct
        end
      end

      -- 3b) TWT 单体目标模式（O(1) 直接索引，替代原 pairs 遍历）
      if TWT and TWT.threats then
        local playerName = UnitName("player")
        local entry = TWT.threats[playerName]
        if entry and entry.perc and entry.perc > 0 then
          return entry.perc
        end
      end

      -- 3c) 回退到 ShaguDPS 的仇恨表
      if ShaguDPS and ShaguDPS.data and ShaguDPS.data.threat then
        local playerName = UnitName("player")
        local entry = ShaguDPS.data.threat[playerName]
        if entry and entry.perc and entry.perc > 0 then
          return entry.perc
        end
      end
    end

    return nil
  end

  -- 修复: IsNamePlate 中的 plate 变量错误，应为 frame
  local function IsNamePlate(frame)
    if frame:GetObjectType() ~= NAMEPLATE_FRAMETYPE then return nil end
    -- local: this used to assign to the file-local `regions`, leaking state
    -- across calls inside the scan loop below.
    local regions = frame:GetRegions()

    if not regions then return nil end
    if not regions.GetObjectType then return nil end
    if not regions.GetTexture then return nil end

    if regions:GetObjectType() ~= "Texture" then return nil end
    return regions:GetTexture() == "Interface\\Tooltips\\Nameplate-Border" or nil
  end

  local function DisableObject(object)
    if not object then return end
    if not object.GetObjectType then return end

    local otype = object:GetObjectType()

    if otype == "Texture" then
      object:SetTexture("")
      object:SetTexCoord(0, 0, 0, 0)
    elseif otype == "FontString" then
      object:SetWidth(0.001)
    elseif otype == "StatusBar" then
      object:SetStatusBarTexture("")
    end
  end

  local function TotemPlate(name)
    if C.nameplates.totemicons == "1" then
      for totem, icon in pairs(L["totems"]) do
        if string.find(name, totem) then return icon end
      end
    end
  end

  local function HidePlate(unittype, name, fullhp, target)
    -- keep some plates always visible according to config
    if C.nameplates.fullhealth == "1" and not fullhp then return nil end
    if C.nameplates.target == "1" and target then return nil end

    -- ========== 新增：黑名单单位检查，如果是目标则不隐藏 ==========
    local nameLower = name and strlower(name) or nil
    if cfg.hideblacklist and name and blacklistUnits[nameLower] and not target then
      return "BLACKLIST"  -- 返回特殊标识，表示需要完全隐藏
    end
    -- return true when something needs to be hidden
    if C.nameplates.enemynpc == "1" and unittype == "ENEMY_NPC" then
      return true
    elseif C.nameplates.enemyplayer == "1" and unittype == "ENEMY_PLAYER" then
      return true
    elseif C.nameplates.neutralnpc == "1" and unittype == "NEUTRAL_NPC" then
      return true
    elseif C.nameplates.friendlynpc == "1" and unittype == "FRIENDLY_NPC" then
      return true
    elseif C.nameplates.friendlyplayer == "1" and unittype == "FRIENDLY_PLAYER" then
      return true
    elseif C.nameplates.critters == "1" and unittype == "NEUTRAL_NPC" then
      for i, critter in pairs(L["critters"]) do
        if string.lower(name) == string.lower(critter) then return true end
      end
    elseif C.nameplates.totems == "1" then
      for totem in pairs(L["totems"]) do
        if string.find(name, totem) then return true end
      end
    end

    -- nothing to hide
    return nil
  end

  local function abbrevname(t)
    return string.sub(t,1,1)..". "
  end

  local function GetNameString(name)
    local abbrev = pfUI_config.unitframes.abbrevname == "1" or nil
    local size = 20

    -- first try to only abbreviate the first word
    if abbrev and name and strlen(name) > size then
      name = string.gsub(name, "^(%S+) ", abbrevname)
    end

    -- abbreviate all if it still doesn't fit
    if abbrev and name and strlen(name) > size then
      name = string.gsub(name, "(%S+) ", abbrevname)
    end

    return name
  end


  local function GetUnitType(red, green, blue)
    if red > .9 and green < .2 and blue < .2 then
      return "ENEMY_NPC"
    elseif red > .9 and green > .9 and blue < .2 then
      return "NEUTRAL_NPC"
    elseif red < .2 and green < .2 and blue > 0.9 then
      return "FRIENDLY_PLAYER"
    elseif red < .2 and green > .9 and blue < .2 then
      return "FRIENDLY_NPC"
    end
  end

  local filter, list, cache
  local function DebuffFilterPopulate()
    -- initialize variables
    filter = C.nameplates["debuffs"]["filter"]
    if filter == "none" then return end
    list = C.nameplates["debuffs"][filter]
    cache = {}

    -- populate list
    for _, val in pairs({strsplit("#", list)}) do
      cache[strlower(val)] = true
    end
  end

  -- 优化: 接受预计算的小写 effect
  local function DebuffFilter(effect, effectLower)
    if filter == "none" then return true end
    if not cache then DebuffFilterPopulate() end
    local key = effectLower or strlower(effect)

    if filter == "blacklist" and cache[key] then
      return nil
    elseif filter == "blacklist" then
      return true
    elseif filter == "whitelist" and cache[key] then
      return true
    elseif filter == "whitelist" then
      return nil
    end
  end

  local function PlateCacheDebuffs(self, unitstr, verify, ownOnly)
    if not self.debuffcache then self.debuffcache = {} end
    if not libdebuff then return end

    local now = GetTime()

    -- Clear existing cache slots
    for id = 1, 16 do
        if self.debuffcache[id] then
            self.debuffcache[id].empty = true
        end
    end

    if unitstr and libdebuff then
        if ownOnly and libdebuff.UnitOwnDebuff then
            -- 仅自身 debuff：循环调用 UnitOwnDebuff
            for id = 1, 16 do
                local effect, rank, texture, stacks, dtype, duration, timeleft = libdebuff:UnitOwnDebuff(unitstr, id)
                if effect and texture and timeleft and timeleft > 0 then
                    local start = now - ((duration or 0) - (timeleft or 0))
                    local stop = now + timeleft
                    self.debuffcache[id] = self.debuffcache[id] or {}
                    self.debuffcache[id].effect = effect
                    self.debuffcache[id].texture = texture
                    self.debuffcache[id].stacks = stacks
                    self.debuffcache[id].duration = duration or 0
                    self.debuffcache[id].start = start
                    self.debuffcache[id].stop = stop
                    self.debuffcache[id].empty = nil
                end
            end
        elseif libdebuff.IterDebuffs and GetUnitGUID then
            -- 高效迭代（所有 debuff）
            local id = 0
            libdebuff:IterDebuffs(unitstr, function(auraSlot, spellId, effect, texture, stacks, dtype, duration, timeleft)
                if not effect or not texture then return end
                id = id + 1
                if id > 16 then return end
                local stop = (timeleft and timeleft > 0) and (now + timeleft) or nil
                local start = stop and (stop - (duration or 0)) or now
                self.debuffcache[id] = self.debuffcache[id] or {}
                self.debuffcache[id].effect = effect
                self.debuffcache[id].texture = texture
                self.debuffcache[id].stacks = stacks
                self.debuffcache[id].duration = duration or 0
                self.debuffcache[id].start = start
                self.debuffcache[id].stop = stop
                self.debuffcache[id].empty = nil
            end)
        else
            -- 回退到 UnitDebuff 循环
            for id = 1, 16 do
                local effect, rank, texture, stacks, dtype, duration, timeleft = libdebuff:UnitDebuff(unitstr, id)
                if effect and texture and timeleft and timeleft > 0 then
                    local start = now - ((duration or 0) - (timeleft or 0))
                    local stop = now + timeleft
                    self.debuffcache[id] = self.debuffcache[id] or {}
                    self.debuffcache[id].effect = effect
                    self.debuffcache[id].texture = texture
                    self.debuffcache[id].stacks = stacks
                    self.debuffcache[id].duration = duration or 0
                    self.debuffcache[id].start = start
                    self.debuffcache[id].stop = stop
                    self.debuffcache[id].empty = nil
                end
            end
        end
    end

    self.verify = verify
end

  local function PlateUnitDebuff(self, id, now)
    now = now or GetTime()
    -- break on unknown data
    if not self.debuffcache then return end
    if not self.debuffcache[id] then return end
    if not self.debuffcache[id].stop then return end

    -- break on timeout debuffs
    if self.debuffcache[id].empty then return end
    if self.debuffcache[id].stop < now then return end

    -- return cached debuff
    local c = self.debuffcache[id]
    return c.effect, c.rank, c.texture, c.stacks, c.dtype, c.duration, (c.stop - now)
  end

  local function CreateDebuffIcon(plate, index)
    plate.debuffs[index] = CreateFrame("Frame", plate.platename.."Debuff"..index, plate)
    plate.debuffs[index]:Hide()
    plate.debuffs[index]:SetFrameLevel(4)

    plate.debuffs[index].icon = plate.debuffs[index]:CreateTexture(nil, "BACKGROUND")
    plate.debuffs[index].icon:SetTexture(.3,1,.8,1)
    plate.debuffs[index].icon:SetAllPoints(plate.debuffs[index])
    -- PERF: fixed crop, set once here instead of on every debuff update
    plate.debuffs[index].icon:SetTexCoord(.078, .92, .079, .937)

    plate.debuffs[index].stacks = plate.debuffs[index]:CreateFontString(nil, "OVERLAY")
    plate.debuffs[index].stacks:SetAllPoints(plate.debuffs[index])
    plate.debuffs[index].stacks:SetJustifyH("RIGHT")
    plate.debuffs[index].stacks:SetJustifyV("BOTTOM")
    plate.debuffs[index].stacks:SetTextColor(1,1,0)

    -- PERF: Use lightweight fake cooldown frame when animation disabled
    -- The Model-based CooldownFrameTemplate causes major lag with many nameplates
    if pfUI.client <= 11200 and cfg.debuffanim ~= 1 then
      plate.debuffs[index].cd = CreateFrame("Frame", plate.platename.."Debuff"..index.."Cooldown", plate.debuffs[index])
      plate.debuffs[index].cd:SetAllPoints(plate.debuffs[index])
      plate.debuffs[index].cd:SetFrameLevel(6)
      plate.debuffs[index].cd:SetScript("OnUpdate", CooldownFrame_OnUpdateModel)
      plate.debuffs[index].cd.AdvanceTime = DoNothing
      plate.debuffs[index].cd.SetSequence = DoNothing
      plate.debuffs[index].cd.SetSequenceTime = DoNothing
    else
      -- Use CooldownFrameTemplate for animation or TBC+
      plate.debuffs[index].cd = CreateFrame(COOLDOWN_FRAME_TYPE, plate.platename.."Debuff"..index.."Cooldown", plate.debuffs[index], "CooldownFrameTemplate")
      plate.debuffs[index].cd:SetAllPoints(plate.debuffs[index])
      plate.debuffs[index].cd:SetFrameLevel(6)
    end

    -- Set initial config flags (will be cached per-cooldown later)
    plate.debuffs[index].cd.pfCooldownStyleAnimation = cfg.debuffanim
    plate.debuffs[index].cd.pfCooldownStyleText = cfg.debufftext
    plate.debuffs[index].cd.pfCooldownType = "ALL"
  end

  local function UpdateDebuffConfig(nameplate, i)
    if not nameplate.debuffs[i] then return end

    -- update debuff positions
    local width = tonumber(C.nameplates.width)
    local debuffsize = tonumber(C.nameplates.debuffsize)
    local debuffoffset = tonumber(C.nameplates.debuffoffset)
    local limit = floor(width / debuffsize)
    local font = C.nameplates.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
    local font_style = C.nameplates.name.fontstyle

    local aligna, alignb, offs, space
    if C.nameplates.debuffs["position"] == "BOTTOM" then
      aligna, alignb, offs, space = "TOPLEFT", "BOTTOMLEFT", -debuffoffset, -1
    else
      aligna, alignb, offs, space = "BOTTOMLEFT", "TOPLEFT", debuffoffset, 1
    end

    nameplate.debuffs[i].stacks:SetFont(font, font_size, font_style)
    nameplate.debuffs[i]:ClearAllPoints()
    if i == 1 then
      nameplate.debuffs[i]:SetPoint(aligna, nameplate.health, alignb, 0, offs)
    elseif i <= limit then
      nameplate.debuffs[i]:SetPoint("LEFT", nameplate.debuffs[i-1], "RIGHT", 1, 0)
    elseif i > limit and limit > 0 then
      nameplate.debuffs[i]:SetPoint(aligna, nameplate.debuffs[i-limit], alignb, 0, space)
    end

    nameplate.debuffs[i]:SetWidth(tonumber(C.nameplates.debuffsize))
    nameplate.debuffs[i]:SetHeight(tonumber(C.nameplates.debuffsize))
    
    -- Update cooldown display settings
    if nameplate.debuffs[i].cd then
      local cooldown_text = tonumber(C.nameplates.debufftext) or 1
      local cooldown_anim = tonumber(C.nameplates.debuffanim) or 0
      nameplate.debuffs[i].cd.pfCooldownStyleText = cooldown_text
      nameplate.debuffs[i].cd.pfCooldownStyleAnimation = cooldown_anim
      
      -- Update scale for TBC+
      if pfUI.client > 11200 then
        local debuffsize = tonumber(C.nameplates.debuffsize)
        local cdScale = debuffsize / 32
        nameplate.debuffs[i].cd:SetScale(cdScale)
      end
    end
  end

  -- ============================================================================
  -- Control-skill (CC) highlight icons
  -- 把常见的控制技能（闷棍/肾击/变形术 等）从普通 debuff 行里抽出来，
  -- 以更大的图标显示在姓名板最顶部，并带冷却计时。完全可配置。
  -- 注意：以下辅助函数定义为 nameplates 的方法而非文件级 local，
  -- 以避免给 OnDataChanged 等闭包增加 upvalue（本客户端单函数 upvalue 上限约 32）。
  -- ============================================================================

  -- create nameplate core
local nameplates = CreateFrame("Frame", "pfNameplates", UIParent)
nameplates:RegisterEvent("PLAYER_ENTERING_WORLD")
nameplates:RegisterEvent("PLAYER_TARGET_CHANGED")
nameplates:RegisterEvent("PLAYER_LOGOUT")
nameplates:RegisterEvent("UNIT_COMBO_POINTS")
nameplates:RegisterEvent("PLAYER_COMBO_POINTS")
nameplates:RegisterEvent("ZONE_CHANGED_NEW_AREA")
nameplates:RegisterEvent("RAID_ROSTER_UPDATE")
nameplates:RegisterEvent("PARTY_MEMBERS_CHANGED")
if GetUnitField then
  nameplates:RegisterEvent("UNIT_FLAGS_GUID")
end
  
  -- Cast tracking handled by libdebuff (SPELL_START/GO/FAILED events)
  -- No local event registration needed

  -- ============================================================================
  -- 控制技能（CC）高亮图标辅助方法（定义为 nameplates 方法，避免占用闭包 upvalue）
  -- ============================================================================

  -- 判断某个 debuff 是否为配置中的控制技能（精确查表，与 En_LoseControl.lua 一致）
  nameplates.CreateCCIcon = function(plate, index)
    plate.ccdebuffs[index] = CreateFrame("Frame", plate.platename.."CC"..index, plate.cccontainer)
    plate.ccdebuffs[index]:Hide()
    plate.ccdebuffs[index]:SetFrameLevel(8)

    plate.ccdebuffs[index].icon = plate.ccdebuffs[index]:CreateTexture(nil, "BACKGROUND")
    plate.ccdebuffs[index].icon:SetTexture(.3,1,.8,1)
    plate.ccdebuffs[index].icon:SetAllPoints(plate.ccdebuffs[index])
    -- PERF: fixed crop, set once here instead of on every debuff update
    plate.ccdebuffs[index].icon:SetTexCoord(.078, .92, .079, .937)

    CreateBackdrop(plate.ccdebuffs[index])

    -- 冷却计时（复用 debuff 的冷却样式）
    if pfUI.client <= 11200 and (cfg.debuffanim or 0) ~= 1 then
      plate.ccdebuffs[index].cd = CreateFrame("Frame", plate.platename.."CC"..index.."Cooldown", plate.ccdebuffs[index])
      plate.ccdebuffs[index].cd:SetAllPoints(plate.ccdebuffs[index])
      plate.ccdebuffs[index].cd:SetFrameLevel(10)
      plate.ccdebuffs[index].cd:SetScript("OnUpdate", CooldownFrame_OnUpdateModel)
      plate.ccdebuffs[index].cd.AdvanceTime = DoNothing
      plate.ccdebuffs[index].cd.SetSequence = DoNothing
      plate.ccdebuffs[index].cd.SetSequenceTime = DoNothing
    else
      plate.ccdebuffs[index].cd = CreateFrame(COOLDOWN_FRAME_TYPE, plate.platename.."CC"..index.."Cooldown", plate.ccdebuffs[index], "CooldownFrameTemplate")
      plate.ccdebuffs[index].cd:SetAllPoints(plate.ccdebuffs[index])
      plate.ccdebuffs[index].cd:SetFrameLevel(10)
    end
    plate.ccdebuffs[index].cd.pfCooldownStyleAnimation = cfg.debuffanim or 0
    plate.ccdebuffs[index].cd.pfCooldownStyleText = cfg.debufftext or 1
    plate.ccdebuffs[index].cd.pfCooldownType = "ALL"
  end

  -- 定位/缩放所有 CC 图标及容器（整块姓名板调用一次）
  nameplates.UpdateCCConfig = function(nameplate)
    if not nameplate.cccontainer then return end
    local ccsize = tonumber(C.nameplates.ccsize) or 28
    local ccmax = tonumber(C.nameplates.ccmax) or 4
    local gap = 2

    nameplate.cccontainer:ClearAllPoints()
    nameplate.cccontainer:SetHeight(ccsize)
    if C.nameplates.ccposition == "BOTTOM" then
      nameplate.cccontainer:SetPoint("TOP", nameplate.health, "BOTTOM", tonumber(C.nameplates.ccoffx) or 0, -(tonumber(C.nameplates.ccoffy) or 0))
    else
      nameplate.cccontainer:SetPoint("BOTTOM", nameplate, "TOP", tonumber(C.nameplates.ccoffx) or 0, tonumber(C.nameplates.ccoffy) or 2)
    end

    for i = 1, ccmax do
      local cc = nameplate.ccdebuffs[i]
      if not cc then break end
      cc:SetWidth(ccsize)
      cc:SetHeight(ccsize)
      cc:ClearAllPoints()
      if i == 1 then
        cc:SetPoint("LEFT", nameplate.cccontainer, "LEFT", 0, 0)
      else
        cc:SetPoint("LEFT", nameplate.ccdebuffs[i-1], "RIGHT", gap, 0)
      end
      if cc.cd and pfUI.client > 11200 then
        cc.cd:SetScale(ccsize / 32)
      end
    end
  end

  -- Callback from libdebuff when auras change (GUID-based, event-driven)
  nameplates.OnAuraUpdate = function(self, guid)
    if not guid then return end
    
    -- GUID is actual GUID (0xF13000...) from Nampower events
    local plate = guidRegistry[guid]
    if plate and plate.nameplate then
      -- Mark nameplate for aura update in next OnUpdate cycle
      plate.nameplate.auraUpdate = true
    end
  end

  -- Hook into libdebuff timer signal (fires when slotTimers written or cleared)
  pfUI.libdebuff_on_unit_updated = pfUI.libdebuff_on_unit_updated or {}
  table.insert(pfUI.libdebuff_on_unit_updated, function(guid)
    local plate = guidRegistry[guid]
    if plate and plate.nameplate then
      plate.nameplate.auraUpdate = true
    end
  end)

  -- 记录上一次 WorldFrame 子对象数量，用于检测姓名板显隐
  local lastParentCount = 0

  nameplates:SetScript("OnEvent", function()
    -- Stop event handling during logout to prevent crash 132
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      this:SetScript("OnUpdate", nil)
      if nameplates.mouselook then
        nameplates.mouselook:SetScript("OnUpdate", nil)
      end
      return
      
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
      if event == "PLAYER_ENTERING_WORLD" then
        if GetUnitGUID then
          _, PlayerGUID = UnitExists("player")
          PlayerGUID = GetUnitGUID("player")
        end
        CacheConfig()
        this:SetGameVariables()
        RebuildRaidGuidCache()
        lastParentCount = WorldFrame:GetNumChildren()  -- 初始化基准数量
      end
      
      -- Handle friendly zone nameplate disable feature
      local disableHostile = C.nameplates["disable_hostile_in_friendly"] == "1"
      local disableFriendly = C.nameplates["disable_friendly_in_friendly"] == "1"
      
      if disableHostile or disableFriendly then
        local pvpType = GetZonePVPInfo()
        local nowFriendly = (pvpType == "friendly")
        
        if nowFriendly and not inFriendlyZone then
          -- Entering friendly zone - save current state and hide based on options
          inFriendlyZone = true
          savedHostileState = C.nameplates["showhostile"]
          savedFriendlyState = C.nameplates["showfriendly"]
          
          if disableHostile then
            _G.NAMEPLATES_ON = nil
            HideNameplates()
          end
          
          if disableFriendly then
            _G.FRIENDNAMEPLATES_ON = nil
            HideFriendNameplates()
          end
        elseif not nowFriendly and inFriendlyZone then
          -- Leaving friendly zone - restore previous state
          inFriendlyZone = false
          
          if savedHostileState == "1" then
            _G.NAMEPLATES_ON = true
            ShowNameplates()
          end
          
          if savedFriendlyState == "1" then
            _G.FRIENDNAMEPLATES_ON = true
            ShowFriendNameplates()
          end
          
          savedHostileState = nil
          savedFriendlyState = nil
        end
      end

    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
      RebuildRaidGuidCache()

    elseif event == "UNIT_FLAGS_GUID" then
      -- Nampower: fires instantly when any unit's flags change (e.g. stun, combat enter/leave)
      -- arg1 = guid — directly flag that nameplate for immediate update, bypassing throttle
      local plate = guidRegistry[arg1]
      if plate and plate.nameplate then
        plate.nameplate.eventcache = true
      end

    elseif event == "PLAYER_TARGET_CHANGED" then
      -- 清除所有 GUID 的仇恨颜色缓存，确保目标切换后立即更新
      for guid in pairs(combatColorCache) do
        combatColorCache[guid] = nil
      end
      -- Flag target plate for update via GUID registry
      local targetGuid = GetUnitGUID and GetUnitGUID("target")
      if targetGuid then
        local plate = guidRegistry[targetGuid]
        if plate and plate.nameplate then
          plate.nameplate.targetUpdate = true
        end
      end
      -- Also propagate to all plates for alpha/strata updates
      this.eventcache = true

    elseif event == "PLAYER_COMBO_POINTS" or event == "UNIT_COMBO_POINTS" then
      -- Only flag the target plate for combo point update
      local targetGuid = GetUnitGUID and GetUnitGUID("target")
      if targetGuid then
        local plate = guidRegistry[targetGuid]
        if plate and plate.nameplate then
          plate.nameplate.comboUpdate = true
        end
      end
    else
      this.eventcache = true
    end
  end)

  nameplates:SetScript("OnUpdate", function()
    -- PERF: Throttle central OnUpdate to ~80 FPS (0.0125s)
    -- Saves ~44% calls at 144 FPS while staying above 50 FPS target-plate rate
    local now = GetTime()
    if (this.frameTick or 0) + 0.01 > now then return end
    this.frameTick = now

    -- PERF: Cache GetTime() once per frame
    frameState.now = now
    frameState.hasTarget, frameState.targetGuid = UnitExists("target")
    if frameState.hasTarget and GetUnitGUID then
      frameState.targetGuid = GetUnitGUID("target")
    else
      frameState.targetGuid = nil
    end
    frameState.hasMouseover = UnitExists("mouseover")

    -- ===== 固定位置目标姓名板（目标姓名板不可见时显示） =====
    if C.nameplates.fixedposition == "1" or target_fixed_plate then
      nameplates.UpdateFixedPlate(frameState)
    end

    -- propagate events to all nameplates
    if this.eventcache then
      this.eventcache = nil
      for plate in pairs(registry) do
        plate.eventcache = true
      end
    end

    -- PERF: Update visible plate count periodically for adaptive throttling
    if frameState.now - lastVisibleCheck > 0.5 then
      lastVisibleCheck = frameState.now
      local count = 0
      for plate in pairs(visiblePlates) do
        if plate:IsVisible() then count = count + 1 end
      end
      visiblePlateCount = count
    end

    -- ===== 实时检测 WorldFrame 子对象数量变化 =====
    local currentParentCount = WorldFrame:GetNumChildren()
    local forceScan = (currentParentCount ~= lastParentCount)
    if forceScan then
      lastParentCount = currentParentCount
    end

    -- Throttle ONLY the nameplate scanner (但当数量变化时强制立即扫描)
    local scanThrottle = nameplates.combat and nameplates.combat.inCombat and 0.1 or 0.05
    local shouldScan = forceScan or (this.tick or 0) <= frameState.now
    if shouldScan then
      if not forceScan then
        this.tick = frameState.now + scanThrottle
      end

      -- detect new nameplates
      parentcount = currentParentCount   -- 使用已获取的数量
      if initialized < parentcount then
        -- PERF: Reuse childs table instead of creating new one
        local newchilds = { WorldFrame:GetChildren() }
        for i = 1, parentcount do
          childs[i] = newchilds[i]
        end

        for i = initialized + 1, parentcount do
          plate = childs[i]
          if IsNamePlate(plate) and not registry[plate] then
            nameplates.OnCreate(plate)
            registry[plate] = plate
            visiblePlates[plate] = true  -- 新血条默认为可见，后续 OnShow/OnHide 会管理
          end
        end

        initialized = parentcount

        -- 清理 registry 中已失效（被销毁/脱离 WorldFrame）的 nameplate 引用，防止长时间游玩后内存只增不减
        -- 已接管板（_pfNamePlate）必须豁免：DisableObject 清空边框纹理后 IsNamePlate 判 false，
        -- 不豁免会把所有活着的板清出 registry，导致 UpdateConfig 的 OnConfigChange 循环永远空转
        --（表现为：团队图标等仅 OnConfigChange 应用的设置改了必须 /reload 才生效）。
        for plate in pairs(registry) do
          if not plate._pfNamePlate and not IsNamePlate(plate) then
            registry[plate] = nil
            visiblePlates[plate] = nil
            hiddenPlates[plate] = nil
          end
        end
      end
    end

    -- Central OnUpdate for all VISIBLE plates only (optimization)
    for plate in pairs(visiblePlates) do
      if plate:IsVisible() then
        nameplates.OnUpdate(plate, frameState)
      else
        -- 隐藏的血条移到 hiddenPlates
        visiblePlates[plate] = nil
        hiddenPlates[plate] = true
        -- 清理缓存
        local guid = plate.nameplate and plate.nameplate.cachedGuid
        if guid then
          if guidRegistry[guid] == plate then
            guidRegistry[guid] = nil
          end
          
          local castInfo = GetCastInfo(guid)
          if castInfo and castInfo.endTime and castInfo.endTime < frameState.now then
            if pfUI.libdebuff_casts then
              pfUI.libdebuff_casts[guid] = nil
            end
          end
          
          if debuffCache[guid] then debuffCache[guid] = nil end
          if threatMemory[guid] then threatMemory[guid] = nil end
          if threatCache[guid] then threatCache[guid] = nil end
          if combatColorCache[guid] then combatColorCache[guid] = nil end
        end
      end
    end
  end)

  -- combat tracker
  nameplates.combat = CreateFrame("Frame")
  nameplates.combat:RegisterEvent("PLAYER_ENTER_COMBAT")
  nameplates.combat:RegisterEvent("PLAYER_LEAVE_COMBAT")
  nameplates.combat:RegisterEvent("PLAYER_LOGOUT")
  nameplates.combat:SetScript("OnEvent", function()
    if event == "PLAYER_LOGOUT" then
      this:UnregisterAllEvents()
      this:SetScript("OnEvent", nil)
      return
    elseif event == "PLAYER_ENTER_COMBAT" then
      this.inCombat = 1
      if PlayerFrame then PlayerFrame.inCombat = 1 end
    elseif event == "PLAYER_LEAVE_COMBAT" then
      this.inCombat = nil
      if PlayerFrame then PlayerFrame.inCombat = nil end
      -- Clear threat memory when leaving combat
      for k in pairs(threatMemory) do
        threatMemory[k] = nil
      end
      -- 脱离战斗时同时清空仇恨颜色缓存，避免残留数据
      for k in pairs(combatColorCache) do
        combatColorCache[k] = nil
      end
    end
  end)

  nameplates.OnCreate = function(frame)
    local parent = frame or this
    platecount = platecount + 1
    platename = "pfNamePlate" .. platecount

    -- create pfUI nameplate overlay
    local nameplate = CreateFrame("Button", platename, parent)
    nameplate.platename = platename
    nameplate:EnableMouse(0)
    nameplate.parent = parent
    -- 标记：此暴雪板已被 pfUI 接管。DisableObject 会把边框纹理 SetTexture("")，
    -- 之后 IsNamePlate()（靠 Nameplate-Border 纹理识别）永远返回 false，
    -- registry 清理若不豁免已接管板，会把它们全部清空（UpdateConfig 刷新循环空转）。
    parent._pfNamePlate = true
    nameplate.cache = {}
    nameplate.UnitDebuff = PlateUnitDebuff
    nameplate.CacheDebuffs = PlateCacheDebuffs
    nameplate.original = {}

    -- 初始化缓存字段
    nameplate.cachedVerifyName = nil
    nameplate.cachedVerifyLevel = nil
    nameplate.cachedVerify = ""
    nameplate.cachedTargetGUID = nil
    nameplate.cachedTargetClass = nil
    -- 出生时间：客户端给新板压"非目标"透明度(0.6)之前，原始帧 alpha 是默认的
    -- 1.0，这段时间内不能拿 alpha>=0.99 当目标判据（见 OnUpdate 的 alphaEligible）
    nameplate.spawnT = GetTime()

    -- create shortcuts for all known elements and disable them
    nameplate.original.healthbar, nameplate.original.castbar = parent:GetChildren()
    DisableObject(nameplate.original.healthbar)
    DisableObject(nameplate.original.castbar)

    for i, object in pairs({parent:GetRegions()}) do
      if NAMEPLATE_OBJECTORDER[i] and NAMEPLATE_OBJECTORDER[i] == "raidicon" then
        nameplate[NAMEPLATE_OBJECTORDER[i]] = object
      elseif NAMEPLATE_OBJECTORDER[i] then
        nameplate.original[NAMEPLATE_OBJECTORDER[i]] = object
        DisableObject(object)
      else
        DisableObject(object)
      end
    end

    HookScript(nameplate.original.healthbar, "OnValueChanged", nameplates.OnValueChanged)

    -- adjust sizes and scaling of the nameplate
    nameplate:SetScale(UIParent:GetScale())

    nameplate.health = CreateFrame("StatusBar", nil, nameplate)
    nameplate.health:SetFrameLevel(4) -- keep above glow
    nameplate.health.text = nameplate.health:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameplate.health.text:SetAllPoints()
    nameplate.health.text:SetTextColor(1,1,1,1)

    nameplate.name = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.name:SetPoint("TOP", nameplate, "TOP", 0, 0)

    -- 新增：目标显示文本
    nameplate.targetname = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.targetname:SetPoint("LEFT", nameplate.name, "RIGHT", 10, 0)
    nameplate.targetname:SetTextColor(1, 1, 0.5, 0.9)	

    -- 新增：仇恨显示文本
    nameplate.hatred = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.hatred:SetPoint("LEFT", nameplate.targetname, "RIGHT", 5, 0)
    nameplate.hatred:SetTextColor(1, 1, 1, 0.9)
    nameplate.hatred:Hide()							  
    
    -- 任务怪提示图标
    nameplate.cluster = nameplate:CreateTexture(nil, "OVERLAY")
    nameplate.cluster:SetWidth(15)
    nameplate.cluster:SetHeight(15)
    nameplate.cluster:ClearAllPoints()
    nameplate.cluster:SetPoint("LEFT", nameplate.health, "RIGHT", 3, 0)
    nameplate.cluster:Hide()

    -- 唯一 glow 创建（删除重复）
    nameplate.glow = nameplate:CreateTexture(nil, "BACKGROUND")
    nameplate.glow:SetPoint("CENTER", nameplate.health, "CENTER", 0, 0)
    nameplate.glow:SetTexture(pfUI.media["img:dot"])
    nameplate.glow:Hide()	
    
    nameplate.guild = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.guild:SetPoint("BOTTOM", nameplate.health, "BOTTOM", 0, 0)

    nameplate.level = nameplate:CreateFontString(nil, "OVERLAY")
    nameplate.level:SetPoint("RIGHT", nameplate.health, "LEFT", -3, 0)

    -- Create a dedicated high-level frame for the raid icon so it renders
    -- ABOVE nameplate.health (FrameLevel 4) and stays visible even when
    -- nameplates are toggled off (the Blizzard parent plate still exists).
    nameplate.raidiconframe = CreateFrame("Frame", nil, nameplate)
    nameplate.raidiconframe:SetFrameLevel(10)
    nameplate.raidiconframe:SetAllPoints(nameplate)
    nameplate.raidicon:SetParent(nameplate.raidiconframe)
    nameplate.raidicon:SetDrawLayer("OVERLAY", 7)
    if C.unitframes.blizzard_raidicons ~= "1" then
      nameplate.raidicon:SetTexture(pfUI.media["img:raidicons"])
    end

    nameplate.totem = CreateFrame("Frame", nil, nameplate)
    nameplate.totem:SetPoint("CENTER", nameplate, "CENTER", 0, 0)
    nameplate.totem:SetHeight(32)
    nameplate.totem:SetWidth(32)
    nameplate.totem.icon = nameplate.totem:CreateTexture(nil, "OVERLAY")
    nameplate.totem.icon:SetTexCoord(.078, .92, .079, .937)
    nameplate.totem.icon:SetAllPoints()
    CreateBackdrop(nameplate.totem)

    do -- debuffs
      nameplate.debuffs = {}
      CreateDebuffIcon(nameplate, 1)
    end

    do -- control-skill (CC) highlight icons
      nameplate.cccontainer = CreateFrame("Frame", nil, nameplate)
      nameplate.cccontainer:SetFrameLevel(8)
      nameplate.cccontainer:Hide()
      nameplate.ccdebuffs = {}
      local ccmax = tonumber(C.nameplates.ccmax) or 4
      for i = 1, ccmax do
        nameplates.CreateCCIcon(nameplate, i)
      end
      nameplates.UpdateCCConfig(nameplate)
    end

    do -- combopoints
      local combopoints = { }
      for i = 1, 5 do
        combopoints[i] = CreateFrame("Frame", nil, nameplate)
        combopoints[i]:Hide()
        combopoints[i]:SetFrameLevel(8)
        combopoints[i].tex = combopoints[i]:CreateTexture("OVERLAY")
        combopoints[i].tex:SetAllPoints()

        if i < 3 then
          combopoints[i].tex:SetTexture(1, .3, .3, .75)
        elseif i < 4 then
          combopoints[i].tex:SetTexture(1, 1, .3, .75)
        else
          combopoints[i].tex:SetTexture(.3, 1, .3, .75)
        end
      end
      nameplate.combopoints = combopoints
    end

    do -- castbar
      local castbar = CreateFrame("StatusBar", nil, nameplate.health)
      castbar:Hide()

      castbar:SetScript("OnShow", function()
        if C.nameplates.debuffs["position"] == "BOTTOM" then
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this, "BOTTOMLEFT", 0, -4)
        end
      end)

      castbar:SetScript("OnHide", function()
        if C.nameplates.debuffs["position"] == "BOTTOM" then
          nameplate.debuffs[1]:SetPoint("TOPLEFT", this:GetParent(), "BOTTOMLEFT", 0, -4)
        end
      end)

      castbar.text = castbar:CreateFontString("Status", "DIALOG", "GameFontNormal")
      castbar.text:SetPoint("RIGHT", castbar, "LEFT", -4, 0)
      castbar.text:SetNonSpaceWrap(false)
      castbar.text:SetTextColor(1,1,1,.5)

      castbar.spell = castbar:CreateFontString("Status", "DIALOG", "GameFontNormal")
      castbar.spell:SetPoint("CENTER", castbar, "CENTER")
      castbar.spell:SetNonSpaceWrap(false)
      castbar.spell:SetTextColor(1,1,1,1)

      castbar.icon = CreateFrame("Frame", nil, castbar)
      castbar.icon.tex = castbar.icon:CreateTexture(nil, "BORDER")
      castbar.icon.tex:SetAllPoints()

      nameplate.castbar = castbar
    end

    -- Stagger tick to spread updates across frames (0.05s apart per plate)
    nameplate.tick = GetTime() + mathmod(platecount, 10) * 0.05

    parent.nameplate = nameplate
    HookScript(parent, "OnShow", nameplates.OnShow)
    HookScript(parent, "OnHide", nameplates.OnHide)  -- 新增：管理可见血条表
    parent:SetScript("OnUpdate", nil)  -- Disable Blizzard's OnUpdate

    nameplates.OnConfigChange(parent)
    -- 固定位置姓名板复用 OnCreate 时，不触发 OnShow 的 GUID/可见表注册，
    -- 否则会污染 IsTargetNamePlateVisible 的判定（把自身误判为目标姓名板可见）。
    if not parent._pfFixedPlate then
      nameplates.OnShow(parent)
    end
  end

  nameplates.OnHide = function(frame)
    frame = frame or this
    local plate = frame
    -- 固定位置姓名板不进入可见/隐藏表，跳过
    if frame and frame._pfFixedPlate then return end
    if plate and visiblePlates[plate] then
      visiblePlates[plate] = nil
      hiddenPlates[plate] = true
    end
    -- 清理缓存已在 OnUpdate 隐藏分支处理，此处也可补充
  end

  nameplates.OnConfigChange = function(frame)
    local parent = frame
    local nameplate = frame.nameplate

    -- 刷新黑名单缓存
    RefreshBlacklistCache()																  
    local font = C.nameplates.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
    local font_style = C.nameplates.name.fontstyle

    -- 固定姓名板：使用独立的宽度/高度配置（-1 或空值表示跟随目标姓名板尺寸）
    local is_fixedplate = parent and parent._pfFixedPlate
    local fpw = C.nameplates.width
    local fph = C.nameplates.heighthealth
    if is_fixedplate then
      local fw = tonumber(C.nameplates.fixedposition_width)
      local fh = tonumber(C.nameplates.fixedposition_height)
      fpw = (fw and fw >= 0) and fw or tonumber(C.nameplates.width)
      fph = (fh and fh >= 0) and fh or tonumber(C.nameplates.heighthealth)
    end
    local glowr, glowg, glowb, glowa = GetStringColor(C.nameplates.glowcolor)
    local hlr, hlg, hlb, hla = GetStringColor(C.nameplates.highlightcolor)
    local hptexture = pfUI.media[C.nameplates.healthtexture]
    local rawborder, default_border = GetBorderSize("nameplates")

    local plate_width = fpw + 50
    local plate_height = fph + font_size + 5
    local plate_height_cast = fph + font_size + 5 + C.nameplates.heightcast + 5
    local combo_size = 5

    local width = tonumber(fpw)
    local debuffsize = tonumber(C.nameplates.debuffsize)
    local healthoffset = tonumber(C.nameplates.health.offset)
    local orientation = C.nameplates.verticalhealth == "1" and "VERTICAL" or "HORIZONTAL"

    local c = combatstate -- load combat state colors
    c.CASTING.r, c.CASTING.g, c.CASTING.b, c.CASTING.a = GetStringColor(C.nameplates.combatcasting)
    c.THREAT.r, c.THREAT.g, c.THREAT.b, c.THREAT.a = GetStringColor(C.nameplates.combatthreat)
    c.NOTHREAT.r, c.NOTHREAT.g, c.NOTHREAT.b, c.NOTHREAT.a = GetStringColor(C.nameplates.combatnothreat)
    c.OFFTANK.r, c.OFFTANK.g, c.OFFTANK.b, c.OFFTANK.a = GetStringColor(C.nameplates.combatofftank)
    c.STUN.r, c.STUN.g, c.STUN.b, c.STUN.a = GetStringColor(C.nameplates.combatstun)

    RebuildOfftanks()

    nameplate:SetWidth(plate_width)
    nameplate:SetHeight(plate_height)
    nameplate:SetPoint("TOP", parent, "TOP", 0, 0)

    nameplate.name:SetFont(font, font_size, font_style)

    nameplate.health:SetOrientation(orientation)
    nameplate.health:SetPoint("TOP", nameplate.name, "BOTTOM", 0, healthoffset)
    nameplate.health:SetStatusBarTexture(hptexture)
    nameplate.health:SetWidth(fpw)
    nameplate.health:SetHeight(fph)
    nameplate.health.hlr, nameplate.health.hlg, nameplate.health.hlb, nameplate.health.hla = hlr, hlg, hlb, hla

    CreateBackdrop(nameplate.health, default_border)

    nameplate.health.text:SetFont(font, font_size - 2, "OUTLINE")
    nameplate.health.text:SetJustifyH(C.nameplates.hptextpos)

    nameplate.guild:SetFont(font, font_size, font_style)

    nameplate.glow:SetWidth(fpw + 60)
    nameplate.glow:SetHeight(fph + 30)
    nameplate.glow:SetVertexColor(glowr, glowg, glowb, glowa)

    nameplate.raidicon:ClearAllPoints()
    -- 团队图标位置接入 GUI 设置（raidiconpos 此前是死设置：只有 GUI 写入、无人读取）。
    -- 智能锚点：「位置」= 图标悬浮在血条对应边的外侧（顶部=悬在血条上方，
    -- 左上=悬在左上角外），避免同点锚定（TOP/TOP）时图标从锚线向下垂、
    -- 叠加默认负偏移后看起来"上下颠倒"的方向错觉。
    -- 偏移保持 WoW 惯例：offy 正=上，offx 正=右，从外侧停靠位再微调。
    -- 配置值来自 GUI 文本框（字符串），显式 tonumber 兜底。
    local pos = C.nameplates.raidiconpos or "CENTER"
    local opposite = {
      TOP = "BOTTOM", BOTTOM = "TOP", LEFT = "RIGHT", RIGHT = "LEFT",
      TOPLEFT = "BOTTOMRIGHT", TOPRIGHT = "BOTTOMLEFT",
      BOTTOMLEFT = "TOPRIGHT", BOTTOMRIGHT = "TOPLEFT", CENTER = "CENTER",
    }
    nameplate.raidicon:SetPoint(opposite[pos] or "CENTER", nameplate.health, pos,
      tonumber(C.nameplates.raidiconoffx) or 0, tonumber(C.nameplates.raidiconoffy) or 0)
    nameplate.level:SetFont(font, font_size, font_style)
    nameplate.raidicon:SetWidth(tonumber(C.nameplates.raidiconsize) or 16)
    nameplate.raidicon:SetHeight(tonumber(C.nameplates.raidiconsize) or 16)

    if nameplate.targetname then
        nameplate.targetname:SetFont(font, font_size, font_style)
    end	
   if nameplate.hatred then
       nameplate.hatred:SetFont(font, font_size, font_style)
   end
    for i=1,16 do
      UpdateDebuffConfig(nameplate, i)
    end

    -- 确保 CC 图标池随 ccmax 变化补全（运行时调大上限时动态创建缺失图标）
    if nameplate.ccdebuffs then
      local ccmax = tonumber(C.nameplates.ccmax) or 4
      for i = 1, ccmax do
        if not nameplate.ccdebuffs[i] then
          nameplates.CreateCCIcon(nameplate, i)
        end
      end
    end
    nameplates.UpdateCCConfig(nameplate)

    for i=1,5 do
      nameplate.combopoints[i]:SetWidth(combo_size)
      nameplate.combopoints[i]:SetHeight(combo_size)
      nameplate.combopoints[i]:SetPoint("TOPRIGHT", nameplate.health, "BOTTOMRIGHT", -(i-1)*(combo_size+default_border*3), -default_border*3)
      CreateBackdrop(nameplate.combopoints[i], default_border)
    end

    nameplate.castbar:SetPoint("TOPLEFT", nameplate.health, "BOTTOMLEFT", 0, -default_border*3)
    nameplate.castbar:SetPoint("TOPRIGHT", nameplate.health, "BOTTOMRIGHT", 0, -default_border*3)
    nameplate.castbar:SetHeight(C.nameplates.heightcast)
    -- Use the same castbar texture and color as the unit frame castbar (castbar.lua)
    local cbtexture = pfUI.media[C.appearance.castbar.texture]
    nameplate.castbar:SetStatusBarTexture(cbtexture or hptexture)
    local cbr, cbg, cbb, cba = strsplit(",", C.appearance.castbar.castbarcolor)
    nameplate.castbar:SetStatusBarColor(cbr, cbg, cbb, cba)
    -- reset endTime cache so color/texture refresh takes effect on next cast
    nameplate.castbar.lastEndTime = nil
    CreateBackdrop(nameplate.castbar, default_border)

    nameplate.castbar.text:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.spell:SetFont(font, font_size, "OUTLINE")
    nameplate.castbar.icon:SetPoint("BOTTOMLEFT", nameplate.castbar, "BOTTOMRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetPoint("TOPLEFT", nameplate.health, "TOPRIGHT", default_border*3, 0)
    nameplate.castbar.icon:SetWidth(C.nameplates.heightcast + default_border*3 + fph)
    CreateBackdrop(nameplate.castbar.icon, default_border)

    nameplates:OnDataChanged(nameplate)
  end

  nameplates.OnValueChanged = function()
    local plate = this:GetParent().nameplate
    if plate and plate.health then
      plate.health:SetMinMaxValues(plate.original.healthbar:GetMinMaxValues())
      plate.health:SetValue(plate.original.healthbar:GetValue())
    end
  end

  nameplates.OnDataChanged = function(self, plate)
    local now = frameState.now  -- 使用全局缓存的时间
    local visible = plate:IsVisible()
    local hp = plate.original.healthbar:GetValue()
    local hpmin, hpmax = plate.original.healthbar:GetMinMaxValues()
    local name = plate.original.name:GetText()
    local level = plate.original.level:IsShown() and plate.original.level:GetObjectType() == "FontString" and tonumber(plate.original.level:GetText()) or "??"
    local class, ulevel, elite, player, guild = GetUnitData(name, true)
    
    -- Use database level ONLY if current level is ?? (fixes ?? after reload, but doesn't override visible levels)
    local levelFromDB = false
    if level == "??" and ulevel and ulevel > 0 then
      level = ulevel
      levelFromDB = true
    end
    
    -- ⛔ 客户端复用 NamePlate frame：上一任单位是目标时 istarget 残留为 true，
    --    换了单位后的第一次重绘会把旧目标态（高亮/发光）画给新单位，下一拍又被
    --    OnUpdate 纠正 = "新板顶着目标样式出现又瞬间变回普通"（2026-10-12）。
    --    名字变了就先清目标态；同名不同单位的情况由 OnShow 的 GUID 对比兜底。
    --    ⚠️ 必须放在读取 plate.istarget 之前，否则本次重绘仍用旧值。
    if plate.cache.name and plate.cache.name ~= name then
      plate.istarget = nil
      plate.cache.target = nil
    end

    local target = plate.istarget
    local mouseover = UnitExists("mouseover") and plate.original.glow:IsShown() or nil
    local unitstr = target and "target" or mouseover and "mouseover" or nil
    local red, green, blue = plate.original.healthbar:GetStatusBarColor()
    local unittype = GetUnitType(red, green, blue) or "ENEMY_NPC"
    local font_size = C.nameplates.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size

    -- use unit guid as unitstr if possible
    if not unitstr then
      unitstr = plate.parent:GetName(1)
    end

    -- ========== 新增：黑名单提前检查（防止后续debuff显示） ==========
    local nameLower = name and strlower(name) or nil
    local isTarget = (UnitName("target") == name)
    if cfg.hideblacklist and name and blacklistUnits[nameLower] and not isTarget then
      -- 黑名单单位且不是目标：隐藏所有元素并立即返回
      pfUI_HidePlateElements(plate)
      return
    end						 
    -- ignore players with npc names if plate level is lower than player level
    if ulevel and ulevel > (level == "??" and -1 or level) then player = nil end

    -- cache name and reset unittype on change
    if plate.cache.name ~= name then
      plate.cache.name = name
      plate.cache.player = nil
      plate.cdCache = nil  -- new unit, reset spell-keyed timer cache
    end

    -- read and cache unittype
    if plate.cache.player then
      -- overwrite unittype from cache if existing
      player = plate.cache.player == "PLAYER" and true or nil
    elseif unitstr then
      -- read unit type while unitstr is set
      plate.cache.player = UnitIsPlayer(unitstr) and "PLAYER" or "NPC"
    end

    if player and unittype == "ENEMY_NPC" then unittype = "ENEMY_PLAYER" end
    if player and unittype == "FRIENDLY_NPC" then unittype = "FRIENDLY_PLAYER" end
    elite = plate.original.levelicon:IsShown() and not player and "boss" or elite
    if not class then plate.wait_for_scan = true end

    -- skip data updates on invisible frames
    if not visible then return end

    -- target event sometimes fires too quickly, where nameplate identifiers are not
    -- yet updated. So while being inside this event, we cannot trust the unitstr.
    if event == "PLAYER_TARGET_CHANGED" then unitstr = nil end

    -- remove unitstr on unit name mismatch
    if unitstr and UnitName(unitstr) ~= name then unitstr = nil end

    -- use mobhealth values if addon is running
    if (MobHealth3 or MobHealthFrame) and target and name == UnitName('target') and MobHealth_GetTargetCurHP() then
      hp = MobHealth_GetTargetCurHP() > 0 and MobHealth_GetTargetCurHP() or hp
      hpmax = MobHealth_GetTargetMaxHP() > 0 and MobHealth_GetTargetMaxHP() or hpmax
    end

    -- always make sure to keep plate visible
    plate:Show()

    if target and cfg.targetglow then
      plate.glow:Show() else plate.glow:Hide()
    end

    -- 自定义 NPC 颜色：按名字命中则覆盖，优先级
    -- 战斗状态覆盖 > 自定义NPC > 目标高亮 > 单位类型颜色
    local npccolor = nameLower and unitcolors._custom[nameLower] or nil

    -- target indicator
    if cfg.outcombatstate then
      local guid = plate.parent:GetName(1) or ""

      -- determine color based on combat state
      local color = GetCombatStateColor(guid)
      if not color then color = combatstate.NONE end

      -- set border color
      plate.health.backdrop:SetBackdropBorderColor(color.r, color.g, color.b, color.a)
    elseif npccolor then
      plate.health.backdrop:SetBackdropBorderColor(npccolor[1], npccolor[2], npccolor[3], npccolor[4])
    elseif target and cfg.targethighlight then
      plate.health.backdrop:SetBackdropBorderColor(plate.health.hlr, plate.health.hlg, plate.health.hlb, plate.health.hla)
    elseif C.nameplates.outfriendlynpc == "1" and unittype == "FRIENDLY_NPC" then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outfriendly == "1" and unittype == "FRIENDLY_PLAYER" then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outneutral == "1" and strfind(unittype, "NEUTRAL") then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    elseif C.nameplates.outenemy == "1" and strfind(unittype, "ENEMY") then
      plate.health.backdrop:SetBackdropBorderColor(unpack(unitcolors[unittype]))
    else
      plate.health.backdrop:SetBackdropBorderColor(er,eg,eb,ea)
    end

    -- hide frames according to the configuration
    local TotemIcon = TotemPlate(name)

    if TotemIcon then
      -- create totem icon
      plate.totem.icon:SetTexture("Interface\\Icons\\" .. TotemIcon)

      plate.glow:Hide()
      plate.level:Hide()
      plate.name:Hide()
      plate.health:Hide()
      plate.guild:Hide()
      plate.totem:Show()
    elseif HidePlate(unittype, name, (hpmax-hp == hpmin), target) then
      plate.level:SetPoint("RIGHT", plate.name, "LEFT", -3, 0)
      plate.name:SetParent(plate)
      plate.guild:SetPoint("BOTTOM", plate.name, "BOTTOM", -2, -(font_size + 2))

      plate.level:Show()
      plate.name:Show()
      plate.health:Hide()
      if guild and C.nameplates.showguildname == "1" then
        plate.glow:SetPoint("CENTER", plate.name, "CENTER", 0, -(font_size / 2) - 2)
      else
        plate.glow:SetPoint("CENTER", plate.name, "CENTER", 0, 0)
      end
      plate.totem:Hide()
    else
      plate.level:SetPoint("RIGHT", plate.health, "LEFT", -5, 0)
      plate.name:SetParent(plate.health)
      plate.guild:SetPoint("BOTTOM", plate.health, "BOTTOM", 0, -(font_size + 4))

      plate.level:Show()
      plate.name:Show()
      plate.health:Show()
      plate.glow:SetPoint("CENTER", plate.health, "CENTER", 0, 0)
      plate.totem:Hide()
    end

    plate.name:SetText(GetNameString(name))
    plate.level:SetText(string.format("%s%s", level, (elitestrings[elite] or "")))
    
    -- Set level color from GetDifficultyColor when using DB level
    if levelFromDB and type(level) == "number" then
      local color = GetDifficultyColor(level)
      plate.level:SetTextColor(color.r + 0.3, color.g + 0.3, color.b + 0.3, 1)
    end

    if guild and C.nameplates.showguildname == "1" then
      plate.guild:SetText(guild)
      if guild == GetGuildInfo("player") then
        plate.guild:SetTextColor(0, 0.9, 0, 1)
      else
        plate.guild:SetTextColor(0.8, 0.8, 0.8, 1)
      end
      plate.guild:Show()
    else
      plate.guild:Hide()
    end

    -- PERF: Only update bar + HP text when values actually changed
    if plate.cache.hp ~= hp or plate.cache.hpmax ~= hpmax then
      plate.cache.hp = hp
      plate.cache.hpmax = hpmax
      plate.health:SetMinMaxValues(hpmin, hpmax)
      plate.health:SetValue(hp)

      if cfg.showhp then
        local rhp, rhpmax, estimated
        
        -- Try Nampower first for real HP values via GUID
        local guid = plate.parent:GetName(1)
        if guid and GetUnitField then
          local npHp = GetUnitField(guid, "health")
          local npMaxHp = GetUnitField(guid, "maxHealth")
          if npHp and npHp > 0 and npMaxHp and npMaxHp > 0 then
            rhp, rhpmax = npHp, npMaxHp
          end
        end
        
        -- Fallback to existing methods
        if not rhp then
          if hpmax > 100 or (round(hpmax/100*hp) ~= hp) then
            rhp, rhpmax = hp, hpmax
          elseif pfUI.libhealth and pfUI.libhealth.enabled then
            rhp, rhpmax, estimated = pfUI.libhealth:GetUnitHealthByName(name,level,tonumber(hp),tonumber(hpmax))
          end
        end

        local setting = cfg.hptextformat
        local hasdata = ( rhp and rhpmax ) or estimated or hpmax > 100 or (round(hpmax/100*hp) ~= hp)

        if setting == "curperc" and hasdata and rhp then
          plate.health.text:SetText(string.format("%s | %s%%", Abbreviate(rhp), ceil(hp/hpmax*100)))
        elseif setting == "cur" and hasdata and rhp then
          plate.health.text:SetText(string.format("%s", Abbreviate(rhp)))
        elseif setting == "curmax" and hasdata and rhp then
          plate.health.text:SetText(string.format("%s - %s", Abbreviate(rhp), Abbreviate(rhpmax)))
        elseif setting == "curmaxs" and hasdata and rhp then
          plate.health.text:SetText(string.format("%s / %s", Abbreviate(rhp), Abbreviate(rhpmax)))
        elseif setting == "curmaxperc" and hasdata and rhp then
          plate.health.text:SetText(string.format("%s - %s | %s%%", Abbreviate(rhp), Abbreviate(rhpmax), ceil(hp/hpmax*100)))
        elseif setting == "curmaxpercs" and hasdata and rhp then
          plate.health.text:SetText(string.format("%s / %s | %s%%", Abbreviate(rhp), Abbreviate(rhpmax), ceil(hp/hpmax*100)))
        elseif setting == "deficit" and rhp then
          plate.health.text:SetText(string.format("-%s" .. (hasdata and "" or "%%"), Abbreviate(rhpmax - rhp)))
        else -- "percent" as fallback
          plate.health.text:SetText(string.format("%s%%", ceil(hp/hpmax*100)))
        end
      else
        plate.health.text:SetText()
      end
    end -- hp cache gate

    local r, g, b, a = unpack(unitcolors[unittype])

    -- 自定义 NPC 颜色优先于职业色/单位类型色（战斗状态覆盖仍在其上，见下方 barcombatstate）
    if npccolor then
      r, g, b, a = npccolor[1], npccolor[2], npccolor[3], npccolor[4]
    elseif unittype == "ENEMY_PLAYER" and C.nameplates["enemyclassc"] == "1" and class and RAID_CLASS_COLORS[class] then
      r, g, b, a = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b, 1
    elseif unittype == "FRIENDLY_PLAYER" and C.nameplates["friendclassc"] == "1" and class and RAID_CLASS_COLORS[class] then
      r, g, b, a = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b, 1
    end

    if unitstr and UnitIsTapped(unitstr) and not UnitIsTappedByPlayer(unitstr) then
      r, g, b, a = .5, .5, .5, .8
    end

    if cfg.barcombatstate then
      local guid = plate.parent:GetName(1) or ""
      local color = GetCombatStateColor(guid)

      if color then
        r, g, b, a = color.r, color.g, color.b, color.a
      end
    end

    if r ~= plate.cache.r or g ~= plate.cache.g or b ~= plate.cache.b then
      plate.health:SetStatusBarColor(r, g, b, a)
      plate.cache.r, plate.cache.g, plate.cache.b = r, g, b
    end

    if r + g + b ~= plate.cache.namecolor and unittype == "FRIENDLY_PLAYER" and C.nameplates["friendclassnamec"] == "1" and class and RAID_CLASS_COLORS[class] then
      plate.name:SetTextColor(r, g, b, a)
      plate.cache.namecolor = r + g + b
    end

    -- update combopoints
    for i=1, 5 do plate.combopoints[i]:Hide() end
    if target and C.nameplates.cpdisplay == "1" then
      for i=1, GetComboPoints("target") do plate.combopoints[i]:Show() end
    end

    -- 新增：目标显示逻辑与仇恨显示（独立控制）
    local showTargetName = C.nameplates.showtargetname == "1"
    local showHatred = cfg.showhatred

    -- 先处理仇恨百分比
    if showHatred and plate.hatred then
      local guid = plate.cachedGuid
      if guid and not UnitIsUnit(guid, "player") then
        local perc = GetThreatPercent(guid)
        if perc and perc > 0 then
          local color
          if perc > 80 then
            color = "|cFFFF0000"
          elseif perc > 60 then
            color = "|cFFFF7D0A"
          else
            color = "|cFFABD473"
          end
          local displayNum = tonumber(perc) or 0
          plate.hatred:SetText(color .. "(" .. string.format("%.0f", displayNum) .. "%)")
          
          -- 动态调整锚点
          plate.hatred:ClearAllPoints()
          if showTargetName and plate.targetname and plate.targetname:IsShown() then
            plate.hatred:SetPoint("LEFT", plate.targetname, "RIGHT", 5, 0)
          else
            plate.hatred:SetPoint("LEFT", plate.name, "RIGHT", 10, 0)
          end
          plate.hatred:Show()
        else
          plate.hatred:Hide()
        end
      else
        plate.hatred:Hide()
      end
    elseif plate.hatred then
      plate.hatred:Hide()
    end

    -- 再处理目标姓名显示
    if showTargetName and plate.targetname and unitstr and not UnitIsUnit(unitstr, "player") then
      local targetUnit = unitstr .. "target"
      local targetName = UnitName(targetUnit)
      if targetName then
        -- 缓存目标 GUID 和职业（与之前相同）
        if GetUnitGUID then
          local targetGUID = GetUnitGUID(targetUnit)
          if targetGUID ~= plate.cachedTargetGUID then
            plate.cachedTargetGUID = targetGUID
            plate.cachedTargetClass = select(2, UnitClass(targetUnit))
          end
        end
        if UnitIsUnit(targetUnit, "player") then
          plate.targetname:SetText(">> 你")
          plate.targetname:SetTextColor(1, 0.2, 0.2, 0.9)
        else
          plate.targetname:SetText(">> " .. targetName)
          local class = plate.cachedTargetClass
          if class and RAID_CLASS_COLORS[class] then
            local color = RAID_CLASS_COLORS[class]
            plate.targetname:SetTextColor(color.r, color.g, color.b, 0.9)
          else
            plate.targetname:SetTextColor(1, 1, 0.5, 0.9)
          end
        end
        plate.targetname:Show()
      else
        plate.targetname:Hide()
      end
    elseif plate.targetname then
      plate.targetname:Hide()
    end

					  
    -- update debuffs & control-skills (CC)
    local index = 1
    -- CC 图标计数器存于 plate 表（不新增 OnDataChanged 的 upvalue，规避 1.12 单函数 32 upvalue 上限）
    plate._ccidx = 1

    local isFriendly = unittype == "FRIENDLY_PLAYER" or unittype == "FRIENDLY_NPC"
    local showDebuffsForType = cfg.showdebuffs and (isFriendly and cfg.showdebuffs_friendly or (not isFriendly and cfg.showdebuffs_hostile))
    -- 仅目标显示 debuff：非目标板不显示普通 debuff（CC 控制技能不受影响）
    if showDebuffsForType and cfg.showdebuffs_targetonly and not isTarget then
      showDebuffsForType = false
    end
    -- 控制技能独立于普通 debuff 开关：只要启用 CC 就抓取 debuff 数据
    if showDebuffsForType or cfg.ccenabled then
      -- 优化：缓存 verify 字符串
      if name ~= plate.cachedVerifyName or level ~= plate.cachedVerifyLevel then
        plate.cachedVerifyName = name
        plate.cachedVerifyLevel = level
        plate.cachedVerify = (name or "") .. ":" .. (level or "")
      end
      local verify = plate.cachedVerify

      -- update cached debuffs
      if C.nameplates["guessdebuffs"] == "1" and unitstr then
        -- 传递 ownOnly 标志
        plate:CacheDebuffs(unitstr, verify, cfg.selfdebuff)
      end

      -- update all debuff icons
      local debuffCount = 0
      -- 清空缓冲
      for i = 1, 16 do debuffDisplayBuf[i].effect = nil end

      if unitstr and libdebuff then
        if cfg.selfdebuff and libdebuff.UnitOwnDebuff then
          -- 仅自身 debuff：使用传统循环调用 UnitOwnDebuff
          for i = 1, 16 do
            local effect, rank, texture, stacks, dtype, duration, timeleft = libdebuff:UnitOwnDebuff(unitstr, i)
            if effect and texture then
              debuffCount = debuffCount + 1
              local b = debuffDisplayBuf[debuffCount]
              b.effect, b.texture, b.stacks, b.dtype, b.duration, b.timeleft = effect, texture, stacks, dtype, duration, timeleft
              b.effectLower = effect and strlower(effect)
            end
          end
        elseif libdebuff.IterDebuffs and GetUnitGUID then
          -- 高效迭代（所有 debuff）
          _iterDebuffCount = 0
          libdebuff:IterDebuffs(unitstr, iterDebuffCallback)
          debuffCount = _iterDebuffCount
        else
          -- 回退到 UnitDebuff 循环
          for i = 1, 16 do
            local effect, rank, texture, stacks, dtype, duration, timeleft = libdebuff:UnitDebuff(unitstr, i)
            if effect then
              debuffCount = debuffCount + 1
              local b = debuffDisplayBuf[debuffCount]
              b.effect, b.texture, b.stacks, b.dtype, b.duration, b.timeleft = effect, texture, stacks, dtype, duration, timeleft
              b.effectLower = effect and strlower(effect)
            end
          end
        end
      elseif plate.verify == verify then
        -- 使用缓存的 debuff（由 CacheDebuffs 填充）
        for i = 1, 16 do
          local effect, rank, texture, stacks, dtype, duration, timeleft = plate:UnitDebuff(i, now)
          if effect then
            debuffCount = debuffCount + 1
            local b = debuffDisplayBuf[debuffCount]
            b.effect, b.texture, b.stacks, b.dtype, b.duration, b.timeleft = effect, texture, stacks, dtype, duration, timeleft
            b.effectLower = effect and strlower(effect)
          end
        end
      end

      -- 遍历显示 debuff / 控制技能(CC) 图标
      -- PERF: 按槽位签名缓存（懒创建，挂 plate 字段上 —— OnDataChanged 已满
      -- 32 upvalue 上限，不能再引用新的文件级 local）。SetTexture/SetText/
      -- SetTexCoord 即使参数相同也会置脏重排，多板多 debuff 时是最大的 UI
      -- churn；内容没变就整段跳过。隐藏的图标保留旧纹理，重显同纹理时跳过
      -- SetTexture 也是安全的（客户端保留了纹理状态）。
      local showstacks = C.nameplates.debuffs["showstacks"] == "1"
      local debuffSigTex = plate.debuffSigTex
      if not debuffSigTex then debuffSigTex = {}; plate.debuffSigTex = debuffSigTex end
      local debuffSigStacks = plate.debuffSigStacks
      if not debuffSigStacks then debuffSigStacks = {}; plate.debuffSigStacks = debuffSigStacks end
      local ccSigTex = plate.ccSigTex
      if not ccSigTex then ccSigTex = {}; plate.ccSigTex = ccSigTex end
      for i = 1, debuffCount do
        local b = debuffDisplayBuf[i]
        local effect, texture, stacks, dtype, duration, timeleft = b.effect, b.texture, b.stacks, b.dtype, b.duration, b.timeleft
        if effect and texture then
          -- 控制技能：从普通 debuff 抽出，单独显示在姓名板顶部（不受普通 debuff 过滤影响）
          -- 注意：判定在此内联，且本分支不引用 nameplates —— OnDataChanged 已用满 upvalue 上限，
          -- 新增对 nameplates 的 upvalue 引用会令整文件编译失败、姓名板回退原版。
          local isCC = nil
          if cfg.ccenabled then
            local el = b.effectLower
            -- O(1) 查表：内置 local spellIds + 用户自定义 ccfilter（全局函数调用不占 upvalue）
            if pfUI_IsCCSpell(el) or cfg.ccspells[el] then isCC = true end
          end
          if cfg.ccenabled and isCC and plate._ccidx <= cfg.ccmax then
            local cc = plate.ccdebuffs[plate._ccidx]
            if cc then
              cc:Show()
              if ccSigTex[plate._ccidx] ~= texture then
                cc.icon:SetTexture(texture)
                ccSigTex[plate._ccidx] = texture
              end

              if duration and timeleft and cfg.cctimers then
                plate.ccCache = plate.ccCache or {}
                local newStart = now + timeleft - duration
                local slotCache = plate.ccCache[plate._ccidx]
                local cachedStart = slotCache and slotCache.effect == effect and slotCache.start
                local cd = cc.cd
                cd:Show()
                if not cachedStart or math.abs(cachedStart - newStart) > 0.5 then
                  if not cd.configCached or cd.cachedAnim ~= cfg.debuffanim or cd.cachedText ~= cfg.debufftext then
                    cd.pfCooldownStyleAnimation = cfg.debuffanim
                    cd.pfCooldownStyleText = cfg.debufftext
                    cd:SetAlpha(cfg.debuffanim == 1 and 1 or 0)
                    cd.cachedAnim = cfg.debuffanim
                    cd.cachedText = cfg.debufftext
                    cd.configCached = true
                  end
                  CooldownFrame_SetTimer(cd, newStart, duration, 1)
                  plate.ccCache[plate._ccidx] = plate.ccCache[plate._ccidx] or {}
                  plate.ccCache[plate._ccidx].effect = effect
                  plate.ccCache[plate._ccidx].start = newStart
                end
              elseif cc.cd then
                cc.cd:Hide()
              end
              plate._ccidx = plate._ccidx + 1
            end
          elseif showDebuffsForType and DebuffFilter(effect, b.effectLower) then
            -- 普通 debuff 正常显示
            if not plate.debuffs[index] then
              CreateDebuffIcon(plate, index)
              UpdateDebuffConfig(plate, index)
            end
            plate.debuffs[index]:Show()
            -- PERF: 纹理签名比对（GetSpellIcon 缓存返回同一字符串实例，
            -- 比较是指针级的，几乎零成本）
            if debuffSigTex[index] ~= texture then
              plate.debuffs[index].icon:SetTexture(texture)
              debuffSigTex[index] = texture
            end

            local stacksShown = (showstacks and stacks and stacks > 1) and stacks or nil
            if debuffSigStacks[index] ~= stacksShown then
              debuffSigStacks[index] = stacksShown
              local stacksText = plate.debuffs[index].stacks
              if stacksShown then
                stacksText:SetText(stacksShown)
                stacksText:Show()
              else
                stacksText:Hide()
              end
            end

            if duration and timeleft and cfg.debufftimers then
              plate.cdCache = plate.cdCache or {}
              local newStart = now + timeleft - duration
              local slotCache = plate.cdCache[index]
              local cachedStart = slotCache and slotCache.effect == effect and slotCache.start
              local cd = plate.debuffs[index].cd
              cd:Show()
              if not cachedStart or abs(cachedStart - newStart) > 0.5 then
                if not cd.configCached or cd.cachedAnim ~= cfg.debuffanim or cd.cachedText ~= cfg.debufftext then
                  cd.pfCooldownStyleAnimation = cfg.debuffanim
                  cd.pfCooldownStyleText = cfg.debufftext
                  cd:SetAlpha(cfg.debuffanim == 1 and 1 or 0)
                  cd.cachedAnim = cfg.debuffanim
                  cd.cachedText = cfg.debufftext
                  cd.configCached = true
                end
                CooldownFrame_SetTimer(cd, newStart, duration, 1)
                plate.cdCache[index] = plate.cdCache[index] or {}
                plate.cdCache[index].effect = effect
                plate.cdCache[index].start = newStart
              end
            end
            index = index + 1
          end
        end
      end

      -- 控制技能容器：按显示数量设置宽度并居中
      if (plate._ccidx or 1) > 1 then
        local gap = 2
        plate.cccontainer:SetWidth((plate._ccidx - 1) * cfg.ccsize + (plate._ccidx - 2) * gap)
        plate.cccontainer:Show()
      else
        plate.cccontainer:Hide()
      end
    else
      plate.cccontainer:Hide()
    end

    -- hide remaining CC icons
    for i = (plate._ccidx or 1), (cfg.ccmax or 4) do
      if plate.ccdebuffs[i] then
        plate.ccdebuffs[i]:Hide()
      end
    end

    -- hide remaining debuffs
    for i = index, 16 do
      if plate.debuffs[i] then
        plate.debuffs[i]:Hide()
      end
    end
  end

  nameplates.OnShow = function(frame)
    local frame = frame or this
    local nameplate = frame.nameplate

    -- 固定位置姓名板不参与常规可见/ GUID 注册，否则会污染
    -- IsTargetNamePlateVisible 的判定（其 _guid 等于目标 GUID，会覆盖真实目标姓名板）。
    if frame._pfFixedPlate then return end

    -- ⛔ 客户端会复用同一块 NamePlate frame 显示不同单位。上一任单位是目标时
    --    （istarget=true、目标高亮/发光已画上），板隐藏后重新分配给别的单位，
    --    OnShow 里紧接着的 OnDataChanged 就会把旧目标态画给新单位，下一拍才被
    --    OnUpdate 纠正 —— 远距离目标刚进视野、板重新洗牌时最明显：新板顶着
    --    "目标样式"出现又瞬间变回普通（2026-10-12 用户实证）。
    --    GUID 变了就先清干净目标态再走 OnDataChanged；真目标板会由 OnUpdate
    --    的 GUID 等值路径在一两帧内重新标回目标，不会丢目标样式。
    local shownGuid = frame:GetName(1)
    if shownGuid and nameplate.cachedGuid and nameplate.cachedGuid ~= shownGuid then
      nameplate.istarget = nil
      nameplate.cache.target = nil
      if nameplate.glow then nameplate.glow:Hide() end
      if nameplate.health then
        nameplate.health.zoomed = nil
        nameplate.health.zoomTransition = nil
      end
    end
    -- 新板/重新显示的板：客户端还没把非目标板的透明度压下去（原始帧 alpha=1.0），
    -- 给 alpha 目标判据一个出生年龄门槛（见 OnUpdate 的 alphaEligible）
    nameplate.spawnT = GetTime()

    -- 管理可见血条表
    if hiddenPlates[frame] then
      hiddenPlates[frame] = nil
    end
    visiblePlates[frame] = true

    -- Register GUID when plate becomes visible
    local guid = frame:GetName(1)
    if guid then
      nameplate.cachedGuid = guid
      guidRegistry[guid] = frame
      -- notify libunitscan so it can cache unit data without mouseover
      if pfUI.api.libunitscan and pfUI.api.libunitscan.ScanGuid then
        local name = frame.nameplate.original.name:GetText()
        local npcFlags = GetUnitField and GetUnitField(guid, "npcFlags") or 0
        pfUI.api.libunitscan.ScanGuid(guid, name, npcFlags == 0)
      end
    end

    -- ========== 新增：黑名单检查，如果是目标则不隐藏 ==========
    local name = nameplate.original and nameplate.original.name:GetText()
    local nameLower = name and strlower(name) or nil
    local isTarget = frameState.hasTarget and UnitName("target") == name
    if cfg.hideblacklist and name and blacklistUnits[nameLower] and not isTarget then
      pfUI_HidePlateElements(nameplate)
      return  -- 如果是黑名单单位且不是目标，直接返回，不执行后续更新
    end
    nameplates:OnDataChanged(nameplate)
  end

  nameplates.OnUpdate = function(frame, state)
    local nameplate = frame.nameplate
    local now = state and state.now or GetTime()
    
    -- Blacklist hiding moved below the throttle block: it used to call
    -- GetText() + strlower() here, i.e. on every single frame of the 100 Hz
    -- scan loop, for every visible plate.
    -- Update GUID registry (lightweight, needed for event routing)
    local guid = frame:GetName(1)
    if guid and guid ~= nameplate.cachedGuid then
      if nameplate.cachedGuid and guidRegistry[nameplate.cachedGuid] == frame then
        guidRegistry[nameplate.cachedGuid] = nil
      end
      nameplate.cachedGuid = guid
      guidRegistry[guid] = frame
    end
    
    -- PERF: Intelligent throttling based on target/castbar status and plate count
    local targetGuid = state and state.targetGuid
    -- ⛔ alpha 兜底判据有出生年龄门槛：新建的板客户端还没把非目标透明度(0.6)
    --    压下去，原始帧 alpha 默认 1.0，头几帧会把刚出现的非目标板误判成目标板
    --    （目标样式闪一下又变回普通，远距离目标进视野、一批板同时新建时最明显）。
    --    真目标板走上面的 GUID 等值路径，不受此门槛影响。
    local alphaEligible = (now - (nameplate.spawnT or 0)) > 0.4
    local target = (targetGuid and nameplate.cachedGuid and targetGuid == nameplate.cachedGuid) or
                   (state and state.hasTarget and alphaEligible and frame:GetAlpha() >= 0.99) or nil
    -- Target plate castbar runs on its own dedicated frame (nameplates.castbarFrame).
    local isCastingNonTarget = not target and nameplate.castbar and nameplate.castbar:IsShown()
    if not isCastingNonTarget and not target and cfg.showcastbar and nameplate.cachedGuid then
      local castInfo = GetCastInfo(nameplate.cachedGuid)
      if castInfo and castInfo.spellID and castInfo.endTime and castInfo.endTime > now then
        isCastingNonTarget = true
      elseif pfGetCastInfo and nameplate.castUpdate then
        isCastingNonTarget = true
      end
    end

    -- hide castbar before throttle if no cast active
    if not isCastingNonTarget and not target then
      if nameplate.castbar.isShown then
        nameplate.castbar.isShown = nil
        nameplate.castbar.lastEndTime = nil
        nameplate.castbar:Hide()
      end
    end

    local throttle
    if target then
      throttle = pfUI.throttle:Get("nameplates_target")
    elseif visiblePlateCount > 20 then
      throttle = pfUI.throttle:Get("nameplates_mass")
    else
      throttle = pfUI.throttle:Get("nameplates")
    end

    -- Non-target plates with active castbar use the castbar throttle
    if isCastingNonTarget then
      local cbThrottle = pfUI.throttle:Get("nameplates_castbar")
      if cbThrottle < throttle then throttle = cbThrottle end
    end

    -- Check for pending event updates (these bypass throttle for immediate response)
    local hasEventUpdate = nameplate.eventcache or nameplate.auraUpdate or nameplate.castUpdate or nameplate.targetUpdate or nameplate.comboUpdate

    -- Event updates bypass throttle
    if not hasEventUpdate and (nameplate.lasttick or 0) + throttle > now then return end
    nameplate.lasttick = now
    
    -- =========================================================================
    -- EVERYTHING BELOW RUNS AT THROTTLED RATE (50 FPS target, 10 FPS others)
    -- =========================================================================
    
    local update
    local original = nameplate.original
    local name = original.name:GetText()
    local mouseover = state and state.hasMouseover and original.glow:IsShown() or nil

    -- Hide blacklisted units outright, unless they are the current target.
    -- This block used to sit above the throttle and paid for its own
    -- GetText() + strlower() on every frame; it now reuses the throttled
    -- name lookup just above.
    if cfg.hideblacklist and name and not target then
      if blacklistUnits[strlower(name)] then
        pfUI_HidePlateElements(nameplate)
        return
      end
    end

	  -- 添加任务怪提示
    if cfg.questicon and nameplate.cluster and pfUI.api and pfUI.api.IsQuestUnit and not nameplate.raidicon:IsShown() then
        local icon = pfUI.api.IsQuestUnit(name)
        if icon and icon ~= false then
            nameplate.cluster:SetTexture(icon)
            if nameplate.health:IsShown() then
              nameplate.cluster:Show()
            end
        else
            nameplate.cluster:SetTexture()
            nameplate.cluster:Hide()
        end
    elseif nameplate.cluster then
        nameplate.cluster:Hide()  
    end							
    -- trigger queued event update
    if hasEventUpdate then
      nameplates:OnDataChanged(nameplate)
      nameplate.eventcache = nil
      nameplate.auraUpdate = nil
      nameplate.castUpdate = nil
      nameplate.targetUpdate = nil
      nameplate.comboUpdate = nil
    end

    -- =========================================================================
    -- VANILLA OVERLAP/CLICKTHROUGH HANDLING
    -- =========================================================================
    if pfUI.client <= 11200 then
      local useOverlap = C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0"
      local clickable = C.nameplates["clickthrough"] ~= "1"

      if not clickable then
        frame:EnableMouse(false)
        nameplate:EnableMouse(false)
      else
        local plate = useOverlap and nameplate or frame
        plate:EnableMouse(clickable)
      end

      if C.nameplates["overlap"] == "1" then
        if frame:GetWidth() > 1 then
          frame:SetWidth(1)
          frame:SetHeight(1)
        end
      else
        if not nameplate.dwidth then
          nameplate.dwidth = floor(nameplate:GetWidth() * UIParent:GetScale())
        end

        if floor(frame:GetWidth()) ~= nameplate.dwidth then
          frame:SetWidth(nameplate:GetWidth() * UIParent:GetScale())
          frame:SetHeight(nameplate:GetHeight() * UIParent:GetScale())
        end
      end

      local mouseEnabled = nameplate:IsMouseEnabled()
      if C.nameplates["clickthrough"] == "0" and C.nameplates["overlap"] == "1" and SpellIsTargeting() == mouseEnabled then
        nameplate:EnableMouse(not mouseEnabled)
      end
    end

    -- Cache strata changes
    if nameplate.istarget ~= target then
      nameplate.target_strata = nil
    end

    if target and nameplate.target_strata ~= 1 then
      nameplate:SetFrameStrata("LOW")
      nameplate.target_strata = 1
    elseif not target and nameplate.target_strata ~= 0 then
      nameplate:SetFrameStrata("BACKGROUND")
      nameplate.target_strata = 0
    end

    nameplate.istarget = target

    -- Set non-target plate alpha
    local configAlpha = cfg.notargalpha or 0.5
    local desiredAlpha = (target or not state.hasTarget) and 1 or configAlpha

    if nameplate.cachedAlpha ~= desiredAlpha then
      nameplate:SetAlpha(desiredAlpha)
      nameplate.cachedAlpha = desiredAlpha
    end

    -- queue update on visual target update
    if nameplate.cache.target ~= target then
      nameplate.cache.target = target
      update = true
    end

    -- queue update on visual mouseover update
    if nameplate.cache.mouseover ~= mouseover then
      nameplate.cache.mouseover = mouseover
      update = true
    end

    -- trigger update when unit was found
    if nameplate.wait_for_scan and GetUnitData(name, true) then
      nameplate.wait_for_scan = nil
      update = true
    end

    -- trigger update when name color changed (includes combat state check)
    local r, g, b = original.name:GetTextColor()
    local inCombatWithPlayer = false
    if cfg.namefightcolor then
      local guid = nameplate.cachedGuid
      if guid then
        inCombatWithPlayer = UnitAffectingCombat(guid) and UnitAffectingCombat("player")
      end
    end
    
    if r + g + b ~= nameplate.cache.namecolor or (cfg.namefightcolor and nameplate.cache.inCombat ~= inCombatWithPlayer) then
      nameplate.cache.namecolor = r + g + b
      nameplate.cache.inCombat = inCombatWithPlayer

      if cfg.namefightcolor then
        if (r > .9 and g < .2 and b < .2) or inCombatWithPlayer then
          nameplate.name:SetTextColor(1,0.4,0.2,1)
        else
          nameplate.name:SetTextColor(r,g,b,1)
        end
      else
        nameplate.name:SetTextColor(1,1,1,1)
      end
      update = true
    end

    -- trigger update when level color changed
    local r, g, b = original.level:GetTextColor()
    r, g, b = r + .3, g + .3, b + .3
    if r + g + b ~= nameplate.cache.levelcolor then
      nameplate.cache.levelcolor = r + g + b
      nameplate.level:SetTextColor(r,g,b,1)
      update = true
    end

    -- PERF: scan for debuff timeouts using indexed access instead of pairs()
    if nameplate.debuffcache then
      for id = 1, 16 do
        local data = nameplate.debuffcache[id]
        if data and ( not data.stop or data.stop < now ) and not data.empty then
          data.empty = true
          update = true
        end
      end
    end

    -- use timer based updates
    if not nameplate.tick or nameplate.tick < now then
      update = true
    end

    -- run full updates if required
    if update then
      nameplates:OnDataChanged(nameplate)
      nameplate.tick = now + .5
    end

    -- Zoom animation
    if target and cfg.targetzoom then
      if not nameplate.health.zoomed then
        local zoomval = cfg.zoomval
        local wc = cfg.width * zoomval
        local hc = cfg.heighthealth * (zoomval * .9)
        nameplate.health.targetWidth = wc
        nameplate.health.targetHeight = hc
      end
      
      local w, h = nameplate.health:GetWidth(), nameplate.health:GetHeight()
      local wc, hc = nameplate.health.targetWidth, nameplate.health.targetHeight
      
      if wc and hc then
        if wc > w + 0.5 then
          nameplate.health:SetWidth(w*1.05)
          nameplate.health.zoomTransition = true
        elseif hc > h + 0.5 then
          nameplate.health:SetHeight(h*1.05)
          nameplate.health.zoomTransition = true
        else
          if nameplate.health.zoomTransition then
            nameplate.health:SetWidth(wc)
            nameplate.health:SetHeight(hc)
            nameplate.health.zoomTransition = nil
          end
          nameplate.health.zoomed = true
        end
      end
    elseif nameplate.health.zoomed or nameplate.health.zoomTransition then
      local w, h = nameplate.health:GetWidth(), nameplate.health:GetHeight()
      local wc = cfg.width
      local hc = cfg.heighthealth

      if w > wc + 0.5 then
        nameplate.health:SetWidth(w*.95)
      elseif h > hc + 0.5 then
        nameplate.health:SetHeight(h*0.95)
      else
        nameplate.health:SetWidth(wc)
        nameplate.health:SetHeight(hc)
        nameplate.health.zoomTransition = nil
        nameplate.health.zoomed = nil
        nameplate.health.targetWidth = nil
        nameplate.health.targetHeight = nil
      end
    end

    -- Target plate castbar is handled by nameplates.castbarFrame (dedicated OnUpdate)
    local isTargetPlate = target or nameplate.istarget or (nameplate.health and nameplate.health.zoomed)
    if cfg.showcastbar and not cfg.targetcastbar and not isTargetPlate then
      local cbThrottle = pfUI.throttle:Get("nameplates_castbar")
      if visiblePlateCount > 20 then
        local massThrottle = pfUI.throttle:Get("nameplates_mass")
        if massThrottle > cbThrottle then cbThrottle = massThrottle end
      end
      if (nameplate.castbar_tick or 0) + cbThrottle <= now then
        nameplate.castbar_tick = now
        nameplates.UpdateCastbar(nameplate, now)
      end
    elseif cfg.showcastbar and cfg.targetcastbar and not isTargetPlate then
      if nameplate.castbar.isShown then
        nameplate.castbar.isShown = nil
        nameplate.castbar.lastEndTime = nil
        nameplate.castbar:Hide()
      end
    elseif not cfg.showcastbar then
      if nameplate.castbar.isShown then
        nameplate.castbar.isShown = nil
        nameplate.castbar.lastEndTime = nil
        nameplate.castbar:Hide()
      end
    end
  end

  -- ============================================================================
  -- DEDICATED TARGET CASTBAR FRAME
  -- Runs on its own OnUpdate, decoupled from the central nameplate loop.
  -- ============================================================================

  -- Shared castbar update logic (used by both dedicated frame and central loop)
  nameplates.UpdateCastbar = function(nameplate, now)
    if not nameplate or not nameplate.castbar then return end
    local unitstr = nameplate.cachedGuid
    local castInfo = unitstr and GetCastInfo(unitstr)

    if castInfo and castInfo.spellID then
      if castInfo.startTime + castInfo.duration < now then
        wipe(castInfo)
        nameplate.castbar:Hide()
      elseif castInfo.event == "CAST" or castInfo.event == "FAIL" then
        wipe(castInfo)
        nameplate.castbar:Hide()
      else
        -- Only update min/max, color and icon once per cast (when endTime changes)
        local isChannel = castInfo.event == "CHANNEL"
        local duration = castInfo.endTime - castInfo.startTime
        if nameplate.castbar.lastEndTime ~= castInfo.endTime then
          nameplate.castbar.lastEndTime = castInfo.endTime
          -- Use relative 0..duration range (same as castbar.lua)
          nameplate.castbar:SetMinMaxValues(0, duration)
          nameplate.castbar:SetStatusBarColor(strsplit(",", C.appearance.castbar[(isChannel and "channelcolor" or "castbarcolor")]))
          if castInfo.icon then
            nameplate.castbar.icon.tex:SetTexture(castInfo.icon)
            nameplate.castbar.icon.tex:SetTexCoord(.1,.9,.1,.9)
          end
          if cfg.spellname then
            nameplate.castbar.spell:SetText(castInfo.spellName)
          else
            nameplate.castbar.spell:SetText("")
          end
        end
        local barValue
        if isChannel then
          barValue = castInfo.endTime - now
        else
          barValue = now - castInfo.startTime
        end
        barValue = barValue < 0 and 0 or barValue
        barValue = barValue > duration and duration or barValue
        nameplate.castbar:SetValue(barValue)
        local remaining = castInfo.endTime - now
        if C.unitframes.castbardecimals == "1" then
          nameplate.castbar.text:SetText(floor(remaining * 10) / 10)
        else
          nameplate.castbar.text:SetText(string.format("%.2f", remaining))
        end
        if not nameplate.castbar.isShown then nameplate.castbar.isShown = true; nameplate.castbar:Show() end
      end
    else
      -- libcast fallback (vanilla without Nampower)
      if unitstr and pfGetCastInfo then
        local cast, _, _, texture, startTime, endTime = pfGetCastInfo(unitstr)
        local channel
        if not cast then
          channel, _, _, texture, startTime, endTime = pfGetChannelInfo(unitstr)
        end
        if cast or channel then
          local effect = cast or channel
          local duration = endTime - startTime
          local max = duration / 1000
          local cur = now - startTime / 1000
          if channel then cur = max + startTime / 1000 - now end
          if cur < 0 then cur = 0 end
          if cur > max then cur = max end
          if nameplate.castbar.lastEndTime ~= endTime then
            nameplate.castbar.lastEndTime = endTime
            nameplate.castbar:SetMinMaxValues(0, max)
            nameplate.castbar:SetStatusBarColor(strsplit(",", C.appearance.castbar[(channel and "channelcolor" or "castbarcolor")]))
            if texture then
              nameplate.castbar.icon.tex:SetTexture(texture)
              nameplate.castbar.icon.tex:SetTexCoord(.1, .9, .1, .9)
            end
            if cfg.spellname then
              nameplate.castbar.spell:SetText(effect)
            else
              nameplate.castbar.spell:SetText("")
            end
          end
          nameplate.castbar:SetValue(cur)
          local remaining = channel and cur or (max - cur)
          if C.unitframes.castbardecimals == "1" then
            nameplate.castbar.text:SetText(floor(remaining * 10) / 10)
          else
            nameplate.castbar.text:SetText(string.format("%.2f", remaining))
          end
          if not nameplate.castbar.isShown then nameplate.castbar.isShown = true; nameplate.castbar:Show() end
        else
          nameplate.castbar.isShown = nil
          nameplate.castbar.lastEndTime = nil
          nameplate.castbar:Hide()
        end
      else
        nameplate.castbar.isShown = nil
        nameplate.castbar.lastEndTime = nil
        nameplate.castbar:Hide()
      end
    end
  end

  -- Dedicated frame that updates ONLY the target plate castbar.
  nameplates.castbarFrame = CreateFrame("Frame", nil, UIParent)
  nameplates.castbarFrame:SetScript("OnUpdate", function()
    if not cfg.showcastbar then return end
    local now = GetTime()
    local throttle = pfUI.throttle:Get("nameplates_castbar")
    if (this.tick or 0) > now then return end
    this.tick = now + throttle

    local targetGuid = UnitExists("target") and GetUnitGUID and GetUnitGUID("target")
    if not targetGuid then return end

    local frame = guidRegistry[targetGuid]
    if not frame or not frame.nameplate then return end

    nameplates.UpdateCastbar(frame.nameplate, now)
  end)

  -- ============================================================================
  -- FIXED POSITION TARGET NAMEPLATE
  -- 当目标的浮动姓名板不可见（离屏、被遮挡、超出姓名板距离或被配置隐藏）时，
  -- 在屏幕固定位置显示一个目标状态条，确保玩家始终掌握目标的状态。
  -- ============================================================================
  local target_fixed_plate = nil

  -- 检查目标的实际浮动姓名板当前是否正在渲染
  local function IsTargetNamePlateVisible()
    if not UnitExists("target") then return false end
    local guid = GetUnitGUID and GetUnitGUID("target")
    if guid and guidRegistry[guid] then
      local frame = guidRegistry[guid]
      if visiblePlates[frame] and frame:IsVisible() then
        return true
      end
    end
    return false
  end

  local function CreateTargetFixedPlate()
    -- 复刻普通姓名板：构造一个“伪暴雪姓名板”父框体，复用 nameplates.OnCreate 的
    -- 全部视觉构造逻辑（血条/名字/等级/glow/debuff/施法条/连击点等），
    -- 再用 original.* 数据源驱动它显示当前 target，从而与浮动姓名板完全一致。
    local fixed_frame = CreateFrame("Frame", "pfUITargetFixedPlate", UIParent)
    fixed_frame._pfFixedPlate = true
    fixed_frame:SetFrameStrata("HIGH")
    fixed_frame:SetFrameLevel(20)
    fixed_frame:EnableMouse(false)
    fixed_frame:Hide()

    -- 伪暴雪原始元素：供 OnCreate 的 GetChildren/GetRegions 逻辑读取并Disable。
    -- 这些对象只作为数据源，真正的可视为 nameplate.health / nameplate.name 等。
    local fakeHealth = CreateFrame("StatusBar", nil, fixed_frame)
    local fakeCast = CreateFrame("StatusBar", nil, fixed_frame)
    local objs = {}
    for i, key in ipairs(NAMEPLATE_OBJECTORDER) do
      local isTexture = (key ~= "name" and key ~= "level")
      local obj
      if isTexture then
        obj = fixed_frame:CreateTexture(nil, "ARTWORK")
      else
        -- 伪 FontString 必须带字体模板，否则后续 original.name/level:SetText 会报
        -- "<unnamed>:SetText(): Font not set"（普通姓名板的原始 FontString 由暴雪自带字体）。
        obj = fixed_frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
      end
      if key == "raidicon" then obj:Hide() end
      objs[i] = obj
    end
    fixed_frame.GetChildren = function() return fakeHealth, fakeCast end
    fixed_frame.GetRegions = function() return unpack(objs) end
    -- GUID 数据源：OnDataChanged 通过 parent:GetName(1) 读取
    fixed_frame.GetName = function(self, ...)
      return fixed_frame._guid or ""
    end

    -- 复用与普通姓名板完全相同的构造与配置流程（视觉/backdrop/尺寸/debuff图标…）
    nameplates.OnCreate(fixed_frame)

    -- 固定到屏幕指定锚点（或解锁后的拖动保存位置）
    local np = fixed_frame.nameplate

    -- 先清空拖动相关脚本与鼠标，避免重建时残留旧回调
    np:SetMovable(false)
    np:EnableMouse(false)
    np:SetScript("OnDragStart", nil)
    np:SetScript("OnDragStop", nil)

    -- 解锁后可拖动移动
    if C.nameplates.fixedposition_unlock == "1" then
      np:SetMovable(true)
      np:EnableMouse(true)
      np:RegisterForDrag("LeftButton")
      np:SetScript("OnDragStart", function()
        this:StartMoving()
      end)
      np:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        -- 保存中心相对屏幕中心的偏移（UIParent 坐标系，无需再乘 scale）
        local cx = (this:GetLeft() + this:GetWidth() / 2)
        local cy = (this:GetTop() - this:GetHeight() / 2)
        local offx = cx - GetScreenWidth() / 2
        local offy = cy - GetScreenHeight() / 2
        pfUI:UpdateConfig("nameplates", nil, "fixedposition_x", tostring(offx))
        pfUI:UpdateConfig("nameplates", nil, "fixedposition_y", tostring(offy))
      end)
    end

    -- 定位：有保存的拖动位置且处于解锁状态时优先使用，否则用锚点
    local sx = C.nameplates.fixedposition_x
    local sy = C.nameplates.fixedposition_y
    if C.nameplates.fixedposition_unlock == "1" and sx and sx ~= "" and sy and sy ~= "" then
      np:ClearAllPoints()
      np:SetPoint("CENTER", UIParent, "CENTER", tonumber(sx) or 0, tonumber(sy) or 0)
    else
      local anchor = C.nameplates.fixedposition_anchor or "TOP"
      local offx, offy = 0, 0
      if anchor == "TOP" then offy = -120
      elseif anchor == "BOTTOM" then offy = 160
      elseif anchor == "CENTER" then offy = 0 end
      np:ClearAllPoints()
      np:SetPoint(anchor, UIParent, anchor, offx, offy)
    end
    np:SetFrameStrata("HIGH")

    target_fixed_plate = {
      fixed_frame = fixed_frame,
      nameplate = np,
    }
    return target_fixed_plate
  end

  local function UpdateTargetFixedPlate()
    if not target_fixed_plate then return end
    local np = target_fixed_plate.nameplate
    local fixed_frame = target_fixed_plate.fixed_frame

    local guid = GetUnitGUID and GetUnitGUID("target")
    local name = UnitName("target") or ""
    local level = UnitLevel("target")
    local hp = UnitHealth("target")
    local hpmax = UnitHealthMax("target")
    if hpmax <= 0 then hpmax = 1 end

    -- 计算单位类型颜色（GetUnitType 据此判定 ENEMY/FRIENDLY/NEUTRAL）
    local hostile = UnitCanAttack("player", "target")
    local friendly = UnitCanAssist("player", "target")
    local r, g, b
    if hostile then            r, g, b = 1, 0, 0       -- 敌方（含玩家）
    elseif not friendly then   r, g, b = 1, 1, 0       -- 中立
    elseif UnitIsPlayer("target") then r, g, b = 0, 0, 1  -- 友好玩家
    else                       r, g, b = 0, 1, 0 end     -- 友好NPC

    -- 写入伪原始元素（复刻姓名板的数据源）
    np.original.name:SetText(name)
    if level and level >= 0 then
      np.original.level:SetText(tostring(level))
    else
      np.original.level:SetText("??")
    end
    np.original.level:Show()
    np.original.levelicon:Hide()
    np.original.glow:Hide()
    np.original.healthbar:SetMinMaxValues(0, hpmax)
    np.original.healthbar:SetValue(hp)
    np.original.healthbar:SetStatusBarColor(r, g, b)

    -- 标记为目标并绑定 GUID，与普通目标姓名板完全一致
    np.istarget = true
    np.cachedGuid = guid
    fixed_frame._guid = guid

    -- 复用与普通姓名板完全相同的渲染管线（含 debuff、仇恨百分比、配色、
    -- 目标姓名、连击点、glow、任务怪图标等），确保外观完全一致。
    nameplates:OnDataChanged(np)
    -- 固定姓名板不显示光晕特效（删除 glow）
    np.glow:Hide()
    if cfg.showcastbar then
      nameplates.UpdateCastbar(np, frameState.now)
    end

    -- 任务怪提示图标（OnUpdate 中处理，固定姓名板不跑 OnUpdate，这里手动同步）
    if cfg.questicon and np.cluster and pfUI.api and pfUI.api.IsQuestUnit and not np.raidicon:IsShown() then
      local icon = pfUI.api.IsQuestUnit(name)
      if icon and icon ~= false then
        np.cluster:SetTexture(icon)
        if np.health:IsShown() then np.cluster:Show() end
      else
        np.cluster:SetTexture()
        np.cluster:Hide()
      end
    elseif np.cluster then
      np.cluster:Hide()
    end
  end

  -- 中枢控制器：根据目标姓名板可见性显示/隐藏固定姓名板
  nameplates.UpdateFixedPlate = function(state)
    if C.nameplates.fixedposition ~= "1" then
      if target_fixed_plate then target_fixed_plate.fixed_frame:Hide() end
      return
    end

    if not UnitExists("target") then
      -- 没有目标，隐藏固定位置姓名板
      if target_fixed_plate then target_fixed_plate.fixed_frame:Hide() end
      return
    end

    -- 检查目标是否已经死亡，如果是则不显示固定姓名板
    if UnitIsDead("target") or UnitIsDeadOrGhost("target") then
      if target_fixed_plate then target_fixed_plate.fixed_frame:Hide() end
      return
    end

    -- 检查目标类型，根据配置决定是否显示固定位置姓名板
    if C.nameplates.fixedposition_enemyonly == "1" and not UnitCanAttack("player", "target") then
      if target_fixed_plate then target_fixed_plate.fixed_frame:Hide() end
      return
    end

    -- 检查目标姓名板是否可见
    local target_visible = IsTargetNamePlateVisible()

    if not target_visible then
      -- 目标姓名板不可见，显示固定位置姓名板
      if not target_fixed_plate then
        CreateTargetFixedPlate()
      end
      -- 先写入数据再显示：避免 OnShow / 渲染时 original.name 仍为 nil
      -- 而触发 TotemPlate(nil) 崩溃
      UpdateTargetFixedPlate()
      target_fixed_plate.fixed_frame:Show()
    else
      -- 目标姓名板可见，隐藏固定位置姓名板
      if target_fixed_plate then
        target_fixed_plate.fixed_frame:Hide()
      end
    end
  end

  -- 重置固定姓名板位置：清空保存的拖动坐标并重建
  nameplates.ResetFixedPlatePosition = function()
    pfUI:UpdateConfig("nameplates", nil, "fixedposition_x", "")
    pfUI:UpdateConfig("nameplates", nil, "fixedposition_y", "")
    if target_fixed_plate then
      target_fixed_plate.fixed_frame:Hide()
      target_fixed_plate = nil
    end
    nameplates.UpdateFixedPlate()
  end

  -- set nameplate game settings
  nameplates.SetGameVariables = function()
    -- update visibility (hostile)
    if C.nameplates["showhostile"] == "1" then
      _G.NAMEPLATES_ON = true
      ShowNameplates()
    else
      _G.NAMEPLATES_ON = nil
      HideNameplates()
    end

    -- update visibility (friendly)
    if C.nameplates["showfriendly"] == "1" then
      _G.FRIENDNAMEPLATES_ON = true
      ShowFriendNameplates()
    else
      _G.FRIENDNAMEPLATES_ON = nil
      HideFriendNameplates()
    end
  end

  nameplates:SetGameVariables()

  nameplates.UpdateConfig = function()
    -- Refresh config cache for all cfg.* values
    CacheConfig()
    RebuildOfftanks()

    -- 固定位置姓名板：配置变化（锚点/尺寸等）后销毁，下一帧用新设置重建
    if target_fixed_plate then
      target_fixed_plate.fixed_frame:Hide()
      target_fixed_plate = nil
    end
    
    -- update debuff filters
    DebuffFilterPopulate()

    -- Check friendly zone state when config changes
    local disableHostile = C.nameplates["disable_hostile_in_friendly"] == "1"
    local disableFriendly = C.nameplates["disable_friendly_in_friendly"] == "1"
    local pvpType = GetZonePVPInfo()
    local nowFriendly = (pvpType == "friendly")
    
    if nowFriendly and (disableHostile or disableFriendly) then
      if not inFriendlyZone then
        -- Just entered friendly zone or feature just enabled
        inFriendlyZone = true
        savedHostileState = C.nameplates["showhostile"]
        savedFriendlyState = C.nameplates["showfriendly"]
      end
      
      -- Apply current settings based on options
      if disableHostile then
        _G.NAMEPLATES_ON = nil
        HideNameplates()
      else
        -- Restore hostile if option is off but we're in friendly zone
        if savedHostileState == "1" then
          _G.NAMEPLATES_ON = true
          ShowNameplates()
        end
      end
      
      if disableFriendly then
        _G.FRIENDNAMEPLATES_ON = nil
        HideFriendNameplates()
      else
        -- Restore friendly if option is off but we're in friendly zone
        if savedFriendlyState == "1" then
          _G.FRIENDNAMEPLATES_ON = true
          ShowFriendNameplates()
        end
      end

      -- 友好区域提前返回原本会跳过下方的 registry 循环，导致 GUI 里改团队图标
      -- 位置/偏移/大小等设置对现有姓名板全部不生效（静默失效）。此处的可见性
      -- 切换已自行调用 Show/HideNameplates，不需要 SetGameVariables，但配置
      -- 刷新必须照常执行。
      for plate in pairs(registry) do
        nameplates.OnConfigChange(plate)
      end
      return
    elseif inFriendlyZone and not (disableHostile or disableFriendly) then
      -- Both features disabled while in friendly zone - restore state
      inFriendlyZone = false
      
      if savedHostileState == "1" then
        C.nameplates["showhostile"] = savedHostileState
      end
      
      if savedFriendlyState == "1" then
        C.nameplates["showfriendly"] = savedFriendlyState
      end
      
      savedHostileState = nil
      savedFriendlyState = nil
      -- Fall through to SetGameVariables to restore nameplates
    end

    -- update nameplate visibility
    nameplates:SetGameVariables()

    -- apply all config changes
    for plate in pairs(registry) do
      nameplates.OnConfigChange(plate)
    end
  end

  if pfUI.client <= 11200 then
    -- handle vanilla only settings
    local hookOnConfigChange = nameplates.OnConfigChange
    nameplates.OnConfigChange = function(self)
      hookOnConfigChange(self)

      local parent = self
      local nameplate = self.nameplate
      local plate = (C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0") and nameplate or parent

      -- disable all clicks for now
      parent:EnableMouse(false)
      nameplate:EnableMouse(false)

      -- adjust vertical offset
      if C.nameplates["vertical_offset"] ~= "0" then
        nameplate:SetPoint("TOP", parent, "TOP", 0, tonumber(C.nameplates["vertical_offset"]))
      end

      -- replace clickhandler
      if C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0" then
        plate:SetScript("OnClick", function() parent:Click() end)
      end

      -- enable mouselook on rightbutton down
      if C.nameplates["rightclick"] == "1" then
        plate:SetScript("OnMouseDown", nameplates.mouselook.OnMouseDown)
      else
        plate:SetScript("OnMouseDown", nil)
      end
    end

    local hookOnDataChanged = nameplates.OnDataChanged
    nameplates.OnDataChanged = function(self, nameplate)
      hookOnDataChanged(self, nameplate)

      -- make sure to keep mouse events disabled on parent nameplate
      if (C.nameplates["overlap"] == "1" or C.nameplates["vertical_offset"] ~= "0") then
        nameplate.parent:EnableMouse(false)
      end
    end

    -- enable mouselook on rightbutton down
    nameplates.mouselook = CreateFrame("Frame", nil, UIParent)
    nameplates.mouselook.time = nil
    nameplates.mouselook.frame = nil
    nameplates.mouselook.OnMouseDown = function()
      if arg1 and arg1 == "RightButton" then
        MouselookStart()

        -- start detection of the rightclick emulation
        nameplates.mouselook.time = GetTime()
        nameplates.mouselook.frame = this
        nameplates.mouselook:Show()
      end
    end

    nameplates.mouselook:SetScript("OnUpdate", function()
      -- break here if nothing to do
      if not this.time or not this.frame then
        this:Hide()
        return
      end

      -- if threshold is reached (0.5 second) no click action will follow
      if not IsMouselooking() and this.time + tonumber(C.nameplates["clickthreshold"]) < GetTime() then
        this:Hide()
        return
      end

      -- run a usual nameplate rightclick action
      if not IsMouselooking() then
        this.frame:Click("LeftButton")
        if UnitCanAttack("player", "target") and not nameplates.combat.inCombat then AttackTarget() end
        this:Hide()
        return
      end
    end)
  end

  -- 暴露配置供调整
  pfUI.nameplates = nameplates
  
  -- 黑名单管理 API
  pfUI.AddBlacklistUnit = function(unitName)
    if not unitName or unitName == "" then return end
    local currentList = C.nameplates.blacklist or ""
    local exists = false
    for _, name in pairs({strsplit("#", currentList)}) do
      if strlower(name) == strlower(unitName) then
        exists = true
        break
      end
    end
    if not exists then
      if currentList == "" then
        C.nameplates.blacklist = unitName
      else
        C.nameplates.blacklist = currentList .. "#" .. unitName
      end
      RefreshBlacklistCache()
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99pfUI:|r 已添加 '" .. unitName .. "' 到黑名单")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99pfUI:|r '" .. unitName .. "' 已在黑名单中")
    end
  end
  
  pfUI.RemoveBlacklistUnit = function(unitName)
    if not unitName or unitName == "" then return end
    local currentList = C.nameplates.blacklist or ""
    local newList = {}
    local removed = false
    
    for _, name in pairs({strsplit("#", currentList)}) do
      if strlower(name) ~= strlower(unitName) then
        table.insert(newList, name)
      else
        removed = true
      end
    end
    
    if removed then
      C.nameplates.blacklist = table.concat(newList, "#")
      RefreshBlacklistCache()
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99pfUI:|r 已从黑名单移除 '" .. unitName .. "'")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99pfUI:|r '" .. unitName .. "' 不在黑名单中")
    end
  end
  
  pfUI.ClearBlacklist = function()
    C.nameplates.blacklist = ""
    RefreshBlacklistCache()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99pfUI:|r 已清空黑名单")
  end
  
  pfUI.GetBlacklist = function()
    local list = {}
    for unitName in pairs(blacklistUnits) do
      table.insert(list, unitName)
    end
    return list
  end

  -- 初始化黑名单缓存
  RefreshBlacklistCache()

  pfUI.nameplates = nameplates
end)