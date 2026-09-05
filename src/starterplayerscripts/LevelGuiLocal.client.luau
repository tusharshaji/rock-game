local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

-- Build UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LevelGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true -- sit right at the true top of the screen, not below Roblox's reserved top-bar inset
screenGui.Parent = player:WaitForChild("PlayerGui")

local xpContainer = Instance.new("Frame")
xpContainer.Name = "XPContainer"
xpContainer.Size = UDim2.new(0, 360, 0, 16)
xpContainer.Position = UDim2.new(0.5, -180, 0, 2)
xpContainer.BackgroundTransparency = 1
xpContainer.Parent = screenGui

local barBackground = Instance.new("Frame")
barBackground.Name = "BarBackground"
barBackground.Size = UDim2.new(1, -60, 1, 0)
barBackground.Position = UDim2.new(0, 0, 0, 0)
barBackground.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
barBackground.BackgroundTransparency = 0.3
barBackground.ClipsDescendants = true
barBackground.Parent = xpContainer

local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(24, 16, 10)
barStroke.Thickness = 1.5
barStroke.Transparency = 0.4
barStroke.Parent = barBackground

local xpFill = Instance.new("Frame")
xpFill.Name = "Fill"
xpFill.Size = UDim2.new(0, 0, 1, 0)
xpFill.BackgroundColor3 = Color3.fromRGB(240, 220, 60)
xpFill.BorderSizePixel = 0
xpFill.Parent = barBackground

local xpText = Instance.new("TextLabel")
xpText.Name = "XPText"
xpText.Size = UDim2.new(1, 0, 1, 0)
xpText.BackgroundTransparency = 1
xpText.Text = "0 / 100 XP"
xpText.TextColor3 = Color3.fromRGB(255, 255, 255)
xpText.Font = Enum.Font.GothamBold
xpText.TextSize = 10
xpText.TextStrokeTransparency = 0.5
xpText.ZIndex = 2
xpText.Parent = barBackground

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelText"
levelLabel.Size = UDim2.new(0, 50, 1, 0)
levelLabel.Position = UDim2.new(1, -50, 0, 0)
levelLabel.BackgroundTransparency = 1
levelLabel.Text = "Lvl 1"
levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
levelLabel.Font = Enum.Font.GothamBold
levelLabel.TextSize = 13
levelLabel.TextXAlignment = Enum.TextXAlignment.Right
levelLabel.TextStrokeTransparency = 0.5
levelLabel.Parent = xpContainer

-- Safe Remote Listener
local function connectListener(updateXpEvent)
	updateXpEvent.OnClientEvent:Connect(function(level, currentXP, requiredXP)
		if level >= 100 then
			levelLabel.Text = "Lvl MAX"
			xpText.Text = "MAX LEVEL"
			xpFill.Size = UDim2.new(1, 0, 1, 0)
			return
		end

		levelLabel.Text = "Lvl " .. tostring(level)
		xpText.Text = tostring(currentXP) .. " / " .. tostring(requiredXP) .. " XP"

		local progress = math.clamp(currentXP / requiredXP, 0, 1)
		TweenService:Create(xpFill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(progress, 0, 1, 0)
		}):Play()
	end)
end

local updateXpEvent = ReplicatedStorage:FindFirstChild("UpdateXP")
if updateXpEvent then
	connectListener(updateXpEvent)
else
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == "UpdateXP" then
			connectListener(child)
		end
	end)
end