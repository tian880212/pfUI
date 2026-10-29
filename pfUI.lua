SLASH_RELOAD1 = '/rl'
function SlashCmdList.RELOAD(msg, editbox)
  ReloadUI()
end

SLASH_PFUI1 = '/pfui'
function SlashCmdList.PFUI(msg, editbox)
  if pfUI.ShowGUI then
    if pfUI.gui and pfUI.gui:IsShown() then
      pfUI.gui:Hide()
    else
      pfUI:ShowGUI()
    end
    return
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[pfUI]|r GUI not ready (a module likely failed to load). Check FrameXML.log for errors and try /reload.")
end

SLASH_GM1, SLASH_GM2 = '/gm', '/support'
function SlashCmdList.GM(msg, editbox)
  ToggleHelpFrame(1)
end

pfUI = CreateFrame("Frame", nil, UIParent)
pfUI:RegisterEvent("ADDON_LOADED")

-- setup bootvar
pfUI.bootup = true

-- initialize saved variables
pfUI_playerDB = {}
pfUI_config = {}
pfUI_init = {}
pfUI_profiles = {}
pfUI_addon_profiles = {}
pfUI_cache = {}
pfUI_throttle = {}

-- localization
pfUI_locale = {}
pfUI_translation = {}

-- initialize default variables
pfUI.cache = {}
pfUI.module = {}
pfUI.modules = {}
pfUI.skin = {}
pfUI.skins = {}
pfUI.environment = {}
pfUI.movables = {}
pfUI.version = {}
pfUI.hooks = {}
pfUI.env = {}

-- check if macro addons are loaded (disables macrotweak/macroscan)
function pfUI:MacroAddonsLoaded()
  return IsAddOnLoaded("Supermacro") or IsAddOnLoaded("SuperCleveRoidMacros") or IsAddOnLoaded("UltimaMacros")
end

-- detect current addon path
local tocs = { "", "-master", "-tbc", "-wotlk" }
for _, name in pairs(tocs) do
  local current = string.format("pfUI%s", name)
  local _, title = GetAddOnInfo(current)
  if title then
    pfUI.name = current
    pfUI.path = "Interface\\AddOns\\" .. current
    break
  end
end

-- handle/convert media dir paths
pfUI.media = setmetatable({}, { __index = function(tab,key)
  local value = tostring(key)
  if strfind(value, "img:") then
    value = string.gsub(value, "img:", pfUI.path .. "\\img\\")
  elseif strfind(value, "font:") then
    value = string.gsub(value, "font:", pfUI.path .. "\\fonts\\")
  else
    value = string.gsub(value, "Interface\\AddOns\\pfUI\\", pfUI.path .. "\\")
  end
  rawset(tab,key,value)
  return value
end})

-- cache client version
local _, _, _, client = GetBuildInfo()
client = client or 11200

-- detect client expansion
if client >= 20000 and client <= 20400 then
  pfUI.expansion = "tbc"
  pfUI.client = client
elseif client >= 30000 and client <= 30300 then
  pfUI.expansion = "wotlk"
  pfUI.client = client
else
  pfUI.expansion = "vanilla"
  pfUI.client = client
end

-- setup pfUI namespace
setmetatable(pfUI.env, {__index = getfenv(0)})

