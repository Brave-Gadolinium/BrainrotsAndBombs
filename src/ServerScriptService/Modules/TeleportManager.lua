local TeleportManager = {}

local TeleportPlayer = game.ReplicatedStorage.Remotes.Helper.TeleportPlayer

TeleportPlayer.OnServerEvent:Connect(function(player, targetPlayer)
	if not player or not targetPlayer then return end
	
	local character = player.Character
	local targetCharacter = targetPlayer.Character
	if not character or not targetCharacter then return end
	
	local characterRootPart = character:FindFirstChild("HumanoidRootPart")
	local targetCharacterRootPart = game.Workspace.PointToTeleport.PrimaryPart
	if not characterRootPart or not targetCharacterRootPart then return end
	
	character:MoveTo(targetCharacterRootPart.Position)
end)

return TeleportManager
