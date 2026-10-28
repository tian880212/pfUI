-- 同一发送者的相同聊天消息在配置的间隔内只显示一次
--（在聊天设置里配置，间隔单位为秒，
-- 另有逗号分隔的永不过滤频道列表）
pfUI:RegisterModule("chatrepeatfilter", "vanilla:tbc", function()
  if C.chat.global.repeatfilter ~= "1" then return end

  -- 需要做重复判定的聊天消息事件
  local filtered = {
    ["CHAT_MSG_SAY"] = true,
    ["CHAT_MSG_YELL"] = true,
    ["CHAT_MSG_CHANNEL"] = true,
    ["CHAT_MSG_WHISPER"] = true,
    ["CHAT_MSG_EMOTE"] = true,
    ["CHAT_MSG_TEXT_EMOTE"] = true,
    ["CHAT_MSG_PARTY"] = true,
    ["CHAT_MSG_RAID"] = true,
    ["CHAT_MSG_RAID_LEADER"] = true,
    ["CHAT_MSG_RAID_WARNING"] = true,
    ["CHAT_MSG_GUILD"] = true,
    ["CHAT_MSG_OFFICER"] = true,
    ["CHAT_MSG_BATTLEGROUND"] = true,
    ["CHAT_MSG_BATTLEGROUND_LEADER"] = true,
  }

  -- 刷屏者经常改变重复字符的数量来绕过去重检测，
  -- 因此消息会先转换成归一化形式再比较
  local function Normalize(msg)
    msg = string.lower(msg)
    -- 去掉所有空白字符
    msg = gsub(msg, "%s+", "")
    -- 把连续重复字符折叠成一个（"MMMM..." 变成 "M"）。用函数实现，
    -- 因为 %1 反向引用后面不允许跟量词
    local prev
    msg = gsub(msg, "(.)", function(c)
      if c == prev then return "" end
      prev = c
      return c
    end)
    return msg
  end

  -- 记录每条消息最后显示的时间
  local shown = {}
  local lastpurge = 0
  local player

  -- 永不过滤的频道，以小写名称的查找表形式保存
  local excluded = {}
  local excluded_raw

  local function Trim(name)
    -- 允许直接粘贴聊天里看到的频道名（"4. 世界"）
    name = gsub(name, "^%d+%.%s*", "")
    return gsub(name, "^%s*(.-)%s*$", "%1")
  end

  local function LoadExcluded()
    for name in pairs(excluded) do excluded[name] = nil end
    -- 两种逗号都接受，但只按英文逗号切分：如果把多字节的中文逗号
    -- 放进字节类模式，会误伤与其尾字节相同的 utf-8 字符（如"界"）
    local list = gsub(C.chat.global.repeatfilterexclude or "", "，", ",")
    local names = { strsplit(",", list) }
    for _, name in pairs(names) do
      name = string.lower(Trim(name))
      if name ~= "" then excluded[name] = true end
    end
  end

  local function IsRepeat(frameid, eventtype, msg, sender, channel)
    -- 不过滤没有发送者的消息和玩家自己发的消息，
    -- 这样自己重复发布的内容（如广告）依然可见
    if not player then player = UnitName("player") end
    if not msg or not sender or sender == player then return false end

    -- 设置界面里的改动无需重载即可生效
    if excluded_raw ~= C.chat.global.repeatfilterexclude then
      excluded_raw = C.chat.global.repeatfilterexclude
      LoadExcluded()
    end

    -- 排除的频道始终放行
    if channel and excluded[string.lower(channel)] then return false end

    local interval = tonumber(C.chat.global.repeatfilterinterval) or 20
    if interval <= 0 then return false end

    local now = GetTime()

    -- 每个间隔清理一次过期记录，防止表无限增长
    if now - lastpurge > interval then
      lastpurge = now
      for key, timestamp in pairs(shown) do
        if now - timestamp > interval then
          shown[key] = nil
        end
      end
    end

    -- 去重键按聊天窗口区分：客户端会把每个聊天事件逐个分发给
    -- 订阅了它的聊天框，如果共用同一个键，第一个窗口就会用掉
    -- "只显示一次"的名额，其他窗口将永远看不到这条消息。
    -- 键中包含频道，让不同频道里的重复互不影响
    local key = frameid .. "\031" .. eventtype .. "\031" .. (channel or "") .. "\031" .. sender .. "\031" .. Normalize(msg)
    if shown[key] and now - shown[key] < interval then
      return true
    end

    shown[key] = now
    return false
  end

  -- 钩住全局聊天处理器。它会为每个显示该事件的聊天窗口各调用
  -- 一次（this 就是窗口），所以重复判定必须按窗口进行：
  -- 重复消息在每个窗口都被吞掉，而首条消息在所有窗口正常显示
  local original = ChatFrame_OnEvent
  _G.ChatFrame_OnEvent = function(event)
    -- 吞掉配置间隔内的重复消息
    if filtered[event] then
      local frameid = this and this.GetID and this:GetID() or 0
      if IsRepeat(frameid, event, arg1, arg2, arg9) then
        return
      end
    end

    original(event)
  end
end)
