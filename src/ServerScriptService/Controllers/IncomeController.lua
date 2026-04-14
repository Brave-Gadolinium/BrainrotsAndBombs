--!strict
-- LOCATION: ServerScriptService/Controllers/IncomeController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local IncomeController = {}

local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local IncomeCalculationUtils = require(ReplicatedStorage.Modules.IncomeCalculationUtils)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local AnalyticsFunnelsService = require(script.Parent.Parent.Modules.AnalyticsFunnelsService)
local PlayerController -- Lazy load

local CYCLE_RATE = 1.0

function IncomeController:Init(controllers)
	PlayerController = controllers.PlayerController
end

function IncomeController:Start()
	task.spawn(function()
		while true do
			task.wait(CYCLE_RATE)

			for _, player in ipairs(Players:GetPlayers()) do
				local profile = PlayerController:GetProfile(player)
				if profile and profile.Data.Plots then
					local isVip = PlayerController:IsVIP(player)
					local friendBoostMultiplier = math.max(1, tonumber(player:GetAttribute("FriendBoostMultiplier")) or 1)

					local plotModel = Workspace:FindFirstChild("Plot_" .. player.Name)

					for floorName, floorSlots in pairs(profile.Data.Plots) do
						for slotName, slotData in pairs(floorSlots) do
							if slotData.Item then
								if type(slotData.Stored) ~= "number" then slotData.Stored = 0 end

								local itemConf = ItemConfigurations.GetItemData(slotData.Item.Name)
								if itemConf then
									local income = IncomeCalculationUtils.ComputeOnlineIncomePerSecond(
										itemConf.Income,
										slotData.Item.Mutation,
										slotData.Level,
										profile.Data.Rebirths,
										isVip,
										friendBoostMultiplier
									)

									local previousStored = slotData.Stored
									slotData.Stored += income
									if previousStored <= 0 and slotData.Stored > 0 then
										AnalyticsFunnelsService:HandleStoredCashPositive(player, floorName, slotName)
									end

									-- Visual Update
									if plotModel then
										local floor = plotModel:FindFirstChild(floorName)
										local slots = floor and floor:FindFirstChild("Slots")
										local slotMod = slots and slots:FindFirstChild(slotName)
										local colPart = slotMod and slotMod:FindFirstChild("CollectTouch")
										local gui = colPart and colPart:FindFirstChild("CollectGUI")
										local frame = gui and gui:FindFirstChild("CollectFrame")
										local label = frame and frame:FindFirstChild("Price") :: TextLabel

										if label then
											label.Text = "$" .. NumberFormatter.Format(slotData.Stored)
											label.Visible = true
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end)
end

return IncomeController
