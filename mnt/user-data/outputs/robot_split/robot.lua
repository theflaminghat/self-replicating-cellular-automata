-- robot.lua: entry point. Hands control to the scheduler, which drives the
-- robot through an ordered schedule of states (startup, then a repeating weave)
-- rather than letting each state pick the next one.
--
-- All files (common.lua, the state files, and scheduler.lua) must be in the
-- same directory.

local scheduler = require("scheduler")

scheduler()
