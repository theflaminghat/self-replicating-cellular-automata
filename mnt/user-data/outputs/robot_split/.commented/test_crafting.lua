-- test_crafting.lua
-- Crafts the modded items, starting from the stasis spot (4,1,3).
--
-- The modded recipe ids/labels are GUESSES, so this first walks to the chest
-- and checks which ingredients actually exist there. Pages 1-2 tell you what
-- matched; the rest report the crafting itself.
--
-- Short paged output: nothing scrolls off.

local component = require("component")
local robot = require("robot")
local os = require("os")

local C = require("common")
local crafting_state = require("crafting")

-- ---- settings ----------------------------------------------------
local PAGE_SECONDS = 15

-- The modded items to craft. Comment out any you do not want.
local JOBS = {
  { name = "oc:transistor",         amount = 8 },
  { name = "oc:raw_circuit_board",  amount = 8 },
  { name = "oc:disk_platter",       amount = 2 },
  { name = "oc:alu",                amount = 1 },
  { name = "oc:microchip1",         amount = 8 },
  { name = "oc:microchip2",         amount = 8 },
  { name = "oc:microchip3",         amount = 8 },
  { name = "oc:memory3",            amount = 1 },
  { name = "oc:eeprom",             amount = 1 },
  { name = "oc:case3",              amount = 1 },
  { name = "oc:assembler",          amount = 1 },
  { name = "oc:charger",            amount = 1 },
  { name = "aa:iron_casing",        amount = 1 },
  { name = "aa:coal_generator",     amount = 1 },
  { name = "td:leadstone_fluxduct", amount = 6 },
  { name = "xu2:crusher",           amount = 1 },
  { name = "spruce_chest",          amount = 1 },
}

C.assumeMaterials = true
-- ------------------------------------------------------------------

local term
pcall(function() term = require("term") end)
local function clear()
  if term and term.clear then term.clear() else for _ = 1, 12 do print("") end end
end

local pageNo, TOTAL = 0, 5
local function page(title, lines)
  pageNo = pageNo + 1
  clear()
  print("[" .. pageNo .. "/" .. TOTAL .. "] " .. title)
  print("--------------------------")
  for _, l in ipairs(lines) do print(l) end
  print("--------------------------")
  os.sleep(PAGE_SECONDS)
end

local function specOf(item)
  if type(item) == "string" then return { name = item } end
  return item
end
local function specText(item)
  local sp = specOf(item)
  if sp.label then return sp.label end
  if sp.damage then return sp.name .. "#" .. sp.damage end
  return sp.name
end
local function matches(st, item)
  if not st then return false end
  local sp = specOf(item)
  if sp.name and st.name ~= sp.name then return false end
  if sp.damage and st.damage ~= sp.damage then return false end
  if sp.label and st.label ~= sp.label then return false end
  return true
end

C.pos.x, C.pos.y, C.pos.z, C.pos.facing = 4, 1, 3, 2

-- Walk to the chest ourselves so we can inspect it before crafting.
clear()
print("walking to the chest ...")
pcall(function()
  C.gotoXZNoDig(C.TRACKED_CHEST.x + 1, C.TRACKED_CHEST.z)
  C.face(3)
end)

-- Read the chest.
local chestStacks = {}
local sizeOk, chestSize = pcall(C.inv.getInventorySize, C.sides.front)
if sizeOk and chestSize then
  for s = 1, chestSize do
    local ok, st = pcall(C.inv.getStackInSlot, C.sides.front, s)
    if ok and st and st.name then chestStacks[#chestStacks + 1] = st end
  end
end

-- Which ingredients across all jobs can actually be found?
local wanted, order = {}, {}
for _, job in ipairs(JOBS) do
  local r = C.RECIPES[job.name]
  if r then
    for i = 1, 9 do
      local it = r.grid[i]
      if it then
        local key = specText(it)
        if wanted[key] == nil then
          wanted[key] = false
          order[#order + 1] = { key = key, item = it }
        end
      end
    end
  end
end
for _, w in ipairs(order) do
  for _, st in ipairs(chestStacks) do
    if matches(st, w.item) then wanted[w.key] = true break end
  end
end

local missing, presentN = {}, 0
for _, w in ipairs(order) do
  if wanted[w.key] then presentN = presentN + 1
  else missing[#missing + 1] = w.key end
end

-- PAGE 1: did we reach the chest?
page("CHEST", {
  "at    : " .. C.pos.x .. "," .. C.pos.z .. " (want 1,0)",
  "slots : " .. tostring(chestSize or "NOT FACING ONE"),
  "stacks: " .. #chestStacks,
})

-- PAGE 2: ingredient ids that did NOT match
local l2 = { "found  : " .. presentN .. "/" .. #order }
if #missing == 0 then
  l2[#l2 + 1] = "all ids matched"
else
  l2[#l2 + 1] = "NOT in chest:"
  for i = 1, math.min(#missing, 5) do
    l2[#l2 + 1] = "  " .. missing[i]:sub(1, 22)
  end
  if #missing > 5 then l2[#l2 + 1] = "  ...+" .. (#missing - 5) .. " more" end
end
page("INGREDIENT IDS", l2)

-- Snapshot, then craft.
local function snapshot()
  local counts = {}
  for s = 1, (C.INVENTORY_SIZE or 48) do
    local ok, st = pcall(C.inv.getStackInInternalSlot, s)
    if ok and st and st.name then
      counts[st.name] = (counts[st.name] or 0) + (st.size or 0)
    end
  end
  return counts
end
local before = snapshot()

clear()
print("crafting " .. #JOBS .. " modded items ...")
local ok, nextState = pcall(crafting_state, JOBS)
local after = snapshot()

-- PAGE 3: crash?
local l3 = { "crashed : " .. tostring(not ok) }
if ok then
  l3[#l3 + 1] = "returned: " .. tostring(nextState)
else
  local m = tostring(nextState)
  while #m > 0 do l3[#l3 + 1] = "  " .. m:sub(1, 24); m = m:sub(25) end
end
l3[#l3 + 1] = "abort: " .. tostring(C.lastCraftError or "none")
page("RESULT", l3)

-- PAGE 4: what got made
local l4 = {}
for name, n in pairs(after) do
  local was = before[name] or 0
  if n > was then l4[#l4 + 1] = string.format("+%d %s", n - was, name:sub(1, 18)) end
end
if #l4 == 0 then l4[1] = "(nothing crafted)" end
while #l4 > 7 do table.remove(l4) end
page("CRAFTED", l4)

-- PAGE 5: per-job reasons
local l5 = {}
local rep = C.lastCraftReport
if rep and #rep > 0 then
  local shown = 0
  for _, r in ipairs(rep) do
    if (r.batches or 0) == 0 and shown < 6 then
      shown = shown + 1
      l5[#l5 + 1] = tostring(r.name):sub(1, 16) .. " " .. tostring(r.reason or "?"):sub(1, 9)
    end
  end
  if shown == 0 then l5[1] = "all jobs made something" end
else
  l5[1] = "jobs never ran"
end
page("FAILED JOBS", l5)

clear()
print("=== done ===")
print("ids found : " .. presentN .. "/" .. #order)
print("crashed   : " .. tostring(not ok))
print("abort     : " .. tostring(C.lastCraftError or "none"))
