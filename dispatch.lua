-- dispatch.lua
-- Dispatch a finished offspring. Two phases:
--   1. At the computer (case at 7,1,2, button on top at 7,2,2): turn it on, place a
--      hard drive in slot 7 to copy the OS onto, wait 18s, take the drive back out,
--      swap the EEPROM (Lua BIOS) in slot 10 for a fresh one (wait 3s), swap the
--      redstone card in slot 1 for a new one (wait 3s), press the button, and go
--      back to stasis.
--   2. From stasis, carry the offspring (and its BOM payload) out toward its compass
--      direction, bridging with reserve cobble, place the robot, and deposit the
--      resources into it, then return to stasis.
-- The direction (N/E/S/W) is passed in by the scheduler.

local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local os = C.os
local batteryLevel = C.batteryLevel

local moveForward, moveUp, moveDown, moveBack =
  C.moveForward, C.moveUp, C.moveDown, C.moveBack
local turnRight, turnLeft = C.turnRight, C.turnLeft

local COMP_REDSTONE_SLOT = 1
local COMP_HDD_SLOT = 7
local COMP_EEPROM_SLOT = 10

local HDD_LABEL = "Hard Disk Drive (Tier 2) (2MB)"
local EEPROM_LABEL = "EEPROM"
local REDSTONE_LABEL = "Redstone Card (Tier 1)"

-- First robot slot holding an item whose label matches exactly, or nil. Exact
-- matching keeps a fresh "EEPROM" distinct from an "EEPROM (Lua BIOS)".
local function slotWithLabel(label)
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and st and st.size and st.size > 0 and st.label == label then
      return s
    end
  end
  return nil
end

-- Press the button on top of the case (robot is one block above the stand).
local function pressButton()
  for _, side in ipairs({ sides.front, sides.up, sides.down }) do
    local ok, res = pcall(robot.use, side)
    if ok and res == "block_activated" then return true end
  end
  return false
end

-- Drop one item with `label` from the robot into the computer's `compSlot`.
local function placeIntoComputer(label, compSlot)
  local s = slotWithLabel(label)
  if not s then return false end
  robot.select(s)
  local ok, done = pcall(inv.dropIntoSlot, sides.front, compSlot, 1)
  return (ok and done) and true or false
end

-- Suck one item out of the computer's `compSlot` into a free robot slot.
local function takeFromComputer(compSlot)
  local into = C.freeSlot()
  if not into then return false end
  robot.select(into)
  local ok = pcall(inv.suckFromSlot, sides.front, compSlot, 1)
  return ok and true or false
end

-- Take the item in the computer's `compSlot` out into the robot, then drop the
-- robot's own item with `newLabel` in. The robot's item is located BEFORE the
-- take, so a just-harvested same-label item isn't put right back.
local function swapComputerSlot(newLabel, compSlot)
  local src = slotWithLabel(newLabel)
  local into = C.freeSlot()
  if into then
    robot.select(into)
    pcall(inv.suckFromSlot, sides.front, compSlot, 1)
  end
  if not src then return false end
  robot.select(src)
  local ok, done = pcall(inv.dropIntoSlot, sides.front, compSlot, 1)
  return (ok and done) and true or false
end

-- ---------------------------------------------------------------------------
-- Placement helpers.
-- ---------------------------------------------------------------------------

local function fwd(n) for _ = 1, n do moveForward() end end
local function up(n) for _ = 1, n do moveUp() end end
local function down(n) for _ = 1, n do moveDown() end end

-- Bridge forward `n` cells, laying a reserve-cobble block under each new cell.
local function bridge(n)
  for _ = 1, n do
    moveForward()
    C.placeReserveCobbleDown()
  end
end

-- Place the collected offspring robot in front.
local function placeOffspringRobot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and st and st.size and st.size > 0 then
      if st.name == "opencomputers:robot"
          or (st.label and string.find(st.label, "Robot", 1, true)) then
        robot.select(s)
        pcall(robot.place)
        return true
      end
    end
  end
  return false
end

-- Compass name -> index (1..8): reverse of C.COMPASS. Cobblestone count in the
-- type slot; that's how the offspring learns which direction it is.
local COMPASS_INDEX = {}
for i, name in pairs(C.COMPASS or {}) do COMPASS_INDEX[name] = i end

