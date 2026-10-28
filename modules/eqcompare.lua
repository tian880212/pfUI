pfUI:RegisterModule("eqcompare", "vanilla", function ()
  local sides = { "Left", "Right" }
  local loc = pfUI.cache["locale"]
  for key, value in pairs(L["itemtypes"]) do setglobal(key, value) end
  INVTYPE_WEAPON_OTHER = INVTYPE_WEAPON.."_other"
  INVTYPE_FINGER_OTHER = INVTYPE_FINGER.."_other"
  INVTYPE_TRINKET_OTHER = INVTYPE_TRINKET.."_other"
  
  -- 添加装备等级相关的变量
  local LibItem_Level = LibItem_Level or {}
  local lib = LibStub and LibStub("LibItem-enUS-1.0")

  local function AddHeader(tooltip, unit, slot)
    local name = tooltip:GetName()

    -- shift all entries one line down
    for i=tooltip:NumLines(), 1, -1 do
      for _, side in pairs(sides) do
        local current = _G[name.."Text"..side..i]
        local below = _G[name.."Text"..side..i+1]

        if current and current:IsShown() then
          local text = current:GetText()
          local r, g, b = current:GetTextColor()

          if text and text ~= "" then
            if tooltip:NumLines() < i+1 then
              -- add new line if required
              tooltip:AddLine(text, r, g, b, true)
            else
              -- update existing lines
              below:SetText(text)
              below:SetTextColor(r, g, b)
              below:Show()

              -- hide processed line
              current:Hide()
            end
          end
        end
      end
    end

    -- add label to first line
local line = _G[name.."TextLeft1"]
line:SetTextColor(1, 0.84, 0, 1)          -- 金色
line:SetFontObject(GameFontNormalLarge)   -- 大号字体
line:SetText(CURRENTLY_EQUIPPED)
line:Show()
    
    -- 添加装备等级信息
    if unit and slot then
      local itemLink = GetInventoryItemLink(unit, slot)
      if itemLink then
        local _, _, itemID = string.find(itemLink, "item:(%d+):%d+:%d+:%d+")
        itemID = tonumber(itemID)
        if itemID then
          local itemLevel = LibItem_Level[itemID] or 0
          
          -- 如果通过ID没找到，尝试通过物品名称查找
          if itemLevel == 0 and lib and lib.Item_enUS then
            local itemName = GetItemInfo(itemID)
            if itemName then
              for realID, engName in pairs(lib.Item_enUS) do
                if engName == itemName then
                  itemLevel = LibItem_Level[realID] or 0
                  break
                end
              end
            end
          end
          
          if itemLevel > 0 then
            -- 检查是否已添加过装备等级信息
            local lineAdded = false
            for i = 1, tooltip:NumLines() do
              local line = _G[tooltip:GetName() .. "TextLeft" .. i]
              if line and line:GetText() and string.find(line:GetText(), "装备等级") then
                lineAdded = true
                break
              end
            end
            
            -- 未添加过则新增一行
            if not lineAdded then
              tooltip:AddLine("装备等级 " .. itemLevel, 1, 1, 0)
              tooltip:Show()
            end
          end
        end
      end
    end

    -- update tooltip sizes
    tooltip:Show()
  end

  local slotTable = {
    [INVTYPE_2HWEAPON] = "MainHandSlot",
    [INVTYPE_BODY] = "ShirtSlot",
    [INVTYPE_CHEST] = "ChestSlot",
    [INVTYPE_CLOAK] = "BackSlot",
    [INVTYPE_FEET] = "FeetSlot",
    [INVTYPE_FINGER] = "Finger0Slot",
    [INVTYPE_FINGER_OTHER] = "Finger1Slot",
    [INVTYPE_HAND] = "HandsSlot",
    [INVTYPE_HEAD] = "HeadSlot",
    [INVTYPE_HOLDABLE] = "SecondaryHandSlot",
    [INVTYPE_LEGS] = "LegsSlot",
    [INVTYPE_NECK] = "NeckSlot",
    [INVTYPE_RANGED] = "RangedSlot",
    [INVTYPE_RELIC] = "RangedSlot",
    [INVTYPE_ROBE] = "ChestSlot",
    [INVTYPE_SHIELD] = "SecondaryHandSlot",
    [INVTYPE_SHOULDER] = "ShoulderSlot",
    [INVTYPE_TABARD] = "TabardSlot",
    [INVTYPE_TRINKET] = "Trinket0Slot",
    [INVTYPE_TRINKET_OTHER] = "Trinket1Slot",
    [INVTYPE_WAIST] = "WaistSlot",
    [INVTYPE_WEAPON] = "MainHandSlot",
    [INVTYPE_WEAPON_OTHER] = "SecondaryHandSlot",
    [INVTYPE_WEAPONMAINHAND] = "MainHandSlot",
    [INVTYPE_WEAPONOFFHAND] = "SecondaryHandSlot",
    [INVTYPE_WRIST] = "WristSlot",

    [INVTYPE_WAND] = "RangedSlot",
    [INVTYPE_GUN] = "RangedSlot",
    [INVTYPE_PROJECTILE] = "AmmoSlot",
    [INVTYPE_CROSSBOW] = "RangedSlot",
    [INVTYPE_THROWN] = "RangedSlot",
  }

  local function startsWith(str, start)
    return string.sub(str, 1, string.len(start)) == start
  end

  local function ExtractAttributes(tooltip)
    local name = tooltip:GetName()

    -- get the name/header of the last set comparison tooltip
    local comparetooltip = pfUI.eqcompare.tooltip:GetName()
    local iname = _G[comparetooltip .. "TextLeft1"] and _G[comparetooltip .. "TextLeft1"]:GetText()

    -- only run once per item
    if tooltip.pfCompLastName == iname then return end

    tooltip.pfCompData = {}
    tooltip.pfCompLastName = iname

    for i=1,30 do
      local widget = _G[name.."TextLeft"..i]
      if widget and widget:GetObjectType() == "FontString" then
        local text = widget:GetText()
        if text and not string.find(text, "-", 1, true) then
          local start = 1
          if startsWith(text, "\+") or startsWith(text, "\(") then start = 2 end

          local space = string.find(text, " ", 1, true)
          if space then
            local value = tonumber(string.sub(text, start, space-1))
            if value and text then
              -- we've found an attr
              local attr = string.sub(text, space, string.len(text))
              tooltip.pfCompData[attr] = { value = tonumber(value), widget = widget }
            end
          end
        end
      end
    end
  end

  local function CompareAttributes(data, targetData)
    if not data then return end

    for attr,v in pairs(data) do
      if targetData then
        local target = targetData[attr]
        if target then
          if v.value ~= target.value and v.widget:GetText() then
            if v.value > target.value then
              if not strfind(v.widget:GetText(), "|cff88ff88") and not strfind(v.widget:GetText(), "|cffff8888") then
                v.widget:SetText(v.widget:GetText() .. "|cff88ff88 (+" .. round(v.value - target.value, 1) .. ")")
              end
            elseif not v.widget.compSet then
              if not strfind(v.widget:GetText(), "|cff88ff88") and not strfind(v.widget:GetText(), "|cffff8888") then
                v.widget:SetText(v.widget:GetText() .. "|cffff8888 (-" .. round(target.value - v.value, 1) .. ")")
              end
            end
            target.processed = true
          else
            target.processed = true
          end
        else
          -- this attribute doesnt exist in target
          if v.widget and v.widget:GetText() then
            if not strfind(v.widget:GetText(), "|cff88ff88") and not strfind(v.widget:GetText(), "|cffff8888") then
              v.widget:SetText(v.widget:GetText() .. "|cff88ff88 (+" .. v.value .. ")")
            end
          end
        end
      end
    end

    for _,target in pairs(targetData) do
      if target and not target.processed then
        -- we are an extra value
        local text = target.widget:GetText()
        if text and not strfind(text, "|cff88ff88") and not strfind(text, "|cffff8888") then
          target.widget:SetText(text .. "|cff88ff88 (+" .. target.value .. ")")
        end
      end
    end
  end

  pfUI.eqcompare = {}
  pfUI.eqcompare.GameTooltipShow = function()
    -- use this tooltip for the next comparison
    pfUI.eqcompare.tooltip = this

    -- 角色面板内悬停自身已装备物品：对比对象就是自己，无意义 → 跳过装备对比
    local focus = GetMouseFocus()
    local focusName = focus and focus.GetName and focus:GetName()
    if focusName and string.find(focusName, "^Character.*Slot$") then return end

    if not IsShiftKeyDown() and C.tooltip.compare.showalways ~= "1" then return end
    local rawborder, border = GetBorderSize()

    for i=1,this:NumLines() do
      local tmpText = _G[this:GetName() .. "TextLeft"..i]
      for slotType, slotName in pairs(slotTable) do
        if tmpText:GetText() == slotType then
          local slotID = GetInventorySlotInfo(slotTable[slotType])

          -- determine screen part
          local ltrigger = GetScreenWidth() / 2
          local x = GetCursorPosition()
          x = x / UIParent:GetEffectiveScale()
          if x > ltrigger then ltrigger = nil end

          -- first tooltip
          ShoppingTooltip1:SetOwner(this, "ANCHOR_NONE")
          ShoppingTooltip1:ClearAllPoints()

          if ltrigger then
            ShoppingTooltip1:SetPoint("BOTTOMLEFT", this, "BOTTOMRIGHT", 0, 0)
          else
            ShoppingTooltip1:SetPoint("BOTTOMRIGHT", this, "BOTTOMLEFT", -border*2-1, 0)
          end

          ShoppingTooltip1:SetInventoryItem("player", slotID)
          ShoppingTooltip1:Show()
          AddHeader(ShoppingTooltip1, "player", slotID)

          -- second tooltip
          if slotTable[slotType .. "_other"] then
            local slotID_other = GetInventorySlotInfo(slotTable[slotType .. "_other"])

            ShoppingTooltip2:SetOwner(this, "ANCHOR_NONE")
            ShoppingTooltip2:ClearAllPoints()

            if ltrigger then
              ShoppingTooltip2:SetPoint("BOTTOMLEFT", ShoppingTooltip1, "BOTTOMRIGHT", 0, 0)
            else
              ShoppingTooltip2:SetPoint("BOTTOMRIGHT", ShoppingTooltip1, "BOTTOMLEFT", -border*2-1, 0)
            end

            ShoppingTooltip2:SetInventoryItem("player", slotID_other)
            ShoppingTooltip2:Show()
            AddHeader(ShoppingTooltip2, "player", slotID_other)
          end
          return true
        end
      end
    end
  end

  -- add HookScript method if not already existing
  GameTooltip.HookScript = GameTooltip.HookScript or HookScript
  ShoppingTooltip1.HookScript = ShoppingTooltip1.HookScript or HookScript
  ShoppingTooltip2.HookScript = ShoppingTooltip2.HookScript or HookScript

  pfUI.eqcompare.ShoppingTooltipShow = function()
    -- abort if no comparison tooltip has been set
    if not pfUI.eqcompare.tooltip then return end

    ExtractAttributes(this)
    ExtractAttributes(pfUI.eqcompare.tooltip)
    CompareAttributes(pfUI.eqcompare.tooltip.pfCompData, this.pfCompData)
  end

  -- Add Gametooltip Hooks
  GameTooltip:HookScript("OnShow", pfUI.eqcompare.GameTooltipShow)
  if C.tooltip.compare.basestats == "1" then
    ShoppingTooltip1:HookScript("OnShow", pfUI.eqcompare.ShoppingTooltipShow)
    ShoppingTooltip2:HookScript("OnShow", pfUI.eqcompare.ShoppingTooltipShow)
  end
end)