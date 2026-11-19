-- load pfUI environment
setfenv(1, pfUI:GetEnvironment())

--[[ libticker ]]--
-- 共享的 OnUpdate 调度器（模型借鉴 EllesmereUI_Ticker.lua 的 arm/disarm 做法）。
--
-- 存在的理由（1.12 的现状）：
--   OnUpdate 是每个 frame 各挂一个脚本。模块多了以后必然出现三种浪费：
--     1) 每个模块自己拿 GetTime() 做节流，节流口径各写一遍；
--     2) 事件驱动的帧 Show 了忘记 Hide，空闲期照样每帧跑；
--     3) 同一份工作被 N 个 frame 各算一遍（每个 buff 条、每个图标一个 OnUpdate）。
--   这里把这些"按时间"的工作收敛到一个 driver frame：
--     * 只在有订阅者时 Show，最后一个 Remove 时 Hide ⇒ 隐藏帧在 1.12 不跑 OnUpdate，空闲期 0 开销。
--     * 每个订阅者一个 key；Add 幂等（同 key 再 Add = 换函数/换间隔，不重复登记）。
--     * 可选 interval：到点才跑，内部累计真实 dt ⇒ 模块不必再写 GetTime 比较。
--     * 允许在自己的 tick 里 Remove 自己（换位删除 + 遍历重测当前槽）。
--
-- 用法：
--   local ticker = pfUI.api.libticker
--   ticker:Add("buffwatch_player", function(dt) ... end, 0.2)  -- 约每 0.2s
--   ticker:Add("castbar_player",   function(dt) ... end)       -- 每帧
--   ticker:Remove("buffwatch_player")
--   ticker:Once("delayed_close", 0.5, function() ... end)      -- 一次性
--
-- ⛔ 订阅者契约：工作结束后必须自己 Remove（动画到目标、施法结束、CD 走完）。
--    这里不做"无事可做就自动摘掉"的魔法：只有最后一个 key 走了 driver 才 Hide，
--    留着空转的 key 等于留着空转的 OnUpdate。
-- ⛔ 不要在 tick 里做 SetPoint/布局（1.12 拖动/布局对时序敏感），只做数值与文本。
--
-- 诊断：/pfticker 列当前订阅者（含累计帧数/调用次数）；/pfticker test 自检。
--    自检通过 = Show/Hide、interval 累计、自摘除三条路径都正常。
--
-- ⛔⛔ 1.12 的脚本处理器**收不到形参**：引擎把 self 和参数放在全局 this / arg1 里，
--    写 `function(self, elapsed)` 拿到的 elapsed 恒为空。所以本文件的时间基准是
--    GetTime() 差分，不读形参也不读 arg1（读 arg1 在 TBC 之后会变，差分在所有端一致）。

-- return instantly when another libticker is already active
if pfUI.api.libticker then return end

local format = string.format
local lower = string.lower
local sub = string.sub
local type = type
local GetTime = GetTime

-- Create libticker driver
-- 挂 UIParent 并 SetAllPoints 只是为了拿到确定存在的非零区域；不挂任何纹理，
-- 默认不 EnableMouse ⇒ 不产生遮挡。隐藏状态（Hide）下 1.12 不会派发 OnUpdate。
local libticker = CreateFrame("Frame", "pfLibTicker", UIParent)
libticker:SetAllPoints(UIParent)
libticker:Hide()
pfUI.api.libticker = libticker
pfUI.ticker = libticker

-- 稠密数组 + 平行数组：count 是有效长度，index[key] 是槽位号。
-- 换位删除（把末尾搬到空出来的槽）保证 O(1)，代价是遍历时要重测当前槽。
-- calls 只用于诊断（/pfticker 能看到谁真的在跑），每次派发一次自增，成本可忽略。
local keys, funcs, delays, accs, ons, calls, starts = {}, {}, {}, {}, {}, {}, {}
local count = 0
local index = {}

