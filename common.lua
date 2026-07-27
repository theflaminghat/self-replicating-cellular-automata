local robot = require("robot")
local component = require("component")
local computer = require("computer")
local sides = require("sides")
local os = require("os")
local inv = component.inventory_controller

local C = {}

C.robot = robot
C.component = component
C.computer = computer
C.sides = sides
C.os = os
C.inv = inv

C.BUILD_X = 9
C.BUILD_Y = 3
C.BUILD_Z = 16

C.COBBLE_SLOTS = { 1, 2, 3 }
C.RESERVE_COBBLE_COUNT = 4
C.HIGHEST_NAMED_SLOT = 21
C.INVENTORY_SIZE = 64   -- 4 Inventory Upgrades x 16; refreshReserveSlots corrects
C.RESERVE_COBBLE_SLOTS = { 61, 62, 63, 64 }   -- top 4 slots of a 64-slot robot

-- Tool management. robot.durability() returns the fraction of durability left,
-- or nil when there's no tool (broken/absent). A very low value means it's about
-- to break. TOOL_SLOT is a fixed inventory slot used to stage a freshly crafted
-- pickaxe before equipping it.
C.TOOL_LOW = 0.05
C.TOOL_SLOT = 43

function C.toolBrokenOrLow()
  local ok, d = pcall(function() return C.robot.durability() end)
  if not ok then return false end        -- durability() errored; don't false-trigger
  if d == nil then return true end        -- no tool = broken
  return d <= C.TOOL_LOW
end

