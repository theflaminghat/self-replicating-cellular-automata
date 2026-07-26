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
      yield = 4,
      grid = { { label = "Spruce Wood Planks" }, nil, nil,
               { label = "Spruce Wood Planks" }, nil, nil,
               nil, nil, nil },
    },
    ["minecraft:torch"] = {
      yield = 4,
      grid = { "minecraft:coal",  nil, nil,
               "minecraft:stick", nil, nil,
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
      yield = 1,
      grid = { "minecraft:iron_ingot", nil,               "minecraft:iron_ingot",
               "minecraft:iron_ingot", { label = "Spruce Chest" }, "minecraft:iron_ingot",
               nil,                    "minecraft:iron_ingot", nil },
    },
    ["minecraft:stone_button"] = {
      yield = 1,
      grid = { "minecraft:stone", nil, nil,
               nil, nil, nil,
               nil, nil, nil },
    },
    ["minecraft:lever"] = {
      yield = 1,
      grid = { "minecraft:stick",       nil, nil,
               "minecraft:cobblestone", nil, nil,
               nil, nil, nil },
    },
    ["minecraft:iron_bars"] = {
      yield = 16,
      grid = { "minecraft:iron_ingot", "minecraft:iron_ingot", "minecraft:iron_ingot",
               "minecraft:iron_ingot", "minecraft:iron_ingot", "minecraft:iron_ingot",
               nil, nil, nil },
    },
    ["minecraft:diamond_pickaxe"] = {
      yield = 1,
      grid = { "minecraft:diamond", "minecraft:diamond", "minecraft:diamond",
               nil,                 "minecraft:stick",   nil,
               nil,                 "minecraft:stick",   nil },
    },
    ["minecraft:iron_pickaxe"] = {
      yield = 1,
      grid = { "minecraft:iron_ingot", "minecraft:iron_ingot", "minecraft:iron_ingot",
               nil,                    "minecraft:stick",      nil,
               nil,                    "minecraft:stick",      nil },
    },
    ["minecraft:stone_pickaxe"] = {
      yield = 1,
      grid = { "minecraft:cobblestone", "minecraft:cobblestone", "minecraft:cobblestone",
               nil,                     "minecraft:stick",       nil,
               nil,                     "minecraft:stick",       nil },
    },
    ["minecraft:wooden_pickaxe"] = {
      yield = 1,
      grid = { { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" },
               nil,                "minecraft:stick",  nil,
               nil,                "minecraft:stick",  nil },
    },
    ["minecraft:wooden_axe"] = {
      yield = 1,
      grid = { { label = "Spruce Wood Planks" }, { label = "Spruce Wood Planks" }, nil,
               { label = "Spruce Wood Planks" }, "minecraft:stick",  nil,
               nil,                "minecraft:stick",  nil },
    },

    ["oc:transistor"] = {
      result = { label = "Transistor" },
      yield = 8,
      grid = { "minecraft:iron_ingot",  "minecraft:iron_ingot", "minecraft:iron_ingot",
               { label = "Gold Nugget" }, "minecraft:paper",    { label = "Gold Nugget" },
               nil,                     "minecraft:redstone",   nil },
    },
    ["oc:alu"] = {
      result = { label = "Arithmetic Logic Unit (ALU)" },
      yield = 1,
      grid = { { label = "Iron Nugget" }, "minecraft:redstone",       { label = "Iron Nugget" },
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
      grid = { "minecraft:gold_ingot",   "minecraft:clay_ball", nil,
               { label = "Cactus Green" }, nil,                 nil,
               nil,                      nil,                   nil },
    },
    ["oc:microchip1"] = {
      result = { label = "Microchip (Tier 1)" },
      yield = 8,
      grid = { { label = "Iron Nugget" }, { label = "Iron Nugget" }, { label = "Iron Nugget" },
               "minecraft:redstone",      { label = "Transistor" },  "minecraft:redstone",
               { label = "Iron Nugget" }, { label = "Iron Nugget" }, { label = "Iron Nugget" } },
    },
    ["oc:microchip2"] = {
      result = { label = "Microchip (Tier 2)" },
      yield = 4,
      grid = { { label = "Gold Nugget" }, { label = "Gold Nugget" }, { label = "Gold Nugget" },
               "minecraft:redstone",      { label = "Transistor" },  "minecraft:redstone",
               { label = "Gold Nugget" }, { label = "Gold Nugget" }, { label = "Gold Nugget" } },
    },
    ["oc:microchip3"] = {
      result = { label = "Microchip (Tier 3)" },
      yield = 2,
      grid = { { label = "Diamond Nugget" }, { label = "Diamond Nugget" }, { label = "Diamond Nugget" },
               "minecraft:redstone",         { label = "Transistor" },     "minecraft:redstone",
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
               "minecraft:paper",         { label = "Microchip (Tier 1)" }, "minecraft:paper",
               { label = "Gold Nugget" }, "minecraft:redstone_torch",     { label = "Gold Nugget" } },
    },
    ["oc:case3"] = {
      result = { label = "Computer Case (Tier 3)" },
      yield = 1,
      grid = { "minecraft:diamond",  { label = "Microchip (Tier 3)" }, "minecraft:diamond",
               "minecraft:iron_bars", { label = "Spruce Chest" },        "minecraft:iron_bars",
               "minecraft:diamond",  { label = "Printed Circuit Board (PCB)" },
               "minecraft:diamond" },
    },
    ["oc:assembler"] = {
      result = { label = "Electronics Assembler" },
      yield = 1,
      grid = { "minecraft:iron_ingot", "minecraft:crafting_table",      "minecraft:iron_ingot",
               "minecraft:piston",     { label = "Microchip (Tier 2)" }, "minecraft:piston",
               "minecraft:iron_ingot", { label = "Printed Circuit Board (PCB)" },
               "minecraft:iron_ingot" },
    },
    ["oc:charger"] = {
      result = { label = "Charger" },
      yield = 1,
      grid = { "minecraft:iron_ingot", "minecraft:gold_ingot",          "minecraft:iron_ingot",
               { label = "Capacitor" }, { label = "Microchip (Tier 2)" }, { label = "Capacitor" },
               "minecraft:iron_ingot", { label = "Printed Circuit Board (PCB)" },
               "minecraft:iron_ingot" },
    },

    ["aa:iron_casing"] = {
      result = { label = "Iron Casing" },
      yield = 1,
      grid = { "minecraft:iron_ingot", "minecraft:stick",         "minecraft:iron_ingot",
               "minecraft:stick",      { label = "Black Quartz" }, "minecraft:stick",
               "minecraft:iron_ingot", "minecraft:stick",         "minecraft:iron_ingot" },
    },
    ["aa:coal_generator"] = {
      result = { label = "Coal Generator" },
      yield = 1,
      grid = { "minecraft:cobblestone", "minecraft:coal",          "minecraft:cobblestone",
               "minecraft:cobblestone", { label = "Iron Casing" },  "minecraft:cobblestone",
               "minecraft:cobblestone", "minecraft:coal",          "minecraft:cobblestone" },
    },
    ["td:leadstone_fluxduct"] = {
      result = { label = "Leadstone Fluxduct" },
      yield = 6,
      grid = { "minecraft:redstone",     "minecraft:redstone",  "minecraft:redstone",
               { label = "Lead Ingot" }, "minecraft:glass",     { label = "Lead Ingot" },
               "minecraft:redstone",     "minecraft:redstone",  "minecraft:redstone" },
    },
    ["xu2:crusher"] = {
      result = { label = "Crusher" },
      yield = 1,
      grid = { "minecraft:iron_ingot", "minecraft:piston",        "minecraft:iron_ingot",
               "minecraft:iron_ingot", { label = "Machine Block" }, "minecraft:iron_ingot",
               "minecraft:iron_ingot", "minecraft:piston",        "minecraft:iron_ingot" },
    },

    ["oc:inventory_upgrade"] = {
      result = { label = "Inventory Upgrade" },
      yield = 1,
      grid = { { label = "Spruce Wood Planks" }, "minecraft:hopper",           { label = "Spruce Wood Planks" },
               "minecraft:dropper",              { label = "Spruce Chest" },   "minecraft:piston",
               { label = "Microchip (Tier 1)" }, { label = "Spruce Wood Planks" }, nil },
    },

    ["oc:inventory_controller_upgrade"] = {
      result = { label = "Inventory Controller Upgrade" },
      yield = 1,
      grid = { "minecraft:gold_ingot",           { label = "Analyzer" },        "minecraft:gold_ingot",
               "minecraft:dropper",              { label = "Microchip (Tier 2)" }, "minecraft:piston",
               "minecraft:gold_ingot",           { label = "Printed Circuit Board (PCB)" }, "minecraft:gold_ingot" },
    },

    ["oc:solar_generator_upgrade"] = {
      result = { label = "Solar Generator Upgrade" },
      yield = 1,
      grid = { "minecraft:glass",                "minecraft:glass",             "minecraft:glass",
               { label = "Microchip (Tier 3)" }, { label = "Lapis Lazuli Block" }, "minecraft:iron_ingot",
               { label = "Printed Circuit Board (PCB)" }, "minecraft:iron_ingot", nil },
    },

    ["oc:crafting_upgrade"] = {
      result = { label = "Crafting Upgrade" },
      yield = 1,
      grid = { "minecraft:iron_ingot",           nil,                           "minecraft:iron_ingot",
               { label = "Microchip (Tier 1)" }, "minecraft:crafting_table",    { label = "Microchip (Tier 1)" },
               "minecraft:iron_ingot",           { label = "Printed Circuit Board (PCB)" }, "minecraft:iron_ingot" },
    },

    ["oc:generator_upgrade"] = {
      result = { label = "Generator Upgrade" },
      yield = 1,
      grid = { "minecraft:iron_ingot",           nil,                           "minecraft:iron_ingot",
               { label = "Microchip (Tier 1)" }, "minecraft:crafting_table",    { label = "Microchip (Tier 1)" },
               "minecraft:iron_ingot",           { label = "Printed Circuit Board (PCB)" }, "minecraft:iron_ingot" },
    },

    ["minecraft:lapis_block"] = {
      result = { label = "Lapis Lazuli Block" },
      yield = 1,
      grid = { "minecraft:lapis_lazuli", "minecraft:lapis_lazuli", "minecraft:lapis_lazuli",
               "minecraft:lapis_lazuli", "minecraft:lapis_lazuli", "minecraft:lapis_lazuli",
               "minecraft:lapis_lazuli", "minecraft:lapis_lazuli", "minecraft:lapis_lazuli" },
    },

    ["oc:analyzer"] = {
      result = { label = "Analyzer" },
      yield = 1,
      grid = { "minecraft:redstone_torch",    nil,                        nil,
               { label = "Transistor" },       { label = "Gold Nugget" },  nil,
               { label = "Printed Circuit Board (PCB)" }, { label = "Gold Nugget" }, nil },
    },

    ["oc:hdd2"] = {
      result = { label = "Hard Disk Drive (Tier 2) (2MB)" },
      yield = 1,
      grid = { { label = "Microchip (Tier 2)" }, { label = "Disk Platter" }, "minecraft:gold_ingot",
               { label = "Printed Circuit Board (PCB)" }, { label = "Disk Platter" }, "minecraft:piston",
               { label = "Microchip (Tier 2)" }, { label = "Disk Platter" }, "minecraft:gold_ingot" },
    },

    ["oc:memory2"] = {
      result = { label = "Memory (Tier 2)" },
      yield = 1,
      grid = { nil,                          nil,                    nil,
               { label = "Microchip (Tier 2)" }, "minecraft:iron_ingot", { label = "Microchip (Tier 2)" },
               nil,                          { label = "Printed Circuit Board (PCB)" }, nil },
    },

    ["oc:redstone_card1"] = {
      result = { label = "Redstone Card (Tier 1)" },
      yield = 1,
      grid = { nil,                          nil,                        nil,
               "minecraft:redstone_torch",   { label = "Microchip (Tier 1)" }, nil,
               nil,                          { label = "Card Base" },    nil },
    },

    ["oc:cpu3"] = {
      result = { label = "Central Processing Unit (CPU) (Tier 3)" },
      yield = 1,
      grid = { { label = "Diamond Nugget" },     "minecraft:redstone",           { label = "Diamond Nugget" },
               { label = "Microchip (Tier 3)" }, { label = "Control Unit" },      { label = "Microchip (Tier 3)" },
               { label = "Diamond Nugget" },     { label = "Arithmetic Logic Unit (ALU)" }, { label = "Diamond Nugget" } },
    },

    ["oc:cpu2"] = {
      result = { label = "Central Processing Unit (CPU) (Tier 2)" },
      yield = 1,
      grid = { { label = "Gold Nugget" },        "minecraft:redstone",           { label = "Gold Nugget" },
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
      grid = { "minecraft:iron_ingot",     { label = "Transistor" },                  "minecraft:iron_ingot",
               { label = "Gold Nugget" },   "minecraft:paper",                         { label = "Gold Nugget" },
               "minecraft:iron_ingot",      { label = "Printed Circuit Board (PCB)" }, "minecraft:iron_ingot" },
    },

    ["minecraft:diamond_nugget"] = {
      result = { label = "Diamond Nugget" },
      yield = 9,
      grid = { "minecraft:diamond", nil, nil,
               nil,                 nil, nil,
               nil,                 nil, nil },
    },

    ["oc:machine_block"] = {
      result = { label = "Machine Block" },
      yield = 1,
      grid = { "minecraft:iron_ingot", "minecraft:redstone",  "minecraft:iron_ingot",
               "minecraft:redstone",   { label = "Spruce Chest" }, "minecraft:redstone",
               "minecraft:iron_ingot", "minecraft:redstone",  "minecraft:iron_ingot" },
    },

    ["minecraft:crafting_table"] = {
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
      yield = 1,
      grid = { "minecraft:cobblestone", "minecraft:cobblestone", "minecraft:cobblestone",
               "minecraft:cobblestone", nil,                     "minecraft:cobblestone",
               "minecraft:cobblestone", "minecraft:redstone",    "minecraft:cobblestone" },
    },

    ["minecraft:iron_nugget"] = {
      result = { label = "Iron Nugget" },
      yield = 9,
      grid = { "minecraft:iron_ingot", nil, nil,
               nil,                    nil, nil,
               nil,                    nil, nil },
    },

    ["minecraft:gold_nugget"] = {
      result = { label = "Gold Nugget" },
      yield = 9,
      grid = { "minecraft:gold_ingot", nil, nil,
               nil,                    nil, nil,
               nil,                    nil, nil },
    },

    ["oc:control_unit"] = {
      result = { label = "Control Unit" },
      yield = 1,
      grid = { { label = "Gold Nugget" }, "minecraft:redstone",      { label = "Gold Nugget" },
               { label = "Transistor" },  { label = "Clock" },       { label = "Transistor" },
               { label = "Gold Nugget" }, { label = "Transistor" },  { label = "Gold Nugget" } },
    },

    ["oc:clock"] = {
      result = { label = "Clock" },
      yield = 1,
      grid = { nil,                    "minecraft:gold_ingot", nil,
               "minecraft:gold_ingot", "minecraft:redstone",   "minecraft:gold_ingot",
               nil,                    "minecraft:gold_ingot", nil },
    },

    ["minecraft:redstone_torch"] = {
      yield = 1,
      grid = { "minecraft:redstone", nil, nil,
               "minecraft:stick",    nil, nil,
               nil,                  nil, nil },
    },

    ["minecraft:paper"] = {
      result = { label = "Paper" },
      yield = 3,
      grid = { "minecraft:reeds", "minecraft:reeds", "minecraft:reeds",
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
      result = { name = "minecraft:gold_ingot", label = "Gold Ingot" },
      yield = 1,
      smelt = true,
      grid = { "minecraft:gold_ore", nil, nil,
               nil,                  nil, nil,
               nil,                  nil, nil },
    },

    ["minecraft:iron_ingot_smelt"] = {
      result = { name = "minecraft:iron_ingot", label = "Iron Ingot" },
      yield = 1,
      smelt = true,
      grid = { "minecraft:iron_ore", nil, nil,
               nil,                   nil, nil,
               nil,                   nil, nil },
    },

    ["minecraft:glass"] = {
      result = { label = "Glass" },
      yield = 1,
      smelt = true,
      grid = { "minecraft:sand", nil, nil,
               nil,              nil, nil,
               nil,              nil, nil },
    },

    -- The crusher grinds cobblestone into sand: 64 cobblestone -> 8 sand, i.e. 8
    -- cobblestone per sand. crush = true marks it a crusher recipe (handled by
    -- C.addToCrusher / C.takeFromHopper, not the crafting grid or the furnace).
    ["minecraft:sand"] = {
      result = { name = "minecraft:sand", label = "Sand" },
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
               "minecraft:cobblestone",           "minecraft:iron_ingot",           "minecraft:cobblestone",
               "minecraft:cobblestone",           "minecraft:redstone",             "minecraft:cobblestone" },
    },

    ["minecraft:bucket"] = {
      result = { label = "Bucket" },
      yield = 1,
      grid = { nil,                    nil,                    nil,
               "minecraft:iron_ingot", nil,                    "minecraft:iron_ingot",
               nil,                    "minecraft:iron_ingot", nil },
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
