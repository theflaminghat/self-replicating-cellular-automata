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

-- Component reads (getStackInInternalSlot) are the crafting bottleneck: the count
-- helpers scan every slot, and they run several times per craft pass. So a pass
-- snapshots the whole inventory ONCE and the read-only counters read the snapshot.
-- snapAt falls back to a live read when no snapshot is active (the mutating
-- helpers -- loadGrid, selectResultSlot -- always read live).
local invSnap = nil
local function refreshInvSnap()
  invSnap = {}
  for s = 1, (C.INVENTORY_SIZE or 32) do
    invSnap[s] = stackAt(s)
  end
end
local function clearInvSnap()
  invSnap = nil
end
local function snapAt(slot)
  if invSnap then return invSnap[slot] end
  return stackAt(slot)
end

local function countInInventory(item)
  local total = 0
  local size = C.INVENTORY_SIZE or 32
  for s = 1, size do
    local st = snapAt(s)
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

-- Move to a given target-chest level (the 3 target chests share one access column,
-- reached by moving up/down).
local function goToChestLevel(level)
  while pos.y < level do if not moveUp() then break end end
  while pos.y > level do if not moveDown() then break end end
end

-- Index all 3 target chests, tagging each entry with the level it lives at so pulls
-- and drops can navigate back to it. Ends at the home (bottom) level.
local function buildChestIndex()
  chestIndex = {}
  for _, cell in ipairs(C.TRACKED_CHESTS) do
    goToChestLevel(cell.y)
    local size = inv.getInventorySize(sides.front)
    if size then
      for s = 1, size do
        local st = inv.getStackInSlot(sides.front, s)
        if st and st.name and st.size and st.size > 0 then
          chestIndex[#chestIndex + 1] =
            { level = cell.y, slot = s, stack = st, size = st.size }
        end
      end
    end
  end
  goToChestLevel(C.TRACKED_CHEST.y)
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

-- How many of `name` are already embodied in finished products that consume it --
-- and, recursively, in the products that consume THOSE. An intermediate (a dropper,
-- a chest baked into a machine, ...) is consumed the moment its parent is crafted,
-- so a loose-only count reads it as "0 made" and the autocrafter re-crafts a whole
-- batch every cycle, piling the surplus into overflow. Crediting the embodied copies
-- makes a fully-consumed intermediate read as satisfied. `seen` guards recipe cycles.
local function embodiedCount(name, seen)
  seen = seen or {}
  if seen[name] then return 0 end
  seen[name] = true
  local total = 0
  for _, c in ipairs(C.itemConsumers(name)) do
    local spec = C.specFor(c.name)
    local made = countInInventory(spec) + chestCountOf(spec) + embodiedCount(c.name, seen)
    -- `made` output items came from made/yield crafts, each consuming `per` of
    -- `name`. So the amount embodied is (made / yield) * per -- dividing by the
    -- consumer's yield, or a high-yield consumer (transistor: 1 paper -> 8) would
    -- over-count the embodied ingredient (8x here) and stall crafting of it.
    total = total + (made / (c.yield or 1)) * c.per
  end
  return total
end

local function pullFromChest(item, count, intoSlot)
  local got = 0
  for _, e in ipairs(chestEntries()) do
    if got >= count then break end
    if e.size > 0 and stackMatches(e.stack, item) then
      goToChestLevel(e.level or C.TRACKED_CHEST.y)   -- the chest this stack lives in
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
  goToChestLevel(C.TRACKED_CHEST.y)   -- back home
  return got
end

-- Drop the slot's contents into the target chests, spilling to the next one when a
-- chest fills. Returns true only if the slot ended up empty (fully stored).
local function dropSlotIntoChest(slot)
  local st = stackAt(slot)
  if not (st and st.size and st.size > 0) then
    return true
  end
  for _, cell in ipairs(C.TRACKED_CHESTS) do
    local cur = inv.getStackInInternalSlot(slot)
    if not (cur and cur.size and cur.size > 0) then break end   -- emptied
    goToChestLevel(cell.y)
    robot.select(slot)
    robot.drop()
  end
  goToChestLevel(C.TRACKED_CHEST.y)
  invalidateChestIndex()
  local final = inv.getStackInInternalSlot(slot)
  return not (final and final.size and final.size > 0)
end

local function isGridSlot(slot)
  for _, g in ipairs(GRID) do
    if g == slot then return true end
  end
  return false
end

local isReserveSlot = C.isReserveSlot

-- Ingredients can come from the robot's own inventory as well as the chest (the
-- robot carries overflow tracked items and freshly crafted intermediates). Count
-- and pull from non-grid, non-reserve internal slots.
local function inventoryCountOf(item)
  local total = 0
  local size = C.INVENTORY_SIZE or 32
  for s = 1, size do
    if not isGridSlot(s) and not isReserveSlot(s) then
      local st = snapAt(s)
      if st and st.size and stackMatches(st, item) then
        total = total + st.size
      end
    end
  end
  return total
end

-- Total of `item` available to craft with: chest + inventory.
local function availableCount(item)
  return chestCountOf(item) + inventoryCountOf(item)
end

-- Move up to `count` of `item` from inventory into grid slot `gridSlot`.
local function pullFromInventory(item, count, gridSlot)
  local got = 0
  local size = C.INVENTORY_SIZE or 32
  for s = 1, size do
    if got >= count then break end
    if s ~= gridSlot and not isGridSlot(s) and not isReserveSlot(s) then
      local st = stackAt(s)
      if st and st.size and st.size > 0 and stackMatches(st, item) then
        local take = math.min(count - got, st.size)
        robot.select(s)
        if robot.transferTo(gridSlot, take) then
          got = got + take
        end
      end
    end
  end
  return got
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
    if availableCount(need.item) < need.count * batches then
      return false
    end
  end
  return true
