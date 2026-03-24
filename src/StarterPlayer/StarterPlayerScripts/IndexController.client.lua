--!strict
-- LOCATION: StarterPlayerScripts/IndexController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local MutationConfigurations = require(ReplicatedStorage.Modules.MutationConfigurations)
local RarityConfigurations = require(ReplicatedStorage.Modules.RarityConfigurations)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Assets
local Templates = ReplicatedStorage:WaitForChild("Templates")
local IndexTemplate = Templates:WaitForChild("IndexTemplate")
local Events = ReplicatedStorage:WaitForChild("Events")

-- UI References
local mainGui = playerGui:WaitForChild("GUI")
local frames = mainGui:WaitForChild("Frames")
local indexFrame = frames:WaitForChild("Index")
local scrolling = indexFrame:WaitForChild("Scrolling")
local buttonsFolder = indexFrame:WaitForChild("Buttons")

-- State
local currentMutation = "Normal"
local discoveredCache = {}

-- [ DATA FETCHING ]
local GetIndexDataFunction = Events:WaitForChild("GetIndexData", 10)

-- [ HELPER: Apply Styling ]
-- Applies text color, stroke, and gradient based on configuration tables
local function applyStyle(label: TextLabel, config: any)
	if not config then return end
	if not label then return end

	-- 1. Text Color
	if config.TextColor then 
		label.TextColor3 = config.TextColor 
	end

	-- 2. Stroke
	local stroke = label:FindFirstChild("Stroke") or label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = config.StrokeColor or Color3.new(0,0,0)
		stroke.Enabled = true
	end

	-- 3. Gradient
	local gradient = label:FindFirstChild("Gradient") or label:FindFirstChildOfClass("UIGradient")
	if gradient then
		if config.GradientColor then
			gradient.Color = config.GradientColor
			gradient.Enabled = true
		else
			gradient.Enabled = false
		end
	end
end

-- [ HELPER: Render List ]
local function RenderList()
	-- 1. Clear Old Items
	for _, child in ipairs(scrolling:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	-- 2. Prepare Items
	local itemsToShow = {}
	for itemName, data in pairs(ItemConfigurations.Items) do
		table.insert(itemsToShow, {Name = itemName, Data = data})
	end

	-- 3. Sort Items (Income: Low -> High)
	table.sort(itemsToShow, function(a, b)
		local incomeA = a.Data.Income or 0
		local incomeB = b.Data.Income or 0

		if incomeA == incomeB then
			return a.Name < b.Name -- Alphabetical tie-breaker
		end
		return incomeA < incomeB -- Lowest Income first
	end)

	-- 4. Populate
	for _, entry in ipairs(itemsToShow) do
		local itemName = entry.Name
		local itemData = entry.Data

		-- Key Format: "Normal_Gulf", "Neon_Supre", etc.
		local key = currentMutation .. "_" .. itemName 
		local isUnlocked = discoveredCache[key] == true

		local template = IndexTemplate:Clone()
		template.Name = itemName
		template.Parent = scrolling
		template.Visible = true

		-- A. Image Color Logic (Silhouette if locked)
		local imageLabel = template:FindFirstChild("Image") :: ImageLabel
		if imageLabel then
			imageLabel.Image = itemData.ImageId
			if isUnlocked then
				imageLabel.ImageColor3 = Color3.new(1, 1, 1) -- White (Full Color)
			else
				imageLabel.ImageColor3 = Color3.new(0, 0, 0) -- Black (Silhouette)
			end
		end

		-- B. Name Logic
		local nameLabel = template:FindFirstChild("Name") :: TextLabel
		if nameLabel then 
			nameLabel.Text = isUnlocked and itemName or "???"
		end

		-- C. Rarity Logic
		local rarityLabel = template:FindFirstChild("Rarity") :: TextLabel
		if rarityLabel then
			local rarityName = itemData.Rarity
			rarityLabel.Text = rarityName
			applyStyle(rarityLabel, RarityConfigurations[rarityName])
		end

		-- D. Mutation Logic (e.g. "Normal", "Neon")
		local mutationLabel = template:FindFirstChild("Mutation") :: TextLabel
		if mutationLabel then
			mutationLabel.Text = currentMutation
			applyStyle(mutationLabel, MutationConfigurations[currentMutation])
		end
	end
end

-- [ CORE LOGIC ]
-- Handles fetching data from server and calling RenderList
local function UpdateIndexUI(forceFetch: boolean)
	-- 1. Render immediately with what we have (even if cache is empty initially)
	RenderList()

	-- 2. Fetch Data in background if needed
	if GetIndexDataFunction and (forceFetch or not next(discoveredCache)) then
		task.spawn(function()
			local success, data = pcall(function()
				return GetIndexDataFunction:InvokeServer()
			end)

			if success and data then
				discoveredCache = data
				RenderList() -- Re-render with valid data
			else
				warn("[IndexController] Failed to fetch data.")
			end
		end)
	end
end

-- [ BUTTON LOGIC ]
local function updateButtonVisuals()
	for _, btn in ipairs(buttonsFolder:GetChildren()) do
		if btn:IsA("GuiButton") then
			if btn.Name == currentMutation then
				btn.BackgroundColor3 = Color3.fromRGB(200, 200, 200) -- Selected (Light)
			else
				btn.BackgroundColor3 = Color3.fromRGB(50, 50, 50) -- Unselected (Dark)
			end
		end
	end
end

local function setupTabButtons()
	for _, btn in ipairs(buttonsFolder:GetChildren()) do
		if btn:IsA("GuiButton") then
			btn.MouseButton1Click:Connect(function()
				currentMutation = btn.Name
				updateButtonVisuals()
				RenderList() -- Re-render list for new mutation
			end)
		end
	end
	updateButtonVisuals() -- Set initial visuals
end

-- [ INIT ]
setupTabButtons()

local refreshEvent = Events:FindFirstChild("RefreshIndex")
if refreshEvent then
	refreshEvent.OnClientEvent:Connect(function()
		UpdateIndexUI(true)
	end)
end

-- Initial Load
UpdateIndexUI(true)

print("[IndexController] Loaded & Sorted by Income")