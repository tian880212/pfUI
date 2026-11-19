-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libglow ]]--
-- 边框流光 / 整块闪烁 / 边框呼吸（思路借鉴 EllesmereUI_Glows.lua）。
--
-- 为什么不照抄 EUI：
--   1.12 没有 maskTexture、没有 atlas、没有 flipbook、没有 AnimationGroup，
--   EUI 的"像素蚂蚁线"靠贴图 flipbook 推进，这里全部不可用。
--   所以退回 1.12 具备的三个物理量：位置、alpha、顶点色。
--     chase = 一条光带沿周长匀速跑，到拐角由下一条边接手
--             （每条边只画"落在自己内侧"的那一段，所以永远画不到框外）。
--             上色用 SetVertexColor（1.12 的 SetGradientAlpha 不传 RGB，见 ApplyChaseColor）。
--     flash = 整块覆盖层的 alpha 正弦闪烁，用于 proc / 冷却就绪提示。
--     pulse = 边框颜色呼吸，需要 frame.backdrop（pfUI 的按钮/图标都有）。
--
-- 成本模型（这点比观感更重要）：
--   * 没有任何手柄 Arm 时，libticker 里连 key 都不存在 ⇒ 0 开销。
--   * 有手柄时每帧 = 手柄数 × (4 次 SetPoint + 4 次 SetAlpha)；pulse 走 20Hz 自节流。
--   * 纹理在构造时一次性创建，Arm/Disarm 只改显隐和 alpha，不重建纹理。
--   * chase 是全套里最贵的（每帧 4 次 SetPoint 会触发 1.12 的布局重算），
--     实战里同时 arm 的数量建议 ≤ 8；几十个图标一起提示请用 pulse（只改颜色）
--     或 flash（只改 alpha），别在同一帧对几十个按钮跑 chase。
--
-- 用法：
--   local glow = pfUI.api.libglow
--   local h = glow:Chase(button, { color = {1, .82, .2}, thickness = 2, speed = 2.2 })
--   h:Arm()            -- 开始
--   h:Disarm()         -- 结束（纹理隐藏，订阅自动摘除）
--   h:SetColor(1, .2, .2)
--
-- ⛔ 生命周期归调用方：这里不做"到点自动停"。触发闪光那种一次性提示请自己
--    用 ticker:Once 或计时后 Disarm，否则它会一直转。
-- ⛔ pulse 会改 frame.backdrop 的边框色：Arm 时记下原色，Disarm 时还原。
--    1.12 没有"还原默认色"的通用接口，不记就会把图标永久留在警告色。
-- ⛔ 不要给 SetPoint 传 GetPoint() 的返回值（1.12 不可靠），这里全是绝对定位。
--
-- 诊断：/pfglow 列当前手柄；/pfglow demo [chase|flash|pulse] 在屏幕中央建一个
--    测试框；/pfglow off 收掉测试框。

-- return instantly when another libglow is already active
if pfUI.api.libglow then return end

local format = string.format
local sin, mod, pi = math.sin, math.mod, math.pi
local min = math.min
local getn = table.getn

local libglow = {}
pfUI.api.libglow = libglow
pfUI.glow = libglow

-- 当前已 arm 的手柄。换位删除（与 libticker 同一套），O(1) 摘除，
-- 代价是遍历里要重测当前槽（手柄可能在回调里 Disarm 自己）。
local handles = {}

local Tick, ChaseUpdate, FlashUpdate, PulseUpdate

-- [ ApplyChaseColor ]
-- ⛔⛔ 不要用 SetGradientAlpha 给流光上色：实测这个客户端只把 alpha 传了下去，
--    RGB 被忽略 —— 纯白纹理 + 金色渐变画出来仍然是**纯白**（症状："选了金色，流光一直白"）。
--    项目里其它 SetGradientAlpha 调用（afkcam / easteregg）传的全是黑色，所以这个坑一直没暴露。
--    改用 SetVertexColor：与 debuffmonitor 的 warn 边框同一条路径，已实测吃色。
-- 代价：光带内部没有"头亮尾暗"的渐变，靠外层 alpha 包络（见 ChaseUpdate 的 fa）做淡出。
-- 顶点色只在颜色变化时重设，不放进每帧路径。
local function ApplyChaseColor(h)
  local r, g, b = h.r, h.g, h.b
  local i
  for i = 1, 4 do
    h.tex[i]:SetVertexColor(r, g, b, 1)
  end
end

