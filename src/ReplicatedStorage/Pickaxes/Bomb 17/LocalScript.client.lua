local tool = script.Parent
local player = game.Players.LocalPlayer
local mouse = player:GetMouse()

local remote = game.ReplicatedStorage.Remotes.Bomb.PlaceBomb

tool.Activated:Connect(function()
	if not player.Character then return end

	local position = player.Character:FindFirstChild('HumanoidRootPart').Position

	remote:FireServer(position)
end)