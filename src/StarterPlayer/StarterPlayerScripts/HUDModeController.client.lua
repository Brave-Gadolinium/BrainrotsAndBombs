--!strict
-- LOCATION: StarterPlayerScripts/HUDModeController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientZoneService = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ClientZoneService"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local hud = gui:WaitForChild("HUD")
local events = ReplicatedStorage:WaitForChild("Events")
local requestAutoBombState = events:WaitForChild("RequestAutoBombState") :: RemoteEvent

local backButton: GuiObject? = nil
local autoBombFrame: GuiObject? = nil
local progressBar: GuiObject? = nil
local wheelButton: GuiObject? = nil
local spinnyWheel: GuiObject? = nil
local extraHudIcons: {GuiObject} = {}

local lastInMineZone: boolean? = nil

local EXTRA_HUD_ICON_CANDIDATES = {
	{"DailyRewards", "DailyRewardsButton"},
	{"Index", "IndexButton"},
	{"PlaytimeRewards", "PlaytimeRewardsButton"},
	{"Rebirth", "RebirthButton"},
	{"Codes", "CodesButton", "RedeemCodesFrame", "RedeemCodesFrameButton"},
	{"Shop", "ShopButton"},
}

local WATCHED_HUD_NAMES = {
	ProgressBar = true,
	Back = true,
	Autobomb = true,
	Wheel = true,
	SpinnyWheel = true,
	DailyRewards = true,
	DailyRewardsButton = true,
	Index = true,
	IndexButton = true,
	PlaytimeRewards = true,
	PlaytimeRewardsButton = true,
	Rebirth = true,
	RebirthButton = true,
	Codes = true,
	CodesButton = true,
	RedeemCodesFrame = true,
	RedeemCodesFrameButton = true,
	Shop = true,
	ShopButton = true,
}

local function findHudGuiObject(candidateNames: {string}): GuiObject?
	for _, candidateName in ipairs(candidateNames) do
		local instance = hud:FindFirstChild(candidateName, true)
		if instance and instance:IsA("GuiObject") then
			return instance
		end
	end

	return nil
end

local function resolveHudElements()
	progressBar = hud:FindFirstChild("ProgressBar") :: GuiObject?
	backButton = hud:FindFirstChild("Back") :: GuiObject?
	spinnyWheel = hud:FindFirstChild("SpinnyWheel") :: GuiObject?

	local leftPanel = hud:FindFirstChild("Left")
	local buttons1 = leftPanel and leftPanel:FindFirstChild("Buttons1")
	local buttons2 = leftPanel and leftPanel:FindFirstChild("Buttons2")

	autoBombFrame = buttons1 and buttons1:FindFirstChild("Autobomb") :: GuiObject?
	wheelButton = buttons2 and buttons2:FindFirstChild("Wheel") :: GuiObject?

	table.clear(extraHudIcons)
	for _, candidateNames in ipairs(EXTRA_HUD_ICON_CANDIDATES) do
		local target = findHudGuiObject(candidateNames)
		if target then
			table.insert(extraHudIcons, target)
		end
	end
end

local function setModeVisibility(target: GuiObject?, visible: boolean)
	if not target then
		return
	end

	target:SetAttribute("HUDModeVisible", visible)
	if not visible then
		target.Visible = false
	end
end

local function setDirectVisibility(target: GuiObject?, visible: boolean)
	if not target then
		return
	end

	target.Visible = visible
end

local function applyHudMode(inMineZone: boolean)
	resolveHudElements()

	setDirectVisibility(progressBar, inMineZone)
	setModeVisibility(backButton, inMineZone)
	setModeVisibility(autoBombFrame, inMineZone)
	setDirectVisibility(wheelButton, not inMineZone)
	setDirectVisibility(spinnyWheel, not inMineZone)

	for _, target in ipairs(extraHudIcons) do
		setDirectVisibility(target, not inMineZone)
	end
end

local function syncHudMode()
	local inMineZone = ClientZoneService.IsInMineZone()
	applyHudMode(inMineZone)

	if lastInMineZone == true and not inMineZone then
		requestAutoBombState:FireServer(false)
	end

	lastInMineZone = inMineZone
end

hud.DescendantAdded:Connect(function(descendant)
	local name = descendant.Name
	if WATCHED_HUD_NAMES[name] then
		task.defer(syncHudMode)
	end
end)

hud.DescendantRemoving:Connect(function(descendant)
	if descendant == progressBar or descendant == backButton or descendant == autoBombFrame or descendant == wheelButton or descendant == spinnyWheel then
		task.defer(syncHudMode)
	end
end)

ClientZoneService.Changed:Connect(function()
	syncHudMode()
end)

player:GetAttributeChangedSignal("OnboardingStep"):Connect(function()
	task.defer(syncHudMode)
end)

player.CharacterAdded:Connect(function()
	task.defer(syncHudMode)
end)

player.CharacterRemoving:Connect(function()
	task.defer(syncHudMode)
end)

task.defer(syncHudMode)
