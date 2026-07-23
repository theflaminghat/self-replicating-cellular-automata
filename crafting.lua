local C = require("common")

local robot = C.robot
local pos = C.pos
local inv = C.inv
local sides = C.sides
local moveUp = C.moveUp
local moveDown = C.moveDown
local batteryLevel = C.batteryLevel

local GRID = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }

local function isCallable(v)
  if type(v) == "function" then
    return true
  end
  if type(v) == "table" then
    local mt = getmetatable(v)
    return mt ~= nil and mt.__call ~= nil
  end
  return false
end

local function usableCrafting(c)
  return c and c.craft ~= nil and isCallable(c.craft)
end

local function craftingComponent()
  -- Preferred: the component.crafting shortcut (works when there is exactly one
  -- crafting component).
  local ok, c = pcall(function() return C.component.crafting end)
  if ok and usableCrafting(c) then
    return c
  end

  -- Fallback: scan the component list for a "crafting" component and proxy it.
  -- This catches setups where the shortcut doesn't resolve even though a crafting
  -- upgrade is installed.
  local okList, iter = pcall(C.component.list, "crafting")
  if okList and iter then
    for addr in iter do
      local okP, proxy = pcall(C.component.proxy, addr)
      if okP and usableCrafting(proxy) then
        return proxy
      end
    end
  end

  return nil, "no crafting component (is a Crafting Upgrade installed?)"
end

-- Shared item helpers (defined in common.lua).
local itemSpec     = C.itemSpec
local stackMatches = C.matchesSpec

-- specLabel keys a grid ingredient for aggregation: label, else name:damage, else
-- name. Distinct from C.specText (which never appends the damage), so kept local.
local function specLabel(item)
  local spec = itemSpec(item)
  if spec.label then return spec.label end
  if spec.damage then return tostring(spec.name) .. ":" .. tostring(spec.damage) end
  return tostring(spec.name)
end

local function stackAt(slot)
  return inv.getStackInInternalSlot(slot)
end

local function countInInventory(item)
  local total = 0
  local size = C.INVENTORY_SIZE or 32
  for s = 1, size do
    local st = stackAt(s)
    if stackMatches(st, item) and st.size then
      total = total + st.size
    end
  end
  return total
end

local function goToTrackedChest()
  while pos.y > C.TRACKED_CHEST.y do
    if not moveDown() then break end
  end
  while pos.y < C.TRACKED_CHEST.y do
    if not moveUp() then break end
  end
  C.gotoXZNoDig(C.TRACKED_CHEST.x + 1, C.TRACKED_CHEST.z)
  C.face(3)
end

local chestIndex = nil

