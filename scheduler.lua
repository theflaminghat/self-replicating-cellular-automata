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
local DIAMOND_PICKAXE = "minecraft:diamond_pickaxe"
local DIAMOND_PICKAXE_LABEL = "Diamond Pickaxe"

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

-- One chest read serves the WHOLE furnace sequence. furnaceTakeStep reads it (to gate on
-- coal), stashes it here, and furnaceAddStep reuses it -- so the robot does NOT make a
-- second full 3-chest round trip between taking and adding. That extra read trip, with no
-- visible work, is what looked like a long stall after take and before add. It's safe to
-- reuse: the chest doesn't change between the two steps (furnace_take only moves output
-- into the robot's own inventory), and the add step reads that live via heldCount.
local pendingFurnacePlan

-- Compute the static smelt gauges (per smeltable: output demand + who consumes it) and
-- read the chest counts for every id/label involved -- inputs, outputs, consumers, and
-- the fuel -- in ONE chest trip. smeltInputNeed / smeltOutputConsumers don't touch the
-- chest; only the single readChestCounts does.
local function readFurnacePlan()
  local smeltables = C.smeltables()
  local builds = C.buildsNeeded()
  local gauges = {}
  local items = {}
  local seen = {}
  local function want(name)
    if name and not seen[name] then seen[name] = true; items[#items + 1] = name end
  end
  want(SMELT_FUEL)
  for _, s in ipairs(smeltables) do
    local consumers = C.smeltOutputConsumers(s.output, s.output)
    gauges[#gauges + 1] = {
      s = s,
      demand = C.smeltInputNeed(s.input) * builds,
      consumers = consumers,
    }
    want(s.input)
    want(s.output)
    for _, c in ipairs(consumers) do want(c.key) end
  end
  local counts = C.readChestCounts(items)
  return { gauges = gauges, counts = counts, coal = counts[SMELT_FUEL] or 0, builds = builds }
end

-- Collect finished results from the furnace (take before add, so we clear the output
-- before loading a new batch). Reads the furnace plan once and hands it to furnaceAddStep.
local function furnaceTakeStep()
  local plan = readFurnacePlan()
  pendingFurnacePlan = plan
  -- No coal -> nothing can smelt, so there's nothing finished to collect and nothing to
  -- add; skip the furnace trip entirely.
  if plan.coal <= 0 then return end
  -- No-wait: grab whatever the furnace has finished and move on. The weave lap gives the
  -- furnace ample time to smelt before the next visit, so sitting here polling for the
  -- current batch would just stall the robot for minutes.
  states.furnace_take(true)
end

-- Build furnace jobs (demand-gated) and load them, reusing the chest read furnaceTakeStep
-- already did this lap (only re-reads if that stash is somehow missing).
--
-- Demand-gate EVERY smeltable: smelt an input only up to its OUTPUT's outstanding build
-- demand, crediting output already loose AND already baked into finished consumers -- so
-- the furnace makes just what replication needs and stops, instead of grinding whole
-- piles of ore/cactus into ingots the build doesn't need.
local function furnaceAddStep()
  local plan = pendingFurnacePlan or readFurnacePlan()
  pendingFurnacePlan = nil
  local gauges, counts, builds = plan.gauges, plan.counts, plan.builds
  local coalLeft = plan.coal

  -- Snapshot the robot's own inventory ONCE, then count from that in memory. C.heldCount
  -- re-scans all 64 slots with a component call every time, and the loop below needs a
  -- held count per smeltable output AND per consumer (~20+ lookups) -- calling heldCount
  -- each time floods OpenComputers' per-tick component-call budget and leaves the robot
  -- pausing at the charger for ~a minute between take and add. One scan fixes that.
  local invStacks = {}
  for slot = 1, (C.INVENTORY_SIZE or 64) do
    local ok, st = pcall(C.inv.getStackInInternalSlot, slot)
    if ok and st and st.size and st.size > 0 then invStacks[#invStacks + 1] = st end
  end
  local function heldOf(spec)
    local total = 0
    for _, st in ipairs(invStacks) do
      if C.matchesSpec(st, spec) then total = total + (st.size or 0) end
    end
    return total
  end

  local jobs = {}
  for _, g in ipairs(gauges) do
    local s = g.s

    -- Output already available toward the demand. Freshly smelted output was collected
    -- into INVENTORY by furnaceTakeStep just before this runs, so the (cached) chest count
    -- alone would miss it -- add the on-hand count. And once the output is crafted into a
    -- consumer it's "gone" from the loose count, so also credit the output embodied in
    -- finished consumers, or the furnace re-smelts after the parts are already made.
    local onHand = (counts[s.output] or 0) + heldOf(C.specFor(s.output))
    for _, c in ipairs(g.consumers) do
      -- (made / yield) * per: each of a consumer's `yield` outputs shares one craft's
      -- `per` of the smelt output, so divide by yield (correct if it's ever > 1).
      local made = (counts[c.key] or 0) + heldOf(C.specFor(c.key))
      onHand = onHand + (made / (c.yield or 1)) * c.per
    end

    -- Smelt at most the OUTSTANDING demand (0 if the output isn't a build item), the
    -- available input, and one furnace load (64).
    local inputHave = counts[s.input] or 0
    local amount = math.min(inputHave, math.max(0, g.demand - onHand), 64)
    g.inputHave, g.onHand, g.amount = inputHave, onHand, amount   -- for the diagnostic
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

  -- Diagnostic: record WHY the furnace did or didn't load, so a "nothing smelting" state
  -- can be explained (no coal / no input in the chest / every output already satisfied)
  -- rather than guessed at. Written to a file each pass -- `print` isn't visible in this
  -- setup -- so `edit /home/furnace_plan.txt` (or read it) shows the latest decision.
  C.lastFurnacePlan = { coal = plan.coal, jobs = #jobs, rows = {} }
  local lines = { string.format("furnace plan: %d job(s), coal=%d, builds=%d",
                                #jobs, plan.coal, builds) }
  for _, g in ipairs(gauges) do
    C.lastFurnacePlan.rows[#C.lastFurnacePlan.rows + 1] = {
      output = g.s.output, input = g.s.input,
      inputHave = g.inputHave or 0, demand = g.demand,
      onHand = g.onHand or 0, amount = g.amount or 0,
    }
    lines[#lines + 1] = string.format("  %-16s in(%s)=%d  demand=%g  onHand=%g  -> smelt %d",
      tostring(g.s.output), tostring(g.s.input),
      g.inputHave or 0, g.demand, g.onHand or 0, g.amount or 0)
  end
  local body = table.concat(lines, "\n") .. "\n"
  pcall(function()
    local f = io.open("/home/furnace_plan.txt", "w")
    if f then f:write(body); f:close() end
  end)
  pcall(print, lines[1])

  if #jobs == 0 then
    return  -- nothing worth smelting (or no coal to smelt it) this pass
  end

  states.furnace_add(jobs)
end

-- Craft the first inventory pickaxe matching (name/label) and equip it. Returns true
-- if one was found and equipped.
local function equipPickaxe(name, label)
  for s = 1, (C.INVENTORY_SIZE or 32) do
    local ok, st = pcall(C.inv.getStackInInternalSlot, s)
    if ok and st and st.size and st.size > 0 and (st.name == name or st.label == label) then
      C.robot.select(s)
      pcall(C.inv.equip)
      return true
    end
  end
  return false
end

-- Craft a replacement pickaxe and equip it. Below world y = C.DIAMOND_BELOW_Y the quarry
-- is in the deep layers, so make a DIAMOND pickaxe; iron is fine higher up. C.quarryWorldY
-- is the world Y of the layer the quarry was on when the tool broke (the crafter itself
-- runs at the surface). Ingots/sticks (iron) or diamonds/sticks (diamond) come from the
-- chest. If a diamond one can't be made (no diamonds yet), fall back to iron so the
-- quarry can still continue.
local function craftAndEquipPickaxe()
  local deep = (C.quarryWorldY or math.huge) < (C.DIAMOND_BELOW_Y or 0)
  if deep then
    states.crafting({ name = DIAMOND_PICKAXE, amount = 1 })
    if equipPickaxe(DIAMOND_PICKAXE, DIAMOND_PICKAXE_LABEL) then return end
    C.lastPickaxeError = "wanted a diamond pickaxe below y=" .. tostring(C.DIAMOND_BELOW_Y)
      .. " but couldn't craft one (no diamonds?); falling back to iron"
  end

  states.crafting({ name = PICKAXE, amount = 1 })
  if not equipPickaxe(PICKAXE, PICKAXE_LABEL) then
    C.lastPickaxeError = "no pickaxe crafted (missing ingots/diamonds?)"
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

  -- The crusher's yield per batch isn't fixed, so don't assume 8 -- COUNT the real sand.
  -- takeFromHopper just pulled the ground sand into the robot's inventory (it's shelved
  -- into the chest by a later inventory step), so the chest count alone misses it. Add
  -- the sand on hand to the chest total so the "have we ground enough?" test reflects
  -- what was actually produced, not an assumed batch size.
  local sandHave = (counts["Sand"] or 0) + C.heldCount(C.specFor("Sand"))
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
  crushStep,
  furnaceTakeStep,
  furnaceAddStep,
  "farm_spruce_sweep",   -- collect the spruce drops AFTER furnace add (leaves have had
                         -- ample time to decay); skips itself if no tree was chopped
  "inventory",
  autocraftStep,
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
