-- test_mining.lua
-- Runs the real mining state once, assuming the robot begins at the stasis
-- spot (4,1,3) -- in front of the charging port at (4,1,2).
--
-- Place all split files (common.lua, mining.lua, etc.) in the same
-- directory as this script and run it from there.
--
-- IMPORTANT: This drives the actual robot. It will travel to the mining start,
-- dig the shaft at (4,5) straight down to bedrock, then build a cobblestone
-- pillar back up using the reserve slots, exactly as the real state does.
-- It is a "test" only in that it runs that one state in isolation, starting
-- from the stasis point, rather than the full state loop.

local component = require("component")
local robot = require("robot")

local C = require("common")
local mining = require("mining")

-- Seed the position tracker to the real starting location: the stasis spot
-- (4,1,3), facing the charging port at (4,1,2), which is -Z from here.
-- facing convention: 0=+Z, 1=+X, 2=-Z, 3=-X. Facing the port (-Z) is 2.
C.pos.x = C.STASIS_X      -- 4
C.pos.y = C.STASIS_Y      -- 1
C.pos.z = C.STASIS_Z      -- 3
C.pos.facing = 2          -- facing -Z, toward the charger

print("=== mining test ===")
print(string.format("start pos: x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
print(string.format("shaft column: (%d, ~, %d)   pillar: (%d, ~, %d)",
  C.MINE_START_X, C.MINE_START_Z, C.PILLAR_X, C.PILLAR_Z))

-- Count reserve cobblestone before the run; the pillar is built from it.
local inv = C.inv
local function reserveCount()
  local total = 0
  for _, slot in ipairs(C.RESERVE_COBBLE_SLOTS) do
    local stack = inv.getStackInInternalSlot(slot)
    if stack and stack.size then
      total = total + stack.size
    end
  end
  return total
end

local before = reserveCount()
local size = C.INVENTORY_SIZE
print("robot inventorySize(): " .. tostring(size or "unknown"))
local slotList = {}
for _, s in ipairs(C.RESERVE_COBBLE_SLOTS) do
  slotList[#slotList + 1] = tostring(s)
end
print("reserve slots in use: " .. table.concat(slotList, ", "))
print("reserve cobblestone before: " .. before)
if size and size <= C.HIGHEST_NAMED_SLOT then
  print("  *** PROBLEM: this robot has only " .. size .. " slots, but the build")
  print("      assigns named items through slot " .. C.HIGHEST_NAMED_SLOT .. ".")
  print("      Add inventory upgrades (16 slots each) -- 32 slots is the minimum.")
elseif before == 0 then
  print("  (no reserve cobble found -- load cobblestone into the slots above)")
end

-- Run the real mining state exactly once.
local nextState = mining()

print(string.format("end pos:   x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
print("shaft depth dug: " .. tostring(C.shaftDepth))

local after = reserveCount()
print("reserve cobblestone after:  " .. after ..
  "  (used " .. (before - after) .. ")")
print("allowHole flag: " .. tostring(C.allowHole) ..
  "  (stays true through quarry; cleared in returning)")
print("mining() returned next state: " .. tostring(nextState))
print("=== done ===")
