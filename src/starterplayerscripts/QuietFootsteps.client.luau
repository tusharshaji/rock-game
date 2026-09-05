local Players = game:GetService("Players")

local WALK_SOUND_VOLUME = 0.15 -- default is roughly 0.65

-- Client-side because the "Running" (footstep) Sound is created by each character's Animate
-- script, which runs as a LocalScript per-viewer -- every client independently renders and sounds
-- every character it can see, including your own. A server script has no reliable access to that,
-- which is why a server-side version of this had no effect. Running locally and covering every
-- player (not just the local one) makes footsteps quieter for everyone, from everyone's
-- perspective, the same as a server-wide change would have looked like if one were possible.
local function quietenFootsteps(character)
	local rootPart = character:WaitForChild("HumanoidRootPart")
	local runningSound = rootPart:WaitForChild("Running", 5)
	if runningSound then
		runningSound.Volume = WALK_SOUND_VOLUME
	end
end

local function onPlayerAdded(player)
	if player.Character then
		quietenFootsteps(player.Character)
	end
	player.CharacterAdded:Connect(quietenFootsteps)
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
