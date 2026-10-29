pfUI:RegisterModule("targettarget", "vanilla:tbc", function ()
  -- do not go further on disabled UFs
  -- 原生模式（unitframes.native）：保留暴雪原生目标的目标框架，pfUI 不再接管
  if C.unitframes.disable == "1" or C.unitframes.native == "1" then return end

  pfUI.uf.targettarget = pfUI.uf:CreateUnitFrame("TargetTarget", nil, C.unitframes.ttarget, .2)
  pfUI.uf.targettarget:UpdateFrameSize()
  pfUI.uf.targettarget:SetPoint("BOTTOM", UIParent , "BOTTOM", 0, 125)
  UpdateMovable(pfUI.uf.targettarget)
end)