function pfUI:UpdateColors()
  if pfUI.expansion == "vanilla" then
    -- update table to get unknown colors and blue shamans for vanilla
    RAID_CLASS_COLORS = {
      ["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
      ["MAGE"]    = { r = 0.41, g = 0.8,  b = 0.94, colorStr = "ff69ccf0" },
      ["ROGUE"]   = { r = 1,    g = 0.96, b = 0.41, colorStr = "fffff569" },
      ["DRUID"]   = { r = 1,    g = 0.49, b = 0.04, colorStr = "ffff7d0a" },
      ["HUNTER"]  = { r = 0.67, g = 0.83, b = 0.45, colorStr = "ffabd473" },
      ["SHAMAN"]  = { r = 0.14, g = 0.35, b = 1.0,  colorStr = "ff0070de" },
      ["PRIEST"]  = { r = 1,    g = 1,    b = 1,    colorStr = "ffffffff" },
      ["WARLOCK"] = { r = 0.58, g = 0.51, b = 0.79, colorStr = "ff9482c9" },
      ["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73, colorStr = "fff58cba" },
    }

    RAID_CLASS_COLORS = setmetatable(RAID_CLASS_COLORS, { __index = function(tab,key)
      return { r = 0.6,  g = 0.6,  b = 0.6,  colorStr = "ff999999" }
    end})
  end
end

function pfUI:UpdateFonts()
  -- abort when config is not ready yet
  if not pfUI_config or not pfUI_config.global then return end

  -- load font configuration
  local default, tooltip, unit, unit_name, combat
  if pfUI_config.global.force_region == "1" and GetLocale() == "zhCN" and pfUI.expansion == "vanilla" then
    -- force locale compatible fonts (zhCN 1.12)
    default = "Fonts\\FZXHLJW.TTF"
    tooltip = "Fonts\\FZXHLJW.TTF"
    combat = "Fonts\\FZXHLJW.TTF"
    unit = "Fonts\\FZXHLJW.TTF"
    unit_name = "Fonts\\FZXHLJW.TTF"
  elseif pfUI_config.global.force_region == "1" and GetLocale() == "zhCN" and pfUI.expansion == "tbc" then
    -- force locale compatible fonts (zhCN 2.4.3)
    default = "Fonts\\ZYHei.ttf"
    tooltip = "Fonts\\ZYHei.ttf"
    combat = "Fonts\\ZYKai_C.ttf"
    unit = "Fonts\\ZYKai_T.ttf"
    unit_name = "Fonts\\ZYHei.ttf"
  elseif pfUI_config.global.force_region == "1" and GetLocale() == "zhTW" and pfUI.expansion == "vanilla" then
    -- force locale compatible fonts (zhTW 1.12)
    default = "Fonts\\FZXHLJW.ttf"
    tooltip = "Fonts\\FZXHLJW.ttf"
    combat = "Fonts\\FZXHLJW.ttf"
    unit = "Fonts\\FZXHLJW.ttf"
    unit_name = "Fonts\\FZXHLJW.ttf"
  elseif pfUI_config.global.force_region == "1" and GetLocale() == "zhTW" and pfUI.expansion == "tbc" then
    -- force locale compatible fonts (zhTW 2.4.3)
    default = "Fonts\\bHEI01B.ttf"
    tooltip = "Fonts\\bHEI01B.ttf"
    combat = "Fonts\\bHEI01B.ttf"
    unit = "Fonts\\bHEI01B.ttf"
    unit_name = "Fonts\\bHEI01B.ttf"
  elseif pfUI_config.global.force_region == "1" and GetLocale() == "koKR" then
    -- force locale compatible fonts (koKR)
    default = "Fonts\\2002.TTF"
    tooltip = "Fonts\\2002.TTF"
    combat = "Fonts\\2002.TTF"
    unit = "Fonts\\2002.TTF"
    unit_name = "Fonts\\2002.TTF"
  else
    -- use default entries
    default = pfUI.media[pfUI_config.global.font_default]
    tooltip = pfUI.media[pfUI_config.tooltip.font_tooltip]
    combat = pfUI.media[pfUI_config.global.font_combat]
    unit = pfUI.media[pfUI_config.global.font_unit]
    unit_name = pfUI.media[pfUI_config.global.font_unit_name]
  end

  -- write setting shortcuts
  pfUI.font_default = default
  pfUI.font_combat = combat
  pfUI.font_unit = unit
  pfUI.font_unit_name = unit_name

  -- skip setting fonts, keep blizzard defaults
  if pfUI_config.global.font_blizzard == "1" then
    return
  end

  -- set game constants
  STANDARD_TEXT_FONT = default
  DAMAGE_TEXT_FONT   = combat
  NAMEPLATE_FONT     = default
  UNIT_NAME_FONT     = unit_name

  -- If the Invisible font is selected, suppress all combat text entirely
  if string.find(combat or "", "AdobeBlank") then
    SHOW_COMBAT_TEXT = "0"
  end


  -- set dropdown font to default size
  UIDROPDOWNMENU_DEFAULT_TEXT_HEIGHT = 11

  -- change default game font objects
  SystemFont:SetFont(default, 15)
  GameFontNormal:SetFont(default, 12)
  GameFontBlack:SetFont(default, 12)
  GameFontNormalSmall:SetFont(default, 11)
  GameFontNormalLarge:SetFont(default, 16)
  GameFontNormalHuge:SetFont(default, 20)
  NumberFontNormal:SetFont(default, 14, "OUTLINE")
  NumberFontNormalSmall:SetFont(default, 14, "OUTLINE")
  NumberFontNormalLarge:SetFont(default, 16, "OUTLINE")
  NumberFontNormalHuge:SetFont(default, 30, "OUTLINE")
  QuestTitleFont:SetFont(default, 18)
  QuestFont:SetFont(default, 13)
  QuestFontHighlight:SetFont(default, 14)
  ItemTextFontNormal:SetFont(default, 15)
  MailTextFontNormal:SetFont(default, 15)
  SubSpellFont:SetFont(default, 12)
  DialogButtonNormalText:SetFont(default, 16)
  ZoneTextFont:SetFont(default, 34, "OUTLINE")
  SubZoneTextFont:SetFont(default, 24, "OUTLINE")
  GameTooltipText:SetFont(tooltip, pfUI_config.tooltip.font_tooltip_size)
  GameTooltipTextSmall:SetFont(tooltip, pfUI_config.tooltip.font_tooltip_size)
  GameTooltipHeaderText:SetFont(tooltip, pfUI_config.tooltip.font_tooltip_size + 1)
  WorldMapTextFont:SetFont(default, 102, "THICK")
  InvoiceTextFontNormal:SetFont(default, 12)
  InvoiceTextFontSmall:SetFont(default, 12)
  CombatTextFont:SetFont(combat, 25)
  ChatFontNormal:SetFont(default, 13, pfUI_config.chat.text.outline == "1" and "OUTLINE")

  if TextStatusBarTextSmall then -- does not exist in koKR
    TextStatusBarTextSmall:SetFont(default, 12, "NORMAL")
  end
end

local translations
function pfUI:GetEnvironment()
  -- load api into environment
  for m, func in pairs(pfUI.api or {}) do
    pfUI.env[m] = func
  end

  if pfUI_config and pfUI_config.global and pfUI_config.global.language and not translations then
    local lang = pfUI_config and pfUI_config.global and pfUI_config.global.language and pfUI_translation[pfUI_config.global.language] and pfUI_config.global.language or GetLocale()
    pfUI.env.T = setmetatable(pfUI_translation[lang] or {}, { __index = function(tab,key)
      local value = tostring(key)
      rawset(tab,key,value)
      return value
    end})
    translations = true
  end

  pfUI.env._G = getfenv(0)
  pfUI.env.C = pfUI_config
  pfUI.env.pfUI_throttle = _G.pfUI_throttle
  pfUI.env.L = (pfUI_locale[GetLocale()] or pfUI_locale["enUS"])

  return pfUI.env
end

function pfUI:RegisterModule(name, a2, a3)
  if pfUI.module[name] then return end
  local hasv = type(a2) == "string"
  local func, version = hasv and a3 or a2, hasv and a2 or "vanilla:tbc:wotlk"

  -- check for client compatibility
  if not strfind(version, pfUI.expansion) then return end

  pfUI.module[name] = func
  table.insert(pfUI.modules, name)
  if not pfUI.bootup then
    pfUI:LoadModule(name)
  end
end

function pfUI:RegisterSkin(name, a2, a3)
  if pfUI.skin[name] then return end
  local hasv = type(a2) == "string"
  local func, version = hasv and a3 or a2, hasv and a2 or "vanilla:tbc:wotlk"

  -- check for client compatibility
  if not strfind(version, pfUI.expansion) then return end

  pfUI.skin[name] = func
  table.insert(pfUI.skins, name)
  if not pfUI.bootup then
    pfUI:LoadSkin(name)
  end
end

function pfUI:LoadModule(m)
  setfenv(pfUI.module[m], pfUI:GetEnvironment())
  pfUI.module[m]()
end

function pfUI:LoadSkin(s)
  setfenv(pfUI.skin[s], pfUI:GetEnvironment())
  pfUI.skin[s]()
end

-- Open the config GUI. The gui module can be switched off in the module list
-- (or fail to load) which leaves pfUI.gui unset -- every entry point used to
-- error out with "attempt to index field `gui`". Load it on demand instead and
-- report the real reason when that is not possible.
function pfUI:ShowGUI()
  if pfUI.gui then
    pfUI.gui:Show()
    return true
  end

  if not pfUI.module or not pfUI.module["gui"] then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[pfUI]|r gui module was never registered."
      .. " The file failed to compile -- check Interface\\AddOns\\pfUI\\modules\\gui.lua"
      .. " in Logs\\FrameXML.log for the syntax error (Lua 5.0: no '%', no '#', no '//').")
    return false
  end

  -- the module is known but was skipped on bootup, most likely because it is
  -- switched off in the module list -- switch it back on and load it now
  local was = pfUI_config and pfUI_config.disabled and pfUI_config.disabled["gui"]
  if pfUI_config and pfUI_config.disabled then
    pfUI_config.disabled["gui"] = "0"
  end

  local ok, err = pcall(function() pfUI:LoadModule("gui") end)
  if not ok then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[pfUI]|r gui module failed to load: " .. tostring(err))
    return false
  end

  if not pfUI.gui then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[pfUI]|r gui module ran but pfUI.gui is still nil.")
    return false
  end

  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|r|cffffffffUI: gui module was off (disabled.gui="
    .. tostring(was) .. "), re-enabled. Please /reload to restore every settings page.")
  pfUI.gui:Show()
  return true
end

-- [ Place Native Unit Frames ]
-- 原生模式（unitframes.native）：把暴雪原生单人单位框「救回来」并按 pfUI 自己的
-- 存档坐标落位，做到「只换外观、不换位置」。
--
-- ⛔ 必须在 skins 加载之后调用：barbershop.lua 会 PlayerFrame:Hide() 并把
--    PlayerFrame.Show 换成空函数，之后再调 Show 才有意义。
-- ⛔ 坐标写法与 api.LoadMovable 一致：3 参 SetPoint = 相对 parent(UIParent) 的
--    绝对坐标；不要用 GetPoint() 反推（1.12 返回值不可信）。
-- ⛔ C.position 的键名是 "pf"..模块名（pfPlayer / pfTarget / pfPet），不是
--    暴雪框名，见 env/profiles.lua 的 light 档。
-- 可重复调用（幂等），登录后由 OnUpdate 再补两次，防止别的插件/服务器 UI
-- 在 PLAYER_ENTERING_WORLD 之后把原生框排回默认位。
function pfUI:PlaceNativeUnitFrames()
  if not pfUI._nativeUF then return 0 end

  local count = 0

  for i = 1, 3 do
    local f = pfUI._nativeUF[i]
    if f then
      if pfUI._nativeUFShow[i] then
        f.Show = pfUI._nativeUFShow[i]
      end

      f:SetAlpha(1)
      f:EnableMouse(true)

      local pos = pfUI_config.position and pfUI_config.position[pfUI._nativeUFKeys[i]]
      -- ⛔ 正在拖动时一次 SetPoint 都不能调（1.12 会打断 StartMoving ⇒ 拖不动/一放弹回）
      if pos and pos.anchor and pos.xpos and not f.dragging then
        f:ClearAllPoints()
        f:SetPoint(pos.anchor, pos.xpos, pos.ypos or 0)
        if pos.scale then f:SetScale(pos.scale) end
        count = count + 1
      end

      -- 玩家框永远存在；目标/宠物只在真有目标/宠物时显示，否则会留空框
      if f == PlayerFrame or UnitExists(f == PetFrame and "pet" or "target") then
        f:Show()
      end
    end
  end

  -- 队伍框（暴雪 PartyMemberFrame1..4）：同样按 C.position.pfGroup1..4 落位。
  -- ⛔ 暴雪队伍的默认位置写死在客户端左上角，不摆就是「位置不对」。
  -- ⛔ Turtle 客户端的 GroupClusterFrame1-8 是另一套（由 modules/turtle-wow.lua 处理），
  --    实测那套在本机是空壳（宽高 0、从未显示），所以真正露出来的是下面这 4 个。
  local gpos = pfUI_config.position
  for i = 1, 4 do
    local pf = _G["PartyMemberFrame" .. i]
    local p = gpos and gpos["pfGroup" .. i]
    if pf and p and p.anchor and p.xpos and not pf.dragging then
      -- ⛔⛔ 必须显式给 relativeTo（5 参 SetPoint）：pfUI 自己的 LoadMovable 会先按存档
      -- 的 parent 字段 SetParent，再用 3 参 SetPoint 相对「那个父级」算坐标。这里若沿用
      -- 3 参写法、而原生队伍框的父级不是 UIParent，250/-104 就会相对别的容器算 ——
      -- 表现就是「摆下来了，但和 pfUI 的框不重合」。父级也照存档对齐。
      local rel = (p.parent and _G[p.parent]) or UIParent
      if rel and pf:GetParent() ~= rel then
        pf:SetParent(rel)
      end
      pf:ClearAllPoints()
      pf:SetPoint(p.anchor, rel, p.anchor, p.xpos, p.ypos or 0)
      if p.scale then pf:SetScale(p.scale) end
      count = count + 1
    end
  end

  return count
end

-- [ Find Native Tot Frame ]
-- 原生模式下「目标的目标」也交给客户端，modules/targettarget.lua 是直接早退的
-- ⇒ 那个原生框从没进过 pfUI.movables ⇒ 解锁里没有 dragger、拖不动。
-- ⛔ 各客户端/改版 UI 给它的全局名不统一（原版是 TargetofTargetFrame，魔改版常见
--    TargetFrameTargetofTarget / TargetToTFrame），所以先按候选名找，找不到再在 _G
--    里按名字特征扫一遍（1.12 没有按类型枚举 frame 的接口）。
-- ⛔ 全局表里同名的东西不一定是 frame（可能是普通 table）⇒ 一律 pcall 调 GetName()
--    并与键名比对，只有真 frame 才认。
--    找到后缓存在 pfUI._nativeTot，避免每次开解锁都扫一遍全局表。
local function IsFrameNamed(f, name)
  if type(f) ~= "table" or not f.GetName then return false end

  local ok, realname = pcall(f.GetName, f)

  return ok and realname == name
end

function pfUI:FindNativeTotFrame()
  if pfUI._nativeTot then return pfUI._nativeTot end

  local names = {
    "TargetofTargetFrame", "TargetFrameToT", "TargetFrameTot",
    "TargetFrameTargetofTarget", "TargetToTFrame", "TargetofTarget",
  }

  for i = 1, table.getn(names) do
    if IsFrameNamed(_G[names[i]], names[i]) then
      pfUI._nativeTot = _G[names[i]]
      return pfUI._nativeTot
    end
  end

  -- 兜底 1：直接翻 TargetFrame 的直接子框。原生 Tot 一定是它的子级，而且名字在各改版里
  -- 差别很大（TargetFrameToT / TargetofTargetFrame / …），按子树找比按名字猜可靠。
  -- 这个客户端支持多返回值形式 {frame:GetChildren()}（见 addonbuttons.lua / minimap.lua）。
  if TargetFrame and TargetFrame.GetChildren then
    local kids = { TargetFrame:GetChildren() }
    local names = {}

    for i = 1, table.getn(kids) do
      local k = kids[i]
      local n = k and k.GetName and k:GetName()

      if n then
        table.insert(names, n)

        local lower = string.lower(n)
        if string.find(lower, "tot") or string.find(lower, "targetoftarget") then
          pfUI._nativeTot = k
          return k
        end
      end
    end

    -- 没认出来就把子框名打到聊天（一个会话一次）：下一轮据此补候选名，
    -- 不然只能在"没找到框 / 找到错框 / 框画在别处"之间瞎猜。
    if not pfUI._nativeTotNames and table.getn(names) > 0 then
      pfUI._nativeTotNames = true
      DEFAULT_CHAT_FRAME:AddMessage("pfUI native: TargetFrame 子框 = " .. table.concat(names, ","), .8, .8, 1)
    end
  end

  -- 兜底 2：扫 _G，按名字特征找（并优先父级就是 TargetFrame 的那个）。
  local fallback
  for k, v in pairs(_G) do
    if type(k) == "string" and string.sub(k, 1, 2) ~= "pf" then
      local lower = string.lower(k)

      if string.find(lower, "targetoftarget") or string.find(lower, "frametot")
         or string.find(lower, "totframe") or string.find(lower, "targettarget") then
        if IsFrameNamed(v, k) then
          if TargetFrame and v.GetParent and v:GetParent() == TargetFrame then
            pfUI._nativeTot = v
            return v
          end

          if not fallback then fallback = v end
        end
      end
    end
  end

  if fallback then
    pfUI._nativeTot = fallback
    return fallback
  end

  -- ⛔ 只缓存「找到了」：找不到就别写 false，否则万一那个框是别的东西延迟创建的，
  --    这一整个会话都再也认不到了（扫一次 _G 也就几千项，开解锁时跑一次无所谓）。
  return nil
end

-- [ Register Native Movables ]
-- 原生模式（unitframes.native）：把暴雪原生头像框补登记进 pfUI.movables。
-- 不登记的话，解锁模式里它们没有 dragger —— 表现就是「头像/目标头像拖不动」。
-- 坐标键通过 frame.pfSaveName 映射到 pfUI 自己的条目（api.lua 的
-- LoadMovable/SaveMovable/UpdateMovable 都认这个字段）：
--   PlayerFrame → pfPlayer / TargetFrame → pfTarget / PetFrame → pfPet
--   PartyMemberFrame1..4 → pfGroup1..4 / 目标的目标 → pfTargetTarget
-- 好处：拖原生框存下来的就是 pfUI 原本那条坐标，切回 pfUI 模式位置完全一致；
-- 中键回位、滚轮缩放、右键 dock 也都能照常用。
-- ⛔ 必须由 unlock 的 OnShow 调（那时 pfUI.movables 一定已建好）。在 ADDON_LOADED
--    里直接调会因为模块加载顺序拿不到这张表。
function pfUI:RegisterNativeMovables()
  if not (pfUI_config and pfUI_config.unitframes and pfUI_config.unitframes.native == "1") then
    return 0
  end
  if not pfUI.movables then return 0 end

  local list = {
    { PlayerFrame, "pfPlayer" },
    { TargetFrame, "pfTarget" },
    { PetFrame,    "pfPet" },
  }

  for i = 1, 4 do
    table.insert(list, { _G["PartyMemberFrame" .. i], "pfGroup" .. i })
  end

  -- 目标的目标：native 下 pfTargetTarget 这个键是空的（targettarget 模块早退没建框），
  -- 正好让原生 Tot 框占住 —— 拖动存下来的位置切回 pfUI 模式也照样生效。
  local tot = pfUI:FindNativeTotFrame()
  if tot then
    -- 别的皮肤可能把它 alpha 成 0（原生目标框被接管时常见），救回一次
    if tot.SetAlpha then tot:SetAlpha(1) end
    table.insert(list, { tot, "pfTargetTarget" })
  elseif not pfUI._nativeTotWarn then
    -- 只在会话里提示一次：找不到这个框时解锁模式下它拖不了，用户看到这条就能直接回报
    -- （而不是在"到底没找到框还是框画在了别处"之间猜）。
    pfUI._nativeTotWarn = true
    DEFAULT_CHAT_FRAME:AddMessage("pfUI native: 未定位到原生「目标的目标」框，解锁模式下无法单独移动它。", 1, .5, .5)
  end

  local count = 0
  for i = 1, table.getn(list) do
    local f, key = list[i][1], list[i][2]
    if f and key then
      f.pfSaveName = key

      -- ⛔⛔ 必须「强制」占位，不能只靠 UpdateMovable 的「键不存在才登记」
      --     （api.lua:992 `if not pfUI.movables[name]`）。原生模式下 modules/target.lua
      --     仍会建一个 alpha=0 的 pfUI 目标框（当 debuff/计时宿主），它加载更早、
      --     已经占了 pfUI.movables["pfTarget"] ⇒ 原生 TargetFrame 永远登记不进来。
      --     表现就是「解锁后玩家框有内容、目标框是个空的窄条」：
      --       玩家框 = 原生 PlayerFrame（player.lua 直接 return，没建 pfUI 玩家框，键空着）
      --       目标框 = 那个隐形的 pfUI 目标框（200x46），原生目标框根本没有 dragger。
      local old = pfUI.movables[key]
      if old and old ~= f then
        pfUI.movables[key] = nil
        -- 隐形宿主本来就不该出现在解锁模式里：dragger 一并收掉（alpha=0 的按钮
        -- 仍然吃鼠标，留着会挡住下面真正的原生框）
        if old.drag then
          old.drag:Hide()
          old.drag = nil
        end
        -- ⛔ 只摘登记、不要 Hide 宿主框本身：它还是 buff 图标的父级，
        --    Hide 会把图标一起带走（就是之前「光环全没」那个坑）。
      end

      -- 先占位再 UpdateMovable：它看到键已存在就不会被旧框顶回去，
      -- 同时照常跑 LoadMovable 按 C.position 摆位。
      pfUI.movables[key] = f
      pfUI.api.UpdateMovable(f)
      count = count + 1
    end
  end

  return count
end

pfUI:SetScript("OnEvent", function()
  -- enforce color updates on each event
  pfUI:UpdateColors()

  -- make sure to initialize and set our fonts
  -- each time an addon got loaded but only
  -- when the config is already accessible
  if not pfUI.bootup then
    pfUI:UpdateFonts()
  end

  if arg1 == pfUI.name then
    -- read pfUI version from .toc file
    local major, minor, fix = pfUI.api.strsplit(".", tostring(GetAddOnMetadata(pfUI.name, "Version")))
    pfUI.version.major = tonumber(major) or 1
    pfUI.version.minor = tonumber(minor) or 2
    pfUI.version.fix   = tonumber(fix)   or 0
    pfUI.version.string = pfUI.version.major .. "." .. pfUI.version.minor .. "." .. pfUI.version.fix

    -- use "light" as default profile on a fresh install
    if pfUI.api.isempty(pfUI_init) and pfUI.api.isempty(pfUI_config) then
      pfUI_config = pfUI.api.CopyTable(pfUI_profiles["light"]) or {}
    end

    pfUI:LoadConfig()
    pfUI:MigrateConfig()
    pfUI:UpdateFonts()

    -- 原生模式（unitframes.native）：先把暴雪原生框真正的 Show 存下来。
    -- ⛔⛔ skins 在 modules 之后加载，barbershop.lua 会 PlayerFrame:Hide() 并把
    --     PlayerFrame.Show 换成空函数 —— 一旦换掉就再也找不回来，必须提前备份。
    if pfUI_config.unitframes and pfUI_config.unitframes.native == "1" then
      pfUI._nativeUF = { PlayerFrame, TargetFrame, PetFrame }
      pfUI._nativeUFKeys = { "pfPlayer", "pfTarget", "pfPet" }
      pfUI._nativeUFShow = { PlayerFrame and PlayerFrame.Show,
                             TargetFrame and TargetFrame.Show,
                             PetFrame and PetFrame.Show }
    end

    -- load modules
    for _, m in pairs(this.modules) do
      if not ( pfUI_config["disabled"] and pfUI_config["disabled"][m]  == "1" ) then
        pfUI:LoadModule(m)
      end
    end

    -- load skins
    for _, s in pairs(this.skins) do
      if not ( pfUI_config["disabled"] and pfUI_config["disabled"]["skin_" .. s]  == "1" ) then
        pfUI:LoadSkin(s)
      end
    end

    -- 原生模式收尾：skin 跑完再把被隐藏 / 被 stub 掉的原生框救回来，
    -- 并且**按 pfUI 自己存档的坐标落位**（切原生模式只换外观、不换位置）。
    if pfUI._nativeUF then
      pfUI:PlaceNativeUnitFrames()

      -- 把原生框也登记进 pfUI.movables（解锁模式才有 dragger 可拖）。
      -- 幂等；unlock 每次打开时还会再调一次兜底。
      pfUI:RegisterNativeMovables()

      -- 再补两次：有的服务器 UI / 别的插件会在 PLAYER_ENTERING_WORLD 之后
      -- 把 PlayerFrame/TargetFrame 排回暴雪默认位（左上角/顶部中间），
      -- 只在登录那一刻摆一次会被覆盖掉。
      if not pfUI._nativeFix then
        local fix = CreateFrame("Frame", nil, UIParent)
        fix.elapsed, fix.stage, fix.samples = 0, 0, ""
        fix:Show()
        fix:SetScript("OnUpdate", function()
          this.elapsed = this.elapsed + arg1

          -- 每次补位前先采样，用来判断「是我们没摆」还是「摆完被别人挪走」
          if this.stage == 0 and this.elapsed > 2 then
            this.stage = 1
            this.samples = "PF@2=" .. tostring(PlayerFrame and PlayerFrame:GetLeft())
              .. "," .. tostring(PlayerFrame and PlayerFrame:GetTop())
            pfUI:PlaceNativeUnitFrames()
          elseif this.stage == 1 and this.elapsed > 5 then
            this.stage = 2
            this.samples = this.samples .. " PF@5=" .. tostring(PlayerFrame and PlayerFrame:GetLeft())
              .. "," .. tostring(PlayerFrame and PlayerFrame:GetTop())
            pfUI:PlaceNativeUnitFrames()
          elseif this.stage == 2 and this.elapsed > 10 then
            this.stage = 3
            local n = pfUI:PlaceNativeUnitFrames()
            this:SetScript("OnUpdate", nil)

            -- 一次性自检（确认没问题后可删）
            local p = pfUI_config.position and pfUI_config.position["pfPlayer"]
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|r|cffffffffUI|r native: placed="
              .. tostring(n)
              .. " cfg=" .. tostring(p and (tostring(p.anchor) .. " " .. tostring(p.xpos) .. "," .. tostring(p.ypos)))
              .. " pts=" .. tostring(PlayerFrame and PlayerFrame:GetNumPoints())
              .. " " .. this.samples
              .. " PF@10=" .. tostring(PlayerFrame and PlayerFrame:GetLeft())
              .. "," .. tostring(PlayerFrame and PlayerFrame:GetTop())
              .. " TF@10=" .. tostring(TargetFrame and TargetFrame:GetLeft())
              .. "," .. tostring(TargetFrame and TargetFrame:GetTop())
              -- 队伍框实测：用来判断「没摆上」还是「摆上了但尺寸不同」
              .. " | P1=" .. tostring(PartyMemberFrame1 and PartyMemberFrame1:GetLeft())
              .. "/" .. tostring(PartyMemberFrame1 and PartyMemberFrame1:GetTop())
              .. " w=" .. tostring(PartyMemberFrame1 and PartyMemberFrame1:GetWidth())
              .. " h=" .. tostring(PartyMemberFrame1 and PartyMemberFrame1:GetHeight())
              .. " us=" .. tostring(UIParent:GetScale())
              .. " uw=" .. tostring(UIParent:GetWidth())
              -- 目标的目标：nil = 这个客户端里没找到它（候选名对不上），
              -- 有名字但坐标为 nil = 找到了但没被摆上/没显示
              .. " | TOT=" .. tostring(pfUI._nativeTot and pfUI._nativeTot:GetName())
              .. " p=" .. tostring(pfUI._nativeTot and pfUI._nativeTot:GetParent()
                             and pfUI._nativeTot:GetParent():GetName())
              .. " " .. tostring(pfUI._nativeTot and pfUI._nativeTot:GetLeft())
              .. "," .. tostring(pfUI._nativeTot and pfUI._nativeTot:GetTop()))
          end
        end)
        pfUI._nativeFix = fix
      end
    elseif pfUI_config.unitframes and pfUI_config.unitframes.native == "1" then
      -- native 开着但备份没拿到：说明 player/target/pet 三个全局在 pfUI 的
      -- ADDON_LOADED 时刻还不存在（客户端变体），退化为不落位，先报出来
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|r|cffffffffUI|r native: capture failed (PF="
        .. tostring(PlayerFrame) .. " TF=" .. tostring(TargetFrame) .. ")")
    end

    -- the config GUI is the only way to switch modules back on, so make sure a
    -- missing gui module is reported instead of silently breaking the button
    if not pfUI.gui then
      local reason = pfUI_config and pfUI_config.disabled and pfUI_config.disabled["gui"]
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[pfUI]|r gui module did not load"
        .. " (disabled.gui=" .. tostring(reason) .. ", registered="
        .. tostring(pfUI.module and pfUI.module["gui"] and true or false) .. "). Use /pfui to retry.")
    end

    pfUI.bootup = nil
  end
