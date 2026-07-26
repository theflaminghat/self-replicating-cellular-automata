-- quarry.lua
local C = require("common")

local robot = C.robot
local pos = C.pos
local moveUp = C.moveUp
local moveDown = C.moveDown
local gotoXZ = C.gotoXZ
local batteryLevel = C.batteryLevel
local climbToSurface = C.climbToSurface

local function returnToShaft()
  gotoXZ(C.MINE_START_X, C.MINE_START_Z)
end

local BATTERY_MIN = 0.25

local function lowBattery()
  return batteryLevel() < BATTERY_MIN
end

local function patchFloorHere()
  if robot.detectDown() then
    return true
  end
  for _, slot in ipairs(C.RESERVE_COBBLE_SLOTS) do
    local stack = C.inv.getStackInInternalSlot(slot)
    if stack and stack.size and stack.size > 0 then
      robot.select(slot)
      if robot.placeDown() then
        return true
      end
    end
  end
  return false
end

local function isShaftCell(x, z)
  return (x == C.MINE_START_X and z == C.MINE_START_Z)
      or (x == C.FLOOR_HOLE_X and z == C.FLOOR_HOLE_Z)
end

local function isProtectedCell(x, z)
  -- Never fill the escape shaft (the robot climbs out through it) and never
  -- disturb the pillar column.
  return isShaftCell(x, z)
      or (x == C.PILLAR_X and z == C.PILLAR_Z)
end

local function visitCell(patch)
  if patch and not isProtectedCell(pos.x, pos.z) then
    patchFloorHere()
  end
end

-- Quarry progress, persisted to a file so it survives reboots and chunk
-- unloads. bandBottom / layer / xi / zi mark exactly where the sweep stopped so
-- it can pick up from the same cell instead of restarting the whole quarry.
local PROGRESS_FILE = "/home/quarry_progress.txt"

local progress = {
  started    = false,
  bandBottom = nil,
  layer      = 1,
  xi         = nil,
  zi         = nil,
  done       = false,
  shaftDepth = nil,
}

local function saveProgress()
  local f = io.open(PROGRESS_FILE, "w")
  if not f then
    return false
  end
  f:write(string.format(
    "started=%s\nbandBottom=%s\nlayer=%s\nxi=%s\nzi=%s\ndone=%s\nshaftDepth=%s\n",
    tostring(progress.started),
    tostring(progress.bandBottom or ""),
    tostring(progress.layer or 1),
    tostring(progress.xi or ""),
    tostring(progress.zi or ""),
    tostring(progress.done),
    tostring(progress.shaftDepth or "")))
  f:close()
  return true
end

local function loadProgress()
  local f = io.open(PROGRESS_FILE, "r")
  if not f then
    return false
  end
  for line in f:lines() do
    local k, v = line:match("^(%w+)=(.*)$")
    if k then
      if k == "started" or k == "done" then
        progress[k] = (v == "true")
      elseif v == "" then
        progress[k] = nil
      else
        progress[k] = tonumber(v)
      end
    end
  end
  f:close()
  if progress.layer == nil then
    progress.layer = 1
  end
  return true
end

function C.resetQuarryProgress()
  progress.started = false
  progress.bandBottom = nil
  progress.layer = 1
  progress.xi = nil
  progress.zi = nil
  progress.done = false
  progress.shaftDepth = nil
  local ok, fs = pcall(require, "filesystem")
  if ok and fs and fs.remove then
    pcall(fs.remove, PROGRESS_FILE)
  else
    local f = io.open(PROGRESS_FILE, "w")
    if f then f:close() end
  end
end

local function zRangeFor(xi)
  -- Boustrophedon: direction depends on the column index so the pattern is
  -- deterministic and resumable regardless of where we left off.
  local even = ((xi - C.QUARRY_MIN_X) % 2 == 0)
  if even then
    return C.QUARRY_MIN_Z, C.QUARRY_MAX_Z, 1
  end
  return C.QUARRY_MAX_Z, C.QUARRY_MIN_Z, -1
end

