local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local RecipesConfig = require(ReplicatedStorage:WaitForChild("RecipesConfig"))
local HotbarState = require(ReplicatedStorage:WaitForChild("HotbarState"))
local ItemIconRenderer = require(ReplicatedStorage:WaitForChild("ItemIconRenderer"))

local updateEvent = ReplicatedStorage:WaitForChild("UpdateInventory")
local dropEvent = ReplicatedStorage:WaitForChild("DropItem", 5)
local craftEvent = ReplicatedStorage:WaitForChild("CraftItem", 5)
local requestEvent = ReplicatedStorage:WaitForChild("RequestInventory")
-- No timeout here (unlike the others above): these go through an extra hop server-side
-- (InventoryManager boots -> spawns a task that requires ArmorManager -> that creates these),
-- so a fixed timeout risked returning nil permanently if that chain was slow to finish.
local equipArmorEvent = ReplicatedStorage:WaitForChild("EquipArmor")
local updateArmorEvent = ReplicatedStorage:WaitForChild("UpdateArmor")
local requestArmorEvent = ReplicatedStorage:WaitForChild("RequestArmor")
local eatItemEvent = ReplicatedStorage:WaitForChild("EatItem")
local equipSackEvent = ReplicatedStorage:WaitForChild("EquipSack")
local updateSackEvent = ReplicatedStorage:WaitForChild("UpdateSack")

-- Items that eat instead of hotbar-assigning when clicked. Mirrors HungerManager's FOOD_VALUES.
local FOOD_ITEMS = {
	MeatItem = true,
	CookedMeatItem = true,
}

local ARMOR_SLOT_ORDER = { "Helmet", "Chest", "Legs" }

-- Groups both the inventory list and the crafting list into sections, in this order. Anything
-- without a recipe entry (raw materials) has no Category and falls back to "Resources"; any
-- recipe missing a Category (shouldn't happen, but just in case) falls back to "Other".
local CATEGORY_ORDER = { "Tools", "Armor", "Bags", "Placeables", "Resources", "Other" }

local function categoryFor(itemName)
	local recipe = RecipesConfig[itemName]
	return (recipe and recipe.Category) or "Resources"
end

-- Collapse state persists across rebuilds (both tabs fully destroy-and-rebuild on every
-- inventory/recipe change), keyed by category name, one table per tab so collapsing "Tools" in
-- Crafting doesn't also collapse it in Inventory. Reset to all-shut every time the menu is
-- opened (see toggleTab) -- collapse choices don't carry over between separate visits.
local collapsedInventoryCategories = {}
local collapsedCraftingCategories = {}

local function collapseAllCategories(collapsedState)
	for _, categoryName in ipairs(CATEGORY_ORDER) do
		collapsedState[categoryName] = true
	end
end

-- Builds a clickable header that toggles `body`'s visibility. `collapsedState` is one of the
-- two tables above -- whichever tab this header belongs to -- so the open/shut state survives
-- the next full rebuild.
local function createSectionHeader(categoryName, parent, layoutOrder, body, collapsedState)
	local isCollapsed = collapsedState[categoryName] == true
	body.Visible = not isCollapsed

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 20)
	header.BackgroundTransparency = 1
	header.AutoButtonColor = false
	header.Text = ""
	header.LayoutOrder = layoutOrder
	header.Parent = parent

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = (isCollapsed and "\226\150\182 " or "\226\150\188 ") .. categoryName:upper()
	label.TextColor3 = Color3.fromRGB(180, 155, 130)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = header

	header.MouseButton1Click:Connect(function()
		local nowCollapsed = not (collapsedState[categoryName] == true)
		collapsedState[categoryName] = nowCollapsed
		body.Visible = not nowCollapsed
		label.Text = (nowCollapsed and "\226\150\182 " or "\226\150\188 ") .. categoryName:upper()
	end)

	return header
end

