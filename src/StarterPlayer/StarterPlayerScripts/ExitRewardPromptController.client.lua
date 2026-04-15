--!strict
-- LOCATION: StarterPlayerScripts/ExitRewardPromptController

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local FrameManager = require(ReplicatedStorage.Modules:WaitForChild("FrameManager"))
local TutorialConfiguration = require(ReplicatedStorage.Modules:WaitForChild("TutorialConfiguration"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")
local frames = gui:WaitForChild("Frames")
local globalSounds = Workspace:FindFirstChild("Sounds")

local playtimeRewardsRemotes = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlaytimeRewards")
local getStatusRemote = playtimeRewardsRemotes:WaitForChild("GetStatus") :: RemoteFunction
local confirmExitRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Helper"):WaitForChild("ConfirmExitGame") :: RemoteEvent

local REQUIRED_PLAYTIME_SECONDS = 30 * 60
local MENU_OPEN_MIN_DURATION = 0.75
local PROMPT_TITLE = "WAIT!"
local PROMPT_SUBTITLE = "CHECK YOUR REWARDS!"
local PROMPT_OPEN_TEXT = "OPEN"

local cachedFrame: GuiObject? = nil
local hasInterceptedThisSession = false
local pendingMenuIntercept = false
local menuOpenedAt = 0

local function isTutorialActive(): boolean
	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep > 0 and onboardingStep < TutorialConfiguration.FinalStep
end

local function playRewardPromptSound()
	if not globalSounds or globalSounds.Parent == nil then
		globalSounds = Workspace:FindFirstChild("Sounds")
	end

	local soundTemplate = globalSounds and globalSounds:FindFirstChild("Reward")
	if not soundTemplate or not soundTemplate:IsA("Sound") then
		return
	end

	local rewardSound = soundTemplate:Clone()
	rewardSound.Parent = Workspace.CurrentCamera or Workspace
	rewardSound:Play()
	Debris:AddItem(rewardSound, math.max(rewardSound.TimeLength, 0.1) + 0.1)
end

local function isTextInstance(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("TextLabel") or instance:IsA("TextButton"))
end

local function setText(instance: Instance?, text: string)
	if instance and instance:IsA("TextLabel") then
		instance.Text = text
	elseif instance and instance:IsA("TextButton") then
		instance.Text = text
	end
end

local function findFirstTextDescendant(root: Instance?, excluded: {[Instance]: boolean}?): Instance?
	if not root then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if isTextInstance(descendant) and not (excluded and excluded[descendant]) then
			return descendant
		end
	end

	return nil
end

local function ensureOverlayButton(target: Instance?, name: string): GuiButton?
	if not target or not target:IsA("GuiObject") then
		return nil
	end

	local existing = target:FindFirstChild(name)
	if existing and existing:IsA("GuiButton") then
		return existing
	end

	local overlay = Instance.new("TextButton")
	overlay.Name = name
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.ZIndex = target.ZIndex + 5
	overlay.Parent = target
	return overlay
end

local function resolveButton(target: Instance?): GuiButton?
	if not target then
		return nil
	end

	if target:IsA("GuiButton") then
		return target
	end

	for _, descendant in ipairs(target:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			return descendant
		end
	end

	return ensureOverlayButton(target, "InteractionOverlay")
end

local function getRewardFrame(): GuiObject?
	if cachedFrame and cachedFrame.Parent then
		return cachedFrame
	end

	local frame = frames:FindFirstChild("RewardForExit")
	if frame and frame:IsA("GuiObject") then
		cachedFrame = frame
		return frame
	end

	return nil
end

local function shouldFastCheckPrompt(): boolean
	local playtimeSeconds = tonumber(player:GetAttribute("PlaytimeRewardSeconds")) or 0
	local claimableCount = tonumber(player:GetAttribute("PlaytimeRewardClaimableCount")) or 0
	local nextRewardId = tonumber(player:GetAttribute("PlaytimeRewardNextId")) or 0

	if claimableCount <= 0 and nextRewardId <= 0 and playtimeSeconds >= REQUIRED_PLAYTIME_SECONDS then
		return false
	end

	return playtimeSeconds < REQUIRED_PLAYTIME_SECONDS or claimableCount > 0
end

local function requestPlaytimeStatus(): any?
	local ok, result = pcall(function()
		return getStatusRemote:InvokeServer()
	end)

	if not ok or type(result) ~= "table" or result.Success ~= true then
		return nil
	end

	return result.Status
end

local function shouldShowPrompt(status: any): boolean
	if type(status) ~= "table" then
		return false
	end

	local claimableCount = #(status.ClaimableRewardIds or {})
	local playtimeSeconds = tonumber(status.PlaytimeSeconds) or 0
	local allRewardsClaimed = claimableCount <= 0 and status.NextRewardId == nil

	if allRewardsClaimed then
		return false
	end

	return playtimeSeconds < REQUIRED_PLAYTIME_SECONDS or claimableCount > 0
end

local function configureGiftSection(frame: GuiObject)
	local gift = frame:FindFirstChild("Gift")
	if not gift then
		return
	end

	local freeBadge = gift:FindFirstChild("Free")
	if freeBadge and freeBadge:IsA("GuiObject") then
		freeBadge.Visible = false
	end

	for _, child in ipairs(gift:GetChildren()) do
		if child.Name == "Image" and child:IsA("ImageLabel") then
			child.ImageColor3 = Color3.fromRGB(12, 12, 16)
		end
	end

	local nameContainer = gift:FindFirstChild("Name")
	if not nameContainer or not nameContainer:IsA("GuiObject") then
		return
	end

	local titleLabel = nameContainer:FindFirstChild("Title", true)
	setText(titleLabel, PROMPT_TITLE)

	local excluded = {}
	if titleLabel then
		excluded[titleLabel] = true
	end

	local subtitleLabel = nameContainer:FindFirstChild("Subtitle")
	if not isTextInstance(subtitleLabel) then
		subtitleLabel = findFirstTextDescendant(nameContainer, excluded)
	end

	if subtitleLabel and isTextInstance(subtitleLabel) then
		setText(subtitleLabel, PROMPT_SUBTITLE)
		return
	end

	local createdSubtitle = Instance.new("TextLabel")
	createdSubtitle.Name = "Subtitle"
	createdSubtitle.BackgroundTransparency = 1
	createdSubtitle.AnchorPoint = Vector2.new(0.5, 0)
	createdSubtitle.Position = UDim2.fromScale(0.5, 0.46)
	createdSubtitle.Size = UDim2.fromScale(1, 0.42)
	createdSubtitle.Font = Enum.Font.GothamBold
	createdSubtitle.Text = PROMPT_SUBTITLE
	createdSubtitle.TextColor3 = Color3.fromRGB(255, 255, 255)
	createdSubtitle.TextScaled = true
	createdSubtitle.TextWrapped = true
	createdSubtitle.ZIndex = nameContainer.ZIndex + 1
	createdSubtitle.Parent = nameContainer
end

local function configureClaimSection(frame: GuiObject): GuiButton?
	local claim = frame:FindFirstChild("Claim")
	if not claim then
		return nil
	end

	local claimButton = resolveButton(claim)
	for _, descendant in ipairs(claim:GetDescendants()) do
		if isTextInstance(descendant) and descendant.Name == "Text" then
			setText(descendant, PROMPT_OPEN_TEXT)
		end
	end

	return claimButton
end

local function configureFrame(frame: GuiObject): (GuiButton?, GuiButton?)
	frame.Visible = false

	configureGiftSection(frame)
	local openButton = configureClaimSection(frame)
	local closeButton = resolveButton(frame:FindFirstChild("Close", true))

	return openButton, closeButton
end

local function openPlaytimeRewards()
	local rewardFrame = getRewardFrame()
	if rewardFrame and rewardFrame.Visible then
		FrameManager.close(rewardFrame.Name)
	end

	FrameManager.open("PlaytimeRewards")
	hasInterceptedThisSession = true
end

local function confirmExit()
	local rewardFrame = getRewardFrame()
	if rewardFrame and rewardFrame.Visible then
		rewardFrame.Visible = false
	end

	hasInterceptedThisSession = true
	confirmExitRemote:FireServer()
end

local function ensureBindings()
	local rewardFrame = getRewardFrame()
	if not rewardFrame then
		return
	end

	local existing = rewardFrame:FindFirstChild("ExitRewardPromptBound")
	if existing then
		return
	end

	local marker = Instance.new("BoolValue")
	marker.Name = "ExitRewardPromptBound"
	marker.Value = true
	marker.Parent = rewardFrame

	local openButton, closeButton = configureFrame(rewardFrame)
	if openButton then
		openButton.Activated:Connect(openPlaytimeRewards)
	end

	if closeButton then
		closeButton.Activated:Connect(confirmExit)
	end
end

local function showPromptIfEligible()
	if isTutorialActive() then
		return
	end

	if hasInterceptedThisSession then
		return
	end

	local rewardFrame = getRewardFrame()
	if not rewardFrame or rewardFrame.Visible then
		return
	end

	local status = requestPlaytimeStatus()
	if not shouldShowPrompt(status) then
		return
	end

	ensureBindings()
	playRewardPromptSound()
	FrameManager.open(rewardFrame.Name)
end

GuiService.MenuOpened:Connect(function()
	if isTutorialActive() or hasInterceptedThisSession or not shouldFastCheckPrompt() then
		pendingMenuIntercept = false
		return
	end

	menuOpenedAt = tick()
	pendingMenuIntercept = true

	task.delay(0.15, function()
		if pendingMenuIntercept and not hasInterceptedThisSession then
			showPromptIfEligible()
		end
	end)
end)

GuiService.MenuClosed:Connect(function()
	if isTutorialActive() then
		pendingMenuIntercept = false
		return
	end

	if not pendingMenuIntercept then
		return
	end

	pendingMenuIntercept = false
	if tick() - menuOpenedAt < MENU_OPEN_MIN_DURATION then
		return
	end

	task.defer(showPromptIfEligible)
end)

frames.ChildAdded:Connect(function(child)
	if child.Name == "RewardForExit" and child:IsA("GuiObject") then
		cachedFrame = child
		ensureBindings()
	end
end)

task.defer(ensureBindings)
