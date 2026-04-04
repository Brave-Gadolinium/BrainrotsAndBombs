--!strict
-- LOCATION: StarterPlayerScripts/PromoCodeUIController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local FrameManager = require(ReplicatedStorage.Modules.FrameManager)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)

type ButtonLike = TextButton | ImageButton
type VisualState = {
	TextBoxColor: Color3?,
	TextBoxStrokeColor: Color3?,
	ButtonColor: Color3?,
	ButtonStrokeColor: Color3?,
	ButtonTextColor: Color3?,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local reportAnalyticsIntent = ReplicatedStorage:WaitForChild("Events"):WaitForChild("ReportAnalyticsIntent") :: RemoteEvent
local redeemRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Codes"):WaitForChild("Redeem") :: RemoteFunction

local FRAME_NAME = "RedeemCodesFrame"
local OPEN_BUTTON_NAME = "Codes"
local FEEDBACK_TWEEN_INFO = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BUTTON_TWEEN_INFO = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local LOG_PREFIX = "[PromoCodeUI]"

local ERROR_MESSAGES = {
	EmptyCode = "Enter a code first.",
	InvalidCode = "That code is invalid.",
	AlreadyRedeemed = "You already redeemed this code.",
	Busy = "Please wait a moment.",
	ProfileNotLoaded = "Your data is still loading. Try again in a second.",
	RewardGrantFailed = "Could not grant this reward. Try again.",
}

local mainGui: ScreenGui? = nil
local framesContainer: Instance? = nil
local hud: Instance? = nil

local codeFrame: Frame? = nil
local codeTextBox: TextBox? = nil
local checkCodeButton: ButtonLike? = nil
local closeButton: ButtonLike? = nil
local openButton: ButtonLike? = nil
local checkButtonScale: UIScale? = nil

local isSubmitting = false
local feedbackSerial = 0
local baseVisualState: VisualState? = nil

local function log(message: string)
	print(`${LOG_PREFIX} {message}`)
end

local function warnLog(message: string)
	warn(`${LOG_PREFIX} {message}`)
end

local function resolveRootUi(): boolean
	mainGui = playerGui:FindFirstChild("GUI") :: ScreenGui?
	if not mainGui then
		return false
	end

	framesContainer = mainGui:FindFirstChild("Frames")
	hud = mainGui:FindFirstChild("HUD")
	return framesContainer ~= nil and hud ~= nil
end

local function findDescendantButton(root: Instance?, name: string): ButtonLike?
	if not root then
		return nil
	end

	local instance = root:FindFirstChild(name, true)
	if instance and (instance:IsA("TextButton") or instance:IsA("ImageButton")) then
		return instance
	end

	return nil
end

local function getStroke(instance: Instance?): UIStroke?
	if not instance then
		return nil
	end

	return instance:FindFirstChildOfClass("UIStroke")
end

local function ensureScale(target: ButtonLike): UIScale
	local existing = target:FindFirstChildOfClass("UIScale")
	if existing then
		return existing
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = target
	return scale
end

local function tweenScale(scale: UIScale?, value: number, tweenInfo: TweenInfo?)
	if not scale then
		return
	end

	TweenService:Create(scale, tweenInfo or BUTTON_TWEEN_INFO, {Scale = value}):Play()
end

local function captureBaseVisualState()
	if not codeTextBox or not checkCodeButton then
		return
	end

	local textBoxStroke = getStroke(codeTextBox)
	local buttonStroke = getStroke(checkCodeButton)
	baseVisualState = {
		TextBoxColor = codeTextBox.BackgroundColor3,
		TextBoxStrokeColor = textBoxStroke and textBoxStroke.Color or nil,
		ButtonColor = checkCodeButton.BackgroundColor3,
		ButtonStrokeColor = buttonStroke and buttonStroke.Color or nil,
		ButtonTextColor = if checkCodeButton:IsA("TextButton") then checkCodeButton.TextColor3 else nil,
	}
end

local function restoreBaseVisualState(token: number)
	task.delay(0.26, function()
		if token ~= feedbackSerial or not baseVisualState then
			return
		end

		local textBoxStroke = getStroke(codeTextBox)
		local buttonStroke = getStroke(checkCodeButton)

		if codeTextBox and baseVisualState.TextBoxColor then
			TweenService:Create(codeTextBox, FEEDBACK_TWEEN_INFO, {BackgroundColor3 = baseVisualState.TextBoxColor}):Play()
			TweenService:Create(codeTextBox, FEEDBACK_TWEEN_INFO, {Rotation = 0}):Play()
		end
		if textBoxStroke and baseVisualState.TextBoxStrokeColor then
			TweenService:Create(textBoxStroke, FEEDBACK_TWEEN_INFO, {Color = baseVisualState.TextBoxStrokeColor}):Play()
		end
		if checkCodeButton and baseVisualState.ButtonColor then
			TweenService:Create(checkCodeButton, FEEDBACK_TWEEN_INFO, {BackgroundColor3 = baseVisualState.ButtonColor}):Play()
		end
		if buttonStroke and baseVisualState.ButtonStrokeColor then
			TweenService:Create(buttonStroke, FEEDBACK_TWEEN_INFO, {Color = baseVisualState.ButtonStrokeColor}):Play()
		end
		if checkCodeButton and checkCodeButton:IsA("TextButton") and baseVisualState.ButtonTextColor then
			TweenService:Create(checkCodeButton, FEEDBACK_TWEEN_INFO, {TextColor3 = baseVisualState.ButtonTextColor}):Play()
		end
	end)
end

local function playErrorWiggle()
	if not codeTextBox then
		return
	end

	task.spawn(function()
		for _, rotation in ipairs({-4, 4, -3, 3, 0}) do
			if not codeTextBox then
				return
			end

			local tween = TweenService:Create(codeTextBox, TweenInfo.new(0.04, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), {
				Rotation = rotation,
			})
			tween:Play()
			tween.Completed:Wait()
		end
	end)
end

local function playFeedback(isSuccess: boolean)
	if not codeTextBox or not checkCodeButton then
		return
	end

	feedbackSerial += 1
	local token = feedbackSerial
	local textBoxStroke = getStroke(codeTextBox)
	local buttonStroke = getStroke(checkCodeButton)

	local textBoxColor = if isSuccess then Color3.fromRGB(34, 79, 55) else Color3.fromRGB(77, 38, 47)
	local textBoxStrokeColor = if isSuccess then Color3.fromRGB(122, 255, 176) else Color3.fromRGB(255, 123, 142)
	local buttonColor = if isSuccess then Color3.fromRGB(42, 155, 100) else Color3.fromRGB(139, 62, 76)
	local buttonStrokeColor = if isSuccess then Color3.fromRGB(160, 255, 201) else Color3.fromRGB(255, 156, 172)

	TweenService:Create(codeTextBox, FEEDBACK_TWEEN_INFO, {BackgroundColor3 = textBoxColor}):Play()
	if textBoxStroke then
		TweenService:Create(textBoxStroke, FEEDBACK_TWEEN_INFO, {Color = textBoxStrokeColor}):Play()
	end

	TweenService:Create(checkCodeButton, FEEDBACK_TWEEN_INFO, {BackgroundColor3 = buttonColor}):Play()
	if buttonStroke then
		TweenService:Create(buttonStroke, FEEDBACK_TWEEN_INFO, {Color = buttonStrokeColor}):Play()
	end

	if checkCodeButton:IsA("TextButton") then
		TweenService:Create(checkCodeButton, FEEDBACK_TWEEN_INFO, {TextColor3 = Color3.fromRGB(255, 255, 255)}):Play()
	end

	if isSuccess then
		tweenScale(checkButtonScale, 1.08, POP_TWEEN_INFO)
		task.delay(0.1, function()
			if token == feedbackSerial then
				tweenScale(checkButtonScale, 1, POP_TWEEN_INFO)
			end
		end)
	else
		playErrorWiggle()
	end

	restoreBaseVisualState(token)
end

local function updateSubmittingState(submitting: boolean)
	isSubmitting = submitting

	if codeTextBox then
		codeTextBox.TextEditable = not submitting
	end

	if checkCodeButton then
		checkCodeButton.Active = not submitting
		checkCodeButton.AutoButtonColor = false
		if checkCodeButton:IsA("TextButton") then
			checkCodeButton.Text = if submitting then "CHECKING..." else "CHECK CODE"
		end
	end
end

local function submitCode()
	if isSubmitting or not codeTextBox then
		if isSubmitting then
			log("Ignored submit because a request is already in flight.")
		else
			warnLog("Ignored submit because TextBox is missing.")
		end
		return
	end

	local rawCode = codeTextBox.Text
	log(`Submit requested by {player.Name}. Raw input="{rawCode}"`)
	updateSubmittingState(true)
	log("Invoking server redeem remote...")

	local success, result = pcall(function()
		return redeemRemote:InvokeServer(rawCode)
	end)

	updateSubmittingState(false)

	if not success then
		warnLog(`Remote invoke failed for input "{rawCode}". Error={tostring(result)}`)
		NotificationManager.show("Code service is unavailable right now.", "Error")
		playFeedback(false)
		return
	end

	if type(result) ~= "table" or result.Success ~= true then
		local errorCode = if type(result) == "table" then result.Error else nil
		log(`Redeem failed for input "{rawCode}". Error={tostring(errorCode)} Result={tostring(result)}`)
		NotificationManager.show(ERROR_MESSAGES[errorCode] or "Could not redeem this code right now.", "Error")
		playFeedback(false)
		return
	end

	log(`Redeem succeeded for input "{rawCode}". CodeId={tostring(result.CodeId)} RewardType={tostring(result.RewardType)} RewardText={tostring(result.RewardText)}`)
	codeTextBox.Text = ""
	NotificationManager.show(result.RewardText or "Code redeemed!", "Success")
	playFeedback(true)
end

local function connectOnce(button: ButtonLike?, attributeName: string, callback: () -> ())
	if not button or button:GetAttribute(attributeName) == true then
		return
	end

	button:SetAttribute(attributeName, true)
	button.Activated:Connect(callback)
end

local function bindUi()
	if not resolveRootUi() then
		return
	end

	local existingFrame = framesContainer and framesContainer:FindFirstChild(FRAME_NAME)
	codeFrame = if existingFrame and existingFrame:IsA("Frame") then existingFrame else nil
	local foundTextBox = codeFrame and codeFrame:FindFirstChild("TextBox", true)
	codeTextBox = if foundTextBox and foundTextBox:IsA("TextBox") then foundTextBox else nil
	checkCodeButton = findDescendantButton(codeFrame, "CheckCode")
	closeButton = findDescendantButton(codeFrame, "Close")
	openButton = findDescendantButton(hud, OPEN_BUTTON_NAME) or findDescendantButton(hud, OPEN_BUTTON_NAME .. "Button")

	if not codeFrame then
		warnLog(`Existing frame "{FRAME_NAME}" was not found. The controller will not create a new UI.`)
		return
	end

	if not openButton then
		warnLog(`Existing open button "{OPEN_BUTTON_NAME}" was not found. The controller will not create one.`)
	end

	if checkCodeButton then
		checkButtonScale = ensureScale(checkCodeButton)
	end

	if codeTextBox and codeTextBox.PlaceholderText == "" then
		codeTextBox.PlaceholderText = "Enter code here..."
	end

	if not codeTextBox or not checkCodeButton then
		baseVisualState = nil
	end

	if not codeTextBox then
		warnLog(`TextBox was not found inside "{FRAME_NAME}".`)
	end
	if not checkCodeButton then
		warnLog(`CheckCode button was not found inside "{FRAME_NAME}".`)
	end
	if not closeButton then
		warnLog(`Close button was not found inside "{FRAME_NAME}".`)
	end

	captureBaseVisualState()

	connectOnce(openButton, "PromoCodesOpenBound", function()
		FrameManager.open(FRAME_NAME)
	end)
	connectOnce(closeButton, "PromoCodesCloseBound", function()
		FrameManager.close(FRAME_NAME)
	end)
	connectOnce(checkCodeButton, "PromoCodesSubmitBound", submitCode)

	if codeTextBox and codeTextBox:GetAttribute("PromoCodesFocusBound") ~= true then
		codeTextBox:SetAttribute("PromoCodesFocusBound", true)
		codeTextBox.FocusLost:Connect(function(enterPressed: boolean)
			log(`TextBox focus lost. EnterPressed={tostring(enterPressed)} CurrentText="{codeTextBox.Text}"`)
			if enterPressed then
				submitCode()
			end
		end)
	end

	if codeFrame and codeFrame:GetAttribute("PromoCodesVisibleBound") ~= true then
		codeFrame:SetAttribute("PromoCodesVisibleBound", true)
		codeFrame:GetPropertyChangedSignal("Visible"):Connect(function()
			if codeFrame and codeFrame.Visible then
				log(`${FRAME_NAME} opened.`)
				reportAnalyticsIntent:FireServer("CodesOpened")
			end
		end)
	end
end

bindUi()

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "GUI" then
		task.defer(bindUi)
	end
end)

player.CharacterAdded:Connect(function()
	task.defer(bindUi)
end)
