local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local batteryLevel = C.batteryLevel

local function fwd(n)
  for _ = 1, n do C.moveForward() end
end

-- Shared item/inventory helpers (defined in common.lua).
local stackMatches    = C.matchesSpec
local specText        = C.specText
local facingInventory = C.facingFront




-- Scanning the chest with getStackInSlot is the slow part: one component call
-- per slot, and pulling each part used to rescan the whole chest. The chest
-- only changes when we take from it, so scan once and track counts locally.
local chestIndex = nil

local function buildChestIndex()
  chestIndex = {}
  local size = facingInventory()
  if not size then return false end
  for s = 1, size do
    local ok, st = pcall(inv.getStackInSlot, sides.front, s)
    if ok and st and st.name and st.size and st.size > 0 then
      chestIndex[#chestIndex + 1] = { slot = s, stack = st, size = st.size }
    end
  end
  return true
end

local function chestEntries()
  if not chestIndex then buildChestIndex() end
  return chestIndex or {}
end

-- Track where each item's stack lives in the robot so we don't rescan the whole
-- inventory for every pull. Also track a rising "next free slot" cursor.
local heldSlotOf = {}
local nextFree = 1

local function reserveSlot(item)
  local key = specText(item)
  if heldSlotOf[key] then
    return heldSlotOf[key]
  end
  while nextFree <= (C.INVENTORY_SIZE or 32) do
    local s = nextFree
    nextFree = nextFree + 1
    local isReserve = false
    for _, r in ipairs(C.RESERVE_COBBLE_SLOTS or {}) do
      if r == s then isReserve = true break end
    end
    if not isReserve then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and not st then
        heldSlotOf[key] = s
        return s
      end
    end
  end
  return nil
end

-- Pull `count` of an item from the inventory in front into robot storage.
local function pullFromFront(item, count)
  local got = 0
  for _, e in ipairs(chestEntries()) do
    if got >= count then break end
    if e.size > 0 and stackMatches(e.stack, item) then
      local take = math.min(count - got, e.size)
      local dest = reserveSlot(item)
      if not dest then break end
      robot.select(dest)
      if inv.suckFromSlot(sides.front, e.slot, take) then
        got = got + take
        e.size = e.size - take
      else
        chestIndex = nil
        break
      end
    end
  end
  return got
end

-- Drop `count` of an item from robot storage into the inventory in front.
-- Drop everything in a known slot into the inventory in front.
local function dropSlotToFront(slot)
  local ok, st = pcall(inv.getStackInInternalSlot, slot)
  if not (ok and st and st.size and st.size > 0) then
    return 0
  end
  robot.select(slot)
  local dropped, size = pcall(robot.drop, st.size)
  if dropped and size then
    return st.size
  end
  return 0
end

local function build_robot()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.lastBuildError = nil
  C.lastBuildReport = {}

  local parts = C.ROBOT_PARTS or {}

  -- Stasis -> chest: right, forward 3, left, forward 3, right.
  C.gotoChestFromStasis()
  if not facingInventory() then
    C.lastBuildError = "not facing the tracked chest"
    C.gotoStasisFromChest()
    return "stasis"
  end

  -- Take every part from the chest. pullFromFront returns how many it moved, so
  -- there's no need to rescan the robot's inventory before and after each part.
  for _, part in ipairs(parts) do
    local want = part.count or 1
    local got = pullFromFront(part, want)
    C.lastBuildReport[#C.lastBuildReport + 1] =
      { item = specText(part), wanted = want, taken = got }
    if got < want then
      C.lastBuildError = "missing: " .. specText(part)
    end
  end

  -- Chest -> assembler, directly.
  C.gotoAssemblerFromChest()
  if not facingInventory() then
    C.lastBuildError = "not facing the assembler"
    C.gotoStasisFromAssembler()
    return "stasis"
  end

  -- Deposit every part, case first (ROBOT_PARTS is already in that order).
  -- Each part's slot was recorded when we took it, so drop straight from there
  -- instead of rescanning the inventory.
  for _, part in ipairs(parts) do
    local slot = heldSlotOf[specText(part)]
    if slot then
      dropSlotToFront(slot)
    end
  end

  -- Assembler -> button: left, forward, right, up, then use the button in front.
  C.turnLeft()
  fwd(1)
  C.turnRight()
  C.moveUp()

  -- The button is on TOP of the block, so click upward. Keep front/down as
  -- fallbacks in case the exact mounting differs.
  local pressed = false
  local lastResult = nil
  local attempts = { sides.up, sides.front, sides.down }
  for _, side in ipairs(attempts) do
    for _ = 1, 2 do
      local ok, res = pcall(robot.use, side)
      lastResult = ok and tostring(res) or ("error:" .. tostring(res))
      if ok and res == "block_activated" then
        pressed = true
        break
      end
    end
    if pressed then break end
  end
  C.lastBuildReport.pressed = pressed
  C.lastBuildReport.useResult = lastResult
  if not pressed then
    C.lastBuildError = "button press failed (use returned " .. tostring(lastResult) .. ")"
  end

  -- Button -> stasis: right, down, forward 3, left.
  C.turnRight()
  C.moveDown()
  fwd(3)
  C.turnLeft()

  return "stasis"
end

C.buildRobot = build_robot

return build_robot
