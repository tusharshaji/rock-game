local RecipesConfig = {
	WoodenPickaxe = {
		DisplayName = "Wooden Pickaxe",
		Category = "Tools", -- drives the category grouping in MainUIController's inventory/crafting UI; items with no recipe (raw materials) fall back to "Resources" there
		ReqText = "4x Wood",
		Ingredients = { WoodItem = 4 },
		IsGear = true, -- Flags this as a tool/armor for death penalty
	},
	WoodenAxe = {
		DisplayName = "Wooden Axe",
		Category = "Tools",
		ReqText = "4x Wood",
		Ingredients = { WoodItem = 4 },
		IsGear = true,
	},
	StonePickaxe = {
		DisplayName = "Stone Pickaxe",
		Category = "Tools",
		ReqText = "2x Wood, 3x Stone",
		Ingredients = { WoodItem = 2, StoneItem = 3 },
		IsGear = true,
	},
	StoneAxe = {
		DisplayName = "Stone Axe",
		Category = "Tools",
		ReqText = "2x Wood, 3x Stone",
		Ingredients = { WoodItem = 2, StoneItem = 3 },
		IsGear = true,
	},
	IronPickaxe = {
		DisplayName = "Iron Pickaxe",
		Category = "Tools",
		ReqText = "2x Wood, 3x Iron Ingot",
		Ingredients = { WoodItem = 2, IronIngotItem = 3 },
		IsGear = true,
	},
	IronAxe = {
		DisplayName = "Iron Axe",
		Category = "Tools",
		ReqText = "2x Wood, 3x Iron Ingot",
		Ingredients = { WoodItem = 2, IronIngotItem = 3 },
		IsGear = true,
	},
	Bow = {
		DisplayName = "Bow",
		Category = "Tools",
		ReqText = "3x Wood, 3x Leaf",
		Ingredients = { WoodItem = 3, LeafItem = 3 },
		IsGear = true,
	},
	Arrow = {
		DisplayName = "Arrow (x5)",
		Category = "Tools",
		ReqText = "1x Wood, 1x Stone",
		Ingredients = { WoodItem = 1, StoneItem = 1 },
		YieldAmount = 5,
		-- No IsGear flag, so you don't lose arrows on death
	},
	LeafBag = {
		DisplayName = "Leaf Bag",
		Category = "Bags",
		ReqText = "6x Wood, 4x Leaf",
		Ingredients = { WoodItem = 6, LeafItem = 4 },
		IsGear = true,
		CapacityBonus = 100, -- added to max carry weight while owned; items with CapacityBonus are exempt from the death penalty, see InventoryManager
		EquipSlot = "Sack", -- shown in its own inventory slot instead of the generic list
	},
	IronBackpack = {
		DisplayName = "Iron Backpack",
		Category = "Bags",
		ReqText = "6x Hide, 4x Iron Ingot",
		Ingredients = { HideItem = 6, IronIngotItem = 4 },
		IsGear = true,
		CapacityBonus = 200, -- double the Plant Fiber Sack's capacity
		EquipSlot = "Sack",
	},
	WoodHelmet = {
		DisplayName = "Wood Helmet",
		Category = "Armor",
		ReqText = "4x Wood",
		Ingredients = { WoodItem = 4 },
		IsGear = true,
		ArmorSlot = "Helmet",
		DamageReduction = 0.06, -- full Wood set totals 30% reduction
	},
	WoodChestplate = {
		DisplayName = "Wood Chestplate",
		Category = "Armor",
		ReqText = "8x Wood",
		Ingredients = { WoodItem = 8 },
		IsGear = true,
		ArmorSlot = "Chest",
		DamageReduction = 0.15, -- the biggest single contribution
	},
	WoodLeggings = {
		DisplayName = "Wood Leggings",
		Category = "Armor",
		ReqText = "6x Wood",
		Ingredients = { WoodItem = 6 },
		IsGear = true,
		ArmorSlot = "Legs",
		DamageReduction = 0.09, -- in between helmet and chest
	},
	IronHelmet = {
		DisplayName = "Iron Helmet",
		Category = "Armor",
		ReqText = "4x Iron Ingot",
		Ingredients = { IronIngotItem = 4 },
		IsGear = true,
		ArmorSlot = "Helmet",
		DamageReduction = 0.08, -- full Iron set totals 40% reduction, the strongest of the three sets
	},
	IronChestplate = {
		DisplayName = "Iron Chestplate",
		Category = "Armor",
		ReqText = "8x Iron Ingot",
		Ingredients = { IronIngotItem = 8 },
		IsGear = true,
		ArmorSlot = "Chest",
		DamageReduction = 0.20,
	},
	IronLeggings = {
		DisplayName = "Iron Leggings",
		Category = "Armor",
		ReqText = "6x Iron Ingot",
		Ingredients = { IronIngotItem = 6 },
		IsGear = true,
		ArmorSlot = "Legs",
		DamageReduction = 0.12,
	},
	CactusHelmet = {
		DisplayName = "Cactus Helmet",
		Category = "Armor",
		ReqText = "4x Cactus",
		Ingredients = { CactusItem = 4 },
		IsGear = true,
		ArmorSlot = "Helmet",
		DamageReduction = 0.06, -- full Cactus set totals 30% reduction, same as Wood -- its distinct trait is DamageReflect instead
		DamageReflect = 4, -- flat damage (not a %), full Cactus set totals 20 reflected back at the attacker -- reduced by the ATTACKER's own armor same as any other hit (see ArmorManager.ApplyDamage); Admin Pickaxe is exempt from triggering this at all
	},
	CactusChestplate = {
		DisplayName = "Cactus Chestplate",
		Category = "Armor",
		ReqText = "8x Cactus",
		Ingredients = { CactusItem = 8 },
		IsGear = true,
		ArmorSlot = "Chest",
		DamageReduction = 0.18,
		DamageReflect = 12,
	},
	CactusLeggings = {
		DisplayName = "Cactus Leggings",
		Category = "Armor",
		ReqText = "6x Cactus",
		Ingredients = { CactusItem = 6 },
		IsGear = true,
		ArmorSlot = "Legs",
		DamageReduction = 0.06,
		DamageReflect = 4,
	},
	Furnace = {
		DisplayName = "Furnace",
		Category = "Placeables",
		ReqText = "10x Stone, 4x Coal",
		Ingredients = { StoneItem = 10, CoalItem = 4 },
		IsPlaceable = true, -- crafting it jumps straight to blueprint/placement mode instead of adding it to inventory, see DeployablePlacementManager + FurnaceManager
	},
	WoodBoat = {
		DisplayName = "Wood Boat",
		Category = "Placeables",
		ReqText = "5x Wood",
		Ingredients = { WoodItem = 5 },
		IsPlaceable = true, -- crafting it jumps straight to blueprint/placement mode instead of adding it to inventory, see DeployablePlacementManager + BoatManager
	},
}

return RecipesConfig