-- ===== 1. SCREEN GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainHud"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- ===== 2. SIDEBAR MENU =====
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.new(0, 60, 0, 300)
sidebar.Position = UDim2.new(0, 10, 0.5, -150)
sidebar.BackgroundTransparency = 1
sidebar.Parent = screenGui

local sidebarLayout = Instance.new("UIListLayout")
sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
sidebarLayout.Padding = UDim.new(0, 10)
sidebarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
sidebarLayout.Parent = sidebar

local function createSidebarButton(name, order, symbol)
	local btn = Instance.new("TextButton")
	btn.Name = name
	btn.Size = UDim2.new(0, 45, 0, 45)
	btn.BackgroundColor3 = Color3.fromRGB(87, 63, 43)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = symbol
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 18
	btn.LayoutOrder = order
	btn.Parent = sidebar

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 88, 58)
	stroke.Thickness = 2
	stroke.Parent = btn

	return btn
end

local invBtn = createSidebarButton("InventoryBtn", 1, "🎒")
local craftBtn = createSidebarButton("CraftingBtn", 2, "🔨")
local shopBtn = createSidebarButton("ShopBtn", 3, "🛒")
local codesBtn = createSidebarButton("CodesBtn", 4, "🎁")
local settingsBtn = createSidebarButton("SettingsBtn", 5, "⚙️")

-- ===== 3. MAIN CONTAINER =====
local mainWindow = Instance.new("Frame")
mainWindow.Name = "MainWindow"
mainWindow.Size = UDim2.new(0, 400, 0, 440)
mainWindow.Position = UDim2.new(0, 80, 0.5, -220)
mainWindow.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
mainWindow.BackgroundTransparency = 0.2
mainWindow.Visible = false
mainWindow.Parent = screenGui

local windowStroke = Instance.new("UIStroke")
windowStroke.Color = Color3.fromRGB(120, 88, 58)
windowStroke.Thickness = 2
windowStroke.Parent = mainWindow

local windowTitle = Instance.new("TextLabel")
windowTitle.Name = "Title"
windowTitle.Size = UDim2.new(1, -20, 0, 40)
windowTitle.Position = UDim2.new(0, 15, 0, 5)
windowTitle.BackgroundTransparency = 1
windowTitle.Text = "INVENTORY"
windowTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
windowTitle.Font = Enum.Font.GothamBold
windowTitle.TextSize = 16
windowTitle.TextXAlignment = Enum.TextXAlignment.Left
windowTitle.Parent = mainWindow

local weightLabel = Instance.new("TextLabel")
weightLabel.Name = "WeightLabel"
weightLabel.Size = UDim2.new(1, -20, 0, 40)
weightLabel.Position = UDim2.new(0, 0, 0, 5)
weightLabel.BackgroundTransparency = 1
weightLabel.Text = "Weight: 0 / 50"
weightLabel.TextColor3 = Color3.fromRGB(198, 172, 145)
weightLabel.Font = Enum.Font.Gotham
weightLabel.TextSize = 13
weightLabel.TextXAlignment = Enum.TextXAlignment.Right
weightLabel.Parent = mainWindow

-- ===== 4. EQUIPMENT ROW (Sack + Armor slots) =====
local equipmentRow = Instance.new("Frame")
equipmentRow.Name = "EquipmentRow"
equipmentRow.Size = UDim2.new(1, -20, 0, 66)
equipmentRow.Position = UDim2.new(0, 10, 0, 50)
equipmentRow.BackgroundTransparency = 1
equipmentRow.Parent = mainWindow

local equipmentLayout = Instance.new("UIListLayout")
equipmentLayout.FillDirection = Enum.FillDirection.Horizontal
equipmentLayout.Padding = UDim.new(0, 8)
equipmentLayout.Parent = equipmentRow

