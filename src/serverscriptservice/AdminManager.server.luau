local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local InventoryManager = require(ServerScriptService:WaitForChild("InventoryManager"))

-- The real access-control boundary for the admin menu. AdminMenu.client.luau keeps its own copy of
-- this list purely to decide whether to show the button at all -- that copy is not trusted here.
local ADMIN_USERNAMES = {
	GoneFishingAgain = true,
	tushar123tushar = true,
}

local MAX_GIVE_AMOUNT = 1000

local adminGiveItemEvent = Instance.new("RemoteEvent")
adminGiveItemEvent.Name = "AdminGiveItem"
adminGiveItemEvent.Parent = ReplicatedStorage

adminGiveItemEvent.OnServerEvent:Connect(function(player, itemName, amount)
	if not ADMIN_USERNAMES[player.Name] then
		return
	end
	if typeof(itemName) ~= "string" then
		return
	end

	itemName = itemName:gsub("^%s+", ""):gsub("%s+$", "")
	if itemName == "" then
		return
	end

	amount = tonumber(amount) or 1
	amount = math.clamp(math.floor(amount), 1, MAX_GIVE_AMOUNT)

	InventoryManager.AdminGiveItem(player, itemName, amount)
end)
