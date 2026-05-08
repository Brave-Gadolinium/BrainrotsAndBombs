--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CandyEventConfiguration = require(ReplicatedStorage.Modules.CandyEventConfiguration)
local DailySpinConfiguration = require(ReplicatedStorage.Modules.DailySpinConfiguration)
local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

type RewardPayload = {
	sourceFrame: string?,
	index: number?,
	reward: {
		name: string?,
		icon: string?,
	}?,
	chanceText: string?,
}

type DisplayData = {
	sourceFrame: string,
	name: string,
	icon: string,
	chanceText: string,
}

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui"):WaitForChild("GUI")
local itemGetFrame = gui:WaitForChild("ItemGet") :: GuiObject
local itemGetRewardImageInstance = itemGetFrame:WaitForChild("Item")
local itemGetYouGot = itemGetFrame:WaitForChild("YouGot") :: TextLabel
local itemGetChance = itemGetFrame:WaitForChild("Chance") :: TextLabel
local itemGetSpinButton = itemGetFrame:WaitForChild("SpinButton") :: GuiButton
local itemGetClose = itemGetFrame:FindFirstChild("Close")

if not (itemGetRewardImageInstance:IsA("ImageLabel") or itemGetRewardImageInstance:IsA("ImageButton")) then
	warn("[ItemGetController] GUI.ItemGet.Item must be an ImageLabel or ImageButton.")
	return
end

local itemGetRewardImage = itemGetRewardImageInstance :: ImageLabel | ImageButton

local function ensureCorner(instance: GuiObject, radius: UDim)
	if instance:FindFirstChildOfClass("UICorner") then
		return
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius
	corner.Parent = instance
end

local function applyDefaultLayout()
	itemGetFrame.Visible = false

	if itemGetFrame:GetAttribute("SkipRuntimeLayout") == true then
		return
	end

	itemGetFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	itemGetFrame.Position = UDim2.fromScale(0.5, 0.5)
	--itemGetFrame.Size = UDim2.fromScale(0.32, 0.42)
	itemGetFrame.BackgroundColor3 = Color3.fromRGB(30, 32, 42)
	itemGetFrame.BorderSizePixel = 0
	ensureCorner(itemGetFrame, UDim.new(0, 8))

	local rewardImage = itemGetRewardImage
	rewardImage.AnchorPoint = Vector2.new(0.5, 0)
	rewardImage.Position = UDim2.fromScale(0.5, 0.12)
	rewardImage.Size = UDim2.fromScale(0.42, 0.42)
	rewardImage.BackgroundTransparency = 1
	rewardImage.ScaleType = Enum.ScaleType.Fit
	rewardImage.ImageColor3 = Color3.new(1, 1, 1)

	itemGetYouGot.AnchorPoint = Vector2.new(0.5, 0)
	itemGetYouGot.Position = UDim2.fromScale(0.5, 0.56)
	itemGetYouGot.Size = UDim2.fromScale(0.86, 0.13)
	itemGetYouGot.BackgroundTransparency = 1
	itemGetYouGot.Font = Enum.Font.GothamBlack
	itemGetYouGot.TextColor3 = Color3.fromRGB(255, 255, 255)
	itemGetYouGot.TextScaled = true

	itemGetChance.AnchorPoint = Vector2.new(0.5, 0)
	itemGetChance.Position = UDim2.fromScale(0.5, 0.7)
	itemGetChance.Size = UDim2.fromScale(0.7, 0.08)
	itemGetChance.BackgroundTransparency = 1
	itemGetChance.Font = Enum.Font.GothamBold
	itemGetChance.TextColor3 = Color3.fromRGB(255, 214, 90)
	itemGetChance.TextScaled = true

	itemGetSpinButton.AnchorPoint = Vector2.new(0.5, 1)
	itemGetSpinButton.Position = UDim2.fromScale(0.5, 0.92)
	itemGetSpinButton.Size = UDim2.fromScale(0.56, 0.13)
	itemGetSpinButton.BackgroundColor3 = Color3.fromRGB(255, 196, 62)
	itemGetSpinButton.BorderSizePixel = 0
	ensureCorner(itemGetSpinButton, UDim.new(0, 8))
	if itemGetSpinButton:IsA("TextButton") then
		itemGetSpinButton.Font = Enum.Font.GothamBlack
		itemGetSpinButton.Text = "Spin Again"
		itemGetSpinButton.TextColor3 = Color3.fromRGB(35, 28, 15)
		itemGetSpinButton.TextScaled = true
	end

	if itemGetClose and itemGetClose:IsA("GuiButton") then
		itemGetClose.AnchorPoint = Vector2.new(1, 0)
		itemGetClose.Position = UDim2.fromScale(0.96, 0.04)
		itemGetClose.Size = UDim2.fromScale(0.1, 0.1)
		itemGetClose.BackgroundColor3 = Color3.fromRGB(66, 68, 80)
		itemGetClose.BorderSizePixel = 0
		ensureCorner(itemGetClose, UDim.new(1, 0))
		if itemGetClose:IsA("TextButton") then
			itemGetClose.Font = Enum.Font.GothamBlack
			itemGetClose.Text = "X"
			itemGetClose.TextColor3 = Color3.fromRGB(255, 255, 255)
			itemGetClose.TextScaled = true
		end
	end
end

local function getNonEmptyString(value: any): string?
	if type(value) == "string" and value ~= "" then
		return value
	end

	return nil
