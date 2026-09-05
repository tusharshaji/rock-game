local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

local HOLD_TIME = 2.5
local FADE_TIME = 0.35
local UPDATE_TIME = 0.2
-- No remote reports exactly what the local player hit, so proximity is used as a stand-in --
-- whichever trackable Breakable/Animal nearest the player's own character last changed Health is
-- treated as "the target". Generous enough to comfortably cover every tool's attack range (7-8
-- studs) plus some slack, small enough that a different player fighting something else nearby
-- shouldn't often trigger it.
local TRACK_RANGE = 15

local COLOR_LOW = Color3.fromRGB(220, 60, 60)
local COLOR_MID = Color3.fromRGB(240, 190, 60)
local COLOR_HIGH = Color3.fromRGB(80, 200, 120)

local function healthColor(percent)
	if percent >= 0.5 then
		return COLOR_MID:Lerp(COLOR_HIGH, (percent - 0.5) * 2)
	else
		return COLOR_LOW:Lerp(COLOR_MID, percent * 2)
	end
end

-- ===== UI: one shared bar at the top of the screen, not a BillboardGui per node. Same width
-- (360) and horizontal positioning convention (manual half-width offset, not AnchorPoint) as
-- LevelGuiLocal's XP bar, stacked directly beneath it so both left/right edges line up exactly.
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TargetHealthGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true -- sit right at the true top of the screen, matching LevelGuiLocal
screenGui.Parent = player:WaitForChild("PlayerGui")

local container = Instance.new("Frame")
container.Name = "TargetHealthContainer"
container.Size = UDim2.new(0, 360, 0, 16)
container.Position = UDim2.new(0.5, -180, 0, 22) -- XP bar sits at y=2, height 16 -- this starts right after it, plus a small gap
container.BackgroundTransparency = 1
container.Visible = false
container.Parent = screenGui

local track = Instance.new("Frame")
track.Name = "Track"
track.Size = UDim2.new(1, 0, 1, 0)
track.BackgroundColor3 = Color3.fromRGB(50, 36, 26)
track.BackgroundTransparency = 0.15
track.BorderSizePixel = 0
track.Parent = container

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(1, 0, 1, 0)
fill.BackgroundColor3 = COLOR_HIGH
fill.BorderSizePixel = 0
fill.ZIndex = 2
fill.Parent = track

local numbersText = Instance.new("TextLabel")
numbersText.Name = "Numbers"
numbersText.Size = UDim2.new(1, 0, 1, 0)
numbersText.BackgroundTransparency = 1
numbersText.Font = Enum.Font.GothamBold
numbersText.TextSize = 11
numbersText.TextColor3 = Color3.fromRGB(255, 255, 255)
numbersText.TextStrokeTransparency = 0.5
numbersText.ZIndex = 3
numbersText.Parent = track

local hideToken = 0

local function resetTransparency()
	track.BackgroundTransparency = 0.15
	fill.BackgroundTransparency = 0
	numbersText.TextTransparency = 0
	numbersText.TextStrokeTransparency = 0.5
end

local function show()
	hideToken += 1
	container.Visible = true
	resetTransparency()

	local myToken = hideToken
	task.delay(HOLD_TIME, function()
		if hideToken ~= myToken then return end

		local fadeInfo = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(track, fadeInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(fill, fadeInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(numbersText, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()

		task.wait(FADE_TIME)
		if hideToken == myToken then
			container.Visible = false
		end
	end)
end

-- ===== Tracking: same "Breakable" attribute (or "Animal" tag) as before, now on a Model or a
-- BasePart, since resource nodes are Models with the attributes set on the Model itself =====
local function isTrackable(instance)
	return instance:GetAttribute("Breakable") == true or CollectionService:HasTag(instance, "Animal")
end

local function getPosition(instance)
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	elseif instance:IsA("BasePart") then
		return instance.Position
	end
	return nil
end

local function isNearLocalPlayer(instance)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end

	local position = getPosition(instance)
	if not position then return false end

	return (position - rootPart.Position).Magnitude <= TRACK_RANGE
end

local processed = setmetatable({}, { __mode = "k" })

local function setupTracking(instance)
	if processed[instance] then return end
	if not (instance:IsA("BasePart") or instance:IsA("Model")) then return end
	if not isTrackable(instance) then return end

	-- Avoid double-tracking a node whose parent Model is also trackable.
	local ancestor = instance.Parent
	while ancestor do
		if (ancestor:IsA("BasePart") or ancestor:IsA("Model")) and isTrackable(ancestor) then
			return
		end
		ancestor = ancestor.Parent
	end

	processed[instance] = true

	instance:GetAttributeChangedSignal("Health"):Connect(function()
		if not isNearLocalPlayer(instance) then return end

		local maxHealth = instance:GetAttribute("MaxHealth") or 100
		local health = instance:GetAttribute("Health") or maxHealth
		local percent = math.clamp(health / maxHealth, 0, 1)

		numbersText.Text = string.format("%s: %d / %d", instance.Name, math.ceil(health), math.floor(maxHealth))

		TweenService:Create(fill, TweenInfo.new(UPDATE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(percent, 0, 1, 0),
			BackgroundColor3 = healthColor(percent),
		}):Play()

		show()
	end)
end

for _, desc in ipairs(workspace:GetDescendants()) do setupTracking(desc) end
workspace.DescendantAdded:Connect(setupTracking)
