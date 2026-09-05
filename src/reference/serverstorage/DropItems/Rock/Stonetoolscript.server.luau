local tool = script.Parent
local handle = tool:WaitForChild("Handle")

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local levelModule = ServerScriptService:WaitForChild("LevelManager", 10)
local LevelManager = levelModule and require(levelModule) or nil
local dropItemsFolder = ServerStorage:WaitForChild("DropItems")
local hitSound = tool:FindFirstChild("BreakableHitSound") or handle:FindFirstChild("BreakableHitSound")

-- ===== SETTINGS (TIER 0 - STARTER TOOL) =====
local DAMAGE = 5                  
local TOOL_TIER = 0
local COOLDOWN = 0.8
local ATTACK_RANGE = 7
local ATTACK_ANGLE = 180
local SWING_ANIM_ID = "rbxassetid://126541900784445"
local HIT_TIMING = 0.35
-- ============================================

local debounce = false
local swingTrack = nil

tool.Equipped:Connect(function()
	for _, desc in ipairs(tool:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.CanCollide = false
		end
	end

	local character = tool.Parent
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)

	local anim = Instance.new("Animation")
	anim.AnimationId = SWING_ANIM_ID
	swingTrack = animator:LoadAnimation(anim)
	swingTrack.Priority = Enum.AnimationPriority.Action
end)

local function performAttack()
	local character = tool.Parent
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local originPos = rootPart.Position
	local forward = rootPart.CFrame.LookVector

	local hitCharacters = {}

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Humanoid") and obj.Health > 0 then
			local targetModel = obj.Parent
			if targetModel ~= character and not hitCharacters[targetModel] then
				local targetRoot = targetModel:FindFirstChild("HumanoidRootPart")
				if targetRoot then
					local toTarget = targetRoot.Position - originPos
					local distance = toTarget.Magnitude

					if distance <= ATTACK_RANGE and distance > 0 then
						local direction = toTarget.Unit
						local dot = forward:Dot(direction)
						local angleBetween = math.deg(math.acos(math.clamp(dot, -1, 1)))

						if angleBetween <= ATTACK_ANGLE / 2 then
							hitCharacters[targetModel] = true
							obj:TakeDamage(DAMAGE)
						end
					end
				end
			end
		end
	end

	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and obj:GetAttribute("Breakable") then
			local requiredTier = obj:GetAttribute("RequiredTier") or 0

			if TOOL_TIER >= requiredTier then
				local toTarget = obj.Position - originPos
				local distance = toTarget.Magnitude

				if distance <= ATTACK_RANGE and distance > 0 then
					local direction = toTarget.Unit
					local dot = forward:Dot(direction)
					local angleBetween = math.deg(math.acos(math.clamp(dot, -1, 1)))

					if angleBetween <= ATTACK_ANGLE / 2 then
						-- Play hit sound when successfully striking a breakable node
						if hitSound and hitSound:IsA("Sound") then
							hitSound:Play()
						end

						local maxHealth = obj:GetAttribute("MaxHealth") or 100
						local currentHealth = obj:GetAttribute("Health") or maxHealth

						currentHealth = math.max(0, currentHealth - DAMAGE)
						obj:SetAttribute("Health", currentHealth)

						if currentHealth <= 0 and not obj:GetAttribute("IsBreaking") then
							obj:SetAttribute("IsBreaking", true) 

							local player = Players:GetPlayerFromCharacter(character)
							if player and LevelManager then
								local xpReward = obj:GetAttribute("XPReward") or 10
								LevelManager.AddXP(player, xpReward)
							end

							local dropsToSpawn = {}
							local i = 1
							while obj:GetAttribute("Drop" .. i .. "_Name") do
								table.insert(dropsToSpawn, {
									Name = obj:GetAttribute("Drop" .. i .. "_Name"),
									Min = obj:GetAttribute("Drop" .. i .. "_Min") or 1,
									Max = obj:GetAttribute("Drop" .. i .. "_Max") or 1
								})
								i += 1
							end

							if #dropsToSpawn == 0 and obj:GetAttribute("DropName") then
								table.insert(dropsToSpawn, {
									Name = obj:GetAttribute("DropName"),
									Min = obj:GetAttribute("MinDrops") or 1,
									Max = obj:GetAttribute("MaxDrops") or 1
								})
							end

							for _, dropInfo in ipairs(dropsToSpawn) do
								local template = dropItemsFolder:FindFirstChild(dropInfo.Name)
								if template then
									local dropCount = math.random(dropInfo.Min, dropInfo.Max)
									for _ = 1, dropCount do
										local drop = template:Clone()
										local offset = Vector3.new(math.random(-15, 15) / 10, 2, math.random(-15, 15) / 10)

										drop:PivotTo(CFrame.new(obj.Position + offset))
										drop:SetAttribute("ItemName", dropInfo.Name)
										drop:SetAttribute("Amount", 1)
										CollectionService:AddTag(drop, "Pickupable")

										if drop:IsA("BasePart") then drop.CanTouch = false end
										for _, child in ipairs(drop:GetDescendants()) do
											if child:IsA("BasePart") then child.CanTouch = false end
										end

										drop.Parent = workspace
									end
								end
							end

							local respawnTime = obj:GetAttribute("RespawnTime") or 60
							local nodeClone = obj:Clone()
							local originalParent = obj.Parent

							for _, child in ipairs(nodeClone:GetChildren()) do
								if child:IsA("BillboardGui") then
									child:Destroy()
								end
							end
							nodeClone:SetAttribute("IsBreaking", nil) 
							nodeClone:SetAttribute("Health", nodeClone:GetAttribute("MaxHealth") or 100)

							local respawnEvent = ServerStorage:FindFirstChild("RespawnNodeEvent")
							if respawnEvent then
								respawnEvent:Fire(nodeClone, originalParent, respawnTime)
							end

							obj:Destroy()
						end
					end
				end
			end
		end
	end
end

tool.Activated:Connect(function()
	if debounce or not swingTrack then return end
	debounce = true

	swingTrack:Play()
	task.wait(swingTrack.Length * HIT_TIMING)
	performAttack()
	swingTrack.Stopped:Wait()
	task.wait(COOLDOWN)
	debounce = false
end)