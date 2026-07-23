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

-- Run one smelt step through the furnace: load it, then collect the output.
local function doSmelt(step)
  local jobs = { {
    item = step.name,
    fuel = SMELT_FUEL,
    amount = step.count,
    fuelAmount = math.max(1, math.ceil(step.count / 8)),
  } }
  furnace_add(jobs)
  furnace_take()
  -- The furnace states don't report a count, so treat a completed pass as the
  -- requested amount; the final chest check below is the real verification.
  produced[step.name] = (produced[step.name] or 0) + step.count
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
