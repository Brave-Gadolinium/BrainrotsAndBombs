--!strict
-- LOCATION: ServerScriptService/Controllers/ExitGameController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExitGameController = {}

local confirmExitRemote: RemoteEvent? = nil

local function ensureRemotePath(): RemoteEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local helperFolder = remotesFolder:FindFirstChild("Helper")
	if not helperFolder then
		helperFolder = Instance.new("Folder")
		helperFolder.Name = "Helper"
		helperFolder.Parent = remotesFolder
	end

	local remote = helperFolder:FindFirstChild("ConfirmExitGame")
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	local createdRemote = Instance.new("RemoteEvent")
	createdRemote.Name = "ConfirmExitGame"
	createdRemote.Parent = helperFolder
	return createdRemote
end

function ExitGameController:Init()
	confirmExitRemote = ensureRemotePath()

	confirmExitRemote.OnServerEvent:Connect(function(player)
		if not player or player.Parent ~= Players then
			return
		end

		task.defer(function()
			if player.Parent == Players then
				player:Kick("Thanks for playing!")
			end
		end)
	end)
end

return ExitGameController
