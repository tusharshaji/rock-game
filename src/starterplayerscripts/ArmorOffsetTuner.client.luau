local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Mirrors ArmorOffsetTuner.server.luau's whitelist purely to decide whether to build this UI at
-- all -- the server independently re-checks and is the actual security boundary.
local ADMIN_USERNAMES = {
	GoneFishingAgain = true,
	tushar123tushar = true,
}

if not ADMIN_USERNAMES[player.Name] then
	return
end

local tuneEvent = ReplicatedStorage:WaitForChild("TuneArmorOffset")

-- ===== State =====
-- Position in studs, rotation in degrees -- matches ArmorOffsetTuner.server.luau's units exactly.
local values = { x = 0, y = 0, z = 0, rx = 0, ry = 0, rz = 0 }
local FIELDS = {
	{ key = "x", label = "X", step = 0.05 },
	{ key = "y", label = "Y", step = 0.05 },
	{ key = "z", label = "Z", step = 0.05 },
	{ key = "rx", label = "RX", step = 5 },
	{ key = "ry", label = "RY", step = 5 },
	{ key = "rz", label = "RZ", step = 5 },
}

-- ===== UI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ArmorOffsetTunerGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "TunerToggle"
toggleButton.Size = UDim2.new(0, 110, 0, 32)
toggleButton.Position = UDim2.new(1, -100, 0, 50) -- just below the ADMIN button (AdminMenu.client.luau)
toggleButton.BackgroundColor3 = Color3.fromRGB(60, 90, 160)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 13
toggleButton.Text = "ARMOR TUNE"
toggleButton.ZIndex = 10
toggleButton.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "TunerPanel"
panel.Size = UDim2.new(0, 260, 0, 400)
panel.Position = UDim2.new(1, -270, 0, 88)
panel.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
panel.BackgroundTransparency = 0.1
panel.Visible = false
panel.ZIndex = 10
panel.Parent = screenGui

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(60, 90, 160)
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local function makeLabel(text, y, height, size)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -20, 0, height or 16)
	label.Position = UDim2.new(0, 10, 0, y)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = Color3.fromRGB(214, 190, 165)
	label.Font = Enum.Font.Gotham
	label.TextSize = size or 11
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 10
	label.Parent = panel
	return label
end

makeLabel("Wear the item you're tuning, then adjust below.\nSlots preview live; hardcode the printed value once it's right.", 6, 30, 10)

local itemNameBox = Instance.new("TextBox")
itemNameBox.Size = UDim2.new(1, -20, 0, 26)
itemNameBox.Position = UDim2.new(0, 10, 0, 40)
itemNameBox.BackgroundColor3 = Color3.fromRGB(76, 55, 38)
itemNameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
itemNameBox.PlaceholderText = "Item name (e.g. CactusChestplate)"
itemNameBox.PlaceholderColor3 = Color3.fromRGB(180, 155, 130)
itemNameBox.Font = Enum.Font.Gotham
itemNameBox.TextSize = 12
itemNameBox.ClearTextOnFocus = false
itemNameBox.ZIndex = 10
itemNameBox.Parent = panel

local partNameBox = Instance.new("TextBox")
partNameBox.Size = UDim2.new(1, -20, 0, 26)
partNameBox.Position = UDim2.new(0, 10, 0, 70)
partNameBox.BackgroundColor3 = Color3.fromRGB(76, 55, 38)
partNameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
partNameBox.PlaceholderText = "Sub-part (e.g. default, Torso, LShoulder)"
partNameBox.PlaceholderColor3 = Color3.fromRGB(180, 155, 130)
partNameBox.Font = Enum.Font.Gotham
partNameBox.TextSize = 12
partNameBox.Text = "default"
partNameBox.ClearTextOnFocus = false
partNameBox.ZIndex = 10
partNameBox.Parent = panel

local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(1, -20, 0, 40)
codeBox.Position = UDim2.new(0, 10, 0, 302)
codeBox.BackgroundColor3 = Color3.fromRGB(28, 20, 14)
codeBox.TextColor3 = Color3.fromRGB(140, 220, 140)
codeBox.Font = Enum.Font.Code
codeBox.TextSize = 11
codeBox.TextWrapped = true
codeBox.ClearTextOnFocus = false
codeBox.TextEditable = false
codeBox.ZIndex = 10
codeBox.Parent = panel

