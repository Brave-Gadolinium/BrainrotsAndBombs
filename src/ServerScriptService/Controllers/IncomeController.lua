--!strict
-- LOCATION: ServerScriptService/Controllers/IncomeController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local IncomeController = {}

local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local PlayerController -- Lazy load
local Constants = require(ReplicatedStorage.Modules.Constants)

local CYCLE_RATE = 1.0
local INCOME_SCALING = Constants.INCOME_SCALING
local VIP_MULTIPLIER = 1.5 -- VIP gives +50% Income

local MUTATION_MULTIPLIERS = {
	["Normal"] = 1,
	["Golden"] = 2,
	["Diamond"] = 3,
	["Ruby"] = 4,
	["Neon"] = 5,
}

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

					-- ## ADDED: Check VIP Status ##
					local isVip = PlayerController:IsVIP(player)
					local vipMult = isVip and VIP_MULTIPLIER or 1

					local plotModel = Workspace:FindFirstChild("Plot_" .. player.Name)

					for floorName, floorSlots in pairs(profile.Data.Plots) do
						for slotName, slotData in pairs(floorSlots) do
							if slotData.Item then
								if type(slotData.Stored) ~= "number" then slotData.Stored = 0 end

								local itemConf = ItemConfigurations.GetItemData(slotData.Item.Name)
								if itemConf then
									local base = itemConf.Income
									local mutMult = MUTATION_MULTIPLIERS[slotData.Item.Mutation] or 1
									local levelMult = INCOME_SCALING ^ (slotData.Level - 1)

									local reb = profile.Data.Rebirths or 0
									local rebMult = 1 + (reb * 0.5)

									-- ## APPLIED VIP MULT HERE ##
									local income = base * mutMult * levelMult * rebMult * vipMult

									slotData.Stored += income

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
											local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
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