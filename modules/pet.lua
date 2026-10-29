pfUI:RegisterModule("pet", "vanilla:tbc", function ()
  -- 原生模式（unitframes.native）：把宠物框架交回暴雪原生（同 player/target，显式救回一次）
  if C.unitframes.native == "1" then
    if PetFrame then
      PetFrame:SetAlpha(1)
      PetFrame:EnableMouse(true)
      -- 没有宠物时不要凭空显示，否则会留一个空宠物框
      if UnitExists("pet") then PetFrame:Show() end
    end
    return
  end

  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end
  pfUI.uf.pet = pfUI.uf:CreateUnitFrame("Pet", nil, C.unitframes.pet)
  pfUI.uf.pet:UpdateFrameSize()
  pfUI.uf.pet:SetPoint("BOTTOM", UIParent , "BOTTOM", 0, 163)
  UpdateMovable(pfUI.uf.pet)
end)