-- [ PlaceChase ]
-- a..b 是这段光带落在第 i 条边**内侧**的坐标（沿行进方向，0 = 这条边的起点）。
-- ⛔ 调用方必须保证 0 <= a < b <= 边长。超出边外的部分没有 mask 可以裁，
--    1.12 会把纹理原样画在框外 —— 症状就是"流光跑到图标外面去了"。
local function PlaceChase(h, i, a, b, w, hgt)
  local tex = h.tex[i]
  local k = h.thickness
  local span = b - a

  if span <= 0 then
    tex:SetAlpha(0)
    return
  end

  if i == 1 then
    -- 上边：左 → 右
    tex:SetWidth(span)
    tex:SetHeight(k)
    tex:SetPoint("TOPLEFT", h.frame, "TOPLEFT", a, 0)
  elseif i == 2 then
    -- 右边：上 → 下
    tex:SetWidth(k)
    tex:SetHeight(span)
    tex:SetPoint("TOPRIGHT", h.frame, "TOPRIGHT", 0, -a)
  elseif i == 3 then
    -- 下边：右 → 左（物理 x 从 w-b 到 w-a）
    tex:SetWidth(span)
    tex:SetHeight(k)
    tex:SetPoint("BOTTOMLEFT", h.frame, "BOTTOMLEFT", w - b, 0)
  else
    -- 左边：下 → 上（物理 y 从 h-b 到 h-a）
    tex:SetWidth(k)
    tex:SetHeight(span)
    tex:SetPoint("BOTTOMLEFT", h.frame, "BOTTOMLEFT", 0, hgt - b)
  end
end

ChaseUpdate = function(h, now)
  local f = h.frame

  -- ⛔ 隐藏帧直接跳过：chase 每帧 4 次 SetPoint 会触发布局重算，图标一旦 Hide
  --    （buff 到点消失、切换目标、动作条翻页）继续跑就是纯烧帧。IsShown 只看自身标志，
  --    父级隐藏时仍返回 true —— 够用：pfUI 里的图标都是自己被 Hide 的。
  if not f:IsShown() then return end

  local w, hgt = f:GetWidth(), f:GetHeight()

  -- 未布局/隐藏的 frame 拿不到真实尺寸：整组 alpha 归零，等下一次布局再说。
  if not w or not hgt or w < 6 or hgt < 6 then
    local i
    for i = 1, 4 do
      h.tex[i]:SetAlpha(0)
    end
    return
  end

  -- 周长，以及四条边的"起跑线"（沿行进方向：上 → 右 → 下 → 左）
  local per = 2 * (w + hgt)
  local off = { 0, w, w + hgt, 2 * w + hgt }
  local elen = { w, hgt, w, hgt }

  -- ⛔ 光带长度必须短于最短的边：否则同一时刻横跨两条边，看起来是"半圈在亮"
  --    而不是"一点在跑"。按短边 0.7 倍取，再夹在 [8, 36]。
  local len = min(w, hgt) * 0.7
  if len > 36 then len = 36 end
  if len < 8 then len = 8 end

  -- 一条光带沿周长跑：head 是亮端（头），tail 是暗端（尾）。
  -- 旧实现是四条边各跑一条、把负偏移当"淡入"画到框外，观感是四点齐闪 + 出框。
  local head = mod(now / h.speed, 1) * per
  local tail = head - len

  local i
  for i = 1, 4 do
    local o, L = off[i], elen[i]
    local t0, t1 = -1, -1

    -- 段 1：光带主体与这条边的交集
    local a = tail
    if a < o then a = o end
    local b = head
    if b > o + L then b = o + L end
    if b > a then t0, t1 = a, b end

    -- 段 2：光带跨过周长起点（tail < 0 时，前半段其实在周长末尾）
    if t0 < 0 and tail < 0 then
      a = tail + per
      if a < o then a = o end
      b = per
      if b > o + L then b = o + L end
      if b > a then t0, t1 = a, b end
    end

    if t0 < 0 then
      h.tex[i]:SetAlpha(0)
    else
      PlaceChase(h, i, t0 - o, t1 - o, w, hgt)

      -- 亮度按"这条边看到的是光带的哪一段"缩放：整条都在 = 原亮度，
      -- 拐角只露出一小截 = 暗下去 ⇒ 衔接自然，不像被刀切断。
      local q0 = mod(o + t0 - tail, per)
      local q1 = mod(o + t1 - tail, per)
      local fa = (q0 + q1) / len
      if fa > 1 then fa = 1 end
      h.tex[i]:SetAlpha(h.alpha * fa)
    end
  end
end

FlashUpdate = function(h, now)
  if not h.frame:IsShown() then return end
  local t = mod(now / h.period, 1)
  h.tex[1]:SetAlpha(h.low + (h.high - h.low) * (0.5 + 0.5 * sin(2 * pi * t)))
end

