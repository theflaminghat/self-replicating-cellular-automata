local robot = require("robot")
local component = require("component")
local computer = require("computer")
local sides = require("sides")
local os = require("os")
local inv = component.inventory_controller

local state = "inventory"

local BUILD_X = 9
local BUILD_Y = 3
local BUILD_Z = 16

local COBBLE_SLOTS = { 1, 2, 3 }
local RESERVE_COBBLE_SLOTS = { 29, 30, 31, 32 }
local WATER_SLOTS = { 14, 15 }
local SLOTS = {
  dirt           = 4,
  coal_generator = 5,
  flux_duct      = 6,
  case3          = 7,
  assembler      = 8,
  hopper         = 9,
  furnace        = 10,
  sand           = 11,
  chest          = 12,
  stone_button   = 13,
  crusher        = 16,
  charger        = 17,
  lever          = 18,
}
SLOTS.leadstone_duct = SLOTS.flux_duct

local FLOOR_OVERRIDES = {
  { x = 4, z = 12, slot = SLOTS.dirt },
}

local PLACEMENTS = {
  { x = 3, z = 1, slot = SLOTS.flux_duct },
  { x = 4, z = 1, slot = SLOTS.flux_duct },
  { x = 5, z = 1, slot = SLOTS.flux_duct },
  { x = 6, z = 1, slot = SLOTS.flux_duct },
  { x = 7, z = 1, slot = SLOTS.flux_duct },
  { x = 8, z = 1, slot = SLOTS.flux_duct },
  { x = 3, z = 0, slot = SLOTS.coal_generator },
  { x = 4, z = 0, slot = SLOTS.coal_generator },
  { x = 5, z = 0, slot = SLOTS.coal_generator },
  { x = 6, z = 0, slot = SLOTS.coal_generator },
  { x = 7, z = 0, slot = SLOTS.coal_generator },
  { x = 8, z = 0, slot = SLOTS.coal_generator },
  { x = 7, z = 2, slot = SLOTS.case3 },
  { x = 6, z = 2, slot = SLOTS.assembler },
  { x = 5, z = 2, slot = SLOTS.hopper },
  { x = 2, z = 2, slot = SLOTS.furnace },
  { x = 4, z = 2, slot = SLOTS.charger },
}

local SAND_PLACEMENTS = {
  { x = 4, z = 6 },
  { x = 5, z = 6 },
  { x = 6, z = 6 },
  { x = 3, z = 7 },
  { x = 7, z = 7 },
  { x = 4, z = 8 },
  { x = 5, z = 8 },
  { x = 6, z = 8 },
}

local CHEST_STACK_HEIGHT = 6
local CHEST_PLACEMENTS = {
  { x = 0, z = 0 },
  { x = 0, z = 1 },
  { x = 0, z = 3 },
  { x = 0, z = 4 },
  { x = 0, z = 6 },
  { x = 0, z = 7 },
}

local TRACKED_CHEST = { x = 0, y = 1, z = 0 }

local STASIS_X = 4
local STASIS_Y = 1
local STASIS_Z = 3

local TRACKED_RESOURCES = {
  { name = "minecraft:cobblestone", min = 128, target = 1024 },
  { name = "minecraft:iron_ore",    min = 64,  target = 512 },
  { name = "minecraft:coal",        min = 64,  target = 512 },
  { name = "minecraft:gold_ore",    min = 32,  target = 256 },
  { name = "minecraft:redstone",    min = 64,  target = 512 },
}

local WATER_PLACEMENTS = {
  { x = 4, z = 7 },
  { x = 6, z = 7 },
}

local Y2_PLACEMENTS = {
  { x = 7, z = 2, slot = SLOTS.stone_button },
  { x = 5, z = 2, slot = SLOTS.crusher },
  { x = 5, z = 1, slot = SLOTS.leadstone_duct },
  { x = 4, z = 2, slot = SLOTS.lever },
}

local pos = { x = 0, y = 0, z = 0, facing = 0 }

local function moveForward()
  if robot.forward() then
    if pos.facing == 0 then pos.z = pos.z + 1
    elseif pos.facing == 1 then pos.x = pos.x + 1
    elseif pos.facing == 2 then pos.z = pos.z - 1
    elseif pos.facing == 3 then pos.x = pos.x - 1 end
    return true
  end
  return false
end

local function moveBack()
  if robot.back() then
    if pos.facing == 0 then pos.z = pos.z - 1
    elseif pos.facing == 1 then pos.x = pos.x - 1
    elseif pos.facing == 2 then pos.z = pos.z + 1
    elseif pos.facing == 3 then pos.x = pos.x + 1 end
    return true
  end
  return false
end

local function moveUp()
  if robot.up() then
    pos.y = pos.y + 1
    return true
  end
  return false
