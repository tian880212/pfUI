-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

function pfUI:UpdateConfig(group, subgroup, entry, value)
  -- create empty config if not existing
  if not pfUI_config then
    _G.pfUI_config = {}
  end

  -- check for missing config groups
  if not pfUI_config[group] then
    pfUI_config[group] = {}
  end

  -- update config
  if not subgroup and entry and value and not pfUI_config[group][entry] then
    pfUI_config[group][entry] = value
  end

  -- check for missing config subgroups
  if subgroup and not pfUI_config[group][subgroup] then
    pfUI_config[group][subgroup] = {}
  end

  -- update config in subgroup
  if subgroup and entry and value and not pfUI_config[group][subgroup][entry] then
    pfUI_config[group][subgroup][entry] = value
  end
end

function pfUI:LoadConfig()
  --                MODULE        SUBGROUP       ENTRY               VALUE
  pfUI:UpdateConfig("global",     nil,           "language",         GetLocale())
  pfUI:UpdateConfig("global",     nil,           "profile",          "light")
  pfUI:UpdateConfig("global",     nil,           "pixelperfect",     "0")
  pfUI:UpdateConfig("global",     nil,           "offscreen",        "0")
  -- 解锁模式的吸附对齐（unlock.lua）：unlock_snap "1"/"0"，距离为 UI 单位（手动输入，默认 1）
  pfUI:UpdateConfig("global",     nil,           "unlock_snap",          "1")
  pfUI:UpdateConfig("global",     nil,           "unlock_snap_distance", "8")

  pfUI:UpdateConfig("global",     nil,           "font_blizzard",    "0")
  pfUI:UpdateConfig("global",     nil,           "font_default",     "Interface\\AddOns\\pfUI\\fonts\\Myriad-Pro.ttf")
  pfUI:UpdateConfig("global",     nil,           "font_size",        "12")
  pfUI:UpdateConfig("global",     nil,           "font_unit",        "Interface\\AddOns\\pfUI\\fonts\\BigNoodleTitling.ttf")
  pfUI:UpdateConfig("global",     nil,           "font_unit_size",   "12")
  pfUI:UpdateConfig("global",     nil,           "font_unit_style",  "OUTLINE")
  pfUI:UpdateConfig("global",     nil,           "font_unit_name",   "Interface\\AddOns\\pfUI\\fonts\\Myriad-Pro.ttf")
  pfUI:UpdateConfig("global",     nil,           "font_combat",      "Interface\\AddOns\\pfUI\\fonts\\Continuum.ttf")

  pfUI:UpdateConfig("global",     nil,           "force_region",     "1")
  pfUI:UpdateConfig("global",     nil,           "errors",           "1")
  pfUI:UpdateConfig("global",     nil,           "errors_limit",     "1")
  pfUI:UpdateConfig("global",     nil,           "errors_hide",      "0")
  pfUI:UpdateConfig("global",     nil,           "hidebuff",         "0")
  pfUI:UpdateConfig("global",     nil,           "hidewbuff",        "0")
  pfUI:UpdateConfig("global",     nil,           "twentyfour",       "1")
  pfUI:UpdateConfig("global",     nil,           "servertime",       "0")
  pfUI:UpdateConfig("global",     nil,           "autosell",         "0")
  pfUI:UpdateConfig("global",     nil,           "autorepair",       "0")
  pfUI:UpdateConfig("global",     nil,           "buyemall",         "1")
  pfUI:UpdateConfig("global",     nil,           "libhealth",        "1")
  pfUI:UpdateConfig("global",     nil,           "libhealth_hit",    "4")
  pfUI:UpdateConfig("global",     nil,           "libhealth_dmg",    ".05")
  pfUI:UpdateConfig("global",     nil,           "colorblind",       "0")
  pfUI:UpdateConfig("global",     nil,           "autodismount",     "1")

  pfUI:UpdateConfig("gui",        nil,           "reloadmarker",     "0")
  pfUI:UpdateConfig("gui",        nil,           "showdisabled",     "0")

  pfUI:UpdateConfig("buffs",      nil,           "buffs",            "1")
  pfUI:UpdateConfig("buffs",      nil,           "debuffs",          "1")
  pfUI:UpdateConfig("buffs",      nil,           "weapons",          "1")
  pfUI:UpdateConfig("buffs",      nil,           "separateweapons",  "0")
  pfUI:UpdateConfig("buffs",      nil,           "separatebuffs",    "0")
  pfUI:UpdateConfig("buffs",      nil,           "separatelist",     "")
  pfUI:UpdateConfig("buffs",      nil,           "sepbuffsize",      "36")
  pfUI:UpdateConfig("buffs",      nil,           "sepbuffrowsize",   "8")
  pfUI:UpdateConfig("buffs",      nil,           "sepbuffglow",      "1")
  pfUI:UpdateConfig("buffs",      nil,           "sepbuffmonitor",   "0")
  pfUI:UpdateConfig("buffs",      nil,           "separatedebuffs",  "0")
  pfUI:UpdateConfig("buffs",      nil,           "sepdebufflist",    "")
  pfUI:UpdateConfig("buffs",      nil,           "sepdebuffsize",    "36")
  pfUI:UpdateConfig("buffs",      nil,           "sepdebuffrowsize", "8")
  pfUI:UpdateConfig("buffs",      nil,           "sepdebuffglow",    "1")
  pfUI:UpdateConfig("buffs",      nil,           "sepdebuffmonitor", "0")
  pfUI:UpdateConfig("buffs",      nil,           "separatetargetbuffs",   "0")
  pfUI:UpdateConfig("buffs",      nil,           "septargetbufflist",     "")
  pfUI:UpdateConfig("buffs",      nil,           "septargetbuffsize",     "36")
  pfUI:UpdateConfig("buffs",      nil,           "septargetbuffrowsize",  "8")
  pfUI:UpdateConfig("buffs",      nil,           "septargetbuffglow",     "1")
  pfUI:UpdateConfig("buffs",      nil,           "separatetargetdebuffs", "0")
  pfUI:UpdateConfig("buffs",      nil,           "septargetdebufflist",   "")
  pfUI:UpdateConfig("buffs",      nil,           "septargetdebuffsize",   "36")
  pfUI:UpdateConfig("buffs",      nil,           "septargetdebuffrowsize","8")
  pfUI:UpdateConfig("buffs",      nil,           "septargetdebuffglow",   "1")
  pfUI:UpdateConfig("buffs",      nil,           "size",             "24")
  pfUI:UpdateConfig("buffs",      nil,           "spacing",          "5")
  pfUI:UpdateConfig("buffs",      nil,           "wepbuffrowsize",   "2")
  pfUI:UpdateConfig("buffs",      nil,           "buffrowsize",      "16")
  pfUI:UpdateConfig("buffs",      nil,           "debuffrowsize",    "16")
  pfUI:UpdateConfig("buffs",      nil,           "textinside",       "0")
  pfUI:UpdateConfig("buffs",      nil,           "sep_textinside",   "0") -- 监控条（分离式Buff/Debuff）独立的「显示持续时间在Buff里面」；默认 0 与存量行为一致
  pfUI:UpdateConfig("buffs",      nil,           "sep_fontsize",     "-1") -- 监控条独立字号；-1=跟随主 Buff 字号（存量行为）
  pfUI:UpdateConfig("buffs",      nil,           "fontsize",         "-1")
  pfUI:UpdateConfig("buffs",      nil,           "filter",           "none")
  pfUI:UpdateConfig("buffs",      nil,           "whitelist",        "")
  pfUI:UpdateConfig("buffs",      nil,           "blacklist",        "")
  pfUI:UpdateConfig("buffs",      nil,           "exacttime",        "1")																		 

  pfUI:UpdateConfig("buffbar",    "pbuff",       "enable",           "0")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "use_unitfonts",    "0")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "sort",             "asc")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "color",            ".5,.5,.5,1")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "bordercolor",      "0,0,0,0")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "textcolor",        "1,1,1,1")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "dtypebg",          "1")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "dtypeborder",      "0")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "dtypetext",        "0")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "colorstacks",      "0")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "width",            "-1")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "height",           "20")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "filter",           "blacklist")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "threshold",        "120")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "whitelist",        "")
  pfUI:UpdateConfig("buffbar",    "pbuff",       "blacklist",        "")

  pfUI:UpdateConfig("buffbar",    "pdebuff",     "enable",           "0")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "use_unitfonts",    "0")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "sort",             "asc")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "color",            "8,.4,.4,1")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "bordercolor",      "0,0,0,0")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "textcolor",        "1,1,1,1")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "dtypebg",          "0")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "dtypeborder",      "1")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "dtypetext",        "0")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "colorstacks",      "0")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "width",            "-1")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "height",           "20")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "filter",           "blacklist")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "threshold",        "120")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "whitelist",        "")
  pfUI:UpdateConfig("buffbar",    "pdebuff",     "blacklist",        "")

  pfUI:UpdateConfig("buffbar",    "tdebuff",     "enable",           "0")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "use_unitfonts",    "0")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "sort",             "asc")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "color",            ".8,.4,.4,1")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "bordercolor",      "0,0,0,0")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "textcolor",        "1,1,1,1")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "dtypebg",          "0")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "dtypeborder",      "1")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "dtypetext",        "0")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "colorstacks",      "0")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "width",            "-1")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "height",           "20")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "selfdebuff",       "0")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "filter",           "blacklist")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "threshold",        "120")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "whitelist",        "")
  pfUI:UpdateConfig("buffbar",    "tdebuff",     "blacklist",        "")

  pfUI:UpdateConfig("appearance", "border",      "background",       "0,0,0,1")
  pfUI:UpdateConfig("appearance", "border",      "color",            "0.2,0.2,0.2,1")
  pfUI:UpdateConfig("appearance", "border",      "shadow",           "0")
  pfUI:UpdateConfig("appearance", "border",      "shadow_intensity", ".35")
  pfUI:UpdateConfig("appearance", "border",      "pixelperfect",     "1")
  pfUI:UpdateConfig("appearance", "border",      "force_blizz",      "0")
  pfUI:UpdateConfig("appearance", "border",      "hidpi",            "1")
  pfUI:UpdateConfig("appearance", "border",      "default",          "3")
  pfUI:UpdateConfig("appearance", "border",      "nameplates",       "-1")
  pfUI:UpdateConfig("appearance", "border",      "actionbars",       "-1")
  pfUI:UpdateConfig("appearance", "border",      "unitframes",       "-1")
  pfUI:UpdateConfig("appearance", "border",      "panels",           "-1")
  pfUI:UpdateConfig("appearance", "border",      "chat",             "-1")
  pfUI:UpdateConfig("appearance", "border",      "bags",             "-1")
  pfUI:UpdateConfig("appearance", "cd",          "lowcolor",         "1,.2,.2,1")
  pfUI:UpdateConfig("appearance", "cd",          "normalcolor",      "1,1,1,1")
  pfUI:UpdateConfig("appearance", "cd",          "minutecolor",      ".2,1,1,1")
  pfUI:UpdateConfig("appearance", "cd",          "hourcolor",        ".2,.5,1,1")
  pfUI:UpdateConfig("appearance", "cd",          "daycolor",         ".2,.2,1,1")
  pfUI:UpdateConfig("appearance", "cd",          "threshold",        "2")
  pfUI:UpdateConfig("appearance", "cd",          "font_size",        "12")
  pfUI:UpdateConfig("appearance", "cd",          "font_size_blizz",  "12")
  pfUI:UpdateConfig("appearance", "cd",          "font_size_foreign","12")
  pfUI:UpdateConfig("appearance", "cd",          "blizzard",         "1")
  pfUI:UpdateConfig("appearance", "cd",          "foreign",          "0")
  pfUI:UpdateConfig("appearance", "cd",          "milliseconds",     "1")
  pfUI:UpdateConfig("appearance", "cd",          "hideanim",         "0")
  pfUI:UpdateConfig("appearance", "cd",          "font",             "Interface\\AddOns\\pfUI\\fonts\\BigNoodleTitling.ttf")
  pfUI:UpdateConfig("appearance", "cd",          "dynamicsize",      "1")
  pfUI:UpdateConfig("appearance", "castbar",     "castbarcolor",     ".7,.7,.9,.8")
  pfUI:UpdateConfig("appearance", "castbar",     "channelcolor",     ".9,.9,.7,.8")
  pfUI:UpdateConfig("appearance", "castbar",     "texture",          "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
  -- 全局材质（外观设置）：off = 不批量修改，各处保持独立设置；选择具体材质时批量写入所有进度条材质配置
  pfUI:UpdateConfig("appearance", "texture",     "default",          "off")
  pfUI:UpdateConfig("appearance", "infight",     "screen",           "0")
  pfUI:UpdateConfig("appearance", "infight",     "aggro",            "0")
  pfUI:UpdateConfig("appearance", "infight",     "health",           "1")
  pfUI:UpdateConfig("appearance", "infight",     "intensity",           "16")
  pfUI:UpdateConfig("appearance", "bags",        "unusable",         "1")
  pfUI:UpdateConfig("appearance", "bags",        "unusable_color",   ".9,.2,.2,1")
  pfUI:UpdateConfig("appearance", "bags",        "borderlimit",      "1")
  pfUI:UpdateConfig("appearance", "bags",        "borderonlygear",   "0")
  pfUI:UpdateConfig("appearance", "bags",        "fulltext",         "1")
  pfUI:UpdateConfig("appearance", "bags",        "movable",          "0")
  pfUI:UpdateConfig("appearance", "bags",        "abovechat",        "0")
  pfUI:UpdateConfig("appearance", "bags",        "hidechat",         "0")
  pfUI:UpdateConfig("appearance", "bags",        "icon_size",        "-1")
  pfUI:UpdateConfig("appearance", "bags",        "bagrowlength",     "10")
  pfUI:UpdateConfig("appearance", "bags",        "bankrowlength",    "10")
  pfUI:UpdateConfig("appearance", "minimap",     "size",             "140")
  pfUI:UpdateConfig("appearance", "minimap",     "arrowscale",       "1")
  pfUI:UpdateConfig("appearance", "minimap",     "zonetext",         "off")
  pfUI:UpdateConfig("appearance", "minimap",     "coordstext",       "mouseover")
  pfUI:UpdateConfig("appearance", "minimap",     "coordsloc",        "bottomleft")
  pfUI:UpdateConfig("appearance", "minimap",     "tracking_size",    "16")
  pfUI:UpdateConfig("appearance", "minimap",     "tracking_pulse",   "1")
  pfUI:UpdateConfig("appearance", "minimap",     "addon_buttons",    "0")
  pfUI:UpdateConfig("appearance", "worldmap",    "tooltipsize",      "0")
  pfUI:UpdateConfig("appearance", "worldmap",    "mapreveal",        "0")
  pfUI:UpdateConfig("appearance", "worldmap",    "mapreveal_color",  ".4,.4,.4,1")
  pfUI:UpdateConfig("appearance", "worldmap",    "mapexploration",   "0")
  pfUI:UpdateConfig("appearance", "worldmap",    "groupcircles",     "3")
  pfUI:UpdateConfig("appearance", "worldmap",    "colornames",       "1")

  pfUI:UpdateConfig("loot",       nil,           "autoresize",       "1")
  pfUI:UpdateConfig("loot",       nil,           "autopickup",       "1")
  pfUI:UpdateConfig("loot",       nil,           "mousecursor",      "1")
  pfUI:UpdateConfig("loot",       nil,           "advancedloot",     "1")
  pfUI:UpdateConfig("loot",       nil,           "rollannouncequal", "3")
  pfUI:UpdateConfig("loot",       nil,           "rollannounce",     "0")
  pfUI:UpdateConfig("loot",       nil,           "raritytimer",      "1")
  -- 新增的通报配置
  pfUI:UpdateConfig("loot",       nil,           "announce_enabled",   "1")
  pfUI:UpdateConfig("loot",       nil,           "announce_merge",   "0")
  pfUI:UpdateConfig("loot",       nil,           "announce_numbers", "1")
  pfUI:UpdateConfig("loot",       nil,           "announce_quality", "3")
  pfUI:UpdateConfig("loot",       nil,           "announce_stacksize", "1")

  pfUI:UpdateConfig("unitframes", nil,           "disable",          "0")
  pfUI:UpdateConfig("unitframes", nil,           "pastel",           "1")
  pfUI:UpdateConfig("unitframes", nil,           "custom",           "0")
  pfUI:UpdateConfig("unitframes", nil,           "customfullhp",     "0")
  pfUI:UpdateConfig("unitframes", nil,           "customfade",       "0")
  pfUI:UpdateConfig("unitframes", nil,           "customcolor",      ".2,.2,.2,1")
  pfUI:UpdateConfig("unitframes", nil,           "custombg",         "0")
  pfUI:UpdateConfig("unitframes", nil,           "custombgcolor",    ".5,.2,.2,1")
  pfUI:UpdateConfig("unitframes", nil,           "custompbg",        "0")
  pfUI:UpdateConfig("unitframes", nil,           "custompbgcolor",   ".5,.2,.2,1")
  pfUI:UpdateConfig("unitframes", nil,           "manacolor",        ".5,.5,1,1")
  pfUI:UpdateConfig("unitframes", nil,           "energycolor",      "1,1,.5,1")
  pfUI:UpdateConfig("unitframes", nil,           "ragecolor",        "1,.5,.5,1")
  pfUI:UpdateConfig("unitframes", nil,           "focuscolor",       "1,1,.75,1")

  pfUI:UpdateConfig("unitframes", nil,           "animation_speed",  "5")
  pfUI:UpdateConfig("unitframes", nil,           "portraitalpha",    "0.1")
  pfUI:UpdateConfig("unitframes", nil,           "always2dportrait", "0")
  pfUI:UpdateConfig("unitframes", nil,           "portraittexture",  "1")
  pfUI:UpdateConfig("unitframes", nil,           "layout",           "default")
  pfUI:UpdateConfig("unitframes", nil,           "rangecheck",       "0")
  pfUI:UpdateConfig("unitframes", nil,           "rangecheck_mode",  "vanilla")
  pfUI:UpdateConfig("unitframes", nil,           "rangecheck_distance", "40")																			 
  pfUI:UpdateConfig("unitframes", nil,           "buffdetect",       "0")
																			  
  pfUI:UpdateConfig("unitframes", nil,           "druidmanabar",     "1")
  pfUI:UpdateConfig("unitframes", nil,           "druidmanafont",    "0")
  pfUI:UpdateConfig("unitframes", nil,           "druidmanafontsize",  "12")
  pfUI:UpdateConfig("unitframes", nil,           "druidmanafontcolor",  ".5,.5,1,1")
  pfUI:UpdateConfig("unitframes", nil,           "druidmanaheight",  "10")
  pfUI:UpdateConfig("unitframes", nil,           "druidmanawidth",   "-1")
  pfUI:UpdateConfig("unitframes", nil,           "druidmanaoffx",    "0")
  pfUI:UpdateConfig("unitframes", nil,           "druidmanaoffy",    "0")
  pfUI:UpdateConfig("unitframes", nil,           "druidmanaspace",   "-3")
  pfUI:UpdateConfig("unitframes", nil,           "druidmanatexture", "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")

  pfUI:UpdateConfig("unitframes", nil,           "rangechecki",      "4")

  -- combopoints（目标连击点外观。combowidth/comboheight 是旧键，保留不动）
  -- 默认值取自 light 档角色「最爱扎你」的存档（2026-10-23），即当前实际在用的观感：
  -- 水平向右、40.5 宽 x 6 高、点间距 3、满点闪光开启。
  -- ⚠️ 存档位置只有 pfCombo1 生效，2-5 靠 combogrow + combospacing 链出来，
  --    这两个默认值一旦偏离 light 档，进游戏就会看起来"跟以前不一样"。
  pfUI:UpdateConfig("unitframes", nil,           "comboshow",        "1")
  pfUI:UpdateConfig("unitframes", nil,           "combostyle",       "pips")
  pfUI:UpdateConfig("unitframes", nil,           "combogrow",        "right")
  pfUI:UpdateConfig("unitframes", nil,           "combowidth",       "40.5")
  pfUI:UpdateConfig("unitframes", nil,           "comboheight",      "6")
  pfUI:UpdateConfig("unitframes", nil,           "combospacing",     "3")
  pfUI:UpdateConfig("unitframes", nil,           "combooffx",        "0")
  pfUI:UpdateConfig("unitframes", nil,           "combooffy",        "0")
  pfUI:UpdateConfig("unitframes", nil,           "combotexture",     "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
  pfUI:UpdateConfig("unitframes", nil,           "combocolor_low",   "1,0.3,0.3,0.75")
  pfUI:UpdateConfig("unitframes", nil,           "combocolor_mid",   "1,1,0.3,0.75")
  pfUI:UpdateConfig("unitframes", nil,           "combocolor_high",  "0.3,1,0.3,0.75")
  pfUI:UpdateConfig("unitframes", nil,           "comboborder",      "1")
  pfUI:UpdateConfig("unitframes", nil,           "comboshadow",      "1")
  pfUI:UpdateConfig("unitframes", nil,           "comboempty",       "0")
  pfUI:UpdateConfig("unitframes", nil,           "comboemptycolor",  "0.15,0.15,0.15,0.5")
  pfUI:UpdateConfig("unitframes", nil,           "combopipnumbers",  "0")
  pfUI:UpdateConfig("unitframes", nil,           "combofontsize",    "8")
  pfUI:UpdateConfig("unitframes", nil,           "combotextcolor",   "1,1,1,1")
  pfUI:UpdateConfig("unitframes", nil,           "comboglow",        "1")

  -- 能量条（独立模块 modules/energybar.lua）。**默认关闭**（comboenergyshow=0），
  -- 需要时在「连击点 → 能量条」里勾选。
  -- 宽度 214.5 = light 档「最爱扎你」连击点整排宽（40.5 x 5 + 间距 3 x 4），
  -- **填 0 才是「跟随连击点」**（只对有连击点的职业有意义，其他职业恒用 214.5）；
  -- 高度 12 与 light 档一致；Y 偏移 -4 只在跟随模式下生效。
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyshow",      "0")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergywidth",     "214.5")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyheight",    "12")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyoffx",      "0")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyoffy",      "-4")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergytexture",   "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergycolor",     "0.8,0.77,0.33,1")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyshowtext",  "1")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyfontsize",  "12")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergytextcolor", "1,1,1,1")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergytextalign", "center")
  -- 开启能量条时，连击点 / 距离指示器 / 目标仇恨框上移多少（UI 单位）。
  -- 关闭能量条时自动还原，等于「未开启时保持 light 档原位」；填 0 = 不让位。
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyshift",     "20")
  -- 底部对齐：能量条 / 连击点 / 距离指示器自下而上堆叠，最下面那块贴玩家框底边
  -- （关掉下面的块，上面的会落到它的位置）。仇恨框另贴底边，不在这条链上。
  pfUI:UpdateConfig("unitframes", nil,           "bottomalign",          "1")
  pfUI:UpdateConfig("unitframes", nil,           "bottomalign_gap",      "3")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyshowtick",  "1")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyallpower",  "1")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyautocolor", "1")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergybgcolor",   "0,0,0,0.4")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyborder",    "1")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergytextformat","0")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergysmooth",    "1")
  -- 自动隐藏（逻辑与头像框 unitframes 的 AUTOHIDE 一致）：
  -- 脱战 N 秒后淡出；战斗/能量变化时重新计时；可单独要求「满能量也隐藏」。
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyauthide",   "0")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyhidetime",  "3")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyhidecombat","1")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergyhidefull",  "0")
  -- 德鲁伊变形时在能量条下方附一条基础法力（参考头像框的 Druid Mana Bar）
  pfUI:UpdateConfig("unitframes", nil,           "comboenergydruidmana", "0")
  pfUI:UpdateConfig("unitframes", nil,           "comboenergydruidmanaheight", "6")

  pfUI:UpdateConfig("unitframes", nil,           "swingtimerwidth",  "200")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimerheight", "12")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimertexture", "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimertext",   "1")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimerlabel",  "1")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimeroffhand","1")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimerranged", "1")																		 
  pfUI:UpdateConfig("unitframes", nil,           "swingtimerfontsize","12")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimermhcolor",".8,.3,.3,1")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimerohcolor",".3,.8,.3,1")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimerrangedcolor",".3,.6,1,1")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimerrangedwarncolor",".9,0,0,1")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimerhsqueue","1")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimerattackspeed","0")  
  pfUI:UpdateConfig("unitframes", nil,           "swingtimertarget",  "0")
  pfUI:UpdateConfig("unitframes", nil,           "swingtimer",       "1")																																								 
  pfUI:UpdateConfig("unitframes", nil,           "marktrackingenabled", "0")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkerwidth",  "80")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkerheight", "14")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkergrow",   "down")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkertexture", "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkerfontsize","12")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkershowname","1")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkershowpct","1")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkershowportrait","0")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkercolor_star",     "1,.9,0,1")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkercolor_circle",   "1,.5,0,1")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkercolor_diamond",  ".8,0,.8,1")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkercolor_triangle", "0,.8,0,1")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkercolor_moon",     ".7,.7,.7,1")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkercolor_square",   "0,.4,.9,1")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkercolor_cross",    ".9,0,0,1")
  pfUI:UpdateConfig("unitframes", nil,           "raidmarkercolor_skull",    "1,1,1,1")
  pfUI:UpdateConfig("unitframes", nil,           "abbrevnum",        "1")
  pfUI:UpdateConfig("unitframes", nil,           "castbardecimals",  "2")
  pfUI:UpdateConfig("unitframes", nil,           "abbrevname",       "1")

  -- Nampower Settings
  pfUI:UpdateConfig("unitframes", nil,           "spellqueue",       "1")
  pfUI:UpdateConfig("unitframes", nil,           "spellqueuesize",   "24")
  pfUI:UpdateConfig("unitframes", nil,           "reactive_indicator", "0")
  pfUI:UpdateConfig("unitframes", nil,           "reactive_size",    "28")

  -- UnitXP Settings
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator",    "0")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_font_size", "13")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_use_gradient", "1")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_face_color", "1,0.3,0.3,1")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_back_color", "0,1,0,1")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_deadzone_color", "1,1,0,1")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_outsight_color", "0.66,0.66,0.66,1")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_outsight_icon", "0")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_icon_size", "20")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_show_prefix", "0")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_sound",     "0")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_sound_only_group", "1")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_sound_cooldown", "2")
  -- 新增：鼠标悬停距离提示及颜色设置
  pfUI:UpdateConfig("unitframes", nil,           "mouseover_tooltip_distance",          "0")
  pfUI:UpdateConfig("unitframes", nil,           "mouseover_distance_linear_color",     "0")
  pfUI:UpdateConfig("unitframes", nil,           "mouseover_distance_linear_from",      "0")
  pfUI:UpdateConfig("unitframes", nil,           "mouseover_distance_linear_to",        "40")
  pfUI:UpdateConfig("unitframes", nil,           "mouseover_distance_linear_color_from", "0,1,0,1")   -- 带 alpha
  pfUI:UpdateConfig("unitframes", nil,           "mouseover_distance_linear_color_to",   "1,0,0,1")
  pfUI:UpdateConfig("unitframes", nil,           "mouseover_distance_use_outsight",     "0")
  pfUI:UpdateConfig("unitframes", nil,           "mouseover_distance_outsight_color",   "0.66,0.66,0.66,1")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_pet_mode", "0")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_pet_font_size", "13")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_pet_color", "0,1,0,1")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_pet_offset_y", "-10")
  pfUI:UpdateConfig("unitframes", nil,           "distance_indicator_update_interval", "0.1")
  pfUI:UpdateConfig("unitframes", nil,           "mouseover_tooltip_update_interval", "0.1")


  pfUI:UpdateConfig("unitframes", nil,           "track_group",      "0")

  pfUI:UpdateConfig("unitframes", nil,           "selfingroup",      "0")
  pfUI:UpdateConfig("unitframes", nil,           "selfinraid",       "0")
  pfUI:UpdateConfig("unitframes", nil,           "raidforgroup",     "0")
  pfUI:UpdateConfig("unitframes", nil,           "maxraid",          "40")
  -- separate pet pool: number of raid pet frames (default 20, cap 40).
  -- Pets no longer occupy member slots 41..50 of the raid frame pool.
  pfUI:UpdateConfig("unitframes", nil,           "raidpetmax",       "20")

  pfUI:UpdateConfig("unitframes", nil,           "clickcast",        "target")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast_shift",  "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast_alt",    "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast_ctrl",   "")

  pfUI:UpdateConfig("unitframes", nil,           "clickcast2",        "menu")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast2_shift",  "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast2_alt",    "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast2_ctrl",   "")

  pfUI:UpdateConfig("unitframes", nil,           "clickcast3",        "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast3_shift",  "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast3_alt",    "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast3_ctrl",   "")

  pfUI:UpdateConfig("unitframes", nil,           "clickcast4",        "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast4_shift",  "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast4_alt",    "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast4_ctrl",   "")

  pfUI:UpdateConfig("unitframes", nil,           "clickcast5",        "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast5_shift",  "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast5_alt",    "")
  pfUI:UpdateConfig("unitframes", nil,           "clickcast5_ctrl",   "")

  pfUI:UpdateConfig("unitframes", "player",      "showPVPMinimap",   "0")
  pfUI:UpdateConfig("unitframes", "player",      "showRest",         "0")
  pfUI:UpdateConfig("unitframes", "player",      "energy",           "1")
  pfUI:UpdateConfig("unitframes", "player",      "manatick",         "0")
  pfUI:UpdateConfig("unitframes", "player",      "display_haste",           "0")
  pfUI:UpdateConfig("unitframes", "player",      "display_haste_color",     "1,1,1,1")
  pfUI:UpdateConfig("unitframes", "player",      "display_spellpower",      "0")
  pfUI:UpdateConfig("unitframes", "player",      "display_sp_color_override", "0")
  pfUI:UpdateConfig("unitframes", "player",      "display_sp_color",        "")																																									  																																																											   

  pfUI:UpdateConfig("unitframes", "focus",       "width",            "120")
  pfUI:UpdateConfig("unitframes", "focus",       "height",           "34")
  pfUI:UpdateConfig("unitframes", "focus",       "pheight",          "4")
  pfUI:UpdateConfig("unitframes", "focus",       "buffsize",         "12")
  pfUI:UpdateConfig("unitframes", "focus",       "debuffsize",       "12")

  pfUI:UpdateConfig("unitframes", "focustarget", "visible",          "0")
  pfUI:UpdateConfig("unitframes", "focustarget", "width",            "80")
  pfUI:UpdateConfig("unitframes", "focustarget", "height",           "12")
  pfUI:UpdateConfig("unitframes", "focustarget", "pheight",          "-1")
  pfUI:UpdateConfig("unitframes", "focustarget", "buffs",            "off")
  pfUI:UpdateConfig("unitframes", "focustarget", "debuffs",          "off")
  pfUI:UpdateConfig("unitframes", "focustarget", "txthpleft",        "none")
  pfUI:UpdateConfig("unitframes", "focustarget", "txthpcenter",      "name")
  pfUI:UpdateConfig("unitframes", "focustarget", "txthpright",       "none")

  pfUI:UpdateConfig("unitframes", "group",       "portrait",         "off")
  pfUI:UpdateConfig("unitframes", "group",       "width",            "164")
  pfUI:UpdateConfig("unitframes", "group",       "height",           "32")
  pfUI:UpdateConfig("unitframes", "group",       "pheight",          "4")
  pfUI:UpdateConfig("unitframes", "group",       "buffs",            "BOTTOMLEFT")
  pfUI:UpdateConfig("unitframes", "group",       "buffsize",         "8")
  pfUI:UpdateConfig("unitframes", "group",       "debuffs",          "BOTTOMLEFT")
  pfUI:UpdateConfig("unitframes", "group",       "debuffsize",       "8")
  pfUI:UpdateConfig("unitframes", "group",       "debufflimit",      "8")
  pfUI:UpdateConfig("unitframes", "group",       "buff_indicator",   "1")
  pfUI:UpdateConfig("unitframes", "group",       "debuff_indicator", "2")
  pfUI:UpdateConfig("unitframes", "group",       "faderange",        "1")
  pfUI:UpdateConfig("unitframes", "group",       "glowcombat",       "0")
  pfUI:UpdateConfig("unitframes", "group",       "hide_in_raid",     "0")
  pfUI:UpdateConfig("unitframes", "group",       "txthpright",       "healthmiss")
  pfUI:UpdateConfig("unitframes", "group",       "bufffilter",       "none")
  pfUI:UpdateConfig("unitframes", "group",       "buffwhitelist",    "")
  pfUI:UpdateConfig("unitframes", "group",       "buffblacklist",    "")
  pfUI:UpdateConfig("unitframes", "group",       "debufffilter",     "none")
  pfUI:UpdateConfig("unitframes", "group",       "debuffwhitelist",  "")
  pfUI:UpdateConfig("unitframes", "group",       "debuffblacklist",  "")																			
  pfUI:UpdateConfig("unitframes", "grouptarget", "portrait",         "off")
  pfUI:UpdateConfig("unitframes", "grouptarget", "width",            "120")
  pfUI:UpdateConfig("unitframes", "grouptarget", "height",           "16")
  pfUI:UpdateConfig("unitframes", "grouptarget", "pheight",          "0")
  pfUI:UpdateConfig("unitframes", "grouptarget", "buffs",            "off")
  pfUI:UpdateConfig("unitframes", "grouptarget", "buffsize",         "16")
  pfUI:UpdateConfig("unitframes", "grouptarget", "debuffs",          "off")
  pfUI:UpdateConfig("unitframes", "grouptarget", "debuffsize",       "16")
  pfUI:UpdateConfig("unitframes", "grouptarget", "faderange",        "1")
  pfUI:UpdateConfig("unitframes", "grouptarget", "glowcombat",       "0")
  pfUI:UpdateConfig("unitframes", "grouptarget", "txthpright",       "healthperc")

  pfUI:UpdateConfig("unitframes", "grouppet",    "portrait",         "off")
  pfUI:UpdateConfig("unitframes", "grouppet",    "width",            "100")
  pfUI:UpdateConfig("unitframes", "grouppet",    "height",           "14")
  pfUI:UpdateConfig("unitframes", "grouppet",    "pheight",          "0")
  pfUI:UpdateConfig("unitframes", "grouppet",    "buffs",            "off")
  pfUI:UpdateConfig("unitframes", "grouppet",    "buffsize",         "16")
  pfUI:UpdateConfig("unitframes", "grouppet",    "debuffs",          "off")
  pfUI:UpdateConfig("unitframes", "grouppet",    "debuffsize",       "16")
  pfUI:UpdateConfig("unitframes", "grouppet",    "faderange",        "1")
  pfUI:UpdateConfig("unitframes", "grouppet",    "glowcombat",       "0")
  pfUI:UpdateConfig("unitframes", "grouppet",    "txthpright",       "healthperc")

  pfUI:UpdateConfig("unitframes", "raid",        "portrait",         "off")
  pfUI:UpdateConfig("unitframes", "raid",        "width",            "50")
  pfUI:UpdateConfig("unitframes", "raid",        "height",           "26")
  pfUI:UpdateConfig("unitframes", "raid",        "pheight",          "4")
  pfUI:UpdateConfig("unitframes", "raid",        "buffs",            "off")
  pfUI:UpdateConfig("unitframes", "raid",        "buffsize",         "16")
  pfUI:UpdateConfig("unitframes", "raid",        "debuffs",          "off")
  pfUI:UpdateConfig("unitframes", "raid",        "debuffsize",       "16")
  pfUI:UpdateConfig("unitframes", "raid",        "buff_indicator",   "1")
  pfUI:UpdateConfig("unitframes", "raid",        "debuff_indicator", "2")
  pfUI:UpdateConfig("unitframes", "raid",        "faderange",        "1")
  pfUI:UpdateConfig("unitframes", "raid",        "glowcombat",       "0")
  pfUI:UpdateConfig("unitframes", "raid",        "txthpleft",        "name")
  pfUI:UpdateConfig("unitframes", "raid",        "txthpright",       "healthmiss")
  pfUI:UpdateConfig("unitframes", "raid",        "overhealperc",     "10")
  pfUI:UpdateConfig("unitframes", "raid",        "raidlayout",       "custom")
  pfUI:UpdateConfig("unitframes", "raid",        "raidpadding",      "3")
  pfUI:UpdateConfig("unitframes", "raid",        "raidfill",         "VERTICAL")
  pfUI:UpdateConfig("unitframes", "raid",        "raidgrouplabel",   "0")
  pfUI:UpdateConfig("unitframes", "raid",        "grouplabelxoff",   "0")
  pfUI:UpdateConfig("unitframes", "raid",        "grouplabelyoff",   "8")
  pfUI:UpdateConfig("unitframes", "raid",        "grouplabelfontsize","8")
  pfUI:UpdateConfig("unitframes", "raid",        "squareaggro",      "1")
  pfUI:UpdateConfig("unitframes", "raid",        "squaresize",       "6")
  pfUI:UpdateConfig("unitframes", "raid",        "buffoffx",         "0")
  pfUI:UpdateConfig("unitframes", "raid",        "buffoffy",         "0")
  pfUI:UpdateConfig("unitframes", "raid",        "debuffoffx",       "0")
  pfUI:UpdateConfig("unitframes", "raid",        "debuffoffy",       "0")
  pfUI:UpdateConfig("unitframes", "raid",        "bufffilter",       "none")
  pfUI:UpdateConfig("unitframes", "raid",        "buffwhitelist",    "")
  pfUI:UpdateConfig("unitframes", "raid",        "buffblacklist",    "")
  pfUI:UpdateConfig("unitframes", "raid",        "debufffilter",     "none")
  pfUI:UpdateConfig("unitframes", "raid",        "debuffwhitelist",  "")
  pfUI:UpdateConfig("unitframes", "raid",        "debuffblacklist",  "")																		

  pfUI:UpdateConfig("unitframes", "raidpet",    "portrait",         "off")
  pfUI:UpdateConfig("unitframes", "raidpet",    "width",            "70")
  pfUI:UpdateConfig("unitframes", "raidpet",    "height",           "13")
  pfUI:UpdateConfig("unitframes", "raidpet",    "bartexture",       "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
  pfUI:UpdateConfig("unitframes", "raidpet",    "pbartexture",      "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
  pfUI:UpdateConfig("unitframes", "raidpet",    "pheight",          "0")
  pfUI:UpdateConfig("unitframes", "raidpet",    "buffs",            "off")
  pfUI:UpdateConfig("unitframes", "raidpet",    "buffsize",         "16")
  pfUI:UpdateConfig("unitframes", "raidpet",    "debuffs",          "off")
  pfUI:UpdateConfig("unitframes", "raidpet",    "debuffsize",       "16")
  pfUI:UpdateConfig("unitframes", "raidpet",    "faderange",        "1")
  pfUI:UpdateConfig("unitframes", "raidpet",    "glowcombat",       "0")
  pfUI:UpdateConfig("unitframes", "raidpet",    "txthpleft",        "none")
  pfUI:UpdateConfig("unitframes", "raidpet",    "txthpcenter",      "name")
  pfUI:UpdateConfig("unitframes", "raidpet",    "txthpright",       "none")

  pfUI:UpdateConfig("unitframes", "ttarget",     "width",            "100")
  pfUI:UpdateConfig("unitframes", "ttarget",     "height",           "17")
  pfUI:UpdateConfig("unitframes", "ttarget",     "pheight",          "3")
  pfUI:UpdateConfig("unitframes", "ttarget",     "buffs",            "off")
  pfUI:UpdateConfig("unitframes", "ttarget",     "buffsize",         "16")
  pfUI:UpdateConfig("unitframes", "ttarget",     "debuffs",          "off")
  pfUI:UpdateConfig("unitframes", "ttarget",     "debuffsize",       "16")
  pfUI:UpdateConfig("unitframes", "ttarget",     "txthpleft",        "none")
  pfUI:UpdateConfig("unitframes", "ttarget",     "txthpcenter",      "name")
  pfUI:UpdateConfig("unitframes", "ttarget",     "txthpright",       "none")
  pfUI:UpdateConfig("unitframes", "ttarget",     "overhealperc",     "10")

  pfUI:UpdateConfig("unitframes", "tttarget",    "visible",          "0")
  pfUI:UpdateConfig("unitframes", "tttarget",    "width",            "100")
  pfUI:UpdateConfig("unitframes", "tttarget",    "height",           "17")
  pfUI:UpdateConfig("unitframes", "tttarget",    "pheight",          "3")
  pfUI:UpdateConfig("unitframes", "tttarget",    "buffs",            "off")
  pfUI:UpdateConfig("unitframes", "tttarget",    "buffsize",         "16")
  pfUI:UpdateConfig("unitframes", "tttarget",    "debuffs",          "off")
  pfUI:UpdateConfig("unitframes", "tttarget",    "debuffsize",       "16")
  pfUI:UpdateConfig("unitframes", "tttarget",    "txthpleft",        "none")
  pfUI:UpdateConfig("unitframes", "tttarget",    "txthpcenter",      "name")
  pfUI:UpdateConfig("unitframes", "tttarget",    "txthpright",       "none")
  pfUI:UpdateConfig("unitframes", "tttarget",    "overhealperc",     "10")

  pfUI:UpdateConfig("unitframes", "pet",         "happinessicon",    "2")
  pfUI:UpdateConfig("unitframes", "pet",         "happinesssize",    "12")
  pfUI:UpdateConfig("unitframes", "pet",         "width",            "100")
  pfUI:UpdateConfig("unitframes", "pet",         "height",           "14")
  pfUI:UpdateConfig("unitframes", "pet",         "pheight",          "4")
  pfUI:UpdateConfig("unitframes", "pet",         "buffsize",         "12")
  pfUI:UpdateConfig("unitframes", "pet",         "debuffsize",       "12")
  pfUI:UpdateConfig("unitframes", "pet",         "txthpleft",        "none")
  pfUI:UpdateConfig("unitframes", "pet",         "txthpcenter",      "name")
  pfUI:UpdateConfig("unitframes", "pet",         "txthpright",       "none")

  pfUI:UpdateConfig("unitframes", "ptarget",     "visible",          "0")
  pfUI:UpdateConfig("unitframes", "ptarget",     "width",            "100")
  pfUI:UpdateConfig("unitframes", "ptarget",     "height",           "4")
  pfUI:UpdateConfig("unitframes", "ptarget",     "pheight",          "-1")
  pfUI:UpdateConfig("unitframes", "ptarget",     "buffs",            "off")
  pfUI:UpdateConfig("unitframes", "ptarget",     "buffsize",         "16")
  pfUI:UpdateConfig("unitframes", "ptarget",     "debuffs",          "off")
  pfUI:UpdateConfig("unitframes", "ptarget",     "debuffsize",       "16")
  pfUI:UpdateConfig("unitframes", "ptarget",     "txthpleft",        "none")
  pfUI:UpdateConfig("unitframes", "ptarget",     "txthpcenter",      "name")
  pfUI:UpdateConfig("unitframes", "ptarget",     "txthpright",       "none")
  pfUI:UpdateConfig("unitframes", "ptarget",     "overhealperc",     "10")

  local ufs = { "player", "target", "focus", "focustarget", "group", "grouptarget", "grouppet", "raid", "raidpet", "ttarget", "pet", "ptarget", "fallback", "tttarget" }
  for _, unit in pairs(ufs) do
    pfUI:UpdateConfig("unitframes", unit,      "visible",          "1")
    pfUI:UpdateConfig("unitframes", unit,      "showPVP",          "0")
    pfUI:UpdateConfig("unitframes", unit,      "pvpiconsize",      "16" )
    pfUI:UpdateConfig("unitframes", unit,      "pvpiconalign",     "CENTER")
    pfUI:UpdateConfig("unitframes", unit,      "pvpiconoffx",      "0")
    pfUI:UpdateConfig("unitframes", unit,      "pvpiconoffy",      "0")
    pfUI:UpdateConfig("unitframes", unit,      "raidicon",         "1")
    pfUI:UpdateConfig("unitframes", unit,      "raidiconalign",    "CENTER")
    pfUI:UpdateConfig("unitframes", unit,      "raidiconoffx",     "0")
    pfUI:UpdateConfig("unitframes", unit,      "raidiconoffy",     "20")
    pfUI:UpdateConfig("unitframes", unit,      "leadericon",       "1")
    pfUI:UpdateConfig("unitframes", unit,      "assisticon",       "1")
    pfUI:UpdateConfig("unitframes", unit,      "looticon",         "1")
    pfUI:UpdateConfig("unitframes", unit,      "raidiconsize",     "24")
    pfUI:UpdateConfig("unitframes", unit,      "portrait",         "bar")
    pfUI:UpdateConfig("unitframes", unit,      "bartexture",       "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
    pfUI:UpdateConfig("unitframes", unit,      "pbartexture",       "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
    pfUI:UpdateConfig("unitframes", unit,      "width",            "200")
    pfUI:UpdateConfig("unitframes", unit,      "height",           "46")
    pfUI:UpdateConfig("unitframes", unit,      "pheight",          "10")
    pfUI:UpdateConfig("unitframes", unit,      "pwidth",           "-1")
    pfUI:UpdateConfig("unitframes", unit,      "poffx",           "0")
    pfUI:UpdateConfig("unitframes", unit,      "poffy",           "0")
    pfUI:UpdateConfig("unitframes", unit,      "portraitheight",   "-1")
    pfUI:UpdateConfig("unitframes", unit,      "portraitwidth",    "-1")
    pfUI:UpdateConfig("unitframes", unit,      "panchor",          "TOP")
    pfUI:UpdateConfig("unitframes", unit,      "pspace",           "-3")
    pfUI:UpdateConfig("unitframes", unit,      "cooldown_text",    "1")
    pfUI:UpdateConfig("unitframes", unit,      "cooldown_anim",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "buffs",            "TOPLEFT")
    pfUI:UpdateConfig("unitframes", unit,      "buffsize",         "20")
    pfUI:UpdateConfig("unitframes", unit,      "bufflimit",        "32")
    pfUI:UpdateConfig("unitframes", unit,      "buffperrow",       "8")
    pfUI:UpdateConfig("unitframes", unit,      "debuffs",          "TOPLEFT")
    pfUI:UpdateConfig("unitframes", unit,      "debuffsize",       "20")
    -- 目标框体（target）的 Debuff 总数量默认 64，其余框体保持 32
    pfUI:UpdateConfig("unitframes", unit,      "debufflimit",      (unit == "target" and "64") or "32")
    pfUI:UpdateConfig("unitframes", unit,      "debuffperrow",     "8")
    pfUI:UpdateConfig("unitframes", unit,      "selfdebuff",       "0")
    pfUI:UpdateConfig("unitframes", unit,      "invert_healthbar", "0")
    pfUI:UpdateConfig("unitframes", unit,      "verticalbar",      "0")
    pfUI:UpdateConfig("unitframes", unit,      "buff_indicator",   "0")
    pfUI:UpdateConfig("unitframes", unit,      "debuff_indicator", "0")
    pfUI:UpdateConfig("unitframes", unit,      "custom_indicator", "")

    pfUI:UpdateConfig("unitframes", unit,      "debuff_ind_pos",   "CENTER")
    pfUI:UpdateConfig("unitframes", unit,      "debuff_ind_size",  ".65")
    pfUI:UpdateConfig("unitframes", unit,      "debuff_ind_class", "1")

    pfUI:UpdateConfig("unitframes", unit,      "show_buffs",       "1")
    pfUI:UpdateConfig("unitframes", unit,      "missing_buffs_enabled", "0")
    pfUI:UpdateConfig("unitframes", unit,      "missing_buffs", "")
    pfUI:UpdateConfig("unitframes", unit,      "show_hots",        "0")
    pfUI:UpdateConfig("unitframes", unit,      "all_hots",         "0")
    pfUI:UpdateConfig("unitframes", unit,      "show_procs",       "0")
    pfUI:UpdateConfig("unitframes", unit,      "show_totems",      "0")
    pfUI:UpdateConfig("unitframes", unit,      "all_procs",        "0")
    pfUI:UpdateConfig("unitframes", unit,      "indicator_time",   "1")
    pfUI:UpdateConfig("unitframes", unit,      "indicator_stacks", "1")
    pfUI:UpdateConfig("unitframes", unit,      "indicator_size",   "10")
    pfUI:UpdateConfig("unitframes", unit,      "indicator_spacing","1")
    pfUI:UpdateConfig("unitframes", unit,      "indicator_pos",    "TOPLEFT")

    pfUI:UpdateConfig("unitframes", unit,      "clickcast",        "0")
    pfUI:UpdateConfig("unitframes", unit,      "faderange",        "0")
    pfUI:UpdateConfig("unitframes", unit,      "alpha_visible",    "1")
    pfUI:UpdateConfig("unitframes", unit,      "alpha_outrange",   ".50")
    pfUI:UpdateConfig("unitframes", unit,      "alpha_offline",    ".25")
    pfUI:UpdateConfig("unitframes", unit,      "squareaggro",      "0")
    pfUI:UpdateConfig("unitframes", unit,      "squarecombat",     "0")
    pfUI:UpdateConfig("unitframes", unit,      "squaresize",       "8")
    pfUI:UpdateConfig("unitframes", unit,      "squarepos",        "TOPLEFT")

    pfUI:UpdateConfig("unitframes", unit,      "hoverglow",         "1")   -- 新增此行
    pfUI:UpdateConfig("unitframes", unit,      "glowaggro",        "1")
    pfUI:UpdateConfig("unitframes", unit,      "glowcombat",       "1")
    pfUI:UpdateConfig("unitframes", unit,      "showtooltip",      "1")
    pfUI:UpdateConfig("unitframes", unit,      "healthcolor",      "1")
    pfUI:UpdateConfig("unitframes", unit,      "powercolor",       "1")
    pfUI:UpdateConfig("unitframes", unit,      "levelcolor",       "1")
    pfUI:UpdateConfig("unitframes", unit,      "classcolor",       "1")
    pfUI:UpdateConfig("unitframes", unit,      "txthpleft",        "unit")
    pfUI:UpdateConfig("unitframes", unit,      "txthpleftoffx",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txthpleftoffy",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txthpcenter",      "none")
    pfUI:UpdateConfig("unitframes", unit,      "txthpcenteroffx",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txthpcenteroffy",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txthpright",       "healthdyn")
    pfUI:UpdateConfig("unitframes", unit,      "txthprightoffx",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txthprightoffy",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txtpowerleft",     "none")
    pfUI:UpdateConfig("unitframes", unit,      "txtpowerleftoffx",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txtpowerleftoffy",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txtpowercenter",   "none")
    pfUI:UpdateConfig("unitframes", unit,      "txtpowercenteroffx",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txtpowercenteroffy",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txtpowerright",    "none")
    pfUI:UpdateConfig("unitframes", unit,      "txtpowerrightoffx",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "txtpowerrightoffy",    "0")
    pfUI:UpdateConfig("unitframes", unit,      "hitindicator",     "0")
    pfUI:UpdateConfig("unitframes", unit,      "hitindicatorsize", "15")
    pfUI:UpdateConfig("unitframes", unit,      "hitindicatorfont", "Interface\\AddOns\\pfUI\\fonts\\Continuum.ttf")
    pfUI:UpdateConfig("unitframes", unit,      "defcolor",         "1")
    pfUI:UpdateConfig("unitframes", unit,      "custom",           "0")
    pfUI:UpdateConfig("unitframes", unit,      "customfullhp",     "0")
    pfUI:UpdateConfig("unitframes", unit,      "customfade",       "0")
    pfUI:UpdateConfig("unitframes", unit,      "customcolor",      ".2,.2,.2,1")
    pfUI:UpdateConfig("unitframes", unit,      "custombg",         "0")
    pfUI:UpdateConfig("unitframes", unit,      "custombgcolor",    ".5,.2,.2,1")
    pfUI:UpdateConfig("unitframes", unit,      "custompbg",        "0")
    pfUI:UpdateConfig("unitframes", unit,      "custompbgcolor",   ".5,.2,.2,1")
    pfUI:UpdateConfig("unitframes", unit,      "manacolor",        ".5,.5,1,1")
    pfUI:UpdateConfig("unitframes", unit,      "energycolor",      "1,1,.5,1")
    pfUI:UpdateConfig("unitframes", unit,      "ragecolor",        "1,.5,.5,1")
    pfUI:UpdateConfig("unitframes", unit,      "focuscolor",       "1,1,.75,1")
    pfUI:UpdateConfig("unitframes", unit,      "healcolor",        "0,1,0,0.6")
    pfUI:UpdateConfig("unitframes", unit,      "overhealperc",     "20")
    pfUI:UpdateConfig("unitframes", unit,      "customfont",       "0")
    pfUI:UpdateConfig("unitframes", unit,      "customfont_name",  "Interface\\AddOns\\pfUI\\fonts\\BigNoodleTitling.ttf")
    pfUI:UpdateConfig("unitframes", unit,      "customfont_size",  "12")
    pfUI:UpdateConfig("unitframes", unit,      "customfont_style", "OUTLINE")
    pfUI:UpdateConfig("unitframes", unit,      "buffoffx",         "0")
    pfUI:UpdateConfig("unitframes", unit,      "buffoffy",         "0")
    pfUI:UpdateConfig("unitframes", unit,      "debuffoffx",       "0")
    pfUI:UpdateConfig("unitframes", unit,      "debuffoffy",       "0")
    pfUI:UpdateConfig("unitframes", unit,      "bufffilter",       "none")
    pfUI:UpdateConfig("unitframes", unit,      "buffwhitelist",    "")
    pfUI:UpdateConfig("unitframes", unit,      "buffblacklist",    "")
    pfUI:UpdateConfig("unitframes", unit,      "debufffilter",     "none")
    pfUI:UpdateConfig("unitframes", unit,      "debuffwhitelist",  "")
    pfUI:UpdateConfig("unitframes", unit,      "debuffblacklist",  "")
    pfUI:UpdateConfig("unitframes", unit, "autohide", "0")
    pfUI:UpdateConfig("unitframes", unit, "hide_time", "3")
    pfUI:UpdateConfig("unitframes", unit, "hide_combat", "1")
    pfUI:UpdateConfig("unitframes", unit, "hide_fullhp", "0")
  end

  -- ⛔ 一次性迁移（2026-09-18）：UpdateConfig 只补缺失键、永不覆盖已有值，上面把 target 的
  -- debufflimit 默认改成 64 对**现网角色**不生效 —— 老存档里 target.debufflimit 恒为旧默认
  -- "32"，图标池循环 `if i > debufflimit then break` 会在第 33 个图标处断掉，溢出 debuff
  -- （落在 aura 1-32 区的那批）永远显示不出来。这里只在"仍是旧默认 32 且未迁移过"时抬到 64，
  -- 并打标记，避免用户以后手动改回别的值被反复覆盖。
  if pfUI_config.unitframes.target
     and pfUI_config.unitframes.target.debufflimit == "32"
     and pfUI_config.unitframes.target.debufflimit64_migrated ~= "1" then
    pfUI_config.unitframes.target.debufflimit = "64"
    pfUI_config.unitframes.target.debufflimit64_migrated = "1"
  end

  pfUI:UpdateConfig("bars",       "bar1",        "pageable",         "1")
  pfUI:UpdateConfig("bars",       "bar2",        "pageable",         "1")

  pfUI:UpdateConfig("bars",       "bar1",        "enable",           "1")
  pfUI:UpdateConfig("bars",       "bar3",        "enable",           "1")
  pfUI:UpdateConfig("bars",       "bar4",        "enable",           "1")
  pfUI:UpdateConfig("bars",       "bar5",        "enable",           "1")
  pfUI:UpdateConfig("bars",       "bar6",        "enable",           "1")
  pfUI:UpdateConfig("bars",       "bar11",       "enable",           "1")
  pfUI:UpdateConfig("bars",       "bar12",       "enable",           "1")

  pfUI:UpdateConfig("bars",       "bar3",        "formfactor",       "6 x 2")
  pfUI:UpdateConfig("bars",       "bar5",        "formfactor",       "6 x 2")
  pfUI:UpdateConfig("bars",       "bar4",        "formfactor",       "1 x 12")
  pfUI:UpdateConfig("bars",       "bar11",       "formfactor",       "10 x 1")
  pfUI:UpdateConfig("bars",       "bar12",       "formfactor",       "10 x 1")

  pfUI:UpdateConfig("bars",       "bar11",       "icon_size",        "18")
  pfUI:UpdateConfig("bars",       "bar12",       "icon_size",        "18")

  for i=1,12 do
    pfUI:UpdateConfig("bars",     "bar"..i,      "enable",           "0")
    pfUI:UpdateConfig("bars",     "bar"..i,      "pageable",         "0")
    pfUI:UpdateConfig("bars",     "bar"..i,      "icon_size",        "20")
    pfUI:UpdateConfig("bars",     "bar"..i,      "spacing",          "1")
    pfUI:UpdateConfig("bars",     "bar"..i,      "formfactor",       "12 x 1")
    pfUI:UpdateConfig("bars",     "bar"..i,      "background",       "1")
    pfUI:UpdateConfig("bars",     "bar"..i,      "showempty",        "1")
    pfUI:UpdateConfig("bars",     "bar"..i,      "showmacro",        "1")
    pfUI:UpdateConfig("bars",     "bar"..i,      "showkeybind",      "1")
    pfUI:UpdateConfig("bars",     "bar"..i,      "showcount",        "1")
    pfUI:UpdateConfig("bars",     "bar"..i,      "autohide",         "0")
    pfUI:UpdateConfig("bars",     "bar"..i,      "hide_time",        "3")
    pfUI:UpdateConfig("bars",     "bar"..i,      "hide_combat",      "1")
    if i ~= 11 and i ~= 12 then
      pfUI:UpdateConfig("bars",     "bar"..i,      "buttons",           "12")
    end
  end

  pfUI:UpdateConfig("bars",       nil,           "keydown",          "0")
  pfUI:UpdateConfig("bars",       nil,           "altself",          "0")
  pfUI:UpdateConfig("bars",       nil,           "rightself",        "0")
  pfUI:UpdateConfig("bars",       nil,           "animation",        "zoomfade")
  pfUI:UpdateConfig("bars",       nil,           "animmode",         "keypress")
  pfUI:UpdateConfig("bars",       nil,           "animalways",       "0")
  pfUI:UpdateConfig("bars",       nil,           "macroscan",        "1")
  pfUI:UpdateConfig("bars",       nil,           "reagents",         "1")
  pfUI:UpdateConfig("bars",       nil,           "hunterbar",        "0")
  pfUI:UpdateConfig("bars",       nil,           "pagemasteralt",    "0")
  pfUI:UpdateConfig("bars",       nil,           "pagemastershift",  "0")
  pfUI:UpdateConfig("bars",       nil,           "pagemasterctrl",   "0")
  pfUI:UpdateConfig("bars",       nil,           "druidstealth",     "0")
  pfUI:UpdateConfig("bars",       nil,           "showcastable",     "1")
  pfUI:UpdateConfig("bars",       nil,           "glowrange",        "1")
  pfUI:UpdateConfig("bars",       nil,           "rangecolor",       "1,0.1,0.1,1")
  pfUI:UpdateConfig("bars",       nil,           "showoom",          "1")
  pfUI:UpdateConfig("bars",       nil,           "oomcolor",         ".2,.2,1,1")
  pfUI:UpdateConfig("bars",       nil,           "showna",           "1")
  pfUI:UpdateConfig("bars",       nil,           "nacolor",          ".3,.3,.3,1")
  pfUI:UpdateConfig("bars",       nil,           "showequipped",     "1")
  pfUI:UpdateConfig("bars",       nil,           "eqcolor",          ".2,.8,.2,.2")
  pfUI:UpdateConfig("bars",       nil,           "shiftdrag",        "1")
  pfUI:UpdateConfig("bars",       nil,           "monitorenable",    "0")
  pfUI:UpdateConfig("bars",       nil,           "monitorlock",      "0")
  pfUI:UpdateConfig("bars",       nil,           "monitorlist",      "")
  pfUI:UpdateConfig("bars",       nil,           "monitorsize",      "36")
  pfUI:UpdateConfig("bars",       nil,           "monitorrowsize",   "8")
  pfUI:UpdateConfig("bars",       nil,           "monitorhide",      "0")
  pfUI:UpdateConfig("bars",       nil,           "monitorautohide",  "0")
  pfUI:UpdateConfig("bars",       nil,           "monitorhidetime",  "3")
  pfUI:UpdateConfig("bars",       nil,           "monitorspacing",   "1")
  pfUI:UpdateConfig("bars",       nil,           "monitorbackdrop",  "1")
  pfUI:UpdateConfig("bars",       nil,           "monitorcount",     "1")
  pfUI:UpdateConfig("bars",       nil,           "monitorshowmacro", "0")
  pfUI:UpdateConfig("bars",       nil,           "monitorshowkeybind", "1")
  pfUI:UpdateConfig("bars",       nil,           "monitorcombat",    "1")
  pfUI:UpdateConfig("bars",       nil,           "monitorborder",    "1")
  pfUI:UpdateConfig("bars",       nil,           "monitorglow",      "1")

  pfUI:UpdateConfig("bars",       nil,           "font",             "Interface\\AddOns\\pfUI\\fonts\\BigNoodleTitling.ttf")
  pfUI:UpdateConfig("bars",       nil,           "font_offset",      "0")
  pfUI:UpdateConfig("bars",       nil,           "macro_size",       "9")
  pfUI:UpdateConfig("bars",       nil,           "macro_color",      "1,1,1,1")
  pfUI:UpdateConfig("bars",       nil,           "count_size",       "11")
  pfUI:UpdateConfig("bars",       nil,           "count_color",      ".2,1,.8,1")
  pfUI:UpdateConfig("bars",       nil,           "bind_size",        "8")
  pfUI:UpdateConfig("bars",       nil,           "bind_color",       "1,1,0,1")
  pfUI:UpdateConfig("bars",       nil,           "cd_size",          "12")

  pfUI:UpdateConfig("bars",       "gryphons",    "texture",          "None")
  pfUI:UpdateConfig("bars",       "gryphons",    "color",            ".6,.6,.6,1")
  pfUI:UpdateConfig("bars",       "gryphons",    "size",             "64")
  pfUI:UpdateConfig("bars",       "gryphons",    "anchor_left",      "pfActionBarLeft")
  pfUI:UpdateConfig("bars",       "gryphons",    "anchor_right",     "pfActionBarRight")
  pfUI:UpdateConfig("bars",       "gryphons",    "offset_h",         "-48")
  pfUI:UpdateConfig("bars",       "gryphons",    "offset_v",         "-4")

  pfUI:UpdateConfig("totems",     nil,           "direction",        "HORIZONTAL")
  pfUI:UpdateConfig("totems",     nil,           "iconsize",         "26")
  pfUI:UpdateConfig("totems",     nil,           "spacing",          "3")
  pfUI:UpdateConfig("totems",     nil,           "showbg",           "0")

  pfUI:UpdateConfig("panel",      nil,           "use_unitfonts",    "0")
  pfUI:UpdateConfig("panel",      nil,           "hide_leftchat",    "0")
  pfUI:UpdateConfig("panel",      nil,           "hide_rightchat",   "0")
  pfUI:UpdateConfig("panel",      nil,           "hide_minimap",     "0")
  pfUI:UpdateConfig("panel",      nil,           "hide_microbar",    "0")
  pfUI:UpdateConfig("panel",      nil,           "seconds",          "1")
  pfUI:UpdateConfig("panel",      "left",        "left",             "guild")
  pfUI:UpdateConfig("panel",      "left",        "center",           "durability")
  pfUI:UpdateConfig("panel",      "left",        "right",            "friends")
  pfUI:UpdateConfig("panel",      "right",       "left",             "fps")
  pfUI:UpdateConfig("panel",      "right",       "center",           "time")
  pfUI:UpdateConfig("panel",      "right",       "right",            "gold")
  pfUI:UpdateConfig("panel",      "other",       "minimap",          "zone")
  pfUI:UpdateConfig("panel",      "micro",       "enable",           "0")
  pfUI:UpdateConfig("panel",      nil,           "fpscolors",        "1")

  pfUI:UpdateConfig("panel",      "bag",         "ignorespecial",    "1")
  pfUI:UpdateConfig("panel",      "xp",          "xp_always",        "0")
  pfUI:UpdateConfig("panel",      "xp",          "xp_display",       "XPFLEX")
  pfUI:UpdateConfig("panel",      "xp",          "xp_timeout",       "5")
  pfUI:UpdateConfig("panel",      "xp",          "xp_width",         "5")
  pfUI:UpdateConfig("panel",      "xp",          "xp_height",        "5")
  pfUI:UpdateConfig("panel",      "xp",          "xp_mode",          "VERTICAL")
  pfUI:UpdateConfig("panel",      "xp",          "xp_anchor",        "pfChatLeft")
  pfUI:UpdateConfig("panel",      "xp",          "xp_position",      "RIGHT")
  pfUI:UpdateConfig("panel",      "xp",          "xp_text",          "0")
  pfUI:UpdateConfig("panel",      "xp",          "xp_text_off_y",    "0")
  pfUI:UpdateConfig("panel",      "xp",          "xp_text_mouse",    "0")
  pfUI:UpdateConfig("panel",      "xp",          "xp_color",         ".25,.25,1,1")
  pfUI:UpdateConfig("panel",      "xp",          "rest_color",       "1,.25,1,.5")
  pfUI:UpdateConfig("panel",      "xp",          "texture",          "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")

  pfUI:UpdateConfig("panel",      "xp",          "rep_always",       "0")
  pfUI:UpdateConfig("panel",      "xp",          "rep_display",      "REP")
  pfUI:UpdateConfig("panel",      "xp",          "rep_timeout",      "5")
  pfUI:UpdateConfig("panel",      "xp",          "rep_width",        "5")
  pfUI:UpdateConfig("panel",      "xp",          "rep_height",       "5")
  pfUI:UpdateConfig("panel",      "xp",          "rep_mode",         "VERTICAL")
  pfUI:UpdateConfig("panel",      "xp",          "rep_anchor",       "pfChatRight")
  pfUI:UpdateConfig("panel",      "xp",          "rep_position",     "LEFT")
  pfUI:UpdateConfig("panel",      "xp",          "rep_text",         "0")
  pfUI:UpdateConfig("panel",      "xp",          "rep_text_off_y",   "0")
  pfUI:UpdateConfig("panel",      "xp",          "rep_text_mouse",   "0")
  pfUI:UpdateConfig("panel",      "xp",          "dont_overlap",     "0")

  pfUI:UpdateConfig("castbar",    "player",      "hide_blizz",       "1")
  pfUI:UpdateConfig("castbar",    "player",      "hide_pfui",        "0")
  pfUI:UpdateConfig("castbar",    "player",      "width",            "-1")
  pfUI:UpdateConfig("castbar",    "player",      "height",           "-1")
  pfUI:UpdateConfig("castbar",    "player",      "showicon",         "0")
  pfUI:UpdateConfig("castbar",    "player",      "showname",         "1")
  pfUI:UpdateConfig("castbar",    "player",      "showtimer",        "1")
  pfUI:UpdateConfig("castbar",    "player",      "txtleftoffx",      "0")
  pfUI:UpdateConfig("castbar",    "player",      "txtleftoffy",      "0")
  pfUI:UpdateConfig("castbar",    "player",      "showlag",          "0")
  pfUI:UpdateConfig("castbar",    "player",      "showrank",         "0")
  pfUI:UpdateConfig("castbar",    "player",      "txtrightoffx",     "0")
  pfUI:UpdateConfig("castbar",    "player",      "txtrightoffy",     "0")
  pfUI:UpdateConfig("castbar",    "target",      "hide_pfui",        "0")
  pfUI:UpdateConfig("castbar",    "target",      "width",            "-1")
  pfUI:UpdateConfig("castbar",    "target",      "height",           "-1")
  pfUI:UpdateConfig("castbar",    "target",      "showicon",         "0")
  pfUI:UpdateConfig("castbar",    "target",      "showname",         "1")
  pfUI:UpdateConfig("castbar",    "target",      "showtimer",        "1")
  pfUI:UpdateConfig("castbar",    "target",      "txtleftoffx",      "0")
  pfUI:UpdateConfig("castbar",    "target",      "txtleftoffy",      "0")
  pfUI:UpdateConfig("castbar",    "target",      "showlag",          "0")
  pfUI:UpdateConfig("castbar",    "target",      "showrank",         "0")
  pfUI:UpdateConfig("castbar",    "target",      "txtrightoffx",     "0")
  pfUI:UpdateConfig("castbar",    "target",      "txtrightoffy",     "0")
  pfUI:UpdateConfig("castbar",    "focus",       "hide_pfui",        "0")
  pfUI:UpdateConfig("castbar",    "focus",       "width",            "-1")
  pfUI:UpdateConfig("castbar",    "focus",       "height",           "-1")
  pfUI:UpdateConfig("castbar",    "focus",       "showicon",         "0")
  pfUI:UpdateConfig("castbar",    "focus",       "showname",         "1")
  pfUI:UpdateConfig("castbar",    "focus",       "showtimer",        "1")
  pfUI:UpdateConfig("castbar",    "focus",       "txtleftoffx",      "0")
  pfUI:UpdateConfig("castbar",    "focus",       "txtleftoffy",      "0")
  pfUI:UpdateConfig("castbar",    "focus",       "showlag",          "0")
  pfUI:UpdateConfig("castbar",    "focus",       "showrank",         "0")
  pfUI:UpdateConfig("castbar",    "focus",       "txtrightoffx",     "0")
  pfUI:UpdateConfig("castbar",    "focus",       "txtrightoffy",     "0")
  pfUI:UpdateConfig("castbar",    nil,           "use_unitfonts",    "0")

  pfUI:UpdateConfig("tooltip",    nil,           "position",         "chat")
  pfUI:UpdateConfig("tooltip",    nil,           "cursoralign",      "native")
  pfUI:UpdateConfig("tooltip",    nil,           "cursoroffset",     "20")
  pfUI:UpdateConfig("tooltip",    nil,           "extguild",         "1")
  pfUI:UpdateConfig("tooltip",    nil,           "itemid",           "0")
  pfUI:UpdateConfig("tooltip",    nil,           "alpha",            "0.8")
  pfUI:UpdateConfig("tooltip",    nil,           "alwaysperc",       "0")
  pfUI:UpdateConfig("tooltip",    nil,           "manaperc",         "0")
  pfUI:UpdateConfig("tooltip",    nil,           "manabar",          "1")
  pfUI:UpdateConfig("tooltip",    nil,           "barheight",        "12")
  pfUI:UpdateConfig("tooltip",    nil,           "barpos",           "TOP")
  pfUI:UpdateConfig("tooltip",    nil,           "bar_font_size",    "11")
  pfUI:UpdateConfig("tooltip",    nil,           "bar_text_offy",    "0")
  pfUI:UpdateConfig("tooltip",    "compare",     "basestats",        "1")
  pfUI:UpdateConfig("tooltip",    "compare",     "showalways",       "0")
  pfUI:UpdateConfig("tooltip",    "vendor",      "showalways",       "0")
  pfUI:UpdateConfig("tooltip",    "questitem",   "showquest",        "1")
  pfUI:UpdateConfig("tooltip",    "questitem",   "showcount",        "0")
  pfUI:UpdateConfig("tooltip",    "statusbar",   "texture",          "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
  pfUI:UpdateConfig("tooltip",     nil,          "font_tooltip",     "Interface\\AddOns\\pfUI\\fonts\\Myriad-Pro.ttf")
  pfUI:UpdateConfig("tooltip",     nil,          "font_tooltip_size", "12")

  -- 3D 模型（人物像）配置
  pfUI:UpdateConfig("tooltip",     nil,          "show3dmodel",      "0")
  pfUI:UpdateConfig("tooltip",     nil,          "modelsize",        "120")
  pfUI:UpdateConfig("tooltip",     nil,          "modelposition",    "TOP")
  pfUI:UpdateConfig("tooltip",     nil,          "modeloffsetx",     "0")
  pfUI:UpdateConfig("tooltip",     nil,          "modeloffsety",     "10")
  pfUI:UpdateConfig("tooltip",     nil,          "modelrotation",    "1")
  pfUI:UpdateConfig("tooltip",     nil,          "modeledge",        "1")

  -- Throttle Settings					  
  pfUI:UpdateConfig("chat",       "text",        "input_width",      "0")
  pfUI:UpdateConfig("chat",       "text",        "input_height",     "0")
  pfUI:UpdateConfig("chat",       "text",        "outline",          "1")
  pfUI:UpdateConfig("chat",       "text",        "history",          "1")
  pfUI:UpdateConfig("chat",       "text",        "mouseover",        "0")
  pfUI:UpdateConfig("chat",       "text",        "bracket",          "[]")
  pfUI:UpdateConfig("chat",       "text",        "time",             "0")
  pfUI:UpdateConfig("chat",       "text",        "timeformat",       "%H:%M:%S")
  pfUI:UpdateConfig("chat",       "text",        "timebracket",      "[]")
  pfUI:UpdateConfig("chat",       "text",        "timecolor",        ".8,.8,.8,1")
  pfUI:UpdateConfig("chat",       "text",        "tintunknown",      "1")
  pfUI:UpdateConfig("chat",       "text",        "unknowncolor",     ".7,.7,.7,1")
  pfUI:UpdateConfig("chat",       "text",        "channelnumonly",   "1")
  pfUI:UpdateConfig("chat",       "text",        "playerlinks",      "1")
  pfUI:UpdateConfig("chat",       "text",        "detecturl",        "1")
  pfUI:UpdateConfig("chat",       "text",        "classcolor",       "1")
  pfUI:UpdateConfig("chat",       "text",        "whosearchunknown", "0")
  pfUI:UpdateConfig("chat",       "text",        "playerlevel",      "1")
  pfUI:UpdateConfig("chat",       "text",        "playerrace",      "0")
  pfUI:UpdateConfig("chat",       "left",        "width",            "380")
  pfUI:UpdateConfig("chat",       "left",        "height",           "180")
  pfUI:UpdateConfig("chat",       "right",       "enable",           "0")
  pfUI:UpdateConfig("chat",       "right",       "width",            "380")
  pfUI:UpdateConfig("chat",       "right",       "height",           "180")
  pfUI:UpdateConfig("chat",       "global",      "combathide",       "0")
  pfUI:UpdateConfig("chat",       "global",      "tabdock",          "0")
  pfUI:UpdateConfig("chat",       "global",      "tabmouse",         "0")
  pfUI:UpdateConfig("chat",       "global",      "chatflash",        "1")
  pfUI:UpdateConfig("chat",       "global",      "maxlines",         "128")
  pfUI:UpdateConfig("chat",       "global",      "frameshadow",      "1")
  pfUI:UpdateConfig("chat",       "global",      "custombg",         "0")
  pfUI:UpdateConfig("chat",       "global",      "background",       ".2,.2,.2,.5")
  pfUI:UpdateConfig("chat",       "global",      "border",           ".4,.4,.4,.5")
  pfUI:UpdateConfig("chat",       "global",      "whispermod",       "1")
  pfUI:UpdateConfig("chat",       "global",      "whisper",          "1,.7,1,1")
  pfUI:UpdateConfig("chat",       "global",      "sticky",           "1")
  pfUI:UpdateConfig("chat",       "global",      "whispernonsticky", "1")
  pfUI:UpdateConfig("chat",       "global",      "fadeout",          "0")
  pfUI:UpdateConfig("chat",       "global",      "fadetime",         "300")
  pfUI:UpdateConfig("chat",       "global",      "scrollspeed",      "1")
  pfUI:UpdateConfig("chat",       "global",      "repeatfilter",     "1")
  pfUI:UpdateConfig("chat",       "global",      "repeatfilterinterval", "20")
  pfUI:UpdateConfig("chat",       "global",      "repeatfilterexclude", "")
  pfUI:UpdateConfig("chat",       "bubbles",     "borders",          "1")
  pfUI:UpdateConfig("chat",       "bubbles",     "alpha",            ".75")

  pfUI:UpdateConfig("nameplates", nil,           "showhostile",                "1")
  pfUI:UpdateConfig("nameplates", nil,           "showfriendly",               "0")
  pfUI:UpdateConfig("nameplates", nil,           "disable_hostile_in_friendly", "0")
  pfUI:UpdateConfig("nameplates", nil,           "disable_friendly_in_friendly", "0")
  pfUI:UpdateConfig("nameplates", nil,           "use_unitfonts",              "0")
  pfUI:UpdateConfig("nameplates", nil,           "overlap",          "0")
  pfUI:UpdateConfig("nameplates", nil,           "verticalhealth",   "0")
  pfUI:UpdateConfig("nameplates", nil,           "vertical_offset",  "15")
  pfUI:UpdateConfig("nameplates", nil,           "showcastbar",      "1")
  pfUI:UpdateConfig("nameplates", nil,           "targetcastbar",    "0")
  pfUI:UpdateConfig("nameplates", nil,           "spellname",        "0")
  pfUI:UpdateConfig("nameplates", nil,           "showdebuffs",      "1")
  pfUI:UpdateConfig("nameplates", nil,           "showdebuffs_hostile",  "1")
  pfUI:UpdateConfig("nameplates", nil,           "showdebuffs_friendly", "0")
  pfUI:UpdateConfig("nameplates", nil,           "selfdebuff",       "0")																			 								         
  pfUI:UpdateConfig("nameplates", nil,           "guessdebuffs",     "1")
  pfUI:UpdateConfig("nameplates", nil,           "clickthrough",     "0")
  pfUI:UpdateConfig("nameplates", nil,           "rightclick",       "1")
  pfUI:UpdateConfig("nameplates", nil,           "clickthreshold",   "0.5")
  pfUI:UpdateConfig("nameplates", nil,           "enemyclassc",      "1")
  pfUI:UpdateConfig("nameplates", nil,           "friendclassc",     "1")
  pfUI:UpdateConfig("nameplates", nil,           "friendclassnamec", "0")
  pfUI:UpdateConfig("nameplates", nil,           "raidiconsize",     "16")
  pfUI:UpdateConfig("unitframes",  nil,           "blizzard_raidicons","1")																		   
  pfUI:UpdateConfig("nameplates", nil,           "raidiconpos",      "CENTER")
  pfUI:UpdateConfig("nameplates", nil,           "raidiconoffx",     "0")
  pfUI:UpdateConfig("nameplates", nil,           "raidiconoffy",     "-5")
  pfUI:UpdateConfig("nameplates", nil,           "fullhealth",       "1")
  pfUI:UpdateConfig("nameplates", nil,           "target",           "1")
  pfUI:UpdateConfig("nameplates", nil,           "namefightcolor",   "1")
  pfUI:UpdateConfig("nameplates", nil,           "enemynpc",         "0")
  pfUI:UpdateConfig("nameplates", nil,           "enemyplayer",      "0")
  pfUI:UpdateConfig("nameplates", nil,           "neutralnpc",       "0")
  pfUI:UpdateConfig("nameplates", nil,           "friendlynpc",      "0")
  pfUI:UpdateConfig("nameplates", nil,           "friendlyplayer",   "0")
  pfUI:UpdateConfig("nameplates", nil,           "critters",         "1")
  pfUI:UpdateConfig("nameplates", nil,           "totems",           "1")
  pfUI:UpdateConfig("nameplates", nil,           "totemicons",       "0")
  pfUI:UpdateConfig("nameplates", nil,           "showguildname",    "0")
  pfUI:UpdateConfig("nameplates", nil,           "showtargetname",   "1")  -- 新增目标
  pfUI:UpdateConfig("nameplates", nil,           "showhatred",     "1")
  pfUI:UpdateConfig("nameplates", nil,           "questicon",        "1")  -- 新增任务

  pfUI:UpdateConfig("nameplates", nil,           "hideblacklist",    "0")
  pfUI:UpdateConfig("nameplates", nil,           "blacklist",        "")

  -- 固定位置目标姓名板（目标姓名板不可见时显示）
  pfUI:UpdateConfig("nameplates", nil,           "fixedposition",          "0")
  pfUI:UpdateConfig("nameplates", nil,           "fixedposition_enemyonly","0")
  pfUI:UpdateConfig("nameplates", nil,           "fixedposition_anchor",   "TOP")
  pfUI:UpdateConfig("nameplates", nil,           "fixedposition_unlock",   "0")
  pfUI:UpdateConfig("nameplates", nil,           "fixedposition_width",    "-1")
  pfUI:UpdateConfig("nameplates", nil,           "fixedposition_height",   "-1")
  pfUI:UpdateConfig("nameplates", nil,           "fixedposition_x",        "")
  pfUI:UpdateConfig("nameplates", nil,           "fixedposition_y",        "")

  pfUI:UpdateConfig("nameplates", nil,           "outcombatstate",   "1")
  pfUI:UpdateConfig("nameplates", nil,           "barcombatstate",   "1")

  pfUI:UpdateConfig("nameplates", nil,           "ccombatthreat",    "1")
  pfUI:UpdateConfig("nameplates", nil,           "ccombatofftank",   "1")
  pfUI:UpdateConfig("nameplates", nil,           "ccombatnothreat",  "1")
  pfUI:UpdateConfig("nameplates", nil,           "ccombatstun",      "1")
  pfUI:UpdateConfig("nameplates", nil,           "ccombatcasting",   "0")
  pfUI:UpdateConfig("nameplates", nil,           "combatthreat",     ".7,.2,.2,1")
  pfUI:UpdateConfig("nameplates", nil,           "combatofftank",    ".7,.4,.2,1")
  pfUI:UpdateConfig("nameplates", nil,           "combatnothreat",   ".7,.7,.2,1")
  pfUI:UpdateConfig("nameplates", nil,           "combatstun",       ".2,.7,.7,1")
  pfUI:UpdateConfig("nameplates", nil,           "combatcasting",    ".7,.2,.7,1")
  pfUI:UpdateConfig("nameplates", nil,           "combatofftanks",   "")

  pfUI:UpdateConfig("nameplates", nil,           "outfriendly",      "0")
  pfUI:UpdateConfig("nameplates", nil,           "outfriendlynpc",   "1")
  pfUI:UpdateConfig("nameplates", nil,           "outneutral",       "1")
  pfUI:UpdateConfig("nameplates", nil,           "outenemy",         "1")
  pfUI:UpdateConfig("nameplates", nil,           "targethighlight",  "0")
  pfUI:UpdateConfig("nameplates", nil,           "highlightcolor",   "1,1,1,1")

  -- 单位类型自定义颜色（GUI「单位颜色」）
  pfUI:UpdateConfig("nameplates", nil,           "unitcolor_enemynpc",       ".9,.2,.3,.8")
  pfUI:UpdateConfig("nameplates", nil,           "unitcolor_enemyplayer",    ".9,.2,.3,.8")
  pfUI:UpdateConfig("nameplates", nil,           "unitcolor_neutralnpc",     "1,1,.3,.8")
  pfUI:UpdateConfig("nameplates", nil,           "unitcolor_friendlynpc",    ".6,1,0,.8")
  pfUI:UpdateConfig("nameplates", nil,           "unitcolor_friendlyplayer", ".2,.6,1,.8")

  -- 自定义 NPC 颜色（GUI「自定义 NPC 颜色」）：按 NPC 名字覆盖上面 5 种单位颜色
  -- unitcolor_custom 为 "#" 分隔条目："名字" 或 "名字=r,g,b,a"
  pfUI:UpdateConfig("nameplates", nil,           "unitcolor_customcolor",    "1,.2,.2,1")
  pfUI:UpdateConfig("nameplates", nil,           "unitcolor_custom",         "")

  pfUI:UpdateConfig("nameplates", nil,           "showhp",           "0")
  pfUI:UpdateConfig("nameplates", nil,           "hptextpos",        "RIGHT")
  pfUI:UpdateConfig("nameplates", nil,           "hptextformat",     "curmaxs")
  pfUI:UpdateConfig("nameplates", nil,           "width",            "120")
  pfUI:UpdateConfig("nameplates", nil,           "debuffsize",       "14")
  pfUI:UpdateConfig("nameplates", nil,           "debuffoffset",     "4")
  pfUI:UpdateConfig("nameplates", nil,           "heighthealth",     "8")
  pfUI:UpdateConfig("nameplates", nil,           "heightcast",       "8")
  pfUI:UpdateConfig("nameplates", nil,           "cpdisplay",        "0")
  pfUI:UpdateConfig("nameplates", nil,           "targetglow",       "1")
  pfUI:UpdateConfig("nameplates", nil,           "glowcolor",        "1,1,1,1")
  pfUI:UpdateConfig("nameplates", nil,           "targetzoom",       "0")
  pfUI:UpdateConfig("nameplates", nil,           "targetzoomval",    ".40")
  pfUI:UpdateConfig("nameplates", nil,           "notargalpha",      ".75")
  pfUI:UpdateConfig("nameplates", nil,           "healthtexture",    "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga")
  pfUI:UpdateConfig("nameplates", "name",        "fontstyle",        "OUTLINE")
  pfUI:UpdateConfig("nameplates", "health",      "offset",           "-3")
  pfUI:UpdateConfig("nameplates", "debuffs",     "filter",           "none")
  pfUI:UpdateConfig("nameplates", "debuffs",     "whitelist",        "")
  pfUI:UpdateConfig("nameplates", "debuffs",     "blacklist",        "")
  pfUI:UpdateConfig("nameplates", "debuffs",     "showstacks",       "0")
  pfUI:UpdateConfig("nameplates", "debuffs",     "position",         "BOTTOM")
  pfUI:UpdateConfig("nameplates", nil,           "debufftimers",     "1")
  pfUI:UpdateConfig("nameplates", nil,           "debufftext",       "1")
  pfUI:UpdateConfig("nameplates", nil,           "debuffanim",       "0")

  -- 控制技能（CC）高亮显示（默认关闭，可在 GUI 中开启）
  pfUI:UpdateConfig("nameplates", nil,           "ccenabled",        "0")
  pfUI:UpdateConfig("nameplates", nil,           "ccposition",       "TOP")
  pfUI:UpdateConfig("nameplates", nil,           "ccoffx",           "0")
  pfUI:UpdateConfig("nameplates", nil,           "ccoffy",           "2")
  pfUI:UpdateConfig("nameplates", nil,           "ccmax",            "4")
  pfUI:UpdateConfig("nameplates", nil,           "ccsize",           "28")
  pfUI:UpdateConfig("nameplates", nil,           "cctimers",         "1")
  pfUI:UpdateConfig("nameplates", nil,           "ccfilter",         "闷棍#肾击#致盲术#变形术#恐惧术#媚惑#休眠#纠缠根须#制裁之锤#冰冻陷阱#冲锋#拦截#凿击#心灵尖啸")


  pfUI:UpdateConfig("abuttons",   nil,           "enable",           "1")
  pfUI:UpdateConfig("abuttons",   nil,           "position",         "bottom")
  pfUI:UpdateConfig("abuttons",   nil,           "showdefault",      "0")
  pfUI:UpdateConfig("abuttons",   nil,           "rowsize",          "6")
  pfUI:UpdateConfig("abuttons",   nil,           "spacing",          "2")
  pfUI:UpdateConfig("abuttons",   nil,           "hideincombat",     "1")

  pfUI:UpdateConfig("screenshot", nil,           "interval",         "0")
  pfUI:UpdateConfig("screenshot", nil,           "levelup",          "0")
  pfUI:UpdateConfig("screenshot", nil,           "pvprank",          "0")
  pfUI:UpdateConfig("screenshot", nil,           "faction",          "0")
  pfUI:UpdateConfig("screenshot", nil,           "battleground",     "0")
  pfUI:UpdateConfig("screenshot", nil,           "hk",               "0")
  pfUI:UpdateConfig("screenshot", nil,           "loot",             "0")
  pfUI:UpdateConfig("screenshot", nil,           "hideui",           "0")
  pfUI:UpdateConfig("screenshot", nil,           "caption",          "0")
  pfUI:UpdateConfig("screenshot", nil,           "caption_font",     "Interface\\AddOns\\pfUI\\fonts\\BigNoodleTitling.ttf")
  pfUI:UpdateConfig("screenshot", nil,           "caption_size",     "22")

  pfUI:UpdateConfig("gm",         nil,           "disable",          "1")
  pfUI:UpdateConfig("gm",         nil,           "server",           "elysium")

  pfUI:UpdateConfig("questlog",   nil,           "showQuestLevels",  "0")
  pfUI:UpdateConfig("thirdparty", nil,           "chatbg",           "1")
  pfUI:UpdateConfig("thirdparty", nil,           "showmeter",        "0")
  pfUI:UpdateConfig("thirdparty", "dpsmate",     "skin",             "0")
  pfUI:UpdateConfig("thirdparty", "dpsmate",     "dock",             "0")
  pfUI:UpdateConfig("thirdparty", "shagudps",    "skin",             "0")
  pfUI:UpdateConfig("thirdparty", "shagudps",    "dock",             "0")
  pfUI:UpdateConfig("thirdparty", "swstats",     "skin",             "0")
  pfUI:UpdateConfig("thirdparty", "swstats",     "dock",             "0")
  pfUI:UpdateConfig("thirdparty", "ktm",         "skin",             "0")
  pfUI:UpdateConfig("thirdparty", "ktm",         "dock",             "0")
  pfUI:UpdateConfig("thirdparty", "twt",         "skin",             "0")
  pfUI:UpdateConfig("thirdparty", "twt",         "dock",             "0")
  pfUI:UpdateConfig("thirdparty", "wim",         "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "healcomm",    "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "sortbags",    "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "bag_sort",    "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "mrplow",      "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "bcs",         "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "crafty",      "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "clevermacro", "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "supercleveroidmacros", "enable",  "1")
  pfUI:UpdateConfig("thirdparty", "flightmap",   "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "sheepwatch",  "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "totemtimers", "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "theorycraft", "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "supermacro",  "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "atlasloot",   "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "myroleplay",  "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "druidmana",   "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "druidbar",    "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "ackis",       "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "bcepgp",      "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "noteit",      "enable",           "1")
  pfUI:UpdateConfig("thirdparty", "recount",     "skin",             "0")
  pfUI:UpdateConfig("thirdparty", "recount",     "dock",             "0")
  pfUI:UpdateConfig("thirdparty", "omen",        "skin",             "0")
  pfUI:UpdateConfig("thirdparty", "omen",        "dock",             "0")

  pfUI:UpdateConfig("position",   nil,           nil,                nil)
  pfUI:UpdateConfig("disabled",   nil,           nil,                nil)
end

function pfUI:MigrateConfig()
  -- migrating to new fonts (1.5 -> 1.6)
  if checkversion(1, 6, 0) then
    -- migrate font_default
    if pfUI_config.global.font_default == "arial" then
      pfUI_config.global.font_default = "Myriad-Pro"
    elseif pfUI_config.global.font_default == "homespun" then
      pfUI_config.global.font_default = "Homespun"
    elseif pfUI_config.global.font_default == "diediedie" then
      pfUI_config.global.font_default = "DieDieDie"
    end

    -- migrate font_square
    if pfUI_config.global.font_square == "arial" then
      pfUI_config.global.font_square = "Myriad-Pro"
    elseif pfUI_config.global.font_square == "homespun" then
      pfUI_config.global.font_square = "Homespun"
    elseif pfUI_config.global.font_square == "diediedie" then
      pfUI_config.global.font_square = "DieDieDie"
    end

    -- migrate font_combat
    if pfUI_config.global.font_combat == "arial" then
      pfUI_config.global.font_combat = "Myriad-Pro"
    elseif pfUI_config.global.font_combat == "homespun" then
      pfUI_config.global.font_combat = "Homespun"
    elseif pfUI_config.global.font_combat == "diediedie" then
      pfUI_config.global.font_combat = "DieDieDie"
    end
  end

  -- migrating to new loot config section (> 2.0.5)
  if checkversion(2, 0, 5) then
    if pfUI_config.appearance.loot and pfUI_config.appearance.loot.autoresize then
      pfUI_config.loot.autoresize = pfUI_config.appearance.loot.autoresize
      pfUI_config.appearance.loot.autoresize = nil
      pfUI_config.appearance.loot = nil
    end
  end

  -- migrating to new unitframes (> 2.5)
  if checkversion(2, 5, 0) then
    -- migrate clickcast settings
    if pfUI_config.unitframes.raid.clickcast_ctrl then
      pfUI_config.unitframes.clickcast = pfUI_config.unitframes.raid.clickcast
      pfUI_config.unitframes.clickcast_shift = pfUI_config.unitframes.raid.clickcast_shift
      pfUI_config.unitframes.clickcast_alt = pfUI_config.unitframes.raid.clickcast_alt
      pfUI_config.unitframes.clickcast_ctrl = pfUI_config.unitframes.raid.clickcast_ctrl

      pfUI_config.unitframes.raid.clickcast = "0"
      pfUI_config.unitframes.raid.clickcast_shift = nil
      pfUI_config.unitframes.raid.clickcast_alt = nil
      pfUI_config.unitframes.raid.clickcast_ctrl = nil
    end

    -- migrate buffsizes
    if pfUI_config.unitframes.buff_size then
      pfUI_config.unitframes.player.buffsize = pfUI_config.unitframes.buff_size
      pfUI_config.unitframes.target.buffsize = pfUI_config.unitframes.buff_size
      pfUI_config.unitframes.buff_size = nil
    end

    -- migrate debuffsizes
    if pfUI_config.unitframes.debuff_size then
      pfUI_config.unitframes.player.debuffsize = pfUI_config.unitframes.debuff_size
      pfUI_config.unitframes.target.debuffsize = pfUI_config.unitframes.debuff_size
      pfUI_config.unitframes.debuff_size = nil
    end
  end

  -- migrating to new fontnames (> 2.6)
  if checkversion(2, 6, 0) then
    -- migrate font_combat
    if pfUI_config.global.font_square then
      pfUI_config.global.font_unit = pfUI_config.global.font_square
      pfUI_config.global.font_square = nil
    end
  end


  -- migrating old to new font layout (> 3.0.0)
  if checkversion(3, 0, 0) then
    -- migrate font_default
    if not strfind(pfUI_config.global.font_default, "\\") then
      pfUI_config.global.font_default = "Interface\\AddOns\\pfUI\\fonts\\" .. pfUI_config.global.font_default .. ".ttf"
    end

    -- migrate font_unit
    if not strfind(pfUI_config.global.font_unit, "\\") then
      pfUI_config.global.font_unit = "Interface\\AddOns\\pfUI\\fonts\\" .. pfUI_config.global.font_unit .. ".ttf"
    end

    -- migrate font_combat
    if not strfind(pfUI_config.global.font_combat, "\\") then
      pfUI_config.global.font_combat = "Interface\\AddOns\\pfUI\\fonts\\" .. pfUI_config.global.font_combat .. ".ttf"
    end
  end

  -- migrating old to new unitframe texts (> 3.0.0)
  if checkversion(3, 0, 0) then
    local unitframes = { "player", "target", "focus", "group", "grouptarget", "grouppet", "raid", "ttarget", "pet", "ptarget", "fallback" }

    for _, unitframe in pairs(unitframes) do
      if pfUI_config.unitframes[unitframe].txtleft then
        pfUI_config.unitframes[unitframe].txthpleft = pfUI_config.unitframes[unitframe].txtleft
        pfUI_config.unitframes[unitframe].txtleft = nil
      end
      if pfUI_config.unitframes[unitframe].txtcenter then
        pfUI_config.unitframes[unitframe].txthpcenter = pfUI_config.unitframes[unitframe].txtcenter
        pfUI_config.unitframes[unitframe].txtcenter = nil
      end
      if pfUI_config.unitframes[unitframe].txtright then
        pfUI_config.unitframes[unitframe].txthpright = pfUI_config.unitframes[unitframe].txtright
        pfUI_config.unitframes[unitframe].txtright = nil
      end
    end
  end

  -- migrating animation_speed (> 3.1.2)
  if checkversion(3, 1, 2) then
    if tonumber(pfUI_config.unitframes.animation_speed) >= 13 then
      pfUI_config.unitframes.animation_speed = "13"
    elseif tonumber(pfUI_config.unitframes.animation_speed) >= 8 then
      pfUI_config.unitframes.animation_speed = "8"
    elseif tonumber(pfUI_config.unitframes.animation_speed) >= 5 then
      pfUI_config.unitframes.animation_speed = "5"
    elseif tonumber(pfUI_config.unitframes.animation_speed) >= 3 then
      pfUI_config.unitframes.animation_speed = "3"
    elseif tonumber(pfUI_config.unitframes.animation_speed) >= 2 then
      pfUI_config.unitframes.animation_speed = "2"
    elseif tonumber(pfUI_config.unitframes.animation_speed) >= 1 then
      pfUI_config.unitframes.animation_speed = "1"
    else
      pfUI_config.unitframes.animation_speed = "5"
    end
  end

  -- migrating rangecheck interval (> 3.2.2)
  if checkversion(3, 2, 2) then
    if tonumber(pfUI_config.unitframes.rangechecki) <= 1 then
      pfUI_config.unitframes.rangechecki = "2"
    end
  end

  -- migrating legacy buff/debuff naming (> 3.5.0)
  if checkversion(3, 5, 0) then
    local unitframes = { "player", "target", "focus", "group", "grouptarget", "grouppet", "raid", "ttarget", "pet", "ptarget", "fallback" }

    for _, unitframe in pairs(unitframes) do
      local entry = pfUI_config.unitframes[unitframe]
      if entry.buffs and entry.buffs == "hide" then entry.buffs = "off" end
      if entry.debuffs and entry.debuffs == "hide" then entry.debuffs = "off" end
    end
  end

  -- migrating glow settings (> 3.5.1)
  if checkversion(3, 5, 0) then
    local common = { "player", "target", "ttarget", "pet", "ptarget", "tttarget"}
    for _, unitframe in pairs(common) do
      if pfUI_config.appearance.infight.group == "1" then
        pfUI_config.unitframes[unitframe].glowcombat = "1"
        pfUI_config.unitframes[unitframe].glowaggro = "1"
      elseif pfUI_config.appearance.infight.group == "0" then
        pfUI_config.unitframes[unitframe].glowcombat = "0"
        pfUI_config.unitframes[unitframe].glowaggro = "0"
      end
    end

    if pfUI_config.appearance.infight.group == "1" then
      pfUI_config.unitframes["group"].glowcombat = "1"
      pfUI_config.unitframes["group"].glowaggro = "1"
    elseif pfUI_config.appearance.infight.group == "0" then
      pfUI_config.unitframes["group"].glowcombat = "0"
      pfUI_config.unitframes["group"].glowaggro = "0"
    end
  end

  -- migrating old buff settings (> 3.6.1)
  if checkversion(3, 6, 1) then
    pfUI_config.buffs.weapons =  pfUI_config.global.hidewbuff == "1" and "0" or "1"
    pfUI_config.buffs.buffs   =  pfUI_config.global.hidebuff  == "1" and "0" or "1"
    pfUI_config.buffs.debuffs =  pfUI_config.global.hidebuff  == "1" and "0" or "1"
  end

  -- migrating default debuffbar color settings (> 3.16)
  if checkversion(3, 16, 0) then

    if pfUI_config.buffbar.pdebuff.color == ".1,.1,.1,1" then
      pfUI_config.buffbar.pdebuff.color = ".8,.4,.4,1"
    end

    if pfUI_config.buffbar.tdebuff.color == ".1,.1,.1,1" then
      pfUI_config.buffbar.tdebuff.color   =  ".8,.4,.4,1"
    end
  end

  -- migrate buff/debuff position settings (> 3.19)
  if checkversion(3, 19, 0) then
    local unitframes = { "player", "target", "focus", "group", "grouptarget", "grouppet", "raid", "ttarget", "pet", "ptarget", "fallback" }

    for _, unitframe in pairs(unitframes) do
      local entry = pfUI_config.unitframes[unitframe]
      if entry.buffs and entry.buffs == "top" then entry.buffs = "TOPLEFT" end
      if entry.buffs and entry.buffs == "bottom" then entry.buffs = "BOTTOMLEFT" end
      if entry.debuffs and entry.debuffs == "top" then entry.debuffs = "TOPLEFT" end
      if entry.debuffs and entry.debuffs == "bottom" then entry.debuffs = "BOTTOMLEFT" end
    end
  end

  -- migrating actionbar settings (> 3.19)
  if checkversion(3, 19, 0) then

    local migratebars = {
      ["pfBarActionMain"] = "pfActionBarMain",
      ["pfBarBottomLeft"] = "pfActionBarTop",
      ["pfBarBottomRight"] = "pfActionBarLeft",
      ["pfBarTwoRight"] = "pfActionBarVertical",
      ["pfBarRight"] = "pfActionBarRight",
      ["pfBarShapeshift"] = "pfActionBarStances",
      ["pfBarPet"] = "pfActionBarPet",
    }

    -- migrate bar positions and scaling
    for oldname, newname in pairs(migratebars) do
      if pfUI_config.position[oldname] then
        pfUI_config.position[newname] = pfUI.api.CopyTable(pfUI_config.position[oldname])
        pfUI_config.position[oldname] = nil
      end
    end

    -- migrate global settings to bar specifics
    for i=1,12 do
      if pfUI_config.bars.icon_size then
        pfUI_config.bars["bar"..i].icon_size = pfUI_config.bars.icon_size
      end

      if pfUI_config.bars.background then
        pfUI_config.bars["bar"..i].background = pfUI_config.bars.background
      end

      if pfUI_config.bars.showmacro then
        pfUI_config.bars["bar"..i].showmacro = pfUI_config.bars.showmacro
      end

      if pfUI_config.bars.showkeybind then
        pfUI_config.bars["bar"..i].showkeybind = pfUI_config.bars.showkeybind
      end

      if pfUI_config.bars.hide_time then
        pfUI_config.bars["bar"..i].hide_time = pfUI_config.bars.hide_time
      end
    end

    pfUI_config.bars.icon_size = nil
    pfUI_config.bars.background = nil
    pfUI_config.bars.showmacro = nil
    pfUI_config.bars.showkeybind = nil
    pfUI_config.bars.hide_time = nil

    if pfUI_config.bars.hide_actionmain then
      pfUI_config.bars.bar1.autohide = pfUI_config.bars.hide_actionmain
      pfUI_config.bars.hide_actionmain = nil
    end

    if pfUI_config.bars.hide_bottomleft then
      pfUI_config.bars.bar6.autohide = pfUI_config.bars.hide_bottomleft
      pfUI_config.bars.hide_bottomleft = nil
    end

    if pfUI_config.bars.hide_bottomright then
      pfUI_config.bars.bar5.autohide = pfUI_config.bars.hide_bottomright
      pfUI_config.bars.hide_bottomright = nil
    end

    if pfUI_config.bars.hide_right then
      pfUI_config.bars.bar3.autohide = pfUI_config.bars.hide_right
      pfUI_config.bars.hide_right = nil
    end

    if pfUI_config.bars.hide_tworight then
      pfUI_config.bars.bar4.autohide = pfUI_config.bars.hide_tworight
      pfUI_config.bars.hide_tworight = nil
    end

    if pfUI_config.bars.hide_shapeshift then
      pfUI_config.bars.bar11.autohide = pfUI_config.bars.hide_shapeshift
      pfUI_config.bars.hide_shapeshift = nil
    end

    if pfUI_config.bars.hide_pet then
      pfUI_config.bars.bar12.autohide = pfUI_config.bars.hide_pet
      pfUI_config.bars.hide_pet = nil
    end

    if pfUI_config.bars.actionmain and pfUI_config.bars.actionmain.formfactor then
      pfUI_config.bars.bar1.formfactor = pfUI_config.bars.actionmain.formfactor
      pfUI_config.bars.actionmain.formfactor = nil
    end

    if pfUI_config.bars.bottomleft and pfUI_config.bars.bottomleft.formfactor then
      pfUI_config.bars.bar6.formfactor = pfUI_config.bars.bottomleft.formfactor
      pfUI_config.bars.bottomleft.formfactor = nil
    end

    if pfUI_config.bars.bottomright and pfUI_config.bars.bottomright.formfactor then
      pfUI_config.bars.bar5.formfactor = pfUI_config.bars.bottomright.formfactor
      pfUI_config.bars.bottomright.formfactor = nil
    end

    if pfUI_config.bars.right and pfUI_config.bars.right.formfactor then
      pfUI_config.bars.bar3.formfactor = pfUI_config.bars.right.formfactor
      pfUI_config.bars.right.formfactor = nil
    end

    if pfUI_config.bars.tworight and pfUI_config.bars.tworight.formfactor then
      pfUI_config.bars.bar4.formfactor = pfUI_config.bars.tworight.formfactor
      pfUI_config.bars.tworight.formfactor = nil
    end

    if pfUI_config.bars.shapeshift and pfUI_config.bars.shapeshift.formfactor then
      pfUI_config.bars.bar11.formfactor = pfUI_config.bars.shapeshift.formfactor
      pfUI_config.bars.shapeshift.formfactor = nil
    end

    if pfUI_config.bars.pet and pfUI_config.bars.pet.formfactor then
      pfUI_config.bars.bar12.formfactor = pfUI_config.bars.pet.formfactor
      pfUI_config.bars.pet.formfactor = nil
    end
  end

  -- migrate xp-showalways (> 4.0.2)
  if checkversion(4, 0, 2) and pfUI_config.panel.xp.showalways then
    pfUI_config.panel.xp.xp_always = pfUI_config.panel.xp.showalways
    pfUI_config.panel.xp.rep_always = pfUI_config.panel.xp.showalways
    pfUI_config.panel.xp.showalways = nil
  end

  -- migrate dispell indicators into seperate options (> 4.6.1)
  if checkversion(4, 6, 1) and pfUI_config.unitframes.debuffs_class then
    local unitframes = { "player", "target", "focus", "group", "grouptarget", "grouppet", "raid", "ttarget", "pet", "ptarget", "fallback", "tttarget" }
    for _, unitframe in pairs(unitframes) do
      pfUI_config.unitframes[unitframe].debuff_ind_class = pfUI_config.unitframes.debuffs_class
    end
    pfUI_config.unitframes.debuffs_class = nil
  end

  -- migrate buff indicators into seperate options (> 4.6.2)
  if checkversion(4, 6, 2) and pfUI_config.unitframes.show_hots then
    local unitframes = { "player", "target", "focus", "group", "grouptarget", "grouppet", "raid", "ttarget", "pet", "ptarget", "fallback", "tttarget" }
    local options = { "show_hots", "all_hots", "show_procs", "show_totems", "all_procs", "indicator_time", "indicator_stacks", "indicator_size" }

    for _, unitframe in pairs(unitframes) do
      for _, option in pairs(options) do
        pfUI_config.unitframes[unitframe][option] = pfUI_config.unitframes[option]
      end
    end

    for _, option in pairs(options) do
      pfUI_config.unitframes[option] = nil
    end
  end

  -- use same powerbar texture as for health (> 5.2.10)
  if checkversion(5, 2, 10) then
    local unitframes = { "player", "target", "focus", "group", "grouptarget", "grouppet", "raid", "ttarget", "pet", "ptarget", "fallback", "tttarget" }
    for _, unitframe in pairs(unitframes) do
      pfUI_config.unitframes[unitframe].pbartexture = pfUI_config.unitframes[unitframe].bartexture
    end
  end

  -- migrate minimap zone and coords changes
  if checkversion(5, 4, 11) then
    if pfUI_config.appearance.minimap.mouseoverzone and not pfUI_config.appearance.minimap.zonetext then
      pfUI_config.appearance.minimap.zonetext = (pfUI_config.appearance.minimap.mouseoverzone == "0") and "off" or "mouseover"
      pfUI_config.appearance.minimap.mouseoverzone = nil
    end
    if pfUI_config.appearance.minimap.coordsloc and not pfUI_config.appearance.minimap.coordstext then
      if pfUI_config.appearance.minimap.coordsloc == "off" then
        pfUI_config.appearance.minimap.coordsloc = "bottomleft"
        pfUI_config.appearance.minimap.coordstext = "off"
      else
        pfUI_config.appearance.minimap.coordstext = "mouseover"
      end
    end
  end

  -- migrate pagemaster to separate settings
  if checkversion(5, 4, 15) then
    if pfUI_config.bars.pagemaster == "1" then
      pfUI_config.bars.pagemaster = nil
      pfUI_config.bars.pagemasteralt = "1"
      pfUI_config.bars.pagemastershift = "1"
      pfUI_config.bars.pagemasterctrl = "1"
    end
  end

  -- migrate cooldown font from unit_font to separate setting
  if checkversion(5, 4, 18) then
    pfUI_config.appearance.cd.font = pfUI_config.global.font_unit
  end

  -- migrate combopoint size to separate settings
  if checkversion(5, 4, 18) then
    if pfUI_config.unitframes.combosize then
      pfUI_config.unitframes.combowidth = pfUI_config.unitframes.combosize
      pfUI_config.unitframes.comboheight = pfUI_config.unitframes.combosize
      pfUI_config.unitframes.combosize = nil
    end
  end

  -- raid frame pool back to 40 members: the former "40 -> 50" flip reserved
  -- slots 41..50 for pets inside the member pool, which broke member layout
  -- beyond 40. Pets now have their own pool (unitframes.raidpetmax).
  -- Guards keep this safe when it re-runs (TOC version not bumped yet):
  -- only a leftover "50" is folded back, user choices are never stomped.
  if checkversion(8, 55, 1) then
    if pfUI_config.unitframes.maxraid == "50" then
      pfUI_config.unitframes.maxraid = "40"
    end
    if not pfUI_config.unitframes.raidpetmax then
      pfUI_config.unitframes.raidpetmax = "20"
    end
  end

  -- default positions for the pet placeholder slots 41..50. Fills them in
  -- for existing profiles without requiring a full profile reload. The light
  -- profile uses a TOPLEFT column (x=293, y 0..-353); the lightH profile uses
  -- a BOTTOM layout with two 5-row columns (x=295/360, y 248..112) to match
  -- its 8x5 grid, since a single 10-row column would run off the screen.
  if checkversion(8, 50, 0) then
    if not pfUI_config.position then
      pfUI_config.position = {}
    end
    local isLightH = pfUI_config.global and pfUI_config.global.profile == "lightH"
    local petX = isLightH and {295,295,295,295,295,360,360,360,360,360}
                      or {293,293,293,293,293,293,293,293,293,293}
    local petY = isLightH and {248,216,180,146,112,248,216,180,146,112}
                      or {0,-39,-78,-117,-156,-197,-236,-275,-314,-353}
    for i=1, 10 do
      local name = "pfRaid" .. (40 + i)
      if not pfUI_config.position[name] then
        pfUI_config.position[name] = {
          xpos = petX[i],
          anchor = isLightH and "BOTTOM" or "TOPLEFT",
          ypos = petY[i],
          parent = "UIParent",
        }
      end
    end
  end


  pfUI_config.version = pfUI.version.string
end
