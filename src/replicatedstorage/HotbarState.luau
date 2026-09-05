local HotbarState = {}

local slots = {} -- [slotIndex] = itemName or nil
local activeSlot = nil
local updateListeners = {}

local function notify()
	for _, callback in ipairs(updateListeners) do
		task.spawn(callback, slots, activeSlot)
	end
end

function HotbarState.OnUpdate(callback)
	table.insert(updateListeners, callback)
end

function HotbarState.GetSlots()
	return slots
end

function HotbarState.GetActiveSlot()
	return activeSlot
end

function HotbarState.SetActiveSlot(slotIndex)
	activeSlot = slotIndex
	notify()
end

function HotbarState.AssignItem(itemName)
	for i = 1, 9 do
		if not slots[i] then
			slots[i] = itemName
			notify()
			return true
		end
	end
	return false
end

function HotbarState.RemoveSlot(slotIndex)
	if slots[slotIndex] then
		slots[slotIndex] = nil
		notify()
	end
end

function HotbarState.GetCounts()
	local counts = {}
	for i = 1, 9 do
		local item = slots[i]
		if item then
			counts[item] = (counts[item] or 0) + 1
		end
	end
	return counts
end

function HotbarState.Validate(serverInventory)
	local currentCounts = {}
	local changed = false

	for i = 1, 9 do
		local item = slots[i]
		if item then
			currentCounts[item] = (currentCounts[item] or 0) + 1
			if currentCounts[item] > (serverInventory[item] or 0) then
				if activeSlot == i then
					activeSlot = nil
				end
				slots[i] = nil
				changed = true
			end
		end
	end

	if changed then
		notify()
	end
end

return HotbarState