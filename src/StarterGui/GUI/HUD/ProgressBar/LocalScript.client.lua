--!strict
-- LOCATION: StarterPlayerScripts/HeightBarController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BrainrotEventConfiguration = require(ReplicatedStorage.Modules.BrainrotEventConfiguration)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local hud = playerGui:WaitForChild("GUI"):WaitForChild("HUD")
local map = Workspace:WaitForChild("Mines")

type WallMarker = {
	y: number,
	color: Color3,
	requiredPower: number,
	textureImage: string,
	textureTransparency: number,
}

type Segment = {
	y0: number,
	y1: number,
	color: Color3,
	textureImage: string,
	textureTransparency: number,
}

local ROOT_WIDTH = 96
local ROOT_HEIGHT_SCALE = 0.78
local BAR_WIDTH = 28
local EDGE_PADDING = 25
local DIVIDER_THICKNESS = 2

local MARKER_SIZE = 36
local MARKER_STACK_STEP = 10
local MARKER_BUCKETS = 56
local MARKER_GAP = 8

local DEFAULT_WALL_TEXTURE = "rbxassetid://0"
local DEFAULT_WALL_TEXTURE_TRANSPARENCY = 0.7
local BAR_BG_COLOR = Color3.fromRGB(20, 20, 20)
local SEGMENT_TEXTURE_TILE_SIZE = 24

local REBUILD_INTERVAL = 2
local EVENT_MARKER_SWAY_DEGREES = 7
local EVENT_MARKER_SWAY_OFFSET = 4
local EVENT_MARKER_BOB_OFFSET = 2
local EVENT_MARKER_SEARCH_INTERVAL = 0.35
local EVENT_MARKER_PULSE_MIN_DELAY = 2.4
local EVENT_MARKER_PULSE_MAX_DELAY = 4.8

local rootFrame: Frame
local markerLayer: Frame
local minHeight = 0
local maxHeight = 100
local totalRange = 100

local markerByPlayer: {[Player]: Frame} = {}
local workspaceAttributes = BrainrotEventConfiguration.WorkspaceAttributes
local currentEventToken: string? = nil
local eventMarker: Frame? = nil
local eventMarkerScale: UIScale? = nil
local eventMarkerIcon: ImageLabel? = nil
local eventMarkerPulseLoopId = 0
local cachedEventWorldItem: Model? = nil
local nextEventWorldSearchAt = 0

local function roundToTenth(value: number): number
	return math.floor(value * 10 + 0.5) / 10
end

local function parseRequirementPower(text: string): number
	local numberText = string.match(text, "%d+")
	if not numberText then
		return 0
	end

	return tonumber(numberText) or 0
end

local function normalizeTextureId(raw: string): string
	if raw == "" then
		return ""
	end

	local id = string.match(raw, "%d+")
	if id then
		return "rbxassetid://" .. id
	end

	return raw
end

local function getWallTextureData(part: BasePart): (string, number)
	local fallbackImage = DEFAULT_WALL_TEXTURE
	local fallbackTransparency = DEFAULT_WALL_TEXTURE_TRANSPARENCY

	local firstTextureImage = ""
	local firstTextureTransparency = fallbackTransparency

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Texture") then
			local image = normalizeTextureId(child.Texture)
			if image ~= "" then
				if child.Face == Enum.NormalId.Top then
					return image, math.clamp(child.Transparency, 0, 1)
				end

				if firstTextureImage == "" then
					firstTextureImage = image
					firstTextureTransparency = math.clamp(child.Transparency, 0, 1)
				end
			end
		end
	end

	if firstTextureImage ~= "" then
		return firstTextureImage, firstTextureTransparency
	end

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Decal") then
			local image = normalizeTextureId(child.Texture)
			if image ~= "" then
				return image, math.clamp(child.Transparency, 0, 1)
			end
		end
	end

	return fallbackImage, fallbackTransparency
end

