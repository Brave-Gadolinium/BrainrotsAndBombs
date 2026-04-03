--!strict
-- LOCATION: StarterPlayerScripts/MiningController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService") -- ## ADDED ##

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BombToolClient = require(Modules:WaitForChild("BombToolClient"))
local PickaxesConfigurations = require(Modules:WaitForChild("PickaxesConfigurations"))

-- References for Animation, Sounds & UI
local Templates = ReplicatedStorage:WaitForChild("Templates")
local PickaxeAnimation = Templates:WaitForChild("PickaxeAnimation") :: Animation
local TimerGUI_Template = Templates:WaitForChild("TimerGUI") :: BillboardGui
local CrackTemplate = Templates:WaitForChild("Crack") :: Decal 
local globalSounds = Workspace:WaitForChild("Sounds") 

local player = Players.LocalPlayer

local MINING_RANGE = 25 
local lastSwingTime = 0
local activeToolConnection: RBXScriptConnection? = nil
local currentAnimationTrack: AnimationTrack? = nil 
local currentTool: Tool? = nil

local activeHighlights: {[BasePart]: SelectionBox} = {}
local highlightLoop: RBXScriptConnection? = nil

local MOBILE_BOMB_READY_ICON = "rbxassetid://123855876242070"
local MOBILE_BOMB_COOLDOWN_ICON = "rbxassetid://135164909685622"
local MOBILE_BOMB_MIN_SIZE = 68
local MOBILE_BOMB_MAX_SIZE = 93
local MOBILE_BOMB_SIZE_RATIO = 0.16
local MOBILE_BOMB_MIN_MARGIN_RIGHT = 18
local MOBILE_BOMB_MAX_MARGIN_RIGHT = 30
local MOBILE_BOMB_RIGHT_MARGIN_RATIO = 0.035
local MOBILE_BOMB_EXTRA_LEFT_OFFSET = 92
local MOBILE_BOMB_MIN_MARGIN_BOTTOM = 26
local MOBILE_BOMB_MAX_MARGIN_BOTTOM = 44
local MOBILE_BOMB_BOTTOM_MARGIN_RATIO = 0.06
local MOBILE_BOMB_EXTRA_UP_OFFSET = 54

local mobileBombButton: ImageButton? = nil
local mobileBombButtonScale: UIScale? = nil
local mobileBombButtonIcon: ImageLabel? = nil
local attemptMine: (tool: Tool) -> ()