local function createEquipmentSlot(name, labelText)
	local box = Instance.new("Frame")
	box.Name = name
	box.Size = UDim2.new(0, 60, 0, 60)
	box.BackgroundColor3 = Color3.fromRGB(76, 55, 38)
	box.Parent = equipmentRow

	local stroke = Instance.new("UIStroke")
	stroke.Name = "EquippedBorder"
	stroke.Color = Color3.fromRGB(100, 200, 100)
	stroke.Thickness = 2
	stroke.Enabled = false
	stroke.Parent = box

	local icon = Instance.new("ViewportFrame")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 34, 0, 34)
	icon.Position = UDim2.new(0.5, -17, 0, 4)
	icon.BackgroundTransparency = 1
	icon.Parent = box

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.Size = UDim2.new(1, 0, 0, 14)
	caption.Position = UDim2.new(0, 0, 0, 40)
	caption.BackgroundTransparency = 1
	caption.Text = labelText
	caption.TextColor3 = Color3.fromRGB(198, 172, 145)
	caption.Font = Enum.Font.Gotham
	caption.TextSize = 10
	caption.Parent = box

	local fillBarBg = Instance.new("Frame")
	fillBarBg.Name = "FillBarBg"
	fillBarBg.Size = UDim2.new(1, -8, 0, 5)
	fillBarBg.Position = UDim2.new(0, 4, 1, -8)
	fillBarBg.BackgroundColor3 = Color3.fromRGB(42, 30, 21)
	fillBarBg.Visible = false
	fillBarBg.Parent = box

	local fillBarFg = Instance.new("Frame")
	fillBarFg.Name = "Fill"
	fillBarFg.Size = UDim2.new(0, 0, 1, 0)
	fillBarFg.BackgroundColor3 = Color3.fromRGB(90, 190, 255)
	fillBarFg.BorderSizePixel = 0
	fillBarFg.Parent = fillBarBg

	return box
end

local sackSlot = createEquipmentSlot("SackSlot", "Bag")
local armorSlotFrames = {}
armorSlotFrames.Helmet = createEquipmentSlot("HelmetSlot", "Helmet")
armorSlotFrames.Chest = createEquipmentSlot("ChestSlot", "Chest")
armorSlotFrames.Legs = createEquipmentSlot("LegsSlot", "Legs")

for slotName, box in pairs(armorSlotFrames) do
	box.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if equipArmorEvent then
				equipArmorEvent:FireServer(slotName, nil) -- unequip; no-ops if the slot is already empty
			end
		end
	end)
end

sackSlot.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if equipSackEvent then
			equipSackEvent:FireServer(nil) -- unequip; no-ops if nothing's equipped
		end
	end
end)

-- ===== 5. TAB CONTAINERS =====
local inventoryTab = Instance.new("ScrollingFrame")
inventoryTab.Name = "InventoryTab"
inventoryTab.Size = UDim2.new(1, -20, 1, -132)
inventoryTab.Position = UDim2.new(0, 10, 0, 122)
inventoryTab.BackgroundTransparency = 1
inventoryTab.BorderSizePixel = 0
inventoryTab.ScrollBarThickness = 6
inventoryTab.CanvasSize = UDim2.new(0, 0, 0, 0)
inventoryTab.AutomaticCanvasSize = Enum.AutomaticSize.Y
inventoryTab.Visible = true
inventoryTab.Parent = mainWindow

-- Stacks category sections vertically; each section has its own UIGridLayout for that
-- category's items (see createCategorySection below).
local invListLayout = Instance.new("UIListLayout")
invListLayout.SortOrder = Enum.SortOrder.LayoutOrder
invListLayout.Padding = UDim.new(0, 10)
invListLayout.Parent = inventoryTab

local craftingTab = Instance.new("ScrollingFrame")
craftingTab.Name = "CraftingTab"
craftingTab.Size = UDim2.new(1, -20, 1, -60)
craftingTab.Position = UDim2.new(0, 10, 0, 50)
craftingTab.BackgroundTransparency = 1
craftingTab.BorderSizePixel = 0
craftingTab.ScrollBarThickness = 6
craftingTab.CanvasSize = UDim2.new(0, 0, 0, 0)
craftingTab.AutomaticCanvasSize = Enum.AutomaticSize.Y
craftingTab.Visible = false
craftingTab.Parent = mainWindow

