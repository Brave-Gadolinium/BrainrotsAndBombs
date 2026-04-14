--!strict
-- LOCATION: StarterPlayerScripts/FeedbackTopbarController

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")

local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)

local function resolveTopbarPlusModule(): ModuleScript?
	local satchelFolder = ReplicatedStorage:FindFirstChild("Satchel")
	if not satchelFolder then
		return nil
	end

	local satchelLoader = satchelFolder:FindFirstChild("SatchelLoader")
	local satchelPackage = satchelLoader and satchelLoader:FindFirstChild("Satchel")
	local packages = satchelPackage and satchelPackage:FindFirstChild("Packages")
	local packageIndex = packages and packages:FindFirstChild("_Index")
	local topbarPlusPackage = packageIndex and packageIndex:FindFirstChild("1foreverhd_topbarplus@3.4.0")
	local topbarPlusModule = topbarPlusPackage and topbarPlusPackage:FindFirstChild("topbarplus")

	if topbarPlusModule and topbarPlusModule:IsA("ModuleScript") then
		return topbarPlusModule
	end

	return nil
end

local topbarPlusModule = resolveTopbarPlusModule()
if not topbarPlusModule then
	warn("[FeedbackTopbarController] TopbarPlus module was not found.")
	return
end

local Icon = require(topbarPlusModule)

local FEEDBACK_LABEL = "Feedback"
local FEEDBACK_CAPTION = "Send feedback"
local FEEDBACK_ORDER = 0

local requestInFlight = false

local feedbackIcon = Icon.new()
	:setName("ExperienceFeedback")
	:setLabel(FEEDBACK_LABEL)
	:setCaption(FEEDBACK_CAPTION)
	:oneClick(true)
	:autoDeselect(true)
	:setOrder(FEEDBACK_ORDER)

feedbackIcon.selected:Connect(function()
	if requestInFlight then
		return
	end

	requestInFlight = true
	feedbackIcon:lock()

	task.spawn(function()
		if RunService:IsStudio() then
			NotificationManager.show("Feedback prompt does not work in Studio. Test it in the Roblox app.", "Error")
			requestInFlight = false
			feedbackIcon:unlock()
			return
		end

		local success, errorMessage = pcall(function()
			SocialService:PromptFeedbackSubmissionAsync()
		end)

		if not success then
			warn("[FeedbackTopbarController] Failed to prompt feedback:", errorMessage)
			NotificationManager.show("Feedback is unavailable right now.", "Error")
		end

		requestInFlight = false
		feedbackIcon:unlock()
	end)
end)
