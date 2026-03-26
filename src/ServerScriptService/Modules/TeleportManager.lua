local TeleportManager = {}

local Workspace = game:GetService("Workspace")
local TeleportPlayer = game.ReplicatedStorage.Remotes.Helper.TeleportPlayer

TeleportPlayer.OnServerEvent:Connect(function(player)
	if not player then return end

	local character = player.Character
	if not character then return end

	local characterRootPart = character:FindFirstChild("HumanoidRootPart")
	if not characterRootPart then return end

	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if not plot then return end

	local spawnPart = plot:FindFirstChild("Spawn", true)
	if not spawnPart or not spawnPart:IsA("BasePart") then return end

	character:PivotTo(spawnPart.CFrame + Vector3.new(0, 4, 0))
end)

return TeleportManager