end)

pfUI.backdrop = {
  bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
  edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
  insets = {left = -1, right = -1, top = -1, bottom = -1},
}
pfUI.backdrop_no_top = pfUI.backdrop

pfUI.backdrop_thin = {
  bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
  edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
  insets = {left = 0, right = 0, top = 0, bottom = 0},
}

pfUI.backdrop_hover = {
  edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 24,
  insets = {left = -1, right = -1, top = -1, bottom = -1},
}

pfUI.backdrop_shadow = {
  edgeFile = pfUI.media["img:glow2"], edgeSize = 8,
  insets = {left = 0, right = 0, top = 0, bottom = 0},
}

pfUI.backdrop_blizz_bg = {
  bgFile =  "Interface\\BUTTONS\\WHITE8X8", tile = true, tileSize = 8,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

pfUI.backdrop_blizz_border = {
  edgeFile = pfUI.media["img:border_blizz"], edgeSize = 6,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

pfUI.backdrop_blizz_full = {
  bgFile =  "Interface\\BUTTONS\\WHITE8X8", tile = true, tileSize = 8,
  edgeFile = pfUI.media["img:border_blizz"], edgeSize = 6,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

message = function(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffcccc33INFO: |cffffff55" .. ( msg or "nil" ))
end
print = print or message

-- Error display hook.
--
-- This is deliberately NOT assigned to the global `error`. Overwriting `error`
-- with a print-only version silently changes the control flow of every other
-- addon: any error() they raise to abort an operation would just print and let
-- execution continue into a broken state. `error` is left untouched and this
-- function is installed as the error handler instead, which is all that is
-- needed to show runtime errors in the chat frame rather than in the default
-- red box in the middle of the screen.
local function pfUI_ErrorHandler(msg)
  if string.find(msg or "", "AddOns\\pfUI") then
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc3333ERROR: |cffff5555".. (msg or "nil" ))
  elseif not pfUI_config or (pfUI_config.global and pfUI_config.global.errors == "1") then
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc3333ERROR: |cffff5555".. (msg or "nil" ))
  end
end
seterrorhandler(pfUI_ErrorHandler)

function pfUI.SetupCVars()
  ClearTutorials()
  TutorialFrame_HideAllAlerts()

  ConsoleExec("CameraDistanceMaxFactor 5")

  SetCVar("autoSelfCast", "1")
  SetCVar("profanityFilter", "0")

  MultiActionBar_ShowAllGrids()
  ALWAYS_SHOW_MULTIBARS = "1"

  SHOW_BUFF_DURATIONS = "1"
  QUEST_FADING_DISABLE = "1"
  NAMEPLATES_ON = "1"
  SIMPLE_CHAT = "0"

  -- Only force combat text CVars when not using the Invisible font.
  -- If AdobeBlank is selected, the player wants no combat text -- respect that.
  local isInvisible = pfUI_config.global.font_combat and
    string.find(pfUI_config.global.font_combat, "AdobeBlank")
  if not isInvisible then
    SHOW_COMBAT_TEXT = "1"
    COMBAT_TEXT_SHOW_LOW_HEALTH_MANA = "1"
    COMBAT_TEXT_SHOW_AURAS = "1"
    COMBAT_TEXT_SHOW_AURA_FADE = "1"
    COMBAT_TEXT_SHOW_COMBAT_STATE = "1"
    COMBAT_TEXT_SHOW_DODGE_PARRY_MISS = "1"
    COMBAT_TEXT_SHOW_RESISTANCES = "1"
    COMBAT_TEXT_SHOW_REPUTATION = "1"
    COMBAT_TEXT_SHOW_REACTIVES = "1"
    COMBAT_TEXT_SHOW_FRIENDLY_NAMES = "1"
    COMBAT_TEXT_SHOW_COMBO_POINTS = "1"
    COMBAT_TEXT_SHOW_MANA = "1"
    COMBAT_TEXT_FLOAT_MODE = "1"
    COMBAT_TEXT_SHOW_HONOR_GAINED = "1"
  end
  UIParentLoadAddOn("Blizzard_CombatText")
end