local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local RecipesConfig = require(ReplicatedStorage:WaitForChild("RecipesConfig"))
local HotbarState = require(ReplicatedStorage:WaitForChild("HotbarState"))
local placeItemEvent = ReplicatedStorage:WaitForChild("PlaceItem")
local beginPlacementEvent = ReplicatedStorage:WaitForChild("BeginPlacement")
local cancelPlacementEvent = ReplicatedStorage:WaitForChild("CancelPlacement")

local PLACEMENT_DISTANCE = 6 -- studs in front of the character; matches FurnaceManager/BoatManager's own placement raycast server-side
local ROTATION_STEP = math.rad(15)

-- Maps a placeable recipe's itemName to the ReplicatedStorage template used for its ghost
-- preview. Add an entry here for each new placeable item (the template needs to live in
-- ReplicatedStorage, not ServerStorage, since the client has to be able to see it too).
local PLACEABLE_TEMPLATES = {
	Furnace = "FurnaceTemplate",
	WoodBoat = "WoodBoat",
}

local currentGhost = nil
local currentItemName = nil
local currentRotation = 0
local renderConnection = nil
local activeSlotAtPlacementStart = nil -- snapshot of HotbarState's active slot when blueprint mode began; switching away from it cancels

-- ===== Cancel/hint UI -- shown only while a blueprint is actively being placed =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlacementGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "PlacementPanel"
panel.AnchorPoint = Vector2.new(0.5, 1)
panel.Size = UDim2.new(0, 260, 0, 74)
panel.Position = UDim2.new(0.5, 0, 1, -90)
panel.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
panel.BackgroundTransparency = 0.15
panel.Visible = false
panel.Parent = screenGui

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(120, 88, 58)
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local hintText = Instance.new("TextLabel")
hintText.Name = "HintText"
hintText.Size = UDim2.new(1, -20, 0, 20)
hintText.Position = UDim2.new(0, 10, 0, 6)
hintText.BackgroundTransparency = 1
hintText.Text = "Click to place -- Q/E to rotate"
hintText.TextColor3 = Color3.fromRGB(214, 190, 165)
hintText.Font = Enum.Font.Gotham
hintText.TextSize = 12
hintText.Parent = panel

local cancelButton = Instance.new("TextButton")
cancelButton.Name = "CancelButton"
cancelButton.Size = UDim2.new(1, -20, 0, 30)
cancelButton.Position = UDim2.new(0, 10, 0, 34)
cancelButton.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
cancelButton.Font = Enum.Font.GothamBold
cancelButton.TextSize = 13
cancelButton.Text = "Cancel"
cancelButton.Parent = panel

-- ===== Ghost preview =====

local function destroyGhost()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if currentGhost then
		currentGhost:Destroy()
		currentGhost = nil
	end
	currentItemName = nil
	activeSlotAtPlacementStart = nil
	panel.Visible = false
end

-- Works whether a placeable's template is a Model (GetExtentsSize) or just a single BasePart
-- (Size directly) -- GetExtentsSize only exists on Model.
local function getSize(instance)
	if instance:IsA("Model") then
		return instance:GetExtentsSize()
	elseif instance:IsA("BasePart") then
		return instance.Size
	end
	return Vector3.new(4, 4, 4)
end

local function makeGhostTranslucent(instance)
	-- GetDescendants() only covers children, not the instance itself -- matters for a template
	-- that's a single bare BasePart (e.g. WoodBoat) rather than a Model wrapping several parts.
	local partsToStyle = instance:GetDescendants()
	if instance:IsA("BasePart") then
		table.insert(partsToStyle, instance)
	end

	for _, part in ipairs(partsToStyle) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 0.5
			part.Color = Color3.fromRGB(120, 200, 255)
		elseif part:IsA("Decal") or part:IsA("Texture") then
			part.Transparency = 1 -- keep decals from showing through the hologram tint
		end
	end
end

local function startGhost(itemName)
	local templateName = PLACEABLE_TEMPLATES[itemName]
	if not templateName then return end

	local template = ReplicatedStorage:FindFirstChild(templateName)
	if not template then
		warn("PlacementController: no ghost preview template '" .. templateName .. "' found in ReplicatedStorage")
		return
	end

	destroyGhost()
	currentItemName = itemName
	currentRotation = 0
	activeSlotAtPlacementStart = HotbarState.GetActiveSlot()

	local recipe = RecipesConfig[itemName]
	hintText.Text = (recipe and recipe.DisplayName or itemName) .. " -- Click to place, Q/E to rotate"
	panel.Visible = true

	local ghost = template:Clone()
	ghost.Name = "PlacementGhost"
	makeGhostTranslucent(ghost)
	ghost.Parent = workspace
	currentGhost = ghost

	-- PivotTo() places the model's center at the given point, not its base -- lift by half the
	-- model's height so the preview (and the real furnace/boat, see the matching fix in
	-- FurnaceManager.server.luau/BoatManager.server.luau) sits flush on the ground instead of
	-- half-buried in it.
	local halfHeight = getSize(ghost).Y / 2

	renderConnection = RunService.RenderStepped:Connect(function()
		local character = player.Character
		if not character then return end
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then return end

		local horizontalPosition = rootPart.Position + rootPart.CFrame.LookVector * PLACEMENT_DISTANCE

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { character, ghost }
		-- Cast relative to the player's own current elevation, not a fixed high altitude -- see
		-- the matching comment in FurnaceManager.server.luau for why (underground placement).
		local result = workspace:Raycast(horizontalPosition + Vector3.new(0, 10, 0), Vector3.new(0, -50, 0), raycastParams)
		local groundPosition = result and result.Position or horizontalPosition
		local placePosition = groundPosition + Vector3.new(0, halfHeight, 0)

		ghost:PivotTo(CFrame.new(placePosition) * CFrame.Angles(0, currentRotation, 0))
	end)
end

-- Cancels the current blueprint and asks the server to refund whatever it cost to craft.
local function cancelPlacement()
	if not currentItemName then return end
	local itemName = currentItemName
	destroyGhost()
	cancelPlacementEvent:FireServer(itemName)
end

local function confirmPlacement()
	if not currentItemName then return end
	placeItemEvent:FireServer(currentItemName, currentRotation)
	-- Optimistic: there's only ever one pending blueprint at a time, so a placement always either
	-- consumes it or fails outright server-side -- either way, blueprint mode is done here.
	destroyGhost()
end

-- ===== Entry points: crafting a placeable jumps straight into blueprint mode =====
beginPlacementEvent.OnClientEvent:Connect(function(itemName)
	startGhost(itemName)
end)

-- Server-initiated cancel (e.g. the pending placement was cleared some other way) -- just make
-- sure the client's ghost/UI matches. Player-initiated cancels already clean up locally in
-- cancelPlacement() before this ever fires.
cancelPlacementEvent.OnClientEvent:Connect(function()
	destroyGhost()
end)

cancelButton.MouseButton1Click:Connect(function()
	cancelPlacement()
end)

-- Switching hotbar tools (pressing a number key or clicking a different slot) cancels an
-- in-progress placement, same as the Cancel button.
HotbarState.OnUpdate(function(_, activeSlot)
	if currentGhost and activeSlot ~= activeSlotAtPlacementStart then
		cancelPlacement()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not currentGhost then return end
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.Q then
		currentRotation -= ROTATION_STEP
	elseif input.KeyCode == Enum.KeyCode.E then
		currentRotation += ROTATION_STEP
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		confirmPlacement()
	end
end)
