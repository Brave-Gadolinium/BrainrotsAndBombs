--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer

local MARKER_NAME = "BaseOwnerMarker"
local THUMBNAIL_TYPE = Enum.ThumbnailType.HeadShot
local THUMBNAIL_SIZE = Enum.ThumbnailSize.Size100x100

type MarkerRecord = {
	Billboard: BillboardGui?,
	Label: TextLabel?,
	Image: ImageLabel?,
	Connections: {RBXScriptConnection},
	ThumbnailUserId: number?,
}

local recordsByPlot: {[Model]: MarkerRecord} = {}
local thumbnailCache: {[number]: string} = {}

local function isPlotModel(instance: Instance): boolean
	return instance:IsA("Model") and string.match(instance.Name, "^Plot_.+") ~= nil
end

local function findPlayerByName(playerName: string?): Player?
	if type(playerName) ~= "string" or playerName == "" then
		return nil
	end

	return Players:FindFirstChild(playerName) :: Player?
end

local function resolveOwnerInfo(plot: Model): (number?, string?, string?)
	local ownerUserId = tonumber(plot:GetAttribute("OwnerUserId"))
	local ownerNameAttribute = plot:GetAttribute("OwnerName")
	local ownerDisplayAttribute = plot:GetAttribute("OwnerDisplayName")

	local ownerName = if type(ownerNameAttribute) == "string" and ownerNameAttribute ~= "" then ownerNameAttribute else nil
	local ownerDisplayName = if type(ownerDisplayAttribute) == "string" and ownerDisplayAttribute ~= "" then ownerDisplayAttribute else nil

	if not ownerName then
		ownerName = string.match(plot.Name, "^Plot_(.+)$")
	end

	local ownerPlayer = findPlayerByName(ownerName)
	if ownerPlayer then
		ownerUserId = ownerUserId or ownerPlayer.UserId
		ownerDisplayName = ownerDisplayName or ownerPlayer.DisplayName
	end

	return ownerUserId, ownerName, ownerDisplayName
end

local function getMarkerText(plot: Model): string
	local ownerUserId, ownerName, ownerDisplayName = resolveOwnerInfo(plot)

	if ownerUserId == localPlayer.UserId or ownerName == localPlayer.Name then
		return "Your base"
	end

	return ownerDisplayName or ownerName or "Player base"
end

local function getSpawnPart(plot: Model): BasePart?
	local spawnPart = plot:FindFirstChild("Spawn", true)
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart
	end

	return nil
end

local function buildMarkerGui(spawnPart: BasePart): (BillboardGui, TextLabel, ImageLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = MARKER_NAME
	billboard.Adornee = spawnPart
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 1000
	billboard.Size = UDim2.fromOffset(170, 104)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 6.5, 0)

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = billboard

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = root

	local avatarFrame = Instance.new("Frame")
	avatarFrame.Name = "AvatarFrame"
	avatarFrame.Size = UDim2.fromOffset(48, 48)
	avatarFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	avatarFrame.BackgroundTransparency = 0.15
	avatarFrame.BorderSizePixel = 0
	avatarFrame.Parent = root

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0)
	avatarCorner.Parent = avatarFrame

	local avatarStroke = Instance.new("UIStroke")
	avatarStroke.Thickness = 2
	avatarStroke.Color = Color3.fromRGB(255, 255, 255)
	avatarStroke.Transparency = 0.15
	avatarStroke.Parent = avatarFrame

	local avatarImage = Instance.new("ImageLabel")
	avatarImage.Name = "Avatar"
	avatarImage.Size = UDim2.new(1, -6, 1, -6)
	avatarImage.Position = UDim2.fromOffset(3, 3)
	avatarImage.BackgroundTransparency = 1
	avatarImage.ScaleType = Enum.ScaleType.Crop
	avatarImage.Parent = avatarFrame

	local avatarImageCorner = Instance.new("UICorner")
	avatarImageCorner.CornerRadius = UDim.new(1, 0)
	avatarImageCorner.Parent = avatarImage

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 0, 34)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.TextSize = 18
	label.TextWrapped = true
	label.Parent = root

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 18
	textConstraint.MinTextSize = 12
	textConstraint.Parent = label

	return billboard, label, avatarImage