local resetButton = Instance.new("TextButton")
resetButton.Size = UDim2.new(1, -20, 0, 28)
resetButton.Position = UDim2.new(0, 10, 0, 350)
resetButton.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
resetButton.TextColor3 = Color3.fromRGB(255, 255, 255)
resetButton.Font = Enum.Font.GothamBold
resetButton.TextSize = 13
resetButton.Text = "Reset (clear live override)"
resetButton.ZIndex = 10
resetButton.Parent = panel

local valueLabels = {}

local function formatCode()
	return string.format(
		"CFrame.new(%.3f, %.3f, %.3f) * CFrame.Angles(math.rad(%.2f), math.rad(%.2f), math.rad(%.2f))",
		values.x, values.y, values.z, values.rx, values.ry, values.rz
	)
end

local function sendUpdate()
	local itemName = itemNameBox.Text
	local partName = partNameBox.Text
	if itemName == "" or partName == "" then return end

	tuneEvent:FireServer(itemName, partName, values)
	codeBox.Text = formatCode()
end

for i, field in ipairs(FIELDS) do
	local rowY = 102 + (i - 1) * 33

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(0, 30, 0, 26)
	label.Position = UDim2.new(0, 10, 0, rowY)
	label.BackgroundTransparency = 1
	label.Text = field.label
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.ZIndex = 10
	label.Parent = panel

	local minusButton = Instance.new("TextButton")
	minusButton.Size = UDim2.new(0, 34, 0, 26)
	minusButton.Position = UDim2.new(0, 44, 0, rowY)
	minusButton.BackgroundColor3 = Color3.fromRGB(87, 63, 43)
	minusButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	minusButton.Font = Enum.Font.GothamBold
	minusButton.TextSize = 16
	minusButton.Text = "-"
	minusButton.ZIndex = 10
	minusButton.Parent = panel

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0, 84, 0, 26)
	valueLabel.Position = UDim2.new(0, 82, 0, rowY)
	valueLabel.BackgroundColor3 = Color3.fromRGB(68, 49, 34)
	valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	valueLabel.Font = Enum.Font.Code
	valueLabel.TextSize = 13
	valueLabel.Text = "0"
	valueLabel.ZIndex = 10
	valueLabel.Parent = panel
	valueLabels[field.key] = valueLabel

	local plusButton = Instance.new("TextButton")
	plusButton.Size = UDim2.new(0, 34, 0, 26)
	plusButton.Position = UDim2.new(0, 170, 0, rowY)
	plusButton.BackgroundColor3 = Color3.fromRGB(87, 63, 43)
	plusButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	plusButton.Font = Enum.Font.GothamBold
	plusButton.TextSize = 16
	plusButton.Text = "+"
	plusButton.ZIndex = 10
	plusButton.Parent = panel

	local stepLabel = Instance.new("TextLabel")
	stepLabel.Size = UDim2.new(0, 40, 0, 26)
	stepLabel.Position = UDim2.new(0, 210, 0, rowY)
	stepLabel.BackgroundTransparency = 1
	stepLabel.Text = "±" .. tostring(field.step)
	stepLabel.TextColor3 = Color3.fromRGB(180, 155, 130)
	stepLabel.Font = Enum.Font.Gotham
	stepLabel.TextSize = 10
	stepLabel.ZIndex = 10
	stepLabel.Parent = panel

	local function nudge(sign)
		values[field.key] += field.step * sign
		valueLabel.Text = string.format("%.3f", values[field.key])
		sendUpdate()
	end

	minusButton.MouseButton1Click:Connect(function() nudge(-1) end)
	plusButton.MouseButton1Click:Connect(function() nudge(1) end)
end

toggleButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

resetButton.MouseButton1Click:Connect(function()
	for _, field in ipairs(FIELDS) do
		values[field.key] = 0
		valueLabels[field.key].Text = "0"
	end
	codeBox.Text = ""

	local itemName = itemNameBox.Text
	local partName = partNameBox.Text
	if itemName ~= "" and partName ~= "" then
		tuneEvent:FireServer(itemName, partName, nil)
	end
end)
