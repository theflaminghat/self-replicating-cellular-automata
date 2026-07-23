-- test_inventory.lua
-- Runs the real inventory state once, assuming the robot begins at the stasis
-- spot (4,1,3) -- in front of the charging port at (4,1,2).
--
-- Place all split files (common.lua, inventory.lua, etc.) in the same
-- directory as this script and run it from there.
--
-- IMPORTANT: This drives the actual robot. It will navigate to the chests and
-- deposit items exactly as the normal inventory state does. It is a "test" only
-- in that it runs that one state in isolation, starting from the charger,
-- rather than the full state loop.

local component = require("component")
local robot = require("robot")

local C = require("common")
local inventory = require("inventory")

-- Seed the position tracker to the real starting location: the stasis spot
-- (4,1,3), facing the charging port at (4,1,2), which is -Z from here.
-- facing convention: 0=+Z, 1=+X, 2=-Z, 3=-X. Facing the port (-Z) is 2.
C.pos.x = C.STASIS_X      -- 4
C.pos.y = C.STASIS_Y      -- 1
C.pos.z = C.STASIS_Z      -- 3
C.pos.facing = 2          -- facing -Z, toward the charger

print("=== inventory test ===")
print(string.format("start pos: x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))

-- Report what the robot is carrying before the run.
local inv = C.inv
local carried = 0
for i = 1, 16 do
  local stack = inv.getStackInInternalSlot(i)
  if stack and stack.size and stack.size > 0 then
    carried = carried + 1
    print(string.format("  slot %2d: %s x%d", i,
      tostring(stack.label or stack.name), stack.size))
  end
end
if carried == 0 then
  print("  (carrying nothing -- deposits will be no-ops)")
end

-- Run the real inventory state exactly once.
local nextState = inventory()

print(string.format("end pos:   x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
print("inventory() returned next state: " .. tostring(nextState))
print("=== done ===")
