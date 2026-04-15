--!strict
-- LOCATION: StarterPlayerScripts/UIEffects

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local TutorialConfiguration = require(ReplicatedStorage.Modules:WaitForChild("TutorialConfiguration"))

print("[UIEffects] Initialized (StarterPlayerScripts)")

-- Assets
local Templates = ReplicatedStorage:WaitForChild("Templates")
local shineTemplate: ImageLabel? = Templates:FindFirstChild("ShineEffectTemplate")
local globalSounds = Workspace:WaitForChild("Sounds")
local Events = ReplicatedStorage:WaitForChild("Events")

-- Player
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function isTutorialActive(): boolean
	local onboardingStep = tonumber(player:GetAttribute("OnboardingStep")) or 0
	return onboardingStep > 0 and onboardingStep < TutorialConfiguration.FinalStep
end

-- Script State
local sunburstObjects: {[GuiObject]: boolean} = {}
local bladeObjects: {[GuiObject]: boolean} = {} 
local rotatingGradients: {[UIGradient]: number} = {} 
local panningGradients: {[UIGradient]: {Speed: number, Range: number}} = {}
local buttonConnections: {[GuiButton]: {RBXScriptConnection}} = {}
local physicalButtonDebounce: {[Instance]: boolean} = {}
local activeShineThreads: {[GuiObject]: thread} = {}
local floatingItems: {[Model]: {BaseCFrame: CFrame, TimeOffset: number}} = {}

-- [ CONFIGURATION ]
local SOUND_DEBOUNCE_TIME = 0.05
local lastSoundTime = tick()

local HOVER_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local CLICK_TWEEN_INFO = TweenInfo.new(0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)

local SUNBURST_ROTATION_SPEED = 20
local BLADE_ROTATION_SPEED = 500 
local DEFAULT_GRADIENT_SPEED = 90
local DEFAULT_PAN_SPEED = 1
local DEFAULT_PAN_RANGE = 0.25

local FLOAT_SPEED = 1.5    -- Made 2x slower
local FLOAT_HEIGHT = 0.5 

-- Animation Config for Physical Buttons
local PHYSICAL_PRESS_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, true)
local PHYSICAL_PRESS_OFFSET = 0.4 

-- UI Constants
local HOVER_SCALE = 1.05
local CLICK_SCALE = 0.95

--================------------------------------------------------
-- ## SOUND LOGIC ##
--================------------------------------------------------
local function playLocalSound(soundName: string)
	local now = tick()
	if now - lastSoundTime < SOUND_DEBOUNCE_TIME then return end
	lastSoundTime = now

	local soundTemplate = globalSounds:FindFirstChild(soundName)
	if soundTemplate and soundTemplate:IsA("Sound") then
		local newSound = soundTemplate:Clone()
		newSound.Parent = playerGui
		newSound:Play()
		Debris:AddItem(newSound, newSound.TimeLength + 0.1)
	end
end

--================------------------------------------------------
-- ## PHYSICAL BUTTON LOGIC (3D World) ##
--================------------------------------------------------
local function applyPhysicalButtonEffect(model: Instance)
	if not model:IsA("Model") then return end

	task.spawn(function()
		local touchPart = model:WaitForChild("Touch", 10) :: BasePart
		if not touchPart then return end

		while model.Parent == nil or model:GetPivot().Position.Magnitude < 1 do
			task.wait(0.2)
		end

		local homePivot = model:GetPivot()

		local animValue = Instance.new("NumberValue")
		animValue.Value = 0

		animValue.Changed:Connect(function(val)
			model:PivotTo(homePivot * CFrame.new(0, -val, 0))
		end)

		local pressTween = TweenService:Create(animValue, PHYSICAL_PRESS_INFO, {Value = PHYSICAL_PRESS_OFFSET})

		touchPart.Touched:Connect(function(hit)
			local character = hit.Parent
			if not character then return end

			local hitPlayer = Players:GetPlayerFromCharacter(character)

			if hitPlayer == player and not physicalButtonDebounce[model] then
				physicalButtonDebounce[model] = true

				if animValue.Value == 0 then
					homePivot = model:GetPivot()
				end

				playLocalSound("Click")
				pressTween:Play()

				task.delay(0.5, function()
					physicalButtonDebounce[model] = nil
				end)
			end
		end)
	end)
