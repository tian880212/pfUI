pfUI:RegisterModule("targettargettarget", "vanilla:tbc", function ()
  -- do not go further on disabled UFs
  -- 原生模式（unitframes.native）：保留暴雪原生目标的目标的目标框架，pfUI 不再接管
  if C.unitframes.disable == "1" or C.unitframes.native == "1" then return end

  pfUI.uf.targettargettarget = pfUI.uf:CreateUnitFrame("TargetTargetTarget", nil, C.unitframes.tttarget, .2)
  pfUI.uf.targettargettarget:UpdateFrameSize()
  pfUI.uf.targettargettarget:SetPoint("BOTTOM", UIParent , "BOTTOM", 0, 200)
  UpdateMovable(pfUI.uf.targettargettarget)
end)