local craftListLayout = Instance.new("UIListLayout")
craftListLayout.SortOrder = Enum.SortOrder.LayoutOrder
craftListLayout.Padding = UDim.new(0, 6)
craftListLayout.Parent = craftingTab

local genericTab = Instance.new("Frame")
genericTab.Name = "GenericTab"
genericTab.Size = UDim2.new(1, -20, 1, -60)
genericTab.Position = UDim2.new(0, 10, 0, 50)
genericTab.BackgroundTransparency = 1
genericTab.Visible = false
genericTab.Parent = mainWindow

local genericMsg = Instance.new("TextLabel")
genericMsg.Size = UDim2.new(1, 0, 1, 0)
genericMsg.BackgroundTransparency = 1
genericMsg.Text = "Coming Soon..."
genericMsg.TextColor3 = Color3.fromRGB(198, 172, 145)
genericMsg.Font = Enum.Font.Gotham
genericMsg.TextSize = 16
genericMsg.Parent = genericTab

-- ===== 6. UI RENDERING =====
local currentInventory = {}
local currentArmor = {} -- [slotName] = itemName or nil
local currentSack = nil -- itemName or nil, the currently equipped sack
local lastWeight, lastMaxWeight = 0, 50
local hasAutoAssignedStarterItems = false

local function renderEquipment(currentWeight, maxWeight)
	-- Sack slot: shows the currently equipped sack (server-authoritative, synced via currentSack)
	-- with a fill bar for how full the current weight capacity is
	local sackName = currentSack
	local sackOwned = sackName ~= nil
	local sackIcon = sackSlot:FindFirstChild("Icon")
	local sackFillBg = sackSlot:FindFirstChild("FillBarBg")
	ItemIconRenderer.SetIcon(sackIcon, sackOwned and sackName or nil)
	sackSlot.EquippedBorder.Enabled = sackOwned
	sackFillBg.Visible = sackOwned
	if sackOwned and currentWeight and maxWeight and maxWeight > 0 then
		local fraction = math.clamp(currentWeight / maxWeight, 0, 1)
		sackFillBg.Fill.Size = UDim2.new(fraction, 0, 1, 0)
		sackFillBg.Fill.BackgroundColor3 = fraction < 0.85 and Color3.fromRGB(90, 190, 255) or Color3.fromRGB(230, 90, 90)
	end

	-- Armor slots: show whichever item is currently worn in each slot, if any
	for _, slotName in ipairs(ARMOR_SLOT_ORDER) do
		local box = armorSlotFrames[slotName]
		local itemName = currentArmor[slotName]
		ItemIconRenderer.SetIcon(box.Icon, itemName)
		box.EquippedBorder.Enabled = itemName ~= nil
	end
end

local function canCraft(recipe)
	for ingredient, needed in pairs(recipe.Ingredients) do
		if (currentInventory[ingredient] or 0) < needed then
			return false
		end
	end
	return true
end