end
local function cleanupPhysicalButtonEffect(model: Instance)
	physicalButtonDebounce[model] = nil
end

--================------------------------------------------------
-- ## BUTTON ANIMATION LOGIC (Universal UI) ##
--================------------------------------------------------
local function applyUniversalButtonLogic(button: GuiButton)
	if buttonConnections[button] then return end

	local useUIScale = not button:FindFirstAncestorOfClass("ScrollingFrame")
	local originalSize = button.Size
	local uiScale: UIScale?

	if useUIScale then
		uiScale = button:FindFirstChild("EffectScale") :: UIScale?
		if not uiScale then
			uiScale = Instance.new("UIScale")
			uiScale.Name = "EffectScale"
			uiScale.Parent = button
		end
		uiScale.Scale = 1
	end

	local connections = {}

	table.insert(connections, button.MouseEnter:Connect(function()
		playLocalSound("Hover")
		if uiScale then
			TweenService:Create(uiScale, HOVER_TWEEN_INFO, {Scale = HOVER_SCALE}):Play()
		else
			TweenService:Create(button, HOVER_TWEEN_INFO, {Size = UDim2.new(originalSize.X.Scale * HOVER_SCALE, originalSize.X.Offset, originalSize.Y.Scale * HOVER_SCALE, originalSize.Y.Offset)}):Play()
		end
	end))

	table.insert(connections, button.MouseLeave:Connect(function()
		if uiScale then
			TweenService:Create(uiScale, HOVER_TWEEN_INFO, {Scale = 1}):Play()
		else
			TweenService:Create(button, HOVER_TWEEN_INFO, {Size = originalSize}):Play()
		end
	end))

	table.insert(connections, button.MouseButton1Down:Connect(function()
		playLocalSound("Click")
		if uiScale then
			TweenService:Create(uiScale, CLICK_TWEEN_INFO, {Scale = CLICK_SCALE}):Play()
		else
			TweenService:Create(button, CLICK_TWEEN_INFO, {Size = UDim2.new(originalSize.X.Scale * CLICK_SCALE, originalSize.X.Offset, originalSize.Y.Scale * CLICK_SCALE, originalSize.Y.Offset)}):Play()
		end
	end))

	table.insert(connections, button.MouseButton1Up:Connect(function()
		if uiScale then
			TweenService:Create(uiScale, CLICK_TWEEN_INFO, {Scale = HOVER_SCALE}):Play()
		else
			TweenService:Create(button, CLICK_TWEEN_INFO, {Size = UDim2.new(originalSize.X.Scale * HOVER_SCALE, originalSize.X.Offset, originalSize.Y.Scale * HOVER_SCALE, originalSize.Y.Offset)}):Play()
		end
	end))

	buttonConnections[button] = connections
end

local function cleanupButtonLogic(button: GuiButton)
	if buttonConnections[button] then
		for _, conn in ipairs(buttonConnections[button]) do
			conn:Disconnect()
		end
		buttonConnections[button] = nil
	end
end

--================------------------------------------------------
-- ## VISUAL EFFECTS ##
--================------------------------------------------------

local function applySunburstEffect(guiObject: Instance) if guiObject:IsA("GuiObject") then sunburstObjects[guiObject] = true end end
local function cleanupSunburstEffect(guiObject: Instance) if guiObject:IsA("GuiObject") then sunburstObjects[guiObject] = nil end end

local function applyBladeEffect(guiObject: Instance) if guiObject:IsA("GuiObject") then bladeObjects[guiObject] = true end end
local function cleanupBladeEffect(guiObject: Instance) if guiObject:IsA("GuiObject") then bladeObjects[guiObject] = nil end end

local function applyRotatingGradient(grad: Instance) if grad:IsA("UIGradient") then rotatingGradients[grad] = grad:GetAttribute("RotationSpeed") or DEFAULT_GRADIENT_SPEED end end
local function cleanupRotatingGradient(grad: Instance) if grad:IsA("UIGradient") then rotatingGradients[grad] = nil end end

