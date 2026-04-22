--!strict

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local JoinGiftBrainrotConfiguration = require(ReplicatedStorage.Modules.JoinGiftBrainrotConfiguration)
local MutationConfigurations = require(ReplicatedStorage.Modules.MutationConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)
local RarityUtils = require(ReplicatedStorage.Modules.RarityUtils)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local templates = ReplicatedStorage:WaitForChild("Templates")
local remotesFolder = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("JoinGiftBrainrot")
local getStateRemote = remotesFolder:WaitForChild("GetState") :: RemoteFunction
local markPreviewShownRemote = remotesFolder:WaitForChild("MarkPreviewShown") :: RemoteEvent
local requestPickupRemote = remotesFolder:WaitForChild("RequestPickup") :: RemoteFunction
local stateUpdatedRemote = remotesFolder:WaitForChild("StateUpdated") :: RemoteEvent

local infoGuiTemplate = templates:WaitForChild("InfoGUI")
local itemsFolder = ReplicatedStorage:FindFirstChild("Items")
local minesFolder = Workspace:FindFirstChild("Mines")

local activeToken: string? = nil
local activeModel: Model? = nil
local activePrompt: ProximityPrompt? = nil
local activeHighlight: Highlight? = nil
local activeHighlightConnection: RBXScriptConnection? = nil
local activePromptConnection: RBXScriptConnection? = nil
local refreshNonce = 0
local pickupRequestInFlight = false

local function getAliveRootPart(): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function isClientReadyForPreview(): boolean
	if player:GetAttribute("ProfileReady") ~= true then
		return false
	end

	if Workspace:GetAttribute("ServerSystemsReady") ~= true then
		return false
	end

	if Workspace:GetAttribute("TerrainResetInProgress") == true then
		return false
	end

	if playerGui:FindFirstChild("LoadingScreen") ~= nil then
		return false
	end

	return getAliveRootPart() ~= nil
end

local function disconnectConnection(connection: RBXScriptConnection?)
	if connection then
		connection:Disconnect()
	end
end

local function cleanupPreview()
	pickupRequestInFlight = false
	activeToken = nil

	disconnectConnection(activePromptConnection)
	activePromptConnection = nil

	disconnectConnection(activeHighlightConnection)
	activeHighlightConnection = nil

	if activeHighlight then
		activeHighlight:Destroy()
		activeHighlight = nil
	end

	if activePrompt then
		activePrompt:Destroy()
		activePrompt = nil
	end

	if activeModel then
		if activeModel.Parent then
			activeModel:Destroy()
		end
		activeModel = nil
	end
end

local function getFallbackItemColor(mutation: string, rarity: string): Color3
	local mutationConfig = (MutationConfigurations :: any)[mutation]
	if mutation ~= "Normal" and mutationConfig and mutationConfig.TextColor then
		return mutationConfig.TextColor
	end

	local normalizedRarity = RarityUtils.Normalize(rarity) or rarity
	local rarityConfig = (RarityConfigurations :: any)[normalizedRarity]
	if rarityConfig and rarityConfig.TextColor then
		return rarityConfig.TextColor
	end

	return Color3.fromRGB(255, 255, 255)
end

local function createFallbackPreviewModel(itemName: string, mutation: string, rarity: string): Model
	local model = Instance.new("Model")
	model.Name = itemName

	local rootPart = Instance.new("Part")
	rootPart.Name = "Root"
	rootPart.Shape = Enum.PartType.Ball
	rootPart.Size = Vector3.new(2.4, 2.4, 2.4)
	rootPart.Material = if mutation ~= "Normal" then Enum.Material.Neon else Enum.Material.SmoothPlastic
	rootPart.Color = getFallbackItemColor(mutation, rarity)
	rootPart.TopSurface = Enum.SurfaceType.Smooth
	rootPart.BottomSurface = Enum.SurfaceType.Smooth
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	return model
end

local function getPreviewTemplate(itemName: string, mutation: string): Model?
	if not itemsFolder then
		return nil
	end

	local mutationFolder = itemsFolder:FindFirstChild(mutation)
	local mutationTemplate = mutationFolder and mutationFolder:FindFirstChild(itemName)
	if mutationTemplate and mutationTemplate:IsA("Model") then
		return mutationTemplate
	end

	local normalFolder = itemsFolder:FindFirstChild("Normal")
	local normalTemplate = normalFolder and normalFolder:FindFirstChild(itemName)
	if normalTemplate and normalTemplate:IsA("Model") then
		return normalTemplate
	end

	return nil
end

local function buildPreviewModel(itemName: string, mutation: string, rarity: string, level: number): (Model?, BasePart?)
	local template = getPreviewTemplate(itemName, mutation)
	local model = if template then template:Clone() else createFallbackPreviewModel(itemName, mutation, rarity)

	local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not primaryPart or not primaryPart:IsA("BasePart") then
		model:Destroy()
		return nil, nil
	end

	model.PrimaryPart = primaryPart
	model.Name = "JoinGiftPreview"
	model:SetAttribute("OriginalName", itemName)
	model:SetAttribute("Mutation", mutation)
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Level", level)
	model:SetAttribute("IsSpawnedItem", true)

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	return model, primaryPart
end

