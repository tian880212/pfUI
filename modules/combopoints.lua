pfUI:RegisterModule("combopoints", "vanilla:tbc", function ()
  local rawborder, border = GetBorderSize()

  -- Hide Blizzard combo point frame and unregister all events to prevent it from popping up again
  ComboFrame:Hide()
  ComboFrame:UnregisterAllEvents()

  local _, class = UnitClass("player")
  local MAX_COMBO = 5

  pfUI.combopoints = pfUI.combopoints or {}
  local module = pfUI.combopoints
  module.points = module.points or {}
  module.count = module.count or 0
  module.glowing = false
  module.glowtime = 0

  -- 外观缓存：UpdateConfig 写入，UpdatePoint 只读
  -- （每次点数变化都重新解析颜色字符串太浪费，而且存档里的非法值必须集中兜底一次）
  local enabled = true
  local style = "pips"
  -- 默认材质 pfUI-F（来自 pfUI-CustomMedia 的 A-Z 材质包，与 GUI 下拉里的 pfUI-F 同一条路径）
  local texture = "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga"
  local grow = "right"                                -- 与 light 档一致（水平向右增长）
  local spacing = 3                                   -- 取自 light 档「最爱扎你」存档
  local showempty = false
  local shownumber = false
  local showborder = true
  local showshadow = true
  local glow = false
  local fontsize = 8
  local textcolor = { 1, 1, 1, 1 }
  local emptycolor = { .15, .15, .15, .5 }
  local colors = {}                                   -- [1..MAX_COMBO] = {r,g,b,a}

  -- "r,g,b,a" → 四个分量；缺失或非法时整套回退到默认值。
  -- ⚠️ 配置值可能是任意字符串甚至 nil，必须 tonumber 兜底，
  --    否则直接喂给 SetTexture/SetVertexColor 会抛错（运行期写入的配置值一律守卫）。
  local function ParseColor(str, dr, dg, db, da)
    if type(str) ~= "string" then return dr, dg, db, da end

    local _, _, r, g, b, a = string.find(str, "([%d%.]+),([%d%.]+),([%d%.]+),([%d%.]+)")
    if not r then return dr, dg, db, da end

    return tonumber(r) or dr, tonumber(g) or dg, tonumber(b) or db, tonumber(a) or da
  end

  local function GetNumber(key, default)
    local value = tonumber(C.unitframes[key])
    if not value then value = default end
    return value
  end

  -- five independent pips, chained to the first one (see ApplyChain)
  for point = 1, MAX_COMBO do
    local f = CreateFrame("Frame", "pfCombo" .. point, UIParent)
    f:SetFrameStrata("HIGH")
    f:Hide()

    f.tex = f:CreateTexture("OVERLAY")
    f.tex:SetAllPoints(f)

    -- 数字：方块样式下显示序号，数字样式下显示当前点数
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.text:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.text:SetJustifyH("CENTER")
    f.text:SetJustifyV("MIDDLE")
    f.text:Hide()

    CreateBackdrop(f)
    CreateBackdropShadow(f)

    module.points[point] = f
  end

  -- 上色。solid = 纯色贴图（set texture 带色 + 顶点色归白），
  -- 其余为材质路径（贴图 + 顶点色着色）——两套必须互斥且都清干净，
  -- 否则从材质切回纯色会被上一轮的顶点色二次染色。
  local function PaintPoint(point, r, g, b, a)
    local f = module.points[point]

    if texture == "solid" or texture == "" then
      f.tex:SetTexture(r, g, b, a)
      f.tex:SetVertexColor(1, 1, 1, 1)
    else
      f.tex:SetTexture(texture)
      f.tex:SetVertexColor(r, g, b, a)
    end
  end

  local function UpdatePoint(point)
    local f = module.points[point]
    local num = module.count

    if not enabled then
      f:Hide()
      return
    end

    -- 数字样式：整排收成一个数字（0 点时不显示）
    if style == "numbers" then
      if point > 1 or num < 1 then
        f:Hide()
        return
      end

      f.tex:Hide()
      if f.backdrop then f.backdrop:Hide() end
      if f.backdrop_shadow then f.backdrop_shadow:Hide() end

      f.text:SetText(tostring(num))
      f.text:Show()
      f:SetAlpha(1)
      f:Show()
      return
    end

    local active = point <= num

    -- 未点亮的点：默认隐藏；开启「显示空槽」时用空槽色占位（固定排面大小）
    if not active and not showempty then
      f:Hide()
      return
    end

    f.tex:Show()

    if f.backdrop then
      if showborder then f.backdrop:Show() else f.backdrop:Hide() end
    end

    if f.backdrop_shadow then
      if showshadow then f.backdrop_shadow:Show() else f.backdrop_shadow:Hide() end
    end

    if active then
      local c = colors[point]
      PaintPoint(point, c[1], c[2], c[3], c[4])
    else
      PaintPoint(point, emptycolor[1], emptycolor[2], emptycolor[3], emptycolor[4])
    end

    if shownumber and active then
      f.text:SetText(tostring(point))
      f.text:Show()
    else
      f.text:Hide()
    end

    -- 满点闪光由 OnUpdate 改 alpha，退出闪光时要还原
    if not module.glowing then f:SetAlpha(1) end

    f:Show()
  end

  local function Refresh()
    if module.count > MAX_COMBO then module.count = MAX_COMBO end
    if module.count < 0 then module.count = 0 end

    -- 满点闪光只对方块样式有意义（数字样式只有一个数字，闪起来只会晃眼）；
    -- 解锁模式里点数只是占位，闪起来会干扰对齐，一并排除。
    module.glowing = enabled and glow and not module.unlocking and style ~= "numbers" and module.count >= MAX_COMBO

    for point = 1, MAX_COMBO do
      UpdatePoint(point)
    end
  end

  -- 第一个点：解锁拖动过的存档位置优先（pfUI 约定：C.position 永远赢代码布局），
  -- 否则贴在目标框右侧，并按配置加偏移。其余点靠 ApplyChain 链在它后面。
  local function ApplyAnchor()
    local first = module.points[1]
    local offx = GetNumber("combooffx", 0)
    local offy = GetNumber("combooffy", 0)

    local saved = C.position and C.position["pfCombo1"]

    first:ClearAllPoints()

    if saved and saved.xpos and saved.ypos then
      first:SetPoint(saved.anchor or "TOPLEFT", saved.xpos, saved.ypos)
      first:SetScale(saved.scale or 1)
    elseif pfUI.uf and pfUI.uf.target then
      first:SetPoint("TOPLEFT", pfUI.uf.target, "TOPRIGHT", border*3 + offx, offy)
      first:SetScale(1)
    else
      first:SetPoint("CENTER", UIParent, "CENTER", offx, 10 + offy)
      first:SetScale(1)
    end

    -- 布局变了就丢掉「初始位置」快照，否则解锁里中键 Reset 会回到登录时的旧偏移
    first.posdata = nil
  end

  -- 2..5 链在前一个点上：这样拖动第一个点就能带动整排，
  -- 也避免每改一次间距/方向都要重算绝对坐标。
  local function ApplyChain()
    for point = 2, MAX_COMBO do
      local f = module.points[point]
      local prev = module.points[point - 1]

      f:ClearAllPoints()

      if grow == "up" then
        f:SetPoint("BOTTOMLEFT", prev, "TOPLEFT", 0, spacing)
      elseif grow == "right" then
        f:SetPoint("TOPLEFT", prev, "TOPRIGHT", spacing, 0)
      elseif grow == "left" then
        f:SetPoint("TOPRIGHT", prev, "TOPLEFT", -spacing, 0)
      else
        f:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -spacing)
      end
    end
  end

  function module:DisplayNum(num)
    module.count = tonumber(num) or 0
    Refresh()
  end

  function module:UpdateConfig()
    enabled    = C.unitframes.comboshow ~= "0"
    style      = C.unitframes.combostyle or "pips"
    texture    = C.unitframes.combotexture or "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga"
    grow       = C.unitframes.combogrow or "right"
    spacing    = GetNumber("combospacing", 3)
    showempty  = C.unitframes.comboempty == "1"
    shownumber = C.unitframes.combopipnumbers == "1"
    showborder = C.unitframes.comboborder ~= "0"
    showshadow = C.unitframes.comboshadow ~= "0"
    glow       = C.unitframes.comboglow == "1"
    fontsize   = GetNumber("combofontsize", 8)

    if fontsize < 6 then fontsize = 6 end

    textcolor  = { ParseColor(C.unitframes.combotextcolor, 1, 1, 1, 1) }
    emptycolor = { ParseColor(C.unitframes.comboemptycolor, .15, .15, .15, .5) }

    -- 三档颜色：1-2 低点、3 中点、4-5 高点（旧版硬编码配色的可配置版本）
    colors[1] = { ParseColor(C.unitframes.combocolor_low, 1, .3, .3, .75) }
    colors[2] = colors[1]
    colors[3] = { ParseColor(C.unitframes.combocolor_mid, 1, 1, .3, .75) }
    colors[4] = { ParseColor(C.unitframes.combocolor_high, .3, 1, .3, .75) }
    colors[5] = colors[4]

    local width  = GetNumber("combowidth", 40.5)
    local height = GetNumber("comboheight", 6)

    if width < 1 then width = 1 end
    if height < 1 then height = 1 end

    for point = 1, MAX_COMBO do
      local f = module.points[point]
      f:SetWidth(width)
      f:SetHeight(height)
      f.text:SetFont(pfUI.font_default, fontsize, "OUTLINE")
      f.text:SetTextColor(textcolor[1], textcolor[2], textcolor[3], textcolor[4])
    end

    ApplyAnchor()
    ApplyChain()
    Refresh()
  end

  module:UpdateConfig()

  -- 只有第一个点注册为可拖动模块：其余点链在它后面跟着走，
  -- 免得解锁模式里 5 个点各自可拖、拖完又被链式布局拉回去。
  UpdateMovable(module.points[1])

  -- 满点闪光：隐藏帧不触发 OnUpdate，所以点数不吃满时这个脚本是零开销
  module.points[1]:SetScript("OnUpdate", function()
    if not module.glowing then return end

    module.glowtime = module.glowtime + (arg1 or 0) * 3
    if module.glowtime > 6.28 then module.glowtime = module.glowtime - 6.28 end

    local alpha = .55 + .45 * math.abs(math.sin(module.glowtime))

    for point = 1, MAX_COMBO do
      local f = module.points[point]
      if f:IsShown() then f:SetAlpha(alpha) end
    end
  end)

  -- 解锁模式：临时点亮整排，方便看清方向与间距；退出时恢复真实点数。
  -- 注意必须用 HookScript 链式挂，直接 SetScript 会整体覆盖 unlock 自己的 OnShow/OnHide。
  if pfUI.unlock then
    HookScript(pfUI.unlock, "OnShow", function()
      if not enabled then return end
      module.unlocking = true
      module.unlockbackup = module.count
      module.count = MAX_COMBO
      Refresh()

      -- 只有第 1 个点可拖，而默认 6x6 的拖动热区在解锁模式里几乎抓不住。
      -- 用负的 hit rect 把可点区域向外撑大（只影响点击、不改外观），
      -- 附近点都能拖到整排。unlock 的 dragger 由它的 OnShow 创建，故此处一定已存在。
      local drag = module.points[1].drag
      if drag and drag.SetHitRectInsets then
        local pad = 30 + spacing * 2
        drag:SetHitRectInsets(-pad, -pad, -pad, -pad)
      end
    end)

    HookScript(pfUI.unlock, "OnHide", function()
      module.unlocking = nil
      module.count = module.unlockbackup or 0
      module.unlockbackup = nil
      Refresh()
    end)
  end

  -- combo
  if class == "DRUID" or class == "ROGUE" then
    local combo = CreateFrame("Frame")
    combo:RegisterEvent("UNIT_COMBO_POINTS")
    combo:RegisterEvent("PLAYER_COMBO_POINTS")
    combo:RegisterEvent("PLAYER_TARGET_CHANGED")
    combo:RegisterEvent("PLAYER_ENTERING_WORLD")
    combo:SetScript("OnEvent", function()
      pfUI.combopoints:DisplayNum(GetComboPoints("target"))
    end)

  -- reck
  elseif class == "PALADIN" then
    local reck = CreateFrame("Frame")
    reck:RegisterEvent("CHARACTER_POINTS_CHANGED")
    reck:RegisterEvent("PLAYER_DEAD")
    reck:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
    reck:RegisterEvent("CHAT_MSG_COMBAT_SELF_CRITS")
    reck:RegisterEvent("CHAT_MSG_COMBAT_SELF_MISSES")
    reck:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
    reck:RegisterEvent("CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS")

    local COMBATHITCRITOTHERSELF = SanitizePattern(COMBATHITCRITOTHERSELF)
    local COMBATHITCRITSCHOOLOTHERSELF = SanitizePattern(COMBATHITCRITSCHOOLOTHERSELF)

    reck:SetScript("OnEvent", function()
      if not this.rank or event == "CHARACTER_POINTS_CHANGED" then
        _,_,_,_,this.rank = GetTalentInfo(2,13)
      end

      if event == "PLAYER_DEAD" or event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_COMBAT_SELF_CRITS" or event == "CHAT_MSG_COMBAT_SELF_MISSES" then
        this.stacks = 0
        pfUI.combopoints:DisplayNum(0)
      elseif arg1 and this.rank and this.rank == 5 and this.stacks and this.stacks < 4 then
        if strfind(arg1, COMBATHITCRITOTHERSELF) or strfind(arg1, COMBATHITCRITSCHOOLOTHERSELF) then
          this.stacks = this.stacks + 1
          pfUI.combopoints:DisplayNum(this.stacks)
        end
      end
    end)
  end
end)
