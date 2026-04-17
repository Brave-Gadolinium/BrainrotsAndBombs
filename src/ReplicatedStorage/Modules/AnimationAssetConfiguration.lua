--!strict

local AnimationAssetConfiguration = {}

-- Set this to a shared/public asset id once the experience-owned idle animation is available.
AnimationAssetConfiguration.SharedIdleAnimationId = ""

local function normalizeAnimationId(rawAnimationId: any): string?
	if type(rawAnimationId) ~= "string" then
		return nil
	end

	local trimmed = string.match(rawAnimationId, "%S+")
	if not trimmed or trimmed == "" or trimmed == "rbxassetid://" then
		return nil
	end

	if string.match(trimmed, "^%d+$") then
		return "rbxassetid://" .. trimmed
	end

	return trimmed
end

function AnimationAssetConfiguration.GetSharedIdleAnimationId(): string?
	return normalizeAnimationId(AnimationAssetConfiguration.SharedIdleAnimationId)
end

return AnimationAssetConfiguration
