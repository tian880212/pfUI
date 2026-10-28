pfUI:RegisterModule("raid", "vanilla:tbc", function ()
  -- do not go further on disabled UFs
  if C.unitframes.disable == "1" then return end

  -- tell RaidFrame.lua pfUI replaces party frames
  HookAddonOrVariable("Blizzard_RaidUI", function()
    GROUP_REPLACE_PARTY = "1"
  end)

  pfUI.uf.raid = CreateFrame("Frame", "pfRaidUpdater", UIParent)

  local maxraid = tonumber(C.unitframes.maxraid)
  -- raid pets have their own frame pool (unitframes.raidpetmax, default 20,
  -- cap 40). Pets no longer reserve member slots 41..50; the placeholder
  -- anchors pfRaid41..50 (light/lightH presets, api/config.lua migration)
  -- are still honoured as pet positions by PositionPetFrames.
  -- Stored as a table FIELD (pfUI.uf.raid.petmax), NOT a file-level local:
  -- new locals would add upvalues to every closure below (32 limit).
  pfUI.uf.raid.petmax = tonumber(C.unitframes.raidpetmax) or 20
  if pfUI.uf.raid.petmax > 40 then pfUI.uf.raid.petmax = 40 end
  if pfUI.uf.raid.petmax < 1 then pfUI.uf.raid.petmax = 20 end
  local rawborder, default_border = GetBorderSize("chat")
  local cluster = CreateFrame("Frame", "pfRaidCluster", UIParent)
  cluster:SetFrameLevel(20)
  cluster:SetWidth(120)
  cluster:SetHeight(10)
  cluster:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", default_border*2, C.chat.left.height + default_border*5)
  UpdateMovable(cluster)

  pfUI.uf.raid.tanksfirst = {
    ["PF_TANK_TOGGLE"] = { T["Toggle as Tank"], "toggleTank" }
  }

  -- no tank order for now, just "all tanks first"
  pfUI.uf.raid.tankrole = { }

  -- Resolve a raid member's pet unit id. This server exposes raid pets as
  -- "raidNpet" (ownerUnitId .. "pet"), with the standard "raidpetN" kept as
  -- a fallback for other implementations. The player's own pet is exposed
  -- as "pet" instead of "raidNpet". Returns unit, label, id.
  local function GetRaidPetUnit(raidIndex)
    local owner = "raid" .. raidIndex
    -- the player's own pet lives on "pet", not "raidNpet"
    if UnitIsUnit(owner, "player") and UnitExists("pet") then
      return "pet", "pet", ""
    end
    if UnitExists(owner .. "pet") then
      return owner .. "pet", "raid", raidIndex .. "pet"
    elseif UnitExists("raidpet" .. raidIndex) then
      return "raidpet" .. raidIndex, "raidpet", raidIndex
    end
    return nil
  end

  -- Assign (or clear) a pet unit on a pet frame. id == 0 clears the frame.
  local function SetRaidPetIndex(frame, id, label)
    if not frame then return end
    if frame.id ~= id or frame.label ~= label then
      frame.id = id
      frame.label = label
      frame.update_full = true
      frame.update_aura = true
    end
    frame:UpdateVisibility()
  end

  function pfUI.uf.raid:UpdateConfig()
    local rawborder, default_border = GetBorderSize("unitframes")
    maxraid = tonumber(C.unitframes.maxraid)
    self.petmax = tonumber(C.unitframes.raidpetmax) or 20
    if self.petmax > 40 then self.petmax = 40 end
    if self.petmax < 1 then self.petmax = 20 end
    for i=1,maxraid do
      local isNew = not pfUI.uf.raid[i]
      pfUI.uf.raid[i] = pfUI.uf.raid[i] or pfUI.uf:CreateUnitFrame("Raid", i, C.unitframes.raid)
      -- NotGrid 模式修复：布局刷新（GUI 下拉运行时触发）时绝不对「已显示、
      -- 已注册鼠标」的活动帧反复 SetParent。本客户端对活体安全按钮换父会让
      -- 它脱离引擎的鼠标命中桶 —— OnEnter 从此不触发，鼠标提示消失，只能
      -- /reload 重建帧才恢复（16:15 探针实证：改布局后 TT1 不触发，帧的
      -- parent/strata/mouse 状态却全部正常）。/reload 路径帧是新建+隐藏的，
      -- 换父无害，所以两条路径终态一致但只有运行时路径坏。
      -- 新帧仍需初始父级：custom 布局的成员框停留在 cluster 上。
      if isNew then
        pfUI.uf.raid[i]:SetParent(cluster)
      end
      pfUI.uf.raid[i]:SetFrameLevel(5)

      pfUI.uf.raid[i]:UpdateConfig()
      pfUI.uf.raid[i]:UpdateFrameSize()
    end

    local width = pfUI.uf.raid[1]:GetWidth()+2*default_border
    local height = pfUI.uf.raid[1]:GetHeight()+2*default_border
    local layout = pfUI.uf.raid[1].config.raidlayout
    local padding = tonumber(pfUI.uf.raid[1].config.raidpadding)*GetPerfectPixel()
    local fill = pfUI.uf.raid[1].config.raidfill
    local _, _, x, y = string.find(layout,"(.+)x(.+)")
    x, y = tonumber(x), tonumber(y)
    -- 自定义布局（custom）：不做任何网格推导，完全以手动拖动的存档位置为准
    local isCustom = layout == "custom"

    -- map a 1-based slot into (col,row) using the same order members use.
    -- VERTICAL / VERTICAL_REVERSE fill columns first (a column per group);
    -- VERTICAL_REVERSE mirrors the rows so group 1 ends up at the bottom.
    -- HORIZONTAL / HORIZONTAL_REVERSE fill rows first; HORIZONTAL_REVERSE
    -- mirrors the columns so group 1 ends up on the right.
    local function slotToCell(slot)
      if fill == "VERTICAL" or fill == "VERTICAL_REVERSE" then
        local col = floor((slot-1) / y) + 1
        local row = mod(slot-1, y) + 1
        if fill == "VERTICAL_REVERSE" then
          row = y - row + 1
        end
        return col, row
      else
        local col = mod(slot-1, x) + 1
        local row = floor((slot-1) / x) + 1
        if fill == "HORIZONTAL_REVERSE" then
          col = x - col + 1
        end
        return col, row
      end
    end

    -- Raid frames are a grid: exactly one slot carries the origin (the
    -- position the player dragged) and every other slot is offset from it by
    -- the layout math below.
    -- Unlock mode breaks that invariant: shift-dragging a raid frame selects
    -- pfRaid1..40 at once (see clusters in unlock.lua), and SaveMovable then
    -- writes an absolute position for every single one of them. On the next
    -- UpdateConfig, UpdateMovable() calls LoadMovable(), which restores those
    -- stale absolute positions right on top of the freshly computed grid --
    -- so changing raidlayout / raidfill / raidpadding or the frame size
    -- looked like it did nothing at all.
    -- Keep slot 1 as the only origin and drop the per-slot copies. Shift-drag
    -- still moves the whole raid: slot 1 records the very same offset, and
    -- the grid is rebuilt from it.
    -- Layout signature: only wipe the per-slot copies when a layout parameter
    -- actually changed. Unconditional clearing (the old behaviour) ran on
    -- every login UpdateConfig() and destroyed any manual per-slot arrangement
    -- the player made in unlock mode, snapping the raid back to the plain
    -- config grid (e.g. 10x4 VERTICAL = 4 rows x 10 columns).
    -- Only layout/fill/maxraid take part in the signature: spacing/size
    -- changes are cosmetic and must not wipe hand-placed slots (players who
    -- want a fully hand-made layout should pick the "custom" raid layout).
    -- Stops at 40 (= member pool cap): C.position["pfRaid41..50"] are NOT
    -- member slots anymore -- they carry the tuned pet placeholder anchors
    -- of the light/lightH presets (custom layouts read them in
    -- PositionPetFrames) and must survive the wipe. Manual PET positions
    -- live on separate keys (pfRaidPet1..N) and are never touched here.
    if C.position then
      local sig = layout .. "|" .. fill .. "|" .. tostring(maxraid)
      -- custom 永不清位（上线/换配置都不动手动布局），但签名照常更新：
      -- 这样以后从 custom 手动切回某个预设布局时，签名必然失配，网格正常重建。
      if not isCustom and C.position.pfRaidGridSig ~= sig then
        for i=2, 40 do
          local e = C.position["pfRaid" .. i]
          if e then
            -- 只清位置、保留缩放（2026-09-21）：团队框的"整体缩放"是每个框
            -- 各自的 SetScale（存档在条目的 scale 键里），位置清掉后网格会
            -- 按新布局重建，但 scale 一并清掉的话，重登后 LoadMovable 走
            -- posdata 分支把框重置回 1.0 —— 整个团队框变回原始大小，用户
            -- 不得不每次上线重新 shift+滚轮 缩放。网格间距不参与缩放，
            -- 保留 scale 即可在任何布局重建后还原"整体缩放"效果。
            local s = e.scale
            C.position["pfRaid" .. i] = nil
            if s then
              C.position["pfRaid" .. i] = { ["scale"] = s }
            end
          end
        end
      end
      C.position.pfRaidGridSig = sig
    end

    -- When members live on UIParent (saved profile), the extra slots beyond
    -- the layout (e.g. 41..50, reserved for pets) must keep following them,
    -- so derive their positions from the first member's saved anchor/origin.
    local origin = C.position and C.position["pfRaid1"]
    local originAnchor = origin and origin.anchor
    local originX = origin and origin.xpos
    local originY = origin and origin.ypos
    local originDown = originAnchor == "TOPLEFT" or originAnchor == "TOP" or originAnchor == "TOPRIGHT"

    -- 自定义布局 + 零存档（全新角色首次进入游戏、未选预置配置）：没有任何
    -- 手动位置可循，若不处理框体会散落在代码默认位置。这里以 light 形态的
    -- 默认网格初始化（纵向填充：每列 10 人），并写入存档——之后解锁拖动、
    -- 换布局都基于这份存档，不会再被重置。已有 pfRaid1 存档则完全跳过。
    if isCustom and C.position and not C.position["pfRaid1"] then
      local percol = 10
      for i=1, maxraid do
        local col, row
        if fill == "VERTICAL" or fill == "VERTICAL_REVERSE" then
          col = floor((i-1) / percol) + 1
          row = mod(i-1, percol) + 1
          if fill == "VERTICAL_REVERSE" then row = percol - row + 1 end
        else
          col = mod(i-1, percol) + 1
          row = floor((i-1) / percol) + 1
        end
        C.position["pfRaid" .. i] = {
          ["anchor"] = "TOPLEFT",
          ["xpos"]   = (col-1) * (padding + width),
          ["ypos"]   = -(row-1) * (padding + height),
          ["parent"] = "UIParent",
        }
      end
      origin = C.position["pfRaid1"]
      originAnchor, originX, originY = origin.anchor, origin.xpos, origin.ypos
      originDown = true
    end

    for i=1, maxraid do
      if pfUI.uf.raid[i] then
        if isCustom then
          -- 自定义布局：存档位置即布局。UpdateMovable/LoadMovable 会把
          -- C.position 里手动拖出的每槽位置应用到框体上（存档永远赢）；
          -- 没有存档的槽位保持原样，等玩家在解锁模式里拖。
          if i > 40 then
            local cpos = C.position and C.position["pfRaid" .. i]
            if cpos and cpos.anchor and cpos.xpos then
              pfUI.uf.raid[i]:ClearAllPoints()
              pfUI.uf.raid[i]:SetPoint(cpos.anchor, cpos.xpos, cpos.ypos)
            end
          end
        else
          local col, row = slotToCell(i)
          pfUI.uf.raid[i]:ClearAllPoints()
          if originAnchor and originX then
            -- 仅在真正需要换父时才 SetParent（同父重复调用同样算换父扰动）
            if pfUI.uf.raid[i]:GetParent() ~= UIParent then
              pfUI.uf.raid[i]:SetParent(UIParent)
            end
            pfUI.uf.raid[i]:SetPoint(originAnchor,
              originX + (col-1)*(padding + width),
              originY + (row-1)*(padding + height) * (originDown and -1 or 1))
          else
            pfUI.uf.raid[i]:SetPoint("BOTTOMLEFT", (col-1)*(padding + width), (row-1)*(padding + height))
          end
        end
        -- only real member slots (1..40) become movable. Slots 41..50 are
        -- internal pet placeholders: their layout is computed above, they are
        -- never dragged, and registering them would make unlock mode show
        -- empty leftover draggers for them.
        if i <= 40 then
          UpdateMovable(pfUI.uf.raid[i], true)
        end
      end
    end

    -- raid pet frames: half height, same width, follow behind members.
    -- Pool size = unitframes.raidpetmax (petmax), independent of maxraid.
    pfUI.uf.raid.pet = pfUI.uf.raid.pet or {}
    local showpets = C.unitframes.raidpet and C.unitframes.raidpet.visible == "1"
    for i=1, self.petmax do
      if showpets then
        local isNew = not pfUI.uf.raid.pet[i]
        pfUI.uf.raid.pet[i] = pfUI.uf.raid.pet[i] or pfUI.uf:CreateUnitFrame("RaidPet", i, C.unitframes.raidpet, 0.5)
        local f = pfUI.uf.raid.pet[i]
        -- 同成员框：活体宠物框不再无条件换父（同父跳过）
        if f:GetParent() ~= UIParent then
          f:SetParent(UIParent)
        end
        f:SetFrameLevel(5)
        f:UpdateConfig()
        f:UpdateFrameSize()
        if isNew then
          -- start empty (will be assigned during roster update)
          f.id = 0
          f.label = "raid"
          f:Hide()
        end
      elseif pfUI.uf.raid.pet[i] then
        pfUI.uf.raid.pet[i]:UpdateConfig()
        pfUI.uf.raid.pet[i]:Hide()
        -- no longer shown: drop from unlock movables so no stale draggers
        if pfUI.movables then
          pfUI.movables["pfRaidPet" .. i] = nil
        end
      end
    end

    -- pool shrink: petmax was lowered -- clear, hide and unregister the
    -- frames that fell out of the pool (they are kept around but dormant,
    -- and are revived by the creation branch above if petmax rises again).
    if showpets then
      for i=self.petmax+1, 40 do
        local f = pfUI.uf.raid.pet[i]
        if f then
          SetRaidPetIndex(f, 0, "raid")
          if pfUI.movables then
            pfUI.movables["pfRaidPet" .. i] = nil
          end
        end
      end
    end

    -- (re)position pets right after the last occupied member slot so a config
    -- change (size/width/...) keeps them following the roster; fall back to
    -- maxraid before the first roster update.
    if showpets then
      local lastSlot = 0
      for i=1, maxraid do
        local id = pfUI.uf.raid[i] and pfUI.uf.raid[i].id
        -- member id is a string before the first roster update; only a
        -- numeric roster index > 0 means "occupied"
        if type(id) == "number" and id > 0 then
          lastSlot = i
        end
      end
      pfUI.uf.raid:PositionPetFrames(lastSlot > 0 and lastSlot or maxraid)

      -- register pets as movable AFTER their layout position is applied, so
      -- posdata captures the computed grid position (middle-click reset
      -- target). Pets are draggable in unlock mode; their manual positions
      -- live in C.position["pfRaidPetN"] and win over the grid (see
      -- PositionPetFrames).
      for i=1, self.petmax do
        local f = pfUI.uf.raid.pet[i]
        if f then
          UpdateMovable(f, true)
        end
      end
    end
  end

  -- Place pet frames compactly right after the given member slot (startSlot =
  -- the last occupied member slot). Two half-height pets share one
  -- member-sized slot: the first pet takes the upper half, the second the
  -- lower half. Positions come from the SAVED member position at that slot;
  -- for slots beyond the raid (e.g. 41..50, reserved for pets) the grid is
  -- continued from pfRaid1's saved anchor/origin, so pets always follow the
  -- roster regardless of the extra placeholder frames' anchor state.
  function pfUI.uf.raid:PositionPetFrames(startSlot)
    if not pfUI.uf.raid.pet or not pfUI.uf.raid.pet[1] then return end
    if not C.unitframes.raidpet or C.unitframes.raidpet.visible ~= "1" then return end

    local _, default_border = GetBorderSize("unitframes")
    local width = pfUI.uf.raid[1]:GetWidth()+2*default_border
    local height = pfUI.uf.raid[1]:GetHeight()+2*default_border
    local padding = tonumber(pfUI.uf.raid[1].config.raidpadding)*GetPerfectPixel()
    local fill = pfUI.uf.raid[1].config.raidfill
    local layout = pfUI.uf.raid[1].config.raidlayout
    local isCustom = layout == "custom"
    local _, _, x, y = string.find(layout,"(.+)x(.+)")
    x, y = tonumber(x), tonumber(y)

    local pheight = pfUI.uf.raid.pet[1]:GetHeight()+2*default_border

    -- convert a 1-based slot index into (col,row) using the same ordering
    -- the member frames use. Reverse fill directions mirror the row/col so
    -- pets follow the grid in the same orientation.
    local function slotToCell(slot)
      if fill == "VERTICAL" or fill == "VERTICAL_REVERSE" then
        local col = floor((slot-1) / y) + 1
        local row = mod(slot-1, y) + 1
        if fill == "VERTICAL_REVERSE" then
          row = y - row + 1
        end
        return col, row
      else
        local col = mod(slot-1, x) + 1
        local row = floor((slot-1) / x) + 1
        if fill == "HORIZONTAL_REVERSE" then
          col = x - col + 1
        end
        return col, row
      end
    end

    -- shift a member slot's anchor/position into the upper (half==0) or lower
    -- (half==1) part of the cell, so two pets share one slot. The upper pet
    -- hugs the top edge, the lower pet hugs the bottom edge, leaving the
    -- middle of the slot empty (gap = slot height - 2*pet height). As a
    -- safeguard the lower pet never overlaps the upper pet.
    local function applyHalf(anchor, px, py, half)
      local up = (anchor == "BOTTOMLEFT" or anchor == "BOTTOM" or anchor == "BOTTOMRIGHT")
      local down = (anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT")

      if half == 0 then
        -- upper pet hugs the top edge
        if up then
          py = py + (height - pheight)
        elseif not down then
          py = py + (height/2 - pheight)
        end
      else
        -- lower pet hugs the bottom edge. TOP* anchored grids grow downward
        -- (y gets more negative), so the bottom edge sits at (py - height);
        -- BOTTOM* anchored grids grow upward, so the bottom edge is py.
        if down then
          -- hug the bottom edge, but never overlap the upper pet
          py = py - math.max(height - pheight, pheight + 2*GetPerfectPixel())
        elseif up then
          -- hug the bottom edge, but never overlap the upper pet
          py = py + math.min(0, height - 2*pheight - 2*GetPerfectPixel())
        else
          py = py - height/2
        end
      end

      return px, py
    end

    local start = startSlot or maxraid

    for p=1, pfUI.uf.raid.petmax do
      local pf = pfUI.uf.raid.pet[p]
      if not pf then break end

      pf:ClearAllPoints()

      -- manual pet position (unlock mode drag, saved as pfRaidPetN) always
      -- wins over the computed grid. 3-arg SetPoint anchors to the parent
      -- (UIParent), which is where SaveMovable recorded the offsets.
      local mpos = C.position and C.position["pfRaidPet" .. p]
      if mpos and mpos.anchor and mpos.xpos then
        pf:SetPoint(mpos.anchor, mpos.xpos, mpos.ypos)
      else
        local slot = start + 1 + floor((p-1) / 2)
        local half = mod(p-1, 2)  -- 0 = upper half, 1 = lower half

        -- Prefer the saved position of the member frame at this slot.
        -- - custom layout (light/lightH presets): every slot's saved position
        --   IS the layout, pet placeholder slots 41..50 included -- always
        --   read them, otherwise pets lose their tuned preset positions.
        -- - preset grid layout (NxM): slots 41..50 carry seeded legacy
        --   anchors (api/config.lua migration) that do NOT follow the current
        --   raidlayout/raidfill/maxraid -- ignore them and continue the grid
        --   below, so layout changes reach the pets.
        local pos = (isCustom or slot <= 40) and C.position and C.position["pfRaid" .. slot]
        if pos and pos.anchor and pos.xpos then
          local px, py = applyHalf(pos.anchor, pos.xpos, pos.ypos, half)
          pf:SetPoint(pos.anchor, px, py)
        else
          -- no saved member position: continue the grid from pfRaid1's saved
          -- anchor/origin, or fall back to the cluster grid. Custom layouts
          -- have no parseable grid ("custom" != "NxM"), so fall back to a
          -- simple vertical continuation below the first member instead of
          -- crashing on nil grid dimensions.
          local col, row
          if x and y then
            col, row = slotToCell(slot)
          else
            col, row = 1, slot
          end
          local origin = C.position and C.position["pfRaid1"]
          if origin and origin.anchor and origin.xpos then
            local anchor = origin.anchor
            local down = (anchor == "TOPLEFT" or anchor == "TOP" or anchor == "TOPRIGHT")
            local px = origin.xpos + (col-1)*(padding + width)
            local py = origin.ypos + (row-1)*(padding + height) * (down and -1 or 1)
            px, py = applyHalf(anchor, px, py, half)
            pf:SetPoint(anchor, px, py)
          else
            local px = (col-1)*(padding + width)
            local py = (row-1)*(padding + height)
            if half == 0 then
              py = py + (height - pheight)
            else
              -- hug the bottom edge, but never overlap the upper pet
              py = py + math.min(0, height - 2*pheight - 2*GetPerfectPixel())
            end
            pf:SetPoint("BOTTOMLEFT", cluster, "BOTTOMLEFT", px, py)
          end
        end

        -- keep posdata in sync with the live position. LoadMovable (unlock
        -- exit, middle-click reset) restores posdata when no manual position
        -- is saved; a stale login-time snapshot (captured before the roster
        -- assigned pets, i.e. at the off-grid continuation slots) teleported
        -- pets off-screen the moment unlock mode was left -- "pets visible
        -- in unlock, gone after ESC". init=true re-captures posdata from
        -- the points set above; the saved-position apply inside is a no-op
        -- for pets (PositionPetFrames already honoured it).
        UpdateMovable(pf, true)
      end
    end
  end

  -- pet frames are movable now: manual positions are stored as
  -- pfRaidPet1..N (written by SaveMovable in unlock mode) and re-applied by
  -- PositionPetFrames (manual save wins over the grid). Do NOT clear these
  -- entries here -- that would wipe the player's pet layout on every login.

  pfUI.uf.raid:UpdateConfig()

  local function SetRaidIndex(frame, id)
    frame.id = id
    frame.label = "raid"
    frame:UpdateVisibility()
  end

  -- add units to the beginning of their groups
  function pfUI.uf.raid:AddUnitToGroup(index, group)
    for subindex = 1, 5 do
      local ids = subindex + 5*(group-1)
      if pfUI.uf.raid[ids] and pfUI.uf.raid[ids].id == 0 and pfUI.uf.raid[ids].config.visible == "1" then
        SetRaidIndex(pfUI.uf.raid[ids], index)
        return
      end
    end
  end

  pfUI.uf.raid:Hide()
  pfUI.uf.raid:RegisterEvent("RAID_ROSTER_UPDATE")
  pfUI.uf.raid:RegisterEvent("PARTY_MEMBERS_CHANGED")
  pfUI.uf.raid:RegisterEvent("PARTY_LEADER_CHANGED")
  pfUI.uf.raid:RegisterEvent("VARIABLES_LOADED")
  pfUI.uf.raid:SetScript("OnEvent", function()
    this:Show()
    -- Debounce: delay update by 0.5s to batch rapid roster changes (mass swaps)
    this.pendingUpdate = GetTime() + 0.5
  end)
  pfUI.uf.raid:SetScript("OnUpdate", function()
    -- Wait for debounce: don't update until 0.5s after last event
    if this.pendingUpdate and GetTime() < this.pendingUpdate then return end
    -- Throttle raid roster updates to 1 FPS max
    if (this.tick or 0) > GetTime() then return end
    this.tick = GetTime() + 1.0
    this.pendingUpdate = nil

    -- don't touch frames during combat
    if InCombatLockdown and InCombatLockdown() then return end

    -- no longer in a raid: clear and hide every frame (members + pets) so
    -- nothing is left behind after leaving the raid/group
    if not UnitInRaid("player") then
      for i=1, maxraid do SetRaidIndex(pfUI.uf.raid[i], 0) end
      if pfUI.uf.raid.pet then
        for p=1, pfUI.uf.raid.petmax do
          local pf = pfUI.uf.raid.pet[p]
          if pf then SetRaidPetIndex(pf, 0, "raid") end
        end
      end
      this:Hide()
      return
    end

    -- clear all existing frames
    for i=1, maxraid do SetRaidIndex(pfUI.uf.raid[i], 0) end

    -- sort tanks into their groups
    for i=1, GetNumRaidMembers() do
      local name, _, subgroup  = GetRaidRosterInfo(i)
      if name and pfUI.uf.raid.tankrole[name] then
        pfUI.uf.raid:AddUnitToGroup(i, subgroup)
      end
    end

    -- sort players into roster
    for i=1, GetNumRaidMembers() do
      local name, _, subgroup  = GetRaidRosterInfo(i)
      if name and not pfUI.uf.raid.tankrole[name] then
        pfUI.uf.raid:AddUnitToGroup(i, subgroup)
      end
    end

    -- assign raid pets into compact pet slots (no gaps)
    if pfUI.uf.raid.pet and pfUI.uf.raid.pet[1] and C.unitframes.raidpet and C.unitframes.raidpet.visible == "1" then
      for p=1, pfUI.uf.raid.petmax do
        local pf = pfUI.uf.raid.pet[p]
        if pf then SetRaidPetIndex(pf, 0, "raid") end
      end

      local petslot = 1
      for i=1, GetNumRaidMembers() do
        if petslot > pfUI.uf.raid.petmax then break end
        local unit, label, id = GetRaidPetUnit(i)
        if unit then
          SetRaidPetIndex(pfUI.uf.raid.pet[petslot], id, label)
          petslot = petslot + 1
        end
      end

      -- find the highest member slot actually occupied, then place pets
      -- compactly right after it (follows the member grid order)
      local lastSlot = 0
      for i=1, maxraid do
        if pfUI.uf.raid[i] and pfUI.uf.raid[i].id and pfUI.uf.raid[i].id > 0 then
          lastSlot = i
        end
      end
      pfUI.uf.raid:PositionPetFrames(lastSlot)
    end

    -- Smart GUID-based updates: only refresh frames where unit changed
    -- Safely check if GetUnitGUID and guidTracker exist
    if GetUnitGUID and pfUI.uf.guidTracker then
      local tracker = pfUI.uf.guidTracker
      
      for i = 1, maxraid do
        local frame = pfUI.uf.raid[i]
        if frame and frame.id and frame.id > 0 then
          local unit = "raid" .. frame.id
          local newGuid = GetUnitGUID(unit)
          local oldGuid = tracker.frameToGuid[frame]
          
          if newGuid ~= oldGuid then
            tracker.frameToGuid[frame] = newGuid
            frame.update_full = true
            frame.update_aura = true  -- Force aura refresh!
          end
        end
      end
    end

    -- rebuild unitmap after frame IDs are assigned (if function exists)
    if pfUI.uf.RebuildUnitmap then
      pfUI.uf.RebuildUnitmap()
    end

    this:Hide()
  end)

  -- raid popup option to toggle tank role
  for _, menu in pairs({"RAID", "PARTY"}) do
    for label, data in pairs(pfUI.uf.raid.tanksfirst) do
      UnitPopupButtons[label] = { text = TEXT(data[1]), dist = 0 }
      table.insert(UnitPopupMenus[menu], 3, label)
    end
  end

  hooksecurefunc("UnitPopup_OnClick", function()
    local dropdownFrame = UIDROPDOWNMENU_INIT_MENU and _G[UIDROPDOWNMENU_INIT_MENU]
    if not dropdownFrame then return end
    local button = this.value
    local unit = dropdownFrame.unit
    local name = dropdownFrame.name

    if button and pfUI.uf.raid.tanksfirst[button] and name then
      pfUI.uf.raid.tankrole[name] = not pfUI.uf.raid.tankrole[name]
      pfUI.uf.raid:Show()
    end
  end)
end)