end

local function moveDown()
  if robot.down() then
    pos.y = pos.y - 1
    return true
  end
  return false
end

local function turnLeft()
  robot.turnLeft()
  pos.facing = (pos.facing - 1) % 4
end

local function turnRight()
  robot.turnRight()
  pos.facing = (pos.facing + 1) % 4
end

local function turnAround()
  robot.turnAround()
  pos.facing = (pos.facing + 2) % 4
end

local function face(dir)
  local diff = (dir - pos.facing) % 4
  if diff == 1 then turnRight()
  elseif diff == 2 then turnAround()
  elseif diff == 3 then turnLeft() end
end

local function stepDir(dir)
  face(dir)
  while robot.detect() do
    robot.swing()
  end
  while not moveForward() do
    robot.swing()
  end
end

local function stepDirNoDig(dir)
  face(dir)
  return moveForward()
end

local function batteryLevel()
  return computer.energy() / computer.maxEnergy()
end

local function gotoBuildCorner()
  while pos.x > 0 do stepDir(3) end
  while pos.x < 0 do stepDir(1) end
  while pos.z > 0 do stepDir(2) end
  while pos.z < 0 do stepDir(0) end
  face(0)
end

local function gotoXZ(tx, tz)
  while pos.x < tx do stepDir(1) end
  while pos.x > tx do stepDir(3) end
  while pos.z < tz do stepDir(0) end
  while pos.z > tz do stepDir(2) end
end

local function gotoXZNoDig(tx, tz)
  while pos.x < tx do stepDirNoDig(1) end
  while pos.x > tx do stepDirNoDig(3) end
  while pos.z < tz do stepDirNoDig(0) end
  while pos.z > tz do stepDirNoDig(2) end
end

local TRAVEL_Y = CHEST_STACK_HEIGHT + 1

local FLOOR_HOLE_X = 4
local FLOOR_HOLE_Z = 4

local function wouldEnterHole(nx, nz)
  return nx == FLOOR_HOLE_X and nz == FLOOR_HOLE_Z
end

local function nextCell(dir)
  if dir == 1 then return pos.x + 1, pos.z
  elseif dir == 3 then return pos.x - 1, pos.z
  elseif dir == 0 then return pos.x, pos.z + 1
  elseif dir == 2 then return pos.x, pos.z - 1 end
  return pos.x, pos.z
end

local function walkAxisNoDig(getCur, dirPos, dirNeg, target)
  while getCur() < target do
    local nx, nz = nextCell(dirPos)
    if wouldEnterHole(nx, nz) then return false end
    if not stepDirNoDig(dirPos) then return false end
  end
  while getCur() > target do
    local nx, nz = nextCell(dirNeg)
    if wouldEnterHole(nx, nz) then return false end
    if not stepDirNoDig(dirNeg) then return false end
  end
  return true
end

local function gotoOverTop(tx, tz, workY)
  while pos.y < TRAVEL_Y do
    if not moveUp() then break end
  end
  gotoXZNoDig(tx, tz)
  while pos.y > workY do
    if not moveDown() then break end
  end
  while pos.y < workY do
    if not moveUp() then break end
  end
end

local function gotoNoBreak(tx, tz, workY)
  if pos.y > workY then
    return gotoOverTop(tx, tz, workY)
  end

  while pos.y < workY do
    if not moveUp() then break end
  end

  if not walkAxisNoDig(function() return pos.x end, 1, 3, tx) then
    return gotoOverTop(tx, tz, workY)
  end
  if not walkAxisNoDig(function() return pos.z end, 0, 2, tz) then
    return gotoOverTop(tx, tz, workY)
  end
end

local function floorOverride(x, z)
  for _, o in ipairs(FLOOR_OVERRIDES) do
    if o.x == x and o.z == z then
      return o.slot
    end
  end
  return nil
end

local function placeSlotDown(slot)
  robot.select(slot)
  local stack = inv.getStackInInternalSlot(slot)
  if not (stack and stack.size and stack.size > 0) then
    return false
  end
  for _ = 1, 3 do
    if robot.detectDown() then robot.swingDown() end
    if robot.placeDown() then
      return true
    end
  end
  return false
end

local function placeCobbleDown()
  for _, slot in ipairs(COBBLE_SLOTS) do
    local stack = inv.getStackInInternalSlot(slot)
    if stack and stack.size and stack.size > 0 then
      robot.select(slot)
      if robot.placeDown() then
        return true
      end
    end
  end
  return false
end

local function slotLabel(slot)
  local stack = inv.getStackInInternalSlot(slot)
  if stack then
    return stack.label or stack.name
  end
  return nil
end

