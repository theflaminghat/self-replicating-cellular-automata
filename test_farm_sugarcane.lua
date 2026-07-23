-- test_farm_sugarcane.lua
-- Runs the real farm_sugarcane state once, assuming the robot begins at the
-- stasis spot (4,1,3) -- in front of the charging port at (4,1,2).
--
-- Place all split files (common.lua, farm_sugarcane.lua, etc.) in the same
-- directory as this script and run it from there.
--
-- IMPORTANT: This drives the actual robot. It will go on top of each sugarcane column and mine down to y=3 as the real
-- state does.
-- It is a "test" only in that it runs that one state in isolation, starting
-- from the stasis point, rather than the full state loop.

local component = require("component")
local robot = require("robot")

local C = require("common")
local farm_sugarcane = require("farm_sugarcane")

-- Seed the position tracker to the real starting location: the stasis spot
-- (4,1,3), facing the charging port at (4,1,2), which is -Z from here.
-- facing convention: 0=+Z, 1=+X, 2=-Z, 3=-X. Facing the port (-Z) is 2.
C.pos.x = C.STASIS_X      -- 4
C.pos.y = C.STASIS_Y      -- 1
C.pos.z = C.STASIS_Z      -- 3
C.pos.facing = 2          -- facing -Z, toward the charger

print("=== farm_sugarcane test ===")
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
  print("  (carrying nothing)")
end

-- Run the real farm_sugarcane state exactly once.
local nextState = farm_sugarcane()

print(string.format("end pos:   x=%d y=%d z=%d facing=%d",
  C.pos.x, C.pos.y, C.pos.z, C.pos.facing))
print("farm_sugarcane() returned next state: " .. tostring(nextState))
print("=== done ===")
