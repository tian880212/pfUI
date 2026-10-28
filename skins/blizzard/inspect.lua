local slots = {
  "HeadSlot",
  "NeckSlot",
  "ShoulderSlot",
  "BackSlot",
  "ChestSlot",
  "ShirtSlot",
  "TabardSlot",
  "WristSlot",
  "HandsSlot",
  "WaistSlot",
  "LegsSlot",
  "FeetSlot",
  "Finger0Slot",
  "Finger1Slot",
  "Trinket0Slot",
  "Trinket1Slot",
  "MainHandSlot",
  "SecondaryHandSlot",
  "RangedSlot",
}

pfUI:RegisterSkin("Inspect", "vanilla", function ()
  local rawborder, border = GetBorderSize()
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  HookAddonOrVariable("Blizzard_InspectUI", function()
    local cache = {}

    CreateBackdrop(InspectFrame, nil, nil, .75)
    CreateBackdropShadow(InspectFrame)

    InspectFrame.backdrop:SetPoint("TOPLEFT", 10, -10)
    InspectFrame.backdrop:SetPoint("BOTTOMRIGHT", -30, 72)
    InspectFrame:SetHitRectInsets(10,30,10,72)
    EnableMovable("InspectFrame", "Blizzard_InspectUI", INSPECTFRAME_SUBFRAMES)

    SkinCloseButton(InspectFrameCloseButton, InspectFrame.backdrop, -6, -6)

    InspectFrame:DisableDrawLayer("ARTWORK")

    InspectNameText:ClearAllPoints()
    InspectNameText:SetPoint("TOP", InspectFrame.backdrop, "TOP", 0, -10)

    -- Turtle WoW has 4 inspect tabs: Character, Honor, Arena, Talents
    for i = 1, 4 do
      local tab = _G["InspectFrameTab"..i]
      if tab then
        local lastTab = _G["InspectFrameTab"..(i-1)]
        tab:ClearAllPoints()
        if lastTab then
          tab:SetPoint("LEFT", lastTab, "RIGHT", border*2 + 1, 0)
        else
          tab:SetPoint("TOPLEFT", InspectFrame.backdrop, "BOTTOMLEFT", bpad, -(border + (border == 1 and 1 or 2)))
        end
        SkinTab(tab)
      end
    end

    do -- Character Tab
      StripTextures(InspectPaperDollFrame)

      EnableClickRotate(InspectModelFrame)
      local rotL = InspectModelRotateLeftButton or InspectModelFrameRotateLeftButton
      if rotL then rotL:Hide() end
      local rotR = InspectModelRotateRightButton or InspectModelFrameRotateRightButton
      if rotR then rotR:Hide() end

      for _, slot in pairs(slots) do
        local frame = _G["Inspect"..slot]
        StripTextures(frame)
        CreateBackdrop(frame)
        SetAllPointsOffset(frame.backdrop, frame, 0)

        HandleIcon(frame.backdrop, _G["Inspect"..slot.."IconTexture"])

        local funce = frame:GetScript("OnEnter")
        frame:SetScript("OnEnter", function()
          local bid = this:GetID()
          if not GetInventoryItemLink(InspectFrame.unit, this:GetID()) and this.hasItem then
            GameTooltip:SetOwner(this, "ANCHOR_TOPRIGHT")
            GameTooltip:SetHyperlink("item:"..cache[bid]["id"])
            GameTooltip:Show()
          else
            funce()
          end
        end)
      end

      local updateRetries = 0
      local MAX_RETRIES = 3

      local function UpdateSlots()
        -- 修复：使用 UnitExists 进行更严格的检查
        if not InspectFrame.unit or not UnitExists(InspectFrame.unit) then
          updateRetries = 0
          return
        end

        local guild, title, rank = GetGuildInfo(InspectFrame.unit)
        if guild then
          InspectGuildText:SetPoint("TOP", InspectLevelText, "BOTTOM", 0, -1)
          InspectGuildText:SetText(format(TEXT(GUILD_TITLE_TEMPLATE), title, guild))
          InspectGuildText:Show()
        else
          InspectGuildText:SetText("")
          InspectGuildText:Hide()
        end

        for i, vslot in pairs(slots) do
          local id = GetInventorySlotInfo(vslot)
          local link = GetInventoryItemLink(InspectFrame.unit, id)
          local slot = _G["Inspect" .. vslot]
          local retry = false

          if link and slot.hasItem then
            local _, _, link = string.find(link, "(item:%d+:%d+:%d+:%d+)")
            local _, _, quality = GetItemInfo(link)

            if not quality then
              retry = true
            else
              slot.backdrop:SetBackdropBorderColor(GetItemQualityColor(quality))

              if ShaguScore then
                if not slot.scoreText then
                  slot.scoreText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                  slot.scoreText:SetFont(pfUI.font_default, 12, "OUTLINE")
                  slot.scoreText:SetPoint("TOPRIGHT", 0, 0)
                end

                local r,g,b = GetItemQualityColor(quality)
                local _, _, itemID = string.find(link, "item:(%d+):%d+:%d+:%d+")
                local itemLevel = ShaguScore.Database[tonumber(itemID)] or 0
                local score = ShaguScore:Calculate(vslot, quality, itemLevel)
                if score and score > 0 then
                  slot.scoreText:SetText(score)
                  slot.scoreText:SetTextColor(r, g, b)
                else
                  slot.scoreText:SetText("")
                end
              end
            end
          elseif slot.hasItem then
            retry = true
          else
            CreateBackdrop(slot)
            SetAllPointsOffset(slot.backdrop, slot, 0)
            if slot.scoreText then
              slot.scoreText:SetText("")
            end
          end

          if retry == true and InspectFrame.unit then
            if updateRetries < MAX_RETRIES then
              updateRetries = updateRetries + 1
              QueueFunction(UpdateSlots)
            end
          else
            updateRetries = 0
          end
        end
      end

      hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
        -- 修复：确保被检视的单位存在且有效
        if not InspectFrame.unit or not UnitExists(InspectFrame.unit) then
          return
        end

        local bid = button:GetID()
        local link = GetInventoryItemLink(InspectFrame.unit, bid)
        if link then
          local _,_,itemID = string.find(link, 'item:(%d+)')
          cache[bid] = cache[bid] or {}
          cache[bid]["id"] = itemID
          cache[bid]["tex"] = GetInventoryItemTexture(InspectFrame.unit, button:GetID())
          cache[bid]["count"] = GetInventoryItemCount(InspectFrame.unit, button:GetID())
          cache[bid]["name"] = UnitName(InspectFrame.unit)
        elseif cache[bid] and UnitName(InspectFrame.unit) == cache[bid].name then
          -- restore cache information
          SetItemButtonTexture(button, cache[bid]["tex"])
          SetItemButtonCount(button, cache[bid]["count"])
          button.hasItem = 1
        end

        UpdateSlots()
      end)
    end

    do -- Honor Tab
      StripTextures(InspectHonorFrame)

      CreateBackdrop(InspectHonorFrameProgressBar)
      InspectHonorFrameProgressBar:SetStatusBarTexture(pfUI.media["img:bar"])
      InspectHonorFrameProgressBar:SetHeight(24)
    end

    do -- Arena Tab (InspectArenaFrame)
      if InspectArenaFrame then
        StripTextures(InspectArenaFrame)

        -- 美化竞技场分数条（如果存在）
        local pointsBar = InspectArenaFramePointsBar or InspectArenaFrameProgressBar
        if pointsBar then
          StripTextures(pointsBar)
          CreateBackdrop(pointsBar, nil, true)
          pointsBar:SetStatusBarTexture(pfUI.media["img:bar"])
        end

        -- 美化竞技场队伍框架（最多5队）
        for i = 1, 5 do
          local team = _G["InspectArenaTeam"..i] or _G["InspectArenaFrameTeam"..i]
          if team then
            StripTextures(team)
            CreateBackdrop(team)
          end
        end

        -- 可选：美化其他可能的子元素（如标题、分割线等）
        local title = InspectArenaFrameTitle or InspectArenaFrameHeader
        if title then
          StripTextures(title)
        end
      end
    end
  end)

  -- ========================
  -- Turtle WoW Talent Tab (InspectTalentsFrame)
  -- 样式与玩家天赋面板（TalentFrame）保持一致
  -- ========================
  HookAddonOrVariable("InspectTalentsFrame", function()
    -- 确保天赋选项卡是第4个，不干扰原有的荣誉和竞技场选项卡
    if not InspectFrameTab4 then
      CreateFrame('Button', 'InspectFrameTab4', InspectFrame, 'CharacterFrameTabButtonTemplate')
      -- 放在 Tab3 右边（Tab3 应为竞技场）
      if InspectFrameTab3 then
        InspectFrameTab4:SetPoint("LEFT", InspectFrameTab3, "RIGHT", border*2 + 1, 0)
      else
        -- 如果 Tab3 不存在（极少情况），则放在底部
        InspectFrameTab4:SetPoint("TOPLEFT", InspectFrame.backdrop, "BOTTOMLEFT", bpad, -(border + (border == 1 and 1 or 2)))
      end
      SkinTab(InspectFrameTab4)

      InspectFrameTab4:SetID(4)
      InspectFrameTab4:SetText('Talents')
      PanelTemplates_TabResize(0, InspectFrameTab4)
      PanelTemplates_SetNumTabs(InspectFrame, 4)

      InspectFrameTab4:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("Talents", 1.0, 1.0, 1.0)
      end)

      InspectFrameTab4:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)

      InspectFrameTab4:SetScript("OnClick", function()
        InspectFrameTalentsTab_OnClick()
      end)

      if INSPECTFRAME_SUBFRAMES then
        INSPECTFRAME_SUBFRAMES[4] = "InspectTalentsFrame"
      end
    else
      -- 如果已存在，确保其文本和皮肤
      SkinTab(InspectFrameTab4)
      InspectFrameTab4:SetText('天赋')
    end

    -- 主框架：添加背景和阴影（与玩家天赋面板一致）
    if InspectTalentsFrame then
      StripTextures(InspectTalentsFrame)
      CreateBackdrop(InspectTalentsFrame, nil, nil, .75)
      CreateBackdropShadow(InspectTalentsFrame)

      -- 设置背景位置和点击区域
      InspectTalentsFrame.backdrop:SetPoint("TOPLEFT", 10, -10)
      InspectTalentsFrame.backdrop:SetPoint("BOTTOMRIGHT", -32, 72)
      InspectTalentsFrame:SetHitRectInsets(10, 32, 10, 72)
      EnableMovable(InspectTalentsFrame, "InspectTalentsFrame")  -- 允许拖动

      -- 隐藏取消按钮（如果有）
      local cancelBtn = _G["InspectTalentsFrameCancelButton"]
      if cancelBtn then cancelBtn:Hide() end

      -- 处理标题文本
      local title = _G["InspectTalentsFrameTitle"] or _G["InspectTalentsFrameHeader"]
      if title then
        title:ClearAllPoints()
        title:SetPoint("TOP", InspectTalentsFrame.backdrop, "TOP", 0, -10)
      end

      -- 处理剩余点数文本（如果有）
      local pointsText = _G["InspectTalentsFramePointsText"] or _G["InspectTalentsFramePoints"]
      if pointsText then
        pointsText:ClearAllPoints()
        pointsText:SetPoint("TOP", InspectTalentsFrame.backdrop, "TOP", 0, -48)
        pointsText:SetFont(pfUI.font_default, C.global.font_size, "OUTLINE")
      end

      -- 关闭按钮
      local closeBtn = _G["InspectTalentsFrameCloseButton"]
      if closeBtn then
        SkinCloseButton(closeBtn, InspectTalentsFrame.backdrop, -6, -6)
      end
    end

    -- 美化天赋树标签页（TWTalentFrameTab1~3）
    if TWTalentFrame then
      -- 对 TWTalentFrame 本身也应用背景（如果有独立背景层，通常不需要，但为确保一致，可以加）
      StripTextures(TWTalentFrame)

      -- 天赋页签
      for i = 1, 3 do
        local tab = _G["TWTalentFrameTab"..i]
        if tab then
          SkinTab(tab)
          tab:ClearAllPoints()
          local lastTab = _G["TWTalentFrameTab"..(i-1)]
          if lastTab then
            tab:SetPoint("LEFT", lastTab, "RIGHT", border*2 + 1, 0)
          else
            tab:SetPoint("TOPLEFT", TWTalentFrame, "TOPLEFT", 70, -3)
          end
        end
      end

      local function ScanFrames(parent)
        if not parent then return end
      end
      ScanFrames(TWTalentFrame)
    end

      -- ========== 滚动条美化（完全参照角色界面技能面板） ==========
      local scrollFrame = TWTalentFrameScrollFrame
      if scrollFrame then
          StripTextures(scrollFrame)

          local scrollBar = _G["TWTalentFrameScrollFrameScrollBar"]
          if scrollBar then
              -- SkinScrollbar 会同时处理滚动条主体、滑块以及上下按钮的纹理和高亮效果
              SkinScrollbar(scrollBar)
          end
      end
      -- ===============================================================

    -- 修复切换目标时天赋面板不刷新的问题，同时避免“未知的单位”
    hooksecurefunc("InspectUnit", function()
      -- 修复：先检查被检视的单位是否有效
      if not InspectFrame.unit or not UnitExists(InspectFrame.unit) then
        return
      end
      if not UnitExists("target") or not UnitIsPlayer("target") then return end
      local selectedTab = PanelTemplates_GetSelectedTab(InspectFrame)
      if selectedTab == 4 then
        if InspectTalentsFrame then
          InspectTalentsFrame:Hide()
          InspectFrameTalentsTab_OnClick()
        end
      end
    end)
  end)
end)