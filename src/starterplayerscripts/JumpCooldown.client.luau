local Players = game:GetService("Players")

local JUMP_COOLDOWN = 1 -- seconds between jumps

local player = Players.LocalPlayer

-- Client-side because the player's own character is client-owned for physics -- a server script
-- trying to cancel Humanoid.Jump after the fact has no real authority over that simulation, which
-- is why a server-side version of this had no effect at all. Running locally, cancelling the jump
-- attempt immediately actually prevents the impulse from being applied.
--
-- Note: since this is client-side, a modified client could bypass it -- fine for a gameplay-pacing
-- feature like this, but worth knowing if it ever needs to be exploit-proof.
local function setupJumpCooldown(character)
	local humanoid = character:WaitForChild("Humanoid")
	local onCooldown = false

	humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if not humanoid.Jump then return end -- only care about jump attempts (false -> true)

		if onCooldown then
			humanoid.Jump = false
			return
		end

		onCooldown = true
		task.delay(JUMP_COOLDOWN, function()
			onCooldown = false
		end)
	end)
end

if player.Character then
	setupJumpCooldown(player.Character)
end
player.CharacterAdded:Connect(setupJumpCooldown)
