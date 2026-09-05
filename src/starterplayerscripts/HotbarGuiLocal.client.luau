local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local equipEvent = ReplicatedStorage:WaitForChild("EquipHotbarTool")

local HotbarState = require(ReplicatedStorage:WaitForChild("HotbarState"))
local ItemIconRenderer = require(ReplicatedStorage:WaitForChild("ItemIconRenderer"))

local SLOT_KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9
}

-- Build UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HotbarGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local hotbarFrame = Instance.new("Frame")
hotbarFrame.Name = "HotbarFrame"
hotbarFrame.Size = UDim2.new(0, 460, 0, 50)
hotbarFrame.Position = UDim2.new(0.5, -230, 1, -65)
hotbarFrame.BackgroundTransparency = 1
hotbarFrame.Parent = screenGui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.Padding = UDim.new(0, 5)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Parent = hotbarFrame

local slotFrames = {}

local function equipSlot(slotIndex)
	local active = HotbarState.GetActiveSlot()
	local slots = HotbarState.GetSlots()

	if active == slotIndex then
		HotbarState.SetActiveSlot(nil)
		equipEvent:FireServer(nil)
	else
		HotbarState.SetActiveSlot(slotIndex)
		local toolToEquip = slots[slotIndex]
		equipEvent:FireServer(toolToEquip)
	end
end

for i = 1, 9 do
	local slot = Instance.new("TextButton")
	slot.Name = "Slot_" .. i
	slot.Size = UDim2.new(0, 45, 0, 45)
	slot.BackgroundColor3 = Color3.fromRGB(68, 49, 34)
	slot.BackgroundTransparency = 0.2
	slot.Text = ""
	slot.AutoButtonColor = false
	slot.Parent = hotbarFrame

	local stroke = Instance.new("UIStroke")
	stroke.Name = "SelectionBorder"
	stroke.Color = Color3.fromRGB(230, 190, 130)
	stroke.Thickness = 2
	stroke.Enabled = false
	stroke.Parent = slot

	local numLabel = Instance.new("TextLabel")
	numLabel.Size = UDim2.new(0, 15, 0, 15)
	numLabel.Position = UDim2.new(0, 3, 0, 3)
	numLabel.BackgroundTransparency = 1
	numLabel.Text = tostring(i)
	numLabel.TextColor3 = Color3.fromRGB(198, 172, 145)
	numLabel.Font = Enum.Font.GothamBold
	numLabel.TextSize = 11
	numLabel.ZIndex = 2
	numLabel.Parent = slot

	local itemIcon = Instance.new("ViewportFrame")
	itemIcon.Name = "ItemIcon"
	itemIcon.Size = UDim2.new(1, -10, 1, -10)
	itemIcon.Position = UDim2.new(0, 5, 0, 5)
	itemIcon.BackgroundTransparency = 1
	itemIcon.Parent = slot

	slotFrames[i] = slot

	slot.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			equipSlot(i)
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if HotbarState.GetActiveSlot() == i then
				equipSlot(i)
			end
			HotbarState.RemoveSlot(i)
		end
	end)
end

HotbarState.OnUpdate(function(slots, activeSlot)
	for i = 1, 9 do
		local itemName = slots[i]
		ItemIconRenderer.SetIcon(slotFrames[i].ItemIcon, itemName)
		slotFrames[i].SelectionBorder.Enabled = (i == activeSlot)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	local targetSlot = SLOT_KEYS[input.KeyCode]
	if targetSlot then
		equipSlot(targetSlot)
	end
end)