local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function getOrCreateRemote(name)
	local event = ReplicatedStorage:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = ReplicatedStorage
	end
	return event
end

-- Server -> client: tells the client to enter blueprint/ghost mode for this item right away.
local beginPlacementEvent = getOrCreateRemote("BeginPlacement")
-- Bidirectional: client -> server to request a cancel+refund (Cancel button, switching tool);
-- server -> client to tell it to drop the ghost/UI (used if a pending placement gets cleared some
-- other way than the client asking for it).
local cancelPlacementEvent = getOrCreateRemote("CancelPlacement")

local InventoryManager = require(ServerScriptService:WaitForChild("InventoryManager"))

local DeployablePlacementManager = {}

-- [player] = { itemName = string, ingredients = { [ingredientName] = amount } }. Only one pending
-- placement per player at a time -- InventoryManager's craft handler refuses to start a second one
-- while this is set, so a placement can never get silently overwritten (and its refund data lost).
local pending = {}

function DeployablePlacementManager.HasPending(player)
	return pending[player] ~= nil
end

function DeployablePlacementManager.IsPending(player, itemName)
	local state = pending[player]
	return state ~= nil and state.itemName == itemName
end

-- Called by InventoryManager right after a placeable recipe's ingredients are consumed. Sends the
-- player straight into blueprint mode instead of adding the crafted item to their inventory.
function DeployablePlacementManager.BeginPlacement(player, itemName, ingredients)
	pending[player] = { itemName = itemName, ingredients = ingredients }
	beginPlacementEvent:FireClient(player, itemName)
end

-- Called by FurnaceManager/BoatManager once the real object has actually been placed in the
-- world -- consumes the pending token without refunding (it was already spent on this placement).
function DeployablePlacementManager.ClearPending(player)
	pending[player] = nil
end

local function refundAndClear(player)
	local state = pending[player]
	if not state then return end
	pending[player] = nil

	for ingredientName, amount in pairs(state.ingredients) do
		InventoryManager.AddItem(player, ingredientName, amount)
	end
end

cancelPlacementEvent.OnServerEvent:Connect(function(player, itemName)
	local state = pending[player]
	if not state or state.itemName ~= itemName then return end
	refundAndClear(player)
end)

Players.PlayerRemoving:Connect(function(player)
	-- No refund here -- InventoryManager's own PlayerRemoving handler may run before or after this
	-- one (connection order between separate scripts isn't guaranteed), and calling AddItem after
	-- it's already saved-and-cleared this player's inventory would reseed a fresh one instead of
	-- crediting the refund. Leaving mid-placement is an edge case, not the cancel flow being asked
	-- for here.
	pending[player] = nil
end)

return DeployablePlacementManager
