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

-- Compute the static smelt gauges (per smeltable: its per-build output demand) and take a
-- full snapshot of the tracked chests in ONE trip. smeltInputNeed doesn't touch the chest;
-- only the single chestStacks snapshot does. The add step derives every count it needs
-- (coal, each input, each output + its recursive embodiment) from that snapshot in memory.
local function readFurnacePlan()
  local smeltables = C.smeltables()
  local builds = C.buildsNeeded()
  local gauges = {}
  for _, s in ipairs(smeltables) do
    gauges[#gauges + 1] = {
      s = s,
      demand = C.smeltInputNeed(s.input) * builds,
    }
  end
  -- One chest trip: snapshot the WHOLE tracked-chest contents. The add step credits each
  -- output not just where it sits loose but everywhere it's embodied in finished products
  -- (recursively), which needs the full contents, not a fixed shortlist of item counts.
  local chestStacks = C.chestStacks()
  local coal = C.countStacks(chestStacks, C.specFor(SMELT_FUEL))
  return { gauges = gauges, chestStacks = chestStacks, coal = coal, builds = builds }
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
  local gauges, builds = plan.gauges, plan.builds
  local coalLeft = plan.coal
  local chestStacks = plan.chestStacks

  -- Combine the chest snapshot with a FRESH inventory scan: furnaceTakeStep collected the
  -- just-finished output into inventory after the chest was read, so the current inventory
  -- holds output the chest snapshot doesn't. Counting/embodiment run over this combined
  -- list purely in memory (no per-item component calls), which also avoids the per-tick
  -- component-call flood that used to stall the robot at the charger between take and add.
  local stacks = {}
  for _, st in ipairs(chestStacks) do stacks[#stacks + 1] = st end
  for slot = 1, (C.INVENTORY_SIZE or 64) do
    local ok, st = pcall(C.inv.getStackInInternalSlot, slot)
    if ok and st and st.size and st.size > 0 then stacks[#stacks + 1] = st end
  end

  -- First pass: work out how much each smeltable would smelt this cycle (no coal gate).
  for _, g in ipairs(gauges) do
    local s = g.s

    -- Output already available toward the demand: the loose count (chest + inventory) PLUS
    -- every copy already embodied in finished products that consumed it -- RECURSIVELY, not
    -- just one level. Once an ingot is baked into a piston, and the piston into a drive, the
    -- ingot is gone from the loose count and from the piston count; only a recursive credit
    -- (the same one the farm/crafter use, C.effectiveGathered) sees it. A one-level credit
    -- read low here, so the furnace kept re-smelting inputs whose output was already spoken
    -- for -- exactly the "smelting things it already smelted" symptom.
    local onHand = C.effectiveGathered(s.output, stacks)

    -- How much to smelt this pass. One coal smelts 8 items, so a batch that isn't a
    -- multiple of 8 burns a whole coal for a partial batch. Smelt in whole 8-item batches
    -- to avoid that -- EXCEPT smelt the exact outstanding amount when we have enough input
    -- to finish this output's demand in one load, because then the odd remainder is items
    -- the build actually needs. So a small pile (5 iron ore) with a larger outstanding
    -- demand waits to accumulate a full batch instead of wasting a coal on 5 every pass.
    -- The furnace pulls its input FROM the chest, so gate on the chest-only input count.
    local inputHave = C.countStacks(chestStacks, C.specFor(s.input))
    local outstanding = math.max(0, g.demand - onHand)
    local amount
    if outstanding <= inputHave and outstanding <= 64 then
      amount = outstanding                                   -- finishes it; odd remainder OK
    else
      amount = math.floor(math.min(inputHave, 64) / 8) * 8   -- whole batches only; wait for the rest
    end
    g.inputHave, g.onHand, g.amount = inputHave, onHand, amount   -- for the diagnostic
    g.fuelNeed = math.ceil(amount / 8)
  end

  -- The furnace loads ONE job per pass, so process the BIGGEST pile first: sort by the
  -- amount we'd smelt this cycle (then by raw input backlog to break ties), descending.
  table.sort(gauges, function(a, b)
    if (a.amount or 0) ~= (b.amount or 0) then return (a.amount or 0) > (b.amount or 0) end
    return (a.inputHave or 0) > (b.inputHave or 0)
  end)

  -- Build jobs in that priority order, gating on coal. jobs[1] -- the largest smelt that
  -- can be fueled -- is what furnace_add actually loads.
  local jobs = {}
  for _, g in ipairs(gauges) do
    if (g.amount or 0) > 0 and coalLeft >= (g.fuelNeed or 0) then
      jobs[#jobs + 1] = {
        -- A spec (id or { label = ... }) so furnace_add pulls the input from the chest by
        -- whichever key actually identifies it; specFor("Coal") matches the fuel by label.
        item = C.specFor(g.s.input),
        fuel = C.specFor(SMELT_FUEL),
        amount = g.amount,
        fuelAmount = g.fuelNeed,
      }
      coalLeft = coalLeft - g.fuelNeed
    end
    -- else: nothing to smelt, or not enough coal for it right now -- retry next pass.
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

-- Equip the first inventory pickaxe matching (name/label). Returns true if one was
-- found and equipped. (The pickaxe must already be staged in the inventory -- this only
-- moves it into the tool slot, it does not craft.)
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

-- Craft the pickaxe `name` AND its craftable sub-ingredients into the inventory, in
-- dependency order. The pickaxe eats 2 sticks, and sticks aren't part of the finite build
-- demand -- so make them here (Spruce Wood Planks -> Stick) from the wood the spruce farm
-- keeps replenishing, instead of draining whatever sticks happen to be left over. Smelt
-- steps (iron ingot) are the furnace's job and are skipped; diamonds/ingots come from the
-- chest. The FINAL pickaxe step doesn't count the chest, so a shipping pickaxe already
-- stored there won't stop a fresh mining one from being made in the inventory.
local function craftPickaxeOf(name)
  local jobs = {}
  for _, step in ipairs(C.productionPlan(name, 1)) do
    if step.action == "craft" then
      local isPickaxe = C.PICKAXE_IDS[step.name] or C.PICKAXE_LABELS[step.name]
      jobs[#jobs + 1] = {
        name = step.name,
        amount = step.count,
        countChest = not isPickaxe,
        -- Target LOOSE copies, not embodied ones: the pickaxe pulls its sticks in the
        -- flesh (availableCount ignores embodied), so the sub-crafts must actually make
        -- them even when the build's sticks are already baked into its parts.
        loose = true,
      }
    end
  end
  states.crafting(jobs)
end

-- Craft ONE replacement pickaxe into the inventory (does NOT equip it). Below world
-- y = C.DIAMOND_BELOW_Y the quarry is in the deep layers, so make a DIAMOND pickaxe; iron
-- is fine higher up. C.quarryWorldY is the world Y of the layer the quarry was on. If a
-- diamond one can't be made (no diamonds yet), fall back to iron so the quarry can still
-- continue. hasInventoryPickaxe (not hasSparePickaxe) is the success check: the fresh
-- pickaxe is in a normal slot here, not yet staged into TOOL_SLOT.
local function craftPickaxe()
  local deep = (C.quarryWorldY or math.huge) < (C.DIAMOND_BELOW_Y or 0)
  if deep then
    craftPickaxeOf(DIAMOND_PICKAXE)
    if C.hasInventoryPickaxe() then return end
    C.lastPickaxeError = "wanted a diamond pickaxe below y=" .. tostring(C.DIAMOND_BELOW_Y)
      .. " but couldn't craft one (no diamonds?); falling back to iron"
  end
  craftPickaxeOf(PICKAXE)
end

-- Service the pickaxe after the quarry bailed (see C.needsPickaxeAction). Two cases:
--   * The tool BROKE: equip the spare staged earlier so the old pickaxe's last bit of
--     durability wasn't wasted. If somehow no spare was staged, craft and equip a fresh
--     one so the quarry can continue.
--   * The tool is merely LOW and no spare is staged yet: craft one and leave it in the
--     inventory as a spare -- do NOT equip it. The robot keeps mining with the low tool
--     until it breaks, and the broken-case above then swaps the spare in.
local function servicePickaxe()
  if C.toolBroken() then
    -- Prefer the spare we staged in TOOL_SLOT (never a loose shipping pickaxe).
    if C.hasSparePickaxe() then
      C.robot.select(C.TOOL_SLOT)
      pcall(C.inv.equip)
      return
    end
    -- No spare was staged: make one now and equip it.
    craftPickaxe()
    if equipPickaxe(DIAMOND_PICKAXE, DIAMOND_PICKAXE_LABEL) then return end
    if not equipPickaxe(PICKAXE, PICKAXE_LABEL) then
      C.lastPickaxeError = "no pickaxe crafted (missing ingots/diamonds?)"
    end
    return
  end

  -- Low but not broken, and no spare staged (that's why we're here): craft one, move it
  -- into TOOL_SLOT for safekeeping, and keep mining with the current tool until it breaks.
  craftPickaxe()
  C.stageSparePickaxe()
  if not C.hasSparePickaxe() then
    C.lastPickaxeError = "wanted to stage a spare pickaxe but couldn't craft one"
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
--
-- Writes /home/build_status.txt each pass explaining exactly why a build did or didn't
-- start -- the gating flags AND, once those pass, a per-part have/need table -- so a
-- "has the parts but won't build" state is diagnosable instead of guessed at.
local function buildStep()
  local function writeStatus(header, lines)
    pcall(function()
      local f = io.open("/home/build_status.txt", "w")
      if f then f:write(header .. "\n" .. table.concat(lines or {}, "\n") .. "\n"); f:close() end
    end)
  end

  -- Cheap gating first (no chest trip). A flag stuck true here -- e.g. `assembling` or
  -- `pendingDispatch` restored from disk after a reboot mid-cycle -- blocks building even
  -- with a full parts set, so surface it explicitly.
  if C.batteryLevel() < 0.25 then writeStatus("build: blocked -- low battery") return end
  if assembling then writeStatus("build: blocked -- already assembling (flag stuck? reboot mid-build)") return end
  if pendingDispatch then writeStatus("build: blocked -- waiting to dispatch previous offspring") return end
  if builtCount >= C.buildsNeeded() then
    writeStatus(string.format("build: done -- built %d of %d owed", builtCount, C.buildsNeeded()))
    return
  end

  -- Gates passed: read the chest once and check each part's have vs need.
  local names, need = {}, {}
  for _, part in ipairs(C.ROBOT_PARTS or {}) do
    local label = part.label or part.name
    if not need[label] then names[#names + 1] = label end
    need[label] = (need[label] or 0) + (part.count or 1)
  end
  local have = C.readChestCounts(names)
  local lines, missing = {}, {}
  for _, label in ipairs(names) do
    local h, n = have[label] or 0, need[label]
    lines[#lines + 1] = string.format("  %-40s %d/%d %s", label, h, n, (h >= n) and "ok" or "SHORT")
    if h < n then missing[#missing + 1] = label end
  end

  if #missing > 0 then
    writeStatus("build: blocked -- short on: " .. table.concat(missing, ", "), lines)
    return
  end

  writeStatus("build: STARTING assembly", lines)
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
    -- The quarry saved its progress and came to the surface because the pickaxe needs
    -- servicing: either it broke (swap in the staged spare) or it's low and needs a
    -- spare crafted ahead of time. Handle it with the existing crafting state, then
    -- re-run this same step so the quarry resumes where it stopped.
    servicePickaxe()
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
