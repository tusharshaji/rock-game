-- Script inside ServerScriptService / NodeRespawnManager
local ServerStorage = game:GetService("ServerStorage")

-- Create a BindableEvent so tools can talk to this script
local respawnEvent = Instance.new("BindableEvent")
respawnEvent.Name = "RespawnNodeEvent"
respawnEvent.Parent = ServerStorage

respawnEvent.Event:Connect(function(nodeClone, originalParent, respawnTime)
	-- Wait for the specific timer to finish
	task.wait(respawnTime)

	-- Reset health to full before spawning
	local maxHealth = nodeClone:GetAttribute("MaxHealth") or 100
	nodeClone:SetAttribute("Health", maxHealth)

	-- Return the node to the map
	nodeClone.Parent = originalParent
end)