PulseUpdate = function(h, now)
  -- 隐藏时不写边框色：写了也会被下一次 Show 时的底色重设盖掉，只是白跑一次 SetBackdropBorderColor
  if not h.frame:IsShown() then return end
  local bd = h.frame.backdrop
  if not bd then
    return
  end

  local t = mod(now / h.period, 1)
  local v = 0.5 + 0.5 * sin(2 * pi * t)
  local org = h.org

  bd:SetBackdropBorderColor(
    org.r + (h.r - org.r) * v,
    org.g + (h.g - org.g) * v,
    org.b + (h.b - org.b) * v,
    org.a)
end

-- [ Tick ]
-- 单帧派发全部手柄。手柄可在自己的更新里 Disarm（换位删除 + 重测当前槽）。
Tick = function()
  local now = GetTime()
  local n = getn(handles)
  local i = 1

  while i <= n do
    local h = handles[i]

    if h.kind == "chase" then
      ChaseUpdate(h, now)
    elseif h.kind == "flash" then
      FlashUpdate(h, now)
    else
      if not h.next or h.next <= now then
        h.next = now + 0.05
        PulseUpdate(h, now)
      end
    end

    if handles[i] == h then
      i = i + 1
    end
    n = getn(handles)
  end
end

-- 退化路径用的自驱动帧。libticker 在时永不显示。
local driver = CreateFrame("Frame", "pfLibGlowDriver", UIParent)
driver:Hide()
driver:SetScript("OnUpdate", function()
  Tick()
end)

-- [ Sync ]
-- 手柄数 0 → 摘订阅（driver 隐藏 ⇒ 真的不跑），否则确保订阅在。
local function Sync()
  local ticker = pfUI.api.libticker

  if getn(handles) == 0 then
    if ticker then
      ticker:Remove("glow")
    end
    driver:Hide()
    return
  end

  if not (ticker and ticker:Add("glow", Tick)) then
    driver:Show()
  end
end

local function ShowTex(h, on)
  local n = getn(h.tex)
  local i
  for i = 1, n do
    if on then
      h.tex[i]:SetAlpha(on and h.alpha or 0)
      h.tex[i]:Show()
    else
      h.tex[i]:Hide()
    end
  end
end

local function Register(h)
  if h.armed then
    return
  end

  h.armed = true
  handles[getn(handles) + 1] = h
  ShowTex(h, true)
  Sync()
end

local function Unregister(h)
  if not h.armed then
    return
  end

  local n = getn(handles)
  local idx
  local i
  for i = 1, n do
    if handles[i] == h then
      idx = i
      break
    end
  end

  if idx then
    if idx ~= n then
      handles[idx] = handles[n]
    end
    handles[n] = nil
  end

  h.armed = false
  ShowTex(h, false)

  -- pulse：把边框色还原成 Arm 时记下的那份
  if h.kind == "pulse" and h.org and h.frame.backdrop then
    h.frame.backdrop:SetBackdropBorderColor(h.org.r, h.org.g, h.org.b, h.org.a)
  end
  h.next = nil

  Sync()
end

-- [ Arm / Disarm / SetColor ]
local handles_methods = {}

function handles_methods:Arm()
  Register(self)
  return self
end

function handles_methods:Disarm()
  Unregister(self)
  return self
end

function handles_methods:IsArmed()
  return self.armed == true
end

function handles_methods:SetColor(r, g, b)
  self.r, self.g, self.b = r, g, b
  if self.kind == "chase" then
    ApplyChaseColor(self)
  elseif self.kind == "flash" then
    self.tex[1]:SetTexture(r, g, b, 1)
  end
  return self
end

local function NewHandle(kind)
  return setmetatable({
    kind = kind,
    armed = false,
    r = 0.98, g = 0.80, b = 0.18,
    alpha = 0.9,
    thickness = 2,
    speed = 2.2,
    period = 1.4,
    low = 0,
    high = 0.35,
    tex = {},
  }, { __index = handles_methods })
end

-- [ Chase ]
-- opts: color={r,g,b}, thickness, speed(秒/圈), alpha
function libglow:Chase(frame, opts)
  opts = opts or {}
  local h = NewHandle("chase")
  h.frame = frame
  h.r = opts.color and opts.color[1] or h.r
  h.g = opts.color and opts.color[2] or h.g
  h.b = opts.color and opts.color[3] or h.b
  h.alpha = opts.alpha or h.alpha
  h.thickness = opts.thickness or h.thickness
  h.speed = opts.speed or h.speed

  local i
  for i = 1, 4 do
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(1, 1, 1, 1)
    tex:SetBlendMode("ADD")
    tex:SetAlpha(0)
    tex:Hide()
    h.tex[i] = tex
  end

  ApplyChaseColor(h)
  return h
end