local function shouldShowMobileBombButton(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

local function getCharacterBombTool(): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and PickaxesConfigurations.Pickaxes[child.Name] then
			return child
		end
	end

	return nil
end

local function getBackpackBombTool(): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end

	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") and PickaxesConfigurations.Pickaxes[child.Name] then
			return child
		end
	end

	return nil
end

local function getAvailableBombTool(): Tool?
	return getCharacterBombTool() or getBackpackBombTool()
end

local function getBombCooldownRemaining(tool: Tool?): number
	if not tool then
		return 0
	end

	local cooldownEndsAt = tool:GetAttribute("CooldownEndsAt")
	if type(cooldownEndsAt) ~= "number" then
		return 0
	end

	return math.max(0, cooldownEndsAt - Workspace:GetServerTimeNow())
end

local function getGuiRoot(): ScreenGui?
	local playerGui = player:FindFirstChild("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild("GUI")
	if gui and gui:IsA("ScreenGui") then
		return gui
	end

	return nil
end

local function layoutMobileBombButton()
	local button = mobileBombButton
	if not button then
		return
	end

	local guiRoot = getGuiRoot()
	local camera = Workspace.CurrentCamera
	local viewportSize = if camera then camera.ViewportSize else Vector2.new(0, 0)
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		viewportSize = if guiRoot and guiRoot.AbsoluteSize.Magnitude > 0 then guiRoot.AbsoluteSize else Vector2.new(0, 0)
	end

	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return
	end

	local safeAreaRightInset = 0
	local safeAreaBottomInset = 0
	if guiRoot and guiRoot.AbsoluteSize.Magnitude > 0 then
		local guiBottomRight = guiRoot.AbsolutePosition + guiRoot.AbsoluteSize
		safeAreaRightInset = math.max(0, viewportSize.X - guiBottomRight.X)
		safeAreaBottomInset = math.max(0, viewportSize.Y - guiBottomRight.Y)
	end

	local minViewportSide = math.min(viewportSize.X, viewportSize.Y)
	local buttonSize = math.clamp(math.floor(minViewportSide * MOBILE_BOMB_SIZE_RATIO), MOBILE_BOMB_MIN_SIZE, MOBILE_BOMB_MAX_SIZE)
	local marginRight = math.clamp(
		math.floor(viewportSize.X * MOBILE_BOMB_RIGHT_MARGIN_RATIO),
		MOBILE_BOMB_MIN_MARGIN_RIGHT,
		MOBILE_BOMB_MAX_MARGIN_RIGHT
	)
	local marginBottom = math.clamp(
		math.floor(viewportSize.Y * MOBILE_BOMB_BOTTOM_MARGIN_RATIO),
		MOBILE_BOMB_MIN_MARGIN_BOTTOM,
		MOBILE_BOMB_MAX_MARGIN_BOTTOM
	)

	button.Size = UDim2.fromOffset(buttonSize, buttonSize)
	button.Position = UDim2.new(1, safeAreaRightInset - marginRight - MOBILE_BOMB_EXTRA_LEFT_OFFSET, 1, safeAreaBottomInset - marginBottom - MOBILE_BOMB_EXTRA_UP_OFFSET)
end

local function animateMobileBombButtonPress()
	local scale = mobileBombButtonScale
	if not scale then
		return
	end

	scale.Scale = 1
	local pressTween = TweenService:Create(scale, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.92})
	local releaseTween = TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
	pressTween:Play()
	pressTween.Completed:Once(function()
		releaseTween:Play()
	end)
end

local function updateMobileBombButtonState()
	local button = mobileBombButton
	local icon = mobileBombButtonIcon
	if not button or not icon then
		return
	end

	layoutMobileBombButton()

	local tool = currentTool
	if not tool or not tool.Parent then
		tool = getAvailableBombTool()
		currentTool = tool
	end

	local config = tool and PickaxesConfigurations.Pickaxes[tool.Name] or nil
	local shouldShow = shouldShowMobileBombButton()

	button.Visible = shouldShow
	if not shouldShow then
		return
	end

	local hasBomb = config ~= nil
	local remainingCooldown = if hasBomb then getBombCooldownRemaining(tool) else 0
	local isReady = hasBomb and remainingCooldown <= 0.02

	button.Active = isReady
	button.BackgroundColor3 = if isReady then Color3.fromRGB(26, 28, 37) else Color3.fromRGB(33, 33, 39)
	button.BackgroundTransparency = if isReady then 0.08 else 0.16
	icon.Image = if isReady then MOBILE_BOMB_READY_ICON else MOBILE_BOMB_COOLDOWN_ICON
	icon.ImageTransparency = if hasBomb then (if isReady then 0 else 0.12) else 0.2

	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = if isReady then Color3.fromRGB(255, 163, 94) else if hasBomb then Color3.fromRGB(126, 126, 126) else Color3.fromRGB(170, 170, 170)
	end

	local glow = button:FindFirstChild("Glow")
	if glow and glow:IsA("Frame") then
		glow.BackgroundTransparency = if isReady then 0.82 else if hasBomb then 0.9 else 0.93
	end
end

local function tryActivateBombFromButton(tool: Tool)
	currentTool = tool
	if BombToolClient.TryActivate(tool) then
		animateMobileBombButtonPress()
	end
	updateMobileBombButtonState()
end

local function ensureMobileBombButton()
	if mobileBombButton and mobileBombButton.Parent then
		return mobileBombButton
	end

	local guiRoot = getGuiRoot()
	if not guiRoot then
		return nil
	end

	local button = Instance.new("ImageButton")
	button.Name = "MobileBombButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -MOBILE_BOMB_MIN_MARGIN_RIGHT, 1, -MOBILE_BOMB_MIN_MARGIN_BOTTOM)
	button.Size = UDim2.fromOffset(MOBILE_BOMB_MIN_SIZE, MOBILE_BOMB_MIN_SIZE)
	button.BackgroundColor3 = Color3.fromRGB(26, 28, 37)
	button.BackgroundTransparency = 0.08
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.ImageTransparency = 1
	button.ClipsDescendants = false
	button.Visible = true
	button.ZIndex = 45
	button.Parent = guiRoot

	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 163, 94)
	stroke.Thickness = 2
	stroke.Transparency = 0.1
	stroke.Parent = button

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 135
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 136, 77)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 190, 118)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 108, 87)),
	})
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.76),
		NumberSequenceKeypoint.new(1, 0.45),
	})
	gradient.Parent = button

	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, 20, 1, 20)
	glow.BackgroundColor3 = Color3.fromRGB(255, 150, 82)
	glow.BackgroundTransparency = 0.82
	glow.BorderSizePixel = 0
	glow.ZIndex = 44
	glow.Parent = button

	local glowCorner = Instance.new("UICorner")
	glowCorner.CornerRadius = UDim.new(1, 0)
	glowCorner.Parent = glow

	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.fromScale(0.5, 0.08)
	shine.Size = UDim2.new(0.72, 0, 0.22, 0)
	shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	shine.BackgroundTransparency = 0.85
	shine.BorderSizePixel = 0
	shine.ZIndex = 46
	shine.Parent = button

	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(1, 0)
	shineCorner.Parent = shine

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(1, 1)
	icon.BackgroundTransparency = 1
	icon.Image = MOBILE_BOMB_READY_ICON
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 47
	icon.Parent = button

	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = button

	button.Activated:Connect(function()
		local tool = getAvailableBombTool()
		if not tool then
			updateMobileBombButtonState()
			return
		end

		local config = PickaxesConfigurations.Pickaxes[tool.Name]
		if not config then
			updateMobileBombButtonState()
			return
		end

		tryActivateBombFromButton(tool)
	end)

	mobileBombButton = button
	mobileBombButtonScale = scale
	mobileBombButtonIcon = icon

	layoutMobileBombButton()
	updateMobileBombButtonState()
	return button
