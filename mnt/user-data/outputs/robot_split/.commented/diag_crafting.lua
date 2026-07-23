-- diag_crafting.lua
-- Read-only diagnostic. Moves nothing, crafts nothing, changes nothing.
--
-- Shows ONE SHORT PAGE AT A TIME, clearing the screen between pages, so
-- nothing scrolls off. Each page waits PAGE_SECONDS before the next.
--
-- Run with the robot sitting at the stasis spot (4,1,3).

local component = require("component")
local robot = require("robot")
local sides = require("sides")
local os = require("os")

-- How long each page stays on screen. Raise this if you need longer to read.
local PAGE_SECONDS = 12

local term
local ok_term = pcall(function() term = require("term") end)

local function clear()
  if ok_term and term and term.clear then
    term.clear()
  else
    for _ = 1, 12 do print("") end
  end
end

local pageNo = 0
local TOTAL = 5

local function page(title, lines)
  pageNo = pageNo + 1
  clear()
  print("[" .. pageNo .. "/" .. TOTAL .. "] " .. title)
  print("------------------------------")
  for _, l in ipairs(lines) do
    print(l)
  end
  print("------------------------------")
  print("next page in " .. PAGE_SECONDS .. "s ...")
  os.sleep(PAGE_SECONDS)
end

-- PAGE 1: the crafting component. This is the main question.
local craftOk, craftComp = pcall(function() return component.crafting end)
local hasCraft = craftOk and craftComp ~= nil
-- OC component methods are callable proxy TABLES, not plain functions, so
-- test callability rather than type()=="function".
local function isCallable(v)
  if type(v) == "function" then return true end
  if type(v) == "table" then
    local mt = getmetatable(v)
    return mt ~= nil and mt.__call ~= nil
  end
  return false
end
local craftFn = hasCraft and isCallable(craftComp.craft)

page("CRAFTING COMPONENT", {
  "exists   : " .. tostring(hasCraft),
  "has craft: " .. tostring(craftFn),
  "craft type: " .. (hasCraft and type(craftComp.craft) or "-"),
  "",
  craftFn and "  -> OK" or "  -> craft() MISSING: see next page",
})

-- If .craft is missing, show what the component DOES expose.
if hasCraft and not craftFn then
  local methods = {}
  pcall(function()
    for k, v in pairs(craftComp) do
      methods[#methods + 1] = "  " .. tostring(k) .. " (" .. type(v) .. ")"
    end
  end)
  if #methods == 0 then
    methods[1] = "  (no readable fields)"
  end
  local shown = {}
  for i = 1, math.min(#methods, 7) do shown[i] = methods[i] end
  TOTAL = TOTAL + 1
  page("WHAT crafting EXPOSES", shown)
end

-- PAGE 2: component list (short names only)
local names = {}
pcall(function()
  for _, name in component.list() do
    names[#names + 1] = name
  end
end)
table.sort(names)
local lines = {}
for i = 1, math.min(#names, 8) do
  lines[#lines + 1] = "  " .. names[i]
end
if #names == 0 then lines[1] = "  (none found)" end
page("COMPONENTS (" .. #names .. ")", lines)

-- PAGE 3: inventory size -- decides if slots 29-32 exist
local sizeOk, invSize = pcall(robot.inventorySize)
local size = sizeOk and invSize or 0
page("INVENTORY SIZE", {
  "slots: " .. tostring(sizeOk and invSize or "FAILED"),
  "",
  (size >= 32) and "  -> 32+: reserve slots 29-32 OK"
                or "  -> UNDER 32: reserve 29-32 DO NOT EXIST",
})

-- PAGE 4: what is in front right now
local ic = component.inventory_controller
local frontSize = nil
if ic then
  local fsOk, fs = pcall(ic.getInventorySize, sides.front)
  frontSize = fsOk and fs or nil
end
page("FACING RIGHT NOW", {
  "solid ahead : " .. tostring(robot.detect()),
  "inventory   : " .. tostring(frontSize or "none"),
  "",
  "  (at the charger, 'none' is normal)",
})

-- PAGE 5: first few item ids the robot carries
local items = {}
if ic then
  for s = 1, math.min(size > 0 and size or 16, 32) do
    local st = ic.getStackInInternalSlot(s)
    if st and st.name then
      items[#items + 1] = string.format("%2d: %s", s, tostring(st.name))
      if #items >= 6 then break end
    end
  end
end
if #items == 0 then items[1] = "  (inventory empty)" end
page("ITEM IDS CARRIED", items)

clear()
print("=== diagnostic done ===")
print("")
print("Key answers:")
print("  crafting component : " .. tostring(hasCraft))
print("  inventory slots    : " .. tostring(size))
print("")
print("Re-run to see the pages again.")
