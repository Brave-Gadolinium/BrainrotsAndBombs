--!strict
-- LOCATION: ServerScriptService/Controllers/LeaderboardController

-- Services
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Modules
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

-- Controller References
local PlayerController: any

-- Constants
local LEADERBOARD_REFRESH_INTERVAL = 60
local SAVE_INTERVAL = 60
local TOP_N_PLAYERS = 50 
local LEADERBOARDS_FOLDER_NAME = "Leaderboards" 
local ENTRY_TEMPLATE_NAME = "LeaderboardEntry"

-- Configuration
local LEADERBOARDS_CONFIG = {
	Money = {
		StoreName = "GlobalMoney_v1",       
		ModelName = "MoneyLeaderboard",     
		DataKey = "Money",                  
		ScoreFormatter = function(score) return "$" .. NumberFormatter.Format(score) end
	},
	Time = {
		StoreName = "GlobalTime_v1",       
		ModelName = "TimeLeaderboard",     
		DataKey = "TimePlayed", -- Make sure this matches the stat saved in your PlayerController!
		ScoreFormatter = function(score) 
			-- Assumes TimePlayed is tracked in seconds. Formats to "Xh Ym"
			local hours = math.floor(score / 3600)
			local minutes = math.floor((score % 3600) / 60)
			if hours > 0 then
				return hours .. "h " .. minutes .. "m"
			else
				return minutes .. "m"
			end
		end
	},
	Rebirths = {                            
		StoreName = "GlobalRebirths_v1",
		ModelName = "RebirthLeaderboard",
		DataKey = "Rebirths",
		ScoreFormatter = function(score) return NumberFormatter.Format(score) .. " Rebirths" end
	}
}

local LeaderboardController = {}
local orderedDataStores: {[string]: OrderedDataStore} = {}

-- [ HELPER FUNCTIONS ] -------------------------------------------------------

local function getODS(storeName: string): OrderedDataStore?
	if orderedDataStores[storeName] then return orderedDataStores[storeName] end
	local success, ods = pcall(function() return DataStoreService:GetOrderedDataStore(storeName) end)
	if success then 
		orderedDataStores[storeName] = ods
		return ods 
	else 
		warn(`[LeaderboardController] CRITICAL: Failed to get ODS: {storeName}`)
		return nil 
	end
end

local function clearDisplay(scrollingFrame: ScrollingFrame)
	local template = scrollingFrame:FindFirstChild("Template")
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if not child:IsA("UILayout") and child ~= template then child:Destroy() end
	end
end

-- [ CORE LOGIC ] -------------------------------------------------------------

