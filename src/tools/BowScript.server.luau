local tool = script.Parent
local handle = tool:WaitForChild("Handle")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local inventoryModule = ServerScriptService:WaitForChild("InventoryManager", 10)
local InventoryManager = inventoryModule and require(inventoryModule) or nil
local armorModule = ServerScriptService:WaitForChild("ArmorManager", 10)
local ArmorManager = armorModule and require(armorModule) or nil
local dropItemsFolder = ServerStorage:WaitForChild("DropItems")

local fireEvent = tool:FindFirstChild("FireBowEvent")
if not fireEvent then
	fireEvent = Instance.new("RemoteEvent")
	fireEvent.Name = "FireBowEvent"
	fireEvent.Parent = tool
end

local ARROW_SPEED = 180
local COOLDOWN = 0.7
local debounce = false

fireEvent.OnServerEvent:Connect(function(player, targetPosition)
	if debounce then return end
	if typeof(targetPosition) ~= "Vector3" then return end

	local character = tool.Parent
	local playerCheck = Players:GetPlayerFromCharacter(character)
	if playerCheck ~= player then return end

	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart and not handle then return end

	local spawnPos = handle and handle.Position or (rootPart.Position + Vector3.new(0, 1, 0))

	if InventoryManager then
		local inv = InventoryManager.GetInventory(player)
		local arrowCount = inv["Arrow"] or 0

		if arrowCount > 0 then
			debounce = true
			InventoryManager.RemoveItem(player, "Arrow", 1)

			local arrowTemplate = dropItemsFolder:FindFirstChild("Arrow")
			local arrowClone = nil

			if arrowTemplate then
				arrowClone = arrowTemplate:Clone()
			else
				arrowClone = Instance.new("Part")
				arrowClone.Size = Vector3.new(0.3, 0.3, 2.5)
			end

			local direction = (targetPosition - spawnPos)
			if direction.Magnitude > 0 then
				direction = direction.Unit
			else
				direction = rootPart.CFrame.LookVector
			end

			if arrowClone:IsA("Model") then
				arrowClone:PivotTo(CFrame.new(spawnPos, spawnPos + direction))
				arrowClone.Parent = workspace
				if arrowClone.PrimaryPart then
					arrowClone.PrimaryPart.AssemblyLinearVelocity = direction * ARROW_SPEED
				else
					for _, part in ipairs(arrowClone:GetDescendants()) do
						if part:IsA("BasePart") then
							part.AssemblyLinearVelocity = direction * ARROW_SPEED
						end
					end
				end
			else
				arrowClone.CFrame = CFrame.new(spawnPos, spawnPos + direction)
				arrowClone.AssemblyLinearVelocity = direction * ARROW_SPEED
				arrowClone.Parent = workspace
			end

			local hasHit = false

			-- Arrow hit logic: Ensures it destroys instantly upon impact
			local function onArrowHit(hit)
				if hasHit then return end
				if hit.Parent ~= character and not hit:IsDescendantOf(character) then
					local hitSomethingValid = false

					-- 1. Check if it hit anything with a Humanoid (Players & Test Dummies)
					local humanoid = hit.Parent:FindFirstChildOfClass("Humanoid")
					if humanoid then
						local victim = Players:GetPlayerFromCharacter(hit.Parent)
						if victim and ArmorManager then
							ArmorManager.ApplyDamage(victim, humanoid, 25, player, tool)
						else
							humanoid:TakeDamage(25)
						end
						hitSomethingValid = true
					end

					-- 2. Check if it hit a Tagged Animal
					local targetAnimal = nil
					if CollectionService:HasTag(hit, "Animal") then
						targetAnimal = hit
					elseif hit.Parent and CollectionService:HasTag(hit.Parent, "Animal") then
						targetAnimal = hit.Parent
					end

					if targetAnimal then
						local currentHealth = targetAnimal:GetAttribute("Health") or 100
						targetAnimal:SetAttribute("Health", currentHealth - 25)
						hitSomethingValid = true
					end

					-- Destroy the arrow immediately upon hitting any valid target
					if hitSomethingValid then
						hasHit = true
						arrowClone:Destroy()
					end
				end
			end

			if arrowClone:IsA("Model") then
				for _, part in ipairs(arrowClone:GetDescendants()) do
					if part:IsA("BasePart") then
						part.Touched:Connect(onArrowHit)
					end
				end
			else
				arrowClone.Touched:Connect(onArrowHit)
			end

			task.delay(4, function()
				if arrowClone and arrowClone.Parent then
					arrowClone:Destroy()
				end
			end)

			task.wait(COOLDOWN)
			debounce = false
		end
	end
end)
