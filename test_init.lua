-- test_init.lua
-- Exercises the initialization logic:
--   1. Robot TYPE assignment from the cobblestone count in slot 44
--      (C.TYPE_SLOT), plus the offspring directions and tracked-resource count.
--   2. The build materials list (the BOM: blocks + robot parts + computer parts).
--   3. The recursively expanded raw BASE materials for one build.
--
-- Place all split files (common.lua, scheduler.lua, etc.) in the same directory
-- as this script and run it from there. This test does NOT move the robot -- it
-- only reads slot 44 and prints computed lists, paging between sections.

local component = require("component")
local robot = require("robot")

local C = require("common")

local PAGE_SECONDS = 15

local term
pcall(function() term = require("term") end)
local function clear()
  if term and term.clear then term.clear() else for _ = 1, 12 do print("") end end
end

local pageNo, TOTAL = 0, 3
local function page(title, lines)
  pageNo = pageNo + 1
  clear()
  print("[" .. pageNo .. "/" .. TOTAL .. "] " .. title)
  print("--------------------------------")
  for _, l in ipairs(lines) do print(l) end
  print("--------------------------------")
  os.sleep(PAGE_SECONDS)
end

-- Print `lines` in rolling chunks of `per` (default 12), pausing between chunks.
-- Header lines (passed separately) repeat at the top of every chunk so context
-- isn't lost while scrolling through a long list.
local function rollingPage(title, header, lines, per)
  per = per or 12
  local totalChunks = math.max(1, math.ceil(#lines / per))
  for chunk = 1, totalChunks do
    clear()
    print(title .. "  (" .. chunk .. "/" .. totalChunks .. ")")
    print("--------------------------------")
    for _, h in ipairs(header or {}) do print(h) end
    local from = (chunk - 1) * per + 1
    local to = math.min(#lines, chunk * per)
    for i = from, to do print(lines[i]) end
    print("--------------------------------")
    os.sleep(PAGE_SECONDS)
  end
end

-- Sort a name->count map into "  name  count" lines, alphabetical.
local function mapLines(map)
  local keys = {}
  for k in pairs(map) do keys[#keys + 1] = k end
  table.sort(keys)
  local lines = {}
  local total = 0
  for _, k in ipairs(keys) do
    lines[#lines + 1] = string.format("  %-30s %d", k, map[k])
    total = total + map[k]
  end
  lines[#lines + 1] = string.format("  %-30s %d entries", "(distinct)", #keys)
  return lines, total
end

-- ---------------------------------------------------------------------------
-- Page 1: type assignment from slot 44
-- ---------------------------------------------------------------------------

local robotType, cobbleCount = C.detectRobotType()
local offspring = C.offspringDirections(robotType)
local tracked = C.trackedResourceCount(robotType)

do
  local lines = {}
  lines[#lines + 1] = string.format("slot %d cobblestone: %d", C.TYPE_SLOT, cobbleCount)
  lines[#lines + 1] = string.format("robot type:         %s", robotType)
  lines[#lines + 1] = string.format("offspring sent to:  %s",
    (#offspring > 0) and table.concat(offspring, ", ") or "(none)")
  lines[#lines + 1] = string.format("tracked resources:  %d", tracked)
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Type key (cobble count -> type):"
  lines[#lines + 1] = "  0 Genesis  1 N  2 NE  3 E  4 SE"
  lines[#lines + 1] = "             5 S  6 SW  7 W  8 NW"
  page("INIT: type assignment", lines)
end

-- ---------------------------------------------------------------------------
-- Page 2: build materials BOM (blocks)
-- ---------------------------------------------------------------------------

do
  local lines, total = mapLines(C.BUILD_BOM.blocks)
  table.insert(lines, 1, "Blocks / materials placed by the build:")
  lines[#lines + 1] = string.format("  %-30s %d total items", "(sum)", total)
  page("BUILD MATERIALS: blocks", lines)
end

-- ---------------------------------------------------------------------------
-- Page 3: build materials BOM (robot + computer parts)
-- ---------------------------------------------------------------------------

do
  local lines = { "Offspring robot parts:" }
  for _, p in ipairs(C.BUILD_BOM.robot_parts or {}) do
    lines[#lines + 1] = string.format("  %-34s %d",
      tostring(p.label or p.name), p.count or 1)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Computer parts (into the case):"
  for _, p in ipairs(C.BUILD_BOM.computer_parts or {}) do
    lines[#lines + 1] = string.format("  %-34s %d",
      tostring(p.label or p.name), p.count or 1)
  end
  page("BUILD MATERIALS: parts", lines)
end

-- ---------------------------------------------------------------------------
-- Page 4: recursively expanded base materials
-- ---------------------------------------------------------------------------

do
  local base = C.baseMaterialsForBuild()
  local lines = mapLines(base)  -- includes a trailing "(distinct) N entries" line
  rollingPage("BASE MATERIALS (expanded)",
    { "Raw base materials for 1 build", "(recipes expanded recursively):" },
    lines, 12)
end

clear()
print("init test complete.")
print(string.format("type=%s  offspring=%s",
  robotType, table.concat(offspring, ",")))
