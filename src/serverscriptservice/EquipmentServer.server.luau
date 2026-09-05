-- Script inside ServerScriptService / EquipmentServer
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local equipEvent = ReplicatedStorage:FindFirstChild("EquipHotbarTool") or Instance.new("RemoteEvent", ReplicatedStorage)
equipEvent.Name = "EquipHotbarTool"

local dropItemsFolder = ServerStorage:WaitForChild("DropItems")

equipEvent.OnServerEvent:Connect(function(player, itemName)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	-- Unequip current tools
	humanoid:UnequipTools()

	-- If an itemName was passed, equip the requested tool from ServerStorage
	if itemName and typeof(itemName) == "string" then
		local toolTemplate = dropItemsFolder:FindFirstChild(itemName)
		if toolTemplate and toolTemplate:IsA("Tool") then
			local equippedTool = toolTemplate:Clone()
			equippedTool.Parent = character
		end
	end
end)