local Players = game:GetService("Players")

local uwGround = workspace:WaitForChild("UWGround")

local SPEED_MULTIPLIER = 0.5
local EXIT_LINGER_TIME = 1 -- seconds the slow persists after leaving, so jumping out doesn't dodge it

-- A character has several BaseParts (torso, limbs, worn armor/sack visuals) that can each
-- independently touch/untouch UWGround, so this counts currently-touching parts per Humanoid
-- rather than reacting to a single Touched/TouchEnded pair -- the exit timer only starts once
-- every part has left, not the moment any single one does.
local touchingCount = {} -- [humanoid] = number of currently-touching parts
local originalSpeed = {} -- [humanoid] = WalkSpeed captured just before slowing, restored after the linger time
local pendingRestore = {} -- [humanoid] = token identifying the most recently scheduled restore

local function getHumanoid(hit)
	local character = hit.Parent
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function onTouched(hit)
	local humanoid = getHumanoid(hit)
	if not humanoid then return end

	touchingCount[humanoid] = (touchingCount[humanoid] or 0) + 1
	pendingRestore[humanoid] = nil -- cancel any scheduled restore -- back in the zone

	if not originalSpeed[humanoid] then
		originalSpeed[humanoid] = humanoid.WalkSpeed
	end
	humanoid.WalkSpeed = originalSpeed[humanoid] * SPEED_MULTIPLIER
end

local function onTouchEnded(hit)
	local humanoid = getHumanoid(hit)
	if not humanoid then return end

	touchingCount[humanoid] = math.max(0, (touchingCount[humanoid] or 1) - 1)
	if touchingCount[humanoid] > 0 then return end

	-- Don't restore immediately -- keep them slowed for EXIT_LINGER_TIME so a quick jump out of
	-- the zone doesn't let them dodge the effect. The token lets a re-entry (or another exit)
	-- before this fires supersede it instead of stacking multiple pending restores.
	local token = {}
	pendingRestore[humanoid] = token
	task.delay(EXIT_LINGER_TIME, function()
		if pendingRestore[humanoid] ~= token then return end
		if originalSpeed[humanoid] then
			humanoid.WalkSpeed = originalSpeed[humanoid]
			originalSpeed[humanoid] = nil
		end
		pendingRestore[humanoid] = nil
	end)
end

-- UWGround can be either a single Part or a Folder containing several (e.g. an irregular-shaped
-- underwater area built from multiple pieces) -- connect every actual BasePart involved rather
-- than assuming one or the other.
local function connectPart(part)
	part.CanTouch = true -- required for Touched/TouchEnded to fire at all
	part.Touched:Connect(onTouched)
	part.TouchEnded:Connect(onTouchEnded)
end

if uwGround:IsA("BasePart") then
	connectPart(uwGround)
else
	for _, descendant in ipairs(uwGround:GetDescendants()) do
		if descendant:IsA("BasePart") then
			connectPart(descendant)
		end
	end
end

-- Clean up tracked state if a player leaves while still standing in (or recovering from) the
-- zone, so it doesn't linger referencing a Humanoid that no longer exists.
Players.PlayerRemoving:Connect(function(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		touchingCount[humanoid] = nil
		originalSpeed[humanoid] = nil
		pendingRestore[humanoid] = nil
	end
end)
