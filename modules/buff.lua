pfUI:RegisterModule("buff", "vanilla:tbc", function ()
  -- Hide Blizz
  BuffFrame:Hide()
  BuffFrame:UnregisterAllEvents()
  TemporaryEnchantFrame:Hide()
  TemporaryEnchantFrame:UnregisterAllEvents()

  local br, bg, bb, ba = GetStringColor(pfUI_config.appearance.border.color)

  local function RefreshBuffButton(buff)
    if buff.btype == "HELPFUL" then
      if C.buffs.separateweapons == "1" then
        buff.id = buff.gid - (buff.weapon ~= nill and buff.gid or 0)
      else
        buff.id = buff.gid - pfUI.buff.wepbuffs.count
      end
    else
      buff.id = buff.gid
    end
    buff.bid = GetPlayerBuff(PLAYER_BUFF_START_ID+buff.id, buff.btype)

    if not buff.backdrop then
      CreateBackdrop(buff)
      CreateBackdropShadow(buff)
    end

    -- 初始化武器标签（如果不存在）
    if not buff.weaponLabel and buff.weapon then
      buff.weaponLabel = buff:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      buff.weaponLabel:SetTextColor(1, 1, 1, 1)
      buff.weaponLabel:SetJustifyH("LEFT")
      buff.weaponLabel:SetJustifyV("TOP")
      buff.weaponLabel:SetFont(pfUI.font_default, 10, "OUTLINE")
      buff.weaponLabel:SetPoint("TOPLEFT", buff, "TOPLEFT", 2, -2)
    end

    --detect weapon buffs
    if buff.btype == "HELPFUL" and ((C.buffs.separateweapons == "0" and buff.gid <= pfUI.buff.wepbuffs.count) or (pfUI.buff.wepbuffs.count > 0 and buff.weapon ~= nil)) then
        local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()
        if pfUI.buff.wepbuffs.count == 2 then
          if buff.gid == 1 then
            buff.mode = "MAINHAND"
          else
            buff.mode = "OFFHAND"
          end
        else
          if C.buffs.separateweapons == "0" then
            buff.mode = mh and "MAINHAND" or oh and "OFFHAND"
          else
            if buff.gid == 1 then
              buff.mode = mh and "MAINHAND" or oh and "OFFHAND"
            else
              buff:Hide()
              return
            end
          end
        end

      -- Set Weapon Texture and Border
      if buff.mode == "MAINHAND" then
        buff.texture:SetTexture(GetInventoryItemTexture("player", 16))
        buff.backdrop:SetBackdropBorderColor(GetItemQualityColor(GetInventoryItemQuality("player", 16) or 1))
        if buff.weaponLabel then
          buff.weaponLabel:SetText("主")
          buff.weaponLabel:Show()
        end
      elseif buff.mode == "OFFHAND" then
        buff.texture:SetTexture(GetInventoryItemTexture("player", 17))
        buff.backdrop:SetBackdropBorderColor(GetItemQualityColor(GetInventoryItemQuality("player", 17) or 1))
        if buff.weaponLabel then
          buff.weaponLabel:SetText("副")
          buff.weaponLabel:Show()
        end
      end
    elseif GetPlayerBuffTexture(buff.bid) and (( buff.btype == "HARMFUL" and C.buffs.debuffs == "1" ) or ( buff.btype == "HELPFUL" and C.buffs.buffs == "1" )) then
      -- Set Buff Texture and Border
      buff.mode = buff.btype
      buff.texture:SetTexture(GetPlayerBuffTexture(buff.bid))
      
      -- 隐藏武器标签（如果不是武器buff）
      if buff.weaponLabel then
        buff.weaponLabel:Hide()
      end

      if buff.btype == "HARMFUL" then
        local dtype = GetPlayerBuffDispelType(buff.bid)
        if dtype == "Magic" then
          buff.backdrop:SetBackdropBorderColor(0,1,1,1)
        elseif dtype == "Poison" then
          buff.backdrop:SetBackdropBorderColor(0,1,0,1)
        elseif dtype == "Curse" then
          buff.backdrop:SetBackdropBorderColor(1,0,1,1)
        elseif dtype == "Disease" then
          buff.backdrop:SetBackdropBorderColor(1,1,0,1)
        else
          buff.backdrop:SetBackdropBorderColor(1,0,0,1)
        end
      else
        buff.backdrop:SetBackdropBorderColor(br,bg,bb,ba)
      end
    else
      -- Fallback: try UnitBuff/UnitDebuff API which may be more reliable in some cases
      local fallbackTexture, fallbackStacks, fallbackDispelType, fallbackSpellId
      local maxSlots = buff.btype == "HELPFUL" and 32 or 16

      if buff.id >= 1 and buff.id <= maxSlots then
        if buff.btype == "HELPFUL" and C.buffs.buffs == "1" then
          for i = 1, maxSlots do
            local tex, stacks, dtype, spellId = UnitBuff("player", i)
            if tex and i == buff.id then
              fallbackTexture, fallbackStacks, fallbackDispelType, fallbackSpellId = tex, stacks, dtype, spellId
              break
            end
            if not tex then break end
          end
        elseif buff.btype == "HARMFUL" and C.buffs.debuffs == "1" then
          for i = 1, maxSlots do
            local tex, stacks, dtype, spellId = UnitDebuff("player", i)
            if tex and i == buff.id then
              fallbackTexture, fallbackStacks, fallbackDispelType, fallbackSpellId = tex, stacks, dtype, spellId
              break
            end
            if not tex then break end
          end
        end
      end

      if fallbackTexture then
        buff.mode = buff.btype
        buff.fallbackSpellId = fallbackSpellId
        buff.texture:SetTexture(fallbackTexture)
        if buff.btype == "HARMFUL" then
          if fallbackDispelType == "Magic" then
            buff.backdrop:SetBackdropBorderColor(0,1,1,1)
          elseif fallbackDispelType == "Poison" then
            buff.backdrop:SetBackdropBorderColor(0,1,0,1)
          elseif fallbackDispelType == "Curse" then
            buff.backdrop:SetBackdropBorderColor(1,0,1,1)
          elseif fallbackDispelType == "Disease" then
            buff.backdrop:SetBackdropBorderColor(1,1,0,1)
          else
            buff.backdrop:SetBackdropBorderColor(1,0,0,1)
          end
        else
          buff.backdrop:SetBackdropBorderColor(br,bg,bb,ba)
        end
      else
        buff:Hide()
        return
      end
    end

    -- 黑白名单过滤（与 BuffWatch / BuffBar 一致：# 分隔；以 spellID 为主，名称尽力匹配；武器附魔不参与）
    if buff.mode == buff.btype and not pfUI.buff:AuraVisible(buff) then
      buff:Hide()
      return
    end

    -- 分离显示：命中「分离名单」的 buff/debuff 交给独立容器重点显示，原行内隐藏
    -- （黑名单优先：上面已被隐藏的不会走到这里，所以不会出现在重点区）
    -- 监控模式（monitor = "1"）：只复制一份到分离区重点显示，原行照常保留（相当于复制监控）
    if not buff.sep and buff.mode == buff.btype and (buff.btype == "HELPFUL" or buff.btype == "HARMFUL") then
      local isharm = buff.btype == "HARMFUL"
      local idx = pfUI.buff:SepIndex(buff, buff.btype)
      local container = isharm and pfUI.buff.sepdebuffs or pfUI.buff.sepbuffs
      -- WA 式动态：名单不限长，命中即登记（slots 按名单序号记录，显示端按序紧凑重排）。
      -- 按钮超出当前池时由 RefreshSepBuffs 懒创建，无上限（数据层 48 槽自然封顶）。
      if idx and container then
        container.slots = container.slots or {}
        if not container.slots[idx] then
          container.slots[idx] = { bid = buff.bid, id = buff.id }
        end
        local monitor = C.buffs[isharm and "sepdebuffmonitor" or "sepbuffmonitor"] == "1"
        if not monitor then
          buff:Hide()
          return
        end
        -- 监控模式：不隐藏，继续走原行显示流程
      end
    end

    if not buff.sep then buff:SetAlpha(1) end
    buff:Show()
  end

  local function CreateBuffButton(i, btype, weapon, sep)
    local buttonName, buttonParent
    if sep == 2 then
      -- 分离 Debuff 重点区
      buttonName = "pfSepDebuffFrameBuff" .. i
      buttonParent = pfUI.buff.sepdebuffs
    elseif sep == 1 then
      -- 分离 Buff 重点区
      buttonName = "pfSepBuffFrameBuff" .. i
      buttonParent = pfUI.buff.sepbuffs
    elseif btype == "HELPFUL" then
      if weapon == 1 then
        buttonName = "pfWepBuffFrame" .. i
        buttonParent = pfUI.buff.wepbuffs
      else
        buttonName = "pfBuffFrameBuff" .. i
        buttonParent = pfUI.buff.buffs
      end
    else
      buttonName = "pfDebuffFrameBuff" .. i
      buttonParent = pfUI.buff.debuffs
    end
    local buff = CreateFrame("Button", buttonName, buttonParent)
    -- 分离区用独立的纹理名，避免与 BuffIcon1..N（普通 buff / debuff 行共用）的全局名互相覆盖
    local texname = "BuffIcon" .. i
    if sep == 1 then
      texname = "SepBuffIcon" .. i
    elseif sep == 2 then
      texname = "SepDebuffIcon" .. i
    end
    buff.texture = buff:CreateTexture(texname, "BACKGROUND")
    buff.texture:SetTexCoord(.07,.93,.07,.93)
    buff.texture:SetAllPoints(buff)

    buff.timer = buff:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buff.timer:SetTextColor(1,1,1,1)
    buff.timer:SetJustifyH("CENTER")
    buff.timer:SetJustifyV("CENTER")

    buff.stacks = buff:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buff.stacks:SetTextColor(1,1,1,1)
    buff.stacks:SetJustifyH("RIGHT")
    buff.stacks:SetJustifyV("BOTTOM")
    buff.stacks:SetAllPoints(buff)

    buff:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    buff.weapon = weapon
    buff.sep = sep
    buff.btype = btype
    buff.gid = i

    -- 分离区按钮：独立边框高亮，内容由 RefreshSepBuffs 填充
    -- sep == 1 金色（buff），sep == 2 红色（debuff）
    if sep == 1 then
      CreateBackdrop(buff)
      CreateBackdropShadow(buff)
      buff.backdrop:SetBackdropBorderColor(1, .78, .1, 1)
    elseif sep == 2 then
      CreateBackdrop(buff)
      CreateBackdropShadow(buff)
      buff.backdrop:SetBackdropBorderColor(1, .22, .12, 1)
    end

    -- PERF: OnUpdate moved to consolidated parent frame handler (see pfUI.buff:SetScript("OnUpdate"))
    -- Individual buff frames no longer have their own OnUpdate

    buff:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
      if this.mode == this.btype then
        GameTooltip:SetPlayerBuff(this.bid)

        if IsShiftKeyDown() then
          local texture = GetPlayerBuffTexture(this.bid)

          local playerlist = ""
          local first = true

          if UnitInRaid("player") then
            for i=1,40 do
              local unitstr = "raid" .. i
              if not UnitHasBuff(unitstr, texture) and UnitName(unitstr) then
                playerlist = playerlist .. ( not first and ", " or "") .. GetUnitColor(unitstr) .. UnitName(unitstr) .. "|r"
                first = nil
              end
            end
          else
            if not UnitHasBuff("player", texture) then
              playerlist = playerlist .. ( not first and ", " or "") .. GetUnitColor("player") .. UnitName("player") .. "|r"
              first = nil
            end

            for i=1,4 do
              local unitstr = "party" .. i
              if not UnitHasBuff(unitstr, texture) and UnitName(unitstr) then
                playerlist = playerlist .. ( not first and ", " or "") .. GetUnitColor(unitstr) .. UnitName(unitstr) .. "|r"
                first = nil
              end
            end
          end

          if strlen(playerlist) > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(T["Unbuffed"] .. ":", .3, 1, .8)
            GameTooltip:AddLine(playerlist,1,1,1,1)
            GameTooltip:Show()
          end
        end
      elseif this.mode == "MAINHAND" then
        GameTooltip:SetInventoryItem("player", 16)
      elseif this.mode == "OFFHAND" then
        GameTooltip:SetInventoryItem("player", 17)
      end
    end)

    buff:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    buff:SetScript("OnClick", function()
      -- Alt+左键 加入/移出分离名单；Ctrl+左键 加入白名单；Shift+左键 加入黑名单
      if IsAltKeyDown() then
        pfUI.buff:ToggleSepList(this)
        return
      elseif IsControlKeyDown() then
        pfUI.buff:AddToList(this, "whitelist")
        return
      elseif IsShiftKeyDown() then
        pfUI.buff:AddToList(this, "blacklist")
        return
      end
      -- 普通右键：取消 buff
      if arg1 == "RightButton" then
        if CancelItemTempEnchantment and this.mode and this.mode == "MAINHAND" then
          CancelItemTempEnchantment(1)
        elseif CancelItemTempEnchantment and this.mode and this.mode == "OFFHAND" then
          CancelItemTempEnchantment(2)
        else
          CancelPlayerBuff(this.bid)
        end
      end
    end)

    -- 分离区按钮的 bid 由 RefreshSepBuffs 统一分配，创建时不走普通刷新流程
    if sep then
      buff:Hide()
    else
      RefreshBuffButton(buff)
    end

    return buff
  end

  local function GetNumBuffs()
    local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()
    local offset = (mh and 1 or 0) + (oh and 1 or 0)

    for i=1,32 do
      local bid, untilCancelled = GetPlayerBuff(PLAYER_BUFF_START_ID+i, "HELPFUL")
      if bid < 0 then
        return i - 1 + offset
      end
    end
    return 0 + offset
  end

  pfUI.buff = CreateFrame("Frame", "pfGlobalBuffFrame", UIParent)

  -- 黑白名单过滤（spellID 优先，已验证在你的环境可用）
  -- 名单里只认数字 ID，按 spellID 精确匹配（纯 spellID 路径，不再依赖 tooltip 扫描）
  -- 防御：C.buffs 尚未就绪时直接放行，避免模块加载期崩溃。
  function pfUI.buff:GetBuffId(buff)
    if not C or not C.buffs then return nil end
    if pfUI.api.GetPlayerBuffSpellId and buff.bid then
      local sid = pfUI.api.GetPlayerBuffSpellId(buff.bid)
      if sid then return tonumber(sid) end
    end
    if buff.fallbackSpellId then return tonumber(buff.fallbackSpellId) end
    return nil
  end

  -- 黑白名单过滤：spellID 精确匹配
  function pfUI.buff:AuraVisible(buff)
    if not C or not C.buffs then return true end
    local mode = C.buffs.filter or "none"
    -- 智能默认：Filter Mode 为 none 但某张名单非空时，自动按非空名单启用
    -- （避免只在 GUI 列表框里加了条目、却忘了把 Filter Mode 切到对应模式）
    if mode == "none" then
      if (C.buffs.blacklist or "") ~= "" then mode = "blacklist"
      elseif (C.buffs.whitelist or "") ~= "" then mode = "whitelist" end
    end
    if mode == "none" then return true end
    local liststr = (mode == "whitelist" and C.buffs.whitelist) or (mode == "blacklist" and C.buffs.blacklist) or ""
    if liststr == "" then
      -- 白名单空 => 全部隐藏；黑名单空 => 全部显示
      return mode == "blacklist"
    end
    local sid = pfUI.buff:GetBuffId(buff)
    local found = false
    for v in string.gmatch(liststr, "[^#;]+") do
      v = string.gsub(v, "^%s*(.-)%s*$", "%1") -- 去前后空格
      if v ~= "" and tonumber(v) and sid and tonumber(v) == sid then
        found = true; break
      end
    end
    return mode == "whitelist" and found or not found
  end

  function pfUI.buff:AddToList(buff, which)
    if not C or not C.buffs then return end
    local sid = pfUI.buff:GetBuffId(buff)
    if not sid then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 无法读取该 buff 的 spellID，未能加入名单")
      return
    end
    local tag = which == "whitelist" and "白" or "黑"
    local list = C.buffs[which] or ""
    local exists = false
    for v in string.gmatch(list, "[^#;]+") do
      if tonumber(v) and sid and tonumber(v) == sid then exists = true; break end
    end
    if exists then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: ID " .. sid .. " 已在" .. tag .. "名单中")
      return
    end
    C.buffs[which] = (list ~= "" and list .. "#" or "") .. tostring(sid)
    if C.buffs.filter == "none" then
      C.buffs.filter = which
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: ID " .. sid .. " 已加入" .. tag .. "名单，过滤模式已自动切换为「" .. tag .. "名单」")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: ID " .. sid .. " 已加入" .. tag .. "名单")
    end
    if pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end
  end

  -- ==========================================================================
  -- 分离 Buff（Seperate Buffs）：把名单里的 buff 从普通 buff 行中抽出来，
  -- 放到独立容器里放大 + 高亮显示。与「分离武器 Buff」同一套思路：
  --   独立容器(pfUI.buff.sepbuffs) + 独立按钮 + 原行内隐藏 + 紧凑重排
  -- ==========================================================================

  -- 每帧最多可分离显示的 buff / debuff 数量（也是预创建的按钮数量）
  -- 48 = Nampower aura 数组总槽数（1-32 buff 区 + 33-48 debuff 区），数据层天花板；
  -- 名单条目按序号占槽，抬到 48 让超长名单（第 33-48 条）也能进分离/监控区。
  pfUI.buff.SEPBUFF_COUNT = 48
  pfUI.buff.SEPDEBUFF_COUNT = 48
  pfUI.buff.namecache = {}

  -- 读取 buff 名称：优先 GetPlayerBuffName，失败再用 tooltip 扫描（结果按 spellID 缓存）
  function pfUI.buff:GetBuffName(buff)
    local bid = buff and buff.bid
    if not bid or bid < 0 then return nil end

    if GetPlayerBuffName then
      local n = GetPlayerBuffName(bid)
      if n and n ~= "" then return n end
    end

    local sid = pfUI.buff:GetBuffId(buff)
    if sid and pfUI.buff.namecache[sid] then return pfUI.buff.namecache[sid] end

    if not pfUI.buff.scantip then
      pfUI.buff.scantip = CreateFrame("GameTooltip", "pfSepBuffScanTip", UIParent, "GameTooltipTemplate")
      pfUI.buff.scantip:Hide()
    end

    local name = nil
    local ok = pcall(function()
      local tip = pfUI.buff.scantip
      tip:SetOwner(UIParent, "ANCHOR_NONE")
      tip:ClearLines()
      tip:SetPlayerBuff(bid)
      local label = getglobal("pfSepBuffScanTipTextLeft1")
      if label then
        local txt = label:GetText()
        if txt and txt ~= "" then name = txt end
      end
      tip:Hide()
    end)

    if name and sid then pfUI.buff.namecache[sid] = name end
    return name
  end

  -- 解析分离名单（# 分隔），返回数组，顺序即显示顺序
  -- kind == "HARMFUL" 读 debuff 名单，否则读 buff 名单
  function pfUI.buff:GetSepList(kind)
    local list = {}
    if not C or not C.buffs then return list end
    local raw = (kind == "HARMFUL") and C.buffs.sepdebufflist or C.buffs.separatelist
    for v in string.gmatch(raw or "", "[^#;]+") do
      v = string.gsub(v, "^%s*(.-)%s*$", "%1")
      if v ~= "" then table.insert(list, v) end
    end
    return list
  end

  -- 判断某个 aura 是否命中分离名单，返回命中的名单序号（用于固定显示顺序）
  -- 支持两种写法：aura 名称（推荐），或纯数字 spellID
  -- kind 省略时按 buff.btype 自动判断（HELPFUL -> buff 名单 / HARMFUL -> debuff 名单）
  function pfUI.buff:SepIndex(buff, kind)
    if not C or not C.buffs then return nil end
    kind = kind or (buff and buff.btype) or "HELPFUL"
    local isharm = kind == "HARMFUL"
    if isharm then
      if C.buffs.separatedebuffs ~= "1" then return nil end
    else
      if C.buffs.separatebuffs ~= "1" then return nil end
    end

    local list = pfUI.buff:GetSepList(kind)
    if getn(list) == 0 then return nil end

    local sid = pfUI.buff:GetBuffId(buff)
    local name = pfUI.buff:GetBuffName(buff)
    local lname = name and string.lower(name) or nil

    -- 第一遍：精确匹配（spellID 或 完整名称）
    for i, entry in ipairs(list) do
      if tonumber(entry) and sid and tonumber(entry) == sid then return i end
      if lname and string.lower(entry) == lname then return i end
    end

    -- 第二遍：子串匹配（填「智慧」也能命中「奥术智慧」之类）
    for i, entry in ipairs(list) do
      if lname and not tonumber(entry) then
        local low = string.lower(entry)
        if string.find(lname, low, 1, true) then return i end
      end
    end

    return nil
  end

  -- 把 slots 里记录的 aura 显示到分离容器（按名单顺序，缺失的不占位）
  -- kind == "HARMFUL" 处理 debuff 重点区，否则处理 buff 重点区
  function pfUI.buff:RefreshSepBuffs(container, kind)
    if not container then return end
    kind = kind or "HELPFUL"
    local isharm = kind == "HARMFUL"
    container.slots = container.slots or {}

    local enabled = C and C.buffs and ((isharm and C.buffs.separatedebuffs == "1") or (not isharm and C.buffs.separatebuffs == "1"))
    -- 监控条独立字号 sep_fontsize（-1=跟随主 Buff 字号，存量行为）
    local fs = 12
    if enabled then
      fs = C.buffs.fontsize == "-1" and C.global.font_size or C.buffs.fontsize
      if C.buffs.sep_fontsize and C.buffs.sep_fontsize ~= "-1" then fs = tonumber(C.buffs.sep_fontsize) end
    end

    -- WA 式动态：名单不限长，遍历名单序号而非按钮池；超出初始池的按钮按需懒创建
    --（新高水位才建 frame，一次性成本）；名单缩短后多余的懒建按钮隐藏待复用
    local list = pfUI.buff:GetSepList(kind)
    local total = getn(list)
    for i = 1, total do
      local btn = container.buttons[i]
      if not btn then
        btn = CreateBuffButton(i, kind, nil, isharm and 2 or 1)
        pfUI.buff:UpdateConfigBuffButton(btn)
        container.buttons[i] = btn
      end
      local slot = enabled and container.slots[i] or nil

      if slot and slot.bid and slot.bid >= 0 and GetPlayerBuffTexture(slot.bid) then
        btn.bid = slot.bid
        btn.id = slot.id
        btn.mode = kind
        btn.texture:SetTexture(GetPlayerBuffTexture(slot.bid))
        if isharm then
          btn.backdrop:SetBackdropBorderColor(1, .22, .12, 1)
        else
          btn.backdrop:SetBackdropBorderColor(1, .78, .1, 1)
        end
        btn:Show()
      else
        btn.bid = nil
        btn.mode = nil
        btn:SetAlpha(1)
        btn:Hide()
      end
    end
    for i = total + 1, getn(container.buttons) do
      local btn = container.buttons[i]
      if btn and btn:IsShown() then
        btn.bid = nil
        btn.mode = nil
        btn:SetAlpha(1)
        btn:Hide()
      end
    end

    if enabled then
      local rows = isharm and C.buffs.sepdebuffrowsize or C.buffs.sepbuffrowsize
      local bsize = isharm and C.buffs.sepdebuffsize or C.buffs.sepbuffsize
      -- 按钮字体比普通 buff 大一号，行高按 fs+1 计算才不会挤在一起
      local r, c = pfUI.buff:RelayoutContainer(container, tonumber(rows), fs + 1, tonumber(bsize), C.buffs.sep_textinside)
      -- 容器尺寸贴合实际命中数量；一个都没命中时保留一格占位，保证框体仍可拖动
      if (r or 0) == 0 or (c or 0) == 0 then
        container:SetWidth(container.step or bsize)
        container:SetHeight(container.rowheight or bsize)
      else
        container:SetWidth(c * (container.step or 0))
        container:SetHeight(r * (container.rowheight or 0))
      end
    else
      container:SetWidth(0)
      container:SetHeight(0)
    end
  end

  -- Alt+左键：把当前 buff/debuff 加入 / 移出分离名单（按名称记录，自动开启功能）
  function pfUI.buff:ToggleSepList(buff)
    if not C or not C.buffs then return end
    local name = pfUI.buff:GetBuffName(buff)
    if not name or name == "" then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 无法读取该光环的名称，未能加入分离名单")
      return
    end

    local isharm = (buff and buff.btype) == "HARMFUL"
    local key = isharm and "sepdebufflist" or "separatelist"
    local onkey = isharm and "separatedebuffs" or "separatebuffs"
    local tag = isharm and "分离Debuff" or "分离Buff"

    C.buffs[key] = C.buffs[key] or ""
    local newlist, removed = "", false
    for v in string.gmatch(C.buffs[key], "[^#;]+") do
      v = string.gsub(v, "^%s*(.-)%s*$", "%1")
      if v ~= "" then
        if string.lower(v) == string.lower(name) then
          removed = true
        else
          newlist = newlist .. "#" .. v
        end
      end
    end

    if removed then
      C.buffs[key] = newlist
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 「" .. name .. "」已从" .. tag .. "名单移除")
    else
      C.buffs[key] = (newlist ~= "" and newlist .. "#" or "") .. name
      if C.buffs[onkey] ~= "1" then
        C.buffs[onkey] = "1"
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 「" .. name .. "」已加入" .. tag .. "名单，并已自动开启监控显示")
        pfUI.buff:UpdateConfig()
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 「" .. name .. "」已加入" .. tag .. "名单")
      end
    end

    if pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end
  end

  -- ==========================================================================
  -- 名单分享（导出 / 导入）
  -- 纯文本分享码，便于在聊天、论坛、好友之间传递，只含名单不含其它配置：
  --   单名单：pfSEP1:B:名称1#名称2
  --   四合一：pfSEP1
  --           B:名称1#名称2
  --           D:名称3
  --           TB:名称4
  --           TD:名称5
  -- 标签：B=玩家Buff  D=玩家Debuff  TB=目标Buff  TD=目标Debuff
  -- ==========================================================================
  pfUI.buff.sepshare = {
    { tag = "B",  list = "separatelist",        on = "separatebuffs" },
    { tag = "D",  list = "sepdebufflist",       on = "separatedebuffs" },
    { tag = "TB", list = "septargetbufflist",   on = "separatetargetbuffs" },
    { tag = "TD", list = "septargetdebufflist", on = "separatetargetdebuffs" },
  }

  -- 导出：tag = "B"/"D"/"TB"/"TD" 单名单，"ALL" = 四套一起
  function pfUI.buff:ExportSepShare(tag)
    if tag == "ALL" then
      local out = "pfSEP1"
      for _, e in ipairs(pfUI.buff.sepshare) do
        -- 只导出非空名单：避免用「只有 B 名单」的分享码把对方的 D/TB/TD 清空
        if (C.buffs[e.list] or "") ~= "" then
          out = out .. "\n" .. e.tag .. ":" .. C.buffs[e.list]
        end
      end
      return out
    end
    for _, e in ipairs(pfUI.buff.sepshare) do
      if e.tag == tag then
        return "pfSEP1:" .. tag .. ":" .. (C.buffs[e.list] or "")
      end
    end
    return ""
  end

  -- 导入：兼容四合一 / 单名单 / 纯名单（无标签时落到 defaultTag）三种写法
  function pfUI.buff:ImportSepShare(str, defaultTag)
    -- 必须以分享码标识开头/包含标识，避免把随手粘贴的文字当成名单写进配置
    if not string.find(str or "", "pfSEP1", 1, true) then
      return false, "分享码格式不对（应以 pfSEP1 开头）"
    end

    local body = string.gsub(str or "", "pfSEP1", "")
    local applied = 0

    for line in string.gmatch(body, "[^\r\n]+") do
      line = string.gsub(line, "^%s*(.-)%s*$", "%1")
      line = string.gsub(line, "^:+", "")
      if line ~= "" then
        local tag, payload = string.match(line, "^(%a+):(.*)$")
        if tag then
          tag = string.upper(tag)
        else
          tag, payload = defaultTag, line
        end
        payload = string.gsub(payload or "", "^%s*(.-)%s*$", "%1")
        for _, e in ipairs(pfUI.buff.sepshare) do
          if e.tag == tag then
            C.buffs[e.list] = payload
            C.buffs[e.on] = (payload ~= "" and "1" or "0")
            applied = applied + 1
          end
        end
      end
    end

    if applied == 0 then
      return false, "未识别到可导入的名单内容（分享码应以 pfSEP1 开头）"
    end

    pfUI.buff:UpdateConfig()
    if pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end
    return true, "已导入 " .. applied .. " 组名单"
  end

  -- /pfsep    : 分离 Buff 名单的命令行管理
  -- /pfsepdeb : 分离 Debuff 名单的命令行管理
  -- 两者共用同一套逻辑，仅操作的名单不同
  function pfUI.buff:HandleSepCmd(msg, isharm)
    local key = isharm and "sepdebufflist" or "separatelist"
    local onkey = isharm and "separatedebuffs" or "separatebuffs"
    local tag = isharm and "分离Debuff" or "分离Buff"
    local akey = isharm and "HARMFUL" or "HELPFUL"
    local slots = isharm and 16 or 32

    msg = msg or ""
    local trimmed = string.gsub(msg, "^%s*(.-)%s*$", "%1")

    if trimmed == "clear" then
      C.buffs[key] = ""
      C.buffs[onkey] = "0"
      if pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 已清空" .. tag .. "名单并关闭监控显示")
      return
    end

    -- 列出当前所有 buff/debuff 的名称，方便确认名称读取是否正常 / 直接复制名字
    if trimmed == "names" then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 名称读取方式 = " .. (GetPlayerBuffName and "GetPlayerBuffName" or "tooltip 扫描"))
      for i = 1, slots do
        local bid = GetPlayerBuff(PLAYER_BUFF_START_ID + i, akey)
        if bid and bid >= 0 then
          local n = pfUI.buff:GetBuffName({ bid = bid })
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: " .. i .. " = " .. (n or "(读取失败)"))
        end
      end
      return
    end

    -- 名单分享：share = 当前名单，shareall = 四套名单一起
    if trimmed == "share" then
      local sharetag = isharm and "D" or "B"
      pfUI.api.CreateShareListDialog("pfSepShare", tag .. " · " .. T["Share List"],
        function() return pfUI.buff:ExportSepShare(sharetag) end,
        function(str) return pfUI.buff:ImportSepShare(str, sharetag) end)
      return
    end

    if trimmed == "shareall" then
      pfUI.api.CreateShareListDialog("pfSepShare", T["Share List"],
        function() return pfUI.buff:ExportSepShare("ALL") end,
        function(str) return pfUI.buff:ImportSepShare(str, "B") end)
      return
    end

    if trimmed ~= "" then
      C.buffs[key] = (C.buffs[key] ~= "" and C.buffs[key] .. "#" or "") .. trimmed
      if C.buffs[onkey] ~= "1" then
        C.buffs[onkey] = "1"
        pfUI.buff:UpdateConfig()
      end
      if pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 「" .. trimmed .. "」已加入" .. tag .. "名单")
      return
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: " .. tag .. "显示 = " .. (C.buffs[onkey] == "1" and "开" or "关"))
    local list = pfUI.buff:GetSepList(akey)
    if getn(list) == 0 then
      local cmd = isharm and "/pfsepdeb" or "/pfsep"
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: " .. tag .. "名单为空（Alt+左键 点图标添加，或 " .. cmd .. " 名称；" .. cmd .. " share 分享名单，shareall 分享全部四套）")
    else
      for i, v in ipairs(list) do
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: " .. tag .. " " .. i .. " = " .. v)
      end
    end
  end

  SLASH_PFSEP1 = "/pfsep"
  SlashCmdList["PFSEP"] = function(msg)
    pfUI.buff:HandleSepCmd(msg, false)
  end

  SLASH_PFSEPDEB1 = "/pfsepdeb"
  SlashCmdList["PFSEPDEB"] = function(msg)
    pfUI.buff:HandleSepCmd(msg, true)
  end

  -- ==========================================================================
  -- 目标 Buff / Debuff 监控区（Target Highlight Icons）
  -- 纯复制监控模式：命中名单的目标光环在监控区重点显示，目标框原行图标始终保留。
  -- 数据源是目标身上的光环（UnitBuff/UnitDebuff("target")）。
  -- 1.12 没有 UNIT_AURA 事件，靠 pfUI.buff OnUpdate 0.25s 节流轮询 + 切目标立即刷新。
  -- 默认锚在目标框上方（目标 debuff 条同一区域），可分别拖动；名单支持
  -- Alt+左键点目标框上的 buff/debuff 图标快捷增删，也支持 /pftsep、/pftsepdeb 命令。
  -- ==========================================================================

  -- 48 = aura 数组总槽数（名单序号 >48 的条目永远进不了监控区，48 已是数据天花板；
  -- 目标 buff 数据最多 32 个，33-48 号槽只有溢出/隐藏 debuff 用得到）
  pfUI.buff.TSEPBUFF_COUNT = 48
  pfUI.buff.TSEPDEBUFF_COUNT = 48
  pfUI.buff.targetnamecache = {}

  -- 读取目标光环名称：debuff 优先 libdebuff（SuperWoW，直接返回名），
  -- 其余走 libtipscan 扫描器，最后用隐藏 tooltip 兜底（与玩家版 scantip 同一实例）
  function pfUI.buff:GetTargetAuraName(unit, i, kind)
    -- 读取顺序与原生 UnitBuff/UnitDebuff 索引同源（scanner/tooltip 优先）；
    -- libdebuff 按独立槽位表索引，与原生顺序不保证一致，只作兜底
    if libtipscan then
      pfUI.buff.scanunit = pfUI.buff.scanunit or libtipscan:GetScanner("septarget")
      if pfUI.buff.scanunit then
        local ok, n = pcall(function()
          if kind == "HARMFUL" then
            pfUI.buff.scanunit:SetUnitDebuff(unit, i)
          else
            pfUI.buff.scanunit:SetUnitBuff(unit, i)
          end
          return pfUI.buff.scanunit:Line(1)
        end)
        if ok and n and n ~= "" then return n end
      end
    end

    if kind == "HARMFUL" and libdebuff then
      local ok, name = pcall(function()
        local n = libdebuff:UnitDebuff(unit, i)
        return n
      end)
      if ok and name and name ~= "" then return name end
    end

    if not pfUI.buff.scantip then
      pfUI.buff.scantip = CreateFrame("GameTooltip", "pfSepBuffScanTip", UIParent, "GameTooltipTemplate")
      pfUI.buff.scantip:Hide()
    end

    local name = nil
    pcall(function()
      local tip = pfUI.buff.scantip
      tip:SetOwner(UIParent, "ANCHOR_NONE")
      tip:ClearLines()
      if kind == "HARMFUL" then
        tip:SetUnitDebuff(unit, i)
      else
        tip:SetUnitBuff(unit, i)
      end
      local label = getglobal("pfSepBuffScanTipTextLeft1")
      if label then
        local txt = label:GetText()
        if txt and txt ~= "" then name = txt end
      end
      tip:Hide()
    end)
    return name
  end

  -- 名单解析缓存：配置串不变时直接复用拆好的条目（原先每光环每轮重新 gmatch 拆串）
  function pfUI.buff:GetTargetSepEntries(isharm, raw)
    pfUI.buff.tseplistcache = pfUI.buff.tseplistcache or {}
    local key = isharm and "d" or "b"
    local cache = pfUI.buff.tseplistcache[key]
    if not cache or cache.raw ~= raw then
      local entries = {}
      for v in string.gmatch(raw, "[^#;]+") do
        v = string.gsub(v, "^%s*(.-)%s*$", "%1")
        if v ~= "" then
          entries[getn(entries)+1] = { v = v, lv = string.lower(v), num = tonumber(v) }
        end
      end
      cache = { raw = raw, entries = entries }
      pfUI.buff.tseplistcache[key] = cache
    end
    return cache.entries
  end

  -- 判断目标光环是否命中目标分离名单，返回名单序号（固定显示顺序）
  -- 支持名称（精确/子串）与纯数字 spellID（需 SuperWoW 扩展 UnitBuff/UnitDebuff）
  function pfUI.buff:TargetSepIndex(name, sid, kind)
    if not C or not C.buffs then return nil end
    local isharm = kind == "HARMFUL"
    if isharm then
      if C.buffs.separatetargetdebuffs ~= "1" then return nil end
    else
      if C.buffs.separatetargetbuffs ~= "1" then return nil end
    end

    local raw = isharm and C.buffs.septargetdebufflist or C.buffs.septargetbufflist
    if raw == "" then return nil end
    -- 名称和 spellID 都拿不到时直接跳过，不空跑两遍匹配
    if not name and not sid then return nil end
    local lname = name and string.lower(name) or nil
    local entries = pfUI.buff:GetTargetSepEntries(isharm, raw)

    -- 第一遍：精确匹配（spellID 或完整名称）
    for idx = 1, getn(entries) do
      local e = entries[idx]
      if sid and e.num and e.num == sid then return idx end
      if lname and e.lv == lname then return idx end
    end

    -- 第二遍：子串匹配
    for idx = 1, getn(entries) do
      local e = entries[idx]
      if lname and not e.num and string.find(lname, e.lv, 1, true) then return idx end
    end

    return nil
  end

  -- 名单增删核心（按名称，自动开启功能）；unit/i 可省略（分离区按钮自带 tname 时）
  function pfUI.buff:ToggleTargetSepName(name, kind)
    if not C or not C.buffs then return end
    local isharm = kind == "HARMFUL"
    local key = isharm and "septargetdebufflist" or "septargetbufflist"
    local onkey = isharm and "separatetargetdebuffs" or "separatetargetbuffs"
    local tag = isharm and "目标Debuff监控" or "目标Buff监控"

    C.buffs[key] = C.buffs[key] or ""
    local newlist, removed = "", false
    for v in string.gmatch(C.buffs[key], "[^#;]+") do
      v = string.gsub(v, "^%s*(.-)%s*$", "%1")
      if v ~= "" then
        if string.lower(v) == string.lower(name) then
          removed = true
        else
          newlist = newlist .. "#" .. v
        end
      end
    end

    if removed then
      C.buffs[key] = newlist
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 「" .. name .. "」已从" .. tag .. "名单移除")
    else
      C.buffs[key] = (newlist ~= "" and newlist .. "#" or "") .. name
      if C.buffs[onkey] ~= "1" then
        C.buffs[onkey] = "1"
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 「" .. name .. "」已加入" .. tag .. "名单，并已自动开启显示")
        pfUI.buff:UpdateConfig()
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 「" .. name .. "」已加入" .. tag .. "名单")
      end
    end

    if pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end
  end

  -- 目标框图标 Alt+左键入口（unitframes.lua 调用）
  -- knownname：unitframes 收集光环时已解析好的名字（与显示图标同源，优先使用，避免索引错位取错名）
  function pfUI.buff:ToggleTargetSepList(unit, i, kind, knownname)
    local name = knownname
    if not name or name == "" then
      name = pfUI.buff:GetTargetAuraName(unit, i, kind)
    end
    if not name or name == "" then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 无法读取该目标光环的名称，未能加入名单")
      return
    end
    pfUI.buff:ToggleTargetSepName(name, kind)
  end

  -- 目标分离区命令：/pftsep、/pftsepdeb（add / names / clear / 空=状态）
  function pfUI.buff:HandleTargetSepCmd(msg, isharm)
    local key = isharm and "septargetdebufflist" or "septargetbufflist"
    local onkey = isharm and "separatetargetdebuffs" or "separatetargetbuffs"
    local tag = isharm and "目标Debuff监控" or "目标Buff监控"
    local kind = isharm and "HARMFUL" or "HELPFUL"

    msg = msg or ""
    local trimmed = string.gsub(msg, "^%s*(.-)%s*$", "%1")

    if trimmed == "clear" then
      C.buffs[key] = ""
      C.buffs[onkey] = "0"
      pfUI.buff:UpdateConfig()
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 已清空" .. tag .. "名单并关闭显示")
      return
    end

    -- 名单分享：目标 Buff / Debuff 监控名单
    if trimmed == "share" then
      local sharetag = isharm and "TD" or "TB"
      pfUI.api.CreateShareListDialog("pfSepShare", tag .. " · " .. T["Share List"],
        function() return pfUI.buff:ExportSepShare(sharetag) end,
        function(str) return pfUI.buff:ImportSepShare(str, sharetag) end)
      return
    end

    if trimmed == "shareall" then
      pfUI.api.CreateShareListDialog("pfSepShare", T["Share List"],
        function() return pfUI.buff:ExportSepShare("ALL") end,
        function(str) return pfUI.buff:ImportSepShare(str, "B") end)
      return
    end

    -- 列出当前目标身上的光环名称
    if trimmed == "names" then
      if not UnitExists("target") then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 当前没有目标")
        return
      end

      -- ① 原始 aura 槽位直读（权威视图）：槽位 / 分类 / spellId / 名称 / 是否隐藏光环。
      --    GetUnitField(guid,"aura") 是客户端**真实**光环数组，隐藏光环（SuperWoW/Nampower
      --    的 IsAuraHidden=1）也在里面；显示层会过滤它们，这里能看出"究竟过滤掉了什么"。
      if libdebuff and GetUnitField and GetUnitGUID then
        local dbgguid = GetUnitGUID("target")
        local dbgauras = dbgguid and GetUnitField(dbgguid, "aura")
        if dbgauras then
          for di = 1, 48 do
            local dsid = dbgauras[di]
            if type(dsid) == "number" and dsid > 0 then
              local dname = (GetSpellRecField and GetSpellRecField(dsid, "name")) or "?"
              local dflag = ""
              if IsAuraHidden then
                local dh = IsAuraHidden(dsid)
                if dh == 1 or dh == true or dh == "1" then dflag = " |cffff5555[隐藏]|r" end
              end
              DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 槽 " .. di .. " (" .. (di <= 32 and "buff" or "debuff") .. ") = " .. dsid .. " " .. dname .. dflag)
            end
          end
        end
      end

      -- ② 显示层实际取到的 buff（GetBuffSlot 视图，已过滤隐藏光环与溢出 debuff）
      local dg_auras, dg_apps
      if not isharm and libdebuff and libdebuff.GetAuraSnapshot then
        dg_auras, dg_apps = libdebuff:GetAuraSnapshot("target")
      end
      for i = 1, 32 do
        local tex, n
        if not isharm and libdebuff and libdebuff.GetBuffSlot then
          -- 原生 UnitBuff 读不到 target，用 Nampower buff 槽；槽位有空洞不能 break
          n, _, tex = libdebuff:GetBuffSlot("target", i, dg_auras, dg_apps)
        else
          tex = isharm and UnitDebuff("target", i) or UnitBuff("target", i)
          if not tex then break end
        end
        if tex then
          if not n then n = pfUI.buff:GetTargetAuraName("target", i, kind) end
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 显示槽 " .. i .. " = " .. (n or "(读取失败)"))
        end
      end

      -- ③ 行内实际渲染：目标框 buff 行走的正是 DetectBuff，逐原始槽位打印它的返回。
      --    非玩家单位的口径必须是"该槽位取不到 ⇒ 空"；一旦出现"空槽却渲染出别的 buff"，
      --    就是又掉进了 tooltip 猜测路径（原始槽位 vs 原生紧凑索引错位 → 重复图标）。
      if pfUI.uf and pfUI.uf.DetectBuff and UnitExists("target") then
        local dtex, dstacks, dname
        -- 与目标框 buff 行同一条路径：快照在循环外取一次（生产代码也是这么传的）
        local dg2_auras, dg2_apps
        if libdebuff and libdebuff.GetAuraSnapshot then
          dg2_auras, dg2_apps = libdebuff:GetAuraSnapshot("target")
        end
        for i = 1, 32 do
          dtex, dstacks, dname = pfUI.uf:DetectBuff("target", i, dg2_auras, dg2_apps)
          if dtex then
            -- 顺带打出"原生紧凑索引"：悬浮提示就是拿它去 GameTooltip:SetUnitBuff 取完整详情的
            local didx = libdebuff and libdebuff.GetBuffDisplayIndex and libdebuff:GetBuffDisplayIndex("target", i, dg2_auras)
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 行内槽 " .. i .. " = " .. (dname or "?") .. " ×" .. (dstacks or 1) .. "（原生索引 " .. (didx or "无") .. "）")
          end
        end
      end
      return
    end

    if trimmed ~= "" then
      pfUI.buff:ToggleTargetSepName(trimmed, kind)
      return
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: " .. tag .. "显示 = " .. (C.buffs[onkey] == "1" and "开" or "关"))
    local raw = C.buffs[key] or ""
    local idx = 0
    for v in string.gmatch(raw, "[^#;]+") do
      v = string.gsub(v, "^%s*(.-)%s*$", "%1")
      if v ~= "" then
        idx = idx + 1
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: " .. tag .. " " .. idx .. " = " .. v)
      end
    end
    if idx == 0 then
      local cmd = isharm and "/pftsepdeb" or "/pftsep"
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: " .. tag .. "名单为空（Alt+左键点目标框图标添加，或 " .. cmd .. " 名称；" .. cmd .. " share 分享名单）")
    end
  end

  SLASH_PFTSEP1 = "/pftsep"
  SlashCmdList["PFTSEP"] = function(msg)
    pfUI.buff:HandleTargetSepCmd(msg, false)
  end

  SLASH_PFTSEPDEB1 = "/pftsepdeb"
  SlashCmdList["PFTSEPDEB"] = function(msg)
    pfUI.buff:HandleTargetSepCmd(msg, true)
  end

  -- 扫描目标光环并填充分离区（kind: HELPFUL / HARMFUL）
  function pfUI.buff:RefreshTargetSepBuffs(kind)
    local isharm = kind == "HARMFUL"
    local container = isharm and pfUI.buff.septargetdebuffs or pfUI.buff.septargetbuffs
    if not container then return end
    local enabled = C and C.buffs and ((isharm and C.buffs.separatetargetdebuffs == "1") or (not isharm and C.buffs.separatetargetbuffs == "1"))
    -- WA 式动态：名单不限长，槽位仍按名单序号记录（显示顺序稳定），按钮由填充端按需懒创建
    -- 每轮重建槽位（槽位按名单序号固定；不清空会让过期/移出的光环残留显示）
    container.slots = {}

    if enabled and UnitExists("target") then
      -- ⚡ 快照：48 槽循环只取一份 aura 数组（不给快照就是每槽一份 = 48 倍放大）
      -- buff 路径槽 33-48 由 GetBuffSlot 的 slot>32 守卫返回 nil，安全；
      -- debuff 路径 libdebuff:UnitDebuff 枚举独立槽位表，33-48 覆盖溢出/隐藏区条目
      local sep_auras, sep_apps
      if not isharm and libdebuff and libdebuff.GetAuraSnapshot then
        sep_auras, sep_apps = libdebuff:GetAuraSnapshot("target")
      end
      for i = 1, 48 do
        local tex, stacks, dtype, sid, name, timeleft
        if isharm and libdebuff then
          -- 单源取数：libdebuff(Nampower) 用独立槽位表枚举，与原生 UnitDebuff 顺序不保证一致，
          -- 名称/纹理/层数/剩余时间/spellID 必须全部取自同一来源，否则会"名字配错图标"→ 错误命中名单
          local dn, rank, dtex, dstacks, ddtype, ddur, dtl, dcaster, dsid = libdebuff:UnitDebuff("target", i)
          if not dn or dn == "" or not dtex then break end
          name = dn
          tex = dtex
          stacks = dstacks
          sid = dsid
          if type(dtl) == "number" then timeleft = dtl end
        else
          -- 1.12 原生 UnitBuff 只对 "player" 生效，对 "target" 恒返回 nil（本机实测
          -- UB 1..10 全 nil）→ 目标 buff 必须直接读 Nampower 的 GetUnitField(guid,"aura")
          -- 槽 1-32，与姓名板/libdebuff 单一数据源。该数组是固定槽位、带空洞
          --（原生索引是紧凑的），取不到只能跳过本槽、不能 break。
          if not isharm and libdebuff and libdebuff.GetBuffSlot then
            name, _, tex, stacks, dtype, _, timeleft, _, sid = libdebuff:GetBuffSlot("target", i, sep_auras, sep_apps)
          else
            -- SuperWoW 扩展：第 4 返回为 spellID；无 SuperWoW 时为 nil（按名称匹配）
            if isharm then
              tex, stacks, dtype, sid = UnitDebuff("target", i)
            else
              tex, stacks, dtype, sid = UnitBuff("target", i)
            end
            if not tex then break end
          end

          if tex then
            -- 溢出 debuff 识别：目标（NPC）debuff 超过 16 个时，第 17+ 个 debuff 会
            -- 出现在 buff 槽位（SuperWoW/Nampower 机制），原生 UnitBuff 把它们当
            -- buff 返回。跳过以免显示成 buff；不中断扫描，防溢出槽位插在真实 buff 之间
            if libdebuff and libdebuff.IsBuffSlotDebuff and libdebuff:IsBuffSlotDebuff("target", i) then
              tex, stacks, sid, name, timeleft = nil, nil, nil, nil, nil
            end

            -- 名称解析：Nampower 路径已直接给出名称；其余按 texture 缓存扫 tooltip
            if tex and not name then
              local ckey = kind .. "|" .. tex
              name = pfUI.buff.targetnamecache[ckey]
              if not name then
                name = pfUI.buff:GetTargetAuraName("target", i, kind)
                if name then pfUI.buff.targetnamecache[ckey] = name end
              end
            end
          end
        end

        local idx = pfUI.buff:TargetSepIndex(name, tonumber(sid), kind)
        if idx and not container.slots[idx] then
          container.slots[idx] = { tex = tex, stacks = stacks, aid = i, name = name, timeleft = timeleft }
        end
      end
    end

    -- 填充按钮（WA 式动态：遍历名单序号而非按钮池；超出初始池的按钮懒创建，
    -- 新高水位才建 frame，一次性成本；名单缩短后多余的懒建按钮隐藏待复用）
    local raw = isharm and C.buffs.septargetdebufflist or C.buffs.septargetbufflist
    local total = raw and raw ~= "" and getn(pfUI.buff:GetTargetSepEntries(isharm, raw)) or 0
    for bi = 1, total do
      local btn = pfUI.buff.EnsureTargetSepButton(container, bi, kind)
      local slot = enabled and container.slots[bi] or nil
      if slot and slot.tex then
        btn.aid = slot.aid
        btn.tname = slot.name
        btn.texture:SetTexture(slot.tex)
        btn.stacks:SetText((slot.stacks or 0) > 1 and slot.stacks or "")
        if slot.timeleft and slot.timeleft > 0 and GetColoredTimeString then
          btn.timer:SetText(GetColoredTimeString(slot.timeleft))
        else
          btn.timer:SetText("")
        end
        btn:Show()
      else
        btn.aid = nil
        btn.tname = nil
        btn.timer:SetText("")
        btn.stacks:SetText("")
        btn:Hide()
      end
    end
    for bi = total + 1, getn(container.buttons) do
      local btn = container.buttons[bi]
      if btn and btn:IsShown() then
        btn.aid = nil
        btn.tname = nil
        btn.timer:SetText("")
        btn.stacks:SetText("")
        btn:Hide()
      end
    end

    -- 尺寸随内容伸缩（无命中保留一格占位，保证框体可拖动）
    if enabled then
      local rows = isharm and C.buffs.septargetdebuffrowsize or C.buffs.septargetbuffrowsize
      local bsize = isharm and C.buffs.septargetdebuffsize or C.buffs.septargetbuffsize
      local fs = C.buffs.fontsize == "-1" and C.global.font_size or C.buffs.fontsize
      -- 监控条独立字号 sep_fontsize（-1=跟随主 Buff 字号，存量行为）
      if C.buffs.sep_fontsize and C.buffs.sep_fontsize ~= "-1" then fs = tonumber(C.buffs.sep_fontsize) end
      local r, c = pfUI.buff:RelayoutContainer(container, tonumber(rows), fs + 1, tonumber(bsize), C.buffs.sep_textinside)
      if (r or 0) == 0 or (c or 0) == 0 then
        container:SetWidth(container.step or tonumber(bsize))
        container:SetHeight(container.rowheight or tonumber(bsize))
      else
        container:SetWidth(c * (container.step or 0))
        container:SetHeight(r * (container.rowheight or 0))
      end
    else
      container:SetWidth(0)
      container:SetHeight(0)
    end
  end

  -- 目标分离区默认锚点：pfUI.uf.target 可能晚于本模块创建（unitframes 模块），
  -- 就绪后在这里补一次默认定位（用户拖动过的位置保存在 C.position，不会被覆盖）
  function pfUI.buff:AnchorTargetSep(container, isharm)
    if not container or container.targetanchored then return end
    if not (pfUI.uf and pfUI.uf.target) then return end
    -- 用户拖过（已保存位置）就不再动默认锚点
    if C.position and C.position[container:GetName()] then
      container.targetanchored = true
      return
    end
    -- 目标 debuff 条开启时上移让位，避免和 buffwatch 的条重叠
    local topoff = (C.buffbar and C.buffbar.tdebuff and C.buffbar.tdebuff.enable == "1") and 30 or 4
    local spacing = tonumber(C.buffs.spacing) or 5
    container:ClearAllPoints()
    if isharm then
      -- debuff 区贴目标框上方（目标 debuff 条同一区域）
      container:SetPoint("BOTTOMRIGHT", pfUI.uf.target, "TOPRIGHT", 0, topoff)
    else
      if C.buffs.separatetargetdebuffs == "1" then
        container:SetPoint("BOTTOMRIGHT", pfUI.buff.septargetdebuffs, "TOPRIGHT", 0, spacing)
      else
        container:SetPoint("BOTTOMRIGHT", pfUI.uf.target, "TOPRIGHT", 0, topoff)
      end
    end
    UpdateMovable(container, true)   -- 以当前位置为初始 posdata 重新捕获
    container.targetanchored = true
  end

  -- 玩家分离区默认锚点：pfUI.uf.player 可能晚于本模块创建（unitframes 模块），
  -- 就绪后在这里补一次默认定位（用户拖动过的位置保存在 C.position，不会被覆盖）
  function pfUI.buff:AnchorPlayerSep(container, isharm)
    if not container or container.playeranchored then return end
    if not (pfUI.uf and pfUI.uf.player) then return end
    -- 用户拖过（已保存位置）就不再动默认锚点
    if C.position and C.position[container:GetName()] then
      container.playeranchored = true
      return
    end
    local spacing = tonumber(C.buffs.spacing) or 5
    container:ClearAllPoints()
    if isharm then
      -- debuff 区贴玩家头像正上方
      container:SetPoint("BOTTOMRIGHT", pfUI.uf.player, "TOPRIGHT", 0, 4)
    else
      -- buff 区叠在分离 debuff 区上方；debuff 分离未开启时退回头像正上方
      if C.buffs.separatedebuffs == "1" then
        -- debuff 区还没锚好（playeranchored 未置位）就等下一拍，避免锚到屏幕中央的中间态
        if not (pfUI.buff.sepdebuffs and pfUI.buff.sepdebuffs.playeranchored) then return end
        container:SetPoint("BOTTOMRIGHT", pfUI.buff.sepdebuffs, "TOPRIGHT", 0, spacing)
      else
        container:SetPoint("BOTTOMRIGHT", pfUI.uf.player, "TOPRIGHT", 0, 4)
      end
    end
    UpdateMovable(container, true)   -- 以当前位置为初始 posdata 重新捕获
    container.playeranchored = true
  end

  -- unitframes 顺风车入口：目标框 aura 组件刷新（事件驱动）时同步分离区，
  -- 取代旧的自建 0.25s 全量轮询——光环没变化时这里一次都不会跑
  function pfUI.buff:OnTargetAuraRefresh()
    if not (C and C.buffs and (C.buffs.separatetargetbuffs == "1" or C.buffs.separatetargetdebuffs == "1")) then return end
    pfUI.buff:RefreshTargetSepBuffs("HELPFUL")
    pfUI.buff:RefreshTargetSepBuffs("HARMFUL")
    pfUI.buff:AnchorTargetSep(pfUI.buff.septargetbuffs, false)
    pfUI.buff:AnchorTargetSep(pfUI.buff.septargetdebuffs, true)
  end

  -- 目标分离区按钮（独立于玩家版：内容来自 UnitBuff/UnitDebuff("target")）
  local function CreateTargetSepButton(container, i, kind)
    local isharm = kind == "HARMFUL"
    local prefix = isharm and "pfSepTargetDebuff" or "pfSepTargetBuff"
    local btn = CreateFrame("Button", prefix .. "Icon" .. i, container)
    btn.texture = btn:CreateTexture(prefix .. "Texture" .. i, "BACKGROUND")
    btn.texture:SetTexCoord(.07,.93,.07,.93)
    btn.texture:SetAllPoints(btn)

    btn.timer = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.timer:SetTextColor(1,1,1,1)
    btn.timer:SetJustifyH("CENTER")
    btn.timer:SetJustifyV("CENTER")

    btn.stacks = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.stacks:SetTextColor(1,1,1,1)
    btn.stacks:SetJustifyH("RIGHT")
    btn.stacks:SetJustifyV("BOTTOM")
    btn.stacks:SetAllPoints(btn)

    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.kind = kind
    btn.aid = nil
    btn.tname = nil

    CreateBackdrop(btn)
    CreateBackdropShadow(btn)
    if isharm then
      btn.backdrop:SetBackdropBorderColor(1, .22, .12, 1)
    else
      btn.backdrop:SetBackdropBorderColor(1, .78, .1, 1)
    end

    btn:SetScript("OnEnter", function()
      if not btn.aid or not UnitExists("target") then return end
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOMRIGHT")
      -- 提示要完整详情：原生 GameTooltip:SetUnitBuff 对 target **能出完整描述**，但它要的是
      -- **原生紧凑索引**（隐藏光环不枚举给 Lua，可见光环重编号 1..N）；btn.aid 是 GetUnitField
      -- 的**原始槽位** → 先换算成紧凑索引再喂原生，否则描述会配到**另一个** buff 上。
      if btn.kind ~= "HARMFUL" and libdebuff and libdebuff.GetBuffSlot then
        -- ⚡ 一次快照同时喂"紧凑索引换算"和"合成提示兜底"，避免两次取数
        local hov_auras, hov_apps
        if libdebuff.GetAuraSnapshot then
          hov_auras, hov_apps = libdebuff:GetAuraSnapshot("target")
        end
        local cidx = libdebuff.GetBuffDisplayIndex and libdebuff:GetBuffDisplayIndex("target", btn.aid, hov_auras)
        if cidx then GameTooltip:SetUnitBuff("target", cidx) end
        -- 原生已给出内容 → 完成；否则退回合成提示（空槽 / 隐藏光环才走到这里）
        if cidx and not (GameTooltip.NumLines and GameTooltip:NumLines() == 0) then return end

        local bname, brank, btex, bstacks, bdtype, bdur, btl = libdebuff:GetBuffSlot("target", btn.aid, hov_auras, hov_apps)
        if bname then
          local rankText = (brank and brank ~= "" and brank ~= 0) and (" (等级 " .. brank .. ")") or ""
          GameTooltip:AddLine(bname .. rankText, 1, 1, 1)
          if bstacks and bstacks > 1 then GameTooltip:AddLine("层数: " .. bstacks, .8, .8, .8) end
          if btl and btl > 0 then GameTooltip:AddLine("剩余: " .. math.floor(btl) .. " 秒", .8, .8, .8) end
          GameTooltip:Show()
        else
          -- 空槽 / 隐藏光环：不喂 SetUnitBuff（紧凑索引会解析成另一个 buff → 错提示）
          GameTooltip:Hide()
        end
        return
      end
      pcall(function()
        if btn.kind == "HARMFUL" then
          -- ⛔ btn.aid 是 libdebuff **地图索引**，原生 SetUnitDebuff 要的是**原生索引**——
          -- 空洞/隐藏/溢出时两者错位，直接喂会弹错内容或空提示（2026-09-19 排查）。
          -- 与上方 HELPFUL 分支对齐：先纹理校验对位，对得上走原生（完整描述），对不上合成。
          local handled = false
          if libdebuff and libdebuff.UnitDebuff then
            local dName, dRank, dTex, dStacks, _, dDur, dTl, dCaster =
              libdebuff:UnitDebuff("target", btn.aid)
            if dName and dTex then
              local nativeTex = btn.aid <= 16 and UnitDebuff("target", btn.aid) or nil
              if nativeTex and string.lower(nativeTex) == string.lower(dTex) then
                GameTooltip:SetUnitDebuff("target", btn.aid)
                handled = true
              elseif pfUI.uf and pfUI.uf.SynthDebuffTooltip then
                -- 合成兜底（unitframes 共享助手：自己的法术走法术书出完整描述）
                local dSpellId
                if libdebuff.GetDebuffSlotEntry then
                  local dEnt = libdebuff:GetDebuffSlotEntry("target", btn.aid)
                  if dEnt then dSpellId = dEnt.spellId end
                end
                handled = pfUI.uf.SynthDebuffTooltip(dName, dRank, dStacks, dDur, dTl, dCaster, dSpellId) and true or false
              end
            end
          end
          if not handled then
            -- 地图条目已消失（光环到期/刷新后未重排）：保留旧行为作最后兜底
            GameTooltip:SetUnitDebuff("target", btn.aid)
          end
        else
          GameTooltip:SetUnitBuff("target", btn.aid)
        end
      end)
    end)

    btn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)

    btn:SetScript("OnClick", function()
      -- Alt+左键：移出目标分离名单
      if IsAltKeyDown() then
        local name = btn.tname
        if not name and btn.aid and UnitExists("target") then
          name = pfUI.buff:GetTargetAuraName("target", btn.aid, btn.kind)
        end
        if name then pfUI.buff:ToggleTargetSepName(name, btn.kind) end
      end
    end)

    btn:Hide()
    return btn
  end

  -- 懒创建入口（WA 式动态监控用）：RefreshTargetSepBuffs 定义在本函数之前，
  -- 词法上捕获不到上面的 local —— 必须经方法表在运行期解引用（与 UpdateConfigTargetSepButton 同理）
  function pfUI.buff.EnsureTargetSepButton(container, bi, kind)
    local btn = container.buttons and container.buttons[bi]
    if not btn then
      btn = CreateTargetSepButton(container, bi, kind)
      pfUI.buff:UpdateConfigTargetSepButton(btn)
      container.buttons[bi] = btn
    end
    return btn
  end
  -- /pfhide : 诊断 + 清空。打印当前过滤状态与每个可见 buff 的真实 spellID，便于排查为何没隐藏
  SLASH_PFHIDE1 = "/pfhide"
  SlashCmdList["PFHIDE"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "clear" then
      C.buffs.filter = "none"
      C.buffs.whitelist = ""
      C.buffs.blacklist = ""
      if pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 已清空 buff 黑白名单并关闭过滤")
      return
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 过滤模式 = " .. (C.buffs.filter or "none"))
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 白名单 = " .. (C.buffs.whitelist ~= "" and C.buffs.whitelist or "(空)"))
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 黑名单 = " .. (C.buffs.blacklist ~= "" and C.buffs.blacklist or "(空)"))
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: ---- 当前可见 buff 的 spellID ----")
    if pfUI.buff.buffs and pfUI.buff.buffs.buttons then
      for i = 1, 32 do
        local b = pfUI.buff.buffs.buttons[i]
        if b and b:IsShown() and b.mode == b.btype then
          local sid = pfUI.buff:GetBuffId(b)
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: slot " .. i .. "  spellID = " .. (sid or "nil"))
        end
      end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 用 Shift+左键 点 buff 加入黑名单；/pfhide clear 清空")
  end

  pfUI.buff:RegisterEvent("PLAYER_AURAS_CHANGED")
  pfUI.buff:RegisterEvent("UNIT_INVENTORY_CHANGED")
  pfUI.buff:RegisterEvent("UNIT_MODEL_CHANGED")
  pfUI.buff:RegisterEvent("PLAYER_TARGET_CHANGED")
  pfUI.buff:SetScript("OnEvent", function()
    if C.buffs.weapons == "1" then
      local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()
      pfUI.buff.wepbuffs.count = (mh and 1 or 0) + (oh and 1 or 0)
    else
      pfUI.buff.wepbuffs.count = 0
    end

    -- 每轮刷新前清空分离槽记录（槽位按名单序号固定，保证显示顺序稳定）
    if pfUI.buff.sepbuffs then pfUI.buff.sepbuffs.slots = {} end
    if pfUI.buff.sepdebuffs then pfUI.buff.sepdebuffs.slots = {} end

    for i=1,32 do
      RefreshBuffButton(pfUI.buff.buffs.buttons[i])
    end

    for i=1,16 do
      RefreshBuffButton(pfUI.buff.debuffs.buttons[i])
    end

    if C.buffs.separateweapons == "1" then
      for i=1,2 do
        RefreshBuffButton(pfUI.buff.wepbuffs.buttons[i])
      end
    end

    -- 分离区（重点显示）：buff 在上，debuff 另起一行
    pfUI.buff:RefreshSepBuffs(pfUI.buff.sepbuffs, "HELPFUL")
    pfUI.buff:RefreshSepBuffs(pfUI.buff.sepdebuffs, "HARMFUL")

    -- 目标分离区：事件驱动立即刷一次（含 PLAYER_TARGET_CHANGED / 配置变更后的 OnEvent 调用）；
    -- 平时光环变化由 unitframes 目标框 aura 刷新顺风车（OnTargetAuraRefresh）负责
    if C.buffs.separatetargetbuffs == "1" or C.buffs.separatetargetdebuffs == "1" then
      pfUI.buff:RefreshTargetSepBuffs("HELPFUL")
      pfUI.buff:RefreshTargetSepBuffs("HARMFUL")
      pfUI.buff:AnchorTargetSep(pfUI.buff.septargetbuffs, false)
      pfUI.buff:AnchorTargetSep(pfUI.buff.septargetdebuffs, true)
    end

    -- 紧凑重排：隐藏的 buff 不留空格，可见 buff 依次前移
    local fs = C.buffs.fontsize == "-1" and C.global.font_size or C.buffs.fontsize
    pfUI.buff:RelayoutContainer(pfUI.buff.buffs, tonumber(C.buffs.buffrowsize), fs)
    pfUI.buff:RelayoutContainer(pfUI.buff.debuffs, tonumber(C.buffs.debuffrowsize), fs)
    if C.buffs.separateweapons == "1" then
      pfUI.buff:RelayoutContainer(pfUI.buff.wepbuffs, tonumber(C.buffs.wepbuffrowsize), fs)
    end
  end)

  -- PERF: Consolidated OnUpdate handler for all buff timers
  -- This replaces 50 individual OnUpdate handlers with a single one
  pfUI.buff:SetScript("OnUpdate", function()
    local now = GetTime()
    if not this.nextUpdate then this.nextUpdate = now + 0.1 end
    if this.nextUpdate > now then return end
    this.nextUpdate = now + 0.1

    -- 目标分离区：图标/增删同步已改为事件驱动（unitframes 目标框 aura 刷新顺风车 OnTargetAuraRefresh），
    -- 这里只做倒计时文本的轻量节流刷新（仅遍历当前显示的按钮，通常个位数）
    if (C.buffs.separatetargetbuffs == "1" or C.buffs.separatetargetdebuffs == "1")
       and libdebuff and pfUI.buff.septargetdebuffs and pfUI.buff.septargetdebuffs.buttons then
      if not this.nextSepTimer or this.nextSepTimer <= now then
        this.nextSepTimer = now + 0.25
        local tbuttons = pfUI.buff.septargetdebuffs.buttons
        for i = 1, getn(tbuttons) do
          local btn = tbuttons[i]
          if btn:IsShown() and btn.aid then
            local dn, rank, dtex, dstacks, ddtype, ddur, dtl = libdebuff:UnitDebuff("target", btn.aid)
            -- 名字对得上才更新（索引漂移时丢弃文本，等下次事件刷新修正）
            if dn and dn ~= "" and btn.tname == dn and type(dtl) == "number" and dtl > 0 then
              btn.timer:SetText(GetColoredTimeString(dtl))
            else
              btn.timer:SetText("")
            end
          end
        end
      end
    end

    -- Cache weapon enchant info once per update cycle
    local mh, mhtime, mhcharge, oh, ohtime, ohcharge = GetWeaponEnchantInfo()

    -- Update all visible buff buttons
    local buttons = pfUI.buff.buffs.buttons
    for i = 1, 32 do
      local buff = buttons[i]
      if buff:IsShown() then
        local timeleft, stacks = 0, 0
        if buff.mode == buff.btype then
          timeleft = GetPlayerBuffTimeLeft(buff.bid, buff.btype)
          stacks = GetPlayerBuffApplications(buff.bid, buff.btype)
        elseif buff.mode == "MAINHAND" then
          timeleft = mhtime and mhtime / 1000 or 0
          stacks = mhcharge or 0
        elseif buff.mode == "OFFHAND" then
          timeleft = ohtime and ohtime / 1000 or 0
          stacks = ohcharge or 0
        end
        -- timeleft/stacks 取不到时必须是"空串"而不是抛错：一次 nil 比较就会
        -- 掐断整个 OnUpdate 后半段（分离区倒计时/发光边框全停）
        buff.timer:SetText(timeleft and timeleft > 0 and GetColoredTimeString(timeleft) or "")
        buff.stacks:SetText((tonumber(stacks) or 0) > 1 and stacks or "")
      end
    end

    -- Update all visible debuff buttons
    buttons = pfUI.buff.debuffs.buttons
    for i = 1, 16 do
      local buff = buttons[i]
      if buff:IsShown() then
        local timeleft = GetPlayerBuffTimeLeft(buff.bid, buff.btype)
        local stacks = GetPlayerBuffApplications(buff.bid, buff.btype)
        buff.timer:SetText(timeleft and timeleft > 0 and GetColoredTimeString(timeleft) or "")
        buff.stacks:SetText((tonumber(stacks) or 0) > 1 and stacks or "")
      end
    end

    -- Update weapon buff buttons if separate
    if C.buffs.separateweapons == "1" then
      buttons = pfUI.buff.wepbuffs.buttons
      for i = 1, 2 do
        local buff = buttons[i]
        if buff:IsShown() then
          local timeleft, stacks = 0, 0
          if buff.mode == "MAINHAND" then
            timeleft = mhtime and mhtime / 1000 or 0
            stacks = mhcharge or 0
          elseif buff.mode == "OFFHAND" then
            timeleft = ohtime and ohtime / 1000 or 0
            stacks = ohcharge or 0
          end
          buff.timer:SetText(timeleft and timeleft > 0 and GetColoredTimeString(timeleft) or "")
          buff.stacks:SetText((tonumber(stacks) or 0) > 1 and stacks or "")
        end
      end
    end

    -- Update separated (highlighted) buffs
    if C.buffs.separatebuffs == "1" and pfUI.buff.sepbuffs then
      -- unitframes 玩家框晚就绪时在这里补默认锚点（已锚/拖过则秒回）
      pfUI.buff:AnchorPlayerSep(pfUI.buff.sepbuffs, false)
      buttons = pfUI.buff.sepbuffs.buttons
      -- 呼吸高亮：边框在暗金 <-> 亮金之间循环，突出「重点显示」的 buff
      local pulse = C.buffs.sepbuffglow == "1" and (math.sin(now * 3) + 1) / 2 or 1
      for i = 1, getn(buttons) do
        local buff = buttons[i]
        if buff:IsShown() and buff.bid then
          local timeleft = GetPlayerBuffTimeLeft(buff.bid, "HELPFUL")
          local stacks = GetPlayerBuffApplications(buff.bid, "HELPFUL")
          buff.timer:SetText(timeleft and timeleft > 0 and GetColoredTimeString(timeleft) or "")
          buff.stacks:SetText((tonumber(stacks) or 0) > 1 and stacks or "")
          if C.buffs.sepbuffglow == "1" then
            buff.backdrop:SetBackdropBorderColor(1, .55 + .35 * pulse, .05 + .1 * pulse, 1)
          else
            buff.backdrop:SetBackdropBorderColor(1, .78, .1, 1)
          end
        end
      end
    end

    -- Update separated (highlighted) debuffs —— 红色呼吸，比 buff 更醒目
    if C.buffs.separatedebuffs == "1" and pfUI.buff.sepdebuffs then
      -- unitframes 玩家框晚就绪时在这里补默认锚点（已锚/拖过则秒回）
      pfUI.buff:AnchorPlayerSep(pfUI.buff.sepdebuffs, true)
      buttons = pfUI.buff.sepdebuffs.buttons
      local pulse = C.buffs.sepdebuffglow == "1" and (math.sin(now * 3) + 1) / 2 or 1
      for i = 1, getn(buttons) do
        local buff = buttons[i]
        if buff:IsShown() and buff.bid then
          local timeleft = GetPlayerBuffTimeLeft(buff.bid, "HARMFUL")
          local stacks = GetPlayerBuffApplications(buff.bid, "HARMFUL")
          buff.timer:SetText(timeleft and timeleft > 0 and GetColoredTimeString(timeleft) or "")
          buff.stacks:SetText((tonumber(stacks) or 0) > 1 and stacks or "")
          if C.buffs.sepdebuffglow == "1" then
            buff.backdrop:SetBackdropBorderColor(1, .12 + .38 * pulse, .08 + .12 * pulse, 1)
          else
            buff.backdrop:SetBackdropBorderColor(1, .22, .12, 1)
          end
        end
      end
    end

    -- 目标分离区呼吸高亮（金/红，与玩家版同款）
    if C.buffs.separatetargetbuffs == "1" and pfUI.buff.septargetbuffs and pfUI.buff.septargetbuffs.buttons then
      local tpulse = C.buffs.septargetbuffglow == "1" and (math.sin(now * 3) + 1) / 2 or 1
      for i = 1, getn(pfUI.buff.septargetbuffs.buttons) do
        local buff = pfUI.buff.septargetbuffs.buttons[i]
        if buff:IsShown() and buff.backdrop then
          if C.buffs.septargetbuffglow == "1" then
            buff.backdrop:SetBackdropBorderColor(1, .55 + .35 * tpulse, .05 + .1 * tpulse, 1)
          else
            buff.backdrop:SetBackdropBorderColor(1, .78, .1, 1)
          end
        end
      end
    end

    if C.buffs.separatetargetdebuffs == "1" and pfUI.buff.septargetdebuffs and pfUI.buff.septargetdebuffs.buttons then
      local tpulse = C.buffs.septargetdebuffglow == "1" and (math.sin(now * 3) + 1) / 2 or 1
      for i = 1, getn(pfUI.buff.septargetdebuffs.buttons) do
        local buff = pfUI.buff.septargetdebuffs.buttons[i]
        if buff:IsShown() and buff.backdrop then
          if C.buffs.septargetdebuffglow == "1" then
            buff.backdrop:SetBackdropBorderColor(1, .12 + .38 * tpulse, .08 + .12 * tpulse, 1)
          else
            buff.backdrop:SetBackdropBorderColor(1, .22, .12, 1)
          end
        end
      end
    end
  end)

  -- 分离显示（Highlight Icons）：buff 区与 debuff 区是两个独立容器，各自注册 movable、
  -- 可以分别拖动到不同位置；拖动过的位置按框名（pfSepBuffFrame / pfSepDebuffFrame）分别记忆。

  -- Seperated Buffs（重点显示区）：必须在 buffs 容器之前创建，
  -- 因为普通 buff 刷新时会把命中的 buff 登记进它的 slots。
  pfUI.buff.sepbuffs = CreateFrame("Frame", "pfSepBuffFrame", UIParent)
  pfUI.buff.sepbuffs.slots = {}
  pfUI.buff.sepbuffs.buttons = {}
  for i=1,pfUI.buff.SEPBUFF_COUNT do
    pfUI.buff.sepbuffs.buttons[i] = CreateBuffButton(i, "HELPFUL", nil, 1)
  end

  -- Seperated Debuffs（重点显示区）：与分离 buff 完全同构，只是名单 / 开关 / 配色不同
  pfUI.buff.sepdebuffs = CreateFrame("Frame", "pfSepDebuffFrame", UIParent)
  pfUI.buff.sepdebuffs.slots = {}
  pfUI.buff.sepdebuffs.buttons = {}
  for i=1,pfUI.buff.SEPDEBUFF_COUNT do
    pfUI.buff.sepdebuffs.buttons[i] = CreateBuffButton(i, "HARMFUL", nil, 2)
  end

  -- 目标分离 Debuff 区：锚在目标框上方（目标 debuff 条同一区域），内容由
  -- RefreshTargetSepBuffs 轮询 UnitBuff/UnitDebuff("target") 填充
  pfUI.buff.septargetdebuffs = CreateFrame("Frame", "pfSepTargetDebuffFrame", UIParent)
  pfUI.buff.septargetdebuffs.slots = {}
  pfUI.buff.septargetdebuffs.buttons = {}
  for i=1,pfUI.buff.TSEPDEBUFF_COUNT do
    pfUI.buff.septargetdebuffs.buttons[i] = CreateTargetSepButton(pfUI.buff.septargetdebuffs, i, "HARMFUL")
  end

  -- 目标分离 Buff 区：默认锚在目标分离 Debuff 区上方；Debuff 区关闭时退回目标框上方
  pfUI.buff.septargetbuffs = CreateFrame("Frame", "pfSepTargetBuffFrame", UIParent)
  pfUI.buff.septargetbuffs.slots = {}
  pfUI.buff.septargetbuffs.buttons = {}
  for i=1,pfUI.buff.TSEPBUFF_COUNT do
    pfUI.buff.septargetbuffs.buttons[i] = CreateTargetSepButton(pfUI.buff.septargetbuffs, i, "HELPFUL")
  end

  -- Weapon Buffs
  pfUI.buff.wepbuffs = CreateFrame("Frame", "pfWepBuffFrame", UIParent)
  pfUI.buff.wepbuffs.count = 0
  pfUI.buff.wepbuffs.buttons = {}
  for i=1,2 do
    pfUI.buff.wepbuffs.buttons[i] = CreateBuffButton(i, "HELPFUL", 1)
  end

  -- Buff Frame
  pfUI.buff.buffs = CreateFrame("Frame", "pfBuffFrame", UIParent)
  pfUI.buff.buffs.buttons = {}
  for i=1,32 do
    pfUI.buff.buffs.buttons[i] = CreateBuffButton(i, "HELPFUL")
  end

  -- Debuffs
  pfUI.buff.debuffs = CreateFrame("Frame", "pfDebuffFrame", UIParent)
  pfUI.buff.debuffs.buttons = {}
  for i=1,16 do
    pfUI.buff.debuffs.buttons[i] = CreateBuffButton(i, "HARMFUL")
  end

  -- config loading
  function pfUI.buff:UpdateConfigBuffButton(buff)
    local fontsize = C.buffs.fontsize == "-1" and C.global.font_size or C.buffs.fontsize
    -- 监控条（sep=1/2）独立字号 sep_fontsize（-1=跟随主 Buff 字号，存量行为）
    if (buff.sep == 1 or buff.sep == 2) and C.buffs.sep_fontsize and C.buffs.sep_fontsize ~= "-1" then
      fontsize = tonumber(C.buffs.sep_fontsize)
    end
    local bsize, bsfont = tonumber(C.buffs.size), fontsize
    if buff.sep == 1 then
      bsize = tonumber(C.buffs.sepbuffsize)
      bsfont = fontsize + 1
    elseif buff.sep == 2 then
      bsize = tonumber(C.buffs.sepdebuffsize)
      bsfont = fontsize + 1
    end

    buff:SetWidth(bsize)
    buff:SetHeight(bsize)
    -- 定位交由 RelayoutContainer 处理（紧凑无空格，隐藏后可见 buff 依次前移）

    buff.timer:SetFont(pfUI.font_default, bsfont, "OUTLINE")
    buff.stacks:SetFont(pfUI.font_default, bsfont+1, "OUTLINE")

    -- 设置武器标签字体大小，根据buff大小动态调整
    if buff.weaponLabel then
      local labelFontSize = max(8, min(12, tonumber(C.buffs.size) / 4))
      buff.weaponLabel:SetFont(pfUI.font_default, labelFontSize, "OUTLINE")
    end

    -- 高度按实际字号算（分离区字号是 fontsize+1，用 fontsize 会偏小）
    buff.timer:SetHeight(bsfont * 1.3)
    -- ⛔ 禁止词内断行：宽度不足时客户端会把一个长词逐字换行（"15" → 上下两行），
    --    或直接省略号截断（"120m" → "10…"）。buffwatch 的计时文字也是这么设的。
    buff.timer:SetNonSpaceWrap(false)

    buff.timer:ClearAllPoints()
    -- 倒计时位置：监控条（sep=1 玩家Buff / sep=2 玩家Debuff）用独立开关 sep_textinside，
    -- 主 Buff/Debuff 条仍用 textinside —— 两者互不干扰（独立设置需求 2026-10-22）
    if (buff.sep == 1 or buff.sep == 2) then
      if C.buffs.sep_textinside == "1" then
        buff.timer:SetAllPoints(buff)
      else
        buff.timer:SetPoint("TOP", buff, "BOTTOM", 0, -3)
        -- ⛔ 宽度必须显式给，而且要按**字号**算，不能只按图标尺寸算：
        --    · 宽度 0      → 逐字换行（"15" 叠成上下两行）、单字符完全不渲染；
        --    · 只给 2 个字宽 → 分钟档 4 字符（"100m"~"120m"）被截断成 "10…"。
        --    倒计时最长 4 字符（分钟档 "120m" / 天档 "365d"），字号 12~13 时
        --    约占 2.7 个字宽 → 留到 3.2 个字宽才有富余（含 OUTLINE 描边余量）。
        buff.timer:SetWidth(max(bsize, bsfont * 3.2))
      end
    elseif C.buffs.textinside == "1" then
      buff.timer:SetAllPoints(buff)
    else
      buff.timer:SetPoint("TOP", buff, "BOTTOM", 0, -3)
      -- ⛔ 宽度必须显式给，而且要按**字号**算，不能只按图标尺寸算：
      --    · 宽度 0      → 逐字换行（"15" 叠成上下两行）、单字符完全不渲染；
      --    · 只给 2 个字宽 → 分钟档 4 字符（"100m"~"120m"）被截断成 "10…"。
      --    倒计时最长 4 字符（分钟档 "120m" / 天档 "365d"），字号 12~13 时
      --    约占 2.7 个字宽 → 留到 3.2 个字宽才有富余（含 OUTLINE 描边余量）。
      buff.timer:SetWidth(max(bsize, bsfont * 3.2))
    end
    
    -- 调整武器标签位置，确保在框内左上角
    if buff.weaponLabel then
      buff.weaponLabel:ClearAllPoints()
      buff.weaponLabel:SetPoint("TOPLEFT", buff, "TOPLEFT", 2, -2)
    end
  end

  -- 紧凑重排：可见 buff 依次前移，隐藏后不留空格
  -- 'inside' [string|nil] 倒计时位置开关覆写（"1"/"0"）：监控条传 C.buffs.sep_textinside，
  --                          nil 时回退主条开关 C.buffs.textinside（主条调用点不传）
  function pfUI.buff:RelayoutContainer(container, rowsize, fontsize, size, inside)
    size = tonumber(size or C.buffs.size)
    local spacing = tonumber(C.buffs.spacing)
    local step = size + 2 * spacing
    local rowHeight = ((inside or C.buffs.textinside) == "1" and 0 or (fontsize * 1.5)) + size + 2 * spacing
    local pos = 0
    local n = getn(container.buttons)
    for i = 1, n do
      local buff = container.buttons[i]
      if buff and buff:IsShown() then
        pos = pos + 1
        local rowcount = floor((pos - 1) / rowsize)
        local offsetX = -(pos - 1 - rowcount * rowsize) * step
        local offsetY = -rowcount * rowHeight
        buff:ClearAllPoints()
        buff:SetPoint("TOPRIGHT", container, "TOPRIGHT", offsetX, offsetY)
      end
    end

    -- 缓存格距，供分离区按实际内容计算容器尺寸（保证与排版完全一致）
    container.step = step
    container.rowheight = rowHeight

    -- 返回实际占用的行数 / 最宽一行的列数，供调用方收缩容器
    -- （多行时首行必然排满，所以取 rowsize；单行时列数就是图标个数）
    local rows = ceil(pos / rowsize)
    local cols = 0
    if rows > 0 then
      cols = (rows > 1) and rowsize or pos
    end
    return rows, cols
  end

  -- 目标分离区按钮的尺寸/字体配置（与玩家版 UpdateConfigBuffButton 同构）
  function pfUI.buff:UpdateConfigTargetSepButton(btn)
    local isharm = btn.kind == "HARMFUL"
    local fontsize = C.buffs.fontsize == "-1" and C.global.font_size or C.buffs.fontsize
    -- 监控条独立字号 sep_fontsize（-1=跟随主 Buff 字号，存量行为）
    if C.buffs.sep_fontsize and C.buffs.sep_fontsize ~= "-1" then fontsize = tonumber(C.buffs.sep_fontsize) end
    local bsize = isharm and tonumber(C.buffs.septargetdebuffsize) or tonumber(C.buffs.septargetbuffsize)
    btn:SetWidth(bsize)
    btn:SetHeight(bsize)

    btn.timer:SetFont(pfUI.font_default, fontsize + 1, "OUTLINE")
    btn.stacks:SetFont(pfUI.font_default, fontsize + 2, "OUTLINE")
    btn.timer:SetHeight((fontsize + 1) * 1.3)
    -- 同 UpdateConfigBuffButton：禁止词内断行，避免逐字换行 / 省略号截断
    btn.timer:SetNonSpaceWrap(false)

    btn.timer:ClearAllPoints()
    -- 目标监控条用独立开关 sep_textinside（与玩家监控条一致，不再跟随主条 textinside）
    if C.buffs.sep_textinside == "1" then
      btn.timer:SetAllPoints(btn)
    else
      btn.timer:SetPoint("TOP", btn, "BOTTOM", 0, -3)
      -- 同 UpdateConfigBuffButton：按字号给足 4 字符（"120m"）的宽度
      btn.timer:SetWidth(max(bsize, (fontsize + 1) * 3.2))
    end

    btn.stacks:ClearAllPoints()
    btn.stacks:SetAllPoints(btn)
  end

  function pfUI.buff:UpdateConfig()
    local fontsize = C.buffs.fontsize == "-1" and C.global.font_size or C.buffs.fontsize

    pfUI.buff.buffs:SetWidth(tonumber(C.buffs.buffrowsize) * (tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
    pfUI.buff.buffs:SetHeight(ceil(32/tonumber(C.buffs.buffrowsize)) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
    pfUI.buff.buffs:SetPoint("TOPRIGHT", pfUI.minimap or UIParent, "TOPLEFT", -4*tonumber(C.buffs.spacing), 0)
    UpdateMovable(pfUI.buff.buffs)

    pfUI.buff.debuffs:SetWidth(tonumber(C.buffs.debuffrowsize) * (tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
    pfUI.buff.debuffs:SetHeight(ceil(16/tonumber(C.buffs.debuffrowsize)) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
    pfUI.buff.debuffs:SetPoint("TOPRIGHT", pfUI.buff.buffs, "BOTTOMRIGHT", 0, 0)
    UpdateMovable(pfUI.buff.debuffs)

    if C.buffs.separateweapons == "1" then
      pfUI.buff.wepbuffs:ClearAllPoints()
      pfUI.buff.wepbuffs:SetWidth(tonumber(C.buffs.wepbuffrowsize) * (tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
      pfUI.buff.wepbuffs:SetHeight(ceil(2/tonumber(C.buffs.wepbuffrowsize)) * ((C.buffs.textinside == "1" and 0 or (fontsize*1.5))+tonumber(C.buffs.size)+2*tonumber(C.buffs.spacing)))
      pfUI.buff.wepbuffs:SetPoint("TOPRIGHT", pfUI.buff.debuffs, "BOTTOMRIGHT", 0, 0)
      pfUI.buff.wepbuffs:Show()
      UpdateMovable(pfUI.buff.wepbuffs)
    else
      pfUI.buff.wepbuffs:Hide()
      RemoveMovable(pfUI.buff.wepbuffs)
    end

    -- 分离显示（Highlight Icons）：默认锚在玩家头像（pfUI.uf.player）上方，与目标分离区同构；
    -- unitframes 模块未就绪时先落屏幕中央，OnUpdate 里 AnchorPlayerSep 补默认锚点；
    -- buff/debuff 区各自独立注册 movable，拖动过的位置按框名分别记忆，互不影响。
    if C.buffs.separatedebuffs == "1" then
      pfUI.buff.sepdebuffs:ClearAllPoints()
      if pfUI.uf and pfUI.uf.player then
        -- debuff 区贴玩家头像正上方
        pfUI.buff.sepdebuffs:SetPoint("BOTTOMRIGHT", pfUI.uf.player, "TOPRIGHT", 0, 4)
        pfUI.buff.sepdebuffs.playeranchored = true
      else
        pfUI.buff.sepdebuffs:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        pfUI.buff.sepdebuffs.playeranchored = false
      end
      pfUI.buff.sepdebuffs:Show()
      UpdateMovable(pfUI.buff.sepdebuffs)
    else
      pfUI.buff.sepdebuffs:Hide()
      pfUI.buff.sepdebuffs.playeranchored = false
      RemoveMovable(pfUI.buff.sepdebuffs)
    end

    if C.buffs.separatebuffs == "1" then
      pfUI.buff.sepbuffs:ClearAllPoints()
      if pfUI.uf and pfUI.uf.player then
        -- buff 区叠在分离 debuff 区上方；debuff 分离未开启时退回头像正上方
        if C.buffs.separatedebuffs == "1" then
          pfUI.buff.sepbuffs:SetPoint("BOTTOMRIGHT", pfUI.buff.sepdebuffs, "TOPRIGHT", 0, tonumber(C.buffs.spacing))
        else
          pfUI.buff.sepbuffs:SetPoint("BOTTOMRIGHT", pfUI.uf.player, "TOPRIGHT", 0, 4)
        end
        pfUI.buff.sepbuffs.playeranchored = true
      else
        pfUI.buff.sepbuffs:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        pfUI.buff.sepbuffs.playeranchored = false
      end
      pfUI.buff.sepbuffs:Show()
      UpdateMovable(pfUI.buff.sepbuffs)
    else
      pfUI.buff.sepbuffs:Hide()
      pfUI.buff.sepbuffs.playeranchored = false
      RemoveMovable(pfUI.buff.sepbuffs)
    end

    -- 目标分离区：锚定目标框（unitframes 模块可能晚于本模块就绪，未就绪时先落屏幕中央，
    -- RefreshTargetSepBuffs 轮询里会通过 AnchorTargetSep 补默认锚点；拖动过的位置不受影响）
    if C.buffs.separatetargetdebuffs == "1" then
      pfUI.buff.septargetdebuffs:ClearAllPoints()
      if pfUI.uf and pfUI.uf.target then
        local topoff = (C.buffbar and C.buffbar.tdebuff and C.buffbar.tdebuff.enable == "1") and 30 or 4
        pfUI.buff.septargetdebuffs:SetPoint("BOTTOMRIGHT", pfUI.uf.target, "TOPRIGHT", 0, topoff)
        pfUI.buff.septargetdebuffs.targetanchored = true
      else
        pfUI.buff.septargetdebuffs:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        pfUI.buff.septargetdebuffs.targetanchored = false
      end
      pfUI.buff.septargetdebuffs:Show()
      UpdateMovable(pfUI.buff.septargetdebuffs)
    else
      pfUI.buff.septargetdebuffs:Hide()
      pfUI.buff.septargetdebuffs.targetanchored = false
      RemoveMovable(pfUI.buff.septargetdebuffs)
    end

    if C.buffs.separatetargetbuffs == "1" then
      pfUI.buff.septargetbuffs:ClearAllPoints()
      if pfUI.uf and pfUI.uf.target then
        if C.buffs.separatetargetdebuffs == "1" then
          pfUI.buff.septargetbuffs:SetPoint("BOTTOMRIGHT", pfUI.buff.septargetdebuffs, "TOPRIGHT", 0, tonumber(C.buffs.spacing))
        else
          local topoff = (C.buffbar and C.buffbar.tdebuff and C.buffbar.tdebuff.enable == "1") and 30 or 4
          pfUI.buff.septargetbuffs:SetPoint("BOTTOMRIGHT", pfUI.uf.target, "TOPRIGHT", 0, topoff)
        end
        pfUI.buff.septargetbuffs.targetanchored = true
      else
        pfUI.buff.septargetbuffs:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        pfUI.buff.septargetbuffs.targetanchored = false
      end
      pfUI.buff.septargetbuffs:Show()
      UpdateMovable(pfUI.buff.septargetbuffs)
    else
      pfUI.buff.septargetbuffs:Hide()
      pfUI.buff.septargetbuffs.targetanchored = false
      RemoveMovable(pfUI.buff.septargetbuffs)
    end

    for i=1,32 do
      pfUI.buff:UpdateConfigBuffButton(pfUI.buff.buffs.buttons[i])
    end

    for i=1,16 do
      pfUI.buff:UpdateConfigBuffButton(pfUI.buff.debuffs.buttons[i])
    end

    for i=1,2 do
      pfUI.buff:UpdateConfigBuffButton(pfUI.buff.wepbuffs.buttons[i])
    end

    -- WA 式动态：懒建按钮超出 COUNT 初始池，按 getn 全量刷新（存在才刷，nil 跳过）
    for i=1,getn(pfUI.buff.sepbuffs.buttons) do
      if pfUI.buff.sepbuffs.buttons[i] then
        pfUI.buff:UpdateConfigBuffButton(pfUI.buff.sepbuffs.buttons[i])
      end
    end

    for i=1,getn(pfUI.buff.sepdebuffs.buttons) do
      if pfUI.buff.sepdebuffs.buttons[i] then
        pfUI.buff:UpdateConfigBuffButton(pfUI.buff.sepdebuffs.buttons[i])
      end
    end

    for i=1,getn(pfUI.buff.septargetbuffs.buttons) do
      if pfUI.buff.septargetbuffs.buttons[i] then
        pfUI.buff:UpdateConfigTargetSepButton(pfUI.buff.septargetbuffs.buttons[i])
      end
    end

    for i=1,getn(pfUI.buff.septargetdebuffs.buttons) do
      if pfUI.buff.septargetdebuffs.buttons[i] then
        pfUI.buff:UpdateConfigTargetSepButton(pfUI.buff.septargetdebuffs.buttons[i])
      end
    end

    pfUI.buff:GetScript("OnEvent")()
  end

  pfUI.buff:UpdateConfig()
end)
