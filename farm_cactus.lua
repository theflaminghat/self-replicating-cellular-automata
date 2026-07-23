local C = require("common")

local robot = C.robot
local pos = C.pos
local moveUp = C.moveUp
local moveDown = C.moveDown
local batteryLevel = C.batteryLevel

local HARVEST_FLOOR = 3

local function descendOntoCactus()
  while pos.y > HARVEST_FLOOR do
    if robot.detectDown() then
      robot.swingDown()
      robot.suckDown()
    end
    if not moveDown() then break end
  end
end

local function climbOut()
  while pos.y < C.CACTUS_TRAVEL_Y do
    if robot.detectUp() then robot.swingUp() end
    if not moveUp() then break end
  end
end

local function farm_cactus()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  C.followPath(C.CACTUS_OUT_PATH)

  descendOntoCactus()

  climbOut()

  C.followPath(C.CACTUS_RETURN_PATH)
  C.face(2)

  return "stasis"
end

return farm_cactus
