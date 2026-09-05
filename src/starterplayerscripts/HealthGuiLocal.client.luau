local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- Build UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HealthGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local healthContainer = Instance.new("Frame")
healthContainer.Name = "HealthContainer"
healthContainer.AnchorPoint = Vector2.new(1, 1)
healthContainer.Size = UDim2.new(0, 160, 0, 14)
healthContainer.Position = UDim2.new(1, -16, 1, -36) -- bottom right corner, stacked above the hunger bar
healthContainer.BackgroundTransparency = 1
healthContainer.Parent = screenGui

local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.Size = UDim2.new(1, 0, 1, 0)
barBackground.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
barBackground.BackgroundTransparency = 0.3
barBackground.ClipsDescendants = true
barBackground.Parent = healthContainer

local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(24, 16, 10)
barStroke.Thickness = 1.5
barStroke.Transparency = 0.4
barStroke.Parent = barBackground

local healthFill = Instance.new("Frame")
healthFill.Name = "Fill"
healthFill.Size = UDim2.new(1, 0, 1, 0)
healthFill.BackgroundColor3 = Color3.fromRGB(70, 190, 90)
healthFill.BorderSizePixel = 0
healthFill.Parent = barBackground

local healthText = Instance.new("TextLabel")
healthText.Name = "HealthText"
healthText.Size = UDim2.new(1, 0, 1, 0)
healthText.BackgroundTransparency = 1
healthText.Text = "Health: 100 / 100"
healthText.TextColor3 = Color3.fromRGB(255, 255, 255)
healthText.Font = Enum.Font.GothamBold
healthText.TextSize = 9
healthText.TextStrokeTransparency = 0.5
healthText.ZIndex = 2
healthText.Parent = barBackground

local function refreshHealth(current, max)
	current = math.clamp(current, 0, max)
	healthText.Text = string.format("Health: %d / %d", math.floor(current + 0.5), math.floor(max + 0.5))

	local progress = max > 0 and (current / max) or 0
	local fillColor = Color3.fromRGB(70, 190, 90)
	if progress < 0.3 then
		fillColor = Color3.fromRGB(220, 70, 60)
	elseif progress < 0.6 then
		fillColor = Color3.fromRGB(230, 180, 40)
	end

	TweenService:Create(healthFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(progress, 0, 1, 0),
		BackgroundColor3 = fillColor,
	}):Play()
end

local function watchHumanoid(character)
	local humanoid = character:WaitForChild("Humanoid")
	refreshHealth(humanoid.Health, humanoid.MaxHealth)

	humanoid.HealthChanged:Connect(function(health)
		refreshHealth(health, humanoid.MaxHealth)
	end)
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		refreshHealth(humanoid.Health, humanoid.MaxHealth)
	end)
end

if player.Character then
	watchHumanoid(player.Character)
end
player.CharacterAdded:Connect(watchHumanoid)
