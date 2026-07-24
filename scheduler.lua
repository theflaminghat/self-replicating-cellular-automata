-- scheduler.lua: drives the robot through an ordered schedule of states rather
-- than letting each state pick the next one.
--
-- Startup runs once: building, mining.
-- Then the weave loops forever:
--   quarry, inventory, <smelt>, sugarcane, inventory, cactus, inventory,
--   spruce, inventory
--
-- Smelting ore and crafting a replacement pickaxe are NOT separate states: the
-- scheduler orchestrates them by calling the existing furnace_add / furnace_take
-- and crafting states with the right jobs.
--
-- Each scheduled state runs to completion. A state's returned "next" is normally
-- ignored -- the schedule decides what runs next. Two exceptions: "returning"
-- (low battery -> charge, then resume the same step) and "craft_pickaxe" (the
-- quarry's tool broke -> craft+equip a pickaxe, then resume the quarry).

local C = require("common")

local states = {
  inventory       = require("inventory"),
  mining          = require("mining"),
  quarry          = require("quarry"),
  building        = require("building"),
  returning       = require("returning"),
  stasis          = require("stasis"),
  farm_spruce     = require("farm_spruce"),
  farm_sugarcane  = require("farm_sugarcane"),
  farm_cactus     = require("farm_cactus"),
  crafting        = require("crafting"),
  furnace_add     = require("furnace_add"),
  furnace_take    = require("furnace_take"),
  fill_generators = require("fill_generators"),
  build_robot     = require("build_robot"),
  take_robot      = require("take_robot"),
  fill_buckets    = require("fill_buckets"),
}

-- Ores to smelt, each with the fuel to use.
-- Fuel used for every furnace job. The list of what to smelt is derived from the
-- smelt recipes (C.smeltables), not hardcoded here.
local SMELT_FUEL = "minecraft:coal"

local PICKAXE = "minecraft:iron_pickaxe"
local PICKAXE_LABEL = "Iron Pickaxe"

-- Runs once at power-on.
local STARTUP = {
  "building",
  "inventory",
  "mining",
}

-- A schedule entry is either a state name (string) or a scheduler-orchestrated
-- step (function). The weave repeats forever after startup.
local WEAVE  -- forward declaration; filled in after the step functions exist.

-- ---------------------------------------------------------------------------
-- Charge cycle
-- ---------------------------------------------------------------------------

-- Charge the robot: run "returning" (drive to the charger) then "stasis" (sit
-- and charge). We stop chaining once a state other than returning/stasis would
-- be next, so we don't wander off into the old stasis -> mining default.
local function chargeCycle()
  local next = "returning"
  local guard = 0
  while guard < 8 do
    guard = guard + 1
    local handler = states[next]
    if not handler then break end
    next = handler()
    if next ~= "returning" and next ~= "stasis" then
      break
    end
  end
end

-- ---------------------------------------------------------------------------
-- Orchestrated steps (reuse existing states, no new state files)
-- ---------------------------------------------------------------------------

-- Smelt only when more than 8 of an ore are present, always a multiple of 8 at
-- or below the amount present.
local function smeltAmount(count)
  if count <= 8 then return 0 end
  return math.floor(count / 8) * 8
end

-- Collect finished results from the furnace (take before add, so we clear the
-- output before loading a new batch).
local function furnaceTakeStep()
  states.furnace_take()
end

-- Read the chest and build furnace jobs for everything smeltable. The list comes
-- from the smelt recipes themselves (C.smeltables), so adding a smelt recipe
-- automatically includes it here.
local function furnaceAddStep()
  local smeltables = C.smeltables()

  local items = {}
  for _, s in ipairs(smeltables) do items[#items + 1] = s.input end
  local counts = C.readChestCounts(items)

  local jobs = {}
  for _, s in ipairs(smeltables) do
    -- Cobblestone is the primary mined block and floods the chest; smelting it to
    -- stone would monopolize the single furnace and starve the ores, so it is not
    -- part of the automatic smelt loop.
    if s.input ~= "minecraft:cobblestone" then
      -- One furnace load is at most a stack (64). Larger piles are smelted across
      -- successive passes rather than all at once.
      local amount = math.min(smeltAmount(counts[s.input] or 0), 64)
      if amount > 0 then
        jobs[#jobs + 1] = {
          -- A spec (id or { label = ... }) so furnace_add pulls the ore from the
          -- chest by whichever key actually identifies it.
          item = C.specFor(s.input),
          fuel = SMELT_FUEL,
          amount = amount,
          fuelAmount = math.ceil(amount / 8),
        }
      end
    end
  end

  if #jobs == 0 then
    return  -- nothing worth smelting this pass
  end

  states.furnace_add(jobs)
end

-- Craft one iron pickaxe using the crafting state, then equip it. Ingots and
-- sticks are expected in the chest (ingots from smelting).
local function craftAndEquipPickaxe()
  states.crafting({ name = PICKAXE, amount = 1 })

  -- Equip the freshly crafted pickaxe.
  local slot
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(C.inv.getStackInInternalSlot, s)
    if ok and st and st.size and st.size > 0 then
      if st.name == PICKAXE or st.label == PICKAXE_LABEL then
        slot = s
        break
      end
    end
  end
  if slot then
    C.robot.select(slot)
    pcall(C.inv.equip)
  else
    C.lastPickaxeError = "no iron pickaxe crafted (missing ingots?)"
  end
end

-- Autocrafting: craft the whole build recursively, deepest dependency first.
--
-- C.buildProductionPlan returns every craft AND smelt needed to turn raw base
-- materials into the BOM, ordered so an item's ingredients are always produced
-- before the item itself. The smelt steps are the furnace's job (handled earlier
-- in the weave), so here we take only the CRAFT steps, in that order, and hand
-- them to the crafting state in one trip. A finished item stays in the robot's
-- inventory, where a later step (e.g. a microchip) sources the intermediate it
-- depends on (e.g. a transistor) directly -- crafting pulls ingredients from the
-- inventory as well as the chest.
--
-- Each job counts what's already in the chest toward its target (countChest), so
-- repeat passes don't re-craft what earlier passes (or the current one) already
-- produced. What actually gets made is fed back into the tracked resources via
-- C.onItemCrafted, and the inventory state deposits the finished items afterward.
local function autocraftStep()
  local builds = C.buildsNeeded()

  C.lastAutocraftReport = {}

  local jobs = {}
  for _, step in ipairs(C.buildProductionPlan()) do
    if step.action == "craft" then
      jobs[#jobs + 1] = {
        name = step.name,
        amount = (step.count or 1) * builds,
        countChest = true,
      }
    end
  end

  if #jobs == 0 then
    return  -- nothing to craft; robot is already at stasis
  end

  -- The plan can be long, so crafting may run the battery down partway and bail
  -- with "returning" without walking home. Charge, then leave; countChest means
  -- the next pass skips whatever this pass already made and picks up where it
  -- stopped.
  local result = states.crafting(jobs)
  if result == "returning" then
    chargeCycle()
  end

  -- Fold the results back into the tracked resources, using the real amount made
  -- (batches * recipe yield) reported per job.
  if C.lastCraftReport then
    for _, r in ipairs(C.lastCraftReport) do
      if r.batches and r.batches > 0 then
        local made = r.batches * C.recipeYield(r.name)
        if made > 0 then
          C.onItemCrafted(r.name, made)
          C.lastAutocraftReport[#C.lastAutocraftReport + 1] =
            { name = r.name, made = made }
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Step runner
-- ---------------------------------------------------------------------------

-- Run one scheduled entry. Returns true if the step is finished (or was ended
-- by a battery charge), false only if it was interrupted by a pickaxe craft and
-- should be re-run so the new tool gets used immediately.
local function runStep(entry)
  -- Scheduler-orchestrated step: just call it.
  if type(entry) == "function" then
    entry()
    return true
  end

  local handler = states[entry]
  if not handler then
    error("Scheduler: unknown state '" .. tostring(entry) .. "'")
  end
  local result = handler()

  if result == "returning" then
    -- Low battery: charge, then END this step and let the weave move on. The
    -- quarry (and other resumable states) saved their progress before bailing,
    -- so the next time the schedule comes back around they pick up where they
    -- stopped. This keeps the robot cycling through the whole weave rather than
    -- getting stuck re-running one step after every charge.
    chargeCycle()
    return true  -- step ends; advance to the next scheduled entry
  end

  if result == "craft_pickaxe" then
    -- The tool broke mid-step (the quarry saved its progress and came to the
    -- surface). Craft + equip a new pickaxe using the existing crafting state,
    -- then re-run this same step so the quarry resumes where it stopped.
    craftAndEquipPickaxe()
    return false  -- interrupted; caller re-runs this step
  end

  return true  -- completed
end

-- Run a step until it finishes. A battery charge ends the step (advances the
-- weave); only a pickaxe craft loops back to re-run the same step.
local function runToCompletion(entry)
  while not runStep(entry) do
    -- interrupted by a pickaxe craft; run the same step again with the new tool
  end
end

-- Now that smeltStep exists, define the weave. Smelting runs after quarry +
-- inventory, as a scheduler-orchestrated step (not a state).
WEAVE = {
  "quarry",
  "inventory",
  "farm_spruce",
  "farm_sugarcane",
  "farm_cactus",
  "inventory",
  furnaceTakeStep,
  furnaceAddStep,
  autocraftStep,
  "inventory",
}

local function scheduler()
  -- Initialization: determine this robot's type from slot 44, expand the build
  -- BOM into base materials, and set the tracked resources to those base
  -- materials times the number of builds this robot needs to make (one per
  -- offspring it will send).
  C.robotType = C.detectRobotType()
  C.offspringPlan = C.offspringDirections(C.robotType)
  C.baseMaterials = C.baseMaterialsForBuild()
  C.scaleTrackedResources()

  for _, entry in ipairs(STARTUP) do
    runToCompletion(entry)
  end

  while true do
    for _, entry in ipairs(WEAVE) do
      runToCompletion(entry)
    end
  end
end

C.scheduler = scheduler

return scheduler