local function emptyBucketFromSlot(slot)
  robot.select(slot)
  local before = slotLabel(slot)
  if not before then
    return false
  end
  if robot.detectDown() then
    return false
  end
  if not inv.equip() then
    return false
  end
  pcall(function() robot.useDown(nil, true) end)
  inv.equip()
  local after = slotLabel(slot)
  return before ~= after
end

local function placeWaterDown()
  for _, slot in ipairs(WATER_SLOTS) do
    if slotLabel(slot) then
      if emptyBucketFromSlot(slot) then
        return true
      end
    end
  end
  return false
end

local function isTracked(name)
  for _, r in ipairs(TRACKED_RESOURCES) do
    if r.name == name then
      return r
    end
  end
  return nil
end

local function positionAtChest(cx, cy, cz)
  gotoNoBreak(cx + 1, cz, cy + 1)
  while pos.y > cy do
    if not moveDown() then break end
  end
  while pos.y < cy do
    if not moveUp() then break end
  end
  face(3)
end

local function chestCountOf(name)
  local total = 0
  local size = inv.getInventorySize(sides.front)
  if not size then
    return 0
  end
  for slot = 1, size do
    local stack = inv.getStackInSlot(sides.front, slot)
    if stack and stack.name == name and stack.size then
      total = total + stack.size
    end
  end
  return total
end

local function depositTrackedChest()
  positionAtChest(TRACKED_CHEST.x, TRACKED_CHEST.y, TRACKED_CHEST.z)

  for i = 1, 16 do
    local stack = inv.getStackInInternalSlot(i)
    if stack and stack.name and stack.size and stack.size > 0 then
      local r = isTracked(stack.name)
      if r then
        local stored = chestCountOf(stack.name)
        local room = r.target - stored
        if room > 0 then
          local toDrop = math.min(room, stack.size)
          robot.select(i)
          robot.drop(toDrop)
        end
      end
    end
  end
end

local function hasAnyItems()
  for i = 1, 16 do
    local stack = inv.getStackInInternalSlot(i)
    if stack and stack.size and stack.size > 0 then
      return true
    end
  end
  return false
end

local function dumpAllHere()
  for i = 1, 16 do
    local stack = inv.getStackInInternalSlot(i)
    if stack and stack.size and stack.size > 0 then
      robot.select(i)
      robot.drop()
    end
  end
end

local function depositOverflow()
  for _, c in ipairs(CHEST_PLACEMENTS) do
    for level = 1, CHEST_STACK_HEIGHT do
      if not hasAnyItems() then
        return
      end
      if not (c.x == TRACKED_CHEST.x and c.z == TRACKED_CHEST.z and level == TRACKED_CHEST.y) then
        positionAtChest(c.x, level, c.z)
        dumpAllHere()
      end
    end
  end
end

local function inventory()
  gotoNoBreak(STASIS_X, STASIS_Z, STASIS_Y)
  depositTrackedChest()
  depositOverflow()
  return "mining"
end

local MINE_START_X = 4
local MINE_START_Y = 0
local MINE_START_Z = 4

local PILLAR_X = 4
local PILLAR_Z = 5

local QUARRY_MIN_X = 0
local QUARRY_MAX_X = 31
local QUARRY_MIN_Z = 0
local QUARRY_MAX_Z = 31
local QUARRY_BAND = 8

local function selectReserveCobble()
  for _, slot in ipairs(RESERVE_COBBLE_SLOTS) do
    local stack = inv.getStackInInternalSlot(slot)
    if stack and stack.size and stack.size > 0 then
      robot.select(slot)
      return true
    end
  end
  return false
end

local function placeReserveCobbleDown()
  if robot.detectDown() then
    return true
  end
  if selectReserveCobble() then
    return robot.placeDown()
  end
  return false
end

local function gotoMiningStart()
  while pos.y < TRAVEL_Y do
    if not moveUp() then break end
  end
  gotoXZNoDig(MINE_START_X, MINE_START_Z)
  while pos.y > MINE_START_Y do
    if robot.detectDown() then robot.swingDown() end
    if not moveDown() then break end
  end
end

local shaftDepth = 0

local function returnToShaft()
  gotoXZ(MINE_START_X, MINE_START_Z)
end

local function digShaftToBedrock()
  gotoXZ(PILLAR_X, PILLAR_Z)
  shaftDepth = 0
  while true do
    if robot.detectDown() then
      robot.swingDown()
    end
    if not moveDown() then
      break
    end
    shaftDepth = shaftDepth + 1
  end
end

local function buildPillarUp()
  while pos.y < MINE_START_Y do
    if robot.detectUp() then robot.swingUp() end
    if not moveUp() then break end
    placeReserveCobbleDown()
  end
end