end

local function cleanupPlot(plot: Model)
	local record = recordsByPlot[plot]
	if not record then
		return
	end

	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end

	if record.Billboard then
		record.Billboard:Destroy()
	end

	recordsByPlot[plot] = nil
end

local function updateThumbnail(plot: Model, record: MarkerRecord, ownerUserId: number?)
	record.ThumbnailUserId = ownerUserId

	if not record.Image then
		return
	end

	if not ownerUserId then
		record.Image.Image = ""
		return
	end

	local cachedThumbnail = thumbnailCache[ownerUserId]
	if cachedThumbnail then
		record.Image.Image = cachedThumbnail
		return
	end

	record.Image.Image = ""

	task.spawn(function()
		local ok, content = pcall(function()
			local image, _ready = Players:GetUserThumbnailAsync(ownerUserId, THUMBNAIL_TYPE, THUMBNAIL_SIZE)
			return image
		end)

		if not ok or type(content) ~= "string" or content == "" then
			return
		end

		thumbnailCache[ownerUserId] = content

		local currentRecord = recordsByPlot[plot]
		if not currentRecord or currentRecord ~= record or currentRecord.ThumbnailUserId ~= ownerUserId then
			return
		end

		if currentRecord.Image then
			currentRecord.Image.Image = content
		end
	end)
end

local function refreshPlotMarker(plot: Model)
	local record = recordsByPlot[plot]
	if not record then
		return
	end

	if not plot:IsDescendantOf(Workspace) then
		cleanupPlot(plot)
		return
	end

	local spawnPart = getSpawnPart(plot)
	if not spawnPart then
		if record.Billboard then
			record.Billboard:Destroy()
			record.Billboard = nil
			record.Label = nil
			record.Image = nil
			record.ThumbnailUserId = nil
		end
		return
	end

	if not record.Billboard or not record.Billboard.Parent then
		local billboard, label, image = buildMarkerGui(spawnPart)
		record.Billboard = billboard
		record.Label = label
		record.Image = image
		billboard.Parent = spawnPart
	else
		record.Billboard.Adornee = spawnPart
		if record.Billboard.Parent ~= spawnPart then
			record.Billboard.Parent = spawnPart
		end
	end

	local ownerUserId = select(1, resolveOwnerInfo(plot))
	local isOwnPlot = ownerUserId == localPlayer.UserId

	if record.Label then
		record.Label.Text = getMarkerText(plot)
		record.Label.TextColor3 = if isOwnPlot then Color3.fromRGB(255, 240, 148) else Color3.fromRGB(255, 255, 255)
	end

	updateThumbnail(plot, record, ownerUserId)
end

local function watchPlot(plot: Model)
	if recordsByPlot[plot] then
		refreshPlotMarker(plot)
		return
	end

	local record: MarkerRecord = {
		Billboard = nil,
		Label = nil,
		Image = nil,
		Connections = {},
		ThumbnailUserId = nil,
	}

	recordsByPlot[plot] = record

	for _, attributeName in ipairs({"OwnerUserId", "OwnerName", "OwnerDisplayName"}) do
		table.insert(record.Connections, plot:GetAttributeChangedSignal(attributeName):Connect(function()
			refreshPlotMarker(plot)
		end))
	end

	table.insert(record.Connections, plot.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant.Name == "Spawn" then
			refreshPlotMarker(plot)
		end
	end))

	table.insert(record.Connections, plot.AncestryChanged:Connect(function()
		if not plot:IsDescendantOf(Workspace) then
			cleanupPlot(plot)
		end
	end))

	refreshPlotMarker(plot)
end

for _, child in ipairs(Workspace:GetChildren()) do
	if isPlotModel(child) then
		watchPlot(child :: Model)
	end
end

Workspace.ChildAdded:Connect(function(child)
	if isPlotModel(child) then
		watchPlot(child :: Model)
	end
end)

Workspace.ChildRemoved:Connect(function(child)
	if child:IsA("Model") then
		cleanupPlot(child)
	end
end)
