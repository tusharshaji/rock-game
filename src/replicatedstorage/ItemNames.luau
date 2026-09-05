-- Single source of truth for turning an internal item name (the name of the ServerStorage
-- DropItems template, which is what the inventory table, hotbar and every remote pass around)
-- into the human-readable name shown in UI. Every place that puts an item name on screen should
-- go through here rather than displaying the raw name.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RecipesConfig = require(ReplicatedStorage:WaitForChild("RecipesConfig"))

local ItemNames = {}

-- Raw resources have no RecipesConfig entry, and so no DisplayName. Rather than duplicating the
-- full item list here, anything unlisted is prettified from its internal name: the trailing
-- "Item" suffix is dropped and camelCase boundaries become spaces -- "IronIngotItem" -> "Iron
-- Ingot", "RawIronItem" -> "Raw Iron", "Rock" -> "Rock". Add an entry to OVERRIDES only for the
-- items where that rule gives the wrong answer.
local OVERRIDES = {}

local cache = {}

local function prettify(itemName)
	local base = itemName:gsub("Item$", "")
	-- Insert a space at every lower->upper transition, plus inside acronym runs followed by a
	-- word ("XPItem" -> "XP Item"), then collapse any doubled spacing.
	base = base:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
	base = base:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
	return base ~= "" and base or itemName
end

-- Returns the display name for itemName, e.g. "WoodenPickaxe" -> "Wooden Pickaxe". Safe to call
-- with nil or an unknown item; nil gives "" and an unknown item gives its prettified own name.
function ItemNames.Get(itemName)
	if typeof(itemName) ~= "string" or itemName == "" then return "" end

	local cached = cache[itemName]
	if cached then return cached end

	local recipe = RecipesConfig[itemName]
	local resolved = OVERRIDES[itemName] or (recipe and recipe.DisplayName) or prettify(itemName)

	cache[itemName] = resolved
	return resolved
end

return ItemNames