local function createCraftingCard(recipeName, recipeData, layoutOrder, parent)
	local card = Instance.new("Frame")
	card.Name = recipeName
	card.Size = UDim2.new(1, 0, 0, 60)
	card.BackgroundColor3 = Color3.fromRGB(76, 55, 38)
	card.LayoutOrder = layoutOrder
	card.Parent = parent

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, -110, 0.5, 0)
	nameLbl.Position = UDim2.new(0, 12, 0, 8)
	nameLbl.BackgroundTransparency = 1
	nameLbl.Text = recipeData.DisplayName or recipeName
	nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLbl.Font = Enum.Font.GothamBold
	nameLbl.TextSize = 14
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Parent = card

	local reqLbl = Instance.new("TextLabel")
	reqLbl.Size = UDim2.new(1, -110, 0.5, 0)
	reqLbl.Position = UDim2.new(0, 12, 0.5, -2)
	reqLbl.BackgroundTransparency = 1
	reqLbl.Text = recipeData.ReqText
	reqLbl.TextColor3 = Color3.fromRGB(198, 172, 145)
	reqLbl.Font = Enum.Font.Gotham
	reqLbl.TextSize = 12
	reqLbl.TextXAlignment = Enum.TextXAlignment.Left
	reqLbl.Parent = card

	local cBtn = Instance.new("TextButton")
	cBtn.Size = UDim2.new(0, 85, 0, 36)
	cBtn.Position = UDim2.new(1, -95, 0.5, -18)
	cBtn.Font = Enum.Font.GothamBold
	cBtn.TextSize = 13
	cBtn.Parent = card

	if canCraft(recipeData) then
		cBtn.BackgroundColor3 = Color3.fromRGB(80, 180, 80)
		cBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		cBtn.Text = "CRAFT"
		cBtn.MouseButton1Click:Connect(function()
			if craftEvent then craftEvent:FireServer(recipeName) end
		end)
	else
		cBtn.BackgroundColor3 = Color3.fromRGB(90, 68, 50)
		cBtn.TextColor3 = Color3.fromRGB(160, 140, 120)
		cBtn.Text = "MISSING"
	end
end

