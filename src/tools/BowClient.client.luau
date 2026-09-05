local tool = script.Parent
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local mouse = player:GetMouse()

tool.Activated:Connect(function()
	local fireEvent = tool:FindFirstChild("FireBowEvent")
	if fireEvent then
		-- Sends the world position of where your mouse cursor is pointing to the server
		fireEvent:FireServer(mouse.Hit.Position)
	end
end)