end

-- Fill the grid for `mult` batches, sourcing each ingredient from the robot's own
-- inventory first, then the chest for any remainder.
local function loadGrid(recipe, mult)
  mult = mult or 1
  for i = 1, 9 do
    local item = recipe.grid[i]
    if item then
      local slot = GRID[i]
      local got = pullFromInventory(item, mult, slot)
      if got < mult then
        got = got + pullFromChest(item, mult - got, slot)
      end
      if got < mult then
        return false
      end
    end
  end
  return true
end

local function maxMultiplier(recipe, wantBatches)
  local yield = recipe.yield or 1
  local m = wantBatches
  if m > 64 then m = 64 end
  -- Never make more than one output stack (64) in a single craft, or the result
  -- overflows its slot -- possibly into the crafting grid.
  local perStack = math.max(1, math.floor(64 / yield))
  if m > perStack then m = perStack end
  for _, need in pairs(ingredientNeeds(recipe)) do
    local avail = availableCount(need.item)
    local canDo = math.floor(avail / need.count)
    if canDo < m then m = canDo end
  end
  if m < 1 then m = 1 end
  return m
end

-- Craft the result into a FRESH empty non-grid, non-reserve slot. Because each
-- craft yields at most one stack (maxMultiplier caps it), an empty slot always has
-- room -- so the result never overflows into another slot, and in particular never
-- spills into the crafting grid.
local function selectResultSlot()
  local size = C.INVENTORY_SIZE or 32
  for s = 1, size do
    if not isGridSlot(s) and not isReserveSlot(s) and not stackAt(s) then
      robot.select(s)
      return true
    end
  end
  return false
end

local function craftOnce(recipe, crafting, count)
  if not selectResultSlot() then
    return false
  end
  return crafting.craft(count or recipe.yield)
end

-- Safety cap on loop passes. Each pass makes up to one output stack, so this many
-- passes covers any realistic job while still bounding a runaway loop.
local MAX_PASSES = 64

local function runJob(job, crafting)
  local recipe = recipeFor(job.name)
  if not recipe then
    return 0, "no recipe for " .. tostring(job.name)
  end

  local resultItem = recipe.result or job.name

  local target = job.amount or 0
  local batches = 0

  -- Copies of this item already consumed into finished parents. Crafting this item
  -- doesn't change its consumers' counts, so compute it once per job rather than per
  -- pass. Without it, a consumed intermediate re-crafts a full batch every cycle.
  local embodied = embodiedCount(job.name, nil)

  local function have()
    local n = countInInventory(resultItem)
    if job.countChest then
      n = n + chestCountOf(resultItem)
    end
    return n + embodied
  end

  for _ = 1, MAX_PASSES do
    if batteryLevel() < 0.25 then
      return batches, "low battery"
    end
    -- The snapshot is kept current by crafting_state up front and refreshed after
    -- each craft (and after a failure's clearGrid) below, so it's already valid
    -- here. An already-satisfied job therefore costs one count, not a fresh
    -- full-inventory scan -- the win across a weave's worth of mostly-done jobs.
    local before = have()
    if before >= target then
      break
    end
    if not chestCanSupply(recipe, 1) then
      return batches, "out of materials"
    end

    local yield = recipe.yield or 1
    local shortfall = target - before
    local wantBatches = math.ceil(shortfall / yield)
    if wantBatches < 1 then wantBatches = 1 end
    local mult = maxMultiplier(recipe, wantBatches)

    if not loadGrid(recipe, mult) then
      clearGrid()
      refreshInvSnap()
      return batches, "could not load grid"
    end
    if not craftOnce(recipe, crafting, yield * mult) then
      clearGrid()
      refreshInvSnap()
      return batches, "craft failed"
    end
    batches = batches + mult
    refreshInvSnap()   -- inventory changed; keep the snapshot current

    -- Stop if the freshly crafted output isn't being counted toward the target
    -- (have() didn't rise). That means the recipe's result identity doesn't match
    -- the live item's, and without this guard the loop would keep crafting until it
    -- burned through every ingredient making output it can't recognize.
    if have() <= before then
      return batches, "crafted output not counted (recipe result vs live item)"
    end
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

  -- Prime the inventory snapshot once; runJob keeps it current after each craft,
  -- so jobs that are already satisfied don't each re-scan all 64 slots.
  refreshInvSnap()

  -- The chest index is a module-level cache that survives between crafting_state
  -- calls. A stale copy from an earlier weave cycle wouldn't include items the
  -- inventory step has deposited since (finished furnaces, chests, ...), so have()
  -- would read 0 and re-craft a fresh batch every cycle. Drop it so the first
  -- count/pull this run reads the tracked chest's CURRENT contents.
  invalidateChestIndex()

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
    -- No per-job deposit: a finished item stays in the robot's inventory, where a
    -- later job sources it directly (loadGrid pulls ingredients from inventory as
    -- well as the chest), and the inventory state deposits the finished items to
    -- the tracked chest afterward. Skipping the deposit keeps the chest index
    -- valid across jobs, so the chest is scanned once instead of once per job.
  end

  clearInvSnap()

  -- Head back to the charger so the next state starts from stasis.
  C.gotoStasisFromChest()
  return "stasis"
end

C.craftJobs = function(jobs)
  return crafting_state(jobs)
end

return crafting_state
