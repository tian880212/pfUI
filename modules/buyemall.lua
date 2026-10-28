-- pfUI 模块:商人批量购买(BuyEmAll)
-- 移植自 BuyEmAll(作者 Cogwheel),按本客户端(Turtle 1.12 / GetItemInfo 布局异常)行为适配后并入 pfUI
-- 按住 Shift 点击商人出售的物品时弹出购买窗口,可一次购买多组(原生 Shift 拆分只能买一组)
-- 开关:pfUI 设置 -> 背包和银行 -> 启用商人批量购买(C.global.buyemall,点击时实时读取,无需重载)

pfUI:RegisterModule("buyemall", "vanilla", function()
  -- 当前购买会话的状态数据
  local st = { typing = 0 }

  ---------------------------------------------------------------
  -- 界面(对照 BuyEmAll.xml 的 BuyEmAllFrame 重建,外观走 pfUI backdrop)
  ---------------------------------------------------------------
  local frame = CreateFrame("Frame", "pfBuyEmAllFrame", UIParent)
  frame:SetWidth(176)
  frame:SetHeight(150)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:Hide()
  CreateBackdrop(frame, nil, true)
  -- 弹窗浮在商人列表上,主题背景色通常过淡,几乎看不清:强制改为不透明深色底
  -- (legacy 模式下 backdrop 直接画在 frame 上,这里覆写背景色;边框色仍随主题)
  frame:SetBackdropColor(0, 0, 0, .88)

  -- 数量显示(加大字号 + 描边,保证在商人列表上可读)
  local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetJustifyH("CENTER")
  text:SetPoint("TOP", frame, "TOP", 0, -14)
  text:SetFont(pfUI.font_default, 16, "OUTLINE")
  text:SetText("0")

  -- 数量减/加箭头
  local leftBtn = CreateFrame("Button", nil, frame)
  leftBtn:SetWidth(16)
  leftBtn:SetHeight(16)
  leftBtn:SetPoint("RIGHT", text, "LEFT", -12, 0)
  leftBtn:SetNormalTexture("Interface\\MoneyFrame\\Arrow-Left-Up")
  leftBtn:SetPushedTexture("Interface\\MoneyFrame\\Arrow-Left-Down")
  leftBtn:SetDisabledTexture("Interface\\MoneyFrame\\Arrow-Left-Disabled")

  local rightBtn = CreateFrame("Button", nil, frame)
  rightBtn:SetWidth(16)
  rightBtn:SetHeight(16)
  rightBtn:SetPoint("LEFT", text, "RIGHT", 12, 0)
  rightBtn:SetNormalTexture("Interface\\MoneyFrame\\Arrow-Right-Up")
  rightBtn:SetPushedTexture("Interface\\MoneyFrame\\Arrow-Right-Down")
  rightBtn:SetDisabledTexture("Interface\\MoneyFrame\\Arrow-Right-Disabled")

  -- 总价显示(MoneyFrame_Update 按全局名查找金银铜按钮,必须用全局名)
  local mfName = "pfBuyEmAllMoneyFrame"
  local money = CreateFrame("Frame", mfName, frame, "SmallMoneyFrameTemplate")
  money:SetWidth(120)
  money:SetHeight(24)
  money:SetPoint("TOP", frame, "TOP", 7, -40)

  -- 模板 OnLoad 已按 PLAYER 类型初始化,这里改为静态类型:只显示设置的金额,不随玩家金钱变动刷新
  MoneyTypeInfo["PFUI_BUYEMALL"] = {
    UpdateFunc = function() return 0 end,
    showSmallerCoins = "Backpack",
    fixedWidth = 1,
    collapse = 1,
  }
  money.info = MoneyTypeInfo["PFUI_BUYEMALL"]
  money.moneyType = "PFUI_BUYEMALL"
  getglobal(mfName.."GoldButton"):EnableMouse(false)
  getglobal(mfName.."SilverButton"):EnableMouse(false)
  getglobal(mfName.."CopperButton"):EnableMouse(false)
  -- 总价数字同样加大字号 + 描边
  for _, coin in ipairs({ "Gold", "Silver", "Copper" }) do
    local fs = getglobal(mfName..coin.."Button")
    if fs and fs.SetFont then pcall(fs.SetFont, fs, pfUI.font_default, 14, "OUTLINE") end
  end

  -- 按钮(pfUI 风格:纯 Button + SkinButton + 自建 FontString)
  local function MakeButton(width, height, label)
    local btn = CreateFrame("Button", nil, frame)
    btn:SetWidth(width)
    btn:SetHeight(height)
    SkinButton(btn)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontWhite")
    btn.text:SetAllPoints(btn)
    btn.text:SetText(label)
    return btn
  end

  local okayBtn = MakeButton(64, 24, OKAY)
  okayBtn:SetPoint("RIGHT", frame, "BOTTOM", -6, 30)

  local cancelBtn = MakeButton(64, 24, CANCEL)
  cancelBtn:SetPoint("LEFT", frame, "BOTTOM", 6, 30)

  local stackBtn = MakeButton(64, 24, T["Stack"])
  stackBtn:SetPoint("BOTTOM", okayBtn, "TOP", 0, 4)

  local maxBtn = MakeButton(64, 24, T["Max"])
  maxBtn:SetPoint("BOTTOM", cancelBtn, "TOP", 0, 4)

  ---------------------------------------------------------------
  -- 物品信息 / 背包空间计算
  ---------------------------------------------------------------
  -- 草药包/附魔材料包可收纳的物品列表(源自 Periodic Table)
  local specialBagItems = {
    herb = "3358 8839 13466 4625 13467 3821 785 13465 13468 2450 2452 3818 3355 3357 8838 3369 3820 8153 8836 13463 8845 8846 13464 2447 2449 765 2453 3819 3356 8831",
    enchanting = "11083 16204 11137 11176 10940 11174 10938 11135 11175 16202 11134 16203 10998 11082 10939 11084 14343 11139 10978 11177 14344 11138 11178",
  }

  -- 本客户端 GetItemInfo 行为古怪:裸数字/纯数字串会报 Usage,链接未缓存时可能返回 nil;
  -- 且原生返回存在两种布局(带 reqLevel 的标准序 第 7 位子类型/第 8 位堆叠,或不带的 第 6 位/第 7 位),
  -- pfUI 的 compat 垫片还会把返回值重排一遍,按固定位置解构必然取错。
  -- 这里绕开垫片直接调 _G.GetItemInfo,按"数字落在哪一位"自适应取子类型与堆叠。
  -- 返回: itemID, 名称, 子类型, 堆叠上限(未缓存时后两项为 nil,由调用方兜底)
  local function GetItemInfoSafe(link)
    local itemID
    if type(link) == "string" then
      local _, _, id = string.find(link, "item:(%d+):")
      itemID = tonumber(id)
    end
    if not itemID then return end

    local ok, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10
    ok, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10 = pcall(_G.GetItemInfo, link)
    if not (ok and v1) then
      ok, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10 = pcall(_G.GetItemInfo, itemID)
    end
    if not (ok and v1) then
      ok, v1, v2, v3, v4, v5, v6, v7, v8, v9, v10 = pcall(_G.GetItemInfo, string.format("item:%d:0:0:0", itemID))
    end
    if not (ok and v1) then return end

    local itemSubType, stackSize
    if type(v7) == "number" then
      -- 无 reqLevel 布局:第 6 位子类型,第 7 位堆叠
      itemSubType, stackSize = v6, v7
    elseif type(v8) == "number" then
      -- 标准 1.12 布局:第 7 位子类型,第 8 位堆叠
      itemSubType, stackSize = v7, v8
    end

    return itemID, v1, itemSubType, stackSize
  end

  -- 判断物品是否可放入草药包/附魔材料包(itemID 是数字,gfind 捕获是字符串,统一转数字再比)
  local function IsSpecialBagItem(bagType, itemID)
    for curID in string.gfind(specialBagItems[bagType], "%d+") do
      if itemID == tonumber(curID) then return true end
    end
    return false
  end

  -- 袋型/弹药类型匹配(本客户端可能是英文或中文,两边都认)
  local function eqAny(value, list)
    for _, v in ipairs(list) do
      if value == v then return true end
    end
    return false
  end
  local AMMO_POUCH = { "Ammo Pouch", "弹药袋" }
  local QUIVER     = { "Quiver", "箭袋" }
  local HERB_BAG   = { "Herb Bag", "草药袋" }
  local ENCH_BAG   = { "Enchanting Bag", "附魔材料袋" }
  local BULLET     = { "Bullet", "子弹" }
  local ARROW      = { "Arrow", "箭矢" }

  -- 计算背包还能容纳多少该物品
  -- 返回: 普通袋可容纳量, 特殊袋(箭袋/弹药袋等)可容纳量, 堆叠上限, 未满堆叠剩余空间列表
  local function FreeBagSpace(itemLink)
    local returns = { freeSpace = 0, specialSpace = 0 }
    local partialSpaces = {}
    local itemID, name, itemSubType, stackSize = GetItemInfoSafe(itemLink)
    if not stackSize or not name then
      -- 物品数据未缓存,放弃计算(调用方会得到可买上限 0,本次 Shift 点击不弹窗)
      return 0, 0, 1
    end

    for theBag = 0, 4 do
      local which, doBag = "freeSpace", true

      if theBag > 0 then -- 0 是背包本体
        local _, _, bagSubType = GetItemInfoSafe(GetInventoryItemLink("player", theBag + 19))
        if (eqAny(bagSubType, AMMO_POUCH) and eqAny(itemSubType, BULLET)) or
           (eqAny(bagSubType, QUIVER) and eqAny(itemSubType, ARROW)) then
          which = "specialSpace"
        elseif eqAny(bagSubType, AMMO_POUCH) or eqAny(bagSubType, QUIVER) or
               eqAny(bagSubType, HERB_BAG) and not IsSpecialBagItem("herb", itemID) or
               eqAny(bagSubType, ENCH_BAG) and not IsSpecialBagItem("enchanting", itemID) then
          doBag = false
        end
      end

      if doBag then
        local numSlot = GetContainerNumSlots(theBag)
        for theSlot = 1, numSlot do
          local link = GetContainerItemLink(theBag, theSlot)
          if not link then
            returns[which] = returns[which] + stackSize
          elseif string.find(link, "["..name.."]", 1, true) then
            local _, itemCount = GetContainerItemInfo(theBag, theSlot)
            returns[which] = returns[which] + stackSize - itemCount
            -- 记录每个未满堆叠的剩余空间(按背包扫描顺序,与客户端堆叠填充顺序一致)
            if itemCount > 0 and itemCount < stackSize then
              table.insert(partialSpaces, stackSize - itemCount)
            end
          end
        end
      end
    end

    return returns.freeSpace, returns.specialSpace, stackSize, partialSpaces
  end

  ---------------------------------------------------------------
  -- 数量与显示逻辑
  ---------------------------------------------------------------
  -- 计算"一组"按钮点到的数量:向上补到下一整堆叠
  local function SetStackClick()
    local increase = st.partialFit - mod(st.split, st.stack)
    -- 原版此处 increase 为负时会向下取整(背包恰好装满整数组时可复现,数量甚至可归零);
    -- 改为向上取整,更符合"一组"按钮的直觉
    if increase <= 0 then increase = increase + st.stack end
    st.stackClick = st.split + increase
  end

  local isUpdating
  -- 刷新数量文字、总价和按钮状态;amount 仅用于悬停按钮时预览,不改变实际选定数量
  local function UpdateDisplay(amount)
    local purchase = ceil((amount and amount or st.split) / st.preset)
    MoneyFrame_Update(mfName, purchase * st.price)

    if not amount and not isUpdating then
      -- Enable/Disable 会触发事件回调重入本函数,用 isUpdating 防栈溢出
      isUpdating = true

      text:SetText(st.split)
      leftBtn:Enable()
      rightBtn:Enable()
      if st.split == st.max then
        rightBtn:Disable()
      elseif st.split <= st.preset then
        leftBtn:Disable()
      end

      SetStackClick()
      stackBtn:Enable()
      if st.max < st.stackClick then
        stackBtn:Disable()
      end

      isUpdating = nil
    end
  end

  -- 数量减到下一整商人组
  local function Left_Click()
    if st.split <= st.preset then return end

    local decrease = mod(st.split, st.preset)
    decrease = decrease == 0 and st.preset or decrease
    st.split = st.split - decrease

    UpdateDisplay()
  end

  -- 数量加到上一整商人组
  local function Right_Click()
    local increase = st.preset - mod(st.split, st.preset)
    if st.split + increase > st.max then return end

    st.split = st.split + increase

    UpdateDisplay()
  end

  -- 购买请求泵:逐帧派发 BuyMerchantItem(每 0.05 秒一笔)
  -- ⛔ 两个约束:1) 同一帧内连发多笔购买会丢数量(实测买 100 缺 10);
  -- 2) OnUpdate 不会在隐藏 frame 上触发,而 DoPurchase 会先 Hide 弹窗,
  --    所以泵用独立的无贴图 frame 承载(无贴图 = 屏幕上不可见,但 OnUpdate 正常跑)
  local purchaseQueue, queueItem, purchaseCooldown = nil, nil, 0
  _G.PFBUYEMALL_LOG = _G.PFBUYEMALL_LOG or {}
  local pump = CreateFrame("Frame", "pfBuyEmAllPump", UIParent)
  pump:SetScript("OnUpdate", function()
    if not purchaseQueue then return end
    purchaseCooldown = purchaseCooldown - arg1
    if purchaseCooldown > 0 then return end
    purchaseCooldown = 0.05
    -- 商人窗口已关,剩余请求作废
    if not MerchantFrame:IsVisible() then purchaseQueue = nil return end
    local n = table.remove(purchaseQueue, 1)
    if table.getn(purchaseQueue) == 0 then purchaseQueue = nil end
    if n then
      BuyMerchantItem(queueItem, n)
      -- 诊断日志(上限 200 条):/run pfBuyEmAllDumpLog() 查看实际发出的每笔请求
      if table.getn(_G.PFBUYEMALL_LOG) > 200 then _G.PFBUYEMALL_LOG = {} end
      table.insert(_G.PFBUYEMALL_LOG, "buy "..queueItem.." x"..n)
    end
  end)
  _G.pfBuyEmAllDumpLog = function()
    for _, line in ipairs(_G.PFBUYEMALL_LOG) do
      DEFAULT_CHAT_FRAME:AddMessage(line)
    end
  end

  -- 实际购买;amount 必须是商人组的整数倍(组>1 时);生成请求队列交由 pump 逐帧派发
  local function DoPurchase(amount)
    -- 上一批请求还没发完,忽略本次购买(防队列被覆盖导致丢数量)
    if purchaseQueue then return end
    frame:Hide()

    local queue = {}
    queueItem = st.itemIndex
    if st.preset > 1 then
      for i = 1, amount / st.preset do
        table.insert(queue, 1)
      end
    else
      local remaining = amount
      -- ⛔ 本客户端 BuyMerchantItem 一次买 N 个,若客户端选中的堆叠剩余空间 < N,
      -- 多余数量会被吞掉(实测:背包有一组 10/20 的水晶瓶,买 100 只到手 90)。
      -- 未满堆叠逐个买 1 补满(1 恒 <= 任意剩余空间,不依赖客户端的堆叠选择顺序);
      -- 补满后再按整堆叠买,零头最后买(此时已无未满堆叠,任意数量安全)。
      if st.partialSpaces and remaining > 0 then
        for i = 1, table.getn(st.partialSpaces) do
          for _ = 1, st.partialSpaces[i] do
            table.insert(queue, 1)
            remaining = remaining - 1
            if remaining <= 0 then break end
          end
          if remaining <= 0 then break end
        end
      end
      while remaining >= st.stack do
        table.insert(queue, st.stack)
        remaining = remaining - st.stack
      end
      if remaining > 0 then
        table.insert(queue, remaining)
      end
    end
    purchaseQueue = queue
    purchaseCooldown = 0
  end

  StaticPopupDialogs["PFUI_BUYEMALL_CONFIRM"] = {
    text = T["Are you sure you want to buy\n %d × %s?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(amount) DoPurchase(amount) end,
    timeout = 0,
    hideOnEscape = 1,
  }

  -- 购买数量超过一整组时先弹确认框
  local function DoConfirmation(amount)
    StaticPopup_Show("PFUI_BUYEMALL_CONFIRM", amount, st.itemName, amount)
  end

  local function VerifyPurchase(amount)
    amount = amount or st.split
    if amount > 0 then
      amount = ceil(amount / st.preset) * st.preset
      if amount > st.stack and amount > st.defaultStack then
        DoConfirmation(amount)
      else
        DoPurchase(amount)
      end
    end
  end

  -- 初始化并显示购买窗口,锚定在被点击的物品按钮上
  local function OpenFrame(anchor)
    st.typing = 0
    leftBtn:Disable()
    rightBtn:Enable()
    stackBtn:Enable()
    if st.max < st.stackClick then
      stackBtn:Disable()
    end

    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 0)
    frame:Show()
    UpdateDisplay()
  end

  ---------------------------------------------------------------
  -- "一组"/"最多"按钮的悬停提示(对照 BuyEmAll.lines;
  -- 原版把 afford/fit 两个标签对调了,这里按正确含义对应)
  ---------------------------------------------------------------
  local tipLines = {
    stack = {
      label = T["Stack purchase"],
      field = "stackClick",
      { label = T["Stack size"], field = "stack" },
      { label = T["Partial stack"], field = "partialFit" },
    },
    max = {
      label = T["Max purchase"],
      field = "max",
      { label = T["You can afford"], field = "afford" },
      { label = T["You can fit"], field = "fit" },
      { label = T["Vendor has"], field = "available",
        Hide = function() return st.available <= 1 end },
    },
  }

  local function ButtonOnEnter()
    local lines = tipLines[this == maxBtn and "max" or "stack"]
    lines.amount = st[lines.field]
    for i, line in ipairs(lines) do
      line.amount = st[line.field]
    end

    GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetText(lines.label.."|cFFFFFFFF - |r"..GREEN_FONT_COLOR_CODE..lines.amount.."|r")
    for _, line in ipairs(lines) do
      if not (line.Hide and line.Hide()) then
        local color = line.amount == lines.amount and GREEN_FONT_COLOR or HIGHLIGHT_FONT_COLOR
        GameTooltip:AddDoubleLine(line.label, line.amount, 1, 1, 1, color.r, color.g, color.b)
      end
    end
    GameTooltip:Show()

    UpdateDisplay(lines.amount)
  end

  local function ButtonOnLeave()
    UpdateDisplay()
    GameTooltip:Hide()
  end

  ---------------------------------------------------------------
  -- 脚本接线
  ---------------------------------------------------------------
  leftBtn:SetScript("OnClick", function() Left_Click() end)
  rightBtn:SetScript("OnClick", function() Right_Click() end)
  okayBtn:SetScript("OnClick", function() VerifyPurchase() end)
  cancelBtn:SetScript("OnClick", function() frame:Hide() end)

  stackBtn:SetScript("OnClick", function()
    st.split = st.stackClick
    UpdateDisplay()
    if this:IsEnabled() == 1 then
      ButtonOnEnter()
    else
      GameTooltip:Hide()
    end
  end)
  maxBtn:SetScript("OnClick", function()
    st.split = st.max
    UpdateDisplay()
  end)

  stackBtn:SetScript("OnEnter", ButtonOnEnter)
  stackBtn:SetScript("OnLeave", ButtonOnLeave)
  maxBtn:SetScript("OnEnter", ButtonOnEnter)
  maxBtn:SetScript("OnLeave", ButtonOnLeave)

  -- 直接输入数字设定购买数量(移植自原生界面的堆叠拆分输入逻辑)
  frame:SetScript("OnChar", function()
    if arg1 < "0" or arg1 > "9" then return end

    if st.typing == 0 then
      st.typing = 1
      st.split = 0
    end

    local split = (st.split * 10) + arg1
    if split == st.split then
      if st.split == 0 then
        st.split = 1
      end
      UpdateDisplay()
      return
    end

    if split <= st.max then
      st.split = split
    elseif split == 0 then
      st.split = 1
    end
    UpdateDisplay()
  end)

  frame:SetScript("OnKeyDown", function()
    if arg1 == "BACKSPACE" or arg1 == "DELETE" then
      if st.typing == 0 or st.split == 1 then return end

      st.split = floor(st.split / 10)
      if st.split <= 1 then
        st.split = 1
        st.typing = 0
      end
      UpdateDisplay()
    elseif arg1 == "ENTER" then
      VerifyPurchase()
    elseif arg1 == "ESCAPE" then
      frame:Hide()
    elseif arg1 == "LEFT" or arg1 == "DOWN" then
      Left_Click()
    elseif arg1 == "RIGHT" or arg1 == "UP" then
      Right_Click()
    end
  end)

  -- ⛔ 本客户端常驻 frame 绝不能常开 EnableKeyboard(会抢占键盘焦点吞掉全部按键)
  -- 改为仅在窗口显示期间开启,关闭时立即还原
  frame:SetScript("OnShow", function() this:EnableKeyboard(true) end)
  frame:SetScript("OnHide", function()
    this:EnableKeyboard(false)
    StaticPopup_Hide("PFUI_BUYEMALL_CONFIRM")
  end)

  -- 商人窗口关闭时一并关闭购买窗口(pfUI HookScript 为链式安全版)
  HookScript(MerchantFrame, "OnHide", function()
    frame:Hide()
  end)

  ---------------------------------------------------------------
  -- 接管商人物品按钮的 Shift 点击(链式保留原实现)
  ---------------------------------------------------------------
  if not _G.pfUIBuyEmAllHooked then
    _G.pfUIBuyEmAllHooked = true
    local origMerchantItemButton_OnClick = _G.MerchantItemButton_OnClick

    function _G.MerchantItemButton_OnClick(button, ignoreModifiers)
      if MerchantFrame.selectedTab == 1
          and C["global"]["buyemall"] == "1"
          and IsShiftKeyDown()
          and not IsControlKeyDown()
          and not ignoreModifiers
          and not (ChatFrameEditBox and ChatFrameEditBox:IsVisible() and button == "LeftButton") then

        local itemButton = this
        st.itemIndex = itemButton:GetID()

        local name, texture, price, quantity, numAvailable = GetMerchantItemInfo(st.itemIndex)
        st.preset = quantity or 1
        st.price = price or 0
        st.itemName = name
        st.available = numAvailable

        local bagMax, specialMax, stack, partialSpaces = FreeBagSpace(GetMerchantItemLink(st.itemIndex))
        st.stack = stack
        st.partialSpaces = partialSpaces
        st.fit = floor(bagMax / st.preset) * st.preset + specialMax
        if st.price > 0 then
          st.afford = floor(GetMoney() / st.price) * st.preset
        else
          st.afford = st.fit -- 免费物品按可容纳量计,避免 0 除产生 nan
        end
        st.max = min(st.fit, st.afford)
        if numAvailable and numAvailable > -1 then
          st.max = min(st.max, numAvailable * st.preset)
        end

        if st.max == 0 or not name then
          return
        elseif st.max == 1 then
          -- 只能买一个时直接走原生单击购买
          origMerchantItemButton_OnClick("LeftButton", 1)
          return
        end

        specialMax = floor(specialMax / st.preset) * st.preset
        st.defaultStack = (specialMax > 0 and specialMax <= st.max) and specialMax or st.preset
        st.split = st.defaultStack
        st.partialFit = mod(st.fit, stack)
        SetStackClick()
        OpenFrame(itemButton)
      else
        origMerchantItemButton_OnClick(button, ignoreModifiers)
      end
    end
  end
end)
