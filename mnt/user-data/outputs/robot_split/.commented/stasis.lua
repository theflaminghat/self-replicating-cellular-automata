-- stasis.lua
local C = require("common")

local robot = C.robot
local pos = C.pos
local os = C.os
local moveUp = C.moveUp
local moveDown = C.moveDown
local gotoXZNoDig = C.gotoXZNoDig
local batteryLevel = C.batteryLevel

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
  while batteryLevel() < 0.9 do
    os.sleep(5)
  end
  return "mining"
end

return stasis
