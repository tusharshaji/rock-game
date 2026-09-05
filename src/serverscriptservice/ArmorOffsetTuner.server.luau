local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ArmorManager = require(ServerScriptService:WaitForChild("ArmorManager"))

-- Mirrors AdminManager.server.luau's whitelist -- this is the real access-control gate; the
-- client copy (in ArmorOffsetTuner.client.luau) only decides whether to show the tuning panel.
local ADMIN_USERNAMES = {
	GoneFishingAgain = true,
	tushar123tushar = true,
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

local tuneEvent = getOrCreateRemote("TuneArmorOffset")

-- components = { x, y, z, rx, ry, rz } (studs / degrees) or nil/omitted to clear the live override
-- and fall back to whatever's hardcoded in ArmorManager's ITEM_OFFSET_OVERRIDES.
tuneEvent.OnServerEvent:Connect(function(player, itemName, partName, components)
	if not ADMIN_USERNAMES[player.Name] then return end
	if typeof(itemName) ~= "string" or itemName == "" then return end
	if typeof(partName) ~= "string" or partName == "" then return end

	if components == nil then
		ArmorManager.ClearLiveOffset(itemName)
	else
		if typeof(components) ~= "table" then return end

		local x = tonumber(components.x) or 0
		local y = tonumber(components.y) or 0
		local z = tonumber(components.z) or 0
		local rx = tonumber(components.rx) or 0
		local ry = tonumber(components.ry) or 0
		local rz = tonumber(components.rz) or 0

		local offset = CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
		ArmorManager.SetLiveOffset(itemName, partName, offset)
	end

	-- Re-applies immediately so whichever slot the admin currently has that item equipped in
	-- previews the change without needing to unequip/re-equip.
	ArmorManager.RefreshVisuals(player)
end)
