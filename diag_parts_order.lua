-- diag_parts_order.lua
-- Prints the CURRENT C.ROBOT_PARTS order as the running robot sees it.
-- If this doesn't match what you expect, the common.lua on the robot is stale.

local os = require("os")

-- require() caches modules in package.loaded, so if common.lua was loaded
-- earlier this session, require("common") returns the OLD in-memory copy and
-- ignores edits to the file. Drop it from the cache first to read the real file.
package.loaded["common"] = nil
local C = require("common")

local term
pcall(function() term = require("term") end)
local function clear()
  if term and term.clear then term.clear() else for _ = 1, 12 do print("") end end
end

local parts = C.ROBOT_PARTS or {}
local lines = {}
for i, p in ipairs(parts) do
  lines[#lines + 1] = string.format("%2d. %s", i, p.label)
end

-- paged, ~7 per screen
local per = 7
local page = 1
local total = math.ceil(#lines / per)
for start = 1, #lines, per do
  clear()
  print("ROBOT_PARTS order  (page " .. page .. "/" .. total .. ")")
  print("--------------------------")
  for i = start, math.min(start + per - 1, #lines) do
    print(lines[i])
  end
  print("--------------------------")
  print("generator should be #2")
  os.sleep(15)
  page = page + 1
end

clear()
print("=== done ===")
print("total parts: " .. #parts)
print("if generator is NOT #2 here,")
print("the robot has a stale common.lua")
