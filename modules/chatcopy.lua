-- ============================================================================
-- pfUI · chatcopy —— 聊天内容复制
-- ----------------------------------------------------------------------------
-- 架构：**独立复制窗口**（参考 CopyChat 的成熟做法，2026-09-13 重构）
--
-- 为什么不再"就地覆盖在聊天窗口上"：
--   旧实现把复制层做成 ChatFrame 的子对象，于是同时踩中三个本客户端特有的坑：
--     ① pfUI 的 fadeout 是 **C 侧渐隐**（chat.lua:531-536 只点火 SetFading + SetTimeVisible），
--        淡出**不经过 Lua 的 SetAlpha** ⇒ 覆盖 SetAlpha 拦不住；子对象乘性继承父帧 alpha，
--        静默满 fadetime 后整帧掉到 ~5%，复制层的黑底和文字一起消失
--        =「点复制后看不见字」。综合/战斗记录消息不断，计时器反复复位，所以只有它们一直好用。
--     ② 本客户端 EditBox 的**选区高亮消不掉**：诊断实测 SetHighlightTexture / SetHighlightColor /
--        SetSelectionColor 三个方法全「无」，而它是 C 侧画的**不透明 (96,96,96) 灰块、画在文字之上、
--        不吃父帧 alpha** ⇒ 为了 Ctrl+C 一拖选，被选中的几行必然变灰块盖住字
--        =「拖选时一大块灰挡住字」（录像定案帧 f021 像素级验证：块内逐行只有 1 种颜色、零字形）。
--     ③ 覆盖层挂 ChatFrame 就跟着它显隐/层序走；改挂面板又得自己管显隐，反复失手。
--
--   独立窗口从结构上一次解决三条：它不是聊天窗口的子对象 ⇒ 不继承渐隐、不参与聊天窗口的层序、
--   不受停靠/切标签影响；文字也不再需要"盖住灰块"这类花活。
--
-- 两条硬约束（本客户端实测，改动前务必保留）：
--   ⛔ EditBox / FontString 的字体必须**两步走**：先 SetFontObject 兜底，再 SetFont 覆盖。
--      只写 SetFont，一旦这台客户端不认就是"什么都不画"（黑底 + 没字）。
--   ⛔ 选区高亮消不掉 ⇒ 只能让 EditBox **整个不可见**（SetAlpha(0)），文字由上层 FontString 画；
--      并对 FontString 做**运行期自检**，画不出来就退回"EditBox 自己显示"
--      （宁可拖选发灰，也绝不出现"一片空白"）。
--
-- 命令：/pfchatcopy                     诊断（逐窗口历史/字体/滚动/剪贴板 API）
--       /pfchatcopy show                打开复制窗口
--       /pfchatcopy <n>                 打印窗口 n 的原文（竖线转义）
--       /pfchatcopy max <n>             每个窗口保留多少行（默认 200）
--       /pfchatcopy format all|plain    保留颜色 / 纯文本
--       /pfchatcopy mode lines|text     行选（默认，零灰块）/ 文本（可拖选任意字句）
--       /pfchatcopy textpad <0.9~2>     文本模式高度系数（默认 1=不留空白，底部缺行时调大）
--       /pfchatcopy ghost on|off        静默全选开关（默认 on；off = 显示 EditBox 兜底）
--       /pfchatcopy clear               清空已捕获内容
--
-- 两种选取形态（2026-10-28 新增，工具栏有按钮可切，选择持久化在 pfUI_cache.chatcopy.mode）：
--   lines —— 逐行 FontString + 行热区：点一行选一行、Shift 连选。**零灰块**，日常用这个。
--   text  —— 整个区域就是原生多行 EditBox：鼠标定位、拖选任意字句。代价是 1.12 那个
--            消不掉的 C 侧灰块选区（见下面 ②），只适合"要从一段里抠一句话"的场合。
-- ============================================================================
pfUI:RegisterModule("chatcopy", "vanilla:tbc", function ()
  local limit    = 200     -- 每个聊天窗口最多保留的行数
  local MIRROR_W = 566     -- 窗口内文字的排版宽度（改窗口宽度时同步）

  local win                -- 复制窗口（单例，首次点击才创建）
  local source             -- 当前显示的是哪个 ChatFrame
  local Fill, Open, Close, Cycle, ToggleMode   -- 前置声明：按钮回调互相引用

  pfUI.chatcopy = pfUI.chatcopy or {}
  if not pfUI.chatcopy.format then pfUI.chatcopy.format = "all" end

  -- ==========================================================================
  -- 显示项：复制窗口里额外附加的信息 —— 时间戳 / 职业·等级
  -- --------------------------------------------------------------------------
  -- 存在 SavedVariables 的 `pfUI_cache` 里（**账号级**存档），所以不必动
  -- api/config.lua 与 modules/gui.lua —— 本模块的界面一直是斜杠命令。
  -- ⛔ 与 pfUI 聊天自带的同类开关**去重**：`chat.text.time` / `chat.text.playerlevel`
  --    打开时，捕获到的正文里**已经有**时间戳/等级了，再叠一遍就是一行两个。
  -- ==========================================================================
  pfUI_cache = pfUI_cache or {}
  local opts = pfUI_cache.chatcopy
  if not opts then opts = {}; pfUI_cache.chatcopy = opts end
  if not opts.time    then opts.time    = "1"        end   -- 时间戳开关
  if not opts.timefmt then opts.timefmt = "%H:%M:%S" end   -- strftime 格式
  if not opts.class   then opts.class   = "1"        end   -- 职业/等级标签开关
  -- 选取形态（2026-10-28 新增，工具栏按钮可切、持久化在 pfUI_cache）：
  --   "lines" —— 逐行 FontString + 行热区：点一行选一行，**零灰块**（默认）
  --   "text"  —— 整个区域就是原生多行 EditBox：可鼠标定位、拖选任意字句，
  --              代价是 1.12 那个消不掉的 C 侧灰块选区（见文件头 ②）
  if not opts.mode or (opts.mode ~= "lines" and opts.mode ~= "text") then
    opts.mode = "lines"
  end
  -- 静默全选（ghost）：1 = 行选模式下把 EditBox 压到 alpha 0 再全选，屏幕上不见灰块。
  -- 万一某台客户端在 α=0 时 Ctrl+C 读不到选区，用 `/pfchatcopy ghost off` 切回
  -- "把 EditBox 显出来"的老行为（有灰块，但一定复制得到）。
  if not opts.ghost then opts.ghost = "1" end
  -- 文本模式的高度余量系数（2026-10-28）：
  --   EditBox 不会自动撑高，超出 SetHeight 的内容直接被裁（= "少几行"）；
  --   但**给多了同样难看**：多出来的部分会变成内容区下方的空白，
  --   滚动到底时就是「整屏全空」（用户 19:42 录屏实证）。
  --   字号已与行 FontString 同步（见 Fill 里的 SetFont 段），两者行高本来就接近，
  --   所以默认 **1.0（不再放大）**，只留 8px 收边。
  --   现场若仍缺行：`/pfchatcopy textpad 1.15`。宁可多一行空白，不要整屏空白。
  if type(opts.textpad) ~= "number" or opts.textpad < 0.9 or opts.textpad > 2 then
    opts.textpad = 1
  end

  -- ==========================================================================
  -- 一、捕获：把每个聊天窗口的消息另存一份
  -- ==========================================================================
  -- 频道色。上游是直接用 rgbhex(r,g,b) 把整行套色，但本客户端"世界"这类自定义频道的
  -- 颜色实测偏暗（暗红/暗灰），整行一包，在深色窗口上就是"看不见字"。
  -- 这里只做一件事：**太暗就换白** —— 牺牲一点保真，换"一定看得清"。
  local function ColorOf(r, g, b)
    local rgb = pfUI.api and pfUI.api.rgbhex
    if not (rgb and r and g and b) then return nil end

    local col = rgb(r, g, b)
    if not col or col == "" then return nil end

    local h  = string.sub(col, 3)                        -- col = "|cAARRGGBB"
    local rr = tonumber(string.sub(h, 3, 4), 16) or 255
    local gg = tonumber(string.sub(h, 5, 6), 16) or 255
    local bb = tonumber(string.sub(h, 7, 8), 16) or 255
    if (rr * .299 + gg * .587 + bb * .114) < 90 then return "|cffffffff" end
    return col
  end

  -- --------------------------------------------------------------------------
  -- 装饰：给每一行补上「时间戳」与「职业·等级」
  -- --------------------------------------------------------------------------
  -- 职业英文 token（libunitscan / pfUI_playerDB 里存的就是这个形态）→ 显示名（全称）
  local CLASS_NAME = {
    WARRIOR = "战士", MAGE = "法师", ROGUE = "盗贼", DRUID = "德鲁伊", HUNTER = "猎人",
    SHAMAN  = "萨满", PRIEST = "牧师", WARLOCK = "术士", PALADIN = "圣骑士",
  }
  if _G.GetLocale and _G.GetLocale() ~= "zhCN" then
    CLASS_NAME = {
      WARRIOR = "Warrior", MAGE = "Mage", ROGUE = "Rogue", DRUID = "Druid", HUNTER = "Hunter",
      SHAMAN  = "Shaman", PRIEST = "Priest", WARLOCK = "Warlock", PALADIN = "Paladin",
    }
  end

  -- pfUI 聊天自己的同类开关（读活值：profile 切换会换掉 pfUI_config）
  local function ChatText()
    return (pfUI_config and pfUI_config.chat and pfUI_config.chat.text) or {}
  end

  -- 时间戳的显示色：沿用 pfUI 聊天的 `chat.text.timecolor`（读一次缓存即可）
  local timeCol
  local function TimeCol()
    if timeCol then return timeCol end
    timeCol = "|cffb0b0b0"
    local rgb = pfUI.api and pfUI.api.rgbhex
    local r, g, b, a = strsplit(",", ChatText().timecolor or ".8,.8,.8,1")
    r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
    if rgb and r and g and b then
      local c = rgb(r, g, b, a)
      if c and c ~= "" then timeCol = c end
    end
    return timeCol
  end

  -- 捕获那一刻的时钟字符串（**必须**在消息到达时取；渲染时再取就成了"当前时间"）
  local function TimeNow()
    local ok, s = pcall(date, opts.timefmt)
    if ok and s then return s end
    return date("%H:%M:%S")
  end

  -- 职业/等级标签。数据源只用 libunitscan 的玩家库（`units.players = pfUI_playerDB`，
  -- 是 SavedVariables ⇒ 跨会话累积）。
  -- ⛔ 这里**绝不**调 GetPlayerLevel：它未命中时会扫一遍公会 + 好友名单，
  --    一屏 200 行会被拖到明显卡顿。库里没有就**不显示** ——
  --    等 /who、公会/队伍/好友事件把数据补进库，点一下「刷新」就有。
  -- memo：一次填充内的「名字 → 标签」备忘，避免同名重复解析。
  local function WhoTag(name, memo)
    if memo then
      local hit = memo[name]
      if hit ~= nil then
        if hit == "" then return nil end
        return hit
      end
    end

    local out    = ""
    local class, level = nil, nil
    if type(_G.GetUnitData) == "function" then
      class, level = GetUnitData(name)
    end

    -- ⛔ 1.12 的 `RAID_CLASS_COLORS[class]` 只有 {r,g,b}，**没有 `colorStr`**
    --    （colorStr 是 2.0 才加进 ColorMixin 的）。职业色一律走 `rgbhex(表)`，
    --    它返回 `|cAARRGGBB` **完整前缀**；不要再拼 "|c"..hex，
    --    否则 hex 取不到就永远落到兜底灰（本客户端实测）。
    local classHex, className
    if class and class ~= "" then
      local c   = _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
      local rgb = pfUI.api and pfUI.api.rgbhex
      if c and rgb then classHex = rgb(c) end
      if not (classHex and classHex ~= "") then classHex = "|cff999999" end
      className = CLASS_NAME[class] or class
    end

    -- 等级：难度色（不去重，理由同 Decorate 里的时间戳：捕获的是原始文本）
    local levelStr
    if level and level > 0 then
      local lvcol = "|cffb0b0b0"
      local fn, rgb = _G.GetDifficultyColorChatMod, pfUI.api and pfUI.api.rgbhex
      if type(fn) == "function" and rgb then
        local ok, cc = pcall(fn, level, false)
        if ok and type(cc) == "table" and cc.r then lvcol = rgb(cc.r, cc.g, cc.b) end
      end
      levelStr = lvcol .. level .. "|r"
    end

    -- 拼成一对方括号：[60 法师]（等级在前、用难度色；职业全名在后、用职业色）
    -- ⚠️ levelStr 自身以 |c… 开头、|r 收尾，会把外层的职业色重置掉 ⇒
    --    等级后面必须再补一次 classHex，否则职业名与 "]" 会掉回频道色。
    if className then
      out = classHex .. "["
      if levelStr then out = out .. levelStr .. " " end
      out = out .. classHex .. className .. "]|r"
    elseif levelStr then
      out = levelStr
    end

    if memo then memo[name] = out end
    if out == "" then return nil end
    return out
  end

  -- 把一条历史记录渲染成"窗口里显示的那一行"（也是会被复制走的那一行）
  local function Decorate(e, memo)
    -- 兼容纯字符串条目（老写法 / 仿真脚本直接喂字符串时仍能跑）
    if type(e) ~= "table" then return e end

    local txt, col = e.txt or "", e.col or ""
    local C = ChatText()

    -- ① 时间戳前缀。括号沿用 pfUI 聊天自己的 `chat.text.timebracket`（默认 "[]"），
    --    这样复制框里长什么样、和聊天窗口里一致，不会一边圆括号一边方括号。
    -- ⛔ 这里**不做"pfUI 已开时间戳就去重"**（曾经写过，是错的）：
    --    pfUI 是在**模块加载期**把 `frame.AddMessage` 换成自己的解析函数
    --    （chat.lua:1281-1282），而本模块要到 PLAYER_ENTERING_WORLD 才在外层包一层
    --    ⇒ 我们捕获到的永远是**未经 pfUI 加工的原始文本**（时间戳/等级都还没有）。
    --    换句话说：聊天窗口里的时间戳是"显示层"产物，压根不会进 pfHistory，
    --    去重只会让用户在开着 pfUI 时间戳时**永远看不到**复制框的时间戳。
    if opts.time == "1" and e.t and e.t ~= "" then
      local br = C.timebracket or "[]"
      txt = TimeCol() .. string.sub(br, 1, 1) .. e.t .. string.sub(br, 2, 2) .. "|r " .. txt
    end

    -- ② 职业/等级：插在**第一个玩家名链接之前** ⇒ 读作 `[60 法师][小明]`。
    --    `tag` 自带 |r 收尾，会把颜色重置成默认 ⇒ 后面必须紧跟 `col` 把频道色接回来，
    --    否则玩家名与正文都会变成白色。
    --    ⚠️ 用函数式替换，避免标签里可能出现的 % 被 gsub 当成转义。
    if opts.class == "1" and e.name and e.name ~= "" then
      local tag = WhoTag(e.name, memo)
      if tag then
        txt = string.gsub(txt, "(|Hplayer:.-|h%[.-%]|h)", function(m)
          return tag .. col .. m
        end, 1)
      end
    end
    return txt
  end

  local function Capture(frame)
    local history = {}
    frame.pfHistory = history

    local AddMessage = frame.AddMessage
    frame.AddMessage = function(self, msg, r, g, b)
      if msg then
        -- 与上游算法一致：整行套频道色，并把行内的颜色复位 |r 也换成频道色，
        -- 这样"名字带色"的消息在复制框里整行仍保持同一个底色。
        local col  = ColorOf(r, g, b)
        local body = col and (col .. string.gsub(msg, "|r", col)) or msg

        -- 顺手记下两件"只有此刻查得到"的东西：
        --   · 时间戳：必须取**消息到达这一刻**的时钟（渲染时再取就成了当前时间，没意义）
        --   · 发言者名：从玩家链接里取第一个（渲染时用它查职业/等级）
        local who
        for nm in string.gfind(body, "|Hplayer:(.-)|h") do who = nm break end
        if who then who = strsplit(":", who) end

        table.insert(history, 1, {
          txt  = body,
          col  = col or "",
          t    = TimeNow(),
          name = who,
        })
        while table.getn(history) > limit do table.remove(history) end
      end
      AddMessage(self, msg, r, g, b)
    end
  end

  -- 给所有还没有记录器的聊天窗口补挂一个（进服后又新开的标签也能被抓到）
  local function EnsureCapture()
    for i=1, (_G.NUM_CHAT_WINDOWS or 10) do
      local cf = _G["ChatFrame"..i]
      if cf and not cf.pfHistory then pcall(Capture, cf) end
    end
  end

  -- 纯文本化（/pfchatcopy format plain）
  -- --------------------------------------------------------------------------
  -- ⛔ 顺序有讲究，别随手调换（2026-10-28 对着 RurutiaSuite 的 PlainText 重写）：
  --   ① `||` 是**玩家自己打的字面竖线**（客户端把单个 | 存成 ||）⇒ 必须先换成占位符
  --      保护起来。否则后面删 `|c`/`|r` 时会把字面 "||c" 当颜色码吃掉一半，
  --      而没被保护的 `||` 会原样复制出去（粘到记事本就多一根竖线）。
  --   ② `|h` 必须**晚于** `|H…|h` 处理：链接结构是 `|Hxxx|h[文本]|h`，
  --      先删单独的 `|h` 会把结构拆散、留下 `|Hxxx[文本]`。
  --   ③ `|n` 是换行转义，要还原成真换行；它必须在占位符还原之前做。
  --   ④ 6 位色码 `|cRRGGBB` 确实存在（部分频道/插件消息用），旧实现只删 8 位 ⇒ 漏出 `|cff0000`。
  local PIPE = string.char(1)      -- 字面竖线的临时占位（正常聊天文本里不会出现这个字节）
  local function Strip(s)
    if type(s) ~= "string" then return s end
    s = string.gsub(s, "||", PIPE)                  -- ① 保护字面竖线
    s = string.gsub(s, "|K.-|k", "")                -- 受保护名字占位（本身没有可见文本）
    s = string.gsub(s, "|H[^|]*|h(.-)|h", "%1")     -- 链接：留下可见部分，去掉 |H 段
    s = string.gsub(s, "|T.-|t", "")                -- 贴图图标
    s = string.gsub(s, "|A.-|a", "")                -- 图集图标
    s = string.gsub(s, "|c%x%x%x%x%x%x%x%x", "")    -- 8 位色码
    s = string.gsub(s, "|c%x%x%x%x%x%x", "")        -- 6 位色码
    s = string.gsub(s, "|r", "")                    -- 颜色复位
    s = string.gsub(s, "|h", "")                    -- 残链接标记（② 晚于 |H…|h）
    s = string.gsub(s, "|n", "\n")                  -- ③ 换行转义
    s = string.gsub(s, PIPE, "|")                   -- 还原字面竖线
    return s
  end

  -- history 是"新→旧"（insert 到 1），显示要"旧→新"。
  -- 返回**行数组**（不是拼好的整串）：逐行渲染 + 按行选择都要按索引取行，
  -- 拼串只在真正要复制/打印时做（table.concat(lines, "\n")）。
  local function Compose(frame)
    local hist  = (frame and frame.pfHistory) or {}
    local n     = table.getn(hist)
    local plain = (pfUI.chatcopy.format == "plain")
    local memo  = {}          -- 本次填充内 名字→标签 的备忘（同名只解析一次）
    local out   = {}

    for k=1, n do
      local s = Decorate(hist[n - k + 1], memo)
      if plain then s = Strip(s) end
      out[k] = s
    end
    return out, n
  end

  -- 复制到剪贴板。有 SetClipboardText 就直连（不选、不聚焦，最干净）；
  -- 没有就把文本塞进 EditBox 全选，让用户按 Ctrl+C（本客户端未知，两条都要留）。
  -- 返回 true = 已经复制好了；false = 走了 Ctrl+C 退路（调用方负责提示）。
  local function CopyText(text)
    if type(_G.SetClipboardText) == "function" then
      if pcall(_G.SetClipboardText, text) then return true end
    end
    return false
  end

  -- ==========================================================================
  -- 二、复制窗口
  -- ==========================================================================
  local function Build()
    if win then return win end

    local f = CreateFrame("Frame", "pfChatCopyWindow", UIParent)
    f:SetWidth(640)
    f:SetHeight(420)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() this:StartMoving() end)
    f:SetScript("OnDragStop",  function() this:StopMovingOrSizing() end)
    f:Hide()

    -- Esc 关窗（照 RurutiaSuite 的做法）：注册进 UISpecialFrames，按 Esc 由客户端关。
    -- ⚠️ 只在 Build 里登记一次，别每次 Open 都 insert —— 表会越滚越大，
    --    客户端的 CloseSpecialWindows 每次都遍历它。
    -- ⚠️ EditBox 有焦点时 Esc 会先被 EditBox 吃掉，所以 edit 的 OnEscapePressed
    --    也挂了隐藏，两条路都通。
    if type(_G.UISpecialFrames) == "table" then
      local dup = false
      for k=1, table.getn(_G.UISpecialFrames) do
        if _G.UISpecialFrames[k] == "pfChatCopyWindow" then dup = true break end
      end
      if not dup then table.insert(_G.UISpecialFrames, "pfChatCopyWindow") end
    end

    CreateBackdrop(f)
    if f.backdrop then
      f.backdrop:SetBackdropColor(0, 0, 0, .92)
      f.backdrop:SetBackdropBorderColor(.35, .35, .35, 1)
    end

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    f.title:SetText("|cffffd100" .. T["Chat Copy"] .. "|r")

    -- 滚动区：pfUI 原生滚动框（自带滑块 + 滚轮）
    -- ⚠️ 下边界必须**高于状态行**（58 > 状态行顶端 ~53）：
    --    之前给到 40，而状态行锚在 36、实际占到 ~49 ⇒ 内容滚到底时最后一行
    --    正好落进提示文字那一带，两排字叠在一起（2026-09-13 截图实证）。
    local scroll = CreateScrollFrame("pfChatCopyScroll", f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 58)
    -- ⛔ 覆盖默认的 OnValueChanged（api/ui-widgets.lua:647 那版）：
    --    默认实现是 `SetVerticalScroll(v)` + `UpdateScrollState()`，而 UpdateScrollState
    --    里又 `slider:SetValue(GetVerticalScroll())` ⇒ SetValue → OnValueChanged →
    --    SetValue 来回弹，手感就是"黏、回弹、乱跳"。
    --    这里只做「滑块 → 滚动框」的单向同步，并留 pfSync 给程序化定位（PinScroll）用。
    --    ⚠️ 不去改 api 层：gui / addons / share 都在用同一个滚动框，动公共层风险太大。
    local slider = scroll.slider
    if slider then
      slider:SetScript("OnValueChanged", function()
        if this.pfSync then return end
        local v = this:GetValue()
        if type(v) ~= "number" then return end
        scroll:SetVerticalScroll(v)
      end)
    end
    f.scroll = scroll

    -- 滚动子帧：高度 = 文字实际高度（Fill 里量出来再设）
    local child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(MIRROR_W)
    child:SetHeight(1)
    scroll:SetScrollChild(child)
    f.content = child

    -- ① 显示层：**每一行一个 FontString**（不再是一整块）。
    --    为什么拆行（2026-09-13）：
    --      · "只想复制其中几句"需要**按行**命中 —— 拆行后每行自带精确的 y 与高度，
    --        不必再用 GetCursorPosition + 缩放换算去反推行号（那种做法遇到长消息折行必然错位）；
    --      · 每行的点击热区就是这一行自己，点哪行就是哪行，零误差；
    --      · 行 FontString 放进**子 frame**（子 frame 一定画在父 frame 自己的区域之上），
    --        层级压在 EditBox 之上 ⇒ 无论下面的选区高亮是什么颜色，都盖不住字。
    local fsFrame = CreateFrame("Frame", nil, child)
    fsFrame:SetAllPoints(child)
    fsFrame:SetFrameLevel(child:GetFrameLevel() + 2)
    f.fsFrame = fsFrame

    f.hits = {}      -- 行热区 Button 池（点击选择 + 选中底色 + 该行 FontString）

    -- 行点击：单击 = 切换该行选中；Shift+单击 = 从上次落点整段选中。
    -- ⚠️ 用全局 this（本客户端 SetScript 回调不传 self），this.pfIndex = 行号。
    local function OnLineDown()
      if not win then return end
      local i = this.pfIndex
      if not i then return end

      local sel = win.selected
      if IsShiftKeyDown() and win.anchor then
        local a, b = win.anchor, i
        if a > b then a, b = b, a end
        for k=a, b do sel[k] = true end
      else
        sel[i] = (not sel[i]) or nil
        win.anchor = i
      end
      -- 选区一变，之前 arm 好的那份文本就作废了 ⇒ 提示必须跟着收。
      -- 否则窗口上还举着「已全选，按 Ctrl+C」，而此刻按下去复制到的是**旧的选区内容**，
      -- 跟眼前高亮的行根本对不上（"复制出来不是我选的"这类怪现象的来源之一）。
      -- 只在真的 arm 过时才 Disarm：非 arm 状态点行不该被动焦点（文本模式下尤其）。
      if win.armedText or win.armUntil then f.Disarm() end
      win:PaintSelection()
    end

    -- 行上的滚轮：转发给滚动框。
    -- 行热区铺满了文字区，滚轮事件会落到鼠标下的那个 Button 上，
    -- 不转发的话"鼠标停在文字上就滚不动"。
    local function OnLineWheel()
      if win and win.scroll then win.scroll:Scroll((arg1 or 0) * 10) end
    end

    f.MakeLine = function(i)
      -- 父级必须是 fsFrame（不是 child）：退路形态要能**一次 Hide 掉所有行**，
      -- 否则 EditBox 的字会和行文字叠在一起。
      local b = CreateFrame("Button", nil, fsFrame)
      b:SetWidth(MIRROR_W)
      b:SetHeight(16)
      b:SetFrameLevel(fsFrame:GetFrameLevel() + 1)
      b.pfIndex = i

      b.bg = b:CreateTexture(nil, "BACKGROUND")
      b.bg:SetAllPoints(b)
      b.bg:SetTexture(.25, .45, .85, .45)
      b.bg:Hide()

      b.fs = b:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
      b.fs:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
      b.fs:SetWidth(MIRROR_W)
      b.fs:SetJustifyH("LEFT")
      b.fs:SetJustifyV("TOP")
      b.fs:SetTextColor(1, 1, 1, 1)

      b:SetScript("OnMouseDown", OnLineDown)
      if b.EnableMouseWheel then b:EnableMouseWheel(1) end
      b:SetScript("OnMouseWheel", OnLineWheel)
      return b
    end

    -- ② EditBox：不再负责显示（文字由上面的逐行 FontString 画），只在两种情况下出场：
    --      · 没有 SetClipboardText 时的 **Ctrl+C 退路**（把文本塞进来 + 全选）；
    --      · 逐行渲染自检**没通过**时的**兜底显示**（宁可拖选发灰，也绝不出现一片空白）。
    --    层级压到最低（child 本身），保证任何情况下都不会盖住行文字。
    local edit = CreateFrame("EditBox", nil, child)
    edit:SetFrameLevel(child:GetFrameLevel())
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextColor(1, 1, 1, 1)
    edit:SetWidth(MIRROR_W)
    edit:SetHeight(1)
    edit:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    -- ⛔ 上限必须**显式给足**（照参考实现的 `math.max(524288, #text+1)`）：
    --    本客户端 EditBox 若被默认上限卡住，`SetText` 会**静默截断** ——
    --    200 行大约十几 KB，被截一半就等于"复制内容不全"，且没有任何报错。
    if edit.SetMaxLetters then pcall(edit.SetMaxLetters, edit, 524288) end
    -- 不接鼠标：文字区已被逐行热区铺满，剩下那点空白让滚轮落到滚动框上
    -- （EditBox 默认 EnableMouse，会把这部分滚轮事件吃掉）。SetFocus 是独立机制，不受影响。
    if edit.EnableMouse then pcall(edit.EnableMouse, edit, false) end
    -- 文本模式下它铺满整个区域且 EnableMouse(true)，滚轮会落到它身上 ⇒ 不转发行选
    -- 模式那套 OnMouseWheel，文本模式就"滚不动"。行选模式它没接鼠标，轮不到它。
    if edit.EnableMouseWheel then pcall(edit.EnableMouseWheel, edit, 1) end
    edit:SetScript("OnMouseWheel", function()
      if win and win.scroll then win.scroll:Scroll((arg1 or 0) * 10) end
    end)
    edit:SetScript("OnEscapePressed", function()
      edit:HighlightText(0, 0)
      edit:ClearFocus()
      f:Hide()
    end)
    -- Ctrl+C 回执：引擎的复制动作在 C 侧，Lua 收不到"已复制"事件，
    -- 只能靠按键回调侧面确认（1.12 的 frame 有 OnKeyDown，本插件 buyemall 已在用）。
    -- ⚠️ 这里只"记一笔"，不拦按键、不改引擎默认的复制行为。
    edit:SetScript("OnKeyDown", function()
      local key = arg1
      if win then win.sawKey = true end     -- 诊断用：证明这台客户端确实派发 OnKeyDown
      if type(key) ~= "string" then return end
      key = string.upper(key)
      -- Ctrl+C / Ctrl+Insert 都是标准"复制"；命中就当作完成
      if (key == "C" or key == "INSERT") and IsControlKeyDown() then
        pcall(f.FinishCopy, f)
      end
    end)
    -- 焦点一丢 = 这一轮 arm 作废，提示同步收走。
    -- ⛔ 这条专门对付「点了按钮没反应」：arm 之后 EditBox 占着键盘焦点，
    --    点界面上别处时，那一次点击有可能先被"取消焦点"吃掉再没落到按钮上；
    --    更关键的是 —— 焦点没了，Ctrl+C 也已经不可能再进到 EditBox，
    --    此时提示还挂着「已全选，按 Ctrl+C」就是**骗人**。
    --    收掉之后：提示消失（用户看到反馈），第二次点击正常落到按钮。
    edit:SetScript("OnEditFocusLost", function()
      if win and (win.armedText or win.armUntil) then
        pcall(f.Disarm, f)
      end
    end)
    f.edit = edit

    -- 按钮
    local function Button(label, x, w, fn)
      local b = CreateFrame("Button", nil, f)
      b:SetHeight(20)
      b:SetWidth(w)
      b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 12)
      CreateBackdrop(b, 2)
      if b.backdrop then
        b.backdrop:SetBackdropColor(.12, .12, .12, 1)
        b.backdrop:SetBackdropBorderColor(.45, .45, .45, 1)
      end
      b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
      b.label:SetText(label)
      b:SetScript("OnClick", fn)
      b:SetScript("OnEnter", function()
        if this.backdrop then this.backdrop:SetBackdropColor(.28, .28, .28, 1) end
      end)
      b:SetScript("OnLeave", function()
        if this.backdrop then this.backdrop:SetBackdropColor(.12, .12, .12, 1) end
      end)
      return b
    end

    -- 选中状态：selected[行号] = true。行号是**显示顺序**（1 = 最旧、末尾 = 最新）。
    f.selected = {}
    f.anchor   = nil      -- Shift+点击的区间起点

    -- 当前窗口的完整文本（行数组优先；退路形态下退回 EditBox 里的内容）
    -- ⚠️ 判据用 lineText 是否存在，不用"行数 > 0"：空窗口时行数组是空表，
    --    拼出来就是 ""，而**不能**退回 EditBox（那里可能还残留着别的内容）。
    f.Text = function()
      if win.lineText and win.lineCount then return table.concat(win.lineText, "\n") end
      return (win.edit:GetText() or "")
    end

    -- 只拼被选中的那几行
    f.SelectedText = function()
      local sel = win.selected
      local buf, n = {}, 0
      for i=1, (win.lineCount or 0) do
        if sel[i] and win.lineText[i] then n = n + 1; buf[n] = win.lineText[i] end
      end
      if n == 0 then return nil, 0 end
      return table.concat(buf, "\n"), n
    end

    -- 重绘选中底色 + 状态行
    f.PaintSelection = function()
      local sel, cnt = win.selected, 0
      for i=1, (win.lineCount or 0) do
        local b = win.hits[i]
        if b then
          if sel[i] then cnt = cnt + 1; b.bg:Show() else b.bg:Hide() end
        end
      end
      win.selCount = cnt
      -- ⛔ DoCopy/ArmClipboard 之后几秒内不要覆盖状态行：否则
      --    "已全选，请按 Ctrl+C" 会被"200 行"立刻顶掉（Fill 常被 QueueRefill 追上），
      --    用户根本来不及看见该按什么。countLock 由 ArmClipboard 设置。
      if win.countLock and GetTime() < win.countLock then return end
      local plain = (win.lineCount or 0) .. " " .. T["lines"]
      if cnt > 0 then
        win.count:SetText(plain .. "  |cff88ff88" .. T["Selected"] .. " " .. cnt .. "|r")
      else
        win.count:SetText(plain)
      end
    end

    -- 写入 EditBox 并**回读校验**（文本模式的显示/复制全都来自 EditBox）。
    -- ⛔⛔ EditBox 有字母上限，超出就**静默截断**、连一条报错都没有 ⇒ 用户看到的就是
    --     "文本模式显示的行比行选少"（2026-10-28 实证）。所以每次写完都必须回读量一遍，
    --     把真实容量记在窗口上：界面能提示、诊断能看、arm 时能拦住"复制半截"。
    f.ApplyText = function(txt)
      if not win or not win.edit then return end
      win.edit:SetText(txt)
      win.editText = txt
      win.textCap, win.textGap = nil, nil
      if win.edit.GetText then
        local okc, cur = pcall(win.edit.GetText, win.edit)
        if okc and type(cur) == "string" then
          win.textCap = string.len(cur)
          win.textGap = string.len(txt) - win.textCap
        end
      end
    end

    -- ------------------------------------------------------------------------
    -- 无剪贴板 API 时的唯一出路：把文本塞进 EditBox 全选，让用户按 Ctrl+C。
    -- ⛔ 三条硬约束（2026-10-28 定案，改之前先读）：
    --   ① **行选模式下绝不能把 EditBox 显出来**。本客户端选区高亮是 C 侧画的
    --      不透明 (96,96,96) 灰块、消不掉，但它跟 EditBox 自身 alpha 走同一条
    --      绘制路径 ⇒ α=0 时灰块也一起不画，屏幕上仍是干净的逐行文字；
    --      而焦点与选区数据在引擎里，**Ctrl+C 照样读得到**。
    --      旧实现在这里 `fsFrame:Hide()` + `edit:SetAlpha(1)`，等于主动把灰块请出来盖字，
    --      同时把干净的逐行显示收走 =「点了复制，满屏一块灰，还得自己按 Ctrl+C」。
    --   ② **文本模式下不要动 alpha**（那里 EditBox 本身就是显示层，α=0 等于把内容藏了），
    --      全选后让用户看得见选区，符合"文本模式"的预期。
    --   ③ `HighlightText()` **不带参数**才是全选；带 0 是"把光标移到开头"，两者别混。
    local function ArmClipboard(text)
      if not win.edit then return end
      -- 什么时候该让 EditBox 可见：
      --   · 文本模式（它本身就是显示层）
      --   · 行选模式但镜像自检没过（win.mirror=false ⇒ 文字只能靠 EditBox 画）
      -- 只有"行选 + 逐行画得出来"这一种情况才把 α 压到 0（屏幕上看不到灰块）。
      if opts.mode == "text" or not win.mirror then
        win.edit:SetAlpha(1)
      elseif opts.ghost == "0" then
        -- 兜底形态（/pfchatcopy ghost off）：把 EditBox 显出来、逐行收起。
        -- 会有那个消不掉的灰块，但至少"看得见选区 + Ctrl+C 一定读得到"。
        win.ghostHold = true
        if win.fsFrame then win.fsFrame:Hide() end
        win.edit:SetAlpha(1)
      else
        win.edit:SetAlpha(0)
      end
      -- 再保一次上限：文本比 524288 还长时按实际长度放开（照参考实现）
      if win.edit.SetMaxLetters and string.len(text) + 1 > 524288 then
        pcall(win.edit.SetMaxLetters, win.edit, string.len(text) + 1)
      end
      win.edit:SetText(text)
      win.edit:SetFocus()
      pcall(win.edit.HighlightText, win.edit)
      -- 回读校验（关键探针）：EditBox 是有**字母上限**的，超了就是静默截断、没有报错。
      -- 文本模式的"显示"和"复制"全都直接来自 EditBox ⇒ 一旦截断，
      -- 「文本模式复制出来的」和「行选模式复制出来的」就**必然不一样**
      -- （2026-10-28 用户实证）。这里量出这台客户端的真实上限并存到窗口上：
      --   · 诊断里能直接看（·EditBox上限= / ·缺口=）
      --   · 缺口>2 时给用户一句明确的警告，而不是悄悄复制半截内容
      win.editCap, win.editGap = nil, nil
      if win.edit.GetText then
        local okr, got = pcall(win.edit.GetText, win.edit)
        if okr and type(got) == "string" then
          win.editCap = string.len(got)
          win.editGap = string.len(text) - win.editCap
        end
      end
      -- armedText = "当前 EditBox 里已经全选好的那份文本"，Fill 靠它判断
      -- 要不要把选区洗掉（内容没变就保留，见 Fill 里的说明）；
      -- FinishCopy 靠它校验"按 Ctrl+C 之前内容有没有被误改"。
      win.armedText = text
      win.countLock = GetTime() + 3      -- 3 秒内别让状态行把提示顶掉
      -- arm 有效期（秒）。到点由 tip 的 0.25s 定时器收回焦点，见 Build 里那段。
      -- 为什么必须有：EditBox 握着焦点时玩家按 W/A/S/D 会被输进文本框，
      -- **全选状态下打一个字 = 整段被替换** ⇒ Ctrl+C 只剩那个字母。
      win.armUntil = GetTime() + 20
    end

    -- ------------------------------------------------------------------------
    -- Ctrl+C 的回执
    -- ⛔ 引擎的 Ctrl+C 是 C 侧处理的，Lua 收不到任何"已复制"事件，只能在
    --    OnKeyDown 里侧面确认。所以这里必须**校验内容有没有被误改**：
    --    EditBox 全选后玩家随手按一个键 = 替换掉整段选中内容，
    --    此时再按 Ctrl+C 复制到的就是一个字母（"复制出来是空的/只有一个字"
    --    这类怪现象的真因）。发现长度对不上就重新全选，让用户再按一次。
    f.FinishCopy = function()
      if not win or not win.edit then return end
      local want = win.armedText
      if not want then return end
      local wl = string.len(want)

      local cl = -1
      if win.edit.GetText then
        local ok, v = pcall(win.edit.GetText, win.edit)
        if ok and type(v) == "string" then cl = string.len(v) end
      end

      if cl >= 0 and wl > 4 and cl < wl - 2 then
        -- 长度**大幅变短** = 典型的"全选被一次按键替换掉"（变长只是多打了几个字，
        -- 危害小得多）。这时静默复制出去的就是一份错内容，必须复位重来。
        win.edit:SetText(want)
        pcall(win.edit.HighlightText, win.edit)
        win.armUntil = GetTime() + 20
        f.ShowTip("|cffff8844" .. T["Content was changed, re-selected - press Ctrl+C again"] .. "|r", 6)
        return
      end

      win.countLock = nil
      -- "再按一次"的窗口 = 提示的存活时间（两者同寿，到期由 Disarm 一并收走）。
      -- 有人习惯按两下 Ctrl+C，给 3 秒；再久就只是白占着键盘。
      win.armUntil  = GetTime() + 3
      f.ShowTip("|cff88ff88" .. T["Copied"] .. " " .. wl .. " " .. T["chars"] .. "|r", 3)
    end

    local function DoCopy(text)
      if not text or string.len(text) == 0 then
        f.ShowTip("|cffff8888" .. T["Nothing to copy"] .. "|r", 3)
        return
      end

      -- 首选剪贴板 API：不选、不聚焦，连一丝灰块都不会出现
      if CopyText(text) then
        win.armedText = text
        f.ShowTip("|cff88ff88" .. T["Copied"] .. " " .. string.len(text) .. " " .. T["chars"] .. "|r", 2)
        return
      end

      -- 退路：后台全选，屏幕上不出现任何灰块（见上面 ArmClipboard 的注释）。
      -- 回执走居中大字，hold 与 arm 有效期一致：提示消失 = 选区作废。
      ArmClipboard(text)

      -- 装不下就明说，别让用户拿着一份**悄悄被截断**的文本去粘贴
      -- （文本模式下这一截就是"文本模式复制出来的比行选少"的真因）。
      if win.editGap and win.editGap > 2 then
        f.ShowTip("|cffff8844" .. T["EditBox limit"] .. " " .. tostring(win.editCap) .. " "
          .. T["chars - content was truncated, use Line Mode"] .. "|r", 8)
        return
      end

      f.ShowTip("|cffffd100" .. T["All selected - press Ctrl+C to copy"] .. "|r  |cffaaaaaa("
        .. string.len(text) .. " " .. T["chars"] .. ")|r", 20)
    end

    f.btnCopy = Button(T["Copy All"], 12, 76, function()
      if win then DoCopy(win:Text()) end
    end)

    f.btnCopySel = Button(T["Copy Selected"], 92, 76, function()
      if not win then return end
      local text, n = win:SelectedText()
      if not text then
        win.count:SetText("|cffff8888" .. T["No lines selected"] .. "|r")
        return
      end
      DoCopy(text)
    end)

    f.btnClearSel = Button(T["Clear Selection"], 172, 56, function()
      if not win then return end
      -- 诊断计数：万一"点了没反应"，看 /pfchatcopy 里的「·清除点击」是 0 还是递增，
      -- 一眼分清是"回调没被触发"（点击被焦点吃掉 / 按钮被挡）还是"回调跑了但界面没变"。
      win.clearHits = (win.clearHits or 0) + 1
      -- ⛔ 顺序不能反，两步都要：
      --   ① 先作废 arm：提示/状态行锁/EditBox 里那份旧全选是一体的（Disarm 一起收）。
      --      不作废的话窗口上还挂着「已全选，按 Ctrl+C」，可这时 Ctrl+C 复制到的
      --      是一份跟当前选区无关的旧内容 —— 2026-10-28 用户实证"点清除选择提示不变"。
      --   ② 再清选区、再重绘：Disarm 已经把 countLock 清掉，PaintSelection 才不会被
      --      锁在那 3 秒里提前 return（否则状态行还写着"已选 N"）。
      if win.armedText or win.countLock or win.armUntil then f.Disarm() end
      win.selected = {}
      win.anchor   = nil
      win:PaintSelection()
    end)

    f.btnNext    = Button(T["Switch Window"], 232, 64, function() Cycle() end)
    -- ⚠️ Fill(true) = 用户主动刷新 ⇒ 重新定位到最新（否则缩在顶部看不出有没有刷新，
    --    这正是旧版"点刷新没反应"的直接原因：内容其实刷新了，但视口停在最旧那几行）
    f.btnRefresh = Button(T["Refresh"],       300, 48, function() Fill(true) end)
    f.btnMode    = Button(T["Text Mode"],     352, 56, function() ToggleMode(nil, true) end)
    f.btnClose   = Button(T["Close"],         412, 48, function() Close() end)

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.count:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 40)

    -- 静态操作提示：**右对齐**（不再是固定 x=250 左对齐）——
    -- 锚右下角后，无论左侧状态行多长（如"99 行  已选 3"）都不会撞上它；
    -- 纵坐标 40 = 状态行那一带，落在滚动区（下边界 58）之下，文字不再重叠。
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.hint:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 40)
    f.hint:SetTextColor(.6, .6, .6, 1)
    f.hint:SetText(T["Click a line to select, Shift+click for a range"])

    -- 空窗口提示（照 RurutiaSuite 的 "当前聊天窗口暂无可复制内容"）：
    -- 以前这个按钮点下去只开出一个空框 + "0 行"，用户不知道是没捕获到还是坏了。
    -- 放在标题下方、内容区顶部，与内容不重叠（空窗口时内容高 ~8px）。
    f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.empty:SetPoint("TOP", f, "TOP", 0, -100)
    f.empty:SetTextColor(.55, .55, .55, 1)
    f.empty:SetText(T["No messages in this window"])
    f.empty:Hide()

    -- ------------------------------------------------------------------------
    -- 复制回执浮层（居中、大字）
    -- ⛔ 前提：1.12 的 Lua **没有任何写系统剪贴板的途径**，插件也不能模拟按键
    --    （`SetClipboardText` 不存在；nampower / SuperWoWhook / UnitXP_SP3 / wsloot
    --    四个 DLL 里 clipboard / sendkey / SendInput / keybd_event / PostMessage
    --    全部零命中，2026-10-28 二次复核）⇒「点一下就进剪贴板」物理上做不到，
    --    只能"后台全选好 + 玩家按 Ctrl+C"。
    --    既然那一步免不掉，就必须把「该按什么」和「按完成没成」做成看得见的回执。
    --    以前只有左下角状态行变个颜色、3 秒后被"200 行"顶掉 ⇒ 玩家根本不知道
    --    发生了什么，这就是"点了复制为什么还要我自己按 Ctrl+C"的来源。
    -- ⛔⛔ 层级：提示必须装在**自己的子 Frame** 里，并且把 frameLevel 抬高。
    --    每一行文字是挂在 `scroll → content` 这个**子 Frame** 上的，而子 Frame
    --    永远画在父 Frame 自己的 region 之上 ⇒ 直接 `f:CreateFontString(...)`
    --    做出来的提示会被内容整片盖住（2026-10-28 用户截图实证：提示"被挡住了"）。
    --    ⚠️ 只把 f.tip 的 drawer 改成 OVERLAY 没用 —— 那是**同一个 Frame 内**的
    --    图层顺序，跨 Frame 一律比 frameLevel。
    f.tipFrame = CreateFrame("Frame", nil, f)
    f.tipFrame:SetAllPoints(f)
    f.tipFrame:SetFrameLevel(f:GetFrameLevel() + 20)   -- 高过 scroll/content/edit/按钮
    -- 不吃鼠标：否则整块浮层会把底下的按钮和拖选一起挡住
    f.tipFrame:EnableMouse(false)

    f.tip = f.tipFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    -- 贴底：就在刚点的那排按钮上方，视线不用跑。顶在图标题下会盖住最新的几行。
    f.tip:SetPoint("BOTTOM", f.tipFrame, "BOTTOM", 0, 64)
    f.tip:SetWidth(600)          -- ⛔ 不给宽度 = 宽度 0 → 逐字竖排换行
    f.tip:SetJustifyH("CENTER")
    f.tip:Hide()

    -- 深色底条：回执盖在内容区上方，没有底色会被行文字干扰
    f.tipBG = f.tipFrame:CreateTexture(nil, "OVERLAY")
    f.tipBG:SetTexture(0, 0, 0, .92)
    f.tipBG:SetPoint("TOPLEFT",     f.tip, "TOPLEFT",     -14,  6)
    f.tipBG:SetPoint("BOTTOMRIGHT", f.tip, "BOTTOMRIGHT",  14, -6)
    f.tipBG:Hide()

    -- hold = 显示多少秒后自动收起（nil = 一直留着，等下一次覆盖）
    f.ShowTip = function(text, hold)
      if not f.tip then return end
      f.tip:SetText(text)
      f.tip:Show()
      if f.tipBG then f.tipBG:Show() end
      -- ⛔ 时间戳记在**窗口表 f 上**，不写进 FontString：
      --    FontString 是引擎对象，能不能随便挂字段各版本不一致，别赌这个。
      --    （同理：它连 SetScript 都没有，见下面的 tipTimer。）
      f.tipUntil = hold and (GetTime() + hold) or nil
      f.tipOn    = true          -- 诊断用（不查 FontString:IsShown，少赌一个方法是否存在）
    end

    -- ⚠️ tipBG 是 f 的 Texture（不是 FontString 的子级），tip 隐藏时不会跟着走，
    --    必须成对处理 —— 否则会留一条黑杠挂在窗口上。
    f.HideTip = function()
      if f.tip then f.tip:Hide() end
      f.tipUntil = nil
      f.tipOn    = false
      if f.tipBG then f.tipBG:Hide() end
    end

    -- 作废 arm：清字段 + 收提示 + 交还键盘焦点。
    -- ⛔ 三件事必须一起做，缺一样就留下坏状态：
    --    只清字段 ⇒ 选区还挂在 EditBox 里，Ctrl+C 仍能复制到一份"没人认领"的旧文本；
    --    只收提示 ⇒ EditBox 继续占着键盘焦点，玩家按 W/A/S/D 会直接打进文本框；
    --    且**全选状态下打一个字就等于整段被替换**（下一轮 Ctrl+C 只剩那个字母）。
    -- ⇒ 统一约定：**提示的生命周期 = arm 的生命周期**，谁先结束谁作废。
    f.Disarm = function()
      if win then
        win.armedText = nil
        win.armUntil  = nil
        -- ⛔ countLock 也要清：它是"别让状态行顶掉提示"的锁，提示都收走了还锁着，
        --    状态行就会一直停在旧数字（用户实证：点「清除选择」后仍显示"已选 1"，
        --    因为 PaintSelection 在锁内提前 return，连重绘都被跳过）。
        win.countLock = nil
        if win.edit then
          pcall(win.edit.HighlightText, win.edit, 0, 0)
          pcall(win.edit.ClearFocus, win.edit)
        end
      end
      f.HideTip()
    end

    -- 回执/arm 到期的定时器（0.25s 节流）。
    -- ⛔⛔ 必须挂在一个**真正的 Frame** 上：1.12 的 FontString / Texture 都不是 Frame，
    --     身上**没有 SetScript 方法** ⇒ `tip:SetScript("OnUpdate", …)` 直接报
    --     "attempt to call method 'SetScript' (a nil value)"，Build 从这里中断，
    --     win 永远赋不上值 ⇒ 每次 Open 都重跑 Build、每次都报同一行（2026-10-28 实证，
    --     聊天框里连续 5 条同错）。
    -- ⚠️ 也不能挂窗口本身：窗口的 OnUpdate 是 QueueRefill 的地盘，SetScript 会互相顶掉。
    -- ⇒ 专用一个无边框小 Frame，随窗口显隐（父级就是 f）。
    -- ⛔ 到期一律走 f.Disarm，不再分开处理：提示和 arm 是一体的，
    --    以前 FinishCopy 把提示设成 2 秒、arm 设成 5 秒，结果提示先消失、
    --    后 3 秒里没人收焦点 —— 玩家这时按 W 就往文本框里打字。
    f.tipTimer = CreateFrame("Frame", nil, f)
    f.tipTimer:SetAllPoints(f)
    f.tipTimer:SetScript("OnUpdate", function()
      local now = GetTime()
      if (this.pfNext or 0) > now then return end
      this.pfNext = now + 0.25

      -- 提示到期 = 这一轮 arm 结束（无论是否真的按过 Ctrl+C）
      if f.tipUntil and now > f.tipUntil then
        f.Disarm()
        return
      end

      -- 兜底：提示被别的 ShowTip 顶掉而不自知时，arm 也不能无限期占着键盘
      if win and win.armUntil and now > win.armUntil then
        f.Disarm()
      end
    end)

    f:SetScript("OnHide", function()
      if pfChatCopyButton then
        pfChatCopyButton.state = false
        pfChatCopyButton.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Disabled")
      end
      -- 收起时把焦点/选区/"已全选"状态一并清掉（Disarm 三件一起做）
      if win then
        win.countLock = nil
        win.ghostHold = nil
      end
      -- ⛔ 关窗即作废 arm：否则下次打开时残留的 armedText 会让 Fill 误判成
      --    "用户已经 arm 过"而跳过清理；残留的焦点还会把 W/A/S/D 打进文本框。
      if f.Disarm then f.Disarm() end
    end)

    -- ------------------------------------------------------------------------
    -- 延迟重填：本客户端 FontString `SetText` 之后要**晚一拍**才排版，
    -- 同一帧取 GetHeight 拿到的是旧值或 0 ⇒ 行高算错 = 叠字 / 裁字。
    -- 所以凡是有行需要重新测量高度，就约一次短延迟的第二趟 Fill。
    -- ⛔ 全局只挂一个 OnUpdate（多次预约合并），否则 OnShow 与 Fill 会互相顶掉脚本。
    -- ⚠️ 1.12 的方法调用会传 self ⇒ 一律用 `x.QueueRefill(delay)` **点调用**，不要用冒号。
    f.QueueRefill = function(delay)
      if not win then return end
      delay = delay or .05
      local due = win.refillAt
      if due and (due - GetTime()) >= delay then return end   -- 已约了更晚的，别提前触发
      win.refillAt = GetTime() + delay
      if win.refillHooked then return end
      win.refillHooked = true
      win:SetScript("OnUpdate", function()
        if not this:IsShown() then
          this:SetScript("OnUpdate", nil)
          this.refillHooked, this.refillAt = nil, nil
          return
        end
        if GetTime() < (this.refillAt or 0) then return end
        this:SetScript("OnUpdate", nil)
        this.refillHooked, this.refillAt = nil, nil
        pcall(Fill)
      end)
    end

    -- ------------------------------------------------------------------------
    -- 滚动条状态：可滚范围 / 滑块可见性 / 滑块长度
    -- ------------------------------------------------------------------------
    -- ⛔ 不要调 `scroll:UpdateScrollState()`（api/ui-widgets.lua:652）：
    --      local m = f:GetHeight() + f:GetVerticalScrollRange()
    --    本客户端**未布局的帧 GetHeight 可能是 nil** ⇒ 这行直接抛错；调用点外面套着
    --    pcall ⇒ 错误静默吞掉 = 「打开一片空白 / 滚动条乱跳 / 拖到底弹回去」同一个根因。
    -- ⛔ 但矫枉不能过正（2026-10-28 踩坑，**整根滑动条消失**就是这里来的）：
    --    只信 `GetVerticalScrollRange()` 也不行 —— 布局没定稿时它返回 nil 或 0，
    --    一旦把这个当"没有可滚内容"就会 `slider:Hide()`，而此后没有任何东西会把它
    --    请回来（Fill 之后只有 QueueRefill 那一趟，也很可能同样读到 0）。
    --    所以拆两层：
    --      ScrollRange() —— 能算就算；引擎不给就走**几何兜底**（内容高 - 视口高）；
    --                       实在量不出来返回 nil（= 未知）
    --      SyncBar(r)    —— r 为 nil 时**一律不动**；只要可滚就先 Show 再算 thumb
    --                       （Show 必须排在 thumb 计算之前，否则 thumb 一 nil 整条不亮）
    f.ScrollRange = function()
      local sc = f.scroll
      if not sc then return nil end

      local engine
      if sc.GetVerticalScrollRange then
        local ok, v = pcall(sc.GetVerticalScrollRange, sc)
        if ok and type(v) == "number" and v > 0 then engine = v end
      end

      -- `f.contentH` = 这一次 Fill 亲手 SetHeight 的值，比 GetHeight 更可信
      --（本客户端隐藏/未布局的 frame GetHeight 会给 nil 或 1，那会把范围算成 0）
      local ch = f.contentH
      if type(ch) ~= "number" then
        ch = f.content and f.content.GetHeight and f.content:GetHeight()
      end
      local sh = sc.GetHeight and sc:GetHeight()

      -- ⛔ **几何值优先**，引擎值只当兜底（2026-10-28 切窗口一片空白后定案）：
      --    内容高是我们刚刚 `SetHeight` 的**真值**，而引擎的滚动范围要等下一次排版
      --    才更新 —— 从 200 行的窗口切到 128 行的窗口时，它还会先报旧（更大）的范围，
      --    照着它 `SetVerticalScroll` 就直接滚过新内容末尾 = 整屏空白，得手动往上翻。
      if type(ch) == "number" and type(sh) == "number" then
        local geom = ch - sh
        if geom < 0 then geom = 0 end
        return geom
      end

      return engine        -- 几何量不出来才退回引擎值
    end

    f.SyncBar = function(range)
      local sc = f.scroll
      if not sc then return end
      local sl = sc.slider
      if not sl then return end
      if range == nil then return end          -- 未知：保持原样，宁可不藏

      if range <= 0 then
        sl:Hide()
        sc.pfRange = 0
        return
      end

      -- ① 先让条子出现：后面任何一步算错都不能连累可见性
      sl:Show()

      -- ② min/max 只在范围真的变了才写：每帧重写会在用户拖动中途把滑块顶回去
      if sc.pfRange ~= range then
        sc.pfRange = range
        sl.pfSync  = true
        pcall(sl.SetMinMaxValues, sl, 0, range)
        sl.pfSync  = nil
      end

      -- ③ 滑块长度 = 视口 / 总内容
      local h    = sc.GetHeight and sc:GetHeight()
      local size = 12
      if type(h) == "number" and h > 0 then
        size = math.floor(h * (h / (h + range)))
        if size < 12 then size = 12 end
        if size > h  then size = h  end
      end
      local thumb = sl.thumb or (sl.GetThumbTexture and sl:GetThumbTexture())
      if thumb and thumb.SetHeight then pcall(thumb.SetHeight, thumb, size) end
    end

    -- 定位。where: "bottom"（最新）/ "top"（最旧）/ "keep"（保持当前偏移）
    -- 返回数字 = 这一趟真的定了位；返回 nil = 范围还没量出来，位置没动（pinTo 留着）
    f.PinScroll = function(where, offset)
      local sc = f.scroll
      if not sc then return end
      local sl = sc.slider

      local range = f.ScrollRange()
      if range == nil then
        f.SyncBar(nil)
        return nil
      end

      local off = offset
      if off == nil then
        if where == "bottom" then
          off = range
        elseif where == "keep" then
          off = sc.GetVerticalScroll and sc:GetVerticalScroll()
          if type(off) ~= "number" then off = 0 end
        else
          off = 0
        end
      end
      if off > range then off = range end
      if off < 0 then off = 0 end

      pcall(sc.SetVerticalScroll, sc, off)

      if sl and range > 0 then
        local cur
        if sl.GetValue then pcall(function() cur = sl:GetValue() end) end
        -- 值没变就别写：SetValue 会触发 OnValueChanged，来回写会让滑块"黏"
        if type(cur) ~= "number" or math.abs(cur - off) > 0.5 then
          -- pfSync 期间禁掉 OnValueChanged 回灌（见 Build 里覆盖的那版），避免来回弹
          sl.pfSync = true
          pcall(sl.SetValue, sl, off)
          sl.pfSync = nil
        end
      end

      f.SyncBar(range)
      return off
    end

    -- ------------------------------------------------------------------------
    -- 常驻轻量同步（0.25s，只在窗口显示时跑）
    -- ------------------------------------------------------------------------
    -- 解三类时序问题，都发生在"Fill 那一瞬间量不准"之后：
    --   · 布局晚一拍到位 ⇒ 滑块自己补出来（不然就永远不出现）
    --   · 内容变长/变短   ⇒ 滑块自己出现/收掉
    --   · 打开时没定上位（pinTo 还挂着）⇒ 补定一次
    -- ⚠️ 别挂到窗口上：窗口的 OnUpdate 是 QueueRefill 的地盘，SetScript 会互相顶掉。
    -- ⚠️ 本客户端方法调用会传 self ⇒ 一律点调用（x.Foo()），不要冒号。
    scroll.pfTick = 0
    scroll:SetScript("OnUpdate", function()
      if not f:IsShown() then return end
      local now = GetTime()
      if now - (this.pfTick or 0) < .25 then return end
      this.pfTick = now

      local r = f.ScrollRange()
      f.SyncBar(r)

      -- 自愈：视口被"旧范围"推到新内容之外（切窗口后一片空白就是这么来的）。
      -- 引擎晚一拍才修正范围，所以这里每 0.25s 校一次，超出就拉回底部。
      if r then
        local cur = f.scroll.GetVerticalScroll and f.scroll:GetVerticalScroll()
        if type(cur) == "number" and cur > r + 4 then
          f.PinScroll("bottom")
        end
      end

      -- 打开时范围没量出来、pinTo 没定上：等能算了再补一次
      if r and win and win.pinTo then
        if f.PinScroll(win.pinTo) ~= nil then win.pinTo = nil end
      end
    end)

    -- 滚轮 / 行热区转发都走这里。范围用 ScrollRange：
    -- 旧实现读 GetVerticalScrollRange()，读到 0 时整段判断全落空 ⇒ 滚轮也没反应。
    scroll.Scroll = function(self, step)
      local r = f.ScrollRange()
      if not r or r <= 0 then return end
      local cur = scroll.GetVerticalScroll and scroll:GetVerticalScroll()
      if type(cur) ~= "number" then cur = 0 end
      local new = cur - (step or 0)
      if new > r then new = r end
      if new < 0 then new = 0 end
      pcall(scroll.SetVerticalScroll, scroll, new)
      f.SyncBar(r)
    end

    -- 覆盖公共 UpdateScrollState（gui / addons / share 用的那份不动，只改本实例）
    scroll.UpdateScrollState = function()
      f.SyncBar(f.ScrollRange())
    end

    -- ⚠️ 必须在**窗口已显示**时才填：
    --   本客户端"隐藏/未布局"的 frame，GetStringWidth / GetHeight 都不可信
    --    （和 GetLeft/GetTop 全 nil 是同一类行为）。自检要是拿着不可信的数字去判，
    --    首次打开就会被误判成"镜像画不出来"，直接退回带灰块的旧形态。
    --    所以：显隐归 OnShow，填充也归 OnShow；再约一次短延迟重填，
    --    等客户端真正把布局算完，把行高与镜像判定的结果钉死。
    f:SetScript("OnShow", function()
      pcall(Fill)
      this.QueueRefill(.06)
    end)

    win = f
    return f
  end

  -- 把当前 source 的内容灌进窗口
  -- `force` = 用户主动点「刷新」⇒ 重新定位到最新（见 btnRefresh 处的注释）
  Fill = function(force)
    if not win or not source then return end

    -- 换窗口（点"切换窗口"或换标签）时清掉上一次的选中：行号是索引，
    -- 不清就会把"上一个窗口的第 3 行"错套到新窗口上。
    local resetScroll = false
    if win.lastSource ~= source then
      win.lastSource = source
      win.selected   = {}
      win.anchor     = nil
      win.pinTo      = "bottom"        -- 换源一律先看最新
      resetScroll    = true
    end
    if force then
      win.pinTo   = "bottom"
      resetScroll = true
    end

    -- ----------------------------------------------------------------------
    -- ⛔ 换窗口/刷新时**先把偏移归零**，末尾再定位到底。
    --    本客户端引擎的滚动范围要等下一次排版才更新：从 200 行的窗口切到 128 行的
    --    窗口时它会先报旧（更大）的范围，照着它定位就直接滚过新内容末尾 = 整屏空白，
    --    得手动往上翻才看得见（2026-10-28 用户截图实证）。
    --    归零不依赖任何测量，先保证"一定有字看得见"，这是兜底的兜底。
    -- ----------------------------------------------------------------------
    if resetScroll and win.scroll then
      pcall(win.scroll.SetVerticalScroll, win.scroll, 0)
      win.scroll.pfRange = nil          -- 让 SyncBar 重写 min/max
      win.contentH       = nil
    end

    local lines, n = Compose(source)

    -- 字体必须两步走：先 FontObject 兜底（保证一定有字体），读得到有效字号再 SetFont 覆盖。
    -- ⛔ 顺序不能反、也不能省掉第一步：只 SetFont 一旦不生效 = 什么都不画。
    local font, size, flags = source:GetFont()
    local hasFont  = font and size and tonumber(size) and tonumber(size) > 0
    local lineSize = (hasFont and tonumber(size)) or 14

    -- ----------------------------------------------------------------------
    -- ⛔⛔ EditBox 必须跟逐行 FontString 用**同一套字体**（2026-10-28 用户实证）
    --    EditBox 默认只套了 `ChatFontNormal` 模板，而聊天窗口自己的字号通常更大。
    --    字号不一致会连锁出三个现象，全都指向"文本模式看起来缺内容"：
    --      ① 两模式文字大小肉眼可见地不同（用户最先注意到的就是这个）；
    --      ② 同一份内容在 EditBox 里字更宽 ⇒ 折行更多 ⇒ 总高更大；
    --      ③ 于是超出我们给的 SetHeight 的部分被裁掉 ⇒ "文本模式显示的行更少"。
    --    所以字体要跟着 Fill 一起同步（换窗口/改聊天字号都能跟上），
    --    仍然两步走：先 FontObject 兜底，再 SetFont 覆盖。
    -- ----------------------------------------------------------------------
    if win.edit then
      pcall(win.edit.SetFontObject, win.edit, ChatFontNormal)
      if hasFont then pcall(win.edit.SetFont, win.edit, font, size, flags) end
    end

    local y, pool, needMeasure = 0, win.hits, false
    local unmeasured = 0          -- 还没拿到真实高度的行数（=0 说明 y 是实测值，可信）
    for i=1, n do
      local b = pool[i]
      if not b then b = win.MakeLine(i); pool[i] = b end
      b.pfIndex = i

      -- 字体两步走（同 EditBox 的规矩）
      pcall(b.fs.SetFontObject, b.fs, ChatFontNormal)
      if hasFont then pcall(b.fs.SetFont, b.fs, font, size, flags) end
      pcall(b.fs.SetTextColor, b.fs, 1, 1, 1, 1)

      -- ----------------------------------------------------------------------
      -- 行高必须"两趟"（2026-10-28 定案，别再改回一趟）：
      --   FontString:SetText 之后本客户端要**晚一拍**才排版，同一帧 GetHeight()
      --   拿到的是旧值或 0 ⇒ 行高算错并被 b.pfH 缓存住 = 行与行叠字 / 后面几行被裁。
      --   做法：文本一变先拿**估算值**撑住并打 pfNeedH 标记，下一趟 Fill（由
      --   QueueRefill 保证一定会来）再取真实 GetHeight 校正。
      -- ----------------------------------------------------------------------
      local want = lines[i] or ""
      -- 估算值只用来"撑到下一趟"：真实行高 ≈ 字号 + 1~2（14 号字实测 14~15px）。
      -- ⛔ 别再用 1.35×字号：那是 2026-10-28 上一版为了"治缺行"放大出来的，
      --    而文本模式常常量不到真实高度（下面有说明），142 行 × 多算 6px = 800px
      --    ⇒ 滚到底就是一大片（战斗记录那种不折行的短句尤其明显）。
      local est  = lineSize + 2

      if b.pfText ~= want or b.pfFont ~= font then
        pcall(b.fs.SetText, b.fs, want)
        b.pfText, b.pfFont = want, font
        b.pfH     = est
        b.pfEst   = true                 -- 这一行的高度还是估算值（判定"y 可不可信"用）
        b.pfNeedH = true
        b.pfTry   = 0
        needMeasure = true
      elseif b.pfNeedH then
        b.pfTry = (b.pfTry or 0) + 1
        local okH, v = pcall(b.fs.GetHeight, b.fs)
        if okH and type(v) == "number" and v >= 1 then
          b.pfH     = v
          b.pfEst   = nil                -- 拿到真实高度，估算值作废
          b.pfNeedH = nil
        elseif b.pfTry < 4 then
          needMeasure = true               -- 还没排完，下一趟再试
        else
          b.pfNeedH = nil                  -- 试了 3 次还量不出来就认了，用估算值
        end
      end
      if b.pfEst then unmeasured = unmeasured + 1 end

      local h = b.pfH or est
      if h < 1 then h = est end

      b:SetHeight(h)
      if b.pfY ~= y then
        b.pfY = y
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", win.content, "TOPLEFT", 0, -y)
      end
      b:Show()
      y = y + h
    end

    -- 多余的行收起来（池只增不减，避免反复创建销毁）
    local old = table.getn(pool)
    for i=n+1, old do
      if pool[i] then
        pool[i]:Hide()
        pool[i].bg:Hide()
        pool[i].pfIndex = nil
      end
    end

    win.lineText  = lines        -- 行文本：复制"全部/选中"都按索引从这里取，不再依赖 EditBox
    win.lineCount = n
    if y < 1 then y = n * 15 + 8 end
    win.rowsH = y                -- 逐行 FontString 累加出的总高（诊断用，别当 EditBox 真值）
    -- ⛔ y 只有在"每一行都量到了真实高度"时才能当真值用。
    --    只要还有估算行在里边，y 就是偏大的，拿去设内容高 = 底部凭空多出空白。
    win.rowsUnmeasured = unmeasured
    win.rowsMeasured   = (unmeasured == 0)

    local joined = table.concat(lines, "\n")

    -- ----------------------------------------------------------------------
    -- 显示形态
    -- ----------------------------------------------------------------------
    if opts.mode == "text" then
      -- 文本模式：EditBox 自己当显示层（可鼠标定位、拖选任意字句）
      -- ⛔ 高度必须"刚好包住文字"：给少了裁字，给多了就是内容区下方的一大片空白
      --    （滚动到底 = 整屏全空，用户 19:42 录屏）。字号已同步，这里不再放大。
      --    两路取大，互为兜底：
      --      ① FontString 实测总高 × textpad（默认 1.0）+ 8：常规情形；
      --      ② 行数 × (字号+3) + 8：FontString 量不准/行数多而折行少时兜底。
      --    只留 8px 收边，滚到底最多多出一行内的空白。
      local ehByText = y * opts.textpad + 8
      local ehByFont = n * (lineSize + 3) + 8
      local eh = ehByText
      if ehByFont > eh then eh = ehByFont end
      win.fsFrame:Hide()
      win.edit:SetAlpha(1)
      -- ⛔ 文本模式**必须重新打开鼠标**：Build 里为让滚轮落到滚动框上，默认把
      --    EditBox 的鼠标关了（行选模式下文字区已被行热区铺满，不需要它）。
      --    不开的话文本模式整个是"只读"的，点不动也拖不动 = 白切。
      if win.edit.EnableMouse then pcall(win.edit.EnableMouse, win.edit, true) end
      win.edit:SetHeight(eh)
      win.content:SetHeight(eh)
      win.contentH = eh          -- 交给 ScrollRange 当真值用（别去问 GetHeight）
      win.textH    = eh          -- 诊断：文本模式的内容高（多出来的就是底部空白）
      -- 内容没变就别重 SetText：会打断用户正在进行的拖选
      -- ⛔⛔ 这里是"文本模式显示的行比行选少"的根源：EditBox 装不下就**静默截断**。
      --     处理成阶梯自愈，把能救的都救掉：
      --       ① 按当前上限写入 → 回读比对
      --       ② 有缺口 ⇒ 试 `SetMaxLetters(0)`（0 = 不限制，Blizzard 惯例）再写一次
      --       ③ 还不行 ⇒ 写回 524288 保住可用状态，打上 textCapped 标记，
      --          由界面那句提示明说"只能显示前 N 字符，完整内容请用行选"
      --     绝不留下"看着少了半截、却一个字都不提示"的状态。
      if win.editText ~= joined then
        win.textCapped = nil
        win.ApplyText(joined)
        if (win.textGap or 0) > 2 then
          if win.edit.SetMaxLetters then
            pcall(win.edit.SetMaxLetters, win.edit, 0)
            win.ApplyText(joined)
            if (win.textGap or 0) > 2 then
              -- 这台客户端不认 0（可能理解成"不许输入"）：退回显式大值
              pcall(win.edit.SetMaxLetters, win.edit, 524288)
              win.ApplyText(joined)
            end
          end
          win.textCapped = ((win.textGap or 0) > 2) and true or nil
        end
      end
      win.mirror = false

    else
      -- 行选模式：逐行 FontString 当显示层，EditBox 隐到 α=0
      win.content:SetHeight(y)
      win.edit:SetHeight(y)
      win.contentH = y           -- 同上：这是本次 Fill 亲手设的高度，最可信
      win.textH    = nil         -- 行选模式没有"文本高"这回事
      win.editText = nil
      -- 行选模式的文字由逐行 FontString 提供、**不经过 EditBox** ⇒ 上限对它没影响。
      -- 必须把文本模式的截断标记清掉，否则那句"只能显示前 N 字符"会跟着跑到行选模式里。
      win.textCapped, win.textGap, win.textCap = nil, nil, nil
      -- 行选模式下文字区已被行热区铺满，EditBox 不该再吃鼠标（否则滚轮失灵）
      if win.edit.EnableMouse then pcall(win.edit.EnableMouse, win.edit, false) end

      -- 运行期自检（这几种失败在客户端里全是**静默**的，只能填完之后验）：
      --   逐行画得出来 ⇒ EditBox 隐到 α=0（连选区灰块一起看不见），文字由行 FontString 提供；
      --   画不出来     ⇒ 退回"EditBox 自己显示"
      --                  （宁可拖选发灰，也绝不出现"一片空白"这种比原来更糟的回归）。
      local mirror = false
      if n > 0 and win.hits[1] then
        local probe = win.hits[1].fs
        local _, pSize = probe:GetFont()
        local fw = 0
        if probe.GetStringWidth then pcall(function() fw = probe:GetStringWidth() or 0 end) end
        mirror = (pSize and pSize > 0 and fw > 0) and true or false
      end
      win.mirror = mirror

      if mirror then
        if win.ghostHold then
          -- /pfchatcopy ghost off 的兜底形态：EditBox 继续显形（带灰块），直到内容变了
          win.fsFrame:Hide()
          win.edit:SetAlpha(1)
          if win.armedText ~= joined then
            win.ghostHold = nil
            if win.Disarm then win.Disarm() else win.armedText = nil end
            pcall(win.edit.SetText, win.edit, "")
            win.fsFrame:Show()
            win.edit:SetAlpha(0)
          end
        else
          win.fsFrame:Show()
          win.edit:SetAlpha(0)
          -- ⛔ 已经 arm 好的全文别洗掉：用户可能刚好还没按 Ctrl+C，
          --    一次自动重填就把选区清了 = 白按一次。只有内容真的变了才清。
          --    清的时候提示必须一起收：不然"已全选，按 Ctrl+C"会挂在一份
          --    已经作废的选区上（新消息进来时这条几乎必现）。
          if win.armedText ~= joined then
            if win.Disarm then win.Disarm() else win.armedText = nil end
            pcall(win.edit.SetText, win.edit, "")
          end
        end
      elseif n > 0 then
        win.fsFrame:Hide()
        win.edit:SetAlpha(1)
        win.edit:SetText(joined)
      else
        -- 空窗口：行都收起来了，但 EditBox 里可能还留着上一次的内容，
        -- 不对付它，"复制全部"就会拿到别的窗口的残留文本。
        win.fsFrame:Show()
        win.edit:SetAlpha(0)
        win.edit:SetText("")
        if win.Disarm then win.Disarm() else win.armedText = nil end
      end
    end

    -- ----------------------------------------------------------------------
    -- 滚动定位
    -- ----------------------------------------------------------------------
    -- 有行还在等重新测量 ⇒ 约一趟短延迟的第二趟；这一趟**不改定位**（pinTo 留着），
    -- 等高度定稿再定位，避免"先按错高度滚到底、高度一变又跳一下"。
    if needMeasure then win.QueueRefill(.05) end

    -- ⛔ 定位默认"bottom"（看最新）—— 旧版固定回顶部，等于打开就看到 200 行里最旧的
    --    那一段，新消息全在下面看不见 ⇒ 用户点「刷新」感觉"没反应"（内容其实刷了）。
    --    2026-10-12 那次的"空白"是因为拿旧 range 滚到底；现在 PinScroll 量不出来就
    --    干脆不定位（返回 nil），并且测量没定稿前也不定位（上面 needMeasure 那段），
    --    所以不会再被"旧 range"推出视口。
    --    ⚠️ pinTo 只有**真的定上位**了才清：量不出来时留着，交给窗口的 0.25s 同步补。
    local pinned = win.PinScroll(win.pinTo or "keep")
    if pinned ~= nil and not needMeasure then win.pinTo = nil end

    -- 空窗口提示（照 RurutiaSuite 的做法）：内容区中央给一句，别让用户对着空框猜。
    -- 同一行也复用来报"文本模式装不下"—— 比起默默显示半截内容，明说一句更重要。
    if win.empty then
      if n == 0 then
        win.empty:SetText(T["No messages in this window"])
        win.empty:Show()
      elseif win.textCapped then
        win.empty:SetText("|cffff8844" .. T["Text mode shows only"] .. " "
          .. tostring(win.textCap or "?") .. " " .. T["chars - use Line Mode"] .. "|r")
        win.empty:Show()
      else
        win.empty:Hide()
      end
    end

    -- 工具栏随模式变脸：按钮上写"点它会切到哪个模式"，hint 写当前模式怎么操作
    if win.btnMode and win.btnMode.label then
      win.btnMode.label:SetText(opts.mode == "text" and T["Line Mode"] or T["Text Mode"])
    end
    if win.hint then
      win.hint:SetText((opts.mode == "text"
        and T["Drag to select text, then press Ctrl+C"]
        or  T["Click a line to select, Shift+click for a range"])
        .. "  |cff707070" .. T["Esc to close"] .. "|r")
    end

    -- 窗口名：pcall 保护 —— 拿不到名字不能连累整次填充
    local okName, nm = pcall(_G.GetChatWindowInfo, source:GetID())
    if not okName or not nm or nm == "" then nm = "Chat " .. source:GetID() end
    win.title:SetText("|cffffd100" .. T["Chat Copy"] .. "|r  |cffaaaaaa" .. nm .. "|r")
    win:PaintSelection()
  end

  Open = function(frame)
    local w = Build()

    -- 兜底：晚建的聊天窗口（进服后又新开的标签）也补挂记录器，否则它永远是空的
    EnsureCapture()

    source = frame or SELECTED_CHAT_FRAME or _G.ChatFrame1
    if not (source and source.pfHistory) then
      source = nil
      for i=1, (_G.NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame"..i]
        if cf and cf.pfHistory and table.getn(cf.pfHistory) > 0 then
          source = cf
          break
        end
      end
    end
    if not source then source = _G.ChatFrame1 end

    -- 显隐交给 Show，填充交给窗口的 OnShow（那里才是"已显示"的状态，量得准）。
    -- 已经开着就只重填，不重复 Show（Show 在已显示时不触发 OnShow）。
    -- 每次打开都定位到最新（旧版固定回顶部 ⇒ 打开看到的永远是 200 行里最旧那段，
    -- 新消息全在下面看不见，用户会以为"刷新没反应"。见 Fill 里的详细说明）
    w.pinTo = "bottom"
    if w:IsShown() then pcall(Fill) else w:Show() end

    if pfChatCopyButton then
      pfChatCopyButton.state = true
      pfChatCopyButton.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    end
  end

  Close = function()
    if win then win:Hide() end
  end

  -- 在"有历史的窗口"之间循环切换（综合 / 战斗记录 / 世界 …）
  Cycle = function()
    if not win then return end
    local n  = _G.NUM_CHAT_WINDOWS or 10
    local id = (source and source:GetID()) or 0

    for k=1, n do
      id = id + 1
      if id > n then id = 1 end
      local cf = _G["ChatFrame"..id]
      if cf and cf.pfHistory and table.getn(cf.pfHistory) > 0 then
        source = cf
        break
      end
    end
    Fill()
  end

  -- 行选模式 ←→ 文本模式（工具栏按钮 / `/pfchatcopy mode lines|text`）
  -- 两套形态各自解决一半问题，所以都留着：
  --   行选：点一行选一行、零灰块，适合"整段消息搬走"（日常用法）
  --   文本：原生 EditBox，能鼠标定位、拖选任意字句，适合"只抠一句话"
  ToggleMode = function(to, quiet)
    if to ~= "lines" and to ~= "text" then
      to = (opts.mode == "text") and "lines" or "text"
    end
    opts.mode = to
    pfUI_cache.chatcopy.mode = to

    -- 按钮切换靠 Fill 更新按钮文案就够了，别往聊天窗刷消息（命令调用才回一行确认）
    if not quiet then
      DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[chatcopy]|r mode=" .. to)
    end

    if not win then return end
    -- 换形态等于换一套显示层：行号/选区/EditBox 里那份全选文本全部作废，重来一遍
    win.selected, win.anchor   = {}, nil
    win.editText               = nil
    win.armUntil               = nil
    win.ghostHold              = nil
    if win.Disarm then win.Disarm() else win.armedText = nil end
    win.pinTo = "keep"          -- 切形态不该把用户正在看的位置顶走
    pcall(Fill)
  end

  -- ==========================================================================
  -- 三、聊天面板上的小按钮（左键开/关复制窗口）
  -- ==========================================================================
  local events = CreateFrame("Frame")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  events:SetScript("OnEvent", function()
    -- 给每个聊天窗口挂历史记录器（只挂一次）
    EnsureCapture()

    if pfUI.chat and pfUI.chat.left and not this.button then
      -- parent to pfUI.chat.left (stable), NOT panelTop:
      -- panelTop is shown/hidden + FCF_DockUpdate'd by the mouseover handler and
      -- jitters while chat content refreshes fast, making the button unclickable.
      local button = CreateFrame("Button", "pfChatCopyButton", pfUI.chat.left)
      button:SetPoint("TOPRIGHT", pfUI.chat.left, "TOPRIGHT", 0, -4)
      -- ⛔ 只注册左键：右键那套「聊天菜单」已按用户要求去掉
      --    （ChatMenu 会浮在聊天面板上，与复制按钮的用途重叠、容易误触）。
      button:RegisterForClicks("LeftButtonUp")
      button:SetWidth(16)
      button:SetHeight(16)
      button:SetAlpha(0)
      button.icon = button:CreateTexture(nil, "BACKGROUND")
      button.icon:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Disabled")
      button.icon:SetAllPoints()

      button:SetScript("OnClick", function()
        -- 左键：开/关**独立复制窗口**（内容 = 你正在看的那个聊天窗口）
        if win and win:IsShown() then
          Close()
        else
          Open(SELECTED_CHAT_FRAME)
        end
      end)

      -- 悬停只做提亮（按钮本身很淡），**不弹鼠标提示**
      button:SetScript("OnEnter", function()
        this:SetAlpha(1)
      end)

      -- 渐隐（平滑过渡到目标透明度）：
      --   复制窗口开着 → 1；鼠标悬停聊天面板 → 0.6；离开聊天区 → 0（与其他按钮一致）。
      -- 8/23 防抖修复把按钮父级从 panelTop（随悬停显隐）移到 pfUI.chat.left 后
      -- 按钮常驻显示，这里用 OnUpdate 插值补回渐隐观感。1.12 无动画组，手动插值。
      button.fadetarget = 0
      button:SetScript("OnLeave", function()
        this.fadetarget = MouseIsOver(pfUI.chat.left) and .6 or 0
        this:SetAlpha(this.fadetarget)
      end)

      button:SetScript("OnUpdate", function()
        if this.state then
          this.fadetarget = 1
        elseif MouseIsOver(pfUI.chat.left) then
          this.fadetarget = .6
        else
          this.fadetarget = 0
        end

        local cur, target = this:GetAlpha(), this.fadetarget
        if math.abs(target - cur) < .01 then return end

        -- 节流 ~25fps，指数逼近
        this.alphaTick = (this.alphaTick or 0) + arg1
        if this.alphaTick < .04 then return end
        this.alphaTick = 0
        this:SetAlpha(cur + (target - cur) * .25)
      end)

      this.button = button
    end

    this:UnregisterAllEvents()
  end)

  -- ==========================================================================
  -- 四、诊断与命令
  -- ==========================================================================
  local function ChainWalk(frame)
    local parts, n, eff = {}, 0, 1
    local f = frame
    while f and n < 8 do
      n = n + 1
      local a = (f.GetAlpha and f:GetAlpha()) or 1
      if type(a) == "number" and a > 0 and a < 1 then eff = eff * a end
      parts[n] = ((f.GetName and f:GetName()) or "?")
        .."(a=" .. (math.floor(a * 100) / 100)
        .. "," .. ((f.IsVisible and f:IsVisible()) and "可见" or "隐藏")
        .. ",lvl=" .. tostring((f.GetFrameLevel and f:GetFrameLevel()) or "?") .. ")"
      f = (f.GetParent and f:GetParent()) or nil
    end
    return table.concat(parts, " > "), eff
  end

  local function Diag()
    local out = DEFAULT_CHAT_FRAME

    for i=1, (_G.NUM_CHAT_WINDOWS or 10) do
      local cf = _G["ChatFrame"..i]
      if cf then
        local hist = cf.pfHistory
        local cnt  = hist and table.getn(hist) or 0
        local fsize = "?"
        if cf.GetFont then
          local _, sz = cf:GetFont()
          fsize = tostring(sz)
        end
        out:AddMessage("|cffffcc00[chatcopy]|r CF" .. i
          .. "｜历史=" .. cnt
          .. "｜字体=" .. fsize
          .. "｜可见=" .. (cf:IsVisible() and "是" or "否")
          .. ((SELECTED_CHAT_FRAME == cf) and "｜←当前" or ""))
      end
    end

    -- 窗口自身：开没开、镜像自检有没有过、剪贴板 API 在不在
    local ws = "未建"
    if win then
      local probe = (win.hits and win.hits[1] and win.hits[1].fs) or win.edit
      -- 滚动状态：偏移/上限。这两个数直接决定"打开空白"和"乱跳"是不是还在
      local sc, off, rng = win.scroll, "?", "?"
      if sc and sc.GetVerticalScroll then
        local a, b
        pcall(function() a = sc:GetVerticalScroll() end)
        if sc.GetVerticalScrollRange then pcall(function() b = sc:GetVerticalScrollRange() end) end
        off = (type(a) == "number") and tostring(a) or "nil"
        rng = (type(b) == "number") and tostring(b) or "nil"
      end
      -- 生效范围（ScrollRange 的结论：引擎给不出就走几何兜底）+ 滑块真身可见性。
      -- 「滑动条不见了」这类问题看这三项就够：
      --   ·滑块=隐藏 且 ·生效范围>0  ⇒ 是显示层的问题（Hide 被误调）
      --   ·生效范围=nil             ⇒ 这个客户端连内容高/视口高都量不出来
      local eff, shown, chh, shh = "?", "?", "?", "?"
      if win.ScrollRange then
        local r = win.ScrollRange()
        eff = (type(r) == "number") and tostring(r) or "nil"
      end
      if sc then
        if sc.slider then shown = sc.slider:IsShown() and "显示" or "隐藏" end
        local c1 = win.content and win.content.GetHeight and win.content:GetHeight()
        local c2 = sc.GetHeight and sc:GetHeight()
        chh = type(c1) == "number" and tostring(c1) or "nil"
        shh = type(c2) == "number" and tostring(c2) or "nil"
      end
      -- 还有多少行在等第二趟量高（正常应为 0；长期不为 0 = 这个客户端量不出来）
      local pend = 0
      if win.hits then
        for k=1, table.getn(win.hits) do
          if win.hits[k] and win.hits[k].pfNeedH then pend = pend + 1 end
        end
      end

      -- 两模式"复制内容不一样"的定位三件套：
      --   ·行文字数    = 按钮复制真正取的字符串长度（行选/文本都一样，来自 win.lineText）
      --   ·EditBox现有 = EditBox 此刻真实装着的字数（**实时回读**，不是缓存）
      --   ·EditBox上限 = 上次 arm 时回读到的字数
      --   ⇒ 「EditBox现有 < 行文字数」= 文本模式的显示/复制被静默截断，这就是两模式
      --      内容不一致的唯一可能原因（2026-10-28 用户反馈，先量再改，别猜）。
      local ebox = "-"
      if win.edit and win.edit.GetText then
        local okg, g = pcall(win.edit.GetText, win.edit)
        if okg and type(g) == "string" then ebox = tostring(string.len(g)) end
      end
      local allLen = "-"
      if win.lineText then allLen = tostring(string.len(table.concat(win.lineText, "\n"))) end

      -- 两模式文字大小必须一致（不同 = EditBox 没吃到源窗口字体 = 折行更多 = 底部被裁）
      local efs = "-"
      if win.edit and win.edit.GetFont then
        local okF, _f, _s = pcall(win.edit.GetFont, win.edit)
        if okF and type(_s) == "number" then efs = tostring(_s) end
      end

      ws = (win:IsShown() and "开" or "关")
        .. "·形态=" .. tostring(opts.mode)
        .. "·逐行=" .. tostring(win.mirror) .. "(true=文字由逐行 FontString 画)"
        .. "·EditBoxα=" .. (win.edit and (math.floor(win.edit:GetAlpha() * 100) / 100) or "?")
        .. "·行字号=" .. tostring(probe and select(2, probe:GetFont()))
        .. "·EditBox字号=" .. efs .. "(两者应完全相同)"
        .. "·行数=" .. tostring(win.lineCount)
        .. "·选中=" .. tostring(win.selCount)
        .. "·滚动=" .. off .. "/" .. rng
        .. "·滑块=" .. shown .. "·生效范围=" .. eff
        .. "·内容/视口=" .. chh .. "/" .. shh
        -- 文本模式"底部空白"定位：文本高 > 行高 说明内容区比实际文字高，
        -- 差值就是滚到底时那片空白的高度（≈ 视口高时 = 整屏全空）。
        .. "·文本高=" .. tostring(win.textH or "-")
        .. "·行文字总高=" .. tostring(win.rowsH or "-")
        .. "·textpad=" .. tostring(opts.textpad)
        .. "·armed=" .. tostring(win.armedText and string.len(win.armedText) or "无")
        .. "·按键回调=" .. tostring(win.sawKey and "有" or "无") .. "(有=这台客户端派发 OnKeyDown)"
        .. "·arm剩余=" .. (win.armUntil and tostring(math.floor(win.armUntil - GetTime())) or "-")
        .. "·提示=" .. tostring(win.tipOn and "显示" or "隐藏")
        .. "·清除点击=" .. tostring(win.clearHits or 0) .. "(点「清除选择」应递增)"
        -- 两模式"复制内容不一样"的定位三件套：
        --   ·行文字数  = 按钮复制真正取的字符串长度（行选/文本都一样，来自 win.lineText）
        --   ·EditBox上限 = 上次 arm 时 EditBox 实际吃下的字数（回读得到）
        --   ·缺口      > 0 ⇒ EditBox 装不下、被静默截断 ⇒ 文本模式必然比行选少
        .. "·模式=" .. tostring(opts.mode)
        .. "·行文字数=" .. allLen
        .. "·EditBox现有=" .. ebox .. "(<行文字数=文本模式被截断)"
        .. "·EditBox上限=" .. tostring(win.editCap or "-")
        .. "·文本缺口=" .. tostring(win.textGap or "-") .. "(>0=文本模式装不下、显示被截断)"
        .. "·缺口=" .. tostring(win.editGap or "-")
        .. "·待测高=" .. tostring(pend)
    end
    out:AddMessage("|cffffcc00[chatcopy]|r 窗口=" .. ws
      .. "｜来源=" .. tostring(source and source.GetName and source:GetName())
      .. "｜行数上限=" .. limit
      .. "｜格式=" .. tostring(pfUI.chatcopy.format)
      .. "｜ghost=" .. tostring(opts.ghost)
      .. "｜显示项: time=" .. tostring(opts.time)
      .. "/class=" .. tostring(opts.class)
      .. "/timefmt=" .. tostring(opts.timefmt)
      .. "｜剪贴板: SetClipboardText=" .. tostring(_G.SetClipboardText and "有" or "无")
      .. "/GetClipboardText=" .. tostring(_G.GetClipboardText and "有" or "无"))

    -- EditBox 能力边界探测（一次问清，别一次猜一个）
    local names = {"SetHighlightTexture", "SetHighlightColor", "SetSelectionColor",
                   "HighlightText", "SetCursorPosition", "SetTextInsets", "EnableMouse", "SetFocus"}
    local pe = {}
    for k=1, table.getn(names) do
      local nm = names[k]
      pe[k] = nm .. "=" .. (((win and win.edit and win.edit[nm]) and "有") or "无")
    end
    out:AddMessage("|cffffcc00[chatcopy]|r EditBox: " .. table.concat(pe, " "))

    -- FontString 侧（逐行渲染能不能画，全看这些）
    local probe2 = (win and win.hits and win.hits[1] and win.hits[1].fs) or nil
    local names2 = {"SetFontObject", "SetFont", "GetFont", "GetStringWidth", "GetHeight"}
    local pf = {}
    for k=1, table.getn(names2) do
      local nm = names2[k]
      pf[k] = nm .. "=" .. (((probe2 and probe2[nm]) and "有") or "无")
    end
    out:AddMessage("|cffffcc00[chatcopy]|r FontString: " .. table.concat(pf, " "))

    local list = {}
    if SELECTED_CHAT_FRAME then table.insert(list, SELECTED_CHAT_FRAME) end
    if _G.ChatFrame3 and _G.ChatFrame3 ~= SELECTED_CHAT_FRAME then table.insert(list, _G.ChatFrame3) end
    for k=1, table.getn(list) do
      out:AddMessage("|cffffcc00[chatcopy]|r 链> " .. (ChainWalk(list[k])))
    end
  end

  _G.SLASH_PFCHATCOPY1 = "/pfchatcopy"
  _G.SlashCmdList["PFCHATCOPY"] = function(msg)
    local out = DEFAULT_CHAT_FRAME
    -- ⚠️ 用形参 msg，不要用全局 arg1：SlashCmdList 是按 func(msg) 调的
    msg = msg or _G.arg1 or ""
    msg = string.gsub(msg, "^%s*(.-)%s*$", "%1")

    if msg == "" then Diag() return end
    if msg == "show" or msg == "window" then Open(SELECTED_CHAT_FRAME) return end

    if msg == "clear" then
      for i=1, (_G.NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame"..i]
        if cf and cf.pfHistory then cf.pfHistory = {} end
      end
      if win then Fill() end
      out:AddMessage("|cffffcc00[chatcopy]|r " .. T["Cleared"])
      return
    end

    local _, _, fmt = string.find(msg, "^format%s+(%a+)$")
    if fmt then
      if fmt == "plain" or fmt == "all" then
        pfUI.chatcopy.format = fmt
        if win then Fill() end
      end
      out:AddMessage("|cffffcc00[chatcopy]|r format=" .. tostring(pfUI.chatcopy.format))
      return
    end

    local _, _, mx = string.find(msg, "^max%s+(%d+)$")
    if mx then
      local n = tonumber(mx)
      if n and n > 0 then limit = n end
      out:AddMessage("|cffffcc00[chatcopy]|r max=" .. limit)
      return
    end

    -- 显示项：时间戳 / 职业·等级（持久化在 pfUI_cache，账号级）
    -- ⚠️ 必须放在 format / max 之后：`^(%a+)%s+(%S+)$` 也能匹配 "format plain"，
    --    放前面会把它们截胡。
    -- ⚠️ 用 `string.find` 的捕获，**不用 `string.match`**：本客户端是 Lua 5.0，
    --    它的 string 库没有 match（WoW 只补了全局别名 strmatch，不一定挂在 string 表上）。
    local _, _, key, val = string.find(msg, "^(%a+)%s+(%S+)$")
    if key and (key == "time" or key == "class") then
      local on = (val == "on" or val == "1")
      if val == "on" or val == "off" or val == "1" or val == "0" then
        opts[key] = on and "1" or "0"
        if win then Fill() end
      end
      out:AddMessage("|cffffcc00[chatcopy]|r " .. key .. "=" .. tostring(opts[key]))
      return
    end

    if key == "timefmt" then
      opts.timefmt = val
      if win then Fill() end
      out:AddMessage("|cffffcc00[chatcopy]|r timefmt=" .. tostring(opts.timefmt))
      return
    end

    -- 选取形态：/pfchatcopy mode lines|text
    if key == "mode" and (val == "lines" or val == "text") then
      ToggleMode(val)
      return
    end

    -- 文本模式高度余量：/pfchatcopy textpad 1.3
    -- 只在"文本模式底部还缺几行"时用得上（EditBox 静默裁字），行选模式不受影响。
    if key == "textpad" then
      local v = tonumber(val)
      if v and v >= 0.9 and v <= 2 then
        opts.textpad = v
        if win then Fill() end
      end
      out:AddMessage("|cffffcc00[chatcopy]|r textpad=" .. tostring(opts.textpad)
        .. "  |cffaaaaaa(文本模式内容高 = 行文字总高 × 该系数 + 8；1=不留空白，缺行才调大)|r")
      return
    end

    -- 静默全选开关：/pfchatcopy ghost on|off
    if key == "ghost" and (val == "on" or val == "off") then
      opts.ghost = (val == "on") and "1" or "0"
      if win then
        win.ghostHold = nil
        if win.Disarm then win.Disarm() else win.armedText = nil end
        pcall(Fill)
      end
      out:AddMessage("|cffffcc00[chatcopy]|r ghost=" .. tostring(opts.ghost)
        .. "（1=后台全选、屏幕无灰块；0=显示 EditBox、有灰块但一定能选中）")
      return
    end

    local n = tonumber(msg)
    if n and _G["ChatFrame"..n] then
      local lines, cnt = Compose(_G["ChatFrame"..n])
      local text = table.concat(lines, "\n")
      out:AddMessage("|cffffcc00[chatcopy]|r 窗口" .. n .. " 行数=" .. cnt
        .. " 前120字(竖线转义)：" .. (string.gsub(string.sub(text, 1, 120), "|", "||")))
      return
    end

    out:AddMessage("|cffffcc00[chatcopy]|r " .. T["Usage"]
      .. ": /pfchatcopy [show | clear | max <n> | format all|plain | mode lines|text | ghost on|off | textpad <0.9~2> | time on|off | class on|off | timefmt <格式> | <窗口号>]")
  end

  ----------------------------------------------------------------------------
  -- /pfchatscan —— 列出所有压在 ChatFrame1 上方的可见 frame（挖"灰块/黑块"用）
  ----------------------------------------------------------------------------
  _G.SLASH_PFCHATSCAN1 = "/pfchatscan"
  _G.SlashCmdList["PFCHATSCAN"] = function()
    local out = DEFAULT_CHAT_FRAME
    local cf  = _G.ChatFrame1
    if not cf or not cf:GetLeft() then
      out:AddMessage("|cffffcc00[chatscan]|r ChatFrame1 无几何信息")
      return
    end

    local l, r, t, b = cf:GetLeft(), cf:GetRight(), cf:GetTop(), cf:GetBottom()
    out:AddMessage("|cffffcc00[chatscan]|r ChatFrame1 rect=" .. l .. "," .. t .. "," .. r .. "," .. b)

    for i=1, (_G.NUM_CHAT_WINDOWS or 10) do
      local frame = _G["ChatFrame"..i]
      if frame then
        local bgT = _G["ChatFrame"..i.."Background"]
        local bg  = "无"
        if bgT then bg = (bgT:IsShown() and "显示" or "隐藏") .. "/" .. tostring(bgT:GetTexture()) end
        out:AddMessage("|cffffcc00[chatscan]|r CF" .. i
          .. " rect=" .. tostring(frame:GetLeft()) .. "," .. tostring(frame:GetTop())
          .. "," .. tostring(frame:GetRight()) .. "," .. tostring(frame:GetBottom())
          .. " a=" .. (math.floor(frame:GetAlpha() * 100) / 100)
          .. " 可见=" .. (frame:IsVisible() and "是" or "否")
          .. " 背景=" .. bg)
      end
    end

    if pfUI.chat and pfUI.chat.left then
      local p = pfUI.chat.left
      local bdc = "无"
      if p.backdrop and p.backdrop.GetBackdropColor then
        local br, bgc, bb, ba = p.backdrop:GetBackdropColor()
        bdc = tostring(br) .. "," .. tostring(bgc) .. "," .. tostring(bb) .. "," .. tostring(ba)
          .. "(" .. (p.backdrop:IsShown() and "显示" or "隐藏") .. ")"
      end
      out:AddMessage("|cffffcc00[chatscan]|r pfChatLeft rect=" .. tostring(p:GetLeft())
        .. "," .. tostring(p:GetTop()) .. "," .. tostring(p:GetRight()) .. "," .. tostring(p:GetBottom())
        .. " 背景色=" .. bdc)
    end

    local count = 0
    if type(EnumerateFrames) == "function" then
      local fr = EnumerateFrames()
      while fr do
        local fl, frr, ft, fb = fr:GetLeft(), fr:GetRight(), fr:GetTop(), fr:GetBottom()
        if fr ~= cf and fr:IsVisible() and fl and frr and ft and fb
           and frr > l and fl < r and ft > b and fb < t then
          local nm    = fr:GetName()
          local hasbd = fr.GetBackdrop and fr:GetBackdrop() and true or false
          if hasbd or (nm and string.find(nm, "Chat", 1, true)) then
            local bds = ""
            if hasbd and fr.GetBackdropColor then
              local br, bgc, bb, ba = fr:GetBackdropColor()
              bds = " 背色=" .. tostring(br) .. "," .. tostring(bgc) .. "," .. tostring(bb) .. "," .. tostring(ba)
            end
            out:AddMessage("|cffffcc00[chatscan]|r " .. tostring(nm) .. " 背=" .. tostring(hasbd) .. bds
              .. " strata=" .. tostring(fr.GetFrameStrata and fr:GetFrameStrata())
              .. " lvl=" .. tostring(fr.GetFrameLevel and fr:GetFrameLevel())
              .. " a=" .. (math.floor(fr:GetAlpha() * 100) / 100)
              .. " rect=" .. fl .. "," .. ft .. "," .. frr .. "," .. fb)
            count = count + 1
          end
        end
        fr = EnumerateFrames(fr)
      end
    end
    out:AddMessage("|cffffcc00[chatscan]|r 命中 " .. count .. " 个")
  end
end)
