--!strict

local ProfileReadyUtils = {}

ProfileReadyUtils.AttributeName = "ProfileReady"
ProfileReadyUtils.ProfileNotLoadedError = "ProfileNotLoaded"

local POLL_INTERVAL = 0.1

function ProfileReadyUtils.IsReady(player: Player): boolean
	return player:GetAttribute(ProfileReadyUtils.AttributeName) == true
end

function ProfileReadyUtils.WaitForReady(player: Player, timeoutSeconds: number?): boolean
	local timeout = tonumber(timeoutSeconds)
	local deadline = if type(timeout) == "number" and timeout > 0 then os.clock() + timeout else math.huge

	while player.Parent and not ProfileReadyUtils.IsReady(player) do
		if os.clock() >= deadline then
			return false
		end

		task.wait(POLL_INTERVAL)
	end

	return player.Parent ~= nil and ProfileReadyUtils.IsReady(player)
end

return ProfileReadyUtils