-- 有效运行时间（"引擎真的在派发"的那部分墙钟），只给诊断当分母用。
-- ⛔ 别用 GetTime() 差值当分母：`/reload` 之后有约 2 秒加载画面，那段时间引擎不跑 OnUpdate，
--    但墙钟照走 ⇒ 所有"次/秒"被摊薄到 0.7 倍，看起来像节流失效（实测 8.9s 墙钟里只有 6.6s 在跑）。
-- ⛔ 也别用总 activeTime 当**单个 key** 的分母：key 是懒登记的（cooldown 文本要等第一次冷却、
--    buff 条要等第一条可见），登记前的运行时间不属于它，否则 0.1s 的订阅会显示成 8.3 次/秒，
--    看起来像"漏了几拍"。每个 key 记自己的 starts[i]，速率一律按 (activeTime - starts[i]) 算。
--    判据：三个不同间隔的"间隔 × 调用次数"应当彼此相等，那才是真的在按间隔跑。
local activeTime = 0

local function SlotAdd(key, fn, delay, oneshot)
  local i = index[key]
  if i then
    -- 已登记：只换实现，槽位、累计时间都不动（避免"重新 Add 就重启计时"）
    funcs[i], delays[i], ons[i] = fn, delay, oneshot
    return
  end

  count = count + 1
  keys[count] = key
  funcs[count] = fn
  delays[count] = delay
  accs[count] = 0
  ons[count] = oneshot
  calls[count] = 0
  starts[count] = activeTime        -- 登记时刻（有效运行时间），只用于诊断分母
  index[key] = count

  if count == 1 then
    libticker:Show()
  end
end

local function SlotRemove(key)
  local i = index[key]
  if not i then return false end

  local last = count
  if i ~= last then
    keys[i], funcs[i], delays[i], accs[i], ons[i], calls[i], starts[i] =
      keys[last], funcs[last], delays[last], accs[last], ons[last], calls[last], starts[last]
    index[keys[i]] = i
  end
  keys[last], funcs[last], delays[last], accs[last], ons[last], calls[last], starts[last] =
    nil, nil, nil, nil, nil, nil, nil
  index[key] = nil
  count = last - 1

  if count == 0 then
    libticker:Hide()
  end
  return true
end

-- 调度主体
-- 遍历时必须每步重读 count 并重测当前槽：订阅者可能在 fn 里摘掉自己或别人，
-- 被搬到当前槽的那个订阅者还没跑过，不能跳过。
--
-- ⛔⛔ 帧间隔必须三级回退拿（这是踩过坑的地方，别再"简化"）：
--   1.12 的脚本处理器**收不到形参** —— 引擎把 self/参数塞进全局 this、arg1，
--   写 `function(self, elapsed)` 拿到的 elapsed 恒为 nil（本仓库 screenshot.lua /
--   marktracking.lua 都用 `arg1` 就是这个原因）。第一版只读形参 ⇒ interval 永远
--   累计不到 0.1、只有"每帧订阅"在跑 ⇒ buff 计时器全体停摆且零报错。
--   所以：形参 → 全局 arg1 → GetTime() 差分，依次兜底。三者都拿不到时按 0 处理。
local lastTick = GetTime()
local startTime = lastTick
local frames = 0