-- The set of slots to hand over: every build-layout slot, plus the type marker.
local DEPOSIT_SLOTS = (function()
  local set = { [C.TYPE_SLOT] = true }
  for _, e in ipairs(C.BUILD_LAYOUT or {}) do
    if e.slot then set[e.slot] = true end
  end
  local list = {}
  for s in pairs(set) do list[#list + 1] = s end
  table.sort(list)
  return list
end)()

-- Copy each laid-out slot's stack into the SAME slot of the robot in front, so
-- the offspring's inventory ends up identical to a freshly-set-up robot's.
local function depositResources()
  for _, s in ipairs(DEPOSIT_SLOTS) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and st and st.size and st.size > 0 then
      robot.select(s)
      pcall(inv.dropIntoSlot, sides.front, s, st.size)
    end
  end
end

-- Retrace `nav` (recorded outbound moves) in reverse to return to stasis. Each
-- forward becomes a back-step (facing is already restored by undoing later turns
-- first), each turn its opposite, each ascent a descent.
local function retrace(nav)
  for i = #nav, 1, -1 do
    local m = nav[i]
    if m[1] == "fwd" then for _ = 1, m[2] do moveBack() end
    elseif m[1] == "up" then for _ = 1, m[2] do moveDown() end
    elseif m[1] == "down" then for _ = 1, m[2] do moveUp() end
    elseif m[1] == "right" then turnLeft()
    elseif m[1] == "left" then turnRight()
    end
  end
end

-- Carry the offspring out toward `dir`, bridge to its spot, place it, hand over the
-- resources, then retrace the exact path back to stasis. Movements are the fixed
-- per-direction routes; the robot starts at stasis (4,1,3) facing the charger (-Z).
local function placeOffspring(dir)
  -- Mirror the build layout in our own inventory (type marker = this direction),
  -- so the slot-for-slot deposit lands everything where the offspring expects it.
  C.arrangeBuildLayout(COMPASS_INDEX[dir])

  local nav = {}
  local function recFwd(n) fwd(n); nav[#nav + 1] = { "fwd", n } end
  local function recUp(n) up(n); nav[#nav + 1] = { "up", n } end
  local function recDown(n) down(n); nav[#nav + 1] = { "down", n } end
  local function recRight() turnRight(); nav[#nav + 1] = { "right" } end
  local function recLeft() turnLeft(); nav[#nav + 1] = { "left" } end
  -- Bridge n cells, then step back one to make room for the offspring. The net
  -- advance is n-1, which is what the retrace must undo.
  local function recBridgeBack(n)
    bridge(n)
    moveBack()
    nav[#nav + 1] = { "fwd", n - 1 }
  end

  if dir == "N" then
    recRight(); recFwd(3); recRight(); recFwd(12); recLeft(); recFwd(1); recRight()
    recBridgeBack(17)
  elseif dir == "E" then
    recLeft(); recFwd(4); recRight(); recFwd(3); recLeft()
    recBridgeBack(24)
  elseif dir == "S" then
    recUp(6); recRight(); recFwd(4); recLeft(); recFwd(5); recDown(6)
    C.placeReserveCobbleDown()   -- footing before bridging
    recBridgeBack(31)
  elseif dir == "W" then
    recUp(6); recRight(); recFwd(4); recLeft(); recFwd(4); recRight(); recFwd(1); recDown(6)
    C.placeReserveCobbleDown()   -- footing before bridging
    recBridgeBack(31)
  else
    return  -- unknown direction; nothing to do
  end

  placeOffspringRobot()
  depositResources()
  retrace(nav)
  C.face(2)
end

-- ---------------------------------------------------------------------------

local function dispatch(direction)
  if batteryLevel() < 0.25 then
    return "returning"
  end
  C.lastDispatchError = nil
  C.lastDispatch = { hdd = false, eeprom = false, redstone = false, dir = direction }

  -- Stasis -> assembler stand (6,1,3) -> computer stand (7,1,3), case in front.
  C.gotoAssemblerFromStasis()
  C.face(1)
  moveForward()
  C.face(2)
  if not C.facingFront() then
    C.lastDispatchError = "not facing the computer"
    C.face(3)
    moveForward()
    C.face(2)
    C.gotoStasisFromAssembler()
    return "stasis"
  end

  -- Turn the computer on (button on top).
  moveUp()
  pressButton()
  moveDown()

  -- Place the hard drive, wait for the OS to copy, then take it back out.
  C.lastDispatch.hdd = placeIntoComputer(HDD_LABEL, COMP_HDD_SLOT)
  os.sleep(18)
  takeFromComputer(COMP_HDD_SLOT)

  -- Swap the EEPROM: Lua BIOS out, fresh EEPROM in (to be flashed).
  C.lastDispatch.eeprom = swapComputerSlot(EEPROM_LABEL, COMP_EEPROM_SLOT)
  os.sleep(3)

  -- Swap the redstone card in slot 1: old one out, new one in.
  C.lastDispatch.redstone = swapComputerSlot(REDSTONE_LABEL, COMP_REDSTONE_SLOT)
  os.sleep(3)

  -- Press the button on top of the computer.
  moveUp()
  pressButton()
  moveDown()

  -- Computer stand -> assembler stand -> stasis.
  C.face(3)
  moveForward()
  C.face(2)
  C.gotoStasisFromAssembler()

  -- Now carry the offspring out to its compass direction and set it up.
  placeOffspring(direction)
  return "stasis"
end

C.dispatch = dispatch

return dispatch
