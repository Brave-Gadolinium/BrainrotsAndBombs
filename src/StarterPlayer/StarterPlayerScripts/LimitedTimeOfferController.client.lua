--!strict
-- LOCATION: StarterPlayerScripts/LimitedTimeOfferController

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local LimitedTimeOfferConfiguration = require(ReplicatedStorage.Modules.LimitedTimeOfferConfiguration)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")
local events = ReplicatedStorage:WaitForChild("Events")
local reportAnalyticsIntent = events:WaitForChild("ReportAnalyticsIntent") :: RemoteEvent

local frame = frames:WaitForChild(LimitedTimeOfferConfiguration.FrameName, 10)
if not frame or not frame:IsA("GuiObject") then
	warn("[LimitedTimeOfferController] LimitedTimeOffer frame was not found.")
	return
end

local title = frame:WaitForChild("Title", 5)
local timerLabel = title and title:WaitForChild("timer", 5)
local main = frame:WaitForChild("Main", 5)
local right = main and main:WaitForChild("Right", 5)
local buyRobux = right and right:WaitForChild("BuyRobux", 5)
local buyButton = buyRobux and buyRobux:FindFirstChildWhichIsA("TextButton", true)
local priceLabel = buyRobux and (buyRobux:FindFirstChild("Cost", true) or buyRobux:FindFirstChild("Price", true))
local robuxSymbol = utf8.char(57346)

local passName = LimitedTimeOfferConfiguration.GamePassName
local passId = ProductConfigurations.GamePasses[passName]
local purchaseAttribute = LimitedTimeOfferConfiguration.PurchaseAttribute
local startAttribute = LimitedTimeOfferConfiguration.StartAttribute
local endAttribute = LimitedTimeOfferConfiguration.EndAttribute
local readyAttribute = LimitedTimeOfferConfiguration.ReadyAttribute

local autoOpenConsumed = false
local priceResolved = false

local function getServerTimestamp(): number
	return Workspace:GetServerTimeNow()
end

local function getOfferEndTime(): number
	return math.max(0, tonumber(player:GetAttribute(endAttribute)) or 0)
end

local function getRemainingSeconds(): number
	return math.max(0, math.floor(getOfferEndTime() - getServerTimestamp()))
end

local function isOfferReady(): boolean
	return player:GetAttribute(readyAttribute) == true
end

local function isOfferPurchased(): boolean
	return player:GetAttribute(purchaseAttribute) == true
end

local function isOfferExpired(): boolean
	local endTime = getOfferEndTime()
	return endTime <= 0 or getServerTimestamp() >= endTime
end

local function isOfferAvailable(): boolean
	if LimitedTimeOfferConfiguration.Enabled ~= true then
		return false
	end

	if not isOfferReady() then
		return false
	end

	if isOfferPurchased() then
		return false
	end

	if isOfferExpired() then
		return false
	end

	return tonumber(player:GetAttribute(startAttribute)) ~= nil
end

local function formatRemainingTime(remainingSeconds: number): string
	local totalHours = math.floor(remainingSeconds / 3600)
	local minutes = math.floor((remainingSeconds % 3600) / 60)
	local seconds = remainingSeconds % 60
	return string.format("%s %02d:%02d:%02d", LimitedTimeOfferConfiguration.TimerPrefix, totalHours, minutes, seconds)
end

local function refreshTimer()
	if timerLabel and timerLabel:IsA("TextLabel") then
		timerLabel.Text = formatRemainingTime(getRemainingSeconds())
	end
end

local function hideOffer()
	if FrameManager.getCurrentFrameName() == LimitedTimeOfferConfiguration.FrameName then
		FrameManager.close(LimitedTimeOfferConfiguration.FrameName)
	else
		frame.Visible = false
	end
end

local function refreshPriceLabel()
	if priceResolved or not priceLabel or not priceLabel:IsA("TextLabel") then
		return
	end

	if type(passId) ~= "number" or passId <= 0 then
		return
	end

	priceResolved = true
	task.spawn(function()
		local success, info = pcall(function()
			return MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)
		end)

		if not success or type(info) ~= "table" then
			priceResolved = false
			return
		end

		local price = tonumber(info.PriceInRobux)
		if not price or price <= 0 then
			priceResolved = false
			return
		end

		if priceLabel.Parent then
			priceLabel.Text = robuxSymbol .. " " .. tostring(math.floor(price))
		end
	end)
end

local function tryAutoOpen()
	if autoOpenConsumed or not isOfferAvailable() then
		return
	end

	if FrameManager.isAnyFrameOpen() then
		return
	end

	autoOpenConsumed = true
	refreshTimer()
	refreshPriceLabel()
	FrameManager.open(LimitedTimeOfferConfiguration.FrameName)
end

local function refreshOfferState()
	refreshTimer()
	refreshPriceLabel()

	if not isOfferAvailable() then
		hideOffer()
	end
end

if buyButton then
	buyButton.Text = "Buy"
	buyButton.Activated:Connect(function()
		if not isOfferAvailable() then
			hideOffer()
			return
		end

		if type(passId) ~= "number" or passId <= 0 then
			return
		end

		reportAnalyticsIntent:FireServer("StoreOfferPrompted", {
			surface = LimitedTimeOfferConfiguration.Surface,
			section = LimitedTimeOfferConfiguration.Section,
			entrypoint = LimitedTimeOfferConfiguration.Entrypoint,
			productName = passName,
			passId = passId,
			purchaseKind = "gamepass",
			paymentType = "robux",
		})

		local success, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, passId)
		end)
		if not success then
			warn("[LimitedTimeOfferController] Failed to prompt limited-time offer purchase:", err)
		end
	end)
else
	warn("[LimitedTimeOfferController] Buy button inside LimitedTimeOffer was not found.")
end

player:GetAttributeChangedSignal(readyAttribute):Connect(function()
	refreshOfferState()
	tryAutoOpen()
end)

player:GetAttributeChangedSignal(purchaseAttribute):Connect(function()
	refreshOfferState()
end)

player:GetAttributeChangedSignal(startAttribute):Connect(function()
	refreshOfferState()
	tryAutoOpen()
end)

player:GetAttributeChangedSignal(endAttribute):Connect(function()
	refreshOfferState()
	tryAutoOpen()
end)

FrameManager.Changed:Connect(function(anyFrameOpen)
	if not anyFrameOpen then
		tryAutoOpen()
	end
end)

task.spawn(function()
	while frame.Parent do
		refreshOfferState()
		task.wait(1)
	end
end)

task.defer(function()
	refreshOfferState()
	tryAutoOpen()
end)
