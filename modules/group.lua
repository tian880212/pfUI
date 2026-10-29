pfUI:RegisterModule("group", "vanilla:tbc", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  -- 原生模式（unitframes.native）：队伍框架交回客户端，pfUI 不再建队伍框。
  -- ⛔ 不能只 return 了事：下面那段会把原生 PartyMemberFrame1..4 Hide 掉，并把它们的
  --    Show 换成空函数（本会话内再也点不亮）。所以必须在这里提前退出。
  -- · Turtle WoW：队伍框是客户端自带的 GroupUI（GroupClusterFrame1-8），
  --   由 modules/turtle-wow.lua 的 pfUIHandlesGroupOrRaid() 放行（native 时返回 false）。
  -- · 其它客户端：暴雪原生 PartyMemberFrame1..4，由客户端自己在队伍变化时显示。
  if C.unitframes.native == "1" then
    for i = 1, 4 do
      local f = _G["PartyMemberFrame" .. i]
      if f then
        f:SetAlpha(1)
        f:EnableMouse(true)
        -- 重载时人已经在队伍里的话，客户端事件未必再触发一次，这里补一次
        if UnitExists("party" .. i) then f:Show() end
      end
    end
    return
  end

  -- hide blizzard group frames
  local frame
  for i=1, 4 do
    frame = _G[string.format("PartyMemberFrame%d", i)]
    if frame then
      frame:Hide()
      frame:UnregisterAllEvents()
      frame.Show = function () return end
    end
  end

  pfUI.uf.group = {}

  function pfUI.uf.group:UpdateConfig()
    local startid = C.unitframes.selfingroup == "1" and 0 or 1
    local spacing = C.unitframes.group.pspace
    local rawborder, default_border = GetBorderSize("unitframes")

    for i=0, 4 do
      local active = i >= 1 or startid == 0

      if active then
        pfUI.uf.group[i] = pfUI.uf.group[i] or pfUI.uf:CreateUnitFrame("Party", i, C.unitframes.group)
        pfUI.uf.group[i]:UpdateFrameSize()
        pfUI.uf.group[i]:SetPoint("TOPLEFT", 5, -5 - ((i-startid)*75))
        pfUI.uf.group[i]:UpdateConfig()
        UpdateMovable(pfUI.uf.group[i])
      elseif pfUI.uf.group[i] then
        pfUI.uf.group[i]:UpdateConfig()
        RemoveMovable(pfUI.uf.group[i])
      end

      if C.unitframes.grouptarget.visible == "1" and active then
        pfUI.uf.group[i].target = pfUI.uf.group[i].target or pfUI.uf:CreateUnitFrame("Party" .. i .. "Target", nil, C.unitframes.grouptarget, 0.2)
        pfUI.uf.group[i].target:UpdateFrameSize()
        pfUI.uf.group[i].target:SetPoint("TOPLEFT", pfUI.uf.group[i], "TOPRIGHT", 3*default_border, 0)
        pfUI.uf.group[i].target:UpdateConfig()
        UpdateMovable(pfUI.uf.group[i].target)
      elseif pfUI.uf.group[i] and pfUI.uf.group[i].target then
        pfUI.uf.group[i].target:UpdateConfig()
        RemoveMovable(pfUI.uf.group[i].target)
      end

      if C.unitframes.grouppet.visible == "1" and active then
        pfUI.uf.group[i].pet = pfUI.uf.group[i].pet or pfUI.uf:CreateUnitFrame("PartyPet", i, C.unitframes.grouppet, 0.5)
        pfUI.uf.group[i].pet:UpdateFrameSize()
        pfUI.uf.group[i].pet:SetPoint("BOTTOMLEFT", pfUI.uf.group[i], "BOTTOMRIGHT", 3*default_border, -default_border)
        pfUI.uf.group[i].pet:UpdateConfig()
        UpdateMovable(pfUI.uf.group[i].pet)
      elseif pfUI.uf.group[i] and pfUI.uf.group[i].pet then
        pfUI.uf.group[i].pet:UpdateConfig()
        RemoveMovable(pfUI.uf.group[i].pet)
      end
    end
  end

  pfUI.uf.group:UpdateConfig()
end)
