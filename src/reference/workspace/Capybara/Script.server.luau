-- Script inside a Breakable BasePart (Animal)
local part = script.Parent

-- ===== SETTINGS =====
local MAX_HEALTH = 100        -- Maximum health of the animal
local HIT_SPEED = 25          -- Speed when hit by a player
local HIT_DURATION = 1        -- How long it moves away when hit (seconds)
local IDLE_SPEED = 7          -- Speed while wandering around idling
local TURN_SPEED = 3          -- How fast it turns to face its movement direction
local WANDER_CHANGE_TIME = 5  -- How often it picks a new random direction (seconds)
-- ====================

-- Initialize Health attribute if it doesn't exist yet
if not part:GetAttribute("Health") then
	part:SetAttribute("Health", MAX_HEALTH)
end

-- Ensure a BodyGyro exists to keep it upright and handle smooth turning dynamically
local bg = part:FindFirstChildOfClass("BodyGyro")
if not bg then
	bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(40000, 40000, 40000)
	bg.P = 3000
	bg.D = 100
	bg.Parent = part
end

local isHit = false
local currentDirection = Vector3.new(1, 0, 0)
local targetCFrame = part.CFrame

-- Idle wandering loop
task.spawn(function()
	local timer = 0
	while true do
		local dt = task.wait(0.1)
		if not isHit then
			timer -= dt
			if timer <= 0 then
				timer = WANDER_CHANGE_TIME
				local randomAngle = math.random() * math.pi * 2
				currentDirection = Vector3.new(math.cos(randomAngle), 0, math.sin(randomAngle))
			end

			-- Apply idle movement
			part.AssemblyLinearVelocity = Vector3.new(
				currentDirection.X * IDLE_SPEED,
				part.AssemblyLinearVelocity.Y,
				currentDirection.Z * IDLE_SPEED
			)

			-- Set target rotation facing movement direction
			if currentDirection.Magnitude > 0 then
				targetCFrame = CFrame.lookAt(part.Position, part.Position + currentDirection) * CFrame.Angles(0, math.rad(-90), 0)
			end
		end
	end
end)

-- Smoothly update rotation and handle hit reactions using Heartbeat
local runService = game:GetService("RunService")
local hitTimer = 0
local hitDirection = Vector3.new(0, 0, 0)

runService.Heartbeat:Connect(function(dt)
	if isHit then
		hitTimer -= dt
		if hitTimer <= 0 then
			isHit = false
		else
			-- Move away fast when hit
			part.AssemblyLinearVelocity = Vector3.new(
				hitDirection.X * HIT_SPEED,
				part.AssemblyLinearVelocity.Y,
				hitDirection.Z * HIT_SPEED
			)
			targetCFrame = CFrame.lookAt(part.Position, part.Position + hitDirection) * CFrame.Angles(0, math.rad(-90), 0)
		end
	end

	-- Smoothly rotate towards the target direction
	bg.CFrame = bg.CFrame:Lerp(targetCFrame, TURN_SPEED * dt)
end)

-- React whenever the health attribute changes
local lastHealth = part:GetAttribute("Health")

part:GetAttributeChangedSignal("Health"):Connect(function()
	local newHealth = part:GetAttribute("Health")

	-- Check if health has dropped to 0 or below (Death)
	if newHealth <= 0 then
		part:Destroy()
		return
	end

	-- If health went down, it means it took a hit
	if newHealth < lastHealth then
		isHit = true
		hitTimer = HIT_DURATION

		-- Find the closest character to flee from
		local closestChar = nil
		local shortestDist = 30 -- Max range to check for reacting

		for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if root then
				local dist = (root.Position - part.Position).Magnitude
				if dist < shortestDist then
					shortestDist = dist
					closestChar = char
				end
			end
		end

		if closestChar and closestChar:FindFirstChild("HumanoidRootPart") then
			local playerRoot = closestChar.HumanoidRootPart
			hitDirection = (part.Position - playerRoot.Position) * Vector3.new(1, 0, 1)
			if hitDirection.Magnitude > 0 then
				hitDirection = hitDirection.Unit
			else
				hitDirection = Vector3.new(1, 0, 0)
			end
		else
			local fallback = Vector3.new(math.random(-100, 100), 0, math.random(-100, 100))
			hitDirection = fallback.Magnitude > 0 and fallback.Unit or Vector3.new(1, 0, 0)
		end
	end

	lastHealth = newHealth
end)