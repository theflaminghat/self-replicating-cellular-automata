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
  farm_spruce_sweep = require("farm_spruce_sweep"),
  farm_sugarcane  = require("farm_sugarcane"),
  farm_cactus     = require("farm_cactus"),
  crafting        = require("crafting"),
  furnace_add     = require("furnace_add"),
  furnace_take    = require("furnace_take"),
  fill_generators = require("fill_generators"),
  build_robot     = require("build_robot"),
  take_robot      = require("take_robot"),
  dispatch        = require("dispatch"),
  fill_buckets    = require("fill_buckets"),
}

-- Ores to smelt, each with the fuel to use.
-- Fuel used for every furnace job. The list of what to smelt is derived from the
-- smelt recipes (C.smeltables), not hardcoded here.
local SMELT_FUEL = "Coal"

local PICKAXE = "minecraft:iron_pickaxe"
local PICKAXE_LABEL = "Iron Pickaxe"

-- Set true when the robot is already built and parked at stasis: skips the one-time
-- startup (building the base + initial mining) and goes straight to the main weave.
local start_from_stasis = false

-- Runs once at power-on (skipped entirely when start_from_stasis is set).
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
-- Charge cycle: drive home (returning) then sit and charge (stasis). The stasis
-- state fuels the generators itself, right after it parks at the charger and before
-- it draws on them -- so no fill_generators call belongs here.
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

  -- Cobblestone floods the chest, so its stone OUTPUT is capped to the build's real
  -- demand rather than smelting the whole pile. Precompute that demand and who
  -- consumes stone, so we can discount stone the build already has -- both raw stone
  -- and stone already baked into finished buttons.
  local builds = C.buildsNeeded()
  local stoneDemand = C.smeltInputNeed("minecraft:cobblestone") * builds
  local stoneConsumers = C.smeltOutputConsumers("Stone", "Stone")

  local items = {}
  for _, s in ipairs(smeltables) do items[#items + 1] = s.input end
  items[#items + 1] = "Stone"          -- output, to gauge raw stone on hand
  for _, c in ipairs(stoneConsumers) do items[#items + 1] = c.key end
  local counts = C.readChestCounts(items)

  -- Coal on hand for smelting. Each job burns ceil(amount/8) coal; jobs that can't
  -- be fueled are skipped this pass and retried later, once more coal is available.
  local coalLeft = C.readChestCounts({ SMELT_FUEL })[SMELT_FUEL] or 0

  -- Stone the build already has toward its demand. The freshly smelted stone is
  -- collected into INVENTORY by furnaceTakeStep just before this runs, so counting
  -- the chest alone would miss it and smelt a second batch. And once that stone is
  -- crafted into buttons it's "gone" from the stone count -- so also credit the
  -- stone embodied in finished buttons, or the furnace would re-smelt after the
  -- buttons are already made. Both are what the user saw as an extra stone job.
  local stoneOnHand = (counts["Stone"] or 0)
                    + C.heldCount(C.specFor("Stone"))
  for _, c in ipairs(stoneConsumers) do
    -- (made / yield) * per: a consumer's yield outputs share one craft's `per`
    -- stone, so divide by yield (harmless at yield 1, correct if it's ever higher).
    local made = (counts[c.key] or 0) + C.heldCount(C.specFor(c.key))
    stoneOnHand = stoneOnHand + (made / (c.yield or 1)) * c.per
  end

  local jobs = {}
  for _, s in ipairs(smeltables) do
    local amount
    if s.input == "minecraft:cobblestone" then
      -- Smelt cobblestone to stone only up to the build's OUTSTANDING stone demand.
      amount = math.min(counts[s.input] or 0,
                        math.max(0, stoneDemand - stoneOnHand), 64)
    else
      -- One furnace load is at most a stack (64). Larger piles are smelted across
      -- successive passes rather than all at once.
      amount = math.min(smeltAmount(counts[s.input] or 0), 64)
    end
    if amount > 0 then
      local fuelNeed = math.ceil(amount / 8)
      if coalLeft >= fuelNeed then
        jobs[#jobs + 1] = {
          -- A spec (id or { label = ... }) so furnace_add pulls the input from the
          -- chest by whichever key actually identifies it.
          item = C.specFor(s.input),
          -- specFor so a label fuel ("Coal") matches by label; a bare string would
          -- be treated as an item id and never match the live coal (minecraft:coal).
          fuel = C.specFor(SMELT_FUEL),
          amount = amount,
          fuelAmount = fuelNeed,
        }
        coalLeft = coalLeft - fuelNeed
      end
      -- else: not enough coal for this input right now -- skip, retry next pass.
    end
  end

  if #jobs == 0 then
    return  -- nothing worth smelting (or no coal to smelt it) this pass
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

-- Crushing: collect the sand the crusher ground into the hopper, then -- if the build
-- still needs sand and there's at least a batch of cobblestone in the target chests --
-- grind another 64-cobblestone batch. The SAND target caps how much ever gets ground
-- (only the ~sandTarget*8 cobble the build's sand needs), and mining refills the
-- cobble, so this converts just the sand's share and never runs the cobble to nothing.
local function crushStep()
  -- Skip on low battery; the next state drives the charge cycle.
  if C.batteryLevel() < 0.25 then return end

  C.takeFromHopper()

  local counts = C.readChestCounts({ "Sand", "minecraft:cobblestone" })
  local sandTarget = 0
  for _, r in ipairs(C.TRACKED_RESOURCES or {}) do
    if r.name == "Sand" then sandTarget = r.target or 0 end
  end

  local sandHave = counts["Sand"] or 0
  local cobbleHave = counts["minecraft:cobblestone"] or 0
  if sandHave < sandTarget and cobbleHave >= C.CRUSHER_BATCH_IN then
    C.addToCrusher(C.CRUSHER_BATCH_IN)
  end
end

-- ---------------------------------------------------------------------------
-- Replication: assemble and collect offspring.
-- ---------------------------------------------------------------------------

-- Replication progress. Persisted to disk so a reboot or chunk unload mid-cycle
-- doesn't re-build an offspring already made or forget one waiting to be
-- dispatched.
--   builtCount      -- offspring finished so far
--   assembling      -- an assembly is in progress (don't load a second robot)
--   pendingDispatch -- an offspring has been collected and still needs dispatching
local builtCount = 0
local assembling = false
local pendingDispatch = false

local REPL_FILE = "/home/replication.txt"

local function saveReplication()
  local f = io.open(REPL_FILE, "w")
  if not f then return end
  f:write(string.format("builtCount=%d\nassembling=%s\npendingDispatch=%s\n",
    builtCount, tostring(assembling), tostring(pendingDispatch)))
  f:close()
end

local function loadReplication()
  local f = io.open(REPL_FILE, "r")
  if not f then return end
  for line in f:lines() do
    local k, v = line:match("^(%w+)=(.*)$")
    if k == "builtCount" then
      builtCount = tonumber(v) or 0
    elseif k == "assembling" then
      assembling = (v == "true")
    elseif k == "pendingDispatch" then
      pendingDispatch = (v == "true")
    end
  end
  f:close()
end

-- Are all the robot parts for one offspring sitting in the tracked chest?
local function partsReady()
  local names, need = {}, {}
  for _, part in ipairs(C.ROBOT_PARTS or {}) do
    local label = part.label or part.name
    if not need[label] then names[#names + 1] = label end
    need[label] = (need[label] or 0) + (part.count or 1)
  end
  local have = C.readChestCounts(names)
  for label, n in pairs(need) do
    if (have[label] or 0) < n then return false end
  end
  return true
end

-- Collect a finished offspring from the assembler. If one comes out, the current
-- assembly is done, it counts toward the offspring this robot owes, and it now
-- needs dispatching.
local function takeRobotStep()
  states.take_robot()
  if C.lastTakeRobot and (C.lastTakeRobot.taken or 0) > 0 then
    assembling = false
    builtCount = builtCount + 1
    pendingDispatch = true
    saveReplication()
  end
end

-- Dispatch a collected offspring (program its boot media at the computer). Only
-- runs when one is waiting.
local function dispatchStep()
  if not pendingDispatch then return end
  if C.batteryLevel() < 0.25 then return end  -- charge first; retry next pass

  -- Direction for the offspring just collected. buildStep won't assemble another
  -- while a dispatch is pending, so builtCount stays put and this stays correct.
  local dir = (C.offspringPlan or {})[builtCount]
  if not dir then
    -- Plan exhausted (nothing to place). Clear the flag so we don't spin on it.
    pendingDispatch = false
    saveReplication()
    return
  end

  -- Robot gate: only dispatch when the offspring we're supposed to send is actually
  -- in inventory. A stale pendingDispatch (e.g. replication state inherited by a
  -- fresh offspring, or a flag set before assembly finished) would otherwise run the
  -- whole computer-programming dance -- including its 24s of os.sleep -- with no
  -- robot to place. That's the "robot stalls at the computer doing nothing". No
  -- robot present means nothing to dispatch, so clear the stale flag and let
  -- buildStep assemble the next one.
  if not C.offspringRobotSlot() then
    pendingDispatch = false
    saveReplication()
    return
  end

  -- Materials gate: don't dispatch until the offspring's ENTIRE build payload is in
  -- the chest. takeBuildMaterialsFromChest is all-or-nothing -- it pulls only when
  -- everything is available and returns false otherwise -- so a not-yet-crafted
  -- machine (e.g. the coal generator) leaves the offspring waiting in inventory
  -- rather than loading a partial cobble/coal payload into the crafting-grid slots
  -- and shipping an under-supplied offspring. Keep pendingDispatch set; the weave
  -- crafts/gathers the rest and the dispatch retries next pass.
  if not C.takeBuildMaterialsFromChest() then
    return
  end

  -- Only clear the pending flag if the dispatch actually finished (not a low
  -- battery bail), so an interrupted dispatch is retried.
  if states.dispatch(dir) ~= "returning" then
    pendingDispatch = false
    saveReplication()
  end
end

-- Start assembling the next offspring, but only when the assembler is free (not
-- mid-build), we still owe offspring, and a full parts set is in the chest.
local function buildStep()
  if C.batteryLevel() < 0.25 then return end
  if assembling then return end
  -- Don't start the next offspring until the current one is dispatched. This keeps
  -- builtCount stable while a dispatch is pending, so dispatchStep's direction
  -- lookup can't be knocked out from under it by a fresh collection.
  if pendingDispatch then return end
  if builtCount >= C.buildsNeeded() then return end
  if not partsReady() then return end
  states.build_robot()
  assembling = true
  saveReplication()
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
  crushStep,
  furnaceTakeStep,
  furnaceAddStep,
  "farm_spruce_sweep",   -- collect the spruce drops AFTER furnace add (leaves have had
                         -- ample time to decay); skips itself if no tree was chopped
  autocraftStep,
  "inventory",
  takeRobotStep,
  dispatchStep,
  "inventory",     -- clean up dispatch leftovers and refill the reserve used bridging
  buildStep,
}

local function scheduler()
  -- Initialization: determine this robot's type from slot 44, expand the build
  -- BOM into base materials, and set the tracked resources to those base materials
  -- times the number of builds this robot needs to make -- so the tracked chest
  -- holds everything replication requires (plus the spruce-sapling/coal floors).
  C.robotType = C.detectRobotType()
  C.offspringPlan = C.offspringDirections(C.robotType)
  C.baseMaterials = C.baseMaterialsForBuild()
  C.scaleTrackedResources()

  -- Restore replication progress (offspring built, assembly in flight, dispatch
  -- pending) so a reboot resumes rather than restarts.
  loadReplication()

  if start_from_stasis then
    -- Already built and parked at the charger. The startup phase is what normally
    -- establishes the robot's location, so seed the position tracker to stasis
    -- (facing the charger, -Z) -- otherwise the weave navigates from the default
    -- (0,0,0) and the quarry heads off to the wrong spot.
    C.pos.x, C.pos.y, C.pos.z, C.pos.facing = C.STASIS_X, C.STASIS_Y, C.STASIS_Z, 2
  else
    for _, entry in ipairs(STARTUP) do
      runToCompletion(entry)
    end
  end

  while true do
    for _, entry in ipairs(WEAVE) do
      runToCompletion(entry)
    end
  end
end

C.scheduler = scheduler

return scheduler
