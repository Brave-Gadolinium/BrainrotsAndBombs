--!strict
-- LOCATION: ServerScriptService/Controllers/FriendBoostController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FriendBoostConfiguration = require(ReplicatedStorage.Modules.FriendBoostConfiguration)

local FriendBoostController = {}

local function setBoostAttributes(player: Player, onlineFriendCount: number)
	player:SetAttribute("FriendBoostCount", onlineFriendCount)
	player:SetAttribute(
		"FriendBoostMultiplier",
		FriendBoostConfiguration.GetMultiplierForFriendCount(onlineFriendCount)
	)
end

local function getOnlineFriendCount(player: Player): number
	local total = 0

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			local success, isFriend = pcall(function()
				return player:IsFriendsWith(otherPlayer.UserId)
			end)

			if success and isFriend then
				total += 1
			end
		end
	end

	return total
end

function FriendBoostController:RefreshAll()
	for _, player in ipairs(Players:GetPlayers()) do
		setBoostAttributes(player, getOnlineFriendCount(player))
	end
end

function FriendBoostController:Start()
	Players.PlayerAdded:Connect(function()
		task.defer(function()
			self:RefreshAll()
		end)
	end)

	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			self:RefreshAll()
		end)
	end)

	self:RefreshAll()
end

return FriendBoostController
