--!strict
-- LOCATION: ReplicatedStorage/Modules/NotificationManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local NotificationManager = {}

-- [ REFERENCES ]
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 1. Where notifications appear (Added timeout to avoid infinite yield)
local mainGui = playerGui:WaitForChild("GUI", 10)
if not mainGui then warn("CRITICAL: 'GUI' ScreenGui not found!") end

local frames = mainGui and mainGui:WaitForChild("Frames", 10)
local notificationContainer = frames and frames:WaitForChild("Notifications", 10)

if not notificationContainer then
	warn("CRITICAL: 'Notifications' Frame not found inside GUI.Frames!")
end

-- 2. The Template
local templates = ReplicatedStorage:WaitForChild("Templates")
local notificationTemplate = templates:WaitForChild("NotificationTemplate")

-- [ CONFIG ]
local TWEEN_INFO_FADE = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local NOTIFICATION_LIFETIME = 2

-- [ COLORS ]
local COLORS = {
	Success = {
		Stroke = Color3.fromRGB(25, 75, 0),
		Gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 255, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 0))
		})
	},
	Error = {
		Stroke = Color3.fromRGB(100, 0, 0),
		Gradient = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 85, 127))
		})
	}
}

function NotificationManager.show(message: string, messageType: string)
	if not notificationContainer then return end

	-- 1. Clone Template
	local newNotification = notificationTemplate:Clone() :: TextLabel
	newNotification.Text = message
	newNotification.Name = "ActiveNotification"

	-- ## FORCE VISIBILITY SETTINGS ##
	newNotification.Visible = true
	newNotification.ZIndex = 10 -- Ensure it sits on top
	newNotification.TextTransparency = 1 -- Start hidden for fade in

	-- 2. Apply Styles
	local stroke = newNotification:FindFirstChild("Stroke") :: UIStroke
	local gradient = newNotification:FindFirstChild("Gradient") :: UIGradient
	local style = COLORS[messageType] or COLORS.Error

	if stroke then 
		stroke.Color = style.Stroke 
		stroke.Transparency = 1
	end
	if gradient then 
		gradient.Color = style.Gradient 
	end

	-- 3. Parent to UI
	newNotification.Parent = notificationContainer

	-- 4. Animate In
	local textFadeIn = TweenService:Create(newNotification, TWEEN_INFO_FADE, {TextTransparency = 0})
	local strokeFadeIn = stroke and TweenService:Create(stroke, TWEEN_INFO_FADE, {Transparency = 0})

	textFadeIn:Play()
	if strokeFadeIn then strokeFadeIn:Play() end

	-- 5. Play Sound
	local soundFolder = Workspace:FindFirstChild("Sounds")
	if soundFolder then
		local sound = soundFolder:FindFirstChild(messageType) :: Sound
		if sound then
			SoundService:PlayLocalSound(sound)
		end
	end

	-- 6. Cleanup
	task.delay(NOTIFICATION_LIFETIME, function()
		if not newNotification.Parent then return end

		local textFadeOut = TweenService:Create(newNotification, TWEEN_INFO_FADE, {TextTransparency = 1})
		local strokeFadeOut = stroke and TweenService:Create(stroke, TWEEN_INFO_FADE, {Transparency = 1})

		textFadeOut:Play()
		if strokeFadeOut then strokeFadeOut:Play() end

		textFadeOut.Completed:Wait()
		newNotification:Destroy()
	end)
end

return NotificationManager