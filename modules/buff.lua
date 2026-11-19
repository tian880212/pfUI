pfUI:RegisterModule("buff", "vanilla:tbc", function ()
  -- Hide Blizz
  BuffFrame:Hide()
  BuffFrame:UnregisterAllEvents()
  TemporaryEnchantFrame:Hide()
  TemporaryEnchantFrame:UnregisterAllEvents()

  local br, bg, bb, ba = GetStringColor(pfUI_config.appearance.border.color)

  -- ── 提醒 / 监控区配色 ───────────────────────────────────────────────────────
  -- 必须定义在文件靠前：CreateBuffButton 建图标时要上基础色、RestoreIconBorder
  -- 还原时要上同一条色、ExpireWarn 闪的时候还要在上面派生亮暗档，三处共用一套。
  -- C.buffs.expirewarncolor = "r,g,b,a"（取前三段）；三种样式（常亮 / 呼吸 / 闪烁）
  -- 的颜色一律从这一个基色派生：亮档向白混、暗档压暗。
  -- ⛔ 不要写死红橙：基色改成蓝的，写死的红档会把它整片盖掉，
  --    用户看到的是"选了颜色却不生效"，比没有这个选项更糟。
  -- ⛔ 0.1s 一拍里每个可见图标都会调一次（几十个），不能每拍 strsplit + tonumber：
  --    用原始字符串当签名缓存，改配置时签名先变，下一拍自然重建。
  -- 按区域前缀缓存：四组（右上角 / 分离 Buff / 分离 Debuff / 目标区）各一条基色。
  -- key = 该组的键前缀，如 "expirewarnmain" ⇒ 读 C.buffs.expirewarnmaincolor。
  local warnTint = {}

  local function GroupWarnTint(prefix)
    local t = warnTint[prefix]
    if not t then
      t = { r = 1, g = .35, b = .12 }
      warnTint[prefix] = t
    end
    -- 缺键/空串时退回老的共享基色：与 sec/style 的兜底一致，
    -- 否则删掉某组颜色键后图标会停在上一次的颜色上（看起来像"颜色没生效"）。
    local s = C.buffs[prefix .. "color"]
    if not s or s == "" then s = C.buffs.expirewarncolor or "" end
    if s ~= t.sig then
      t.sig = s
      local r, g, b = strsplit(",", s)
      -- 脏值只覆盖能解析的成分，保留上一次的值（不能整体回默认，会把用户刚调好的颜色吃掉）
      t.r = tonumber(r) or t.r
      t.g = tonumber(g) or t.g
      t.b = tonumber(b) or t.b
    end
    return t.r, t.g, t.b
  end

  -- （各区域统一走 GroupWarnTint，不再有单独入口）

  -- k >= 1：向白色混（k=2 时最多混 .6）；k < 1：整体压暗。
  -- 任何基色都能拉出"亮-暗"两档：深蓝 (.1,.2,1) 压暗后仍然可见，亮档也不会过曝成白。
  local function WarnLevel(r, g, b, k)
    if k >= 1 then
      local t = (k - 1) * .6
      if t > .6 then t = .6 end
      return r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t
    end
    return r * k, g * k, b * k
  end

  -- ── 分离监控区（Highlight Icons）的基色 ─────────────────────────────────────
  -- 玩家区与目标区共用同一组：buff 一组、debuff 一组，各自可以染色。
  -- 呼吸高亮 = 在这条基色上做明暗（不另设"亮档颜色"，否则两个颜色会打架）。
  local sepTint = {
    buff   = { sig = false, r = 1, g = .78, b = .1 },
    debuff = { sig = false, r = 1, g = .22, b = .12 },
  }

  local function SepTint(which)
    local t = sepTint[which]
    local s = C.buffs[which == "buff" and "sepbuffglowcolor" or "sepdebuffglowcolor"] or ""
    if s ~= t.sig then
      t.sig = s
      local r, g, b = strsplit(",", s)
      -- 脏值只覆盖能解析的成分，保留上一次的值（不能整体回默认，会把用户刚调好的颜色吃掉）
      t.r = tonumber(r) or t.r
      t.g = tonumber(g) or t.g
      t.b = tonumber(b) or t.b
    end
    return t.r, t.g, t.b
  end

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
              -- 隐藏前收掉提醒动画：按钮是复用的，残留的 chase/flash 会跟着下一个 buff 一起亮
              pfUI.buff:WarnGlowDrop(buff)
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
        pfUI.buff:WarnGlowDrop(buff)
        buff:Hide()
        return
      end
    end

    -- 黑白名单过滤（与 BuffWatch / BuffBar 一致：# 分隔；以 spellID 为主，名称尽力匹配；武器附魔不参与）
    if buff.mode == buff.btype and not pfUI.buff:AuraVisible(buff) then
      pfUI.buff:WarnGlowDrop(buff)
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
          pfUI.buff:WarnGlowDrop(buff)
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
    -- sep == 1 取 buff 基色，sep == 2 取 debuff 基色（都可在 GUI 里改）
    if sep == 1 or sep == 2 then
      CreateBackdrop(buff)
      CreateBackdropShadow(buff)
      local r, g, b = SepTint(sep == 1 and "buff" or "debuff")
      buff.backdrop:SetBackdropBorderColor(r, g, b, 1)
    end

    -- PERF: 单个 buff 图标不挂 OnUpdate —— 倒计时/层数/边框呼吸全部由
    -- pfUI.buff 的周期回调 BuffTimerTick 统一驱动（登记在 pfUI.api.libticker，0.1s 一拍）

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

  -- ⛔ 这两个方法必须定义在 pfUI.buff = CreateFrame(...) **之后**：
  --    `function pfUI.buff:X()` 是给 pfUI.buff 表赋值，表还不存在时会直接
  --    "attempt to index global" 让整个模块静默不加载。
  -- 图标边框的「基础色」：到期提醒结束后用它还原。
  -- 配色必须与 RefreshBuffButton 里设的完全一致（道具品质 / 减益驱散类型 / 分离区金色红色），
  -- 否则提醒结束后图标会莫名其妙变成另一种颜色。
  function pfUI.buff:RestoreIconBorder(buff)
    local bd = buff.backdrop
    if not bd then return end
    local kind = buff.btype or buff.kind
    if buff.sep == 1 then
      local r, g, b = SepTint("buff")
      bd:SetBackdropBorderColor(r, g, b, 1)
    elseif buff.sep == 2 then
      local r, g, b = SepTint("debuff")
      bd:SetBackdropBorderColor(r, g, b, 1)
    elseif buff.kind then
      -- 目标监控区按钮只有 kind（HELPFUL / HARMFUL）、没有 btype/bid，基础色取对应分组的基色
      local r, g, b = SepTint(buff.kind == "HARMFUL" and "debuff" or "buff")
      bd:SetBackdropBorderColor(r, g, b, 1)
    elseif buff.mode == "MAINHAND" or buff.mode == "OFFHAND" then
      local slot = buff.mode == "MAINHAND" and 16 or 17
      bd:SetBackdropBorderColor(GetItemQualityColor(GetInventoryItemQuality("player", slot) or 1))
    elseif kind == "HARMFUL" then
      local dtype = buff.bid and GetPlayerBuffDispelType(buff.bid)
      if dtype == "Magic" then
        bd:SetBackdropBorderColor(0,1,1,1)
      elseif dtype == "Poison" then
        bd:SetBackdropBorderColor(0,1,0,1)
      elseif dtype == "Curse" then
        bd:SetBackdropBorderColor(1,0,1,1)
      elseif dtype == "Disease" then
        bd:SetBackdropBorderColor(1,1,0,1)
      else
        bd:SetBackdropBorderColor(1,0,0,1)
      end
    else
      bd:SetBackdropBorderColor(br, bg, bb, ba)
    end
  end

  -- ── 到期提醒的动画手柄（libglow：闪烁=整块、流光=边框跑圈）─────────────────────
  -- ⛔ 只有 flash / chase 交给 libglow：它们画在各自的覆盖纹理上，一帧都不碰 backdrop
  --    的边框色。pulse（边框色呼吸）必须留在 0.1s 循环里手写 —— 分离区/目标监控区的
  --    底色呼吸也在同一个 0.1s 循环里、而且是在 ExpireWarn **之前**写边框色，
  --    只有"后写"的一方稳定；交给每帧更新的 libglow 就是两方抢同一个
  --    SetBackdropBorderColor，边框会以 10Hz 抖一下（肉眼像接触不良）。
  -- ⛔ 手柄按风格缓存、永久复用：切一次风格重建一次纹理的话，来回切十次就是每个图标
  --    多出十几张 OVERLAY 纹理。纹理是引擎侧对象，不随 Lua 表回收。
  -- ⛔ 换风格必须先把另一种 Disarm：chase 的 4 条渐变带 + flash 的覆盖层同时 Arm 会叠着闪。
  function pfUI.buff:WarnGlowHandle(buff, style, cr, cg, cb)
    local glow = pfUI.api.libglow
    if not (glow and glow.Chase) then return nil end

    local set = buff.pfwarnset
    if not set then
      set = {}
      buff.pfwarnset = set
    end

    local h = set[style]
    if not h then
      if style == "chase" then
        -- 图标通常 20~32px：2px 光带、2.4s 一圈 —— 再细看不见，再快像在抽。
        h = glow:Chase(buff, { color = { cr, cg, cb }, thickness = 2, speed = 2.4, alpha = .95 })
      else
        -- 整块闪：峰值 .42（再高就把图标本身糊成一片，也压住倒计时文字）。
        -- period .7 ⇒ 一秒半不到闪两下，比动作条就绪提示慢一点，因为是持续状态。
        h = glow:Flash(buff, { color = { cr, cg, cb }, period = .7, low = .02, high = .42 })
      end
      set[style] = h
    elseif h.r ~= cr or h.g ~= cg or h.b ~= cb then
      -- GUI 改色后下一次进阈值自动同步。比数值不做字符串拼接：0.1s 一拍 × 几十个图标。
      h:SetColor(cr, cg, cb)
    end

    return h
  end

  -- 只收手柄，不动边框色（调用方紧接着会自己设底色或 Hide）
  function pfUI.buff:WarnGlowDrop(buff)
    local set = buff.pfwarnset
    if not set then return end
    for _, h in pairs(set) do
      if h:IsArmed() then h:Disarm() end
    end
  end

  -- 收手柄 + 按当前配置还原边框色。
  -- ⛔ 顺序不能反：pulse 的 Disarm 会把边框色写回"进阈值那一刻"记下的旧值，
  --    先还原再 Disarm 等于白还原（图标会跳回上一轮的颜色）。
  function pfUI.buff:WarnGlowClear(buff)
    self:WarnGlowDrop(buff)
    self:RestoreIconBorder(buff)
  end

  -- 各区域的提醒基色统一走 GroupWarnTint(前缀)（定义在文件顶部），不再各存一份缓存。

  -- 四个区域各一套「开关 + 阈值 + 样式 + 颜色」（2026-11-19 全部独立，配置项也放到各自页面）：
  --   右上角三行（Buff / Debuff / 武器 Buff） → expirewarnmain*      + expirewarnmaindebuff
  --   玩家分离 Buff                          → expirewarnsepbuff*
  --   玩家分离 Debuff                        → expirewarnsepdebuff*
  --   目标分离 Buff / Debuff                 → expirewarnseptarget*  + expirewarnseptargetdebuff
  -- 减益监控（debuffmonitor.lua）是第五套，参数在 C.debuffmon 自己的表里。
  -- ⛔ 分组判据只能是按钮自身属性：分离区按钮带 sep(1=Buff / 2=Debuff)、目标监控区按钮带 kind，
  --    普通行两者皆无 —— 不能靠"按钮属于哪个 container"去猜（目标区按钮父级也是 UIParent 级 frame）。
  function pfUI.buff:ExpireWarn(buff, timeleft, now)
    if not buff.backdrop then return end
    local group
    if buff.sep == 1 then
      group = "expirewarnsepbuff"
    elseif buff.sep == 2 then
      group = "expirewarnsepdebuff"
    elseif buff.kind then
      group = "expirewarnseptarget"
    else
      group = "expirewarnmain"
    end

    local on = C.buffs[group] == "1"
    -- 混合组（右上角三行、目标区）还要过一道「Debuff 也提醒」：
    -- 纯 Buff / 纯 Debuff 组不需要，它们自己的开关就是答案。
    if on and (buff.btype or buff.kind) == "HARMFUL" then
      if group == "expirewarnmain" and C.buffs.expirewarnmaindebuff ~= "1" then on = false end
      if group == "expirewarnseptarget" and C.buffs.expirewarnseptargetdebuff ~= "1" then on = false end
    end
    if not on then
      if buff.expwarn then
        buff.expwarn = nil
        pfUI.buff:WarnGlowClear(buff)
      end
      return
    end
    -- 参数按组取；缺键退回老的共享三键（config 补键前先加载模块的极端情况也不至于"没样式/没阈值"）
    local warnAt = tonumber(C.buffs[group .. "sec"]) or tonumber(C.buffs.expirewarnsec) or 5
    local style = C.buffs[group .. "style"] or C.buffs.expirewarnstyle
    local cr, cg, cb = GroupWarnTint(group)
    if warnAt < 1 then warnAt = 1 end
    if type(timeleft) == "number" and timeleft > 0 and timeleft <= warnAt then
      buff.expwarn = 1

      -- 一次只允许一种动画在跑：GUI 里换风格时把另一种收掉（否则两套叠着闪）
      local set = buff.pfwarnset
      if set then
        for k, h in pairs(set) do
          if k ~= style and h:IsArmed() then h:Disarm() end
        end
      end

      if style == "chase" or style == "flash" then
        local h = pfUI.buff:WarnGlowHandle(buff, style, cr, cg, cb)
        if h then
          -- 已经是这个风格就不要反复 Arm（Arm 会重跑一遍 ShowTex + Sync）
          if not h:IsArmed() then h:Arm() end
        else
          -- libglow 缺失：退化成常亮，至少看得见 —— 不静默失效
          buff.backdrop:SetBackdropBorderColor(cr, cg, cb, 1)
        end
      elseif style == "pulse" then
        -- 呼吸：亮度 .55 → 1.45 来回走，alpha 同时 .55 → 1（双通道，细边框也看得出来）
        local p = (math.sin(now * 6) + 1) / 2
        local pr, pg, pb = WarnLevel(cr, cg, cb, .55 + .9 * p)
        buff.backdrop:SetBackdropBorderColor(pr, pg, pb, .55 + .45 * p)
      else
        -- 常亮（含老存档里剩下的未知值）：基色原样，不晃眼
        buff.backdrop:SetBackdropBorderColor(cr, cg, cb, 1)
      end
    elseif buff.expwarn then
      buff.expwarn = nil
      pfUI.buff:WarnGlowClear(buff)
    end
  end

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

  -- 名单只有一组：C.buffs.filter / whitelist / blacklist，Buff 图标与 Debuff 图标共用。
  -- ⛔ 2026-11-01 曾拆成「Buff 行 / Debuff 行各一组」（debufffilter 等三键 + follow），
  --    实际用起来是反的：加个 Debuff 名单还得挑行、模式还要 follow，图标行为前后不一致。
  --    现按用户要求回退成一组 —— 加谁的 ID，两行就按同一套规则过滤，行为一致可预期。
  -- 常量表：AuraVisible 会被逐个图标调用，别在这里 new table。
  local FilterGroupAll = { mode = "filter", wl = "whitelist", bl = "blacklist" }

  -- 某个光环实际生效的 (过滤模式, 白名单串, 黑名单串)
  -- buff 参数保留（调用点按图标传），以后要再分组不必改调用方
  function pfUI.buff:GetAuraFilter(buff)
    local g = FilterGroupAll
    local mode = C.buffs[g.mode] or "none"
    -- 空串（存档被写坏 / 手工改过）必须当 none：否则 liststr 为空会落到「白名单空 ⇒ 全隐藏」，整行图标消失
    if mode == "" then mode = "none" end
    local wl = C.buffs[g.wl] or ""
    local bl = C.buffs[g.bl] or ""
    -- 智能默认：Filter Mode 为 none 但某张名单非空时，自动按非空名单启用
    -- （避免只在 GUI 列表框里加了条目、却忘了把 Filter Mode 切到对应模式）
    if mode == "none" then
      if bl ~= "" then mode = "blacklist"
      elseif wl ~= "" then mode = "whitelist" end
    end
    return mode, wl, bl
  end

  -- 名单键名：恒为同一组（保留 isdebuff 形参，历史调用点不用改）
  function pfUI.buff:GetListKeys(isdebuff)
    return "whitelist", "blacklist", "filter"
  end

  -- 黑白名单过滤：spellID 精确匹配
  function pfUI.buff:AuraVisible(buff)
    if not C or not C.buffs then return true end
    local mode, wl, bl = pfUI.buff:GetAuraFilter(buff)
    if mode == "none" then return true end
    local liststr = (mode == "whitelist" and wl) or (mode == "blacklist" and bl) or ""
    if liststr == "" then
      -- 白名单空 => 全部隐藏；黑名单空 => 全部显示
      return mode == "blacklist"
    end
    -- 没有 SuperWoW/Nampower 就没有 GetPlayerBuffID：所有 buff 都拿不到 spellID，
    -- 白名单会把整排图标藏光（黑名单则全放行）⇒ 这种环境直接放弃过滤，只提示一次
    if mode == "whitelist" and not (pfUI.api and pfUI.api.GetPlayerBuffSpellId) then
      if not pfUI.buff.noSpellIdWarned then
        pfUI.buff.noSpellIdWarned = true
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 当前客户端拿不到 Buff 的 spellID（缺 SuperWoW/Nampower 的 GetPlayerBuffID），白名单无法过滤，已临时放行全部 Buff")
      end
      return true
    end
    local sid = pfUI.buff:GetBuffId(buff)
    local found = false
    for v in string.gmatch(liststr, "[^#;]+") do
      v = string.gsub(v, "^%s*(.-)%s*$", "%1") -- 去前后空格
      if v ~= "" and tonumber(v) and sid and tonumber(v) == sid then
        found = true; break
      end
    end
    -- ⛔ 不能写成 `mode == "whitelist" and found or not found`：
    --    白名单未命中时前半段是 false，`or not found` 直接把它翻成 true ⇒ 白名单永远不隐藏任何东西。
    if mode == "whitelist" then return found end
    return not found
  end

  -- 真正写入名单（确认之后才走这里）：重复检查、过滤模式自动切换、刷新都在这
  -- 名单只有一组，Buff 图标与 Debuff 图标写的是同一张（isdebuff 只为提示措辞服务）
  function pfUI.buff:DoAddToList(which, sid, isdebuff)
    if not C or not C.buffs or not sid then return end
    local wkey, bkey, mkey = pfUI.buff:GetListKeys(isdebuff)
    local key  = (which == "whitelist") and wkey or bkey
    local tag  = (which == "whitelist") and "白" or "黑"
    local list = C.buffs[key] or ""
    for v in string.gmatch(list, "[^#;]+") do
      if tonumber(v) and tonumber(v) == tonumber(sid) then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: ID " .. sid .. " 已在" .. tag .. "名单中")
        return
      end
    end
    C.buffs[key] = (list ~= "" and list .. "#" or "") .. tostring(sid)

    -- ⛔ 模式必须跟着「刚加进去的那张名单」走，否则条目写进去了却什么都不变：
    --    none = 压根没在过滤；反向 = 黑名单模式里加白名单条目（或反之），那张名单当前不参与判定。
    local mode = C.buffs[mkey] or "none"
    if mode ~= which then
      C.buffs[mkey] = which
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: ID " .. sid .. " 已加入" .. tag .. "名单，过滤模式已切换为「" .. tag .. "名单」")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: ID " .. sid .. " 已加入" .. tag .. "名单")
    end

    -- 立即生效：整套刷新先跑一遍（pcall 兜底 —— 任一行抛错也要落到下面只看过滤的重判，
    -- 否则用户看到的就是「确认了，但图标一动不动，得等下次 Buff 变化甚至 /reload」）
    if pfUI.buff:GetScript("OnEvent") then pcall(pfUI.buff:GetScript("OnEvent")) end
    pfUI.buff:RefreshFilter()
  end

  -- 只看可见性的轻量刷新：名单被改过之后必须当场重判一遍
  -- （不能依赖 PLAYER_AURAS_CHANGED —— 加完名单还得等身上 Buff 发生变化才看见效果）
  function pfUI.buff:RefreshFilter()
    if not C or not C.buffs then return end
    -- 分离/监控区的槽位按本轮刷新重新登记，先清空（与 OnEvent 里的做法一致）
    if pfUI.buff.sepbuffs then pfUI.buff.sepbuffs.slots = {} end
    if pfUI.buff.sepdebuffs then pfUI.buff.sepdebuffs.slots = {} end

    local function pass(container, count)
      if not container or not container.buttons then return end
      for i = 1, count do
        local b = container.buttons[i]
        if b then pcall(RefreshBuffButton, b) end
      end
    end

    pass(pfUI.buff.buffs, 32)
    pass(pfUI.buff.debuffs, 16)
    if C.buffs.separateweapons == "1" then pass(pfUI.buff.wepbuffs, 2) end

    -- 分离区也吃名单：槽位序号会变 ⇒ 按本轮重新登记后重排
    -- （下面几个方法都由同一模块稍后定义，运行期才存在，这里一律判空再调）
    if pfUI.buff.sepbuffs and pfUI.buff.RefreshSepBuffs then pfUI.buff:RefreshSepBuffs(pfUI.buff.sepbuffs, "HELPFUL") end
    if pfUI.buff.sepdebuffs and pfUI.buff.RefreshSepBuffs then pfUI.buff:RefreshSepBuffs(pfUI.buff.sepdebuffs, "HARMFUL") end

    -- 紧凑重排：被藏掉的图标不留空格
    if not pfUI.buff.RelayoutContainer then return end
    local fs = C.buffs.fontsize == "-1" and C.global.font_size or C.buffs.fontsize
    pfUI.buff:RelayoutContainer(pfUI.buff.buffs, tonumber(C.buffs.buffrowsize), fs)
    pfUI.buff:RelayoutContainer(pfUI.buff.debuffs, tonumber(C.buffs.debuffrowsize), fs)
    if C.buffs.separateweapons == "1" then
      pfUI.buff:RelayoutContainer(pfUI.buff.wepbuffs, tonumber(C.buffs.wepbuffrowsize), fs)
    end
  end

  -- Ctrl+左键（白名单）/ Shift+左键（黑名单）：先弹确认再写
  -- ⛔ 名单是存档级配置，误按一下整片图标就没了 ⇒ 点图标的路子也要二次确认
  -- Buff 图标与 Debuff 图标写同一张名单（一组规则、两行表现一致）
  function pfUI.buff:AddToList(buff, which)
    if not C or not C.buffs then return end
    -- 武器附魔图标走的是 MAINHAND/OFFHAND 分支，本来就不参与名单过滤，加了也没用
    if buff and (buff.mode == "MAINHAND" or buff.mode == "OFFHAND") then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 武器附魔图标不参与黑白名单过滤，未加入名单")
      return
    end
    local isdebuff = (buff and buff.btype == "HARMFUL") and true or false
    local kind = isdebuff and "Debuff" or "Buff"
    local wkey, bkey = pfUI.buff:GetListKeys(isdebuff)
    local key = (which == "whitelist") and wkey or bkey
    local tag = (which == "whitelist") and "白" or "黑"

    local sid = pfUI.buff:GetBuffId(buff)
    if not sid then
      -- 把 bid 一起打出来：拿不到 spellID 时这是唯一能对上的线索（/pfhide 里同一槽位也会是 nil）
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 读不到该 " .. kind .. " 的 spellID（bid=" ..
        tostring(buff and buff.bid) .. "），未能加入名单；敲 /pfhide 看这个槽位的 ID 是不是 nil")
      return
    end

    for v in string.gmatch(C.buffs[key] or "", "[^#;]+") do
      if tonumber(v) and tonumber(v) == sid then
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: ID " .. sid .. " 已在" .. tag .. "名单中")
        return
      end
    end

    -- 名字只用在提示里：GetSpellRecField 依赖 Nampower/SuperWoW，拿不到就退回只说 ID
    local sname = GetSpellRecField and GetSpellRecField(sid, "name")
    if type(sname) ~= "string" then sname = nil end
    local what = sname and ("|cffffd200" .. sname .. "|r") or ("该" .. kind)
    local text = string.format("确认把 %s（ID %s）加入%s名单吗？\n\n名单对 Buff 和 Debuff 共用：确认后过滤模式会切到「%s名单」，两行图标当场按同一套规则重判。\n要删掉可在 设置 → Buffs → Buff/Debuff 图标 的名单里点「-」。", what, sid, tag, tag)

    CreateQuestionDialog(text, function()
      pfUI.buff:DoAddToList(which, sid, isdebuff)
    end)
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

  -- ==========================================================================
  -- 监控名单的匹配语义（2026-11-01）
  -- ⛔ 旧实现：无前缀条目一律「先精确、再子串」两遍 ⇒ 监控「狂热」必然把
  --    「狂热梦想」一起拉进监控区（同名不同 spellID 的光环同样一起进），
  --    而名单里只有「狂热」一条、删无可删 = 用户说的「屏蔽不掉」。
  -- 条目语法（大小写不敏感，前后空格忽略；纯数字仍按 spellID 精确）：
  --   名字    按 sepmatch 全局模式（默认 exact = 精确，只认同名光环）
  --   =名字   强制精确（「=狂热」不命中「狂热梦想」）
  --   ^名字   前缀（「^狂热」命中「狂热」「狂热梦想」）
  --   *名字   子串（旧的模糊行为，显式写法）
  -- 四套名单（玩家 Buff/Debuff、目标 Buff/Debuff）共用这一套判定。
  -- ==========================================================================

  -- 全局默认匹配模式：exact（默认）/ smart（先精确再子串 = 旧行为）/ fuzzy（只子串）
  function pfUI.buff:SepMatchMode()
    local m = C and C.buffs and C.buffs.sepmatch
    if m == "exact" or m == "smart" or m == "fuzzy" then return m end
    return "exact"
  end

  -- 切换匹配模式（命令与 GUI 共用）：存档 + 提示 + 四组监控条当场重判
  function pfUI.buff:SetSepMatchMode(mode)
    if not C or not C.buffs then return end
    if mode ~= "exact" and mode ~= "smart" and mode ~= "fuzzy" then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 未知匹配模式「" .. tostring(mode) .. "」（可用 exact / smart / fuzzy）")
      return
    end
    C.buffs.sepmatch = mode
    local desc = (mode == "exact" and "精确（只认同名，狂热 ≠ 狂热梦想）")
      or (mode == "smart" and "先精确再子串（旧行为，狂热 会命中 狂热梦想）")
      or "子串（只模糊匹配）"
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 监控名单匹配模式 = " .. mode .. " · " .. desc)
    if pfUI.buff:GetScript("OnEvent") then pcall(pfUI.buff:GetScript("OnEvent")) end
    if pfUI.buff.OnTargetAuraRefresh then pcall(pfUI.buff.OnTargetAuraRefresh, pfUI.buff) end
  end

  -- 条目去掉匹配前缀（= ^ *）后的可见名字：用于「加过一次再点就移除」的比较，
  -- 否则带前缀的条目永远认不出同名，Alt+左键会反复追加
  function pfUI.buff:SepEntryLabel(entry)
    if not entry then return "" end
    local c = string.sub(entry, 1, 1)
    if c == "=" or c == "^" or c == "*" then entry = string.sub(entry, 2) end
    return (string.gsub(entry, "^%s*(.-)%s*$", "%1"))
  end

  -- 拆名单 + 预解析匹配方式（raw 串不变时复用；名单一改才重建）
  -- 条目 = { v = 原文, mode = exact|prefix|fuzzy|auto, lv = 小写内容, num = spellID 或 nil }
  function pfUI.buff:ParseSepEntries(raw)
    -- ⛔ raw 可能是 nil（配置键缺失）：直接拿 nil 当表键写缓存会抛 table index is nil
    raw = raw or ""
    pfUI.buff.entrycache = pfUI.buff.entrycache or {}
    local hit = pfUI.buff.entrycache[raw]
    if hit then return hit end

    local entries = {}
    for v in string.gmatch(raw or "", "[^#;]+") do
      v = string.gsub(v, "^%s*(.-)%s*$", "%1")
      if v ~= "" then
        local mode, val = "auto", v
        local c = string.sub(v, 1, 1)
        if c == "=" then
          mode, val = "exact", string.sub(v, 2)
        elseif c == "^" then
          mode, val = "prefix", string.sub(v, 2)
        elseif c == "*" then
          mode, val = "fuzzy", string.sub(v, 2)
        end
        val = string.gsub(val, "^%s*(.-)%s*$", "%1")
        -- 只有前缀没有名字（比如单写一个「=」）当空条目丢掉，否则会命中所有光环
        if val ~= "" then
          entries[getn(entries)+1] = {
            v = v, mode = mode, val = val,
            lv = string.lower(val), num = tonumber(val),
          }
        end
      end
    end

    -- 缓存上限：GUI 里连续编辑名单会不断产生新 raw 串，别无限攒
    if (pfUI.buff.entrycachen or 0) > 32 then
      pfUI.buff.entrycache = {}
      pfUI.buff.entrycachen = 0
    end
    pfUI.buff.entrycachen = (pfUI.buff.entrycachen or 0) + 1
    pfUI.buff.entrycache[raw] = entries
    return entries
  end

  -- 单条目 vs 单光环判定。phase 1 = 精确/前缀/spellID，phase 2 = 子串
  -- ⛔ 两趟必须保留：模糊条目不能抢在精确条目前面占位（条目顺序就是显示顺序）
  function pfUI.buff:SepEntryMatch(e, lname, sid, defmode, phase)
    if not e then return false end
    if e.num then return phase == 1 and sid ~= nil and e.num == sid end
    if not lname then return false end
    local mode = e.mode
    if mode == "auto" then mode = defmode end

    if phase == 1 then
      if mode == "exact" or mode == "smart" then return lname == e.lv end
      if mode == "prefix" then return string.sub(lname, 1, string.len(e.lv)) == e.lv end
      return false
    end

    if mode == "fuzzy" or mode == "smart" then
      return string.find(lname, e.lv, 1, true) ~= nil
    end
    return false
  end

  -- 判断某个 aura 是否命中分离名单，返回命中的名单序号（用于固定显示顺序）
  -- 条目写法：名字 / =精确 / ^前缀 / *子串 / 纯数字 spellID
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

    local raw = isharm and C.buffs.sepdebufflist or C.buffs.separatelist
    local entries = pfUI.buff:ParseSepEntries(raw)
    if getn(entries) == 0 then return nil end

    local sid = pfUI.buff:GetBuffId(buff)
    local name = pfUI.buff:GetBuffName(buff)
    local lname = name and string.lower(name) or nil
    local defmode = pfUI.buff:SepMatchMode()

    for phase = 1, 2 do
      for i = 1, getn(entries) do
        if pfUI.buff:SepEntryMatch(entries[i], lname, sid, defmode, phase) then return i end
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
    -- ⛔ 计数必须与 SepIndex 用同一份解析结果：直接拆 raw 串会把「=」这类空条目也数进去，
    --    而 SepIndex 会丢掉它 ⇒ 名单序号与按钮序号错位（后一个光环顶到前一个槽位）
    local entries = pfUI.buff:ParseSepEntries(isharm and C.buffs.sepdebufflist or C.buffs.separatelist)
    local total = getn(entries)
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
          local gr, gg, gb = SepTint("debuff")
          btn.backdrop:SetBackdropBorderColor(gr, gg, gb, 1)
        else
          local gr, gg, gb = SepTint("buff")
          btn.backdrop:SetBackdropBorderColor(gr, gg, gb, 1)
        end
        btn:Show()
      else
        btn.bid = nil
        btn.mode = nil
        btn:SetAlpha(1)
        pfUI.buff:WarnGlowDrop(btn)
        btn:Hide()
      end
    end
    for i = total + 1, getn(container.buttons) do
      local btn = container.buttons[i]
      if btn and btn:IsShown() then
        btn.bid = nil
        btn.mode = nil
        btn:SetAlpha(1)
        pfUI.buff:WarnGlowDrop(btn)
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
        if string.lower(pfUI.buff:SepEntryLabel(v)) == string.lower(name) then
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
        -- ⛔ 本客户端 Lua 5.0 的 string 表没有 match ⇒ 用 find 的捕获（否则分享码导入一进来就抛错）
        local _, _, tag, payload = string.find(line, "^(%a+):(.*)$")
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

  -- /pfsep match ...、/pftsep match ... 共用：查看 / 切换监控名单的匹配模式
  -- 返回 true 表示这条命令已被吃掉（调用方直接 return）
  function pfUI.buff:HandleSepMatchCmd(trimmed)
    -- ⛔ 本客户端 Lua 5.0 的 string 表没有 match（只有全局 strmatch 别名）⇒ 走 find 的捕获
    local _, _, sub = string.find(string.lower(trimmed or ""), "^match%s*(%a*)$")
    if not sub then return false end
    if sub == "" then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 监控名单匹配模式 = " .. pfUI.buff:SepMatchMode())
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: exact = 精确（默认，狂热 不命中 狂热梦想） / smart = 先精确再子串（旧行为） / fuzzy = 只子串")
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 单个条目也可写 =名字（精确）/ ^名字（前缀）/ *名字（子串）；纯数字仍按 spellID")
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 切换用法 = /pfsep match exact 或 /pftsep match smart")
    else
      pfUI.buff:SetSepMatchMode(sub)
    end
    return true
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

    if pfUI.buff:HandleSepMatchCmd(trimmed) then return end

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

  -- ⚠️ 模块跑在 pfUI setfenv 环境里：裸写 `SLASH_XXX1 = "/cmd"` 只会写进 env 表，
  -- 引擎解析 /命令 时只查 _G 的 SLASH_xxx1 ⇒ 报"无效的命令"。必须显式写 _G。
  _G["SLASH_PFSEP1"] = "/pfsep"
  SlashCmdList["PFSEP"] = function(msg)
    pfUI.buff:HandleSepCmd(msg, false)
  end

  _G["SLASH_PFSEPDEB1"] = "/pfsepdeb"
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
  -- 目标版与玩家版共用同一套解析（ParseSepEntries），这里只是旧调用点的兼容壳
  function pfUI.buff:GetTargetSepEntries(isharm, raw)
    return pfUI.buff:ParseSepEntries(raw)
  end

  -- 判断目标光环是否命中目标分离名单，返回名单序号（固定显示顺序）
  -- 条目写法：名字 / =精确 / ^前缀 / *子串 / 纯数字 spellID（需 SuperWoW 扩展 UnitBuff/UnitDebuff）
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
    local entries = pfUI.buff:ParseSepEntries(raw)
    local defmode = pfUI.buff:SepMatchMode()

    for phase = 1, 2 do
      for idx = 1, getn(entries) do
        if pfUI.buff:SepEntryMatch(entries[idx], lname, sid, defmode, phase) then return idx end
      end
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
        if string.lower(pfUI.buff:SepEntryLabel(v)) == string.lower(name) then
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

    if pfUI.buff:HandleSepMatchCmd(trimmed) then return end

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

  _G["SLASH_PFTSEP1"] = "/pftsep"
  SlashCmdList["PFTSEP"] = function(msg)
    pfUI.buff:HandleTargetSepCmd(msg, false)
  end

  _G["SLASH_PFTSEPDEB1"] = "/pftsepdeb"
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
        btn.tl = slot.timeleft   -- 到期提醒的初值（随后由 OnUpdate 的 0.25s 轮询刷新为实时值）
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
        btn.tl = nil
        -- 隐藏的按钮不会再被 OnUpdate 重设颜色 ⇒ 这里必须把提醒状态一起清掉，
        -- 否则下次复用同一按钮时会保留上一轮的红色边框
        if btn.expwarn then
          btn.expwarn = nil
          pfUI.buff:WarnGlowClear(btn)
        end
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
        btn.tl = nil
        if btn.expwarn then
          btn.expwarn = nil
          pfUI.buff:WarnGlowClear(btn)
        end
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
      local gr, gg, gb = SepTint("debuff")
      btn.backdrop:SetBackdropBorderColor(gr, gg, gb, 1)
    else
      local gr, gg, gb = SepTint("buff")
      btn.backdrop:SetBackdropBorderColor(gr, gg, gb, 1)
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
  _G["SLASH_PFHIDE1"] = "/pfhide"
  SlashCmdList["PFHIDE"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "clear" then
      C.buffs.filter = "none"
      C.buffs.whitelist = ""
      C.buffs.blacklist = ""
      -- 兼容老存档里残留的独立 Debuff 三键（现在不再读取，清一下免得看着莫名其妙）
      C.buffs.debufffilter = nil
      C.buffs.debuffwhitelist = nil
      C.buffs.debuffblacklist = nil
      if pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 已清空黑白名单并关闭过滤（Buff / Debuff 共用这一组）")
      return
    end
    -- 名单只有一组、两行共用 ⇒ 只打印一次生效值，再分别打印两行的逐槽判定
    local mode, wl, bl = pfUI.buff:GetAuraFilter(nil)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 设置值 = " .. tostring(C.buffs.filter) .. "  →  生效模式 = " .. mode .. "（Buff / Debuff 共用）")
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 白名单 = " .. (wl ~= "" and wl or "(空)"))
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 黑名单 = " .. (bl ~= "" and bl or "(空)"))
    local groups = {
      { tag = "Buff",   container = pfUI.buff.buffs,   count = 32 },
      { tag = "Debuff", container = pfUI.buff.debuffs, count = 16 },
    }
    for _, g in ipairs(groups) do
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: ---- " .. g.tag .. " 槽位 ----")
      -- 逐个槽位打印「spellID + 判定结果」：被过滤掉的槽位 IsShown 就是 false，
      -- 只看 IsShown 永远看不到「为什么被藏掉」——排查白名单只能靠这张全量表。
      if g.container and g.container.buttons then
        for i = 1, g.count do
          local b = g.container.buttons[i]
          if b and type(b.bid) == "number" and b.mode == b.btype and GetPlayerBuffTexture(b.bid) then
            local sid = pfUI.buff:GetBuffId(b)
            local shown = pfUI.buff:AuraVisible(b)
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: slot " .. i .. "  ID=" ..
              (sid and tostring(sid) or "nil（解析不到 ⇒ 白名单下算未命中）") ..
              "  " .. (shown and "|cff55ff55显示|r" or "|cff888888隐藏|r"))
          end
        end
      end
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: Ctrl+左键 加白名单、Shift+左键 加黑名单（Buff / Debuff 图标写同一张名单）；/pfhide clear 清空")
  end

  -- /pfexpire : 到期提醒诊断。二分顺序 = 开关 → 分组门槛 → 图标是否真有边框 → 是否进入提醒窗口。
  -- 末列「最短剩余」是判定"阈值设太大/太小"的唯一依据：阈值以内才会闪。
  _G["SLASH_PFEXPIRE1"] = "/pfexpire"
  _G["SLASH_PFEXPIRE2"] = "/pfwarn"
  SlashCmdList["PFEXPIRE"] = function(msg)
    -- 每组各一套参数，诊断按组分别打印：拆开后"我改了颜色怎么还是原来的"十有八九是改错了组。
    local groups = {
      { tag = "右上角",   prefix = "expirewarnmain",      list = { pfUI.buff.buffs, pfUI.buff.debuffs, pfUI.buff.wepbuffs } },
      { tag = "自身Buff", prefix = "expirewarnsepbuff",   list = { pfUI.buff.sepbuffs } },
      { tag = "自身Debuff", prefix = "expirewarnsepdebuff", list = { pfUI.buff.sepdebuffs } },
      { tag = "目标区",   prefix = "expirewarnseptarget", list = { pfUI.buff.septargetbuffs, pfUI.buff.septargetdebuffs } },
    }

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 到期提醒 — 右上角=" .. tostring(C.buffs.expirewarnmain)
      .. "(" .. tostring(C.buffs.expirewarnmaindebuff) .. ")"
      .. " 自身Buff=" .. tostring(C.buffs.expirewarnsepbuff)
      .. " 自身Debuff=" .. tostring(C.buffs.expirewarnsepdebuff)
      .. " 目标区=" .. tostring(C.buffs.expirewarnseptarget)
      .. "(" .. tostring(C.buffs.expirewarnseptargetdebuff) .. ")"
      .. " 减益监控=" .. tostring(C.debuffmon and C.debuffmon.expirewarn)
      .. " libglow=" .. type(pfUI.api.libglow))

    for _, g in ipairs(groups) do
      local warnAt = tonumber(C.buffs[g.prefix .. "sec"]) or tonumber(C.buffs.expirewarnsec) or 5
      if warnAt < 1 then warnAt = 1 end
      DEFAULT_CHAT_FRAME:AddMessage("  " .. g.tag .. "参数: 阈值=" .. warnAt .. "s 样式="
        .. tostring(C.buffs[g.prefix .. "style"])
        .. " 颜色=" .. tostring(C.buffs[g.prefix .. "color"]))

      local shown, nobd, warn, armed, soon, soonleft = 0, 0, 0, 0, 0
      for _, c in ipairs(g.list) do
        if c and c.buttons then
          for i = 1, getn(c.buttons) do
            local b = c.buttons[i]
            if b and b:IsShown() then
              shown = shown + 1
              if not b.backdrop then nobd = nobd + 1 end
              if b.expwarn then warn = warn + 1 end
              if b.pfwarnset then
                for _, h in pairs(b.pfwarnset) do
                  if h:IsArmed() then armed = armed + 1 end
                end
              end
              -- 剩余时间：主行用原生 API，监控区用 0.25s 轮询写回的 tl
              -- ⛔ 必须先判 b.mode 非空：目标区按钮 mode/btype 都是 nil，nil==nil 为真会拿
              --    空槽去问 GetPlayerBuffTimeLeft（拿到 0，诊断就把"有 buff 在窗口里"漏报成 0）
              local tl
              if b.mode and b.mode == b.btype and b.bid then
                tl = GetPlayerBuffTimeLeft(b.bid, b.btype)
              elseif b.mode == "MAINHAND" or b.mode == "OFFHAND" then
                local _, mht, _, _, oht = GetWeaponEnchantInfo()
                tl = (b.mode == "MAINHAND") and (mht and mht / 1000) or (oht and oht / 1000)
              end
              tl = tl or b.tl
              if tl and tl > 0 and tl <= warnAt then soon = soon + 1 end
              if tl and tl > 0 and (not soonleft or tl < soonleft) then soonleft = tl end
            end
          end
        end
      end
      DEFAULT_CHAT_FRAME:AddMessage("    " .. g.tag .. ": 显示=" .. shown
        .. " 缺边框=" .. nobd
        .. " 已进窗口=" .. soon
        .. " 正在闪=" .. warn
        .. " arm=" .. armed
        .. " 最短剩余=" .. (soonleft and string.format("%.1f", soonleft) .. "s" or "-"))
    end
    if C.debuffmon then
      DEFAULT_CHAT_FRAME:AddMessage("  减益监控参数: 阈值=" .. tostring(C.debuffmon.expirewarnsec)
        .. "s 样式=" .. tostring(C.debuffmon.expirewarnstyle)
        .. " 颜色=" .. tostring(C.debuffmon.expirewarncolor) .. "（图标统计见 /pfdm warn）")
    end
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

  -- PERF: 所有 buff 计时统一交给 pfUI.api.libticker（0.1s 一拍）。
  -- 旧版是 pfUI.buff 自己挂 OnUpdate + 手写 GetTime 节流；现在节流由 driver 的 interval
  -- 承担，这里只保留"这一拍要做什么"。视觉节奏不变（仍是 10Hz，呼吸高亮同频）。
  -- ⛔ now 必须是本拍的实时时间：ExpireWarn 的到期判定和呼吸高亮相位都靠它，
  --    不能用 ticker 累计出来的 dt 代替（dt 只代表"距上一拍多久"）。
  local function BuffTimerTick()
    local now = GetTime()

    -- 目标分离区：图标/增删同步已改为事件驱动（unitframes 目标框 aura 刷新顺风车 OnTargetAuraRefresh），
    -- 这里只做倒计时文本的轻量节流刷新（仅遍历当前显示的按钮，通常个位数）
    if (C.buffs.separatetargetbuffs == "1" or C.buffs.separatetargetdebuffs == "1")
       and libdebuff and pfUI.buff.septargetdebuffs and pfUI.buff.septargetdebuffs.buttons then
      if not pfUI.buff.nextSepTimer or pfUI.buff.nextSepTimer <= now then
        pfUI.buff.nextSepTimer = now + 0.25
        local tbuttons = pfUI.buff.septargetdebuffs.buttons
        for i = 1, getn(tbuttons) do
          local btn = tbuttons[i]
          if btn:IsShown() and btn.aid then
            local dn, rank, dtex, dstacks, ddtype, ddur, dtl = libdebuff:UnitDebuff("target", btn.aid)
            -- 名字对得上才更新（索引漂移时丢弃文本，等下次事件刷新修正）
            if dn and dn ~= "" and btn.tname == dn and type(dtl) == "number" and dtl > 0 then
              btn.timer:SetText(GetColoredTimeString(dtl))
              btn.tl = dtl      -- 供到期提醒用（实时值，下面着色循环读取）
            else
              btn.timer:SetText("")
              btn.tl = nil
            end
          end
        end
        -- 目标 buff 区：同样每 0.25s 取一次剩余时间供到期提醒。
        -- ⛔ 原生 UnitBuff("target") 恒 nil，只能走 libdebuff:GetBuffSlot；
        --    一次 GetAuraSnapshot 喂所有按钮，不要在循环里反复取整份 aura 表。
        -- PERF: 两道闸门——① 目标区那组到期提醒关掉时整段不跑；② 快照「懒取」，名单全空/全隐藏时
        --       一次 GetUnitField 都不发（GetAuraSnapshot 会解码整份 48 项 aura 表）。
        -- ⛔ 闸门必须是**目标区那组**的开关（expirewarnseptarget），不是遗留的总开关 expirewarn：
        --    2026-11-19 起各组独立，拿总开关当闸门会让"关掉别组提醒"的人连带失去目标区提醒。
        local tbuffs = pfUI.buff.septargetbuffs
        if (C.buffs.expirewarnseptarget or C.buffs.expirewarnsep) == "1" and C.buffs.separatetargetbuffs == "1"
           and tbuffs and tbuffs.buttons and libdebuff.GetBuffSlot then
          local snap_auras, snap_apps, snap_taken
          local btns = tbuffs.buttons
          for i = 1, getn(btns) do
            local btn = btns[i]
            if btn:IsShown() then
              if btn.aid then
                if not snap_taken then
                  if libdebuff.GetAuraSnapshot then
                    snap_auras, snap_apps = libdebuff:GetAuraSnapshot("target")
                  end
                  snap_taken = 1
                end
                local bn, _, _, _, _, _, btl = libdebuff:GetBuffSlot("target", btn.aid, snap_auras, snap_apps)
                if bn and bn ~= "" and btn.tname == bn and type(btl) == "number" and btl > 0 then
                  btn.tl = btl
                else
                  btn.tl = nil
                end
              else
                btn.tl = nil
              end
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
        -- 到期提醒（剩余时间实时值来自 GetPlayerBuffTimeLeft）
        pfUI.buff:ExpireWarn(buff, timeleft, now)
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
        pfUI.buff:ExpireWarn(buff, timeleft, now)
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
          pfUI.buff:ExpireWarn(buff, timeleft, now)
        end
      end
    end

    -- Update separated (highlighted) buffs
    if C.buffs.separatebuffs == "1" and pfUI.buff.sepbuffs then
      -- unitframes 玩家框晚就绪时在这里补默认锚点（已锚/拖过则秒回）
      pfUI.buff:AnchorPlayerSep(pfUI.buff.sepbuffs, false)
      buttons = pfUI.buff.sepbuffs.buttons
      -- 呼吸高亮：边框在暗档 <-> 亮档之间循环，突出「重点显示」的 buff（基色可配）
      local pulse = C.buffs.sepbuffglow == "1" and (math.sin(now * 3) + 1) / 2 or 1
      local sgr, sgg, sgb = SepTint("buff")
      for i = 1, getn(buttons) do
        local buff = buttons[i]
        if buff:IsShown() and buff.bid then
          local timeleft = GetPlayerBuffTimeLeft(buff.bid, "HELPFUL")
          local stacks = GetPlayerBuffApplications(buff.bid, "HELPFUL")
          buff.timer:SetText(timeleft and timeleft > 0 and GetColoredTimeString(timeleft) or "")
          buff.stacks:SetText((tonumber(stacks) or 0) > 1 and stacks or "")
          if C.buffs.sepbuffglow == "1" then
            local gr, gg, gb = WarnLevel(sgr, sgg, sgb, .75 + .6 * pulse)
            buff.backdrop:SetBackdropBorderColor(gr, gg, gb, 1)
          else
            buff.backdrop:SetBackdropBorderColor(sgr, sgg, sgb, 1)
          end
          -- 到期提醒必须排在呼吸设色**之后**，否则同帧被呼吸色覆盖
          pfUI.buff:ExpireWarn(buff, timeleft, now)
        end
      end
    end

    -- Update separated (highlighted) debuffs —— 红色呼吸，比 buff 更醒目
    if C.buffs.separatedebuffs == "1" and pfUI.buff.sepdebuffs then
      -- unitframes 玩家框晚就绪时在这里补默认锚点（已锚/拖过则秒回）
      pfUI.buff:AnchorPlayerSep(pfUI.buff.sepdebuffs, true)
      buttons = pfUI.buff.sepdebuffs.buttons
      local pulse = C.buffs.sepdebuffglow == "1" and (math.sin(now * 3) + 1) / 2 or 1
      local dgr, dgg, dgb = SepTint("debuff")
      for i = 1, getn(buttons) do
        local buff = buttons[i]
        if buff:IsShown() and buff.bid then
          local timeleft = GetPlayerBuffTimeLeft(buff.bid, "HARMFUL")
          local stacks = GetPlayerBuffApplications(buff.bid, "HARMFUL")
          buff.timer:SetText(timeleft and timeleft > 0 and GetColoredTimeString(timeleft) or "")
          buff.stacks:SetText((tonumber(stacks) or 0) > 1 and stacks or "")
          if C.buffs.sepdebuffglow == "1" then
            local gr, gg, gb = WarnLevel(dgr, dgg, dgb, .75 + .6 * pulse)
            buff.backdrop:SetBackdropBorderColor(gr, gg, gb, 1)
          else
            buff.backdrop:SetBackdropBorderColor(dgr, dgg, dgb, 1)
          end
          pfUI.buff:ExpireWarn(buff, timeleft, now)
        end
      end
    end

    -- 目标分离区呼吸高亮（金/红，与玩家版同款）
    if C.buffs.separatetargetbuffs == "1" and pfUI.buff.septargetbuffs and pfUI.buff.septargetbuffs.buttons then
      local tpulse = C.buffs.septargetbuffglow == "1" and (math.sin(now * 3) + 1) / 2 or 1
      local tgr, tgg, tgb = SepTint("buff")
      for i = 1, getn(pfUI.buff.septargetbuffs.buttons) do
        local buff = pfUI.buff.septargetbuffs.buttons[i]
        if buff:IsShown() and buff.backdrop then
          if C.buffs.septargetbuffglow == "1" then
            local gr, gg, gb = WarnLevel(tgr, tgg, tgb, .75 + .6 * tpulse)
            buff.backdrop:SetBackdropBorderColor(gr, gg, gb, 1)
          else
            buff.backdrop:SetBackdropBorderColor(tgr, tgg, tgb, 1)
          end
          -- 目标分离区剩余时间由上面的 0.25s 轮询写进 btn.tl（事件驱动的槽位快照不会自己流逝）
          pfUI.buff:ExpireWarn(buff, buff.tl, now)
        end
      end
    end

    if C.buffs.separatetargetdebuffs == "1" and pfUI.buff.septargetdebuffs and pfUI.buff.septargetdebuffs.buttons then
      local tpulse = C.buffs.septargetdebuffglow == "1" and (math.sin(now * 3) + 1) / 2 or 1
      local tdr, tdg, tdb = SepTint("debuff")
      for i = 1, getn(pfUI.buff.septargetdebuffs.buttons) do
        local buff = pfUI.buff.septargetdebuffs.buttons[i]
        if buff:IsShown() and buff.backdrop then
          if C.buffs.septargetdebuffglow == "1" then
            local gr, gg, gb = WarnLevel(tdr, tdg, tdb, .75 + .6 * tpulse)
            buff.backdrop:SetBackdropBorderColor(gr, gg, gb, 1)
          else
            buff.backdrop:SetBackdropBorderColor(tdr, tdg, tdb, 1)
          end
          pfUI.buff:ExpireWarn(buff, buff.tl, now)
        end
      end
    end
  end

  -- 周期登记：pfUI.buff 创建后一直可见（模块里没有 Hide 调用），所以这是一个常驻订阅，
  -- 与旧版"永远有一个 OnUpdate 在跑"等价；区别只是入口收敛到统一 driver。
  local ticker = pfUI.api.libticker
  if not (ticker and ticker:Add("buff.timers", BuffTimerTick, 0.1)) then
    -- 退化路径：libticker 缺失或登记被拒（不应发生）时保留旧的手写节流，功能不能停摆
    local nextUpdate = 0
    pfUI.buff:SetScript("OnUpdate", function()
      local now = GetTime()
      if nextUpdate > now then return end
      nextUpdate = now + 0.1
      BuffTimerTick()
    end)
  end

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
