local TeleportManager = {}

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportPlayer = game.ReplicatedStorage.Remotes.Helper.TeleportPlayer
local SpawnUtils = require(ServerScriptService.Modules.SpawnUtils)

TeleportPlayer.OnServerEvent:Connect(function(player)
	if not player then return end

	local character = player.Character
	if not character then return end

	local characterRootPart = character:FindFirstChild("HumanoidRootPart")
	if not characterRootPart then return end

	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if not plot then return end

	local spawnCFrame = SpawnUtils.GetPlotSpawnCFrame(plot, 4)
	if not spawnCFrame then return end

	character:PivotTo(spawnCFrame)
end)

return TeleportManager
