pfUI:RegisterSkin("Macro", "vanilla:tbc", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  HookAddonOrVariable("Blizzard_MacroUI", function()
    -- 主框架美化
    StripTextures(MacroFrame)
    CreateBackdrop(MacroFrame, nil, nil, .75)
    CreateBackdropShadow(MacroFrame)

    MacroFrame.backdrop:SetPoint("TOPLEFT", 10, -10)
    MacroFrame.backdrop:SetPoint("BOTTOMRIGHT", -32, 52)
    MacroFrame:SetHitRectInsets(10,32,10,72)
    EnableMovable(MacroFrame)

    SkinCloseButton(MacroFrameCloseButton, MacroFrame.backdrop, -6, -6)

    local MacroFrameHeaderText = GetNoNameObject(MacroFrame, "FontString", "BORDER", CREATE_MACROS)
    MacroFrameHeaderText:ClearAllPoints()
    MacroFrameHeaderText:SetPoint("TOP", MacroFrame.backdrop, "TOP", 0, -10)

    SkinTab(MacroFrameTab1)
    SkinTab(MacroFrameTab2)
    MacroFrameTab2:ClearAllPoints()
    MacroFrameTab2:SetPoint("LEFT", MacroFrameTab1, "RIGHT", border*2 + 1, 0)

    -- 宏按钮列表
    for i=1, MAX_MACROS do
      local button = _G["MacroButton"..i]
      local icon = _G["MacroButton"..i..'Icon']
      StripTextures(button)
      SkinButton(button, nil, nil, nil, icon)
    end

    -- 选中的宏按钮
    StripTextures(MacroFrameSelectedMacroButton)
    SkinButton(MacroFrameSelectedMacroButton, nil, nil, nil, MacroFrameSelectedMacroButtonIcon, true)
    MacroFrameSelectedMacroName:ClearAllPoints()
    MacroFrameSelectedMacroName:SetPoint("TOPLEFT", MacroFrameSelectedMacroButton, "TOPRIGHT", 6, 3)

    -- 操作按钮
    SkinButton(MacroEditButton)
    SkinButton(MacroDeleteButton)
    SkinButton(MacroExitButton)
    SkinButton(MacroNewButton)
    MacroDeleteButton:ClearAllPoints()
    MacroDeleteButton:SetPoint("BOTTOMLEFT", MacroFrame, "BOTTOMLEFT", 17, 57)
    MacroExitButton:ClearAllPoints()
    MacroExitButton:SetPoint("BOTTOMRIGHT", MacroFrame, "BOTTOMRIGHT", -32, 57)
    MacroNewButton:ClearAllPoints()
    MacroNewButton:SetPoint("RIGHT", MacroExitButton, "LEFT", -2*bpad, 0)

    MacroEditButton:SetHeight(22)
    MacroEditButton:SetWidth(150)
    MacroEditButton:ClearAllPoints()
    MacroEditButton:SetPoint("BOTTOMLEFT", MacroFrameSelectedMacroButton, "BOTTOMRIGHT", 6, -2)

    -- 宏名称输入框
    MacroFrameEnterMacroText:ClearAllPoints()
    MacroFrameEnterMacroText:SetPoint("BOTTOMLEFT", MacroFrameTextBackground, "TOPLEFT", 8, 2)

    -- 宏内容编辑框
    CreateBackdrop(MacroFrameTextBackground, nil, true)
    MacroFrameTextBackground:ClearAllPoints()
    MacroFrameTextBackground:SetPoint("TOPLEFT", MacroFrame, "TOPLEFT", 18, -300)
    StripTextures(MacroFrameScrollFrame)
    SkinScrollbar(MacroFrameScrollFrameScrollBar)
    MacroFrameScrollFrame:ClearAllPoints()
    MacroFrameScrollFrame:SetPoint("TOPLEFT", MacroFrameSelectedMacroBackground, "BOTTOMLEFT", 11, -13)

    -- 图标选择弹出框
    StripTextures(MacroPopupFrame)
    CreateBackdrop(MacroPopupFrame, nil, nil, .75)
    MacroPopupFrame:SetFrameStrata("DIALOG")
    MacroPopupFrame:ClearAllPoints()
    MacroPopupFrame:SetPoint("TOPLEFT", MacroFrame.backdrop, "TOPRIGHT", 2*border, 0)

    -- 弹出框滚动条
    StripTextures(MacroPopupScrollFrame)
    SkinScrollbar(MacroPopupScrollFrameScrollBar)

    -- 弹出框编辑框（图标名称输入）
    MacroPopupEditBox:DisableDrawLayer("BACKGROUND")
    CreateBackdrop(MacroPopupEditBox, nil, true)
    MacroPopupEditBox:SetScript("OnEscapePressed", function()
      MacroPopupFrame:Hide()
      MacroFrame_Update()
    end)

    -- 弹出框图标按钮
    for i=1, NUM_MACRO_ICONS_SHOWN do
      local button = _G["MacroPopupButton"..i]
      local icon = _G["MacroPopupButton"..i..'Icon']
      StripTextures(button)
      SkinButton(button, nil, nil, nil, icon)
    end

    -- 弹出框操作按钮
    SkinButton(MacroPopupCancelButton)
    SkinButton(MacroPopupOkayButton)
    MacroPopupOkayButton:ClearAllPoints()
    MacroPopupOkayButton:SetPoint("RIGHT", MacroPopupCancelButton, "LEFT", -2*bpad, 0)

    -- =============================================
    -- 新增：美化搜索框（您指定的精确名称）
    -- =============================================
    local searchBox = _G["MacroPopupFrameSearchBox"]
    if searchBox then
      StripTextures(searchBox)          -- 移除默认边框
      CreateBackdrop(searchBox, nil, true)  -- 添加 pfUI 风格背景

      -- （可选）如果搜索框位置偏移，可以在这里微调，例如：
      -- searchBox:ClearAllPoints()
      -- searchBox:SetPoint("TOPLEFT", MacroPopupFrame, "TOPLEFT", 10, -10)
      -- searchBox:SetWidth(150)
    end
    -- =============================================

  end)
end)