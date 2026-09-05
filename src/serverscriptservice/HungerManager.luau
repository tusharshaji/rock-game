local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Force LevelManager to load on server boot so UpdateXP RemoteEvent exists instantly
task.spawn(function()
	local levelModule = ServerScriptService:WaitForChild("LevelManager", 5)
	if levelModule then require(levelModule) end
end)

-- Note: ArmorManager is NOT force-loaded from here (unlike LevelManager above) because
-- ArmorManager itself requires InventoryManager. Requiring it before this module has finished
-- loading throws "Requested module was required recursively". It's booted from PickupServer
-- instead, after InventoryManager has already fully finished loading there.

local function getOrCreateRemote(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = ReplicatedStorage
	end
	return event
end

local updateHungerEvent = getOrCreateRemote("UpdateHunger")
local eatItemEvent = getOrCreateRemote("EatItem")

local InventoryManager = require(ServerScriptService:WaitForChild("InventoryManager"))

local HungerManager = {}

local MAX_HUNGER = 100
local DRAIN_INTERVAL = 30 -- seconds per 1 hunger point lost
local STARVE_DAMAGE_INTERVAL = 5 -- seconds per 1 HP lost while hunger is at 0

-- How much hunger each food item restores when eaten. Cooked food (see FurnaceManager) is worth
-- more than raw, as an incentive to actually use the furnace.
local FOOD_VALUES = {
	MeatItem = 10,
	CookedMeatItem = 25,
}

local playerHunger = {}

local function getHunger(player)
	if not playerHunger[player] then
		playerHunger[player] = MAX_HUNGER
	end
	return playerHunger[player]
end

local function setHunger(player, value)
	playerHunger[player] = math.clamp(value, 0, MAX_HUNGER)
	updateHungerEvent:FireClient(player, playerHunger[player], MAX_HUNGER)
end

function HungerManager.GetHunger(player)
	return getHunger(player)
end

eatItemEvent.OnServerEvent:Connect(function(player, itemName)
	if typeof(itemName) ~= "string" then return end
	local restoreAmount = FOOD_VALUES[itemName]
	if not restoreAmount then return end

	local success = InventoryManager.RemoveItem(player, itemName, 1)
	if not success then return end

	setHunger(player, getHunger(player) + restoreAmount)
end)

Players.PlayerAdded:Connect(function(player)
	-- Yields until InventoryManager's load finishes (once), same pattern as ArmorManager/LevelManager.
	local savedHunger = InventoryManager.ConsumePendingHungerRestore(player)
	playerHunger[player] = savedHunger or MAX_HUNGER

	player.CharacterAdded:Connect(function()
		setHunger(player, getHunger(player))
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	playerHunger[player] = nil
end)

-- Passive drain, plus slow starvation damage once hunger hits 0
task.spawn(function()
	local drainTimer = 0
	local starveTimer = 0
	while true do
		task.wait(1)
		drainTimer += 1
		starveTimer += 1

		if drainTimer >= DRAIN_INTERVAL then
			drainTimer = 0
			for _, player in ipairs(Players:GetPlayers()) do
				setHunger(player, getHunger(player) - 1)
			end
		end

		if starveTimer >= STARVE_DAMAGE_INTERVAL then
			starveTimer = 0
			for _, player in ipairs(Players:GetPlayers()) do
				if getHunger(player) <= 0 then
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						humanoid:TakeDamage(1)
					end
				end
			end
		end
	end
end)

return HungerManager
