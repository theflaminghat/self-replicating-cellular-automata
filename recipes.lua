-- recipes.lua
-- Crafting and smelting recipe definitions, split out of common.lua.
-- Each recipe: result (optional label), yield, and a 9-slot grid (item ids or
-- { label = ... } tables, nil for empty). Recipes with smelt = true are
-- furnace recipes (single input); the rest are crafting-grid recipes.
--
-- Returns a function that populates C.RECIPES on the shared common table.

return function(C)

  C.RECIPES = {

    ["minecraft:stick"] = {
      result = { label = "Stick" },
      yield = 4,
      grid = { { label = "Spruce Wood Planks" }, nil, nil,
               { label = "Spruce Wood Planks" }, nil, nil,
               nil, nil, nil },
    },
    ["minecraft:torch"] = {
      yield = 4,
      grid = { { label = "Coal" },  nil, nil,
               { label = "Stick" }, nil, nil,
               nil, nil, nil },
    },
    ["minecraft:chest"] = {
      -- 8 spruce planks craft a Spruce Chest in this pack; the live item is matched
      -- by its label, so declare the result so tracking/crafting recognize it.
      result = { label = "Spruce Chest" },
      yield = 1,
      grid = { { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" },
               { label = "Spruce Wood Planks" }, nil,                { label = "Spruce Wood Planks" },
               { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" } },
    },
    ["minecraft:hopper"] = {
      result = { label = "Hopper" },
      yield = 1,
      grid = { { label = "Iron Ingot" }, nil,               { label = "Iron Ingot" },
               { label = "Iron Ingot" }, { label = "Spruce Chest" }, { label = "Iron Ingot" },
               nil,                    { label = "Iron Ingot" }, nil },
    },
    ["minecraft:stone_button"] = {
      yield = 1,
      grid = { { label = "Stone" }, nil, nil,
               nil, nil, nil,
               nil, nil, nil },
    },
    ["minecraft:lever"] = {
      yield = 1,
      grid = { { label = "Stick" },       nil, nil,
               "minecraft:cobblestone", nil, nil,
               nil, nil, nil },
    },
    ["minecraft:iron_bars"] = {
      result = { label = "Iron Bars" },
      yield = 16,
      grid = { { label = "Iron Ingot" }, { label = "Iron Ingot" }, { label = "Iron Ingot" },
               { label = "Iron Ingot" }, { label = "Iron Ingot" }, { label = "Iron Ingot" },
               nil, nil, nil },
    },
    ["minecraft:diamond_pickaxe"] = {
      yield = 1,
      grid = { { label = "Diamond" }, { label = "Diamond" }, { label = "Diamond" },
               nil,                 { label = "Stick" },   nil,
               nil,                 { label = "Stick" },   nil },
    },
    ["minecraft:iron_pickaxe"] = {
      yield = 1,
      grid = { { label = "Iron Ingot" }, { label = "Iron Ingot" }, { label = "Iron Ingot" },
               nil,                    { label = "Stick" },      nil,
               nil,                    { label = "Stick" },      nil },
    },
    ["minecraft:stone_pickaxe"] = {
      yield = 1,
      grid = { "minecraft:cobblestone", "minecraft:cobblestone", "minecraft:cobblestone",
               nil,                     { label = "Stick" },       nil,
               nil,                     { label = "Stick" },       nil },
    },
    ["minecraft:wooden_pickaxe"] = {
      yield = 1,
      grid = { { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" },
               nil,                { label = "Stick" },  nil,
               nil,                { label = "Stick" },  nil },
    },
    ["minecraft:wooden_axe"] = {
      yield = 1,
      grid = { { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" }, nil,
               { label = "Spruce Wood Planks" }, { label = "Stick" },  nil,
               nil,                { label = "Stick" },  nil },
    },

    ["oc:transistor"] = {
      result = { label = "Transistor" },
      yield = 8,
      grid = { { label = "Iron Ingot" },  { label = "Iron Ingot" }, { label = "Iron Ingot" },
               { label = "Gold Nugget" }, { label = "Paper" },    { label = "Gold Nugget" },
               nil,                     { label = "Redstone" },   nil },
    },
    ["oc:alu"] = {
      result = { label = "Arithmetic Logic Unit (ALU)" },
      yield = 1,
      grid = { { label = "Iron Nugget" }, { label = "Redstone" },       { label = "Iron Nugget" },
               { label = "Transistor" },  { label = "Microchip (Tier 1)" }, { label = "Transistor" },
               { label = "Iron Nugget" }, { label = "Transistor" },   { label = "Iron Nugget" } },
    },
    ["oc:disk_platter"] = {
      result = { label = "Disk Platter" },
      yield = 1,
      grid = { nil,                       { label = "Iron Nugget" }, nil,
               { label = "Iron Nugget" }, nil,                       { label = "Iron Nugget" },
               nil,                       { label = "Iron Nugget" }, nil },
    },
    ["oc:raw_circuit_board"] = {
      result = { label = "Raw Circuit Board" },
      yield = 8,
      grid = { { label = "Gold Ingot" },   { label = "Clay" }, nil,
               { label = "Cactus Green" }, nil,                 nil,
               nil,                      nil,                   nil },
    },
    ["oc:microchip1"] = {
      result = { label = "Microchip (Tier 1)" },
      yield = 8,
      grid = { { label = "Iron Nugget" }, { label = "Iron Nugget" }, { label = "Iron Nugget" },
               { label = "Redstone" },      { label = "Transistor" },  { label = "Redstone" },
               { label = "Iron Nugget" }, { label = "Iron Nugget" }, { label = "Iron Nugget" } },
    },
    ["oc:microchip2"] = {
      result = { label = "Microchip (Tier 2)" },
      yield = 4,
      grid = { { label = "Gold Nugget" }, { label = "Gold Nugget" }, { label = "Gold Nugget" },
               { label = "Redstone" },      { label = "Transistor" },  { label = "Redstone" },
               { label = "Gold Nugget" }, { label = "Gold Nugget" }, { label = "Gold Nugget" } },
    },
    ["oc:microchip3"] = {
      result = { label = "Microchip (Tier 3)" },
      yield = 2,
      grid = { { label = "Diamond Nugget" }, { label = "Diamond Nugget" }, { label = "Diamond Nugget" },
               { label = "Redstone" },         { label = "Transistor" },     { label = "Redstone" },
               { label = "Diamond Nugget" }, { label = "Diamond Nugget" }, { label = "Diamond Nugget" } },
    },
    ["oc:memory3"] = {
      result = { label = "Memory (Tier 3)" },
      yield = 1,
      grid = { nil, nil, nil,
               { label = "Microchip (Tier 3)" }, { label = "Iron Nugget" },
               { label = "Microchip (Tier 3)" },
               nil, { label = "Printed Circuit Board (PCB)" }, nil },
    },
    ["oc:eeprom"] = {
      result = { label = "EEPROM" },
      yield = 1,
      grid = { { label = "Gold Nugget" }, { label = "Transistor" },       { label = "Gold Nugget" },
               { label = "Paper" },         { label = "Microchip (Tier 1)" }, { label = "Paper" },
               { label = "Gold Nugget" }, { label = "Redstone Torch" },     { label = "Gold Nugget" } },
    },
    ["oc:case3"] = {
      result = { label = "Computer Case (Tier 3)" },
      yield = 1,
      grid = { { label = "Diamond" },  { label = "Microchip (Tier 3)" }, { label = "Diamond" },
               { label = "Iron Bars" }, { label = "Spruce Chest" },        { label = "Iron Bars" },
               { label = "Diamond" },  { label = "Printed Circuit Board (PCB)" },
               { label = "Diamond" } },
    },
    ["oc:assembler"] = {
      result = { label = "Electronics Assembler" },
      yield = 1,
      grid = { { label = "Iron Ingot" }, { label = "Crafting Table" },      { label = "Iron Ingot" },
               { label = "Piston" },     { label = "Microchip (Tier 2)" }, { label = "Piston" },
               { label = "Iron Ingot" }, { label = "Printed Circuit Board (PCB)" },
               { label = "Iron Ingot" } },
    },
    ["oc:charger"] = {
      result = { label = "Charger" },
      yield = 1,
      grid = { { label = "Iron Ingot" }, { label = "Gold Ingot" },          { label = "Iron Ingot" },
               { label = "Capacitor" }, { label = "Microchip (Tier 2)" }, { label = "Capacitor" },
               { label = "Iron Ingot" }, { label = "Printed Circuit Board (PCB)" },
               { label = "Iron Ingot" } },
    },

    ["aa:iron_casing"] = {
      result = { label = "Iron Casing" },
      yield = 1,
      grid = { { label = "Iron Ingot" }, { label = "Stick" },         { label = "Iron Ingot" },
               { label = "Stick" },      { label = "Black Quartz" }, { label = "Stick" },
               { label = "Iron Ingot" }, { label = "Stick" },         { label = "Iron Ingot" } },
    },
    ["aa:coal_generator"] = {
      result = { label = "Coal Generator" },
      yield = 1,
      grid = { "minecraft:cobblestone", { label = "Coal" },          "minecraft:cobblestone",
               "minecraft:cobblestone", { label = "Iron Casing" },  "minecraft:cobblestone",
               "minecraft:cobblestone", { label = "Coal" },          "minecraft:cobblestone" },
    },
    ["td:leadstone_fluxduct"] = {
      result = { label = "Leadstone Fluxduct" },
      yield = 6,
      grid = { { label = "Redstone" },     { label = "Redstone" },  { label = "Redstone" },
               { label = "Lead Ingot" }, { label = "Glass" },     { label = "Lead Ingot" },
               { label = "Redstone" },     { label = "Redstone" },  { label = "Redstone" } },
    },
    ["xu2:crusher"] = {
      result = { label = "Crusher" },
      yield = 1,
      grid = { { label = "Iron Ingot" }, { label = "Piston" },        { label = "Iron Ingot" },
               { label = "Iron Ingot" }, { label = "Machine Block" }, { label = "Iron Ingot" },
               { label = "Iron Ingot" }, { label = "Piston" },        { label = "Iron Ingot" } },
    },

    ["oc:inventory_upgrade"] = {
      result = { label = "Inventory Upgrade" },
      yield = 1,
      grid = { { label = "Spruce Wood Planks" }, { label = "Hopper" },           { label = "Spruce Wood Planks" },
               { label = "Dropper" },              { label = "Spruce Chest" },   { label = "Piston" },
               { label = "Microchip (Tier 1)" }, { label = "Spruce Wood Planks" }, nil },
    },

    ["oc:inventory_controller_upgrade"] = {
      result = { label = "Inventory Controller Upgrade" },
      yield = 1,
      grid = { { label = "Gold Ingot" },           { label = "Analyzer" },        { label = "Gold Ingot" },
               { label = "Dropper" },              { label = "Microchip (Tier 2)" }, { label = "Piston" },
               { label = "Gold Ingot" },           { label = "Printed Circuit Board (PCB)" }, { label = "Gold Ingot" } },
    },

    ["oc:solar_generator_upgrade"] = {
      result = { label = "Solar Generator Upgrade" },
      yield = 1,
      grid = { { label = "Glass" },                { label = "Glass" },             { label = "Glass" },
               { label = "Microchip (Tier 3)" }, { label = "Lapis Lazuli Block" }, { label = "Iron Ingot" },
               { label = "Printed Circuit Board (PCB)" }, { label = "Iron Ingot" }, nil },
    },

    ["oc:crafting_upgrade"] = {
      result = { label = "Crafting Upgrade" },
      yield = 1,
      grid = { { label = "Iron Ingot" },           nil,                           { label = "Iron Ingot" },
               { label = "Microchip (Tier 1)" }, { label = "Crafting Table" },    { label = "Microchip (Tier 1)" },
               { label = "Iron Ingot" },           { label = "Printed Circuit Board (PCB)" }, { label = "Iron Ingot" } },
    },

    ["oc:generator_upgrade"] = {
      result = { label = "Generator Upgrade" },
      yield = 1,
      grid = { { label = "Iron Ingot" },           nil,                           { label = "Iron Ingot" },
               { label = "Microchip (Tier 1)" }, { label = "Crafting Table" },    { label = "Microchip (Tier 1)" },
               { label = "Iron Ingot" },           { label = "Printed Circuit Board (PCB)" }, { label = "Iron Ingot" } },
    },

    ["minecraft:lapis_block"] = {
      result = { label = "Lapis Lazuli Block" },
      yield = 1,
      -- Match lapis by its display label, not an item id: in the OpenComputers MC
      -- versions the lapis item is minecraft:dye (damage 4), so the id
      -- "minecraft:lapis_lazuli" never matches the mined item and it was being
      -- dumped to overflow instead of kept/crafted. The label is stable.
      grid = { { label = "Lapis Lazuli" }, { label = "Lapis Lazuli" }, { label = "Lapis Lazuli" },
               { label = "Lapis Lazuli" }, { label = "Lapis Lazuli" }, { label = "Lapis Lazuli" },
               { label = "Lapis Lazuli" }, { label = "Lapis Lazuli" }, { label = "Lapis Lazuli" } },
    },

    ["oc:analyzer"] = {
      result = { label = "Analyzer" },
      yield = 1,
      grid = { { label = "Redstone Torch" },    nil,                        nil,
               { label = "Transistor" },       { label = "Gold Nugget" },  nil,
               { label = "Printed Circuit Board (PCB)" }, { label = "Gold Nugget" }, nil },
    },

    ["oc:hdd2"] = {
      result = { label = "Hard Disk Drive (Tier 2) (2MB)" },
      yield = 1,
      grid = { { label = "Microchip (Tier 2)" }, { label = "Disk Platter" }, { label = "Gold Ingot" },
               { label = "Printed Circuit Board (PCB)" }, { label = "Disk Platter" }, { label = "Piston" },
               { label = "Microchip (Tier 2)" }, { label = "Disk Platter" }, { label = "Gold Ingot" } },
    },

    ["oc:memory2"] = {
      result = { label = "Memory (Tier 2)" },
      yield = 1,
      grid = { nil,                          nil,                    nil,
               { label = "Microchip (Tier 2)" }, { label = "Iron Ingot" }, { label = "Microchip (Tier 2)" },
               nil,                          { label = "Printed Circuit Board (PCB)" }, nil },
    },

    ["oc:redstone_card1"] = {
      result = { label = "Redstone Card (Tier 1)" },
      yield = 1,
      grid = { nil,                          nil,                        nil,
               { label = "Redstone Torch" },   { label = "Microchip (Tier 1)" }, nil,
               nil,                          { label = "Card Base" },    nil },
    },

    ["oc:cpu3"] = {
      result = { label = "Central Processing Unit (CPU) (Tier 3)" },
      yield = 1,
      grid = { { label = "Diamond Nugget" },     { label = "Redstone" },           { label = "Diamond Nugget" },
               { label = "Microchip (Tier 3)" }, { label = "Control Unit" },      { label = "Microchip (Tier 3)" },
               { label = "Diamond Nugget" },     { label = "Arithmetic Logic Unit (ALU)" }, { label = "Diamond Nugget" } },
    },

    ["oc:cpu2"] = {
      result = { label = "Central Processing Unit (CPU) (Tier 2)" },
      yield = 1,
      grid = { { label = "Gold Nugget" },        { label = "Redstone" },           { label = "Gold Nugget" },
               { label = "Microchip (Tier 2)" }, { label = "Control Unit" },      { label = "Microchip (Tier 2)" },
               { label = "Gold Nugget" },        { label = "Arithmetic Logic Unit (ALU)" }, { label = "Gold Nugget" } },
    },

    ["oc:card_base"] = {
      result = { label = "Card Base" },
      yield = 1,
      grid = { { label = "Iron Nugget" }, nil,                                        nil,
               { label = "Iron Nugget" }, { label = "Printed Circuit Board (PCB)" },  nil,
               { label = "Iron Nugget" }, { label = "Gold Nugget" },                  nil },
    },

    ["oc:capacitor"] = {
      result = { label = "Capacitor" },
      yield = 1,
      grid = { { label = "Iron Ingot" },     { label = "Transistor" },                  { label = "Iron Ingot" },
               { label = "Gold Nugget" },   { label = "Paper" },                         { label = "Gold Nugget" },
               { label = "Iron Ingot" },      { label = "Printed Circuit Board (PCB)" }, { label = "Iron Ingot" } },
    },

    ["minecraft:diamond_nugget"] = {
      result = { label = "Diamond Nugget" },
      yield = 9,
      grid = { { label = "Diamond" }, nil, nil,
               nil,                 nil, nil,
               nil,                 nil, nil },
    },

    ["oc:machine_block"] = {
      result = { label = "Machine Block" },
      yield = 1,
      grid = { { label = "Iron Ingot" }, { label = "Redstone" },  { label = "Iron Ingot" },
               { label = "Redstone" },   { label = "Spruce Chest" }, { label = "Redstone" },
               { label = "Iron Ingot" }, { label = "Redstone" },  { label = "Iron Ingot" } },
    },

    ["minecraft:crafting_table"] = {
      result = { label = "Crafting Table" },
      yield = 1,
      grid = { { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" }, nil,
               { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" }, nil,
               nil,                              nil,                              nil },
    },

    ["furnace"] = {
      result = { label = "Furnace" },
      yield = 1,
      grid = { "minecraft:cobblestone", "minecraft:cobblestone", "minecraft:cobblestone",
               "minecraft:cobblestone", nil,                     "minecraft:cobblestone",
               "minecraft:cobblestone", "minecraft:cobblestone", "minecraft:cobblestone" },
    },

    ["minecraft:dropper"] = {
      result = { label = "Dropper" },
      yield = 1,
      grid = { "minecraft:cobblestone", "minecraft:cobblestone", "minecraft:cobblestone",
               "minecraft:cobblestone", nil,                     "minecraft:cobblestone",
               "minecraft:cobblestone", { label = "Redstone" },    "minecraft:cobblestone" },
    },

    ["minecraft:iron_nugget"] = {
      result = { label = "Iron Nugget" },
      yield = 9,
      grid = { { label = "Iron Ingot" }, nil, nil,
               nil,                    nil, nil,
               nil,                    nil, nil },
    },

    ["minecraft:gold_nugget"] = {
      result = { label = "Gold Nugget" },
      yield = 9,
      grid = { { label = "Gold Ingot" }, nil, nil,
               nil,                    nil, nil,
               nil,                    nil, nil },
    },

    ["oc:control_unit"] = {
      result = { label = "Control Unit" },
      yield = 1,
      grid = { { label = "Gold Nugget" }, { label = "Redstone" },      { label = "Gold Nugget" },
               { label = "Transistor" },  { label = "Clock" },       { label = "Transistor" },
               { label = "Gold Nugget" }, { label = "Transistor" },  { label = "Gold Nugget" } },
    },

    ["oc:clock"] = {
      result = { label = "Clock" },
      yield = 1,
      grid = { nil,                    { label = "Gold Ingot" }, nil,
               { label = "Gold Ingot" }, { label = "Redstone" },   { label = "Gold Ingot" },
               nil,                    { label = "Gold Ingot" }, nil },
    },

    ["minecraft:redstone_torch"] = {
      result = { label = "Redstone Torch" },
      yield = 1,
      grid = { { label = "Redstone" }, nil, nil,
               { label = "Stick" },    nil, nil,
               nil,                  nil, nil },
    },

    ["minecraft:paper"] = {
      result = { label = "Paper" },
      yield = 3,
      grid = { { label = "Sugar Canes" }, { label = "Sugar Canes" }, { label = "Sugar Canes" },
               nil,               nil,               nil,
               nil,               nil,               nil },
    },

    -- Smelting recipes: a single input smelted into the result. Represented with a
    -- one-cell grid plus a smelt marker so the base-material expander walks them
    -- and any future smelting step can distinguish them from crafting-grid recipes.
    ["oc:printed_circuit_board"] = {
      result = { label = "Printed Circuit Board (PCB)" },
      yield = 1,
      smelt = true,
      grid = { { label = "Raw Circuit Board" }, nil, nil,
               nil,                              nil, nil,
               nil,                              nil, nil },
    },

    ["minecraft:iron_ingot_lead"] = {
      result = { label = "Lead Ingot" },
      yield = 1,
      smelt = true,
      grid = { { label = "Lead Ore" }, nil, nil,
               nil,                    nil, nil,
               nil,                    nil, nil },
    },

    ["minecraft:gold_ingot_smelt"] = {
      result = { label = "Gold Ingot" },
      yield = 1,
      smelt = true,
      grid = { { label = "Gold Ore" }, nil, nil,
               nil,                  nil, nil,
               nil,                  nil, nil },
    },

    ["minecraft:iron_ingot_smelt"] = {
      result = { label = "Iron Ingot" },
      yield = 1,
      smelt = true,
      grid = { { label = "Iron Ore" }, nil, nil,
               nil,                   nil, nil,
               nil,                   nil, nil },
    },

    ["minecraft:glass"] = {
      result = { label = "Glass" },
      yield = 1,
      smelt = true,
      grid = { { label = "Sand" }, nil, nil,
               nil,              nil, nil,
               nil,              nil, nil },
    },

    -- Black Quartz Ore smelts 1:1 into Black Quartz, the center ingredient of the
    -- Iron Casing (aa:iron_casing) -> Coal Generator chain. Adding it lets the base-
    -- material expander walk the coal generator down to a mineable ore instead of an
    -- uncraftable dead end.
    ["aa:black_quartz_smelt"] = {
      result = { label = "Black Quartz" },
      yield = 1,
      smelt = true,
      grid = { { label = "Black Quartz Ore" }, nil, nil,
               nil,                            nil, nil,
               nil,                            nil, nil },
    },

    -- The crusher grinds cobblestone into sand: 64 cobblestone -> 8 sand, i.e. 8
    -- cobblestone per sand. crush = true marks it a crusher recipe (handled by
    -- C.addToCrusher / C.takeFromHopper, not the crafting grid or the furnace).
    ["minecraft:sand"] = {
      result = { label = "Sand" },
      yield = 1,
      crush = true,
      grid = { "minecraft:cobblestone", "minecraft:cobblestone", "minecraft:cobblestone",
               "minecraft:cobblestone", "minecraft:cobblestone", "minecraft:cobblestone",
               "minecraft:cobblestone", "minecraft:cobblestone", nil },
    },

    ["minecraft:piston"] = {
      result = { label = "Piston" },
      yield = 1,
      grid = { { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" },
               "minecraft:cobblestone",           { label = "Iron Ingot" },           "minecraft:cobblestone",
               "minecraft:cobblestone",           { label = "Redstone" },             "minecraft:cobblestone" },
    },

    ["minecraft:bucket"] = {
      result = { label = "Bucket" },
      yield = 1,
      grid = { nil,                    nil,                    nil,
               { label = "Iron Ingot" }, nil,                    { label = "Iron Ingot" },
               nil,                    { label = "Iron Ingot" }, nil },
    },

    ["minecraft:cactus_green"] = {
      result = { label = "Cactus Green" },
      yield = 1,
      smelt = true,
      grid = { { label = "Cactus" }, nil, nil,
               nil,      nil, nil,
               nil,      nil, nil },
    },

    ["minecraft:planks_spruce"] = {
      result = { label = "Spruce Wood Planks" },
      yield = 4,
      grid = { { label = "Spruce Wood" }, nil, nil,
               nil,                      nil, nil,
               nil,                      nil, nil },
    },

    ["minecraft:stone"] = {
      result = { label = "Stone" },
      yield = 1,
      smelt = true,
      grid = { "minecraft:cobblestone", nil, nil,
               nil,                     nil, nil,
               nil,                     nil, nil },
    },
  }

  return C.RECIPES
end
