--!strict
-- LOCATION: StarterPlayerScripts/GroupRewardController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Events = ReplicatedStorage:WaitForChild("Events")
local RequestGroupReward = Events:WaitForChild("RequestGroupReward") :: RemoteFunction

local CLAIM_TEXT = "Claim"
local CLAIMED_TEXT = "Claimed"

local MUTATION_MULTIPLIERS = {
	["Normal"] = 1,
	["Golden"] = 2,
	["Diamond"] = 3,
	["Ruby"] = 4,
	["Neon"] = 5,
}

local function setupRewardUI()
	local gui = playerGui:WaitForChild("GUI", 10)
	if not gui then return end

	local frames = gui:WaitForChild("Frames", 5)
	local rewards = frames and frames:WaitForChild("Rewards", 5)
	local scrolling = rewards and rewards:WaitForChild("Scrolling", 5)

	if not scrolling then return end

	-- 1. SETUP GIFT FRAME
	local giftFrame = scrolling:WaitForChild("Gift", 5)
	if giftFrame then
		local rewardConfig = ProductConfigurations.Group.Reward
		local itemData = ItemConfigurations.GetItemData(rewardConfig.Name)
		local displayName = itemData and itemData.DisplayName or rewardConfig.Name

		if itemData then
			local imageLabel = giftFrame:FindFirstChild("Image") :: ImageLabel
			if imageLabel and itemData.ImageId then
				imageLabel.Image = itemData.ImageId
			end

			local nameLabel = giftFrame:FindFirstChild("Name") :: TextLabel
			if nameLabel then
				nameLabel.Text = rewardConfig.Mutation .. " " .. displayName
			end

			local incomeLabel = giftFrame:FindFirstChild("Income") :: TextLabel
			if incomeLabel then
				local base = itemData.Income
				local mutMult = MUTATION_MULTIPLIERS[rewardConfig.Mutation] or 1
				local income = base * mutMult
				incomeLabel.Text = "+$" .. NumberFormatter.Format(income) .. "/s"
			end
		end
	end

	-- 2. SETUP CLAIM BUTTON
	local claimButton = scrolling:FindFirstChild("Claim") :: TextButton
	if claimButton then
		local textLabel = claimButton:FindFirstChild("Text") :: TextLabel
		if not textLabel then return end

		-- [[ STATUS CHECK LOGIC ]]
		local function updateState()
			local isClaimed = player:GetAttribute("GroupRewardClaimed") == true
			textLabel.Text = isClaimed and CLAIMED_TEXT or CLAIM_TEXT

			-- Optional: Disable button if claimed
			-- claimButton.Interactable = not isClaimed 
		end

		-- Run immediately
		updateState()

		-- Listen for when the Server finishes loading data
		player:GetAttributeChangedSignal("GroupRewardClaimed"):Connect(updateState)

		-- [[ INTERACTION ]]
		local debounce = false

		claimButton.MouseButton1Click:Connect(function()
			if debounce then return end
			if textLabel.Text == CLAIMED_TEXT then return end

			debounce = true

			local result = RequestGroupReward:InvokeServer()

			if result.Success then
				textLabel.Text = CLAIMED_TEXT
				NotificationManager.show("Reward Claimed Successfully!", "Success")
			else
				if result.Msg == "Already claimed!" then
					textLabel.Text = CLAIMED_TEXT
					NotificationManager.show(result.Msg, "Error")
				else
					textLabel.Text = CLAIM_TEXT
					NotificationManager.show(result.Msg or "Join Group first!", "Error")
				end
			end

			debounce = false
		end)
	end
end

if player.Character then
	setupRewardUI()
else
	player.CharacterAdded:Once(function()
		setupRewardUI()
	end)
end

print("[GroupRewardController] Loaded")
