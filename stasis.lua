-- stasis.lua
local C = require("common")

local robot = C.robot
local pos = C.pos
local os = C.os
local sides = C.sides
local moveUp = C.moveUp
local moveDown = C.moveDown
local gotoXZNoDig = C.gotoXZNoDig
local batteryLevel = C.batteryLevel

-- The charger sits in front of the stasis spot with a lever on top of it. Charging
-- draws generator fuel, so the charger is only powered while the robot is actually
-- charging: step up one to reach the lever, flip it, and step back down onto the
-- charge spot. The same toggle turns it back off. (robot.use right-clicks the
-- block in front, which flips the lever.)
local function toggleCharger()
  moveUp()                        -- up beside the lever on top of the charger
  pcall(robot.use, sides.front)   -- flip the lever
  moveDown()                      -- back down onto the charge spot
end

local function stasis()
  while pos.y < C.TRAVEL_Y do
    if not moveUp() then break end
  end
  gotoXZNoDig(C.STASIS_X, C.STASIS_Z)
  while pos.y > C.STASIS_Y do
    if not moveDown() then break end
  end
  while pos.y < C.STASIS_Y do
    if not moveUp() then break end
  end
  C.face(2)  -- face the charger (and the lever above it)

  if batteryLevel() < 0.9 then
    toggleCharger()                       -- flip the lever on to start charging
    while batteryLevel() < 0.9 do
      os.sleep(5)
    end
    toggleCharger()                       -- flip it back off once charged
  end

  return "mining"
end

return stasis
