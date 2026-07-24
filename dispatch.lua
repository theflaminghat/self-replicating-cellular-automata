-- dispatch.lua
-- Dispatch a finished offspring at the computer (the case at 7,1,2, with its power
-- button on top at 7,2,2). The robot should already be carrying the offspring robot
-- plus the full BOM of resources for it. The sequence:
--   go to the computer, turn it on,
--   place a hard drive in (slot 7) to copy the OS onto, wait 18s,
--   take the EEPROM (Lua BIOS) out of slot 10 and drop a fresh EEPROM in, wait 3s,
--   take the redstone card out of slot 1 and drop a new redstone card in, wait 3s,
--   press the button on top, then return to stasis.

local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local os = C.os
local batteryLevel = C.batteryLevel

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

-- Press the button on top of the case (robot is one block above the stand). Tries
-- each face and returns true on block_activated.
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

local function dispatch()
  if batteryLevel() < 0.25 then
    return "returning"
  end
  C.lastDispatchError = nil
  C.lastDispatch = { hdd = false, eeprom = false, redstone = false }

  -- Stasis -> assembler stand (6,1,3) -> computer stand (7,1,3), case in front.
  C.gotoAssemblerFromStasis()
  C.face(1)
  C.moveForward()
  C.face(2)
  if not C.facingFront() then
    C.lastDispatchError = "not facing the computer"
    C.face(3)
    C.moveForward()
    C.face(2)
    C.gotoStasisFromAssembler()
    return "stasis"
  end

  -- Turn the computer on (button on top).
  C.moveUp()
  pressButton()
  C.moveDown()

  -- Place the hard drive to copy the OS onto it.
  C.lastDispatch.hdd = placeIntoComputer(HDD_LABEL, COMP_HDD_SLOT)
  os.sleep(18)

  -- Swap the EEPROM: Lua BIOS out, fresh EEPROM in (to be flashed).
  C.lastDispatch.eeprom = swapComputerSlot(EEPROM_LABEL, COMP_EEPROM_SLOT)
  os.sleep(3)

  -- Swap the redstone card in slot 1: old one out, new one in.
  C.lastDispatch.redstone = swapComputerSlot(REDSTONE_LABEL, COMP_REDSTONE_SLOT)
  os.sleep(3)

  -- Press the button on top of the computer.
  C.moveUp()
  pressButton()
  C.moveDown()

  -- Computer stand -> assembler stand -> stasis.
  C.face(3)
  C.moveForward()
  C.face(2)
  C.gotoStasisFromAssembler()
  return "stasis"
end

C.dispatch = dispatch

return dispatch
