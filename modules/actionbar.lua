pfUI:RegisterModule("actionbar", "vanilla:tbc", function ()
  local _, class = UnitClass("player")
  local color = RAID_CLASS_COLORS[class]
  local cr, cg, cb = color.r , color.g, color.b
  local er, eg, eb, ea = GetStringColor(pfUI_config.appearance.border.color)

  local backdrop_highlight = { edgeFile = pfUI.media["img:glow"], edgeSize = 8 }
  local showgrid = 0
  local showgrid_pet = 0
  local rawborder, border = GetBorderSize("actionbars")
  local bpad = rawborder > 1 and border - GetPerfectPixel() or GetPerfectPixel()

  local eventcache = { } -- contains a list of events that shall be processed later -> [event] = true
  local updatecache = { } -- contains a list of buttons slots that shall be refreshed later -> [slot] = true
  local buttoncache = { } -- contains a list of all buttons ever created -> [slot] = frame
  local visibleButtons = { } -- cache of visible buttons to optimize range checks
  local lastCombatUpdate = 0 -- last time combat state was checked
  local inCombat = false -- current combat state
  local updateRate = 0.3 -- default update rate

  local petvisibility = "[pet] show; hide"

  -- try to assume based on the current mouse positions if a button drag
  -- should happen even if action-on-key-down is used. By that replace the
  -- cast events by reverting the active buttons to the old mouse-up state.
  local drag_await
  local drag_active
  local function AssumeButtonDrag()
    -- skip during combat
    if InCombatLockdown and InCombatLockdown() then return end

    -- skip if keydown press is not enabled
    if C.bars.keydown ~= "1" then return end

    -- skip if always shift-drag is not enabled
    if C.bars.shiftdrag ~= "1" then return end

    if drag_await and not drag_active and IsShiftKeyDown() then
      drag_active = true
      -- set all buttons to regular on release clicks
      for id, button in pairs(buttoncache) do
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      end
    elseif drag_active and not IsShiftKeyDown() then
      drag_active = nil
      -- set all buttons back to their defaults
      for id, button in pairs(buttoncache) do
        button:RegisterForClicks("LeftButtonDown", "RightButtonDown")
      end
    end
  end

  -- hide blizzard bars
  local function kill(f, killshow)
    if f.Show and killshow then f.Show = function() return end end
    if f.UnregisterAllEvents then f:UnregisterAllEvents() end
    if f.Hide then f:Hide() end
  end

  -- also abbreviate mouse buttons
  local OrigGetBindingText = GetBindingText
  local function GetBindingText(msg, mod, abbrev)
    local txt = OrigGetBindingText(msg, mod, abbrev)
    if abbrev then
      txt = string.gsub(txt, _G[string.format("%s%s", mod, "BUTTON3")], "MB3")
      txt = string.gsub(txt, _G[string.format("%s%s", mod, "BUTTON4")], "MB4")
      txt = string.gsub(txt, _G[string.format("%s%s", mod, "BUTTON5")], "MB5")
      txt = string.gsub(txt, _G[string.format("%s%s", mod, "MOUSEWHEELDOWN")], "MWD")
      txt = string.gsub(txt, _G[string.format("%s%s", mod, "MOUSEWHEELUP")], "MWU")
    end
    return txt
  end

  kill(MainMenuBar)

  local blizzard_elements = { MultiBarBottomLeft,
    MultiBarBottomRight, MultiBarLeft, MultiBarRight }
  for _, f in pairs(blizzard_elements) do
    kill(f, true)
  end

  -- enable all possible actionbar pages
  SetActionBarToggles(0, 0, 0, 0)
  _G.SHOW_MULTI_ACTIONBAR_1 = nil
  _G.SHOW_MULTI_ACTIONBAR_2 = nil
  _G.SHOW_MULTI_ACTIONBAR_3 = nil
  _G.SHOW_MULTI_ACTIONBAR_4 = nil

  -- events that provide special updater functions
  local special_events = {
    ["ACTIONBAR_UPDATE_COOLDOWN"] = true,
    ["ACTIONBAR_UPDATE_USABLE"] = true,
    ["ACTIONBAR_UPDATE_STATE"] = true,
  }

  -- events that are shared across all buttons
  local global_events = {
    -- slot/button updates
    ["PLAYER_ENTERING_WORLD"] = true,
    ["ACTIONBAR_SLOT_CHANGED"] = true,
    ["UPDATE_BINDINGS"] = true,
    ["ACTIONBAR_PAGE_CHANGED"] = true,
    ["UPDATE_BONUS_ACTIONBAR"] = true,
    -- 移除不必要的事件以降低功耗
    -- ["CRAFT_SHOW"] = true,      -- 移除：专业技能界面显示
    -- ["CRAFT_CLOSE"] = true,     -- 移除：专业技能界面关闭
    -- ["TRADE_SKILL_SHOW"] = true, -- 移除：交易技能界面显示
    -- ["TRADE_SKILL_CLOSE"] = true, -- 移除：交易技能界面关闭
    ["PLAYER_ENTER_COMBAT"] = true,
    ["PLAYER_LEAVE_COMBAT"] = true,
    -- cooldown updates
    ["UNIT_INVENTORY_CHANGED"] = true,
    -- auto repeat action
    ["START_AUTOREPEAT_SPELL"] = true,
    ["STOP_AUTOREPEAT_SPELL"] = true,
  }

  -- events that are used for the aura/shapeshift bar
  local aura_events = {
    ["UPDATE_SHAPESHIFT_FORMS"] = true,
    ["PLAYER_AURAS_CHANGED"] = true,
  }

  -- events that are used for the pet bar
  local pet_events = {
    -- ["PLAYER_CONTROL_LOST"] = true,    -- 移除：玩家失去控制（不常用）
    -- ["PLAYER_CONTROL_GAINED"] = true,   -- 移除：玩家获得控制（不常用）
    -- ["PLAYER_FARSIGHT_FOCUS_CHANGED"] = true, -- 移除：远视焦点变化（不常用）
    ["UNIT_PET"] = true,
    ["PET_BAR_UPDATE"] = true,
    ["PET_BAR_UPDATE_COOLDOWN"] = true,
  }

  local buttontypes = {
    -- blizzard keybinds
    [3] = "MULTIACTIONBAR3BUTTON",
    [4] = "MULTIACTIONBAR4BUTTON",
    [5] = "MULTIACTIONBAR2BUTTON",
    [6] = "MULTIACTIONBAR1BUTTON",
    [11] = "SHAPESHIFTBUTTON",
    [12] = "BONUSACTIONBUTTON",
    -- additional keybinds
    [2] = "PFPAGING",
    [7] = "PFSTANCEONE",
    [8] = "PFSTANCETWO",
    [9] = "PFSTANCETHREE",
    [10] = "PFSTANCEFOUR",
  }

  local blizzbarmapping = {
    ["MultiBarRight"] = 3,
    ["MultiBarLeft"] = 4,
    ["MultiBarBottomRight"] = 5,
    ["MultiBarBottomLeft"] = 6,
    ["ShapeShiftBar"] = 11,
    ["BonusActionBar"] = 12,
  }

  local barnames = {
    [1] = "Main",
    [2] = "Paging",
    [3] = "Right",
    [4] = "Vertical",
    [5] = "Left",
    [6] = "Top",
    [7] = "StanceBar1",
    [8] = "StanceBar2",
    [9] = "StanceBar3",
    [10] = "StanceBar4",
    [11] = "Stances",
    [12] = "Pet",
  }

  local button_animations = {
    ["none"] = function()
      this.active = nil
      this:Hide()
    end,
    ["zoomfade"] = function()
      if this.active == 0 then
        -- init animation
        this:SetWidth(this.parent:GetWidth())
        this:SetHeight(this.parent:GetHeight())
        this:SetScale(this.parent:GetScale())
        this.tex:SetTexture(this.parent.icon:GetTexture())
        this.tex:SetVertexColor(this.parent.icon:GetVertexColor())
        this:SetAlpha(1)
        this.active = 1
        return
      elseif this.active == 1 then
        -- run animation
        local fade = 30/GetFramerate()*0.05
        this:SetAlpha(this:GetAlpha() - fade)
        this:SetScale(this:GetScale() + fade)
        if this:GetAlpha() > 0 then return end
      end

      -- stop animation
      this.active = nil
      this:Hide()
    end,
    ["shrinkreturn"] = function()
      if this.active == 0 then
        -- init animation
        this:SetWidth(this.parent:GetWidth())
        this:SetHeight(this.parent:GetHeight())
        this:SetScale(this.parent:GetScale())
        this.tex:SetTexture(this.parent.icon:GetTexture())
        this.tex:SetVertexColor(this.parent.icon:GetVertexColor())
        this:SetAlpha(1)
        this.parent.icon:Hide()
        this.active = 1
        this.time = 0
        return
      elseif this.active == 1 then
        -- run animation
        this.time = this.time + 30/GetFramerate()*0.1
        local fade = 1 -math.exp(-this.time)*math.sin(this.time*math.pi)
        this:SetAlpha(fade)
        this:SetScale(fade)
        if this.time < 1 then return end
      end

      -- stop animation
      this.active = nil
      this:Hide()
      this.parent.icon:Show()
    end,
    ["elasticzoom"] = function()
      if this.active == 0 then
        -- init animation
        this:SetWidth(this.parent:GetWidth())
        this:SetHeight(this.parent:GetHeight())
        this:SetScale(this.parent:GetScale())
        this.tex:SetTexture(this.parent.icon:GetTexture())
        this.tex:SetVertexColor(this.parent.icon:GetVertexColor())
        this:SetAlpha(1)
        this.parent.icon:Hide()
        this.active = 1
        this.time = 0
        return
      elseif this.active == 1 then
        -- run animation
        this.time = this.time + 30/GetFramerate()*0.03
        local fade = 1 -math.exp(-this.time*6)*math.sin(this.time*4*math.pi)
        this:SetAlpha(fade)
        this:SetScale(fade)
        if this.time < 1 then return end
      end

      -- stop animation
      this.active = nil
      this:Hide()
      this.parent.icon:Show()
    end,
    ["wobblezoom"] = function()
      if this.active == 0 then
        -- init animation
        this:SetWidth(this.parent:GetWidth())
        this:SetHeight(this.parent:GetHeight())
        this:SetScale(this.parent:GetScale())
        this.tex:SetTexture(this.parent.icon:GetTexture())
        this.tex:SetVertexColor(this.parent.icon:GetVertexColor())
        this:SetAlpha(1)
        this.parent.icon:Hide()
        this.active = 1
        this.time = 0
        return
      elseif this.active == 1 then
        -- run animation
        this.time = this.time + 30/GetFramerate()*0.02
        local fade = 1 -math.exp(-this.time*6)*math.sin(this.time*10*math.pi)
        this:SetAlpha(fade)
        this:SetScale(fade)
        if this.time < 1 then return end
      end

      -- stop animation
      this.active = nil
      this:Hide()
      this.parent.icon:Show()
    end,
  }

  local function GetActiveBar()
    if CURRENT_ACTIONBAR_PAGE == 1 and GetBonusBarOffset() ~= 0 then
      return NUM_ACTIONBAR_PAGES + GetBonusBarOffset()
    else
      return CURRENT_ACTIONBAR_PAGE
    end
  end

  local function ButtonDrag(self)
    -- skip during combat
    if InCombatLockdown and InCombatLockdown() then return end

    local self = self or this

    if _G.LOCK_ACTIONBAR == "1" and not (pfUI_config.bars.shiftdrag == "1" and IsShiftKeyDown()) then return end

    if self.bar == 12 then
      PickupPetAction(self.id)
    else
      PickupAction(self.id)
    end
  end

  local function ButtonDragStop(self)
    -- skip during combat
    if InCombatLockdown and InCombatLockdown() then return end

    local self = self or this

    if MacroFrame_SaveMacro then
      MacroFrame_SaveMacro()
    end

    if self.bar == 12 then
      PickupPetAction(self.id)
    else
      PlaceAction(self.id)
    end
  end

  local mouse
  local function ButtonAnimate(self)
    local self = self or this
    mouse = arg1 and not keystate

    -- trigger action animation
    if ( pfUI_config.bars.keydown == "1" and keystate == "down" ) or (pfUI_config.bars.keydown == "0" and keystate == "up" ) or self.bar == 11 or mouse then
      if C.bars.animmode == "keypress" and ( self:GetAlpha() > .1  or C.bars.animalways == "1" ) then
        self.animation.active = 0
        self.animation:Show()
      end
    end

    -- handle button highlight
    if keystate == "down" then
      self.highlight:Show()
    elseif not MouseIsOver(self) then
      self.highlight:Hide()
    end
  end

  local function ButtonClick(self)
    local self = self or this

    local grid = self.bar == 12 and showgrid_pet or showgrid
    local mouse = arg1 and not keystate
    local keystate = keystate
    local slfcast = C.bars.altself == "1" and IsAltKeyDown() and true or self.slfcast
    slfcast = C.bars.rightself == "1" and arg1 and arg1 == "RightButton" and true or slfcast
    self.slfcast = nil

    -- 动作条监控：Alt+左键把槽位加入/移出监控名单（图标拖放模式 grid=1 时放行，不干扰拖技能）
    -- 锁定（monitorlock=1）时不拦截，保留 Alt 原有功能（如 altself 自施法）
    if C.bars.monitorenable == "1" and C.bars.monitorlock ~= "1" and mouse and arg1 == "LeftButton" and IsAltKeyDown()
      and grid == 0 and self.bar and self.bar <= 10 and pfUI.bars and pfUI.bars.ToggleMonitorSlot then
      pfUI.bars:ToggleMonitorSlot(self.id)
      return
    end

    if ( pfUI_config.bars.keydown == "1" and keystate == "down" and not drag_active ) or (pfUI_config.bars.keydown == "0" and keystate == "up" or drag_active ) or self.bar == 11 or mouse then
      if self.bar == 11 then
        CastShapeshiftForm(self.id)
      elseif grid == 1 then
        if self.bar == 12 then
          PickupPetAction(self.id)
        else
          PickupAction(self.id)
        end
      elseif self.bar == 12 then
        if arg1 == "LeftButton" then
          if IsPetAttackActive(self.id) then
            PetStopAttack()
          else
            CastPetAction(self.id)
          end
        else
          TogglePetAutocast(self.id)
        end
      else
        if MacroFrame_SaveMacro then
          MacroFrame_SaveMacro()
        end

        UseAction(self.id, nil, slfcast)
      end
    end
  end

  -- 添加时间节流常量（降低功耗）
  local MACRO_SCAN_INTERVAL = 1.0 -- 从0.5增加到1.0以降低功耗
  
  local function ButtonMacroScan(self)
    if self.bar > 10 then return end
    if not self.scanmacro then return end
    if pfUI.bars.skip_macro then return end
    
    -- 时间节流：限制宏扫描频率
    local currentTime = GetTime()
    if self.lastMacroScan and currentTime - self.lastMacroScan < MACRO_SCAN_INTERVAL then
      return
    end
    self.lastMacroScan = currentTime

    local macro = GetActionText(self.id)
    self.spellslot = nil
    self.booktype = nil
    if macro then
      local slot = GetMacroIndexByName(macro)
      local name, _, body = GetMacroInfo(slot)

      if name and body then
        local match

        for line in gfind(body, "[^%\n]+") do
          _, _, match = string.find(line, '^#showtooltip (.+)')

          -- skip any further manual macro scanning on
          -- gameclients with native macro spell detection
          if pfUI.client > 11200 and match then
            self.spellslot = nil
            self.booktype = nil
            return
          end

          -- allow the user to disable the scan
          if match and strfind(match, "disable") then
            return
          end

          if not match then
            -- add support to specify custom tooltips via:
            --  /run --showtooltip SPELLNAME
            _, _, match = string.find(line, '%-%-showtooltip (.+)')
          end

          if not match then
            _, _, match = string.find(line, '^/cast (.+)')
          end

          if not match then
            _, _, match = string.find(line, '^/pfcast (.+)')
          end

          if not match then
            _, _, match = string.find(line, '^/pfmouse (.+)')
          end

          if not match then
            _, _, match = string.find(line, 'CastSpellByName%(%"(.+)%"%)')
          end

          if match then
            local _, _, spell, rank = string.find(match, '(.+)%((.+)%)')
            spell = spell or match
            self.spellslot, self.booktype = libspell.GetSpellIndex(spell, rank)

            if self.spellslot and self.spellslot > 0 then return end
          end
        end
      end
    end
  end

  local function ButtonEnter(self)
    local self = self or this

    -- indicate that dragging could get enabled
    drag_await = true

    GameTooltip:ClearLines()
    GameTooltip_SetDefaultAnchor(GameTooltip, self)

    if self.bar == 11 then
      GameTooltip:SetShapeshift(self.id)
    elseif self.bar == 12 then
      local name, _, _, token = GetPetActionInfo(self.id)
      if token then
        GameTooltip:AddLine(_G[name])
        GameTooltip:Show()
      else
        GameTooltip:SetPetAction(self.id)
      end
    elseif self.spellslot and self.booktype then
      GameTooltip:SetSpell(self.spellslot, self.booktype)
    else
      GameTooltip:SetAction(self.id)
    end

    self.highlight:Show()
  end

  local function ButtonLeave(self)
    local self = self or this

    -- no longer wait for a drag event
    drag_await = nil

    self.highlight:Hide()
    GameTooltip:Hide()
  end

  local start, duration, enable, castable, autocast, token
  local grid, sid, id, bar, active, texture, _
  local function ButtonSlotUpdate(self)
    if not self then return end
    local self = self or this
    sid = self.id -- 1 to 120

    -- reset shared variables
    castable, autocast, token = nil, nil, nil

    -- set the own ID for compatibility to some vanilla addons
    if pfUI.client <= 11200 then self:SetID(self.id) end

    grid = self.bar == 12 and showgrid_pet or showgrid

    if self.bar == 11 then
      -- stance button
      bar = self.bar
      id = sid
      texture, _, active = GetShapeshiftFormInfo(id)
    elseif self.bar == 12 then
      -- pet button
      bar = self.bar
      id = sid
      _, _, texture, token, active, castable, autocast = GetPetActionInfo(id)
      texture = token and _G[texture] or texture
    else
      active = IsCurrentAction(sid) or IsAutoRepeatAction(sid)
      texture = GetActionTexture(sid)
      bar = GetActiveBar()
      id = self.bar == 1 and self.slot or sid-((self.bar)-1)*12
    end

    -- overwrite with spell macro texture where possible
    if self.spellslot and self.booktype then
      texture = GetSpellTexture(self.spellslot, self.booktype)
    end

    if not self.showempty and self.backdrop and not texture and grid == 0 then
      self.backdrop:Hide()
      self.hide = true
    else
      self.backdrop:Show()
      self.hide = nil
    end

    -- active border
    if active then
      if C.bars.animmode == "statechange" and not self.active:IsShown() then
        self.animation.active = 0
        self.animation:Show()
      end

      self.backdrop:SetBackdropBorderColor(cr,cg,cb,1)
      self.active:Show()
    else
      self.backdrop:SetBackdropBorderColor(er,eg,eb,ea)
      self.active:Hide()
    end

    if self.bar == 11 then
      -- stance button: show reagent item count (cache filled by reagent counter below)
      local sreagents = pfUI.bars and pfUI.bars.stancereagents
      local sname = sreagents and sreagents[self.id]
      self.count:SetText(sname and pfUI.bars.stancereagentcounts[sname] or nil)
    elseif self.bar ~= 12 then
      -- update consumables
      if IsConsumableAction(sid) then
        self.count:SetText(GetActionCount(sid))
      elseif IsReagentAction and IsReagentAction(sid) then
        self.count:SetText(GetReagentCount(sid))
      else
        self.count:SetText(nil)
      end

      -- equipped item
      if IsEquippedAction(sid) and C.bars.showequipped == "1" then
        self.equipped:Show()
      else
        self.equipped:Hide()
      end

      -- update macro text
      if C.bars["bar"..self.bar] and C.bars["bar"..self.bar].showmacro == "1" then
        self.macro:SetText(GetActionText(sid))
      else
        self.macro:SetText("")
      end
    end

    -- icon
    if texture ~= self.texture then
      self.icon:SetTexture(texture)
      self.texture = texture
    end

    -- handle pet bar quirks
    if self.bar == 12 then
      -- desaturate disabled petbar
      self.icon:SetDesaturated(not GetPetActionsUsable())

      -- display autocast
      if autocast then
        self.autocast:Show()
        self.autocast:SetAlpha(self:GetAlpha() * 0.10)
      else
        self.autocast:Hide()
      end

      if castable and C.bars.showcastable == "1" then
        self.autocastable:Show()
      else
        self.autocastable:Hide()
      end
    end

    -- keybinds
    if not self.hide and self.bar == 1 and self.bar ~= 11 and self.bar ~= 12 then
      self.keybind:SetText(GetBindingText(GetBindingKey("ACTIONBUTTON"..id), "KEY_", 1))
    elseif not self.hide and buttontypes[self.bar] then
      self.keybind:SetText(GetBindingText(GetBindingKey(buttontypes[self.bar]..id), "KEY_", 1))
    else
      self.keybind:SetText("")
    end
  end

  local sid, usable, oom, _
  local function ButtonUsableUpdate(self)
    local self = self or this
    sid = self.id -- 1 to 120

    if self.bar == 11 then
      _, _, _, usable = GetShapeshiftFormInfo(sid)
    elseif self.bar == 12 then
      usable = true
    else
      usable, oom = IsUsableAction(sid)
    end

    -- update usable [out-of-range = 1, oom = 2, not-usable = 3, default = 0]
    if self.outofrange and C.bars.glowrange == "1" then
      if self.vertexstate ~= 1 then
        self.icon:SetVertexColor(self.rangeColor[1], self.rangeColor[2], self.rangeColor[3], self.rangeColor[4])
        self.vertexstate = 1
      end
    elseif oom and C.bars.showoom == "1" then
      if self.vertexstate ~= 2 then
        self.icon:SetVertexColor(self.oomColor[1], self.oomColor[2], self.oomColor[3], self.oomColor[4])
        self.vertexstate = 2
      end
    elseif not usable and C.bars.showna == "1" then
      if self.vertexstate ~= 3 then
        self.icon:SetVertexColor(self.naColor[1], self.naColor[2], self.naColor[3], self.naColor[4])
        self.vertexstate = 3
      end
    else
      if self.vertexstate ~= 0 then
        self.icon:SetVertexColor(1, 1, 1, 1)
        self.vertexstate = 0
      end
    end
  end

  -- 优化的按钮范围检查函数
  local rangeCheckCache = {}
  local lastRangeCheck = 0
  local RANGE_CHECK_INTERVAL = 0.2 -- 范围检查的最小间隔（从0.1增加到0.2以降低功耗）
  
  local function ButtonRangeUpdate(self)
    local self = self or this
    
    -- 如果范围显示功能关闭，直接返回
    if C.bars.glowrange ~= "1" then
      if self.outofrange then
        self.outofrange = nil
        ButtonUsableUpdate(self)
      end
      return
    end
    
    -- 跳过姿态栏和宠物栏
    if self.bar == 11 or self.bar == 12 then return end
    
    -- 优化：添加时间节流
    local currentTime = GetTime()
    if not self.lastRangeCheck or currentTime - self.lastRangeCheck < RANGE_CHECK_INTERVAL then
      return
    end
    self.lastRangeCheck = currentTime
    
    -- 检查动作是否存在且有范围限制
    if HasAction(self.id) and ActionHasRange(self.id) then
      -- 使用缓存优化频繁调用
    
      local currentRangeState = IsActionInRange(self.id)
      
      if currentRangeState == 0 then
        if not self.outofrange then
          self.outofrange = true
          ButtonUsableUpdate(self)
        end
      elseif self.outofrange then
        self.outofrange = nil
        ButtonUsableUpdate(self)
      end
    elseif self.outofrange then
      self.outofrange = nil
      ButtonUsableUpdate(self)
    end
  end

  local start, duration, enable
  local function ButtonCooldownUpdate(button)
    if not button then return end

    if button.bar == 11 then
      start, duration, enable = GetShapeshiftFormCooldown(button.id)
    elseif button.bar == 12 then
      start, duration, enable = GetPetActionCooldown(button.id)
    elseif button.spellslot and button.booktype then
      start, duration = GetSpellCooldown(button.spellslot, button.booktype)
      enable = 1
    else
      start, duration, enable = GetActionCooldown(button.id)
    end

    CooldownFrame_SetTimer(button.cd, start, duration, enable)
  end

  local _, active
  local function ButtonIsActiveUpdate(button)
    if not button then return end

    if button.bar == 11 then
      _, _, active, _ = GetShapeshiftFormInfo(button.id)
    elseif button.bar == 12 then
      _, _, _, _, active, _, _ = GetPetActionInfo(button.id)
    else
      active = IsCurrentAction(button.id) or IsAutoRepeatAction(button.id)
    end

    -- active border
    if active then
      if not button.border_active then
        button.backdrop:SetBackdropBorderColor(cr,cg,cb,1)
        button.border_active = true
      end

      button.active:Show()
    else
      if button.border_active then
        button.backdrop:SetBackdropBorderColor(er,eg,eb,ea)
        button.border_active = nil
      end

      button.active:Hide()
    end
  end


  -- 更新可见按钮的缓存
  local function UpdateVisibleButtonsCache()
    -- 清空当前缓存
    for k in pairs(visibleButtons) do visibleButtons[k] = nil end
    
    -- 只缓存可见的按钮
    for id, button in pairs(buttoncache) do
      if button:IsShown() then
        visibleButtons[id] = button
      end
    end
  end

  -- 优化的按钮完全更新函数
  local function ButtonFullUpdate(button)
    if not button or not button:IsShown() then return end
    
    -- 优先检查是否需要更新宏扫描（相对不频繁）
    if C.bars.macroscan == "1" then
      ButtonMacroScan(button)
    end
    
    -- 基础更新
    ButtonSlotUpdate(button)
    
    -- 范围和可用性检查
    if button.bar ~= 11 and button.bar ~= 12 then
      ButtonUsableUpdate(button)
      
      -- 更新范围检查的时间戳，确保下一帧会进行范围检查
      button.lastRangeCheck = 0
    end
    
    -- 冷却和激活状态检查
    ButtonCooldownUpdate(button)
    ButtonIsActiveUpdate(button)
  end

  -- 优化的事件处理函数
  local function BarsEvent(self)
    local self = self or this

    -- 刷新特定槽位
    if event == "ACTIONBAR_SLOT_CHANGED" and arg1 and arg1 ~= 0 then
      updatecache[arg1] = true
      return
    end

    -- 运行特殊刷新函数
    if special_events[event] then
      eventcache[event] = true
      return
    end

    -- 处理光环事件
    if aura_events[event] then
      if self[11] then
        for j=1,12 do
          if self[11][j] and self[11][j]:IsShown() then
            updatecache[self[11][j].slot] = true
          end
        end
      end
      return
    end

    -- 处理宠物事件
    if pet_events[event] then
      if self[12] then
        for j=1,12 do
          if self[12][j] and self[12][j]:IsShown() then
            updatecache[self[12][j].slot] = true
          end
        end
      end
      return
    end

    -- 优化全局事件处理：只更新可见按钮
    if event == "PLAYER_ENTERING_WORLD" or event == "ACTIONBAR_PAGE_CHANGED" then
      UpdateVisibleButtonsCache()
    end
    
    for id, button in pairs(visibleButtons) do
      updatecache[id] = true
    end
  end



    -- 优化的更新频率变量（降低功耗）
  local updateFrequency = {
    combat = 0.15, -- 战斗中的更新频率
    normal = 0.4,  -- 正常状态的更新频率（从0.3增加到0.4）
    idle = 1.0     -- 空闲状态的更新频率（从0.5增加到1.0）
  }
  
  -- 检查玩家是否在战斗中
  local function IsPlayerInCombat()
    if InCombatLockdown and InCombatLockdown() then return true end
    return UnitAffectingCombat("player")
  end
  
  -- 魔兽世界 1.12 兼容的鼠标按钮检测函数
  local function IsMouseButtonDown(button)
    -- 在魔兽世界 1.12 中，可以使用 arg1 来检测鼠标按钮状态
    -- 这个函数用于替换不存在的 IsMouseButtonDown API
    if button == "LeftButton" then
      return arg1 == "LeftButton"
    elseif button == "RightButton" then
      return arg1 == "RightButton"
    elseif button == "MiddleButton" then
      return arg1 == "MiddleButton"
    elseif button == "Button4" then
      return arg1 == "Button4"
    elseif button == "Button5" then
      return arg1 == "Button5"
    end
    return false
  end

  -- 魔兽世界 1.12 兼容的施法检测函数
  local function IsPlayerCasting()
    -- 在魔兽世界 1.12 中，可以通过检查玩家状态来检测是否正在施法
    -- 使用 UnitCastingInfo 或 UnitChannelInfo 来检测施法状态
    local casting = UnitCastingInfo("player")
    local channeling = UnitChannelInfo("player")
    return casting ~= nil or channeling ~= nil
  end

  -- 检查玩家是否在移动中（用于进一步优化）
  local function IsPlayerMoving()
    -- 魔兽世界 1.12 中检测玩家移动的简化方法
    -- 通过检查常见移动键是否被按下
    local moving = IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()
    -- 如果正在施法，则认为不在移动（施法时不能移动）
    if IsPlayerCasting() then
      return false
    end
    return moving
  end
  

  local function BarsUpdate(self)
    self = self or this
    
    -- 更新按钮拖动状态
    AssumeButtonDrag()

    -- 检查解锁状态
    if pfUI.unlock then
      if pfUI.unlock:IsShown() ~= unlock then
        pfUI.bars:UpdateConfig()
        unlock = pfUI.unlock:IsShown()
        -- 解锁状态变化时更新可见按钮缓存
        UpdateVisibleButtonsCache()
      end
    end

    -- 处理缓存的事件
    if eventcache["ACTIONBAR_UPDATE_USABLE"] then
      eventcache["ACTIONBAR_UPDATE_USABLE"] = nil
      for id, button in pairs(buttoncache) do
        if button:IsShown() then -- 只更新可见按钮
          ButtonUsableUpdate(button)
        end
      end
    end

    if eventcache["ACTIONBAR_UPDATE_COOLDOWN"] then
      eventcache["ACTIONBAR_UPDATE_COOLDOWN"] = nil
      for id, button in pairs(buttoncache) do
        if button:IsShown() then -- 只更新可见按钮
          ButtonCooldownUpdate(button)
        end
      end
    end

    if eventcache["ACTIONBAR_UPDATE_STATE"] then
      eventcache["ACTIONBAR_UPDATE_STATE"] = nil
      for id, button in pairs(buttoncache) do
        if button:IsShown() then -- 只更新可见按钮
          ButtonIsActiveUpdate(button)
        end
      end
    end

    -- 处理按钮更新缓存
    for id in pairs(updatecache) do
      local button = buttoncache[id]
      if button and button:IsShown() then -- 只更新可见按钮
        pfUI.bars.ButtonFullUpdate(button)
        
        -- 处理分页动作条的更新
        if button.bar == 1 then
          for i=1,12 do
            if pfUI.bars[1][i].id == id then
              pfUI.bars.ButtonFullUpdate(pfUI.bars[1][i])
            end
          end
        end
      end
      -- 清除更新缓存
      updatecache[id] = nil
    end

    -- 根据战斗状态调整更新频率
    if GetTime() - lastCombatUpdate > 1 then -- 每秒检查一次战斗状态
      inCombat = IsPlayerInCombat()
      lastCombatUpdate = GetTime()
    end
    
    -- 根据当前状态选择更新频率
    if inCombat then
      updateRate = updateFrequency.combat
    else
      -- 检查是否有目标，没有目标则使用更慢的更新频率
      if not UnitExists("target") then
        updateRate = updateFrequency.idle
        -- 如果没有目标且玩家不在移动或施法中，使用更低的更新频率
        if not IsPlayerMoving() and not IsPlayerCasting() then
          updateRate = updateFrequency.idle * 1.5 -- 进一步降低更新频率
        end
      else
        updateRate = updateFrequency.normal
        -- 如果有目标但玩家不在移动或施法中，使用中等更新频率
        if not IsPlayerMoving() and not IsPlayerCasting() then
          updateRate = updateFrequency.normal * 1.2
        end
      end
    end
    
    -- 控制更新频率
    if (this.tick or 0) > GetTime() then return else this.tick = GetTime() + updateRate end

    -- 只更新可见按钮的范围检查
    for id, button in pairs(visibleButtons) do
      if button:IsShown() then
        ButtonRangeUpdate(button)
      end
    end
  end

  -- create the main event and update handler for pfUI actionbars
  local bars = CreateFrame("Frame", "pfActionBar", UIParent)
  for event in pairs(special_events) do bars:RegisterEvent(event) end
  for event in pairs(global_events) do bars:RegisterEvent(event) end
  for event in pairs(aura_events) do bars:RegisterEvent(event) end
  for event in pairs(pet_events) do bars:RegisterEvent(event) end

  -- refresh actionbar buttons on event
  bars:SetScript("OnEvent", BarsEvent)

  -- update actionbar buttons
  bars:SetScript("OnUpdate", BarsUpdate)

  -- enable bar paging via secure functions
  local function ButtonSwitch(self, att, value)
    if att == "state-parent" then
      local action = SecureButton_GetModifiedAttribute(self, "action", SecureStateChild_GetEffectiveButton(self)) or self.id
      if self.id == action then return end
      updatecache[self.slot] = true
      self.id = action
    end
  end

  local function EnablePaging(bar)
    if pfUI.client <= 11200 then
      if not bar.pager then
        bar.pager = CreateFrame("Frame")
        bar.pager:RegisterEvent("PLAYER_ENTERING_WORLD")
        bar.pager:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
        bar.pager:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
        bar.pager:SetScript("OnEvent", function()
          for i=1, 10 do -- reload pageable bars
            local pageable = C.bars["bar"..i] and C.bars["bar"..i].pageable == "1" and true or nil
            _G.VIEWABLE_ACTION_BAR_PAGES[i] = pageable
          end

          local active = GetActiveBar()
          for i=1,12 do
            local id = i + (active-1)*12
            bar[i].id = id
            updatecache[i] = true
          end
        end)
      end
    else
      -- append paging enabled bars to the filter list
      for i=1,12 do bar[i]:SetScript("OnAttributeChanged", ButtonSwitch) end

      -- fill all possible page states
      local page, pages = nil, {}
      while not pages[6] do
        for i=1, 6 do
          page = i == 1 and 1 or C.bars["bar"..i] and C.bars["bar"..i].pageable == "1" and i
          if page then table.insert(pages, page) end
        end
      end

      bar:SetAttribute("statemap-page", "$input")
      bar:SetAttribute("state", (bar:GetAttribute("state-page") or 1))

      -- prio posses bar
      bar.filter = "[bonusbar: 5] 11;"

      -- set bar 8 for druid stealth if enabled
      local prowl = class == "DRUID" and C.bars["druidstealth"] == "1" and "8" or "7"

      -- write default pages
      for state, page in pairs(pages) do
        if page ~= 1 then -- skip page 1 as it is supposed to stay dynamic for stances
          bar.filter = string.format("%s[actionbar: %s] %s; ", bar.filter, state, page)
        end
      end

      -- write page driver conditions
      bar.filter = string.format("%s[bonusbar:1,nostealth] 7; [bonusbar:1,stealth] %s; [bonusbar:2] 10; [bonusbar:3] 9; [bonusbar:4] 10; 1", bar.filter, prowl)

      -- prepend pagemaster states if enabled
      if C.bars.pagemaster == "1" then
        for mod, page in pairs({ ["shift"] = "6", ["ctrl"] = "5", ["alt"] = "3" }) do
          bar.filter = string.format("[modifier:%s] %s;", mod, page) .. bar.filter
        end
      end

      -- enable page driver conditions
      RegisterStateDriver(bar, "page", bar.filter)
      SecureStateHeader_Refresh(bar)
    end
  end

  local function SwitchBar(bar)
    if _G.CURRENT_ACTIONBAR_PAGE ~= bar then
      _G.CURRENT_ACTIONBAR_PAGE = bar
      
      -- 动作条切换时立即停止所有动画并强制更新图标
      for id, button in pairs(buttoncache) do
        if button and button.animation then
          -- 立即停止动画
          button.animation.active = nil
          button.animation:Hide()
          
          -- 强制显示图标
          if button.icon then
            button.icon:Show()
          end
          
          -- 立即更新按钮内容（不等待下一次更新循环）
          if button:IsShown() then
            pfUI.bars.ButtonFullUpdate(button)
          end
        end
      end
      
      ChangeActionBarPage(bar)
    end
  end

  local cat, stealth
  local function IsCatStealth()
    if class ~= "DRUID" then return nil end
    cat, stealth = nil, nil

    for i = 0, 31 do
      local texture = GetPlayerBuffTexture(i)
      if not texture then break end

      -- catform icon detected
      if strfind(texture, "Ability_Druid_CatForm") then
        if stealth then return true end
        cat = true
      end

      -- stealth icon detected
      if strfind(texture, "Ability_Ambush") then
        if cat then return true end
        stealth = true
      end
    end
    return nil
  end

  -- pagemaster / meta page switch
  if pfUI.expansion == "vanilla" then
    local prowl, shift, ctrl, alt, default = 8, 6, 5, 3, 1

    -- set temporary pagemaster bindings keybinds
    if C.bars.pagemaster == "1" then
      local modifier = { "ALT", "SHIFT", "CTRL" }
      local buttons = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "+", "=", "´" }
      local current = CURRENT_ACTIONBAR_PAGE
      bars.pagemaster = bars.pagemaster or CreateFrame("Frame", "pfPageMaster", UIParent)
      bars.pagemaster:RegisterEvent("PLAYER_ENTERING_WORLD")
      bars.pagemaster:SetScript("OnEvent", function()
        for _,mod in pairs(modifier) do
          for _,but in pairs(buttons) do
            SetBinding(mod.."-"..but)
          end
        end
      end)
    end

    -- setup page switch frame
    local pageswitch = CreateFrame("Frame", "pfActionBarPageSwitch", UIParent)
    pageswitch:SetScript("OnUpdate", function()
      -- Poll modifier keys at 20 Hz instead of every frame. Still feels
      -- instant, but IsCatStealth() no longer runs on most frames.
      local now = GetTime()
      if (this.tick or 0) > now then return end
      this.tick = now + 0.05

      -- switch actionbar page depending on meta key that is pressed
      if C.bars.pagemastershift == "1" and IsShiftKeyDown() then
        SwitchBar(shift)
        return
      elseif C.bars.pagemasterctrl == "1" and IsControlKeyDown() then
        SwitchBar(ctrl)
        return
      elseif C.bars.pagemasteralt == "1" and IsAltKeyDown() then
        SwitchBar(alt)
        return
      elseif C.bars.pagemasteralt == "1" or C.bars.pagemasterctrl == "1" or C.bars.pagemastershift == "1" then
        SwitchBar(default)
      end

      -- switch actionbar page if druid stealth is detected
      if C.bars.druidstealth == "1" then
        local stealth = IsCatStealth()
        if stealth and _G.CURRENT_ACTIONBAR_PAGE == 1 then
          SwitchBar(prowl)
        elseif not stealth and _G.CURRENT_ACTIONBAR_PAGE == 8 then
          SwitchBar(default)
        end
      end
    end)
  end

  local function CreateActionButton(parent, bar, button)
    -- load config
    local size = C.bars["bar"..bar].icon_size
    local font = pfUI.media[C.bars.font]
    local font_offset = tonumber(C.bars.font_offset)

    local macro_size = tonumber(C.bars.macro_size)
    local macro_color = { strsplit(",", C.bars.macro_color) }

    local count_size = tonumber(C.bars.count_size)
    local count_color = { strsplit(",", C.bars.count_color) }

    local bind_size = tonumber(C.bars.bind_size)
    local bind_color = { strsplit(",", C.bars.bind_color) }

    local cd_size = tonumber(C.bars.cd_size)

    local showempty = C.bars["bar"..bar].showempty
    local showmacro = C.bars["bar"..bar].showmacro
    local showkybind = C.bars["bar"..bar].showkeybind
    local showcount = C.bars["bar"..bar].showcount

    -- sanitize font sizes
    if macro_size == 0 then macro_size = 1 end
    if count_size == 0 then macro_size = 1 end
    if bind_size == 0 then macro_size = 1 end
    if cd_size == 0 then cd_size = nil end

    local button_name = "pfActionBar" .. barnames[bar] .. "Button" .. button

    local id = (bar-1)*12+button
    local exists = _G[button_name] and true or nil
    local f = _G[button_name] or CreateFrame("Button", button_name, parent, ACTIONBAR_SECURE_TEMPLATE_BUTTON)

    -- no button available, create a new one
    if not exists then
      -- prepare the button for vanilla
      if not f.HookScript then
        f.HookScript = HookScript
        f:SetScript("OnClick", ButtonClick)
      end
      
      -- 添加范围检查时间戳
      f.lastRangeCheck = 0
      -- 添加宏扫描时间戳（用于时间节流）
      f.lastMacroScan = 0

      if bar ~= 11 then
        f:RegisterForDrag("LeftButton", "RightButton")
        f:SetScript("OnDragStart", ButtonDrag)
        f:SetScript("OnReceiveDrag", ButtonDragStop)
      end

      -- add mouseovers
      f:SetScript("OnEnter", ButtonEnter)
      f:SetScript("OnLeave", ButtonLeave)

      -- add click animation handler
      f:HookScript("OnClick", ButtonAnimate)
      f.id = id

      -- set a static slot
      f.slot = id

      -- cooldown
      f.cd = CreateFrame(COOLDOWN_FRAME_TYPE, f:GetName() .. "Cooldown", f, "CooldownFrameTemplate")
      f.cd.pfCooldownStyleAnimation = 1
      f.cd.pfCooldownType = "NOGCD"
      f.cd.pfCooldownSize = cd_size

      -- icon
      f.icon = f:CreateTexture(button_name .. "Icon", "BACKGROUND")
      f.icon:SetTexCoord(.08, .92, .08, .92)
      f.icon:SetAllPoints()

      -- animation
      f.animation = CreateFrame("Frame", button_name .. "Animation", f)
      f.animation.parent = f
      f.animation:SetPoint("CENTER", 0, 0)
      f.animation:Hide()
      f.animation.tex = f.animation:CreateTexture(button_name .. "AnimationTexture", "BACKGROUND")
      f.animation.tex:SetTexCoord(.08, .92, .08, .92)
      f.animation.tex:SetAllPoints()

      if bar ~= 11 and bar ~= 12 then
        -- equipped item
        f.equipped = f:CreateTexture(nil, "BORDER")
        f.equipped:SetAllPoints()
        f.equipped:Hide()
      elseif bar == 12 then
        f.autocast = CreateFrame("Model", nil, f)
        f.autocast:SetAllPoints()
        f.autocast:SetModel("Interface\\Buttons\\UI-AutoCastButton.mdx")
        f.autocast:SetSequence(0)
        f.autocast:SetSequenceTime(0, 0)
        f.autocast:Hide()

        f.autocastable = f:CreateTexture(nil, "BORDER")
        f.autocastable:SetAllPoints()
        f.autocastable:SetTexture("Interface\\Buttons\\UI-AutoCastableOverlay")
        f.autocastable:SetTexCoord(.25, .75, .25, .75)
      end

      -- macro
      f.macro = f:CreateFontString(button_name .. "Name", "LOW", "GameFontNormal")

      -- keybind
      f.keybind = f:CreateFontString(nil, "LOW", "GameFontNormal")

      -- itemcount
      f.count = f:CreateFontString(button_name .. "Count", "LOW", "GameFontNormal")

      -- highlight
      f.highlight = CreateFrame("Frame", nil, f)
      f.highlight:SetBackdrop(backdrop_highlight)
      f.highlight:SetBackdropBorderColor(1,1,1,.8)
      f.highlight:SetAllPoints()
      f.highlight:Hide()

      -- active
      f.active = CreateFrame("Frame", nil, f)
      f.active:SetBackdrop(backdrop_highlight)
      f.active:SetBackdropBorderColor(1,1,.5,1)
      f.active:SetAllPoints()
      f.active:Hide()

      -- add to buttoncache
      buttoncache[id] = f
    end

    -- set required attributes for regular tbc buttons
    if pfUI.client > 11200 then
      if bar == 11 then
        f:SetAttribute("type", "spell")
        f:SetAttribute('spell', select(2, GetShapeshiftFormInfo(button)))
      elseif bar == 12 then
        f:SetAttribute("type1", "pet")
        f:SetAttribute("action1", button)
        f:SetAttribute("type2", "macro")
        f:SetAttribute("macrotext2", "/click PetActionButton".. button .. " RightButton")
      else
        bars[bar]:SetAttribute("addchild", f)
        f:SetAttribute("type", "action")
        f:SetAttribute("action", id)
        f:SetAttribute("checkselfcast", true)
        f:SetAttribute("useparent-unit", true)
        f:SetAttribute("useparent-statebutton", true)

        for state = 0, 11 do -- add custom states
          local action = ((state == 0 and bar or state)-1)*12+button
          f:SetAttribute(string.format("*type-S%d", state), "action")
          f:SetAttribute(string.format("*type-S%dRight", state), "action")
          f:SetAttribute(string.format("*action-S%d", state), action)
          f:SetAttribute(string.format("*action-S%dRight", state), action)
          if C.bars.rightself == "1" then
            f:SetAttribute(string.format("*unit-S%dRight", state), "player")
          else
            f:SetAttribute(string.format("*unit-S%dRight", state), nil)
          end
        end
      end
    end

    -- set keydown option
    if C.bars.keydown == "1" then
      f:RegisterForClicks("LeftButtonDown", "RightButtonDown")
    else
      f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end

    -- set animation with throttling to reduce CPU usage
  local lastAnimationUpdate = 0
  local ANIMATION_UPDATE_INTERVAL = 0.01 -- 动画更新间隔（降低功耗）
  f.animation:SetScript("OnUpdate", function()
    if GetTime() - lastAnimationUpdate > ANIMATION_UPDATE_INTERVAL then
      button_animations[C.bars.animation]()
      lastAnimationUpdate = GetTime()
    end
  end)
  
  -- 添加动作条切换时的动画重置处理
  f:SetScript("OnHide", function()
    -- 当按钮隐藏时（如动作条切换），强制完成动画并显示图标
    if f.animation.active ~= nil then
      f.animation.active = nil
      f.animation:Hide()
      if f.icon then
        f.icon:Show()
      end
    end
  end)

    -- pet autocast
    if bar == 12 then
      f.autocast:SetScale(C.bars["bar"..bar].icon_size / 25)
      f.autocast:SetAlpha(.10)
    end

    -- macro options
    if showmacro == "1" then f.macro:Show() else f.macro:Hide() end
    SetAllPointsOffset(f.macro, f, font_offset, -font_offset)
    f.macro:SetFont(font, macro_size, "OUTLINE")
    f.macro:SetTextColor(unpack(macro_color))
    f.macro:SetJustifyH("LEFT")
    f.macro:SetJustifyV("BOTTOM")

    -- keybind options
    if showkybind == "1" then f.keybind:Show() else f.keybind:Hide() end
    SetAllPointsOffset(f.keybind, f, font_offset, -font_offset)
    f.keybind:SetFont(font, bind_size, "OUTLINE")
    f.keybind:SetTextColor(unpack(bind_color))
    f.keybind:SetJustifyH("RIGHT")
    f.keybind:SetJustifyV("TOP")
    f.keybind:SetNonSpaceWrap(false)

    -- item count options
    if showcount == "1" then f.count:Show() else f.count:Hide() end
    SetAllPointsOffset(f.count, f, font_offset, -font_offset)
    f.count:SetFont(font, count_size, "OUTLINE")
    f.count:SetTextColor(unpack(count_color))
    f.count:SetJustifyH("RIGHT")
    f.count:SetJustifyV("BOTTOM")

    -- macro spell scan
    if C.bars.macroscan == "0" then
      f.scanmacro, f.spellslot, f.booktype = nil, nil, nil
    else
      f.scanmacro = true
    end

    -- range glow color
    f.rangeColor = { strsplit(",", C.bars.rangecolor) }

    -- out of mana color
    f.oomColor = { strsplit(",", C.bars.oomcolor) }

    -- not usable color
    f.naColor = { strsplit(",", C.bars.nacolor) }

    -- equipped color
    if f.equipped then
      f.equipped:SetTexture(strsplit(",", C.bars.eqcolor))
    end

    -- general appearance
    f.showempty = showempty == "1" and true or nil
    f:SetHeight(size)
    f:SetWidth(size)
    CreateBackdrop(f, border)

    return f
  end

  local function CreateActionBar(i)
    -- load config
    local buttonbasename = "pfActionBar" .. barnames[i] .. "Button"
    local enable = C.bars["bar"..i].enable
    local size = C.bars["bar"..i].icon_size
    local spacing = C.bars["bar"..i].spacing
    local background = C.bars["bar"..i].background
    local formfactor = C.bars["bar"..i].formfactor
    local autohide = C.bars["bar"..i].autohide
    local hide_time = C.bars["bar"..i].hide_time
    local hide_combat = C.bars["bar"..i].hide_combat == "1" and true or nil

    local buttons = tonumber(C.bars["bar"..i].buttons) or 12
    if i == 11 and bars[i] then -- shapeshift buttons
      buttons = GetNumShapeshiftForms()
    elseif i == 12 and bars[i] then -- pet buttons
      buttons = NUM_PET_ACTION_SLOTS
    elseif i == 12 or i == 11 then
      -- Fallback to 10 buttons on shapeshift and petbar during initialization.
      -- This lets us load bars that aren't yet available for your class or level.
      buttons = 10
    end

    -- don't process empty bars
    if buttons == 0 then
      bars[i]:Hide()
      return
    end

    -- the stored layout is invalid, temporary fallback
    if not pfGridmath[buttons][BarLayoutFormfactor(formfactor)] then
      formfactor = BarLayoutOptions(buttons)[1]
    end

    local font = pfUI.font_unit
    local font_size = C.global.font_unit_size

    local realsize = size+border*2

    -- create frame
    local init = not bars[i]
    bars[i] = bars[i] or CreateFrame("Frame", "pfActionBar" .. barnames[i], UIParent, ACTIONBAR_SECURE_TEMPLATE_BAR)
    bars[i]:SetID(i)

    -- autohide
    if autohide == "1" then
      EnableAutohide(bars[i], tonumber(hide_time), hide_combat)
    else
      DisableAutohide(bars[i])
    end

    -- apply visible settings
    if enable == "1" then
      -- handle pet bar
      if i == 12 then
        if pfUI.client > 11200 then
          if InCombatLockdown and InCombatLockdown() then
            -- don't process those events during combat
          else
            -- set state driver for pet bars
            bars[i]:SetAttribute("unit", "pet")
            local visibility = pfUI.unlock and pfUI.unlock:IsShown() and "show" or petvisibility
            if bars[i].visibility ~= visibility then
              RegisterStateDriver(bars[i], 'visibility', visibility)
              bars[i].visibility = visibility
            end
          end
        else
          -- only show when pet actions exists
          if PetHasActionBar() or pfUI.unlock and pfUI.unlock:IsShown() then
            bars[i]:Show()
          else
            bars[i]:Hide()
          end

          -- show/hide petbar on petbar updates
          if init then
            bars[i]:RegisterEvent("PET_BAR_UPDATE")
            bars[i]:SetScript("OnEvent", function()
              -- hide obsolete buttons
              for i=1, NUM_PET_ACTION_SLOTS do
               if not PetHasActionBar() and bars[12][i] then
                 bars[12][i]:Hide()
               end
              end
              -- refresh layout
              CreateActionBar(12)
            end)
          end
        end

      -- handle shapeshift bar
      elseif i == 11 then
        -- only show when shapeshifts exist
        if GetNumShapeshiftForms() > 0 then
          bars[i]:Show()
        else
          bars[i]:Hide()
        end

        -- update shapeshift bar when amount of spells changes
        if init then
          bars[i]:RegisterEvent("PLAYER_ENTERING_WORLD")
          bars[i]:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
          bars[i]:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
          bars[i]:SetScript("OnEvent", function()
            local count = GetNumShapeshiftForms()
            if count ~= this.lastCount then
              this.lastCount = count

              -- hide obsolete buttons
              for i=1, NUM_SHAPESHIFT_SLOTS do
                if i > GetNumShapeshiftForms() and bars[11][i] then
                  bars[11][i]:Hide()
                end
              end

              -- create new buttons and refresh layout
              CreateActionBar(11)
            end
          end)
        end

      -- regular bars
      else
        bars[i]:Show()
      end

    elseif enable == "0" then
      bars[i]:UnregisterAllEvents()
      bars[i]:Hide()
    end

    -- create action buttons
    local maxbuttons = (i == 11 or i == 12) and 10 or 12
    for j=1,maxbuttons do
      bars[i][j] = CreateActionButton(bars[i], i, j)
      bars[i][j].bar = i

      BarButtonAnchor(bars[i][j], buttonbasename, j, buttons, formfactor, size, border, spacing)
      bars[i][j]:ClearAllPoints()
      bars[i][j]:SetPoint(unpack(bars[i][j]._anchor))
      bars[i][j]:Show()

      if i > 10 then
        bars[i][j].id = j
      end

      -- refresh button
      updatecache[bars[i][j].slot] = true
    end

    for j=buttons+1,12 do
      if bars[i][j] then
        bars[i][j]:Hide()
      end
    end

    -- add up to 0-11 button parent states to each bar
    if i <= 10 and pfUI.client > 11200 then
      bars[i]:SetAttribute("statebutton", "0:S0;1:S1;2:S2;3:S3;4:S4;5:S5;6:S6;7:S7;8:S8;9:S9;10:S10;11:S11;")
      bars[i]:SetAttribute("statebutton2", "0:S0Right;1:S1Right;2:S2Right;3:S3Right;4:S4Right;5:S5Right;6:S6Right;7:S7Right;8:S8Right;9:S9Right;10:S10Right;11:S11Right;")
    end

    -- enable paging for the first actionbar
    if i == 1 then
      EnablePaging(bars[i])
    end

    -- adjust actionbar size
    BarLayoutSize(bars[i], buttons, formfactor, size, border, spacing)
    bars[i]:SetWidth(bars[i]._size[1])
    bars[i]:SetHeight(bars[i]._size[2])
    bars[i]:ClearAllPoints()
    if i == 1 then -- main
      bars[i]:SetPoint("BOTTOM", 0, 2*border)
    elseif i == 3 then -- left
      bars[i]:SetPoint("BOTTOMLEFT", bars[1], "BOTTOMRIGHT", 3*border, 0)
    elseif i == 4 then -- vertical
      bars[i]:SetPoint("RIGHT", -2*border, 0)
    elseif i == 5 then -- right
      bars[i]:SetPoint("BOTTOMRIGHT", bars[1], "BOTTOMLEFT", -3*border, 0)
    elseif i == 6 then -- top
      bars[i]:SetPoint("BOTTOM", bars[1], "TOP", 0, -spacing)
    elseif i == 11 then -- stances
      bars[i]:SetPoint("BOTTOM", bars[6], "TOP", 0, 3*border)
    elseif i == 12 then -- pet
      bars[i]:SetPoint("BOTTOM", bars[6], "TOP", 0, 3*border)

      -- make stance bar dodge by default
      bars[i]:SetScript("OnShow", function()
        if bars[11] and bars[11]:IsShown() then
          bars[11]:ClearAllPoints()
          bars[11]:SetPoint("BOTTOM", bars[12], "TOP", 0, 3*border)
          UpdateMovable(bars[11], true)
        end
      end)

      -- restore old stance bar position
      bars[i]:SetScript("OnHide", function()
        if bars[11] and bars[11]:IsShown() then
          bars[11]:ClearAllPoints()
          bars[11]:SetPoint("BOTTOM", bars[6], "TOP", 0, 3*border)
          UpdateMovable(bars[11], true)
        end
      end)
    else -- others
      bars[i]:SetPoint("TOP", 0, -i*50)
    end

    UpdateMovable(bars[i])

    -- apply backdrop settings
    if background == "1" then
      CreateBackdrop(bars[i], border)
      CreateBackdropShadow(bars[i])
      bars[i].backdrop:Show()
    elseif bars[i].backdrop then
      bars[i].backdrop:Hide()
    end

    -- share backdrop of main and top actionbar
    if bars[6] and bars[1] then
      bars[6].OnMove = bars[6].OnMove or function()
        bars[1].mergedBackdrop = bars[1].mergedBackdrop or CreateFrame("Frame", nil, UIParent)
        bars[1].mergedBackdrop:SetPoint("TOPLEFT", bars[6], "TOPLEFT", 0, 0)
        bars[1].mergedBackdrop:SetPoint("BOTTOMRIGHT", bars[1], "BOTTOMRIGHT", 0, 0)
        CreateBackdrop(bars[1].mergedBackdrop)

        local _, anchor, _ = bars[6]:GetPoint()
        if anchor == bars[1] and C.bars.bar1.enable == "1"
          and C.bars.bar1.enable == "1" and C.bars.bar6.enable == "1"
          and C.bars.bar1.background == "1" and C.bars.bar6.background == "1"
          and C.bars.bar1.autohide == "0" and C.bars.bar6.autohide == "0"
          and C.bars.bar1.icon_size == C.bars.bar6.icon_size
          and C.bars.bar1.spacing == C.bars.bar6.spacing
          and C.bars.bar1.formfactor == C.bars.bar6.formfactor
          and C.bars.bar1.buttons == C.bars.bar6.buttons
        then
          bars[1].mergedBackdrop:Show()

          if C.bars.bar1.background == "1" and bars[1].backdrop then
            bars[1].backdrop:Hide()
          end

          if C.bars.bar6.background == "1" and bars[6].backdrop then
            bars[6].backdrop:Hide()
          end
        else
          bars[1].mergedBackdrop:Hide()

          if C.bars.bar1.background == "1" and bars[1].backdrop then
            bars[1].backdrop:Show()
          end

          if C.bars.bar6.background == "1" and bars[6].backdrop then
            bars[6].backdrop:Show()
          end
        end
      end
      bars[6].OnMove()
    end
  end

  -- create actionbars
  pfUI.bars = bars
  pfUI.bars.update = updatecache
  pfUI.bars.buttons = buttoncache
  pfUI.bars.ButtonFullUpdate = ButtonFullUpdate
  pfUI.bars.ButtonEnter = ButtonEnter
  pfUI.bars.ButtonLeave = ButtonLeave

  pfUI.bars.UpdateGrid = function(self, state, typ)
    if not typ then
      showgrid = state

      for id in pairs(buttoncache) do
        updatecache[id] = true
      end
    elseif typ == "PET" then
      showgrid_pet = state
      for slot=133,142 do
        updatecache[slot] = true
      end
    end
  end

  -- ============================================================================
  -- 动作条监控（Action Monitor）：Alt+左键动作条按钮，把槽位加入监控区重点显示。
  -- 监控区为独立 movable 容器，显示图标/冷却扫掠+倒计时/可用性灰显/超范围红边/物品数量。
  -- 事件驱动：光环/冷却/槽位事件置脏后重建，OnUpdate 仅 0.25s 轻刷倒计时与范围状态。
  -- ============================================================================
  pfUI.bars.MONITOR_COUNT = 32

  if not pfUI.bars.monitor then
    local mon = CreateFrame("Frame", "pfActionMonitorFrame", UIParent)
    pfUI.bars.monitor = mon
    mon.slotset = {}
    mon.buttons = {}

    -- 名单解析："1;5;61" -> {1,5,61}
    local function MonitorListToTable()
      local t = {}
      local raw = C.bars.monitorlist or ""
      for v in string.gmatch(raw, "[^;]+") do
        local n = tonumber(v)
        if n and n >= 1 and n <= 120 then t[getn(t) + 1] = n end
      end
      return t
    end

    -- 边框统一出口：金边开关关掉时一律透明（红边/呼吸都随开关失效，只剩图标）
    local function MonitorSetBorder(b)
      if C.bars.monitorborder ~= "1" then
        b.backdrop:SetBackdropBorderColor(0, 0, 0, 0)
      elseif b.monOutOfRange then
        b.backdrop:SetBackdropBorderColor(1, .1, .1, 1)
      else
        b.backdrop:SetBackdropBorderColor(1, .78, .1, 1)
      end
    end

    -- 单按钮全量刷新（图标/可用色/红边/数量/冷却）
    local function MonitorUpdateButton(b)
      if not b or not b.slot then return end
      local slot = b.slot

      -- icon（槽位变空时 tex 与 monTex 同为 nil，必须显式清理，否则残留上个技能贴图）
      local tex = GetActionTexture(slot)
      if tex ~= b.monTex or tex == nil then
        b.icon:SetTexture(tex)
        b.monTex = tex
      end

      -- usable / oom / out-of-range 图标着色（与动作条本体同配色）
      local usable, oom = IsUsableAction(slot)
      if b.monOutOfRange and C.bars.glowrange == "1" then
        b.icon:SetVertexColor(1, .1, .1, 1)
      elseif oom and C.bars.showoom == "1" then
        b.icon:SetVertexColor(.2, .2, 1, 1)
      elseif not usable and C.bars.showna == "1" then
        b.icon:SetVertexColor(.3, .3, .3, 1)
      else
        b.icon:SetVertexColor(1, 1, 1, 1)
      end

      -- 超范围红边（状态变化时才重设，避免和呼吸脉动互相打架）
      local outrange = C.bars.glowrange == "1" and HasAction(slot)
        and ActionHasRange(slot) and IsActionInRange(slot) == 0
      outrange = outrange and true or nil
      if outrange ~= b.monOutOfRange then
        b.monOutOfRange = outrange
        MonitorSetBorder(b)
      end

      -- 激活态边框（与本体一致：当前施法/自动重复类动作亮黄边；statechange 动画模式下播动画）
      local act = IsCurrentAction(slot) or IsAutoRepeatAction(slot)
      if act and not b.monActive then
        b.monActive = true
        if C.bars.animmode == "statechange" then
          b.animation.active = 0
          b.animation:Show()
        end
        b.backdrop:SetBackdropBorderColor(1, 1, .5, 1)
        b.active:Show()
      elseif not act and b.monActive then
        b.monActive = nil
        MonitorSetBorder(b)
        b.active:Hide()
      end

      -- 消耗品数量
      if IsConsumableAction(slot) then
        local cnt = GetActionCount(slot)
        if b.monCount ~= cnt then
          b.count:SetText(cnt)
          b.monCount = cnt
        end
      elseif b.monCount then
        b.count:SetText(nil)
        b.monCount = nil
      end

      -- 宏名（对齐本体 showmacro）
      if C.bars.monitorshowmacro == "1" then
        local mtext = GetActionText(slot) or ""
        if b.monMacro ~= mtext then
          b.macro:SetText(mtext)
          b.monMacro = mtext
        end
      end

      -- 热键文本（hoverbind 绑定模式设置：悬停监控按钮按键即绑定 PFMONITORBUTTON<uid>）
      if C.bars.monitorshowkeybind == "1" then
        local key = GetBindingKey("PFMONITORBUTTON" .. b.uid)
        local ktext = key and GetBindingText(key, "KEY_", 1) or ""
        if b.monKey ~= ktext then
          b.keybind:SetText(ktext)
          b.monKey = ktext
        end
      end

      -- 冷却扫掠（倒计时数字由 pfUI 本体 CooldownFrame 显示，不再叠加自绘文本）
      local start, duration, enable = GetActionCooldown(slot)
      CooldownFrame_SetTimer(b.cd, start, duration, enable)
    end

    -- 全量重建（名单 -> 按钮布局 + 内容）
    local function MonitorRefresh()
      if not mon:IsShown() then return end

      local list = MonitorListToTable()
      local size = tonumber(C.bars.monitorsize) or 36
      local rowsize = tonumber(C.bars.monitorrowsize) or 8
      if rowsize < 1 then rowsize = 1 end
      local spacing = tonumber(C.bars.monitorspacing) or 1
      if spacing < 0 then spacing = 0 end
      local count = getn(list)
      if count > pfUI.bars.MONITOR_COUNT then count = pfUI.bars.MONITOR_COUNT end

      for k in pairs(mon.slotset) do mon.slotset[k] = nil end

      local n = 0
      for i = 1, pfUI.bars.MONITOR_COUNT do
        local b = mon.buttons[i]
        if i <= count then
          local slot = list[i]
          mon.slotset[slot] = true
          if b.slot ~= slot then
            b.slot = slot
            b.monTex = nil
            b.monCount = nil
            b.monOutOfRange = nil
            b.monMacro = nil
          end
          local col = math.mod(n, rowsize)
          local row = math.floor(n / rowsize)
          b:ClearAllPoints()
          b:SetPoint("TOPLEFT", mon, "TOPLEFT", col * (size + spacing) + 2, -(row * (size + spacing) + 2))
          b:SetWidth(size)
          b:SetHeight(size)
          b:Show()
          MonitorUpdateButton(b)
          n = n + 1
        else
          b.slot = nil
          b:Hide()
        end
      end

      -- 容器几何随内容伸缩（空名单保留一格占位，便于拖动）
      local wcols = count == 0 and 1 or (count < rowsize and count or rowsize)
      local wrows = count == 0 and 1 or math.floor((count + rowsize - 1) / rowsize)
      mon:SetWidth(wcols * (size + spacing) - spacing + 4)
      mon:SetHeight(wrows * (size + spacing) - spacing + 4)
    end

    -- 轻刷：仅遍历已显示按钮（倒计时/范围/可用性随时间变化的部分）
    local function MonitorTimers()
      for i = 1, pfUI.bars.MONITOR_COUNT do
        local b = mon.buttons[i]
        if b.slot and b:IsShown() then
          MonitorUpdateButton(b)
        end
      end
    end

    -- 监控按钮
    -- 冷却字号跟随本体 cd_size（0 = 用全局字号，与本体同语义）
    local mcd_size = tonumber(C.bars.cd_size)
    if mcd_size == 0 then mcd_size = nil end
    for i = 1, pfUI.bars.MONITOR_COUNT do
      local b = CreateFrame("Button", "pfActionMonitorButton" .. i, mon)
      mon.buttons[i] = b
      b.uid = i
      -- 点击模式跟随本体动作条设置（C.bars.keydown=1 按下即触发，否则抬起触发）
      if C.bars.keydown == "1" then
        b:RegisterForClicks("LeftButtonDown", "RightButtonDown")
      else
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
      end

      b.icon = b:CreateTexture(nil, "BACKGROUND")
      b.icon:SetTexCoord(.08, .92, .08, .92)
      b.icon:SetAllPoints()

      b.cd = CreateFrame(COOLDOWN_FRAME_TYPE, b:GetName() .. "Cooldown", b, "CooldownFrameTemplate")
      -- 与本体按钮一致：强制 GCD 扇形转动动画（否则外观开了「隐藏冷却动画」时此帧被置透明）
      b.cd.pfCooldownStyleAnimation = 1
      b.cd.pfCooldownType = "NOGCD"
      b.cd.pfCooldownSize = mcd_size

      b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      b.count:SetFont(pfUI.media["font"], 12, "OUTLINE")
      b.count:SetTextColor(1, 1, 1, 1)
      b.count:SetJustifyH("RIGHT")
      b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 2)

      -- 宏名/热键文本（样式与本体一致，显隐由 UpdateMonitorConfig 管理）
      b.macro = b:CreateFontString(nil, "LOW", "GameFontNormal")
      b.keybind = b:CreateFontString(nil, "LOW", "GameFontNormal")

      -- 悬停/按下高亮：与本体动作条按钮同款 glow 层（ButtonEnter/Leave/Animate 控制）
      b.highlight = CreateFrame("Frame", nil, b)
      b.highlight:SetBackdrop(backdrop_highlight)
      b.highlight:SetBackdropBorderColor(1, 1, 1, .8)
      b.highlight:SetAllPoints()
      b.highlight:Hide()

      -- active 激活边框：与本体同款（IsCurrentAction/IsAutoRepeatAction 时亮黄边）
      b.active = CreateFrame("Frame", nil, b)
      b.active:SetBackdrop(backdrop_highlight)
      b.active:SetBackdropBorderColor(1, 1, .5, 1)
      b.active:SetAllPoints()
      b.active:Hide()

      -- 点击动画层：与本体按钮同结构，OnUpdate 驱动 button_animations（none 时立即自隐藏）
      b.animation = CreateFrame("Frame", b:GetName() .. "Animation", b)
      b.animation.parent = b
      b.animation:SetPoint("CENTER", 0, 0)
      b.animation:Hide()
      b.animation.tex = b.animation:CreateTexture(b:GetName() .. "AnimationTexture", "BACKGROUND")
      b.animation.tex:SetTexCoord(.08, .92, .08, .92)
      b.animation.tex:SetAllPoints()
      b.animation:SetScript("OnUpdate", function()
        button_animations[C.bars.animation]()
      end)

      CreateBackdrop(b, 2)
      MonitorSetBorder(b)

      -- 点击使用（原动作条同款逻辑）；Alt+左键优先：移出监控（锁定时保留 Alt 原有功能）
      b:SetScript("OnClick", function()
        if not b.slot then return end

        -- Alt+左键：加入/移出监控（监控优先于 altself；锁定时不拦截）
        if IsAltKeyDown() and arg1 == "LeftButton" and C.bars.monitorlock ~= "1" then
          pfUI.bars:ToggleMonitorSlot(b.slot)
          return
        end

        -- 左键/右键：直接使用该槽位动作（与 ButtonClick 的 mouse 分支一致）
        if HasAction(b.slot) then
          if MacroFrame_SaveMacro then
            MacroFrame_SaveMacro()
          end
          local slfcast = nil
          if arg1 == "RightButton" and C.bars.rightself == "1" then slfcast = true end
          if IsAltKeyDown() and C.bars.altself == "1" then slfcast = true end
          UseAction(b.slot, nil, slfcast)

          -- 点击动画：animmode=keypress 时播放（本体 mouse 分支同条件；监控按钮恒可见，alpha 条件恒满足）
          if C.bars.animmode == "keypress" then
            b.animation.active = 0
            b.animation:Show()
          end
        end
      end)

      b:SetScript("OnEnter", function()
        GameTooltip:ClearLines()
        GameTooltip_SetDefaultAnchor(GameTooltip, b)
        if b.slot and HasAction(b.slot) then
          GameTooltip:SetAction(b.slot)
          GameTooltip:AddLine(T["Click To Use Action"])
          if C.bars.monitorlock ~= "1" then
            GameTooltip:AddLine(T["Alt+Leftclick To Remove From Monitor"])
          end
        else
          GameTooltip:AddLine(T["Action Monitor"])
        end
        GameTooltip:Show()
        b.highlight:Show()
      end)

      b:SetScript("OnLeave", function()
        GameTooltip:Hide()
        b.highlight:Hide()
      end)
    end

    -- 键盘触发：hoverbind 绑定模式把 PFMONITORBUTTON%d 绑到按键后，由此使用对应监控槽位
    -- （1.12 的自定义绑定名没有引擎动作；本体 ACTIONBUTTON 走暴雪绑定链不受影响）
    -- ⚠️ 不能再用 EnableKeyboard 的常驻 frame 接 OnKeyDown/OnKeyUp：本客户端该 frame 会抢
    --    键盘焦点并吞掉全部按键（表现为键盘全失效、鼠标正常）。改成 OnUpdate 轮询 IsKeyDown，
    --    只读取状态、不劫持输入。IsKeyDown 缺失时整段降级（不报错）。
    local monitorkeymap = {}
    local monitorkeyheld = {}
    local monitorpolling = (type(IsKeyDown) == "function")

    local function MonitorRebuildKeybinds()
      for k in pairs(monitorkeymap) do monitorkeymap[k] = nil end
      for k in pairs(monitorkeyheld) do monitorkeyheld[k] = nil end
      for i = 1, pfUI.bars.MONITOR_COUNT do
        local key = GetBindingKey("PFMONITORBUTTON" .. i)
        if key then monitorkeymap[key] = i end
      end
    end

    local listener = CreateFrame("Frame", "pfActionMonitorKeybindListener", UIParent)
    pfUI.bars.monitorKeybindListener = listener
    listener:RegisterEvent("PLAYER_ENTERING_WORLD")
    listener:RegisterEvent("UPDATE_BINDINGS")
    listener:SetScript("OnEvent", function()
      MonitorRebuildKeybinds()
    end)

    -- 组合键：修饰键走 1.12 确定的 IsAlt/Control/ShiftKeyDown，末段才走 IsKeyDown
    local function MonitorKeyHeld(keystr)
      local base
      for p in string.gmatch(keystr, "[^%-]+") do
        if p == "ALT" then
          if not IsAltKeyDown() then return false end
        elseif p == "CTRL" then
          if not IsControlKeyDown() then return false end
        elseif p == "SHIFT" then
          if not IsShiftKeyDown() then return false end
        else
          base = p
        end
      end
      if not base then return false end
      return IsKeyDown(base) and true or false
    end

    local function MonitorUseButton(idx)
      local b = mon.buttons[idx]
      if b and b.slot and HasAction(b.slot) then
        if MacroFrame_SaveMacro then
          MacroFrame_SaveMacro()
        end
        local slfcast = nil
        if IsAltKeyDown() and C.bars.altself == "1" then slfcast = true end
        UseAction(b.slot, nil, slfcast)

        -- 键盘触发的点击动画（对齐本体 ButtonAnimate 的键盘分支）
        if C.bars.animmode == "keypress" then
          b.animation.active = 0
          b.animation:Show()
        end
      end
    end

    -- 由 mon 的 OnUpdate 调用：无绑定键时 pairs 一次即出，零开销
    local function MonitorPollKeys()
      if not monitorpolling then return end
      if C.bars.monitorenable ~= "1" then return end

      -- 惰性重建兜底：UPDATE_BINDINGS 缺失时也能捡到新绑定（2s 限频，代价可忽略）
      if not mon.nextRebuild or mon.nextRebuild <= GetTime() then
        mon.nextRebuild = GetTime() + 2
        MonitorRebuildKeybinds()
      end

      local blocked = (ChatFrameEditBox and ChatFrameEditBox:IsShown())
        or (pfUI.hoverbind and pfUI.hoverbind:IsShown())
      for key, idx in pairs(monitorkeymap) do
        local down = MonitorKeyHeld(key)
        local held = monitorkeyheld[key] and true or false
        if down ~= held then
          monitorkeyheld[key] = down
          -- 键盘按下/抬起的按下反馈（对齐本体 ButtonAnimate：down 亮、up 且鼠标不在按钮上时灭）
          local mb = mon.buttons[idx]
          if mb and mb.highlight then
            if down then
              mb.highlight:Show()
            elseif not MouseIsOver(mb) then
              mb.highlight:Hide()
            end
          end
          if not blocked then
            -- 触发时机对齐本体 keydown 配置（keydown=1 按下触发，否则抬起触发）
            if C.bars.keydown == "1" then
              if down then MonitorUseButton(idx) end
            elseif not down then
              MonitorUseButton(idx)
            end
          end
        end
      end
    end

    -- 事件驱动置脏（OnUpdate 里统一处理）
    mon:RegisterEvent("PLAYER_ENTERING_WORLD")
    mon:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    mon:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    mon:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
    mon:RegisterEvent("ACTIONBAR_UPDATE_STATE")
    mon:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    mon:RegisterEvent("UNIT_INVENTORY_CHANGED")
    mon:RegisterEvent("BAG_UPDATE")
    mon:RegisterEvent("START_AUTOREPEAT_SPELL")
    mon:RegisterEvent("STOP_AUTOREPEAT_SPELL")
    mon:SetScript("OnEvent", function()
      this.dirty = true
    end)

    mon:SetScript("OnUpdate", function()
      if C.bars.monitorenable ~= "1" then return end

      if this.dirty then
        this.dirty = nil
        MonitorRefresh()
      end

      local now = GetTime()
      if not this.nextTimer or this.nextTimer <= now then
        this.nextTimer = now + 0.25
        MonitorTimers()
      end

      -- 呼吸高亮（金色边框脉动，与分离区 glow 同风格；0.1s 独立节流，倒计时 0.25s 下呼吸会卡顿）
      -- 超范围红边优先：monOutOfRange 按钮跳过，恢复金边时由 MonitorUpdateButton 重设
      if C.bars.monitorglow == "1" and C.bars.monitorborder == "1" then
        if not this.nextGlow or this.nextGlow <= now then
          this.nextGlow = now + 0.1
          local pulse = .5 + .5 * math.sin(math.mod(now, 2) / 2 * math.pi * 2)
          for i = 1, pfUI.bars.MONITOR_COUNT do
            local b = mon.buttons[i]
            if b.slot and b:IsShown() and not b.monOutOfRange then
              b.backdrop:SetBackdropBorderColor(1, .56 + .22 * pulse, .02 + .08 * pulse, 1)
            end
          end
        end
      end

      MonitorPollKeys()
    end)

    pfUI.bars.RefreshMonitor = function() MonitorRefresh() end

    -- 开关同步（UpdateConfig 与 GUI 变更都会走到这里）
    -- 外观配置与动作条本体对齐：隐藏/自动隐藏/间距/背景/计数
    pfUI.bars.UpdateMonitorConfig = function(self)
      if C.bars.monitorenable ~= "1" then
        pfUI.api.DisableAutohide(mon)
        mon:Hide()
        RemoveMovable(mon)
        return
      end

      -- 点击模式实时跟随本体 keydown 设置（按钮只创建一次，配置变更在此重注册）
      for i = 1, pfUI.bars.MONITOR_COUNT do
        local b = mon.buttons[i]
        if b then
          if C.bars.keydown == "1" then
            b:RegisterForClicks("LeftButtonDown", "RightButtonDown")
          else
            b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
          end
        end
      end

      -- 背景板（对应本体 background；懒创建，开关只做显隐）
      if C.bars.monitorbackdrop == "1" then
        if not mon.backdrop then
          pfUI.api.CreateBackdrop(mon, 2)
          pfUI.api.CreateBackdropShadow(mon)
        end
        mon.backdrop:Show()
        if mon.backdrop.shadow then mon.backdrop.shadow:Show() end
      elseif mon.backdrop then
        mon.backdrop:Hide()
        if mon.backdrop.shadow then mon.backdrop.shadow:Hide() end
      end

      -- 消耗品数量文本显隐（对应本体 showcount；更新逻辑照常，代价可忽略）
      for i = 1, pfUI.bars.MONITOR_COUNT do
        if C.bars.monitorcount == "1" then
          mon.buttons[i].count:Show()
        else
          mon.buttons[i].count:Hide()
        end
      end

      -- 宏名/热键文本显隐 + 字体样式（复用本体字体配置，对齐 showmacro/showkeybind）
      local mfont = pfUI.font_unit
      local macro_size = tonumber(C.bars.macro_size) or 10
      if macro_size == 0 then macro_size = 1 end
      local macro_color = { strsplit(",", C.bars.macro_color) }
      local bind_size = tonumber(C.bars.bind_size) or 10
      if bind_size == 0 then bind_size = 1 end
      local bind_color = { strsplit(",", C.bars.bind_color) }
      local font_offset = C.bars.font_offset or 0
      for i = 1, pfUI.bars.MONITOR_COUNT do
        local b = mon.buttons[i]
        if C.bars.monitorshowmacro == "1" then
          b.macro:Show()
        else
          b.macro:Hide()
        end
        pfUI.api.SetAllPointsOffset(b.macro, b, font_offset)
        b.macro:SetFont(mfont, macro_size, "OUTLINE")
        b.macro:SetTextColor(unpack(macro_color))
        b.macro:SetJustifyH("LEFT")
        b.macro:SetJustifyV("BOTTOM")

        if C.bars.monitorshowkeybind == "1" then
          b.keybind:Show()
        else
          b.keybind:Hide()
        end
        pfUI.api.SetAllPointsOffset(b.keybind, b, font_offset)
        b.keybind:SetFont(mfont, bind_size, "OUTLINE")
        b.keybind:SetTextColor(unpack(bind_color))
        b.keybind:SetJustifyH("RIGHT")
        b.keybind:SetJustifyV("TOP")
        b.keybind:SetNonSpaceWrap(false)
        b.monMacro = nil
        b.monKey = nil
      end

      -- 鼠标离开自动隐藏（复用本体 EnableAutohide 渐隐机制；monitorcombat=战斗中保持显示，对齐本体 hide_combat）
      if C.bars.monitorautohide == "1" then
        pfUI.api.EnableAutohide(mon, tonumber(C.bars.monitorhidetime) or 3, C.bars.monitorcombat == "1")
      else
        pfUI.api.DisableAutohide(mon)
      end

      -- 边框恢复：金边开关关掉→整条边框透明；呼吸关掉→恢复静态金边（否则停在最后一次脉动色）
      if C.bars.monitorborder ~= "1" or C.bars.monitorglow ~= "1" then
        mon.nextGlow = nil
        for i = 1, pfUI.bars.MONITOR_COUNT do
          MonitorSetBorder(mon.buttons[i])
        end
      end

      -- 手动隐藏开关：隐藏但保留 movable 注册，位置不丢
      if C.bars.monitorhide == "1" then
        mon:Hide()
      else
        mon:Show()
        mon:ClearAllPoints()
        -- 默认位置：屏幕底部中央偏上（对齐位置面板 BOTTOM X:0 Y:369）。
        -- 存档永远赢：这里只决定出厂位置与「重置」的落点，用户拖过/存过档则 LoadMovable 覆盖。
        mon:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 369)
        UpdateMovable(mon)
      end
      mon.dirty = true
    end


    -- Alt+左键入口：加入/移出槽位
    pfUI.bars.ToggleMonitorSlot = function(self, slot)
      slot = tonumber(slot)
      if not slot or slot < 1 or slot > 120 then return end

      local list = MonitorListToTable()
      local found = nil
      for i = 1, getn(list) do
        if list[i] == slot then
          table.remove(list, i)
          found = true
          break
        end
      end

      if not found then
        if getn(list) >= pfUI.bars.MONITOR_COUNT then
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 动作条监控已满 (" .. pfUI.bars.MONITOR_COUNT .. ")")
          return
        end
        list[getn(list) + 1] = slot
        C.bars.monitorenable = "1"
      end

      local parts = {}
      for i = 1, getn(list) do parts[i] = tostring(list[i]) end
      C.bars.monitorlist = table.concat(parts, ";")

      pfUI.bars:UpdateMonitorConfig()
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 动作条监控 " .. (found and "移出槽位 " or "加入槽位 ") .. slot)
    end

    -- /pfmon 命令：names 列出名单 / clear 清空
    SLASH_PFMON1 = "/pfmon"
    -- 名单分享：导出/导入动作条监控槽位（格式 pfMON1:1;5;61），命令行与 GUI 共用
    function pfUI.bars:ExportMonShare()
      return "pfMON1:" .. (C.bars.monitorlist or "")
    end

    function pfUI.bars:ImportMonShare(str)
      if not string.find(str or "", "pfMON1", 1, true) then return false, "分享码格式不对（应以 pfMON1 开头）" end
      local payload = string.gsub(str or "", "pfMON1", "")
      payload = string.gsub(payload, "[^0-9;,]", "")   -- 逗号也当分隔符，兼容手打/粘贴的 "1,5,61"
      local out, n = "", 0
      for v in string.gmatch(payload, "[^;,]+") do
        local num = tonumber(v)
        if num and num >= 1 and num <= 120 then
          out = out .. (out ~= "" and ";" or "") .. num
          n = n + 1
        end
      end
      C.bars.monitorlist = out
      if out ~= "" then C.bars.monitorenable = "1" end
      pfUI.bars:UpdateMonitorConfig()
      if n > 0 then
        return true, "已导入 " .. n .. " 个监控槽位"
      end
      return false, "未识别到可导入的槽位（分享码应以 pfMON1 开头）"
    end

    SlashCmdList["PFMON"] = function(msg)
      msg = string.lower(msg or "")
      if string.find(msg, "clear", 1, true) then
        C.bars.monitorlist = ""
        C.bars.monitorenable = "0"
        pfUI.bars:UpdateMonitorConfig()
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 已清空动作条监控名单并关闭监控显示")
      elseif string.find(msg, "names", 1, true) then
        local list = MonitorListToTable()
        if getn(list) == 0 then
          DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: 动作条监控名单为空")
        else
          local out = "|cff33ffccpfUI|r: 动作条监控槽位: "
          for i = 1, getn(list) do
            out = out .. list[i] .. (i < getn(list) and ", " or "")
          end
          DEFAULT_CHAT_FRAME:AddMessage(out)
        end
      elseif string.find(msg, "share", 1, true) then
        -- 名单分享：导出/导入动作条监控槽位（格式 pfMON1:1;5;61）
        pfUI.api.CreateShareListDialog("pfMonShare", "动作条监控 · " .. T["Share List"],
          function() return pfUI.bars:ExportMonShare() end,
          function(str) return pfUI.bars:ImportMonShare(str) end)
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfUI|r: /pfmon names 查看名单 | /pfmon share 分享名单 | /pfmon clear 清空 | Alt+左键动作条按钮加入/移出监控")
      end
    end
  end

  -- 优化的配置更新函数
  pfUI.bars.UpdateConfig = function(self)
    for i=1,12 do
      CreateActionBar(i)
    end
    -- 更新可见按钮缓存
    UpdateVisibleButtonsCache()
    -- 动作条监控布局同步
    self:UpdateMonitorConfig()
  end

  pfUI.bars:UpdateConfig()

  -- Localize custom keybinds for additional actionbars (see Bindings.xml)
  local names = {
    ["PAGING"] = T["Paging Actionbar"],
    ["STANCEONE"] = T["Stance Bar 1"],
    ["STANCETWO"] = T["Stance Bar 2"],
    ["STANCETHREE"] = T["Stance Bar 3"],
    ["STANCEFOUR"] = T["Stance Bar 4"],
  }

  for name, loc in pairs(names) do
    _G["BINDING_HEADER_PFBAR"..name] = T["Action Bar"] .. " " .. loc
    for i=1,12 do
      _G["BINDING_NAME_PF" .. name .. i] = loc .. " " .. T["Button"] .. " " .. i
    end
  end

  -- Map Keybinds to button clicks
  function _G.pfActionButton(slot, slfcast, opt)
    if ChatFrameEditBox:IsShown() then return end

    local bar, button = 1, slot

    -- determine the proper bar and button
    if opt and blizzbarmapping[opt] then
      bar = blizzbarmapping[opt]
    elseif slot > 12 then
      bar, button = ceil(slot/12), mod(slot, 12)
      button = button == 0 and 12 or button
    end

    local frame = bars[bar][button]
    if frame then
      frame.slfcast = slfcast
      frame:Click()
    end
  end

  -- Set keybinds to all actionbuttons
  if pfUI.client <= 11200 then
    -- In order to be able to reuse already defined keybinds, we need to remap
    -- existing button functions to pfUI. We need to get rid of the blizzard calls
    -- to avoid having them call texture changes and errors due to missing buttons
    _G.ActionButtonDown = pfActionButton
    _G.ActionButtonUp = pfActionButton
    _G.BonusActionButtonDown = function(slot) pfActionButton(slot, nil, "BonusActionBar") end
    _G.BonusActionButtonUp = function(slot) pfActionButton(slot, nil, "BonusActionBar") end
    _G.MultiActionButtonDown = function(bar, slot, slf) pfActionButton(slot, slf, bar) end
    _G.MultiActionButtonUp = function(bar, slot, slf) pfActionButton(slot, slf, bar) end
    _G.ShapeshiftBar_ChangeForm = function(slot) pfActionButton(slot, nil, "ShapeShiftBar") end
  else
    local bindwraps = {
      ["ACTIONBUTTON%d"] = 1,
      ["SHAPESHIFTBUTTON%d"] = 11, -- ShapeShiftBar
      ["BONUSACTIONBUTTON%d"] = 12, -- BonusActionBar
      ["MULTIACTIONBAR1BUTTON%d"] = 6, -- MultiBarBottomLeft
      ["MULTIACTIONBAR2BUTTON%d"] = 5, -- MultiBarBottomRight
      ["MULTIACTIONBAR3BUTTON%d"] = 3, -- MultiBarRight
      ["MULTIACTIONBAR4BUTTON%d"] = 4, -- MultiBarLeft
      ["PFPAGING%d"] = 2,
      ["PFSTANCEONE%d"] = 7,
      ["PFSTANCETWO%d"] = 8,
      ["PFSTANCETHREE%d"] = 9,
      ["PFSTANCEFOUR%d"] = 10,
    }

    -- rebind all existing bindings to our own buttons
    local keybinder = CreateFrame("Frame")
    keybinder:RegisterEvent("UPDATE_BINDINGS")
    keybinder:SetScript("OnEvent", function()
      for name, bar in pairs(bindwraps) do
        for i=1,12 do
          local key = GetBindingKey(format(name, i))
          local button = bars[bar][i]
          if key and button then
            SetOverrideBindingClick(button, false, key, button:GetName(), 'LeftButton')
          end
        end
      end
    end)
  end

  -- handle drag-drop grid
  local grid = CreateFrame("Frame")
  grid:RegisterEvent("ACTIONBAR_SHOWGRID")
  grid:RegisterEvent("ACTIONBAR_HIDEGRID")
  grid:RegisterEvent("PET_BAR_SHOWGRID")
  grid:RegisterEvent("PET_BAR_HIDEGRID")

  grid:SetScript("OnEvent", function()
    if event == "ACTIONBAR_SHOWGRID" then
      pfUI.bars:UpdateGrid(1)
    elseif event == "ACTIONBAR_HIDEGRID" then
      pfUI.bars:UpdateGrid(0)
    elseif event == "PET_BAR_SHOWGRID" then
      pfUI.bars:UpdateGrid(1, "PET")
    elseif event == "PET_BAR_HIDEGRID" then
      pfUI.bars:UpdateGrid(0, "PET")
    end
  end)

  -- reagent counter
  if C.bars.reagents == "1" then
    local reagent_slots = { }
    local reagent_counts = { }
    local reagent_capture = SPELL_REAGENTS.."(.+)"
    local scanner = libtipscan:GetScanner("actionbar")

    local UpdateSlot = function(slot)
      local texture = GetActionTexture(slot)

      -- update buttons that previously had an reagent
      if reagent_slots[slot] and not HasAction(slot) then
        reagent_slots[slot] = nil
        updatecache[slot] = true
      end

      -- search for reagent requirements
      if HasAction(slot) then
        scanner:SetAction(slot)
        local _, reagents = scanner:Find(reagent_capture)

        -- remove reagent counts if existing
        reagents = reagents and string.gsub(reagents, " %((.+)%)", "")

        -- update on reagent requirement changes
        if reagents and reagent_slots[slot] ~= reagents then
          reagent_counts[reagents] = reagent_counts[reagents] or 0
          reagent_slots[slot] = reagents
          updatecache[slot] = true
        end
      end
    end

    -- scan shapeshift forms for reagent requirements (stance bar item count)
    -- stance buttons have slots 121-130, form id = slot - 120
    local stance_slots = { }
    local UpdateStance = function(id)
      local _, sname = GetShapeshiftFormInfo(id)

      -- form no longer exists, clear stale entry
      if not sname then
        if stance_slots[id] then
          stance_slots[id] = nil
          updatecache[120+id] = true
        end
        return
      end

      scanner:SetShapeshift(id)
      local _, reagents = scanner:Find(reagent_capture)
      reagents = reagents and string.gsub(reagents, " %((.+)%)", "")

      -- register for bag-update recounts
      if reagents and reagent_counts[reagents] == nil then
        reagent_counts[reagents] = 0
      end

      -- refresh stance button on reagent changes
      if stance_slots[id] ~= reagents then
        stance_slots[id] = reagents
        updatecache[120+id] = true
      end
    end

    local reagentcounter = CreateFrame("Frame", "pfReagentCounter", UIParent)
    reagentcounter:RegisterEvent("PLAYER_ENTERING_WORLD")
    reagentcounter:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    reagentcounter:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
    reagentcounter:RegisterEvent("BAG_UPDATE")
    reagentcounter:SetScript("OnEvent", function()
      if event == "BAG_UPDATE" then
        this.event = true
      else
        this.scan = 1
      end
    end)

    -- limit events to one per second and smoothen action scanning
    reagentcounter:SetScript("OnUpdate", function()
      -- scan one action slot per frame
      if this.scan and this.scan <= 120 then
        UpdateSlot(this.scan)
        this.scan = this.scan + 1
      elseif this.scan and this.scan <= 130 then
        -- scan one shapeshift form per frame (stance bar)
        UpdateStance(this.scan - 120)
        this.scan = this.scan + 1
      end

      -- trigger reagent count updates after action scans
      if this.scan and this.scan > 130 then
        this.event = true
        this.scan = nil
      end

      -- queue events to fire only once per second
      if not this.event then return end
      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + 1 end

      -- scan for all reagent item counts
      for item in pairs(reagent_counts) do
        reagent_counts[item] = GetItemCount(item)
      end

      -- update all actionbar buttons
      for slot in pairs(reagent_slots) do
        updatecache[slot] = true
      end

      -- refresh stance bar buttons (reagent counts may have changed)
      for id in pairs(stance_slots) do
        updatecache[120+id] = true
      end

      -- remove event trigger
      this.event = nil
    end)

    function IsReagentAction(slot)
      return reagent_slots[slot] and true or nil
    end

    function GetReagentCount(slot)
      return reagent_counts[reagent_slots[slot]]
    end

    -- share stance reagent cache with ButtonSlotUpdate (pfUI.bars exists by now)
    pfUI.bars.stancereagents = stance_slots
    pfUI.bars.stancereagentcounts = reagent_counts
  end
end)
