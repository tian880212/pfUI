pfUI:RegisterModule("easteregg", "vanilla:tbc", function ()
  -- 捕获客户端原始 AFK 系统消息（在所有节日覆写之前），用于稳定触发彩花
  -- 部分节日会覆写 _G.MARKED_AFK，而 zhCN/Turtle 客户端实际打印的 AFK 消息并不吃该覆写，
  -- 导致 strfind(arg1, _G.MARKED_AFK) 漏匹配、彩花不显示。这里捕获覆写前的原始文案作兜底。
  local afk_marked_default = _G.MARKED_AFK
  local afk_marked_msg_default = _G.MARKED_AFK_MESSAGE
  local afk_cleared_default = _G.CLEARED_AFK

  -- 当前日期（年/月/日），用于农历节日的精确年份判定，避免跨年误触发（如 2028 七夕=8/26 误用到其余年份）
  local now_y = tonumber(date("%Y"))
  local now_m = tonumber(date("%m"))
  local now_d = tonumber(date("%d"))

  -- 圣诞快乐！
  if date("%m%d") == "1224" or date("%m%d") == "1225" then
    local title = (UnitFactionGroup("player") == "Horde") and PVP_RANK_18_0 or PVP_RANK_18_1
    local oldflag = _G.CHAT_FLAG_AFK

    local pvpking = CreateFrame("Frame", "pfPvPKing", UIParent)
    pvpking:Hide()

    pvpking:RegisterEvent("CHAT_MSG_SYSTEM")
    pvpking:SetScript("OnEvent", function()
      if strfind(arg1, "You are now", 1) and strfind(arg1, "(AFK)", 1) then
        _G.CHAT_FLAG_AFK = title .. " "
        this.time = GetTime()
        this:Show()
      end
    end)

    pvpking:SetScript("OnUpdate", function()
      if this.time + 1 < GetTime() then
        _G.CHAT_FLAG_AFK = oldflag
        this:Hide()
      end
    end)

    _G.MARKED_AFK           = "你现在是 |cff33ffcc" .. title .. "|r (暂离)。"
    _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc" .. title .. "|r (暂离)：%s"
    _G.CLEARED_AFK          = "你不再是 |cff33ffcc" .. title .. "|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你圣诞快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
  end

  -- 新年快乐
  if date("%m%d") == "1231" or date("%m%d") == "0101" then
    local fireworks = CreateFrame("Button", "pfFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你节日快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("新年快乐！")

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("又一年相伴！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    -- 暂离时触发烟花
    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    -- 基础爆炸动画
    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    -- 缓存爆炸效果以复用帧
    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    -- 在随机位置创建随机数量的烟花
    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      -- 淡入黑夜
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      -- 让"新年快乐"闪烁
      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      -- 创建基础爆炸
      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(25)
      f:SetHeight(25)
      f.tex:SetTexture(1,1,1,.5)
      f:SetAlpha(1)
      f:Show()

      -- 创建随机数量的彩色爆炸
      for i=1, math.random(20) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,100)-50), y+(math.random(0,100)-50))
        f:SetWidth(2)
        f:SetHeight(2)
        f.tex:SetTexture(math.random(),math.random(),math.random(),1)
        f:SetAlpha(1)
        f:Show()
      end
    end)
  end

  -- 情人节快乐 (2月14日)
  if date("%m%d") == "0214" then
    local fireworks = CreateFrame("Button", "pfFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你情人节快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("情人节快乐！")
    fireworks.text:SetTextColor(1, 0.4, 0.7) -- 粉色系

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("愿有岁月可回首，情深不负共白头！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    -- 暂离时触发特效
    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    -- 基础爆炸动画
    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    -- 缓存爆炸效果以复用帧
    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    -- 在随机位置创建随机数量的心形特效
    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      -- 淡入黑夜
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      -- 让"情人节快乐"闪烁
      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      -- 创建基础爆炸（心形）
      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(30)
      f:SetHeight(30)
      f.tex:SetTexture(1, 0.4, 0.7,.5) -- 粉色
      f:SetAlpha(1)
      f:Show()

      -- 创建随机数量的彩色心形
      for i=1, math.random(15) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,80)-40), y+(math.random(0,80)-40))
        f:SetWidth(3)
        f:SetHeight(3)
        f.tex:SetTexture(1, math.random(0.3,0.7), math.random(0.6,0.9),1) -- 粉色到紫色
        f:SetAlpha(1)
        f:Show()
      end
    end)
  end

  -- 除夕快乐（农历腊月最后一天：2026=2/16, 2027=2/5, 2028=1/25）
  if (now_y == 2026 and now_m == 2 and now_d == 16) or
     (now_y == 2027 and now_m == 2 and now_d == 5) or
     (now_y == 2028 and now_m == 1 and now_d == 25) then
    local fireworks = CreateFrame("Button", "pfFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你除夕快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("除夕快乐！")
    fireworks.text:SetTextColor(1, 0.8, 0) -- 金色

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("今岁今宵尽，明年明日催！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    -- 暂离时触发特效
    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    -- 基础爆炸动画
    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    -- 缓存爆炸效果以复用帧
    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    -- 在随机位置创建随机数量的烟花
    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      -- 淡入黑夜
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      -- 让"除夕快乐"闪烁
      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      -- 创建基础爆炸
      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(25)
      f:SetHeight(25)
      f.tex:SetTexture(1,0.8,0,.5) -- 金色
      f:SetAlpha(1)
      f:Show()

      -- 创建随机数量的彩色爆炸（红色和金色为主）
      for i=1, math.random(20) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,100)-50), y+(math.random(0,100)-50))
        f:SetWidth(2)
        f:SetHeight(2)
        f.tex:SetTexture(math.random(0.8,1), math.random(0.5,0.8), 0,1) -- 红金色系
        f:SetAlpha(1)
        f:Show()
      end
    end)
  end

  -- 春节快乐（农历正月初一至初三：2026=2/17-19, 2027=2/6-8, 2028=1/26-28）
  if (now_y == 2026 and now_m == 2 and (now_d == 17 or now_d == 18 or now_d == 19)) or
     (now_y == 2027 and now_m == 2 and (now_d == 6 or now_d == 7 or now_d == 8)) or
     (now_y == 2028 and now_m == 1 and (now_d == 26 or now_d == 27 or now_d == 28)) then
    local fireworks = CreateFrame("Button", "pfFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你春节快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("春节快乐！")
    fireworks.text:SetTextColor(1, 0, 0) -- 红色

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("春风吹拂千山绿，新年新景新气象！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    -- 暂离时触发特效
    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    -- 基础爆炸动画
    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    -- 缓存爆炸效果以复用帧
    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    -- 在随机位置创建随机数量的烟花
    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      -- 淡入黑夜
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      -- 让"春节快乐"闪烁
      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      -- 创建基础爆炸
      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(25)
      f:SetHeight(25)
      f.tex:SetTexture(1,0,0,.5) -- 红色
      f:SetAlpha(1)
      f:Show()

      -- 创建随机数量的彩色爆炸（红色和金色为主）
      for i=1, math.random(25) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,120)-60), y+(math.random(0,120)-60))
        f:SetWidth(2)
        f:SetHeight(2)
        f.tex:SetTexture(math.random(0.8,1), math.random(0,0.2), 0,1) -- 红色系
        f:SetAlpha(1)
        f:Show()
      end
    end)
  end

  -- 劳动节 (5月1日)
  if date("%m%d") == "0501" then
    local fireworks = CreateFrame("Button", "pfLaborFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你劳动节快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("劳动最光荣！")
    fireworks.text:SetTextColor(0.2, 0.8, 0.2) -- 绿色

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("每一份劳动都是点亮幸福的光！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(25)
      f:SetHeight(25)
      f.tex:SetTexture(0.2,0.8,0.2,.5)
      f:SetAlpha(1)
      f:Show()

      for i=1, math.random(20) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,100)-50), y+(math.random(0,100)-50))
        f:SetWidth(2)
        f:SetHeight(2)
        f.tex:SetTexture(math.random(0.2,0.6), math.random(0.6,1), math.random(0.2,0.5),1)
        f:SetAlpha(1)
        f:Show()
      end
    end)

    -- 修改AFK消息
    _G.MARKED_AFK           = "你现在是 |cff33ffcc劳动模范|r (暂离)。"
    _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc劳动模范|r (暂离)：%s"
    _G.CLEARED_AFK          = "你不再是 |cff33ffcc劳动模范|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你劳动节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
  end

  -- 儿童节快乐 (6月1日)
  if date("%m%d") == "0601" then
    local fireworks = CreateFrame("Button", "pfChildrenFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你儿童节快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("儿童节快乐！")
    fireworks.text:SetTextColor(0.2, 0.8, 1) -- 天蓝色

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("愿你眼里有光，心里有爱，做永远的孩子！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(25)
      f:SetHeight(25)
      f.tex:SetTexture(math.random(), math.random(), math.random(), .5) -- 五彩
      f:SetAlpha(1)
      f:Show()

      for i=1, math.random(20) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,100)-50), y+(math.random(0,100)-50))
        f:SetWidth(2)
        f:SetHeight(2)
        f.tex:SetTexture(math.random(), math.random(), math.random(), 1)
        f:SetAlpha(1)
        f:Show()
      end
    end)

    _G.MARKED_AFK           = "你现在是 |cff33ffcc快乐儿童|r (暂离)。"
    _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc快乐儿童|r (暂离)：%s"
    _G.CLEARED_AFK          = "你不再是 |cff33ffcc快乐儿童|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你儿童节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
  end

  -- 建党节 (7月1日)
  if date("%m%d") == "0701" then
    local fireworks = CreateFrame("Button", "pfPartyFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你建党节快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("七一建党节！")
    fireworks.text:SetTextColor(0.8, 0.2, 0.2) -- 暗红

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("不忘初心，牢记使命！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(25)
      f:SetHeight(25)
      f.tex:SetTexture(0.8,0.2,0.2,.5)
      f:SetAlpha(1)
      f:Show()

      for i=1, math.random(20) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,100)-50), y+(math.random(0,100)-50))
        f:SetWidth(2)
        f:SetHeight(2)
        f.tex:SetTexture(1, math.random(0.6,0.9), 0,1)
        f:SetAlpha(1)
        f:Show()
      end
    end)

    _G.MARKED_AFK           = "你现在是 |cff33ffcc红色先锋|r (暂离)。"
    _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc红色先锋|r (暂离)：%s"
    _G.CLEARED_AFK          = "你不再是 |cff33ffcc红色先锋|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你建党节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
  end

  -- 建军节 (8月1日)
  if date("%m%d") == "0801" then
    local fireworks = CreateFrame("Button", "pfArmyFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你建军节快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("八一建军节！")
    fireworks.text:SetTextColor(0.9, 0.1, 0.1) -- 军红

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("铁血军魂，护国佑民！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(25)
      f:SetHeight(25)
      f.tex:SetTexture(0.9,0.1,0.1,.5)
      f:SetAlpha(1)
      f:Show()

      for i=1, math.random(20) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,100)-50), y+(math.random(0,100)-50))
        f:SetWidth(2)
        f:SetHeight(2)
        f.tex:SetTexture(math.random(0.7,1), math.random(0.5,0.8), math.random(0,0.3),1)
        f:SetAlpha(1)
        f:Show()
      end
    end)

    _G.MARKED_AFK           = "你现在是 |cff33ffcc钢铁战士|r (暂离)。"
    _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc钢铁战士|r (暂离)：%s"
    _G.CLEARED_AFK          = "你不再是 |cff33ffcc钢铁战士|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你建军节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
  end

  -- 国庆节 (10月1日)
  if date("%m%d") == "1001" then
    local fireworks = CreateFrame("Button", "pfNationalFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你国庆节快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("国庆节快乐！")
    fireworks.text:SetTextColor(1, 0.5, 0) -- 橙色

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("盛世华诞，举国同庆！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(25)
      f:SetHeight(25)
      f.tex:SetTexture(1,0.5,0,.5)
      f:SetAlpha(1)
      f:Show()

      for i=1, math.random(25) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,120)-60), y+(math.random(0,120)-60))
        f:SetWidth(2)
        f:SetHeight(2)
        f.tex:SetTexture(math.random(0.8,1), math.random(0.2,0.5), 0,1)
        f:SetAlpha(1)
        f:Show()
      end
    end)

    _G.MARKED_AFK           = "你现在是 |cff33ffcc祖国卫士|r (暂离)。"
    _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc祖国卫士|r (暂离)：%s"
    _G.CLEARED_AFK          = "你不再是 |cff33ffcc祖国卫士|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你国庆节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
  end

  -- 中秋节（农历八月十五：2026=9/25, 2027=9/15, 2028=10/3）
  if (now_y == 2026 and now_m == 9 and now_d == 25) or
     (now_y == 2027 and now_m == 9 and now_d == 15) or
     (now_y == 2028 and now_m == 10 and now_d == 3) then
    local fireworks = CreateFrame("Button", "pfMidAutumnFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你中秋快乐!")

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetText("中秋快乐！")
    fireworks.text:SetTextColor(1, 0.9, 0.2) -- 金黄色

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.dtext:SetText("月圆人团圆，千里共婵娟！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, afk_marked_default) or strfind(arg1, afk_marked_msg_default) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) or strfind(arg1, afk_cleared_default) then
        this:Hide()
      end
    end)

    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(25)
      f:SetHeight(25)
      f.tex:SetTexture(1,0.9,0.2,.5)
      f:SetAlpha(1)
      f:Show()

      for i=1, math.random(20) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,100)-50), y+(math.random(0,100)-50))
        f:SetWidth(2)
        f:SetHeight(2)
        f.tex:SetTexture(1, math.random(0.8,1), math.random(0.4,0.7),1)
        f:SetAlpha(1)
        f:Show()
      end
    end)

    _G.MARKED_AFK           = "你现在是 |cff33ffcc月宫玉兔|r (暂离)。"
    _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc月宫玉兔|r (暂离)：%s"
    _G.CLEARED_AFK          = "你不再是 |cff33ffcc月宫玉兔|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你中秋快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
  end

  -- 医师节（公历8月19日，每年固定）& 七夕节（农历七月初七：2026=8/19, 2027=8/8, 2028=8/26）
  -- 仅 2026-08-19 两者重合 → 一起庆祝；其余日期只显示各自节日
  local is_doctor = (now_m == 8 and now_d == 19)
  local is_qixi  = (now_y == 2026 and now_m == 8 and now_d == 19) or
                   (now_y == 2027 and now_m == 8 and now_d == 8) or
                   (now_y == 2028 and now_m == 8 and now_d == 26)
  if is_doctor or is_qixi then
    local default_marked = _G.MARKED_AFK
    local default_marked_msg = _G.MARKED_AFK_MESSAGE
    local fireworks = CreateFrame("Button", "pfLoveDoctorFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetTextColor(1, 0.4, 0.7) -- 粉色

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)

    if is_doctor and is_qixi then
      fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你七夕节与医师节快乐！")
      fireworks.text:SetText("七夕快乐！")
      fireworks.dtext:SetText("愿有情人终成眷属，也向所有白衣天使致敬！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")
    elseif is_qixi then
      fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你七夕节快乐！")
      fireworks.text:SetText("七夕快乐！")
      fireworks.dtext:SetText("愿有情人终成眷属，花好月圆！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")
    else -- 仅医师节（2027/2028 的 8/19）
      fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你中国医师节快乐！")
      fireworks.text:SetText("医师节快乐！")
      fireworks.dtext:SetText("向每一位白衣天使致敬，谢谢你守护生命！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")
    end

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    -- 暂离时触发特效（vanilla 无 UnitIsAFK API，故用系统消息匹配；三重兜底：稳定前缀+实时全局+覆写前原始文案）
    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, default_marked) or strfind(arg1, default_marked_msg) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) then
        this:Hide()
      end
    end)

    -- 基础爆炸动画
    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    -- 缓存爆炸效果以复用帧
    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end

      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()

      table.insert(explosions, frame)

      return frame
    end

    -- 在随机位置创建随机数量的烟花（粉色与蓝白交织）
    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      -- 淡入黑夜
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end

      -- 让"七夕快乐"闪烁
      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)

      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end

      local x,y = math.random(1, width), -1*math.random(1,height)

      -- 创建基础爆炸（粉色）
      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(28)
      f:SetHeight(28)
      f.tex:SetTexture(1, 0.4, 0.7, .5) -- 粉色
      f:SetAlpha(1)
      f:Show()

      -- 创建随机数量的彩色爆炸（蓝白系，象征医师）
      for i=1, math.random(15) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,80)-40), y+(math.random(0,80)-40))
        f:SetWidth(3)
        f:SetHeight(3)
        f.tex:SetTexture(math.random(0.4,0.8), math.random(0.6,1), math.random(0.8,1), 1) -- 蓝白
        f:SetAlpha(1)
        f:Show()
      end
    end)

    -- 修改AFK消息（按实际节日区分，仅在两者重合时一起显示）
    if is_doctor and is_qixi then
      _G.MARKED_AFK           = "你现在是 |cff33ffcc鹊桥医者|r (暂离)。"
      _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc鹊桥医者|r (暂离)：%s"
      _G.CLEARED_AFK          = "你不再是 |cff33ffcc鹊桥医者|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝七夕与医师节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
    elseif is_qixi then
      _G.MARKED_AFK           = "你现在是 |cff33ffcc织女星|r (暂离)。"
      _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc织女星|r (暂离)：%s"
      _G.CLEARED_AFK          = "你不再是 |cff33ffcc织女星|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你七夕节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
    else -- 仅医师节（2027/2028 的 8/19）
      _G.MARKED_AFK           = "你现在是 |cff33ffcc白衣天使|r (暂离)。"
      _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc白衣天使|r (暂离)：%s"
      _G.CLEARED_AFK          = "你不再是 |cff33ffcc白衣天使|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你中国医师节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
    end
  end

  -- 护士节（国际护士节，公历5月12日，每年固定）
  if now_m == 5 and now_d == 12 then
    local default_marked = _G.MARKED_AFK
    local default_marked_msg = _G.MARKED_AFK_MESSAGE
    local fireworks = CreateFrame("Button", "pfNurseFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetTextColor(0.4, 0.85, 1) -- 天蓝

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你国际护士节快乐！")
    fireworks.text:SetText("护士节快乐！")
    fireworks.dtext:SetText("向每一位提灯天使致敬，谢谢你守护健康！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    -- 暂离时触发特效（vanilla 无 UnitIsAFK API，故用系统消息匹配；三重兜底）
    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, default_marked) or strfind(arg1, default_marked_msg) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) then
        this:Hide()
      end
    end)

    -- 基础爆炸动画
    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end
      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()
      table.insert(explosions, frame)
      return frame
    end

    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end
      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)
      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end
      local x,y = math.random(1, width), -1*math.random(1,height)
      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(28)
      f:SetHeight(28)
      f.tex:SetTexture(0.4, 0.85, 1, .5) -- 天蓝
      f:SetAlpha(1)
      f:Show()
      -- 创建随机数量的彩色爆炸（蓝白系，象征护理）
      for i=1, math.random(15) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,80)-40), y+(math.random(0,80)-40))
        f:SetWidth(3)
        f:SetHeight(3)
        f.tex:SetTexture(math.random(0.5,0.9), math.random(0.8,1), math.random(0.8,1), 1) -- 蓝白
        f:SetAlpha(1)
        f:Show()
      end
    end)

    -- 修改AFK消息
    _G.MARKED_AFK           = "你现在是 |cff33ffcc提灯天使|r (暂离)。"
    _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc提灯天使|r (暂离)：%s"
    _G.CLEARED_AFK          = "你不再是 |cff33ffcc提灯天使|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你国际护士节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
  end

  -- 教师节（公历9月10日，每年固定）
  if now_m == 9 and now_d == 10 then
    local default_marked = _G.MARKED_AFK
    local default_marked_msg = _G.MARKED_AFK_MESSAGE
    local fireworks = CreateFrame("Button", "pfTeacherFireworks", WorldFrame)
    fireworks:SetFrameStrata("DIALOG")
    fireworks:SetAllPoints()
    fireworks:Hide()

    fireworks.night = fireworks:CreateTexture("LOW")
    fireworks.night:SetTexture(0,0,0,1)
    fireworks.night:SetGradientAlpha("VERTICAL", 0,0,0,.5, 0,0,0,1)
    fireworks.night:SetAllPoints()

    fireworks.stext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.stext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.stext:SetPoint("TOP", 0, -380)

    fireworks.text = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.text:SetFont(pfUI.media["font:BigNoodleTitling.ttf"], 38)
    fireworks.text:SetPoint("TOP", 0, -400)
    fireworks.text:SetTextColor(1, 0.8, 0.3) -- 金色

    fireworks.dtext = fireworks:CreateFontString("Status", "LOW", "GameFontWhite")
    fireworks.dtext:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    fireworks.dtext:SetPoint("TOP", 0, -430)
    fireworks.stext:SetText("|cff33ffcc最爱|cffffffff 祝你教师节快乐！")
    fireworks.text:SetText("教师节快乐！")
    fireworks.dtext:SetText("感恩每一位辛勤的园丁，桃李满天下！\n\n感谢使用|cff33ffcc最爱|cffffffff插件包（基于PFUI，感谢|cff33ffccShagu|cffffffff!）\n\n|cff444444<点击>或输入'/afk'退出")

    fireworks:SetScript("OnClick", function()
      this:Hide()
    end)

    -- 暂离时触发特效（vanilla 无 UnitIsAFK API，故用系统消息匹配；三重兜底）
    fireworks:RegisterEvent("CHAT_MSG_SYSTEM")
    fireworks:SetScript("OnEvent", function()
      if strfind(arg1, "你现在是")
         or strfind(arg1, _G.MARKED_AFK) or strfind(arg1, _G.MARKED_AFK_MESSAGE)
         or strfind(arg1, default_marked) or strfind(arg1, default_marked_msg) then
        this:SetAlpha(0)
        this:Show()
      elseif strfind(arg1, "你不再是") or strfind(arg1, _G.CLEARED_AFK) then
        this:Hide()
      end
    end)

    -- 基础爆炸动画
    local function animation()
      local fps = (60 / math.max(GetFramerate(), 1))
      this:SetWidth(this:GetWidth()+fps)
      this:SetHeight(this:GetHeight()+fps)
      this:SetAlpha(this:GetAlpha()-fps*.01)
      if this:GetAlpha() <= 0 then
        this.free = true
        this:Hide()
      end
    end

    local explosions = {}
    local function GetExplosion()
      for id, frame in pairs(explosions) do
        if frame.free then
          frame.free = nil
          return frame
        end
      end
      local frame = CreateFrame("Frame", nil, fireworks)
      frame:SetScript("OnUpdate", animation)
      frame.tex = frame:CreateTexture("HIGH")
      frame.tex:SetAllPoints()
      table.insert(explosions,  frame)
      return frame
    end

    local width, height = GetScreenWidth(), GetScreenHeight()
    fireworks:SetScript("OnUpdate", function()
      if this:GetAlpha() < 1 then
        this:SetAlpha(this:GetAlpha() + .02)
        return
      end
      local r,g,b = this.text:GetTextColor()
      this.text:SetTextColor(r+(math.random()-.5)/10, g+(math.random()-.5)/10, b+(math.random()-.5)/10,1)
      if ( this.tick or 1) > GetTime() then return else this.tick = GetTime() + math.random() - .2 end
      local x,y = math.random(1, width), -1*math.random(1,height)
      local f = GetExplosion()
      f:ClearAllPoints()
      f:SetPoint("CENTER", fireworks, "TOPLEFT", x, y)
      f:SetWidth(28)
      f:SetHeight(28)
      f.tex:SetTexture(1, 0.8, 0.3, .5) -- 金色
      f:SetAlpha(1)
      f:Show()
      -- 创建随机数量的彩色爆炸（暖色系，象征桃李）
      for i=1, math.random(15) do
        local f = GetExplosion()
        f:ClearAllPoints()
        f:SetPoint("CENTER", fireworks, "TOPLEFT", x+(math.random(0,80)-40), y+(math.random(0,80)-40))
        f:SetWidth(3)
        f:SetHeight(3)
        f.tex:SetTexture(math.random(0.8,1), math.random(0.6,0.9), math.random(0.3,0.6), 1) -- 暖色
        f:SetAlpha( 1)
        f:Show()
      end
    end)

    -- 修改AFK消息
    _G.MARKED_AFK           = "你现在是 |cff33ffcc辛勤园丁|r (暂离)。"
    _G.MARKED_AFK_MESSAGE   = "你现在是 |cff33ffcc辛勤园丁|r (暂离)：%s"
    _G.CLEARED_AFK          = "你不再是 |cff33ffcc辛勤园丁|r (暂离)。\n|cff33ffcc最爱|cffffffff 祝你教师节快乐。感谢使用最爱插件包（基于PFUI，感谢shagu！）"
  end
end)