local function collectWallMarkers(): {WallMarker}
	local markers: {WallMarker} = {}
	local uniqueByY: {[number]: boolean} = {}

	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("SurfaceGui") then
			local title = desc:FindFirstChild("TitleLabel")
			if title and title:IsA("TextLabel") and title.Text == "Jump" then
				local parentPart = desc.Parent
				if parentPart and parentPart:IsA("BasePart") then
					local roundedY = roundToTenth(parentPart.Position.Y)
					if not uniqueByY[roundedY] then
						uniqueByY[roundedY] = true

						local reqLabel = desc:FindFirstChild("JetpackRequirement")
						local reqText = (reqLabel and reqLabel:IsA("TextLabel")) and reqLabel.Text or ""
						local textureImage, textureTransparency = getWallTextureData(parentPart)

						table.insert(markers, {
							y = parentPart.Position.Y,
							color = parentPart.Color,
							requiredPower = parseRequirementPower(reqText),
							textureImage = textureImage,
							textureTransparency = textureTransparency,
						})
					end
				end
			end
		end
	end

	table.sort(markers, function(a, b)
		return a.y < b.y
	end)

	return markers
end

local function collectFloorHeights(): {number}
	local itemSpawns = Workspace:FindFirstChild("ItemSpawns")
	if not itemSpawns then
		return {}
	end

	local unique: {[number]: boolean} = {}
	local heights: {number} = {}

	for _, spawn in ipairs(itemSpawns:GetChildren()) do
		if spawn:IsA("BasePart") then
			local y = roundToTenth(spawn.Position.Y)
			if not unique[y] then
				unique[y] = true
				table.insert(heights, spawn.Position.Y)
			end
		end
	end

	table.sort(heights, function(a, b)
		return a < b
	end)

	return heights
end

local function getBaseRangeFallback(): (number, number)
	local minY = math.huge
	local maxY = -math.huge

	for _, desc in ipairs(map:GetDescendants()) do
		if desc:IsA("BasePart") then --and desc.Name == "Base" then
			local y0 = desc.Position.Y - desc.Size.Y * 0.5
			local y1 = desc.Position.Y + desc.Size.Y * 0.5
			if y0 < minY then
				minY = y0
			end
			if y1 > maxY then
				maxY = y1
			end
		end
	end

	if minY == math.huge or maxY == -math.huge or maxY <= minY then
		return 0, 100
	end

	return minY, maxY
end

local function createSegment(y0: number, y1: number, wall: WallMarker): Segment
	return {
		y0 = y0,
		y1 = y1,
		color = wall.color,
		textureImage = wall.textureImage,
		textureTransparency = wall.textureTransparency,
	}
end