function C.refreshReserveSlots()
  local size = nil
  if robot.inventorySize then
    local ok, n = pcall(robot.inventorySize)
    if ok and type(n) == "number" and n > 0 then
      size = n
    end
  end
  C.INVENTORY_SIZE = size or 64   -- fall back to the expected 64-slot layout
  if not size then
    return C.RESERVE_COBBLE_SLOTS
  end
  local slots = {}
  for i = 0, C.RESERVE_COBBLE_COUNT - 1 do
    local s = size - i
    if s > C.HIGHEST_NAMED_SLOT then
      table.insert(slots, 1, s)
    end
  end
  if #slots > 0 then
    C.RESERVE_COBBLE_SLOTS = slots
  end
  C.RESERVE_SLOTS_OK = (#slots == C.RESERVE_COBBLE_COUNT)
  return C.RESERVE_COBBLE_SLOTS
end

pcall(C.refreshReserveSlots)
C.WATER_SLOTS = { 14, 15 }
C.SLOTS = {
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
  cactus         = 19,
  sugarcane      = 20,
  spruce_sapling = 21,
}
C.SLOTS.leadstone_duct = C.SLOTS.flux_duct

-- Components dropped into the computer case during the build sequence, in the
-- order they are added. These live in fixed inventory slots.
C.COMPUTER_PARTS = {
  -- Crafted as a plain EEPROM; it becomes an "EEPROM (Lua BIOS)" once inserted
  -- into the case, so crafting/BOM only ever deal with the plain EEPROM.
  { slot = 33, label = "EEPROM" },
  { slot = 34, label = "Redstone Card (Tier 1)" },
  { slot = 35, label = "Hard Disk Drive (Tier 2) (2MB)" },
  { slot = 36, label = "Central Processing Unit (CPU) (Tier 2)" },
  { slot = 37, label = "Memory (Tier 2)" },
}

-- Components for the build_robot state, in the order they are dropped into the
-- assembler. The case MUST be first. Everything is matched by in-game label,
-- since these share item ids or vary by pack; fix any label that the assembler
-- rejects. `count` is how many of that item to load (default 1).
C.ROBOT_PARTS = {
  { label = "Computer Case (Tier 3)" },
  { label = "Generator Upgrade" },
  { label = "Solar Generator Upgrade" },
  { label = "Inventory Controller Upgrade" },
  { label = "Crafting Upgrade" },
  { label = "Central Processing Unit (CPU) (Tier 3)" },
  { label = "Memory (Tier 3)" },
  { label = "Hard Disk Drive (Tier 2) (2MB)" },
  { label = "EEPROM" },
  { label = "Inventory Upgrade", count = 4 },  -- 4 x 16 = 64 internal slots
  { label = "Redstone Card (Tier 1)" },
}

C.FLOOR_OVERRIDES = {
  { x = 4, z = 12, slot = C.SLOTS.dirt },
}

-- ---------------------------------------------------------------------------
-- Robot type + compass direction system.
--
-- Every robot has a TYPE, determined at initialization by the amount of
-- cobblestone in slot 44 (C.TYPE_SLOT):
--   0        -> Genesis
--   1..8     -> a compass direction, clockwise from North:
--               1 N, 2 NE, 3 E, 4 SE, 5 S, 6 SW, 7 W, 8 NW
--
-- Compass directions map to the world facing convention (0=+Z, 1=+X, 2=-Z,
-- 3=-X). We take North = -Z (facing 2) and go clockwise: N(-Z) -> E(+X) ->
-- S(+Z) -> W(-X). The four intercardinals sit between them.
--
-- Offspring rules by type:
--   Genesis            -> send robots outward to N, E, S, W.
--   Main cardinal      -> send one robot FORWARD (its own direction) and one to
--                         its RIGHT.
--   Secondary cardinal -> send one robot to its RIGHT only.
-- ---------------------------------------------------------------------------

C.TYPE_SLOT = 44

C.GENESIS = "genesis"

-- Compass index (1..8) -> name. Clockwise from North.
C.COMPASS = {
  [1] = "N", [2] = "NE", [3] = "E", [4] = "SE",
  [5] = "S", [6] = "SW", [7] = "W", [8] = "NW",
}

-- Which compass indices are main (cardinal) vs secondary (intercardinal).
C.MAIN_CARDINALS = { N = true, E = true, S = true, W = true }

-- Compass name -> world facing (0=+Z, 1=+X, 2=-Z, 3=-X). Only the four main
-- cardinals correspond to a pure facing; intercardinals face their clockwise
-- cardinal for "forward"/"right" purposes (they only ever send a right probe).
C.COMPASS_FACING = {
  N = 2,  -- -Z
  E = 1,  -- +X
  S = 0,  -- +Z
  W = 3,  -- -X
  NE = 1, -- treat as E-ish for right-hand turns
  SE = 0,
  SW = 3,
  NW = 2,
}

-- Clockwise compass order for the four cardinals: N -> E -> S -> W -> N.
-- "Right" of a cardinal is the next one clockwise.
local CARDINAL_RIGHT = { N = "E", E = "S", S = "W", W = "N" }

-- Given a robot's type (Genesis or a compass name), return the list of compass
-- directions it should send offspring toward.
function C.offspringDirections(robotType)
  if robotType == C.GENESIS then
    return { "N", "E", "S", "W" }
  end
  if C.MAIN_CARDINALS[robotType] then
    -- Forward (its own direction) and to its right (next cardinal clockwise).
    return { robotType, CARDINAL_RIGHT[robotType] }
  end
  -- Secondary cardinal (intercardinal): a right probe only. Its "right" is the
  -- next cardinal clockwise from the cardinal it leads into. Map each
  -- intercardinal to the cardinal on its right:
  --   NE -> E, SE -> S, SW -> W, NW -> N
  local INTER_RIGHT = { NE = "E", SE = "S", SW = "W", NW = "N" }
  return { INTER_RIGHT[robotType] }
end

-- Number of tracked resources this robot type manages. Main cardinals and
-- Genesis carry the full tracked set; secondary cardinals carry a reduced set
-- (probes that only scout, not full builders). Adjust to taste.
function C.trackedResourceCount(robotType)
  if robotType == C.GENESIS or C.MAIN_CARDINALS[robotType] then
    return #C.TRACKED_RESOURCES
  end
  return math.min(2, #C.TRACKED_RESOURCES)
end

-- Detect this robot's type at initialization by reading the cobblestone count in
-- the type slot (44). 0 -> Genesis; 1..8 -> compass direction. Anything else
-- defaults to Genesis. Returns the type string and the raw count.
function C.detectRobotType()
  local count = 0
  local ok, stack = pcall(inv.getStackInInternalSlot, C.TYPE_SLOT)
  if ok and stack and stack.name == "minecraft:cobblestone" and stack.size then
    count = stack.size
  end
  if count == 0 then
    return C.GENESIS, 0
  end
  local name = C.COMPASS[count]
  if name then
    return name, count
  end
  return C.GENESIS, count
end

-- Bill of materials for one build sequence plus one offspring robot. Derived
-- from the placement tables (floor + machines + farm) and the robot/computer
-- part lists. Quantities are per single build+robot.
C.BUILD_BOM = {
  blocks = {
    ["minecraft:cobblestone"]   = 151,  -- 143 floor + 8 type marker (offspring mines its own reserve)
    ["Dirt"]                    = 1,
    ["td:leadstone_fluxduct"]   = 5,
    ["aa:coal_generator"]       = 2,
    ["oc:case3"]                = 1,
    ["oc:assembler"]            = 1,
    ["minecraft:hopper"]        = 1,
    ["furnace"]                 = 1,
    ["oc:charger"]              = 1,
    ["minecraft:stone_button"]  = 1,
    ["xu2:crusher"]             = 1,
    ["minecraft:lever"]         = 1,
    ["minecraft:chest"]         = 36,  -- 6 chest stacks x 6 high (CHEST_PLACEMENTS)
    ["minecraft:sand"]          = 8,
    ["minecraft:bucket"]        = 2,
    ["Coal"]                    = 64,  -- starting generator/furnace fuel
    ["minecraft:diamond_pickaxe"] = 1,  -- the offspring's mining tool
    ["Cactus"]                  = 1,
    ["Sugar Canes"]             = 7,  -- sugarcane
    ["Spruce Sapling"]          = 6,  -- 1 planted + 5 spare (matched by label)
  },
  -- One offspring robot: the ROBOT_PARTS list (with counts) assembled in the
  -- assembler, plus the COMPUTER_PARTS dropped into the case during the build.
  robot_parts = C.ROBOT_PARTS,
  computer_parts = C.COMPUTER_PARTS,
}

-- ---------------------------------------------------------------------------
-- Recursive recipe expansion: turn a set of required items into the raw base
-- materials needed to craft them all, by walking C.RECIPES until nothing left
-- is craftable.
--
-- An item is "base" if it has no recipe in C.RECIPES. For a craftable item, one
-- craft produces `yield` of it, consuming the grid ingredients; to make N we
-- need ceil(N / yield) crafts, each consuming the per-craft ingredient counts.
-- ---------------------------------------------------------------------------

-- The lookup key for a grid entry or requested item: label if present, else the
-- item id string. Recipes are keyed by item id, so we look recipes up by name.
local function itemName(item)
  if type(item) == "table" then
    return item.name or item.label
  end
  return item
end

-- Per-craft ingredient counts for a recipe: map of ingredient-name -> count.
local function recipeIngredients(recipe)
  local needs = {}
  for i = 1, 9 do
    local g = recipe.grid and recipe.grid[i]
    if g then
      local key = itemName(g)
      if key then needs[key] = (needs[key] or 0) + 1 end
    end
  end
  return needs
end

-- Build a name/label -> recipe-key map from any recipe that declares a result.
-- This lets the expander resolve items referenced by label (as robot parts and
-- some grid entries are) OR by item id back to the recipe keyed by something
-- else. The id bridge is what makes e.g. minecraft:iron_ingot resolve to its
-- smelt recipe (keyed minecraft:iron_ingot_smelt), so ingots expand down to their
-- ores instead of being treated as raw base materials.
local function labelToRecipeKey()
  local map = {}
  for key, recipe in pairs(C.RECIPES or {}) do
    if type(recipe.result) == "table" then
      if recipe.result.label then map[recipe.result.label] = key end
      if recipe.result.name then map[recipe.result.name] = key end
    end
  end
  return map
end

-- Resolve a requirement name to the recipe key that makes it, if any: a direct
-- id key, or a label bridged through the result-label map.
local function recipeKeyFor(name, labelMap)
  if C.RECIPES and C.RECIPES[name] then return name end
  if labelMap and labelMap[name] then return labelMap[name] end
  return nil
end

-- Expand `requirements` (name -> count) into base materials (name -> count).
-- `seen` guards against recipe cycles on the current dependency path.
local function expandInto(base, requirements, seen, labelMap)
  for name, count in pairs(requirements) do
    if count > 0 then
      local key = recipeKeyFor(name, labelMap)
      local recipe = key and C.RECIPES[key] or nil
      if not recipe or (seen and seen[key]) then
        -- Base material (or a cycle we won't re-enter): accumulate as-is.
        base[name] = (base[name] or 0) + count
      else
        local yield = recipe.yield or 1
        local crafts = math.ceil(count / yield)
        local perCraft = recipeIngredients(recipe)
        local subReq = {}
        for ing, per in pairs(perCraft) do
          subReq[ing] = per * crafts
        end
        local nextSeen = { [key] = true }
        if seen then for k, v in pairs(seen) do nextSeen[k] = v end end
        expandInto(base, subReq, nextSeen, labelMap)
      end
    end
  end
  return base
end

-- Public: compute the raw base-material list for the whole build BOM (blocks +
-- one robot's parts + the computer parts). Returns name -> total count.
function C.baseMaterialsForBuild()
  local requirements = {}
  local function addReq(name, count)
    if name and count and count > 0 then
      requirements[name] = (requirements[name] or 0) + count
    end
  end

  for name, count in pairs(C.BUILD_BOM.blocks) do
    addReq(name, count)
  end
  for _, part in ipairs(C.BUILD_BOM.robot_parts or {}) do
    addReq(itemName(part.item or part.label or part.name), part.count or 1)
  end
  for _, part in ipairs(C.BUILD_BOM.computer_parts or {}) do
    addReq(itemName(part.item or part.label or part.name), part.count or 1)
  end

  return expandInto({}, requirements, nil, labelToRecipeKey())
end

-- Number of builds this robot needs to make: one per offspring it sends.
function C.buildsNeeded()
  local dirs = C.offspringDirections(C.robotType or C.GENESIS)
  return #dirs
end

-- The full ordered list of craftable items for ONE build, in the order the
-- autocrafter should prioritize them (blocks first, then computer parts, then
-- the robot parts). Each entry is { name = <recipe name/label>, count = N }.
-- Only items that actually have a recipe are included (raw materials are
-- gathered, not crafted).
function C.buildCraftList()
  local labelMap = labelToRecipeKey()
  local function recipeOf(name)
    local key = (C.RECIPES and C.RECIPES[name] and name) or (labelMap and labelMap[name])
    return key and C.RECIPES[key] or nil
  end
  -- What the FINISHED stack is actually identified by: its recipe's result label
  -- (or name), not the BOM key. Keying tracking off the raw BOM id (e.g. "furnace",
  -- "td:leadstone_fluxduct") means specFor produces a name-spec that never matches
  -- the live item, so it's never kept in the tracked chest.
  local function craftedIdentity(name)
    local recipe = recipeOf(name)
    if recipe and type(recipe.result) == "table" then
      return recipe.result.label or recipe.result.name or name
    end
    return name
  end

  local list = {}
  local function add(name, count)
    if name and count and count > 0 and recipeOf(name) then
      list[#list + 1] = { name = craftedIdentity(name), count = count }
    end
  end

  for name, count in pairs(C.BUILD_BOM.blocks) do
    add(name, count)
  end
  for _, part in ipairs(C.BUILD_BOM.computer_parts or {}) do
    add(itemName(part.item or part.label or part.name), part.count or 1)
  end
  for _, part in ipairs(C.BUILD_BOM.robot_parts or {}) do
    add(itemName(part.item or part.label or part.name), part.count or 1)
  end
  return list
end

-- Expand a single item into its base materials (name -> count).
function C.baseMaterialsOf(name, count)
  return expandInto({}, { [name] = count or 1 }, nil, labelToRecipeKey())
end

-- Set C.TRACKED_RESOURCES to the base materials needed for all builds:
-- (base materials for one build) x (number of builds). Keeps each resource's
-- min/target proportional. Overwrites the tracked list.
function C.scaleTrackedResources()
  local builds = C.buildsNeeded()
  local base = C.baseMaterialsForBuild()
  local tracked = {}
  local index = {}

  local function put(name, total)
    if not name or total <= 0 then return end
    local e = index[name]
    if e then
      e.min = e.min + total
      e.target = e.target + total
    else
      e = { name = name, min = total, target = total }
      index[name] = e
      tracked[#tracked + 1] = e
    end
  end

  -- Raw base materials the robot must gather, scaled by the number of builds.
  for name, per in pairs(base) do
    put(name, per * builds)
  end

  -- Crafted build items (furnace, chests, machines, robot parts, ...) also need
  -- to be kept in the tracked chest rather than dumped into overflow, so track
  -- them at the per-build count times the number of builds.
  for _, entry in ipairs(C.buildCraftList()) do
    put(entry.name, (entry.count or 1) * builds)
  end

  -- Smeltable inputs (ores, sand, cactus, raw circuit board, ...) mostly come out
  -- of the base-material expansion already tracked. Their 1:1 smelt OUTPUTS (ingots,
  -- PCB, glass, ...) do not, and would otherwise land in overflow where crafting
  -- can't find them -- so keep each output available at the same amount its input
  -- is tracked for (all of that input becomes the output), rather than a flat,
  -- inflated default. Cobblestone is never auto-smelted (furnaceAddStep skips it),
  -- so Stone is not reserved at all.
  local SMELT_UNTRACKED_INPUT = 64
  for _, s in ipairs(C.smeltables()) do
    if s.input == C.COBBLE_NAME then
      -- Cobblestone isn't smelted wholesale (that would flood the furnace), so its
      -- stone OUTPUT isn't reserved at the input amount. But the build does need a
      -- little stone (the stone button), so track that output at the ACTUAL build
      -- demand. Keeping it in the tracked chest makes it available to crafting and
      -- lets furnaceAddStep see how much already exists and stop smelting. The
      -- cobblestone input is already tracked in bulk for the floor.
      local need = C.smeltInputNeed(C.COBBLE_NAME) * builds
      if need > 0 and not index[s.output] then put(s.output, need) end
    else
      local inEntry = index[s.input]
      local amount = (inEntry and inEntry.target) or SMELT_UNTRACKED_INPUT
      if not index[s.input] then put(s.input, amount) end
      if not index[s.output] then put(s.output, amount) end
    end
  end

  -- Baseline floors: always keep at least a stack of spruce saplings (replanting
  -- stock the farm depends on) and coal (fuel), even when the per-build totals are
  -- lower. Never lowers a higher replication target.
  local function ensureAtLeast(name, minTarget)
    local e = index[name]
    if e then
      e.target = math.max(e.target or 0, minTarget)
      e.min = math.max(e.min or 0, minTarget)
    else
      e = { name = name, min = minTarget, target = minTarget }
      index[name] = e
      tracked[#tracked + 1] = e
    end
  end
  ensureAtLeast("Spruce Sapling", 64)
  ensureAtLeast("Coal", 64)

  C.TRACKED_RESOURCES = tracked
  return tracked
end

-- Find a tracked resource entry by name.
local function trackedEntry(name)
  for _, r in ipairs(C.TRACKED_RESOURCES) do
    if r.name == name then return r end
  end
  return nil
end

-- Adjust a tracked resource by delta (creating/removing entries as needed).
local function adjustTracked(name, delta)
  if not name or delta == 0 then return end
  local e = trackedEntry(name)
  if e then
    e.target = math.max(0, (e.target or 0) + delta)
    e.min = math.max(0, (e.min or 0) + delta)
    if e.target <= 0 and e.min <= 0 then
      for i, r in ipairs(C.TRACKED_RESOURCES) do
        if r == e then table.remove(C.TRACKED_RESOURCES, i); break end
      end
    end
  elseif delta > 0 then
    C.TRACKED_RESOURCES[#C.TRACKED_RESOURCES + 1] =
      { name = name, min = delta, target = delta }
  end
end

-- When `count` of `name` is crafted: remove the DIRECT ingredients it consumed from
-- the tracked resources and add the crafted item itself (it now needs to be kept).
-- Mutates C.TRACKED_RESOURCES.
--
-- Direct ingredients, NOT the fully-expanded base materials: each intermediate is
-- tracked in turn as it's crafted (planks added when made, then consumed when the
-- chest is made). Charging a chest all the way back to logs would double-count the
-- logs -- once for the planks, again for the chest that used them -- draining the
-- log target to zero and sending logs the robot still needs (e.g. for sticks) to
-- the overflow instead of keeping them.
function C.onItemCrafted(name, count)
  count = count or 1
  local labelMap = labelToRecipeKey()
  local key = recipeKeyFor(name, labelMap)
  local recipe = key and C.RECIPES[key] or nil
  if recipe then
    local crafts = math.ceil(count / (recipe.yield or 1))
    for ing, per in pairs(recipeIngredients(recipe)) do
      adjustTracked(ing, -per * crafts)
    end
  end
  adjustTracked(name, count)
end

-- All smelting recipes, as a list of { input, output, key }. Derived from
-- C.RECIPES (recipes flagged smelt = true), so adding a smelt recipe
-- automatically adds it to the furnace sequence and the tracked base materials.
function C.smeltables()
  local list = {}
  for key, recipe in pairs(C.RECIPES or {}) do
    if recipe.smelt then
      local input
      for i = 1, 9 do
        local g = recipe.grid and recipe.grid[i]
        if g then
          input = itemName(g)
          break
        end
      end
      local output = (type(recipe.result) == "table" and recipe.result.label) or key
      if input then
        list[#list + 1] = { input = input, output = output, key = key }
      end
    end
  end
  table.sort(list, function(a, b) return tostring(a.input) < tostring(b.input) end)
  return list
end

-- Build a dependency-ordered production plan to make `name` x `count` starting
-- from raw base materials. Returns a list of steps in the order they can be
-- executed: { action = "smelt"|"craft", name = <item>, count = <how many> }.
-- Deepest dependencies come first, so every step's inputs exist by the time it
-- runs. Raw materials (no recipe) are omitted -- they are gathered, not made.
function C.productionPlan(name, count)
  local labelMap = labelToRecipeKey()

  local function recipeFor(n)
    local key = (C.RECIPES and C.RECIPES[n] and n) or (labelMap and labelMap[n])
    return key and C.RECIPES[key] or nil
  end

  -- Topological order via post-order DFS: an item is appended AFTER all its
  -- ingredients. Accumulating needed[] in REVERSE (parents first) then guarantees an
  -- item's demand is fully summed from EVERY parent before it charges its own
  -- ingredients. So a multiply-used intermediate (the transistor, used by many chips)
  -- charges its ingredients (paper) for all of its uses, not just the first -- the old
  -- single-pass DFS recursed on an item's first visit only and under-counted paper.
  local topo = {}
  local seen = {}
  local function collect(item, stack)
    local recipe = recipeFor(item)
    if not recipe then return end          -- raw material: not a step
    if stack[item] or seen[item] then return end
    seen[item] = true
    stack[item] = true
    for i = 1, 9 do
      local g = recipe.grid and recipe.grid[i]
      if g then
        local ing = itemName(g)
        if ing then collect(ing, stack) end
      end
    end
    stack[item] = nil
    topo[#topo + 1] = item
  end
  collect(name, {})

  -- Accumulate total needed[] parents-first (reverse of the topo order).
  local needed = { [name] = count or 1 }
  for i = #topo, 1, -1 do
    local item = topo[i]
    local recipe = recipeFor(item)
    local qty = needed[item] or 0
    if recipe and qty > 0 then
      local crafts = math.ceil(qty / (recipe.yield or 1))
      for ing, per in pairs(recipeIngredients(recipe)) do
        needed[ing] = (needed[ing] or 0) + crafts * per
      end
    end
  end

  -- Emit steps deepest-first (topo order) with the final totals. For a smelt OR crush
  -- step, record the item the machine actually CONSUMES (the single grid ingredient),
  -- since callers feed the input, not the result (cobblestone, not the sand it yields).
  local steps = {}
  for _, item in ipairs(topo) do
    local recipe = recipeFor(item)
    local qty = needed[item] or 0
    if recipe and qty > 0 then
      local machineInput
      if recipe.smelt or recipe.crush then
        for i = 1, 9 do
          local g = recipe.grid and recipe.grid[i]
          if g then machineInput = itemName(g); break end
        end
      end
      steps[#steps + 1] = {
        action = recipe.smelt and "smelt" or (recipe.crush and "crush") or "craft",
        name = item,
        count = qty,
        input = machineInput,
      }
    end
  end
  return steps
end

-- The full ordered production plan for one build: every craft and smelt needed
-- to turn raw base materials into all the BOM items, deepest-first.
-- The plan is a pure function of the static BOM + recipes, but the autocrafter
-- rebuilds it every weave cycle. Compute it once and cache.
local _productionPlanCache
function C.buildProductionPlan()
  if _productionPlanCache then return _productionPlanCache end
  local merged = {}
  local order = {}
  for _, entry in ipairs(C.buildCraftList()) do
    for _, step in ipairs(C.productionPlan(entry.name, entry.count)) do
      local prev = merged[step.name]
      if prev then
        prev.count = prev.count + step.count
      else
        merged[step.name] = step
        order[#order + 1] = step
      end
    end
  end
  _productionPlanCache = order
  return order
end

-- Per-build quantity of `inputName` the BOM's smelt steps must CONSUME (0 if none).
-- The furnace uses this to smelt a flood-prone input -- cobblestone, mined by the
-- ton -- only up to the little the build actually needs (its stone, for the stone
-- button) instead of converting the whole pile and starving the ore smelts. For a
-- 1:1 smelt this equals the output demand.
function C.smeltInputNeed(inputName)
  local total = 0
  for _, step in ipairs(C.buildProductionPlan()) do
    if step.action == "smelt" and step.input == inputName then
      total = total + (step.count or 0)
    end
  end
  return total
end

-- Non-smelt/crush recipes that CONSUME the smelt output identified by `outputKey`
-- (or its display `outputLabel`) in their grid, as { key, per } -- how many of the
-- output each craft uses. Lets the furnace count stone already baked into finished
-- products (e.g. buttons) toward the build's stone demand, so it stops smelting
-- once the stone is spoken for instead of re-smelting a fresh batch.
function C.smeltOutputConsumers(outputKey, outputLabel)
  local consumers = {}
  for key, recipe in pairs(C.RECIPES or {}) do
    if not (recipe.smelt or recipe.crush) then
      local per = 0
      for i = 1, 9 do
        local g = recipe.grid and recipe.grid[i]
        if g then
          local n = itemName(g)
          if n == outputKey or (outputLabel and n == outputLabel) then
            per = per + 1
          end
        end
      end
      if per > 0 then
        consumers[#consumers + 1] = { key = key, per = per, yield = recipe.yield or 1 }
      end
    end
  end
  return consumers
end

-- Every recipe (craft, smelt, or crush) that consumes `ingredientName` in its grid,
-- as { name, per }: the consumer's crafted identity (result label/name, for counting
-- how many exist) and how many of the ingredient each craft uses. The autocrafter
-- sums the ingredient already embodied in finished consumers so it stops re-crafting
-- an intermediate once the parent that eats it has been built.
function C.itemConsumers(ingredientName)
  local consumers = {}
  for key, recipe in pairs(C.RECIPES or {}) do
    local per = 0
    for i = 1, 9 do
      local g = recipe.grid and recipe.grid[i]
      if g and itemName(g) == ingredientName then per = per + 1 end
    end
    if per > 0 then
      local ident = (type(recipe.result) == "table"
                     and (recipe.result.label or recipe.result.name)) or key
      -- yield: one craft consumes `per` of the ingredient but produces `yield`
      -- output items, so each output item embodies only per/yield of it.
      consumers[#consumers + 1] = { name = ident, per = per, yield = recipe.yield or 1 }
    end
  end
  return consumers
end

-- The yield of the recipe that makes `name` (via id key or label bridge), or 1.
function C.recipeYield(name)
  local labelMap = labelToRecipeKey()
  local key = (C.RECIPES and C.RECIPES[name] and name) or (labelMap and labelMap[name])
  local recipe = key and C.RECIPES[key] or nil
  return (recipe and recipe.yield) or 1
end

-- Check whether the given chest counts (name -> count) contain enough base
-- materials to craft `count` of `name`. Returns true/false. Only considers the
-- expanded base materials; assumes intermediate items are crafted on demand.
function C.canCraftFrom(available, name, count)
  local need = C.baseMaterialsOf(name, count)
  for baseName, baseCount in pairs(need) do
    if (available[baseName] or 0) < baseCount then
      return false
    end
  end
  return true
end

C.GENERATORS = { { x = 5, y = 1, z = 0 }, { x = 6, y = 1, z = 0 } }
C.GENERATOR_FUEL_SLOT = 1
C.GENERATOR_TARGET = 64

-- The crusher (5,2,2) grinds cobblestone dropped in from above; the sand falls into
-- the hopper directly below it (5,1,2), where the robot collects it. One batch is
-- 64 cobblestone -> 8 sand. See C.addToCrusher / C.takeFromHopper.
C.CRUSHER = { x = 5, y = 2, z = 2 }
C.HOPPER = { x = 5, y = 1, z = 2 }
C.CRUSHER_BATCH_IN = 64
C.CRUSHER_BATCH_OUT = 8

-- The furnace sits one block up (y=2) with a gap at (2,1,2) below it, so the robot
-- can insert the smeltable through the top, fuel through a side, and pull the
-- output from underneath. It is NOT in C.PLACEMENTS -- building.lua raises it with
-- a dedicated sequence (place cobble, set furnace on top, break the cobble out).
C.FURNACE = { x = 2, y = 2, z = 2 }
C.FURNACE_SLOT_INPUT = 1
C.FURNACE_SLOT_FUEL = 2
C.FURNACE_SLOT_OUTPUT = 3

C.PLACEMENTS = {
  { x = 4, z = 1, slot = C.SLOTS.flux_duct },
  { x = 5, z = 1, slot = C.SLOTS.flux_duct },
  { x = 6, z = 1, slot = C.SLOTS.flux_duct },
  { x = 7, z = 1, slot = C.SLOTS.flux_duct },
  { x = 5, z = 0, slot = C.SLOTS.coal_generator },
  { x = 6, z = 0, slot = C.SLOTS.coal_generator },
  { x = 7, z = 2, slot = C.SLOTS.case3 },
  { x = 6, z = 2, slot = C.SLOTS.assembler },
  { x = 5, z = 2, slot = C.SLOTS.hopper },
  { x = 4, z = 2, slot = C.SLOTS.charger },
}

C.SAND_PLACEMENTS = {
  { x = 4, z = 6 },
  { x = 5, z = 6 },
  { x = 6, z = 6 },
  { x = 3, z = 7 },
  { x = 7, z = 7 },
  { x = 4, z = 8 },
  { x = 5, z = 8 },
  { x = 6, z = 8 },
}

C.CACTUS_PLACEMENTS = {
  { x = 3, z = 7 },
}

C.SUGARCANE_PLACEMENTS = {
  { x = 4, z = 6 },
  { x = 5, z = 6 },
  { x = 6, z = 6 },
  { x = 7, z = 7 },
  { x = 4, z = 8 },
  { x = 5, z = 8 },
  { x = 6, z = 8 },
}

C.CACTUS_X = 3
C.CACTUS_Z = 7
C.CACTUS_TRAVEL_Y = 5

C.CACTUS_OUT_PATH = {
  { x = 3, y = 5, z = 3 },
  { x = 3, y = 5, z = 7 },
}

C.CACTUS_RETURN_PATH = {
  { x = 3, y = 5, z = 3 },
  { x = 4, y = 1, z = 3 },
}

C.SUGARCANE_HARVEST_ORDER = {
  { x = 4, z = 6 },
  { x = 5, z = 6 },
  { x = 6, z = 6 },
  { x = 7, z = 7 },
  { x = 6, z = 8 },
  { x = 5, z = 8 },
  { x = 4, z = 8 },
}

C.SUGARCANE_OUT_PATH = {
  { x = 5, y = 5, z = 3 },
  { x = 5, y = 5, z = 6 },
  { x = 4, y = 5, z = 6 },
}

C.SUGARCANE_TO_77_PATH = {
  { x = 7, y = 5, z = 6 },
  { x = 7, y = 5, z = 7 },
}

C.SUGARCANE_TO_ROW8_PATH = {
  { x = 7, y = 5, z = 8 },
}

C.SUGARCANE_RETURN_PATH = {
  { x = 5, y = 5, z = 8 },
  { x = 5, y = 5, z = 3 },
  { x = 4, y = 1, z = 3 },
}

C.SAPLING_PLACEMENTS = {
  { x = 4, z = 12 },
}

C.CHEST_STACK_HEIGHT = 6
C.CHEST_PLACEMENTS = {
  { x = 0, z = 0 },
  { x = 0, z = 1 },
  { x = 0, z = 3 },
  { x = 0, z = 4 },
  { x = 0, z = 6 },
  { x = 0, z = 7 },
}

-- The "target chest" is actually a stack of 3 chests in the z=0 column (levels
-- 1-3). They share one access cell; the robot moves up/down between levels to reach
-- each. C.TRACKED_CHEST stays the bottom/home cell (navigation anchor + back-compat).
C.TRACKED_CHESTS = {
  { x = 0, y = 1, z = 0 },
  { x = 0, y = 2, z = 0 },
  { x = 0, y = 3, z = 0 },
}
C.TRACKED_CHEST = C.TRACKED_CHESTS[1]

-- Is (z, level) one of the target chests?
function C.isTrackedChestCell(z, level)
  for _, c in ipairs(C.TRACKED_CHESTS) do
    if c.z == z and c.y == level then return true end
  end
  return false
end

-- Is column `z` the target-chest column? The overflow logic skips the WHOLE column
-- (not just the target levels), so mined junk (foreign ores, etc.) never lands in
-- the same stack as the tracked resources -- the levels above the target chests are
-- reserved, kept clear rather than used as overflow.
function C.isTrackedColumn(z)
  for _, c in ipairs(C.TRACKED_CHESTS) do
    if c.z == z then return true end
  end
  return false
end

C.STASIS_X = 4
C.STASIS_Y = 1
C.STASIS_Z = 3

-- Tracked = the items KEPT in the tracked chest (up to target); everything else
-- flows to the overflow chests. Only spruce saplings (replanting stock) and coal
-- (fuel) are kept; the build materials ride through the overflow chests.
C.TRACKED_RESOURCES = {
  { name = "Spruce Sapling",  min = 64, target = 64 },
  { name = "Coal", min = 64, target = 64 },
}

require("recipes")(C)

-- ---------------------------------------------------------------------------
-- Item matching by id OR display label.
--
-- Items in this codebase are referenced two ways: by item id ("minecraft:sand")
-- or by a { label = ... } table ("Cactus", "Raw Circuit Board"). Labels are
-- unavoidable for some items -- notably OpenComputers materials, where Raw
-- Circuit Board and Printed Circuit Board share the id "opencomputers:material"
-- and differ only by label -- so a live stack can only be recognized by its
-- label, not its name.
--
-- C.LABELS collects every label that appears in the recipes (as a result label
-- or a { label = ... } grid ingredient). C.specFor turns a tracked/smelt name
-- into a matcher: a label the recipes know about is matched against the stack's
-- label; anything else is treated as an item id and matched against the name.
-- ---------------------------------------------------------------------------

function C.buildLabelSet()
  local labels = {}
  for _, recipe in pairs(C.RECIPES or {}) do
    if type(recipe.result) == "table" and recipe.result.label then
      labels[recipe.result.label] = true
    end
    for i = 1, 9 do
      local g = recipe.grid and recipe.grid[i]
      if type(g) == "table" and g.label then
        labels[g.label] = true
      end
    end
  end
  C.LABELS = labels
  return labels
end

C.buildLabelSet()
-- Spruce Sapling has no recipe (it's farmed), so it isn't picked up from the
-- recipes, but it must be matched by display label -- its item id didn't match.
C.LABELS["Spruce Sapling"] = true
-- Dirt is a mined block used only as a dispatch-layout item (no recipe), so it
-- isn't picked up from the recipes; register its label so it matches by label too.
C.LABELS["Dirt"] = true

-- Turn a name (item id or label string) into a match spec.
function C.specFor(name)
  if C.LABELS and C.LABELS[name] then
    return { label = name }
  end
  return { name = name }
end

-- Does live stack `st` satisfy match spec `spec` (a string id or a table with
-- name/label/damage)?
function C.matchesSpec(st, spec)
  if not st then return false end
  if type(spec) == "string" then spec = { name = spec } end
  if spec.name and st.name ~= spec.name then return false end
  if spec.damage and st.damage ~= spec.damage then return false end
  if spec.label and st.label ~= spec.label then return false end
  return true
end

-- ---------------------------------------------------------------------------
-- Shared inventory helpers.
--
-- These were previously copy-pasted (with small variations) into most of the
-- state files -- furnace_add/take, build_robot, take_robot, fill_generators,
-- fill_buckets, crafting. They live here now so every state matches items and
-- scans slots the same way. Item references are an id string ("minecraft:coal")
-- or a spec table ({ name = / label = / damage = }); C.matchesSpec accepts both.
-- ---------------------------------------------------------------------------

-- Normalize an item reference to a spec table.
function C.itemSpec(item)
  if type(item) == "string" then return { name = item } end
  return item
end

-- Human-readable text for an item reference.
function C.specText(item)
  local spec = C.itemSpec(item)
  return spec.label or spec.name or "?"
end

-- Is internal slot `s` one of the reserve cobble slots (kept for pillaring)?
function C.isReserveSlot(s)
  for _, r in ipairs(C.RESERVE_COBBLE_SLOTS or {}) do
    if r == s then return true end
  end
  return false
end

-- Size of the inventory the robot is facing (front), or nil if there is none.
function C.facingFront()
  local ok, size = pcall(inv.getInventorySize, sides.front)
  if ok and size then return size end
  return nil
end

-- First empty non-reserve internal slot, or nil.
function C.freeSlot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not C.isReserveSlot(s) then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and not st then return s end
    end
  end
  return nil
end

-- Total count of `item` across non-reserve internal slots.
function C.heldCount(item)
  local total = 0
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not C.isReserveSlot(s) then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and C.matchesSpec(st, item) and st.size then
        total = total + st.size
      end
    end
  end
  return total
end

-- First non-reserve internal slot holding `item`, or nil.
function C.findHeldSlot(item)
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not C.isReserveSlot(s) then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and C.matchesSpec(st, item) and st.size and st.size > 0 then
        return s
      end
    end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- Build layout: where each carried resource lives in a freshly-set-up robot's
-- inventory. A robot dispatching an offspring first arranges its own inventory
-- to match this, then copies it slot-for-slot into the offspring, so the child
-- boots with everything exactly where its build/computer code expects it.
--
-- Each entry: { slot, name= or label=, count }. Cobblestone is split across the
-- floor slots (1-3, 143), the reserve slots (45-48, 256), and the type slot (44,
-- set separately to the compass index). The 8 spare cobble in the BOM cover the
-- type marker so it never has to steal from the floor or reserve.
-- ---------------------------------------------------------------------------

-- C.SLOTS key -> item spec + count for the machines/farm blocks.
local SLOT_ITEM = {
  dirt           = { label = "Dirt",                    count = 1 },
  coal_generator = { label = "Coal Generator",          count = 2 },
  flux_duct      = { label = "Leadstone Fluxduct",      count = 5 },
  case3          = { label = "Computer Case (Tier 3)",  count = 1 },
  assembler      = { label = "Electronics Assembler",   count = 1 },
  hopper         = { label = "Hopper",                  count = 1 },
  furnace        = { label = "Furnace",                 count = 1 },
  sand           = { label = "Sand",                    count = 8 },
  chest          = { label = "Spruce Chest",            count = 36 },  -- 6 stacks x 6 high
  stone_button   = { label = "Button",                  count = 1 },
  crusher        = { label = "Crusher",                 count = 1 },
  charger        = { label = "Charger",                 count = 1 },
  lever          = { label = "Lever",                   count = 1 },
  cactus         = { label = "Cactus",                  count = 1 },
  sugarcane      = { label = "Sugar Canes",             count = 7 },
  spruce_sapling = { label = "Spruce Sapling",          count = 6 },
}

C.BUILD_LAYOUT = {
  { slot = 1, name = "minecraft:cobblestone", count = 64 },  -- floor (143 total)
  { slot = 2, name = "minecraft:cobblestone", count = 64 },
  { slot = 3, name = "minecraft:cobblestone", count = 15 },
  { slot = 22, label = "Coal", count = 64 },        -- starting fuel
  { slot = C.TOOL_SLOT, label = "Diamond Pickaxe", count = 1 },  -- mining tool
}
for key, item in pairs(SLOT_ITEM) do
  C.BUILD_LAYOUT[#C.BUILD_LAYOUT + 1] =
    { slot = C.SLOTS[key], name = item.name, label = item.label, count = item.count }
end
-- Filled water buckets, not empty ones: the offspring places water from these
-- during its build (an empty bucket can't place water). The parent crafts empty
-- buckets (BOM) and fills them before dispatch.
for _, s in ipairs(C.WATER_SLOTS) do
  C.BUILD_LAYOUT[#C.BUILD_LAYOUT + 1] = { slot = s, label = "Water Bucket", count = 1 }
end
for _, p in ipairs(C.COMPUTER_PARTS) do
  -- The EEPROM the robot carries for the offspring is the Lua BIOS it pulled out of
  -- the computer during the copy sequence (before dropping the fresh blank in), so
  -- sorting/deposit must match its post-insertion label, not the blank "EEPROM".
  local label = (p.label == "EEPROM") and "EEPROM (Lua BIOS)" or p.label
  C.BUILD_LAYOUT[#C.BUILD_LAYOUT + 1] = { slot = p.slot, label = label, count = 1 }
end
-- No reserve cobble in the layout: the offspring mines its own pillaring reserve
-- once it starts quarrying. The parent's reserve slots (45-48) stay its own.

-- Every slot the layout owns (targets + type marker), plus each slot's target
-- spec so we can tell whether a slot is already correctly filled.
local LAYOUT_SLOTS = { [C.TYPE_SLOT] = true }
local SLOT_SPEC = {}
for _, e in ipairs(C.BUILD_LAYOUT) do
  if e.slot then LAYOUT_SLOTS[e.slot] = true; SLOT_SPEC[e.slot] = e end
end

-- Slots the type marker must never pull cobblestone out of (floor + reserve).
local COBBLE_PROTECTED = {}
for _, s in ipairs(C.COBBLE_SLOTS) do COBBLE_PROTECTED[s] = true end
for _, s in ipairs(C.RESERVE_COBBLE_SLOTS) do COBBLE_PROTECTED[s] = true end
COBBLE_PROTECTED[C.TYPE_SLOT] = true

-- Somewhere to park a displaced item. Prefer a scratch (non-layout) slot, but fall
-- back to ANY empty non-reserve slot so parking never fails while free space
-- exists. Correctness must not depend on how many scratch slots the incoming
-- placement happened to leave open -- that was the bug that left slots empty.
local function parkSlot()
  local fallback = nil
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not C.isReserveSlot(s) then
      local ok, st = pcall(inv.getStackInInternalSlot, s)
      if ok and (not st or not st.size or st.size == 0) then
        if not LAYOUT_SLOTS[s] then return s end   -- scratch: ideal
        fallback = fallback or s                    -- empty layout slot: last resort
      end
    end
  end
  return fallback
end

-- Move whatever is in `slot` (up to `n`, or all of it) out to a park slot.
local function evictFrom(slot, n)
  local dest = parkSlot()
  if not dest then return false end
  robot.select(slot)
  if n then return robot.transferTo(dest, n) end
  return robot.transferTo(dest)
end

-- Fill `target` with `count` items matching `spec`: clear a wrong occupant / shed
-- excess to a park slot, then pull matches in from every slot EXCEPT ones that are
-- a correctly-filled layout target. Skipping only correctly-filled targets means a
-- displaced item is still found wherever it landed (even in another slot's target,
-- e.g. after a fallback park), while a same-item target that's already right (floor
-- vs reserve cobble) is never drained. robot.transferTo moves selected -> target.
function C.gatherInto(target, spec, count)
  local cur = 0
  local ok, st = pcall(inv.getStackInInternalSlot, target)
  if ok and st and st.size and st.size > 0 then
    if C.matchesSpec(st, spec) then
      cur = st.size
      if cur > count then evictFrom(target, cur - count); cur = count end
    else
      evictFrom(target)                          -- wrong item: clear the slot
      cur = 0
    end
  end
  if cur >= count then return end
  for s = 1, (C.INVENTORY_SIZE or 32) do
    -- Never source from the target itself or the reserve slots (the robot's own
    -- pillaring cobble, which is not part of any offspring's payload).
    if s ~= target and not C.isReserveSlot(s) then
      local ok2, st2 = pcall(inv.getStackInInternalSlot, s)
      if ok2 and st2 and st2.size and st2.size > 0 and C.matchesSpec(st2, spec) then
        -- Don't raid a layout slot that already holds its own correct item.
        local own = SLOT_SPEC[s]
        if not (own and C.matchesSpec(st2, own)) then
          robot.select(s)
          robot.transferTo(target, count - cur)
          local ok3, st3 = pcall(inv.getStackInInternalSlot, target)
          cur = (ok3 and st3 and st3.size) or cur
          if cur >= count then break end
        end
      end
    end
  end
end

-- Set the type slot (44) to exactly `index` cobblestone (the offspring's compass
-- index, 1..8). Pulls only from non-floor/non-reserve cobble (the BOM's spare 8),
-- so the floor and pillaring reserve stay full.
function C.setTypeSlot(index)
  if not index or index <= 0 then return end
  local ok, st = pcall(inv.getStackInInternalSlot, C.TYPE_SLOT)
  local cur = 0
  if ok and st and st.size and st.size > 0 then
    if st.name == "minecraft:cobblestone" then
      cur = st.size
      if cur > index then evictFrom(C.TYPE_SLOT, cur - index); return end
    else
      evictFrom(C.TYPE_SLOT)
      cur = 0
    end
  end
  for s = 1, (C.INVENTORY_SIZE or 32) do
    if not COBBLE_PROTECTED[s] and cur < index then
      local ok2, st2 = pcall(inv.getStackInInternalSlot, s)
      if ok2 and st2 and st2.name == "minecraft:cobblestone" and st2.size and st2.size > 0 then
        robot.select(s)
        robot.transferTo(C.TYPE_SLOT, index - cur)
        local ok3, st3 = pcall(inv.getStackInInternalSlot, C.TYPE_SLOT)
        cur = (ok3 and st3 and st3.size) or cur
      end
    end
  end
end

-- Arrange this robot's own inventory into the build layout for an offspring whose
-- compass index is `typeIndex` (1..8).
--   Pass 1 (normalize): push every layout slot down to AT MOST its target of the
--     right item -- evict wrong items and shed any excess to a park slot -- so no
--     target is overfull before filling begins.
--   Pass 2 (fill): top each slot up to its target, pulling matches from anywhere
--     except a correctly-filled layout target.
--   Pass 3: stamp the type marker from spare cobble.
-- Shedding excess up front matters: without it, a slot filled early (e.g. floor 2)
-- can't borrow from a later slot's overflow (e.g. floor 3's excess), which is how
-- the floor ended up 0/49/15.
function C.arrangeBuildLayout(typeIndex)
  for _, e in ipairs(C.BUILD_LAYOUT) do
    if e.slot then
      local ok, st = pcall(inv.getStackInInternalSlot, e.slot)
      if ok and st and st.size and st.size > 0 then
        if not C.matchesSpec(st, e) then
          evictFrom(e.slot)                       -- wrong item
        elseif st.size > e.count then
          evictFrom(e.slot, st.size - e.count)    -- shed excess
        end
      end
    end
  end
  for _, e in ipairs(C.BUILD_LAYOUT) do
    if e.slot then C.gatherInto(e.slot, e, e.count) end
  end
  C.setTypeSlot(typeIndex)
end

C.WATER_PLACEMENTS = {  { x = 4, z = 7 },
  { x = 6, z = 7 },
}

C.Y2_PLACEMENTS = {
  { x = 7, z = 2, slot = C.SLOTS.stone_button },
  { x = 5, z = 2, slot = C.SLOTS.crusher },
  { x = 5, z = 1, slot = C.SLOTS.leadstone_duct },
  { x = 4, z = 2, slot = C.SLOTS.lever },
}

C.MINE_START_X = 4
C.MINE_START_Y = 0
C.MINE_START_Z = 4

C.PILLAR_X = 4
C.PILLAR_Z = 5

C.QUARRY_MIN_X = 0
C.QUARRY_MAX_X = 31
C.QUARRY_MIN_Z = 0
C.QUARRY_MAX_Z = 31
C.QUARRY_BAND = 8

C.TRAVEL_Y = C.CHEST_STACK_HEIGHT + 1

C.FLOOR_HOLE_X = 4
C.FLOOR_HOLE_Z = 4

C.pos = { x = 0, y = 0, z = 0, facing = 0 }
C.shaftDepth = 0

local pos = C.pos

function C.moveForward()
  if robot.forward() then
    if pos.facing == 0 then pos.z = pos.z + 1
    elseif pos.facing == 1 then pos.x = pos.x + 1
    elseif pos.facing == 2 then pos.z = pos.z - 1
    elseif pos.facing == 3 then pos.x = pos.x - 1 end
    return true
  end
  return false
end

function C.moveBack()
  if robot.back() then
    if pos.facing == 0 then pos.z = pos.z - 1
    elseif pos.facing == 1 then pos.x = pos.x - 1
    elseif pos.facing == 2 then pos.z = pos.z + 1
    elseif pos.facing == 3 then pos.x = pos.x + 1 end
    return true
  end
  return false
end

function C.moveUp()
  if robot.up() then
    pos.y = pos.y + 1
    return true
  end
  return false
end

function C.moveDown()
  if robot.down() then
    pos.y = pos.y - 1
    return true
  end
  return false
end

function C.turnLeft()
  robot.turnLeft()
  pos.facing = (pos.facing - 1) % 4
end

function C.turnRight()
  robot.turnRight()
  pos.facing = (pos.facing + 1) % 4
end

function C.turnAround()
  robot.turnAround()
  pos.facing = (pos.facing + 2) % 4
end

function C.face(dir)
  local diff = (dir - pos.facing) % 4
  if diff == 1 then C.turnRight()
  elseif diff == 2 then C.turnAround()
  elseif diff == 3 then C.turnLeft() end
end

function C.stepDir(dir)
  C.face(dir)
  while robot.detect() do
    robot.swing()
  end
  while not C.moveForward() do
    robot.swing()
  end
end

function C.stepDirNoDig(dir)
  C.face(dir)
  return C.moveForward()
end

function C.batteryLevel()
  return computer.energy() / computer.maxEnergy()
end

function C.gotoBuildCorner()
  while pos.x > 0 do C.stepDir(3) end
  while pos.x < 0 do C.stepDir(1) end
  while pos.z > 0 do C.stepDir(2) end
  while pos.z < 0 do C.stepDir(0) end
  C.face(0)
end

C.allowHole = false
C.protectPillar = false

function C.isPillarCell(nx, nz)
  return C.protectPillar and nx == C.PILLAR_X and nz == C.PILLAR_Z
end

local function doStep(dir, dig)
  if dig then C.stepDir(dir); return true else return C.stepDirNoDig(dir) end
end

local function blockedCell(nx, nz)
  if C.isPillarCell(nx, nz) then return true end
  if C.allowHole then return false end
  return C.wouldEnterHole(nx, nz)
end

local function stepAvoidingHole(dir, dig)
  local nx, nz = C.nextCell(dir)
  if not blockedCell(nx, nz) then
    return doStep(dir, dig)
  end

  local perp, back
  if dir == 1 or dir == 3 then
    perp, back = 0, 2
    local sx, sz = C.nextCell(perp)
    if blockedCell(sx, sz) then perp, back = 2, 0 end
  else
    perp, back = 1, 3
    local sx, sz = C.nextCell(perp)
    if blockedCell(sx, sz) then perp, back = 3, 1 end
  end

  if not doStep(perp, dig) then return false end

  repeat
    if not doStep(dir, dig) then return false end
    local bx, bz = C.nextCell(back)
  until not blockedCell(bx, bz)

  return doStep(back, dig)
end

function C.gotoXZ(tx, tz)
  while pos.x < tx do stepAvoidingHole(1, true) end
  while pos.x > tx do stepAvoidingHole(3, true) end
  while pos.z < tz do stepAvoidingHole(0, true) end
  while pos.z > tz do stepAvoidingHole(2, true) end
end

function C.gotoXZNoDig(tx, tz)
  while pos.x < tx do if not stepAvoidingHole(1, false) then break end end
  while pos.x > tx do if not stepAvoidingHole(3, false) then break end end
  while pos.z < tz do if not stepAvoidingHole(0, false) then break end end
  while pos.z > tz do if not stepAvoidingHole(2, false) then break end end
end

function C.followPath(path)
  for _, wp in ipairs(path) do
    while pos.y > wp.y do if not C.moveDown() then break end end
    while pos.y < wp.y do if not C.moveUp() then break end end
    while pos.x < wp.x do if not C.stepDirNoDig(1) then break end end
    while pos.x > wp.x do if not C.stepDirNoDig(3) then break end end
    while pos.z < wp.z do if not C.stepDirNoDig(0) then break end end
    while pos.z > wp.z do if not C.stepDirNoDig(2) then break end end
  end
end

function C.wouldEnterHole(nx, nz)
  return nx == C.FLOOR_HOLE_X and nz == C.FLOOR_HOLE_Z
end

function C.nextCell(dir)
  if dir == 1 then return pos.x + 1, pos.z
  elseif dir == 3 then return pos.x - 1, pos.z
  elseif dir == 0 then return pos.x, pos.z + 1
  elseif dir == 2 then return pos.x, pos.z - 1 end
  return pos.x, pos.z
end

function C.walkAxisNoDig(getCur, dirPos, dirNeg, target)
  while getCur() < target do
    local nx, nz = C.nextCell(dirPos)
    if C.wouldEnterHole(nx, nz) then return false end
    if not C.stepDirNoDig(dirPos) then return false end
  end
  while getCur() > target do
    local nx, nz = C.nextCell(dirNeg)
    if C.wouldEnterHole(nx, nz) then return false end
    if not C.stepDirNoDig(dirNeg) then return false end
  end
  return true
end

function C.gotoOverTop(tx, tz, workY)
  while pos.y < C.TRAVEL_Y do
    if not C.moveUp() then break end
  end
  C.gotoXZNoDig(tx, tz)
  while pos.y > workY do
    if not C.moveDown() then break end
  end
  while pos.y < workY do
    if not C.moveUp() then break end
  end
end

function C.gotoNoBreak(tx, tz, workY)
  if pos.y > workY then
    return C.gotoOverTop(tx, tz, workY)
  end
  while pos.y < workY do
    if not C.moveUp() then break end
  end
  if not C.walkAxisNoDig(function() return pos.x end, 1, 3, tx) then
    return C.gotoOverTop(tx, tz, workY)
  end
  if not C.walkAxisNoDig(function() return pos.z end, 0, 2, tz) then
    return C.gotoOverTop(tx, tz, workY)
  end
end

function C.floorOverride(x, z)
  for _, o in ipairs(C.FLOOR_OVERRIDES) do
    if o.x == x and o.z == z then
      return o.slot
    end
  end
  return nil
end

function C.placeSlotDown(slot)
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

function C.placeCobbleDown()
  for _, slot in ipairs(C.COBBLE_SLOTS) do
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

function C.slotLabel(slot)
  local stack = inv.getStackInInternalSlot(slot)
  if stack then
    return stack.label or stack.name
  end
  return nil
end

function C.emptyBucketFromSlot(slot)
  robot.select(slot)
  local before = C.slotLabel(slot)
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
  local after = C.slotLabel(slot)
  return before ~= after
end

function C.placeWaterDown()
  for _, slot in ipairs(C.WATER_SLOTS) do
    if C.slotLabel(slot) then
      if C.emptyBucketFromSlot(slot) then
        return true
      end
    end
  end
  return false
end

function C.selectReserveCobble()
  for _, slot in ipairs(C.RESERVE_COBBLE_SLOTS) do
    local stack = inv.getStackInInternalSlot(slot)
    if stack and stack.size and stack.size > 0 then
      robot.select(slot)
      return true
    end
  end
  return false
end

function C.placeReserveCobbleDown()
  if robot.detectDown() then
    return true
  end
  if C.selectReserveCobble() then
    return robot.placeDown()
  end
  return false
end

C.COBBLE_NAME = "minecraft:cobblestone"
C.RESERVE_STACK = 64   -- a full cobblestone stack per reserve slot
-- Below this many cobble in reserve the quarry bails out (enough left to pillar
-- back to the surface rather than getting stranded at the bottom).
C.RESERVE_BAILOUT = 32

-- Total cobblestone currently sitting in the reserve slots.
function C.reserveCobbleCount()
  local total = 0
  for _, s in ipairs(C.RESERVE_COBBLE_SLOTS or {}) do
    local st = inv.getStackInInternalSlot(s)
    if st and st.name == C.COBBLE_NAME and st.size then total = total + st.size end
  end
  return total
end

-- How many cobble the reserve is short of completely full.
function C.reserveCobbleDeficit()
  return (C.RESERVE_COBBLE_COUNT * C.RESERVE_STACK) - C.reserveCobbleCount()
end

-- Move cobblestone from the robot's own non-reserve slots into the reserve slots
-- until they are full (64 each) or no loose cobble remains. Returns the reserve
-- count afterward. Used to keep the pillaring reserve topped up from freshly mined
-- cobble without visiting a chest.
function C.topUpReserveFromInventory()
  for _, rs in ipairs(C.RESERVE_COBBLE_SLOTS or {}) do
    local st = inv.getStackInInternalSlot(rs)
    local have = (st and st.name == C.COBBLE_NAME and st.size) or 0
    if have < C.RESERVE_STACK then
      for s = 1, (C.INVENTORY_SIZE or 32) do
        if s ~= rs and not C.isReserveSlot(s) then
          local cs = inv.getStackInInternalSlot(s)
          if cs and cs.name == C.COBBLE_NAME and cs.size and cs.size > 0 then
            robot.select(s)
            robot.transferTo(rs, C.RESERVE_STACK - have)
            local st2 = inv.getStackInInternalSlot(rs)
            have = (st2 and st2.size) or have
            if have >= C.RESERVE_STACK then break end
          end
        end
      end
    end
  end
  return C.reserveCobbleCount()
end

-- The build layout collapsed to per-item totals (cobblestone spans several slots),
-- as a list of { spec, count }.
function C.buildMaterialTotals()
  local totals, index = {}, {}
  local function bump(spec, count, key)
    if not key or count <= 0 then return end
    if index[key] then
      totals[index[key]].count = totals[index[key]].count + count
    else
      totals[#totals + 1] = { spec = spec, count = count }
      index[key] = #totals
    end
  end
  for _, e in ipairs(C.BUILD_LAYOUT or {}) do
    bump({ name = e.name, label = e.label }, e.count, e.label or e.name)
  end
  -- The type marker is up to 8 cobblestone stamped into slot 44 (set separately by
  -- setTypeSlot, not a layout entry), so gather that spare on top of the floor.
  bump({ name = C.COBBLE_NAME }, 8, C.COBBLE_NAME)
  return totals
end

-- Before dispatching an offspring, pull the materials it needs (one build's worth,
-- per the layout) out of the tracked chest and into the robot's inventory, up to
-- each item's target. Items the robot already carries count toward the target, so
-- a retried dispatch doesn't over-draw. Starts and ends at stasis.
--
-- All-or-nothing: a first pass verifies the chest (plus whatever the robot already
-- carries from an interrupted, retried dispatch) covers the WHOLE payload before a
-- second pass commits any pull. Pulling a partial payload would strand cobble/coal
-- in the low inventory slots -- which overlap the crafting grid (slots 1,2,3,...) --
-- and send an under-supplied offspring, so if any material is short we take nothing,
-- record what's missing in C.lastMaterialsMissing, and return false. Returns true
-- only when the full payload is now carried.
function C.takeBuildMaterialsFromChest()
  C.gotoChestFromStasis()
  local totals = C.buildMaterialTotals()
  local ready = true
  local missing = {}

  -- Pass 1: count-only, across all 3 target chests plus what the robot already
  -- carries. Is the WHOLE payload available?
  local avail = {}
  for ti = 1, #totals do avail[ti] = C.heldCount(totals[ti].spec) end
  C.forEachTrackedChest(function()
    local size = inv.getInventorySize(sides.front)
    if size then
      for cs = 1, size do
        local st = inv.getStackInSlot(sides.front, cs)
        if st and st.size and st.size > 0 then
          for ti, t in ipairs(totals) do
            if avail[ti] < t.count and C.matchesSpec(st, t.spec) then
              avail[ti] = avail[ti] + st.size
            end
          end
        end
      end
    end
  end)
  for ti, t in ipairs(totals) do
    if avail[ti] < t.count then
      ready = false
      missing[#missing + 1] =
        { item = t.spec.label or t.spec.name, need = t.count, have = avail[ti] }
    end
  end

  -- Pass 2: commit the pull only when the whole payload is available.
  if ready then
    C.forEachTrackedChest(function()
      local size = inv.getInventorySize(sides.front)
      if size then
        for _, t in ipairs(totals) do
          for cs = 1, size do
            local held = C.heldCount(t.spec)
            if held >= t.count then break end
            local st = inv.getStackInSlot(sides.front, cs)
            if st and C.matchesSpec(st, t.spec) and st.size and st.size > 0 then
              local dest = C.freeSlot()
              if dest then
                robot.select(dest)
                inv.suckFromSlot(sides.front, cs, math.min(t.count - held, st.size))
              end
            end
          end
        end
      end
    end)
  end

  C.gotoStasisFromChest()
  C.lastMaterialsMissing = missing
  return ready
end

-- First internal slot holding a collected offspring robot (an "opencomputers:robot"
-- item, or any stack whose label contains "Robot"), or nil. Same detection
-- placeOffspringRobot uses, so a "there's a robot to place" check here agrees with
-- what dispatch can actually place.
function C.offspringRobotSlot()
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(inv.getStackInInternalSlot, s)
    if ok and st and st.size and st.size > 0 then
      if st.name == "opencomputers:robot"
          or (st.label and string.find(st.label, "Robot", 1, true)) then
        return s
      end
    end
  end
  return nil
end

-- Scripted furnace-area movement. These are literal step sequences (not
-- coordinate navigation) so they match the real base layout exactly.
local function fwd(n)
  for _ = 1, n do C.moveForward() end
end

-- Stasis (4,1,3 facing charger) -> in front of the tracked chest.
function C.gotoChestFromStasis()
  C.turnRight()
  fwd(3)
  C.turnLeft()
  fwd(3)
  C.turnRight()
end

-- In front of the chest -> in front of the furnace.
function C.gotoFurnaceFromChest()
  C.turnRight()
  fwd(3)
  C.turnRight()
  fwd(1)
  C.turnRight()
end

-- In front of the furnace -> stasis (facing the charger).
function C.gotoStasisFromFurnace()
  C.turnLeft()
  fwd(2)
  C.turnRight()
end

-- Stasis (4,1,3 facing charger) -> in front of the furnace.
function C.gotoFurnaceFromStasis()
  C.turnRight()
  fwd(2)
  C.turnLeft()
end

-- In front of the furnace -> in front of the tracked chest.
function C.gotoChestFromFurnace()
  C.turnRight()
  fwd(1)
  C.turnLeft()
  fwd(3)
  C.turnRight()
end

-- In front of the chest -> stasis (facing the charger).
function C.gotoStasisFromChest()
  C.turnRight()
  fwd(3)
  C.turnRight()
  fwd(3)
  C.turnRight()
end

-- The target chest is a stack of C.TRACKED_CHESTS (z=0 column, levels 1-3). With the
-- robot already at the tracked-chest access cell (facing the chest), run fn() with it
-- facing each one in turn -- moving up/down between levels -- then return to the
-- bottom (home) level so the scripted return-to-stasis lines up. fn works on the
-- chest in front.
function C.forEachTrackedChest(fn)
  for _, cell in ipairs(C.TRACKED_CHESTS) do
    while pos.y < cell.y do if not C.moveUp() then break end end
    while pos.y > cell.y do if not C.moveDown() then break end end
    fn(cell)
  end
  while pos.y > C.TRACKED_CHEST.y do if not C.moveDown() then break end end
end

-- Go to the tracked chest, count each requested item across all 3 target chests, and
-- return to stasis. `items` is a list of item name strings. Returns name -> count.
function C.readChestCounts(items)
  local counts = {}
  local specs = {}
  for _, name in ipairs(items) do
    counts[name] = 0
    specs[name] = C.specFor(name)
  end

  C.gotoChestFromStasis()
  C.forEachTrackedChest(function()
    local ok, size = pcall(inv.getInventorySize, sides.front)
    if ok and size then
      for s = 1, size do
        local okS, st = pcall(inv.getStackInSlot, sides.front, s)
        if okS and st and st.size then
          -- Match each requested item by id or label, so smelt inputs given only
          -- by label (Cactus, Raw Circuit Board, Lead Ore) are counted too.
          for name, spec in pairs(specs) do
            if C.matchesSpec(st, spec) then
              counts[name] = counts[name] + st.size
            end
          end
        end
      end
    end
  end)
  C.gotoStasisFromChest()
  return counts
end

-- Read EVERY item count from the target chests (name -> count). Navigates and back.
function C.readAllChestCounts()
  local counts = {}
  C.gotoChestFromStasis()
  C.forEachTrackedChest(function()
    local ok, size = pcall(inv.getInventorySize, sides.front)
    if ok and size then
      for s = 1, size do
        local okS, st = pcall(inv.getStackInSlot, sides.front, s)
        if okS and st and st.name and st.size then
          counts[st.name] = (counts[st.name] or 0) + st.size
        end
      end
    end
  end)
  C.gotoStasisFromChest()
  return counts
end

-- In front of the tracked chest -> in front of the assembler (6,1,2).
-- right, forward 3, right, forward 5, right  => (6,1,3) facing -Z.
function C.gotoAssemblerFromChest()
  C.turnRight()
  for _ = 1, 3 do C.moveForward() end
  C.turnRight()
  for _ = 1, 5 do C.moveForward() end
  C.turnRight()
end

-- Stasis (4,1,3 facing charger) -> in front of the assembler (6,1,2).
-- left, forward 2, right  => (6,1,3) facing -Z, assembler in front.
function C.gotoAssemblerFromStasis()
  C.turnLeft()
  for _ = 1, 2 do C.moveForward() end
  C.turnRight()
end

-- In front of the assembler -> stasis.
-- right, forward 2, left  => back to (4,1,3) facing -Z.
function C.gotoStasisFromAssembler()
  C.turnRight()
  for _ = 1, 2 do C.moveForward() end
  C.turnLeft()
end

function C.returnToStasis()
  -- Stasis (4,3) sits right next to the mine-shaft hole (4,4). Allow the hole
  -- during this navigation so the hole-avoidance logic doesn't send the robot
  -- into a detour dance when it passes near the shaft on the way to stasis.
  local prevAllowHole = C.allowHole
  C.allowHole = true
  while pos.y > C.STASIS_Y do
    if not C.moveDown() then break end
  end
  while pos.y < C.STASIS_Y do
    if not C.moveUp() then break end
  end
  C.gotoXZNoDig(C.STASIS_X, C.STASIS_Z)
  C.face(2)
  C.allowHole = prevAllowHole
end

function C.climbToSurface()
  C.gotoXZ(C.MINE_START_X, C.MINE_START_Z)
  while pos.y < C.MINE_START_Y do
    if robot.detectUp() then robot.swingUp() end
    if not C.moveUp() then break end
  end
  C.gotoXZ(C.MINE_START_X, C.MINE_START_Z)
end

C.SPRUCE_X = 4
C.SPRUCE_Y = 1
C.SPRUCE_Z = 12

C.SPRUCE_RETURN_PATH = {
  { x = 1, y = 1, z = 15 },
  { x = 1, y = 1, z = 3 },
  { x = 4, y = 1, z = 3 },
}

function C.suckMatchFromFront(match)
  local size = inv.getInventorySize(sides.front)
  if not size then
    return false
  end
  for slot = 1, size do
    local stack = inv.getStackInSlot(sides.front, slot)
    if stack and stack.name and string.find(stack.name, match, 1, true) then
      -- Suck into a real empty slot; suckFromSlot targets the SELECTED slot, and if
      -- that happened to hold something else the transfer would silently fail.
      local dest = C.freeSlot()
      if dest then robot.select(dest) end
      if inv.suckFromSlot(sides.front, slot, 1) then
        return true
      end
    end
  end
  return false
end

function C.takeFromTrackedChest(match)
  C.gotoNoBreak(C.TRACKED_CHEST.x + 1, C.TRACKED_CHEST.z, C.TRACKED_CHEST.y + 1)
  while pos.y > C.TRACKED_CHEST.y do
    if not C.moveDown() then break end
  end
  while pos.y < C.TRACKED_CHEST.y do
    if not C.moveUp() then break end
  end
  C.face(3)
  local got = false
  C.forEachTrackedChest(function()
    if not got and C.suckMatchFromFront(match) then got = true end
  end)
  return got
end

function C.takeFromTrackedChestLow(match)
  while pos.y > C.TRACKED_CHEST.y do
    if not C.moveDown() then break end
  end
  while pos.y < C.TRACKED_CHEST.y do
    if not C.moveUp() then break end
  end
  C.gotoXZNoDig(C.TRACKED_CHEST.x + 1, C.TRACKED_CHEST.z)
  C.face(3)
  local got = false
  C.forEachTrackedChest(function()
    if not got and C.suckMatchFromFront(match) then got = true end
  end)
  return got
end

function C.selectMatching(match)
  -- Scan the WHOLE inventory (not just the first 16 slots) but skip the reserve
  -- cobble -- a sucked sapling can land anywhere in a 64-slot robot, and the old
  -- 1..16 limit is why replanting sometimes found nothing to place.
  for i = 1, (C.INVENTORY_SIZE or 32) do
    if not C.isReserveSlot(i) then
      local stack = inv.getStackInInternalSlot(i)
      if stack and stack.name and stack.size and stack.size > 0
          and string.find(stack.name, match, 1, true) then
        robot.select(i)
        return true
      end
    end
  end
  return false
end

C.SWEEP_RADIUS = 3

function C.spiralOffsets(radius)
  local out = {}
  local seen = {}
  local function add(dx, dz)
    local key = dx .. ":" .. dz
    if seen[key] then return end
    seen[key] = true
    out[#out + 1] = { dx = dx, dz = dz }
  end
  for r = 1, radius do
    local dx, dz = 0, r
    add(dx, dz)
    while dx < r do
      dx = dx + 1
      add(dx, dz)
    end
    while dz > -r do
      dz = dz - 1
      add(dx, dz)
    end
    while dx > -r do
      dx = dx - 1
      add(dx, dz)
    end
    while dz < r do
      dz = dz + 1
      add(dx, dz)
    end
    while dx < 0 do
      dx = dx + 1
      add(dx, dz)
    end
  end
  return out
end

function C.sweepAround(cx, cz, workY)
  for _, o in ipairs(C.spiralOffsets(C.SWEEP_RADIUS)) do
    C.gotoNoBreak(cx + o.dx, cz + o.dz, workY)
    robot.suckDown()
    robot.suck()
  end
end

-- ---------------------------------------------------------------------------
-- Crusher: grind cobblestone into sand.
-- ---------------------------------------------------------------------------

-- Pull up to `amount` cobblestone from the tracked chest and drop it straight down
-- into the crusher (5,2,2) from above; the sand it grinds falls into the hopper
-- below. Defaults to one full batch (64 cobblestone -> 8 sand). Starts and ends at
-- stasis. Returns how many cobblestone it actually loaded.
function C.addToCrusher(amount)
  amount = math.min(amount or C.CRUSHER_BATCH_IN, C.CRUSHER_BATCH_IN)
  local COBBLE = "minecraft:cobblestone"

  -- Stasis -> chest: pull the cobblestone into one free slot.
  C.gotoChestFromStasis()
  local dest = C.freeSlot()
  local pulled = 0
  local size = C.facingFront()
  if dest and size then
    robot.select(dest)
    for s = 1, size do
      if pulled >= amount then break end
      local ok, st = pcall(inv.getStackInSlot, sides.front, s)
      if ok and st and st.name == COBBLE and st.size and st.size > 0 then
        local take = math.min(amount - pulled, st.size)
        if inv.suckFromSlot(sides.front, s, take) then
          pulled = pulled + take
        end
      end
    end
  end

  -- Chest -> directly above the crusher (5,3,2), drop the cobblestone down into it.
  C.gotoNoBreak(C.CRUSHER.x, C.CRUSHER.z, C.CRUSHER.y + 1)
  if dest and pulled > 0 then
    robot.select(dest)
    pcall(robot.dropDown, pulled)
  end

  -- Step off the crusher column (it would block a straight descent), then go home.
  C.face(0)
  C.moveForward()
  C.returnToStasis()
  return pulled
end

-- Collect the sand the crusher ground into the hopper below it (5,1,2): stand
-- beside the hopper and suck all the sand out. Starts and ends at stasis. Returns
-- how many sand it took.
function C.takeFromHopper()
  C.gotoNoBreak(C.HOPPER.x, C.HOPPER.z + 1, C.HOPPER.y)  -- (5,1,3)
  C.face(2)                                              -- hopper (5,1,2) in front
  local took = 0
  local size = C.facingFront()
  if size then
    for slot = 1, size do
      local ok, st = pcall(inv.getStackInSlot, sides.front, slot)
      if ok and st and st.label == "Sand" and st.size and st.size > 0 then
        local dest = C.freeSlot()
        if not dest then break end
        robot.select(dest)
        if inv.suckFromSlot(sides.front, slot, st.size) then
          took = took + st.size
        end
      end
    end
  end
  C.returnToStasis()
  return took
end

return C
