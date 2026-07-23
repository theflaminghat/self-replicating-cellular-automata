-- returning.lua
local C = require("common")

local function returning()
  -- Still using the (4,4) shaft to climb out, so keep hole passage on until the
  -- robot is back at the surface, then disable it so other states avoid the hole.
  C.allowHole = true
  C.climbToSurface()
  C.allowHole = false
  return "stasis"
end

return returning