local function buildSegmentsFromData(walls: {WallMarker}, floorHeights: {number}): ({Segment}, {number}, number, number)
	local segments: {Segment} = {}
	local dividers: {number} = {}

	if #floorHeights >= 2 and #walls > 0 then
		local yMin = floorHeights[1]
		local yMax = floorHeights[#floorHeights]

		for i = 1, #floorHeights - 1 do
			local y0 = floorHeights[i]
			local y1 = floorHeights[i + 1]
			local wall = walls[math.min(i, #walls)]

			if y1 > y0 then
				table.insert(segments, createSegment(y0, y1, wall))
			end

			if i < (#floorHeights - 1) then
				table.insert(dividers, y1)
			end
		end

		return segments, dividers, yMin, yMax
	end

	local yMin, yMax = getBaseRangeFallback()

	if #walls == 0 then
		table.insert(segments, {
			y0 = yMin,
			y1 = yMax,
			color = Color3.fromRGB(80, 170, 255),
			textureImage = DEFAULT_WALL_TEXTURE,
			textureTransparency = DEFAULT_WALL_TEXTURE_TRANSPARENCY,
		})
		return segments, dividers, yMin, yMax
	end

	local cursor = yMin
	for i, wall in ipairs(walls) do
		local markerY = math.clamp(wall.y, yMin, yMax)
		if markerY > cursor then
			table.insert(segments, createSegment(cursor, markerY, wall))
		end

		if i < #walls then
			table.insert(dividers, markerY)
		end

		cursor = markerY
	end

	if yMax > cursor then
		table.insert(segments, createSegment(cursor, yMax, walls[#walls]))
	end

	if #segments == 0 then
		table.insert(segments, createSegment(yMin, yMax, walls[#walls]))
	end

	return segments, dividers, yMin, yMax
end

local function clearChildren(instance: Instance)
	for _, child in ipairs(instance:GetChildren()) do
		child:Destroy()
	end
end

local function buildBarUI()
	-- local existing = hud:FindFirstChild("HeightBar")
	-- if existing then
	-- 	existing:Destroy()
	-- end

	rootFrame = hud:FindFirstChild("ProgressBar"):FindFirstChild("Levels")
	--rootFrame.Name = "HeightBar"
	--rootFrame.AnchorPoint = Vector2.new(1, 0.5)
	--rootFrame.Position = UDim2.new(1, -EDGE_PADDING, 0.5, 0)
	--rootFrame.Size = UDim2.new(0, ROOT_WIDTH, ROOT_HEIGHT_SCALE, 0)
	--rootFrame.BackgroundTransparency = 1
	--rootFrame.ZIndex = 2
	--rootFrame.Parent = hud

	--local bar = rootFrame:FindFirstChild("Bar")
	--bar.Name = "Bar"
	--bar.AnchorPoint = Vector2.new(1, 0.5)
	--bar.Position = UDim2.new(1, 0, 0.5, 0)
	--bar.Size = UDim2.new(0, BAR_WIDTH, 1, 0)
	--bar.BackgroundColor3 = BAR_BG_COLOR
	--bar.BorderSizePixel = 0
	--bar.ZIndex = 3
	--bar.Parent = rootFrame

	-- local barCorner = Instance.new("UICorner")
	-- barCorner.CornerRadius = UDim.new(0, 8)
	-- barCorner.Parent = bar

	-- local barStroke = Instance.new("UIStroke")
	-- barStroke.Thickness = 3
	-- barStroke.Color = Color3.fromRGB(0, 0, 0)
	-- barStroke.Parent = bar

	--local segmentContainer = Instance.new("Frame")
	--segmentContainer.Name = "Segments"
	--segmentContainer.Size = UDim2.fromScale(1, 1)
	--segmentContainer.BackgroundTransparency = 1
	--segmentContainer.ClipsDescendants = true
	--segmentContainer.ZIndex = 3
	--segmentContainer.Parent = bar

	--local segmentCorner = Instance.new("UICorner")
	--segmentCorner.CornerRadius = UDim.new(0, 8)
	--segmentCorner.Parent = segmentContainer

	local walls = collectWallMarkers()
	local floorHeights = collectFloorHeights()
	local segments, dividers, yMin, yMax = buildSegmentsFromData(walls, floorHeights)

	minHeight = yMin
	maxHeight = yMax
	totalRange = math.max(1, maxHeight - minHeight)

	--clearChildren(segmentContainer)

	--for _, segment in ipairs(segments) do
	--	local alpha0 = math.clamp((segment.y0 - minHeight) / totalRange, 0, 1)
	--	local alpha1 = math.clamp((segment.y1 - minHeight) / totalRange, 0, 1)
	--	local h = alpha1 - alpha0

	--	if h > 0.001 then
	--		local part = Instance.new("Frame")
	--		part.Size = UDim2.new(1, 0, h, 0)
	--		part.Position = UDim2.new(0, 0, 1 - alpha1, 0)
	--		part.BackgroundColor3 = segment.color
	--		part.BorderSizePixel = 0
	--		part.ZIndex = 3
	--		part.Parent = segmentContainer

	--		local texture = Instance.new("ImageLabel")
	--		texture.Name = "Texture"
	--		texture.Size = UDim2.fromScale(1, 1)
	--		texture.BackgroundTransparency = 1
	--		texture.Image = segment.textureImage
	--		texture.ImageColor3 = Color3.new(1, 1, 1)
	--		texture.ImageTransparency = math.clamp(segment.textureTransparency, 0, 1)
	--		texture.ScaleType = Enum.ScaleType.Tile
	--		texture.TileSize = UDim2.fromOffset(SEGMENT_TEXTURE_TILE_SIZE, SEGMENT_TEXTURE_TILE_SIZE)
	--		texture.ZIndex = 3
	--		texture.Parent = part
	--	end
	--end

	--for _, dividerY in ipairs(dividers) do
	--	local alpha = math.clamp((dividerY - minHeight) / totalRange, 0, 1)

	--	local divider = Instance.new("Frame")
	--	divider.AnchorPoint = Vector2.new(0.5, 0.5)
	--	divider.Position = UDim2.new(0.5, 0, 1 - alpha, 0)
	--	divider.Size = UDim2.new(1, -4, 0, DIVIDER_THICKNESS)
	--	divider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	--	divider.BackgroundTransparency = 0.1
	--	divider.BorderSizePixel = 0
	--	divider.ZIndex = 3
	--	divider.Parent = segmentContainer
	--end

	markerLayer = hud:FindFirstChild("ProgressBar"):FindFirstChild("Markers")
	-- markerLayer.Name = "Markers"
	-- markerLayer.BackgroundTransparency = 1
	-- markerLayer.Size = UDim2.fromScale(1, 1)
	-- markerLayer.ClipsDescendants = false
	-- markerLayer.ZIndex = 3
	-- markerLayer.Parent = rootFrame
end

local function getThumbnail(userId: number): string
	local ok, content = pcall(function()
		local image, _ready = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		return image
	end)

	if ok and content then
		return content
	end

	return ""
end

local function createPlayerMarker(player: Player): Frame
	local marker = hud:FindFirstChild("ProgressBar"):FindFirstChild("Markers"):FindFirstChild("PlayerMark"):Clone()
	--print(marker)
	marker.Visible = true
	marker.Parent = hud:FindFirstChild("ProgressBar"):FindFirstChild("Markers")
	
	marker.Name = tostring(player.UserId)
	
	--marker.Size = UDim2.fromOffset(MARKER_SIZE, MARKER_SIZE)
	--marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.BackgroundColor3 = if player == localPlayer then Color3.fromRGB(186, 255, 72) else Color3.fromRGB(255, 255, 255)
	--marker.BorderSizePixel = 0
	--marker.ZIndex = 3
	--marker.Parent = markerLayer

	--local markerCorner = Instance.new("UICorner")
	--markerCorner.CornerRadius = UDim.new(1, 0)
	--markerCorner.Parent = marker

	--local markerStroke = Instance.new("UIStroke")
	--markerStroke.Thickness = 3
	--markerStroke.Color = Color3.fromRGB(0, 0, 0)
	--markerStroke.Parent = marker

	local icon = marker:FindFirstChild('PlayerImage')
	icon.Name = "Icon"
	--icon.AnchorPoint = Vector2.new(0.5, 0.5)
	--icon.Position = UDim2.fromScale(0.5, 0.5)
	--icon.Size = UDim2.new(1, -8, 1, -8)
	--icon.BackgroundTransparency = 1
	--icon.ScaleType = Enum.ScaleType.Crop
	icon.ZIndex = 3
	
	icon.Parent = marker

	--local iconCorner = Instance.new("UICorner")
	--iconCorner.CornerRadius = UDim.new(1, 0)
	--iconCorner.Parent = icon

	task.spawn(function()
		icon.Image = getThumbnail(player.UserId)
	end)


	return marker
end

local function ensureMarker(player: Player): Frame
	local marker = markerByPlayer[player]
	if marker and marker.Parent then
		return marker
	end

	local newMarker = createPlayerMarker(player)
	markerByPlayer[player] = newMarker
	return newMarker
end

local function removeMarker(player: Player)
	local marker = markerByPlayer[player]
	if marker then
		marker:Destroy()
		markerByPlayer[player] = nil
	end
end

local function getEventMarkerBaseX(): number
	local barCenterX = rootFrame.AbsoluteSize.X - (BAR_WIDTH * 0.5)
	return barCenterX + MARKER_GAP + (MARKER_SIZE * 0.5)
end

local function destroyEventMarker()
	eventMarkerPulseLoopId += 1
	if eventMarker then
		eventMarker:Destroy()
		eventMarker = nil
	end
	eventMarkerScale = nil
	eventMarkerIcon = nil
	cachedEventWorldItem = nil
	nextEventWorldSearchAt = 0
end

local function startEventMarkerPulseLoop(marker: Frame, scale: UIScale)
	eventMarkerPulseLoopId += 1
	local pulseLoopId = eventMarkerPulseLoopId

	task.spawn(function()
		while eventMarker == marker and eventMarkerScale == scale and pulseLoopId == eventMarkerPulseLoopId and marker.Parent do
			task.wait(math.random(
				math.floor(EVENT_MARKER_PULSE_MIN_DELAY * 10),
				math.floor(EVENT_MARKER_PULSE_MAX_DELAY * 10)
			) / 10)

			if pulseLoopId ~= eventMarkerPulseLoopId or not marker.Parent or eventMarker ~= marker or eventMarkerScale ~= scale then
				break
			end

			local growTween = TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1.14})
			local shrinkTween = TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1})
			growTween:Play()
			growTween.Completed:Wait()

			if pulseLoopId ~= eventMarkerPulseLoopId or not marker.Parent then
				break
			end

			shrinkTween:Play()
			shrinkTween.Completed:Wait()
		end
	end)
end

local function ensureEventMarker(): Frame?
	if eventMarker and eventMarker.Parent then
		return eventMarker
	end

	local progressBar = hud:FindFirstChild("ProgressBar")
	local markersContainer = progressBar and progressBar:FindFirstChild("Markers")
	local dedicatedTemplate = markersContainer and markersContainer:FindFirstChild("EventBrainrotMarkTemplate")
	local markerTemplate = if dedicatedTemplate and dedicatedTemplate:IsA("Frame")
		then dedicatedTemplate
		else markersContainer and markersContainer:FindFirstChild("PlayerMark")
	if not markersContainer or not markersContainer:IsA("Frame") or not markerTemplate or not markerTemplate:IsA("Frame") then
		return nil
	end

	local marker = markerTemplate:Clone()
	marker.Name = "EventBrainrotMark"
	marker.Visible = false
	marker.BackgroundColor3 = Color3.fromRGB(255, 176, 66)
	marker.ZIndex = 4

	if markerTemplate.Name ~= "EventBrainrotMarkTemplate" then
		for _, descendant in ipairs(marker:GetDescendants()) do
			if descendant:IsA("UIStroke") then
				descendant:Destroy()
			elseif descendant:IsA("GuiObject") and string.find(string.lower(descendant.Name), "arrow", 1, true) then
				descendant:Destroy()
			end
		end
	end

	local icon = marker:FindFirstChild("Icon", true)
	if not icon or not icon:IsA("ImageLabel") then
		icon = marker:FindFirstChild("PlayerImage", true)
	end
	if not icon or not icon:IsA("ImageLabel") then
		icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Parent = marker
	end

	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = ""
	icon.ImageTransparency = 0
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 5

	if markerTemplate.Name ~= "EventBrainrotMarkTemplate" then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromScale(0.94, 0.94)
	end

	eventMarkerIcon = icon

	marker.Parent = markersContainer

	local scale = marker:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = marker
	end
	scale.Scale = 1

	eventMarker = marker
	eventMarkerScale = scale
	startEventMarkerPulseLoop(marker, scale)
	return marker
end

local function findActiveEventWorldItem(token: string): Model?
	if cachedEventWorldItem and cachedEventWorldItem.Parent and cachedEventWorldItem:GetAttribute("EventBrainrotToken") == token then
		return cachedEventWorldItem
	end

	local now = tick()
	if now < nextEventWorldSearchAt then
		return nil
	end

	nextEventWorldSearchAt = now + EVENT_MARKER_SEARCH_INTERVAL

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant.Name == "SpawnedItem"
			and descendant:GetAttribute("EventBrainrotToken") == token
		then
			cachedEventWorldItem = descendant
			return descendant
		end
	end

	cachedEventWorldItem = nil
	return nil
end

local function updateEventMarkerAppearance()
	if not currentEventToken then
		return
	end

	local marker = ensureEventMarker()
	local icon = eventMarkerIcon
	if not marker or not icon then
		return
	end

	local itemName = Workspace:GetAttribute(workspaceAttributes.ItemName)
	local itemData = type(itemName) == "string" and ItemConfigurations.GetItemData(itemName) or nil
	icon.Image = itemData and itemData.ImageId or ""

	local rarity = Workspace:GetAttribute(workspaceAttributes.Rarity)
	local rarityConfig = type(rarity) == "string" and (RarityConfigurations[rarity] :: any) or nil
	if rarityConfig then
		marker.BackgroundColor3 = rarityConfig.TextColor or marker.BackgroundColor3
	end
end

local function refreshEventMarkerState()
	local active = Workspace:GetAttribute(workspaceAttributes.Active) == true
	local tokenAttribute = Workspace:GetAttribute(workspaceAttributes.Token)
	local token = if active and type(tokenAttribute) == "string" and tokenAttribute ~= "" then tokenAttribute else nil

	if currentEventToken ~= token then
		currentEventToken = token
		cachedEventWorldItem = nil
		nextEventWorldSearchAt = 0

		if not currentEventToken then
			destroyEventMarker()
			return
		end

		destroyEventMarker()
	end

	if not currentEventToken then
		return
	end

	updateEventMarkerAppearance()
end

local function getPlayerY(player: Player): number?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return root.Position.Y
end

local function getMarkerBaseX(): number
	local barLeft = rootFrame.AbsoluteSize.X - BAR_WIDTH
	return barLeft - MARKER_GAP - (MARKER_SIZE * 0.5)
end

local function applyRightEdgeLayout()
	rootFrame.Position = UDim2.new(1, -EDGE_PADDING, 0.5, 0)
end

buildBarUI()
refreshEventMarkerState()

Players.PlayerAdded:Connect(function(player)
	ensureMarker(player)
end)

Players.PlayerRemoving:Connect(function(player)
	removeMarker(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	ensureMarker(player)
end

for _, attributeName in pairs(workspaceAttributes) do
	Workspace:GetAttributeChangedSignal(attributeName):Connect(refreshEventMarkerState)
end

local rebuildTimer = 0

RunService.Heartbeat:Connect(function(dt)
	rebuildTimer += dt
	if rebuildTimer >= REBUILD_INTERVAL then
		rebuildTimer = 0
		buildBarUI()
		for _, player in ipairs(Players:GetPlayers()) do
			ensureMarker(player)
		end
	end

	--applyRightEdgeLayout()

	local stackByBucket: {[number]: number} = {}
	local markerBaseX = getMarkerBaseX()

	for _, player in ipairs(Players:GetPlayers()) do
		local marker = ensureMarker(player)
		local y = getPlayerY(player)

		if y == nil then
			marker.Visible = false
			continue
		end

		local alpha = math.clamp((y - minHeight) / totalRange, 0, 1)
		local bucket = math.floor(alpha * MARKER_BUCKETS + 0.5)
		local stack = stackByBucket[bucket] or 0
		stackByBucket[bucket] = stack + 1

		local x = markerBaseX - stack * MARKER_STACK_STEP
		marker.Position = UDim2.new(0, x, 1 - alpha, 0)
		marker.Visible = true
	end

	if currentEventToken then
		local marker = ensureEventMarker()
		if marker then
			local carrierUserId = tonumber(Workspace:GetAttribute(workspaceAttributes.CarrierUserId))
			local targetY: number? = nil

			if carrierUserId then
				local carrierPlayer = Players:GetPlayerByUserId(carrierUserId)
				if carrierPlayer then
					targetY = getPlayerY(carrierPlayer)
				end
			end

			if targetY == nil then
				local worldItem = findActiveEventWorldItem(currentEventToken)
				if worldItem and worldItem.Parent then
					targetY = worldItem:GetPivot().Position.Y
				end
			end

			if targetY == nil then
				marker.Visible = false
			else
				local alpha = math.clamp((targetY - minHeight) / totalRange, 0, 1)
				local t = Workspace:GetServerTimeNow()
				local swayOffset = math.sin(t * 2.2) * EVENT_MARKER_SWAY_OFFSET
				local bobOffset = math.cos(t * 1.6) * EVENT_MARKER_BOB_OFFSET
				local baseX = getEventMarkerBaseX()

				marker.Position = UDim2.new(0, baseX + swayOffset, 1 - alpha, bobOffset)
				marker.Rotation = 0
				marker.Visible = true

				if eventMarkerIcon then
					eventMarkerIcon.Rotation = math.sin(t * 2.5) * EVENT_MARKER_SWAY_DEGREES
				end
			end
		end
	end
end)
