
pfUI:RegisterModule("addons", "vanilla:tbc", function ()
  local rawborder, border = GetBorderSize()

  -- add main menu button
  local pfUIAddonButton = CreateFrame("Button", "GameMenuButtonPFUIAddOns", GameMenuFrame, "GameMenuButtonTemplate")
  pfUIAddonButton:SetPoint("TOP", 0, -32)
  pfUIAddonButton:SetText(T["AddOns"])
  pfUIAddonButton:SetScript("OnClick", function()
    pfUI.addons:Show()
    HideUIPanel(GameMenuFrame)
  end)
  SkinButton(pfUIAddonButton)

  local point, relativeTo, relativePoint, xOffset, yOffset = GameMenuButtonOptions:GetPoint()
  GameMenuButtonOptions:SetPoint(point, relativeTo, relativePoint, xOffset, yOffset - 22)
  GameMenuFrame:SetHeight(GameMenuFrame:GetHeight()+22)

  -- addon window
  pfUI.addons = CreateFrame("Frame", "pfAddons", UIParent)
  pfUI.addons:SetFrameStrata("DIALOG")
  pfUI.addons:SetHeight(490)
  pfUI.addons:SetWidth(380)
  pfUI.addons:SetPoint("CENTER", 0,0)
  pfUI.addons:EnableMouseWheel(1)
  pfUI.addons:SetMovable(true)
  pfUI.addons:EnableMouse(true)
  pfUI.addons:RegisterForDrag("LeftButton")
  pfUI.addons:SetScript("OnDragStart", function() this:StartMoving() end)
  pfUI.addons:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  pfUI.addons:Hide()

  CreateBackdrop(pfUI.addons, nil, true, .75)
  CreateBackdropShadow(pfUI.addons)

  pfUI.addons:SetScript("OnHide", function()
    if this.hasChanged then
      pfUI.gui:Reload()
      this.hasChanged = nil
    end
  end)

  tinsert(UISpecialFrames,"pfAddons")

  pfUI.addons.caption = pfUI.addons:CreateFontString("Status", "LOW", "GameFontNormal")
  pfUI.addons.caption:SetFont(pfUI.font_default, C.global.font_size + 4, "OUTLINE")
  pfUI.addons.caption:SetTextColor(.2, 1, .8, 1)
  pfUI.addons.caption:SetPoint("TOP", 0, -10)
  pfUI.addons.caption:SetJustifyH("LEFT")
  pfUI.addons.caption:SetText(T["Addon List"])

  pfUI.addons.close = CreateFrame("Button", "pfBagClose", pfUI.addons)
  pfUI.addons.close:SetPoint("TOPRIGHT", -border*2,-border*2 )
  CreateBackdrop(pfUI.addons.close)
  pfUI.addons.close:SetHeight(15)
  pfUI.addons.close:SetWidth(15)
  pfUI.addons.close.texture = pfUI.addons.close:CreateTexture("pfBagClose")
  pfUI.addons.close.texture:SetTexture(pfUI.media["img:close"])
  pfUI.addons.close.texture:ClearAllPoints()
  pfUI.addons.close.texture:SetPoint("TOPLEFT", pfUI.addons.close, "TOPLEFT", 4, -4)
  pfUI.addons.close.texture:SetPoint("BOTTOMRIGHT", pfUI.addons.close, "BOTTOMRIGHT", -4, 4)
  pfUI.addons.close.texture:SetVertexColor(1,.25,.25,1)
  pfUI.addons.close:SetScript("OnEnter", function ()
    CreateBackdrop(pfUI.addons.close)
    pfUI.addons.close.backdrop:SetBackdropBorderColor(1,.25,.25,1)
  end)

  pfUI.addons.close:SetScript("OnLeave", function ()
    CreateBackdrop(pfUI.addons.close)
  end)

  pfUI.addons.close:SetScript("OnClick", function()
    pfUI.addons:Hide()
  end)

  -- addons profile
  local function GetSelectedAddonsList()
    local selected_addons = {}
    for i, frame in ipairs(pfUI.addons.list) do
      if frame.input:GetChecked() then
        table.insert(selected_addons, frame.aname)
      end
    end
    return selected_addons
  end

  local function SetAddonProfile(profile)
    -- create new profile if not existing
    if not pfUI_addon_profiles[profile] then
      pfUI_addon_profiles[profile] = GetSelectedAddonsList()
    end

    -- set dropdown to profile
    pfUI.addons.profile.dropdown:SetSelectionByText(profile)

    -- load profile
    local selected_list = pfUI_addon_profiles[profile]
    for i=1, GetNumAddOns() do
      local active = false
      local f = pfUI.addons.list[i]

      for i_i, n in ipairs(selected_list) do
        if f.aname == n then
          active = true
          break
        end
      end

      if active then
        if not f.input:GetChecked() then
          f.input:Click()
        end
      else
        if f.input:GetChecked() then
          f.input:Click()
        end
      end
    end
  end

  -- addon profiles
  pfUI.addons.profile = CreateFrame("Frame", "pfAddonListProfile", pfUI.addons)
  pfUI.addons.profile:SetScript("OnShow", function()
    pfUI_addon_profiles[T["Current"]] = GetSelectedAddonsList()
    SetAddonProfile(T["Current"])
  end)

  pfUI.addons.profile:SetPoint("TOP", pfUI.addons, "TOP", 0, -30)
  pfUI.addons.profile:SetHeight(30)
  pfUI.addons.profile:SetWidth(370)
  CreateBackdrop(pfUI.addons.profile, nil, true)

  -- addon profile: title
  pfUI.addons.profile.caption = pfUI.addons.profile:CreateFontString("Status", "LOW", "GameFontNormal")
  pfUI.addons.profile.caption:SetFontObject(GameFontWhite)
  pfUI.addons.profile.caption:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
  pfUI.addons.profile.caption:SetPoint("LEFT", 10, 0)
  pfUI.addons.profile.caption:SetText(T["Addon Profile"])

  -- addon profile: delete
  pfUI.addons.profile.del = CreateFrame("Button", nil, pfUI.addons.profile, "UIPanelButtonTemplate")
  SkinButton(pfUI.addons.profile.del)
  pfUI.addons.profile.del:SetWidth(16)
  pfUI.addons.profile.del:SetHeight(16)
  pfUI.addons.profile.del:SetPoint("RIGHT", -10, 0)
  pfUI.addons.profile.del:GetFontString():SetPoint("CENTER", 1, 0)
  pfUI.addons.profile.del:SetText("-")
  pfUI.addons.profile.del:SetTextColor(1,.5,.5,1)
  pfUI.addons.profile.del:SetScript("OnClick", function()
    local id, name = pfUI.addons.profile.dropdown:GetSelection()
    if not name then return end
    CreateQuestionDialog(T["Delete profile"] .. " '|cff33ffcc" .. name .. "|r'?", function()
      pfUI_addon_profiles[name] = nil
      SetAddonProfile(T["Current"])
    end)
  end)

  -- addon profile: create
  pfUI.addons.profile.add = CreateFrame("Button", nil, pfUI.addons.profile, "UIPanelButtonTemplate")
  SkinButton(pfUI.addons.profile.add)
  pfUI.addons.profile.add:SetWidth(16)
  pfUI.addons.profile.add:SetHeight(16)
  pfUI.addons.profile.add:SetPoint("RIGHT", pfUI.addons.profile.del, "LEFT", -4, 0)
  pfUI.addons.profile.add:GetFontString():SetPoint("CENTER", 1, 0)
  pfUI.addons.profile.add:SetText("+")
  pfUI.addons.profile.add:SetTextColor(.5,1,.5,1)
  pfUI.addons.profile.add:SetScript("OnClick", function()
    CreateQuestionDialog(T["Please enter a name for the new profile."],
    function()
      local profile_name = this:GetParent().input:GetText()
      -- 只检查是否为空，不检查字符类型
      if profile_name == "" then
        message(T["Profile name cannot be empty"])
      else
        SetAddonProfile(profile_name)
      end
    end, false, true)
  end)

  -- addon profile: dropdown
  pfUI.addons.profile.dropdown = CreateDropDownButton("pfAddonListProfileList", pfUI.addons.profile)
  pfUI.addons.profile.dropdown:SetBackdrop(nil)
  pfUI.addons.profile.dropdown:ClearAllPoints()
  pfUI.addons.profile.dropdown:SetPoint("RIGHT", pfUI.addons.profile.add, "LEFT", -2, 0)
  pfUI.addons.profile.dropdown:SetWidth(220)
  pfUI.addons.profile.dropdown:SetMenu(function()
    local menu = {}

    for name, list in pairs(pfUI_addon_profiles) do
      local name = name
      local entry = {}
      entry.text = name
      entry.checked = false
      entry.func = function()
        SetAddonProfile(name)
      end
      table.insert(menu, entry)
    end

    return menu
  end)

 -- ===================== 重新设计搜索功能 =====================
  -- 搜索容器
  pfUI.addons.search = CreateFrame("Frame", "pfAddonSearchFrame", pfUI.addons)
  pfUI.addons.search:SetPoint("TOP", pfUI.addons.profile, "BOTTOM", 0, -5)
  pfUI.addons.search:SetHeight(28)
  pfUI.addons.search:SetWidth(370)
  CreateBackdrop(pfUI.addons.search, nil, true)

  -- 搜索标签
  pfUI.addons.search.label = pfUI.addons.search:CreateFontString(nil, "OVERLAY", "GameFontWhite")
  pfUI.addons.search.label:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
  pfUI.addons.search.label:SetPoint("LEFT", 8, 0)
  pfUI.addons.search.label:SetText(T["Search"] .. ":")

  -- 搜索输入框
  pfUI.addons.search.input = CreateFrame("EditBox", "pfAddonSearchInput", pfUI.addons.search)
  pfUI.addons.search.input:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
  pfUI.addons.search.input:SetAutoFocus(false)
  pfUI.addons.search.input:SetWidth(310)
  pfUI.addons.search.input:SetHeight(20)
  pfUI.addons.search.input:SetPoint("LEFT", pfUI.addons.search.label, "RIGHT", 5, 0)
  pfUI.addons.search.input:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true, tileSize = 16, edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 }
  })
  pfUI.addons.search.input:SetBackdropColor(0, 0, 0, 0.5)
  pfUI.addons.search.input:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  pfUI.addons.search.input:SetTextInsets(4, 4, 0, 0)
  
  -- 优化的搜索函数
  local function UpdateAddonSearch()
    local searchText = string.lower(pfUI.addons.search.input:GetText() or "")
    
    -- 初始化匹配缓存
    if not pfUI.addons.search.matchCache then
      pfUI.addons.search.matchCache = {}
    end
    
    local matchCount = 0
    
    -- 遍历所有插件
    for i = 1, GetNumAddOns() do
      local frame = pfUI.addons.list[i]
      if frame then
        local match = false
        
        if searchText == "" then
          match = true
        else
          -- 获取插件信息 - 添加更多字段
          local aname = frame.aname or ""
          local atitle = frame.atitle or ""
          local aauthor = frame.aauthor or ""
          local anote = frame.anote or ""
          
          -- 获取更多元数据
          local metadataTitle = GetAddOnMetadata(aname, "Title") or ""
          local metadataNotes = GetAddOnMetadata(aname, "Notes") or ""
          local metadataXTitle = GetAddOnMetadata(aname, "X-Title") or ""
          local metadataXLocalization = GetAddOnMetadata(aname, "X-Localization") or ""
          
          -- 将所有文本合并并转换为小写
          local allText = string.lower(
            aname .. " " .. 
            atitle .. " " .. 
            aauthor .. " " .. 
            anote .. " " .. 
            metadataTitle .. " " .. 
            metadataNotes .. " " .. 
            metadataXTitle .. " " .. 
            metadataXLocalization
          )
          
          -- 使用简单的字符串查找
          if string.find(allText, searchText, 1, true) then
            match = true
          end
        end
        
        pfUI.addons.search.matchCache[i] = match
        
        if match then
          matchCount = matchCount + 1
        end
      end
    end
    
    -- 更新列表高度
    pfUI.addons.list:SetHeight(matchCount * 25 + 26)
    
    -- 刷新显示
    pfUI.addons.scroll:ShowVisibleRange()
  end

  -- 搜索文本变化事件
  pfUI.addons.search.input:SetScript("OnTextChanged", function()
    local text = this:GetText() or ""
    
    -- 显示/隐藏清除按钮
    if text ~= "" then
      pfUI.addons.search.debug:Show()
    else
      pfUI.addons.search.debug:Hide()
    end
    
    -- 更新搜索
    UpdateAddonSearch()
  end)

  -- 输入框焦点/失焦样式
  pfUI.addons.search.input:SetScript("OnEditFocusGained", function()
    this:SetBackdropBorderColor(0.2, 1, 0.8, 1)
  end)
  pfUI.addons.search.input:SetScript("OnEditFocusLost", function()
    this:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  end)

  -- 按ESC失焦
  pfUI.addons.search.input:SetScript("OnEscapePressed", function()
    this:ClearFocus()
  end)
  
  -- 清除按钮
  pfUI.addons.search.debug = CreateFrame("Button", nil, pfUI.addons.search)
  pfUI.addons.search.debug:SetPoint("RIGHT", pfUI.addons.search.input, "RIGHT", -2, 0)
  pfUI.addons.search.debug:SetWidth(16)
  pfUI.addons.search.debug:SetHeight(16)
  pfUI.addons.search.debug:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
  pfUI.addons.search.debug:SetScript("OnClick", function()
    pfUI.addons.search.input:SetText("")
    pfUI.addons.search.input:SetFocus()
  end)
  pfUI.addons.search.debug:Hide()
  -- ===================== 搜索功能结束 =====================

  -- addon list: scroll frame
  pfUI.addons.scroll = CreateScrollFrame("pfAddonListScroll", pfUI.addons)
  pfUI.addons.scroll:SetWidth(360)
  pfUI.addons.scroll:SetHeight(410)
  pfUI.addons.scroll:SetPoint("BOTTOM", 0, 10)
  pfUI.addons.scroll:SetPoint("TOP", pfUI.addons.search, "BOTTOM", 0, -5)

  pfUI.addons.scroll.backdrop = CreateFrame("Frame", nil, pfUI.addons.scroll)
  pfUI.addons.scroll.backdrop:SetFrameLevel(1)
  pfUI.addons.scroll.backdrop:SetPoint("TOPLEFT", pfUI.addons.scroll, "TOPLEFT", -5, 5)
  pfUI.addons.scroll.backdrop:SetPoint("BOTTOMRIGHT", pfUI.addons.scroll, "BOTTOMRIGHT", 5, -5)
  CreateBackdrop(pfUI.addons.scroll.backdrop, nil, true)

  -- addon list: scroll parent
  pfUI.addons.list = CreateScrollChild("pfAddonList", pfUI.addons.scroll)
  pfUI.addons.list:RegisterEvent("ADDON_LOADED")
  pfUI.addons.list:RegisterEvent("PLAYER_ENTERING_WORLD")
  pfUI.addons.list:SetHeight(GetNumAddOns() * 25 + 26)

  local function AddonOnEnter()
    this:SetBackdropBorderColor(1,1,1,.08)

    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText(this.atitle)
    if this.aversion then
      GameTooltip:AddDoubleLine(T["Version"], this.aversion, 1,1,1, .2,1,.8)
    end

    if this.aauthor then
      GameTooltip:AddDoubleLine(T["Author"], this.aauthor, 1,1,1, .2,1,.8)
    end

    GameTooltip:AddLine(this.anote, .75,.75,.75,1)
    GameTooltip:SetWidth(180)
    GameTooltip:Show()
  end

  local function AddonOnLeave()
    this:SetBackdropBorderColor(1,1,1,.04)
    GameTooltip:Hide()
  end

  local function AddonOnClick()
    this.input:Click()
  end

  local function InputOnClick()
    if this:GetChecked() then
      EnableAddOn(this:GetID())
    else
      DisableAddOn(this:GetID())
    end
    pfUI.addons.hasChanged = true

    local id, name = pfUI.addons.profile.dropdown:GetSelection()
    name = name or T["Current"]
    pfUI_addon_profiles[name] = GetSelectedAddonsList()
  end

  pfUI.addons.list:SetScript("OnEvent", function()
    -- 确保搜索缓存初始化
    if not pfUI.addons.search.matchCache then
      pfUI.addons.search.matchCache = {}
    end
    
    for i=1, GetNumAddOns() do
      local aname, atitle, anote = GetAddOnInfo(i)
      local aauthor = GetAddOnMetadata(aname, "Author")
      local aversion = GetAddOnMetadata(aname, "Version")
      
      -- 获取更多元数据，包括中文名称
      local metadataTitle = GetAddOnMetadata(aname, "Title") or ""
      local metadataNotes = GetAddOnMetadata(aname, "Notes") or ""
      local metadataXTitle = GetAddOnMetadata(aname, "X-Title") or ""
      local metadataXLocalization = GetAddOnMetadata(aname, "X-Localization") or ""

      -- basic frame
      if not pfUI.addons.list[i] then
        pfUI.addons.list[i] = CreateFrame("Button", nil, pfUI.addons.list)
        local frame = pfUI.addons.list[i]
        frame.aname = aname
        frame.atitle = atitle
        frame.anote = anote
        frame.aauthor = aauthor
        frame.aversion = aversion
        
        -- 存储额外的元数据用于搜索
        frame.metadataTitle = metadataTitle
        frame.metadataNotes = metadataNotes
        frame.metadataXTitle = metadataXTitle
        frame.metadataXLocalization = metadataXLocalization

        frame:SetWidth(340)
        frame:SetHeight(25)
        frame:SetPoint("TOPLEFT", 5, i * -25 + 20)

        frame:SetBackdrop(pfUI.backdrop_hover)
        frame:SetBackdropBorderColor(1,1,1,.04)

        frame:EnableMouse(1)
        frame:SetScript("OnEnter", AddonOnEnter)
        frame:SetScript("OnLeave", AddonOnLeave)
        frame:SetScript("OnClick", AddonOnClick)

        -- caption
        frame.caption = frame:CreateFontString("Status", "LOW", "GameFontNormal")
        frame.caption:SetFont(pfUI.font_default, C.global.font_size + 2, "OUTLINE")
        frame.caption:SetPoint("LEFT", frame, "LEFT", 2, 0)
        frame.caption:SetFontObject(GameFontWhite)
        frame.caption:SetJustifyH("LEFT")
        frame.caption:SetText(atitle)

        -- input field
        frame.input = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        frame.input:SetFrameLevel(3)
        frame.input:SetNormalTexture("")
        frame.input:SetPushedTexture("")
        frame.input:SetHighlightTexture("")
        CreateBackdrop(frame.input, nil, true)
        frame.input:SetBackdropBorderColor(.3,.3,.3,1)
        frame.input:SetWidth(14)
        frame.input:SetHeight(14)
        frame.input:SetPoint("RIGHT" , -5, 1)
        frame.input:SetID(i)
        frame.input:SetScript("OnClick", InputOnClick)
        
        -- 初始化缓存为true
        pfUI.addons.search.matchCache[i] = true
      end

      if IsAddOnLoaded(i) then
        pfUI.addons.list[i].input:SetChecked()
        pfUI.addons.list[i].caption:SetAlpha(1)
      else
        pfUI.addons.list[i].caption:SetAlpha(.5)
      end
    end
    
    -- 如果有搜索文本，更新搜索
    if pfUI.addons.search.input:GetText() ~= "" then
      UpdateAddonSearch()
    end
    
    -- 刷新显示
    pfUI.addons.scroll:ShowVisibleRange()
  end)

  -- 简化版显示可见范围函数
  function pfUI.addons.scroll:ShowVisibleRange()
    local top_index, bottom_index, range
    range = floor(pfUI.addons.scroll:GetHeight() / 25) + 1
    top_index = floor(pfUI.addons.scroll:GetVerticalScroll() / 25) > 0 and floor(pfUI.addons.scroll:GetVerticalScroll() / 25) or 1
    bottom_index = top_index + range
    
    local visibleIndex = 0
    
    -- 遍历所有插件
    for i = 1, GetNumAddOns() do
      local frame = pfUI.addons.list[i]
      if frame then
        local isMatch = pfUI.addons.search.matchCache and pfUI.addons.search.matchCache[i]
        
        -- 如果缓存不存在，默认为匹配
        if isMatch == nil then
          isMatch = true
        end
        
        if isMatch then
          visibleIndex = visibleIndex + 1
          local isInRange = (visibleIndex >= top_index and visibleIndex <= bottom_index)
          
          -- 重新定位匹配的项
          frame:ClearAllPoints()
          frame:SetPoint("TOPLEFT", 5, -((visibleIndex - 1) * 25) - 20)
          
          if isInRange then
            frame:Show()
          else
            frame:Hide()
          end
        else
          frame:Hide()
        end
      end
    end
    
    -- 计算匹配总数并更新列表高度
    local matchCount = 0
    for i = 1, GetNumAddOns() do
      if pfUI.addons.search.matchCache and pfUI.addons.search.matchCache[i] then
        matchCount = matchCount + 1
      end
    end
    
    pfUI.addons.list:SetHeight(matchCount * 25 + 26)
  end

  pfUI.addons.scroll.slider:SetScript("OnValueChanged", function()
    this:GetParent():SetVerticalScroll(this:GetValue())
    pfUI.addons.scroll:ShowVisibleRange()
  end)
  
  pfUI.addons.scroll:SetScript("OnScrollRangeChanged", function()
    local scrollRange = this:GetVerticalScrollRange()
    if scrollRange > 0 then
      this.slider:SetMinMaxValues(0, scrollRange)
    else
      this.slider:SetMinMaxValues(0, 0)
    end
  end)
  
  pfUI.addons.scroll:SetScript("OnShow", function()
    pfUI.addons.scroll:ShowVisibleRange()
  end)
  
  pfUI.addons.scroll:SetScript("OnVerticalScroll", function()
    pfUI.addons.scroll:ShowVisibleRange()
  end)

end)