libticker:SetScript("OnUpdate", function(self, elapsed)
  local dt = elapsed
  if type(dt) ~= "number" then
    dt = arg1                              -- 1.12：引擎把帧间隔放这里
  end
  if type(dt) ~= "number" then
    local now = GetTime()                  -- 端既不传参也不给 arg1 时自己算
    dt = now - lastTick
    lastTick = now
  end
  frames = frames + 1

  -- 只把"正常一帧"的时长计入有效运行时间：> 1s 的是卡顿/读蓝条/alt-tab，不算运行
  if type(dt) == "number" and dt > 0 and dt <= 1 then
    activeTime = activeTime + dt
  end

  -- 读条画面 / alt-tab 回来时 dt 可能是几十上百秒：夹上界，别让动画订阅者一帧跳到终点。
  -- 下界 0：同一毫秒内两次派发（不该有）时按 0 处理，只让每帧订阅者跑。
  if dt <= 0 then
    dt = 0
  elseif dt > 0.5 then
    dt = 0.5
  end

  local i = 1
  while i <= count do
    local key = keys[i]
    local fn = funcs[i]

    if fn then
      local delay = delays[i]
      if delay and delay > 0 then
        local acc = accs[i] + dt
        if acc >= delay then
          -- 余数结转（原来是清 0）：高帧率下 dt 几乎不可能整除 interval，
          -- 每轮清 0 都会白丢一点 ⇒ 0.100s 实际跑成 0.103s、0.020s 跑成 0.021s。
          -- 结转后长期平均严格等于 interval，代价是单次间隔可能略短。
          accs[i] = acc - delay
          if accs[i] >= delay then
            accs[i] = 0            -- 长时间卡顿后不补偿，避免连着补好几拍
          end
          -- ⛔ 自增必须放在"真正执行"这一支里：放在 fn 之前的外层会把"遍历到"当成"执行"，
          --    于是所有订阅的计数都等于 frames（诊断输出看起来像节流失效，实际没坏）。
          calls[i] = calls[i] + 1
          if ons[i] then
            SlotRemove(key)
          end
          fn(acc)
        else
          accs[i] = acc
        end
      else
        calls[i] = calls[i] + 1
        if ons[i] then
          SlotRemove(key)
        end
        fn(dt)
      end
    end

    if keys[i] == key then
      i = i + 1
    end
  end
end)

-- [ Add ]
-- 登记（或替换）一个周期性订阅。
-- 'key'      [string]     唯一键，建议 "模块名" 或 "模块名_单位"
-- 'fn'       [function]   回调，参数是本次累计的真实时间（秒）
-- 'interval' [number/nil] 可选；nil 或 0 = 每帧，>0 = 至少间隔这么久才跑
-- return:    [boolean]    登记是否成功
function libticker:Add(key, fn, interval)
  if not key or type(fn) ~= "function" then return false end
  if interval and (type(interval) ~= "number" or interval <= 0) then
    interval = nil
  end
  SlotAdd(key, fn, interval, false)
  return true
end

-- [ Once ]
-- 一次性订阅：到点跑一次并自动摘除。interval 省略 = 下一帧。
function libticker:Once(key, interval, fn)
  if type(interval) == "function" and fn == nil then
    fn, interval = interval, nil
  end
  if not key or type(fn) ~= "function" then return false end
  if type(interval) ~= "number" or interval < 0 then
    interval = nil
  end
  SlotAdd(key, fn, interval, true)
  return true
end

-- [ Remove ]
function libticker:Remove(key)
  return SlotRemove(key)
end

-- [ Has ]
function libticker:Has(key)
  return index[key] ~= nil
end

-- [ Count ]
function libticker:Count()
  return count
end

-- [ RemovePrefix ]
-- 批量摘除同一前缀的订阅（"buffbar:" 这类按单位/类型生成 key 的族）。
function libticker:RemovePrefix(prefix)
  if not prefix or prefix == "" then return 0 end
  local len = strlen(prefix)
  local doomed = {}
  local n = 0
  for i = 1, count do
    local key = keys[i]
    if key and sub(key, 1, len) == prefix then
      n = n + 1
      doomed[n] = key
    end
  end
  for i = 1, n do
    SlotRemove(doomed[i])
  end
  return n
end

-- [ Keys ]
-- 调试用快照（不要拿着它去 Remove，快照与实时槽位无关）。
function libticker:Keys()
  local out = {}
  for i = 1, count do
    out[i] = keys[i]
  end
  return out
end

-- [ Interval ]
-- 查询某订阅的间隔（nil = 每帧；未登记返回 false）。
function libticker:Interval(key)
  local i = index[key]
  if not i then return false end
  return delays[i]
end

-- [ Frames ]
-- driver 累计被派发的帧数（诊断用）。有订阅却一直是 0 = 帧没被引擎驱动。
function libticker:Frames()
  return frames
end

-- [ Calls ]
-- 某订阅累计被调用次数（诊断用）。
function libticker:Calls(key)
  local i = index[key]
  if not i then return false end
  return calls[i]
end

