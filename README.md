# self-replicating-cellular-automata

A self-replicating robot for modded Minecraft 1.12.2, written in Lua for
[OpenComputers](https://github.com/MightyPirates/OpenComputers).

You place one robot (the **Genesis** robot) carrying a starter kit. It builds a small
base, then mines, farms, smelts and crafts until it has made a complete copy of itself:
a new robot, plus every block and machine that robot needs to build its own base. It
carries each copy out along a cobblestone bridge, places it, and hands over the kit.
Each copy then does the same thing, so the bases spread across the world following a
simple growth rule, like a cellular automaton.

## How it works

### Lifecycle

1. **Build:** on first boot the robot lays a 9 × 16 cobblestone floor and places its
   machines, a chest wall, a sugarcane and cactus farm, and a spruce tree.
2. **Mine:** it digs a shaft to bedrock, then quarries a 32 × 32 area from the bottom up.
3. **Loop forever:** quarry, deposit, farm (spruce, sugarcane, cactus), grind
   cobblestone into sand, smelt, autocraft the next copy, assemble it, fill its water
   buckets, and send it out. It charges at the charger whenever its battery runs low.

The robot works out what to gather from a list of everything one copy needs (`C.BUILD_BOM`
in `common.lua`) and the recipes in `recipes.lua`. It breaks that list down into raw
materials, keeps exactly that much in its three storage chests, and stops farming or
crafting anything it already has. An item counts as "had" even after it has been crafted
into something else (paper that became transistors still counts as paper).

### Replication rule

A robot's type is the number of cobblestone in its inventory slot 44:

| Slot 44 | Type | Sends copies |
|---|---|---|
| empty | Genesis | one each north, east, south and west, of those types |
| 1, 3, 5, 7 | N, E, S, W | one straight on, of its own type, and one to its right, of the diagonal type between them (N → NE, E → SE, S → SW, W → NW) |
| 2, 4, 6, 8 | NE, SE, SW, NW | one onward, of its own type: NE east, SE south, SW west, NW north |

Each copy is placed exactly 32 blocks from its parent's corner, so the bases and their
32 × 32 quarries tile a 32-block grid. The four main arms run straight out from the
Genesis base, and each diagonal type fills the quarter of the grid to its arm's right,
one cell after another. Every grid cell gets exactly one base, and the colony grows by
one ring per generation. After four generations (north is up):

```
 .  .  .  .  N  .  .  .  .
 .  .  . NW  N NE  .  .  .
 .  . NW NW  N NE NE  .  .
 . NW NW NW  N NE NE NE  .
 W  W  W  W  G  E  E  E  E
 . SW SW SW  S SE SE SE  .
 .  . SW SW  S SE SE  .  .
 .  .  . SW  S SE  .  .  .
 .  .  .  .  S  .  .  .  .
```

### How a copy is made

- **Parts:** the robot autocrafts every part of the new robot and its base from the raw
  materials, deepest ingredient first.
- **Boot media:** the base's computer copies its own hard drive and BIOS onto blank
  ones, for both the new robot and the new robot's computer.
- **Assembly:** the robot loads the parts into the Electronics Assembler and presses the
  button on the computer, which starts the assembler. Robots can't start the assembler
  themselves.
- **Dispatch:** the robot arranges its own inventory into the exact slot layout a new
  robot expects, lays a cobblestone bridge out to the spot 32 blocks from its corner,
  places the new robot there, and copies the inventory over slot by slot.

The same files run on both machines: `robot.lua` runs the robot program when it finds a
`robot` component, and the computer program otherwise.

## Requirements

### Minecraft and mods

Minecraft **1.12.2** with Forge, plus:

| Mod | What the robot uses from it |
|---|---|
| OpenComputers | The robots, the base computer, the Electronics Assembler, the Charger, and every electronic part (chips, CPUs, memory, drives, cards, upgrades) |
| Actually Additions | Coal Generator (crafted from an Iron Casing, which needs Black Quartz from Black Quartz Ore) |
| Thermal Dynamics | Leadstone Fluxduct, which carries power from the generators to the machines |
| Thermal Foundation (and CoFH Core, CoFH World) | Required by Thermal Dynamics; its Lead Ore makes the fluxducts' lead ingots |
| Extra Utilities 2 | Crusher (crafted from a Machine Block), which grinds cobblestone into sand |

### Items matched by name

The code finds items by their in-game display names, and every recipe is written out in
`recipes.lua`. Your pack must provide these items under exactly these names and recipes:

- **Spruce Chest:** 8 Spruce Wood Planks make 1. Vanilla makes a plain "Chest" instead.
- **Spruce Button:** 1 Spruce Wood Planks makes 1. Vanilla makes a plain "Button".
- **Diamond Nugget:** 1 Diamond makes 9. Not in vanilla.

If your pack changes any recipe the robot crafts, edit `recipes.lua` to match.

### OpenComputers config

The quarry assumes the default robot flight limit (`limitFlightHeight = 8`): a robot
can't hover more than 8 blocks above a solid block unless it's right next to one. So it
mines 7 layers and leaves 1 solid as a floor, which leaves about 1 layer in 8 unmined.

## Setting up the Genesis robot

### The robot

Assemble it from the same parts it will build for its copies (`C.ROBOT_PARTS`):

- Computer Case (Tier 3)
- Central Processing Unit (CPU) (Tier 3)
- Memory (Tier 3)
- Hard Disk Drive (Tier 2) (2MB), with OpenOS and this repo's files
- EEPROM (Lua BIOS)
- Battery Upgrade (Tier 3)
- 2 × Solar Generator Upgrade
- Inventory Controller Upgrade
- Crafting Upgrade
- 4 × Inventory Upgrade (64 inventory slots in total)

An Internet Card is only needed if you use `pull_repo` to download the code (see below).
Copies don't get one; they get the code from the drive copy.

### Starting inventory

The robot expects its starter kit in these exact slots (`C.BUILD_LAYOUT`):

| Slot | Item | Count |
|---|---|---|
| 1, 2, 3 | Cobblestone (floor) | 64, 64, 15 |
| 4 | Dirt | 1 |
| 5 | Coal Generator | 2 |
| 6 | Leadstone Fluxduct | 5 |
| 7 | Computer Case (Tier 3) | 1 |
| 8 | Electronics Assembler | 1 |
| 9 | Hopper | 1 |
| 10 | Furnace | 1 |
| 11 | Sand | 8 |
| 12 | Spruce Chest | 36 |
| 13 | Spruce Button | 1 |
| 14, 15 | Water Bucket | 1 each |
| 16 | Crusher | 1 |
| 17 | Charger | 1 |
| 18 | Lever | 1 |
| 19 | Cactus | 1 |
| 20 | Sugar Canes | 7 |
| 21 | Spruce Sapling | 6 |
| 22, 23 | Coal | 64 each |
| 33 | EEPROM (Lua BIOS) | 1 |
| 34 | Redstone Card (Tier 1) | 1 |
| 35 | Hard Disk Drive (Tier 2) (2MB) | 1 |
| 36 | Central Processing Unit (CPU) (Tier 2) | 1 |
| 37 | Memory (Tier 2) | 1 |
| 43 | Diamond Pickaxe (spare; equipped when the tool breaks or is missing) | 1 |
| 44 | Leave empty (marks the Genesis robot) | — |

Slots 33–37 go into the base computer during the build. **The hard drive in slot 35
becomes the master copy for the whole lineage:** the base computer copies it onto every
new robot's drive and every new computer's drive. Give it OpenOS and this repo's files,
the same as the robot's own drive.

### Boot

Nothing in this repo starts `robot.lua` at boot. Set that up on the drives yourself, for
example with a `/home/.shrc` that runs `robot`. The drive copy carries it to every copy.

### Placement

Place the robot on flat, open ground facing **east**. Its block becomes the corner of the
base, which extends 9 blocks ahead of it (east) and 16 blocks to its left (north). The
quarry covers 32 × 32 blocks east and north of the corner, from bedrock up to world
y = 55. Chests stack 6 high and the robot travels up to 7 blocks above the floor, so
leave the space above clear. Its four copies go 32 blocks north, east, south and west of
the corner, at the same height.

Facing east is what makes the N/E/S/W labels match the real compass. The robot only
knows directions relative to how it was placed, so a Genesis robot facing another way
builds the same base, rotated.

Base layout, relative to the corner (x = east, z = north, y = 1 is the robot's start
level, the floor is y = 0). These are the code's own coordinates, so z counts north,
unlike Minecraft's F3 screen, where z counts south:

| Position | What's there |
|---|---|
| x = 0, z = 0, 1, 3, 4, 6, 7 | Chest wall, 6 high. The bottom 3 chests at z = 0 are the storage chests; the rest are overflow |
| (5,1,0), (6,1,0) | Coal Generators |
| (4..7,1,1), (5,2,1) | Leadstone Fluxducts |
| (4,1,2) | Charger, with a lever on top |
| (4,1,3) | Where the robot parks to charge |
| (5,1,2) / (5,2,2) | Hopper, with the Crusher on top |
| (6,1,2) | Electronics Assembler |
| (7,1,2) | Base computer, with a button on top |
| (2,2,2) | Furnace, raised one block so the robot can reach it from below |
| z = 6–8 | Sand with sugarcane and cactus, water at (4,1,7), (5,1,7), (6,1,7) |
| (4,1,12) | Spruce tree, planted on dirt |
| (4,·,4) | Mine shaft into the quarry |

## Getting and updating the code

`pull_repo.lua` downloads every file listed in `manifest.txt` from this repo's `main`
branch into `/home`. It needs an Internet Card. To get it onto a robot the first time:

```
wget -f https://raw.githubusercontent.com/theflaminghat/self-replicating-cellular-automata/refs/heads/main/pull_repo.lua /home/pull_repo.lua
```

After that, run `pull_repo` to update. A file is only overwritten when its download
succeeds. To add or remove a file, edit `manifest.txt`.

## Checking on a robot

The robot writes its progress and decisions to files in `/home`:

| File | What it holds |
|---|---|
| `quarry_progress.txt` | Where the quarry stopped, so it resumes after a reboot |
| `replication.txt` | Copies built so far, and whether one is assembling or waiting to be sent |
| `build_status.txt` | Why the last assembly did or didn't start, with each part's have/need count |
| `furnace_plan.txt` | What the furnace decided to smelt last time, and why |

## Files

| File | What it does |
|---|---|
| `robot.lua` | Entry point: runs `scheduler.lua` on a robot, `computer_controller.lua` on a computer |
| `scheduler.lua` | The startup sequence and the main loop |
| `computer_controller.lua` | The base computer: copies drives and BIOS, starts the assembler |
| `common.lua` | Shared code: movement, inventory, base layout, materials planning |
| `recipes.lua` | Every crafting, smelting, crushing and filling recipe |
| `building.lua`, `mining.lua`, `quarry.lua` | Build the base, dig the shaft, run the quarry |
| `inventory.lua` | Sort the robot's inventory into the storage and overflow chests |
| `farm_*.lua` | The spruce, sugarcane and cactus farms |
| `crafting.lua`, `furnace_add.lua`, `furnace_take.lua` | Autocrafting and smelting |
| `fill_generators.lua`, `fill_buckets.lua` | Fuel the generators, fill water buckets |
| `build_robot.lua`, `take_robot.lua`, `dispatch.lua` | Assemble, collect and send out a copy |
| `returning.lua`, `stasis.lua` | Go home and charge |
| `pull_repo.lua`, `manifest.txt` | Download and update the code |
| `test_*.lua` | Run one real state in-game, starting from the charging spot |
| `diag_*.lua` | In-game diagnostics |

The tests drive the real robot in-game; they aren't unit tests.

## Settings

| Setting | Where | Default | What it does |
|---|---|---|---|
| `start_from_stasis` | `scheduler.lua` | `false` | Skip building and the first mining run, for a robot already parked at its charger |
| `QUARRY_CEILING_Y` | `common.lua` | 55 | World y where the quarry stops climbing |
| `BEDROCK_LAYER_Y` | `common.lua` | 2 | World y of the lowest layer above bedrock, used to work out the robot's depth |
| `DIAMOND_BELOW_Y` | `common.lua` | 17 | Below this world y, the robot crafts diamond pickaxes instead of iron |
| `RESOURCE_BUFFERS` | `common.lua` | Redstone 16, Gold Ore 6 | Extra stock on top of the computed need |

## Known issues

- **Nothing checks whether a spot is free.** The growth rule never aims two copies at
  the same grid cell, but a robot doesn't look before it bridges out. Terrain, a player's
  build, or a copy that failed partway can block a route.
- **About 1 layer in 8 of the quarry is left unmined,** as a floor for the flight limit
  (see [OpenComputers config](#opencomputers-config)).
- **Nothing in the repo starts the program at boot** (see [Boot](#boot)).
