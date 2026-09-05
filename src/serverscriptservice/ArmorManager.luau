local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local RecipesConfig = require(ReplicatedStorage:WaitForChild("RecipesConfig"))
local InventoryManager = require(ServerScriptService:WaitForChild("InventoryManager"))

local dropItemsFolder = ServerStorage:WaitForChild("DropItems")

local function getOrCreateRemote(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = ReplicatedStorage
	end
	return event
end

local equipArmorEvent = getOrCreateRemote("EquipArmor")
local updateArmorEvent = getOrCreateRemote("UpdateArmor")
local requestArmorEvent = getOrCreateRemote("RequestArmor")

local ARMOR_SLOTS = { "Helmet", "Chest", "Legs" }

local ArmorManager = {}
local equipped = {} -- [player] = { Helmet = itemName, Chest = itemName, Legs = itemName }

local function getState(player)
	if not equipped[player] then
		equipped[player] = {}
	end
	return equipped[player]
end

local function sync(player)
	updateArmorEvent:FireClient(player, getState(player))
end

-- Self-healing read: if a worn item was lost (e.g. death penalty), drop it from the slot here
-- rather than trying to coordinate with InventoryManager's removal timing.
function ArmorManager.GetEquipped(player)
	local state = getState(player)
	local inv = InventoryManager.GetInventory(player)
	for _, slotName in ipairs(ARMOR_SLOTS) do
		local itemName = state[slotName]
		if itemName and (inv[itemName] or 0) < 1 then
			state[slotName] = nil
		end
	end
	return state
end

-- Restores a saved equip state (from PlayerDataManager, via InventoryManager). Validated per-slot
-- against RecipesConfig rather than trusted as-is, in case a saved item was renamed/removed since
-- the save was written. Ownership isn't re-checked here -- GetEquipped's self-heal handles that
-- the next time it's read, once the inventory has also finished loading.
function ArmorManager.SetEquipped(player, savedState)
	if typeof(savedState) ~= "table" then return end
	local state = getState(player)

	for _, slotName in ipairs(ARMOR_SLOTS) do
		local itemName = savedState[slotName]
		if typeof(itemName) == "string" then
			local recipe = RecipesConfig[itemName]
			if recipe and recipe.ArmorSlot == slotName then
				state[slotName] = itemName
			end
		end
	end
end

function ArmorManager.GetDamageReduction(player)
	local state = ArmorManager.GetEquipped(player)
	local reduction = 0
	for _, slotName in ipairs(ARMOR_SLOTS) do
		local itemName = state[slotName]
		local recipe = itemName and RecipesConfig[itemName]
		if recipe and recipe.DamageReduction then
			reduction += recipe.DamageReduction
		end
	end
	return reduction
end

-- Same idea as GetDamageReduction, for armor (e.g. Cactus) that reflects a flat amount of damage
-- back at whoever dealt the hit, on top of (not instead of) the normal reduction. This is a flat
-- number, not a percentage of the incoming hit -- see ApplyDamage for how it gets applied.
function ArmorManager.GetDamageReflect(player)
	local state = ArmorManager.GetEquipped(player)
	local reflect = 0
	for _, slotName in ipairs(ARMOR_SLOTS) do
		local itemName = state[slotName]
		local recipe = itemName and RecipesConfig[itemName]
		if recipe and recipe.DamageReflect then
			reflect += recipe.DamageReflect
		end
	end
	return reflect
end

-- Applies a victim's armor reduction to a raw damage amount and calls Humanoid:TakeDamage.
-- attackerPlayer/attackingTool are both optional -- only real for player-vs-player hits, not
-- environmental damage (starvation, fall damage, etc.) -- and are what let reflect-type armor
-- (Cactus) damage the attacker back, and let a specific tool (Admin Pickaxe) opt out of triggering
-- that reflection at all, by name, via attackingTool.Name. Returns the actual damage dealt to the
-- victim (not counting any reflected damage).
function ArmorManager.ApplyDamage(player, humanoid, rawDamage, attackerPlayer, attackingTool)
	local reduction = ArmorManager.GetDamageReduction(player)
	local finalDamage = rawDamage * (1 - reduction)
	humanoid:TakeDamage(finalDamage)

	if attackerPlayer and (not attackingTool or attackingTool.Name ~= "AdminPickaxe") then
		local reflectDamage = ArmorManager.GetDamageReflect(player)
		if reflectDamage > 0 then
			local attackerCharacter = attackerPlayer.Character
			local attackerHumanoid = attackerCharacter and attackerCharacter:FindFirstChildOfClass("Humanoid")
			if attackerHumanoid and attackerHumanoid.Health > 0 then
				-- The reflected hit is itself just a hit -- it goes through the attacker's own
				-- armor reduction same as any other damage they'd take, rather than bypassing it.
				local attackerReduction = ArmorManager.GetDamageReduction(attackerPlayer)
				attackerHumanoid:TakeDamage(reflectDamage * (1 - attackerReduction))
			end
		end
	end

	return finalDamage
end

-- ===== VISUALS =====
-- Maps each armor slot to the character limb(s) its pieces get welded to. "default" covers a
-- template that's a single Part (e.g. the Helmet/Legs placeholder studs). "subParts" covers a
-- template that's a Model with named children (e.g. the Chest's Torso/LShoulder/RShoulder),
-- each welded to its own limb so they move independently instead of as one rigid block.
local ARMOR_LIMB_MAP = {
	Helmet = { default = "Head" },
	Chest = {
		default = "UpperTorso",
		subParts = {
			Torso = "UpperTorso",
			LShoulder = "LeftUpperArm",
			RShoulder = "RightUpperArm",
		},
	},
	Legs = {
		default = "LowerTorso",
		subParts = {
			Hip = "LowerTorso",
			RightUpperLeg = "RightUpperLeg",
			RightLowerLeg = "RightLowerLeg",
			LeftUpperLeg = "LeftUpperLeg",
			LeftLowerLeg = "LeftLowerLeg",
			RightFoot = "RightFoot",
			LeftFoot = "LeftFoot",
			["Left Foot"] = "LeftFoot", -- in case the part keeps its space instead of "LeftFoot"
		},
	},
}

