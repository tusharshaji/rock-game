local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LevelManager = {}
local playerXP = {}

local function getOrCreateRemote(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = ReplicatedStorage
	end
	return event
end

local updateXpEvent = getOrCreateRemote("UpdateXP")

local XP_PER_LEVEL = 100 -- Base XP required per level

local function calculateLevelData(xp)
	xp = xp or 0
	local level = math.floor(xp / XP_PER_LEVEL) + 1
	local currentLevelXP = xp % XP_PER_LEVEL
	return level, currentLevelXP, XP_PER_LEVEL
end

function LevelManager.SendUpdate(player)
	local xp = playerXP[player] or 0
	local level, currentXP, requiredXP = calculateLevelData(xp)
	updateXpEvent:FireClient(player, level, currentXP, requiredXP)
end

function LevelManager.AddXP(player, amount)
	playerXP[player] = (playerXP[player] or 0) + amount
	LevelManager.SendUpdate(player)
end

function LevelManager.GetXP(player)
	return playerXP[player] or 0
end

Players.PlayerAdded:Connect(function(player)
	-- Required lazily (not at this module's top level) since InventoryManager's own save-time code
	-- requires LevelManager back -- see buildSaveData in InventoryManager.luau. By the time a
	-- player actually joins, both modules are already loaded, so this is just a cached lookup.
	local InventoryManager = require(ServerScriptService:WaitForChild("InventoryManager"))
	local savedXP = InventoryManager.ConsumePendingXPRestore(player)
	playerXP[player] = savedXP or 0

	task.wait(1)
	LevelManager.SendUpdate(player)
end)

Players.PlayerRemoving:Connect(function(player)
	playerXP[player] = nil
end)

return LevelManager