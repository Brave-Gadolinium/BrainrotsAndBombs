--!strict
-- LOCATION: StarterPlayerScripts/PopUpController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local CandyEventConfiguration = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CandyEventConfiguration"))
local NumberFormatter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("NumberFormatter"))

type PopUpKind = "cash" | "candy"

type PopUpRequest = {
	Amount: number,
	Kind: PopUpKind,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("GUI")

local Templates = ReplicatedStorage:WaitForChild("Templates")
local Events = ReplicatedStorage:WaitForChild("Events")
local GlobalSounds = Workspace:WaitForChild("Sounds")

local TWEEN_INFO_IN = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_INFO_FADE_IN = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_INFO_OUT = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local LIFETIME = 1.5
local SPREAD_X = 0.1
local SPREAD_Y = 0.1
local DEFAULT_MONEY_POPUP_IMAGE = "rbxassetid://18209585783"
local CANDY_BODY_COLOR = Color3.fromRGB(255, 124, 178)
local CANDY_WRAP_COLOR = Color3.fromRGB(255, 236, 92)
local CANDY_WRAP_STROKE_COLOR = Color3.fromRGB(222, 186, 62)
local CUSTOM_ICON_ATTRIBUTE = "IsCustomPopUpIcon"
local CUSTOM_ICON_TARGET_BG_ATTRIBUTE = "CustomPopUpTargetBackgroundTransparency"
local CUSTOM_ICON_TARGET_STROKE_ATTRIBUTE = "CustomPopUpTargetStrokeTransparency"

local cachedPopUpTemplate: Frame? = nil
local hasWarnedAboutMissingPopUpTemplate = false

print("[PopUpController] Loaded")

local function markCustomIcon(instance: Instance)
	instance:SetAttribute(CUSTOM_ICON_ATTRIBUTE, true)
end

local function setCustomIconBackgroundTarget(instance: Instance, transparency: number)
	instance:SetAttribute(CUSTOM_ICON_TARGET_BG_ATTRIBUTE, transparency)
end

local function setCustomIconStrokeTarget(instance: Instance, transparency: number)
	instance:SetAttribute(CUSTOM_ICON_TARGET_STROKE_ATTRIBUTE, transparency)
end

local function createFallbackPopUpTemplate(): Frame
	local frame = Instance.new("Frame")
	frame.Name = "PopUp"
	frame.Size = UDim2.fromOffset(170, 52)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0

	local icon = Instance.new("ImageLabel")
	icon.Name = "Image"
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromOffset(34, 34)
	icon.Position = UDim2.fromOffset(0, 9)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = DEFAULT_MONEY_POPUP_IMAGE
	icon.Parent = frame

	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(40, 4)
	text.Size = UDim2.new(1, -40, 1, -8)
	text.Font = Enum.Font.GothamBlack
	text.Text = "+$0"
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextSize = 28
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Stroke"
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = text

	return frame
end

local function getPopUpTemplate(): Frame
	if cachedPopUpTemplate then
		return cachedPopUpTemplate
	end

	local template = Templates:FindFirstChild("PopUp")
	if template and template:IsA("Frame") then
		cachedPopUpTemplate = template
		return template
	end

	if not hasWarnedAboutMissingPopUpTemplate then
		hasWarnedAboutMissingPopUpTemplate = true
		warn("[PopUpController] ReplicatedStorage.Templates.PopUp is missing. Falling back to a code-built template.")
	end

	cachedPopUpTemplate = createFallbackPopUpTemplate()
	return cachedPopUpTemplate
end

local function clearCustomIcon(imageLabel: ImageLabel)
	for _, child in ipairs(imageLabel:GetChildren()) do
		if child:GetAttribute(CUSTOM_ICON_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function createCandyPiece(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, rotation: number, rounded: boolean): Frame
	local piece = Instance.new("Frame")
	piece.Name = name
	piece.Size = size
	piece.Position = position
	piece.BackgroundColor3 = color
	piece.BackgroundTransparency = 0
	piece.BorderSizePixel = 0
	piece.Rotation = rotation
	piece.Parent = parent
	markCustomIcon(piece)
	setCustomIconBackgroundTarget(piece, piece.BackgroundTransparency)

	if rounded then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = piece
		markCustomIcon(corner)
	end

	return piece
end

local function renderCandyIcon(imageLabel: ImageLabel)
	clearCustomIcon(imageLabel)
	imageLabel.Image = ""
	imageLabel.ImageTransparency = 1
	imageLabel.BackgroundTransparency = 1

	local body = createCandyPiece(
		imageLabel,
		"CandyBody",
		UDim2.fromScale(0.5, 0.5),
		UDim2.fromScale(0.25, 0.25),
		CANDY_BODY_COLOR,
		0,
		true
	)

	local bodyStroke = Instance.new("UIStroke")
	bodyStroke.Color = Color3.fromRGB(255, 255, 255)
	bodyStroke.Thickness = 1.5
	bodyStroke.Transparency = 0.15
	bodyStroke.Parent = body
	markCustomIcon(bodyStroke)
	setCustomIconStrokeTarget(bodyStroke, bodyStroke.Transparency)

	local leftWrap = createCandyPiece(
		imageLabel,
		"LeftWrap",
		UDim2.fromScale(0.22, 0.22),
		UDim2.fromScale(0.08, 0.39),
		CANDY_WRAP_COLOR,
		45,
		true
	)

	local rightWrap = createCandyPiece(
		imageLabel,
		"RightWrap",
		UDim2.fromScale(0.22, 0.22),
		UDim2.fromScale(0.70, 0.39),
		CANDY_WRAP_COLOR,
		-45,
		true
	)

	for _, wrap in ipairs({leftWrap, rightWrap}) do
		local wrapStroke = Instance.new("UIStroke")
		wrapStroke.Color = CANDY_WRAP_STROKE_COLOR
		wrapStroke.Thickness = 1.5
		wrapStroke.Transparency = 0.2
		wrapStroke.Parent = wrap
		markCustomIcon(wrapStroke)
		setCustomIconStrokeTarget(wrapStroke, wrapStroke.Transparency)
	end

	local highlight = createCandyPiece(
		imageLabel,
		"BodyHighlight",
		UDim2.fromScale(0.16, 0.16),
		UDim2.fromScale(0.38, 0.30),
		Color3.fromRGB(255, 214, 231),
		0,
		true
	)
	highlight.BackgroundTransparency = 0.1
	setCustomIconBackgroundTarget(highlight, highlight.BackgroundTransparency)
end

local function applyIconStyle(imageLabel: ImageLabel?, request: PopUpRequest)
	if not imageLabel then
		return
	end

	clearCustomIcon(imageLabel)

	if request.Kind == "cash" then
		if imageLabel.Image == "" then
			imageLabel.Image = DEFAULT_MONEY_POPUP_IMAGE
		end
		imageLabel.ImageTransparency = 0
		return
	end

	renderCandyIcon(imageLabel)
end

local function getTextForRequest(request: PopUpRequest): string
	if request.Kind == "cash" then
		return "+$" .. NumberFormatter.Format(request.Amount)
	end

	return "+" .. tostring(request.Amount)
end

local function playPopUpSound(parent: Instance, request: PopUpRequest)
	if request.Kind == "cash" then
		local soundTemplate = GlobalSounds:FindFirstChild("Money")
		if soundTemplate and soundTemplate:IsA("Sound") then
			local sound = soundTemplate:Clone()
			sound.Parent = parent
			sound:Play()
			Debris:AddItem(sound, math.max(2, sound.TimeLength + 0.25))
		end
		return
	end

	local soundId = tostring(CandyEventConfiguration.PickupPopUpSoundId or "")
	if soundId == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "CandyPickupPopUpSound"
	sound.SoundId = soundId
	sound.Volume = 1
	sound.RollOffMaxDistance = 40
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, math.max(2, sound.TimeLength + 0.25))
end

local function createRequest(payload: any, defaultKind: PopUpKind): PopUpRequest?
	local resolvedKind = defaultKind
	local resolvedAmount: number?

	if type(payload) == "number" then
		resolvedAmount = payload
	elseif type(payload) == "table" then
		if payload.Kind == "cash" or payload.Kind == "candy" then
			resolvedKind = payload.Kind
		end

		resolvedAmount = tonumber(payload.Amount)
	end

	if type(resolvedAmount) ~= "number" or resolvedAmount <= 0 then
		return nil
	end

	if resolvedKind == "cash" then
		resolvedAmount = math.max(1, math.floor(resolvedAmount + 0.5))
	else
		resolvedAmount = math.max(1, math.floor(resolvedAmount))
	end

	return {
		Amount = resolvedAmount,
		Kind = resolvedKind,
	}
end

local function spawnPopUp(request: PopUpRequest)
	local template = getPopUpTemplate()
	local popUp = template:Clone() :: Frame
	local textLabel = popUp:FindFirstChild("Text") :: TextLabel?
	local imageLabel = popUp:FindFirstChild("Image") :: ImageLabel?
	local textStroke = textLabel and (textLabel:FindFirstChild("Stroke") or textLabel:FindFirstChildOfClass("UIStroke")) :: UIStroke?

	if not textLabel then
		warn("[PopUpController] PopUp template is missing 'Text'.")
		popUp:Destroy()
		return
	end

	textLabel.Text = getTextForRequest(request)
	applyIconStyle(imageLabel, request)

	local randX = 0.5 + (math.random() * SPREAD_X * 2 - SPREAD_X)
	local randY = 0.5 + (math.random() * SPREAD_Y * 2 - SPREAD_Y)
	local originalSize = template.Size

	popUp.Position = UDim2.fromScale(randX, randY)
	popUp.Size = UDim2.fromScale(0, 0)
	popUp.Rotation = math.random(-10, 10)

	popUp.BackgroundTransparency = 1
	textLabel.TextTransparency = 1
	textLabel.TextStrokeTransparency = 1
	if imageLabel then
		imageLabel.ImageTransparency = if request.Kind == "cash" then 1 else imageLabel.ImageTransparency
	end
	if textStroke then
		textStroke.Transparency = 1
	end

	for _, descendant in ipairs(popUp:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant:GetAttribute(CUSTOM_ICON_ATTRIBUTE) == true then
			descendant.BackgroundTransparency = 1
		elseif descendant:IsA("UIStroke") and descendant:GetAttribute(CUSTOM_ICON_ATTRIBUTE) == true then
			descendant.Transparency = 1
		end
	end

	popUp.Parent = mainGui
	playPopUpSound(popUp, request)

	local tweenPopSize = TweenService:Create(popUp, TWEEN_INFO_IN, {Size = originalSize})
	local tweenFadeText = TweenService:Create(textLabel, TWEEN_INFO_FADE_IN, {TextTransparency = 0, TextStrokeTransparency = 0})
	local tweenFadeImage = imageLabel and TweenService:Create(imageLabel, TWEEN_INFO_FADE_IN, {
		ImageTransparency = if request.Kind == "cash" then 0 else imageLabel.ImageTransparency,
	})
	local tweenFadeStroke = textStroke and TweenService:Create(textStroke, TWEEN_INFO_FADE_IN, {Transparency = 0})
	local customIconTweens = {}

	for _, descendant in ipairs(popUp:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant:GetAttribute(CUSTOM_ICON_ATTRIBUTE) == true then
			table.insert(customIconTweens, TweenService:Create(descendant, TWEEN_INFO_FADE_IN, {
				BackgroundTransparency = tonumber(descendant:GetAttribute(CUSTOM_ICON_TARGET_BG_ATTRIBUTE)) or 0,
			}))
		elseif descendant:IsA("UIStroke") and descendant:GetAttribute(CUSTOM_ICON_ATTRIBUTE) == true then
			table.insert(customIconTweens, TweenService:Create(descendant, TWEEN_INFO_FADE_IN, {
				Transparency = tonumber(descendant:GetAttribute(CUSTOM_ICON_TARGET_STROKE_ATTRIBUTE)) or 0,
			}))
		end
	end

	tweenPopSize:Play()
	tweenFadeText:Play()
	if tweenFadeImage then
		tweenFadeImage:Play()
	end
	if tweenFadeStroke then
		tweenFadeStroke:Play()
	end
	for _, tween in ipairs(customIconTweens) do
		tween:Play()
	end

	task.delay(LIFETIME * 0.7, function()
		if not popUp.Parent then
			return
		end

		local endPos = popUp.Position - UDim2.fromScale(0, 0.15)
		local tweenOutFrame = TweenService:Create(popUp, TWEEN_INFO_OUT, {Position = endPos})
		local tweenOutText = TweenService:Create(textLabel, TWEEN_INFO_OUT, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		local tweenOutImage = imageLabel and TweenService:Create(imageLabel, TWEEN_INFO_OUT, {ImageTransparency = 1})
		local tweenOutStroke = textStroke and TweenService:Create(textStroke, TWEEN_INFO_OUT, {Transparency = 1})

		tweenOutFrame:Play()
		tweenOutText:Play()
		if tweenOutImage then
			tweenOutImage:Play()
		end
		if tweenOutStroke then
			tweenOutStroke:Play()
		end

		for _, descendant in ipairs(popUp:GetDescendants()) do
			if descendant:IsA("GuiObject") and descendant:GetAttribute(CUSTOM_ICON_ATTRIBUTE) == true then
				TweenService:Create(descendant, TWEEN_INFO_OUT, {BackgroundTransparency = 1}):Play()
			elseif descendant:IsA("UIStroke") and descendant:GetAttribute(CUSTOM_ICON_ATTRIBUTE) == true then
				TweenService:Create(descendant, TWEEN_INFO_OUT, {Transparency = 1}):Play()
			end
		end

		Debris:AddItem(popUp, TWEEN_INFO_OUT.Time + 0.1)
	end)
end

local cashEvent = Events:WaitForChild("ShowCashPopUp")
cashEvent.OnClientEvent:Connect(function(payload: any)
	local request = createRequest(payload, "cash")
	if request then
		spawnPopUp(request)
	end
end)

local candyEvent = Events:WaitForChild("ShowCandyPopUp")
candyEvent.OnClientEvent:Connect(function(payload: any)
	local request = createRequest(payload, "candy")
	if request then
		spawnPopUp(request)
	end
end)
