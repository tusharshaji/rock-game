local StarterGui = game:GetService("StarterGui")

-- Disables every default Roblox core GUI element (backpack, health, chat, player list,
-- emotes menu, etc.) in one call, since custom UI now covers these.
local success = false
while not success do
	success = pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	task.wait(0.1)
end