-- [ Span ]
-- 该订阅已经"有效运行"了多久（秒）。key 是懒登记的，登记前的时间不算它的。
-- 未登记返回 false。
function libticker:Span(key)
  local i = index[key]
  if not i then return false end
  local span = activeTime - (starts[i] or 0)
  if span < 0 then span = 0 end
  return span
end

-- [ Rate ]
-- 每秒实际执行次数 = 调用次数 / 自己的有效运行时间。判断 interval 是否真的生效就用它：
--   每 0.1s 的订阅应 ≈ 10；每帧订阅应 ≈ fps；显示成 100+ = interval 没吃到。
-- 未登记返回 false（不是 0：0 会被误读成"在跑但没执行"）。
function libticker:Rate(key)
  local i = index[key]
  if not i then return false end
  local span = activeTime - (starts[i] or 0)
  if span <= 0 then return 0 end
  return calls[i] / span
end

-- 诊断输出
local function Say(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99[libticker]|r " .. text)
end

local function PrintList()
  local n = libticker:Count()
  local wall = GetTime() - startTime
  local fps = 0
  if activeTime > 0 then
    fps = frames / activeTime
  end

  Say(format("订阅 %d 个 · driver %s · 累计派发 %d 帧",
    n, libticker:IsShown() and "运行中" or "休眠（0 开销）", frames))
  Say(format("  运行 %.1fs / 墙钟 %.1fs（%.0f%%）· 约 %.0f fps",
    activeTime, wall, wall > 0 and activeTime / wall * 100 or 100, fps))

  -- 这条是踩过坑才加的：有订阅但 frames 一直是 0 = 帧根本没被引擎驱动
  -- （父级不可见、被 Hide、或被别的插件 SetScript 覆盖），不是订阅者的错。
  if n > 0 and frames == 0 then
    Say("|cffff0000警告：有订阅但 driver 一帧都没跑过|r —— 检查 pfLibTicker 是否可见/脚本是否被覆盖")
  end

  -- "次/秒"这一列是判断节流是否真的生效的直接证据。分母用**该 key 自己的**有效运行时间：
  --   总 activeTime 会把 key 登记之前的时间也算进去（cooldown 文本要等第一次冷却、buff 条要等
  --   第一条可见），0.1s 的订阅就显示成 8.3 次/秒，看着像漏拍，其实一拍没漏。
  --   判据：每 0.1s 的订阅应 ~10 次/秒；每帧订阅应 ~fps；显示成 100+ = interval 没吃到。
  for i = 1, n do
    local delay = delays[i]
    local span = activeTime - (starts[i] or 0)
    local rate = 0
    if span > 0 then
      rate = calls[i] / span
    end
    Say(format("  %s%s · 已调用 %d 次（约 %.1f 次/秒，运行 %.1fs）", tostring(keys[i]),
      delay and format("  —  每 %.3fs", delay) or "  —  每帧", calls[i], rate, span))
  end
end

-- 自检：0.5s 一次，打印 4 行后自己摘除，末行报告 driver 是否已回到休眠。
-- 三条路径（interval 累计、回调执行、自动摘除 → Hide）任一坏了都会看出来。
local selftest = 0
local function RunSelfTest()
  selftest = 0
  Say("自检开始：登记 0.5s 间隔的临时订阅")
  libticker:Add("selftest", function(dt)
    selftest = selftest + 1
    Say(format("第 %d 次触发，累计 %.2fs（真实时间 %.2fs）", selftest, dt, GetTime()))
    if selftest >= 4 then
      libticker:Remove("selftest")
      if libticker:Count() == 0 then
        Say(format("自检结束：driver %s", libticker:IsShown() and "仍在运行（异常）" or "已休眠（正常）"))
      else
        Say(format("自检结束：已摘除，另有 %d 个订阅在跑", libticker:Count()))
      end
    end
  end, 0.5)
end

pfUI.api.RegisterSlashCommand("PFTICKER", {"/pfticker", "/pftick"}, function(msg)
  msg = lower(msg or "")
  if msg == "test" then
    RunSelfTest()
  else
    PrintList()
  end
end, true)
