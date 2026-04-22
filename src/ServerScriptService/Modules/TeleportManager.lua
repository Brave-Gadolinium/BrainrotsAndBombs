local TeleportManager = {}

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportPlayer = game.ReplicatedStorage.Remotes.Helper.TeleportPlayer
local SpawnUtils = require(ServerScriptService.Modules.SpawnUtils)

function TeleportManager.TeleportPlayerToBase(player: Player, heightOffset: number?): boolean
	if not player then return false end

	local character = player.Character
	if not character then return false end

	local characterRootPart = character:FindFirstChild("HumanoidRootPart")
	if not characterRootPart then return false end

	local plot = Workspace:FindFirstChild("Plot_" .. player.Name)
	if not plot then return false end

	local spawnCFrame = SpawnUtils.GetPlotSpawnCFrame(plot, heightOffset or 4)
	if not spawnCFrame then return false end

	character:PivotTo(spawnCFrame)
	return true
end

TeleportPlayer.OnServerEvent:Connect(function(player)
	TeleportManager.TeleportPlayerToBase(player, 4)
end)

return TeleportManager
