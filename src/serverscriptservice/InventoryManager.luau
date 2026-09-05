local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

-- Force LevelManager to load on server boot so UpdateXP RemoteEvent exists instantly
task.spawn(function()
	local levelModule = ServerScriptService:WaitForChild("LevelManager", 5)
	if levelModule then require(levelModule) end
end)

-- Note: ArmorManager is NOT force-loaded from here (unlike LevelManager above) because
-- ArmorManager itself requires InventoryManager. Requiring it before this module has finished
-- loading throws "Requested module was required recursively". It's booted from PickupServer
-- instead, after InventoryManager has already fully finished loading there.

local RecipesConfig = require(ReplicatedStorage:WaitForChild("RecipesConfig"))
local PlayerDataManager = require(ServerScriptService:WaitForChild("PlayerDataManager"))

-- Timed wait, not an indefinite one: this module is required by nearly every other server system,
-- so if StarterItems is ever missing from ServerStorage an open-ended WaitForChild here would stop
-- InventoryManager from ever loading and take the whole game down with it. New players still get
-- GUARANTEED_STARTER_ITEMS below regardless of what (if anything) the folder holds.
local starterItemsFolder = ServerStorage:WaitForChild("StarterItems", 10)
local dropItemsFolder = ServerStorage:WaitForChild("DropItems")

-- Handed to every brand new player on top of whatever StarterItems contains. The Rock is the tool
-- the entire early game is gated behind -- without one a fresh player can't gather anything at
-- all -- so it's guaranteed here in code rather than depending on the Studio-side folder.
local GUARANTEED_STARTER_ITEMS = {
	Rock = 1,
}

