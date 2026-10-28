-- pfUI 内置模块：Debuff 监控
-- 由外部插件 pfUI-debuffmonitor (dein0s, v0.8.3) 集成，功能不变：
--   目标护甲/抗性统计 + 重要团队减益（破甲/精灵之火/元素诅咒/火焰易伤等）监控
--   Nampower >= 2.40 时层数/施法者归属增强（借鉴 Cursive 调用方式），未装 DLL 自动降级
--   存在性检测采用 aDF v4.3 方案：由 UNIT_AURA 事件驱动（0.5s 节流）保证准点熄灭，
--   不做任何伤害/施法事件推断；倒计时（默认关）与施法者名（默认开）均有独立开关
-- 配置命名空间 C.debuffmon（存量存档无缝沿用，含 pfDebuffMonitorTarget 位置）
pfUI:RegisterModule("debuffmonitor", "vanilla:tbc", function()
  local config
  local font_size
  local font = "Fonts\\FZLBJW.TTF" -- 战斗字体（中文客户端标准字体）
  local border = tonumber(C.appearance.border.actionbars) > 0 and tonumber(C.appearance.border.actionbars) or 1
  local scanner = libtipscan:GetScanner("debuffmonitor")

  -- 默认配置（pfUI:UpdateConfig 只补缺失键，不覆盖存量值）
  pfUI:UpdateConfig("debuffmon", nil, "enable", "0") -- 总开关，默认关闭
  pfUI:UpdateConfig("debuffmon", nil, "icons_per_row", "6")
  pfUI:UpdateConfig("debuffmon", nil, "width", "-1")
  pfUI:UpdateConfig("debuffmon", nil, "font_size", "-1")
  pfUI:UpdateConfig("debuffmon", nil, "show", "always")
  pfUI:UpdateConfig("debuffmon", nil, "hide_solo", "0")
  pfUI:UpdateConfig("debuffmon", nil, "background", "1")
  pfUI:UpdateConfig("debuffmon", nil, "alive", "1")
  pfUI:UpdateConfig("debuffmon", nil, "announce_armor", "0") -- 护甲变化通报，默认关闭（借鉴 aDF）
  pfUI:UpdateConfig("debuffmon", nil, "show_time", "0") -- 图标倒计时，默认关闭（aDF 方案：存在性检测即可）
  pfUI:UpdateConfig("debuffmon", nil, "show_caster", "1") -- 施法者名（点燃归属），默认开启
  pfUI:UpdateConfig("debuffmon", nil, "name", "1")
  pfUI:UpdateConfig("debuffmon", nil, "armor", "1")
  pfUI:UpdateConfig("debuffmon", nil, "resistances", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "sa", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "ea", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "as", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "ff", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "cor", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "cy", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "nf", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "ev", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "coe", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "sc", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "ig", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "ad", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "wc", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "cos", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "sw", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "sb", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "ve", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "rf", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "hf", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "sz", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "sp", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "dz", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "tl", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "jow", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "joc", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "ag", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "gr", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "cot", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "mnp", "1")
  pfUI:UpdateConfig("debuffmon", "debuff", "rpp", "1")

  local debuff_list = {
    ["破甲攻击"] = {
      ["name"] = "破甲攻击",
      ["short"] = "sa",
      ["texture"] = "Interface\\Icons\\Ability_Warrior_Sunder",
      ["max_stacks"] = 5, -- 破甲上限 5 层：1-4 层白色，满 5 层荧光绿
      ["order"] = 1
    },
    ["鲁莽诅咒"] = {
      ["name"] = "鲁莽诅咒",
      ["short"] = "cor",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_UnholyStrength",
      ["order"] = 2
    },
    ["卸甲"] = {
      ["name"] = "卸甲",
      ["short"] = "ea",
      ["texture"] = "Interface\\Icons\\Ability_Warrior_Riposte",
      ["order"] = 3
    },
    ["护甲粉碎"] = {
      ["name"] = "护甲粉碎",
      ["short"] = "as",
      ["texture"] = "Interface\\Icons\\INV_Axe_12",
      ["order"] = 4
    },
    ["精灵之火"] = {
      ["name"] = "精灵之火",
      ["short"] = "ff",
      ["texture"] = "Interface\\Icons\\Spell_Nature_FaerieFire",
      ["order"] = 5
    },
    ["破甲水晶"] = {
      ["name"] = "破甲水晶",
      ["short"] = "cy",
      ["texture"] = "Interface\\Icons\\INV_Misc_Gem_Amethyst_01",
      ["order"] = 6
    },
    ["元素诅咒"] = {
      ["name"] = "元素诅咒",
      ["short"] = "coe",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_ChillTouch",
      ["order"] = 7
    },
    ["暗影诅咒"] = {
      ["name"] = "暗影诅咒",
      ["short"] = "cos",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_CurseOfAchimonde",
      ["order"] = 8
    },
    ["夜幕降临"] = {
      ["name"] = "夜幕降临",
      ["short"] = "nf",
      ["texture"] = "Interface\\Icons\\Spell_Holy_ElunesGrace",
      ["order"] = 9
    },
    ["元素易伤"] = {
      ["name"] = "元素易伤",
      ["short"] = "ev",
      ["tooltip_name"] = "元素易伤",
      ["texture"] = "Interface\\Icons\\Spell_Holy_Dizzy",
      ["order"] = 10
    },
    ["奥金幼龙"] = {
      ["name"] = "奥金幼龙",
      ["short"] = "ad",
      ["texture"] = "Interface\\Icons\\Spell_Fire_Fireball",
      ["order"] = 11
    },
    ["火焰易伤"] = {
      ["name"] = "火焰易伤",
      ["short"] = "sc",
      ["texture"] = "Interface\\Icons\\Spell_Fire_SoulBurn",
      ["max_stacks"] = 5, -- 火焰易伤叠层上限 5 层：1-4 层白色，满 5 层荧光绿
      ["duration"] = 30, -- 倒计时兜底时长（Cursive spells/mage.lua 22959；AURA_CAST 事件 durationMs 优先）
      ["order"] = 12
    },
    ["点燃"] = {
      ["name"] = "点燃",
      ["short"] = "ig",
      ["texture"] = "Interface\\Icons\\Spell_Fire_Incinerate",
      ["max_stacks"] = 5, -- 点燃叠层上限 5 层：1-4 层白色，满 5 层荧光绿
      ["duration"] = 4, -- 倒计时兜底时长（Cursive spells/mage.lua 12654；AURA_CAST 事件 durationMs 优先）
      ["order"] = 13
    },
    ["寒冬之寒"] = {
      ["name"] = "寒冬之寒",
      ["short"] = "wc",
      ["texture"] = "Interface\\Icons\\Spell_Frost_ChillingBlast",
      ["order"] = 14
    },
    ["暗影箭"] = {
      ["name"] = "暗影箭",
      ["short"] = "sb",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_ShadowBolt",
      ["order"] = 15
    },
    ["吸血鬼之拥"] = {
      ["name"] = "吸血鬼之拥",
      ["short"] = "ve",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_UnsummonBuilding",
      ["order"] = 16
    },
    ["暗影之波"] = {
      ["name"] = "暗影之波",
      ["short"] = "sw",
      ["tooltip_name"] = "暗影易伤",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_BlackPlague",
      ["order"] = 17
    },
    -- ==== 以下条目借鉴 aDF v4.3（Turtle 特化减益表）====
    ["腐烂血肉"] = {
      ["name"] = "腐烂血肉",
      ["short"] = "rf",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_Lifedrain",
      ["max_stacks"] = 3, -- 3 层=400 护甲（哈卡盛宴前置）
      ["order"] = 18
    },
    ["哈卡盛宴"] = {
      ["name"] = "哈卡盛宴",
      ["short"] = "hf",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_Bloodboil",
      ["order"] = 19 -- 400 护甲
    },
    ["破甲斩"] = {
      ["name"] = "破甲斩",
      ["short"] = "sz",
      ["texture"] = "Interface\\Icons\\Ability_Warrior_Savageblow",
      ["order"] = 20 -- 300 护甲
    },
    ["神圣破甲"] = {
      ["name"] = "神圣破甲",
      ["short"] = "sp",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_CurseOfSargeras",
      ["order"] = 21 -- 50 护甲
    },
    ["挫志怒吼"] = {
      ["name"] = "挫志怒吼",
      ["short"] = "dz",
      ["texture"] = "Interface\\Icons\\Ability_Warrior_WarCry",
      ["order"] = 22 -- 战士挫志怒吼/德鲁伊挫志咆哮同图标
    },
    ["雷霆一击"] = {
      ["name"] = "雷霆一击",
      ["short"] = "tl",
      ["texture"] = "Interface\\Icons\\Spell_Nature_Cyclone",
      ["order"] = 23 -- 雷霆一击/雷霆之怒（风剑）/严寒冲击同图标
    },
    ["智慧审判"] = {
      ["name"] = "智慧审判",
      ["short"] = "jow",
      ["texture"] = "Interface\\Icons\\Spell_Holy_RighteousnessAura",
      ["order"] = 24 -- 骑士回蓝审判
    },
    ["十字军审判"] = {
      ["name"] = "十字军审判",
      ["short"] = "joc",
      -- aDF 原表笔误 Holysmite（小写 s）——/pfdm scan 实测为 HolySmite（2026-10-18）
      ["texture"] = "Interface\\Icons\\Spell_Holy_HolySmite",
      ["order"] = 25 -- 骑士十字军审判（+近战强度）
    },
    ["阿尔萨斯的礼物"] = {
      ["name"] = "阿尔萨斯的礼物",
      ["short"] = "ag",
      ["tooltip_name"] = "阿尔萨斯的礼物", -- 与「麻痹毒药」共用纹理（NullifyDisease），靠首行名字区分
      ["texture"] = "Interface\\Icons\\Spell_Nature_NullifyDisease",
      ["order"] = 26 -- -50 全抗
    },
    ["勾爪"] = {
      ["name"] = "勾爪",
      ["short"] = "gr",
      ["texture"] = "Interface\\Icons\\Ability_Druid_Rake",
      ["order"] = 27 -- 农夫镰刀宠物 2% 近战
    },
    ["语言诅咒"] = {
      ["name"] = "语言诅咒",
      ["short"] = "cot",
      ["texture"] = "Interface\\Icons\\Spell_Shadow_CurseOfTounges", -- 客户端历史拼写 Tounges（Cat2/BigWigs/Babble 多方实证）
      ["order"] = 28 -- 施法减速诅咒
    },
    ["麻痹毒药"] = {
      ["name"] = "麻痹毒药",
      ["short"] = "mnp",
      ["tooltip_name"] = "麻痹毒药", -- 与「阿尔萨斯的礼物」共用纹理（NullifyDisease，Babble-Spell 实证），靠首行名字区分
      ["texture"] = "Interface\\Icons\\Spell_Nature_NullifyDisease",
      ["order"] = 29 -- 盗贼毒药：施法减速
    },
    ["开膛手"] = {
      ["name"] = "开膛手",
      ["short"] = "rpp",
      ["texture"] = "Interface\\Icons\\Spell_Nature_CorrosiveBreath", -- spell 3396 Corrosive Poison（腐蚀毒药 DoT+抗性-60，乌龟服武器开膛手/邪恶之刺复用的 NPC 法术）；BigWigs 多处毒系法术同图标，待 /pfdm scan 实测
      ["order"] = 30 -- 暴风城监狱武器「开膛手」特效（aDF: 护甲-163）
    }
  }

  -- GUI 只需要 _debuff_list；启用后再被下面的 Frame 覆盖重建（会重新赋 _debuff_list）
  pfUI.debuffmonitor = pfUI.debuffmonitor or {}
  pfUI.debuffmonitor._debuff_list = debuff_list -- 存储减益列表（GUI 生成勾选项用）

  -- ============================================================
  -- GUI 注册（gui.lua 在 modules.xml 中先于本模块加载，此处直接注册；
  -- 若 gui 模块被禁用后经 /pfui 按需加载，由 ShowGUI 包装兜底补注册）
  -- 页面挂在「Buff（增益）」根页下，位于 Buff/Debuff 监控各子页之后
  -- ============================================================
  local gui_loaded = false
  local function RegisterGui()
    if gui_loaded then return end
    if not pfUI.gui or not pfUI.gui.CreateGUIEntry then return end
    gui_loaded = true

    pfUI.gui.dropdowns.debuffmonitor_show = {
      "always:" .. T["Always"],
      "never:" .. T["Never"],
      "target:" .. T["Target"],
      "inraid:" .. T["Only Show In Raid"],
    }

    local CreateConfig = pfUI.gui.CreateConfig
    local U = pfUI.gui.UpdaterFunctions

    pfUI.gui.CreateGUIEntry(T["Buffs"], T["Debuff Monitor"], function()
      CreateConfig(nil, T["General"], nil, nil, "header")
      -- 总开关：默认关闭。改动后关 GUI 触发重载提示，重载后生效
      CreateConfig(nil, T["Enable Debuff Monitor"], C.debuffmon, "enable", "checkbox")
      CreateConfig(nil, T["Frame Width"], C.debuffmon, "width")
      CreateConfig(nil, T["Font Size"], C.debuffmon, "font_size")
      CreateConfig(nil, T["Monitor Icons Per Row"], C.debuffmon, "icons_per_row")
      CreateConfig(U["debuffmonitor"], T["Show Monitor"], C.debuffmon, "show", "dropdown", pfUI.gui.dropdowns.debuffmonitor_show)
      CreateConfig(U["debuffmonitor"], T["Hide When Solo"], C.debuffmon, "hide_solo", "checkbox")
      CreateConfig(U["debuffmonitor"], T["Show Background"], C.debuffmon, "background", "checkbox")
      CreateConfig(U["debuffmonitor"], T["Only Monitor Alive Units"], C.debuffmon, "alive", "checkbox")
      CreateConfig(U["debuffmonitor"], T["Armor Drop Announce"], C.debuffmon, "announce_armor", "checkbox")
      CreateConfig(U["debuffmonitor"], T["Show Countdown"], C.debuffmon, "show_time", "checkbox")
      CreateConfig(U["debuffmonitor"], T["Show Caster Name"], C.debuffmon, "show_caster", "checkbox")

      CreateConfig(nil, T["Show Statistics"], nil, nil, "header")
      CreateConfig(U["debuffmonitor"], T["Unit Name"], C.debuffmon, "name", "checkbox")
      CreateConfig(U["debuffmonitor"], T["Unit Resistance"], C.debuffmon, "resistances", "checkbox")
      CreateConfig(U["debuffmonitor"], T["Unit Armor"], C.debuffmon, "armor", "checkbox")

      CreateConfig(nil, T["Show Debuffs"], nil, nil, "header")
      if pfUI.debuffmonitor._debuff_list then
        -- 按 order 排序，保证 GUI 勾选项顺序稳定
        local ordered = {}
        for _, data in pairs(pfUI.debuffmonitor._debuff_list) do
          table.insert(ordered, data)
        end
        table.sort(ordered, function(a, b) return a.order < b.order end)
        for _, data in ipairs(ordered) do
          pfUI:UpdateConfig("debuffmon", "debuff", data.short, "1")
          CreateConfig(U["debuffmonitor"], data.name, C.debuffmon.debuff, data.short, "checkbox")
        end
      end
    end)
  end

  RegisterGui()

  -- /pfui 兜底：gui 模块可能在被禁用后按需加载，此时补注册本页
  if pfUI.ShowGUI then
    local prev_ShowGUI = pfUI.ShowGUI
    -- Lua 5.0 兼容：... 不能作表达式（5.1 才支持），显式转发参数
    pfUI.ShowGUI = function(a1, a2, a3)
      local ret = prev_ShowGUI(a1, a2, a3)
      pcall(RegisterGui)
      return ret
    end
  end

  -- ============================================================
  -- 启用开关：默认关闭（GUI「启用 Debuff 监控」勾选后重载生效）
  -- 关闭时不创建任何帧、不注册任何事件；GUI 页保持可用以便再开启
  -- ============================================================
  if C.debuffmon.enable ~= "1" then
    return
  end

  -- ============================================================
  -- Nampower 模组集成（借鉴 Cursive 插件的调用方式）
  -- 用途: DEBUFF 的层数与剩余时间显示更准确
  -- ============================================================
  local nampower = { available = false }

  local function HasMinimumNampowerVersion(major, minor, patch)
    if GetNampowerVersion then
      local installedMajor, installedMinor, installedPatch = GetNampowerVersion()
      if installedMajor > major then
        return true
      elseif installedMajor == major and installedMinor > minor then
        return true
      elseif installedMajor == major and installedMinor == minor and installedPatch >= patch then
        return true
      end
    end
    return false
  end

  nampower.available = HasMinimumNampowerVersion(2, 40, 0)

  -- 纹理反查表：Nampower 事件提供的是 spellID，用纹理匹配监控列表
  -- 键一律 strlower 归一化：客户端实际纹理大小写与资料可能不一致（aDF 原表 Holysmite 笔误实证）
  -- 值为条目数组（组）：同纹理可能对应多个监控条目（如 阿尔萨斯的礼物/麻痹毒药 共用 NullifyDisease），
  -- 存在性共享同一纹理命中，条目间靠 tooltip_name 首行名字校验独立区分
  local debuff_by_texture = {}
  for name, data in pairs(debuff_list) do
    local key = strlower(data.texture)
    if not debuff_by_texture[key] then
      debuff_by_texture[key] = {}
    end
    table.insert(debuff_by_texture[key], data)
  end

  -- Nampower 缓存: [unitGUID] = { [spellID] = { stacks=, texture=, caster=, expiration= } }
  -- （存在性只由真实 aura 槽扫描决定，缓存只补施法者/层数/倒计时参考值）
  local np_cache = {}

  -- 倒计时时长来源（仅 show_time 开启时消费，存在性不受影响）：
  -- AURA_CAST 事件自带 durationMs（精确）> 监控表硬编码 duration（Cursive 同款）> GetSpellDuration(DBC)
  local function AuraDurationSec(entry_data, spellId)
    if entry_data and entry_data.duration then return entry_data.duration end
    if GetSpellDuration then
      local ok, durMs = pcall(GetSpellDuration, spellId)
      if ok and durMs and durMs > 0 then return durMs / 1000 end
    end
    return nil
  end

  -- 由 spellID 取图标纹理（Nampower 的 GetSpellRecField + GetSpellIconTexture）
  local function SpellTextureFromId(spellId)
    if not spellId or spellId <= 0 then return nil end
    if GetSpellRecField and GetSpellIconTexture then
      local iconId = GetSpellRecField(spellId, "spellIconID")
      if iconId and iconId > 0 then
        return GetSpellIconTexture(iconId)
      end
    end
    return nil
  end

  -- 主动扫描目标 aura 槽位，重建/修正缓存
  -- （重载UI后 DEBUFF_ADDED_OTHER 事件不会补发，靠这里恢复层数；
  --   同时清空重建可清除施法未命中造成的残留条目）
  local scan_tick = 0
  local function ScanGuidAuras(guid)
    if not nampower.available or not guid or not GetUnitField then return end
    if (scan_tick or 0) > GetTime() then return end
    scan_tick = GetTime() + 0.5
    local auras = GetUnitField(guid, "aura") or {}
    local applications = GetUnitField(guid, "auraApplications") or {}
    local old_cache = np_cache[guid] -- 保留旧缓存中的施法者归属
    np_cache[guid] = {}
    for i, spellId in pairs(auras) do
      if spellId and spellId > 0 then
        local texture = SpellTextureFromId(spellId)
        local group = texture and debuff_by_texture[strlower(texture)]
        if group then
          local old = old_cache and old_cache[spellId]
          local stacks = 1
          if applications[i] then stacks = applications[i] + 1 end
          local expiration = old and old.expiration -- 扫描重建保留事件写入的到期时间
          if not expiration then
            local dur = AuraDurationSec(group[1], spellId)
            if dur then expiration = GetTime() + dur end
          end
          np_cache[guid][spellId] = {
            stacks = stacks,
            expiration = expiration,
            texture = texture,
            caster = old and old.caster, -- 保留施法者名（事件写入，扫描重建不丢失）
          }
        end
      end
    end
    if not next(np_cache[guid]) then np_cache[guid] = nil end -- 清理空表
  end

  -- 注册 Nampower 事件（独立事件帧，避免与主帧 OnEvent/UpdateDisplay 冲突）
  -- aDF 方案：事件只用于施法者归属/层数同步/倒计时参考值，存在性判定仍以扫描为准
  if nampower.available then
    local np_events = CreateFrame("Frame")
    np_events:RegisterEvent("DEBUFF_ADDED_OTHER")
    np_events:RegisterEvent("DEBUFF_REMOVED_OTHER")
    np_events:RegisterEvent("AURA_CAST_ON_OTHER")
    np_events:SetScript("OnEvent", function()
      -- vanilla 1.12: OnEvent 无参数调用，事件名与参数在隐式全局 event / arg1-arg10（参照 pfUI 本体写法）
      if event == "DEBUFF_ADDED_OTHER" then
        -- 参数: guid, luaSlot, spellId, stackCount, auraLevel, auraSlot, state
        local guid, spellId, stackCount = arg1, arg3, arg4
        if guid and spellId and spellId > 0 then
          local texture = SpellTextureFromId(spellId)
          local group = texture and debuff_by_texture[strlower(texture)]
          if group then
            np_cache[guid] = np_cache[guid] or {}
            local old = np_cache[guid][spellId]
            local expiration = old and old.expiration
            if not expiration then
              local dur = AuraDurationSec(group[1], spellId)
              if dur then expiration = GetTime() + dur end
            end
            np_cache[guid][spellId] = {
              stacks = tonumber(stackCount) or (old and old.stacks) or 1,
              expiration = expiration,
              texture = texture,
              caster = old and old.caster, -- 保留施法者名（点燃叠层刷新时不清空）
            }
          end
        end
      elseif event == "DEBUFF_REMOVED_OTHER" then
        local guid, spellId = arg1, arg3
        if np_cache[guid] then
          np_cache[guid][spellId] = nil
          if not next(np_cache[guid]) then np_cache[guid] = nil end
        end
      elseif event == "AURA_CAST_ON_OTHER" then
        -- 参数: spellId, casterGuid, targetGuid, effect, effectAuraName, effectAmplitude,
        --       effectMiscValue, durationMs, auraCapStatus（durationMs 提供精确倒计时）
        local spellId, casterGuid, targetGuid, durationMs = arg1, arg2, arg3, arg8
        if spellId and spellId > 0 and targetGuid and durationMs and durationMs > 0 then
          local texture = SpellTextureFromId(spellId)
          local group = texture and debuff_by_texture[strlower(texture)]
          if group then
            np_cache[targetGuid] = np_cache[targetGuid] or {}
            local entry = np_cache[targetGuid][spellId]
            if not entry then
              entry = { stacks = 1, texture = texture }
              np_cache[targetGuid][spellId] = entry
            end
            entry.expiration = GetTime() + durationMs / 1000 -- 每次施加/刷新都续期（精确）
            -- 点燃归属规则：首次施加者锁定（已有 caster 不覆盖），刷新不换人（经典旧世"抢点燃"机制）
            if not entry.caster then
              entry.caster = casterGuid and UnitName(casterGuid)
            end
          end
        end
      end
      -- aDF 原则：只显示客户端确认存在的 debuff，不做任何伤害/施法事件推断；
      -- 存在性唯一来源 = UnitDebuff/UnitBuff 扫描 + GetUnitField 全景（UNIT_AURA 事件驱动刷新）
    end)
  end

  pfUI.debuffmonitor = CreateFrame("Frame", "pfDebuffMonitor", UIParent) -- 创建框架
  pfUI.debuffmonitor:RegisterEvent("VARIABLES_LOADED") -- 注册事件

  -- ==== 护甲变化通报（借鉴 aDF aDFArmorVals：护甲差值反推施加/消失的减益）====
  local armor_diffs = {
    -- 破甲攻击（按叠层与等级的差值全覆盖）
    [90] = "破甲攻击", [180] = "破甲攻击", [270] = "破甲攻击", [360] = "破甲攻击",
    [450] = "破甲攻击", [540] = "破甲攻击", [720] = "破甲攻击", [810] = "破甲攻击",
    [900] = "破甲攻击", [1080] = "破甲攻击", [1350] = "破甲攻击", [1440] = "破甲攻击",
    [1800] = "破甲攻击", [2250] = "破甲攻击",
    -- 精灵之火（1-4 级 / 野性）
    [505] = "精灵之火", [395] = "精灵之火", [285] = "精灵之火", [175] = "精灵之火",
    -- 鲁莽诅咒（1-4 级）
    [640] = "鲁莽诅咒", [465] = "鲁莽诅咒", [290] = "鲁莽诅咒", [140] = "鲁莽诅咒",
    -- 卸甲（盗贼 725/1050/1375/1700，强化天赋 2550）
    [725] = "卸甲", [1050] = "卸甲", [1375] = "卸甲", [1700] = "卸甲", [2550] = "强化卸甲",
    -- 乌龟服特化
    [163] = "开膛手", -- 乌龟服武器开膛手/邪恶之刺特效（spell 3396，tooltip 误标 60）
    [100] = "刺破护甲", -- non-stacking proc spell=13752, Puncture Armor r1 x1 spell=11791
    [400] = "哈卡盛宴", [250] = "破碎铠甲", [300] = "破甲斩", [50] = "神圣破甲",
  }

  -- 第三行元素（减益）

  -- ==== 单次扫描（借鉴 aDF update.lua：全局一次遍历代替每图标独立扫描）====
  -- 旧实现：每个图标 OnUpdate 各自调 FindDebuff（64 槽循环 + tooltip），
  -- 27 图标 × 0.2s ≈ 每秒 135 次全量扫描；现在一次扫描建 [texture] = 结果，所有图标查表。
  local scan_results = {} -- [texture] = { found, name_ok, stacks, expiration, caster, spell_id, guid }
  local scan_unit_used = nil -- 上次扫描的单位（换目标时强制重扫）

  local function ScanUnitAuras()
    for k in pairs(scan_results) do scan_results[k] = nil end -- 清空上轮结果
    local unit = pfUI.debuffmonitor.target.unit
    scan_unit_used = unit
    if not unit then return end

    -- 1) 权威层数数据源：UnitDebuff 单次遍历（与客户端默认 debuff 显示同源）
    -- 实测：乌龟服 UnitDebuff 返回 (texture, stacks, type, spellId, nil)——
    -- 第 4 个返回值是 spellId 而非 duration，第 5 个（expirationTime）为 nil，故剩余时间不由此提供
    for i = 1, 64 do
      local d_texture, d_stacks = UnitDebuff(unit, i)
      if not d_texture then break end -- 无更多光环，提前退出
      local r = scan_results[strlower(d_texture)]
      if not r then
        r = { found = true, stacks = 0, name_ok = true }
        scan_results[strlower(d_texture)] = r
        -- 同纹理组内每个条目独立做 tooltip 首行名校验（如 阿尔萨斯的礼物/麻痹毒药 共用纹理），
        -- 结果写 name_ok_map[条目名]；无 tooltip_name 的条目沿用 r.name_ok=true
        -- 匹配用前缀（Cat2 实证乌龟服首行带等级后缀，如「麻痹毒药 III」），plain 模式无模式符风险
        local group = debuff_by_texture[strlower(d_texture)]
        if group and table.getn(group) > 0 then
          scanner:SetUnitDebuff(unit, i)
          local d_name = scanner:Line(1) or ""
          for _, data in ipairs(group) do
            if data.tooltip_name and data.tooltip_name ~= "" then
              r.name_ok_map = r.name_ok_map or {}
              r.name_ok_map[data.name] = string.find(strupper(d_name), strupper(data.tooltip_name), 1, true) == 1
            end
          end
        end
      end
      if d_stacks and d_stacks > r.stacks then r.stacks = d_stacks end -- 权威层数
    end

    -- 1.5) buff 槽兜底（借鉴 aDF aura.lua）：debuff 槽满时部分减益会被客户端塞进 buff 槽
    -- 只对监控表里的纹理生效；UnitDebuff 已命中的纹理跳过（debuff 槽层数权威）
    for i = 1, 64 do
      local d_texture, d_stacks = UnitBuff(unit, i)
      if not d_texture then break end
      if debuff_by_texture[strlower(d_texture)] and not scan_results[strlower(d_texture)] then
        local r = { found = true, stacks = 0, name_ok = true }
        scan_results[strlower(d_texture)] = r
        local group = debuff_by_texture[strlower(d_texture)]
        if group and table.getn(group) > 0 then
          scanner:SetUnitBuff(unit, i)
          local d_name = scanner:Line(1) or ""
          for _, data in ipairs(group) do
            if data.tooltip_name and data.tooltip_name ~= "" then
              r.name_ok_map = r.name_ok_map or {}
              r.name_ok_map[data.name] = string.find(strupper(d_name), strupper(data.tooltip_name), 1, true) == 1
            end
          end
        end
        if d_stacks and d_stacks > 0 then r.stacks = d_stacks end
      end
    end

    -- 2) 施法者/层数兜底数据源：np_cache（事件写入，ScanGuidAuras 扫描重建，跨帧持久）
    if nampower.available and GetUnitGUID then
      local guid = GetUnitGUID(unit)
      if guid then
        ScanGuidAuras(guid)
        local cache = np_cache[guid]
        if cache then
          for spellId, entry in pairs(cache) do
            local r = scan_results[strlower(entry.texture)]
            if not r then
              r = { found = true, stacks = 0, name_ok = true }
              scan_results[strlower(entry.texture)] = r
            end
            r.found = true -- np_cache 兜底命中（UnitDebuff 索引外的 debuff）
            if r.stacks == 0 and entry.stacks then r.stacks = entry.stacks end
            if not r.expiration then r.expiration = entry.expiration end -- 倒计时参考值
            if not r.caster then r.caster = entry.caster end -- 施法者名（点燃归属由事件记录）
            r.spell_id = spellId
            r.guid = guid
          end
        end
      end
    end
  end

  -- 统一图标刷新：消费 scan_results，更新透明度/层数/倒计时/施法者
  local function UpdateIcons()
    if not pfUI.debuffmonitor.target:IsShown() then return end
    if pfUI.debuffmonitor.target.unit ~= scan_unit_used then
      ScanUnitAuras() -- 换目标：强制重扫
    end
    local now = GetTime()
    for name, data in pairs(debuff_list) do
      local frame = pfUI.debuffmonitor.target.debuffs.frames[data.short]
      if frame and frame:IsShown() then
        local r = scan_results[strlower(data.texture)]
        -- 名字校验判定：组内同纹理条目各自取 name_ok_map，未参与校验的沿用 r.name_ok
        local ok_flag = r and r.name_ok
        if r and r.name_ok_map and r.name_ok_map[data.name] ~= nil then
          ok_flag = r.name_ok_map[data.name]
        end
        local found = r and r.found and ok_flag
        if not found then
          frame.active = false
          frame.stacks:SetText("") -- 设置堆叠文本为空
          frame.time:SetText("") -- 设置剩余时间为空
          frame.caster:Hide() -- 隐藏施法者名
          frame.texture:SetAlpha(0.3) -- 设置透明度
        else
          frame.active = true
          frame.texture:SetAlpha(1) -- 设置透明度为1
          local stacks = r.stacks or 0
          if stacks > 1 then
            frame.stacks:SetText(stacks) -- 设置堆叠数量
            -- 层数颜色：未满级白色，满级（达到 max_stacks）荧光绿
            local max_st = data.max_stacks or 1
            if stacks >= max_st then
              frame.stacks:SetTextColor(0.1, 1, 0.3, 1) -- 满级：荧光绿
            else
              frame.stacks:SetTextColor(1, 1, 1, 1) -- 未满级：白色
            end
          else
            frame.stacks:SetText("") -- 设置堆叠文本为空
          end
          -- 倒计时（可选开关 show_time，默认关=aDF 方案）：过期由扫描存在性决定，这里只显示参考值
          if config.show_time == "1" and r.expiration then
            local remaining = r.expiration - now
            if remaining > 0 then
              if remaining < 10 then
                frame.time:SetText(string.format("%.1f", remaining)) -- 10秒内显示一位小数
              else
                frame.time:SetText(tostring(math.ceil(remaining))) -- 显示整数秒
              end
            else
              frame.time:SetText("")
            end
          else
            frame.time:SetText("")
          end
          -- 施法者名（点燃归属，由 AURA_CAST_ON_OTHER 事件记录；开关 show_caster）
          if r.caster and config.show_caster == "1" then
            frame.caster:SetText(r.caster)
            frame.caster:Show()
          else
            frame.caster:Hide()
          end
        end
      end
    end
  end

  local function CreateDebuff(d_name, d_short) -- 创建减益
    local debuff_frame = CreateFrame("Frame", nil, pfUI.debuffmonitor.target.debuffs)
    debuff_frame.short = d_short
    debuff_frame.name = d_name
    debuff_frame.active = false
    debuff_frame:SetFrameStrata("MEDIUM") -- 设置框架层级
    debuff_frame:EnableMouse(false) -- 鼠标穿透：不影响选择目标与施法

    debuff_frame.texture = debuff_frame:CreateTexture(nil, "OVERLAY") -- 创建纹理
    debuff_frame.texture:SetTexCoord(.07,.93,.07,.93) -- 设置纹理坐标
    debuff_frame.texture:SetAllPoints(debuff_frame) -- 设置纹理填充
    debuff_frame.texture:SetTexture(debuff_list[d_name].texture) -- 设置纹理图标
    debuff_frame.texture:SetAlpha(0.3) -- 设置透明度

    debuff_frame.stacks = debuff_frame:CreateFontString("Status", "OVERLAY", "GameFontNormal") -- 创建堆叠字体
    debuff_frame.stacks:SetTextColor(1,1,1,1) -- 默认白色（未满级）；满级时 OnUpdate 切换荧光绿
    debuff_frame.stacks:SetJustifyH("RIGHT") -- 设置水平对齐（右下角）
    debuff_frame.stacks:SetJustifyV("BOTTOM") -- 设置垂直对齐
    debuff_frame.stacks:SetPoint("BOTTOMRIGHT", debuff_frame, "BOTTOMRIGHT", -1, -3) -- 右下角显示层数（再往下 3px，避免视觉居中偏高）
    debuff_frame.stacks:SetFont(font, 50) -- 层数 50 号

    debuff_frame.time = debuff_frame:CreateFontString("Status", "OVERLAY", "GameFontNormal") -- 剩余时间（开关 show_time）
    debuff_frame.time:SetTextColor(1,1,1,1) -- 设置文本颜色（白色）
    debuff_frame.time:SetJustifyH("CENTER") -- 设置水平对齐（正中间）
    debuff_frame.time:SetJustifyV("CENTER") -- 设置垂直对齐
    debuff_frame.time:SetAllPoints(debuff_frame) -- 正中间显示剩余时间
    debuff_frame.time:SetFont(font, 40) -- 剩余时间 40 号

    debuff_frame.caster = debuff_frame:CreateFontString("Status", "OVERLAY", "GameFontNormal") -- 施法者名（点燃图标下方）
    debuff_frame.caster:SetTextColor(1,0.82,0,1) -- 亮黄色（醒目）
    debuff_frame.caster:SetJustifyH("CENTER")
    debuff_frame.caster:SetPoint("TOP", debuff_frame, "BOTTOM", 0, -2) -- 图标下方
    debuff_frame.caster:SetFont(font, 22, "OUTLINE") -- 22 号 + 黑色描边（点燃图标正下方）
    debuff_frame.caster:Hide() -- 默认隐藏，有施法者数据时显示

    -- 图标刷新已由主帧 OnUpdate 统一调度（UpdateIcons），不再各自 OnUpdate
    -- （旧实现 27 图标 × 0.2s 各自全量扫描 64 槽 + tooltip，性能浪费严重）

    local icon_spacing = 1 -- 增加的间距
    debuff_frame:SetPoint("TOPLEFT", pfUI.debuffmonitor.target.debuffs, "TOPLEFT", 0, -icon_spacing) -- 向上移动图标

    return debuff_frame -- 返回减益框架
  end

  -- 重置统计文本（无有效目标 / 仅团队模式不在团队时共用）
  local function ResetStatsText()
    pfUI.debuffmonitor.target.name:SetText("|cffffff00减益监控")
    pfUI.debuffmonitor.target.armor:SetText("|cffffff00甲: ") -- 护甲文本
    pfUI.debuffmonitor.target.fire:SetText("|cffFF0000火: ") -- 火焰文本
    pfUI.debuffmonitor.target.nature:SetText("|cff00FF00毒: ") -- 自然文本
    pfUI.debuffmonitor.target.frost:SetText("|cff4AE8F5冰: ") -- 冰霜文本
    pfUI.debuffmonitor.target.shadow:SetText("|cff800080暗: ") -- 暗影文本
  end

  -- 顶部统计文字按框架 scale 反比补偿字号：框架被 unlock 缩小（如 0.7）后，
  -- 固定字号会视觉过小（截图实证），除以 scale 保持视觉大小恒定。
  -- scale 由 LoadMovable 在进服后应用，且 unlock 滚轮可随时改 → 放在每秒 tick 检测变化。
  local ApplyStatsLayoutScale -- 前向声明（定义在 UpdateConfigDebuffs 之后，需引用其重算总高）
  local stats_scale_used = nil
  local function ApplyStatsFontScale()
    local f = pfUI.debuffmonitor.target
    if not f then return end
    local scale = f:GetScale()
    if not scale or scale <= 0 then return end
    if stats_scale_used == scale then return end -- scale 未变化，跳过
    stats_scale_used = scale
    for _, key in pairs({ "name", "armor", "fire", "nature", "frost", "shadow" }) do
      local fs = f[key]
      if fs then fs:SetFont(font, math.floor(font_size / scale + 0.5)) end
    end
    ApplyStatsLayoutScale() -- 行高/行位置/总高同步放大，否则第一行文字溢出行高与第二行重叠
  end

  -- 显示更新
  local function UpdateDisplay()
    ApplyStatsFontScale() -- 统计文字字号随 scale 补偿（unlock 模式滚轮改缩放也实时生效）
    -- ⛔ 解锁模式期间完全不接管显隐：
    -- 1) 隐藏类配置（inraid/hide_solo/无目标）会在拖动中途把框 Hide 掉；
    -- 2) 本客户端隐藏帧 GetLeft/Top 全 nil，松手时 unlock 的几何守卫会跳过存档
    --    ⇒ 「移动后位置不保存」的根因（swingtimer 距离指示器同款守卫）。
    if pfUI.unlock and pfUI.unlock:IsShown() then return end

    -- 仅团队模式：不在团队时直接清空并隐藏（存量存档 show="inraid" 的既定行为）
    if config.show == "inraid" and not UnitInRaid("player") then
      pfUI.debuffmonitor.target.unit = nil
      ResetStatsText()
      pfUI.debuffmonitor.target:Hide()
      return
    end

    local scan_unit
    if UnitIsPlayer("target") then
      if not UnitIsPlayer("targettarget") and UnitCanAttack("player", "targettarget") then
        scan_unit = "targettarget" -- 扫描目标的目标
      end
    else
      if UnitCanAttack("player", "target") then
        scan_unit = "target" -- 扫描当前目标
      end
    end

    if config.alive == "1" and (scan_unit ~= nil and UnitIsDead(scan_unit) == 1) then
      scan_unit = nil -- 如果目标死了则设置为空
    end

    if scan_unit == nil then
      pfUI.debuffmonitor.target.unit = nil
      ResetStatsText()
      if config.show == "target" or config.show == "inraid" then
        pfUI.debuffmonitor.target:Hide() -- 隐藏目标
      end
    else
      pfUI.debuffmonitor.target.unit = scan_unit
      pfUI.debuffmonitor.target.name:SetText(strupper(UnitName(scan_unit))) -- 设置目标名称
      pfUI.debuffmonitor.target.armor:SetText("|cffffff00甲: " .. UnitResistance(scan_unit, 0) or "??") -- 护甲值
      pfUI.debuffmonitor.target.fire:SetText("|cffFF0000火: " .. UnitResistance(scan_unit, 2) or "??") -- 火焰值
      pfUI.debuffmonitor.target.nature:SetText("|cff00FF00毒: " .. UnitResistance(scan_unit, 3) or "??") -- 自然值
      pfUI.debuffmonitor.target.frost:SetText("|cff4AE8F5冰: " .. UnitResistance(scan_unit, 4) or "??") -- 冰霜值
      pfUI.debuffmonitor.target.shadow:SetText("|cff800080暗: " .. UnitResistance(scan_unit, 5) or "??") -- 暗影值
      pfUI.debuffmonitor.target:Show() -- 显示目标

      -- 护甲变化通报（借鉴 aDF aDFArmorVals：护甲差值反推施加/消失的减益；默认关闭）
      if config.announce_armor == "1" then
        local armorcurr = UnitResistance(scan_unit, 0)
        local tname = UnitName(scan_unit) or "?"
        if pfUI.debuffmonitor.target._armor_name ~= tname then
          -- 换目标：重置基线，不通报
          pfUI.debuffmonitor.target._armor_name = tname
          pfUI.debuffmonitor.target._armor_prev = armorcurr
        else
          local prev = pfUI.debuffmonitor.target._armor_prev
          if prev and armorcurr ~= prev then
            local diff = armorcurr - prev
            local reason = armor_diffs[math.abs(diff)]
            if reason then
              local msg
              if diff < 0 then
                msg = "|cffffcc00[Debuff监控]|r " .. tname .. " 护甲 " .. prev .. " -> " .. armorcurr
                  .. "（下降 |cff00ff00" .. (-diff) .. "|r：" .. reason .. "）"
              else
                msg = "|cffffcc00[Debuff监控]|r " .. tname .. " 护甲 " .. prev .. " -> " .. armorcurr
                  .. "（回升 |cff00ff00" .. diff .. "|r：" .. reason .. " 消失）"
              end
              DEFAULT_CHAT_FRAME:AddMessage(msg)
            end
            pfUI.debuffmonitor.target._armor_prev = armorcurr
          elseif not prev then
            pfUI.debuffmonitor.target._armor_prev = armorcurr
          end
        end
      end
    end

    if config.hide_solo == "1" then
      if not UnitExists("party1") and not UnitInRaid("player") then
        pfUI.debuffmonitor.target:Hide() -- 如果没有队友则隐藏目标
      end
    end

    if config.show == "never" then
      pfUI.debuffmonitor.target:Hide() -- 从不显示
    elseif config.show == "always" then
      pfUI.debuffmonitor.target:Show() -- 始终显示
    end
  end

  -- 动态更新
  local function NumDebuffsToShow() -- 计算要显示的减益数量
    local counter = 0
    for name, _ in pairs(debuff_list) do
      if config.debuff[debuff_list[name].short] == "1" then
        counter = counter + 1
      end
    end
    return counter
  end

  local function DebuffSize()
    local icons_per_row = tonumber(C.debuffmon.icons_per_row) or 6  -- 获取每行图标数量，确保与配置一致
    local spacing = border * 2
    local actual_width = pfUI.debuffmonitor.target:GetWidth() - spacing * (icons_per_row - 1) - border  -- 调整计算实际宽度的方式，考虑边框
    local size = actual_width / icons_per_row
    return size  -- 不限制最大宽度
  end

  local function UpdateConfigDebuffs()
    local parent = config.resistances == "1" and "row_3" or "row_2"
    local size = DebuffSize()
    local index = 0
    local spacing = border * 2
    local icons_per_row = tonumber(C.debuffmon.icons_per_row) or 6  -- 获取每行图标数量，确保与配置一致
    local num_debuffs = NumDebuffsToShow()
    local rows_needed = math.ceil(num_debuffs / icons_per_row)

    local icon_spacing = 1 -- 增加的间距

    -- 将 debuff_list 转换为数组并按 order 排序
    local debuff_array = {}
    for name, data in pairs(debuff_list) do
      table.insert(debuff_array, {name = name, data = data})
    end
    table.sort(debuff_array, function(a, b) return a.data.order < b.data.order end)

    -- 按照排序后的顺序处理图标
    for _, entry in ipairs(debuff_array) do
      local l_name = entry.name
      local d_short = entry.data.short
      if config.debuff[d_short] == "1" then
        index = index + 1
        local row_index = math.ceil(index / icons_per_row)  -- 计算图标所在行数
        local column_index = index - ((row_index - 1) * icons_per_row)  -- 计算图标在该行的列数
        local x_offset = (column_index - 1) * (size + spacing) + spacing - 1  -- 计算x轴偏移量，并向左偏移1个像素
        local y_offset = -(row_index - 1) * (size + spacing) - pfUI.debuffmonitor.target.spacing * 3 -- 增加一个固定的偏移量来确保图标不会与文字重叠

        pfUI.debuffmonitor.target.debuffs.frames[d_short]:ClearAllPoints()
        pfUI.debuffmonitor.target.debuffs.frames[d_short]:SetWidth(size)
        pfUI.debuffmonitor.target.debuffs.frames[d_short]:SetHeight(size)  -- 设置高度与宽度相同
        -- 图标字号随图标尺寸自适应：固定 50/40 号在小图标上层数与倒计时相互重叠（截图实证）
        -- 字号是 frame 自身单位，随整体 scale 缩放，无需再做 scale 补偿
        pfUI.debuffmonitor.target.debuffs.frames[d_short].stacks:SetFont(font, math.max(math.floor(size * 0.55 + 0.5), 12))
        pfUI.debuffmonitor.target.debuffs.frames[d_short].time:SetFont(font, math.max(math.floor(size * 0.45 + 0.5), 10))
        pfUI.debuffmonitor.target.debuffs.frames[d_short].caster:SetFont(font, math.max(math.floor(size * 0.38 + 0.5), 10), "OUTLINE")
        pfUI.debuffmonitor.target.debuffs.frames[d_short]:SetPoint("TOPLEFT", pfUI.debuffmonitor.target[parent], "TOPLEFT", x_offset, y_offset)
        pfUI.debuffmonitor.target.debuffs.frames[d_short]:Show()
      else
        pfUI.debuffmonitor.target.debuffs.frames[d_short]:Hide()
      end
    end

    -- 调整框架高度以适应图标和前两行文字（文字区高度按 layout_comp 补偿倍数放大）
    local layout_comp = pfUI.debuffmonitor.target.layout_comp or 1
    local new_height = (pfUI.debuffmonitor.target.font_height * 2 + pfUI.debuffmonitor.target.spacing * 4) * layout_comp + rows_needed * (size + spacing)
    pfUI.debuffmonitor.target:SetHeight(new_height)

    -- 确保背景框的高度与框架高度一致
    if pfUI.debuffmonitor.target.backdrop then
      pfUI.debuffmonitor.target.backdrop:SetHeight(new_height)
    end
  end

  -- 行高/行位置按补偿字号同步放大：字号补偿 1/scale 倍后原行高装不下，
  -- 第一行文字底边越过 row_2 顶造成两行重叠（截图实证）。
  -- 由 ApplyStatsFontScale 在 scale 变化时调用；图标区锚定 row_3/row_2 自动跟随下移，
  -- 框架/背景总高经 UpdateConfigDebuffs 按 layout_comp 重算。
  ApplyStatsLayoutScale = function()
    local f = pfUI.debuffmonitor.target
    if not f or not f.font_height then return end
    local scale = f:GetScale()
    if not scale or scale <= 0 then return end
    local comp = 1 / scale
    if comp < 1 then comp = 1 end -- 放大框架时文字区不缩，保持原布局余量
    f.layout_comp = comp

    local row_h = f.font_height * 2 - f.spacing * 4 - 6 -- 原始行高（Load 同款公式）
    local row_h2 = math.floor(row_h * comp + 0.5)
    for i = 1, 4 do
      local row = f["row_" .. i]
      row:SetHeight(row_h2)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -(row_h2 * (i - 1)))
    end

    -- 第二行抗性文字：X 四等分不变，Y 下移量按比例放大
    local idx = 0
    for _, key in pairs({ strsplit("#", f.second_row) }) do
      idx = idx + 1
      local fs = f[key]
      if fs then
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", f.row_2, "TOPLEFT", (f:GetWidth() / 4) * (idx - 1), -f.spacing * comp)
        fs:SetPoint("BOTTOMRIGHT", f.row_2, "BOTTOMRIGHT", (f:GetWidth() / 4) * (idx - 1), -f.spacing * comp)
      end
    end

    -- armor 起点：名字补偿后更宽，右移量按比例放大
    f.armor:ClearAllPoints()
    f.armor:SetPoint("TOPLEFT", f.row_1, "TOPLEFT", (f:GetWidth() / 2) + f.font_height * comp, 0)
    f.armor:SetPoint("BOTTOMRIGHT", f.row_1, "BOTTOMRIGHT", (f:GetWidth() / 2) + f.font_height * comp, 0)

    UpdateConfigDebuffs() -- 图标重排 + 框架/背景总高按 layout_comp 重算
  end

  function pfUI.debuffmonitor:Load()
    if pfUI.debuffmonitor.target then
      return
    end
    config = C.debuffmon
    font_size = config.font_size == "-1" and tonumber(C.global.font_size) or tonumber(config.font_size)
    pfUI.debuffmonitor.target = CreateFrame("Frame", "pfDebuffMonitorTarget", UIParent)
    pfUI.debuffmonitor.target:SetWidth(config.width == "-1" and C.chat.right.width or config.width)
    local icons_per_row = tonumber(C.debuffmon.icons_per_row) or 5  -- 获取每行图标数量，默认5个

    -- 创建一个临时字体字符串来获取字体高度
    local temp_font_string = pfUI.debuffmonitor.target:CreateFontString("Status", "LOW", "GameFontNormal")
    temp_font_string:SetFont(font, font_size)
    local _, font_height = temp_font_string:GetFont()
    temp_font_string:Hide()

    pfUI.debuffmonitor.target.font_height = font_height  -- 存储字体高度
    pfUI.debuffmonitor.target.spacing = font_height/6  -- 计算间距

    pfUI.debuffmonitor.target:SetHeight(math.ceil(NumDebuffsToShow() / icons_per_row) * (config.font_size == "-1" and tonumber(C.global.font_size) or tonumber(config.font_size)) + (icons_per_row - 1) * border * 2)  -- 根据图标数量和字体大小设置高度
    pfUI.debuffmonitor.target:EnableMouse(false) -- 鼠标穿透：不影响选择目标与施法
    CreateBackdrop(pfUI.debuffmonitor.target)

    pfUI.debuffmonitor.target.first_row = "#name#armor" -- 第一行（名字和护甲）
    pfUI.debuffmonitor.target.second_row = "#fire#nature#frost#shadow" -- 第二行（抵抗）

    -- 创建行
    for i=1,4 do
      pfUI.debuffmonitor.target["row_" .. i] = CreateFrame("Frame", nil, pfUI.debuffmonitor.target)
      pfUI.debuffmonitor.target["row_" .. i]:SetWidth(pfUI.debuffmonitor.target:GetWidth()) -- 设置行宽
      pfUI.debuffmonitor.target["row_" .. i]:SetHeight(pfUI.debuffmonitor.target.font_height * 2 - pfUI.debuffmonitor.target.spacing * 4-6) -- 设置行高
      pfUI.debuffmonitor.target["row_" .. i]:ClearAllPoints()
      pfUI.debuffmonitor.target["row_" .. i]:SetPoint("TOPLEFT", pfUI.debuffmonitor.target, "TOPLEFT", 0, -(pfUI.debuffmonitor.target["row_" .. i]:GetHeight() * (i-1))) -- 设置位置
    end

    -- 第一行元素（名字，护甲）
    for index, value in pairs({strsplit("#", pfUI.debuffmonitor.target.first_row)}) do
      pfUI.debuffmonitor.target[value] = pfUI.debuffmonitor.target:CreateFontString("Status", "LOW", "GameFontNormal") -- 创建字体字符串
      pfUI.debuffmonitor.target[value]:ClearAllPoints()
      if index == 1 then
        pfUI.debuffmonitor.target[value]:SetPoint("TOPLEFT", pfUI.debuffmonitor.target.row_1, "TOPLEFT", 0, 0)
        pfUI.debuffmonitor.target[value]:SetPoint("BOTTOMRIGHT", pfUI.debuffmonitor.target.row_1, "BOTTOMRIGHT", 0, 0)
      else
        pfUI.debuffmonitor.target[value]:SetPoint("TOPLEFT", pfUI.debuffmonitor.target.row_1, "TOPLEFT", (pfUI.debuffmonitor.target:GetWidth()), 0)
        pfUI.debuffmonitor.target[value]:SetPoint("BOTTOMRIGHT", pfUI.debuffmonitor.target.row_1, "BOTTOMRIGHT", (pfUI.debuffmonitor.target:GetWidth()), 0)
      end
      pfUI.debuffmonitor.target[value]:SetFontObject(GameFontWhite) -- 设置字体对象
      pfUI.debuffmonitor.target[value]:SetFont(font, font_size) -- 设置字体
      pfUI.debuffmonitor.target[value]:SetJustifyH("LEFT") -- 设置水平对齐为左
      pfUI.debuffmonitor.target[value]:SetText(strupper(value)) -- 设置文本
    end

    -- 第二行元素（抵抗）
    local spacing = font_height/6 -- 增加的间距
    for index, value in pairs({strsplit("#", pfUI.debuffmonitor.target.second_row)}) do
      pfUI.debuffmonitor.target[value] = pfUI.debuffmonitor.target:CreateFontString("Status", "LOW", "GameFontNormal") -- 创建字体字符串
      pfUI.debuffmonitor.target[value]:SetWidth(pfUI.debuffmonitor.target:GetWidth()/4)
      pfUI.debuffmonitor.target[value]:ClearAllPoints()
      pfUI.debuffmonitor.target[value]:SetPoint("TOPLEFT", pfUI.debuffmonitor.target.row_2, "TOPLEFT", (pfUI.debuffmonitor.target:GetWidth()/4) * (index - 1), -spacing) -- 增加间距
      pfUI.debuffmonitor.target[value]:SetPoint("BOTTOMRIGHT", pfUI.debuffmonitor.target.row_2, "BOTTOMRIGHT", (pfUI.debuffmonitor.target:GetWidth()/4) * (index - 1), -spacing) -- 增加间距
      pfUI.debuffmonitor.target[value]:SetFontObject(GameFontWhite) -- 设置字体对象
      pfUI.debuffmonitor.target[value]:SetFont(font, font_size) -- 设置字体
      pfUI.debuffmonitor.target[value]:SetJustifyH("LEFT") -- 设置水平对齐为左
      pfUI.debuffmonitor.target[value]:SetText(strupper(value)) -- 设置文本
    end

    -- 调整护甲和冰霜对齐
    pfUI.debuffmonitor.target.armor:SetPoint("TOPLEFT", pfUI.debuffmonitor.target.row_1, "TOPLEFT", (pfUI.debuffmonitor.target:GetWidth()/2) + pfUI.debuffmonitor.target.font_height, 0)
    pfUI.debuffmonitor.target.armor:SetPoint("BOTTOMRIGHT", pfUI.debuffmonitor.target.row_1, "BOTTOMRIGHT", (pfUI.debuffmonitor.target:GetWidth()/2) + pfUI.debuffmonitor.target.font_height, 0)

    pfUI.debuffmonitor.target.debuffs = CreateFrame("Frame", nil, pfUI.debuffmonitor.target)
    pfUI.debuffmonitor.target.debuffs.frames = {}
    -- 按照 debuff_list 的顺序创建减益图标
    for l_name, _ in pairs(debuff_list) do
      pfUI.debuffmonitor.target.debuffs.frames[debuff_list[l_name].short] = CreateDebuff(debuff_list[l_name].name, debuff_list[l_name].short)
    end

    pfUI.debuffmonitor:UnregisterEvent("VARIABLES_LOADED") -- 取消注册事件
    pfUI.debuffmonitor:RegisterEvent("PLAYER_TARGET_CHANGED") -- 注册改变目标事件
    pfUI.debuffmonitor:RegisterEvent("UNIT_AURA") -- 注册目标光环变化（事件驱动，aDF 同款）
    pfUI.debuffmonitor:SetScript("OnEvent", function()
      -- vanilla 1.12: 事件名与参数在隐式全局 event / arg1
      if event == "PLAYER_TARGET_CHANGED" then
        UpdateDisplay() -- 立即刷新显隐/统计
        ScanUnitAuras()
        UpdateIcons()
      elseif event == "UNIT_AURA" then
        -- 仅刷新正在扫描的单位；0.5s 节流（aDF：0.5 平衡响应速度与性能）
        if arg1 and arg1 == pfUI.debuffmonitor.target.unit then
          if (this.aura_ok or 0) <= GetTime() then
            this.aura_ok = GetTime() + 0.5
            ScanUnitAuras()
            UpdateIcons()
          end
        end
      end
    end)
    pfUI.debuffmonitor:SetScript("OnUpdate", function() -- 更新事件
      -- 图标：0.5s 节流统一刷新（旧实现每图标 0.2s 独立全量扫描，性能浪费严重）
      if (this.icon_tick or 0) <= GetTime() then
        this.icon_tick = GetTime() + 0.5
        ScanUnitAuras()
        UpdateIcons()
      end
      -- 显隐/统计：每秒一次
      if (this.tick or 1) > GetTime() then return else this.tick = GetTime() + 1 end
      UpdateDisplay() -- 更新显示
    end)

    pfUI.debuffmonitor:UpdateConfig()  -- 更新配置
    ApplyStatsFontScale() -- 首次应用统计文字字号补偿（存档 scale 可能尚未应用，后续 tick 会修正）

    if nampower.available then
      print("|cff33ffccpfUI-debuffmonitor:|r Nampower 模组已启用 (层数/施法者归属增强)")
    else
      print("|cff33ffccpfUI-debuffmonitor:|r 未检测到 Nampower >= 2.40，层数/施法者显示精度受限")
    end
  end

  function pfUI.debuffmonitor:UpdateConfig() -- 更新配置
    if config.name ~= "1" then
      pfUI.debuffmonitor.target.name:Hide() -- 隐藏名称
    else
      pfUI.debuffmonitor.target.name:Show() -- 显示名称
    end

    if config.armor ~= "1" then
      pfUI.debuffmonitor.target.armor:Hide() -- 隐藏护甲
    else
      pfUI.debuffmonitor.target.armor:Show() -- 显示护甲
    end

    if config.resistances ~= "1" then
      pfUI.debuffmonitor.target.fire:Hide() -- 隐藏火焰抵抗
      pfUI.debuffmonitor.target.nature:Hide() -- 隐藏自然抵抗
      pfUI.debuffmonitor.target.frost:Hide() -- 隐藏冰霜抵抗
      pfUI.debuffmonitor.target.shadow:Hide() -- 隐藏暗影抵抗
      pfUI.debuffmonitor.target:SetHeight(42) -- 设置高度
    else
      pfUI.debuffmonitor.target.fire:Show() -- 显示火焰抵抗
      pfUI.debuffmonitor.target.nature:Show() -- 显示自然抵抗
      pfUI.debuffmonitor.target.frost:Show() -- 显示冰霜抵抗
      pfUI.debuffmonitor.target.shadow:Show() -- 显示暗影抵抗
      pfUI.debuffmonitor.target:SetHeight(56) -- 设置高度
    end

    if config.background ~= "1" then
      pfUI.debuffmonitor.target.backdrop:Hide() -- 隐藏背景
    else
      pfUI.debuffmonitor.target.backdrop:Show() -- 显示背景
    end

    pfUI.debuffmonitor.target:SetPoint("BOTTOMLEFT", pfUI.chat.right or UIParent, "TOPLEFT", 0, 5) -- 设置位置
    UpdateMovable(pfUI.debuffmonitor.target) -- 更新可移动性（存量位置 pfDebuffMonitorTarget 优先）

    UpdateConfigDebuffs() -- 更新减益配置
    UpdateDisplay() -- 更新显示
  end

  pfUI.debuffmonitor:SetScript("OnEvent", pfUI.debuffmonitor.Load) -- 设置事件脚本为加载

  pfUI.debuffmonitor._debuff_list = debuff_list -- 存储减益列表（Frame 覆盖重建后重新挂上）

  -- ==== 诊断命令：/pfdm scan ====
  -- 打印当前目标全部 debuff/buff 槽（索引/层数/纹理/名字）与 Nampower 缓存，
  -- 用于"目标有 debuff 但图标不亮"的纹理匹配排查
  -- ⚠️ 模块跑在 pfUI setfenv 环境里，直接 `SLASH_PFDMS1 = ...` 会写进 env 表而非真全局
  -- （引擎解析 /命令 时只查 _G 的 SLASH_xxx1 ⇒ 报"无效的命令"），必须显式写 _G
  _G["SLASH_PFDMS1"] = "/pfdm"
  _G["SlashCmdList"] = _G["SlashCmdList"] or {}
  _G["SlashCmdList"]["PFDMS"] = function(msg)
    msg = strlower(msg or "")
    if msg == "scan" then
      local unit = pfUI.debuffmonitor.target and pfUI.debuffmonitor.target.unit
      if not unit then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[pfdm]|r 无有效扫描目标（先选中怪）")
        return
      end
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[pfdm]|r 扫描目标: " .. tostring(UnitName(unit)))
      local function DumpAura(auraFunc, tag)
        for i = 1, 64 do
          local tex, stacks = auraFunc(unit, i)
          if not tex then break end
          local name = ""
          if tag == "D" then scanner:SetUnitDebuff(unit, i) else scanner:SetUnitBuff(unit, i) end
          name = scanner:Line(1) or ""
          DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00" .. tag .. i .. "|r x" .. tostring(stacks or 0)
            .. " |cff88ff88" .. tostring(tex) .. "|r " .. tostring(name))
        end
      end
      DumpAura(UnitDebuff, "D")
      DumpAura(UnitBuff, "B")
      -- Nampower 缓存（监控表内条目的 spellId → 纹理 → 层数/施法者）
      if nampower.available and GetUnitGUID then
        local guid = GetUnitGUID(unit)
        local cache = guid and np_cache[guid]
        if cache then
          DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[pfdm] np_cache:|r")
          for spellId, entry in pairs(cache) do
            local remain = entry.expiration and string.format("%.1f", entry.expiration - GetTime()) or "nil"
            DEFAULT_CHAT_FRAME:AddMessage("spell " .. spellId .. " x" .. tostring(entry.stacks)
              .. " |cff88ff88" .. tostring(entry.texture) .. "|r 剩余" .. remain .. "s 施法者:" .. tostring(entry.caster or "无"))
          end
        else
          DEFAULT_CHAT_FRAME:AddMessage("|cff88ccff[pfdm] np_cache:|r 空（guid=" .. tostring(guid) .. "）")
        end
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[pfdm]|r 用法: /pfdm scan（选中怪后扫描其全部光环）")
    end
  end
end)
