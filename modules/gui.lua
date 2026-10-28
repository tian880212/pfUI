pfUI:RegisterModule("gui", "vanilla:tbc", function ()
  local Reload, U, CreateConfig, CreateTabFrame, CreateArea, CreateGUIEntry, EntryUpdate

  -- "searchDB" gets populated when CreateConfig is called. The table holds
  -- information about the title, its parent buttons and the frame itself:
  --   searchDB[tostring(frame)][-1] = frame
  --                             [0] = caption
  --                           [1-X] = parent buttons
  local searchDB = {}

  do -- Core Functions/Variables
    function Reload()
      CreateQuestionDialog(T["Some settings need to reload the UI to take effect.\nDo you want to reload now?"], function()
        pfUI.gui.settingChanged = nil
        ReloadUI()
      end)
    end

    U = setmetatable({}, { __index = function(tab,key)
      -- nil key 必须早退：rawset(tab,nil,...) 会抛 "table index is nil" 并中断整个设置页构建。
      -- 上游同样存在 U[c] 这类「c 在当前作用域不存在」的写法（如 Unit Frames → General 的
      -- Font/Group/Colors 三个 header），旧实现因 ufunc 为空时不 rawset 而侥幸无事；
      -- 惰性化后解析器总是返回闭包，若不早退就会命中 rawset(tab,nil)。
      if key == nil then return nil end

      -- 惰性解析：返回的闭包在「被调用时」才查找目标模块的 UpdateConfig。
      -- 原实现是「构建 GUI 条目时」立即解析，而 gui.lua 在 modules.xml 中最先加载，
      -- 姓名板等后加载模块此刻还不存在（pfUI.nameplates 为 nil），ufunc 解析失败为
      -- nil，CreateConfig 改动时只置 settingChanged（重载提示），即时刷新永远失效。
      -- 惰性化后所有模块统一在改动发生时解析，不再受模块加载顺序影响。
      local resolver = function()
        -- search pfUI.uf.frames first - these are the active unit frames
        if pfUI.uf and pfUI.uf.frames then
          for _, f in ipairs(pfUI.uf.frames) do
            if f.label == key and f.id == "" then
              for _, fr in ipairs(pfUI.uf.frames) do
                if fr.label == key then
                  fr:UpdateConfig()
                end
              end
              return
            end
          end
        end
        -- fallback to pfUI[key] for non-unitframe modules
        if type(pfUI[key]) == "table" and pfUI[key].UpdateConfig then
          return pfUI[key]:UpdateConfig()
        elseif pfUI.uf and type(pfUI.uf[key]) == "table" and pfUI.uf[key].UpdateConfig then
          return pfUI.uf[key]:UpdateConfig()
        end
      end
      rawset(tab,key,resolver)
      return resolver
    end})

    function EntryUpdate()
      -- detect and skip during dropdowns
      local focus = GetMouseFocus()
      if focus and focus.parent and focus.parent.menu then
        if this.over then
          this.tex:Hide()
          this.over = nil
        end
        return
      end

      if MouseIsOver(this) and not this.over then
        this.tex:Show()
        this.over = true
      elseif not MouseIsOver(this) and this.over then
        this.tex:Hide()
        this.over = nil
      end
    end

    function CreateConfig(ufunc, caption, category, config, widget, values, skip, named, type, expansion)
      local disabled = expansion and not strfind(expansion, pfUI.expansion)
      if disabled and pfUI_config.gui.showdisabled == "0" then return end

      -- this object placement
      if this.objectCount == nil then
        this.objectCount = 0
      elseif not skip then
        this.objectCount = this.objectCount + 1
        this.lineCount = 1
      end

      if skip then
        if this.lineCount == nil then
          this.lineCount = 1
        end

        if skip then
          this.lineCount = this.lineCount + 1
        end
      end

      if not caption then return end

      -- basic frame
      local frame = CreateFrame("Frame", nil, this)
      frame:SetWidth(this.parent:GetRight()-this.parent:GetLeft()-20)
      frame:SetHeight(22)
      frame:SetPoint("TOPLEFT", this, "TOPLEFT", 5, (this.objectCount*-23)-5)

      -- populate search index
      if caption and this and this.GetParent and widget ~= "button" and widget ~= "header" then
        local id = tostring(frame)

        searchDB[id] = searchDB[id] or { }
        searchDB[id][0] = caption
        searchDB[id][-1] = frame

        -- scrollchild scrollframe  Area        Area        Btton
        -- this        .parent      :GetParent():GetParent().button
        -- this        .parent      :GetParent().button
        local scrollframe = this.parent
        while scrollframe.GetParent and scrollframe:GetParent() and scrollframe:GetParent().button do
          table.insert(searchDB[id], scrollframe:GetParent().button)
          scrollframe = scrollframe:GetParent()
        end
      end

      if not widget or (widget and widget ~= "button") then

        if widget ~= "header" then
          frame:SetScript("OnUpdate", EntryUpdate)
          frame.tex = frame:CreateTexture(nil, "BACKGROUND")
          frame.tex:SetTexture(1,1,1,.05)
          frame.tex:SetAllPoints()
          frame.tex:Hide()
        end

        if not ufunc and widget ~= "header" and C.gui.reloadmarker == "1" then
          caption = caption .. " [|cffffaaaa!|r]"
        end

        -- caption
        frame.caption = frame:CreateFontString("Status", "LOW", "GameFontWhite")
        frame.caption:SetFont(pfUI.font_default, C.global.font_size)
        frame.caption:SetPoint("LEFT", frame, "LEFT", 3, 1)
        frame.caption:SetJustifyH("LEFT")
        frame.caption:SetText(caption)
      end

      if disabled then
        if frame.caption then
          frame.caption:SetText(caption .. " |cffff5555[" .. T["Only"] .. " " .. string.gsub(expansion, ":", "&") .. "]")
        end

        frame:SetAlpha(.5)
        return
      end

      if category == "CVAR" then
        category = {}
        category[config] = tostring(GetCVar(config))
        ufunc = function()
          SetCVar(this:GetParent().config, this:GetParent().category[config])
        end
      end

      if category == "GVAR" then
        category = {}
        category[config] = tostring(_G[config] or 0)

        local U = ufunc

        ufunc = function()
          UIOptionsFrame_Load()
          _G[config] = this:GetChecked() and 1 or nil
          UIOptionsFrame_Save()
          if U then
            U()
          end
        end
      end

      if category == "UVAR" then
        category = {}
        category[config] = _G[config]

        local U = ufunc

        ufunc = function()
          _G[config] = this:GetChecked() and "1" or "0"
          if U then
            U()
          end
        end
      end

      frame.category = category
      frame.config = config

      if widget == "color" then
        -- color picker
        frame.color = CreateFrame("Button", nil, frame)
        frame.color:SetWidth(24)
        frame.color:SetHeight(12)
        CreateBackdrop(frame.color)
        frame.color:SetPoint("RIGHT" , -5, 1)
        frame.color.prev = frame.color.backdrop:CreateTexture("OVERLAY")
        frame.color.prev:SetAllPoints(frame.color)

        local cr, cg, cb, ca = strsplit(",", category[config])
        if not cr or not cg or not cb or not ca then
          cr, cg, cb, ca = 1, 1, 1, 1
        end
        frame.color.prev:SetTexture(cr,cg,cb,ca)

        frame.color:SetScript("OnClick", function()
          local cr, cg, cb, ca = strsplit(",", category[config])
          if not cr or not cg or not cb or not ca then
            cr, cg, cb, ca = 1, 1, 1, 1
          end
          local preview = this.prev

          function ColorPickerFrame.func()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = 1 - OpacitySliderFrame:GetValue()

            r = round(r, 3)
            g = round(g, 3)
            b = round(b, 3)
            a = round(a, 3)

            preview:SetTexture(r,g,b,a)

            if not this:GetParent():IsShown() then
              category[config] = r .. "," .. g .. "," .. b .. "," .. a
              if ufunc then ufunc() else pfUI.gui.settingChanged = true end
            end
          end

          function ColorPickerFrame.cancelFunc()
            preview:SetTexture(cr,cg,cb,ca)
          end

          ColorPickerFrame.opacityFunc = ColorPickerFrame.func
          ColorPickerFrame.element = this
          ColorPickerFrame.opacity = 1 - ca
          ColorPickerFrame.hasOpacity = 1
          ColorPickerFrame:SetColorRGB(cr,cg,cb)
          ColorPickerFrame:SetFrameStrata("DIALOG")
          ShowUIPanel(ColorPickerFrame)
        end)

        -- hide shadows on wrong stratas
        if frame.color.backdrop_shadow then
          frame.color.backdrop_shadow:Hide()
        end
      end

      if widget == "warning" then
        CreateBackdrop(frame, nil, true)
        frame:SetBackdropBorderColor(1,.5,.5)
        frame:SetHeight(50)
        frame:SetPoint("TOPLEFT", 25, this.objectCount * -35)
        this.objectCount = this.objectCount + 2
        frame.caption:SetJustifyH("CENTER")
        frame.caption:SetJustifyV("CENTER")
      end

      if widget == "header" then
        frame:SetBackdrop(nil)
        frame:SetHeight(40)
        this.objectCount = this.objectCount + 1
        frame.caption:SetJustifyH("LEFT")
        frame.caption:SetJustifyV("BOTTOM")
        frame.caption:SetTextColor(.2,1,.8,1)
        frame.caption:SetAllPoints(frame)
      end

      -- use text widget (default)
      if not widget or widget == "text" then
        -- input field
        frame.input = CreateFrame("EditBox", nil, frame)
        CreateBackdrop(frame.input, nil, true)
        frame.input:SetTextInsets(5, 5, 5, 5)
        frame.input:SetTextColor(.2,1,.8,1)
        frame.input:SetJustifyH("RIGHT")

        frame.input:SetWidth(100)
        frame.input:SetHeight(18)
        frame.input:SetPoint("RIGHT" , -3, 0)
        frame.input:SetFontObject(GameFontNormal)
        frame.input:SetAutoFocus(false)
        frame.input:SetText(category[config] or "")
        frame.input:SetScript("OnEscapePressed", function(self)
          this:ClearFocus()
        end)

        frame.input:SetScript("OnTextChanged", function(self)
          if ( type and type ~= "number" ) or tonumber(this:GetText()) then
            if this:GetText() ~= this:GetParent().category[this:GetParent().config] then
              this:GetParent().category[this:GetParent().config] = this:GetText()
              if ufunc then ufunc() else pfUI.gui.settingChanged = true end
            end
            this:SetTextColor(.2,1,.8,1)
          else
            this:SetTextColor(1,.3,.3,1)
          end
        end)

        -- hide shadows on wrong stratas
        if frame.input.backdrop_shadow then
          frame.input.backdrop_shadow:Hide()
        end
      end

      -- use button widget
      if widget == "button" then
        -- 页面第一个控件是 button 时 lineCount 未初始化（仅 elseif/skip 分支赋值），先兜底
        if this.lineCount == nil then this.lineCount = 1 end
        frame.button = CreateFrame("Button", "pfButton", frame, "UIPanelButtonTemplate")
        CreateBackdrop(frame.button, nil, true)
        SkinButton(frame.button)
        frame.button:SetWidth(100)
        frame.button:SetHeight(20)
        frame.button:SetPoint("TOPRIGHT", -(this.lineCount-1) * 105, -5)
        frame.button:SetText(caption)
        frame.button:SetTextColor(1,1,1,1)
        frame.button:SetScript("OnClick", values)

        -- hide shadows on wrong stratas
        if frame.button.backdrop_shadow then
          frame.button.backdrop_shadow:Hide()
        end
      end

      -- use checkbox widget
      if widget == "checkbox" then
        -- input field
        frame.input = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        frame.input:SetNormalTexture("")
        frame.input:SetPushedTexture("")
        frame.input:SetHighlightTexture("")
        CreateBackdrop(frame.input, nil, true)
        frame.input:SetWidth(14)
        frame.input:SetHeight(14)
        frame.input:SetPoint("RIGHT" , -5, 1)
        frame.input:SetScript("OnClick", function ()
          if this:GetChecked() then
            this:GetParent().category[this:GetParent().config] = "1"
          else
            this:GetParent().category[this:GetParent().config] = "0"
          end

          if ufunc then ufunc() else pfUI.gui.settingChanged = true end
        end)

        if category[config] == "1" then frame.input:SetChecked() end

        -- hide shadows on wrong stratas
        if frame.input.backdrop_shadow then
          frame.input.backdrop_shadow:Hide()
        end
      end

      -- use dropdown widget
      if widget == "dropdown" and values then
        frame.input = CreateDropDownButton(nil, frame)
        frame.input:SetBackdrop(nil)
        frame.input.menuframe:SetParent(pfUI.gui)

        frame.input:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
        frame.input:SetWidth(180)
        frame.input:SetMenu(function()
          local menu = {}

          for i, k in pairs(_G.type(values) == "function" and values() or values) do
            local entry = {}
            -- get human readable
            local value, text = strsplit(":", k)
            text = text or value

            entry.text = text
            entry.value = value -- 原始值（材质路径等）暴露给下拉条目，供缩略图预览用（2026-09-18）
            entry.func = function()
              if category and category[config] ~= value then
                category[config] = value
                if ufunc then ufunc() else pfUI.gui.settingChanged = true end
              end
            end

            if category and category[config] == value then
              frame.input.current = i
            end

            table.insert(menu, entry)
          end

          return menu
        end)

        frame.input:SetSelection(frame.input.current)
      end

      -- use list widget
      if widget == "list" then
        frame.del = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        SkinButton(frame.del)
        frame.del:SetWidth(16)
        frame.del:SetHeight(16)
        frame.del:SetPoint("RIGHT", -4, 0)
        frame.del:GetFontString():SetPoint("CENTER", 1, 0)
        frame.del:SetText("-")
        frame.del:SetTextColor(1,.5,.5,1)
        frame.del:SetScript("OnClick", function()
          local sel = frame.input:GetSelection()
          local newconf = ""
          for id, val in pairs({strsplit("#", category[config])}) do
            if id ~= sel then newconf = newconf .. "#" .. val end
          end
          category[config] = newconf
          if ufunc then ufunc() else pfUI.gui.settingChanged = true end
          frame.input:UpdateMenu()
        end)

        frame.add = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        SkinButton(frame.add)
        frame.add:SetWidth(16)
        frame.add:SetHeight(16)
        frame.add:SetPoint("RIGHT", frame.del, "LEFT", -4, 0)
        frame.add:GetFontString():SetPoint("CENTER", 1, 0)
        frame.add:SetText("+")
        frame.add:SetTextColor(.5,1,.5,1)
        frame.add:SetScript("OnClick", function()
          CreateQuestionDialog(T["New entry:"], function()
            category[config] = category[config] .. "#" .. this:GetParent().input:GetText()
            if ufunc then ufunc() else pfUI.gui.settingChanged = true end
            frame.input:UpdateMenu()
          end, false, true)
        end)

        frame.input = CreateDropDownButton(nil, frame)
        frame.input:SetBackdrop(nil)
        frame.input.menuframe:SetParent(pfUI.gui)
        frame.input:SetPoint("RIGHT", frame.add, "LEFT", -2, 0)
        frame.input:SetWidth(140)
        frame.input:SetMenu(function()
          local menu = {}
          for i, val in pairs({strsplit("#", category[config])}) do
            table.insert(menu, { text = val })
          end
          return menu
        end)
      end

      return frame
    end

    local TabFrameOnMouseDown = function()
      pfUI.gui.search:ClearFocus()
    end

    local TabFrameOnClick = function()
      if this.area:IsShown() then
        return
      else
        -- hide all others
        for id, name in pairs(this.parent) do
          if type(name) == "table" and name.area and id ~= "parent" then
            name.area:Hide()
          end
        end
        this.area:Show()
      end
    end

    local width, height = 130, 20
    function CreateTabFrame(parent, title)
      if not parent.area.count then parent.area.count = 0 end

      local f = CreateFrame("Button", nil, parent.area)
      f:SetPoint("TOPLEFT", parent.area, "TOPLEFT", 0, -parent.area.count*height)
      f:SetPoint("BOTTOMRIGHT", parent.area, "TOPLEFT", width, -(parent.area.count+1)*height)
      f.parent = parent

      f:SetScript("OnMouseDown", TabFrameOnMouseDown)
      f:SetScript("OnClick", TabFrameOnClick)

      -- background
      f.bg = f:CreateTexture(nil, "BACKGROUND")
      f.bg:SetAllPoints()

      -- text
      f.text = f:CreateFontString(nil, "LOW", "GameFontWhite")
      f.text:SetFont(pfUI.font_default, C.global.font_size)
      f.text:SetAllPoints()
      f.text:SetText(title)

      -- U element count
      parent.area.count = parent.area.count + 1

      return f
    end

    function CreateArea(parent, title, func)
      -- create drawarea
      local f = CreateFrame("Frame", nil, parent.area)
      f:SetPoint("TOPLEFT", parent.area, "TOPLEFT", width, 0)
      f:SetPoint("BOTTOMRIGHT", parent.area, "BOTTOMRIGHT", 0, 0)

      if not parent.firstarea then
        parent.firstarea = true
      else
        f:Hide()
      end

      f.button = parent[title]

      f.bg = f:CreateTexture(nil, "BACKGROUND")
      f.bg:SetTexture(1,1,1,.05)
      f.bg:SetAllPoints()

      f:SetScript("OnShow", function()
        this.indexed = true
        this.button.text:SetTextColor(.2,1,.8,1)
        this.button.bg:SetTexture(1,1,1,1)
        this.button.bg:SetGradientAlpha("HORIZONTAL", 0,0,0,0,  1,1,1,.05)
      end)

      f:SetScript("OnHide", function()
        this.button.text:SetTextColor(1,1,1,1)
        this.button.bg:SetTexture(0,0,0,0)
      end)

      -- are we a frame with contents?
      if func then
        f.scroll = CreateScrollFrame(nil, f)
        SetAllPointsOffset(f.scroll, f, 2)
        f.scroll.content = CreateScrollChild(nil, f.scroll)
        f.scroll.content.parent = f.scroll
        f.scroll.content:SetScript("OnShow", function()
          if not this.setup then
            func()
            this.setup = true
          end
        end)
      end

      return f
    end

    function CreateGUIEntry(parent, title, populate)
      -- create main menu if not yet exists
      if not pfUI.gui.frames[parent] then
        pfUI.gui.frames[parent] = CreateTabFrame(pfUI.gui.frames, parent)
        if title then
          pfUI.gui.frames[parent].area = CreateArea(pfUI.gui.frames, parent, nil)
        else
          -- populate area when no submenus are given
          pfUI.gui.frames[parent].area = CreateArea(pfUI.gui.frames, parent, populate)
          return
        end
      end

      -- create submenus when title was given
      if title and not pfUI.gui.frames[parent][title] then
        pfUI.gui.frames[parent][title] = CreateTabFrame(pfUI.gui.frames[parent], title)
        pfUI.gui.frames[parent][title].area = CreateArea(pfUI.gui.frames[parent], title, populate)
      end
    end
  end

  do -- GUI Frame
    -- main frame
    pfUI.gui = CreateFrame("Frame", "pfConfigGUI", UIParent)
    pfUI.gui:SetMovable(true)
    pfUI.gui:EnableMouse(true)
    pfUI.gui:RegisterForDrag("LeftButton")
    pfUI.gui:SetWidth(720)
    pfUI.gui:SetHeight(480)
    pfUI.gui:SetFrameStrata("DIALOG")
    pfUI.gui:SetPoint("CENTER", 0, 0)
    pfUI.gui:Hide()

    pfUI.gui:SetScript("OnShow",function()
      pfUI.gui.settingChanged = pfUI.gui.delaySettingChanged
      pfUI.gui.delaySettingChanged = nil

      -- exit unlock mode
      if pfUI.unlock and pfUI.unlock:IsShown() then
        pfUI.unlock:Hide()
      end

      -- exit hoverbind mode
      if pfUI.hoverbind and pfUI.hoverbind:IsShown() then
        pfUI.hoverbind:Hide()
      end
    end)

    pfUI.gui:SetScript("OnHide",function()
      if ColorPickerFrame and ColorPickerFrame:IsShown() then
        ColorPickerFrame:Hide()
      end

      if pfUI.gui.settingChanged then
        pfUI.gui:Reload()
      end
      pfUI.gui:Hide()
    end)

    pfUI.gui:SetScript("OnDragStart",function()
      this:StartMoving()
    end)

    pfUI.gui:SetScript("OnDragStop",function()
      this:StopMovingOrSizing()
    end)

    CreateBackdrop(pfUI.gui, nil, true, .85)
    CreateBackdropShadow(pfUI.gui)
    table.insert(UISpecialFrames, "pfConfigGUI")

    -- make some locals available to thirdparty
    pfUI.gui.Reload = Reload
    pfUI.gui.CreateConfig = CreateConfig
    pfUI.gui.CreateGUIEntry = CreateGUIEntry
    pfUI.gui.UpdaterFunctions = U

    -- decorations
    pfUI.gui.title = pfUI.gui:CreateFontString("Status", "LOW", "GameFontNormal")
    pfUI.gui.title:SetFontObject(GameFontWhite)
    pfUI.gui.title:SetPoint("TOPLEFT", pfUI.gui, "TOPLEFT", 8, -8)
    pfUI.gui.title:SetJustifyH("LEFT")
    pfUI.gui.title:SetFont(pfUI.media["font:Hooge.ttf"], 10)
    pfUI.gui.title:SetText("|cff33ffccpf|rUI")

    pfUI.gui.version = pfUI.gui:CreateFontString("Status", "LOW", "GameFontNormal")
    pfUI.gui.version:SetFontObject(GameFontWhite)
    pfUI.gui.version:SetPoint("LEFT", pfUI.gui.title, "RIGHT", 0, 0)
    pfUI.gui.version:SetJustifyH("LEFT")
    pfUI.gui.version:SetFont(pfUI.media["font:Myriad-Pro.ttf"], 10)
    pfUI.gui.version:SetText("|cff555555[|r" .. pfUI.version.string.. "|cff555555]|r")

    pfUI.gui.close = CreateFrame("Button", "pfQuestionDialogClose", pfUI.gui)
    pfUI.gui.close:SetPoint("TOPRIGHT", -7, -7)
    pfUI.api.CreateBackdrop(pfUI.gui.close)
    pfUI.gui.close:SetHeight(10)
    pfUI.gui.close:SetWidth(10)
    pfUI.gui.close.texture = pfUI.gui.close:CreateTexture("pfQuestionDialogCloseTex")
    pfUI.gui.close.texture:SetTexture(pfUI.media["img:close"])
    pfUI.gui.close.texture:ClearAllPoints()
    pfUI.gui.close.texture:SetAllPoints(pfUI.gui.close)
    pfUI.gui.close.texture:SetVertexColor(1,.25,.25,1)
    pfUI.gui.close:SetScript("OnEnter", function ()
      this.backdrop:SetBackdropBorderColor(1,.25,.25,1)
    end)

    pfUI.gui.close:SetScript("OnLeave", function ()
      pfUI.api.CreateBackdrop(this)
    end)

    pfUI.gui.close:SetScript("OnClick", function()
     this:GetParent():Hide()
    end)

    -- root layer
    pfUI.gui.frames = {}
    pfUI.gui.frames.area = CreateFrame("Frame", nil, pfUI.gui)
    pfUI.gui.frames.area:SetPoint("TOPLEFT", 7, -25)
    pfUI.gui.frames.area:SetPoint("BOTTOMRIGHT", -7, 37)
    CreateBackdrop(pfUI.gui.frames.area)

    -- unlock
    pfUI.gui.unlock = CreateFrame("Button", nil, pfUI.gui)
    pfUI.gui.unlock:SetPoint("TOPLEFT", pfUI.gui.frames.area.backdrop, "BOTTOMLEFT", 0, -5)
    pfUI.gui.unlock:SetWidth(110)
    pfUI.gui.unlock:SetHeight(25)
    pfUI.gui.unlock:SetText(T["Unlock"])
    pfUI.gui.unlock:SetScript("OnClick", function()
      if pfUI.unlock then pfUI.unlock:Show() end
    end)
    SkinButton(pfUI.gui.unlock)

    -- hoverbind
    pfUI.gui.hoverbind = CreateFrame("Button", nil, pfUI.gui)
    pfUI.gui.hoverbind:SetPoint("LEFT", pfUI.gui.unlock, "RIGHT", 5, 0)
    pfUI.gui.hoverbind:SetWidth(110)
    pfUI.gui.hoverbind:SetHeight(25)
    pfUI.gui.hoverbind:SetText(T["Hoverbind"])
    pfUI.gui.hoverbind:SetScript("OnClick", function()
      if pfUI.hoverbind then
        pfUI.hoverbind:Show()
      else
        message("Please enable the Hoverbind module to use this feature.")
      end
    end)

    SkinButton(pfUI.gui.hoverbind)

    -- share
    pfUI.gui.share = CreateFrame("Button", nil, pfUI.gui)
    pfUI.gui.share:SetPoint("LEFT", pfUI.gui.hoverbind, "RIGHT", 5, 0)
    pfUI.gui.share:SetWidth(110)
    pfUI.gui.share:SetHeight(25)
    pfUI.gui.share:SetText(T["Share"])
    pfUI.gui.share:SetScript("OnClick", function()
      if pfShare then
        pfShare:Show()
        pfShareExport:Click()
      else
        message("Please enable the Share module to share your config.")
      end
    end)
    SkinButton(pfUI.gui.share)

    -- searchbar
    local function SearchEntryClick()
      -- clear search focus
      pfUI.gui.search:ClearFocus()

      -- open submenus
      for i=table.getn(this.obj),1,-1 do
        this.obj[i]:Click()
      end

      -- highlight matched entry
      if not this.obj[-1].highlight then
        this.obj[-1].highlight = this.obj[-1]:CreateTexture(nil, "OVERLAY")
        this.obj[-1].highlight:SetAllPoints()
        this.obj[-1].highlight:SetTexture(.2,1,.8,.2)
      end
      this.obj[-1].highlight:Show()
    end

    local function CreateSearchEntry(parent, i)
      local f = CreateFrame("Button", nil, parent)
      f:SetPoint("TOPLEFT", 5, -5 + (i-1)*-25)
      f:SetWidth(565)
      f:SetHeight(20)
      f:SetScript("OnClick", SearchEntryClick)
      f:SetScript("OnUpdate", EntryUpdate)

      f.text = f:CreateFontString("Status", "LOW", "GameFontWhite")
      f.text:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
      f.text:SetAllPoints()
      f.text:SetJustifyH("LEFT")
      f.text:SetJustifyV("CENTER")
      f.text:SetTextColor(.5,.5,.5)

      f.tex = f:CreateTexture(nil, "BACKGROUND")
      f.tex:SetTexture(1,1,1,.05)
      f.tex:SetAllPoints()
      f.tex:Hide()

      return f
    end

    pfUI.gui.search = CreateFrame("EditBox", nil, pfUI.gui)
    pfUI.gui.search:SetPoint("LEFT", pfUI.gui.share, "RIGHT", 5, 0)
    pfUI.gui.search:SetPoint("TOPRIGHT", pfUI.gui.frames.area.backdrop, "BOTTOMRIGHT", 0, -5)
    pfUI.gui.search:SetHeight(25)
    pfUI.gui.search:SetAutoFocus(false)
    pfUI.gui.search:SetTextInsets(5, 5, 5, 5)
    pfUI.gui.search:SetTextColor(.2,1,.8,1)
    pfUI.gui.search:SetJustifyH("CENTER")
    pfUI.gui.search:SetFontObject(GameFontNormal)
    pfUI.gui.search:SetText(T["Search"] .. "...")
    CreateBackdrop(pfUI.gui.search, nil, true)

    pfUI.gui.search:SetScript("OnEscapePressed", function()
      this:ClearFocus()
      if this:GetText() == "" then
        this:SetText(T["Search"].."...")
      end
    end)

    pfUI.gui.search:SetScript("OnTextChanged", function()
      if this:GetText() == T["Search"].."..." then return end
      local defval = "["..T["Search"].."]"

      -- initialize search window
      CreateGUIEntry(defval, nil, function() end)
      pfUI.gui.frames[defval]:Click()

      local scroll = pfUI.gui.frames[defval].area.scroll.content
      local parent = pfUI.gui.frames[defval].area.scroll
      scroll.results = scroll.results or {}

      for i=1,table.getn(scroll.results) do
        scroll.results[i]:Hide()
        if scroll.results[i].obj and scroll.results[i].obj[-1].highlight then
          scroll.results[i].obj[-1].highlight:Hide()
        end
      end

      if strlen(this:GetText()) < 1 then return end

      local i = 1
      local search = strlower(this:GetText())
      for name, obj in pairs(searchDB) do
        local title = obj[0] and strlower(obj[0])
        if strfind(title, search) then
          -- build caption string
          local caption = ""
          for x=table.getn(obj),1,-1 do
            caption = caption .. "|cff33ffcc" .. obj[x].text:GetText() .. "|r » "
          end
          caption = caption .. "|cffffffff" .. obj[0]

          -- build search entry button
          scroll.results[i] = scroll.results[i] or CreateSearchEntry(scroll, i)
          scroll.results[i].obj = obj
          scroll.results[i].text:SetText(caption)
          scroll.results[i]:Show()

          i = i + 1
        end
      end

      -- reload scroll frames
      scroll:Hide()
      scroll:SetHeight(i * 25 )
      scroll:Show()
      parent:SetScrollChild(scroll)
      QueueFunction(function()
        parent:SetVerticalScroll(0)
        parent:UpdateScrollState()
        parent:Scroll()
      end)
    end)

    pfUI.gui.search:SetScript("OnEditFocusGained", function(self)
      if this:GetText() == T["Search"] .. "..." then this:SetText("") end
      if this.indexed then return end
      -- Trigger "OnShow" for each subpage to initialize search index
      for name, frame in pairs(pfUI.gui.frames) do
        if type(frame) == "table" and frame.area and name ~= "parent" then
          frame.area:Show()

          for name, frame in pairs(pfUI.gui.frames[name]) do
            if type(frame) == "table" and frame.area and name ~= "parent" and not frame.area.indexed then
              frame.area:Show()
              frame.area:Hide()
            end
          end

          frame.area:Hide()
        end
      end
      this.indexed = true
    end)
  end

  do -- DropDown Menus
    -- [[ Static Dropdowns ]] --
    pfUI.gui.dropdowns = {
      -- Populated right after this table is built: only languages whose
      -- translation table was actually loaded get an entry, so the dropdown can
      -- never offer a language that would silently fall back to English.
      ["languages"] = {},
      ["fonts"] = {
        "Interface\\AddOns\\pfUI\\fonts\\BigNoodleTitling.ttf:BigNoodleTitling",
        "Interface\\AddOns\\pfUI\\fonts\\Continuum.ttf:Continuum",
        "Interface\\AddOns\\pfUI\\fonts\\DieDieDie.ttf:DieDieDie",
        "Interface\\AddOns\\pfUI\\fonts\\Expressway.ttf:Expressway",
        "Interface\\AddOns\\pfUI\\fonts\\Homespun.ttf:Homespun",
        "Interface\\AddOns\\pfUI\\fonts\\Hooge.ttf:Hooge",
        "Interface\\AddOns\\pfUI\\fonts\\Myriad-Pro.ttf:Myriad-Pro",
        "Interface\\AddOns\\pfUI\\fonts\\PT-Sans-Narrow-Bold.ttf:PT-Sans-Narrow-Bold",
        "Interface\\AddOns\\pfUI\\fonts\\PT-Sans-Narrow-Regular.ttf:PT-Sans-Narrow-Regular"
      },
      ["border"] = {
        "-1:" .. T["Default"],
        "0:" .. T["None"],
        "1:1 " .. T["Pixel"],
        "2:2 " .. T["Pixel"],
        "3:3 " .. T["Pixel"],
        "4:4 " .. T["Pixel"],
        "5:5 " .. T["Pixel"],
      },
      ["fontstyle"] = {
        "NONE:" .. T["None"],
        "OUTLINE:" .. T["Outline"],
        "THICKOUTLINE:" .. T["Thick Outline"],
        "MONOCHROME:" .. T["Monochrome"],
      },
      ["spacing"] = {
        "0:0" .. T["None"],
        "1:1 " .. T["Pixel"],
        "2:2 " .. T["Pixel"],
        "3:3 " .. T["Pixel"],
        "4:4 " .. T["Pixel"],
        "5:5 " .. T["Pixel"],
        "6:6 " .. T["Pixel"],
        "7:7 " .. T["Pixel"],
        "8:8 " .. T["Pixel"],
        "9:9 " .. T["Pixel"],
      },
      ["maxraid"] = {
        "5:5",
        "10:10",
        "15:15",
        "20:20",
        "25:25",
        "30:30",
        "35:35",
        "40:40",
      },
      ["raidpetmax"] = {
        "5:5",
        "10:10",
        "15:15",
        "20:20",
        "25:25",
        "30:30",
        "35:35",
        "40:40",
      },
      ["scaling"] = {
        "0:" .. T["Off"],
        "4:" .. T["Huge (PixelPerfect)"],
        "5:" .. T["Large"],
        "6:" .. T["Medium"],
        "7:" .. T["Small"],
        "8:" .. T["Tiny (PixelPerfect)"],
      },
      ["abbrevnum"] = {
        "0:" .. T["Full Numbers (4250)"],
        "1:" .. T["Abbreviate 2 Decimals (4.25k)"],
        "2:" .. T["Abbreviate 1 Decimal (4.2k)"],
        "3:" .. T["Chinese 2 Decimals (4.25万)"],
        "4:" .. T["Chinese 1 Decimal (4.2万)"],
      },
      ["castbardecimals"] = {
        "1:" .. T["1 Decimal (2.1)"],
        "2:" .. T["2 Decimals (2.14)"],
      },
      ["orientation"] = {
        "HORIZONTAL:" .. T["Horizontal"],
        "VERTICAL:" .. T["Vertical"],
      },
      ["uf_animationspeed"] = {
        "1:" .. T["Instant"],
        "2:" .. T["Very Fast"],
        "3:" .. T["Fast"],
        "5:" .. T["Medium"],
        "8:" .. T["Slow"],
        "13:" .. T["Very Slow"],
      },
      ["xpanchors"] = {
        "__NONONIL__:" .. T["No Anchor"],
        "pfChatLeft:" .. T["Left Chat Frame"],
        "pfChatRight:" .. T["Right Chat Frame"],
        "pfActionBarMain:" .. T["Main Actionbar"],
        "pfActionBarTop:" .. T["Top Actionbar"],
        "pfActionBarLeft:" .. T["Left Actionbar"],
        "pfActionBarRight:" .. T["Right Actionbar"],
        "pfActionBarVertical:" .. T["Vertical Actionbar"],
        "pfExperienceBar:" .. T["Experience Bar"],
        "pfReputationBar:" .. T["Reputation Bar"],
        "pfPlayer:" .. T["Player Unitframe"],
        "pfMinimap:" .. T["Minimap"],
        "pfPanelMinimap:" .. T["Minimap Panel"],
      },
      ["uf_bartexture"] = {
        "Interface\\AddOns\\pfUI\\img\\bar:pfUI",
        "Interface\\AddOns\\pfUI\\img\\bar_tukui:TukUI",
        "Interface\\AddOns\\pfUI\\img\\bar_elvui:ElvUI",
        "Interface\\AddOns\\pfUI\\img\\bar_gradient:Gradient",
        "Interface\\AddOns\\pfUI\\img\\bar_striped:Striped",
        "Interface\\TargetingFrame\\UI-StatusBar:Wow Status",
        "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar:Wow Skill"
      },
      ["uf_threattexture"] = (function()
        -- 注意：此 IIFE 处于 pfUI.gui.dropdowns 表构造内部，此时 pfUI.gui.dropdowns 自身
        -- 尚未完成赋值，不可引用 pfUI.gui.dropdowns.xxx（会 nil 索引崩溃，进而中断
        -- LoadModule 导致所有头像框回退原生）。标准纹理在此内联，再追加 CustomMedia。
        local std = {
          "Interface\\AddOns\\pfUI\\img\\bar:pfUI",
          "Interface\\AddOns\\pfUI\\img\\bar_tukui:TukUI",
          "Interface\\AddOns\\pfUI\\img\\bar_elvui:ElvUI",
          "Interface\\AddOns\\pfUI\\img\\bar_gradient:Gradient",
          "Interface\\AddOns\\pfUI\\img\\bar_striped:Striped",
          "Interface\\TargetingFrame\\UI-StatusBar:Wow Status",
          "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar:Wow Skill"
        }
        local t = {}
        for _, v in ipairs(std) do table.insert(t, v) end
        for letter in string.gmatch("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ".") do
          table.insert(t, "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-" .. letter .. ".tga:pfUI-" .. letter)
        end
        return t
      end)(),
      ["uf_rangecheckinterval"] = {
        "1:" .. T["Very Fast"],
        "2:" .. T["Fast"],
        "4:" .. T["Medium"],
        "8:" .. T["Slow"],
        "16:" .. T["Very Slow"],
      },
      ["uf_rangecheck_mode"] = {
        "vanilla:" .. T["Vanilla (Spellbook)"],
        "unitxp:" .. T["UnitXP (Precise)"],
      },		
      ["uf_raidlayout"] = {
        "1x40:" .. "1x40",
        "2x20:" .. "2x20",
        "4x10:" .. "4x10",
        "5x8:" ..  "5x8",
        "8x5:" ..  "8x5",
        "10x4:" .. "10x4",
        "20x2:" .. "20x2",
        "40x1:" .. "40x1",
        "custom:" .. T["Custom"],
      },
      ["uf_raidfill"] = {
        "VERTICAL:" .. T["Vertical Down"],
        "VERTICAL_REVERSE:" .. T["Vertical Up"],
        "HORIZONTAL:" .. T["Horizontal Right"],
        "HORIZONTAL_REVERSE:" .. T["Horizontal Left"],
      },
      ["uf_powerbar_position"] = {
        "TOPLEFT:" .. T["Left"],
        "TOP:" .. T["Center"],
        "TOPRIGHT:" .. T["Right"]
      },
      ["uf_portrait_position"] = {
        "bar:" .. T["Healthbar Embedded"],
        "left:" .. T["Left"],
        "right:" .. T["Right"],
        "off:" .. T["Disabled"]
      },
      ["uf_happiness"] = {
        "0:" .. T["Disabled"],
        "1:" .. T["Face"],
        "2:" .. T["Rank"]
      },
      ["uf_buff_position"] = {
        "TOPLEFT:" .. T["Top Left"],
        "TOPRIGHT:" .. T["Top Right"],
        "BOTTOMLEFT:" .. T["Bottom Left"],
        "BOTTOMRIGHT:" .. T["Bottom Right"],
        "off:" .. T["Disabled"]
      },
      ["uf_debuff_indicator"] = {
        "0:" .. T["Disabled"],
        "1:" .. T["Legacy"],
        "2:" .. T["Glow"],
        "3:" .. T["Square"],
        "4:" .. T["Icon"]
      },
      ["uf_debuff_indicator_size"] = {
        ".10:10%",
        ".25:25%",
        ".35:35%",
        ".50:50%",
        ".65:65%",
        ".75:75%",
        ".90:90%",
      },
      ["percent_small"] = {
        "0:0%",
        ".05:5%",
        ".10:10%",
        ".15:15%",
        ".20:20%",
        ".25:25%",
        ".30:30%",
        ".35:35%",
        ".40:40%",
        ".45:45%",
        ".50:50%",
        ".55:55%",
        ".60:60%",
        ".65:65%",
        ".70:70%",
        ".75:75%",
        ".80:80%",
        ".85:85%",
        ".90:90%",
        ".95:95%",
        "1:100%",
      },
      ["uf_overheal"] = {
        "0:0%",
        "10:10%",
        "20:20%",
        "30:30%",
        "40:40%",
        "50:50%",
        "60:60%",
        "70:70%",
        "80:80%",
        "90:90%",
        "100:100%",
      },
      ["uf_layout"] = {
        "default:" .. T["Default"],
        "tukui:TukUI"
      },
      ["raidmarker_grow"] = {
        "down:" .. T["Down"],
        "up:" .. T["Up"],
      },							 		
      ["combo_grow"] = {
        "down:" .. T["Down"],
        "up:" .. T["Up"],
        "right:" .. T["Right"],
        "left:" .. T["Left"],
      },
      ["combo_style"] = {
        "pips:" .. T["Blocks"],
        "numbers:" .. T["Numbers"],
      },
      -- 能量条数值格式
      ["comboenergy_format"] = {
        "0:" .. T["Current Value"],
        "1:" .. T["Current / Max"],
        "2:" .. T["Percent"],
      },
      -- 能量条数值对齐
      ["comboenergy_align"] = {
        "left:" .. T["Left"],
        "center:" .. T["Center"],
        "right:" .. T["Right"],
      },
      -- 纯色 + 全部材质（做法同 uf_threattexture：此表构造期间 pfUI.gui.dropdowns
      -- 自身尚未赋值，不能引用 uf_bartexture，必须把标准纹理内联后再追加 pfUI-A..Z）
      ["combo_texture"] = (function()
        local t = { "solid:" .. T["Solid Color"] }
        local std = {
          "Interface\\AddOns\\pfUI\\img\\bar:pfUI",
          "Interface\\AddOns\\pfUI\\img\\bar_tukui:TukUI",
          "Interface\\AddOns\\pfUI\\img\\bar_elvui:ElvUI",
          "Interface\\AddOns\\pfUI\\img\\bar_gradient:Gradient",
          "Interface\\AddOns\\pfUI\\img\\bar_striped:Striped",
          "Interface\\TargetingFrame\\UI-StatusBar:Wow Status",
          "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar:Wow Skill"
        }
        for _, v in ipairs(std) do table.insert(t, v) end
        for letter in string.gmatch("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ".") do
          table.insert(t, "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-" .. letter .. ".tga:pfUI-" .. letter)
        end
        return t
      end)(),
      ["uf_color"] = {
        "0:" .. T["Class"],
        "1:" .. T["Custom"],
        "2:" .. T["Health"],
      },
      ["uf_texts"] = {
        "none:" .. T["Disable"],
        "unit:" .. T["Unit String"],
        "unitrev:" .. T["Unit String (Reverse)"],
        "name:" .. T["Name"],
        "nameshort:" .. T["Name (Short)"],
        "level:" .. T["Level"],
        "class:" .. T["Class"],
        "namehealth:" .. T["Name | Health Missing"],
        "namehealthbreak:" .. T["Name (Linebreak) -Health Missing"],
        "shortnamehealth:" .. T["Name (Short) | Health Missing"],
        "healthdyn:" .. T["Health - Auto"],
        "health:" .. T["Health - Current"],
        "healthmax:" .. T["Health - Max"],
        "healthperc:" .. T["Health - Percentage"],
        "healthmiss:" .. T["Health - Missing"],
        "healthminmax:" .. T["Health - Min/Max"],
        "powerdyn:" .. T["Mana - Auto"],
        "power:" .. T["Mana - Current"],
        "powermax:" .. T["Mana - Max"],
        "powerperc:" .. T["Mana - Percentage"],
        "powermiss:" .. T["Mana - Missing"],
        "powerminmax:" .. T["Mana - Min/Max"],
      },
      ["hpformat"] = {
        "percent:" .. T["Percent"],
        "cur:" .. T["Current HP"],
        "curperc:" .. T["Current HP | Percent"],
        "curmax:" .. T["Current HP - Max HP"],
        "curmaxs:" .. T["Current HP / Max HP"],
        "curmaxperc:" .. T["Current HP - Max HP | Percent"],
        "curmaxpercs:" .. T["Current HP / Max HP | Percent"],
        "deficit:" .. T["Deficit"],
      },
      ["panel_values"] = {
        "none:" .. T["Disable"],
        "time:" .. T["Clock"],
        "fps:" .. T["FPS & Ping"],
        "exp:" .. T["XP Percentage"],
        "gold:" .. T["Gold"],
        "friends:" .. T["Friends Online"],
        "guild:" .. T["Guild Online"],
        "durability:" .. T["Item Durability"],
        "zone:" .. T["Zone Name"],
        "combat:" .. T["Combat Timer"],
        "ammo:" .. T["Ammo Counter"],
        "soulshard:" .. T["Soulshard Counter"],
        "bindlocation:" .. T["Hearth"],
        "thistletea:" .. T["Thistle Tea"],
        "flashpowder:" .. T["Flash Powder"],
        "blindpowder:" .. T["Blinding Powder"],
        "bagspace:" .. T["Bagspace"]
      },
      ["tooltip_position"] = {
        "bottom:" .. T["Bottom"],
        "chat:" .. T["Dodge"],
        "cursor:" .. T["Cursor"],
        "free:" .. T["Custom"]
      },
      ["tooltip_align"] = {
        "native:" .. T["Native"],
        "top:" .. T["Top"],
        "left:" .. T["Left"],
        "right:" .. T["Right"]
      },
      ["debuffposition"] = {
        "TOP:" .. T["Top"],
        "BOTTOM:" .. T["Bottom"],
      },
      ["gmserver_text"] = {
        "elysium:" .. T["Elysium Based Core"],
      },
      ["buffbarfilter"] = {
        "none:"      .. T["None"],
        "whitelist:" .. T["Whitelist"],
        "blacklist:" .. T["Blacklist"],
      },
      ["buffbarsort"] = {
        "asc:" .. T["Ascending"],
        "desc:" .. T["Descending"],
      },
      ["minimap_cords_position"] = {
        "topleft:" .. T["Top Left"],
        "topright:" .. T["Top Right"],
        "bottomleft:" .. T["Bottom Left"],
        "bottomright:" .. T["Bottom Right"],
      },
      ["minimap_cords_visibility"] = {
        "mouseover:" .. T["Mouseover"],
        "on:" .. T["Enable"],
        "off:" .. T["Disable"]
      },
      ["minimap_zone_visibility"] = {
        "mouseover:" .. T["Mouseover"],
        "on:" .. T["Enable"],
        "off:" .. T["Disable"]
      },
      ["positions"] = {
        "TOPLEFT:" .. T["Top Left"],
        "TOP:" .. T["Top"],
        "TOPRIGHT:" .. T["Top Right"],
        "LEFT:" .. T["Left"],
        "CENTER:" .. T["Center"],
        "RIGHT:" .. T["Right"],
        "BOTTOMLEFT:" .. T["Bottom Left"],
        "BOTTOM:" .. T["Bottom"],
        "BOTTOMRIGHT:" .. T["Bottom Right"],
      },
      ["actionbuttonanimations"] = {
        "none:" .. T["None"],
        "zoomfade:" .. T["Zoom & Fade"],
        "shrinkreturn:" .. T["Shrink & Return"],
        "elasticzoom:" .. T["Elastic Zoom"],
        "wobblezoom:" .. T["Wobble Zoom"],
      },
      ["animationmode"] = {
        "keypress:" .. T["On Key Press"],
        "statechange:" .. T["On State Change"]
      },
      ["actionbarbuttons"] = {
        "1","2","3","4","5","6","7","8","9","10","11","12"
      },
      ["addonbuttons_position"] = {
        "bottom:" .. T["Bottom"],
        "left:" .. T["Left"],
        "top:" .. T["Top"],
        "right:" .. T["Right"]
      },
      ["xp_display"] = {
        "XPFLEX:" .. T["Automatic"],
        "XP:" .. T["Experience"],
        "REP:" .. T["Tracked Reputation"],
        "FLEX:" .. T["Last Reputation"],
        "PETXP:" .. T["Pet Experience"],
        "DISABLED:" .. T["Disabled"],
      },
      ["xp_position"] = {
        "BOTTOM:" .. T["Bottom"],
        "LEFT:" .. T["Left"],
        "TOP:" .. T["Top"],
        "RIGHT:" .. T["Right"]
      },
      ["glowintensity"] = {
        "8:" .. T["Tiny"],
        "16:" .. T["Small"],
        "32:" .. T["Medium"],
        "64:" .. T["Large"],
        "128:" .. T["Huge"],
      },
      ["mapcircle"] = {
        "5:" .. T["Tiny"],
        "3:" .. T["Small"],
        "1:" .. T["Medium"],
        "-1:" .. T["Large"],
        "-3:" .. T["Huge"],
      },
      ["maptooltip"] = {
        ".10:10%",
        ".20:20%",
        ".30:30%",
        ".40:40%",
        ".50:50%",
        ".60:60%",
        ".70:70%",
        ".80:80%",
        ".90:90%",
        "1:100%",
        "0:" .. T["World Map Scale"],
      },
      ["textalign"] = {
        "LEFT:" .. T["Left"],
        "CENTER:" .. T["Center"],
        "RIGHT:" .. T["Right"],
      },
      ["gryphons"] = {
        "None:"..T["None"],
        "Gryphon:"..T["Gryphon"],
        "Lion:"..T["Lion"],
      }
    }

    -- add locale dependent client fonts to the list
    if GetLocale() == "enUS" or GetLocale() == "frFR" or GetLocale() == "deDE" or GetLocale() == "ruRU" then
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\ARIALN.TTF:ARIALN")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\FRIZQT__.TTF:FRIZQT")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\MORPHEUS.TTF:MORPHEUS")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\SKURRI.TTF:SKURRI")
    elseif GetLocale() == "koKR" then
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\2002.TTF:2002")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\2002B.TTF:2002B")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\ARIALN.TTF:ARIALN")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\FRIZQT__.TTF:FRIZQT")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\K_Damage.TTF:K_Damage")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\K_Pagetext.TTF:K_Pagetext")
    elseif GetLocale() == "zhCN" then
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\ARIALN.TTF:ARIALN")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\FRIZQT__.TTF:FRIZQT")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\FZBWJW.TTF:FZBWJW")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\FZJZJW.TTF:FZJZJW")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\FZLBJW.TTF:FZLBJW")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\FZXHJW.TTF:FZXHJW")
      table.insert(pfUI.gui.dropdowns.fonts, "Fonts\\FZXHLJW.TTF:FZXHLJW")
    end

    pfUI.gui.dropdowns.loot_rarity = {}
    -- 全局材质选择（外观设置）：off = 不批量修改；其余与单位框材质列表一致并追加 CustomMedia
    pfUI.gui.dropdowns.global_bartexture = { "off:" .. T["Off"] .. "（各处独立设置）" }
    for _, v in ipairs(pfUI.gui.dropdowns.uf_bartexture) do
      table.insert(pfUI.gui.dropdowns.global_bartexture, v)
    end
    for letter in string.gmatch("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ".") do
      table.insert(pfUI.gui.dropdowns.global_bartexture,
        "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-" .. letter .. ".tga:pfUI-" .. letter)
    end
    for i=0, getn(_G.ITEM_QUALITY_COLORS)-2  do
      local entry = string.format("%d:%s", i, string.format("%s%s%s", _G.ITEM_QUALITY_COLORS[i].hex, _G[string.format("ITEM_QUALITY%d_DESC",i)], FONT_COLOR_CODE_CLOSE))
      table.insert(pfUI.gui.dropdowns.loot_rarity, entry)
    end

    pfUI.gui.dropdowns.screenshot_battle = {
      "0:".._G.NONE,
      "1:"..T["Won"],
      "2:"..T["Ended"],
    }
    pfUI.gui.dropdowns.screenshot_loot = {"0:".._G.NONE}
    for i=3, 5 do
      local entry = string.format("%d:%s", i, string.format("%s%s%s", _G.ITEM_QUALITY_COLORS[i].hex, _G[string.format("ITEM_QUALITY%d_DESC",i)], FONT_COLOR_CODE_CLOSE))
        table.insert(pfUI.gui.dropdowns.screenshot_loot, entry)
    end
  end

  -- Language dropdown: built from the translation tables that are really
  -- present (see init\env.xml). A hardcoded list used to advertise languages
  -- that ship no data, and picking one just fell back to the client locale.
  -- pairs() has no defined order, so sort to keep the list stable.
  for code, name in pairs({
    ["deDE"] = "German",
    ["enGB"] = "British English",
    ["enUS"] = "English",
    ["esES"] = "Spanish",
    ["esMX"] = "Spanish (Latin American)",
    ["frFR"] = "French",
    ["koKR"] = "Korean",
    ["ruRU"] = "Russian",
    ["zhCN"] = "Chinese (Simplified)",
    ["zhTW"] = "Chinese (Traditional)",
  }) do
    if pfUI_translation[code] then
      table.insert(pfUI.gui.dropdowns.languages, code .. ":" .. name)
    end
  end
  table.sort(pfUI.gui.dropdowns.languages)

  do -- Generate Config UI
    CreateGUIEntry(T["About"], nil, function()
      -- read data
      local lang = T["Unknown"]
      for _, entry in pairs(pfUI.gui.dropdowns.languages) do
        local short, full = strsplit(":", entry)
        if short == C.global.language then
          lang = full
        end
      end

      -- draw pfUI logo
      local function draw(p, fx, fy, tx, ty, r, g, b, a)
        local t = p:CreateTexture(nil, "OVERLAY")
        t:SetTexture(r,g,b,a)
        t:SetPoint("TOPLEFT", fx, fy)
        t:SetPoint("BOTTOMRIGHT", p, "TOPLEFT", tx, ty)
      end

      local x, y, p = 250, 55, 10  -- startx, starty, pencilsize
      draw(this, x,     -y-2*p, x+p,      -y-7*p, .2, 1, .8, 1)
      draw(this, x+p,   -y-2*p, x+2*p,    -y-3*p, .2, 1, .8, 1)
      draw(this, x+p,   -y-4*p, x+2*p,    -y-5*p, .2, 1, .8, 1)
      draw(this, x+2*p, -y,     x+3*p,    -y-5*p, .2, 1, .8, 1)
      draw(this, x+3*p, -y,     x+4*p,    -y-1*p, .2, 1, .8, 1)
      draw(this, x+p,   -y-2*p, x+4*p,    -y-3*p, .2, 1, .8, 1)
      draw(this, x+4*p, -y,     x+5*p,    -y-5*p, 1,  1, 1,  1)
      draw(this, x+5*p, -y-4*p, x+5*p+p,  -y-5*p, 1,  1, 1,  1)
      draw(this, x+6*p, -y,     x+7*p,    -y-p,   1,  1, 1,  1)
      draw(this, x+6*p, -y-2*p, x+7*p,    -y-5*p, 1,  1, 1,  1)

      -- version
      this.versionc = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.versionc:SetFont(pfUI.font_default, C.global.font_size)
      this.versionc:SetPoint("TOPLEFT", 200, -170)
      this.versionc:SetWidth(200)
      this.versionc:SetJustifyH("LEFT")
      this.versionc:SetText(T["Version"] .. ":")

      this.version = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.version:SetFont(pfUI.font_default, C.global.font_size)
      this.version:SetPoint("TOPRIGHT", 375, -170)
      this.version:SetWidth(200)
      this.version:SetJustifyH("RIGHT")

      this.update = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.update:SetFont(pfUI.font_default, C.global.font_size)
      this.update:SetPoint("TOPLEFT", 200, -140)
      this.update:SetPoint("TOPRIGHT", 375, -140)
      this.update:SetJustifyH("CENTER")
      this.update:SetTextColor(.2,1,.8)

      this.screenc = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.screenc:SetFont(pfUI.font_default, C.global.font_size)
      this.screenc:SetPoint("TOPLEFT", 200, -200)
      this.screenc:SetWidth(200)
      this.screenc:SetJustifyH("LEFT")
      this.screenc:SetText(T["Resolution"] .. ":")

      this.screen = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.screen:SetFont(pfUI.font_default, C.global.font_size)
      this.screen:SetPoint("TOPRIGHT", 375, -200)
      this.screen:SetWidth(200)
      this.screen:SetJustifyH("RIGHT")

      this.scalec = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.scalec:SetFont(pfUI.font_default, C.global.font_size)
      this.scalec:SetPoint("TOPLEFT", 200, -220)
      this.scalec:SetWidth(200)
      this.scalec:SetJustifyH("LEFT")
      this.scalec:SetText(T["Scaling"] .. ":")

      this.scale = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.scale:SetFont(pfUI.font_default, C.global.font_size)
      this.scale:SetPoint("TOPRIGHT", 375, -220)
      this.scale:SetWidth(200)
      this.scale:SetJustifyH("RIGHT")

      this.clientc = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.clientc:SetFont(pfUI.font_default, C.global.font_size)
      this.clientc:SetPoint("TOPLEFT", 200, -250)
      this.clientc:SetWidth(200)
      this.clientc:SetJustifyH("LEFT")
      this.clientc:SetText(T["Gameclient"] .. ":")

      this.client = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.client:SetFont(pfUI.font_default, C.global.font_size)
      this.client:SetPoint("TOPRIGHT", 375, -250)
      this.client:SetWidth(200)
      this.client:SetJustifyH("RIGHT")

      this.langc = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.langc:SetFont(pfUI.font_default, C.global.font_size)
      this.langc:SetPoint("TOPLEFT", 200, -270)
      this.langc:SetWidth(200)
      this.langc:SetJustifyH("LEFT")
      this.langc:SetText(T["Language"] .. ":")
      this.lang = this:CreateFontString("Status", "LOW", "GameFontWhite")
      this.lang:SetFont(pfUI.font_default, C.global.font_size)
      this.lang:SetPoint("TOPRIGHT", 375, -270)
      this.lang:SetWidth(200)
      this.lang:SetJustifyH("RIGHT")

      -- info updater
      local f = CreateFrame("Frame", nil, this)
      f:SetScript("OnUpdate", function()
        if ( this.tick or 0) > GetTime() then return else this.tick = GetTime() + 1 end

        local parent = this:GetParent()
        local localversion  = tonumber(pfUI.version.major*10000 + pfUI.version.minor*100 + pfUI.version.fix)
        local remoteversion = tonumber(pfUI_init.updateavailable) or 0
        if localversion < remoteversion then
          parent.update:SetText("|cffffffff[|r!|cffffffff] " .. T["A new version is available"])
        end

        parent.version:SetText(pfUI.version.string)
        parent.screen:SetText(GetCVar("gxResolution"))
        parent.scale:SetText(round(UIParent:GetEffectiveScale(),2))
        parent.client:SetText(GetBuildInfo() .. " (" .. GetLocale() .. ")")
        parent.lang:SetText(lang)
      end)

      local github = CreateFrame("Button", nil, this)
      github:SetPoint("TOPLEFT", 200, -335)
      github:SetWidth(100)
      github:SetHeight(20)
      github:SetText(T["GitHub"])
      github:SetScript("OnClick", function()
        pfUI.chat.urlcopy.CopyText("https://github.com/me0wg4ming/pfUI")
      end)
      SkinButton(github)

      local website = CreateFrame("Button", nil, this)
      website:SetPoint("TOPLEFT", 310, -335)
      website:SetWidth(100)
      website:SetHeight(20)
      website:SetText(T["Website"])
      website:SetScript("OnClick", function()
        pfUI.chat.urlcopy.CopyText("https://www.kookapp.cn/app/channels/5574114869722737/1993451221059869/87554418060296960")
      end)
      SkinButton(website)
    end)

    CreateGUIEntry(T["Settings"], T["General"], function()
      local header = CreateConfig(nil, T["Profile"], nil, nil, "header")
      header:GetParent().objectCount = header:GetParent().objectCount - 1
      header:SetHeight(20)

      CreateConfig(function() return end, T["Select profile"], C.global, "profile", "dropdown", function()
        local values = {}
        for name, config in pairs(pfUI_profiles) do table.insert(values, name) end
        table.sort(values)
        return values
      end, false, "Profile")

      -- load profile
      CreateConfig(nil, T["Load profile"], C.global, "profile", "button", function()
        if C.global.profile and pfUI_profiles[C.global.profile] then
          CreateQuestionDialog(T["Load profile"] .. " '|cff33ffcc" .. C.global.profile .. "|r'?", function()
            local selp = C.global.profile
            local rchat = C.chat.right.enable

            -- load profile
            _G["pfUI_config"] = CopyTable(pfUI_profiles[C.global.profile])

            -- restore values
            pfUI:UpdateConfig("global", nil, "profile", selp)
            pfUI:UpdateConfig("chat", "right", "enable", rchat)

            -- add default values
            pfUI:LoadConfig()

            ReloadUI()
          end)
        end
      end)

      -- delete profile
      CreateConfig(nil, T["Delete profile"], C.global, "profile", "button", function()
        if C.global.profile and pfUI_profiles[C.global.profile] then
          CreateQuestionDialog(T["Delete profile"] .. " '|cff33ffcc" .. C.global.profile .. "|r'?", function()
            pfUI_profiles[C.global.profile] = nil
            this:GetParent():Hide()
          end)
        end
      end, true)

      -- save profile
      CreateConfig(nil, T["Save profile"], C.global, "profile", "button", function()
        if C.global.profile and pfUI_profiles[C.global.profile] then
          CreateQuestionDialog(T["Save current settings to profile"] .. " '|cff33ffcc" .. C.global.profile .. "|r'?", function()
            if pfUI_profiles[C.global.profile] then
              pfUI_profiles[C.global.profile] = CopyTable(C)
            end
            this:GetParent():Hide()
          end)
        end
      end, true)

      -- create profile
      CreateConfig(nil, T["Create Profile"], C.global, "profile", "button", function()
        CreateQuestionDialog(T["Please enter a name for the new profile.\nExisting profiles sharing the same name will be overwritten."],
        function()
          local profile = this:GetParent().input:GetText()
          local bad = string.gsub(profile,"([%w%s]+)","")
          if bad~="" then
            message("\"" .. bad .. "\" " .. T["is not allowed in profile name"])
          else
            profile = (string.gsub(profile,"^%s*(.-)%s*$", "%1"))
            if profile and profile ~= "" then
              pfUI_profiles[profile] = CopyTable(C)
              this:GetParent():Hide()
            end
          end
        end, false, true)
      end, true)

      -- add invisible font to disable combat messages
      local combatfonts = CopyTable(pfUI.gui.dropdowns.fonts)
      table.insert(combatfonts, "Interface\\AddOns\\pfUI\\fonts\\AdobeBlank.ttf:Invisible")

      CreateConfig(nil, T["Settings"], nil, nil, "header")
      CreateConfig(nil, T["Language"], C.global, "language", "dropdown", pfUI.gui.dropdowns.languages)
      CreateConfig(U["pixelperfect"], T["Enable UI-Scale"], C.global, "pixelperfect", "dropdown", pfUI.gui.dropdowns.scaling)
      CreateConfig(nil, T["Use Original Game Fonts"], C.global, "font_blizzard", "checkbox")
      CreateConfig(nil, T["Enable Region Compatible Font"], C.global, "force_region", "checkbox")
      CreateConfig(nil, T["Standard Text Font"], C.global, "font_default", "dropdown", pfUI.gui.dropdowns.fonts)
      CreateConfig(nil, T["Standard Text Font Size"], C.global, "font_size")
      CreateConfig(nil, T["3D World Unit Font"], C.global, "font_unit_name", "dropdown", pfUI.gui.dropdowns.fonts)
      CreateConfig(nil, T["Scrolling Combat Text Font"], C.global, "font_combat", "dropdown", combatfonts)
      CreateConfig(nil, T["Enable Offscreen Frame Positions"], C.global, "offscreen", "checkbox")

      -- 解锁模式吸附对齐（modules/unlock.lua，拖动时即时读取配置，不需要重载）
      CreateConfig(function() return end, T["Snap Frames In Unlock Mode"], C.global, "unlock_snap", "checkbox")
      CreateConfig(function() return end, T["Snap Distance"], C.global, "unlock_snap_distance", "text", nil, nil, nil, "number")
      CreateConfig(nil, T["Display Addon Errors In Chat"], C.global, "errors", "checkbox")
      CreateConfig(nil, T["Use Single Line UIErrors Frame"], C.global, "errors_limit", "checkbox")
      CreateConfig(nil, T["Disable Errors in UIErrors Frame"], C.global, "errors_hide", "checkbox")
      CreateConfig(nil, T["Highlight Settings That Require Reload"], C.gui, "reloadmarker", "checkbox")
      CreateConfig(nil, T["Show Incompatible Config Entries"], C.gui, "showdisabled", "checkbox")
      CreateConfig(nil, T["Abbreviate Numbers"], C.unitframes, "abbrevnum", "dropdown", pfUI.gui.dropdowns.abbrevnum)
      CreateConfig(nil, T["Castbar Timer Decimals"], C.unitframes, "castbardecimals", "dropdown", pfUI.gui.dropdowns.castbardecimals)
      CreateConfig(nil, T["Abbreviate Unit Names"], C.unitframes, "abbrevname", "checkbox")

      -- 自动下马（autoshift 模块在事件时即时读取配置，无需重载）
      CreateConfig(nil, "自动下马", nil, nil, "header")
      CreateConfig(function() return end, "自动下马（施法/攻击被坐骑阻挡时自动取消坐骑）", C.global, "autodismount", "checkbox")

      CreateConfig(nil, T["Health Point Estimation"], nil, nil, "header")
      CreateConfig(nil, T["Estimate Enemy Health Points"], C.global, "libhealth", "checkbox")
      CreateConfig(nil, T["Threshold To Trust Health Estimation"], C.global, "libhealth_hit", "dropdown", pfUI.gui.dropdowns.uf_rangecheckinterval)
      CreateConfig(nil, T["Required Damage In Percent"], C.global, "libhealth_dmg", "dropdown", pfUI.gui.dropdowns.percent_small)

      -- 色盲模式（装备品质文字标记）
      CreateConfig(nil, "色盲模式", nil, nil, "header")
      CreateConfig(nil, "色盲模式（在装备名字后追加品质标记，如 [精良]/[史诗]）", C.global, "colorblind", "checkbox")

      -- Delete / Reset
      CreateConfig(nil, T["Delete / Reset"], nil, nil, "header")
      CreateConfig(nil, T["|cffff5555EVERYTHING"], C.global, "profile", "button", function()
        CreateQuestionDialog(T["Do you really want to reset |cffffaaaaEVERYTHING|r?\n\nThis will reset:\n - Current Configuration\n - Current Frame Positions\n - Firstrun Wizard\n - Addon Cache\n - Saved Profiles"],
          function()
            _G["pfUI_init"] = {}
            _G["pfUI_config"] = pfUI.api.CopyTable(pfUI_profiles["Modern"])
            _G["pfUI_playerDB"] = {}
            _G["pfUI_profiles"] = {}
            _G["pfUI_cache"] = {}
            pfUI:LoadConfig()
            this:GetParent():Hide()
            pfUI.gui:Reload()
          end)
      end)

      CreateConfig(nil, T["Configuration"], C.global, "profile", "button", function()
        CreateQuestionDialog(T["Do you really want to reset your configuration?\nThis also includes frame positions"],
          function()
            _G["pfUI_config"] = pfUI.api.CopyTable(pfUI_profiles["Modern"])
            _G["pfUI_init"] = {}
            pfUI:LoadConfig()
            this:GetParent():Hide()
            pfUI.gui:Reload()
          end)
      end, true)

      CreateConfig(nil, T["Cache"], C.global, "profile", "button", function()
        CreateQuestionDialog(T["Do you really want to reset the Cache?"],
          function()
            _G["pfUI_playerDB"] = {}
            _G["pfUI_cache"] = {}
            this:GetParent():Hide()
            pfUI.gui:Reload()
          end)
      end, true)

      CreateConfig(nil, T["Firstrun"], C.global, "profile", "button", function()
        _G["pfUI_init"] = {}
        pfUI.gui:Hide()
        pfUI.firstrun:NextStep()
      end, true)
    end)

    CreateGUIEntry(T["Settings"], T["Appearance"], function()
      CreateConfig(nil, T["Background Color"], C.appearance.border, "background", "color")
      CreateConfig(nil, T["Border Color"], C.appearance.border, "color", "color")
      CreateConfig(U["mapreveal"], T["Map Reveal Color"], C.appearance.worldmap, "mapreveal_color", "color")
      CreateConfig(U["mapreveal"], T["Map Exploration Points"], C.appearance.worldmap, "mapexploration", "checkbox")
      CreateConfig(U["mapcolors"], T["Map Group/Raid Circle Size"], C.appearance.worldmap, "groupcircles", "dropdown", pfUI.gui.dropdowns.mapcircle)
      CreateConfig(U["mapcolors"], T["Colorize player name on WorldMap and BattlefieldMinimap"], C.appearance.worldmap, "colornames", "checkbox")
      CreateConfig(U["map"], T["Map Tooltip Scale"], C.appearance.worldmap, "tooltipsize", "dropdown", pfUI.gui.dropdowns.maptooltip)
      CreateConfig(nil) -- spacer
      -- 全局材质：选择后批量写入所有进度条材质配置（头像框/团队框血条法力条/仇恨框、
      -- 姓名板血条、施法条、小德法力条、swing timer、标记追踪、经验条、tooltip 状态条），并提示重载
      CreateConfig(nil, "材质", nil, nil, "header")
      CreateConfig(function()
        local tex = C.appearance.texture.default
        if not tex or tex == "off" then return end
        for unit, cfg in pairs(C.unitframes) do
          if type(cfg) == "table" then
            if cfg.bartexture then cfg.bartexture = tex end
            if cfg.pbartexture then cfg.pbartexture = tex end
            if cfg.threattexture then cfg.threattexture = tex end
          end
        end
        C.unitframes.druidmanatexture = tex
        C.unitframes.swingtimertexture = tex
        C.unitframes.raidmarkertexture = tex
        C.nameplates.healthtexture = tex
        C.appearance.castbar.texture = tex
        C.panel.xp.texture = tex
        C.tooltip.statusbar.texture = tex
        pfUI.gui:Reload()
      end, "全局材质（批量修改头像/姓名板/施法条等所有材质）", C.appearance.texture, "default", "dropdown", pfUI.gui.dropdowns.global_bartexture)
      CreateConfig(nil) -- spacer
      CreateConfig(nil, T["Enable Frame Shadow"], C.appearance.border, "shadow", "checkbox")
      CreateConfig(nil, T["Frame Shadow Intensity"], C.appearance.border, "shadow_intensity", "dropdown", pfUI.gui.dropdowns.uf_debuff_indicator_size)
      CreateConfig(nil) -- spacer
      CreateConfig(nil, T["Force Blizzard Borders (|cffffaaaaExperimental|r)"], C.appearance.border, "force_blizz", "checkbox")
      CreateConfig(nil, T["Enable Pixel Perfect Borders"], C.appearance.border, "pixelperfect", "checkbox")
      CreateConfig(nil, T["Scale Border On HiDPI Displays"], C.appearance.border, "hidpi", "checkbox")
      CreateConfig(nil) -- spacer
      CreateConfig(nil, T["Global Border Size"], C.appearance.border, "default", "dropdown", pfUI.gui.dropdowns.border)
      CreateConfig(nil, T["Action Bar Border Size"], C.appearance.border, "actionbars", "dropdown", pfUI.gui.dropdowns.border)
      CreateConfig(nil, T["Unit Frame Border Size"], C.appearance.border, "unitframes", "dropdown", pfUI.gui.dropdowns.border)
      CreateConfig(nil, T["Panel Border Size"], C.appearance.border, "panels", "dropdown", pfUI.gui.dropdowns.border)
      CreateConfig(nil, T["Chat Border Size"], C.appearance.border, "chat", "dropdown", pfUI.gui.dropdowns.border)
      CreateConfig(nil, T["Bags Border Size"], C.appearance.border, "bags", "dropdown", pfUI.gui.dropdowns.border)
      CreateConfig(U["nameplates"], T["Nameplate Border Size"], C.appearance.border, "nameplates", "dropdown", pfUI.gui.dropdowns.border)
      CreateConfig(nil) -- spacer
      CreateConfig(U["infight"], T["Enable Combat Glow Effects On Screen Edges"], C.appearance.infight, "screen", "checkbox")
      CreateConfig(U["infight"], T["Enable Aggro Glow Effects On Screen Edges"], C.appearance.infight, "aggro", "checkbox")
      CreateConfig(U["infight"], T["Enable Low Health Glow Effects On Screen Edges"], C.appearance.infight, "health", "checkbox")
      CreateConfig(U["infight"], T["Screen Edge Glow Intensity"], C.appearance.infight, "intensity", "dropdown", pfUI.gui.dropdowns.glowintensity)
    end)

    CreateGUIEntry(T["Settings"], T["Cooldown"], function()
      CreateConfig(U["buff"], T["Show Milliseconds When Timer Runs Out"], C.appearance.cd, "milliseconds", "checkbox")
      CreateConfig(nil, T["Cooldown Color (Less than 3 Sec)"], C.appearance.cd, "lowcolor", "color")
      CreateConfig(nil, T["Cooldown Color (Seconds)"], C.appearance.cd, "normalcolor", "color")
      CreateConfig(nil, T["Cooldown Color (Minutes)"], C.appearance.cd, "minutecolor", "color")
      CreateConfig(nil, T["Cooldown Color (Hours)"], C.appearance.cd, "hourcolor", "color")
      CreateConfig(nil, T["Cooldown Color (Days)"], C.appearance.cd, "daycolor", "color")
      CreateConfig(nil, T["Use Dynamic Font Size"], C.appearance.cd, "dynamicsize", "checkbox")
      CreateConfig(nil, T["Cooldown Text Font"], C.appearance.cd, "font", "dropdown", pfUI.gui.dropdowns.fonts)
      CreateConfig(nil, T["Cooldown Text Font Size"], C.appearance.cd, "font_size")
      CreateConfig(nil, T["Cooldown Text Font Size (Blizzard Frames)"], C.appearance.cd, "font_size_blizz")
      CreateConfig(nil, T["Cooldown Text Font Size (Foreign Frames)"], C.appearance.cd, "font_size_foreign")
      CreateConfig(nil, T["Cooldown Text Time Threshold"], C.appearance.cd, "threshold")
      CreateConfig(nil, T["Enable Durations On Blizzard Frames"], C.appearance.cd, "blizzard", "checkbox")
      CreateConfig(nil, T["Enable Durations On Foreign Frames"], C.appearance.cd, "foreign", "checkbox")
      CreateConfig(nil, T["Hide Foreign Cooldown Animations"], C.appearance.cd, "hideanim", "checkbox")
    end)

    CreateGUIEntry(T["Settings"], T["Screenshot"], function()
      CreateConfig(nil, T["Timer In Minutes"], C.screenshot, "interval")
      CreateConfig(nil, T["Level Up"], C.screenshot, "levelup", "checkbox")
      CreateConfig(nil, T["PvP Rank"], C.screenshot, "pvprank", "checkbox")
      CreateConfig(nil, T["Reputation Level"], C.screenshot, "faction", "checkbox")
      CreateConfig(nil, T["Honorable Kill"], C.screenshot, "hk", "checkbox")
      CreateConfig(nil, T["Battleground Statistics"], C.screenshot, "battleground", "dropdown", pfUI.gui.dropdowns.screenshot_battle)
      CreateConfig(nil, T["Item Looted"], C.screenshot, "loot", "dropdown", pfUI.gui.dropdowns.screenshot_loot)
      CreateConfig(nil, T["Options"], nil, nil, "header")
      CreateConfig(nil, T["Show Description"], C.screenshot, "caption", "checkbox")
      CreateConfig(nil, T["Description Font"], C.screenshot, "caption_font", "dropdown", pfUI.gui.dropdowns.fonts)
      CreateConfig(nil, T["Description Font Size"], C.screenshot, "caption_size")
      CreateConfig(nil, T["Hide All UI Elements"], C.screenshot, "hideui", "checkbox")
    end)

    CreateGUIEntry(T["Settings"], T["GM-Mode"], function()
      CreateConfig(nil, T["Disable GM-Mode"], C.gm, "disable", "checkbox")
      CreateConfig(nil, T["Selected Core"], C.gm, "server", "dropdown", pfUI.gui.dropdowns.gmserver_text)
    end)


    -- Throttling Menu
    CreateGUIEntry(T["Throttling"], T["Nameplates"], function()
      local header = CreateConfig(nil, T["Nameplate Update Rate"], nil, nil, "header")
      header:GetParent().objectCount = header:GetParent().objectCount - 1
      header:SetHeight(20)
      
      local targetCustom  -- declare first so callback can use it
      
      CreateConfig(function()
        -- Callback when dropdown changes - update custom field immediately
        if targetCustom and targetCustom.input then
          local isCustom = pfUI.throttle:IsCustom("nameplates_target")
          if not isCustom then
            -- Preset selected - show FPS from preset, make readonly
            targetCustom.input:EnableMouse(false)
            targetCustom.input:EnableKeyboard(false)
            targetCustom.input:ClearFocus()
            targetCustom.input:SetTextColor(.5,.5,.5,1)
            targetCustom.input:SetText(tostring(pfUI.throttle:GetFps("nameplates_target")))
          else
            -- Custom selected - make editable
            targetCustom.input:EnableMouse(true)
            targetCustom.input:EnableKeyboard(true)
            targetCustom.input:SetTextColor(.2,1,.8,1)
            if _G.pfUI_throttle.nameplates_target_custom then
              targetCustom.input:SetText(_G.pfUI_throttle.nameplates_target_custom)
            end
          end
        end
      end, T["Target Plates"], _G.pfUI_throttle, "nameplates_target", "dropdown", {
        "very_slow:" .. T["Very Slow"] .. " (2 FPS)",
        "slow:" .. T["Slow"] .. " (5 FPS)",
        "normal:" .. T["Normal"] .. " (10 FPS)",
        "fast:" .. T["Fast"] .. " (20 FPS)",
        "very_fast:" .. T["Very Fast"] .. " (30 FPS)",
        "fastest:" .. T["Fastest"] .. " (50 FPS)",
        "custom:" .. T["Custom"],
      })
      
      -- Now create custom field AFTER dropdown
      targetCustom = CreateConfig(nil, T["Custom FPS"], _G.pfUI_throttle, "nameplates_target_custom")
      
      -- Set initial state
      local isCustom = pfUI.throttle:IsCustom("nameplates_target")
      if not isCustom then
        targetCustom.input:EnableMouse(false)
        targetCustom.input:EnableKeyboard(false)
        targetCustom.input:SetTextColor(.5,.5,.5,1)
        targetCustom.input:SetText(tostring(pfUI.throttle:GetFps("nameplates_target")))
      else
        targetCustom.input:EnableMouse(true)
        targetCustom.input:EnableKeyboard(true)
        targetCustom.input:SetTextColor(.2,1,.8,1)
        if _G.pfUI_throttle.nameplates_target_custom then
          targetCustom.input:SetText(_G.pfUI_throttle.nameplates_target_custom)
        end
      end
      
      -- Spacer after custom field
      local spacer1 = CreateConfig(nil, " ", nil, nil, "header")
      spacer1:GetParent().objectCount = spacer1:GetParent().objectCount - 1
      spacer1:SetHeight(5)
      
      local normalCustom
      
      CreateConfig(function()
        if normalCustom and normalCustom.input then
          local isCustom = pfUI.throttle:IsCustom("nameplates")
          if not isCustom then
            normalCustom.input:EnableMouse(false)
            normalCustom.input:EnableKeyboard(false)
            normalCustom.input:ClearFocus()
            normalCustom.input:SetTextColor(.5,.5,.5,1)
            normalCustom.input:SetText(tostring(pfUI.throttle:GetFps("nameplates")))
          else
            normalCustom.input:EnableMouse(true)
            normalCustom.input:EnableKeyboard(true)
            normalCustom.input:SetTextColor(.2,1,.8,1)
            if _G.pfUI_throttle.nameplates_custom then
              normalCustom.input:SetText(_G.pfUI_throttle.nameplates_custom)
            end
          end
        end
      end, T["Normal Plates"], _G.pfUI_throttle, "nameplates", "dropdown", {
        "very_slow:" .. T["Very Slow"] .. " (2 FPS)",
        "slow:" .. T["Slow"] .. " (5 FPS)",
        "normal:" .. T["Normal"] .. " (10 FPS)",
        "fast:" .. T["Fast"] .. " (20 FPS)",
        "very_fast:" .. T["Very Fast"] .. " (30 FPS)",
        "fastest:" .. T["Fastest"] .. " (50 FPS)",
        "custom:" .. T["Custom"],
      })
      
      normalCustom = CreateConfig(nil, T["Custom FPS"], _G.pfUI_throttle, "nameplates_custom")
      
      local isCustom2 = pfUI.throttle:IsCustom("nameplates")
      if not isCustom2 then
        normalCustom.input:EnableMouse(false)
        normalCustom.input:EnableKeyboard(false)
        normalCustom.input:SetTextColor(.5,.5,.5,1)
        normalCustom.input:SetText(tostring(pfUI.throttle:GetFps("nameplates")))
      else
        normalCustom.input:EnableMouse(true)
        normalCustom.input:EnableKeyboard(true)
        normalCustom.input:SetTextColor(.2,1,.8,1)
        if _G.pfUI_throttle.nameplates_custom then
          normalCustom.input:SetText(_G.pfUI_throttle.nameplates_custom)
        end
      end
      
      -- Spacer after custom field
      local spacer2 = CreateConfig(nil, " ", nil, nil, "header")
      spacer2:GetParent().objectCount = spacer2:GetParent().objectCount - 1
      spacer2:SetHeight(5)

      local castbarCustom

      CreateConfig(function()
        if castbarCustom and castbarCustom.input then
          local isCustom = pfUI.throttle:IsCustom("nameplates_castbar")
          if not isCustom then
            castbarCustom.input:EnableMouse(false)
            castbarCustom.input:EnableKeyboard(false)
            castbarCustom.input:ClearFocus()
            castbarCustom.input:SetTextColor(.5,.5,.5,1)
            castbarCustom.input:SetText(tostring(pfUI.throttle:GetFps("nameplates_castbar")))
          else
            castbarCustom.input:EnableMouse(true)
            castbarCustom.input:EnableKeyboard(true)
            castbarCustom.input:SetTextColor(.2,1,.8,1)
            if _G.pfUI_throttle.nameplates_castbar_custom then
              castbarCustom.input:SetText(_G.pfUI_throttle.nameplates_castbar_custom)
            end
          end
        end
      end, T["Castbar Plates"], _G.pfUI_throttle, "nameplates_castbar", "dropdown", {
        "very_slow:" .. T["Very Slow"] .. " (2 FPS)",
        "slow:" .. T["Slow"] .. " (5 FPS)",
        "normal:" .. T["Normal"] .. " (10 FPS)",
        "fast:" .. T["Fast"] .. " (20 FPS)",
        "very_fast:" .. T["Very Fast"] .. " (30 FPS)",
        "fastest:" .. T["Fastest"] .. " (50 FPS)",
        "custom:" .. T["Custom"],
      })

      castbarCustom = CreateConfig(nil, T["Custom FPS"], _G.pfUI_throttle, "nameplates_castbar_custom")

      local spacer3 = CreateConfig(nil, " ", nil, nil, "header")
      spacer3:GetParent().objectCount = spacer3:GetParent().objectCount - 1
      spacer3:SetHeight(5)

      
      local massCustom
      
      CreateConfig(function()
        if massCustom and massCustom.input then
          local isCustom = pfUI.throttle:IsCustom("nameplates_mass")
          if not isCustom then
            massCustom.input:EnableMouse(false)
            massCustom.input:EnableKeyboard(false)
            massCustom.input:ClearFocus()
            massCustom.input:SetTextColor(.5,.5,.5,1)
            massCustom.input:SetText(tostring(pfUI.throttle:GetFps("nameplates_mass")))
          else
            massCustom.input:EnableMouse(true)
            massCustom.input:EnableKeyboard(true)
            massCustom.input:SetTextColor(.2,1,.8,1)
            if _G.pfUI_throttle.nameplates_mass_custom then
              massCustom.input:SetText(_G.pfUI_throttle.nameplates_mass_custom)
            end
          end
        end
      end, T["Mass Pulls (20+ Plates)"], _G.pfUI_throttle, "nameplates_mass", "dropdown", {
        "very_slow:" .. T["Very Slow"] .. " (2 FPS)",
        "slow:" .. T["Slow"] .. " (5 FPS)",
        "normal:" .. T["Normal"] .. " (10 FPS)",
        "fast:" .. T["Fast"] .. " (20 FPS)",
        "very_fast:" .. T["Very Fast"] .. " (30 FPS)",
        "fastest:" .. T["Fastest"] .. " (50 FPS)",
        "custom:" .. T["Custom"],
      })
      
      massCustom = CreateConfig(nil, T["Custom FPS"], _G.pfUI_throttle, "nameplates_mass_custom")
      
      local isCustom3 = pfUI.throttle:IsCustom("nameplates_mass")
      if not isCustom3 then
        massCustom.input:EnableMouse(false)
        massCustom.input:EnableKeyboard(false)
        massCustom.input:SetTextColor(.5,.5,.5,1)
        massCustom.input:SetText(tostring(pfUI.throttle:GetFps("nameplates_mass")))
      else
        massCustom.input:EnableMouse(true)
        massCustom.input:EnableKeyboard(true)
        massCustom.input:SetTextColor(.2,1,.8,1)
        if _G.pfUI_throttle.nameplates_mass_custom then
          massCustom.input:SetText(_G.pfUI_throttle.nameplates_mass_custom)
        end
      end
      
      -- Spacer before reset button
      local spacer = CreateConfig(nil, " ", nil, nil, "header")
      spacer:GetParent().objectCount = spacer:GetParent().objectCount - 1
      spacer:SetHeight(10)
      
      -- Reset to defaults button
      CreateConfig(nil, T["Reset to Defaults"], nil, nil, "button", function()
        pfUI.throttle:ResetToDefault("nameplates_target")
        pfUI.throttle:ResetToDefault("nameplates")
        pfUI.throttle:ResetToDefault("nameplates_mass")
        -- Also reset custom fields to their default FPS values
        _G.pfUI_throttle.nameplates_target_custom = "50"
        _G.pfUI_throttle.nameplates_custom = "10"
        _G.pfUI_throttle.nameplates_mass_custom = "7"
        Reload()
      end, true)
    end)

    CreateGUIEntry(T["Throttling"], T["Tooltips"], function()
      local header = CreateConfig(nil, T["Tooltip Update Rate"], nil, nil, "header")
      header:GetParent().objectCount = header:GetParent().objectCount - 1
      header:SetHeight(20)
      
      local cursorCustom
      
      CreateConfig(function()
        if cursorCustom and cursorCustom.input then
          local isCustom = pfUI.throttle:IsCustom("tooltip_cursor")
          if not isCustom then
            cursorCustom.input:EnableMouse(false)
            cursorCustom.input:EnableKeyboard(false)
            cursorCustom.input:ClearFocus()
            cursorCustom.input:SetTextColor(.5,.5,.5,1)
            cursorCustom.input:SetText(tostring(pfUI.throttle:GetFps("tooltip_cursor")))
          else
            cursorCustom.input:EnableMouse(true)
            cursorCustom.input:EnableKeyboard(true)
            cursorCustom.input:SetTextColor(.2,1,.8,1)
            if _G.pfUI_throttle.tooltip_cursor_custom then
              cursorCustom.input:SetText(_G.pfUI_throttle.tooltip_cursor_custom)
            end
          end
        end
      end, T["Cursor Follow"], _G.pfUI_throttle, "tooltip_cursor", "dropdown", {
        "very_slow:" .. T["Very Slow"] .. " (2 FPS)",
        "slow:" .. T["Slow"] .. " (5 FPS)",
        "normal:" .. T["Normal"] .. " (10 FPS)",
        "fast:" .. T["Fast"] .. " (20 FPS)",
        "very_fast:" .. T["Very Fast"] .. " (30 FPS)",
        "fastest:" .. T["Fastest"] .. " (50 FPS)",
        "custom:" .. T["Custom"],
      })
      
      cursorCustom = CreateConfig(nil, T["Custom FPS"], _G.pfUI_throttle, "tooltip_cursor_custom")
      
      local isCustom = pfUI.throttle:IsCustom("tooltip_cursor")
      if not isCustom then
        cursorCustom.input:EnableMouse(false)
        cursorCustom.input:EnableKeyboard(false)
        cursorCustom.input:SetTextColor(.5,.5,.5,1)
        cursorCustom.input:SetText(tostring(pfUI.throttle:GetFps("tooltip_cursor")))
      else
        cursorCustom.input:EnableMouse(true)
        cursorCustom.input:EnableKeyboard(true)
        cursorCustom.input:SetTextColor(.2,1,.8,1)
        if _G.pfUI_throttle.tooltip_cursor_custom then
          cursorCustom.input:SetText(_G.pfUI_throttle.tooltip_cursor_custom)
        end
      end
      
      -- Small spacer
      local spacer1 = CreateConfig(nil, " ", nil, nil, "header")
      spacer1:GetParent().objectCount = spacer1:GetParent().objectCount - 1
      spacer1:SetHeight(5)
      
      -- Info note about Native mode
      local infoText = CreateConfig(nil, T["Note: Only works when Cursor Align is NOT 'Native'"], nil, nil, "header")
      infoText:GetParent().objectCount = infoText:GetParent().objectCount - 1
      infoText:SetHeight(25)
      
      -- Spacer before reset button
      local spacer = CreateConfig(nil, " ", nil, nil, "header")
      spacer:GetParent().objectCount = spacer:GetParent().objectCount - 1
      spacer:SetHeight(5)
      
      -- Reset to defaults button
      CreateConfig(nil, T["Reset to Defaults"], nil, nil, "button", function()
        pfUI.throttle:ResetToDefault("tooltip_cursor")
        _G.pfUI_throttle.tooltip_cursor_custom = "10"
        Reload()
      end, true)
    end)
    CreateGUIEntry(T["Throttling"], T["Chat Tab"], function()
      local chatCustom
      
      CreateConfig(function()
        if chatCustom and chatCustom.input then
          local isCustom = pfUI.throttle:IsCustom("chat_tab")
          if not isCustom then
            chatCustom.input:EnableMouse(false)
            chatCustom.input:EnableKeyboard(false)
            chatCustom.input:ClearFocus()
            chatCustom.input:SetTextColor(.5,.5,.5,1)
            chatCustom.input:SetText(tostring(pfUI.throttle:GetFps("chat_tab")))
          else
            chatCustom.input:EnableMouse(true)
            chatCustom.input:EnableKeyboard(true)
            chatCustom.input:SetTextColor(.2,1,.8,1)
            if _G.pfUI_throttle.chat_tab_custom then
              chatCustom.input:SetText(_G.pfUI_throttle.chat_tab_custom)
            end
          end
        end
      end, T["Chat Tab Hover Check"], _G.pfUI_throttle, "chat_tab", "dropdown", {
        "very_slow:" .. T["Very Slow"] .. " (2 FPS)",
        "slow:" .. T["Slow"] .. " (5 FPS)",
        "normal:" .. T["Normal"] .. " (10 FPS)",
        "fast:" .. T["Fast"] .. " (20 FPS)",
        "very_fast:" .. T["Very Fast"] .. " (30 FPS)",
        "fastest:" .. T["Fastest"] .. " (50 FPS)",
        "custom:" .. T["Custom"],
      })
      
      chatCustom = CreateConfig(nil, T["Custom FPS"], _G.pfUI_throttle, "chat_tab_custom")
      
      local isCustom = pfUI.throttle:IsCustom("chat_tab")
      if not isCustom then
        chatCustom.input:EnableMouse(false)
        chatCustom.input:EnableKeyboard(false)
        chatCustom.input:SetTextColor(.5,.5,.5,1)
        chatCustom.input:SetText(tostring(pfUI.throttle:GetFps("chat_tab")))
      else
        chatCustom.input:EnableMouse(true)
        chatCustom.input:EnableKeyboard(true)
        chatCustom.input:SetTextColor(.2,1,.8,1)
        if _G.pfUI_throttle.chat_tab_custom then
          chatCustom.input:SetText(_G.pfUI_throttle.chat_tab_custom)
        end
      end
      
      -- Spacer before reset button
      local spacer = CreateConfig(nil, " ", nil, nil, "header")
      spacer:GetParent().objectCount = spacer:GetParent().objectCount - 1
      spacer:SetHeight(10)
      
      -- Reset to defaults button
      CreateConfig(nil, T["Reset to Defaults"], nil, nil, "button", function()
        pfUI.throttle:ResetToDefault("chat_tab")
        _G.pfUI_throttle.chat_tab_custom = "10"
        Reload()
      end, true)
    end)

    CreateGUIEntry(T["Throttling"], T["Swing Timer"], function()
      local swingCustom

      CreateConfig(function()
        if swingCustom and swingCustom.input then
          local isCustom = pfUI.throttle:IsCustom("swingtimer")
          if not isCustom then
            swingCustom.input:EnableMouse(false)
            swingCustom.input:EnableKeyboard(false)
            swingCustom.input:ClearFocus()
            swingCustom.input:SetTextColor(.5,.5,.5,1)
            swingCustom.input:SetText(tostring(pfUI.throttle:GetFps("swingtimer")))
          else
            swingCustom.input:EnableMouse(true)
            swingCustom.input:EnableKeyboard(true)
            swingCustom.input:SetTextColor(.2,1,.8,1)
            if _G.pfUI_throttle.swingtimer_custom then
              swingCustom.input:SetText(_G.pfUI_throttle.swingtimer_custom)
            end
          end
        end
      end, T["Swing Timer Update Rate"], _G.pfUI_throttle, "swingtimer", "dropdown", {
        "very_slow:" .. T["Very Slow"] .. " (2 FPS)",
        "slow:" .. T["Slow"] .. " (5 FPS)",
        "normal:" .. T["Normal"] .. " (10 FPS)",
        "fast:" .. T["Fast"] .. " (20 FPS)",
        "very_fast:" .. T["Very Fast"] .. " (30 FPS)",
        "fastest:" .. T["Fastest"] .. " (50 FPS)",
        "custom:" .. T["Custom"],
      })

      swingCustom = CreateConfig(nil, T["Custom FPS"], _G.pfUI_throttle, "swingtimer_custom")

      local isCustom = pfUI.throttle:IsCustom("swingtimer")
      if not isCustom then
        swingCustom.input:EnableMouse(false)
        swingCustom.input:EnableKeyboard(false)
        swingCustom.input:SetTextColor(.5,.5,.5,1)
        swingCustom.input:SetText(tostring(pfUI.throttle:GetFps("swingtimer")))
      else
        swingCustom.input:EnableMouse(true)
        swingCustom.input:EnableKeyboard(true)
        swingCustom.input:SetTextColor(.2,1,.8,1)
        if _G.pfUI_throttle.swingtimer_custom then
          swingCustom.input:SetText(_G.pfUI_throttle.swingtimer_custom)
        end
      end

      -- Spacer before reset button
      local spacer = CreateConfig(nil, " ", nil, nil, "header")
      spacer:GetParent().objectCount = spacer:GetParent().objectCount - 1
      spacer:SetHeight(10)

      -- Reset to defaults button
      CreateConfig(nil, T["Reset to Defaults"], nil, nil, "button", function()
        pfUI.throttle:ResetToDefault("swingtimer")
        _G.pfUI_throttle.swingtimer_custom = "50"
        Reload()
      end, true)
    end)
	
    CreateGUIEntry(T["Unit Frames"], T["General"], function()
      CreateConfig(nil, T["Disable pfUI Unit Frames"], C.unitframes, "disable", "checkbox")
      CreateConfig(nil, T["Healthbar Animation Speed"], C.unitframes, "animation_speed", "dropdown", pfUI.gui.dropdowns.uf_animationspeed)
      CreateConfig(nil, T["Portrait Alpha"], C.unitframes, "portraitalpha")
      CreateConfig(nil, T["Always Use 2D Portraits"], C.unitframes, "always2dportrait", "checkbox")
      CreateConfig(nil, T["Enable 2D Portraits As Fallback"], C.unitframes, "portraittexture", "checkbox")
      CreateConfig(nil, T["Unit Frame Layout"], C.unitframes, "layout", "dropdown", pfUI.gui.dropdowns.uf_layout)
      CreateConfig(U["energybar"], T["Align Bottom To Player Frame"], C.unitframes, "bottomalign", "checkbox")
      CreateConfig(U["energybar"], T["Bottom Align Gap"], C.unitframes, "bottomalign_gap", nil, nil, nil, nil, "number")
      CreateConfig(nil, T["Realign Bottom Stack"], C.unitframes, "bottomalign", "button", function()
        if pfUI.energybar and pfUI.energybar.ClearManual then
          pfUI.energybar:ClearManual()
        end
      end)
      -- 杂项（原属 General，保持在一起；必须排在 Combo Points 段**之前**，
      -- 否则会挂在连击点那一串后面，看起来像连击点的配置项）
      CreateConfig(nil, T["Show Resting"], C.unitframes.player, "showRest", "checkbox")
      CreateConfig(nil, T["Enable Energy Ticks"], C.unitframes.player, "energy", "checkbox")
      CreateConfig(nil, T["Enable Mana Ticks"], C.unitframes.player, "manatick", "checkbox")
      CreateConfig(nil, T["Detect Enemy Buffs"], C.unitframes, "buffdetect", "checkbox", nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Raid Mark Icon Style"], C.unitframes, "blizzard_raidicons", "dropdown", function() return {"1:"..T["Original Blizzard"], "0:"..T["pfUI Design"]} end)

      CreateConfig(nil, T["Swing Timer"], nil, nil, "header")
      CreateConfig(nil, T["Enable Swing Timer"], C.unitframes, "swingtimer", "checkbox")																						
      CreateConfig(nil, T["Swing Timer Width"], C.unitframes, "swingtimerwidth")
      CreateConfig(nil, T["Swing Timer Height"], C.unitframes, "swingtimerheight")
      CreateConfig(nil, T["Swing Timer Texture"], C.unitframes, "swingtimertexture", "dropdown", pfUI.gui.dropdowns.uf_bartexture)
      CreateConfig(nil, T["Swing Timer Font Size"], C.unitframes, "swingtimerfontsize")
      CreateConfig(nil, T["Show Timer Text"], C.unitframes, "swingtimertext", "checkbox")
      CreateConfig(nil, T["Show MH/OH Labels"], C.unitframes, "swingtimerlabel", "checkbox")
      CreateConfig(nil, T["Show Offhand Bar"], C.unitframes, "swingtimeroffhand", "checkbox")
      CreateConfig(nil, T["Show Ranged Bar"], C.unitframes, "swingtimerranged", "checkbox")																						   
      CreateConfig(nil, T["Show Target Swing Bar"], C.unitframes, "swingtimertarget", "checkbox")
      CreateConfig(nil, T["Mainhand Bar Color"], C.unitframes, "swingtimermhcolor", "color")
      CreateConfig(nil, T["Offhand Bar Color"], C.unitframes, "swingtimerohcolor", "color")
      CreateConfig(nil, T["Ranged Bar Color"], C.unitframes, "swingtimerrangedcolor", "color")
      CreateConfig(nil, T["Ranged Warn Color (Hunter)"], C.unitframes, "swingtimerrangedwarncolor", "color")
      CreateConfig(nil, T["Show On Next Attack Queue Color"], C.unitframes, "swingtimerhsqueue", "checkbox")
      CreateConfig(nil, T["Show Attack Speed"], C.unitframes, "swingtimerattackspeed", "checkbox")																								  

      CreateConfig(nil, T["Mark Tracking"], nil, nil, "header")
      CreateConfig(nil, T["Enable Mark Tracking"], C.unitframes, "marktrackingenabled", "checkbox")
      CreateConfig(nil, T["Raid Marker Width"], C.unitframes, "raidmarkerwidth")
      CreateConfig(nil, T["Raid Marker Height"], C.unitframes, "raidmarkerheight")
      CreateConfig(nil, T["Raid Marker Grow"], C.unitframes, "raidmarkergrow", "dropdown", pfUI.gui.dropdowns.raidmarker_grow)
      CreateConfig(nil, T["Raid Marker Texture"], C.unitframes, "raidmarkertexture", "dropdown", pfUI.gui.dropdowns.uf_bartexture)
      CreateConfig(nil, T["Raid Marker Font Size"], C.unitframes, "raidmarkerfontsize")
      CreateConfig(nil, T["Show Name"], C.unitframes, "raidmarkershowname", "checkbox")
      CreateConfig(nil, T["Show Percent HP"], C.unitframes, "raidmarkershowpct", "checkbox")
      CreateConfig(nil, T["Show Portrait"], C.unitframes, "raidmarkershowportrait", "checkbox")
      CreateConfig(nil, T["Star Color"], C.unitframes, "raidmarkercolor_star", "color")
      CreateConfig(nil, T["Circle Color"], C.unitframes, "raidmarkercolor_circle", "color")
      CreateConfig(nil, T["Diamond Color"], C.unitframes, "raidmarkercolor_diamond", "color")
      CreateConfig(nil, T["Triangle Color"], C.unitframes, "raidmarkercolor_triangle", "color")
      CreateConfig(nil, T["Moon Color"], C.unitframes, "raidmarkercolor_moon", "color")
      CreateConfig(nil, T["Square Color"], C.unitframes, "raidmarkercolor_square", "color")
      CreateConfig(nil, T["Cross Color"], C.unitframes, "raidmarkercolor_cross", "color")
      CreateConfig(nil, T["Skull Color"], C.unitframes, "raidmarkercolor_skull", "color")
														   
      CreateConfig(U[c], T["Font Options"], nil, nil, "header")
      CreateConfig(nil, T["Unit Frame Text Font"], C.global, "font_unit", "dropdown", pfUI.gui.dropdowns.fonts)
      CreateConfig(nil, T["Unit Frame Text Size"], C.global, "font_unit_size")
      CreateConfig(nil, T["Unit Frame Text Style"], C.global, "font_unit_style", "dropdown", pfUI.gui.dropdowns.fontstyle)

      CreateConfig(U[c], T["Group Options"], nil, nil, "header")
      CreateConfig(nil, T["Enable 40y-Range Check"], C.unitframes, "rangecheck", "checkbox", nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Range Check Mode"], C.unitframes, "rangecheck_mode", "dropdown", pfUI.gui.dropdowns.uf_rangecheck_mode, nil, nil, nil, "vanilla")
      CreateConfig(nil, T["UnitXP Range Threshold (yards)"], C.unitframes, "rangecheck_distance", nil, nil, nil, nil, nil, "vanilla") 
      CreateConfig(nil, T["Range Check Interval"], C.unitframes, "rangechecki", "dropdown", pfUI.gui.dropdowns.uf_rangecheckinterval, nil, nil, nil, "vanilla")
      CreateConfig(nil, T["Use Raid Frames To Display Group Members"], C.unitframes, "raidforgroup", "checkbox")
      CreateConfig(nil, T["Always Show Self In Raid Frames"], C.unitframes, "selfinraid", "checkbox")
      CreateConfig(nil, T["Show Self In Group Frames"], C.unitframes, "selfingroup", "checkbox")
      CreateConfig(nil, T["Hide Group Frames While In Raid"], C.unitframes.group, "hide_in_raid", "checkbox")
      CreateConfig(nil, T["Max Amount Of Raid Frames"], C.unitframes, "maxraid", "dropdown", pfUI.gui.dropdowns.maxraid)
      CreateConfig(nil, T["Max Amount Of Raid Pet Frames"], C.unitframes, "raidpetmax", "dropdown", pfUI.gui.dropdowns.raidpetmax)

      CreateConfig(U[c], T["Colors"], nil, nil, "header")
      CreateConfig(nil, T["Enable Pastel Colors"], C.unitframes, "pastel", "checkbox")
      CreateConfig(nil, T["Health Bar Color"], C.unitframes, "custom", "dropdown", pfUI.gui.dropdowns.uf_color)
      CreateConfig(nil, T["Custom Health Bar Color"], C.unitframes, "customcolor", "color")
      CreateConfig(nil, T["Fade To Custom Color"], C.unitframes, "customfade", "checkbox")
      CreateConfig(nil, T["Use Custom Color On Full Health"], C.unitframes, "customfullhp", "checkbox")
      CreateConfig(nil, T["Enable Custom Color Health Bar Background"], C.unitframes, "custombg", "checkbox")
      CreateConfig(nil, T["Custom Health Bar Background Color"], C.unitframes, "custombgcolor", "color")
      CreateConfig(nil, T["Enable Custom Color Power Bar Background"], C.unitframes, "custompbg", "checkbox")
      CreateConfig(nil, T["Custom Power Bar Background Color"], C.unitframes, "custompbgcolor", "color")
      CreateConfig(nil, T["Mana Color"], C.unitframes, "manacolor", "color")
      CreateConfig(nil, T["Rage Color"], C.unitframes, "ragecolor", "color")
      CreateConfig(nil, T["Energy Color"], C.unitframes, "energycolor", "color")
      CreateConfig(nil, T["Focus Color"], C.unitframes, "focuscolor", "color")

      CreateConfig(nil, T["Druid Settings"], nil, nil, "header")
      CreateConfig(nil, T["Show Druid Mana Bar"], C.unitframes, "druidmanabar", "checkbox", nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Use Custom Font For Druid Mana Bar"], C.unitframes, "druidmanafont", "checkbox")
      CreateConfig(nil, T["Druid Mana Bar Font Size"], C.unitframes, "druidmanafontsize")
      CreateConfig(nil, T["Druid Mana Bar Font Color"], C.unitframes, "druidmanafontcolor","color")
      CreateConfig(nil, T["Druid Mana Bar Height"], C.unitframes, "druidmanaheight", nil, nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Druid Mana Bar Width (-1 = auto)"], C.unitframes, "druidmanawidth", nil, nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Druid Mana Bar X-Offset"], C.unitframes, "druidmanaoffx", nil, nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Druid Mana Bar Y-Offset"], C.unitframes, "druidmanaoffy", nil, nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Druid Mana Bar Spacing"], C.unitframes, "druidmanaspace", nil, nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Druid Mana Bar Texture"], C.unitframes, "druidmanatexture", "dropdown", pfUI.gui.dropdowns.uf_bartexture, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["SuperWoW Settings"], nil, nil, "header")																   
      CreateConfig(nil, T["Track Group on Minimap"], C.unitframes, "track_group", "checkbox", nil, nil, nil, nil, "vanilla" )

      CreateConfig(nil, T["Nampower Settings"], nil, nil, "header")
      CreateConfig(nil, T["Show Spell Queue Indicator"], C.unitframes, "spellqueue", "checkbox", nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Spell Queue Icon Size"], C.unitframes, "spellqueuesize", nil, nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Show Reactive Spell Indicator"], C.unitframes, "reactive_indicator", "checkbox", nil, nil, nil, nil, "vanilla" )
      CreateConfig(nil, T["Reactive Indicator Size"], C.unitframes, "reactive_size", nil, nil, nil, nil, nil, "vanilla" )

    end)

    -- 目标连击点（独立子页。原先 21 项塞在 General 段尾，既把 General 撑长，
    -- 又因为紧跟杂项而看起来像"连击点的其他配置"）
    CreateGUIEntry(T["Unit Frames"], T["Combo Points"], function()
      CreateConfig(U["combopoints"], T["Show Combo Points"], C.unitframes, "comboshow", "checkbox")
      CreateConfig(U["combopoints"], T["Combopoint Style"], C.unitframes, "combostyle", "dropdown", pfUI.gui.dropdowns.combo_style)
      CreateConfig(U["combopoints"], T["Show Empty Combopoints"], C.unitframes, "comboempty", "checkbox")
      CreateConfig(U["combopoints"], T["Show Combopoint Numbers"], C.unitframes, "combopipnumbers", "checkbox")
      CreateConfig(U["combopoints"], T["Glow On Max Combopoints"], C.unitframes, "comboglow", "checkbox")

      CreateConfig(nil, T["Layout"], nil, nil, "header")
      CreateConfig(U["combopoints"], T["Combopoint Grow Direction"], C.unitframes, "combogrow", "dropdown", pfUI.gui.dropdowns.combo_grow)
      CreateConfig(U["combopoints"], T["Combopoint Width"], C.unitframes, "combowidth", nil, nil, nil, nil, "number")
      CreateConfig(U["combopoints"], T["Combopoint Height"], C.unitframes, "comboheight", nil, nil, nil, nil, "number")
      CreateConfig(U["combopoints"], T["Combopoint Spacing"], C.unitframes, "combospacing", nil, nil, nil, nil, "number")
      CreateConfig(U["combopoints"], T["Combopoint X Offset"], C.unitframes, "combooffx", nil, nil, nil, nil, "number")
      CreateConfig(U["combopoints"], T["Combopoint Y Offset"], C.unitframes, "combooffy", nil, nil, nil, nil, "number")

      CreateConfig(nil, T["Appearance"], nil, nil, "header")
      CreateConfig(U["combopoints"], T["Combopoint Texture"], C.unitframes, "combotexture", "dropdown", pfUI.gui.dropdowns.combo_texture)
      CreateConfig(U["combopoints"], T["Show Combopoint Border"], C.unitframes, "comboborder", "checkbox")
      CreateConfig(U["combopoints"], T["Show Combopoint Shadow"], C.unitframes, "comboshadow", "checkbox")

      CreateConfig(nil, T["Colors"], nil, nil, "header")
      CreateConfig(U["combopoints"], T["Low Combopoint Color"], C.unitframes, "combocolor_low", "color")
      CreateConfig(U["combopoints"], T["Medium Combopoint Color"], C.unitframes, "combocolor_mid", "color")
      CreateConfig(U["combopoints"], T["High Combopoint Color"], C.unitframes, "combocolor_high", "color")
      CreateConfig(U["combopoints"], T["Empty Combopoint Color"], C.unitframes, "comboemptycolor", "color")

      CreateConfig(nil, T["Text"], nil, nil, "header")
      CreateConfig(U["combopoints"], T["Combopoint Font Size"], C.unitframes, "combofontsize", nil, nil, nil, nil, "number")
      CreateConfig(U["combopoints"], T["Combopoint Text Color"], C.unitframes, "combotextcolor", "color")
    end)

    -- 能量条（独立子页，与连击点平级；模块 modules/energybar.lua，参考 RogueTicker 样式）
    -- 「所有资源类型都显示」+「自动着色」：德鲁伊人形态(法力)/战士(怒气)也显示并按类型换色；
    -- 关掉前者退回「只在能量形态(盗贼/猫德)显示」；关掉后者用固定「能量条颜色」。
    CreateGUIEntry(T["Unit Frames"], T["Energy Bar"], function()
      CreateConfig(U["energybar"], T["Show Energy Bar"], C.unitframes, "comboenergyshow", "checkbox")
      CreateConfig(U["energybar"], T["Show On All Power Types"], C.unitframes, "comboenergyallpower", "checkbox")

      CreateConfig(nil, T["Layout"], nil, nil, "header")
      CreateConfig(U["energybar"], T["Energy Bar Width (0 = Fit Combopoints)"], C.unitframes, "comboenergywidth", nil, nil, nil, nil, "number")
      CreateConfig(U["energybar"], T["Energy Bar Height"], C.unitframes, "comboenergyheight", nil, nil, nil, nil, "number")
      CreateConfig(U["energybar"], T["Energy Bar X Offset"], C.unitframes, "comboenergyoffx", nil, nil, nil, nil, "number")
      CreateConfig(U["energybar"], T["Energy Bar Y Offset"], C.unitframes, "comboenergyoffy", nil, nil, nil, nil, "number")
      CreateConfig(U["energybar"], T["Shift Other Elements"], C.unitframes, "comboenergyshift", nil, nil, nil, nil, "number")
      CreateConfig(U["energybar"], T["Show Druid Mana Bar"], C.unitframes, "comboenergydruidmana", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(U["energybar"], T["Druid Mana Bar Height"], C.unitframes, "comboenergydruidmanaheight", nil, nil, nil, nil, "number", "vanilla")

      CreateConfig(nil, T["Appearance"], nil, nil, "header")
      CreateConfig(U["energybar"], T["Energy Bar Texture"], C.unitframes, "comboenergytexture", "dropdown", pfUI.gui.dropdowns.combo_texture)
      CreateConfig(U["energybar"], T["Energy Bar Color"], C.unitframes, "comboenergycolor", "color")
      CreateConfig(U["energybar"], T["Auto Power Color"], C.unitframes, "comboenergyautocolor", "checkbox")
      CreateConfig(U["energybar"], T["Energy Bar Background"], C.unitframes, "comboenergybgcolor", "color")
      CreateConfig(U["energybar"], T["Show Energy Bar Border"], C.unitframes, "comboenergyborder", "checkbox")
      CreateConfig(U["energybar"], T["Smooth Energy Bar"], C.unitframes, "comboenergysmooth", "checkbox")

      -- 自动隐藏（与头像框那套 AUTOHIDE 同逻辑）
      CreateConfig(nil, T["Auto Hide"], nil, nil, "header")
      CreateConfig(U["energybar"], T["Enable Auto Hide"], C.unitframes, "comboenergyauthide", "checkbox")
      CreateConfig(U["energybar"], T["Autohide Timeout"], C.unitframes, "comboenergyhidetime", nil, nil, nil, nil, "number")
      CreateConfig(U["energybar"], T["Show In Combat"], C.unitframes, "comboenergyhidecombat", "checkbox")
      CreateConfig(U["energybar"], T["Hide At Full Power"], C.unitframes, "comboenergyhidefull", "checkbox")

      CreateConfig(nil, T["Text"], nil, nil, "header")
      CreateConfig(U["energybar"], T["Show Energy Value"], C.unitframes, "comboenergyshowtext", "checkbox")
      CreateConfig(U["energybar"], T["Energy Value Format"], C.unitframes, "comboenergytextformat", "dropdown", pfUI.gui.dropdowns.comboenergy_format)
      CreateConfig(U["energybar"], T["Energy Font Size"], C.unitframes, "comboenergyfontsize", nil, nil, nil, nil, "number")
      CreateConfig(U["energybar"], T["Energy Text Color"], C.unitframes, "comboenergytextcolor", "color")
      CreateConfig(U["energybar"], T["Energy Text Align"], C.unitframes, "comboenergytextalign", "dropdown", pfUI.gui.dropdowns.comboenergy_align)
      CreateConfig(U["energybar"], T["Show Energy Tick Indicator"], C.unitframes, "comboenergyshowtick", "checkbox")
    end)

    -- 距离显示（原 General 页「UnitXP Settings」整段 35 项拆成独立子页，做法同连击点）
    CreateGUIEntry(T["Unit Frames"], T["Distance Display"], function()
      CreateConfig(nil, T["Distance Display"], nil, nil, "header")
      CreateConfig(nil, T["Show Distance of Target"], C.unitframes, "distance_indicator", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, T["Distance Indicator Update Interval (sec)"], C.unitframes, "distance_indicator_update_interval", nil, nil, nil, nil, "number", "vanilla")
      CreateConfig(function() end, T["Use Distance Gradient"], C.unitframes, "distance_indicator_use_gradient", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Distance Font Size"], C.unitframes, "distance_indicator_font_size", nil, nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Face Color"], C.unitframes, "distance_indicator_face_color", "color", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Back Color"], C.unitframes, "distance_indicator_back_color", "color", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Deadzone Color"], C.unitframes, "distance_indicator_deadzone_color", "color", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Out of Sight Color"], C.unitframes, "distance_indicator_outsight_color", "color", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Show Out of Sight Icon"], C.unitframes, "distance_indicator_outsight_icon", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, T["Out of Sight Icon Size"], C.unitframes, "distance_indicator_icon_size", nil, nil, nil, nil, "number", "vanilla")
      CreateConfig(function() end, T["Show Prefix Text (Melee/Face/Deadzone)"], C.unitframes, "distance_indicator_show_prefix", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Play Sound When Facing"], C.unitframes, "distance_indicator_sound", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Only Play Sound In Group"], C.unitframes, "distance_indicator_sound_only_group", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Sound Cooldown (sec)"], C.unitframes, "distance_indicator_sound_cooldown", nil, nil, nil, nil, nil, "vanilla")

      CreateConfig(nil, T["Mouseover"], nil, nil, "header")
      CreateConfig(nil, T["Mouseover Tooltip Distance"], C.unitframes, "mouseover_tooltip_distance", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, T["Mouseover Tooltip Update Interval (sec)"], C.unitframes, "mouseover_tooltip_update_interval", nil, nil, nil, nil, "number", "vanilla")
      CreateConfig(function() end, T["Use Linear Gradient"], C.unitframes, "mouseover_distance_linear_color", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Gradient Start Distance"], C.unitframes, "mouseover_distance_linear_from", nil, nil, nil, nil, "number", "vanilla")
      CreateConfig(function() end, T["Gradient End Distance"], C.unitframes, "mouseover_distance_linear_to", nil, nil, nil, nil, "number", "vanilla")
      CreateConfig(function() end, T["Start Color"], C.unitframes, "mouseover_distance_linear_color_from", "color", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["End Color"], C.unitframes, "mouseover_distance_linear_color_to", "color", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Use Out of Sight Color Override"], C.unitframes, "mouseover_distance_use_outsight", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(function() end, T["Out of Sight Color"], C.unitframes, "mouseover_distance_outsight_color", "color", nil, nil, nil, nil, "vanilla")

      CreateConfig(nil, T["Pet Distance Display"], nil, nil, "header")
      CreateConfig(function() end, T["Display Mode"], C.unitframes, "distance_indicator_pet_mode", "dropdown", {
          "0:" .. T["Disabled"],
          "1:" .. T["Always"],
          "2:" .. T["Only during Eyes of the Beast"],
       })
      CreateConfig(function() end, T["Font Size"], C.unitframes, "distance_indicator_pet_font_size")
      CreateConfig(function() end, T["Color"], C.unitframes, "distance_indicator_pet_color", "color")
      CreateConfig(function() end, T["Vertical Offset"], C.unitframes, "distance_indicator_pet_offset_y")
    end)

    -- Shared Unit- and Groupframes
    local unitframeSettings = {
      --      config,        text
      [1] = { "player",      T["Player"] },
      [2] = { "target",      T["Target"] },
      [3] = { "ttarget",     T["Target-Target"]},
      [4] = { "tttarget",    T["Target-Target-Target"]},
      [5] = { "pet",         T["Pet"] },
      [6] = { "ptarget",     T["Pet-Target"]},
      [7] = { "focus",       T["Focus"] },
      [8] = { "focustarget", T["Focus-Target"] },
      [9] = { "group",       T["Group"] },
      [10] = { "grouptarget", T["Group-Target"]},
      [11] = { "grouppet",   T["Group-Pet"] },
      [12] = { "raid",       T["Raid"] },
      [13] = { "raidpet",    T["Raid-Pet"] },
    }

    CreateGUIEntry(T["Unit Frames"], T["Click Casting"], function()
      for id, data in ipairs(unitframeSettings) do
        CreateConfig(U[data[1]], T["Enable"] .. " " .. data[2] .. " " .. T["Click Casting"], C.unitframes[data[1]], "clickcast", "checkbox")
      end

      CreateConfig(nil, T["Left Mouse Button"], nil, nil, "header")
      CreateConfig(nil, T["Click Action"], C.unitframes, "clickcast", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Shift-Click Action"], C.unitframes, "clickcast_shift", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Alt-Click Action"], C.unitframes, "clickcast_alt", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Ctrl-Click Action"], C.unitframes, "clickcast_ctrl", nil, nil, nil, nil, "STRING")

      CreateConfig(nil, T["Right Mouse Button"], nil, nil, "header")
      CreateConfig(nil, T["Click Action"], C.unitframes, "clickcast2", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Shift-Click Action"], C.unitframes, "clickcast2_shift", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Alt-Click Action"], C.unitframes, "clickcast2_alt", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Ctrl-Click Action"], C.unitframes, "clickcast2_ctrl", nil, nil, nil, nil, "STRING")

      CreateConfig(nil, T["Middle Mouse Button"], nil, nil, "header")
      CreateConfig(nil, T["Click Action"], C.unitframes, "clickcast3", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Shift-Click Action"], C.unitframes, "clickcast3_shift", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Alt-Click Action"], C.unitframes, "clickcast3_alt", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Ctrl-Click Action"], C.unitframes, "clickcast3_ctrl", nil, nil, nil, nil, "STRING")

      CreateConfig(nil, T["Mouse Button 4"], nil, nil, "header")
      CreateConfig(nil, T["Click Action"], C.unitframes, "clickcast4", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Shift-Click Action"], C.unitframes, "clickcast4_shift", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Alt-Click Action"], C.unitframes, "clickcast4_alt", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Ctrl-Click Action"], C.unitframes, "clickcast4_ctrl", nil, nil, nil, nil, "STRING")

      CreateConfig(nil, T["Mouse Button 5"], nil, nil, "header")
      CreateConfig(nil, T["Click Action"], C.unitframes, "clickcast5", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Shift-Click Action"], C.unitframes, "clickcast5_shift", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Alt-Click Action"], C.unitframes, "clickcast5_alt", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Ctrl-Click Action"], C.unitframes, "clickcast5_ctrl", nil, nil, nil, nil, "STRING")
    end)

    for id, data in ipairs(unitframeSettings) do
      local c = data[1]
      local t = data[2]

      CreateGUIEntry(T["Unit Frames"], t, function()
        -- link Update tables
        U.ttarget     = U["targettarget"]
        U.tttarget    = U["targettargettarget"]
        U.ptarget     = U["pettarget"]
        U.grouptarget = U["group"]
        U.grouppet    = U["group"]
        U.raidpet     = U["raid"]

        -- build config entries
        CreateConfig(U[c], T["Display Frame"] .. ": " .. t, C.unitframes[c], "visible", "checkbox")
        CreateConfig(U[c], T["Enable Mouseover Tooltip"], C.unitframes[c], "showtooltip", "checkbox")
        CreateConfig(U[c], T["Default Transparency"], C.unitframes[c], "alpha_visible", "dropdown", pfUI.gui.dropdowns.percent_small)
        CreateConfig(U[c], T["Out Of Range Transparency"], C.unitframes[c], "alpha_outrange", "dropdown", pfUI.gui.dropdowns.percent_small)
        CreateConfig(U[c], T["Offline Transparency"], C.unitframes[c], "alpha_offline", "dropdown", pfUI.gui.dropdowns.percent_small)
        CreateConfig(U[c], T["Enable Range Fading"], C.unitframes[c], "faderange", "checkbox")
        -- 新增：鼠标悬停发光选项
        CreateConfig(U[c], T["Enable Hover Glow"], C.unitframes[c], "hoverglow", "checkbox")																		   		 
        CreateConfig(U[c], T["Enable Aggro Glow"], C.unitframes[c], "glowaggro", "checkbox")
        CreateConfig(U[c], T["Enable Combat Glow"], C.unitframes[c], "glowcombat", "checkbox")
        CreateConfig(U[c], T["Portrait Position"], C.unitframes[c], "portrait", "dropdown", pfUI.gui.dropdowns.uf_portrait_position)
        CreateConfig(U[c], T["Portrait Width"], C.unitframes[c], "portraitwidth")
        CreateConfig(U[c], T["Portrait Height"], C.unitframes[c], "portraitheight")
        CreateConfig(U[c], T["Health Bar Texture"], C.unitframes[c], "bartexture", "dropdown", pfUI.gui.dropdowns.uf_bartexture)
        CreateConfig(U[c], T["Power Bar Texture"], C.unitframes[c], "pbartexture", "dropdown", pfUI.gui.dropdowns.uf_bartexture)
        CreateConfig(U[c], T["UnitFrame Spacing"], C.unitframes[c], "pspace")
        CreateConfig(U[c], T["Show PvP-Flag"], C.unitframes[c], "showPVP", "checkbox")
		CreateConfig(U[c], T["PvP Flag Size"], C.unitframes[c], "pvpiconsize")
        CreateConfig(U[c], T["PvP Flag Position"], C.unitframes[c], "pvpiconalign", "dropdown", pfUI.gui.dropdowns.positions)
        CreateConfig(U[c], T["PvP Flag X-Offset"], C.unitframes[c], "pvpiconoffx")
        CreateConfig(U[c], T["PvP Flag Y-Offset"], C.unitframes[c], "pvpiconoffy")
        CreateConfig(U[c], T["Show Loot Icon"], C.unitframes[c], "looticon", "checkbox")
        CreateConfig(U[c], T["Show Leader Icon"], C.unitframes[c], "leadericon", "checkbox")
        CreateConfig(U[c], T["Show Assistant Icon"], C.unitframes[c], "assisticon", "checkbox")
        if c == "pet" then
          CreateConfig(U[c], T["Show Happiness Icon"], C.unitframes[c], "happinessicon", "dropdown", pfUI.gui.dropdowns.uf_happiness)
          CreateConfig(U[c], T["Happiness Icon Size"], C.unitframes[c], "happinesssize")
        end
        CreateConfig(U[c], T["Show Raid Mark"], C.unitframes[c], "raidicon", "checkbox")
        CreateConfig(U[c], T["Raid Mark Position"], C.unitframes[c], "raidiconalign", "dropdown", pfUI.gui.dropdowns.positions)
        CreateConfig(U[c], T["Raid Mark X-Offset"], C.unitframes[c], "raidiconoffx")
        CreateConfig(U[c], T["Raid Mark Y-Offset"], C.unitframes[c], "raidiconoffy")
        CreateConfig(U[c], T["Raid Mark Size"], C.unitframes[c], "raidiconsize")
        CreateConfig(U[c], T["Heal Color"], C.unitframes[c], "healcolor", "color")
        CreateConfig(U[c], T["Display Overheal"], C.unitframes[c], "overhealperc", "dropdown", pfUI.gui.dropdowns.uf_overheal)

        -- 仇恨显示框（仅目标框）
        if c == "target" then
          -- 闭包延迟引用：gui 模块排在 target 模块之前加载，构建面板时
          -- pfUI.uf.target_threat_apply 尚为 nil，故用闭包在用户改设置时再取，
          -- 保证材质/长宽改动实时生效（无需重载）。
          local function applyThreatBox()
            if pfUI.uf and pfUI.uf.target_threat_apply then
              pfUI.uf.target_threat_apply()
            end
          end
          CreateConfig(nil, "仇恨显示框", nil, nil, "header")
          CreateConfig(U[c], "显示仇恨框（可拖动，默认在头像框左侧）", C.unitframes[c], "showthreat", "checkbox")
          CreateConfig(applyThreatBox, "仇恨框材质（默认 pfUI-F，同头像）", C.unitframes[c], "threattexture", "dropdown", pfUI.gui.dropdowns.uf_threattexture)
          CreateConfig(applyThreatBox, "仇恨框宽度", C.unitframes[c], "ligh", "text", nil, nil, nil, "number")
          CreateConfig(applyThreatBox, "仇恨框高度", C.unitframes[c], "lightH", "text", nil, nil, nil, "number")
        end

        if c == "raid" then
          CreateConfig(U["raid"], T["Display Raid Group Label"], C.unitframes[c], "raidgrouplabel", "checkbox")
          CreateConfig(U["raid"], T["Group Label X-Offset"], C.unitframes[c], "grouplabelxoff")
          CreateConfig(U["raid"], T["Group Label Y-Offset"], C.unitframes[c], "grouplabelyoff")
          CreateConfig(U["raid"], T["Group Label Font Size"], C.unitframes[c], "grouplabelfontsize")

          CreateConfig(U[c], T["Layout"], nil, nil, "header")
          CreateConfig(U["raid"], T["Raid Padding"], C.unitframes[c], "raidpadding")
          CreateConfig(U["raid"], T["Raid Layout"], C.unitframes[c], "raidlayout", "dropdown", pfUI.gui.dropdowns.uf_raidlayout)
          CreateConfig(U["raid"], T["Raid Fill Direction"], C.unitframes[c], "raidfill", "dropdown", pfUI.gui.dropdowns.uf_raidfill)
        end

        -- Auto Hide
        CreateConfig(nil, T["Auto Hide"], nil, nil, "header")
        CreateConfig(U[c], T["Enable Auto Hide"], C.unitframes[c], "autohide", "checkbox")
        CreateConfig(U[c], T["Hide Timeout (seconds)"], C.unitframes[c], "hide_time")
        CreateConfig(U[c], T["Show in Combat"], C.unitframes[c], "hide_combat", "checkbox")
        CreateConfig(U[c], T["Only Hide at Full Health"], C.unitframes[c], "hide_fullhp", "checkbox")

        CreateConfig(U[c], T["Healthbar"], nil, nil, "header")
        CreateConfig(U[c], T["Health Bar Width"], C.unitframes[c], "width")
        CreateConfig(U[c], T["Health Bar Height"], C.unitframes[c], "height")
        CreateConfig(U[c], T["Left Text"], C.unitframes[c], "txthpleft", "dropdown", pfUI.gui.dropdowns.uf_texts)
        CreateConfig(U[c], T["Left Text X Offset"], C.unitframes[c], "txthpleftoffx")
        CreateConfig(U[c], T["Left Text Y Offset"], C.unitframes[c], "txthpleftoffy")
        CreateConfig(U[c], T["Center Text"], C.unitframes[c], "txthpcenter", "dropdown", pfUI.gui.dropdowns.uf_texts)
        CreateConfig(U[c], T["Center Text X Offset"], C.unitframes[c], "txthpcenteroffx")
        CreateConfig(U[c], T["Center Text Y Offset"], C.unitframes[c], "txthpcenteroffy")
        CreateConfig(U[c], T["Right Text"], C.unitframes[c], "txthpright", "dropdown", pfUI.gui.dropdowns.uf_texts)
        CreateConfig(U[c], T["Right Text X Offset"], C.unitframes[c], "txthprightoffx")
        CreateConfig(U[c], T["Right Text Y Offset"], C.unitframes[c], "txthprightoffy")
        CreateConfig(U[c], T["Invert Health Bar"], C.unitframes[c], "invert_healthbar", "checkbox")
        CreateConfig(U[c], T["Enable Vertical Health Bar"], C.unitframes[c], "verticalbar", "checkbox")

        CreateConfig(U[c], T["Powerbar"], nil, nil, "header")
        CreateConfig(U[c], T["Power Bar Height"], C.unitframes[c], "pheight")
        CreateConfig(U[c], T["Power Bar Width"], C.unitframes[c], "pwidth")
        CreateConfig(U[c], T["Power Bar X-Offset"], C.unitframes[c], "poffx")
        CreateConfig(U[c], T["Power Bar Y-Offset"], C.unitframes[c], "poffy")
        CreateConfig(U[c], T["Left Text"], C.unitframes[c], "txtpowerleft", "dropdown", pfUI.gui.dropdowns.uf_texts)
        CreateConfig(U[c], T["Left Text X Offset"], C.unitframes[c], "txtpowerleftoffx")
        CreateConfig(U[c], T["Left Text Y Offset"], C.unitframes[c], "txtpowerleftoffy")
        CreateConfig(U[c], T["Center Text"], C.unitframes[c], "txtpowercenter", "dropdown", pfUI.gui.dropdowns.uf_texts)
        CreateConfig(U[c], T["Center Text X Offset"], C.unitframes[c], "txtpowercenteroffx")
        CreateConfig(U[c], T["Center Text Y Offset"], C.unitframes[c], "txtpowercenteroffy")
        CreateConfig(U[c], T["Right Text"], C.unitframes[c], "txtpowerright", "dropdown", pfUI.gui.dropdowns.uf_texts)
        CreateConfig(U[c], T["Right Text X Offset"], C.unitframes[c], "txtpowerrightoffx")
        CreateConfig(U[c], T["Right Text Y Offset"], C.unitframes[c], "txtpowerrightoffy")
        CreateConfig(U[c], T["Power Bar Anchor"], C.unitframes[c], "panchor", "dropdown", pfUI.gui.dropdowns.uf_powerbar_position)

        CreateConfig(U[c], T["Combat Text"], nil, nil, "header")
        CreateConfig(U[c], T["Show Combat Text"], C.unitframes[c], "hitindicator", "checkbox")
        CreateConfig(U[c], T["Combat Text Font"], C.unitframes[c], "hitindicatorfont", "dropdown", pfUI.gui.dropdowns.fonts)
        CreateConfig(U[c], T["Combat Text Size"], C.unitframes[c], "hitindicatorsize")

        CreateConfig(U[c], T["Text Colors"], nil, nil, "header")
        CreateConfig(U[c], T["Automatic Health Text Color"], C.unitframes[c], "healthcolor", "checkbox")
        CreateConfig(U[c], T["Automatic Power Text Color"], C.unitframes[c], "powercolor", "checkbox")
        CreateConfig(U[c], T["Automatic Level Text Color"], C.unitframes[c], "levelcolor", "checkbox")
        CreateConfig(U[c], T["Automatic Class Text Color"], C.unitframes[c], "classcolor", "checkbox")

        CreateConfig(U[c], T["Timer"], nil, nil, "header")
        CreateConfig(U[c], T["Show Timer Text"], C.unitframes[c], "cooldown_text", "checkbox")
        CreateConfig(Reload, T["Show Timer Animation"], C.unitframes[c], "cooldown_anim", "checkbox")

        CreateConfig(U[c], T["Buffs"], nil, nil, "header")
        CreateConfig(U[c], T["Buff Position"], C.unitframes[c], "buffs", "dropdown", pfUI.gui.dropdowns.uf_buff_position)
        CreateConfig(U[c], T["Buff Size"], C.unitframes[c], "buffsize")
        CreateConfig(U[c], T["Buff X-Offset"], C.unitframes[c], "buffoffx")
        CreateConfig(U[c], T["Buff Y-Offset"], C.unitframes[c], "buffoffy")
        CreateConfig(U[c], T["Buff Limit"], C.unitframes[c], "bufflimit")
        CreateConfig(U[c], T["Buffs Per Row"], C.unitframes[c], "buffperrow")
        CreateConfig(U[c], T["Filter Mode"], C.unitframes[c], "bufffilter", "dropdown", pfUI.gui.dropdowns.buffbarfilter)
        CreateConfig(U[c], T["Whitelist"], C.unitframes[c], "buffwhitelist", "list")
        CreateConfig(U[c], T["Blacklist"], C.unitframes[c], "buffblacklist", "list")

        CreateConfig(U[c], T["Debuffs"], nil, nil, "header")
        CreateConfig(U[c], T["Debuff Position"], C.unitframes[c], "debuffs", "dropdown", pfUI.gui.dropdowns.uf_buff_position)
        CreateConfig(U[c], T["Debuff Size"], C.unitframes[c], "debuffsize")
        CreateConfig(U[c], T["Debuff X-Offset"], C.unitframes[c], "debuffoffx")
        CreateConfig(U[c], T["Debuff Y-Offset"], C.unitframes[c], "debuffoffy")
        CreateConfig(U[c], T["Debuff Limit"], C.unitframes[c], "debufflimit")
        CreateConfig(U[c], T["Debuffs Per Row"], C.unitframes[c], "debuffperrow")
        CreateConfig(U[c], T["Filter Mode"], C.unitframes[c], "debufffilter", "dropdown", pfUI.gui.dropdowns.buffbarfilter)
        CreateConfig(U[c], T["Whitelist"], C.unitframes[c], "debuffwhitelist", "list")
        CreateConfig(U[c], T["Blacklist"], C.unitframes[c], "debuffblacklist", "list")																					  

        if c ~= "player" then
          CreateConfig(U[c], T["Only Show Own Debuffs"], C.unitframes[c], "selfdebuff", "checkbox")
        end

        CreateConfig(U[c], T["Combat/Aggro Indicators"], nil, nil, "header")
        CreateConfig(U[c], T["Display Aggro Indicator"], C.unitframes[c], "squareaggro", "checkbox")
        CreateConfig(U[c], T["Display Combat Indicator"], C.unitframes[c], "squarecombat", "checkbox")
        CreateConfig(U[c], T["Indicator Position"], C.unitframes[c], "squarepos", "dropdown", pfUI.gui.dropdowns.positions)
        CreateConfig(U[c], T["Indicator Size"], C.unitframes[c], "squaresize")

        CreateConfig(U[c], T["Buff/Debuff Indicators"], nil, nil, "header")
        CreateConfig(U[c], T["Enable Indicators"], C.unitframes[c], "buff_indicator", "checkbox")
        CreateConfig(U[c], T["Show Time Left"], C.unitframes[c], "indicator_time", "checkbox")
        CreateConfig(U[c], T["Show Stacks"], C.unitframes[c], "indicator_stacks", "checkbox")
        CreateConfig(U[c], T["Indicator Size"], C.unitframes[c], "indicator_size")
        CreateConfig(U[c], T["Indicator Spacing"], C.unitframes[c], "indicator_spacing", "dropdown", pfUI.gui.dropdowns.spacing)
        CreateConfig(U[c], T["Indicator Position"], C.unitframes[c], "indicator_pos", "dropdown", pfUI.gui.dropdowns.positions)
        CreateConfig(U[c], T["Show Custom Indicators"], C.unitframes[c], "custom_indicator", "list")
        CreateConfig(U[c], T["Show Buff Indicators"], C.unitframes[c], "show_buffs", "checkbox")
        CreateConfig(U[c], T["Enable Missing Buff Indicators"], C.unitframes[c], "missing_buffs_enabled", "checkbox")
        CreateConfig(U[c], T["Missing Buffs"], C.unitframes[c], "missing_buffs", "list")
        CreateConfig(U[c], T["Show Hots Indicators"], C.unitframes[c], "show_hots", "checkbox")
        CreateConfig(U[c], T["Show Hots of all Classes"], C.unitframes[c], "all_hots", "checkbox")
        CreateConfig(U[c], T["Show Procs Indicators"], C.unitframes[c], "show_procs", "checkbox")
        CreateConfig(U[c], T["Show Procs of all Classes"], C.unitframes[c], "all_procs", "checkbox")
        CreateConfig(U[c], T["Show Totems Indicators"], C.unitframes[c], "show_totems", "checkbox")

        CreateConfig(U[c], T["Dispel Indicators"], nil, nil, "header")
        CreateConfig(U[c], T["Show Dispel Indicators"], C.unitframes[c], "debuff_indicator", "dropdown", pfUI.gui.dropdowns.uf_debuff_indicator)
        CreateConfig(U[c], T["Only Class Dispellable"], C.unitframes[c], "debuff_ind_class", "checkbox")
        CreateConfig(U[c], T["Indicator Position"], C.unitframes[c], "debuff_ind_pos", "dropdown", pfUI.gui.dropdowns.positions)
        CreateConfig(U[c], T["Indicator Size"], C.unitframes[c], "debuff_ind_size", "dropdown", pfUI.gui.dropdowns.uf_debuff_indicator_size)

        CreateConfig(U[c], T["Overwrite Fonts"], nil, nil, "header")
        CreateConfig(U[c], T["Use Custom Font Settings"], C.unitframes[c], "customfont", "checkbox")
        CreateConfig(U[c], T["Custom Font Name"], C.unitframes[c], "customfont_name", "dropdown", pfUI.gui.dropdowns.fonts)
        CreateConfig(U[c], T["Custom Font Size"], C.unitframes[c], "customfont_size")
        CreateConfig(U[c], T["Custom Font Style"], C.unitframes[c], "customfont_style", "dropdown", pfUI.gui.dropdowns.fontstyle)

        CreateConfig(U[c], T["Overwrite Colors"], nil, nil, "header")
        CreateConfig(U[c], T["Inherit Default Colors"], C.unitframes[c], "defcolor", "checkbox")
        CreateConfig(U[c], T["Health Bar Color"], C.unitframes[c], "custom", "dropdown", pfUI.gui.dropdowns.uf_color)
        CreateConfig(U[c], T["Custom Health Bar Color"], C.unitframes[c], "customcolor", "color")
        CreateConfig(U[c], T["Fade To Custom Color"], C.unitframes[c], "customfade", "checkbox")
        CreateConfig(U[c], T["Use Custom Color On Full Health"], C.unitframes[c], "customfullhp", "checkbox")
        CreateConfig(U[c], T["Custom Health Bar Background Color"], C.unitframes[c], "custombgcolor", "color")
        CreateConfig(U[c], T["Use Custom Color Health Bar Background"], C.unitframes[c], "custombg", "checkbox")
        CreateConfig(U[c], T["Custom Power Bar Background Color"], C.unitframes[c], "custompbgcolor", "color")
        CreateConfig(U[c], T["Use Custom Color Power Bar Background"], C.unitframes[c], "custompbg", "checkbox")
        CreateConfig(U[c], T["Mana Color"], C.unitframes[c], "manacolor", "color")
        CreateConfig(U[c], T["Rage Color"], C.unitframes[c], "ragecolor", "color")
        CreateConfig(U[c], T["Energy Color"], C.unitframes[c], "energycolor", "color")
        CreateConfig(U[c], T["Focus Color"], C.unitframes[c], "focuscolor", "color")

        if c == "player" then
          CreateConfig(nil, T["Player SP/Haste Display"], nil, nil, "header")
          CreateConfig(nil, T["Haste Display"], C.unitframes[c], "display_haste", "dropdown", {
            "0:"..T["None"],
            "1:"..T["Haste (cast speed increase)"],
            "2:"..T["Effective Haste (Haste * cast time reduction)"], -- Only affects mages/warlocks I believe
          })
          CreateConfig(nil, T["Haste Display Color"], C.unitframes[c], "display_haste_color", "color")
          CreateConfig(nil, T["Display Spell Power"], C.unitframes[c], "display_spellpower", "checkbox")
          CreateConfig(nil, T["Use Custom Spell Power Color (unchecked = biggest school color)"], C.unitframes[c], "display_sp_color_override", "checkbox")
          CreateConfig(nil, T["Spell Power Color"], C.unitframes[c], "display_sp_color", "color")
        end
      end)
    end

    CreateGUIEntry(T["Bags & Bank"], nil, function()
      CreateConfig(nil, T["Disable Item Quality Color For \"Common\" Items"], C.appearance.bags, "borderlimit", "checkbox")
      CreateConfig(nil, T["Enable Item Quality Color For Equipment Only"], C.appearance.bags, "borderonlygear", "checkbox")
      CreateConfig(nil, T["Highlight Unusable Items"], C.appearance.bags, "unusable", "checkbox")
      CreateConfig(nil, T["Unusable Item Color"], C.appearance.bags, "unusable_color", "color")
      CreateConfig(nil, T["Enable Movable Bags"], C.appearance.bags, "movable", "checkbox")
      CreateConfig(nil, T["Anchor Bags Above Chat"], C.appearance.bags, "abovechat", "checkbox")
      CreateConfig(nil, T["Hide Chat When Bags Are Opened"], C.appearance.bags, "hidechat", "checkbox")
      CreateConfig(nil, T["Bagslots Per Row"], C.appearance.bags, "bagrowlength")
      CreateConfig(nil, T["Bankslots Per Row"], C.appearance.bags, "bankrowlength")
      CreateConfig(nil, T["Enable Full-Text Search"], C.appearance.bags, "fulltext")
      CreateConfig(nil, T["Item Slot Size"], C.appearance.bags, "icon_size")
      CreateConfig(nil, T["Auto Sell Grey Items"], C.global, "autosell", "checkbox")
      CreateConfig(nil, T["Auto Repair Items"], C.global, "autorepair", "checkbox")
      CreateConfig(nil, T["Enable Merchant Bulk Buy (BuyEmAll)"], C.global, "buyemall", "checkbox")
    end)

    CreateGUIEntry(T["Loot"], nil, function()
      CreateConfig(nil, T["Enable Auto-Resize Loot Frame"], C.loot, "autoresize", "checkbox")
      CreateConfig(nil, T["Disable Loot Confirmation Dialog (Without Group)"], C.loot, "autopickup", "checkbox")
      CreateConfig(nil, T["Enable Loot Window On MouseCursor"], C.loot, "mousecursor", "checkbox")
      CreateConfig(nil, T["Enable Advanced Master Loot Menu"], C.loot, "advancedloot", "checkbox")
      CreateConfig(nil, T["Random Roll Announcement Rarity"], C.loot, "rollannouncequal", "dropdown", pfUI.gui.dropdowns.loot_rarity)
      CreateConfig(nil, T["Detailed Random Roll Announcement"], C.loot, "rollannounce", "checkbox")
      CreateConfig(nil, T["Use Item Rarity Color For Loot-Roll Timer"], C.loot, "raritytimer", "checkbox")
       -- 添加新的战利品通报配置项
      CreateConfig(nil, T["Enable Loot Announce Buttons"], C.loot, "announce_enabled", "checkbox")  -- 新增
      CreateConfig(nil, T["Merge Items In Announcement"], C.loot, "announce_merge", "checkbox")
      CreateConfig(nil, T["Show Item Numbers In Announcement"], C.loot, "announce_numbers", "checkbox")
      CreateConfig(nil, T["Show Stack Size In Announcement"], C.loot, "announce_stacksize", "checkbox")
      CreateConfig(nil, T["Minimum Quality To Announce"], C.loot, "announce_quality", "dropdown", pfUI.gui.dropdowns.loot_rarity)
    end)

    CreateGUIEntry(T["Minimap"], T["Minimap"], function()
      CreateConfig(U["minimap"], T["Minimap Size (|cffffaaaaExperimental|r)"], C.appearance.minimap, "size")
      CreateConfig(U["minimap"], T["Minimap Player Arrow Scale"], C.appearance.minimap, "arrowscale")
      CreateConfig(nil, T["Zone Text On Minimap"], C.appearance.minimap, "zonetext", "dropdown", pfUI.gui.dropdowns.minimap_zone_visibility)
      CreateConfig(nil, T["Coordinates On Minimap"], C.appearance.minimap, "coordstext", "dropdown", pfUI.gui.dropdowns.minimap_cords_visibility)
      CreateConfig(nil, T["Coordinates Location"], C.appearance.minimap, "coordsloc", "dropdown", pfUI.gui.dropdowns.minimap_cords_position)
      CreateConfig(nil, T["Show PvP Icon"], C.unitframes.player, "showPVPMinimap", "checkbox")
      CreateConfig(nil, T["Show Inactive Tracking"], C.appearance.minimap, "tracking_pulse", "checkbox")
      CreateConfig(nil, T["Tracking Icon Size"], C.appearance.minimap, "tracking_size")
      CreateConfig(nil, T["Hide Addon Buttons On Combat"], C.appearance.minimap, "addon_buttons", "checkbox")
    end)

    CreateGUIEntry(T["Minimap"], T["Addon Buttons"], function()
      CreateConfig(nil,               T["Enable Addon Button Frame"], C.abuttons, "enable", "checkbox")
      CreateConfig(U["addonbuttons"], T["Addon Buttons Panel Position"], C.abuttons, "position", "dropdown", pfUI.gui.dropdowns.addonbuttons_position)
      CreateConfig(U["addonbuttons"], T["Show Addon Buttons On Login"], C.abuttons, "showdefault", "checkbox")
      CreateConfig(U["addonbuttons"], T["Number Of Buttons Per Row/Column"], C.abuttons, "rowsize")
      CreateConfig(U["addonbuttons"], T["Button Spacing"], C.abuttons, "spacing")
      CreateConfig(U["addonbuttons"], T["Hide When Entering Combat"], C.abuttons, "hideincombat", "checkbox")
    end)

    CreateGUIEntry(T["Buffs"], T["Buff/Debuff Icons"], function()
      CreateConfig(U["buff"], T["Enable Buff Display"], C.buffs, "buffs", "checkbox")
      CreateConfig(U["buff"], T["Enable Debuff Display"], C.buffs, "debuffs", "checkbox")
      CreateConfig(U["buff"], T["Enable Weapon Buff Display"], C.buffs, "weapons", "checkbox")
      CreateConfig(U["buff"], T["Seperate Weapon Buffs"], C.buffs, "separateweapons", "checkbox")
      CreateConfig(U["buff"], T["Buff Size"], C.buffs, "size")
      CreateConfig(U["buff"], T["Buff Spacing"], C.buffs, "spacing")
      CreateConfig(U["buff"], T["Number Of Weapon Buffs Per Row"], C.buffs, "wepbuffrowsize")
      CreateConfig(U["buff"], T["Number Of Buffs Per Row"], C.buffs, "buffrowsize")
      CreateConfig(U["buff"], T["Number Of Debuffs Per Row"], C.buffs, "debuffrowsize")
      CreateConfig(U["buff"], T["Show Duration Inside Buff"], C.buffs, "textinside", "checkbox")
      CreateConfig(U["buff"], T["Buff Font Size"], C.buffs, "fontsize")
      CreateConfig(U["buff"], T["Show Exact Time"], C.buffs, "exacttime", "checkbox")
      CreateConfig(function() if pfUI.buff and pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end end, T["Filter Mode"], C.buffs, "filter", "dropdown", pfUI.gui.dropdowns.buffbarfilter)
      CreateConfig(function() if pfUI.buff and pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end end, T["Whitelist"], C.buffs, "whitelist", "list")
      CreateConfig(function() if pfUI.buff and pfUI.buff:GetScript("OnEvent") then pfUI.buff:GetScript("OnEvent")() end end, T["Blacklist"], C.buffs, "blacklist", "list")																			 
    end)

    CreateGUIEntry(T["Buffs"], T["Highlight Icons"], function()
      -- 名单分享：四套名单（玩家Buff/Debuff + 目标Buff/Debuff）合一导出导入，单按钮
      CreateConfig(nil, T["Share List"], nil, nil, "button", function()
        if not pfUI.buff then return end
        pfUI.api.CreateShareListDialog("pfSepShare", T["Share List"],
          function() return pfUI.buff:ExportSepShare("ALL") end,
          function(str) return pfUI.buff:ImportSepShare(str, "B") end)
      end)

      CreateConfig(nil, T["Seperate Buffs"], nil, nil, "header")
      -- 监控条（分离式Buff/Debuff + 目标版）独立的「显示持续时间在Buff里面」，
      -- 不跟随主 Buff 条的 textinside（独立设置需求 2026-10-22）
      CreateConfig(function() if pfUI.buff then pfUI.buff:UpdateConfig() end end, T["Show Duration Inside Buff"], C.buffs, "sep_textinside", "checkbox")
      -- 监控条独立字号（-1=跟随主 Buff 字号）；改后即时重刷四组监控条
      CreateConfig(function() if pfUI.buff then pfUI.buff:UpdateConfig() end end, T["Buff Font Size"], C.buffs, "sep_fontsize")
      CreateConfig(U["buff"], T["Enable Seperate Buffs"], C.buffs, "separatebuffs", "checkbox")
      CreateConfig(function() if pfUI.buff then pfUI.buff:UpdateConfig() end end, T["Seperate Buff List"], C.buffs, "separatelist", "list")
      CreateConfig(U["buff"], T["Seperate Buff Size"], C.buffs, "sepbuffsize")
      CreateConfig(U["buff"], T["Seperate Buffs Per Row"], C.buffs, "sepbuffrowsize")
      CreateConfig(U["buff"], T["Highlight Seperated Buffs"], C.buffs, "sepbuffglow", "checkbox")
      CreateConfig(U["buff"], T["Monitor Mode (Copy, Keep In Row)"], C.buffs, "sepbuffmonitor", "checkbox")

      CreateConfig(nil, T["Seperate Debuffs"], nil, nil, "header")
      CreateConfig(U["buff"], T["Enable Seperate Debuffs"], C.buffs, "separatedebuffs", "checkbox")
      CreateConfig(function() if pfUI.buff then pfUI.buff:UpdateConfig() end end, T["Seperate Debuff List"], C.buffs, "sepdebufflist", "list")
      CreateConfig(U["buff"], T["Seperate Debuff Size"], C.buffs, "sepdebuffsize")
      CreateConfig(U["buff"], T["Seperate Debuffs Per Row"], C.buffs, "sepdebuffrowsize")
      CreateConfig(U["buff"], T["Highlight Seperated Debuffs"], C.buffs, "sepdebuffglow", "checkbox")
      CreateConfig(U["buff"], T["Monitor Mode (Copy, Keep In Row)"], C.buffs, "sepdebuffmonitor", "checkbox")

      CreateConfig(nil, T["Seperate Target Buffs"], nil, nil, "header")
      CreateConfig(U["buff"], T["Enable Seperate Target Buffs"], C.buffs, "separatetargetbuffs", "checkbox")
      CreateConfig(function() if pfUI.buff then pfUI.buff:UpdateConfig() end end, T["Seperate Target Buff List"], C.buffs, "septargetbufflist", "list")
      CreateConfig(U["buff"], T["Seperate Target Buff Size"], C.buffs, "septargetbuffsize")
      CreateConfig(U["buff"], T["Seperate Target Buffs Per Row"], C.buffs, "septargetbuffrowsize")
      CreateConfig(U["buff"], T["Highlight Seperated Target Buffs"], C.buffs, "septargetbuffglow", "checkbox")

      CreateConfig(nil, T["Seperate Target Debuffs"], nil, nil, "header")
      CreateConfig(U["buff"], T["Enable Seperate Target Debuffs"], C.buffs, "separatetargetdebuffs", "checkbox")
      CreateConfig(function() if pfUI.buff then pfUI.buff:UpdateConfig() end end, T["Seperate Target Debuff List"], C.buffs, "septargetdebufflist", "list")
      CreateConfig(U["buff"], T["Seperate Target Debuff Size"], C.buffs, "septargetdebuffsize")
      CreateConfig(U["buff"], T["Seperate Target Debuffs Per Row"], C.buffs, "septargetdebuffrowsize")
      CreateConfig(U["buff"], T["Highlight Seperated Target Debuffs"], C.buffs, "septargetdebuffglow", "checkbox")

      CreateConfig(nil, T["Highlight Icons Usage"], nil, nil, "header")
    end)

    CreateGUIEntry(T["Buffs"], T["Totem Icons"], function()
      CreateConfig(U["totems"], T["Totem Direction"], C.totems, "direction", "dropdown", pfUI.gui.dropdowns.orientation)
      CreateConfig(U["totems"], T["Icon Size"], C.totems, "iconsize")
      CreateConfig(U["totems"], T["Spacing"], C.totems, "spacing", "dropdown", pfUI.gui.dropdowns.spacing)
      CreateConfig(U["totems"], T["Show Background"], C.totems, "showbg", "checkbox")
    end)

    CreateGUIEntry(T["Buffs"], T["Player Buff Bar"], function()
      CreateConfig(nil, T["Enable Bar"], C.buffbar.pbuff, "enable", "checkbox")
      CreateConfig(nil, T["Use Unit Fonts"], C.buffbar.pbuff, "use_unitfonts", "checkbox")
      CreateConfig(nil, T["Sort Order"], C.buffbar.pbuff, "sort", "dropdown", pfUI.gui.dropdowns.buffbarsort)
      CreateConfig(nil, T["Background Color"], C.buffbar.pbuff, "color", "color")
      CreateConfig(nil, T["Border Color"], C.buffbar.pbuff, "bordercolor", "color")
      CreateConfig(nil, T["Text Color"], C.buffbar.pbuff, "textcolor", "color")
      CreateConfig(nil, T["Automatic Background Color"], C.buffbar.pbuff, "dtypebg", "checkbox")
      CreateConfig(nil, T["Automatic Border Color"], C.buffbar.pbuff, "dtypeborder", "checkbox")
      CreateConfig(nil, T["Automatic Text Color"], C.buffbar.pbuff, "dtypetext", "checkbox")
      CreateConfig(nil, T["Color Buff Stacks"], C.buffbar.pbuff, "colorstacks", "checkbox")
      CreateConfig(nil, T["Buffbar Width"], C.buffbar.pbuff, "width")
      CreateConfig(nil, T["Buffbar Height"], C.buffbar.pbuff, "height")
      CreateConfig(nil, T["Filter Mode"], C.buffbar.pbuff, "filter", "dropdown", pfUI.gui.dropdowns.buffbarfilter)
      CreateConfig(nil, T["Time Threshold"], C.buffbar.pbuff, "threshold")
      CreateConfig(nil, T["Whitelist"], C.buffbar.pbuff, "whitelist", "list")
      CreateConfig(nil, T["Blacklist"], C.buffbar.pbuff, "blacklist", "list")
    end)

    CreateGUIEntry(T["Buffs"], T["Player Debuff Bar"], function()
      CreateConfig(nil, T["Enable Bar"], C.buffbar.pdebuff, "enable", "checkbox")
      CreateConfig(nil, T["Use Unit Fonts"], C.buffbar.pdebuff, "use_unitfonts", "checkbox")
      CreateConfig(nil, T["Sort Order"], C.buffbar.pdebuff, "sort", "dropdown", pfUI.gui.dropdowns.buffbarsort)
      CreateConfig(nil, T["Background Color"], C.buffbar.pdebuff, "color", "color")
      CreateConfig(nil, T["Border Color"], C.buffbar.pdebuff, "bordercolor", "color")
      CreateConfig(nil, T["Text Color"], C.buffbar.pdebuff, "textcolor", "color")
      CreateConfig(nil, T["Automatic Background Color"], C.buffbar.pdebuff, "dtypebg", "checkbox")
      CreateConfig(nil, T["Automatic Border Color"], C.buffbar.pdebuff, "dtypeborder", "checkbox")
      CreateConfig(nil, T["Automatic Text Color"], C.buffbar.pdebuff, "dtypetext", "checkbox")
      CreateConfig(nil, T["Color Debuff Stacks"], C.buffbar.pdebuff, "colorstacks", "checkbox")
      CreateConfig(nil, T["Buffbar Width"], C.buffbar.pdebuff, "width")
      CreateConfig(nil, T["Buffbar Height"], C.buffbar.pdebuff, "height")
      CreateConfig(nil, T["Filter Mode"], C.buffbar.pdebuff, "filter", "dropdown", pfUI.gui.dropdowns.buffbarfilter)
      CreateConfig(nil, T["Time Threshold"], C.buffbar.pdebuff, "threshold")
      CreateConfig(nil, T["Whitelist"], C.buffbar.pdebuff, "whitelist", "list")
      CreateConfig(nil, T["Blacklist"], C.buffbar.pdebuff, "blacklist", "list")
    end)

    CreateGUIEntry(T["Buffs"], T["Target Debuff Bar"], function()
      CreateConfig(nil, T["Enable Bar"], C.buffbar.tdebuff, "enable", "checkbox")
      CreateConfig(nil, T["Use Unit Fonts"], C.buffbar.tdebuff, "use_unitfonts", "checkbox")
      CreateConfig(nil, T["Sort Order"], C.buffbar.tdebuff, "sort", "dropdown", pfUI.gui.dropdowns.buffbarsort)
      CreateConfig(nil, T["Background Color"], C.buffbar.tdebuff, "color", "color")
      CreateConfig(nil, T["Border Color"], C.buffbar.tdebuff, "bordercolor", "color")
      CreateConfig(nil, T["Text Color"], C.buffbar.tdebuff, "textcolor", "color")
      CreateConfig(nil, T["Automatic Background Color"], C.buffbar.tdebuff, "dtypebg", "checkbox")
      CreateConfig(nil, T["Automatic Border Color"], C.buffbar.tdebuff, "dtypeborder", "checkbox")
      CreateConfig(nil, T["Automatic Text Color"], C.buffbar.tdebuff, "dtypetext", "checkbox")
      CreateConfig(nil, T["Color Debuff Stacks"], C.buffbar.tdebuff, "colorstacks", "checkbox")
      CreateConfig(nil, T["Buffbar Width"], C.buffbar.tdebuff, "width")
      CreateConfig(nil, T["Buffbar Height"], C.buffbar.tdebuff, "height")
      CreateConfig(nil, T["Show Only Own Debuffs"], C.buffbar.tdebuff, "selfdebuff", "checkbox")
      CreateConfig(nil, T["Filter Mode"], C.buffbar.tdebuff, "filter", "dropdown", pfUI.gui.dropdowns.buffbarfilter)
      CreateConfig(nil, T["Time Threshold"], C.buffbar.tdebuff, "threshold")
      CreateConfig(nil, T["Whitelist"], C.buffbar.tdebuff, "whitelist", "list")
      CreateConfig(nil, T["Blacklist"], C.buffbar.tdebuff, "blacklist", "list")
    end)

    CreateGUIEntry(T["Actionbar"], T["General"], function()
      CreateConfig(U["bars"], T["Trigger Actions On Key Down"], C.bars, "keydown", "checkbox")
      CreateConfig(U["bars"], T["Self Cast: Alt Key"], C.bars, "altself", "checkbox")
      CreateConfig(U["bars"], T["Self Cast: Right Click"], C.bars, "rightself", "checkbox")
      CreateConfig(U["bars"], T["Button Animation"], C.bars, "animation", "dropdown", pfUI.gui.dropdowns.actionbuttonanimations)
      CreateConfig(U["bars"], T["Button Animation Trigger"], C.bars, "animmode", "dropdown", pfUI.gui.dropdowns.animationmode)
      CreateConfig(U["bars"], T["Show Animation On Hidden Bars"], C.bars, "animalways", "checkbox")
      if not pfUI:MacroAddonsLoaded() then
        CreateConfig(U["bars"], T["Scan Macros For Spells"], C.bars, "macroscan", "checkbox", nil, nil, nil, nil, "vanilla")
      end
      CreateConfig(U["bars"], T["Show Reagent Count"], C.bars, "reagents", "checkbox")
      CreateConfig(U["bars"], T["Highlight Equipped Items"], C.bars, "showequipped", "checkbox")
      CreateConfig(U["bars"], T["Equipped Item Color"], C.bars, "eqcolor", "color")
      CreateConfig(U["bars"], T["Highlight Out Of Range Spells"], C.bars, "glowrange", "checkbox")
      CreateConfig(U["bars"], T["Out Of Range Color"], C.bars, "rangecolor", "color")
      CreateConfig(U["bars"], T["Highlight Out Of Mana Spells"], C.bars, "showoom", "checkbox")
      CreateConfig(U["bars"], T["Out Of Mana Color"], C.bars, "oomcolor", "color")
      CreateConfig(U["bars"], T["Highlight Not Usable Spells"], C.bars, "showna", "checkbox")
      CreateConfig(U["bars"], T["Not Usable Color"], C.bars, "nacolor", "color")
      CreateConfig(U["bars"], T["Lock Actionbars"], "UVAR", "LOCK_ACTIONBAR", "checkbox")
      CreateConfig(U["bars"], T["Always Allow Drag Via Shift Key"], C.bars, "shiftdrag", "checkbox")

      CreateConfig(nil, T["Font Options"], nil, nil, "header")
      CreateConfig(U["bars"], T["Font"], C.bars, "font", "dropdown", pfUI.gui.dropdowns.fonts)
      CreateConfig(U["bars"], T["Font Padding"], C.bars, "font_offset")
      CreateConfig(U["bars"], T["Macro Text Size"], C.bars, "macro_size")
      CreateConfig(U["bars"], T["Macro Text Color"], C.bars, "macro_color", "color")
      CreateConfig(U["bars"], T["Item Count Text Size"], C.bars, "count_size")
      CreateConfig(U["bars"], T["Item Count Text Color"], C.bars, "count_color", "color")
      CreateConfig(U["bars"], T["Keybind Text Size"], C.bars, "bind_size")
      CreateConfig(U["bars"], T["Keybind Text Color"], C.bars, "bind_color", "color")
      CreateConfig(nil, T["Cooldown Text Size"], C.bars, "cd_size")

      CreateConfig(nil, T["Auto Paging"], nil, nil, "header")
      CreateConfig(U["bars"], T["Switch Pages On Alt Key Press"], C.bars, "pagemasteralt", "checkbox")
      CreateConfig(U["bars"], T["Switch Pages On Shift Key Press"], C.bars, "pagemastershift", "checkbox")
      CreateConfig(U["bars"], T["Switch Pages On Ctrl Key Press"], C.bars, "pagemasterctrl", "checkbox")
      CreateConfig(U["bars"], T["Switch Pages On Druid Stealth"], C.bars, "druidstealth", "checkbox")
      CreateConfig(nil, T["Range Based Hunter Paging"], C.bars, "hunterbar", "checkbox", nil, nil, nil, nil, "vanilla")
    end)

    CreateGUIEntry(T["Actionbar"], T["Action Monitor"], function()
      CreateConfig(U["bars"], T["Enable Action Monitor"], C.bars, "monitorenable", "checkbox")
      CreateConfig(U["bars"], T["Lock Action Monitor"], C.bars, "monitorlock", "checkbox")
      CreateConfig(U["bars"], T["Monitored Slots"], C.bars, "monitorlist")
      CreateConfig(nil, T["Share This List"], nil, nil, "button", function()
        if not pfUI.bars or not pfUI.bars.ImportMonShare then return end
        pfUI.api.CreateShareListDialog("pfMonShare", T["Action Monitor"] .. " · " .. T["Share List"],
          function() return pfUI.bars:ExportMonShare() end,
          function(str) return pfUI.bars:ImportMonShare(str) end)
      end)
      CreateConfig(nil, T["Monitor Appearance"], nil, nil, "header")
      CreateConfig(U["bars"], T["Monitor Icon Size"], C.bars, "monitorsize")
      CreateConfig(U["bars"], T["Monitor Icons Per Row"], C.bars, "monitorrowsize")
      CreateConfig(U["bars"], T["Spacing"], C.bars, "monitorspacing")
      CreateConfig(U["bars"], T["Monitor Background"], C.bars, "monitorbackdrop", "checkbox")
      CreateConfig(U["bars"], T["Monitor Show Count"], C.bars, "monitorcount", "checkbox")
      CreateConfig(U["bars"], T["Monitor Show Macro Name"], C.bars, "monitorshowmacro", "checkbox")
      CreateConfig(U["bars"], T["Monitor Show Keybind"], C.bars, "monitorshowkeybind", "checkbox")
      CreateConfig(U["bars"], T["Monitor Border"], C.bars, "monitorborder", "checkbox")
      CreateConfig(U["bars"], T["Monitor Glow"], C.bars, "monitorglow", "checkbox")
      CreateConfig(nil, T["Monitor Visibility"], nil, nil, "header")
      CreateConfig(U["bars"], T["Hide Action Monitor"], C.bars, "monitorhide", "checkbox")
      CreateConfig(U["bars"], T["Monitor Autohide"], C.bars, "monitorautohide", "checkbox")
      CreateConfig(U["bars"], T["Monitor Autohide Time"], C.bars, "monitorhidetime")
      CreateConfig(U["bars"], T["Monitor Keep In Combat"], C.bars, "monitorcombat", "checkbox")
      CreateConfig(nil, T["Action Monitor Usage"], nil, nil, "header")
    end)

    CreateGUIEntry(T["Actionbar"], T["Gryphons"], function()
      CreateConfig(U["gryphons"], T["Texture"], C.bars.gryphons, "texture", "dropdown", pfUI.gui.dropdowns.gryphons)
      CreateConfig(U["gryphons"], T["Color"], C.bars.gryphons, "color", "color")
      CreateConfig(U["gryphons"], T["Left Anchor"], C.bars.gryphons, "anchor_left", "dropdown", pfUI.gui.dropdowns.xpanchors)
      CreateConfig(U["gryphons"], T["Right Anchor"], C.bars.gryphons, "anchor_right", "dropdown", pfUI.gui.dropdowns.xpanchors)
      CreateConfig(U["gryphons"], T["Size"], C.bars.gryphons, "size")
      CreateConfig(U["gryphons"], T["Horizontal Offset"], C.bars.gryphons, "offset_h")
      CreateConfig(U["gryphons"], T["Vertical Offset"], C.bars.gryphons, "offset_v")
    end)

    -- Shared Actionbar Settings
    local barnames = {
      -- default
      {1, T["Main Actionbar"]},
      {6, T["Top Actionbar"]},
      {5, T["Left Actionbar"]},
      {3, T["Right Actionbar"]},
      {4, T["Vertical Actionbar"]},

      -- special
      {2, T["Paging Actionbar"]},
      {7, T["Stance Bar 1"]},
      {8, T["Stance Bar 2"]},
      {9, T["Stance Bar 3"]},
      {10, T["Stance Bar 4"]},

      -- class
      {11, T["Shapeshift Bar"]},
      {12, T["Pet Actionbar"]},
    }

    for _, data in pairs(barnames) do
      local id, caption = data[1], data[2]
      local formfactors = function()
        return BarLayoutOptions(tonumber(C.bars["bar"..id].buttons) or id < 11 and NUM_ACTIONBAR_BUTTONS or id > 11 and NUM_SHAPESHIFT_SLOTS or NUM_PET_ACTION_SLOTS)
      end
      local uneven_options = function()
        local formfactor = tostring(C.bars["bar"..id].formfactor or "")
        local _, _, cols, rows = string.find(formfactor, "(%d+)%s*x%s*(%d+)")
        cols, rows = tonumber(cols), tonumber(rows)

        if cols == 3 and rows == 3 then
          return { T["Up"], T["Down"], T["Left"], T["Right"] }
        elseif cols and cols <= 3 then
          return { T["Up"], T["Down"] }
        elseif rows and rows <= 3 then
          return { T["Left"], T["Right"] }
        end

        return { T["Up"], T["Down"], T["Left"], T["Right"] }
      end		 
      CreateGUIEntry(T["Actionbar"], caption, function()
        CreateConfig(U["bars"], T["Enable"], C.bars["bar"..id], "enable", "checkbox")

        if id ~= 11 and id ~= 12 then
          CreateConfig(U["bars"], T["Buttons"], C.bars["bar"..id], "buttons", "dropdown", pfUI.gui.dropdowns.actionbarbuttons)
          if id ~= 1 then
            CreateConfig(U["bars"], T["Pageable"], C.bars["bar"..id], "pageable", "checkbox")
          end
        end

        if id == 12 then
          CreateConfig(U["bars"], T["Auto-Castable Action Indicator"], C.bars, "showcastable", "checkbox")
        end

        CreateConfig(U["bars"], T["Icon Size"], C.bars["bar"..id], "icon_size")
        CreateConfig(U["bars"], T["Spacing"], C.bars["bar"..id], "spacing", "dropdown", pfUI.gui.dropdowns.actionbarbuttons)
        local uneven_frame = nil
        local layout_ufunc = function()
          local formfactor = tostring(C.bars["bar"..id].formfactor or "")
          local _, _, cols, rows = string.find(formfactor, "(%d+)%s*x%s*(%d+)")
          cols, rows = tonumber(cols), tonumber(rows)
          local is_square = cols == 3 and rows == 3
          local is_vertical = cols and cols <= 3 and not is_square
          local is_horizontal = rows and rows <= 3 and not is_square
          local uneven = C.bars["bar"..id].uneven
          if is_vertical then
            if uneven ~= "Up" and uneven ~= "Down" then C.bars["bar"..id].uneven = "Down" end
          elseif is_horizontal then
            if uneven ~= "Left" and uneven ~= "Right" then C.bars["bar"..id].uneven = "Left" end
          end
          if uneven_frame and uneven_frame.input and uneven_frame.input.UpdateMenu then
            uneven_frame.input:UpdateMenu()
          end
          if U["bars"] then U["bars"]() end
        end
        CreateConfig(layout_ufunc, T["Layout"], C.bars["bar"..id], "formfactor", "dropdown", formfactors)
        uneven_frame = CreateConfig(U["bars"], T["Layout Uneven Orientation"], C.bars["bar"..id], "uneven", "dropdown", uneven_options)
        CreateConfig(U["bars"], T["Fill Order"], C.bars["bar"..id], "fillmode", "dropdown", function()
            return {
               "auto:" .. T["Auto"],
               "row:" .. T["Row-first (1,2,3 / 4,5,6)"],
               "col:" .. T["Column-first (1,3,5 / 2,4,6)"]
             }
        end)
        CreateConfig(U["bars"], T["Bar Background"], C.bars["bar"..id], "background", "checkbox")
        CreateConfig(U["bars"], T["Show Hotkey Text"], C.bars["bar"..id], "showkeybind", "checkbox")

        if id ~= 11 and id ~= 12 then
          CreateConfig(U["bars"], T["Show Macro Text"], C.bars["bar"..id], "showmacro", "checkbox")
          CreateConfig(U["bars"], T["Show Item Count Text"], C.bars["bar"..id], "showcount", "checkbox")
        end

        if id ~= 11 then
          CreateConfig(U["bars"], T["Show Empty Buttons"], C.bars["bar"..id], "showempty", "checkbox")
        end

        CreateConfig(U["bars"], T["Enable Autohide"], C.bars["bar"..id], "autohide", "checkbox")
        CreateConfig(U["bars"], T["Autohide Timeout"], C.bars["bar"..id], "hide_time")
        CreateConfig(U["bars"], T["Show In Combat"], C.bars["bar"..id], "hide_combat", "checkbox")
      end)
    end

    CreateGUIEntry(T["Panel"], nil, function()
      CreateConfig(nil, T["Use Unit Fonts"], C.panel, "use_unitfonts", "checkbox")
      CreateConfig(nil, T["Left Panel: Left"], C.panel.left, "left", "dropdown", pfUI.gui.dropdowns.panel_values)
      CreateConfig(nil, T["Left Panel: Center"], C.panel.left, "center", "dropdown", pfUI.gui.dropdowns.panel_values)
      CreateConfig(nil, T["Left Panel: Right"], C.panel.left, "right", "dropdown", pfUI.gui.dropdowns.panel_values)
      CreateConfig(nil, T["Right Panel: Left"], C.panel.right, "left", "dropdown", pfUI.gui.dropdowns.panel_values)
      CreateConfig(nil, T["Right Panel: Center"], C.panel.right, "center", "dropdown", pfUI.gui.dropdowns.panel_values)
      CreateConfig(nil, T["Right Panel: Right"], C.panel.right, "right", "dropdown", pfUI.gui.dropdowns.panel_values)
      CreateConfig(nil, T["Other Panel: Minimap"], C.panel.other, "minimap", "dropdown", pfUI.gui.dropdowns.panel_values)
      CreateConfig(nil, T["Only Count Bagspace On Regular Bags"], C.panel.bag, "ignorespecial", "checkbox")
      CreateConfig(nil, T["Enable Micro Bar"], C.panel.micro, "enable", "checkbox")
      CreateConfig(nil, T["Enable 24h Clock"], C.global, "twentyfour", "checkbox")
      CreateConfig(nil, T["Enable Seconds"], C.panel, "seconds", "checkbox")
      CreateConfig(nil, T["Servertime"], C.global, "servertime", "checkbox")
      CreateConfig(U["panel"], T["Show FPS and Latency Colors"], C.panel, "fpscolors", "checkbox")

      CreateConfig(nil, T["Auto Hide"], nil, nil, "header")
      CreateConfig(nil, T["Enable Autohide For Left Chat Panel"], C.panel, "hide_leftchat", "checkbox")
      CreateConfig(nil, T["Enable Autohide For Right Chat Panel"], C.panel, "hide_rightchat", "checkbox")
      CreateConfig(nil, T["Enable Autohide For Minimap Panel"], C.panel, "hide_minimap", "checkbox")
      CreateConfig(nil, T["Enable Autohide For Microbar Panel"], C.panel, "hide_microbar", "checkbox")
    end)

    CreateGUIEntry(T["XP Bar"], T["Experience Bar"], function()
      CreateConfig(U["xpbar"], T["Always Show"], C.panel.xp, "xp_always", "checkbox")
      CreateConfig(U["xpbar"], T["Display Mode"], C.panel.xp, "xp_display", "dropdown", pfUI.gui.dropdowns.xp_display)
      CreateConfig(U["xpbar"], T["Hide Timeout"], C.panel.xp, "xp_timeout")
      CreateConfig(U["xpbar"], T["Width"], C.panel.xp, "xp_width")
      CreateConfig(U["xpbar"], T["Height"], C.panel.xp, "xp_height")
      CreateConfig(U["xpbar"], T["Orientation"], C.panel.xp, "xp_mode", "dropdown", pfUI.gui.dropdowns.orientation)
      CreateConfig(U["xpbar"], T["Frame Anchor"], C.panel.xp, "xp_anchor", "dropdown", pfUI.gui.dropdowns.xpanchors)
      CreateConfig(U["xpbar"], T["Aligned Position"], C.panel.xp, "xp_position", "dropdown", pfUI.gui.dropdowns.xp_position)
      CreateConfig(U["xpbar"], T["Don't overlap rested"], C.panel.xp, "dont_overlap", "checkbox")

      CreateConfig(nil, T["Text"], nil, nil, "header")
      CreateConfig(U["xpbar"], T["Show Text"], C.panel.xp, "xp_text", "checkbox")
      CreateConfig(U["xpbar"], T["Vertical Text Offset"], C.panel.xp, "xp_text_off_y")
      CreateConfig(U["xpbar"], T["Only Show On Mouse Over"], C.panel.xp, "xp_text_mouse", "checkbox")

      CreateConfig(nil, T["Colors"], nil, nil, "header")
      CreateConfig(U["xpbar"], T["Experience Color"], C.panel.xp, "xp_color", "color")
      CreateConfig(U["xpbar"], T["Rested Color"], C.panel.xp, "rest_color", "color")
      CreateConfig(U["xpbar"], T["Bar Texture"], C.panel.xp, "texture", "dropdown", pfUI.gui.dropdowns.uf_bartexture)
    end)

    CreateGUIEntry(T["XP Bar"], T["Reputation Bar"], function()
      CreateConfig(U["xpbar"], T["Always Show"], C.panel.xp, "rep_always", "checkbox")
      CreateConfig(U["xpbar"], T["Display Mode"], C.panel.xp, "rep_display", "dropdown", pfUI.gui.dropdowns.xp_display)
      CreateConfig(U["xpbar"], T["Hide Timeout"], C.panel.xp, "rep_timeout")
      CreateConfig(U["xpbar"], T["Width"], C.panel.xp, "rep_width")
      CreateConfig(U["xpbar"], T["Height"], C.panel.xp, "rep_height")
      CreateConfig(U["xpbar"], T["Orientation"], C.panel.xp, "rep_mode", "dropdown", pfUI.gui.dropdowns.orientation)
      CreateConfig(U["xpbar"], T["Frame Anchor"], C.panel.xp, "rep_anchor", "dropdown", pfUI.gui.dropdowns.xpanchors)
      CreateConfig(U["xpbar"], T["Aligned Position"], C.panel.xp, "rep_position", "dropdown", pfUI.gui.dropdowns.xp_position)

      CreateConfig(nil, T["Text"], nil, nil, "header")
      CreateConfig(U["xpbar"], T["Show Text"], C.panel.xp, "rep_text", "checkbox")
      CreateConfig(U["xpbar"], T["Vertical Text Offset"], C.panel.xp, "rep_text_off_y")
      CreateConfig(U["xpbar"], T["Only Show On Mouse Over"], C.panel.xp, "rep_text_mouse", "checkbox")
    end)

    CreateGUIEntry(T["Tooltip"], nil, function()
      CreateConfig(nil, T["Tooltip Position"], C.tooltip, "position", "dropdown", pfUI.gui.dropdowns.tooltip_position)
      CreateConfig(nil, T["Tooltip Text Font"], C.tooltip, "font_tooltip", "dropdown", pfUI.gui.dropdowns.fonts)
      CreateConfig(nil, T["Tooltip Text Font Size"], C.tooltip, "font_tooltip_size")
      CreateConfig(nil, T["Cursor Tooltip Align"], C.tooltip, "cursoralign", "dropdown", pfUI.gui.dropdowns.tooltip_align)
      CreateConfig(nil, T["Cursor Tooltip Offset"], C.tooltip, "cursoroffset")
      CreateConfig(nil, T["Enable Extended Guild Information"], C.tooltip, "extguild", "checkbox")
      CreateConfig(nil, T["Always Show Health In Percent"], C.tooltip, "alwaysperc", "checkbox")
      CreateConfig(nil, T["Always Show Mana In Percent"], C.tooltip, "manaperc", "checkbox")
      CreateConfig(nil, T["Show Power Bar"], C.tooltip, "manabar", "checkbox")
      CreateConfig(nil, T["Status Bar Height"], C.tooltip, "barheight")
      CreateConfig(nil, T["Status Bar Position"], C.tooltip, "barpos", "dropdown", {
          "TOP:" .. T["Top"],
          "BOTTOM:" .. T["Bottom"]
      })
      CreateConfig(nil, T["Status Bar Text Size"], C.tooltip, "bar_font_size")
      CreateConfig(nil, T["Status Bar Text Offset Y"], C.tooltip, "bar_text_offy")
      CreateConfig(nil, T["Show Item IDs"], C.tooltip, "itemid", "checkbox")
      CreateConfig(nil, T["Custom Transparency"], C.tooltip, "alpha")
      CreateConfig(nil, T["Status Bar Texture"], C.tooltip.statusbar, "texture", "dropdown", pfUI.gui.dropdowns.uf_bartexture)
      CreateConfig(nil, T["Compare Item Base Stats"], C.tooltip.compare, "basestats", "checkbox")
      CreateConfig(nil, T["Always Show Item Comparison"], C.tooltip.compare, "showalways", "checkbox")
      CreateConfig(nil, T["Always Show Extended Vendor Values"], C.tooltip.vendor, "showalways", "checkbox")
      CreateConfig(U["questitem"], T["Show Related Quest On Questitems"], C.tooltip.questitem, "showquest", "checkbox")
      CreateConfig(U["questitem"], T["Show Required Questitem Count"], C.tooltip.questitem, "showcount", "checkbox")
      -- 3D 模型设置
      CreateConfig(nil, T["3D Model"], nil, nil, "header")
      CreateConfig(nil, T["Show 3D Model"], C.tooltip, "show3dmodel", "checkbox")
      CreateConfig(nil, T["Model Size"], C.tooltip, "modelsize")
      CreateConfig(nil, T["Model Position"], C.tooltip, "modelposition", "dropdown", {
          "LEFT:" .. T["Left"],
          "RIGHT:" .. T["Right"],
          "TOP:" .. T["Top"],
          "BOTTOM:" .. T["Bottom"]
      })
      CreateConfig(nil, T["Model Offset X"], C.tooltip, "modeloffsetx")
      CreateConfig(nil, T["Model Offset Y"], C.tooltip, "modeloffsety")
      CreateConfig(nil, T["Enable Mouse Rotation"], C.tooltip, "modelrotation", "checkbox")
      CreateConfig(nil, T["Auto Adjust Edge"], C.tooltip, "modeledge", "checkbox")
    end)

    CreateGUIEntry(T["Castbar"], nil, function()
      CreateConfig(nil, T["Use Unit Fonts"], C.castbar, "use_unitfonts", "checkbox")
      CreateConfig(nil, T["Casting Color"], C.appearance.castbar, "castbarcolor", "color")
      CreateConfig(nil, T["Channeling Color"], C.appearance.castbar, "channelcolor", "color")
      CreateConfig(nil, T["Castbar Texture"], C.appearance.castbar, "texture", "dropdown", pfUI.gui.dropdowns.uf_bartexture)
      CreateConfig(nil, T["Disable Blizzard Castbar"], C.castbar.player, "hide_blizz", "checkbox")

      CreateConfig(nil, T["Player Castbar"], nil, nil, "header")
      CreateConfig(nil, T["Disable Player Castbar"], C.castbar.player, "hide_pfui", "checkbox")
      CreateConfig(nil, T["Castbar Width"], C.castbar.player, "width")
      CreateConfig(nil, T["Castbar Height"], C.castbar.player, "height")
      CreateConfig(nil, T["Show Spell Icon"], C.castbar.player, "showicon", "checkbox")
      CreateConfig(nil, T["Show Spell Name"], C.castbar.player, "showname", "checkbox")
      CreateConfig(nil, T["Show Timer"], C.castbar.player, "showtimer", "checkbox")
      CreateConfig(nil, T["Left Text X Offset"], C.castbar.player, "txtleftoffx")
      CreateConfig(nil, T["Left Text Y Offset"], C.castbar.player, "txtleftoffy")
      CreateConfig(nil, T["Show Lag"], C.castbar.player, "showlag", "checkbox")
      CreateConfig(nil, T["Show Rank"], C.castbar.player, "showrank", "checkbox")
      CreateConfig(nil, T["Right Text X Offset"], C.castbar.player, "txtrightoffx")
      CreateConfig(nil, T["Right Text Y Offset"], C.castbar.player, "txtrightoffy")

      CreateConfig(nil, T["Target Castbar"], nil, nil, "header")
      CreateConfig(nil, T["Disable Target Castbar"], C.castbar.target, "hide_pfui", "checkbox")
      CreateConfig(nil, T["Castbar Width"], C.castbar.target, "width")
      CreateConfig(nil, T["Castbar Height"], C.castbar.target, "height")
      CreateConfig(nil, T["Show Spell Icon"], C.castbar.target, "showicon", "checkbox")
      CreateConfig(nil, T["Show Spell Name"], C.castbar.target, "showname", "checkbox")
      CreateConfig(nil, T["Show Timer"], C.castbar.target, "showtimer", "checkbox")
      CreateConfig(nil, T["Left Text X Offset"], C.castbar.target, "txtleftoffx")
      CreateConfig(nil, T["Left Text Y Offset"], C.castbar.target, "txtleftoffy")
      CreateConfig(nil, T["Show Lag"], C.castbar.target, "showlag", "checkbox")
      CreateConfig(nil, T["Show Rank"], C.castbar.target, "showrank", "checkbox")
      CreateConfig(nil, T["Right Text X Offset"], C.castbar.target, "txtrightoffx")
      CreateConfig(nil, T["Right Text Y Offset"], C.castbar.target, "txtrightoffy")

      CreateConfig(nil, T["Focus Castbar"], nil, nil, "header")
      CreateConfig(nil, T["Disable Focus Castbar"], C.castbar.focus, "hide_pfui", "checkbox")
      CreateConfig(nil, T["Castbar Width"], C.castbar.focus, "width")
      CreateConfig(nil, T["Castbar Height"], C.castbar.focus, "height")
      CreateConfig(nil, T["Show Spell Icon"], C.castbar.focus, "showicon", "checkbox")
      CreateConfig(nil, T["Show Spell Name"], C.castbar.focus, "showname", "checkbox")
      CreateConfig(nil, T["Show Timer"], C.castbar.focus, "showtimer", "checkbox")
      CreateConfig(nil, T["Left Text X Offset"], C.castbar.focus, "txtleftoffx")
      CreateConfig(nil, T["Left Text Y Offset"], C.castbar.focus, "txtleftoffy")
      CreateConfig(nil, T["Show Lag"], C.castbar.focus, "showlag", "checkbox")
      CreateConfig(nil, T["Show Rank"], C.castbar.focus, "showrank", "checkbox")
      CreateConfig(nil, T["Right Text X Offset"], C.castbar.focus, "txtrightoffx")
      CreateConfig(nil, T["Right Text Y Offset"], C.castbar.focus, "txtrightoffy")
    end)

    CreateGUIEntry(T["Chat"], nil, function()
      CreateConfig(nil, T["Enable Chat Repeat Filter"], C.chat.global, "repeatfilter", "checkbox")
      CreateConfig(nil, T["Chat Repeat Filter Interval"], C.chat.global, "repeatfilterinterval")
      CreateConfig(nil, T["Chat Repeat Filter Excluded Channels"], C.chat.global, "repeatfilterexclude", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Enable \"Loot & Spam\" Chat Window"], C.chat.right, "enable", "checkbox")
      CreateConfig(nil, T["Inputbox Width"], C.chat.text, "input_width")
      CreateConfig(nil, T["Inputbox Height"], C.chat.text, "input_height")
      CreateConfig(nil, T["Enable Text Shadow"], C.chat.text, "outline", "checkbox")
      CreateConfig(nil, T["Enable Chat History"], C.chat.text, "history", "checkbox")
      CreateConfig(nil, T["Show Items On Mouseover"], C.chat.text, "mouseover", "checkbox")
      CreateConfig(nil, T["Chat Default Brackets"], C.chat.text, "bracket", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Enable Timestamps"], C.chat.text, "time", "checkbox")
      CreateConfig(nil, T["Timestamp Format"], C.chat.text, "timeformat", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Timestamp Brackets"], C.chat.text, "timebracket", nil, nil, nil, nil, "STRING")
      CreateConfig(nil, T["Timestamp Color"], C.chat.text, "timecolor", "color")
      CreateConfig(nil, T["Hide Channel Names"], C.chat.text, "channelnumonly", "checkbox")
      CreateConfig(nil, T["Generate Playerlinks"], C.chat.text, "playerlinks", "checkbox")
      CreateConfig(nil, T["Enable URL Detection"], C.chat.text, "detecturl", "checkbox")
      CreateConfig(nil, T["Enable Class Colors"], C.chat.text, "classcolor", "checkbox")
      CreateConfig(nil, T["Enable Player Levels"], C.chat.text, "playerlevel", "checkbox")
      CreateConfig(nil, T["Enable Player Race"], C.chat.text, "playerrace", "checkbox")
      CreateConfig(nil, T["Who Search Unknown Classes (|cffffaaaaExperimental|r)"], C.chat.text, "whosearchunknown", "checkbox")
      CreateConfig(nil, T["Colorize Unknown Classes"], C.chat.text, "tintunknown", "checkbox")
      CreateConfig(nil, T["Unknown Class Color"], C.chat.text, "unknowncolor", "color")
      CreateConfig(nil, T["Left Chat Width"], C.chat.left, "width")
      CreateConfig(nil, T["Left Chat Height"], C.chat.left, "height")
      CreateConfig(nil, T["Right Chat Width"], C.chat.right, "width")
      CreateConfig(nil, T["Right Chat Height"], C.chat.right, "height")
      CreateConfig(nil, T["Hide Combat Log"], C.chat.global, "combathide", "checkbox")
      CreateConfig(nil, T["Enable Chat Dock Background"], C.chat.global, "tabdock", "checkbox")
      CreateConfig(nil, T["Only Show Chat Dock On Mouseover"], C.chat.global, "tabmouse", "checkbox")
      CreateConfig(nil, T["Enable Chat Tab Flashing"], C.chat.global, "chatflash", "checkbox")
      CreateConfig(nil, T["Enable Frame Shadow"], C.chat.global, "frameshadow", "checkbox")
      CreateConfig(nil, T["Enable Custom Colors"], C.chat.global, "custombg", "checkbox")
      CreateConfig(nil, T["Chat Background Color"], C.chat.global, "background", "color")
      CreateConfig(nil, T["Chat Border Color"], C.chat.global, "border", "color")
      CreateConfig(nil, T["Enable Custom Incoming Whispers Layout"], C.chat.global, "whispermod", "checkbox")
      CreateConfig(nil, T["Incoming Whispers Color"], C.chat.global, "whisper", "color")
      CreateConfig(nil, T["Enable Sticky Chat"], C.chat.global, "sticky", "checkbox")
      CreateConfig(nil, T["Non-Sticky Whisper"], C.chat.global, "whispernonsticky", "checkbox")
      CreateConfig(nil, T["Maximum Number Of Chat Lines"], C.chat.global, "maxlines")
      CreateConfig(nil, T["Enable Chat Fade"], C.chat.global, "fadeout", "checkbox")
      CreateConfig(nil, T["Seconds Before Chat Fade"], C.chat.global, "fadetime")
      CreateConfig(nil, T["Mousewheel Scroll Speed"], C.chat.global, "scrollspeed")
      CreateConfig(nil, T["Enable Chat Bubbles"], "CVAR", "chatBubbles", "checkbox")
      CreateConfig(nil, T["Enable Party Chat Bubbles"], "CVAR", "chatBubblesParty", "checkbox")
      CreateConfig(nil, T["Enable Chat Bubble Borders"], C.chat.bubbles, "borders", "checkbox")
      CreateConfig(nil, T["Chat Bubble Transparency"], C.chat.bubbles, "alpha")
    end)

    CreateGUIEntry(T["Nameplates"], nil, function()
      CreateConfig(U["nameplates"], T["Show On Hostile Units"], C.nameplates, "showhostile", "checkbox")
      CreateConfig(U["nameplates"], T["Show On Friendly Units"], C.nameplates, "showfriendly", "checkbox")
      CreateConfig(U["nameplates"], T["Disable Hostile Nameplates In Friendly Zones"], C.nameplates, "disable_hostile_in_friendly", "checkbox")
      CreateConfig(U["nameplates"], T["Disable Friendly Nameplates In Friendly Zones"], C.nameplates, "disable_friendly_in_friendly", "checkbox")
      CreateConfig(U["nameplates"], T["Vertical Offset (|cffffaaaaExperimental|r)"], C.nameplates, "vertical_offset", nil, nil, nil, nil, nil, "vanilla")
      CreateConfig(U["nameplates"], T["Inactive Nameplate Alpha"], C.nameplates, "notargalpha", "dropdown", pfUI.gui.dropdowns.percent_small)
      CreateConfig(U["nameplates"], T["Draw Glow Around Target Nameplate"], C.nameplates, "targetglow", "checkbox")
      CreateConfig(U["nameplates"], T["Glow Color Around Target Nameplate"], C.nameplates, "glowcolor", "color")
      CreateConfig(U["nameplates"], T["Red Name Text On Infight Units"], C.nameplates, "namefightcolor", "checkbox")
      CreateConfig(U["nameplates"], T["Zoom Target Nameplate"], C.nameplates, "targetzoom", "checkbox")
      CreateConfig(U["nameplates"], T["Target Nameplate Zoom Factor"], C.nameplates, "targetzoomval", "dropdown", pfUI.gui.dropdowns.percent_small)
      CreateConfig(U["nameplates"], T["Nameplate Width"], C.nameplates, "width")
      CreateConfig(U["nameplates"], T["Enable Class Colors On Enemies"], C.nameplates, "enemyclassc", "checkbox")
      CreateConfig(U["nameplates"], T["Enable Class Colors On Friends"], C.nameplates, "friendclassc", "checkbox")
      CreateConfig(U["nameplates"], T["Enable Class Colors On Friends Name"], C.nameplates, "friendclassnamec", "checkbox")
      CreateConfig(U["nameplates"], T["Enable Combo Point Display"], C.nameplates, "cpdisplay", "checkbox")
      CreateConfig(U["nameplates"], T["Enable Clickthrough"], C.nameplates, "clickthrough", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(U["nameplates"], T["Enable Overlap"], C.nameplates, "overlap", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(U["nameplates"], T["Enable Mouselook With Right Click"], C.nameplates, "rightclick", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(U["nameplates"], T["Right Click Auto Attack Threshold"], C.nameplates, "clickthreshold", nil, nil, nil, nil, nil, "vanilla")
      CreateConfig(U["nameplates"], T["Use Unit Fonts"], C.nameplates, "use_unitfonts", "checkbox")
      CreateConfig(U["nameplates"], T["Font Style"], C.nameplates.name, "fontstyle", "dropdown", pfUI.gui.dropdowns.fontstyle)
      CreateConfig(U["nameplates"], T["Replace Totems With Icons"], C.nameplates, "totemicons", "checkbox")
      CreateConfig(U["nameplates"], T["Show Guild Name"], C.nameplates, "showguildname", "checkbox")
      CreateConfig(U["nameplates"], T["Show Target Name"], C.nameplates, "showtargetname", "checkbox")
      CreateConfig(U["nameplates"], T["Show Hatred Percentage"], C.nameplates, "showhatred", "checkbox")
      CreateConfig(U["nameplates"], T["questicon"], C.nameplates, "questicon", "checkbox")

      CreateConfig(nil, T["Fixed Position Target Plate"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Show Fixed Position Target Plate"], C.nameplates, "fixedposition", "checkbox")
      CreateConfig(U["nameplates"], T["Only For Enemy Targets"], C.nameplates, "fixedposition_enemyonly", "checkbox")
      CreateConfig(U["nameplates"], T["Fixed Plate Anchor"], C.nameplates, "fixedposition_anchor", "dropdown", pfUI.gui.dropdowns.positions)
      CreateConfig(U["nameplates"], T["Unlock Fixed Plate (Movable)"], C.nameplates, "fixedposition_unlock", "checkbox")
      CreateConfig(U["nameplates"], T["Fixed Plate Width"], C.nameplates, "fixedposition_width")
      CreateConfig(U["nameplates"], T["Fixed Plate Height"], C.nameplates, "fixedposition_height")
      CreateConfig(U["nameplates"], T["Reset Fixed Plate Position"], nil, nil, "button", function()
        if pfUI.nameplates and pfUI.nameplates.ResetFixedPlatePosition then
          pfUI.nameplates.ResetFixedPlatePosition()
        end
      end)

      CreateConfig(nil, T["Raid Icon"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Raid Icon Position"], C.nameplates, "raidiconpos", "dropdown", pfUI.gui.dropdowns.positions)
      CreateConfig(U["nameplates"], T["Raid Icon X-Offset"], C.nameplates, "raidiconoffx")
      CreateConfig(U["nameplates"], T["Raid Icon Y-Offset"], C.nameplates, "raidiconoffy")
      CreateConfig(U["nameplates"], T["Raid Icon Size"], C.nameplates, "raidiconsize")

      CreateConfig(nil, T["Castbar"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Enable Castbars"], C.nameplates, "showcastbar", "checkbox")
      CreateConfig(U["nameplates"], T["Only Show Target Castbar"], C.nameplates, "targetcastbar", "checkbox")
      CreateConfig(U["nameplates"], T["Enable Spellname"], C.nameplates, "spellname", "checkbox")
      CreateConfig(U["nameplates"], T["Castbar Height"], C.nameplates, "heightcast")

      CreateConfig(nil, T["Debuffs"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Enable Debuffs"], C.nameplates, "showdebuffs", "checkbox")
      CreateConfig(U["nameplates"], T["Show Debuffs on Hostile"], C.nameplates, "showdebuffs_hostile", "checkbox")
      CreateConfig(U["nameplates"], T["Show Debuffs on Friendly"], C.nameplates, "showdebuffs_friendly", "checkbox")																					
      CreateConfig(U["nameplates"], T["Show Debuffs on Target Only"], C.nameplates, "showdebuffs_targetonly", "checkbox")								
      CreateConfig(U["nameplates"], T["Debuff Position"], C.nameplates.debuffs, "position", "dropdown", pfUI.gui.dropdowns.debuffposition)
      CreateConfig(U["nameplates"], T["Debuff Icon Offset"], C.nameplates, "debuffoffset")
      CreateConfig(U["nameplates"], T["Debuff Icon Size"], C.nameplates, "debuffsize")
      CreateConfig(U["nameplates"], T["Estimate Debuffs"], C.nameplates, "guessdebuffs", "checkbox")
      CreateConfig(U["nameplates"], T["Show Debuff Stacks"], C.nameplates.debuffs, "showstacks", "checkbox")
      CreateConfig(U["nameplates"], T["Enable Debuff Timers"], C.nameplates, "debufftimers", "checkbox")
      CreateConfig(U["nameplates"], T["Show Timer Text"], C.nameplates, "debufftext", "checkbox")
      CreateConfig(Reload, T["Show Timer Animation"], C.nameplates, "debuffanim", "checkbox")
      CreateConfig(U["nameplates"], T["Show Only Own Debuffs"], C.nameplates, "selfdebuff", "checkbox")
      CreateConfig(U["nameplates"], T["Filter Mode"], C.nameplates.debuffs, "filter", "dropdown", pfUI.gui.dropdowns.buffbarfilter)
      CreateConfig(U["nameplates"], T["Blacklist"], C.nameplates.debuffs, "blacklist", "list")
      CreateConfig(U["nameplates"], T["Whitelist"], C.nameplates.debuffs, "whitelist", "list")

      CreateConfig(nil, T["Control Skills"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Enable Control Skills"], C.nameplates, "ccenabled", "checkbox")
      CreateConfig(U["nameplates"], T["Control Skill Icon Size"], C.nameplates, "ccsize")
      CreateConfig(U["nameplates"], T["Control Skill Position"], C.nameplates, "ccposition", "dropdown", {"TOP:"..T["Top"], "BOTTOM:"..T["Bottom"]})
      CreateConfig(U["nameplates"], T["Control Skill Horizontal Offset"], C.nameplates, "ccoffx")
      CreateConfig(U["nameplates"], T["Control Skill Vertical Offset"], C.nameplates, "ccoffy")
      CreateConfig(U["nameplates"], T["Max Control Skills Shown"], C.nameplates, "ccmax")
      CreateConfig(U["nameplates"], T["Show Control Skill Timers"], C.nameplates, "cctimers", "checkbox")
      CreateConfig(U["nameplates"], T["Control Skill Filter"], C.nameplates, "ccfilter", "list")

      CreateConfig(nil, T["Outlines"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Blue Border On Friendly Players"], C.nameplates, "outfriendly", "checkbox")
      CreateConfig(U["nameplates"], T["Green Border On Friendly NPCs"], C.nameplates, "outfriendlynpc", "checkbox")
      CreateConfig(U["nameplates"], T["Yellow Border On Neutral Units"], C.nameplates, "outneutral", "checkbox")
      CreateConfig(U["nameplates"], T["Red Border On Enemy Units"], C.nameplates, "outenemy", "checkbox")
      CreateConfig(U["nameplates"], T["Border Around Target Unit"], C.nameplates, "targethighlight", "checkbox")
      CreateConfig(U["nameplates"], T["Border Color Around Target Unit"], C.nameplates, "highlightcolor", "color")

      CreateConfig(nil, T["Unit Colors"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Enemy NPC Color"], C.nameplates, "unitcolor_enemynpc", "color")
      CreateConfig(U["nameplates"], T["Enemy Player Color"], C.nameplates, "unitcolor_enemyplayer", "color")
      CreateConfig(U["nameplates"], T["Neutral NPC Color"], C.nameplates, "unitcolor_neutralnpc", "color")
      CreateConfig(U["nameplates"], T["Friendly NPC Color"], C.nameplates, "unitcolor_friendlynpc", "color")
      CreateConfig(U["nameplates"], T["Friendly Player Color"], C.nameplates, "unitcolor_friendlyplayer", "color")

      CreateConfig(nil, T["Custom NPC Colors"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Custom NPC Color"], C.nameplates, "unitcolor_customcolor", "color")
      local npccolorlist = CreateConfig(U["nameplates"], T["Custom NPC List"], C.nameplates, "unitcolor_custom", "list")
      CreateConfig(U["nameplates"], T["Add Target To Custom NPC List"], C.nameplates, "unitcolor_custom", "button", function()
        local target = UnitName("target")
        if not target or target == "" then
          DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[pfUI]|r " .. T["No target selected"])
          return
        end

        -- strsplit("=", entry) 只取名字部分（"名字=r,g,b,a" 与纯 "名字" 均适用）
        local cur = C.nameplates.unitcolor_custom or ""
        local lower = strlower(target)
        for _, entry in pairs({strsplit("#", cur)}) do
          local npcname = strsplit("=", entry)
          if npcname and strlower(npcname) == lower then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[pfUI]|r " .. target .. " " .. T["Already In List"])
            return
          end
        end

        C.nameplates.unitcolor_custom = cur .. "#" .. target
        if U["nameplates"] then U["nameplates"]() end
        if npccolorlist and npccolorlist.input then npccolorlist.input:UpdateMenu() end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[pfUI]|r " .. T["Added"] .. ": " .. target)
      end)

      CreateConfig(nil, T["Blacklist"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Hide Blacklisted Units"], C.nameplates, "hideblacklist", "checkbox")
      CreateConfig(U["nameplates"], T["Blacklist"], C.nameplates, "blacklist", "list")

      CreateConfig(nil, T["Healthbar"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Healthbar Vertical Offset"], C.nameplates.health, "offset")
      CreateConfig(U["nameplates"], T["Healthbar Height"], C.nameplates, "heighthealth")
      CreateConfig(U["nameplates"], T["Healthbar Texture"], C.nameplates, "healthtexture", "dropdown", pfUI.gui.dropdowns.uf_bartexture)
      CreateConfig(U["nameplates"], T["Show Health Points"], C.nameplates, "showhp", "checkbox")
      CreateConfig(U["nameplates"], T["Health Text Position"], C.nameplates, "hptextpos", "dropdown", pfUI.gui.dropdowns.textalign)
      CreateConfig(U["nameplates"], T["Health Text Format"], C.nameplates, "hptextformat", "dropdown", pfUI.gui.dropdowns.hpformat)
      CreateConfig(U["nameplates"], T["Hide Healthbar On Enemy NPCs"], C.nameplates, "enemynpc", "checkbox")
      CreateConfig(U["nameplates"], T["Hide Healthbar On Enemy Players"], C.nameplates, "enemyplayer", "checkbox")
      CreateConfig(U["nameplates"], T["Hide Healthbar On Neutral NPCs"], C.nameplates, "neutralnpc", "checkbox")
      CreateConfig(U["nameplates"], T["Hide Healthbar On Friendly NPCs"], C.nameplates, "friendlynpc", "checkbox")
      CreateConfig(U["nameplates"], T["Hide Healthbar On Friendly Players"], C.nameplates, "friendlyplayer", "checkbox")
      CreateConfig(U["nameplates"], T["Hide Healthbar On Critters"], C.nameplates, "critters", "checkbox")
      CreateConfig(U["nameplates"], T["Hide Healthbar On Totems"], C.nameplates, "totems", "checkbox")
      CreateConfig(U["nameplates"], T["Always Show On Units With Missing HP"], C.nameplates, "fullhealth", "checkbox")
      CreateConfig(U["nameplates"], T["Always Show On Target Units"], C.nameplates, "target", "checkbox")
      CreateConfig(U["nameplates"], T["Vertical Healthbar"], C.nameplates, "verticalhealth", "checkbox")

      CreateConfig(nil, T["Nampower Settings"], nil, nil, "header")
      CreateConfig(U["nameplates"], T["Overwrite Border Color With Combat State"], C.nameplates, "outcombatstate", "checkbox")
      CreateConfig(U["nameplates"], T["Overwrite Health Color With Combat State"], C.nameplates, "barcombatstate", "checkbox")
      CreateConfig(U["nameplates"], T["Overwrite If Unit Is Attacking You"], C.nameplates, "ccombatthreat", "checkbox")
      CreateConfig(U["nameplates"], T["Overwrite If Unit Is Attacking Off-Tank"], C.nameplates, "ccombatofftank", "checkbox")
      CreateConfig(U["nameplates"], T["Overwrite If Unit Is Attacking Others"], C.nameplates, "ccombatnothreat", "checkbox")
      CreateConfig(U["nameplates"], T["Overwrite If Unit Is Attacking No One"], C.nameplates, "ccombatstun", "checkbox")
      CreateConfig(U["nameplates"], T["Overwrite If Unit Is Casting"], C.nameplates, "ccombatcasting", "checkbox")
      CreateConfig(U["nameplates"], T["Unit Is Attacking You Color"], C.nameplates, "combatthreat", "color")
      CreateConfig(U["nameplates"], T["Unit Is Attacking Off-Tank Color"], C.nameplates, "combatofftank", "color")
      CreateConfig(U["nameplates"], T["Unit Is Attacking Others Color"], C.nameplates, "combatnothreat", "color")
      CreateConfig(U["nameplates"], T["Unit Is Attacking No One Color"], C.nameplates, "combatstun", "color")
      CreateConfig(U["nameplates"], T["Unit Is Casting Color"], C.nameplates, "combatcasting", "color")
      CreateConfig(U["nameplates"], T["Off-Tank Names"], C.nameplates, "combatofftanks", "list")
    end)

    CreateGUIEntry(T["Thirdparty"], T["Integrations"], function()
      CreateConfig(nil, T["Show Meters By Default"], C.thirdparty, "showmeter", "checkbox")
      CreateConfig(nil, T["Use Chat Colors for Meters"], C.thirdparty, "chatbg", "checkbox")
      CreateConfig(nil, "ShaguDPS (" .. T["Skin"] .. ")", C.thirdparty.shagudps, "skin", "checkbox")
      CreateConfig(nil, "ShaguDPS (" .. T["Dock"] .. ")", C.thirdparty.shagudps, "dock", "checkbox")
      CreateConfig(nil, "DPSMate (" .. T["Skin"] .. ")", C.thirdparty.dpsmate, "skin", "checkbox")
      CreateConfig(nil, "DPSMate (" .. T["Dock"] .. ")", C.thirdparty.dpsmate, "dock", "checkbox")
      CreateConfig(nil, "Recount (" .. T["Skin"] .. ")", C.thirdparty.recount, "skin", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "Recount (" .. T["Dock"] .. ")", C.thirdparty.recount, "dock", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "Omen (" .. T["Skin"] .. ")", C.thirdparty.omen, "skin", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "Omen (" .. T["Dock"] .. ")", C.thirdparty.omen, "dock", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "SWStats (" .. T["Skin"] .. ")", C.thirdparty.swstats, "skin", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "SWStats (" .. T["Dock"] .. ")", C.thirdparty.swstats, "dock", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "KLH Threat Meter (" .. T["Skin"] .. ")", C.thirdparty.ktm, "skin", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "KLH Threat Meter (" .. T["Dock"] .. ")", C.thirdparty.ktm, "dock", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "TW Threatmeter (" .. T["Skin"] .. ")", C.thirdparty.twt, "skin", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "TW Threatmeter (" .. T["Dock"] .. ")", C.thirdparty.twt, "dock", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "WIM", C.thirdparty.wim, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "HealComm", C.thirdparty.healcomm, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "SortBags", C.thirdparty.sortbags, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "Bag_Sort", C.thirdparty.bag_sort, "enable", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "MrPlow", C.thirdparty.mrplow, "enable", "checkbox")
      CreateConfig(nil, "BetterCharacterStats", C.thirdparty.bcs, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "Crafty", C.thirdparty.crafty, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "CleverMacro", C.thirdparty.clevermacro, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "SuperCleveRoidMacros", C.thirdparty.supercleveroidmacros, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "AckisRecipeList", C.thirdparty.ackis, "enable", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "SheepWatch", C.thirdparty.sheepwatch, "enable", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "TotemTimers", C.thirdparty.totemtimers, "enable", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "DruidBar", C.thirdparty.druidbar, "enable", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "BCEPGP", C.thirdparty.bcepgp, "enable", "checkbox", nil, nil, nil, nil, "tbc")
      CreateConfig(nil, "FlightMap", C.thirdparty.flightmap, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "TheoryCraft", C.thirdparty.theorycraft, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "SuperMacro", C.thirdparty.supermacro, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "AtlasLoot", C.thirdparty.atlasloot, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "MyRolePlay", C.thirdparty.myroleplay, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "DruidManaBar", C.thirdparty.druidmana, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
      CreateConfig(nil, "NoteIt", C.thirdparty.noteit, "enable", "checkbox", nil, nil, nil, nil, "vanilla")
    end)

    CreateGUIEntry(T["Components"], T["Modules"], function()
      table.sort(pfUI.modules)
      for i,m in pairs(pfUI.modules) do
        -- skip gui and macrotweak when macro addons are loaded
        if m ~= "gui" and not (m == "macrotweak" and pfUI:MacroAddonsLoaded()) then
          -- create disabled entry if not existing and display
          pfUI:UpdateConfig("disabled", nil, m, "0")
          CreateConfig(nil, T["Disable Module"] .. " " .. m, C.disabled, m, "checkbox")
        end
      end
    end)

    CreateGUIEntry(T["Components"], T["Skins"], function()
      table.sort(pfUI.skins)
      for i,m in pairs(pfUI.skins) do
        -- create disabled entry if not existing and display
        pfUI:UpdateConfig("disabled", nil, "skin_" .. m, "0")
        CreateConfig(nil, T["Disable Skin"] .. " " .. m, C.disabled, "skin_" .. m, "checkbox")
      end
    end)
    CreateGUIEntry(T["Components"], T["Skins"], function()
      table.sort(pfUI.skins)
      for i,m in pairs(pfUI.skins) do
        pfUI:UpdateConfig("disabled", nil, "skin_" .. m, "0")
        CreateConfig(nil, T["Disable Skin"] .. " " .. m, C.disabled, "skin_" .. m, "checkbox")
      end
    end)

-- 捐赠支持页面（独立菜单）
CreateGUIEntry("打赏支持", nil, function()
    local parent = this

    -- 水平偏移量，正数向右，负数向左，您可自行调整
    local xOffset = 300

    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", parent, "TOP", xOffset, -6)
    title:SetText("打赏支持")
    title:SetTextColor(1, 0.6, 0.8)

    local y = -6 - 30 - 10

    local box = CreateFrame("Frame", nil, parent)
    box:SetWidth(168); box:SetHeight(168)
    box:SetPoint("TOP", parent, "TOP", xOffset, y)
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0.05, 0.05, 0.07, 1)
    box:SetBackdropBorderColor(1, 0.6, 0.8, 0.7)

    local qr = box:CreateTexture(nil, "ARTWORK")
    qr:SetWidth(160); qr:SetHeight(160)
    qr:SetPoint("CENTER", box, "CENTER", 0, 0)
    qr:SetTexture("Interface\\AddOns\\pfUI\\img\\donate.tga")
    qr:SetTexCoord(0, 1, 0, 1)

    y = y - 168 - 16

    local DONATE_TEXT = {
        "如果 最爱插件包 帮到了您",
        "欢迎给 阿tian 加个鸡腿 ~",
        "",
        "微信扫一扫，打赏支持",
        "",
    }
    for i, text in ipairs(DONATE_TEXT) do
        local line = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        line:SetPoint("TOP", parent, "TOP", xOffset, y - (i - 1) * 18)
        line:SetText(text == "" and " " or text)
        line:SetJustifyH("CENTER")
        if string.find(text, "微信") or string.find(text, "打赏") then
            line:SetTextColor(1, 0.6, 0.8)
        else
            line:SetTextColor(0.82, 0.82, 0.86)
        end
    end
    y = y - table.getn(DONATE_TEXT) * 18 - 16

    local function MakePinkButton(parent, text, w, h)
        local b = CreateFrame("Button", nil, parent)
        b:SetWidth(w); b:SetHeight(h or 24)
        b:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        b:SetBackdropColor(0.16, 0.16, 0.22, 0.95)
        b:SetBackdropBorderColor(1, 0.6, 0.8, 0.8)

        local t = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        t:SetPoint("CENTER", b, "CENTER", 0, 1)
        t:SetText(text)
        t:SetTextColor(1, 0.6, 0.8)
        b.text = t

        local function setNormal()
            b:SetBackdropColor(0.16, 0.16, 0.22, 0.95)
            b:SetBackdropBorderColor(1, 0.6, 0.8, 0.8)
            t:SetTextColor(1, 0.6, 0.8)
        end
        local function setHover()
            b:SetBackdropColor(0.3, 0.18, 0.28, 1)
            b:SetBackdropBorderColor(1, 0.75, 0.9, 1)
            t:SetTextColor(1, 0.85, 0.95)
        end
        local function setPushed()
            b:SetBackdropColor(0.12, 0.12, 0.18, 1)
            b:SetBackdropBorderColor(1, 0.5, 0.75, 1)
            t:SetTextColor(0.95, 0.55, 0.8)
        end

        b:SetScript("OnEnter", setHover)
        b:SetScript("OnLeave", setNormal)
        b:SetScript("OnMouseDown", setPushed)
        b:SetScript("OnMouseUp", setHover)
        return b
    end

    local thanksBtn = MakePinkButton(parent, "说声谢谢 ^_^", 140, 26)
    thanksBtn:SetPoint("TOP", parent, "TOP", xOffset, y)
    thanksBtn:SetScript("OnClick", function()
        DEFAULT_CHAT_FRAME:AddMessage("感谢您的支持！愿你装备全橙、roll 点次次100。", 1, 0.6, 0.8)
    end)

    y = y - 40
    parent:SetHeight(-y + 20)
end)
  end
end)