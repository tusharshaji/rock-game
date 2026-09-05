local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- Build UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HungerGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local hungerContainer = Instance.new("Frame")
hungerContainer.Name = "HungerContainer"
hungerContainer.AnchorPoint = Vector2.new(1, 1)
hungerContainer.Size = UDim2.new(0, 160, 0, 14)
hungerContainer.Position = UDim2.new(1, -16, 1, -16) -- bottom right corner, below the health bar
hungerContainer.BackgroundTransparency = 1
hungerContainer.Parent = screenGui

local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.Size = UDim2.new(1, 0, 1, 0)
barBackground.Position = UDim2.new(0, 0, 0, 0)
barBackground.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
barBackground.BackgroundTransparency = 0.3
barBackground.ClipsDescendants = true
barBackground.Parent = hungerContainer

local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(24, 16, 10)
barStroke.Thickness = 1.5
barStroke.Transparency = 0.4
barStroke.Parent = barBackground

local hungerFill = Instance.new("Frame")
hungerFill.Name = "Fill"
hungerFill.Size = UDim2.new(1, 0, 1, 0)
hungerFill.BackgroundColor3 = Color3.fromRGB(230, 150, 40)
hungerFill.BorderSizePixel = 0
hungerFill.Parent = barBackground

local hungerText = Instance.new("TextLabel")
hungerText.Name = "HungerText"
hungerText.Size = UDim2.new(1, 0, 1, 0)
hungerText.BackgroundTransparency = 1
hungerText.Text = "Hunger: 100 / 100"
hungerText.TextColor3 = Color3.fromRGB(255, 255, 255)
hungerText.Font = Enum.Font.GothamBold
hungerText.TextSize = 9
hungerText.TextStrokeTransparency = 0.5
hungerText.ZIndex = 2
hungerText.Parent = barBackground

local function refreshHunger(current, max)
	hungerText.Text = string.format("Hunger: %d / %d", current, max)

	local progress = max > 0 and math.clamp(current / max, 0, 1) or 0
	local fillColor = Color3.fromRGB(230, 150, 40)
	if progress < 0.25 then
		fillColor = Color3.fromRGB(220, 70, 60) -- red warning once hunger is low
	end

	TweenService:Create(hungerFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(progress, 0, 1, 0),
		BackgroundColor3 = fillColor,
	}):Play()
end

local function connectListener(updateHungerEvent)
	updateHungerEvent.OnClientEvent:Connect(refreshHunger)
end

local updateHungerEvent = ReplicatedStorage:FindFirstChild("UpdateHunger")
if updateHungerEvent then
	connectListener(updateHungerEvent)
else
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "UpdateHunger" then
			connectListener(child)
		end
	end)
end