end

-- [ JUICE: HIGHLIGHT LOGIC ]
local function clearHighlights()
	for part, box in pairs(activeHighlights) do
		if box then box:Destroy() end
	end
	table.clear(activeHighlights)
end

local function updateHighlights(tool: Tool)
	local config = PickaxesConfigurations.Pickaxes[tool.Name]
	if not config then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return end

	local handle = tool:FindFirstChild("Handle") :: BasePart
	local centerPosition = handle and handle.Position or root.Position

	local bonusRange = player:GetAttribute("BonusRange") or 0
	local radius = (config.Radius or 4) + bonusRange

	local validTargets = {}
	local minesFolder = Workspace:FindFirstChild("Mines")
	if minesFolder then
		for _, child in ipairs(minesFolder:GetChildren()) do
			if child.Name:match("LocalOres_") then
				table.insert(validTargets, child)
			end
		end
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = validTargets
	overlapParams.FilterType = Enum.RaycastFilterType.Include

	local hitParts = Workspace:GetPartBoundsInRadius(centerPosition, radius, overlapParams)
	local currentFrameParts = {}

	for _, hitPart in ipairs(hitParts) do
		if hitPart.Parent and hitPart.Parent.Name:match("LocalOres_") then
			local hp = hitPart:GetAttribute("Health")

			if type(hp) == "number" and hp > 0 and hitPart.Transparency < 1 then
				currentFrameParts[hitPart] = true

				if not activeHighlights[hitPart] then
					local box = Instance.new("SelectionBox")
					box.Adornee = hitPart
					box.Color3 = Color3.fromRGB(255, 255, 255)
					box.LineThickness = 0.05
					box.SurfaceColor3 = Color3.fromRGB(255, 255, 255)
					box.SurfaceTransparency = 0.9 
					box.Parent = hitPart
					activeHighlights[hitPart] = box
				end
			end
		end
	end

	for part, box in pairs(activeHighlights) do
		if not currentFrameParts[part] then
			if box then box:Destroy() end
			activeHighlights[part] = nil
		end
	end
end

-- [ JUICE: SOUND EFFECTS ]
local function playLocalSound(soundName: string)
	local soundTemplate = globalSounds:FindFirstChild(soundName)
	if soundTemplate and soundTemplate:IsA("Sound") then
		local newSound = soundTemplate:Clone()
		newSound.PlaybackSpeed = newSound.PlaybackSpeed * (math.random(90, 110) / 100)
		newSound.Parent = Workspace.CurrentCamera
		newSound:Play()
		Debris:AddItem(newSound, newSound.TimeLength + 0.1)
	end
end

-- [ JUICE: CAMERA SHAKE ]
local function shakeCamera()
	local char = player.Character
	local humanoid = char and char:FindFirstChild("Humanoid") :: Humanoid
	if not humanoid then return end

	task.spawn(function()
		for i = 1, 4 do
			local offsetX = (math.random() - 0.5) * 0.3
			local offsetY = (math.random() - 0.5) * 0.3
			local offsetZ = (math.random() - 0.5) * 0.3
			humanoid.CameraOffset = Vector3.new(offsetX, offsetY, offsetZ)
			task.wait(0.03)
		end
		humanoid.CameraOffset = Vector3.new(0, 0, 0)
	end)
end

