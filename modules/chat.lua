pfUI:RegisterModule("chat", "vanilla:tbc", function ()
  -- 确保配置项存在
  C.chat = C.chat or {}
  C.chat.text = C.chat.text or {}
  C.chat.text.playerrace = C.chat.text.playerrace or "0"

  -- 迁移旧键名：config.lua 的默认值曾误声明为 hidecombat，
  -- 而功能与 GUI 一直读写 combathide。老配置的值搬过来，不丢设置。
  C.chat.global = C.chat.global or {}
  if C.chat.global.hidecombat ~= nil then
    if C.chat.global.combathide == nil then
      C.chat.global.combathide = C.chat.global.hidecombat
    end
    C.chat.global.hidecombat = nil
  end

  local panelfont = C.panel.use_unitfonts == "1" and pfUI.font_unit or pfUI.font_default
  local panelfont_size = C.panel.use_unitfonts == "1" and C.global.font_unit_size or C.global.font_size
  local rawborder, default_border = GetBorderSize("chat")

  if pfUI.client <= 11200 then
    -- The 'GetChatWindowInfo' function returns shown as 'false' while the UIParent is hidden (Alt+Z).
    -- Based on that return value, the 'FloatingChatFrame_Update' would remove every chat frame,
    -- that isn't tabbed while the interface is hidden. With this hook we prevent the original
    -- 'FloatingChatFrame_Update' function from being called during that time.

    local HookFloatingChatFrame_Update = _G.FloatingChatFrame_Update
    _G.FloatingChatFrame_Update = function(id, onUpdateEvent)
      if not UIParent:IsShown() then return end
      HookFloatingChatFrame_Update(id, onUpdateEvent)
    end
  end

  _G.CHAT_FONT_HEIGHTS = { 8, 10, 12, 14, 16, 18, 20 }

  -- add dropdown menu button to ignore player
  UnitPopupButtons["IGNORE_PLAYER"] = { text = IGNORE_PLAYER, dist = 0 }
  for index,value in ipairs(UnitPopupMenus["FRIEND"]) do
    if value == "GUILD_LEAVE" then
      table.insert(UnitPopupMenus["FRIEND"], index+1, "IGNORE_PLAYER")
    end
  end

  hooksecurefunc("UnitPopup_OnClick", function(self)
    if this.value == "IGNORE_PLAYER" then
      AddIgnore(_G[UIDROPDOWNMENU_INIT_MENU].name)
    end
  end)

  local realm = GetRealmName()
  local player = UnitName("player")
  local history
  local function SaveChatHistory(id, msg, r, g, b)
    -- create cache tables if not existing
    pfUI_cache = pfUI_cache or {}
    pfUI_cache["chathistory"] = pfUI_cache["chathistory"] or {}
    pfUI_cache["chathistory"][realm] = pfUI_cache["chathistory"][realm] or {}
    pfUI_cache["chathistory"][realm][player] = pfUI_cache["chathistory"][realm][player] or {}
    pfUI_cache["chathistory"][realm][player][id] = pfUI_cache["chathistory"][realm][player][id] or {}

    if r and g and b then
      local color = rgbhex(r*.5+.2, g*.5+.2, b*.5+.2)
      msg = string.gsub(msg, "^", color)
      msg = string.gsub(msg, "|r", "|r" .. color)
    end

    history = pfUI_cache["chathistory"][realm][player][id]
    table.insert(history, 1, msg)
    if history[30] then table.remove(history, 30) end
  end

  local function GetChatHistory(id)
    -- create cache tables if not existing
    pfUI_cache = pfUI_cache or {}
    pfUI_cache["chathistory"] = pfUI_cache["chathistory"] or {}
    pfUI_cache["chathistory"][realm] = pfUI_cache["chathistory"][realm] or {}
    pfUI_cache["chathistory"][realm][player] = pfUI_cache["chathistory"][realm][player] or {}
    pfUI_cache["chathistory"][realm][player][id] = pfUI_cache["chathistory"][realm][player][id] or {}

    return pfUI_cache["chathistory"][realm][player][id]
  end

  -- 修改后的获取玩家等级的函数（兼容经典版本）
  local playerLevelCache = {}
  
  -- 添加手动更新玩家等级的函数
  function UpdatePlayerLevel(name, level)
    if name and level and level > 0 then
      playerLevelCache[name] = level
      
      -- 同时更新 pfUI_playerDB 如果存在
      if pfUI_playerDB then
        pfUI_playerDB[name] = pfUI_playerDB[name] or {}
        pfUI_playerDB[name].level = level
      end
      
      return true
    end
    return false
  end

  function GetPlayerLevel(name)
    if not name then return nil end
    
    -- 首先检查缓存
    if playerLevelCache[name] then
      return playerLevelCache[name]
    end
    
    -- 检查是否在队伍中（兼容经典版本）
    local inParty = GetNumPartyMembers() > 0
    local inRaid = GetNumRaidMembers() > 0
    
    if inParty or inRaid then
      local numMembers = inRaid and GetNumRaidMembers() or GetNumPartyMembers()
      for i = 1, numMembers do
        local unit = inRaid and "raid"..i or "party"..i
        local unitName = GetUnitName(unit, true)
        if unitName and string.lower(unitName) == string.lower(name) then
          local level = UnitLevel(unit)
          if level and level > 0 then
            UpdatePlayerLevel(name, level)
            return level
          end
        end
      end
    end
    
    -- 优先从 pfUI_playerDB 缓存中获取玩家等级
    if pfUI_playerDB and pfUI_playerDB[name] then
      local level = pfUI_playerDB[name].level
      if level and level > 0 then
        playerLevelCache[name] = level
        return level
      end
    end
    
    -- 检查是否在公会中
    if IsInGuild() then
      for i = 1, GetNumGuildMembers() do
        local guildName, rank, rankIndex, level, class, zone, note, officernote, online, status = GetGuildRosterInfo(i)
        if guildName and string.lower(guildName) == string.lower(name) then
          UpdatePlayerLevel(name, level)
          return level
        end
      end
    end
    
    -- 检查好友列表
    for i = 1, GetNumFriends() do
      local friendName, level, class, area, connected = GetFriendInfo(i)
      if friendName and string.lower(friendName) == string.lower(name) then
        UpdatePlayerLevel(name, level)
        return level
      end
    end
    
    -- 如果没有找到，返回nil
    return nil
  end

  -- 创建队友等级缓存更新系统（兼容经典版本）
  local partyLevelUpdateFrame = CreateFrame("Frame")
  partyLevelUpdateFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
  partyLevelUpdateFrame:RegisterEvent("RAID_ROSTER_UPDATE")

  partyLevelUpdateFrame:SetScript("OnEvent", function(self, event)
    -- 更新队伍成员等级信息
    local inParty = GetNumPartyMembers() > 0
    local inRaid = GetNumRaidMembers() > 0
    
    if inParty or inRaid then
      local numMembers = inRaid and GetNumRaidMembers() or GetNumPartyMembers()
      for i = 1, numMembers do
        local unit = inRaid and "raid"..i or "party"..i
        local name = GetUnitName(unit, true)
        local level = UnitLevel(unit)
        
        if name and level and level > 0 then
          -- 更新缓存
          UpdatePlayerLevel(name, level)
        end
      end
    end
    
    -- 更新玩家自己的等级
    local playerName = UnitName("player")
    local playerLevel = UnitLevel("player")
    if playerName and playerLevel > 0 then
      UpdatePlayerLevel(playerName, playerLevel)
    end
  end)

  -- 在玩家进入世界时也更新一次
  local function UpdatePartyLevelsOnLogin()
    C_Timer.After(5, function() -- 延迟5秒确保数据加载完成
      partyLevelUpdateFrame:GetScript("OnEvent")(partyLevelUpdateFrame, "PLAYER_ENTERING_WORLD")
    end)
  end

  -- 注册进入世界事件
  local loginFrame = CreateFrame("Frame")
  loginFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  loginFrame:SetScript("OnEvent", UpdatePartyLevelsOnLogin)

  -- 添加根据难度获取颜色的函数
  local COLOR = {
    impossible = { r = 1.00, g = 0.10, b = 0.10 }, -- 红色
    verydifficult = { r = 1.00, g = 0.50, b = 0.25 }, -- 橙色
    difficult = { r = 1.00, g = 0.82, b = 0.00 }, -- 黄色
    standard = { r = 0.25, g = 0.75, b = 0.25 }, -- 绿色
    trivial = { r = 0.50, g = 0.50, b = 0.50 } -- 灰色
  }

  function GetDifficultyColorChatMod(level, quest)
    if not level then return COLOR.trivial end
    
    local playerLevel = UnitLevel("player")
    local levelDiff = level - playerLevel
    
    -- 对于任务，使用固定的绿色范围
    local QuestGreenRange = quest and 25 or GetQuestGreenRange()
    
    if levelDiff >= 5 then
      return COLOR.impossible
    elseif levelDiff >= 3 then
      return COLOR.verydifficult
    elseif levelDiff >= -2 then
      return COLOR.difficult
    elseif -levelDiff <= QuestGreenRange then
      return COLOR.standard
    else
      return COLOR.trivial
    end
  end

  pfUI.chat = CreateFrame("Frame",nil,UIParent)

  pfUI.chat.left = CreateFrame("Frame", "pfChatLeft", UIParent)
  pfUI.chat.left.OnMove = function()
    pfUI.chat:RefreshChat()
  end

  pfUI.chat.left:SetFrameStrata("BACKGROUND")
  pfUI.chat.left:SetWidth(C.chat.left.width)
  pfUI.chat.left:SetHeight(C.chat.left.height)
  pfUI.chat.left:SetPoint("BOTTOMLEFT", 2*default_border,2*default_border)
  pfUI.chat.left:SetScript("OnShow", function() pfUI.chat:RefreshChat() end)
  UpdateMovable(pfUI.chat.left)
  CreateBackdrop(pfUI.chat.left, default_border, nil, .8)
  if C.chat.global.frameshadow == "1" then
    CreateBackdropShadow(pfUI.chat.left)
  end

  if C.chat.global.custombg == "1" then
    local r, g, b, a = strsplit(",", C.chat.global.background)
    pfUI.chat.left.backdrop:SetBackdropColor(tonumber(r), tonumber(g), tonumber(b), tonumber(a))

    local r, g, b, a = strsplit(",", C.chat.global.border)
    pfUI.chat.left.backdrop:SetBackdropBorderColor(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
  end

  pfUI.chat.left.panelTop = CreateFrame("Frame", "leftChatPanelTop", pfUI.chat.left)
  pfUI.chat.left.panelTop:ClearAllPoints()
  pfUI.chat.left.panelTop:SetHeight(C.global.font_size+default_border*2)
  pfUI.chat.left.panelTop:SetPoint("TOPLEFT", pfUI.chat.left, "TOPLEFT", default_border, -default_border)
  pfUI.chat.left.panelTop:SetPoint("TOPRIGHT", pfUI.chat.left, "TOPRIGHT", -default_border, -default_border)
  if C.chat.global.tabdock == "1" then
    CreateBackdrop(pfUI.chat.left.panelTop, default_border, nil, .8)
  end

  pfUI.chat.URLPattern = {
    WWW = {
      ["rx"]=" (www%d-)%.([_A-Za-z0-9-]+)%.(%S+)%s?",
      ["fm"]="%s.%s.%s"},
    PROTOCOL = {
      ["rx"]=" (%a+)://(%S+)%s?",
      ["fm"]="%s://%s"},
    EMAIL = {
      ["rx"]=" ([_A-Za-z0-9-%.:]+)@([_A-Za-z0-9-]+)(%.)([_A-Za-z0-9-]+%.?[_A-Za-z0-9-]*)%s?",
      ["fm"]="%s@%s%s%s"},
    PORTIP = {
      ["rx"]=" (%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?):(%d%d?%d?%d?%d?)%s?",
      ["fm"]="%s.%s.%s.%s:%s"},
    IP = {
      ["rx"]=" (%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%.(%d%d?%d?)%s?",
      ["fm"]="%s.%s.%s.%s"},
    SHORTURL = {
      ["rx"]=" (%a+)%.(%a+)/(%S+)%s?",
      ["fm"]="%s.%s/%s"},
    URLIP = {
      ["rx"]=" ([_A-Za-z0-9-]+)%.([_A-Za-z0-9-]+)%.(%S+)%:([_0-9-]+)%s?",
      ["fm"]="%s.%s.%s:%s"},
    URL = {
      ["rx"]=" ([_A-Za-z0-9-]+)%.([_A-Za-z0-9-]+)%.(%S+)%s?",
      ["fm"]="%s.%s.%s"},
  }

  pfUI.chat.URLFuncs = {
    ["WWW"] = function(a1,a2,a3) return pfUI.chat:FormatLink(pfUI.chat.URLPattern.WWW.fm,a1,a2,a3) end,
    ["PROTOCOL"] = function(a1,a2) return pfUI.chat:FormatLink(pfUI.chat.URLPattern.PROTOCOL.fm,a1,a2) end,
    ["EMAIL"] = function(a1,a2,a3,a4) return pfUI.chat:FormatLink(pfUI.chat.URLPattern.EMAIL.fm,a1,a2,a3,a4) end,
    ["PORTIP"] = function(a1,a2,a3,a4,a5) return pfUI.chat:FormatLink(pfUI.chat.URLPattern.PORTIP.fm,a1,a2,a3,a4,a5) end,
    ["IP"] = function(a1,a2,a3,a4) return pfUI.chat:FormatLink(pfUI.chat.URLPattern.IP.fm,a1,a2,a3,a4) end,
    ["SHORTURL"] = function(a1,a2,a3) return pfUI.chat:FormatLink(pfUI.chat.URLPattern.SHORTURL.fm,a1,a2,a3) end,
    ["URLIP"] = function(a1,a2,a3,a4) return pfUI.chat:FormatLink(pfUI.chat.URLPattern.URLIP.fm,a1,a2,a3,a4) end,
    ["URL"] = function(a1,a2,a3) return pfUI.chat:FormatLink(pfUI.chat.URLPattern.URL.fm,a1,a2,a3) end,
  }

  -- url copy dialog
  function pfUI.chat:FormatLink(formatter,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)
    if not (formatter and a1) then return end
    local newtext = string.format(formatter,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10)

    -- check the last capture index for consecutive trailing dots (invalid top level domain)
    local invalidtld
    for _, arg in pairs({a10,a9,a8,a7,a6,a5,a4,a3,a2,a1}) do
      if arg then
        invalidtld = string.find(arg, "(%.%.)$")
        break
      end
    end

    if (invalidtld) then return newtext end
    if formatter == self.URLPattern.EMAIL.fm then -- email parser
      local colon = string.find(a1,":")
      if (colon) and string.len(a1) > colon then
        if not (string.sub(a1,1,6) == "mailto") then
          local prefix,address = string.sub(newtext,1,colon),string.sub(newtext,colon+1)
          return string.format(" %s|cffccccff|Hurl:%s|h[%s]|h|r ",prefix,address,address)
        end
      end
    end
    return " |cffccccff|Hurl:" .. newtext .. "|h[" .. newtext .. "]|h|r "
  end

  function pfUI.chat:HandleLink(text)
    local URLPattern = pfUI.chat.URLPattern
    text = string.gsub (text, URLPattern.WWW.rx, pfUI.chat.URLFuncs.WWW)
    text = string.gsub (text, URLPattern.PROTOCOL.rx, pfUI.chat.URLFuncs.PROTOCOL)
    text = string.gsub (text, URLPattern.EMAIL.rx, pfUI.chat.URLFuncs.EMAIL)
    text = string.gsub (text, URLPattern.PORTIP.rx, pfUI.chat.URLFuncs.PORTIP)
    text = string.gsub (text, URLPattern.IP.rx, pfUI.chat.URLFuncs.IP)
    text = string.gsub (text, URLPattern.SHORTURL.rx, pfUI.chat.URLFuncs.SHORTURL)
    text = string.gsub (text, URLPattern.URLIP.rx, pfUI.chat.URLFuncs.URLIP)
    text = string.gsub (text, URLPattern.URL.rx, pfUI.chat.URLFuncs.URL)
    return text
  end

  pfUI.chat.urlcopy = CreateFrame("Frame", "pfURLCopy", UIParent)
  pfUI.chat.urlcopy:Hide()
  pfUI.chat.urlcopy:SetWidth(270)
  pfUI.chat.urlcopy:SetHeight(65)
  pfUI.chat.urlcopy:SetFrameStrata("FULLSCREEN")
  pfUI.chat.urlcopy:SetPoint("CENTER", 0, 0)
  CreateBackdrop(pfUI.chat.urlcopy, nil, nil, 0.8)

  pfUI.chat.urlcopy:SetMovable(true)
  pfUI.chat.urlcopy:EnableMouse(true)
  pfUI.chat.urlcopy:RegisterForDrag("LeftButton")
  pfUI.chat.urlcopy:SetScript("OnDragStart",function()
    this:StartMoving()
  end)

  pfUI.chat.urlcopy:SetScript("OnDragStop",function()
    this:StopMovingOrSizing()
  end)

  pfUI.chat.urlcopy:SetScript("OnShow", function()
    this.text:HighlightText()
  end)

  pfUI.chat.urlcopy.text = CreateFrame("EditBox", "pfURLCopyEditBox", pfUI.chat.urlcopy)
  pfUI.chat.urlcopy.text:SetTextColor(.2,1,.8,1)
  pfUI.chat.urlcopy.text:SetJustifyH("CENTER")

  pfUI.chat.urlcopy.text:SetWidth(250)
  pfUI.chat.urlcopy.text:SetHeight(20)
  pfUI.chat.urlcopy.text:SetPoint("TOP", pfUI.chat.urlcopy, "TOP", 0, -10)
  pfUI.chat.urlcopy.text:SetFontObject(GameFontNormal)
  CreateBackdrop(pfUI.chat.urlcopy.text)

  pfUI.chat.urlcopy.text:SetScript("OnEscapePressed", function(self)
    pfUI.chat.urlcopy:Hide()
  end)

  pfUI.chat.urlcopy.text:SetScript("OnEditFocusLost", function(self)
    pfUI.chat.urlcopy:Hide()
  end)

  pfUI.chat.urlcopy.close = CreateFrame("Button", "pfURLCopyClose", pfUI.chat.urlcopy, "UIPanelButtonTemplate")
  pfUI.api.SkinButton(pfUI.chat.urlcopy.close)
  pfUI.chat.urlcopy.close:SetWidth(70)
  pfUI.chat.urlcopy.close:SetHeight(18)
  pfUI.chat.urlcopy.close:SetPoint("BOTTOMRIGHT", pfUI.chat.urlcopy, "BOTTOMRIGHT", -10, 10)

  pfUI.chat.urlcopy.close:SetText(T["Close"])
  pfUI.chat.urlcopy.close:SetScript("OnClick", function()
    pfUI.chat.urlcopy:Hide()
  end)

  pfUI.chat.urlcopy.SetItemRef = SetItemRef
  pfUI.chat.urlcopy.CopyText = function(text)
    pfUI.chat.urlcopy.text:SetText(text)
    pfUI.chat.urlcopy:Show()
  end

  function _G.SetItemRef(link, text, button)
    if (strsub(link, 1, 3) == "url") then
      if string.len(link) > 4 and string.sub(link,1,4) == "url:" then
        pfUI.chat.urlcopy.CopyText(string.sub(link,5, string.len(link)))
      end
      return
    end
    pfUI.chat.urlcopy.SetItemRef(link, text, button)
  end

  pfUI.chat.right = CreateFrame("Frame", "pfChatRight", UIParent)
  pfUI.chat.right:SetFrameStrata("BACKGROUND")
  pfUI.chat.right:SetWidth(C.chat.right.width)
  pfUI.chat.right:SetHeight(C.chat.right.height)
  pfUI.chat.right:SetPoint("BOTTOMRIGHT", -2*default_border,2*default_border)
  pfUI.chat.right:SetScript("OnShow", function() pfUI.chat:RefreshChat() end)
  UpdateMovable(pfUI.chat.right)
  CreateBackdrop(pfUI.chat.right, default_border, nil, .8)
  if C.chat.global.frameshadow == "1" then
    CreateBackdropShadow(pfUI.chat.right)
  end

  if C.chat.global.custombg == "1" then
    local r, g, b, a = strsplit(",", C.chat.global.background)
    pfUI.chat.right.backdrop:SetBackdropColor(tonumber(r), tonumber(g), tonumber(b), tonumber(a))

    local r, g, b, a = strsplit(",", C.chat.global.border)
    pfUI.chat.right.backdrop:SetBackdropBorderColor(tonumber(r), tonumber(g), tonumber(b), tonumber(a))
  end

  pfUI.chat.right.panelTop = CreateFrame("Frame", "rightChatPanelTop", pfUI.chat.right)
  pfUI.chat.right.panelTop:ClearAllPoints()
  pfUI.chat.right.panelTop:SetHeight(C.global.font_size+default_border*2)
  pfUI.chat.right.panelTop:SetPoint("TOPLEFT", pfUI.chat.right, "TOPLEFT", default_border, -default_border)
  pfUI.chat.right.panelTop:SetPoint("TOPRIGHT", pfUI.chat.right, "TOPRIGHT", -default_border, -default_border)
  if C.chat.global.tabdock == "1" then
    CreateBackdrop(pfUI.chat.right.panelTop, default_border, nil, .8)
  end

  pfUI.chat:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.chat:RegisterEvent("UI_SCALE_CHANGED")

  local function ChatOnMouseWheel()
    if (arg1 > 0) then
      if IsShiftKeyDown() then
        this:ScrollToTop()
      else
        for i=1, C.chat.global.scrollspeed do
          this:ScrollUp()
        end
      end
    elseif (arg1 < 0) then
      if IsShiftKeyDown() then
        this:ScrollToBottom()
      else
        for i=1, C.chat.global.scrollspeed do
          this:ScrollDown()
        end
      end
    end
  end

  function pfUI.chat:RefreshChat()
    local panelheight = C.global.font_size*1.5 + default_border*2 + 2

    if C.chat.global.sticky == "1" then
      ChatTypeInfo.OFFICER.sticky = 1
      ChatTypeInfo.RAID_WARNING.sticky = 1
      ChatTypeInfo.CHANNEL.sticky = 1
    end

    -- 密语非粘性开关（默认开启，与TBC一致）：发送密语后输入框回到上一个粘性频道。
    -- 关闭时恢复香草默认行为（密语保持粘性）。
    if C.chat.global.whispernonsticky == "0" then
      ChatTypeInfo.WHISPER.sticky = 1
    else
      ChatTypeInfo.WHISPER.sticky = 0
    end

    ChatFrameMenuButton:Hide()
    ChatMenu:SetClampedToScreen(true)
    CreateBackdrop(ChatMenu)
    CreateBackdrop(EmoteMenu)
    CreateBackdrop(LanguageMenu)
    CreateBackdrop(VoiceMacroMenu)

    local combatlogpanel = (CombatLogQuickButtonFrame_Custom and CombatLogQuickButtonFrame_Custom:GetHeight() or 0)

    for i=1, NUM_CHAT_WINDOWS do
      local frame = _G["ChatFrame"..i]
      local tab = _G["ChatFrame"..i.."Tab"]

      local combat = 0
      for _, msg in pairs(_G["ChatFrame"..i].messageTypeList) do
        if strfind(msg, "SPELL", 1) or strfind(msg, "COMBAT", 1) then
          combat = combat + 1
        end
      end

      if combat > 5 then
        frame.pfCombatLog = true
      else
        frame.pfCombatLog = nil
      end


      if not frame.pfStartMoving then
        frame.pfStartMoving = frame.StartMoving
        frame.StartMoving = function(a1)
          pfUI.chat.hideLock = true
          frame.pfStartMoving(a1)
        end
      end

      if not frame.pfStopMovingOrSizing then
        frame.pfStopMovingOrSizing = frame.StopMovingOrSizing
        frame.StopMovingOrSizing = function(a1)
          frame.pfStopMovingOrSizing(a1)
          pfUI.chat.RefreshChat()
          pfUI.chat.hideLock = false
        end
      end

      if C.chat.global.fadeout == "1" then
        frame:SetFading(true)
        frame:SetTimeVisible(tonumber(C.chat.global.fadetime))
      else
        frame:SetFading(false)
      end

      if i == 3 and C.chat.right.enable == "1" then
        -- Loot & Spam
        local bottompadding = pfUI.panel and pfUI.panel.right:IsShown() and not pfUI_config.position["pfPanelRight"] and panelheight or default_border
        tab:SetParent(pfUI.chat.right.panelTop)
        frame:SetParent(pfUI.chat.right)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", pfUI.chat.right ,"TOPLEFT", default_border, -panelheight)
        frame:SetPoint("BOTTOMRIGHT", pfUI.chat.right ,"BOTTOMRIGHT", -default_border, bottompadding)
        frame:Show()
      elseif frame.isDocked then
        -- Left Chat
        local bottompadding = pfUI.panel and pfUI.panel.left:IsShown() and not pfUI_config.position["pfPanelLeft"] and panelheight or default_border
        FCF_DockFrame(frame)
        tab:SetParent(pfUI.chat.left.panelTop)
        frame:SetParent(pfUI.chat.left)
        frame:ClearAllPoints()
        if i == 2 then
          frame:SetPoint("TOPLEFT", pfUI.chat.left ,"TOPLEFT", default_border, -panelheight - combatlogpanel)
        else
          frame:SetPoint("TOPLEFT", pfUI.chat.left ,"TOPLEFT", default_border, -panelheight)
        end
        frame:SetPoint("BOTTOMRIGHT", pfUI.chat.left ,"BOTTOMRIGHT", -default_border, bottompadding)
      else
        FCF_UnDockFrame(frame)
        frame:SetParent(UIParent)
        tab:SetParent(UIParent)
      end

      -- Combat Log
      if C.chat.global.combathide == "1" and frame.pfCombatLog then
        FCF_UnDockFrame(frame)
        FCF_Close(frame)
      end

      -- hide textures
      for j,v in ipairs({tab:GetRegions()}) do
        if j==5 then v:SetTexture(0,0,0,0) end
        v:SetHeight(C.global.font_size+default_border*2)
      end

      -- remove background on docked frames
      for _, tex in pairs(CHAT_FRAME_TEXTURES) do
        local texture = _G["ChatFrame"..i..tex]
        if tex == "Background" then
          texture.oldTexture = texture.oldTexture or texture:GetTexture()
          if frame:GetParent() == pfUI.chat.left or frame:GetParent() == pfUI.chat.right then
            texture:SetTexture()
            texture:Hide()
          else
            texture:SetTexture(texture.oldTexture)
            texture:Show()
          end
        else
          texture:SetTexture()
          texture:Hide()
        end
      end

      _G["ChatFrame" .. i .. "ResizeBottom"]:Hide()
      _G["ChatFrame" .. i .. "TabText"]:SetJustifyV("CENTER")
      _G["ChatFrame" .. i .. "TabText"]:SetHeight(C.global.font_size+default_border*2)
      _G["ChatFrame" .. i .. "TabText"]:SetPoint("BOTTOM", 0, default_border)
      _G["ChatFrame" .. i .. "TabLeft"]:SetAlpha(0)
      _G["ChatFrame" .. i .. "TabMiddle"]:SetAlpha(0)
      _G["ChatFrame" .. i .. "TabRight"]:SetAlpha(0)

      if C.chat.global.chatflash == "1" then
        _G["ChatFrame" .. i .. "TabFlash"]:SetAllPoints(_G["ChatFrame" .. i .. "TabText"])
      else
        _G["ChatFrame" .. i .. "TabFlash"].Show = function() return end
      end

      local _, class = UnitClass("player")
      _G["ChatFrame" .. i .. "TabText"]:SetTextColor((RAID_CLASS_COLORS[class].r + .3) * .5, (RAID_CLASS_COLORS[class].g + .3) * .5, (RAID_CLASS_COLORS[class].b + .3) * .5, 1)
      _G["ChatFrame" .. i .. "TabText"]:SetFont(panelfont,panelfont_size, "OUTLINE")

      if _G["ChatFrame" .. i].isDocked or _G["ChatFrame" .. i]:IsVisible() then
        _G["ChatFrame" .. i .. "Tab"]:Show()
      end

      frame:EnableMouseWheel(true)
      frame:SetScript("OnMouseWheel", ChatOnMouseWheel)
    end


    -- update dock frame for all windows
    for index, value in pairs(DOCKED_CHAT_FRAMES) do
      FCF_UpdateButtonSide(value)
    end
  end

  hooksecurefunc("FCF_SaveDock", pfUI.chat.RefreshChat)

  if C.chat.global.tabmouse == "1" then
    pfUI.chat.mouseovertab = CreateFrame("Frame")
    -- track hover state so FCF_DockUpdate() only runs on enter/leave edges,
    -- not on every throttle tick. Calling it continuously re-lays out the dock
    -- and makes panelTop (and any button parented to it) jitter unclickable.
    local wasOverLeft, wasOverRight = false, false
    pfUI.chat.mouseovertab:SetScript("OnUpdate", function()
      -- throttle
      if ( this.tick or .1) > GetTime() then return else this.tick = GetTime() + pfUI.throttle:Get("chat_tab") end  -- Default: Normal (10 FPS)
      if pfUI.chat.hideLock then return end

      local overLeft = MouseIsOver(pfUI.chat.left, 10, -10, -10, 10)
      local overRight = MouseIsOver(pfUI.chat.right, 10, -10, -10, 10) and pfUI.chat.right:GetAlpha() ~= 0

      if overLeft and not wasOverLeft then
        pfUI.chat.left.panelTop:Show()
        FCF_DockUpdate()
      elseif not overLeft and wasOverLeft then
        pfUI.chat.left.panelTop:Hide()
      end

      if overRight and not wasOverRight then
        pfUI.chat.right.panelTop:Show()
        FCF_DockUpdate()
      elseif not overRight and wasOverRight then
        pfUI.chat.right.panelTop:Hide()
      end

      wasOverLeft = overLeft
      wasOverRight = overRight
    end)
  end

  function pfUI.chat.SetupRightChat(state)
    if state then
      C.chat.right.enable = "1"
      pfUI.chat.right:Show()
    else
      C.chat.right.enable = "0"
      pfUI.chat.right:Hide()
    end
  end

  function pfUI.chat.SetupPositions()
    -- close all chat windows
    for i=1, NUM_CHAT_WINDOWS do
      FCF_Close(_G["ChatFrame"..i])
      FCF_DockUpdate()
    end

    -- Main Window
    ChatFrame1:ClearAllPoints()
    ChatFrame1:SetPoint("TOPLEFT", pfUI.chat.left ,"TOPLEFT", 5, -25)
    ChatFrame1:SetPoint("BOTTOMRIGHT", pfUI.chat.left ,"BOTTOMRIGHT", -5, 25)

    FCF_SetLocked(ChatFrame1, 1)
    FCF_SetWindowName(ChatFrame1, GENERAL)
    FCF_SetWindowColor(ChatFrame1, 0, 0, 0)
    FCF_SetWindowAlpha(ChatFrame1, 0)
    FCF_SetChatWindowFontSize(ChatFrame1, 12)
    ChatFrame1:SetUserPlaced(1)

    -- Combat Log
    FCF_SetLocked(ChatFrame2, 1)
    FCF_SetWindowName(ChatFrame2, COMBAT_LOG)
    FCF_SetWindowColor(ChatFrame2, 0, 0, 0)
    FCF_SetWindowAlpha(ChatFrame2, 0)
    FCF_SetChatWindowFontSize(ChatFrame2, 12)
    ChatFrame2:SetUserPlaced(1)

    -- Loot & Spam
    if C.chat.right.enable == "1" then
      -- set position of Loot & Spam
      FCF_SetLocked(ChatFrame3, 1)
      FCF_SetWindowName(ChatFrame3, T["Loot & Spam"])
      FCF_SetWindowColor(ChatFrame3, 0, 0, 0)
      FCF_SetWindowAlpha(ChatFrame3, 0)
      FCF_SetChatWindowFontSize(ChatFrame3, 12)
      FCF_UnDockFrame(ChatFrame3)
      FCF_SetTabPosition(ChatFrame3, 0)
      ChatFrame3:ClearAllPoints()
      ChatFrame3:SetPoint("TOPLEFT", pfUI.chat.right ,"TOPLEFT", 5, -25)
      ChatFrame3:SetPoint("BOTTOMRIGHT", pfUI.chat.right ,"BOTTOMRIGHT", -5, 25)
      ChatFrame3:SetUserPlaced(1)
    end

    pfUI.chat:RefreshChat()
    FCF_DockUpdate()
  end

  function pfUI.chat.SetupChannels()
    ChatFrame_RemoveAllMessageGroups(ChatFrame1)
    ChatFrame_RemoveAllMessageGroups(ChatFrame2)
    ChatFrame_RemoveAllMessageGroups(ChatFrame3)

    ChatFrame_RemoveAllChannels(ChatFrame1)
    ChatFrame_RemoveAllChannels(ChatFrame2)
    ChatFrame_RemoveAllChannels(ChatFrame3)

    local normalg = { "SYSTEM", "SAY", "YELL", "WHISPER", "PARTY", "GUILD", "GUILD_OFFICER", "CREATURE", "CHANNEL", "EMOTE", "RAID", "RAID_LEADER", "RAID_WARNING", "BATTLEGROUND", "BATTLEGROUND_LEADER", "MONSTER_SAY", "MONSTER_EMOTE", "MONSTER_YELL", "MONSTER_WHISPER", "MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER" }
    for _,group in pairs(normalg) do
      ChatFrame_AddMessageGroup(ChatFrame1, group)
    end

    ChatFrame_ActivateCombatMessages(ChatFrame2)

    if C.chat.right.enable == "1" then
      local spamg = { "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL", "LOOT" }
      for _,group in pairs(spamg) do
        ChatFrame_AddMessageGroup(ChatFrame3, group)
      end

      for _, chan in pairs({EnumerateServerChannels()}) do
        ChatFrame_AddChannel(ChatFrame3, chan)
        ChatFrame_RemoveChannel(ChatFrame1, chan)
      end

      -- 注释掉自动加入世界频道的代码
      -- JoinChannelByName("World")
      -- ChatFrame_AddChannel(ChatFrame3, "World")
    end
    pfUI.chat:RefreshChat()
  end

  -- ===== 修改：改为角色专属首次对齐 =====
  pfUI.chat:SetScript("OnEvent", function()
    -- ---- 角色专属首次对齐 ----
    local realm = GetRealmName()
    local player = UnitName("player")
    local charKey = realm .. "_" .. player

    -- 初始化 pfUI_playerDB（如果尚未启用，可自行创建）
    pfUI_playerDB = pfUI_playerDB or {}
    pfUI_playerDB.chat_first_setup = pfUI_playerDB.chat_first_setup or {}

    if not pfUI_playerDB.chat_first_setup[charKey] then
        pfUI.chat.SetupPositions()
        pfUI_playerDB.chat_first_setup[charKey] = true
        -- 注意：pfUI_playerDB 通常会自动保存（如果启用了玩家数据库），
        -- 若未启用，请考虑调用 pfUI.api.SaveConfig() 或自行保存。
    end
    -- ---- 原有其余代码保持不变 ----
    FCF_SelectDockFrame(SELECTED_CHAT_FRAME)
    pfUI.chat:RefreshChat()
    FCF_DockUpdate()
    if C.chat.right.enable == "0" then
      pfUI.chat.right:Hide()
    end
  end)

  local function SkipFading(self, alpha)
    UIFrameFadeRemoveFrame(self)
    if SELECTED_CHAT_FRAME:GetID() == self:GetID() then
      self:_SetAlpha(1)
    else
      self:_SetAlpha(0.5)
    end
  end

  for i=1, NUM_CHAT_WINDOWS do
    _G["ChatFrame" .. i .. "UpButton"]:Hide()
    _G["ChatFrame" .. i .. "UpButton"].Show = function() return end
    _G["ChatFrame" .. i .. "DownButton"]:Hide()
    _G["ChatFrame" .. i .. "DownButton"].Show = function() return end
    _G["ChatFrame" .. i .. "BottomButton"]:Hide()
    _G["ChatFrame" .. i .. "BottomButton"].Show = function() return end
    _G["ChatFrame" .. i .. "Tab"]._SetAlpha = _G["ChatFrame" .. i .. "Tab"].SetAlpha
    _G["ChatFrame" .. i .. "Tab"].SetAlpha = SkipFading
  end

  pfUI.chat.editbox = CreateFrame("Frame", "pfChatInputBox", UIParent)
  pfUI.chat.editbox:SetFrameStrata("DIALOG")
  if C.chat.text.input_height == "0" then
    pfUI.chat.editbox:SetHeight(22)

    if ChatFrameEditBoxLanguage then
      SkinButton(ChatFrameEditBoxLanguage)
      ChatFrameEditBoxLanguage:SetWidth(22)
      ChatFrameEditBoxLanguage:SetHeight(22)
    end
  else
    pfUI.chat.editbox:SetHeight(C.chat.text.input_height)

    if ChatFrameEditBoxLanguage then
      SkinButton(ChatFrameEditBoxLanguage)
      ChatFrameEditBoxLanguage:SetWidth(C.chat.text.input_height)
      ChatFrameEditBoxLanguage:SetHeight(C.chat.text.input_height)
    end
  end

  -- to make sure the bars are set up properly, we need to wait.
  local pfChatArrangeFrame = CreateFrame("Frame", "pfChatArrange", UIParent)
  pfChatArrangeFrame:RegisterEvent("CVAR_UPDATE")
  pfChatArrangeFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfChatArrangeFrame:SetScript("OnEvent", function()
    pfUI.chat.editbox:ClearAllPoints()

    local anchor = pfUI.chat.left
    if pfUI.bars and pfUI.bars[6]:IsShown() then
      anchor = pfUI.bars[6]
    elseif pfUI.bars and pfUI.bars[1]:IsShown() then
      anchor = pfUI.bars[1]
    end

    if C.chat.text.input_width ~= "0" then
      pfUI.chat.editbox:SetPoint("BOTTOM", anchor, "TOP", 0, default_border*3)
      pfUI.chat.editbox:SetWidth(C.chat.text.input_width)
    else
      pfUI.chat.editbox:SetWidth(anchor:GetWidth())
      pfUI.chat.editbox:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, default_border*3)
      pfUI.chat.editbox:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, default_border*3)
    end

    UpdateMovable(pfUI.chat.editbox)
  end)


  ChatFrameEditBox:SetParent(pfUI.chat.editbox)
  ChatFrameEditBox:SetAllPoints(pfUI.chat.editbox)
  CreateBackdrop(ChatFrameEditBox, default_border)

  for i,v in ipairs({ChatFrameEditBox:GetRegions()}) do
    if i==6 or i==7 or i==8 then v:Hide() end
    if v.SetFont then
      v:SetFont(pfUI.font_default, C.global.font_size + 1, "OUTLINE")
    end
  end
  ChatFrameEditBox:SetAltArrowKeyMode(false)

  if C.chat.text.mouseover == "1" then
    for i=1, NUM_CHAT_WINDOWS do
      local frame = _G["ChatFrame" .. i]
      frame:SetScript("OnHyperlinkEnter", function()
        local _, _, linktype = string.find(arg1, "^(.-):(.+)$")
        if linktype == "item" then
          GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
          GameTooltip:SetHyperlink(arg1)
          GameTooltip:Show()
        end
      end)

      frame:SetScript("OnHyperlinkLeave", function()
        GameTooltip:Hide()
      end)
    end
  end

  -- read and parse whisper color settings
  local cr, cg, cb, ca = strsplit(",", C.chat.global.whisper)
  cr, cg, cb = tonumber(cr), tonumber(cg), tonumber(cb)
  local wcol = rgbhex(cr, cg, cb)

  -- read and parse chat bracket settings
  local left = "|r" .. string.sub(C.chat.text.bracket, 1, 1)
  local right = string.sub(C.chat.text.bracket, 2, 2) .. "|r"

  -- read and parse chat time bracket settings
  local tleft = string.sub(C.chat.text.timebracket, 1, 1)
  local tright = string.sub(C.chat.text.timebracket, 2, 2)

  -- shorten chat channel indicators
  local default = " " .. "%s" .. "|r:" .. "\32"
  _G.CHAT_CHANNEL_GET = "%s" .. "|r:" .. "\32"
  _G.CHAT_GUILD_GET = left .. "会" .. right .. default
  _G.CHAT_OFFICER_GET = left .. "官" .. right .. default
  _G.CHAT_PARTY_GET = left .. "队" .. right .. default
  _G.CHAT_RAID_GET = left .. "团" .. right .. default
  _G.CHAT_RAID_LEADER_GET = left .. "团长" .. right .. default
  _G.CHAT_RAID_WARNING_GET = left .. "团队通知" .. right .. default
  _G.CHAT_BATTLEGROUND_GET = left .. "战" .. right .. default
  _G.CHAT_BATTLEGROUND_LEADER_GET = left .. "战场领袖" .. right .. default
  _G.CHAT_SAY_GET = left .. "说" .. right .. default
  _G.CHAT_YELL_GET = left .. "喊" .. right ..default

  if C.chat.global.whispermod == "1" then
    _G.CHAT_WHISPER_GET = wcol .. '[密]' .. default
    _G.CHAT_WHISPER_INFORM_GET = '[密]' .. default
  end

  local r,g,b,a = strsplit(",", C.chat.text.timecolor)
  local timecolorhex = rgbhex(r,g,b,a)

  local r,g,b = strsplit(",", C.chat.text.unknowncolor)
  local unknowncolorhex = rgbhex(r,g,b)

  --================= WSR大神匿名修改 =================--
  -- 等级/职业获取策略：/who 优先（静默查询，绝不弹窗），pfUI 自有缓存
  -- （队伍/公会/好友/DB）作为即时显示与「服务器限流」时的降级回退。

  local who_query = CreateFrame("Frame")
  who_query:RegisterEvent("WHO_LIST_UPDATE")
  who_query.pending = nil
  who_query.lastWhoQuery = 0
  who_query.queryStart = 0
  who_query.lastWhoFailed = false
  -- 静默过滤窗口：自动 /who 期间，AddMessage 钩子会拦截形如「<Name> | <Class>」的
  -- 系统消息（典型 /who 结果）。SetWhoToUI(1) 在 1.12 并不能完全抑制此消息进聊天，
  -- 必须由我们自己在 chat 入口按特征拦截。silentName 置空表示不在拦截窗口。
  who_query.silentUntil = 0
  who_query.silentName = nil
  -- 响应后静默尾巴截止时间：自动查询收到响应(WHO_LIST_UPDATE)后留 1 秒窗口吞掉
  -- 紧随其后的「共计N个玩家」计数消息。手动查询从不置 pending，故不受此影响。
  who_query.silentTail = 0
  -- 保存好友面板原始事件处理函数，供自动 /who 期间临时禁用、查询结束恢复（避免弹窗/面板损坏）
  local originalFriendsFrameOnEvent = _G.FriendsFrame_OnEvent or function() end

  who_query:SetScript("OnEvent", function()
    local evt = arg1 or event
    if evt == "WHO_LIST_UPDATE" then
      if who_query.pending then
        -- 获取 WHO 查询结果并更新缓存
        local numWhos = GetNumWhoResults()
        local got = false
        for i = 1, numWhos do
          local name, guild, level, race, class, zone, classFileName = GetWhoInfo(i)
          if name and level and level > 0 then
            UpdatePlayerLevel(name, level)
            got = true
          end
        end
        -- 成功收到结果，恢复好友面板事件与 /who 导向。
        -- 注意：这里【不要】提前清空 silentName —— 计数消息「共计N个玩家」与逐行结果
        -- 是在同一波响应里稍后以 CHAT_MSG_SYSTEM 发出，清空过早会导致计数漏拦。
        -- silentName 由 8 秒时间窗口(GetTime()<=silentUntil)自动失效，超时分支亦会清理。
        -- 留 1 秒静默尾巴，确保响应后立即到达的计数消息也被吞（手动查询因 pending 为
        -- nil 不在此窗口内，不受影响）。
        who_query.lastWhoFailed = not got
        who_query.pending = nil
        who_query.silentTail = GetTime() + 1
        _G.FriendsFrame_OnEvent = originalFriendsFrameOnEvent
        SetWhoToUI(0)
      end
    end
  end)

  -- 用 OnUpdate 做超时复位：服务器限制/无响应导致 WHO_LIST_UPDATE 不触发时，
  -- 也能在 5 秒后复位 pending、标记失败并恢复 FriendsFrame_OnEvent / SetWhoToUI。
  -- 关键点：查询期间会临时禁用 FriendsFrame_OnEvent（monkey-patch 为空函数）阻止结果
  -- 填充/弹窗；恢复走「WHO_LIST_UPDATE 成功」+「OnUpdate 超时」双出口，可靠，不再依赖
  -- 此前不可靠的 C_Timer.After（那版会在兜底未执行时永久损坏友面板、需小退）。
  -- 注意：1.12 的 SetScript 回调不传入 self，需用闭包变量 who_query。
  who_query:SetScript("OnUpdate", function()
    if who_query.pending and GetTime() - who_query.queryStart >= 5 then
      who_query.pending = nil
      who_query.lastWhoFailed = true
      who_query.silentName = nil
      who_query.silentTail = 0
      -- 超时也需恢复好友面板事件与 /who 结果导向，避免卡死/面板损坏
      _G.FriendsFrame_OnEvent = originalFriendsFrameOnEvent
      SetWhoToUI(0)
    end
  end)

  local function normalizeName(raw)
    if not raw then return nil end
    local colon = string.find(raw, ":")
    local name = raw
    if colon then
      name = string.sub(raw, 1, colon - 1)
    end
    name = gsub(name, "%[", "")
    name = gsub(name, "%]", "")
    name = strtrim(name)
    return name
  end

  local function ScanWhoName(name)
    -- 由 GUI 开关 C.chat.text.whosearchunknown 控制是否启用自动 /who 查询（默认关闭）。
    -- 关闭后完全不发起查询，避免“关了还一直查”的问题。
    if (C.chat.text.whosearchunknown or "0") ~= "1" then return end

    if not name then return end

    local real = normalizeName(name)
    if not real or real == "" then return end

    -- 已有等级则无需查询（/who 仅用于补全未知玩家）
    if GetPlayerLevel(real) then return end

    if who_query.pending then return end

    local currentTime = GetTime()
    -- 客户端 30 秒节流；若上次查询失败（被服务器限流），延长退避，避免不断弹出查询窗口
    local minGap = who_query.lastWhoFailed and 35 or 30
    if currentTime - who_query.lastWhoQuery < minGap then return end

    who_query.pending = true
    who_query.queryStart = currentTime
    who_query.lastWhoQuery = currentTime
    who_query.lastWhoFailed = false
    -- 打开 AddMessage 静默过滤窗口：自动查询进行期间(pending)及收到响应后 1 秒尾巴内，
    -- chat 入口的「<player> | <...>」与「共计N个玩家」系统消息会被吞掉。手动 /who 查询
    -- 从不置 pending，因此照常显示，不会被此逻辑误吞。
    who_query.silentUntil = currentTime + 8
    who_query.silentName = real
    who_query.silentTail = 0

    -- 静默查询：SetWhoToUI(1) 把结果导向好友面板（不进聊天框）；
    -- 同时临时禁用 FriendsFrame_OnEvent，避免结果填充/弹窗。两个出口（WHO_LIST_UPDATE / 超时）
    -- 可靠恢复，不依赖 C_Timer（此前不可靠会导致友面板永久损坏需小退）。
    _G.FriendsFrame_OnEvent = function() end
    SetWhoToUI(1)
    SendWho("n-" .. real)
  end

  -- 频道名称映射表
  local channelMap = {
    ["World"] = "世",
    ["General"] = "综", 
    ["Trade"] = "交",
    ["LFT"] = "组队",
    ["本地防务"] = "防",
    ["China"] = "中",
    ["中文"] = "中",
    -- 添加更多频道映射
    ["综合"] = "综",
    ["交易"] = "交",
    ["世界"] = "世",
    ["世界频道"] = "世界"
  }

  local function AddMessage(frame, text, a1, a2, a3, a4, a5)
    if not text then return end

    -- 自动 /who 静默拦截：仅在「自动查询进行中(pending)」或「刚收到响应的 1 秒尾巴
    -- (silentTail)」内吞掉 /who 系统消息，避免进入聊天框。手动 /who 查询从不置 pending，
    -- 因此照常显示，绝不被此逻辑误吞。1.12 的 SetWhoToUI(1) 拦不住这些消息，必须靠这里拦。
    -- WHO 输出有两类：
    --   (1) 逐行「<player> | <Class>」(含玩家名+分隔符) —— 用 silentName + "|" 精确匹配；
    --   (2) 末尾「共计N个玩家」计数系统消息(不含玩家名、无分隔符) —— 用模式匹配单独屏蔽。
    local _now = GetTime()
    local _silent = who_query.silentName and _now <= who_query.silentUntil
                   and (who_query.pending or _now <= who_query.silentTail)
    if _silent then
      -- (1) 普通 string.find + plain=true 做精确子串匹配（不把玩家名当 Lua 模式）
      if string.find(text, who_query.silentName, 1, true) and string.find(text, "|", 1, true) then
        return
      end
      -- (2) WHO 结果计数消息（如「共计1个玩家」/「共计 1 个玩家」），按模式屏蔽
      if string.find(text, "共计%s*%d+%s*个玩家") then
        return
      end
    end

    -- 更精确的频道名称替换
    -- 处理系统频道消息格式
    for engName, shortName in pairs(channelMap) do
      -- 匹配英文频道名
      text = string.gsub(text, "频道%[" .. engName .. "%]", "频道[" .. shortName .. "]")
      text = string.gsub(text, "频道 %[" .. engName .. "%]", "频道 [" .. shortName .. "]")
      text = string.gsub(text, "%[" .. engName .. "%]", "[" .. shortName .. "]")
      
      -- 匹配中文频道名
      local chnName = engName -- 如果engName本身就是中文
      text = string.gsub(text, "频道%[" .. chnName .. "%]", "频道[" .. shortName .. "]")
      text = string.gsub(text, "频道 %[" .. chnName .. "%]", "频道 [" .. shortName .. "]")
      text = string.gsub(text, "%[" .. chnName .. "%]", "[" .. shortName .. "]")
    end
    
    -- 特殊处理数字频道格式，如 [2. General] -> [2. 综]
    for engName, shortName in pairs(channelMap) do
      text = string.gsub(text, "%[(%d+)%. " .. engName .. "%]", "[%1. " .. shortName .. "]")
      text = string.gsub(text, "%[(%d+)%." .. engName .. "%]", "[%1." .. shortName .. "]")
    end

    -- 处理频道加入/离开消息
    for engName, shortName in pairs(channelMap) do
      text = string.gsub(text, "加入频道%[" .. engName .. "%]", "加入频道[" .. shortName .. "]")
      text = string.gsub(text, "加入了频道%[" .. engName .. "%]", "加入了频道[" .. shortName .. "]")
      text = string.gsub(text, "离开频道%[" .. engName .. "%]", "离开频道[" .. shortName .. "]")
    end

    -- skip chat parsing on combat log
    if frame.pfCombatLog then
      -- 战斗记录同样加时间戳（与普通聊天共用同一配置/格式）
      if C.chat.text.time == "1" then
        text = timecolorhex .. tleft .. date(C.chat.text.timeformat) .. tright .. "|r " .. text
      end
      return frame:HookAddMessage(text, a1, a2, a3, a4, a5)
    end

    -- Remove prat CLINKs
    text = gsub(text, "{CLINK:(%x+):([%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-):([^}]-)}", "|c%1|Hitem:%2|h[%3]|h|r") -- tbc
    text = gsub(text, "{CLINK:(%x+):([%d-]-:[%d-]-:[%d-]-:[%d-]-):([^}]-)}", "|c%1|Hitem:%2|h[%3]|h|r") -- vanilla

    -- Remove chatter CLINKs
    text = gsub(text, "{CLINK:item:(%x+):([%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-:[%d-]-):([^}]-)}", "|c%1|Hitem:%2|h[%3]|h|r")
    text = gsub(text, "{CLINK:enchant:(%x+):([%d-]-):([^}]-)}", "|c%1|Henchant:%2|h[%3]|h|r")
    text = gsub(text, "{CLINK:spell:(%x+):([%d-]-):([^}]-)}", "|c%1|Hspell:%2|h[%3]|h|r")
    text = gsub(text, "{CLINK:quest:(%x+):([%d-]-):([%d-]-):([^}]-)}", "|c%1|Hquest:%2:%3|h[%4]|h|r")

    -- detect urls
    if C.chat.text.detecturl == "1" then
      text = pfUI.chat:HandleLink(text)
    end

    -- display class colors if already indexed
    if C.chat.text.classcolor == "1" then
      for name in gfind(text, "|Hplayer:(.-)|h") do
        local real, _ = strsplit(":", name)
        local color = unknowncolorhex
        local match = false
        local class = GetUnitData(real)
        
        -- 获取玩家等级
        local levelText = ""
        local playerLevel = GetPlayerLevel(real)
        
        -- 如果没找到等级，尝试从队伍中实时获取（兼容经典版本）
        if not playerLevel then
          local inParty = GetNumPartyMembers() > 0
          local inRaid = GetNumRaidMembers() > 0
          if inParty or inRaid then
            local numMembers = inRaid and GetNumRaidMembers() or GetNumPartyMembers()
            for i = 1, numMembers do
              local unit = inRaid and "raid"..i or "party"..i
              local unitName = GetUnitName(unit, true)
              if unitName and string.lower(unitName) == string.lower(real) then
                playerLevel = UnitLevel(unit)
                if playerLevel and playerLevel > 0 then
                  UpdatePlayerLevel(real, playerLevel) -- 使用新函数更新缓存
                  break
                end
              end
            end
          end
        end
        
        if playerLevel and playerLevel > 0 then
          -- 根据难度获取颜色
          local difficultyColor = GetDifficultyColorChatMod(playerLevel, false)
          levelText = rgbhex(difficultyColor.r, difficultyColor.g, difficultyColor.b) .. "[" .. playerLevel .. "]|r"
        end

        if class then
          if class ~= UNKNOWN then
            color = rgbhex(RAID_CLASS_COLORS[class])
            match = true
          end
        end

        -- /who 第一：等级或职业未知时，发起静默 /who 查询补全（30s 节流 + 失败退避）；
        -- pfUI 自有缓存（队伍/公会/好友/DB）作为即时显示与限流降级回退
        if not playerLevel or playerLevel <= 0 or (not class or class == UNKNOWN) then
          ScanWhoName(name)
        end

        if C.chat.text.tintunknown == "1" or match then
          text = string.gsub(text, "|Hplayer:"..name.."|h%["..real.."%]|h(.-:-)",
            left..color.."|Hplayer:"..name.."|h" .. color .. real .. "|h|r"..right.."%1")
        end
      end
    end

    -- display player levels and races if configured
    if (C.chat.text.playerlevel or "0") == "1" or (C.chat.text.playerrace or "0") == "1" then
      for name in gfind(text, "|Hplayer:(.-)|h") do
        local real, _ = strsplit(":", name)
        local class, level, elite, isPlayer, guild, race = GetUnitData(real, true)
        -- 优先使用实时/缓存等级（队伍/公会/好友），避免 GetUnitData 缓存了无效的 -1/0 而显示 ??
        local liveLevel = GetPlayerLevel(real)
        if liveLevel and liveLevel > 0 then
          level = liveLevel
        end

        -- /who 第一：等级未知时优先用 /who 补全；pfUI 缓存作为即时显示与降级回退
        if not level or level <= 0 then
          ScanWhoName(name)
        end

        local prefix = ""
        if (C.chat.text.playerlevel or "0") == "1" then
          if level and level > 0 then
            local levelcolor = rgbhex(GetDifficultyColor(level))
            prefix = prefix .. levelcolor .. "[" .. level .. "]|r"
          elseif level and level <= 0 then
            prefix = prefix .. "|cffff0000[??]|r"
          end
        end

            if (C.chat.text.playerrace or "0") == "1" and race and race ~= "" then
              -- 种族名称映射：将完整名称转换为缩写
              local displayRace = race
              if race == "高等精灵" then
                displayRace = "高精"
             elseif race == "暗夜精灵" then
                displayRace = "暗夜"
             elseif race == "牛头人" then
                displayRace = "牛头"
             end
             -- 使用白色显示种族，可自行修改颜色
             prefix = prefix .. "|cffffffff[" .. displayRace .. "]|r"
          end

        if prefix ~= "" then
          text = string.gsub(text, "(|Hplayer:" .. name .. "|h)(.-)(|h|r)" .. right,
            "%1" .. prefix .. " %2%3" .. right)
        end
      end
    end

    -- reduce channel name to number
    if C.chat.text.channelnumonly == "1" then
      local channel = string.gsub(text, ".*%[(.-)%]%s+(.*|Hplayer).+", "%1")
      if string.find(channel, "%d+%. ") then
        channel = string.gsub(channel, "(%d+)%..*", "channel%1")
        channel = string.gsub(channel, "channel", "")
        text = string.gsub(text, "%[%d+%..-%]%s+(.*|Hplayer)", left .. channel .. right .. " %1")
      end
    end

    -- show timestamp in chat
    if C.chat.text.time == "1" then
      text = timecolorhex .. tleft .. date(C.chat.text.timeformat) .. tright .. "|r " .. text
    end

    -- save chat history
    if C.chat.global.whispermod == "1" and string.find(text, wcol, 1) == 1 then
      SaveChatHistory(frame:GetID(), string.gsub(text, wcol, ""), cr, cg, cb)
    else
      SaveChatHistory(frame:GetID(), text, a1, a2, a3)
    end

    if C.chat.global.whispermod == "1" then
      -- patch incoming whisper string to match the colors
      if string.find(text, wcol, 1) == 1 then
        text = string.gsub(text, "|r", "|r" .. wcol)
      end
    end

    frame:HookAddMessage(text, a1, a2, a3, a4, a5)
  end

  for i=1,NUM_CHAT_WINDOWS do
    if C.chat.global.maxlines ~= "128" then
      _G["ChatFrame"..i]:SetMaxLines(tonumber(C.chat.global.maxlines) or 128)
    end

    if not _G["ChatFrame"..i].HookAddMessage then
      if C.chat.text.history == "1" then
        -- write history to chat
        local history = GetChatHistory(i)
        for j=30,0,-1 do
          if history[j] then
            _G["ChatFrame"..i]:AddMessage(history[j], .7,.7,.7)
          end
        end
      end

      -- add chat parse and history hooks
      _G["ChatFrame"..i].HookAddMessage = _G["ChatFrame"..i].AddMessage
      _G["ChatFrame"..i].AddMessage = AddMessage
    end
  end

  -- create playerlinks on shift-click
  if C.chat.text.playerlinks == "1" then
    local pfHookSetItemRef = SetItemRef
    _G.SetItemRef = function(link, text, button)
      if ( strsub(link, 1, 6) == "player" ) then
        local name = strsub(link, 8)
        if ( name and (strlen(name) > 0) ) then
          local name, _ = strsplit(":", name)
          name = gsub(name, "([^%s]*)%s+([^%s]*)%s+([^%s]*)", "%3")
          name = gsub(name, "([^%s]*)%s+([^%s]*)", "%2")
          if IsShiftKeyDown() and ChatFrameEditBox:IsVisible() then
            ChatFrameEditBox:Insert("|cffffffff|Hplayer:"..name.."|h["..name.."]|h|r")
            return
          end
        end
      end
      pfHookSetItemRef(link, text, button)
    end
  end

  -- ===== 新增：手动对齐斜杠命令 =====
  SLASH_PFALIGNCHAT1 = "/alignchat"
  SlashCmdList["PFALIGNCHAT"] = function()
      pfUI.chat.SetupPositions()
      print("|cff00ff00聊天窗口已对齐！|r")
  end
end)