local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Mirrors AdminManager.server.luau's whitelist, but only to decide whether to build this UI at
-- all -- the server independently re-checks and is the actual security boundary, so there's no
-- harm in a non-admin client somehow bypassing this and firing the remote anyway.
local ADMIN_USERNAMES = {
	GoneFishingAgain = true,
	tushar123tushar = true,
}

if not ADMIN_USERNAMES[player.Name] then
	return
end

local adminGiveItemEvent = ReplicatedStorage:WaitForChild("AdminGiveItem")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AdminMenuGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "AdminToggle"
toggleButton.Size = UDim2.new(0, 90, 0, 32)
toggleButton.Position = UDim2.new(1, -100, 0, 10)
toggleButton.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 13
toggleButton.Text = "ADMIN"
toggleButton.AutoButtonColor = true
toggleButton.ZIndex = 10
toggleButton.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "AdminPanel"
panel.Size = UDim2.new(0, 260, 0, 150)
panel.Position = UDim2.new(1, -270, 0, 50)
panel.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
panel.BackgroundTransparency = 0.1
panel.Visible = false
panel.ZIndex = 10
panel.Parent = screenGui

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(160, 40, 40)
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 0, 22)
title.Position = UDim2.new(0, 10, 0, 8)
title.BackgroundTransparency = 1
title.Text = "Give Item"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 10
title.Parent = panel

local itemNameBox = Instance.new("TextBox")
itemNameBox.Size = UDim2.new(1, -20, 0, 32)
itemNameBox.Position = UDim2.new(0, 10, 0, 36)
itemNameBox.BackgroundColor3 = Color3.fromRGB(76, 55, 38)
itemNameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
itemNameBox.PlaceholderText = "Item name (e.g. IronIngotItem)"
itemNameBox.PlaceholderColor3 = Color3.fromRGB(180, 155, 130)
itemNameBox.Font = Enum.Font.Gotham
itemNameBox.TextSize = 13
itemNameBox.Text = ""
itemNameBox.ClearTextOnFocus = false
itemNameBox.ZIndex = 10
itemNameBox.Parent = panel

local amountBox = Instance.new("TextBox")
amountBox.Size = UDim2.new(1, -20, 0, 32)
amountBox.Position = UDim2.new(0, 10, 0, 74)
amountBox.BackgroundColor3 = Color3.fromRGB(76, 55, 38)
amountBox.TextColor3 = Color3.fromRGB(255, 255, 255)
amountBox.PlaceholderText = "Amount (default 1)"
amountBox.PlaceholderColor3 = Color3.fromRGB(180, 155, 130)
amountBox.Font = Enum.Font.Gotham
amountBox.TextSize = 13
amountBox.Text = ""
amountBox.ClearTextOnFocus = false
amountBox.ZIndex = 10
amountBox.Parent = panel

local giveButton = Instance.new("TextButton")
giveButton.Size = UDim2.new(1, -20, 0, 32)
giveButton.Position = UDim2.new(0, 10, 0, 112)
giveButton.BackgroundColor3 = Color3.fromRGB(80, 160, 80)
giveButton.TextColor3 = Color3.fromRGB(255, 255, 255)
giveButton.Font = Enum.Font.GothamBold
giveButton.TextSize = 13
giveButton.Text = "Give"
giveButton.ZIndex = 10
giveButton.Parent = panel

toggleButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

giveButton.MouseButton1Click:Connect(function()
	local itemName = itemNameBox.Text:gsub("^%s+", ""):gsub("%s+$", "")
	if itemName == "" then
		return
	end
	local amount = tonumber(amountBox.Text) or 1
	adminGiveItemEvent:FireServer(itemName, amount)
end)
