--!strict
-- LOCATION: ServerScriptService/Modules/SellManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local SellManager = {}

-- [ MODULES ]
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)
local Constants = require(ReplicatedStorage.Modules.Constants)

local PlayerController -- Lazy Load

-- [ CONFIG ]
local HOURS_TO_SECONDS = 300
local INCOME_SCALING = Constants.INCOME_SCALING

local MUTATION_MULTIPLIERS = {
	["Normal"] = 1,
	["Golden"] = 2,
	["Diamond"] = 3,
	["Ruby"] = 4,
	["Neon"] = 5,
}

-- [ HELPER: Calculate Price ]
local function getItemSellValue(tool: Tool): number
	local name = tool:GetAttribute("OriginalName")
	local mutation = tool:GetAttribute("Mutation")
	local level = tool:GetAttribute("Level") or 1

	if not name then return 0 end

	local itemData = ItemConfigurations.GetItemData(name)
	if not itemData then return 0 end

	local baseIncome = itemData.Income
	local mutMult = MUTATION_MULTIPLIERS[mutation] or 1

	-- Formula: (Income/sec) * 3600 seconds
	local incomePerSec = baseIncome * mutMult * (INCOME_SCALING ^ (level - 1))
	return math.floor(incomePerSec * HOURS_TO_SECONDS)
end

-- [ ACTIONS ]

function SellManager.SellEquipped(player: Player)
	local char = player.Character
	local tool = char and char:FindFirstChildWhichIsA("Tool")

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local notif = Events and Events:FindFirstChild("ShowNotification")

	if tool then
		local value = getItemSellValue(tool)

		if value > 0 then
			PlayerController:AddMoney(player, value)
			tool:Destroy()

			-- Notify
			if notif then notif:FireClient(player, "Sold for $"..NumberFormatter.Format(value), "Success") end

			-- PopUp Visual
			local popup = Events and Events:FindFirstChild("ShowCashPopUp")
			if popup then popup:FireClient(player, value) end
		else
			-- ## FIXED: Tell them if they are trying to sell a Pickaxe! ##
			if notif then notif:FireClient(player, "This item cannot be sold!", "Error") end
		end
	else
		if notif then notif:FireClient(player, "Hold an item to sell it!", "Error") end
	end
end

function SellManager.SellInventory(player: Player)
	local backpack = player:FindFirstChild("Backpack")
	local char = player.Character

	local totalValue = 0
	local itemsSold = 0

	-- ## FIXED: Helper to scan any container for sellable items ##
	local function scanAndSell(container: Instance?)
		if not container then return end
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") then
				local value = getItemSellValue(tool)
				if value > 0 then
					totalValue += value
					itemsSold += 1
					tool:Destroy()
				end
			end
		end
	end

	-- Scan both locations!
	scanAndSell(backpack)
	scanAndSell(char)

	local Events = ReplicatedStorage:FindFirstChild("Events")
	local notif = Events and Events:FindFirstChild("ShowNotification")

	if totalValue > 0 then
		PlayerController:AddMoney(player, totalValue)

		if notif then notif:FireClient(player, "Sold "..itemsSold.." items for $"..NumberFormatter.Format(totalValue), "Success") end

		local popup = Events and Events:FindFirstChild("ShowCashPopUp")
		if popup then popup:FireClient(player, totalValue) end
	else
		if notif then notif:FireClient(player, "You have no items to sell!", "Error") end
	end
end

-- [ INIT ]

function SellManager:Init(controllers)
	print("[SellManager] Initialized")
	PlayerController = controllers.PlayerController

	local Events = ReplicatedStorage:WaitForChild("Events")

	-- Create Remote
	local sellEvent = Events:FindFirstChild("RequestSell")
	if not sellEvent then
		sellEvent = Instance.new("RemoteEvent")
		sellEvent.Name = "RequestSell"
		sellEvent.Parent = Events
	end

	sellEvent.OnServerEvent:Connect(function(player, actionType)
		if actionType == "Equipped" then
			SellManager.SellEquipped(player)
		elseif actionType == "Inventory" then
			SellManager.SellInventory(player)
		end
	end)
end

function SellManager:Start()
	-- No loop needed
end

return SellManager