-- [ Flash ]
-- opts: color={r,g,b}, period(秒), low, high
function libglow:Flash(frame, opts)
  opts = opts or {}
  local h = NewHandle("flash")
  h.frame = frame
  h.r = opts.color and opts.color[1] or 1
  h.g = opts.color and opts.color[2] or 0.25
  h.b = opts.color and opts.color[3] or 0.1
  h.period = opts.period or 0.6
  h.low = opts.low or 0
  h.high = opts.high or 0.35
  h.alpha = h.high

  local tex = frame:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(frame)
  tex:SetTexture(h.r, h.g, h.b, 1)
  tex:SetBlendMode("ADD")
  tex:SetAlpha(0)
  tex:Hide()
  h.tex[1] = tex

  return h
end

-- [ Pulse ]
-- opts: color={r,g,b}, period(秒)
-- ⛔ 需要 frame.backdrop（pfUI 的 CreateBackdrop 会给）。没有就什么都不做。
function libglow:Pulse(frame, opts)
  opts = opts or {}
  local h = NewHandle("pulse")
  h.frame = frame
  h.r = opts.color and opts.color[1] or 1
  h.g = opts.color and opts.color[2] or 0.62
  h.b = opts.color and opts.color[3] or 0.1
  h.period = opts.period or 1.4
  h.alpha = 1

  local bd = frame.backdrop
  local orr, org, orb, ora = 1, 1, 1, 1
  if bd then
    orr, org, orb, ora = bd:GetBackdropBorderColor()
  end
  h.org = { r = orr or 1, g = org or 1, b = orb or 1, a = ora or 1 }

  return h
end

-- [ Count / Handles ]
function libglow:Count()
  return getn(handles)
end

function libglow:Handles()
  local out = {}
  local i
  for i = 1, getn(handles) do
    out[i] = handles[i]
  end
  return out
end

-- 诊断输出 / 测试框 ---------------------------------------------------------

local function Say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfGlow|r: " .. text)
end

-- 订阅状态口径：libticker 里 glow 只有一个 key，所有手柄共用它。
-- ⛔ 别把 handles 数报成"订阅数"（曾经报错过，看起来像每加一个手柄就多一个订阅）。
local function SubState()
  local ticker = pfUI.api.libticker
  if ticker and ticker.Has then
    if ticker:Has("glow") then
      return "1 个（运行中）"
    end
    return "0 个（休眠）"
  end
  return "退化驱动（无 libticker）"
end

local demo, demo_handles

local function DemoFrame()
  if demo then
    return demo
  end

  demo = CreateFrame("Frame", "pfGlowDemo", UIParent)
  demo:SetWidth(96)
  demo:SetHeight(96)
  demo:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  demo:SetFrameStrata("DIALOG")
  pfUI.api.CreateBackdrop(demo, 2)
  demo:Show()
  return demo
end

local function DemoClear()
  if demo_handles then
    local i
    for i = 1, getn(demo_handles) do
      demo_handles[i]:Disarm()
    end
    demo_handles = nil
  end
  if demo then
    demo:Hide()
  end
end

local function DemoRun(style)
  DemoClear()

  local frame = DemoFrame()
  frame:Show()

  demo_handles = {}
  if style == "flash" then
    demo_handles[1] = libglow:Flash(frame, { color = { 1, 0.3, 0.1 }, period = 0.8, high = 0.45 }):Arm()
  elseif style == "pulse" then
    demo_handles[1] = libglow:Pulse(frame, { color = { 1, 0.2, 0.2 }, period = 1.2 }):Arm()
  elseif style == "all" then
    demo_handles[1] = libglow:Chase(frame, { color = { 1, 0.82, 0.2 } }):Arm()
    demo_handles[2] = libglow:Flash(frame, { color = { 1, 0.3, 0.1 }, period = 1.6, high = 0.2 }):Arm()
  else
    demo_handles[1] = libglow:Chase(frame):Arm()
  end

  Say(format("演示 %s：手柄 %d 个 · glow 订阅 %s（/pfglow off 收掉）",
    style, getn(demo_handles), SubState()))
end

pfUI.api.RegisterSlashCommand("PFGLOW", { "/pfglow" }, function(msg)
  msg = msg and string.lower(msg) or ""

  if msg == "off" then
    DemoClear()
    Say("测试框已收掉")
    return
  elseif msg == "demo" then
    DemoRun("chase")
    return
  elseif msg == "demo flash" then
    DemoRun("flash")
    return
  elseif msg == "demo pulse" then
    DemoRun("pulse")
    return
  elseif msg == "demo all" then
    DemoRun("all")
    return
  end

  local list = libglow:Handles()
  local n = getn(list)
  Say(format("手柄 %d 个 · glow 订阅 %s", n, SubState()))

  local i
  for i = 1, n do
    local h = list[i]
    Say(format("  %s  %s", h.kind, h.frame and (h.frame:GetName() or "匿名") or "?"))
  end
end, true)
