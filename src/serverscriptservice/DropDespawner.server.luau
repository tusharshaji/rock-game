local CollectionService = game:GetService("CollectionService")

-- Every dropped/spawned pickupable item in this game (manual drops, death penalty, breakable
-- nodes, furnace output) gets tagged "Pickupable" -- rather than adding a despawn timer to each of
-- those separate spawn sites, this just watches the tag itself and despawns anything that isn't
-- picked up (which destroys it, removing the tag) within DESPAWN_TIME.
local DESPAWN_TIME = 300 -- 5 minutes

local function onDropAdded(drop)
	task.delay(DESPAWN_TIME, function()
		if drop.Parent then
			drop:Destroy()
		end
	end)
end

for _, drop in ipairs(CollectionService:GetTagged("Pickupable")) do
	onDropAdded(drop)
end
CollectionService:GetInstanceAddedSignal("Pickupable"):Connect(onDropAdded)
