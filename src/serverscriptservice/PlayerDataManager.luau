local DataStoreService = game:GetService("DataStoreService")

-- Thin wrapper around DataStoreService, used by InventoryManager to load/save each player's
-- inventory, equipped sack, and hotbar layout. Bump the store name (e.g. "PlayerData_v2") if the
-- saved shape ever changes in a way that would break loading old data.
local PlayerDataManager = {}

local dataStore = DataStoreService:GetDataStore("PlayerData_v1")

local function keyFor(player)
	return "Player_" .. player.UserId
end

-- Returns the saved data table for this player, or nil if there's no save yet (or the load
-- failed -- e.g. DataStores aren't enabled in this Studio session). Yields.
function PlayerDataManager.Load(player)
	local success, result = pcall(function()
		return dataStore:GetAsync(keyFor(player))
	end)

	if success then
		return result
	end

	warn("PlayerDataManager: failed to load data for " .. player.Name .. " -- " .. tostring(result))
	return nil
end

-- Saves the given data table for this player. Returns true on success. Yields.
function PlayerDataManager.Save(player, data)
	local success, err = pcall(function()
		dataStore:SetAsync(keyFor(player), data)
	end)

	if not success then
		warn("PlayerDataManager: failed to save data for " .. player.Name .. " -- " .. tostring(err))
	end
	return success
end

return PlayerDataManager