local function sweepQuarryLayer(patch, resumeXi, resumeZi)
  if lowBattery() then return false end
  local startXi = resumeXi or C.QUARRY_MIN_X
  for xi = startXi, C.QUARRY_MAX_X do
    if lowBattery() then
      progress.xi, progress.zi = xi, nil
      saveProgress()
      return false
    end
    -- Reserve cobble is only spent on the bottom layer (patching floor holes), so
    -- only bother topping it up / checking it there. Keep it filled from freshly
    -- mined cobble; if it drops near empty the robot can't patch or pillar back out,
    -- so bail (recovered by the inventory step's reserve refill next cycle).
    if patch then
      if C.reserveCobbleDeficit() > 0 then C.topUpReserveFromInventory() end
      if C.reserveCobbleCount() <= C.RESERVE_BAILOUT then
        progress.xi, progress.zi = xi, nil
        saveProgress()
        return "reserve_out"
      end
    end
    local zFrom, zTo, zStep = zRangeFor(xi)
    if resumeZi and xi == startXi then
      zFrom = resumeZi
      resumeZi = nil
    end
    for zi = zFrom, zTo, zStep do
      if lowBattery() then
        progress.xi, progress.zi = xi, zi
        saveProgress()
        return false
      end
      -- If the pickaxe broke, stop and go make a new one. Save exactly where we
      -- are so the quarry resumes this same cell afterward.
      if C.toolBrokenOrLow() then
        progress.xi, progress.zi = xi, zi
        saveProgress()
        return "craft_pickaxe"
      end
      if not C.isPillarCell(xi, zi) then
        gotoXZ(xi, zi)
        if pos.x == xi and pos.z == zi then
          visitCell(patch)
        end
      end
    end
    -- Line (column pass) complete: record the next column and persist.
    progress.xi, progress.zi = xi + 1, nil
    saveProgress()
  end
  progress.xi, progress.zi = nil, nil
  saveProgress()
  return true
end

-- Position the robot in the shaft at exactly targetY, whether it needs to go DOWN
-- (resuming from the surface) or UP (it just probed to bedrock, or is climbing from
-- one band to the next through the already-open shaft). Only moving down -- as it
-- did before -- left the robot a layer too low and it swept/skipped at the wrong
-- height, which looked like switching layers before finishing the current one.
local function descendShaftTo(targetY)
  gotoXZ(C.MINE_START_X, C.MINE_START_Z)
  while pos.y > targetY do
    if robot.detectDown() then robot.swingDown() end
    if not moveDown() then break end
  end
  while pos.y < targetY do
    if robot.detectUp() then robot.swingUp() end
    if not moveUp() then break end
  end
end

local function returnToStasis()
  while pos.y < C.STASIS_Y do
    if robot.detectUp() then robot.swingUp() end
    if not moveUp() then break end
  end
  while pos.y > C.STASIS_Y do
    if not moveDown() then break end
  end
  C.gotoXZ(C.STASIS_X, C.STASIS_Z)
  C.face(2)
end

-- Drive the robot home from wherever it is in the quarry. `reason` decides what
-- the state reports back: "returning" for a genuine low-battery bail (so the
-- scheduler runs a charge cycle), or "stasis" when we're simply finished -- the
-- robot is already parked at the charger, so a charge cycle would just make it
-- walk the same path again.
local function bailOut(reason)
  returnToShaft()
  climbToSurface()
  C.protectPillar = false
  returnToStasis()
  return reason or "returning"
end

local loadedFromFile = false

local function quarry()
  C.allowHole = true
  C.protectPillar = true

  -- Pull saved progress off disk once per session so a reboot resumes.
  if not loadedFromFile then
    loadedFromFile = true
    if not progress.started then
      loadProgress()
    end
  end

  if progress.done then
    -- Nothing left to dig; bailOut parks us at the charger already.
    return bailOut("stasis")
  end

  -- Descend the shaft and measure the true bedrock depth. Returns the y one
  -- block above bedrock. Used both for a fresh quarry and to correct a stale
  -- saved depth (older runs could persist a too-shallow shaftDepth).
  local function probeBedrock()
    gotoXZ(C.MINE_START_X, C.MINE_START_Z)
    while true do
      if robot.detectDown() then robot.swingDown() end
      if not moveDown() then break end
    end
    return pos.y
  end

  -- Resume from remembered progress, or start a fresh quarry.
  if not progress.started then
    progress.started = true
    -- Fresh quarry: measure the real bedrock depth once.
    local bottom = probeBedrock()
    C.shaftDepth = C.MINE_START_Y - bottom
    progress.shaftDepth = C.shaftDepth
    progress.bandBottom = bottom
    progress.layer = 1
    progress.xi, progress.zi = nil, nil
    saveProgress()
  else
    -- Resuming: trust the saved depth. Do NOT re-probe here -- probing digs the
    -- shaft down again and, because quarried layers change the shaft floor, it
    -- would often read a lower bottom and reset layer/xi/zi, throwing away the
    -- robot's remembered place in the sweep.
    if progress.shaftDepth then
      C.shaftDepth = progress.shaftDepth
    end
    if not progress.bandBottom then
      -- No saved bottom (older/corrupt progress): measure it once now.
      local bottom = probeBedrock()
      progress.bandBottom = bottom
      C.shaftDepth = C.MINE_START_Y - bottom
      progress.shaftDepth = C.shaftDepth
      saveProgress()
    end
  end

  local bottomY = progress.bandBottom
  while bottomY < C.MINE_START_Y do
    if lowBattery() then
      progress.bandBottom = bottomY
      saveProgress()
      return bailOut()
    end

    local workBottom = bottomY + 1
    -- Descend to the layer we were working on (workBottom + layers already done).
    local targetY = workBottom + (progress.layer - 1)
    descendShaftTo(targetY)

    for layer = progress.layer, C.QUARRY_BAND - 1 do
      if lowBattery() then
        progress.bandBottom = bottomY
        progress.layer = layer
        saveProgress()
        return bailOut()
      end
      local isBottomLayer = (layer == 1)
      local sweepResult = sweepQuarryLayer(isBottomLayer, progress.xi, progress.zi)
      if sweepResult == "craft_pickaxe" then
        progress.bandBottom = bottomY
        progress.layer = layer
        saveProgress()
        -- Come up to the surface, then hand off to the pickaxe-crafting state.
        climbToSurface()
        C.protectPillar = false
        return "craft_pickaxe"
      elseif sweepResult == "reserve_out" then
        -- Out of cobble to pillar with: go home and let the weave refill the
        -- reserve (inventory step) before the next quarry pass resumes here.
        progress.bandBottom = bottomY
        progress.layer = layer
        saveProgress()
        return bailOut()
      elseif not sweepResult then
        progress.bandBottom = bottomY
        progress.layer = layer
        saveProgress()
        return bailOut()
      end
      progress.xi, progress.zi = nil, nil
      if layer < C.QUARRY_BAND - 1 then
        if robot.detectUp() then robot.swingUp() end
        if not moveUp() then break end
      end
    end

    bottomY = bottomY + C.QUARRY_BAND
    progress.bandBottom = bottomY
    progress.layer = 1
    progress.xi, progress.zi = nil, nil
    saveProgress()
  end

  progress.done = true
  saveProgress()
  return bailOut("stasis")
end

return quarry
