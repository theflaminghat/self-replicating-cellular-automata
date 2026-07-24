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
C.RESERVE_COBBLE_SLOTS = { 45, 46, 47, 48 }

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
  C.INVENTORY_SIZE = size
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
  { slot = 33, label = "EEPROM (Lua BIOS)" },
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
  { label = "EEPROM (Lua BIOS)" },
  { label = "Inventory Upgrade", count = 3 },
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
    ["minecraft:cobblestone"]   = 143,  -- floor (BUILD_X*BUILD_Z minus overrides)
    ["minecraft:dirt"]          = 1,
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
    ["minecraft:chest"]         = 6,
    ["minecraft:sand"]          = 8,
    ["minecraft:bucket"]        = 2,
    ["Cactus"]                  = 1,
    ["minecraft:reeds"]         = 7,  -- sugarcane
    ["minecraft:sapling_spruce"] = 1,
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
  local function craftable(name)
    return (C.RECIPES and C.RECIPES[name]) or (labelMap and labelMap[name]) or nil
  end

  local list = {}
  local function add(name, count)
    if name and count and count > 0 and craftable(name) then
      list[#list + 1] = { name = name, count = count }
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

  -- Smeltable inputs (ores, sand, cactus, raw circuit boards, ...) and their
  -- outputs must also land in the tracked chest: the furnace sequence pulls the
  -- inputs from there, and the outputs feed later crafting. Some of these are
  -- intermediates the base-material expansion passes straight through, so they
  -- would otherwise be untracked and get dumped into the overflow chests.
  -- Anything not already tracked gets a default target so inventory keeps it.
  local SMELT_DEFAULT_TARGET = 256
  for _, s in ipairs(C.smeltables()) do
    if not index[s.input] then put(s.input, SMELT_DEFAULT_TARGET) end
    if not index[s.output] then put(s.output, SMELT_DEFAULT_TARGET) end
  end

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

-- When `count` of `name` is crafted: remove that item's base materials from the
-- tracked resources (they were consumed) and add the crafted item itself as a
-- tracked resource (it now needs to be kept). Mutates C.TRACKED_RESOURCES.
function C.onItemCrafted(name, count)
  count = count or 1
  local consumed = C.baseMaterialsOf(name, count)
  for baseName, baseCount in pairs(consumed) do
    adjustTracked(baseName, -baseCount)
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
  local steps = {}
  local needed = {}
  local emitted = {}

  local function recipeFor(n)
    local key = (C.RECIPES and C.RECIPES[n] and n) or (labelMap and labelMap[n])
    return key and C.RECIPES[key] or nil
  end

  local function visit(item, qty, stack)
    local recipe = recipeFor(item)
    if not recipe then return end       -- raw material
    if stack[item] then return end      -- cycle guard
    needed[item] = (needed[item] or 0) + qty
    if emitted[item] then return end

    local yield = recipe.yield or 1
    local crafts = math.ceil(qty / yield)

    stack[item] = true
    for i = 1, 9 do
      local g = recipe.grid and recipe.grid[i]
      if g then
        local ing = itemName(g)
        if ing then visit(ing, crafts, stack) end
      end
    end
    stack[item] = nil

    -- For a smelt step, record the item the furnace actually CONSUMES (the single
    -- grid ingredient), not just the item produced. Callers must feed the input
    -- to the furnace, not the result -- e.g. cobblestone, not the stone it yields.
    local smeltInput
    if recipe.smelt then
      for i = 1, 9 do
        local g = recipe.grid and recipe.grid[i]
        if g then smeltInput = itemName(g); break end
      end
    end

    emitted[item] = true
    steps[#steps + 1] = {
      action = recipe.smelt and "smelt" or "craft",
      name = item,
      count = qty,
      input = smeltInput,
    }
  end

  visit(name, count or 1, {})

  for _, s in ipairs(steps) do
    s.count = needed[s.name] or s.count
  end
  return steps
end

-- The full ordered production plan for one build: every craft and smelt needed
-- to turn raw base materials into all the BOM items, deepest-first.
function C.buildProductionPlan()
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
  return order
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

C.TRACKED_CHEST = { x = 0, y = 1, z = 0 }

C.STASIS_X = 4
C.STASIS_Y = 1
C.STASIS_Z = 3

C.TRACKED_RESOURCES = {  { name = "minecraft:cobblestone", min = 128, target = 1024 },
  { name = "minecraft:iron_ore",    min = 64,  target = 512 },
  { name = "minecraft:coal",        min = 64,  target = 512 },
  { name = "minecraft:gold_ore",    min = 32,  target = 256 },
  { name = "minecraft:redstone",    min = 64,  target = 512 },
  { name = "minecraft:iron_ingot",  min = 64,  target = 512 },
  { name = "minecraft:gold_ingot",  min = 32,  target = 256 },
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

-- Go to the tracked chest, count each requested item, and return to stasis.
-- `items` is a list of item name strings. Returns a table name -> count.
function C.readChestCounts(items)
  local counts = {}
  local specs = {}
  for _, name in ipairs(items) do
    counts[name] = 0
    specs[name] = C.specFor(name)
  end

  C.gotoChestFromStasis()
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
  C.gotoStasisFromChest()
  return counts
end

-- Read EVERY item count from the tracked chest (name -> count). Navigates to the
-- chest and back. Used by the autocrafter's materials pre-check.
function C.readAllChestCounts()
  local counts = {}
  C.gotoChestFromStasis()
  local ok, size = pcall(inv.getInventorySize, sides.front)
  if ok and size then
    for s = 1, size do
      local okS, st = pcall(inv.getStackInSlot, sides.front, s)
      if okS and st and st.name and st.size then
        counts[st.name] = (counts[st.name] or 0) + st.size
      end
    end
  end
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
  return C.suckMatchFromFront(match)
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
  return C.suckMatchFromFront(match)
end

function C.selectMatching(match)
  for i = 1, 16 do
    local stack = inv.getStackInInternalSlot(i)
    if stack and stack.name and stack.size and stack.size > 0
        and string.find(stack.name, match, 1, true) then
      robot.select(i)
      return true
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

return C