local function setupPreviewInfoGui(target: Model, rootPart: BasePart, itemName: string, mutation: string, rarity: string, level: number)
	local existingGui = target:FindFirstChild("InfoGUI")
	if existingGui then
		existingGui:Destroy()
	end

	local infoGui = infoGuiTemplate:Clone()
	infoGui.Name = "InfoGUI"
	infoGui.Adornee = rootPart

	local labelsFrame = infoGui:WaitForChild("TextLabels")
	local lblEarnings = labelsFrame:WaitForChild("Earnings") :: TextLabel
	local lblRarity = labelsFrame:WaitForChild("Rarity") :: TextLabel
	local lblName = labelsFrame:WaitForChild("Name") :: TextLabel
	local lblMutation = labelsFrame:WaitForChild("Mutation") :: TextLabel

	local itemData = ItemConfigurations.GetItemData(itemName)
	local displayName = itemData and itemData.DisplayName or itemName
	local baseIncome = itemData and itemData.Income or 0
	local rarityName = RarityUtils.Normalize(rarity) or rarity
	local mutationName = if mutation ~= "" then mutation else "Normal"

	lblName.Text = displayName
	lblEarnings.Text = "+" .. NumberFormatter.Format(baseIncome) .. "/s"

	local rarityConfig = RarityConfigurations[rarityName]
	lblRarity.Text = rarityName
	lblRarity.TextColor3 = Color3.fromRGB(255, 255, 255)
	if rarityConfig then
		lblRarity.Text = rarityConfig.DisplayName
		lblRarity.TextColor3 = rarityConfig.TextColor
		local stroke = lblRarity:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = rarityConfig.StrokeColor
			stroke.Thickness = rarityConfig.StrokeThickness
		end
		local gradient = lblRarity:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = rarityConfig.GradientColor
		end
	end

	local mutationConfig = MutationConfigurations[mutationName]
	lblMutation.Text = mutationName
	lblMutation.TextColor3 = Color3.fromRGB(255, 255, 255)
	if mutationConfig then
		lblMutation.Text = mutationConfig.DisplayName
		lblMutation.TextColor3 = mutationConfig.TextColor
		local stroke = lblMutation:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = mutationConfig.StrokeColor
			stroke.Thickness = mutationConfig.StrokeThickness
		end
		local gradient = lblMutation:FindFirstChildOfClass("UIGradient")
		if gradient then
			gradient.Color = mutationConfig.GradientColor
		end
	end

	infoGui.Parent = target
end

local function getBottomOffset(model: Model): number
	local extents = model:GetExtentsSize()
	local boundingBoxCFrame = model:GetBoundingBox()
	return model:GetPivot().Position.Y - (boundingBoxCFrame.Position.Y - (extents.Y * 0.5))
end

local function clampPositionToZone(position: Vector3): Vector3
	local zoneName = tostring(JoinGiftBrainrotConfiguration.ZoneName or "Zone0")
	local zonePart = minesFolder and minesFolder:FindFirstChild(zoneName)
	if not zonePart or not zonePart:IsA("BasePart") then
		return position
	end

	local localPosition = zonePart.CFrame:PointToObjectSpace(position)
	local halfSize = zonePart.Size * 0.5
	local padding = math.max(0, tonumber(JoinGiftBrainrotConfiguration.ZoneClampPadding) or 0)
	local clampedPosition = Vector3.new(
		math.clamp(localPosition.X, -halfSize.X + padding, halfSize.X - padding),
		localPosition.Y,
		math.clamp(localPosition.Z, -halfSize.Z + padding, halfSize.Z - padding)
	)

	return zonePart.CFrame:PointToWorldSpace(clampedPosition)
end

