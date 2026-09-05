local Players = game:GetService("Players")

-- Fully disables Roblox's built-in swimming state -- normally triggered automatically in deep
-- Terrain water. With it disabled, characters just fall/walk through water like any other space
-- instead of floating/swimming.
local function disableSwimming(character)
	local humanoid = character:WaitForChild("Humanoid")
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(disableSwimming)
	if player.Character then
		disableSwimming(player.Character)
	end
end)
