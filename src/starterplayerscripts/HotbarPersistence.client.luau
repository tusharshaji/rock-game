local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HotbarState = require(ReplicatedStorage:WaitForChild("HotbarState"))
local reportHotbarEvent = ReplicatedStorage:WaitForChild("ReportHotbar")

-- HotbarState is purely client-side, so this is the server's only way to know what's in it --
-- reports the current layout every time it changes, so InventoryManager's cached copy (used when
-- saving on leave) stays fresh without needing a live round-trip at logout time.
HotbarState.OnUpdate(function(slots)
	reportHotbarEvent:FireServer(slots)
end)