local function resolvePreviewCFrame(model: Model): CFrame?
	local rootPart = getAliveRootPart()
	if not rootPart then
		return nil
	end

	local forwardDistance = math.max(2, tonumber(JoinGiftBrainrotConfiguration.PreviewForwardDistance) or 8)
	local basePosition = rootPart.Position + (rootPart.CFrame.LookVector * forwardDistance)
	local targetPosition = clampPositionToZone(basePosition)

	local rayOrigin = targetPosition + Vector3.new(0, math.max(2, tonumber(JoinGiftBrainrotConfiguration.PreviewRaycastHeight) or 16), 0)
	local rayDirection = Vector3.new(0, -math.max(4, tonumber(JoinGiftBrainrotConfiguration.PreviewRaycastDepth) or 64), 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {player.Character or player}

	local result = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local floorY = result and result.Position.Y or targetPosition.Y
	local bottomOffset = getBottomOffset(model)

	return CFrame.new(targetPosition.X, floorY + bottomOffset, targetPosition.Z)
end

local function setupPulsingHighlight(target: Model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "JoinGiftHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = JoinGiftBrainrotConfiguration.HighlightFillColor
	highlight.OutlineColor = JoinGiftBrainrotConfiguration.HighlightOutlineColor
	highlight.OutlineTransparency = tonumber(JoinGiftBrainrotConfiguration.HighlightOutlineTransparency) or 0
	highlight.Adornee = target
	highlight.Parent = playerGui

	activeHighlight = highlight
	activeHighlightConnection = RunService.RenderStepped:Connect(function()
		if not activeHighlight or activeHighlight ~= highlight or highlight.Parent == nil then
			return
		end

		local pulseSpeed = tonumber(JoinGiftBrainrotConfiguration.HighlightPulseSpeed) or 3.5
		local minTransparency = tonumber(JoinGiftBrainrotConfiguration.HighlightMinFillTransparency) or 0.15
		local maxTransparency = tonumber(JoinGiftBrainrotConfiguration.HighlightMaxFillTransparency) or 0.45
		local pulseAlpha = (math.sin(os.clock() * pulseSpeed * math.pi * 2) + 1) * 0.5
		highlight.FillTransparency = minTransparency + ((maxTransparency - minTransparency) * pulseAlpha)
	end)
end

local function requestPickup(token: string)
	if pickupRequestInFlight then
		return
	end

	pickupRequestInFlight = true
	local success, result = pcall(function()
		return requestPickupRemote:InvokeServer(token)
	end)
	pickupRequestInFlight = false

	if success and type(result) == "table" and result.Success == true then
		cleanupPreview()
	end
end

local function showPreview(state)
	local token = state.Token
	local itemName = state.ItemName
	local mutation = state.Mutation or "Normal"
	local rarity = state.Rarity or "Legendary"
	local level = math.max(1, math.floor(tonumber(state.Level) or 1))

	cleanupPreview()

	local model, promptPart = buildPreviewModel(itemName, mutation, rarity, level)
	if not model or not promptPart then
		return
	end

	local previewCFrame = resolvePreviewCFrame(model)
	if not previewCFrame then
		model:Destroy()
		return
	end

	model:PivotTo(previewCFrame)
	model.Parent = Workspace
	CollectionService:AddTag(model, "Rotate")

	setupPreviewInfoGui(model, promptPart, itemName, mutation, rarity, level)
	setupPulsingHighlight(model)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JoinGiftPrompt"
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = itemName
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = math.max(1, tonumber(JoinGiftBrainrotConfiguration.PreviewMaxActivationDistance) or 12)
	prompt.Parent = promptPart

	activeModel = model
	activePrompt = prompt
	activeToken = token
	activePromptConnection = prompt.Triggered:Connect(function()
		if activeToken == token then
			requestPickup(token)
		end
	end)

	markPreviewShownRemote:FireServer(token, previewCFrame.Position)
end

local function requestAndMaybeShowPreview(applyJoinDelay: boolean)
	refreshNonce += 1
	local nonce = refreshNonce

	task.spawn(function()
		while refreshNonce == nonce and player.Parent do
			if isClientReadyForPreview() then
				break
			end
			task.wait(0.1)
		end

		if refreshNonce ~= nonce or not player.Parent then
			return
		end

		if applyJoinDelay then
			local deadline = os.clock() + math.max(0, tonumber(JoinGiftBrainrotConfiguration.PreviewDelaySeconds) or 0)
			while refreshNonce == nonce and player.Parent and os.clock() < deadline do
				if not isClientReadyForPreview() then
					return
				end
				task.wait(0.05)
			end
		end

		if refreshNonce ~= nonce or not player.Parent then
			return
		end

		local success, state = pcall(function()
			return getStateRemote:InvokeServer()
		end)
		if not success or refreshNonce ~= nonce then
			return
		end

		if type(state) ~= "table" or type(state.Token) ~= "string" then
			cleanupPreview()
			return
		end

		if activeModel and activeToken == state.Token then
			return
		end

		showPreview(state)
	end)
end

stateUpdatedRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	local status = payload.status
	local token = payload.token
	if status == "claimed" or status == "cancelled" then
		if type(token) == "string" and activeToken ~= nil and token ~= activeToken then
			return
		end
		cleanupPreview()
		return
	end

	if status == "rearm" then
		cleanupPreview()
		requestAndMaybeShowPreview(false)
	end
end)

player.CharacterRemoving:Connect(function()
	cleanupPreview()
	refreshNonce += 1
end)

player.CharacterAdded:Connect(function()
	cleanupPreview()
	requestAndMaybeShowPreview(true)
end)

task.defer(function()
	requestAndMaybeShowPreview(true)
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	if activePrompt and prompt == activePrompt and activePrompt.Parent == nil then
		activePrompt = nil
	end
end)
