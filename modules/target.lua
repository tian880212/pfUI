pfUI:RegisterModule("target", "vanilla:tbc", function ()
  -- 原生模式（unitframes.native）：目标框架交回暴雪原生。
  -- ⛔ 只 return 是不够的：原生框可能已被别的路径/上一会话留在隐藏态（或 alpha=0），
  --    那样会出现「pfUI 框不建 + 原生框也不显示 = 目标头像直接消失」。这里显式救回一次。
  --
  -- ⛔⛔ 但「整个 return」会把目标 debuff 一起弄没：1.12 原生 TargetFrame 自带的
  --    debuff 图标只有 8 格、且**完全不显示剩余时间**（数量少 + 没时间就是这个原因），
  --    而 pfUI 的 debuff 网格是 64 格带计时。所以这里仍然把 pfUI 目标框建出来，
  --    只把「框体本体」变隐形，并把 debuff 图标挂到一个 1x1 宿主框上照常显示。
  -- 一次性修复：上一版原生模式把**共用的存档键** C.unitframes.target.debuffsize
  -- 从 22 直接写成了 18（见下面 native 分支的注释），导致切回非原生模式后
  -- pfUI 自己的目标 debuff 也变小。这里改回 22，并用标记确保只跑一次 ——
  -- 之后用户自己在 GUI 里调成 18 不会再被这段翻回去。
  if C.unitframes.target.debuffsize == "18" and C.unitframes.target.debufffix18 ~= "1" then
    C.unitframes.target.debuffsize = "22"
    C.unitframes.target.debufffix18 = "1"
  end

  if C.unitframes.native == "1" then
    -- 0) 图标尺寸跟原生对齐：暴雪原生 buff 图标是 16px，pfUI 默认 22px 会显得大一圈。
    --    ⛔ 必须放在 CreateUnitFrame 之前：图标宽高和 cooldown 缩放都是在建框时
    --       按 config.debuffsize 定死的，建完再改这里不会生效。
    --    目标值 18（16 上的倒计时数字太糊）。
    --    ⛔⛔ 绝不能改 C.unitframes.target.debuffsize —— 那是 pfUI 模式**共用**的存档键，
    --       写进去就持久化了，切回非原生模式后目标 debuff 也跟着变 18
    --       （"非原生模式 debuff 大小也被改了"的真凶）。
    --       改用一份浅拷贝配置：f.config 指向拷贝，建框/UpdateConfig/UpdateFrameSize
    --       全程读 f.config、不会回读存档，所以原生模式拿到 18，pfUI 模式原样保留用户值。
    local nativecfg = {}
    for k, v in pairs(C.unitframes.target) do nativecfg[k] = v end
    nativecfg.debuffsize = "18"

    if TargetFrame then
      TargetFrame:SetAlpha(1)
      TargetFrame:EnableMouse(true)
      -- 没有目标时不要凭空显示，否则会留一个空目标框
      if UnitExists("target") then TargetFrame:Show() end
    end

    -- 1) 原生框自带的 debuff 小图标藏掉：它们会和下面的 pfUI 网格重复，
    --    而且不显示时间、只有 8 格。用 OnShow 兜住（原生框每次刷新都会去 Show 它们）。
    -- ⛔ 1.12 的 SetScript 不传 self，handler 里用隐式全局 this；写成 this:Hide() 才对。
    -- ⛔ 不要连 buff 图标一起藏：目标 buff 的 pfUI 网格是从框底边往**下**长的，
    --    藏了原生 buff 就会出现「原生没有 + pfUI 的被隐形框带走」= 目标 buff 全没。
    for i = 1, 16 do
      local nd = _G["TargetFrameDebuff" .. i]
      if nd then
        nd:Hide()
        nd:SetScript("OnShow", function() this:Hide() end)
      end
    end

    -- 2) 建 pfUI 目标框：事件、刷新链路、aura 图标池全套都要跑，只是框体不显示。
    local f = pfUI.uf:CreateUnitFrame("Target", nil, nativecfg)
    f:UpdateFrameSize()
    UpdateMovable(f)
    pfUI.uf.target = f
    f:EnableMouse(false)

    -- 3) 框体隐形。⛔ 只 SetAlpha(0) 会被 RefreshUnitState 按 config 改回 1
    --    （它读 unit.alpha_visible），所以把三个 alpha 字段一起置 0。
    f.alpha_visible, f.alpha_outrange, f.alpha_offline = 0, 0, 0
    f.base_alpha = 0
    f:SetAlpha(0)

    -- 4) 坐标系：f 自己不可见，只当兜底锚点（下面的 debuff 布局已直接锚原生格子，
    --    不再依赖 f 的位置；保留这句是为了 buff 网格/指示器将来还有落脚处）。
    if TargetFrame then
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", TargetFrame, "TOPLEFT", 0, 0)
    end

    -- 4.5) debuff 布局：位置沿用暴雪原生（锚 TargetFrameDebuff1），但改成一排 6 个、
    --      往下换行、并显示 pfUI 的剩余时间（原生 1.12 的 debuff 只有 8 格且不计时）。
    --      ⛔ 不动 C.unitframes.target.debuffs / debuffperrow：那是 pfUI 模式的存档，
    --         切回 pfUI 必须原样还原，所以这里不复用那套配置，改为自己 SetPoint。
    --      ⛔ 也不能靠挪 f 的锚点来借坐标系：pfUI 的定位是 anchor(f/f.hp/f.power)
    --         + 方向 + 缓冲行数 + 边框系数一起算的，差一项就整体错位。
    -- 旧默认 6 → 新默认 8（跟原生一样一排 8 格）。
    -- ⛔ UpdateConfig 只补缺失键、永不覆盖，所以存档里已被写进 "6" 的必须在这里迁移一次；
    --    想改回 6 就删掉这三行。
    if C.unitframes.nativedebuffperrow == "6" then
      C.unitframes.nativedebuffperrow = "8"
    end

    _G["pfUI_NativeTargetDebuffLayout"] = function()
      local t = pfUI.uf and pfUI.uf.target
      if not t or not t.debuffs then return end

      -- 原生第一格当锚：隐藏的 frame 一样能当锚点（锚点解析不看可见性）
      local anchor = _G["TargetFrameDebuff1"] or TargetFrame
      if not anchor then return end

      local cfg = t.config or {}
      local size = tonumber(cfg.debuffsize) or 18
      local perrow = tonumber(C.unitframes.nativedebuffperrow) or 8
      if perrow < 1 then perrow = 1 end
      local step = size + 2
      -- 复用 GUI 里的「Debuff 偏移」做微调（默认 0,0 即完全贴原生位置）
      local offx = tonumber(cfg.debuffoffx) or 0
      local offy = tonumber(cfg.debuffoffy) or 0

      local n = 0
      for i = 1, table.getn(t.debuffs) do
        local b = t.debuffs[i]
        if b and b:IsShown() then
          local row = math.floor(n / perrow)
          local col = n - row * perrow
          b:ClearAllPoints()
          b:SetPoint("TOPLEFT", anchor, "TOPLEFT", col * step + offx, -row * step + offy)
          n = n + 1
        end
      end
    end

    -- 4.6) pfUI 每次刷新都会对**所有**可见 debuff 重设 SetPoint（不只是新出现的），
    --      只在 OnShow 里纠正会漏掉「数量不变但被重摆」的情况。这里包一层 RefreshUnit，
    --      刷新完立刻按原生位置重排一遍。
    --      ⛔⛔ 参数必须原样转 3 个：原函数是 `pfUI.uf:RefreshUnit(unit, component)`，
    --      冒号调用传的是 (self, unit, component)。少接一个参数会让 unit 挤进 component、
    --      真正的 "all"/"aura" 丢掉 ⇒ 原函数里 `component == "all" or "aura"` 全部不成立
    --      ⇒ **所有单位框的 buff/debuff 都不再刷新**（整屏 aura 消失的真凶）。
    --      ⛔ 1.12 不能用 ... 转发，只好把三个参数写死。
    if not pfUI.uf.NativeOrigRefresh then
      pfUI.uf.NativeOrigRefresh = pfUI.uf.RefreshUnit
      pfUI.uf.RefreshUnit = function(self, unit, component)
        pfUI.uf.NativeOrigRefresh(self, unit, component)
        if C.unitframes.native == "1" then
          _G["pfUI_NativeTargetDebuffLayout"]()
        end
      end
    end

    -- 5) aura 图标宿主：1x1、alpha=1、不吃鼠标。
    --    图标 reparent 到它之后不再继承 f 的 alpha（这是关键），但坐标仍锚在 f 上
    --    （跨父锚定在 1.12 有效），所以位置跟着 f（= 原生框顶边）走。
    local host = CreateFrame("Frame", "pfNativeTargetAuraHost", UIParent)
    host:SetWidth(1)
    host:SetHeight(1)
    host:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    host:SetAlpha(1)
    host:EnableMouse(false)
    host:Show()
    -- 图标的 tooltip / 右键菜单里会读 this:GetParent().label / .config / .id，
    -- 宿主冒充目标框提供这些字段（否则悬停没有说明、右键也没有反应）。
    -- config 必须给拷贝（与 f.config 同一份），否则读到的还是存档里的 22。
    host.label = "target"
    host.id = ""
    host.unitname = "target"
    host.config = nativecfg

    local function SyncPool(list)
      if not list then return end
      for i = 1, table.getn(list) do
        local b = list[i]
        if b and b:GetParent() ~= host then
          b:SetParent(host)
          -- 父级换成 host 后 frameLevel 会脱离原来那套层级，抬高一档别被原生框盖住
          b:SetFrameLevel(30)
          b:SetAlpha(1)
        end
      end
    end

    local function SyncAuraHost()
      SyncPool(f.debuffs)
      host.unitname = f.unitname or "target"

      -- 图标每次「由隐藏转显示」都按原生位置重排一次。
      -- pfUI 的刷新顺序是 SetPoint → Show，所以在 OnShow 里覆盖坐标，
      -- 才不会先闪到 pfUI 的布局再跳过去（刷新后的整体重排见下面包住的 RefreshUnit）。
      if f.debuffs then
        for i = 1, table.getn(f.debuffs) do
          local b = f.debuffs[i]
          if b and not b.pfNativePosHooked then
            b.pfNativePosHooked = 1
            b:SetScript("OnShow", _G["pfUI_NativeTargetDebuffLayout"])
          end
        end
      end
    end
    SyncAuraHost()

    -- 6) 守护：GUI 改头像设置会重跑 UpdateConfig/UpdateFrameSize，把 alpha 字段和
    --    图标父级改回去；每 0.25s 修一次（只是几十次比较，开销可忽略）。
    local guard = CreateFrame("Frame", "pfNativeTargetAuraGuard", UIParent)
    guard.elapsed = 0
    guard:SetScript("OnUpdate", function()
      this.elapsed = this.elapsed + arg1
      if this.elapsed < 0.25 then return end
      this.elapsed = 0

      -- 关掉原生模式后停表（切换需要重载，这里只是保险）
      if C.unitframes.native ~= "1" then
        this:SetScript("OnUpdate", nil)
        return
      end

      if f.alpha_visible ~= 0 then
        f.alpha_visible, f.alpha_outrange, f.alpha_offline = 0, 0, 0
        f.base_alpha = 0
      end
      if f:GetAlpha() ~= 0 then f:SetAlpha(0) end
      f:EnableMouse(false)
      SyncAuraHost()

      -- 目标没了：图标现在是 host 的子元素，不会跟着 f 一起隐藏，这里补一次清空，
      -- 否则切走目标后旧 debuff 会残留在原生框上方。
      -- （目标存在时不动，显示/隐藏交给 pfUI 自己的刷新链路）
      if not UnitExists("target") and f.debuffs then
        for i = 1, table.getn(f.debuffs) do
          if f.debuffs[i] then f.debuffs[i]:Hide() end
        end
      end

      -- 兜底重排（数量变了才真的动坐标；GUI 改 debuff 大小/偏移后也靠这里跟上）
      _G["pfUI_NativeTargetDebuffLayout"]()
    end)

    return
  end

  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  -- Hide Blizzard target frame and unregister all events to prevent it from popping up again
  TargetFrame:Hide()
  TargetFrame:UnregisterAllEvents()

  pfUI.uf.target = pfUI.uf:CreateUnitFrame("Target", nil, C.unitframes.target)
  pfUI.uf.target:UpdateFrameSize()
  pfUI.uf.target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM", 75, 125)
  UpdateMovable(pfUI.uf.target)

  -- ============================================================================
  -- 仇恨显示框（参考姓名板仇恨显示）
  -- 一个可移动的仇恨百分比显示框，默认位于头像框左侧。
  -- 数据来源优先级：Nampower 原生 > CatThreatLite > TWT 单体 > ShaguDPS。
  -- ============================================================================

  -- 玩家在当前目标上的仇恨百分比（仅对 target 单位，故直接走单体源）
  local function GetTargetThreatPercent()
    if not UnitExists("target") or UnitIsDead("target") then return nil end

    -- 1) Nampower 原生威胁 API（按 GUID 精确，无需网络，最优先）
    if _G.GetUnitThreatPct and _G.GetUnitGUID then
      local guid = _G.GetUnitGUID("target")
      if guid then
        local pct = _G.GetUnitThreatPct(guid)
        if pct and pct > 0 then return pct end
      end
    end

    -- 2) CatThreatLite：轻量共享客户端（无完整 TWT 时覆盖）
    if _G.CatThreatLite then
      local pct = _G.CatThreatLite.GetPercent()
      if pct and pct > 0 then return pct end
    end

    -- 3) TWT 单体目标模式
    if _G.TWT and _G.TWT.threats then
      local entry = _G.TWT.threats[UnitName("player")]
      if entry and entry.perc and entry.perc > 0 then return entry.perc end
    end

    -- 4) ShaguDPS 仇恨表（回退）
    if _G.ShaguDPS and _G.ShaguDPS.data and _G.ShaguDPS.data.threat then
      local entry = _G.ShaguDPS.data.threat[UnitName("player")]
      if entry and entry.perc and entry.perc > 0 then return entry.perc end
    end

    return nil
  end

  -- 仇恨显示框本体（独立可移动顶层框，默认锚定在头像框左侧）
  local threat = CreateFrame("Frame", "pfTargetThreat", UIParent)
  CreateBackdrop(threat)
  threat:SetMovable(true)
  threat:EnableMouse(true)
  threat:RegisterForDrag("LeftButton")
  threat:SetScript("OnDragStart", function() threat:StartMoving() end)
  threat:SetScript("OnDragStop", function()
    threat:StopMovingOrSizing()
    SaveMovable(threat)
  end)

  -- 材质层（背景纹理，默认 pfUI-F，与头像/血条一致）
  threat.tex = threat:CreateTexture(nil, "ARTWORK")
  threat.tex:SetPoint("TOPLEFT", threat, "TOPLEFT", 0, 0)
  threat.tex:SetPoint("BOTTOMRIGHT", threat, "BOTTOMRIGHT", 0, 0)
  threat.tex:SetVertexColor(1, 1, 1, 1)

  threat.text = threat:CreateFontString(nil, "OVERLAY")
  threat.text:SetAllPoints(threat)
  threat.text:SetFont(pfUI.font_unit, tonumber(C.global.font_unit_size) or 12, "OUTLINE")
  threat.text:SetJustifyH("CENTER")
  threat.text:SetJustifyV("CENTER")
  threat.text:SetTextColor(1, 1, 1, 1)

  -- 应用材质/长宽配置（GUI 改动时实时回调此函数）
  local function ApplyThreatBoxStyle()
    local cfg = C.unitframes.target
    local w = tonumber(cfg.ligh) or tonumber(cfg.threatwidth) or 50
    local h = tonumber(cfg.lightH) or tonumber(cfg.threatheight) or 20
    threat:SetWidth(w)
    threat:SetHeight(h)
    local texpath = C.unitframes.target.threattexture
    if texpath and texpath ~= "" then
      pcall(function() threat.tex:SetTexture(pfUI.media[texpath]) end)
    end
  end
  ApplyThreatBoxStyle()
  pfUI.uf.target_threat_apply = ApplyThreatBoxStyle

  -- 默认位置：头像框左侧（未手动拖动前动态跟随目标框）
  threat:ClearAllPoints()
  threat:SetPoint("RIGHT", pfUI.uf.target, "LEFT", -5, 0)

  -- 注册到 pfUI.movables：解锁模式才会给它生成 dragger，右键 dock 才会显示坐标、
  -- 才能改。旧实现自己读 C.position 绕开 movables，结果仇恨框在解锁里既没有
  -- dragger（右键点不开）也不响应 dock 的坐标输入。初始锚点会被 LoadMovable
  -- 记进 posdata，没有存档时自动回落到「贴目标框左侧」。
  UpdateMovable(threat)
  threat:Hide()

  -- 驱动帧：始终可见（透明），用于按节流刷新仇恨框（隐藏的框不会触发 OnUpdate）
  local threatDriver = CreateFrame("Frame", "pfTargetThreatDriver", UIParent)
  threatDriver:SetScript("OnUpdate", function()
    if (this.tick or 0) > GetTime() then return end
    this.tick = GetTime() + 0.2

    local unlock = pfUI.unlock and pfUI.unlock:IsShown()
    local enabled = C.unitframes.target.showthreat ~= "0"

    -- 解锁模式下始终显示，按"安全绿"染色（避免某些角色看到白色底色卡片）
    if unlock then
      local r, g, b = 0.67, 0.83, 0.45 -- 安全绿，与 ≤60% 阈值一致
      threat.text:SetText("仇恨%")
      threat.text:SetTextColor(1, 1, 1, 1)
      if threat.backdrop then
        threat.backdrop:SetBackdropColor(r, g, b, 0.45)    -- 背景底色
        threat.backdrop:SetBackdropBorderColor(r, g, b, 1) -- 边框实色
      end
      if threat.tex then
        threat.tex:SetVertexColor(r, g, b, 1)              -- 材质层染色
      end
      threat:Show()
      return
    end

    if not enabled then
      threat:Hide()
      return
    end

    if not UnitExists("target") or UnitIsDead("target") then
      threat:Hide()
      return
    end

    local perc = GetTargetThreatPercent()
    if perc and perc > 0 then
      -- 底色用 TWT 仇恨小窗同款连续渐变（绿→黄→红），超过 100 按 100 截断
      if perc > 100 then perc = 100 end
      local r, g, b
      if perc < 50 then
        r, g, b = perc / 50, 1, 0
      else
        r, g, b = 1, 1 - (perc - 50) / 50, 0
      end
      -- 文字仅显示百分比，仇恨框（材质+背景+边框）按渐变着色
      threat.text:SetText(string.format("%.0f%%", perc))
      threat.text:SetTextColor(1, 1, 1, 1)
      if threat.backdrop then
        threat.backdrop:SetBackdropColor(r, g, b, 0.45)   -- 背景底色（半透，纹理透明处兜底）
        threat.backdrop:SetBackdropBorderColor(r, g, b, 1) -- 边框实色
      end
      if threat.tex then
        threat.tex:SetVertexColor(r, g, b, 1)             -- 材质层按阈值着色
      end
      threat:Show()
    else
      threat:Hide()
    end
  end)
end)
