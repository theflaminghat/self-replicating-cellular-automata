-- test_autocraft_build.lua
-- Drives the full production of ONE build from raw base materials:
--   1. Shows the raw base materials the build needs (what must already be in
--      the tracked chest for this to succeed).
--   2. Shows the dependency-ordered production plan (every craft and smelt,
--      deepest dependency first).
--   3. Executes the plan: smelt steps go through furnace_add/furnace_take, craft
--      steps go through the crafting state.
--   4. Reports what was actually produced and what fell short.
--
-- Place all split files (common.lua, recipes.lua, the state files) in the same
-- directory and run this from there.
--
-- NOTE: this MOVES the robot -- it walks to the tracked chest and the furnace
-- repeatedly. Start it parked at the charger (stasis).

local C = require("common")

local crafting_state = require("crafting")
local furnace_add    = require("furnace_add")
local furnace_take   = require("furnace_take")

-- Seed the tracked position to the charger (stasis), facing the charger (-Z).
-- The robot must be physically parked here; without this, C.pos defaults to the
-- origin (0,0,0) and the coordinate-based navigation walks to the wrong place.
C.pos.x, C.pos.y, C.pos.z, C.pos.facing = C.STASIS_X, C.STASIS_Y, C.STASIS_Z, 2

local PAGE_SECONDS = 12
local SMELT_FUEL = "minecraft:coal"

local term
pcall(function() term = require("term") end)
local function clear()
  if term and term.clear then term.clear() else for _ = 1, 12 do print("") end end
end

local function page(title, lines)
  clear()
  print(title)
  print("--------------------------------")
  for _, l in ipairs(lines) do print(l) end
  print("--------------------------------")
  os.sleep(PAGE_SECONDS)
end

-- Print `lines` in rolling chunks so long lists stay readable.
local function rollingPage(title, header, lines, per)
  per = per or 12
  local chunks = math.max(1, math.ceil(#lines / per))
  for chunk = 1, chunks do
    clear()
    print(title .. "  (" .. chunk .. "/" .. chunks .. ")")
    print("--------------------------------")
    for _, h in ipairs(header or {}) do print(h) end
    local from = (chunk - 1) * per + 1
    local to = math.min(#lines, chunk * per)
    for i = from, to do print(lines[i]) end
    print("--------------------------------")
    os.sleep(PAGE_SECONDS)
  end
end

local function sortedLines(map, fmt)
  local keys = {}
  for k in pairs(map) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    out[#out + 1] = string.format(fmt or "  %-30s %d", k, map[k])
  end
  return out
end

-- ---------------------------------------------------------------------------
-- 1. Raw base materials required
-- ---------------------------------------------------------------------------

local base = C.baseMaterialsForBuild()
rollingPage("BASE MATERIALS needed for 1 build",
  { "These must be in the tracked chest", "before production can complete:" },
  sortedLines(base), 12)

-- ---------------------------------------------------------------------------
-- 2. The production plan
-- ---------------------------------------------------------------------------

local plan = C.buildProductionPlan()
do
  local lines = {}
  for i, step in ipairs(plan) do
    lines[#lines + 1] = string.format("  %2d. %-5s %-28s x%d",
      i, step.action, step.name, step.count)
  end
  rollingPage("PRODUCTION PLAN (deps first)",
    { string.format("%d steps: smelt + craft, in order", #plan) },
    lines, 12)
end

-- ---------------------------------------------------------------------------
-- 3. Execute the plan
-- ---------------------------------------------------------------------------

local produced = {}   -- name -> amount actually made
local failed = {}     -- name -> reason

-- Run one smelt step through the furnace, a stack at a time.
-- The furnace consumes the recipe's INPUT (step.input, e.g. cobblestone), not the
-- item it produces (step.name, e.g. stone). specFor makes label-only inputs (Raw
-- Circuit Board, Lead Ore, ...) match by label. A furnace holds at most 64 input,
-- so the step is broken into 64-item batches; each batch is loaded, and the count
-- is credited only from what furnace_take actually pulls out (furnace_take waits
-- for the batch to finish first). A batch that yields nothing stops the loop.
local function doSmelt(step)
  local input = C.specFor(step.input or step.name)
  local remaining = step.count
  local made = 0
  while remaining > 0 do
    local batch = math.min(remaining, 64)
    furnace_add({ {
      item = input,
      fuel = SMELT_FUEL,
      amount = batch,
      fuelAmount = math.max(1, math.ceil(batch / 8)),
    } })
    furnace_take()
    local taken = (C.lastFurnaceTake and C.lastFurnaceTake.taken) or 0
    made = made + taken
    if taken == 0 then break end
    remaining = remaining - batch
  end
  produced[step.name] = (produced[step.name] or 0) + made
end

-- Run one craft step through the crafting state and record the real yield.
local function doCraft(step)
  crafting_state({ name = step.name, amount = step.count })

  local made = 0
  local reason
  if C.lastCraftReport then
    local yield = C.recipeYield(step.name)
    for _, r in ipairs(C.lastCraftReport) do
      if r.name == step.name then
        if r.batches and r.batches > 0 then
          made = made + r.batches * yield
        end
        reason = reason or r.reason
      end
    end
  end

  if made > 0 then
    produced[step.name] = (produced[step.name] or 0) + made
  else
    failed[step.name] = reason or C.lastCraftError or "no batches crafted"
  end
end

clear()
print("EXECUTING PRODUCTION PLAN")
print("--------------------------------")
print(string.format("%d steps. This moves the robot.", #plan))
print("--------------------------------")
os.sleep(3)

for i, step in ipairs(plan) do
  clear()
  print(string.format("[%d/%d] %s %s x%d", i, #plan, step.action, step.name, step.count))
  print("--------------------------------")
  if step.action == "smelt" then
    doSmelt(step)
  else
    doCraft(step)
  end
  local madeSoFar = produced[step.name]
  print(string.format("  made: %s", madeSoFar and tostring(madeSoFar) or "0"))
  if failed[step.name] then
    print(string.format("  FAILED: %s", tostring(failed[step.name])))
  end
end

-- ---------------------------------------------------------------------------
-- 4. Results
-- ---------------------------------------------------------------------------

do
  local lines = sortedLines(produced)
  if #lines == 0 then lines = { "  (nothing produced)" } end
  rollingPage("PRODUCED", { "Items successfully made:" }, lines, 12)
end

do
  local lines = {}
  local keys = {}
  for k in pairs(failed) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    lines[#lines + 1] = string.format("  %-26s %s", k, tostring(failed[k]))
  end
  if #lines == 0 then lines = { "  (none -- every step produced output)" } end
  rollingPage("SHORTFALLS", { "Steps that produced nothing:" }, lines, 12)
end

-- Final check: compare the BOM against what is actually in the tracked chest.
do
  local have = C.readAllChestCounts()
  local lines = {}
  local missing = 0
  local craftList = C.buildCraftList()
  table.sort(craftList, function(a, b) return a.name < b.name end)
  for _, entry in ipairs(craftList) do
    local got = have[entry.name] or 0
    local ok = got >= entry.count
    if not ok then missing = missing + 1 end
    lines[#lines + 1] = string.format("  %-26s %d/%d %s",
      entry.name, got, entry.count, ok and "ok" or "SHORT")
  end
  rollingPage("BUILD ITEMS IN CHEST",
    { string.format("%d of %d BOM items short", missing, #craftList) },
    lines, 12)
end

clear()
print("test_autocraft_build complete.")
