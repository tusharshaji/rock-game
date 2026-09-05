-- LocalScript
-- Location: StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local PICKUP_RANGE = 8 -- studs, how close the player needs to be to see the prompt

local pickupEvent = ReplicatedStorage:WaitForChild("PickupItem")

-- ===== Build the reusable prompt UI (moved to whichever item is closest) =====
local promptGui = Instance.new("BillboardGui")
promptGui.Name = "PickupPrompt"
promptGui.Size = UDim2.new(0, 140, 0, 40)
promptGui.StudsOffset = Vector3.new(0, 2, 0)
promptGui.AlwaysOnTop = true
promptGui.Enabled = false

local promptBg = Instance.new("Frame")
promptBg.Size = UDim2.new(1, 0, 1, 0)
promptBg.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
promptBg.BackgroundTransparency = 0.25
promptBg.Parent = promptGui

local promptLabel = Instance.new("TextLabel")
promptLabel.Size = UDim2.new(1, 0, 1, 0)
promptLabel.BackgroundTransparency = 1
promptLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
promptLabel.Font = Enum.Font.GothamBold
promptLabel.TextSize = 16
promptLabel.Text = "Press E"
promptLabel.Parent = promptBg

-- ===== Track the currently targeted item =====
local currentTarget = nil

local function getItemPart(item)
	if item:IsA("BasePart") then
		return item
	elseif item:IsA("Model") then
		return item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

RunService.Heartbeat:Connect(function()
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local closestItem = nil
	local closestDist = PICKUP_RANGE

	for _, item in ipairs(CollectionService:GetTagged("Pickupable")) do
		local part = getItemPart(item)
		if part then
			local dist = (part.Position - rootPart.Position).Magnitude
			if dist <= closestDist then
				closestDist = dist
				closestItem = item
			end
		end
	end

	if closestItem ~= currentTarget then
		currentTarget = closestItem
		if currentTarget then
			local part = getItemPart(currentTarget)
			promptGui.Adornee = part
			promptGui.Parent = part
			promptGui.Enabled = true
		else
			promptGui.Enabled = false
			promptGui.Parent = nil
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E and currentTarget then
		pickupEvent:FireServer(currentTarget)
	end
end)