local function applyPanningGradient(grad: Instance) if grad:IsA("UIGradient") then panningGradients[grad] = {Speed = grad:GetAttribute("PanSpeed") or DEFAULT_PAN_SPEED, Range = grad:GetAttribute("PanRange") or DEFAULT_PAN_RANGE} end end
local function cleanupPanningGradient(grad: Instance) if grad:IsA("UIGradient") then panningGradients[grad] = nil end end

-- Float Logic
local function applyFloatEffect(model: Instance)
	if model:IsA("Model") then
		task.wait() -- Small delay to ensure position is finalized by the server
		floatingItems[model] = {
			BaseCFrame = model:GetPivot(),
			TimeOffset = math.random() * 10 -- Random offset so items bob out of sync!
		}
	end
end

local function cleanupFloatEffect(model: Instance)
	if model:IsA("Model") then
		floatingItems[model] = nil
	end
end

-- Shine
local SHINE_MIN_DELAY = 1; local SHINE_MAX_DELAY = 4
local SHINE_FADE_IN_TIME = 0.3; local SHINE_FADE_OUT_TIME = 0.7
local SHINE_MAX_ROTATION = 45; local SHINE_MAX_SIZE_SCALE = 1.5

local function applyShineEffect(guiObject: Instance)
	if not guiObject:IsA("GuiObject") then return end
	if not shineTemplate then return end
	local shineThread = coroutine.wrap(function()
		while guiObject.Parent do
			task.wait(math.random() * (SHINE_MAX_DELAY - SHINE_MIN_DELAY) + SHINE_MIN_DELAY)
			if not guiObject.Parent then break end
			local newShine = shineTemplate:Clone()
			newShine.Position = UDim2.fromScale(math.random(), math.random())
			newShine.ImageTransparency = 1
			newShine.Rotation = math.random(-SHINE_MAX_ROTATION, SHINE_MAX_ROTATION)
			newShine.Parent = guiObject
			local originalSize = newShine.Size
			local targetSize = UDim2.fromOffset(originalSize.X.Offset * SHINE_MAX_SIZE_SCALE, originalSize.Y.Offset * SHINE_MAX_SIZE_SCALE)
			local fadeInTween = TweenService:Create(newShine, TweenInfo.new(SHINE_FADE_IN_TIME, Enum.EasingStyle.Quad), { ImageTransparency = 0, Rotation = math.random(-SHINE_MAX_ROTATION, SHINE_MAX_ROTATION), Size = targetSize })
			local fadeOutTween = TweenService:Create(newShine, TweenInfo.new(SHINE_FADE_OUT_TIME, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { ImageTransparency = 1, Rotation = math.random(-SHINE_MAX_ROTATION, SHINE_MAX_ROTATION), Size = originalSize })
			fadeInTween:Play(); fadeInTween.Completed:Wait()
			if not newShine.Parent then break end
			fadeOutTween:Play(); fadeOutTween.Completed:Wait(); newShine:Destroy()
		end
	end)()
	activeShineThreads[guiObject] = shineThread
end

local function cleanupShineEffect(guiObject: Instance)
	if guiObject:IsA("GuiObject") and activeShineThreads[guiObject] then 
		task.cancel(activeShineThreads[guiObject]); activeShineThreads[guiObject] = nil 
	end
end

--================------------------------------------------------
-- ## SCREEN EFFECTS (FOV POP) ##
--================------------------------------------------------
local isFovPopping = false
local bombHitFovToken = 0
local fovPopToken = 0
local bombHitBaselineFov: number? = nil
local activeBombHitTweens: {Tween} = {}
local activeFovPopTweens: {Tween} = {}
local DEFAULT_CAMERA_FOV = 70

local BOMB_HIT_FOV_BOOST = 16
local BOMB_HIT_FOV_HOLD_TIME = 0.14
local BOMB_HIT_FOV_IN_INFO = TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
local BOMB_HIT_FOV_OUT_INFO = TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function clearFovPopTweens()
	for _, tween in ipairs(activeFovPopTweens) do
		tween:Cancel()
	end

	table.clear(activeFovPopTweens)
end

local function clearBombHitTweens()
	for _, tween in ipairs(activeBombHitTweens) do
		tween:Cancel()
	end

	table.clear(activeBombHitTweens)
end

local function resetMenuFovEffects()
	if isTutorialActive() then
		return
	end

	fovPopToken += 1
	bombHitFovToken += 1
	isFovPopping = false
	bombHitBaselineFov = nil
	clearFovPopTweens()
	clearBombHitTweens()

	local currentCam = Workspace.CurrentCamera
	if currentCam then
		currentCam.FieldOfView = DEFAULT_CAMERA_FOV
	end
end

local function FOVPop()
	local currentCam = Workspace.CurrentCamera
	if not currentCam then return end
	if GuiService.MenuIsOpen then return end

	-- Prevent spam-glitching the FOV if they exit the zone repeatedly
	if isFovPopping then return end
	isFovPopping = true
	fovPopToken += 1
	local token = fovPopToken

	print("[UIEffects] FOV Pop Triggered!")

	local originalFOV = DEFAULT_CAMERA_FOV
	local targetFOV = originalFOV * 1.25 -- Exactly a 25% increase (87.5)
	clearFovPopTweens()

	-- Pop open instantly
	local popTween = TweenService:Create(
		currentCam,
		TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{FieldOfView = targetFOV}
	)
	table.insert(activeFovPopTweens, popTween)
	popTween:Play()

	-- Hold it for a short duration to make the transition clear within 1 second
	task.wait(0.6) 
	if fovPopToken ~= token or GuiService.MenuIsOpen then
		if fovPopToken == token then
			resetMenuFovEffects()
		end
		return
	end

	-- Ease it back smoothly
	if currentCam then
		local returnTween = TweenService:Create(currentCam, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {FieldOfView = originalFOV})
		table.insert(activeFovPopTweens, returnTween)
		returnTween:Play()
		returnTween.Completed:Wait() -- Wait for it to finish before allowing another pop
	end

	if fovPopToken == token then
		isFovPopping = false
		clearFovPopTweens()
	end
end

local function BombHitFOV()
	local currentCam = Workspace.CurrentCamera
	if not currentCam then
		return
	end
	if GuiService.MenuIsOpen then
		resetMenuFovEffects()
		return
	end

	bombHitFovToken += 1
	local token = bombHitFovToken

	if bombHitBaselineFov == nil then
		bombHitBaselineFov = currentCam.FieldOfView
	end

	local baselineFov = bombHitBaselineFov
	clearBombHitTweens()

	local punchTween = TweenService:Create(
		currentCam,
		BOMB_HIT_FOV_IN_INFO,
		{FieldOfView = math.min(baselineFov + BOMB_HIT_FOV_BOOST, 100)}
	)
	table.insert(activeBombHitTweens, punchTween)
	punchTween:Play()

	task.delay(BOMB_HIT_FOV_HOLD_TIME, function()
		if bombHitFovToken ~= token then
			return
		end
		if GuiService.MenuIsOpen then
			resetMenuFovEffects()
			return
		end

		local cameraForReturn = Workspace.CurrentCamera
		if not cameraForReturn then
			clearBombHitTweens()
			bombHitBaselineFov = nil
			return
		end

		local returnTween = TweenService:Create(
			cameraForReturn,
			BOMB_HIT_FOV_OUT_INFO,
			{FieldOfView = baselineFov}
		)
		table.insert(activeBombHitTweens, returnTween)
		returnTween:Play()
	end)

	task.delay(BOMB_HIT_FOV_HOLD_TIME + BOMB_HIT_FOV_OUT_INFO.Time + 0.05, function()
		if bombHitFovToken ~= token then
			return
		end
		if GuiService.MenuIsOpen then
			resetMenuFovEffects()
			return
		end

		local cameraToRestore = Workspace.CurrentCamera
		if cameraToRestore then
			cameraToRestore.FieldOfView = baselineFov
		end

		clearBombHitTweens()
		bombHitBaselineFov = nil
	end)
end

GuiService.MenuOpened:Connect(resetMenuFovEffects)

--================------------------------------------------------
-- ## EFFECTS LOOP ##
--================------------------------------------------------
RunService.Heartbeat:Connect(function(dt: number)
	-- Process 2D Sunbursts
	for guiObject, _ in pairs(sunburstObjects) do
		if guiObject and guiObject.Parent then
			guiObject.Rotation += (SUNBURST_ROTATION_SPEED or 20) * dt
		else
			sunburstObjects[guiObject] = nil
		end
	end

	-- Process 2D Blades 
	for guiObject, _ in pairs(bladeObjects) do
		if guiObject and guiObject.Parent then
			guiObject.Rotation += (BLADE_ROTATION_SPEED or 500) * dt
		else
			bladeObjects[guiObject] = nil
		end
	end

	-- Process Rotating Gradients
	for gradient, speed in pairs(rotatingGradients) do
		if gradient and gradient.Parent then
			gradient.Rotation = (gradient.Rotation + (speed or 90) * dt) % 360
		else
			rotatingGradients[gradient] = nil
		end
	end

	-- Process Panning Gradients
	for gradient, config in pairs(panningGradients) do
		if gradient and gradient.Parent then
			local offset = math.sin(tick() * config.Speed) * config.Range
			gradient.Offset = Vector2.new(offset, 0)
		else
			panningGradients[gradient] = nil
		end
	end

	-- Process 3D Floating Items
	for model, data in pairs(floatingItems) do
		if model.Parent then
			local newY = math.sin((tick() + data.TimeOffset) * FLOAT_SPEED) * FLOAT_HEIGHT
			model:PivotTo(data.BaseCFrame * CFrame.new(0, newY, 0))
		else
			floatingItems[model] = nil
		end
	end
end)


--================--------------------------------================
-- ## INITIALIZATION & MONITORS ##
--================--------------------------------================
local function setupTag(tagName: string, applyFunction: (Instance) -> (), cleanupFunction: (Instance) -> ())
	for _, instance in ipairs(CollectionService:GetTagged(tagName)) do task.spawn(applyFunction, instance) end
	CollectionService:GetInstanceAddedSignal(tagName):Connect(function(instance: Instance) task.spawn(applyFunction, instance) end)
	CollectionService:GetInstanceRemovedSignal(tagName):Connect(function(instance: Instance) task.spawn(cleanupFunction, instance) end)
end

-- Wire up all CollectionService tags
setupTag("SunburstEffect", applySunburstEffect, cleanupSunburstEffect)
setupTag("BladeEffect", applyBladeEffect, cleanupBladeEffect)
setupTag("RotatingGradient", applyRotatingGradient, cleanupRotatingGradient)
setupTag("PanningGradient", applyPanningGradient, cleanupPanningGradient)
setupTag("PhysicalButton", applyPhysicalButtonEffect, cleanupPhysicalButtonEffect)

setupTag("ShineEffect", applyShineEffect, cleanupShineEffect)
setupTag("FloatingItem", applyFloatEffect, cleanupFloatEffect) 

-- Dynamic UI Button Monitor
local function processGuiElement(element: Instance)
	if element:IsA("TextButton") or element:IsA("ImageButton") then
		task.defer(function()
			if element and element.Parent then
				applyUniversalButtonLogic(element)
			end
		end)
	end
end

for _, child in ipairs(playerGui:GetDescendants()) do processGuiElement(child) end
playerGui.DescendantAdded:Connect(processGuiElement)
playerGui.DescendantRemoving:Connect(function(element)
	if element:IsA("GuiButton") then cleanupButtonLogic(element) end
end)

-- Plot UI Monitor
local function monitorPlotUI()
	local plotName = "Plot_" .. player.Name
	local plot = Workspace:WaitForChild(plotName, 5)
	if not plot then return end

	local function onPlotDescendantAdded(descendant: Instance)
		if descendant:IsA("TextButton") or descendant:IsA("ImageButton") then
			task.wait() 
			applyUniversalButtonLogic(descendant)
		end
	end

	plot.DescendantAdded:Connect(onPlotDescendantAdded)
	for _, child in ipairs(plot:GetDescendants()) do
		onPlotDescendantAdded(child)
	end
end
task.spawn(monitorPlotUI)

-- Screen Event Listener
local triggerEvent = Events:WaitForChild("TriggerUIEffect", 5)
if triggerEvent then
	triggerEvent.OnClientEvent:Connect(function(effectName, ...)
		if effectName == "FOVPop" then
			task.spawn(FOVPop) -- Spawned to prevent blocking
		elseif effectName == "BombHitFOV" then
			task.spawn(BombHitFOV)
		end
	end)
end

print("[UIEffects] Systems Ready.")