end

local function formatPercent(value: number): string
	if math.floor(value) == value then
		return string.format("%d%%", value)
	end

	return string.format("%.1f%%", value)
end

local function getWeightChanceText(chance: number?, totalWeight: number): string
	local weight = tonumber(chance) or 0
	if totalWeight <= 0 or weight <= 0 then
		return ""
	end

	return formatPercent((weight / totalWeight) * 100)
end

local function getDailyFallback(index: number): (string, string, string)
	local reward = DailySpinConfiguration.Rewards[index]
	if type(reward) ~= "table" then
		return "Reward", "", ""
	end

	local name = reward.DisplayName or reward.Name or "Reward"
	local icon = reward.Image or ""

	if reward.Type == "Cash" and type(reward.Amount) == "number" then
		name = reward.DisplayName or ("$" .. NumberFormatter.Format(reward.Amount) .. " cash")
	elseif reward.Type == "Spins" and type(reward.Amount) == "number" then
		name = reward.DisplayName or ("+" .. tostring(reward.Amount) .. " spins")
	elseif reward.Type == "Pickaxe" then
		name = reward.DisplayName or reward.PickaxeName or name
	elseif reward.Type == "Item" or reward.Type == "RandomItemByRarity" then
		local itemData = type(reward.Name) == "string" and ItemConfigurations.GetItemData(reward.Name) or nil
		name = (itemData and itemData.DisplayName) or reward.ResolvedDisplayName or reward.DisplayName or reward.Name or name
		icon = (itemData and itemData.ImageId) or icon
	end

	local displayChance = (reward :: any).DisplayChance
	local chanceText = if type(displayChance) == "string"
		then displayChance
		else getWeightChanceText(reward.Chance, DailySpinConfiguration.GetTotalWeight())

	return name, icon, chanceText
end

local function getCandyFallback(index: number): (string, string, string)
	local reward = CandyEventConfiguration.Rewards[index]
	if type(reward) ~= "table" then
		return "Reward", "", ""
	end

	local chanceText = ""
	local displayChance = tonumber(reward.DisplayChance)
	if displayChance and displayChance > 0 then
		chanceText = formatPercent(displayChance)
	end

	return reward.DisplayName or "Reward", reward.Image or "", chanceText
end

local function normalizeSourceFrame(sourceFrame: string?, defaultSourceFrame: string): string
	local source = getNonEmptyString(sourceFrame) or defaultSourceFrame
	if source == "Wheel" or source == "CandyWheel" then
		return source
	end

	return defaultSourceFrame
end

local function buildDisplayData(payload: RewardPayload, defaultSourceFrame: string): DisplayData
	local sourceFrame = normalizeSourceFrame(payload.sourceFrame, defaultSourceFrame)
	local index = math.max(1, math.floor(tonumber(payload.index) or 1))
	local fallbackName, fallbackIcon, fallbackChanceText

	if sourceFrame == "CandyWheel" then
		fallbackName, fallbackIcon, fallbackChanceText = getCandyFallback(index)
	else
		fallbackName, fallbackIcon, fallbackChanceText = getDailyFallback(index)
	end

	local rewardData = if type(payload.reward) == "table" then payload.reward else nil
	local name = (rewardData and getNonEmptyString(rewardData.name)) or fallbackName
	local icon = (rewardData and getNonEmptyString(rewardData.icon)) or fallbackIcon
	local chanceText = getNonEmptyString(payload.chanceText) or fallbackChanceText

	return {
		sourceFrame = sourceFrame,
		name = name,
		icon = icon,
		chanceText = chanceText,
	}
end

local function showItemGet(rawPayload: any, defaultSourceFrame: string)
	local payload: RewardPayload = {}
	if type(rawPayload) == "table" then
		payload = rawPayload :: RewardPayload
	end

	local displayData = buildDisplayData(payload, defaultSourceFrame)

	itemGetRewardImage.Image = displayData.icon
	itemGetRewardImage.ImageColor3 = Color3.new(1, 1, 1)
	itemGetYouGot.Text = ("You got %s"):format(displayData.name)
	itemGetChance.Text = displayData.chanceText
	itemGetFrame:SetAttribute("SourceFrame", displayData.sourceFrame)
	FrameManager.open("ItemGet")
end

applyDefaultLayout()

itemGetSpinButton.Activated:Connect(function()
	local sourceFrame = normalizeSourceFrame(getNonEmptyString(itemGetFrame:GetAttribute("SourceFrame")), "Wheel")
	FrameManager.close("ItemGet")
	FrameManager.open(sourceFrame)
end)

if itemGetClose and itemGetClose:IsA("GuiButton") then
	itemGetClose.Activated:Connect(function()
		FrameManager.close("ItemGet")
	end)
end

local events = ReplicatedStorage:WaitForChild("Events")
local dailySpinRewardGranted = events:WaitForChild("DailySpinRewardGranted") :: RemoteEvent
dailySpinRewardGranted.OnClientEvent:Connect(function(payload)
	showItemGet(payload, "Wheel")
end)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local candyEventRemotes = remotes:WaitForChild("CandyEvent")
local candyRewardGranted = candyEventRemotes:WaitForChild("RewardGranted") :: RemoteEvent
candyRewardGranted.OnClientEvent:Connect(function(payload)
	showItemGet(payload, "CandyWheel")
end)