-- [ JUICE: ORE SHAKE ]
local function shakeOre(orePart: BasePart)
	local origCFrame = orePart:GetAttribute("OriginalCFrame")
	if not origCFrame then
		origCFrame = orePart.CFrame
		orePart:SetAttribute("OriginalCFrame", origCFrame)
	end

	task.spawn(function()
		for i = 1, 4 do
			if not orePart.Parent then break end
			local offsetX = (math.random() - 0.5) * 0.4
			local offsetY = (math.random() - 0.5) * 0.4
			local offsetZ = (math.random() - 0.5) * 0.4
			orePart.CFrame = origCFrame * CFrame.new(offsetX, offsetY, offsetZ)
			task.wait(0.03)
		end
		if orePart.Parent then
			orePart.CFrame = origCFrame
		end
	end)
end

-- [ JUICE: PHYSICAL DEBRIS CHUNKS ]
local function spawnDebris(orePart: BasePart, amount: number)
	local origColor = orePart:GetAttribute("OriginalColor") or orePart.Color

	for i = 1, amount do
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(0.6, 0.6, 0.6)
		chunk.Color = origColor
		chunk.Material = Enum.Material.Slate
		chunk.CanCollide = false

		local offset = Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 3, (math.random() - 0.5) * 3)
		chunk.CFrame = orePart.CFrame * CFrame.new(offset)
		chunk.Parent = Workspace

		chunk.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 35, math.random(25, 45), (math.random() - 0.5) * 35)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random(-20, 20), math.random(-20, 20), math.random(-20, 20))

		local shrinkTween = TweenService:Create(
			chunk, 
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.2), 
			{Size = Vector3.new(0, 0, 0)}
		)
		shrinkTween:Play()

		Debris:AddItem(chunk, 0.8)
	end
end

-- [ HELPER: APPLY DAMAGE ]
local function applyDamageToOre(orePart: BasePart, damage: number)
	local currentHp = orePart:GetAttribute("Health")
	local maxHp = orePart:GetAttribute("MaxHealth")

	if type(currentHp) ~= "number" or type(maxHp) ~= "number" then return end

	currentHp -= damage

	local oreFolder = orePart.Parent
	if oreFolder and not oreFolder:GetAttribute("Impacted") then
		oreFolder:SetAttribute("Impacted", true)
	end

	local origColor = orePart:GetAttribute("OriginalColor")
	if not origColor then
		origColor = orePart.Color
		orePart:SetAttribute("OriginalColor", origColor)

		for _, child in ipairs(orePart:GetChildren()) do
			if child:IsA("Texture") or child:IsA("Decal") then
				child:SetAttribute("OriginalColor", child.Color3)
			end
		end
	end

	-- Health Percentage (0 to 1)
	local hpPercent = math.clamp(currentHp / maxHp, 0, 1)

	-- Break the Ore
	if currentHp <= 0 then
		spawnDebris(orePart, math.random(4, 7)) 

		orePart.Transparency = 1
		orePart.CanCollide = false
		Debris:AddItem(orePart, 0.1)
		return 
	else
		orePart:SetAttribute("Health", currentHp)
		shakeOre(orePart)
		spawnDebris(orePart, math.random(1, 2))

		-- CRACK DECAL LOGIC
		if CrackTemplate then
			for _, normalId in ipairs(Enum.NormalId:GetEnumItems()) do
				local crackName = "Crack_" .. normalId.Name
				local crackDecal = orePart:FindFirstChild(crackName) :: Decal

				if not crackDecal then
					crackDecal = CrackTemplate:Clone()
					crackDecal.Name = crackName
					crackDecal.Face = normalId
					crackDecal.Transparency = 1 
					crackDecal.Parent = orePart
				end

				crackDecal.Transparency = hpPercent
			end
		end
	end

	-- Darken Color as it takes damage
	local targetColor = origColor:Lerp(Color3.new(0, 0, 0), 1 - hpPercent)
	orePart.Color = targetColor

	for _, child in ipairs(orePart:GetChildren()) do
		if child:IsA("Texture") or child:IsA("Decal") then
			local texOrigColor = child:GetAttribute("OriginalColor")
			if texOrigColor and not child.Name:match("Crack_") then
				child.Color3 = texOrigColor:Lerp(Color3.new(0, 0, 0), 1 - hpPercent)
			end
		end
	end

	-- Hit Flash Effect
	local originalTransparency = orePart.Transparency
	orePart.Transparency = 0.5
	task.delay(0.1, function()
		if orePart.Parent and orePart.Transparency == 0.5 then 
			orePart.Transparency = originalTransparency 
		end
	end)
end