local function renderCrafting()
	for _, child in ipairs(craftingTab:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- Group recipes by Category (see RecipesConfig.luau), then render one collapsible section per
	-- category in CATEGORY_ORDER -- each section is its own container (header + a body holding the
	-- cards) so the header can toggle just that category's cards, same structure as the inventory grid.
	local byCategory = {}
	for recipeName, recipeData in pairs(RecipesConfig) do
		local category = recipeData.Category or "Other"
		byCategory[category] = byCategory[category] or {}
		table.insert(byCategory[category], recipeName)
	end

	local sectionOrder = 0
	for _, categoryName in ipairs(CATEGORY_ORDER) do
		local recipeNames = byCategory[categoryName]
		if recipeNames and #recipeNames > 0 then
			table.sort(recipeNames)

			sectionOrder += 1
			local section = Instance.new("Frame")
			section.Name = categoryName .. "Section"
			section.Size = UDim2.new(1, 0, 0, 0)
			section.AutomaticSize = Enum.AutomaticSize.Y
			section.BackgroundTransparency = 1
			section.LayoutOrder = sectionOrder
			section.Parent = craftingTab

			local sectionLayout = Instance.new("UIListLayout")
			sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
			sectionLayout.Padding = UDim.new(0, 4)
			sectionLayout.Parent = section

			local body = Instance.new("Frame")
			body.Name = "Body"
			body.Size = UDim2.new(1, 0, 0, 0)
			body.AutomaticSize = Enum.AutomaticSize.Y
			body.BackgroundTransparency = 1
			body.LayoutOrder = 2
			body.Parent = section

			local bodyLayout = Instance.new("UIListLayout")
			bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
			bodyLayout.Padding = UDim.new(0, 6)
			bodyLayout.Parent = body

			createSectionHeader(categoryName, section, 1, body, collapsedCraftingCategories)

			for cardOrder, recipeName in ipairs(recipeNames) do
				createCraftingCard(recipeName, RecipesConfig[recipeName], cardOrder, body)
			end
		end
	end
end

local function refreshInventory(invData, currentWeight, maxWeight, hotbarRestoreData)
	if invData then currentInventory = invData end

	if hotbarRestoreData and not hasAutoAssignedStarterItems then
		-- A returning player's saved hotbar layout -- restore it instead of auto-assigning, and
		-- mark this done so the branch below (for brand new players) doesn't also fire.
		hasAutoAssignedStarterItems = true
		for i = 1, 9 do
			local itemName = hotbarRestoreData[i]
			if itemName then
				HotbarState.AssignItem(itemName)
			end
		end
	elseif invData and not hasAutoAssignedStarterItems then
		-- The very first inventory snapshot a brand new player ever receives is, by construction,
		-- nothing but the starter items (nothing else has had a chance to be added yet). Drop
		-- those straight into the hotbar instead of leaving them in the generic backpack list.
		hasAutoAssignedStarterItems = true
		for itemName in pairs(currentInventory) do
			local recipe = RecipesConfig[itemName]
			local isSack = recipe and recipe.EquipSlot == "Sack"
			if not isSack then
				HotbarState.AssignItem(itemName)
			end
		end
	end

	if currentWeight and maxWeight then
		lastWeight, lastMaxWeight = currentWeight, maxWeight
		weightLabel.Text = string.format("Weight: %d / %d", currentWeight, maxWeight)
	end

	HotbarState.Validate(currentInventory)
	local hotbarCounts = HotbarState.GetCounts()

	local armorCounts = {}
	for _, itemName in pairs(currentArmor) do
		if itemName then
			armorCounts[itemName] = (armorCounts[itemName] or 0) + 1
		end
	end

	for _, child in ipairs(inventoryTab:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- Group owned items by Category (see RecipesConfig.luau / categoryFor above) before building
	-- anything, so each category can get its own header + grid section.
	local byCategory = {}
	for itemName, totalCount in pairs(currentInventory) do
		local inHotbar = hotbarCounts[itemName] or 0
		local inArmorSlot = armorCounts[itemName] or 0
		-- Only the currently-equipped sack is pulled out of the generic list -- an owned but
		-- unequipped second sack (e.g. carrying both LeafBag and IronBackpack) still shows
		-- here so it can be clicked to switch.
		local inSackSlot = (itemName == currentSack) and 1 or 0
		local displayCount = totalCount - inHotbar - inArmorSlot - inSackSlot

		if displayCount > 0 then
			local category = categoryFor(itemName)
			byCategory[category] = byCategory[category] or {}
			table.insert(byCategory[category], { itemName = itemName, displayCount = displayCount })
		end
	end

	local sectionOrder = 0
	for _, categoryName in ipairs(CATEGORY_ORDER) do
		local entries = byCategory[categoryName]
		if entries and #entries > 0 then
			table.sort(entries, function(a, b) return a.itemName < b.itemName end)

			sectionOrder += 1
			local section = Instance.new("Frame")
			section.Name = categoryName .. "Section"
			section.Size = UDim2.new(1, 0, 0, 0)
			section.AutomaticSize = Enum.AutomaticSize.Y
			section.BackgroundTransparency = 1
			section.LayoutOrder = sectionOrder
			section.Parent = inventoryTab

			local sectionLayout = Instance.new("UIListLayout")
			sectionLayout.SortOrder = Enum.SortOrder.LayoutOrder
			sectionLayout.Padding = UDim.new(0, 4)
			sectionLayout.Parent = section

			local grid = Instance.new("Frame")
			grid.Name = "Grid"
			grid.Size = UDim2.new(1, 0, 0, 0)
			grid.AutomaticSize = Enum.AutomaticSize.Y
			grid.BackgroundTransparency = 1
			grid.LayoutOrder = 2
			grid.Parent = section

			local gridLayout = Instance.new("UIGridLayout")
			gridLayout.CellSize = UDim2.new(1, 0, 0, 55)
			gridLayout.CellPadding = UDim2.new(0, 0, 0, 6)
			gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
			gridLayout.Parent = grid

			createSectionHeader(categoryName, section, 1, grid, collapsedInventoryCategories)

			for itemOrder, entry in ipairs(entries) do
				local itemName = entry.itemName
				local displayCount = entry.displayCount
				local recipe = RecipesConfig[itemName]

				local slot = Instance.new("Frame")
				slot.Name = itemName
				slot.BackgroundColor3 = Color3.fromRGB(76, 55, 38)
				slot.LayoutOrder = itemOrder
				slot.Parent = grid

				local iconViewport = Instance.new("ViewportFrame")
				iconViewport.Size = UDim2.new(0, 40, 0, 40)
				iconViewport.Position = UDim2.new(0, 10, 0.5, -20)
				iconViewport.BackgroundTransparency = 1
				iconViewport.Parent = slot
				ItemIconRenderer.SetIcon(iconViewport, itemName)

				local nameLabel = Instance.new("TextLabel")
				nameLabel.Size = UDim2.new(1, -60, 0.5, 0)
				nameLabel.Position = UDim2.new(0, 60, 0, 8)
				nameLabel.BackgroundTransparency = 1
				nameLabel.Text = itemName
				nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextSize = 13
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.Parent = slot

				local countLabel = Instance.new("TextLabel")
				countLabel.Size = UDim2.new(1, -60, 0.5, 0)
				countLabel.Position = UDim2.new(0, 60, 0.5, -2)
				countLabel.BackgroundTransparency = 1
				countLabel.Text = "x" .. tostring(displayCount)
				countLabel.TextColor3 = Color3.fromRGB(198, 172, 145)
				countLabel.Font = Enum.Font.Gotham
				countLabel.TextSize = 12
				countLabel.TextXAlignment = Enum.TextXAlignment.Left
				countLabel.Parent = slot

				slot.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						if FOOD_ITEMS[itemName] then
							if eatItemEvent then eatItemEvent:FireServer(itemName) end
						elseif recipe and recipe.EquipSlot == "Sack" then
							if equipSackEvent then equipSackEvent:FireServer(itemName) end
						elseif recipe and recipe.ArmorSlot then
							if equipArmorEvent then equipArmorEvent:FireServer(recipe.ArmorSlot, itemName) end
						else
							-- Placeable items (e.g. Furnace) get assigned to the hotbar just like
							-- tools; equipping that slot is what starts placement mode, handled by
							-- PlacementController.client.luau.
							HotbarState.AssignItem(itemName)
						end
					elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
						if dropEvent then dropEvent:FireServer(itemName) end
					end
				end)
			end
		end
	end

	renderEquipment(lastWeight, lastMaxWeight)
	renderCrafting()
end

updateEvent.OnClientEvent:Connect(refreshInventory)
HotbarState.OnUpdate(function()
	refreshInventory(currentInventory)
end)

if updateArmorEvent then
	updateArmorEvent.OnClientEvent:Connect(function(armorData)
		currentArmor = armorData or {}
		refreshInventory(currentInventory)
	end)
end

if updateSackEvent then
	updateSackEvent.OnClientEvent:Connect(function(sackName)
		currentSack = sackName
		refreshInventory(currentInventory)
	end)
end

-- ===== 7. CONTROLLER LOGIC =====
local activeTab = nil

local function toggleTab(tabName)
	if activeTab == tabName then
		mainWindow.Visible = false
		activeTab = nil
	else
		mainWindow.Visible = true
		activeTab = tabName
		windowTitle.Text = tabName:upper()

		inventoryTab.Visible = (tabName == "Inventory")
		weightLabel.Visible = (tabName == "Inventory")
		equipmentRow.Visible = (tabName == "Inventory")
		craftingTab.Visible = (tabName == "Crafting")
		genericTab.Visible = (tabName ~= "Inventory" and tabName ~= "Crafting")

		-- Every category starts shut on each fresh open, rather than remembering what was
		-- expanded from a previous visit.
		collapseAllCategories(collapsedInventoryCategories)
		collapseAllCategories(collapsedCraftingCategories)
		refreshInventory(currentInventory)
	end
end

invBtn.MouseButton1Click:Connect(function() toggleTab("Inventory") end)
craftBtn.MouseButton1Click:Connect(function() toggleTab("Crafting") end)
shopBtn.MouseButton1Click:Connect(function() toggleTab("Shop") end)
codesBtn.MouseButton1Click:Connect(function() toggleTab("Codes") end)
settingsBtn.MouseButton1Click:Connect(function() toggleTab("Settings") end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.B then
		toggleTab("Inventory")
	elseif input.KeyCode == Enum.KeyCode.C then
		toggleTab("Crafting")
	end
end)

-- Ask the server for an inventory refresh the exact moment the UI script turns on
if requestEvent then requestEvent:FireServer() end
if requestArmorEvent then requestArmorEvent:FireServer() end