local tool = script.Parent
local handle = tool:WaitForChild("Handle")

local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local levelModule = ServerScriptService:WaitForChild("LevelManager", 10)
local LevelManager = levelModule and require(levelModule) or nil
local armorModule = ServerScriptService:WaitForChild("ArmorManager", 10)
local ArmorManager = armorModule and require(armorModule) or nil
local dropItemsFolder = ServerStorage:WaitForChild("DropItems")
local hitSound = tool:FindFirstChild("BreakableHitSound") or handle:FindFirstChild("BreakableHitSound")

-- ===== SETTINGS (TIER 2 - STONE PICKAXE) =====
local PLAYER_DAMAGE = 25
local BREAKABLE_DAMAGE = 3
local TOOL_TIER = 2
local TOOL_TYPE = "Pickaxe"
local COOLDOWN = 0.2
local ATTACK_RANGE = 8
local ATTACK_ANGLE = 180
local SWING_ANIM_ID = "rbxassetid://95615106643542"
local HIT_TIMING = 0.2
-- =============================================

local debounce = false
local swingTrack = nil

local function canBreakNode(nodeModel)
	if TOOL_TYPE == "Rock" then
		return true -- Rock bypasses both type and tier checks entirely, breaks anything
	end

	local requiredTier = nodeModel:GetAttribute(TOOL_TYPE)
	if requiredTier == nil then
		return false -- this node doesn't accept this tool type at all
	end

	return TOOL_TIER >= requiredTier
end

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
							local victim = Players:GetPlayerFromCharacter(targetModel)
							if victim and ArmorManager then
								local attackerPlayer = Players:GetPlayerFromCharacter(character)
								ArmorManager.ApplyDamage(victim, obj, PLAYER_DAMAGE, attackerPlayer, tool)
							else
								obj:TakeDamage(PLAYER_DAMAGE)
							end
						end
					end
				end
			end
		end
	end

	-- Breakable nodes are Models: the "Breakable"/"MaxHealth"/"Health"/drop/tier attributes live
	-- on the parent Model (nodeModel), not on the individual Part that actually gets hit (obj).
	-- obj's own Position is still what's used for range/angle checks and drop placement, since
	-- that's about the physical part standing in the world.
	for _, obj in ipairs(workspace:GetDescendants()) do
		local nodeModel = obj:IsA("BasePart") and obj.Parent
		if nodeModel and nodeModel:GetAttribute("Breakable") then
			if canBreakNode(nodeModel) then
				local toTarget = obj.Position - originPos
				local distance = toTarget.Magnitude

				if distance <= ATTACK_RANGE and distance > 0 then
					local direction = toTarget.Unit
					local dot = forward:Dot(direction)
					local angleBetween = math.deg(math.acos(math.clamp(dot, -1, 1)))

					if angleBetween <= ATTACK_ANGLE / 2 then
						if hitSound and hitSound:IsA("Sound") then
							hitSound:Play()
						end

						local maxHealth = nodeModel:GetAttribute("MaxHealth") or 100
						local currentHealth = nodeModel:GetAttribute("Health") or maxHealth

						currentHealth = math.max(0, currentHealth - BREAKABLE_DAMAGE)
						nodeModel:SetAttribute("Health", currentHealth)

						if currentHealth <= 0 and not nodeModel:GetAttribute("IsBreaking") then
							nodeModel:SetAttribute("IsBreaking", true)

							local player = Players:GetPlayerFromCharacter(character)
							-- Safe check for LevelManager and AddXP function
							if player and LevelManager and type(LevelManager.AddXP) == "function" then
								local xpReward = nodeModel:GetAttribute("XPReward") or 25
								LevelManager.AddXP(player, xpReward)
							end

							local dropsToSpawn = {}
							local i = 1
							while nodeModel:GetAttribute("Drop" .. i .. "_Name") do
								table.insert(dropsToSpawn, {
									Name = nodeModel:GetAttribute("Drop" .. i .. "_Name"),
									Min = nodeModel:GetAttribute("Drop" .. i .. "_Min") or 1,
									Max = nodeModel:GetAttribute("Drop" .. i .. "_Max") or 1
								})
								i += 1
							end

							if #dropsToSpawn == 0 and nodeModel:GetAttribute("DropName") then
								table.insert(dropsToSpawn, {
									Name = nodeModel:GetAttribute("DropName"),
									Min = nodeModel:GetAttribute("MinDrops") or 1,
									Max = nodeModel:GetAttribute("MaxDrops") or 1
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

							local respawnTime = nodeModel:GetAttribute("RespawnTime") or 60
							local nodeClone = nodeModel:Clone()
							local originalParent = nodeModel.Parent

							for _, child in ipairs(nodeClone:GetDescendants()) do
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

							nodeModel:Destroy()
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
