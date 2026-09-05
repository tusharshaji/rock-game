local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function getOrCreateRemote(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = ReplicatedStorage
	end
	return event
end

local pickupEvent = getOrCreateRemote("PickupItem")
local dropEvent = getOrCreateRemote("DropItem")

local InventoryManager = require(ServerScriptService:WaitForChild("InventoryManager"))
local dropItemsFolder = ServerStorage:WaitForChild("DropItems")

-- Force ArmorManager and HungerManager to load on server boot so their remotes (EquipArmor/
-- UpdateArmor/RequestArmor, UpdateHunger/EatItem) exist instantly. Done here (after InventoryManager
-- above has already fully finished loading) rather than from inside InventoryManager itself, since
-- both of them require InventoryManager back -- doing it from InventoryManager's own top level
-- causes a recursive-require error. HungerManager itself force-loads LevelManager the same way.
require(ServerScriptService:WaitForChild("ArmorManager"))
require(ServerScriptService:WaitForChild("HungerManager"))

local PICKUP_RANGE = 10 -- studs

local function getItemPart(item)
	if item:IsA("BasePart") then
		return item
	elseif item:IsA("Model") then
		return item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

-- ===== PICKUP ITEM =====
pickupEvent.OnServerEvent:Connect(function(player, item)
	if typeof(item) ~= "Instance" then return end
	if not item:IsDescendantOf(workspace) then return end
	if not CollectionService:HasTag(item, "Pickupable") then return end

	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local part = getItemPart(item)
	if not part then return end

	local distance = (part.Position - rootPart.Position).Magnitude
	if distance > PICKUP_RANGE then return end

	local itemName = item:GetAttribute("ItemName")
	local amount = item:GetAttribute("Amount") or 1
	if not itemName then return end

	local success = InventoryManager.AddItem(player, itemName, amount)
	if success then
		item:Destroy()
	end
end)

-- ===== DROP ITEM =====
dropEvent.OnServerEvent:Connect(function(player, itemName)
	if typeof(itemName) ~= "string" then return end

	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local template = dropItemsFolder:FindFirstChild(itemName)
	if not template then return end

	local success = InventoryManager.RemoveItem(player, itemName, 1)
	if not success then return end

	local spawnPosition = rootPart.Position + (rootPart.CFrame.LookVector * 4) + Vector3.new(0, 0.5, 0)
	local drop = template:Clone()

	drop:PivotTo(CFrame.new(spawnPosition))
	drop:SetAttribute("ItemName", itemName)
	drop:SetAttribute("Amount", 1)
	CollectionService:AddTag(drop, "Pickupable")

	-- Give it real physics so it falls and settles on the ground instead of floating where it
	-- spawned. Multi-part templates (e.g. armor built from several welded-apart pieces, like
	-- WoodChestplate) get welded together for the fall so they land as one piece instead of
	-- scattering -- this dropped clone is disposable anyway; equipping always clones fresh
	-- from the ServerStorage template, never from a dropped instance.
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
		anchorPart = drop.PrimaryPart or parts[1] -- fall back to the first part if PrimaryPart isn't set
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
end)