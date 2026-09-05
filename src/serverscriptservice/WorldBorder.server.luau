local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Corners given as two arbitrary opposite points; min/max per axis makes an axis-aligned box out
-- of them regardless of which corner is "first".
local CORNER_A = Vector3.new(3.31, -9.325, -452.87)
local CORNER_B = Vector3.new(-4065.88, 177.736, 3618.7)

local MIN_BOUND = Vector3.new(
	math.min(CORNER_A.X, CORNER_B.X),
	math.min(CORNER_A.Y, CORNER_B.Y),
	math.min(CORNER_A.Z, CORNER_B.Z)
)
local MAX_BOUND = Vector3.new(
	math.max(CORNER_A.X, CORNER_B.X),
	math.max(CORNER_A.Y, CORNER_B.Y),
	math.max(CORNER_A.Z, CORNER_B.Z)
)

-- Clamps every character's HumanoidRootPart back inside the box every frame -- smooth/invisible
-- rather than a hard teleport-back on some interval, and zeroes outward velocity on the axis that
-- got clamped so a player pressing into the edge doesn't just keep re-hitting it.
RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if rootPart then
			local pos = rootPart.Position
			local clamped = Vector3.new(
				math.clamp(pos.X, MIN_BOUND.X, MAX_BOUND.X),
				math.clamp(pos.Y, MIN_BOUND.Y, MAX_BOUND.Y),
				math.clamp(pos.Z, MIN_BOUND.Z, MAX_BOUND.Z)
			)

			if clamped ~= pos then
				rootPart.CFrame = rootPart.CFrame - pos + clamped

				local velocity = rootPart.AssemblyLinearVelocity
				rootPart.AssemblyLinearVelocity = Vector3.new(
					clamped.X ~= pos.X and 0 or velocity.X,
					clamped.Y ~= pos.Y and 0 or velocity.Y,
					clamped.Z ~= pos.Z and 0 or velocity.Z
				)
			end
		end
	end
end)