-- ===== POSITION TUNING =====
-- Each piece is welded exactly onto its target limb's CFrame, then nudged by the offset below
-- (in the LIMB's local space): X = left(-)/right(+), Y = down(-)/up(+), Z = toward the limb's
-- back(-)/front(+). Edit these numbers to fix fit -- e.g. the chest's shoulders sitting low means
-- raising their Y value. Keyed by slot, then by sub-part name (or "default" for a single-Part
-- item like the Helmet/Legs placeholders).
local ARMOR_OFFSETS = {
	Chest = {
		Torso = CFrame.new(0, 0, 0),
		LShoulder = CFrame.new(0, 0.21, 0),
		RShoulder = CFrame.new(0, 0.22, 0),
	},
	Helmet = {
		-- Found by trial and error in Studio -- verified working.
		default = CFrame.new(0, 0.1, 0) * CFrame.Angles(-80.07, math.rad(90), 0),
	},
	Legs = {
		Hip = CFrame.new(0, 0, 0),
		RightUpperLeg = CFrame.new(0, 0, 0),
		RightLowerLeg = CFrame.new(0, 0, 0),
		LeftUpperLeg = CFrame.new(0, 0, 0),
		LeftLowerLeg = CFrame.new(0, 0, 0),
		RightFoot = CFrame.new(0, 0, 0),
		LeftFoot = CFrame.new(0, 0, 0),
		["Left Foot"] = CFrame.new(0, 0, 0),
		default = CFrame.new(0, 0, 0),
	},
}

-- Per-item corrections, checked before the slot's normal offset -- same shape as ARMOR_OFFSETS
-- (keyed by sub-part name, or "default" for a single-part item like a helmet), just scoped to one
-- specific item instead of the whole slot. Welding overwrites a clone's CFrame completely
-- (targetLimb.CFrame * offset, not relative), so an item's own Position/Orientation in
-- ServerStorage never survives to affect the final result -- only its baked local geometry does.
-- That means an item built from differently-rotated source pieces (e.g. a reskin unioned together
-- at a different angle than the original) can come out wrong even with the exact same offset the
-- original was tuned for. CactusChestplate/CactusLeggings start as plain copies of the normal
-- Chest/Legs offsets (i.e. no correction yet) -- adjust per sub-part here as testing in Studio
-- shows what's actually wrong, same trial-and-error process the Iron offsets were tuned with.
local ITEM_OFFSET_OVERRIDES = {
	-- Tuned live in-game via ArmorOffsetTuner -- confirmed working.
	CactusHelmet = {
		default = CFrame.new(0, 0.08, 0) * CFrame.Angles(math.rad(180), math.rad(90), math.rad(180)),
	},
	-- Tuned live in-game via ArmorOffsetTuner -- confirmed working.
	CactusChestplate = {
		Torso = CFrame.new(0, -0.1, -0.1),
		LShoulder = CFrame.new(0, 0.25, 0) * CFrame.Angles(math.rad(0), math.rad(-270), math.rad(0)),
		RShoulder = CFrame.new(0, 0.25, 0) * CFrame.Angles(math.rad(0), math.rad(-90), math.rad(0)),
	},
	-- Tuned live in-game via ArmorOffsetTuner -- confirmed working. RightFoot/LeftFoot weren't
	-- tuned (no override here), so they fall through to the Legs slot's plain defaults.
	CactusLeggings = {
		Hip = CFrame.new(0, -0.1, 0) * CFrame.Angles(math.rad(0), math.rad(-90), math.rad(270)),
		RightUpperLeg = CFrame.new(0, 0.05, 0) * CFrame.Angles(math.rad(0), math.rad(-90), math.rad(270)),
		LeftUpperLeg = CFrame.new(0, 0, 0) * CFrame.Angles(math.rad(0), math.rad(-90), math.rad(270)),
		RightLowerLeg = CFrame.new(0.05, 0.05, 0) * CFrame.Angles(math.rad(90), math.rad(0), math.rad(270)),
		LeftLowerLeg = CFrame.new(0.05, 0.05, 0) * CFrame.Angles(math.rad(90), math.rad(0), math.rad(90)),
	},
}

-- Runtime-only overrides set by ArmorOffsetTuner.server.luau for live in-game tuning -- same
-- shape as ITEM_OFFSET_OVERRIDES ([itemName][partName or "default"] = CFrame), checked first so a
-- live tweak immediately previews without editing this file. Not persisted anywhere; once a value
-- looks right in-game, it still needs to be copied into ITEM_OFFSET_OVERRIDES above by hand to
-- keep it permanently.
local liveOffsetOverrides = {}

function ArmorManager.SetLiveOffset(itemName, partName, cframe)
	liveOffsetOverrides[itemName] = liveOffsetOverrides[itemName] or {}
	liveOffsetOverrides[itemName][partName] = cframe
end

function ArmorManager.ClearLiveOffset(itemName)
	liveOffsetOverrides[itemName] = nil
end

local function getOffset(slotName, partName, itemName)
	local liveOffsets = itemName and liveOffsetOverrides[itemName]
	if liveOffsets then
		for offsetPartName, offset in pairs(liveOffsets) do
			if offsetPartName:lower() == partName:lower() then
				return offset
			end
		end
		if liveOffsets.default then
			return liveOffsets.default
		end
	end

	local itemOffsets = itemName and ITEM_OFFSET_OVERRIDES[itemName]
	if itemOffsets then
		for offsetPartName, offset in pairs(itemOffsets) do
			if offsetPartName:lower() == partName:lower() then
				return offset
			end
		end
		if itemOffsets.default then
			return itemOffsets.default
		end
	end

	local slotOffsets = ARMOR_OFFSETS[slotName]
	if not slotOffsets then return CFrame.new() end

	for offsetPartName, offset in pairs(slotOffsets) do
		if offsetPartName:lower() == partName:lower() then
			return offset
		end
	end
	return slotOffsets.default or CFrame.new()
end

local function visualNameFor(slotName)
	return "EquippedArmor_" .. slotName
end

local function weldPartToLimb(part, targetLimb, offset)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	part.CFrame = targetLimb.CFrame * (offset or CFrame.new())

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = targetLimb
	weld.Part1 = part
	weld.Parent = part
end

local function clearArmorVisual(character, slotName)
	local existing = character:FindFirstChild(visualNameFor(slotName))
	if existing then existing:Destroy() end
end

local HEAD_ACCESSORY_TYPES = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

-- Hides (or restores) hair/hat/face accessories on the character while a helmet is worn, so they
-- don't clip through it.
local function setHeadAccessoriesVisible(character, visible)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Accessory") and HEAD_ACCESSORY_TYPES[child.AccessoryType] then
			for _, descendant in ipairs(child:GetDescendants()) do
				if descendant:IsA("BasePart") or descendant:IsA("Decal") then
					descendant.Transparency = visible and 0 or 1
				end
			end
		end
	end
end

local function applyArmorVisual(character, slotName, itemName)
	clearArmorVisual(character, slotName)

	if slotName == "Helmet" then
		setHeadAccessoriesVisible(character, itemName == nil)
	end

	if not itemName then return end

	local template = dropItemsFolder:FindFirstChild(itemName)
	local limbMap = ARMOR_LIMB_MAP[slotName]
	if not template or not limbMap then return end

	local visual = Instance.new("Model")
	visual.Name = visualNameFor(slotName)

	if template:IsA("BasePart") then
		local targetLimb = character:FindFirstChild(limbMap.default)
		if targetLimb then
			local clone = template:Clone()
			clone.Parent = visual
			weldPartToLimb(clone, targetLimb, getOffset(slotName, "default", itemName))
			visual.PrimaryPart = clone
		end
	elseif template:IsA("Model") then
		for _, child in ipairs(template:GetChildren()) do
			if child:IsA("BasePart") then
				local targetLimbName = limbMap.default
				if limbMap.subParts then
					for subPartName, limbName in pairs(limbMap.subParts) do
						if subPartName:lower() == child.Name:lower() then
							targetLimbName = limbName
							break
						end
					end
				end
				local targetLimb = character:FindFirstChild(targetLimbName)
				if targetLimb then
					local clone = child:Clone()
					clone.Parent = visual
					weldPartToLimb(clone, targetLimb, getOffset(slotName, child.Name, itemName))
					if not visual.PrimaryPart then
						visual.PrimaryPart = clone
					end
				end
			end
		end
	end

	if visual.PrimaryPart then
		visual.Parent = character
	else
		visual:Destroy()
	end
end

local function refreshArmorVisuals(player)
	local character = player.Character
	if not character then return end

	local state = ArmorManager.GetEquipped(player) -- self-healing
	for _, slotName in ipairs(ARMOR_SLOTS) do
		applyArmorVisual(character, slotName, state[slotName])
	end
end

-- Public wrapper so ArmorOffsetTuner can force an immediate re-weld after changing a live offset,
-- without needing the player to re-equip.
function ArmorManager.RefreshVisuals(player)
	refreshArmorVisuals(player)
end

equipArmorEvent.OnServerEvent:Connect(function(player, slotName, itemName)
	if typeof(slotName) ~= "string" then return end

	local isValidSlot = false
	for _, s in ipairs(ARMOR_SLOTS) do
		if s == slotName then isValidSlot = true break end
	end
	if not isValidSlot then return end

	local state = getState(player)

	if itemName == nil then
		state[slotName] = nil
		sync(player)
		refreshArmorVisuals(player)
		return
	end

	if typeof(itemName) ~= "string" then return end

	local recipe = RecipesConfig[itemName]
	if not recipe or recipe.ArmorSlot ~= slotName then return end

	local inv = InventoryManager.GetInventory(player)
	if (inv[itemName] or 0) < 1 then return end

	state[slotName] = itemName
	sync(player)
	refreshArmorVisuals(player)
end)

requestArmorEvent.OnServerEvent:Connect(function(player)
	sync(player)
end)

Players.PlayerAdded:Connect(function(player)
	equipped[player] = {}

	-- Yields until InventoryManager's load finishes (once), so the restored equip state is ready
	-- before CharacterAdded fires and tries to apply visuals from it.
	local savedArmor = InventoryManager.ConsumePendingArmorRestore(player)
	if savedArmor then
		ArmorManager.SetEquipped(player, savedArmor)
	end
	sync(player)

	player.CharacterAdded:Connect(function()
		refreshArmorVisuals(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	equipped[player] = nil
end)

return ArmorManager