local function buildChestIndex()
  chestIndex = {}
  local size = inv.getInventorySize(sides.front)
  if not size then
    return false
  end
  for s = 1, size do
    local st = inv.getStackInSlot(sides.front, s)
    if st and st.name and st.size and st.size > 0 then
      chestIndex[#chestIndex + 1] = { slot = s, stack = st, size = st.size }
    end
  end
  return true
end

local function invalidateChestIndex()
  chestIndex = nil
end

local function chestEntries()
  if not chestIndex then
    buildChestIndex()
  end
  return chestIndex or {}
end

local function chestCountOf(item)
  local total = 0
  for _, e in ipairs(chestEntries()) do
    if e.size > 0 and stackMatches(e.stack, item) then
      total = total + e.size
    end
  end
  return total
end

local function pullFromChest(item, count, intoSlot)
  local got = 0
  for _, e in ipairs(chestEntries()) do
    if got >= count then break end
    if e.size > 0 and stackMatches(e.stack, item) then
      local take = math.min(count - got, e.size)
      robot.select(intoSlot)
      if inv.suckFromSlot(sides.front, e.slot, take) then
        got = got + take
        e.size = e.size - take
      else
        invalidateChestIndex()
        break
      end
    end
  end
  return got
end

local function dropSlotIntoChest(slot)
  local st = stackAt(slot)
  if not (st and st.size and st.size > 0) then
    return true
  end
  robot.select(slot)
  local ok = robot.drop()
  invalidateChestIndex()
  return ok
end

local function isGridSlot(slot)
  for _, g in ipairs(GRID) do
    if g == slot then return true end
  end
  return false
end

local isReserveSlot = C.isReserveSlot

-- Drop every non-grid, non-reserve slot holding `item` into the chest in front,
-- and invalidate the cached chest index so a later pull sees the new stock. Used
-- by recursive crafting so an intermediate an earlier job made is available in
-- the chest for the job that depends on it.
local function depositResult(item)
  local size = C.INVENTORY_SIZE or 32
  local dropped = false
  for s = 1, size do
    if not isGridSlot(s) and not isReserveSlot(s) then
      local st = stackAt(s)
      if st and st.size and st.size > 0 and stackMatches(st, item) then
        robot.select(s)
        if robot.drop() then dropped = true end
      end
    end
  end
  if dropped then invalidateChestIndex() end
end

local function findParkingSlot()
  local size = C.INVENTORY_SIZE or 32
  for s = 1, size do
    if not isGridSlot(s) and not isReserveSlot(s) then
      if not stackAt(s) then
        return s
      end
    end
  end
  return nil
end

local function clearGrid()
  for _, slot in ipairs(GRID) do
    local st = stackAt(slot)
    if st and st.size and st.size > 0 then
      local park = findParkingSlot()
      if park then
        robot.select(slot)
        if not robot.transferTo(park) then
          if not dropSlotIntoChest(slot) then
            return false
          end
        end
      elseif not dropSlotIntoChest(slot) then
        return false
      end
    end
  end
  return true
end

local function gridIsClear()
  for _, slot in ipairs(GRID) do
    local st = stackAt(slot)
    if st and st.size and st.size > 0 then
      return false
    end
  end
  return true
end

-- Recipes are keyed by item id ("oc:transistor"), but build items are often
-- requested by display label ("Transistor", "Computer Case (Tier 3)", ...).
-- Resolve a name to its recipe whether it is given as the id/key OR the result
-- label -- otherwise every label-named craft job fails with "no recipe" even when
-- all the materials are in the chest.
local labelToKey
local function recipeFor(name)
  if C.RECIPES and C.RECIPES[name] then
    return C.RECIPES[name]
  end
  if not labelToKey then
    labelToKey = {}
    for key, recipe in pairs(C.RECIPES or {}) do
      if type(recipe.result) == "table" and recipe.result.label then
        labelToKey[recipe.result.label] = key
      end
    end
  end
  local key = labelToKey[name]
  return key and C.RECIPES[key] or nil
end

local function ingredientNeeds(recipe)
  local needs = {}
  for i = 1, 9 do
    local item = recipe.grid[i]
    if item then
      local key = specLabel(item)
      if needs[key] then
        needs[key].count = needs[key].count + 1
      else
        needs[key] = { item = item, count = 1 }
      end
    end
  end
  return needs
end

local function chestCanSupply(recipe, batches)
  if C.assumeMaterials then
    return true
  end
  for _, need in pairs(ingredientNeeds(recipe)) do
    if chestCountOf(need.item) < need.count * batches then
      return false
    end
  end
  return true
end

local function loadGrid(recipe, mult)
  mult = mult or 1
  for i = 1, 9 do
    local item = recipe.grid[i]
    if item then
      local slot = GRID[i]
      if pullFromChest(item, mult, slot) < mult then
        return false
      end
    end
  end
  return true
end

local function maxMultiplier(recipe, wantBatches)
  local m = wantBatches
  if m > 64 then m = 64 end
  for _, need in pairs(ingredientNeeds(recipe)) do
    local avail = chestCountOf(need.item)
    local canDo = math.floor(avail / need.count)
    if canDo < m then m = canDo end
  end
  if m < 1 then m = 1 end
  return m
end

local function selectResultSlot(item)
  local size = C.INVENTORY_SIZE or 32
  for s = 1, size do
    if not isGridSlot(s) then
      local st = stackAt(s)
      if stackMatches(st, item) then
        robot.select(s)
        return true
      end
    end
  end
  for s = 1, size do
    if not isGridSlot(s) then
      if not stackAt(s) then
        robot.select(s)
        return true
      end
    end
  end
  return false
end

local function craftOnce(item, recipe, crafting, count)
  if not selectResultSlot(item) then
    return false
  end
  return crafting.craft(count or recipe.yield)
end

local MAX_BATCHES = 64

local function runJob(job, crafting)
  local recipe = recipeFor(job.name)
  if not recipe then
    return 0, "no recipe for " .. tostring(job.name)
  end

  local resultItem = recipe.result or job.name

  local target = job.amount or 0
  local batches = 0

  local function have()
    local n = countInInventory(resultItem)
    if job.countChest then
      n = n + chestCountOf(resultItem)
    end
    return n
  end

  while batches < MAX_BATCHES do
    if batteryLevel() < 0.25 then
      return batches, "low battery"
    end
    if have() >= target then
      break
    end
    if not chestCanSupply(recipe, 1) then
      return batches, "out of materials"
    end

    local yield = recipe.yield or 1
    local shortfall = target - have()
    local wantBatches = math.ceil(shortfall / yield)
    if wantBatches < 1 then wantBatches = 1 end
    local mult = maxMultiplier(recipe, wantBatches)

    if not loadGrid(recipe, mult) then
      clearGrid()
      return batches, "could not load grid"
    end
    if not craftOnce(resultItem, recipe, crafting, yield * mult) then
      clearGrid()
      return batches, "craft failed"
    end
    batches = batches + mult
  end

  return batches
end

local function crafting_state(jobs)
  if not jobs then
    return "stasis"
  end

  if jobs.name then
    jobs = { jobs }
  end
  if #jobs == 0 then
    return "stasis"
  end

  if batteryLevel() < 0.25 then
    return "returning"
  end

  local crafting, why = craftingComponent()
  if not crafting then
    C.lastCraftError = why or "no crafting upgrade installed"
    return "stasis"
  end

  C.lastCraftError = nil
  goToTrackedChest()

  if not inv.getInventorySize(sides.front) then
    C.lastCraftError = "not facing an inventory at the tracked chest"
    C.gotoStasisFromChest()
    return "stasis"
  end

  if not clearGrid() then
    C.lastCraftError = "could not clear the crafting grid into the chest"
    C.gotoStasisFromChest()
    return "stasis"
  end
  if not gridIsClear() then
    C.lastCraftError = "crafting grid still occupied"
    C.gotoStasisFromChest()
    return "stasis"
  end

  C.lastCraftReport = {}
  for _, job in ipairs(jobs) do
    if batteryLevel() < 0.25 then
      -- Low battery: the returning state drives its own path home.
      return "returning"
    end
    local batches, reason = runJob(job, crafting)
    C.lastCraftReport[#C.lastCraftReport + 1] = {
      name = job.name,
      amount = job.amount,
      batches = batches,
      reason = reason,
    }
    -- Recursive crafting: return the finished item to the chest so a later job can
    -- consume it. Opt-in (job.deposit) so single-item crafts that keep their
    -- result in the robot -- e.g. the pickaxe the scheduler equips -- are left be.
    if job.deposit and batches and batches > 0 then
      local recipe = recipeFor(job.name)
      depositResult(recipe and (recipe.result or job.name) or job.name)
    end
  end

  -- Head back to the charger so the next state starts from stasis.
  C.gotoStasisFromChest()
  return "stasis"
end

C.craftJobs = function(jobs)
  return crafting_state(jobs)
end

return crafting_state
