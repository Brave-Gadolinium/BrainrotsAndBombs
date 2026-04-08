--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local JetpackManager = {}

local EVENTS_FOLDER_NAME = "Events"
local REQUEST_REMOTE_NAME = "RequestJetpackState"
local TEMPLATES_FOLDER_NAME = "Templates"
local ROCKET_TEMPLATE_NAME = "Rocket"
local PLAYER_JETPACK_NAME = "PlayerJetpack"
local ROOT_ATTACHMENT_NAME = "JetpackRootAttachment"
local LIFT_CONSTRAINT_NAME = "JetpackLift"
local ATTACHMENT_BODY_NAME = "BodyAttachment"
local ATTACHMENT_BODY_FALLBACK_NAME = "AttachmentBody"
local ROCKET_ATTACHMENT_NAME = "RocketAttachment"
local FIRE_EMITTER_NAME = "Fire"
local TIMER_TEMPLATE_NAME = "TimerGUI"
local TIMER_GUI_NAME = "JetpackTimerGUI"
local COOLDOWN_ATTRIBUTE_NAME = "JetpackCooldownEndsAt"
local LIFT_VELOCITY = 28
local LIFT_MAX_FORCE = 100000
local CHARACTER_READY_TIMEOUT = 10
local LIFT_RAMP_DURATION = 0.22
local LIFT_RAMP_TWEEN_INFO = TweenInfo.new(LIFT_RAMP_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MAX_FLIGHT_DURATION = 5
local COOLDOWN_DURATION = 3
local TIMER_OFFSET = Vector3.new(0, 3.1, 0)

type CharacterConnections = {
	Died: RBXScriptConnection?,
	Sit: RBXScriptConnection?,
	Ancestry: RBXScriptConnection?,
}

local requestRemote: RemoteEvent? = nil
local characterConnectionsByPlayer: {[Player]: CharacterConnections} = {}
local warnedMissingByCharacter: {[Model]: {[string]: boolean}} = {}
local liftTweensByCharacter: {[Model]: Tween} = {}
local cooldownTweensByCharacter: {[Model]: Tween} = {}
local cooldownRunIdsByCharacter: {[Model]: number} = {}
local flightSessionIdsByCharacter: {[Model]: number} = {}
local cooldownEndsAtByPlayer: {[Player]: number} = {}
local flightRemainingByCharacter: {[Model]: number} = {}
local flightStartedAtByCharacter: {[Model]: number} = {}
local beginCooldown: (player: Player, character: Model) -> ()
local setJetpackActive: (character: Model, active: boolean) -> ()

local function cancelLiftTween(character: Model)
	local tween = liftTweensByCharacter[character]
	if not tween then
		return
	end

	tween:Cancel()
	liftTweensByCharacter[character] = nil
end

local function nextCooldownRunId(character: Model): number
	local nextRunId = (cooldownRunIdsByCharacter[character] or 0) + 1
	cooldownRunIdsByCharacter[character] = nextRunId
	return nextRunId
end

local function cancelCooldownTween(character: Model)
	local tween = cooldownTweensByCharacter[character]
	if not tween then
		return
	end

	tween:Cancel()
	cooldownTweensByCharacter[character] = nil
end

local function invalidateFlightSession(character: Model)
	flightSessionIdsByCharacter[character] = (flightSessionIdsByCharacter[character] or 0) + 1
end

local function getNow(): number
	return Workspace:GetServerTimeNow()
end

local function formatSeconds(seconds: number): string
	return string.format("%.1fs", math.max(0, seconds))
end

local function getFlightRemaining(character: Model): number
	local remaining = flightRemainingByCharacter[character]
	if type(remaining) ~= "number" then
		return MAX_FLIGHT_DURATION
	end

	return math.clamp(remaining, 0, MAX_FLIGHT_DURATION)
end

local function resetFlightRemaining(character: Model)
	flightRemainingByCharacter[character] = MAX_FLIGHT_DURATION
	flightStartedAtByCharacter[character] = nil
end

local function consumeFlightRemaining(character: Model): number
	local startedAt = flightStartedAtByCharacter[character]
	if type(startedAt) ~= "number" then
		return getFlightRemaining(character)
	end

	flightStartedAtByCharacter[character] = nil

	local elapsed = math.max(0, getNow() - startedAt)
	local remaining = math.max(0, getFlightRemaining(character) - elapsed)
	flightRemainingByCharacter[character] = remaining
	return remaining
end

local function warnCharacterOnce(character: Model, key: string, message: string)
	local warnedKeys = warnedMissingByCharacter[character]
	if not warnedKeys then
		warnedKeys = {}
		warnedMissingByCharacter[character] = warnedKeys
	end

	if warnedKeys[key] then
		return
	end

	warnedKeys[key] = true
	warn(`[JetpackManager] {message} (character: {character:GetFullName()})`)
end

local function disconnectCharacterConnections(player: Player)
	local connections = characterConnectionsByPlayer[player]
	if not connections then
		return
	end

	for _, connection in pairs(connections) do
		if connection then
			connection:Disconnect()
		end
	end

	characterConnectionsByPlayer[player] = nil
end

local function getBackPart(character: Model): BasePart?
	local upperTorso = character:FindFirstChild("UpperTorso")
	if upperTorso and upperTorso:IsA("BasePart") then
		return upperTorso
	end

	local torso = character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso
	end

	return nil
end

local function getHumanoid(character: Model): Humanoid?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:IsA("Humanoid") then
		return humanoid
	end

	return nil
end

local function getRootPart(character: Model): BasePart?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function findRocketModel(character: Model): Model?
	local rocket = character:FindFirstChild(PLAYER_JETPACK_NAME)
	if rocket and rocket:IsA("Model") then
		return rocket
	end

	return nil
end

local function findFirstBasePart(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function destroyNamedChildren(parent: Instance, childName: string)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == childName then
			child:Destroy()
		end
	end
end

local function getAttachmentBody(rocket: Model): Attachment?
	local primaryAttachment = rocket:FindFirstChild(ATTACHMENT_BODY_NAME, true)
	if primaryAttachment and primaryAttachment:IsA("Attachment") then
		return primaryAttachment
	end

	local fallbackAttachment = rocket:FindFirstChild(ATTACHMENT_BODY_FALLBACK_NAME, true)
	if fallbackAttachment and fallbackAttachment:IsA("Attachment") then
		return fallbackAttachment
	end

	return nil
end

local function getTimerWidgets(timerGui: BillboardGui): (Frame?, TextLabel?)
	local bar = timerGui:FindFirstChild("Bar")
	if not bar then
		return nil, nil
	end

	local progress = bar:FindFirstChild("Progress")
	local textLabel = bar:FindFirstChild("Text")
	if progress and progress:IsA("Frame") and textLabel and textLabel:IsA("TextLabel") then
		return progress, textLabel
	end

	return nil, nil
end

local function createFallbackTimerGui(): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = TIMER_GUI_NAME
	billboard.Size = UDim2.fromOffset(96, 36)
	billboard.AlwaysOnTop = true
	billboard.StudsOffsetWorldSpace = TIMER_OFFSET

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.5)
	bar.Size = UDim2.new(1, 0, 1, 0)
	bar.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bar

	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.Size = UDim2.fromScale(1, 1)
	progress.BackgroundColor3 = Color3.fromRGB(255, 145, 77)
	progress.BorderSizePixel = 0
	progress.Parent = bar

	local progressCorner = Instance.new("UICorner")
	progressCorner.CornerRadius = UDim.new(0, 10)
	progressCorner.Parent = progress

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Text"
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.new(1, 1, 1)
	textLabel.TextStrokeTransparency = 0.35
	textLabel.Text = formatSeconds(0)
	textLabel.Parent = bar

	return billboard
end

local function ensureCooldownTimerGui(character: Model): BillboardGui?
	local rocket = findRocketModel(character)
	if not rocket then
		return nil
	end

	local rocketRoot = rocket.PrimaryPart or findFirstBasePart(rocket)
	if not rocketRoot then
		return nil
	end

	local existing = rocketRoot:FindFirstChild(TIMER_GUI_NAME)
	if existing and existing:IsA("BillboardGui") then
		existing.Adornee = rocketRoot
		return existing
	end

	local templatesFolder = ReplicatedStorage:FindFirstChild(TEMPLATES_FOLDER_NAME)
	local timerTemplate = templatesFolder and templatesFolder:FindFirstChild(TIMER_TEMPLATE_NAME)
	local timerGui: BillboardGui

	if timerTemplate and timerTemplate:IsA("BillboardGui") then
		timerGui = timerTemplate:Clone()
	else
		timerGui = createFallbackTimerGui()
	end

	timerGui.Name = TIMER_GUI_NAME
	timerGui.Enabled = false
	timerGui.Adornee = rocketRoot
	timerGui.StudsOffsetWorldSpace = TIMER_OFFSET
	timerGui.Parent = rocketRoot
	return timerGui
end

local function clearCooldownVisual(character: Model)
	nextCooldownRunId(character)
	cancelCooldownTween(character)

	local timerGui = ensureCooldownTimerGui(character)
	if not timerGui then
		return
	end

	local progress, textLabel = getTimerWidgets(timerGui)
	if progress then
		progress.Size = UDim2.fromScale(1, 1)
	end
	if textLabel then
		textLabel.Text = formatSeconds(0)
	end

	timerGui.Enabled = false
end

local function showCooldownVisual(character: Model, duration: number, cooldownEndsAt: number)
	if duration <= 0 then
		clearCooldownVisual(character)
		return
	end

	local timerGui = ensureCooldownTimerGui(character)
	if not timerGui then
		return
	end

	local progress, textLabel = getTimerWidgets(timerGui)
	if not progress or not textLabel then
		return
	end

	local runId = nextCooldownRunId(character)
	cancelCooldownTween(character)

	timerGui.Enabled = true
	progress.Size = UDim2.fromScale(1, 1)
	textLabel.Text = formatSeconds(cooldownEndsAt - getNow())

	local tween = TweenService:Create(progress, TweenInfo.new(duration, Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(0, 1),
	})
	cooldownTweensByCharacter[character] = tween
	tween.Completed:Connect(function()
		if cooldownTweensByCharacter[character] == tween then
			cooldownTweensByCharacter[character] = nil
		end
	end)
	tween:Play()

	task.spawn(function()
		while character.Parent and cooldownRunIdsByCharacter[character] == runId do
			local remaining = cooldownEndsAt - getNow()
			if remaining <= 0 then
				break
			end

			textLabel.Text = formatSeconds(remaining)
			task.wait(0.05)
		end

		if cooldownRunIdsByCharacter[character] ~= runId then
			return
		end

		textLabel.Text = formatSeconds(0)
		timerGui.Enabled = false
	end)
end

local function disableRocketFire(character: Model)
	local rocket = findRocketModel(character)
	if not rocket then
		return
	end

	local rocketAttachment = rocket:FindFirstChild(ROCKET_ATTACHMENT_NAME, true)
	if not rocketAttachment or not rocketAttachment:IsA("Attachment") then
		warnCharacterOnce(character, "RocketAttachment", `Missing {ROCKET_ATTACHMENT_NAME} in {PLAYER_JETPACK_NAME}`)
		return
	end

	local fire = rocketAttachment:FindFirstChild(FIRE_EMITTER_NAME)
	if not fire or not fire:IsA("ParticleEmitter") then
		warnCharacterOnce(character, "Fire", `Missing {FIRE_EMITTER_NAME} particle emitter in {ROCKET_ATTACHMENT_NAME}`)
		return
	end

	fire.Enabled = false
end

local function cleanupCharacterArtifacts(character: Model)
	cancelLiftTween(character)
	cancelCooldownTween(character)
	invalidateFlightSession(character)
	disableRocketFire(character)
	character:SetAttribute(COOLDOWN_ATTRIBUTE_NAME, nil)
	destroyNamedChildren(character, PLAYER_JETPACK_NAME)

	local rootPart = getRootPart(character)
	if rootPart then
		destroyNamedChildren(rootPart, ROOT_ATTACHMENT_NAME)
		destroyNamedChildren(rootPart, LIFT_CONSTRAINT_NAME)
	end

	cooldownRunIdsByCharacter[character] = nil
	flightSessionIdsByCharacter[character] = nil
	flightRemainingByCharacter[character] = nil
	flightStartedAtByCharacter[character] = nil
	warnedMissingByCharacter[character] = nil
end

local function stripRocketDescendants(rocket: Model)
	for _, descendant in ipairs(rocket:GetDescendants()) do
		if descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("ModuleScript")
			or descendant:IsA("Weld")
			or descendant:IsA("WeldConstraint")
			or descendant:IsA("ManualWeld")
			or descendant:IsA("Motor6D") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.Massless = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

local function createWeld(part0: BasePart, part1: BasePart)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = part0
end

local function ensureRocketModel(character: Model): Model?
	local existingRocket = findRocketModel(character)
	if existingRocket then
		return existingRocket
	end

	local templatesFolder = ReplicatedStorage:FindFirstChild(TEMPLATES_FOLDER_NAME)
	if not templatesFolder then
		warnCharacterOnce(character, "Templates", `Missing ReplicatedStorage.{TEMPLATES_FOLDER_NAME}`)
		return nil
	end

	local rocketTemplate = templatesFolder:FindFirstChild(ROCKET_TEMPLATE_NAME)
	if not rocketTemplate then
		warnCharacterOnce(character, "RocketTemplate", `Missing {TEMPLATES_FOLDER_NAME}.{ROCKET_TEMPLATE_NAME}`)
		return nil
	end

	if not rocketTemplate:IsA("Model") then
		warnCharacterOnce(character, "RocketTemplateType", `{TEMPLATES_FOLDER_NAME}.{ROCKET_TEMPLATE_NAME} is not a Model`)
		return nil
	end

	local backPart = getBackPart(character)
	if not backPart then
		warnCharacterOnce(character, "BackPart", "Missing UpperTorso/Torso for jetpack attachment")
		return nil
	end

	local rocket = rocketTemplate:Clone()
	rocket.Name = PLAYER_JETPACK_NAME
	stripRocketDescendants(rocket)
	rocket.Parent = character

	local rootPart = rocket.PrimaryPart or findFirstBasePart(rocket)
	if not rootPart then
		warnCharacterOnce(character, "RocketPrimaryPart", "Jetpack rocket has no BasePart to weld")
		rocket:Destroy()
		return nil
	end

	rocket.PrimaryPart = rootPart

	local attachmentBody = getAttachmentBody(rocket)
	if not attachmentBody then
		warnCharacterOnce(
			character,
			"AttachmentBody",
			`Missing {ATTACHMENT_BODY_NAME}/{ATTACHMENT_BODY_FALLBACK_NAME} attachment in rocket`
		)
		rocket:Destroy()
		return nil
	end

	rocket:PivotTo(backPart.CFrame * attachmentBody.CFrame:Inverse())

	createWeld(backPart, rootPart)

	for _, descendant in ipairs(rocket:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= rootPart then
			createWeld(rootPart, descendant)
		end
	end

	disableRocketFire(character)
	return rocket
end

local function ensureJetpackMotion(character: Model): (Attachment?, LinearVelocity?)
	local rootPart = getRootPart(character)
	if not rootPart then
		warnCharacterOnce(character, "HumanoidRootPart", "Missing HumanoidRootPart for jetpack flight")
		return nil, nil
	end

	local rootAttachment = rootPart:FindFirstChild(ROOT_ATTACHMENT_NAME)
	if rootAttachment and not rootAttachment:IsA("Attachment") then
		rootAttachment:Destroy()
		rootAttachment = nil
	end

	if not rootAttachment then
		rootAttachment = Instance.new("Attachment")
		rootAttachment.Name = ROOT_ATTACHMENT_NAME
		rootAttachment.Parent = rootPart
	end

	local lift = rootPart:FindFirstChild(LIFT_CONSTRAINT_NAME)
	if lift and not lift:IsA("LinearVelocity") then
		lift:Destroy()
		lift = nil
	end

	if not lift then
		lift = Instance.new("LinearVelocity")
		lift.Name = LIFT_CONSTRAINT_NAME
		lift.Parent = rootPart
	end

	local linearVelocity = lift :: LinearVelocity
	linearVelocity.Attachment0 = rootAttachment :: Attachment
	linearVelocity.Enabled = false
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	linearVelocity.LineDirection = Vector3.yAxis
	linearVelocity.LineVelocity = 0
	linearVelocity.ForceLimitsEnabled = true
	linearVelocity.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	linearVelocity.MaxForce = LIFT_MAX_FORCE

	return rootAttachment :: Attachment, linearVelocity
end

local function setRocketFireEnabled(character: Model, enabled: boolean)
	local rocket = if enabled then ensureRocketModel(character) else findRocketModel(character)
	if not rocket then
		return
	end

	local rocketAttachment = rocket:FindFirstChild(ROCKET_ATTACHMENT_NAME, true)
	if not rocketAttachment or not rocketAttachment:IsA("Attachment") then
		warnCharacterOnce(character, "RocketAttachment", `Missing {ROCKET_ATTACHMENT_NAME} in {PLAYER_JETPACK_NAME}`)
		return
	end

	local fire = rocketAttachment:FindFirstChild(FIRE_EMITTER_NAME)
	if not fire or not fire:IsA("ParticleEmitter") then
		warnCharacterOnce(character, "Fire", `Missing {FIRE_EMITTER_NAME} particle emitter in {ROCKET_ATTACHMENT_NAME}`)
		return
	end

	fire.Enabled = enabled
end

local function ensureCharacterSetup(character: Model): LinearVelocity?
	ensureRocketModel(character)
	local _, lift = ensureJetpackMotion(character)
	return lift
end

local function getCooldownRemaining(player: Player): number
	local cooldownEndsAt = cooldownEndsAtByPlayer[player]
	if type(cooldownEndsAt) ~= "number" then
		return 0
	end

	return math.max(0, cooldownEndsAt - getNow())
end

local function syncCooldownStateToCharacter(player: Player, character: Model)
	local cooldownEndsAt = cooldownEndsAtByPlayer[player]
	local remaining = getCooldownRemaining(player)
	if type(cooldownEndsAt) == "number" and remaining > 0 then
		character:SetAttribute(COOLDOWN_ATTRIBUTE_NAME, cooldownEndsAt)
		showCooldownVisual(character, remaining, cooldownEndsAt)
	else
		character:SetAttribute(COOLDOWN_ATTRIBUTE_NAME, nil)
		clearCooldownVisual(character)
	end
end

local function startFlightTimeout(player: Player, character: Model, duration: number)
	local sessionId = (flightSessionIdsByCharacter[character] or 0) + 1
	flightSessionIdsByCharacter[character] = sessionId

	task.delay(duration, function()
		if flightSessionIdsByCharacter[character] ~= sessionId then
			return
		end

		if not character.Parent or player.Character ~= character then
			return
		end

		local rootPart = getRootPart(character)
		local lift = rootPart and rootPart:FindFirstChild(LIFT_CONSTRAINT_NAME)
		if not lift or not lift:IsA("LinearVelocity") or not lift.Enabled then
			return
		end

		setJetpackActive(character, false)
	end)
end

local function waitForCharacterReady(character: Model): boolean
	local deadline = os.clock() + CHARACTER_READY_TIMEOUT
	while character.Parent and os.clock() < deadline do
		if getHumanoid(character) and getRootPart(character) and getBackPart(character) then
			return true
		end

		task.wait(0.1)
	end

	return false
end

local function bindHumanoidConnections(character: Model, humanoid: Humanoid, connections: CharacterConnections)
	if connections.Died or connections.Sit then
		return
	end

	connections.Died = humanoid.Died:Connect(function()
		setJetpackActive(character, false)
		cleanupCharacterArtifacts(character)
	end)

	connections.Sit = humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
		if humanoid.Sit then
			setJetpackActive(character, false)
		end
	end)
end

beginCooldown = function(player: Player, character: Model)
	local cooldownEndsAt = getNow() + COOLDOWN_DURATION
	cooldownEndsAtByPlayer[player] = cooldownEndsAt
	flightStartedAtByCharacter[character] = nil
	flightRemainingByCharacter[character] = 0

	local currentCharacter = player.Character
	if currentCharacter and currentCharacter.Parent then
		syncCooldownStateToCharacter(player, currentCharacter)
	elseif character.Parent then
		syncCooldownStateToCharacter(player, character)
	end

	task.delay(COOLDOWN_DURATION, function()
		if cooldownEndsAtByPlayer[player] ~= cooldownEndsAt then
			return
		end

		cooldownEndsAtByPlayer[player] = nil

		local latestCharacter = player.Character
		if latestCharacter and latestCharacter.Parent then
			resetFlightRemaining(latestCharacter)
			syncCooldownStateToCharacter(player, latestCharacter)
		end
	end)
end

setJetpackActive = function(character: Model, active: boolean)
	local humanoid = getHumanoid(character)
	local rootPart = getRootPart(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return
	end

	local lift = ensureCharacterSetup(character)
	if not lift then
		return
	end

	if active and humanoid.Sit then
		active = false
	end

	humanoid.Jump = false

	if lift.Enabled == active then
		if active then
			local currentTween = liftTweensByCharacter[character]
			if currentTween then
				currentTween:Play()
			end
		else
			invalidateFlightSession(character)
		end
		setRocketFireEnabled(character, active)
		return
	end

	cancelLiftTween(character)
	invalidateFlightSession(character)

	if active then
		local remainingFlight = getFlightRemaining(character)
		if remainingFlight <= 0 then
			if player and getCooldownRemaining(player) <= 0 then
				beginCooldown(player, character)
			end
			setRocketFireEnabled(character, false)
			return
		end

		clearCooldownVisual(character)
		local startVelocity = math.clamp(rootPart.AssemblyLinearVelocity.Y, 0, LIFT_VELOCITY)
		flightStartedAtByCharacter[character] = getNow()
		lift.LineVelocity = startVelocity
		lift.Enabled = true

		local tween = TweenService:Create(lift, LIFT_RAMP_TWEEN_INFO, {
			LineVelocity = LIFT_VELOCITY,
		})
		liftTweensByCharacter[character] = tween
		tween.Completed:Connect(function()
			if liftTweensByCharacter[character] == tween then
				liftTweensByCharacter[character] = nil
			end
		end)
		tween:Play()
		if player then
			startFlightTimeout(player, character, remainingFlight)
		end
	else
		local remainingFlight = consumeFlightRemaining(character)
		lift.Enabled = false
		lift.LineVelocity = 0

		if remainingFlight <= 0 and player and getCooldownRemaining(player) <= 0 then
			beginCooldown(player, character)
		end
	end

	setRocketFireEnabled(character, active)
end

local function bindCharacter(player: Player, character: Model)
	disconnectCharacterConnections(player)
	cleanupCharacterArtifacts(character)

	task.spawn(function()
		local isReady = waitForCharacterReady(character)
		if not character.Parent or player.Character ~= character then
			return
		end

		if not isReady then
			warnCharacterOnce(character, "CharacterReadyTimeout", "Timed out while waiting for character parts needed by the jetpack")
		end

		ensureCharacterSetup(character)
		if flightRemainingByCharacter[character] == nil then
			resetFlightRemaining(character)
		end
		syncCooldownStateToCharacter(player, character)
	end)

	local connections: CharacterConnections = {}
	local humanoid = getHumanoid(character)

	if humanoid then
		bindHumanoidConnections(character, humanoid, connections)
	else
		task.spawn(function()
			local waitedHumanoid = character:FindFirstChild("Humanoid") or character:WaitForChild("Humanoid", CHARACTER_READY_TIMEOUT)
			if not waitedHumanoid or not waitedHumanoid:IsA("Humanoid") then
				return
			end

			if not character.Parent or player.Character ~= character then
				return
			end

			local activeConnections = characterConnectionsByPlayer[player]
			if activeConnections ~= connections then
				return
			end

			bindHumanoidConnections(character, waitedHumanoid, connections)
		end)
	end

	connections.Ancestry = character.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		setJetpackActive(character, false)
		cleanupCharacterArtifacts(character)
		warnedMissingByCharacter[character] = nil
	end)

	characterConnectionsByPlayer[player] = connections
end

local function onRequestJetpackState(player: Player, active: boolean)
	if type(active) ~= "boolean" then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = getHumanoid(character)
	local rootPart = getRootPart(character)
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end

	if active and humanoid.Sit then
		setJetpackActive(character, false)
		return
	end

	if active then
		local remainingCooldown = getCooldownRemaining(player)
		if remainingCooldown > 0 then
			syncCooldownStateToCharacter(player, character)
			setJetpackActive(character, false)
			return
		end

		setJetpackActive(character, true)
		return
	end

	setJetpackActive(character, false)
end

local function ensureEventsFolder(): Folder
	local eventsFolder = ReplicatedStorage:FindFirstChild(EVENTS_FOLDER_NAME)
	if eventsFolder and eventsFolder:IsA("Folder") then
		return eventsFolder
	end

	local createdFolder = Instance.new("Folder")
	createdFolder.Name = EVENTS_FOLDER_NAME
	createdFolder.Parent = ReplicatedStorage
	return createdFolder
end

local function ensureRequestRemote(): RemoteEvent
	if requestRemote and requestRemote.Parent then
		return requestRemote
	end

	local eventsFolder = ensureEventsFolder()
	local remote = eventsFolder:FindFirstChild(REQUEST_REMOTE_NAME)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REQUEST_REMOTE_NAME
		remote.Parent = eventsFolder
	end

	requestRemote = remote :: RemoteEvent
	return requestRemote :: RemoteEvent
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)

	player.CharacterRemoving:Connect(function(character)
		setJetpackActive(character, false)
		cleanupCharacterArtifacts(character)
	end)

	if player.Character then
		bindCharacter(player, player.Character)
	end
end

function JetpackManager:Init()
	local remote = ensureRequestRemote()
	remote.OnServerEvent:Connect(onRequestJetpackState)
end

function JetpackManager:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		disconnectCharacterConnections(player)
		cooldownEndsAtByPlayer[player] = nil

		local character = player.Character
		if character then
			setJetpackActive(character, false)
			cleanupCharacterArtifacts(character)
		end

		characterConnectionsByPlayer[player] = nil
	end)
end

return JetpackManager