-- [ CORE MINING LOGIC ]
function attemptMine(tool: Tool)
	local config = PickaxesConfigurations.Pickaxes[tool.Name]
	if not config then return end

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return end

	-- 1. Check Cooldown
	local now = tick()
	if now - lastSwingTime < config.Cooldown then return end
	lastSwingTime = now

	-- 2. Play Animations & Sounds
	if currentAnimationTrack then
		currentAnimationTrack:Play()
	end
	playLocalSound("Swing") 

	-- TRIGGER COOLDOWN UI
	local handle = tool:FindFirstChild("Handle") :: BasePart
	if handle then
		local timerGui = handle:FindFirstChild("TimerGUI") :: BillboardGui
		if timerGui then
			local bar = timerGui:FindFirstChild("Bar")
			local progress = bar and bar:FindFirstChild("Progress") :: Frame
			local textLbl = bar and bar:FindFirstChild("Text") :: TextLabel

			if progress and textLbl then
				timerGui.Enabled = true

				progress.Size = UDim2.fromScale(1, 1)

				local tweenInfo = TweenInfo.new(config.Cooldown, Enum.EasingStyle.Linear)
				TweenService:Create(progress, tweenInfo, {Size = UDim2.fromScale(0, 1)}):Play()

				task.spawn(function()
					local endTime = tick() + config.Cooldown
					while tick() < endTime do
						if tool.Parent ~= char or not timerGui.Parent then break end 

						local remain = math.max(0, endTime - tick())
						textLbl.Text = string.format("%.1fs", remain)
						task.wait(0.03)
					end

					if timerGui and timerGui.Parent then
						textLbl.Text = "0.0s"
						timerGui.Enabled = false
					end
				end)
			end
		end
	end

	-- 3. Deal Damage
	local centerPosition = handle and handle.Position or root.Position
	local bonusRange = player:GetAttribute("BonusRange") or 0
	local radius = (config.Radius or 4) + bonusRange

	local validTargets = {}
	local minesFolder = Workspace:FindFirstChild("Mines")
	if minesFolder then
		for _, child in ipairs(minesFolder:GetChildren()) do
			if child.Name:match("LocalOres_") then
				table.insert(validTargets, child)
			end
		end
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterDescendantsInstances = validTargets
	overlapParams.FilterType = Enum.RaycastFilterType.Include

	local hitParts = Workspace:GetPartBoundsInRadius(centerPosition, radius, overlapParams)
	local hitAnything = false

	for _, hitPart in ipairs(hitParts) do
		if hitPart.Parent and hitPart.Parent.Name:match("LocalOres_") then
			applyDamageToOre(hitPart, config.Damage)
			hitAnything = true
		end
	end

	if hitAnything then
		shakeCamera()
		playLocalSound("Pickaxe")
	end
end

-- [ TOOL LISTENER ]
local function onCharacterAdded(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local animator = humanoid:WaitForChild("Animator") :: Animator
	currentTool = nil
	updateMobileBombButtonState()
	ensureMobileBombButton()

	local function handleToolEquipped(child: Instance)
		if child:IsA("Tool") and PickaxesConfigurations.Pickaxes[child.Name] then
			currentTool = child
			updateMobileBombButtonState()

			local handle = child:WaitForChild("Handle", 2) :: BasePart
			if handle then
				local existingTimer = handle:FindFirstChild("TimerGUI")
				if not existingTimer then
					local newTimer = TimerGUI_Template:Clone()
					newTimer.Enabled = false
					newTimer.Parent = handle
				else
					existingTimer.Enabled = false
				end
			end

			if activeToolConnection then activeToolConnection:Disconnect() end
			activeToolConnection = nil

			if currentAnimationTrack then
				currentAnimationTrack:Stop()
				currentAnimationTrack:Destroy()
				currentAnimationTrack = nil
			end

			if highlightLoop then highlightLoop:Disconnect() end
			highlightLoop = nil
			clearHighlights()
		end
	end

	character.ChildAdded:Connect(function(child)
		handleToolEquipped(child)
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			if child == currentTool then
				currentTool = nil
				updateMobileBombButtonState()
			end

			if activeToolConnection then 
				activeToolConnection:Disconnect() 
				activeToolConnection = nil 
			end
			if currentAnimationTrack then
				currentAnimationTrack:Stop()
				currentAnimationTrack:Destroy()
				currentAnimationTrack = nil
			end

			if highlightLoop then
				highlightLoop:Disconnect()
				highlightLoop = nil
			end
			clearHighlights()
		end
	end)

	for _, child in ipairs(character:GetChildren()) do
		handleToolEquipped(child)
	end
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then onCharacterAdded(player.Character) end

RunService.RenderStepped:Connect(function()
	if shouldShowMobileBombButton() then
		ensureMobileBombButton()
	end

	updateMobileBombButtonState()
end)

print("[MiningController] Juiced Mining + Mobile Tap Support Active!")