function LeaderboardController:UpdateDisplay(config: table)
	-- 1. Check Folder
	local folder = Workspace:FindFirstChild(LEADERBOARDS_FOLDER_NAME)
	if not folder then return end

	-- 2. Check Model
	local leaderboardModel = folder:FindFirstChild(config.ModelName)
	if not leaderboardModel then return end

	-- 3. Check SurfaceGui
	local surfaceGui = leaderboardModel:FindFirstChildWhichIsA("SurfaceGui", true)
	if not surfaceGui then 
		warn("[LeaderboardController] MISSING: SurfaceGui inside '".. config.ModelName .."'.")
		return 
	end

	-- 4. Check ScrollingFrame
	local scrollingFrame = surfaceGui:FindFirstChildWhichIsA("ScrollingFrame", true)
	if not scrollingFrame then 
		warn("[LeaderboardController] MISSING: ScrollingFrame inside SurfaceGui of '".. config.ModelName .."'.")
		return 
	end

	-- 5. Check Template
	local entryTemplate = scrollingFrame:FindFirstChild("Template")
	if not entryTemplate then
		local templatesFolder = ReplicatedStorage:FindFirstChild("Templates")
		if templatesFolder then
			entryTemplate = templatesFolder:FindFirstChild(ENTRY_TEMPLATE_NAME)
		end
	end

	if not entryTemplate then
		warn("[LeaderboardController] MISSING: Template for " .. config.ModelName)
		return
	end

	-- Clear & Hide Template
	clearDisplay(scrollingFrame)
	if entryTemplate.Parent == scrollingFrame then entryTemplate.Visible = false end

	local orderedDataStore = getODS(config.StoreName)
	if not orderedDataStore then return end

	local pages
	local getSuccess, getResult = pcall(function()
		return orderedDataStore:GetSortedAsync(false, TOP_N_PLAYERS)
	end)

	if not getSuccess then 
		warn(`[LeaderboardController] API Error: {getResult}`)
		return 
	end

	pages = getResult
	local dataPage = pages:GetCurrentPage()

	if not dataPage or #dataPage == 0 then
		return
	end

	for rank, entryData in ipairs(dataPage) do
		local userId = tonumber(entryData.key)
		local score = entryData.value
		if not userId then continue end

		local newEntry = entryTemplate:Clone()

		-- Use 001, 002 format to ensure name sorting works
		newEntry.Name = string.format("Entry_%03d", rank) 

		-- Use LayoutOrder to force correct sorting order
		newEntry.LayoutOrder = rank 

		newEntry.Visible = true
		newEntry.Parent = scrollingFrame

		local rankLabel = newEntry:FindFirstChild("Rank"):FindFirstChild("RankLabel")
		local scoreLabel = newEntry:FindFirstChild("Score"):FindFirstChild("ScoreLabel")
		local nameLabel = newEntry:FindFirstChild("Name"):FindFirstChild("NameLabel")
		local imageLabel = newEntry:FindFirstChild("ImageLabel")

		-- Set immediate data
		if rankLabel and rankLabel:IsA("TextLabel") then rankLabel.Text = "#" .. tostring(rank) end
		if scoreLabel and scoreLabel:IsA("TextLabel") then scoreLabel.Text = config.ScoreFormatter(score) end
		if imageLabel and imageLabel:IsA("ImageLabel") then
			imageLabel.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
		end

		-- Fetch Name Async (without disrupting order)
		task.spawn(function()
			local nameSuccess, playerName = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
			if not nameSuccess then playerName = "Unknown" end

			if nameLabel and nameLabel:IsA("TextLabel") and newEntry.Parent then 
				nameLabel.Text = playerName 
			end
		end)
	end
end

function LeaderboardController:SavePlayerToLeaderboards(player: Player)
	if not PlayerController then return end

	local profile = PlayerController:GetProfile(player)
	if not profile or not profile.Data then return end

	for _, config in pairs(LEADERBOARDS_CONFIG) do
		local score = profile.Data[config.DataKey]

		if score and score > 0 then
			local ods = getODS(config.StoreName)
			if ods then
				pcall(function() ods:SetAsync(tostring(player.UserId), score) end)
			end
		end
	end
end

-- [ INIT & START ] -----------------------------------------------------------

function LeaderboardController:Init(controllers: {[string]: any})
	PlayerController = controllers.PlayerController
	print("[LeaderboardController] Initialized")
end

function LeaderboardController:Start()
	-- 1. Refresh Visuals Loop
	task.spawn(function()
		while true do
			task.wait(LEADERBOARD_REFRESH_INTERVAL)
			for _, config in pairs(LEADERBOARDS_CONFIG) do self:UpdateDisplay(config) end
		end
	end)

	-- 2. Initial Update (Wait 5s for game to load)
	task.delay(5, function()
		for _, config in pairs(LEADERBOARDS_CONFIG) do self:UpdateDisplay(config) end
	end)

	-- 3. Auto-Save Loop
	task.spawn(function()
		while true do
			task.wait(SAVE_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do self:SavePlayerToLeaderboards(player) end
		end
	end)

	-- 4. Save on Exit
	Players.PlayerRemoving:Connect(function(player)
		self:SavePlayerToLeaderboards(player)
	end)

	-- 5. Save on Server Shutdown
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			self:SavePlayerToLeaderboards(player)
		end
		task.wait(2)
	end)
end

return LeaderboardController