local function getOrCreateRemote(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = ReplicatedStorage
	end
	return event
end

local updateEvent = getOrCreateRemote("UpdateInventory")
local requestEvent = getOrCreateRemote("RequestInventory")
local craftEvent = getOrCreateRemote("CraftItem")
local equipSackEvent = getOrCreateRemote("EquipSack")
local updateSackEvent = getOrCreateRemote("UpdateSack")
local reportHotbarEvent = getOrCreateRemote("ReportHotbar")

local InventoryManager = {}
local inventories = {}
local playerCapacities = {}
local equippedSack = {} -- [player] = itemName or nil -- only this one contributes CapacityBonus, not every owned sack
local loadedPlayers = {} -- [player] = true once their save has been loaded (or defaulted) this session
local hotbarCache = {} -- [player] = last-reported hotbar slots array (1-9, string or nil), kept fresh by reportHotbarEvent so a save always has a recent layout to write
local pendingHotbarRestore = {} -- [player] = saved hotbar array waiting to be sent to the client on their first sync
local pendingArmorRestore = {} -- [player] = saved { Helmet=, Chest=, Legs= } table, consumed once by ArmorManager
local pendingXPRestore = {} -- [player] = saved XP number, consumed once by LevelManager
local pendingHungerRestore = {} -- [player] = saved hunger number, consumed once by HungerManager

local DEFAULT_MAX_WEIGHT = 50

-- Self-healing: if the equipped sack was lost (death, dropped, etc.), clear it here rather than
-- coordinating with every removal path. Returns the still-valid equipped sack's itemName, or nil.
local function getEquippedSackName(player)
	local itemName = equippedSack[player]
	if not itemName then return nil end

	local inv = inventories[player]
	if not inv or (inv[itemName] or 0) < 1 then
		equippedSack[player] = nil
		return nil
	end
	return itemName
end

local function getCapacityBonus(player)
	local itemName = getEquippedSackName(player)
	if not itemName then return 0 end
	local recipe = RecipesConfig[itemName]
	return (recipe and recipe.CapacityBonus) or 0
end

local function getPlayerCapacity(player)
	local base = playerCapacities[player] or DEFAULT_MAX_WEIGHT
	return base + getCapacityBonus(player)
end

local function getItemWeight(itemName)
	local template = dropItemsFolder:FindFirstChild(itemName)
	if template then
		return template:GetAttribute("Weight") or 1
	end
	return 1
end

local BACKPACK_VISUAL_NAME = "EquippedBackpackVisual"

-- Clones/removes a worn-on-the-back visual to match the currently equipped sack. Purely cosmetic
-- (server-side so it replicates to everyone), independent of the weight/capacity logic. Handles
-- both a single-Part template and a multi-part Model template, welding every part of the clone
-- together (to whichever part is the anchor -- PrimaryPart if set, else the first one found) so
-- it stays in one piece regardless of how the sack model is built.
local function updateBackpackVisual(player)
	local character = player.Character
	if not character then return end

	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not torso then return end

	local sackName = getEquippedSackName(player)
	local existing = character:FindFirstChild(BACKPACK_VISUAL_NAME)

	if sackName and not existing then
		local template = dropItemsFolder:FindFirstChild(sackName)
		if not template then return end

		local clone = template:Clone()
		clone.Name = BACKPACK_VISUAL_NAME

		local parts = {}
		if clone:IsA("BasePart") then
			table.insert(parts, clone)
		else
			for _, descendant in ipairs(clone:GetDescendants()) do
				if descendant:IsA("BasePart") then
					table.insert(parts, descendant)
				end
			end
		end

		local anchorPart = clone:IsA("Model") and (clone.PrimaryPart or parts[1]) or clone
		if not anchorPart then
			clone:Destroy()
			return
		end

		-- Sits just behind the torso, same facing as the torso itself (no extra rotation --
		-- that's what made the original sack appear worn backwards). Nudge the offset per-item
		-- if a new sack model needs positioning differently.
		clone:PivotTo(torso.CFrame * CFrame.new(0, 0, 0.6))
		clone.Parent = character

		for _, part in ipairs(parts) do
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.Massless = true
			if part ~= anchorPart then
				local innerWeld = Instance.new("WeldConstraint")
				innerWeld.Part0 = anchorPart
				innerWeld.Part1 = part
				innerWeld.Parent = part
			end
		end

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = anchorPart
		weld.Parent = anchorPart
	elseif not sackName and existing then
		existing:Destroy()
	end
end

function InventoryManager.GetCurrentWeight(player)
	local inv = inventories[player]
	if not inv then return 0 end

	local totalWeight = 0
	for itemName, count in pairs(inv) do
		totalWeight += (getItemWeight(itemName) * count)
	end
	return totalWeight
end

-- Loads this player's save (if any) on first access this session, populating inventory,
-- equipped sack, and the pending hotbar layout together. Falls back to the StarterItems default
-- if there's no save (new player, or the load failed -- e.g. DataStores disabled in Studio).
-- Yields the first time it runs for a player (DataStore call); a no-op every time after.
local function ensurePlayerDataLoaded(player)
	if loadedPlayers[player] then return end
	loadedPlayers[player] = true

	local saved = PlayerDataManager.Load(player)
	if saved and saved.inventory then
		inventories[player] = saved.inventory
		equippedSack[player] = saved.equippedSack
		pendingHotbarRestore[player] = saved.hotbar
		pendingArmorRestore[player] = saved.armor
		pendingXPRestore[player] = saved.xp
		pendingHungerRestore[player] = saved.hunger
	else
		local inv = {}
		if starterItemsFolder then
			for _, item in ipairs(starterItemsFolder:GetChildren()) do
				inv[item.Name] = (inv[item.Name] or 0) + 1
			end
		end
		-- Top up rather than add: if StarterItems already grants one of these, the player gets
		-- that amount, not that amount plus another.
		for itemName, amount in pairs(GUARANTEED_STARTER_ITEMS) do
			inv[itemName] = math.max(inv[itemName] or 0, amount)
		end
		inventories[player] = inv
	end
end

local function getInventory(player)
	ensurePlayerDataLoaded(player)
	return inventories[player]
end

function InventoryManager.GetInventory(player)
	return getInventory(player)
end

function InventoryManager.GetEquippedSackName(player)
	return getEquippedSackName(player)
end

-- Consumed once by ArmorManager/LevelManager/HungerManager on join, each pulling only its own
-- slice of the save. getInventory(player) forces ensurePlayerDataLoaded to finish first (yielding
-- on the DataStore call the first time only), so no matter which of the three modules asks first,
-- the same load isn't repeated and the data is always ready by the time it's read.
function InventoryManager.ConsumePendingArmorRestore(player)
	getInventory(player)
	local data = pendingArmorRestore[player]
	pendingArmorRestore[player] = nil
	return data
end

function InventoryManager.ConsumePendingXPRestore(player)
	getInventory(player)
	local data = pendingXPRestore[player]
	pendingXPRestore[player] = nil
	return data
end

function InventoryManager.ConsumePendingHungerRestore(player)
	getInventory(player)
	local data = pendingHungerRestore[player]
	pendingHungerRestore[player] = nil
	return data
end

-- Admin-only: grants an item straight into the inventory, bypassing the normal weight-capacity
-- check entirely (see AdminManager.server.luau, which is the actual access-control gate).
function InventoryManager.AdminGiveItem(player, itemName, amount)
	amount = amount or 1
	local inv = getInventory(player)
	inv[itemName] = (inv[itemName] or 0) + amount
	updateEvent:FireClient(player, inv, InventoryManager.GetCurrentWeight(player), getPlayerCapacity(player))
end

function InventoryManager.SetCapacity(player, newCapacity)
	playerCapacities[player] = newCapacity
	updateEvent:FireClient(player, inventories[player], InventoryManager.GetCurrentWeight(player), getPlayerCapacity(player))
end

function InventoryManager.AddItem(player, itemName, amount)
	amount = amount or 1
	local inv = getInventory(player)
	local itemWeight = getItemWeight(itemName) * amount
	local currentWeight = InventoryManager.GetCurrentWeight(player)
	local maxWeight = getPlayerCapacity(player)

	if currentWeight + itemWeight > maxWeight then
		return false
	end

	inv[itemName] = (inv[itemName] or 0) + amount
	-- Recompute capacity here rather than reusing the pre-add "maxWeight" above: if the item
	-- just added is itself capacity-granting (e.g. the Plant Fiber Sack), the client needs the
	-- new post-add value, not the stale pre-add one.
	updateEvent:FireClient(player, inv, InventoryManager.GetCurrentWeight(player), getPlayerCapacity(player))
	local changedRecipe = RecipesConfig[itemName]
	if changedRecipe and changedRecipe.EquipSlot == "Sack" then
		updateBackpackVisual(player)
		updateSackEvent:FireClient(player, getEquippedSackName(player)) -- self-heals if this was the equipped one and it's now gone
	end
	return true
end

function InventoryManager.RemoveItem(player, itemName, amount)
	amount = amount or 1
	local inv = getInventory(player)
	if not inv[itemName] or inv[itemName] < amount then
		return false
	end

	inv[itemName] -= amount
	if inv[itemName] <= 0 then
		inv[itemName] = nil
	end

	updateEvent:FireClient(player, inv, InventoryManager.GetCurrentWeight(player), getPlayerCapacity(player))
	local changedRecipe = RecipesConfig[itemName]
	if changedRecipe and changedRecipe.EquipSlot == "Sack" then
		updateBackpackVisual(player)
		updateSackEvent:FireClient(player, getEquippedSackName(player)) -- self-heals if this was the equipped one and it's now gone
	end
	return true
end

local function hasIngredients(inv, ingredients)
	for ingredient, needed in pairs(ingredients) do
		if (inv[ingredient] or 0) < needed then
			return false
		end
	end
	return true
end

local function consumeIngredients(player, ingredients)
	for ingredient, needed in pairs(ingredients) do
		InventoryManager.RemoveItem(player, ingredient, needed)
	end
end

craftEvent.OnServerEvent:Connect(function(player, recipeName)
	local recipe = RecipesConfig[recipeName]
	if not recipe then return end

	local inv = getInventory(player)
	if not hasIngredients(inv, recipe.Ingredients) then return end

	if recipe.IsPlaceable then
		-- Required lazily (not at this module's top level) since DeployablePlacementManager itself
		-- requires InventoryManager back -- see the matching note on the LevelManager lookup below.
		local deployableModule = ServerScriptService:FindFirstChild("DeployablePlacementManager")
		if not deployableModule then return end
		local DeployablePlacementManager = require(deployableModule)

		-- Only one blueprint pending at a time -- otherwise crafting a second placeable while one
		-- is still being placed would silently overwrite (and leak the refund data for) the first.
		if DeployablePlacementManager.HasPending(player) then return end

		consumeIngredients(player, recipe.Ingredients)
		-- Goes straight to the blueprint/placement phase instead of into the inventory -- see
		-- DeployablePlacementManager for the cancel-and-refund flow.
		DeployablePlacementManager.BeginPlacement(player, recipeName, recipe.Ingredients)
		return
	end

	consumeIngredients(player, recipe.Ingredients)

	local yieldAmount = recipe.YieldAmount or 1
	InventoryManager.AddItem(player, recipeName, yieldAmount)

	if recipe.XPReward then
		local levelManagerModule = ServerScriptService:FindFirstChild("LevelManager")
		if levelManagerModule then
			local LevelManager = require(levelManagerModule)
			LevelManager.AddXP(player, recipe.XPReward)
		end
	end
end)

-- Handlers
requestEvent.OnServerEvent:Connect(function(player)
	updateEvent:FireClient(player, getInventory(player), InventoryManager.GetCurrentWeight(player), getPlayerCapacity(player))
	updateSackEvent:FireClient(player, getEquippedSackName(player))
end)

-- The hotbar is purely client-side state (see HotbarState.luau) -- the server only knows about it
-- via whatever the client last reported here, kept fresh so a save always has a recent layout.
-- Sanitized to a plain 1-9 array of strings/nils so a modified client can't stuff arbitrary data
-- in here that later gets written to the DataStore.
reportHotbarEvent.OnServerEvent:Connect(function(player, slots)
	if typeof(slots) ~= "table" then return end
	local clean = {}
	for i = 1, 9 do
		local value = slots[i]
		if typeof(value) == "string" then
			clean[i] = value
		end
	end
	hotbarCache[player] = clean
end)

-- Only the equipped sack contributes CapacityBonus -- owning several no longer stacks. itemName ==
-- nil unequips whatever's currently worn.
equipSackEvent.OnServerEvent:Connect(function(player, itemName)
	if itemName == nil then
		equippedSack[player] = nil
	elseif typeof(itemName) == "string" then
		local recipe = RecipesConfig[itemName]
		if not recipe or recipe.EquipSlot ~= "Sack" then return end

		local inv = getInventory(player)
		if (inv[itemName] or 0) < 1 then return end

		equippedSack[player] = itemName
	else
		return
	end

	updateSackEvent:FireClient(player, equippedSack[player])
	updateBackpackVisual(player)
	-- Capacity just changed -- push a fresh inventory sync so the client's weight bar updates too.
	updateEvent:FireClient(player, getInventory(player), InventoryManager.GetCurrentWeight(player), getPlayerCapacity(player))
end)

local MEAT_DROP_AMOUNT = 2
local DEATH_DROP_FRACTION = 0.7

-- DEATH_DROP_FRACTION of a recipe's ingredient cost, rounded to the nearest whole number, never
-- below 1 (e.g. at 0.7: 3 -> 2, 4 -> 3, 8 -> 6, 1 -> 1).
local function deathDropAmount(neededAmount)
	return math.max(1, math.floor(neededAmount * DEATH_DROP_FRACTION + 0.5))
end

local DEATH_DROP_RADIUS = 6
local DEATH_DROP_MIN_HEIGHT = 1 -- studs above whatever the raycast hits, so drops don't clip into the ground
local DEATH_DROP_MAX_HEIGHT = 12 -- upper end of that range -- drops spawn partway up and fall/scatter via physics instead of always landing flush on the surface

-- Picks a random point within DEATH_DROP_RADIUS of originPosition, then raycasts straight down
-- to find the actual ground/terrain there (rather than assuming it's flat like the player's own
-- position), so drops fall from somewhere between DEATH_DROP_MIN_HEIGHT and DEATH_DROP_MAX_HEIGHT
-- above that surface instead of floating, clipping into it, or always sitting flush on it.
-- excludeInstances lets the caller keep the raycast from hitting the character or previously
-- dropped items instead of real ground.
local function getGroundDropPosition(originPosition, excludeInstances)
	local angle = math.random() * math.pi * 2
	local distance = math.random() * DEATH_DROP_RADIUS
	local horizontalOffset = Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	local horizontalPosition = originPosition + horizontalOffset
	local heightAboveGround = DEATH_DROP_MIN_HEIGHT + math.random() * (DEATH_DROP_MAX_HEIGHT - DEATH_DROP_MIN_HEIGHT)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = excludeInstances or {}
	raycastParams.IgnoreWater = true

	local rayOrigin = horizontalPosition + Vector3.new(0, 100, 0)
	local result = workspace:Raycast(rayOrigin, Vector3.new(0, -500, 0), raycastParams)

	if result then
		return result.Position + Vector3.new(0, heightAboveGround, 0)
	end

	-- No ground found below this spot (e.g. over a gap) -- fall back to the player's own height
	return horizontalPosition + Vector3.new(0, heightAboveGround, 0)
end

-- Spawns a physical, pickupable world drop. Mirrors PickupServer's drop logic (template clone if
-- one exists in DropItems, generic Part fallback otherwise, welded together and unanchored so
-- multi-part items fall/settle as one piece instead of floating or scattering). Returns the drop
-- so the caller can add it to excludeInstances before spawning the next one.
local function spawnDrop(character, itemName, amount, excludeInstances)
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local template = dropItemsFolder:FindFirstChild(itemName)
	local drop = template and template:Clone() or Instance.new("Part")
	if not template then
		drop.Name = itemName
		drop.Size = Vector3.new(1, 1, 1)
	end

	local spawnPosition = getGroundDropPosition(rootPart.Position, excludeInstances)
	drop:PivotTo(CFrame.new(spawnPosition))
	drop:SetAttribute("ItemName", itemName)
	drop:SetAttribute("Amount", amount)
	CollectionService:AddTag(drop, "Pickupable")

	local parts = {}
	if drop:IsA("BasePart") then
		table.insert(parts, drop)
	else
		for _, child in ipairs(drop:GetDescendants()) do
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
		end
	end

	local anchorPart
	if drop:IsA("Model") then
		anchorPart = drop.PrimaryPart or parts[1]
	else
		anchorPart = drop
	end

	for _, part in ipairs(parts) do
		part.CanTouch = false
		part.Anchored = false
		part.CanCollide = true
		if anchorPart and part ~= anchorPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchorPart
			weld.Part1 = part
			weld.Parent = part
		end
	end

	drop.Parent = workspace
	return drop
end

local function applyDeathPenalty(player, character)
	local inv = InventoryManager.GetInventory(player)
	if not inv then return end

	local itemsToRemove = {}
	local materialsToDrop = {}

	-- 1. Scan inventory for gear to lose (this already covers worn armor too -- ArmorManager
	-- doesn't remove equipped items from the inventory table, it just tracks which slot they're
	-- in, so equipped gear shows up here exactly the same as gear sitting in the backpack).
	for itemName, count in pairs(inv) do
		local recipe = RecipesConfig[itemName]

		-- Gear, excluding capacity items (the Plant Fiber Sack), which is always kept
		if recipe and recipe.IsGear and not recipe.CapacityBonus then
			itemsToRemove[itemName] = count

			for ingredient, neededAmount in pairs(recipe.Ingredients) do
				local dropAmount = deathDropAmount(neededAmount) * count
				materialsToDrop[ingredient] = (materialsToDrop[ingredient] or 0) + dropAmount
			end
		end
	end

	-- 2. Remove the lost gear from inventory. Raw resources are never touched here.
	for itemName, count in pairs(itemsToRemove) do
		InventoryManager.RemoveItem(player, itemName, count)
	end

	-- 3. Drop the material fraction (and some meat) into the world around the death spot, rather
	-- than refunding it straight back into the player's own inventory. Each unit is its own
	-- separate drop (Amount 1) rather than one stack, so they land individually scattered instead
	-- of piled as a single pickup. excludeInstances grows as items are dropped so later ones
	-- raycast past earlier drops onto the real ground beneath.
	if character then
		local excludeInstances = { character }

		local function dropIndividually(itemName, amount)
			for _ = 1, amount do
				local drop = spawnDrop(character, itemName, 1, excludeInstances)
				if drop then table.insert(excludeInstances, drop) end
			end
		end

		for ingredient, amount in pairs(materialsToDrop) do
			dropIndividually(ingredient, amount)
		end

		dropIndividually("MeatItem", MEAT_DROP_AMOUNT)
	end
end

-- Gathers everything worth saving for this player into one table for PlayerDataManager.Save.
-- Armor/XP/hunger live in their own modules, so they're pulled in lazily here (required at
-- save-time, not at this module's own top level) the same way LevelManager is required inside the
-- craft handler above -- avoids a circular require, since ArmorManager and HungerManager both
-- require InventoryManager themselves.
local function buildSaveData(player)
	local armorState = nil
	local armorModule = ServerScriptService:FindFirstChild("ArmorManager")
	if armorModule then
		armorState = require(armorModule).GetEquipped(player)
	end

	local xp = nil
	local levelModule = ServerScriptService:FindFirstChild("LevelManager")
	if levelModule then
		xp = require(levelModule).GetXP(player)
	end

	local hunger = nil
	local hungerModule = ServerScriptService:FindFirstChild("HungerManager")
	if hungerModule then
		hunger = require(hungerModule).GetHunger(player)
	end

	return {
		inventory = inventories[player],
		equippedSack = equippedSack[player],
		hotbar = hotbarCache[player],
		armor = armorState,
		xp = xp,
		hunger = hunger,
	}
end

local function savePlayerData(player)
	-- Nothing to save if they never actually loaded/initialized this session (e.g. left instantly).
	if not loadedPlayers[player] then return end
	PlayerDataManager.Save(player, buildSaveData(player))
end

Players.PlayerAdded:Connect(function(player)
	-- Initialize inventory data immediately (this is also where the DataStore load happens, see
	-- ensurePlayerDataLoaded)
	local initialInv = getInventory(player)

	player.CharacterAdded:Connect(function(character)
		-- Sync UI the moment their character physically spawns. hotbarToRestore is only non-nil
		-- immediately after a load with a saved layout -- MainUIController applies it and skips
		-- its normal "auto-assign starter items" behavior when present. Consumed once so it
		-- doesn't get re-sent (and re-applied, stomping manual changes) on later syncs.
		local hotbarToRestore = pendingHotbarRestore[player]
		pendingHotbarRestore[player] = nil

		updateEvent:FireClient(player, getInventory(player), InventoryManager.GetCurrentWeight(player), getPlayerCapacity(player), hotbarToRestore)
		updateSackEvent:FireClient(player, getEquippedSackName(player))
		updateBackpackVisual(player)

		-- Listen for death
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.Died:Connect(function()
			applyDeathPenalty(player, character)
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)

	inventories[player] = nil
	playerCapacities[player] = nil
	equippedSack[player] = nil
	loadedPlayers[player] = nil
	hotbarCache[player] = nil
	pendingHotbarRestore[player] = nil
	pendingArmorRestore[player] = nil
	pendingXPRestore[player] = nil
	pendingHungerRestore[player] = nil
end)

-- Saves everyone still connected when the whole server is shutting down (e.g. a deploy), not just
-- players leaving individually -- otherwise anyone still in the server at that moment loses
-- whatever's changed since their last individual save.
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerData(player)
	end
end)

return InventoryManager