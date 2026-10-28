-- 独立能量条：参考 RogueTicker 的能量条样式
--   填充条（pfUI 材质 + 顶点色）+ 当前能量数值（右对齐、带黑色阴影）
--   + 回能指示器（CastingBar 光晕 + 2px 白色实线，随回能节奏从左向右扫）
-- 位置默认固定在屏幕下方（与 light 档一致）；在解锁模式里单独拖过之后
-- 以 C.position["pfEnergyBar"] 为准（pfUI 老规矩：存档永远赢）。
-- 帧名从 pfComboEnergy 改成 pfEnergyBar：解锁界面会去掉 "pf" 前缀显示，
-- 原来会写成 "ComboEnergy"，拆分独立子页后已经不再依附连击点，名字也不该再带 Combo。
pfUI:RegisterModule("energybar", "vanilla:tbc", function ()
  local module = pfUI.energybar or {}
  pfUI.energybar = module

  local MAX_COMBO   = 5
  local SPEED       = 200          -- 平滑动画速度（能量/秒），与参考插件一致
  local TICK_BASE   = 2.0          -- 基础回能间隔（秒）
  local TICK_MIN    = 0.5          -- 回能间隔下限（秒）
  local DEF_TEXTURE = "Interface\\AddOns\\pfUI-CustomMedia\\bars\\pfUI-F.tga"

  -- 没有连击点的职业（法/战/牧/猎…）默认按这套几何走，与 light 档「最爱扎你」一致：
  --   宽度 = 连击点整排宽（40.5 x 5 + 间距 3 x 4 = 214.5）、位置 = BOTTOM 上方 282。
  local DEFAULT_WIDTH = 214.5
  local DEFAULT_Y     = 282

  -- 连击点只对这三家有数据源（combopoints 模块也只给它们注册事件），其余职业
  -- 的 pfCombo1..5 永远不显示 —— 跟随它算出来的宽度（6x5+3*4=42）毫无意义。
  --
  -- ⛔ 不能直接用第二个返回值比较：中文客户端的 UnitClass 两个返回值都可能是
  --    「盗贼/德鲁伊」这种本地化串。优先查 pfUI_locale 的 class 映射（本地化→英文
  --    token），拿不到再退回 UnitClass 的两个返回值。也**不要缓存**到文件级 ——
  --    模块加载那一刻玩家信息不一定就绪，缓存成 false 就永久失效了。
  local function HasCombo()
    local cname, ctoken = UnitClass("player")
    local cls = ctoken

    local loc = pfUI_locale and pfUI_locale[GetLocale()]
    if loc and loc["class"] and cname and loc["class"][cname] then
      cls = loc["class"][cname]
    end

    return cls == "DRUID" or cls == "ROGUE" or cls == "PALADIN"
        or cname == "DRUID" or cname == "ROGUE" or cname == "PALADIN"
  end

  local frame, bar, text, textshadow, tick, spark, sparkcore
  local textalign = "center"               -- left / center / right（默认居中，必须先于 ApplyTextAnchor 声明）

  -- 文字位置：左 / 居中 / 右（默认居中）。阴影跟着主文字走，只错开 0.5px。
  local function ApplyTextAnchor()
    text:ClearAllPoints()
    textshadow:ClearAllPoints()

    if textalign == "left" then
      text:SetPoint("LEFT", frame, "LEFT", 5, 0)
      textshadow:SetPoint("LEFT", frame, "LEFT", 5.5, -.5)
    elseif textalign == "right" then
      text:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
      textshadow:SetPoint("RIGHT", frame, "RIGHT", -4.5, -.5)
    else
      text:SetPoint("CENTER", frame, "CENTER", 0, 0)
      textshadow:SetPoint("CENTER", frame, "CENTER", .5, -.5)
    end
  end

  -- 外观缓存：UpdateConfig 写入，绘制/OnUpdate 只读
  local enabled, showtext, showtick = false, true, true
  local allpower, autocolor = true, true   -- 任意资源类型都显示 / 按资源类型自动着色
  local showborder, smooth = true, true
  local fixedwidth, height, offx, offy = 0, 12, 0, -4   -- fixedwidth 见 UpdateConfig（默认 DEFAULT_WIDTH）
  local textformat = 0                     -- 0 = 当前值, 1 = 当前/最大, 2 = 百分比

  -- 自动隐藏状态（打包成一个表，避免给 UpdateConfig 加太多 upvalue）
  local autohide = { on = false, time = 3, combat = true, full = false, timer = nil, alpha = 1 }

  -- 德鲁伊变形时附加的基础法力条（同样打包，省 upvalue）
  local manacfg = { on = false, height = 6, isDruid = false, bar = nil, fill = nil, text = nil }
  local fontsize = 12
  local texture  = DEF_TEXTURE
  local color    = { .8, .77, .33, 1 }
  local bgcolor  = { 0, 0, 0, .4 }
  local textcolor = { 1, 1, 1, 1 }
  local lastptype = -1                     -- 上一次的资源类型（自动着色只在切换时重绘）

  -- 运行状态
  local displayed = 0              -- 平滑后的显示能量
  local inited     = false         -- 是否已经用真实值初始化过（能量为 0 时不能重复初始化）
  local lastenergy = 0             -- 上一次读到的真实能量（检测回能）
  local lastgain   = 0             -- 最后一次回能的时刻
  local lastvalue  = -1            -- 上一次写入的文字值（避免每帧 SetText）
  local incombat   = false
  local tickrate   = TICK_BASE

  -- "r,g,b,a" → 四个分量；非法/缺失时整套回退（运行期写入的配置值一律守卫）
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

  -- 回能间隔：Turtle 的敏捷回能天赋（2 系 16 项）按敏捷缩短间隔。
  -- 其他客户端同一槽位可能是别的天赋，所以整体 pcall，出错或没学就按基础 2 秒。
  local function UpdateTickRate()
    local rate = TICK_BASE

    local ok, _, _, _, _, rank = pcall(GetTalentInfo, 2, 16)
    if ok and rank and rank > 0 then
      local agility = UnitStat("player", 2)
      if agility and agility > 0 then
        rate = TICK_BASE - agility * (0.0006 * rank)
        if rate < TICK_MIN then rate = TICK_MIN end
      end
    end

    tickrate = rate
  end

  -- 连击点的增长方向：决定能量条该有多宽、贴在整排的哪一侧
  local function ComboGrow()
    return C.unitframes.combogrow or "right"
  end

  -- 宽度：固定值 > 0 时用它，否则跟随连击点整排宽度
  --   横排（right/left）= 单格宽 x 5 + 间距 x 4；
  --   竖排（up/down）= 单格宽（此时整排的"宽度"就是一格）；
  --   没有连击点的职业恒定用 DEFAULT_WIDTH（跟随模式对它们没意义）。
  local function GetBarWidth()
    if fixedwidth > 0 then return fixedwidth end

    if not HasCombo() then return DEFAULT_WIDTH end

    local combo = pfUI.combopoints
    local first = combo and combo.points and combo.points[1]
    local cw = first and first:GetWidth() or 6
    local cs = GetNumber("combospacing", 3)

    local w
    local grow = ComboGrow()
    if grow == "up" or grow == "down" then
      w = cw
    else
      w = cw * MAX_COMBO + cs * (MAX_COMBO - 1)
    end

    if w < 20 then w = 20 end
    return w
  end

  -- 位置：存档优先 → 固定宽度/无连击点职业用固定屏幕位置 → 否则贴连击点整排
  local function ApplyAnchor()
    -- ⛔ 拖动中一次 SetPoint 都不能调（1.12 会打断 StartMoving ⇒「按住拖不动」）。
    -- unlock 的 DragStart 会给被拖的帧置 frame.dragging，松手/中键/退出解锁都会清掉。
    if frame and frame.dragging then return end

    local saved = C.position and C.position["pfEnergyBar"]

    frame:ClearAllPoints()

    if saved and saved.xpos and saved.ypos then
      -- 纯按存档落位；底部堆叠由 UpdateConfig 末尾的 AlignAll() 统一接管
      frame:SetPoint(saved.anchor or "BOTTOM", saved.xpos, saved.ypos)
      frame:SetScale(saved.scale or 1)
      return
    end

    frame:SetScale(1)

    -- 固定宽度模式（或没有连击点的职业）：位置也固定，不跟连击点走 ——
    -- 这样换职业开出来是同一个位置，与 light 档的 pfEnergyBar 坐标一致。
    if fixedwidth > 0 or not HasCombo() then
      frame:SetPoint("BOTTOM", UIParent, "BOTTOM", offx, DEFAULT_Y)
      return
    end

    local combo = pfUI.combopoints
    local points = combo and combo.points
    local first = points and points[1]

    if first then
      -- 竖排时整排的"末端"才是贴着能量条的那一格：
      -- down 往下长 -> 末端是第 5 格（最下）；up 往上长 -> 末端也是第 5 格（最上）。
      if ComboGrow() == "up" then
        frame:SetPoint("BOTTOMLEFT", points[MAX_COMBO], "TOPLEFT", offx, -offy)
      elseif ComboGrow() == "down" then
        frame:SetPoint("TOPLEFT", points[MAX_COMBO], "BOTTOMLEFT", offx, offy)
      else
        frame:SetPoint("TOPLEFT", first, "BOTTOMLEFT", offx, offy)
      end
    else
      frame:SetPoint("CENTER", UIParent, "CENTER", offx, -120 + offy)
    end
  end

  local function ApplyGeometry()
    local w = GetBarWidth()

    frame:SetWidth(w)
    frame:SetHeight(height)

    bar:SetHeight(height)
    bar:SetWidth(w)

    if tick then
      -- 光点比条略大：「头像框那种光晕」而不是一根和条等高的细线
      spark:SetHeight(height + 8)
      spark:SetWidth(height + 4)
      sparkcore:SetHeight(height)
    end

    if manacfg.bar then
      manacfg.bar:ClearAllPoints()
      manacfg.bar:SetPoint("TOP", frame, "BOTTOM", 0, -2)
      manacfg.bar:SetWidth(w)
      manacfg.bar:SetHeight(manacfg.height)
      manacfg.fill:SetHeight(manacfg.height)
      manacfg.fill:SetWidth(w)

      if not manacfg.on or not manacfg.isDruid then manacfg.bar:Hide() end
    end

    ApplyAnchor()
  end

  -- 填充上色。autocolor 开启时按资源类型取 unitframes 里已有的三档资源色
  -- （Mana / Rage / Energy Color），关闭时用固定的 comboenergycolor。
  -- ⚠️ 两套互斥：纯色 = SetTexture(r,g,b,a) + 顶点色归白；材质 = SetTexture(path) + 顶点色。
  --    只做一套会在切回纯色时被上一轮顶点色二次染色（combopoints 里踩过同一个坑）。
  local function PaintBar(ptype)
    local c

    if autocolor then
      if ptype == 1 then
        c = { ParseColor(C.unitframes.ragecolor, 1, .5, .5, 1) }
      elseif ptype == 3 then
        c = { ParseColor(C.unitframes.energycolor, 1, 1, .5, 1) }
      else
        c = { ParseColor(C.unitframes.manacolor, .5, .5, 1, 1) }
      end
    else
      c = color
    end

    if texture == "solid" or texture == "" then
      bar:SetTexture(c[1], c[2], c[3], c[4])
      bar:SetVertexColor(1, 1, 1, 1)
    else
      bar:SetTexture(texture)
      bar:SetVertexColor(c[1], c[2], c[3], c[4])
    end
  end

  local function ApplyStyle()
    if frame.bg then
      frame.bg:SetTexture(bgcolor[1], bgcolor[2], bgcolor[3], bgcolor[4])
    end

    if frame.edges then
      for i = 1, table.getn(frame.edges) do
        if showborder then frame.edges[i]:Show() else frame.edges[i]:Hide() end
      end
    end

    PaintBar(lastptype)

    ApplyTextAnchor()

    if manacfg.bar then
      -- 附条材质跟主条走；纯色模式下用白底 + 顶点色（颜色在 OnUpdate 里按 manacolor 刷）
      if texture == "solid" or texture == "" then
        manacfg.fill:SetTexture(1, 1, 1, 1)
        manacfg.fill:SetVertexColor(1, 1, 1, 1)
      else
        manacfg.fill:SetTexture(texture)
      end

      -- 文字对齐跟主条同一设置（左/居中/右）
      manacfg.text:ClearAllPoints()
      if textalign == "left" then
        manacfg.text:SetPoint("LEFT", manacfg.bar, "LEFT", 5, 0)
      elseif textalign == "right" then
        manacfg.text:SetPoint("RIGHT", manacfg.bar, "RIGHT", -5, 0)
      else
        manacfg.text:SetPoint("CENTER", manacfg.bar, "CENTER", 0, 0)
      end

      manacfg.text:SetFont(pfUI.font_default, fontsize - 2, "OUTLINE")
      manacfg.text:SetTextColor(1, 1, 1, 1)
    end

    text:SetFont(pfUI.font_default, fontsize, "OUTLINE")
    text:SetTextColor(textcolor[1], textcolor[2], textcolor[3], textcolor[4])
    textshadow:SetFont(pfUI.font_default, fontsize, "OUTLINE")
    textshadow:SetTextColor(0, 0, 0, 1)

    -- 格式/字号变了要允许重写文字（lastvalue 是「上次写入的值」缓存）
    lastvalue = nil

    if showtext then
      text:Show()
      textshadow:Show()
    else
      text:Hide()
      textshadow:Hide()
    end

    if not showtick and tick:IsShown() then tick:Hide() end
  end

  local function CreateBar()
    frame = CreateFrame("Frame", "pfEnergyBar", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetHeight(height)
    frame:Hide()

    -- 背景（参考插件：纯黑 40% 透明）
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetTexture(0, 0, 0, .4)

    -- 1px 黑边框，四条独立纹理（与参考插件一致，不依赖 CreateBackdrop 的像素对齐）
    -- 存进 frame.edges 以便「显示边框」开关能整组收放
    frame.edges = {}

    local function Edge(top, bottom)
      local t = frame:CreateTexture(nil, "OVERLAY")
      t:SetTexture(0, 0, 0, .8)
      if top then
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
      else
        t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
      end
      t:SetHeight(1)
      frame.edges[table.getn(frame.edges) + 1] = t
    end

    local function Side(left)
      local t = frame:CreateTexture(nil, "OVERLAY")
      t:SetTexture(0, 0, 0, .8)
      if left then
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", -1, 1)
        t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -1, -1)
      else
        t:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 1, 1)
        t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 1, -1)
      end
      t:SetWidth(1)
      frame.edges[table.getn(frame.edges) + 1] = t
    end

    Edge(true)
    Edge(false)
    Side(true)
    Side(false)

    -- 填充：左对齐，宽度按能量百分比缩放
    bar = frame:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("LEFT", frame, "LEFT", 0, 0)
    bar:SetHeight(height)

    -- 数值阴影（先画，压在文字下面）
    textshadow = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    textshadow:SetPoint("RIGHT", frame, "RIGHT", -4.5, -.5)
    textshadow:SetTextColor(0, 0, 0, 1)

    text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("RIGHT", frame, "RIGHT", -5, 0)
    text:SetTextColor(1, 1, 1, 1)

    -- 回能指示器：光晕与能量条等高，叠加一条 2px 实线补齐光晕两端渐隐
    tick = CreateFrame("Frame", nil, frame)
    tick:SetAllPoints(frame)
    tick:Hide()

    spark = tick:CreateTexture(nil, "OVERLAY")
    spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    spark:SetHeight(height + 8)
    spark:SetWidth(height + 4)
    spark:SetBlendMode("ADD")
    spark:SetPoint("LEFT", tick, "LEFT", -10, 0)

    sparkcore = tick:CreateTexture(nil, "OVERLAY")
    sparkcore:SetTexture(1, 1, 1, 1)
    sparkcore:SetWidth(2)
    sparkcore:SetHeight(height)
    sparkcore:SetPoint("CENTER", spark, "CENTER", 0, 0)
    sparkcore:SetBlendMode("ADD")

    -- 德鲁伊变形时附加的基础法力条（挂在能量条下面，默认隐藏）
    local mbar = CreateFrame("Frame", nil, frame)
    mbar:Hide()

    mbar.bg = mbar:CreateTexture(nil, "BACKGROUND")
    mbar.bg:SetAllPoints(mbar)
    mbar.bg:SetTexture(0, 0, 0, .4)

    mbar.fill = mbar:CreateTexture(nil, "ARTWORK")
    mbar.fill:SetPoint("LEFT", mbar, "LEFT", 0, 0)

    mbar.text = mbar:CreateFontString(nil, "OVERLAY")

    manacfg.bar, manacfg.fill, manacfg.text = mbar, mbar.fill, mbar.text
  end

  -- 开启能量条时，这几块要上移让位（相对位移，保留玩家自己拖过的位置）：
  --   连击点整排(pfCombo1) / 距离指示器 / 目标仇恨框。
  -- 关掉能量条时还原 —— 所以「未开启」时它们就停在 light 档的原始坐标。
  local LINKED = { "pfCombo1", "pfDistanceIndicator", "pfTargetThreat" }
  local shiftApplied = {}          -- name -> 当前已叠加的位移（unlock 拖动后要用它换算回原始值）

  -- 「底部对齐」= 自下而上堆叠：能量条 → 连击点 → 距离指示器 → 仇恨框。
  -- 最下面那块（当前显示的）底边贴玩家框底边，上面的依次 +自身高度 + 间隙，
  -- 所以永远不会叠在一起。关掉下面的块，上面的整体落下来。
    -- 注意：仇恨框不在 STACK 里 —— 它和距离指示器**同一 Y**（横向错开），
  -- 不额外往上叠。参见 AlignAll 里的 distY。
  local STACK = { "pfEnergyBar", "pfCombo1", "pfDistanceIndicator" }

  -- 没有 position 条目时的兜底横向位置（取自 light 档）。
  -- 解锁模式按「重置」会把整条 position 删掉，缺了条目原本就会被堆叠跳过 ——
  -- 表现就是「仇恨模块不生效」。这里补一条，让它永远能入栈。
  local FALLBACK_X = {
    pfEnergyBar = 0,
    pfCombo1 = -87,
    pfDistanceIndicator = 0,
    pfTargetThreat = 80,
  }

  -- ⛔ 别只用 _G[name]：仇恨框在 target.lua 里创建，某些加载路径下全局名拿不到
  --    （表现就是「它好高、完全不参与堆叠」）。注册过 movables 的一律从那里兜底。
  local function StackFrame(name)
    local f = _G[name]
    if f then return f end

    local movables = pfUI.movables
    if movables and movables[name] then return movables[name] end

    return nil
  end

  local function AlignMode()
    return C.unitframes.bottomalign ~= "0"
  end

  -- 该块为什么不占位（诊断也用它，能直接看出是「配置关」还是「职业没有连击点」）
  --   on / off / noclass
  local function StackReason(name)
    if name == "pfEnergyBar" then
      return C.unitframes.comboenergyshow == "1" and "on" or "off"
    elseif name == "pfCombo1" then
      -- 没有连击点的职业（法/战/牧…）这排永远不显示，不该给下面的块留下空档
      if not HasCombo() then return "noclass" end
      return C.unitframes.comboshow ~= "0" and "on" or "off"
    elseif name == "pfDistanceIndicator" then
      return C.unitframes.distance_indicator == "1" and "on" or "off"
    elseif name == "pfTargetThreat" then
      -- 仇恨框没有独立开关：有目标就画，所以恒定占位（它在链的最上层，
      -- 不占位也不会影响下面任何一块）
      return "on"
    end

    return "off"
  end

  -- 实际占用高度：距离框的宠物行是运行时加的第二行，SetHeight 只在 OnUpdate 里
  -- 更新，布局瞬间可能还是旧值 —— 按内容兜一次底，否则堆叠会算矮、压到下面一块。
  local function StackHeight(f, name)
    local h = f:GetHeight() or 0

    if name == "pfDistanceIndicator" and f.text and f.petText and f.petText:IsShown() then
      local off = math.abs(tonumber(C.unitframes.distance_indicator_pet_offset_y) or 20)
      local need = (f.text:GetHeight() or 0) + off + (f.petText:GetHeight() or 0)
      if need > h then h = need end
    end

    return h
  end

  local function StackShown(name)
    return StackReason(name) == "on"
  end

  local function AlignAll()
    if not AlignMode() then return end

    local player = pfUI.uf and pfUI.uf.player
    if not player then return end

    -- 玩家框底边，与 position 里的 ypos 同轴。
    -- ⛔ 不要除以 UIParent:GetScale()：本客户端 GetBottom() 已经是 UIParent 坐标，
    --    再除一次会把整排抬高 1/scale 倍（实测 300 → 369）。
    local base = player:GetBottom()
    if not base then return end          -- 玩家框没就绪

    local gap = GetNumber("bottomalign_gap", 3)
    if gap < 0 then gap = 0 end

    local y = 0
    local distY                 -- 距离指示器的「相对底边偏移」（仇恨与它同高）

    for i = 1, table.getn(STACK) do
      local name = STACK[i]
      local f = StackFrame(name)
      local pos = C.position and C.position[name]

      -- position 条目被「重置」删掉后补一条兜底，否则这块永远进不了堆叠
      if not pos and C.position and FALLBACK_X[name] then
        C.position[name] = { anchor = "BOTTOM", xpos = FALLBACK_X[name] }
        pos = C.position[name]
      end

      -- 「手动摆过 = 退出堆叠」：pos.manual 是玩家在解锁模式里拖过 / 用方向键或坐标框
      -- 改过位置的标记（unlock.lua 写入）。它一旦存在就整块跳过 —— **也不推进 y 游标**，
      -- 于是上面的块整体落下来补位（跟「关掉下面的块，上面的落下来」同一套语义）。
      -- f.dragging = 正在被拖动（unlock 的 DragStart 置位）：此时绝不能 SetPoint，
      -- 那会打断 1.12 的 StartMoving 状态，表现为「按住拖不动、一放就弹回」。
      -- 中键重置会用模板重建 position 条目（manual 自然消失）⇒ 重新入栈；
      -- GUI「重新对齐」走 ClearManual 一键全部回收。
      if f and pos and StackShown(name) and pos["manual"] ~= "1" and not f.dragging then
        local anchor = pos.anchor or "BOTTOM"
        local h = StackHeight(f, name)

        -- ⛔ x 用各自的存档值（绝对坐标），**不要**拿它和头像框的 xpos 相减。
        --    头像框可能是 BOTTOMLEFT/TOPLEFT 之类角锚点（xpos 从屏幕左边算），
        --    与 BOTTOM/CENTER 的「相对中心」语义不同，相减会算出巨量偏移
        --    —— 表现就是「能量条跑到屏幕最左边」。y 仍然相对头像框底边堆叠。
        local ay = base + y

        if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
          ay = base + y + h
        elseif anchor == "LEFT" or anchor == "CENTER" or anchor == "RIGHT" then
          ay = base + y + h / 2
        end

        f:ClearAllPoints()
        if pos.scale then f:SetScale(pos.scale) end
        f:SetPoint(anchor, pos.xpos or 0, ay)

        -- 把实际位置写回存档，解锁面板的 X/Y 就反映真实位置
        pos.ypos = math.floor(ay + .5)

        if name == "pfDistanceIndicator" then distY = y end

        y = y + h + gap
      end
    end

    -- 仇恨框：底边跟距离一样（横向靠 xpos 错开），距离关掉时落到当前游标
    local threat = StackFrame("pfTargetThreat")
    local tpos = C.position and C.position["pfTargetThreat"]

    if not tpos and C.position and FALLBACK_X["pfTargetThreat"] then
      C.position["pfTargetThreat"] = { anchor = "BOTTOM", xpos = FALLBACK_X["pfTargetThreat"] }
      tpos = C.position["pfTargetThreat"]
    end

    if threat and tpos and tpos["manual"] ~= "1" and not threat.dragging then
      local anchor = tpos.anchor or "BOTTOM"
      local th = threat:GetHeight() or 0
      local ty = distY or y
      local tay = base + ty

      if anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT" then
        tay = base + ty + th
      elseif anchor == "LEFT" or anchor == "CENTER" or anchor == "RIGHT" then
        tay = base + ty + th / 2
      end

      threat:ClearAllPoints()
      if tpos.scale then threat:SetScale(tpos.scale) end
      threat:SetPoint(anchor, tpos.xpos or 0, tay)

      tpos.ypos = math.floor(tay + .5)
    end
  end

  -- 让这几个模块重新按 C.position 落位。
  -- ⛔ 不能调 combopoints:UpdateConfig()：它已被本模块链式包装过，
  --    会反过来再触发 energybar 的 UpdateConfig ⇒ 无限递归。
  local function ReapplyLinked()
    local combo = _G["pfCombo1"]
    if combo then UpdateMovable(combo) end

    local dist = pfUI.distanceIndicator
    if dist then UpdateMovable(dist) end

    -- 仇恨框自己读一次 C.position 落位
    local threat = StackFrame("pfTargetThreat")
    local pos = C.position and C.position["pfTargetThreat"]
    if threat and pos and pos.ypos then
      threat:ClearAllPoints()
      threat:SetScale(pos.scale or 1)
      threat:SetPoint(pos.anchor or "TOPLEFT", pos.xpos, pos.ypos)
    end

    -- 最后统一做底部对齐（四块的底边 == 玩家框底边）
    AlignAll()
  end

  local function SetLinkedShift(on)
    local shift = GetNumber("comboenergyshift", 20)
    if shift < 0 then shift = 0 end

    -- 底部对齐模式不需要让位（也没有意义：各块本来就贴着同一条底边），
    -- 但要先把之前可能叠加过的位移还原，避免残留偏移。
    if AlignMode() then on = false end

    for i = 1, table.getn(LINKED) do
      local name = LINKED[i]
      local pos = C.position and C.position[name]

      -- 没有位置存档的模块不动（免得把「跟随父框」的默认布局改成绝对坐标）
      if pos and pos.ypos then
        if on then
          if pos.ypos_off == nil then pos.ypos_off = pos.ypos end
          pos.ypos = pos.ypos_off + shift
          shiftApplied[name] = shift
        elseif pos.ypos_off ~= nil then
          pos.ypos = pos.ypos_off
          pos.ypos_off = nil
          shiftApplied[name] = nil
        end
      end
    end

    ReapplyLinked()
  end

  local stackBusy = false

  -- 对外的「重排」入口。带递归保护：ReapplyLinked 里会调 UpdateMovable，
  -- 而 UpdateMovable 完成后会回调本函数 —— 没有这个闸门会无限套娃。
  function module:RefreshLayout()
    if stackBusy then return end
    stackBusy = true
    AlignAll()
    stackBusy = false
  end

  -- 供 pfUI.api.UpdateMovable 回调：某个模块重新落位后，重新算一遍堆叠。
  function module:OnMovableUpdated(name)
    -- 玩家框是整排的基准（base = player:GetBottom()），它一动必须重排，
    -- 否则拖动头像框后能量条/连击点/距离会停在原地，等下次 AlignAll 才跟上。
    if name == "pfPlayer" then
      module:RefreshLayout()
      return
    end

    for i = 1, table.getn(STACK) do
      if STACK[i] == name then
        module:RefreshLayout()
        return
      end
    end
  end

  -- 标记「这个块被玩家手动摆过」→ 退出底部堆叠（AlignAll 会跳过它）。
  -- 由 unlock.lua 在：拖动停止 / 方向键 / dock 坐标框改值 时调用，只对堆叠成员生效。
  -- ⚠️ 标记写进 C.position[name]（就是存档字段）⇒ /reload 后依然退出堆叠；
  --    而「加载 profile」是整份替换 C（gui.lua:1562）、「中键重置」是用模板重建 position
  --    条目（unlock.ResetFramePosition），两者都会让 manual 自动消失 ⇒ 重新参与堆叠。
  function module:MarkManual(name)
    if not name then return end

    local member = (name == "pfTargetThreat")

    if not member then
      for i = 1, table.getn(STACK) do
        if STACK[i] == name then
          member = true
          break
        end
      end
    end

    if not member then return end

    -- ⚠️ 必须容忍「还没有 position 条目」的情况：unlock 里标记是**先于** SavePosition
    --    调用的（顺序反了会被 AlignAll 当场拉回堆叠位），此时块可能从未存过位置。
    --    先建一条含兜底 x/anchor 的条目，紧接着的 SavePosition 会补齐 xpos/ypos/anchor。
    local pos = C.position and C.position[name]

    if not pos then
      pos = {}
      C.position[name] = pos

      if FALLBACK_X[name] then
        pos["anchor"] = "BOTTOM"
        pos["xpos"]   = FALLBACK_X[name]
      end
    end

    pos["manual"] = "1"
  end

  -- 回收所有 manual 标记（让手动摆过的块重新参与堆叠）+ 立即重排。
  -- GUI 的「重新对齐」按钮调它；中键逐个重置是另一条路径（模板重建条目）。
  function module:ClearManual()
    local names = { "pfEnergyBar", "pfCombo1", "pfDistanceIndicator", "pfTargetThreat" }

    for i = 1, table.getn(names) do
      local pos = C.position and C.position[names[i]]
      if pos then pos.manual = nil end
    end

    module:RefreshLayout()
  end

  function module:UpdateConfig()
    -- 默认关闭：用 == "1" 而不是 ~= "0"，否则缺键时会被当成「开启」
    enabled    = C.unitframes.comboenergyshow == "1"
    showtext   = C.unitframes.comboenergyshowtext ~= "0"
    showtick   = C.unitframes.comboenergyshowtick ~= "0"
    allpower   = C.unitframes.comboenergyallpower ~= "0"
    autocolor  = C.unitframes.comboenergyautocolor ~= "0"
    showborder = C.unitframes.comboenergyborder ~= "0"
    smooth     = C.unitframes.comboenergysmooth ~= "0"
    fixedwidth = GetNumber("comboenergywidth", DEFAULT_WIDTH)
    height     = GetNumber("comboenergyheight", 12)
    offx       = GetNumber("comboenergyoffx", 0)
    offy       = GetNumber("comboenergyoffy", -4)
    fontsize   = GetNumber("comboenergyfontsize", 12)
    textformat = GetNumber("comboenergytextformat", 0)
    textalign  = C.unitframes.comboenergytextalign or "center"

    manacfg.on     = C.unitframes.comboenergydruidmana == "1"
    manacfg.height = GetNumber("comboenergydruidmanaheight", 6)
    if manacfg.height < 2 then manacfg.height = 2 end

    -- ⛔ 中文客户端 UnitClass 两个返回值都可能是「德鲁伊」，必须走 pfUI_locale 映射
    do
      local cname, ctoken = UnitClass("player")
      local loc = pfUI_locale and pfUI_locale[GetLocale()]
      local cls = ctoken

      if loc and loc["class"] and cname and loc["class"][cname] then
        cls = loc["class"][cname]
      end

      manacfg.isDruid = (cls == "DRUID" or cname == "DRUID")
    end

    autohide.on     = C.unitframes.comboenergyauthide == "1"
    autohide.time   = GetNumber("comboenergyhidetime", 3)
    autohide.combat = C.unitframes.comboenergyhidecombat ~= "0"
    autohide.full   = C.unitframes.comboenergyhidefull == "1"

    if autohide.time < 0 then autohide.time = 0 end
    if not autohide.on then
      autohide.timer, autohide.alpha = nil, 1
    end

    if textalign ~= "left" and textalign ~= "right" then textalign = "center" end
    texture    = C.unitframes.comboenergytexture or DEF_TEXTURE

    if height < 4 then height = 4 end
    if fontsize < 6 then fontsize = 6 end
    if textformat < 0 or textformat > 2 then textformat = 0 end

    color     = { ParseColor(C.unitframes.comboenergycolor, .8, .77, .33, 1) }
    bgcolor   = { ParseColor(C.unitframes.comboenergybgcolor, 0, 0, 0, .4) }
    textcolor = { ParseColor(C.unitframes.comboenergytextcolor, 1, 1, 1, 1) }

    -- 外观变了要让自动着色重算一次（否则改完颜色配置得等切换形态才生效）
    lastptype = UnitPowerType("player") or 0

    ApplyGeometry()
    ApplyStyle()

    if not enabled then frame:Hide() end

    -- 开启时让连击点 / 距离 / 仇恨整体上移，关闭时还原到 light 档原位
    SetLinkedShift(enabled)
  end

  -- 每帧更新：启用且（任意资源类型，或只认能量形态）时显示
  --   德鲁伊人形态是法力、猫形态是能量，靠 UnitPowerType 自动识别；
  --   allpower 关闭时退回「只在能量形态显示」的旧行为。
  local function OnUpdate()
    if not enabled or not frame then return end

    local ptype = UnitPowerType("player") or 0

    if not allpower and ptype ~= 3 then
      if frame:IsShown() then frame:Hide() end
      return
    end

    if not frame:IsShown() then frame:Show() end

    -- 资源类型变了（变形/姿态切换）→ 自动着色跟着换
    if ptype ~= lastptype then
      lastptype = ptype
      PaintBar(ptype)
    end

    local dt = arg1 or 0
    if dt > .25 then dt = .25 end              -- 掉帧/切窗口回来时不要一步跳到底

    local cur = UnitMana("player") or 0
    local max = UnitManaMax("player") or 0
    if max < 1 then max = 1 end

    if not inited then
      displayed = cur
      inited = true
    elseif displayed > max then
      displayed = max
    end

    -- 平滑插值：文字用真实值，只有填充条走动画（关掉平滑时直接跟随）
    local diff = cur - displayed
    if not smooth then
      displayed = cur
    elseif diff ~= 0 then
      local step = SPEED * dt

      if diff > 0 then
        displayed = displayed + math.min(step, diff)
      else
        displayed = displayed + math.max(-step, diff)
      end

      if math.abs(cur - displayed) < .1 then displayed = cur end
    end

    local w = frame:GetWidth() or 1
    bar:SetWidth(w * displayed / max)

    -- 德鲁伊变形时在下方附一条基础法力（变形后 UnitMana 是能量/怒气，
    -- 法力只能从 Nampower 的 GetUnitField 的 power1 槽读）
    local mbar = manacfg.bar
    if mbar then
      local showMana = manacfg.on and manacfg.isDruid and ptype ~= 0 and GetUnitField

      if showMana then
        local _, guid = UnitExists("player")
        local mcur = guid and GetUnitField(guid, "power1")
        local mmax = guid and GetUnitField(guid, "maxPower1")

        if type(mcur) == "number" and type(mmax) == "number" and mmax > 0 then
          local mc = { ParseColor(C.unitframes.manacolor, .5, .5, 1, 1) }
          mbar.fill:SetVertexColor(mc[1], mc[2], mc[3], mc[4])
          mbar.fill:SetWidth(w * mcur / mmax)
          -- 文字格式跟主条同一个设置（当前值 / 当前/最大 / 百分比）；
          -- 主条关掉「显示数值」时附条也不显示文字
          local mvalue = ""

          if showtext then
            if textformat == 1 then
              mvalue = string.format("%d/%d", math.floor(mcur + .5), math.floor(mmax + .5))
            elseif textformat == 2 then
              mvalue = string.format("%d%%", math.floor(mcur / mmax * 100 + .5))
            else
              mvalue = string.format("%d", math.floor(mcur + .5))
            end
          end

          mbar.text:SetText(mvalue)
          if not mbar:IsShown() then mbar:Show() end
        elseif mbar:IsShown() then
          mbar:Hide()
        end
      elseif mbar:IsShown() then
        mbar:Hide()
      end

    end

    if showtext then
      local value

      if textformat == 1 then
        value = string.format("%d/%d", math.floor(cur + .5), math.floor(max + .5))
      elseif textformat == 2 then
        value = string.format("%d%%", math.floor(cur / max * 100 + .5))
      else
        value = string.format("%d", math.floor(cur + .5))
      end

      if value ~= lastvalue then
        lastvalue = value
        text:SetText(value)
        textshadow:SetText(value)
      end
    end

    -- 自动隐藏：逻辑同头像框（unitframes.lua 的 AUTOHIDE 段）。
    -- 只在这里算 alpha，真正 SetAlpha 在下面统一做。
    local now = GetTime()
    local target_alpha = 1

    if autohide.on then
      local inCombat = UnitAffectingCombat("player")
      local full = cur >= max
      local changed = cur ~= lastenergy

      -- 战斗中 / 能量刚变过 / 满能量但不要求满能量隐藏 -> 重置计时
      if inCombat or changed or (full and not autohide.full) then
        autohide.timer = nil
      elseif not autohide.timer then
        autohide.timer = now + autohide.time
      elseif now > autohide.timer then
        target_alpha = 0
      end

      -- 淡入淡出（帧率无关，同头像框那套）
      local fpsmod = (GetFramerate and GetFramerate() or 30) / 30
      local fade = 0.05 * fpsmod

      if autohide.alpha < target_alpha then
        autohide.alpha = math.min(autohide.alpha + fade, target_alpha)
      elseif autohide.alpha > target_alpha then
        autohide.alpha = math.max(autohide.alpha - fade, target_alpha)
      end
    end

    frame:SetAlpha((pfUI.unlock and pfUI.unlock:IsShown()) and 1 or autohide.alpha)

    -- 回能预测：能量一涨就把「上次回能时刻」推到当前
    if cur > lastenergy then lastgain = now end
    lastenergy = cur

    local progress
    if showtick then
      -- 优先复用头像框那套 tick 相位（energytick 模块里实测校准过，
      -- 含 Blade Rush 的敏捷缩短与减速情况）——这样两处光点永远同步。
      local et = pfUI.energytick
      if et and et.EnergyProgress then
        progress = et:EnergyProgress()
      end

      -- 回退：energytick 未加载/尚未校准（刚登录还没吃到自然回能）时用粗算
      if not progress then
        local elapsed = now - lastgain

        if incombat then
          -- 战斗中循环扫描：无论是否满能量都持续显示下一次回能进度
          progress = math.mod(elapsed, tickrate) / tickrate
        elseif elapsed < tickrate then
          -- 脱战只在刚回能后播一次，播完隐藏
          progress = elapsed / tickrate
        end
      end
    end

    if progress then
      if not tick:IsShown() then tick:Show() end
      spark:SetPoint("LEFT", tick, "LEFT", w * progress - (height + 4) / 2, 0)
    elseif tick:IsShown() then
      tick:Hide()
    end
  end

  -- 旧帧名迁移：pfComboEnergy → pfEnergyBar（改名前的存档位置要接过来，
  -- 否则拖过的角色升级后会跳回默认位置）。只搬一次，旧键顺手清掉。
  if C.position and C.position["pfComboEnergy"] then
    if not C.position["pfEnergyBar"] then
      C.position["pfEnergyBar"] = C.position["pfComboEnergy"]
    end
    C.position["pfComboEnergy"] = nil
  end

  CreateBar()
  module:UpdateConfig()
  UpdateTickRate()


  -- 解锁模式里独立拖动：存档写回 C.position.pfEnergyBar
  UpdateMovable(frame)

  -- 拖动让位模块之后，把「拖动结果」换算回原始值，否则下一次 UpdateConfig
  -- 会用它记着的旧 ypos_off 把刚拖到的位置打回去。
  if pfUI.unlock then
    HookScript(pfUI.unlock, "OnHide", function()
      for i = 1, table.getn(LINKED) do
        local name = LINKED[i]
        local pos = C.position and C.position[name]
        local applied = shiftApplied[name]

        if pos and applied and pos.ypos_off then
          pos.ypos_off = pos.ypos - applied
        end
      end

      -- unlock 退出时会把每个 movable 按 C.position 的绝对坐标摆一遍
      -- （UpdateMovable），正好把堆叠结果冲掉 —— 必须在这里重新堆一次。
      module:RefreshLayout()
    end)
  end

  -- OnUpdate 必须挂在一个常驻可见的 frame 上：能量条自己在非能量形态下是隐藏的，
  -- 挂在它身上就再也醒不过来了。
  local updater = CreateFrame("Frame")
  updater:SetScript("OnUpdate", OnUpdate)

  -- 连击点的宽度/间距变化时同步能量条宽度（宽度跟随模式）。链式替换，保留原实现。
  local combo = pfUI.combopoints
  if combo and combo.UpdateConfig then
    local prev = combo.UpdateConfig
    combo.UpdateConfig = function()
      prev()
      module:UpdateConfig()
    end
  end

  local ev = CreateFrame("Frame")
  ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  ev:RegisterEvent("CHARACTER_POINTS_CHANGED")
  ev:RegisterEvent("UNIT_STATS")
  ev:RegisterEvent("PLAYER_REGEN_DISABLED")
  ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  ev:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
      incombat = UnitAffectingCombat("player") and true or false
      displayed = UnitMana("player") or 0
      inited = true
      lastenergy = displayed
      lastgain = GetTime()
      UpdateTickRate()
      module:UpdateConfig()

      -- 距离指示器由 unitxp 在更晚的时机创建：进世界时再排一次，
      -- 保证三块都能进堆叠（否则刚登录时距离会被漏掉）。
      module:RefreshLayout()
    elseif event == "CHARACTER_POINTS_CHANGED" then
      UpdateTickRate()
    elseif event == "UNIT_STATS" then
      if arg1 == "player" then UpdateTickRate() end
    elseif event == "PLAYER_REGEN_DISABLED" then
      incombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
      incombat = false
    end
  end)

  -- 诊断：/pfe 打印当前能量、上限、回能间隔与实际渲染参数
  _G["SLASH_PFENERGY1"] = "/pfe"
  _G["SLASH_PFENERGY2"] = "/pfenergy"
  _G["SlashCmdList"]["PFENERGY"] = function()
    local ptype = UnitPowerType("player") or 0
    local names = { [0] = "法力", [1] = "怒气", [2] = "集中", [3] = "能量" }

    DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "|cff33ff99energybar|r 资源=%s(%d) %d/%d 回能间隔=%.3fs 显示=%s",
      names[ptype] or "未知", ptype, UnitMana("player") or 0, UnitManaMax("player") or 0, tickrate,
      frame and (frame:IsShown() and "是" or "否") or "未创建"))
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "宽度=%.1f（%s） 高度=%d 偏移=(%d,%d) 格式=%d 自动着色=%s 全资源=%s 平滑=%s",
      GetBarWidth(), fixedwidth > 0 and "固定" or ("跟随连击点/" .. ComboGrow()),
      height, offx, offy, textformat,
      autocolor and "开" or "关", allpower and "开" or "关", smooth and "开" or "关"))
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "材质=%s 边框=%s 背景=%s", tostring(texture),
      showborder and "开" or "关",
      string.format("%.2f,%.2f,%.2f,%.2f", bgcolor[1], bgcolor[2], bgcolor[3], bgcolor[4])))

    -- 底部堆叠状态：缺帧 / 手动(manual) / 堆叠中 / 隐藏
    local parts = {}
    for i = 1, table.getn(STACK) do
      local name = STACK[i]
      local f = StackFrame(name)
      local pos = C.position and C.position[name]
      local state = "缺帧"

      if f then
        -- dragging 残留会让这块**永久**退出堆叠（AlignAll 的跳过条件之一），
        -- 所以诊断里单列一条，排查「怎么拖都不回堆叠」先看它。
        if f.dragging then
          state = "拖动中"
        elseif pos and pos.manual == "1" then
          state = "手动"
        else
          local reason = StackReason(name)
          if reason == "on" then
            state = "堆叠"
          elseif reason == "noclass" then
            state = "无连击点"
          else
            state = "关闭"
          end
        end
      end

      table.insert(parts, string.gsub(name, "^pf", "") .. "=" .. state)
    end

    -- 仇恨框不在 STACK 里（跟随距离的 Y），诊断单独补一条
    local tf = StackFrame("pfTargetThreat")
    table.insert(parts, "TargetThreat=" .. (tf and "同距离" or "缺帧"))

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99堆叠|r: " .. table.concat(parts, "  ")
      .. string.format("  gap=%d 对齐=%s", GetNumber("bottomalign_gap", 3), AlignMode() and "开" or "关"))

    -- 坐标轴自检 + 存档/实际对照：判断「为什么这么高」时看这一行
    local player = pfUI.uf and pfUI.uf.player
    local pb = player and player:GetBottom()

    DEFAULT_CHAT_FRAME:AddMessage(string.format(
      "|cff33ff99坐标轴|r 玩家框 GetBottom=%s  存档ypos=%s  UIParent缩放=%.3f",
      tostring(pb and math.floor(pb + .5)),
      tostring((C.position and C.position["pfPlayer"] or {}).ypos),
      UIParent:GetScale() or 1))

    local cmp = {}
    for i = 1, table.getn(STACK) do
      local name = STACK[i]
      local f = _G[name]
      local pos = C.position and C.position[name]
      local actual = f and f:GetBottom()

      table.insert(cmp, string.format("%s 存档%s/实际%s",
        string.gsub(name, "^pf", ""),
        tostring(pos and pos.ypos),
        tostring(actual and math.floor(actual + .5))))
    end

    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99位置|r: " .. table.concat(cmp, "  "))
  end
end)
