-- robot.lua: entry point. Hands control to the scheduler, which drives the robot
-- through an ordered schedule of states (a one-time startup, then a repeating
-- weave) rather than letting each state pick the next one.
--
-- All modules (common.lua, recipes.lua, the state files, scheduler.lua) must be
-- in the same directory. Fetch/update them with pull_repo.

local scheduler = require("scheduler")

scheduler()
