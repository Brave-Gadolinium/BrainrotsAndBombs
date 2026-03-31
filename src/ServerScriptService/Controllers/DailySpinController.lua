--!strict
-- LOCATION: ServerScriptService/Controllers/DailySpinController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.Modules.DailySpinConfiguration)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local AnalyticsFunnelsService = require(ServerScriptService.Modules.AnalyticsFunnelsService)
local AnalyticsEconomyService = require(ServerScriptService.Modules.AnalyticsEconomyService)

local DailySpinController = {}
local RandomObj = Random.new()
local FREE_SPIN_COOLDOWN_SECONDS = math.max(0, tonumber(Config.FreeSpinCooldownSeconds) or (15 * 60))
local isProcessingSpin = {}
local TRANSACTION_TYPES = AnalyticsEconomyService:GetTransactionTypes()

-- Lazy loaded dependencies
local PlayerController
local ItemManager

function DailySpinController:HandleSpin(player: Player)
	if isProcessingSpin[player.UserId] then 
		return {success = false} 
	end

	local profile = PlayerController:GetProfile(player)
	if not profile then return {success = false} end

	local currentTime = os.time()
	local lastSpinTime = profile.Data.LastDailySpin or 0

	-- 1. AUTO-INJECT FREE SPIN
	if (currentTime - lastSpinTime) >= FREE_SPIN_COOLDOWN_SECONDS then
		profile.Data.SpinNumber = (profile.Data.SpinNumber or 0) + 1
		profile.Data.LastDailySpin = currentTime

		player:SetAttribute("SpinNumber", profile.Data.SpinNumber)
		player:SetAttribute("LastDailySpin", profile.Data.LastDailySpin)
		AnalyticsEconomyService:LogSpinSource(player, 1, TRANSACTION_TYPES.TimedReward, "DailySpinFree", {
			feature = "daily_spin",
			content_id = "DailySpinFree",
			context = "daily_spin",
		})
		AnalyticsFunnelsService:HandleDailySpinAvailable(player)
	end

	-- 2. CHECK BALANCE
	if profile.Data.SpinNumber <= 0 then 
		AnalyticsFunnelsService:HandleDailySpinNoSpins(player)
		return {success = false} 
	end

	-- 3. START TRANSACTION LOCK
	isProcessingSpin[player.UserId] = true
	AnalyticsFunnelsService:HandleDailySpinAttempt(player)

	-- 4. ROLL REWARD
	local totalWeight = Config.GetTotalWeight()
	local randomWeight = RandomObj:NextInteger(1, totalWeight)
	local currentWeight = 0
	local index = 1
	for i = 1, #Config.Rewards do
		currentWeight += Config.Rewards[i].Chance
		if randomWeight <= currentWeight then index = i break end
	end

	local rewardData = Config.Rewards[index]

	-- 5. DEDUCT SPIN IMMEDIATELY (Prevents spamming/exploits)
	profile.Data.SpinNumber -= 1
	player:SetAttribute("SpinNumber", profile.Data.SpinNumber)
	AnalyticsEconomyService:LogSpinSink(player, 1, TRANSACTION_TYPES.Gameplay, "WheelSpin", {
		feature = "daily_spin",
		content_id = "WheelSpin",
		context = "wheel",
	})

	-- 6. DELAY REWARDS & VISUALS TO MATCH THE WHEEL ANIMATION
	-- The client tween takes exactly 6.0 seconds.
	task.delay(6, function()
		-- Release lock safely
		isProcessingSpin[player.UserId] = nil

		-- Ensure player is still in the game
		local currentProfile = PlayerController:GetProfile(player)
		if not player.Parent or not currentProfile then return end

		-- APPLY REWARDS
		if rewardData.Type == "Cash" then
			AnalyticsEconomyService:FlushBombIncome(player)
			PlayerController:AddMoney(player, rewardData.Amount)
			AnalyticsEconomyService:LogCashSource(player, rewardData.Amount, TRANSACTION_TYPES.Gameplay, "WheelReward:Cash", {
				feature = "daily_spin",
				content_id = "WheelRewardCash",
				context = "wheel",
			})
		elseif rewardData.Type == "Spins" then
			currentProfile.Data.SpinNumber += rewardData.Amount
			player:SetAttribute("SpinNumber", currentProfile.Data.SpinNumber)
			AnalyticsEconomyService:LogSpinSource(player, rewardData.Amount, TRANSACTION_TYPES.Gameplay, "WheelReward:Spins", {
				feature = "daily_spin",
				content_id = "WheelRewardSpins",
				context = "wheel",
			})
		elseif rewardData.Type == "Item" then
			local itemData = ItemConfigurations.GetItemData(rewardData.Name)
			local rarity = itemData and itemData.Rarity or "Common"
			local tool = ItemManager.GiveItemToPlayer(player, rewardData.Name, "Normal", rarity, 1)
			if tool then
				AnalyticsEconomyService:LogItemValueSourceForItem(
					player,
					rewardData.Name,
					"Normal",
					1,
					TRANSACTION_TYPES.Gameplay,
					`Item:{rewardData.Name}`,
					{
						feature = "daily_spin",
						content_id = rewardData.Name,
						context = "wheel",
						rarity = rarity,
						mutation = "Normal",
					}
				)
			end
		end

		-- TRIGGER VISUALS & NOTIFICATIONS
		local Events = ReplicatedStorage:FindFirstChild("Events")
		local showNotif = Events and Events:FindFirstChild("ShowNotification")

		if rewardData.Type == "Cash" then
			local popUp = Events and Events:FindFirstChild("ShowCashPopUp")
			if popUp then popUp:FireClient(player, rewardData.Amount) end
			if showNotif then showNotif:FireClient(player, "You got $" .. NumberFormatter.Format(rewardData.Amount) .. " cash!", "Success") end

		elseif rewardData.Type == "Spins" then
			if showNotif then showNotif:FireClient(player, "You got +" .. rewardData.Amount .. " spins!", "Success") end

		elseif rewardData.Type == "Item" then
			if showNotif then showNotif:FireClient(player, "You got a " .. rewardData.Name .. "!", "Success") end
		end

		AnalyticsFunnelsService:HandleDailySpinRewardGranted(player, rewardData)
	end)

	return {success = true, Index = index}
end

function DailySpinController:Init(controllers)
	PlayerController = controllers.PlayerController
	ItemManager = require(ServerScriptService.Modules.ItemManager)

	local events = ReplicatedStorage:WaitForChild("Events")
	local remote = events:FindFirstChild("RequestSpin") or Instance.new("RemoteFunction", events)
	remote.Name = "RequestSpin"

	remote.OnServerInvoke = function(player) return self:HandleSpin(player) end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			repeat task.wait() until not player.Parent or PlayerController:GetProfile(player)
			if player.Parent then
				AnalyticsFunnelsService:HandleDailySpinAvailable(player)
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			repeat task.wait() until not player.Parent or PlayerController:GetProfile(player)
			if player.Parent then
				AnalyticsFunnelsService:HandleDailySpinAvailable(player)
			end
		end)
	end

	-- Cleanup lock if a player leaves mid-spin
	Players.PlayerRemoving:Connect(function(player)
		if isProcessingSpin[player.UserId] then
			isProcessingSpin[player.UserId] = nil
		end
	end)
end

return DailySpinController
