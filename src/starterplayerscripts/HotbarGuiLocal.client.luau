local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local equipEvent = ReplicatedStorage:WaitForChild("EquipHotbarTool")

local HotbarState = require(ReplicatedStorage:WaitForChild("HotbarState"))
local ItemIconRenderer = require(ReplicatedStorage:WaitForChild("ItemIconRenderer"))
-- Timed wait with a fallback, never an open-ended WaitForChild: ItemNames is a cosmetic helper,
-- so if it hasn't replicated (or hasn't been synced into the place yet) the UI must still build.
-- Blocking on it here takes the entire HUD down, which is far worse than raw item names.
local itemNamesModule = ReplicatedStorage:WaitForChild("ItemNames", 5)
local ItemNames = itemNamesModule and require(itemNamesModule) or {
	Get = function(itemName) return itemName or "" end,
}

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

	-- Shown only when the item in this slot has no Photobooth icon export to render. Without it
	-- such a slot looks completely empty and the item reads as lost, even though it's held.
	local itemLabel = Instance.new("TextLabel")
	itemLabel.Name = "ItemLabel"
	itemLabel.Size = UDim2.new(1, -6, 1, -18)
	itemLabel.Position = UDim2.new(0, 3, 0, 15)
	itemLabel.BackgroundTransparency = 1
	itemLabel.Text = ""
	itemLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	itemLabel.Font = Enum.Font.GothamBold
	itemLabel.TextSize = 10
	itemLabel.TextWrapped = true
	itemLabel.Visible = false
	itemLabel.ZIndex = 3
	itemLabel.Parent = slot

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

local function renderSlots(slots, activeSlot)
	for i = 1, 9 do
		local slot = slotFrames[i]
		local itemName = slots[i]
		local hasIcon = ItemIconRenderer.SetIcon(slot.ItemIcon, itemName)

		-- An occupied slot must always look occupied, icon or not: fall back to the item's
		-- display name, and brighten the slot itself so it reads as filled either way.
		local showLabel = itemName ~= nil and not hasIcon
		slot.ItemLabel.Text = showLabel and ItemNames.Get(itemName) or ""
		slot.ItemLabel.Visible = showLabel
		slot.BackgroundTransparency = itemName and 0.05 or 0.2

		slot.SelectionBorder.Enabled = (i == activeSlot)
	end
end

HotbarState.OnUpdate(renderSlots)

-- Paint once from whatever state already exists. MainUIController assigns the starter items as
-- soon as the server's first inventory sync lands, which can easily happen before this script
-- has finished its WaitForChild calls and subscribed above -- without this initial pass those
-- items sit in HotbarState but never appear in the bar.
renderSlots(HotbarState.GetSlots(), HotbarState.GetActiveSlot())

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	local targetSlot = SLOT_KEYS[input.KeyCode]
	if targetSlot then
		equipSlot(targetSlot)
	end
end)