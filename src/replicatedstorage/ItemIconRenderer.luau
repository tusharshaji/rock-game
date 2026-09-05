-- Renders item icons as live 3D previews inside a ViewportFrame, sourced directly from the
-- Model Photobooth exports in Workspace, instead of flat 2D images -- avoids needing to upload
-- and asset-id every single item icon. Usable from both client and server scripts (ReplicatedStorage).
local ItemIconRenderer = {}

local photoboothExports = workspace:WaitForChild("PhotoboothExports")

local CAMERA_FOV = 30
local CAMERA_DIRECTION = Vector3.new(1, 0.65, 1).Unit -- fixed angle so every icon reads consistently
local PADDING_FACTOR = 1.25 -- extra distance so the object doesn't touch the frame edges

local function findIconSource(itemName)
	return photoboothExports:FindFirstChild(itemName .. "_Icon")
end

function ItemIconRenderer.HasIcon(itemName)
	return findIconSource(itemName) ~= nil
end

-- Strips anything that could misbehave sitting in a ViewportFrame's isolated WorldModel (scripts
-- with no real Player/Backpack context to run against, sounds that could play unexpectedly).
local function sanitize(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Sound") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanQuery = false
		instance.CanTouch = false
	end
end

local function getBoundsCFrameAndSize(instance)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	elseif instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end
	return CFrame.new(), Vector3.new(2, 2, 2)
end

-- Populates (or repopulates) `viewport` with a live render of itemName's icon object, framed
-- automatically regardless of its actual size. Reuses the same WorldModel/Camera across repeated
-- calls (e.g. re-rendering a slot whose item changed) rather than recreating them each time.
-- Pass itemName = nil to clear the viewport. Returns true if an icon was found and rendered.
function ItemIconRenderer.SetIcon(viewport, itemName)
	local worldModel = viewport:FindFirstChildOfClass("WorldModel")
	if not worldModel then
		worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport
	end
	worldModel:ClearAllChildren()

	local camera = viewport:FindFirstChildOfClass("Camera")
	if not camera then
		camera = Instance.new("Camera")
		camera.FieldOfView = CAMERA_FOV
		camera.Parent = viewport
	end
	viewport.CurrentCamera = camera

	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.LightDirection = Vector3.new(-1, -1, -1)

	if not itemName then return false end

	local source = findIconSource(itemName)
	if not source then return false end

	local clone = source:Clone()
	sanitize(clone)
	clone.Parent = worldModel

	local boundsCFrame, size = getBoundsCFrameAndSize(clone)
	local radius = size.Magnitude / 2
	local halfFovRad = math.rad(CAMERA_FOV / 2)
	local distance = (radius / math.sin(halfFovRad)) * PADDING_FACTOR

	camera.CFrame = CFrame.new(boundsCFrame.Position + CAMERA_DIRECTION * distance, boundsCFrame.Position)

	return true
end

-- Convenience for the common case: build a brand new ViewportFrame already showing itemName's
-- icon, ready to have its Size/Position/Parent set. Returns nil if there's no icon for this item.
function ItemIconRenderer.CreateIcon(itemName)
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1

	if not ItemIconRenderer.SetIcon(viewport, itemName) then
		viewport:Destroy()
		return nil
	end

	return viewport
end

return ItemIconRenderer
