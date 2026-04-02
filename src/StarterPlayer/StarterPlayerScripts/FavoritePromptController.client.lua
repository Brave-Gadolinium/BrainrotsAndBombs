--!strict
-- LOCATION: StarterPlayerScripts/FavoritePromptController

local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local FAVORITE_ITEM_ID = game.PlaceId
local FAVORITE_ITEM_TYPE = Enum.AvatarItemType.Asset
local PROMPT_RETRY_DELAY_SECONDS = 1
local MAX_PROMPT_REQUEST_RETRIES = 3

local hasResolvedSessionPrompt = false
local promptRequestInFlight = false
local remainingPromptRequestRetries = MAX_PROMPT_REQUEST_RETRIES
local favoritePromptConnection: RBXScriptConnection? = nil

local function disconnectFavoritePromptConnection()
	if favoritePromptConnection then
		favoritePromptConnection:Disconnect()
		favoritePromptConnection = nil
	end
end

local function tryPromptFavoriteFlow()
	if hasResolvedSessionPrompt or promptRequestInFlight or RunService:IsStudio() then
		return
	end

	if FAVORITE_ITEM_ID <= 0 then
		hasResolvedSessionPrompt = true
		return
	end

	promptRequestInFlight = true
	disconnectFavoritePromptConnection()

	favoritePromptConnection = AvatarEditorService.PromptAllowInventoryReadAccessCompleted:Connect(function(result)
		disconnectFavoritePromptConnection()
		promptRequestInFlight = false
		hasResolvedSessionPrompt = true

		if result ~= Enum.AvatarPromptResult.Success then
			return
		end

		local ok, isFavorited = pcall(function()
			return AvatarEditorService:GetFavoriteAsync(FAVORITE_ITEM_ID, FAVORITE_ITEM_TYPE)
		end)
		if not ok or isFavorited == true then
			return
		end

		pcall(function()
			AvatarEditorService:PromptSetFavorite(FAVORITE_ITEM_ID, FAVORITE_ITEM_TYPE, true)
		end)
	end)

	local promptOk = pcall(function()
		AvatarEditorService:PromptAllowInventoryReadAccess()
	end)

	if not promptOk then
		disconnectFavoritePromptConnection()
		promptRequestInFlight = false

		if remainingPromptRequestRetries > 0 then
			remainingPromptRequestRetries -= 1
			task.delay(PROMPT_RETRY_DELAY_SECONDS, tryPromptFavoriteFlow)
			return
		end

		hasResolvedSessionPrompt = true
	end
end

player.CharacterAdded:Connect(function()
	task.defer(tryPromptFavoriteFlow)
end)

task.defer(tryPromptFavoriteFlow)