local function climbToSurface()
  gotoXZ(MINE_START_X, MINE_START_Z)
  while pos.y < MINE_START_Y do
    if robot.detectUp() then robot.swingUp() end
    if not moveUp() then break end
  end
  gotoXZ(MINE_START_X, MINE_START_Z)
end

local miningStarted = false
local function mining()
  if batteryLevel() < 0.25 then
    return "returning"
  end

  if not miningStarted then
    gotoMiningStart()
    miningStarted = true
  end

  digShaftToBedrock()
  buildPillarUp()

  return "quarry"
end

local function sweepQuarryLayer()
  gotoXZ(QUARRY_MIN_X, QUARRY_MIN_Z)
  local xi = QUARRY_MIN_X
  local goingUpZ = true
  while xi <= QUARRY_MAX_X do
    if goingUpZ then
      gotoXZ(xi, QUARRY_MAX_Z)
    else
      gotoXZ(xi, QUARRY_MIN_Z)
    end
    goingUpZ = not goingUpZ
    xi = xi + 1
    if xi <= QUARRY_MAX_X then
      gotoXZ(xi, pos.z)
    end
  end
end

local function descendShaftTo(targetY)
  gotoXZ(MINE_START_X, MINE_START_Z)
  while pos.y > targetY do
    if robot.detectDown() then robot.swingDown() end
    if not moveDown() then break end
  end
end

local function quarry()
  local bottomY = MINE_START_Y - shaftDepth

  while bottomY < MINE_START_Y do
    if batteryLevel() < 0.25 then
      returnToShaft()
      climbToSurface()
      return "returning"
    end

    local workBottom = bottomY + 1

    descendShaftTo(workBottom)

    for layer = 1, QUARRY_BAND - 1 do
      if batteryLevel() < 0.25 then
        returnToShaft()
        climbToSurface()
        return "returning"
      end
      sweepQuarryLayer()
      if layer < QUARRY_BAND - 1 then
        if robot.detectUp() then robot.swingUp() end
        if not moveUp() then break end
      end
    end

    bottomY = bottomY + QUARRY_BAND
  end

  returnToShaft()
  climbToSurface()
  return "returning"
end

local function building()

  gotoBuildCorner()
  if robot.detectUp() then robot.swingUp() end
  moveUp()

  for xi = 0, BUILD_X - 1 do
    local zStart, zEnd, zStep
    if xi % 2 == 0 then
      zStart, zEnd, zStep = 0, BUILD_Z - 1, 1
    else
      zStart, zEnd, zStep = BUILD_Z - 1, 0, -1
    end
    for zi = zStart, zEnd, zStep do
      gotoXZ(xi, zi)

      if robot.detectDown() then robot.swingDown() end
      local override = floorOverride(xi, zi)
      if override then
        placeSlotDown(override)
      else
        if not placeCobbleDown() then
          return "returning"
        end
      end
    end
  end

  if robot.detectUp() then robot.swingUp() end
  moveUp()

  for _, p in ipairs(PLACEMENTS) do
    gotoNoBreak(p.x, p.z, 2)
    placeSlotDown(p.slot)
  end

  for _, c in ipairs(CHEST_PLACEMENTS) do
    gotoNoBreak(c.x, c.z, 2)
    for level = 1, CHEST_STACK_HEIGHT do
      placeSlotDown(SLOTS.chest)
      if level < CHEST_STACK_HEIGHT then
        if not moveUp() then break end
      end
    end
  end

  for _, s in ipairs(SAND_PLACEMENTS) do
    gotoNoBreak(s.x, s.z, 2)
    placeSlotDown(SLOTS.sand)
  end

  for _, w in ipairs(WATER_PLACEMENTS) do
    gotoNoBreak(w.x, w.z, 2)
    placeWaterDown()
  end

  for _, p in ipairs(Y2_PLACEMENTS) do
    gotoNoBreak(p.x, p.z, 3)
    placeSlotDown(p.slot)
  end

  gotoNoBreak(4, 2, 3)
  pcall(function() robot.useDown() end)

  return "stasis"
end

local function returning()
  climbToSurface()
  return "stasis"
end

local function stasis()
  while pos.y < TRAVEL_Y do
    if not moveUp() then break end
  end
  gotoXZNoDig(STASIS_X, STASIS_Z)
  while pos.y > STASIS_Y do
    if not moveDown() then break end
  end
  while pos.y < STASIS_Y do
    if not moveUp() then break end
  end

  while batteryLevel() < 0.9 do
    os.sleep(5)
  end
  return "mining"
end

local states = {
  mining = mining,
  inventory = inventory,
  building = building,
  returning = returning,
  stasis = stasis,
  quarry = quarry,
}

while true do
  local handler = states[state]
  if not handler then
    error("Unknown state: " .. tostring(state))
  end
  state = handler()
end
