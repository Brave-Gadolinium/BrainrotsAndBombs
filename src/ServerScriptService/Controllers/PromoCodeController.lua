--!strict
-- LOCATION: ServerScriptService/Controllers/PromoCodeController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)
local PromoCodesConfiguration = require(ServerScriptService.Modules.PromoCodesConfiguration)

local PromoCodeController = {}
local LOG_PREFIX = "[PromoCodeController]"

type MoneyReward = {
	Type: "Money",
	Amount: number,
}

type ItemReward = {
	Type: "Item",
	ItemName: string,
	Mutation: string?,
	Level: number?,
}

type RandomItemsReward = {
	Type: "RandomItems",
	Rarity: string,
	Count: number,
	Mutation: string?,
	Level: number?,
}

type BundleReward = {
	Type: "Bundle",
	Rewards: {Reward},
}

type Reward = MoneyReward | ItemReward | RandomItemsReward | BundleReward
type PromoCodeEntry = {
	Id: string,
	Code: string,
	Reward: Reward,
	SuccessText: string,
}

type RedeemResponse = {
	Success: boolean,
	Error: string?,
	CodeId: string?,
	RewardType: string?,
	RewardText: string?,
}

local PlayerController: any = nil
local ItemManager: any = nil
local redeemRemote: RemoteFunction? = nil
local redeemLocks: {[Player]: boolean} = {}
local grantReward: (player: Player, reward: Reward) -> (boolean, string?, string?)

local function log(message: string)
	print(`${LOG_PREFIX} {message}`)
end

local function warnLog(message: string)
	warn(`${LOG_PREFIX} {message}`)
end

local function getProfile(player: Player)
	if not PlayerController then
		return nil
	end

	return PlayerController:GetProfile(player)
end

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureRedeemedCodes(profile: any): {[string]: boolean}
	if type(profile.Data.RedeemedCodes) ~= "table" then
		profile.Data.RedeemedCodes = {}
	end

	return profile.Data.RedeemedCodes
end

local function grantMoneyReward(player: Player, reward: MoneyReward): (boolean, string?)
	local amount = math.max(0, math.floor(tonumber(reward.Amount) or 0))
	if amount <= 0 then
		warnLog(`Invalid money reward amount for {player.Name}: {tostring(reward.Amount)}`)
		return false, "RewardGrantFailed"
	end

	log(`Granting money reward to {player.Name}: Amount={amount}`)
	PlayerController:AddMoney(player, amount)
	return true, nil
end

local function grantItemReward(player: Player, reward: ItemReward): (boolean, string?)
	local itemName = reward.ItemName
	local itemData = ItemConfigurations.GetItemData(itemName)
	if not itemData then
		warnLog(`Missing item configuration for code reward "{itemName}".`)
		return false, "RewardGrantFailed"
	end

	local backpack = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		warnLog(`Backpack was not available for {player.Name} while granting item reward "{itemName}".`)
		return false, "RewardGrantFailed"
	end

	local mutation = if type(reward.Mutation) == "string" and reward.Mutation ~= "" then reward.Mutation else "Normal"
	local level = math.max(1, math.floor(tonumber(reward.Level) or 1))
	log(`Granting item reward to {player.Name}: Item={itemName} Mutation={mutation} Level={level}`)
	local tool = ItemManager.GiveItemToPlayer(player, itemName, mutation, itemData.Rarity, level)
	if not tool then
		warnLog(`ItemManager failed to grant "{itemName}" to {player.Name}.`)
		return false, "RewardGrantFailed"
	end

	PlayerController:IncrementBrainrotsCollected(player, 1)
	log(`Item reward granted successfully to {player.Name}: Item={itemName}`)
	return true, nil
end

local function grantRandomItemsReward(player: Player, reward: RandomItemsReward): (boolean, string?)
	local rarity = tostring(reward.Rarity or "")
	local count = math.max(1, math.floor(tonumber(reward.Count) or 0))
	local itemPool = ItemConfigurations.GetItemsByRarity(rarity)
	if #itemPool == 0 then
		warnLog(`No items found for promo code rarity "{rarity}".`)
		return false, "RewardGrantFailed"
	end

	local mutation = if type(reward.Mutation) == "string" and reward.Mutation ~= "" then reward.Mutation else "Normal"
	local level = math.max(1, math.floor(tonumber(reward.Level) or 1))

	for _ = 1, count do
		local itemName = itemPool[math.random(1, #itemPool)]
		local itemData = ItemConfigurations.GetItemData(itemName)
		if not itemData then
			warnLog(`Missing item configuration for random reward "{itemName}".`)
			return false, "RewardGrantFailed"
		end

		local tool = ItemManager.GiveItemToPlayer(player, itemName, mutation, itemData.Rarity, level)
		if not tool then
			warnLog(`ItemManager failed to grant random reward "{itemName}" to {player.Name}.`)
			return false, "RewardGrantFailed"
		end

		PlayerController:IncrementBrainrotsCollected(player, 1)
	end

	log(`Granted random item reward to {player.Name}: Rarity={rarity} Count={count}`)
	return true, nil
end

local function grantBundleReward(player: Player, reward: BundleReward): (boolean, string?)
	if type(reward.Rewards) ~= "table" or #reward.Rewards == 0 then
		warnLog(`Invalid bundle reward for {player.Name}.`)
		return false, "RewardGrantFailed"
	end

	for _, nestedReward in ipairs(reward.Rewards) do
		local success, errorCode = grantReward(player, nestedReward)
		if not success then
			return false, errorCode
		end
	end

	return true, nil
end

function grantReward(player: Player, reward: Reward): (boolean, string?, string?)
	if reward.Type == "Money" then
		local success, errorCode = grantMoneyReward(player, reward)
		return success, errorCode, reward.Type
	end

	if reward.Type == "Item" then
		local success, errorCode = grantItemReward(player, reward)
		return success, errorCode, reward.Type
	end

	if reward.Type == "RandomItems" then
		local success, errorCode = grantRandomItemsReward(player, reward)
		return success, errorCode, reward.Type
	end

	if reward.Type == "Bundle" then
		local success, errorCode = grantBundleReward(player, reward)
		return success, errorCode, reward.Type
	end

	return false, "RewardGrantFailed", nil
end

local function buildErrorResponse(errorCode: string, codeId: string?): RedeemResponse
	return {
		Success = false,
		Error = errorCode,
		CodeId = codeId,
	}
end

function PromoCodeController:HandleRedeem(player: Player, rawCode: string): RedeemResponse
	log(`Redeem request received from {player.Name}. Raw="{tostring(rawCode)}"`)
	local profile = getProfile(player)
	if not profile then
		warnLog(`Profile not loaded for {player.Name}.`)
		return buildErrorResponse("ProfileNotLoaded", nil)
	end

	local normalizedCode = PromoCodesConfiguration.NormalizeCode(rawCode)
	log(`Normalized code for {player.Name}: "{normalizedCode}"`)
	if normalizedCode == "" then
		log(`Rejected empty code from {player.Name}.`)
		return buildErrorResponse("EmptyCode", nil)
	end

	local entry: PromoCodeEntry? = PromoCodesConfiguration.GetByNormalizedCode(normalizedCode)
	if not entry then
		log(`Rejected invalid code from {player.Name}: "{normalizedCode}"`)
		return buildErrorResponse("InvalidCode", nil)
	end

	local redeemedCodes = ensureRedeemedCodes(profile)
	if redeemedCodes[entry.Id] == true then
		log(`Rejected already redeemed code for {player.Name}: CodeId={entry.Id}`)
		return buildErrorResponse("AlreadyRedeemed", entry.Id)
	end

	if redeemLocks[player] then
		log(`Rejected busy redeem request for {player.Name}: CodeId={entry.Id}`)
		return buildErrorResponse("Busy", entry.Id)
	end

	redeemLocks[player] = true
	log(`Processing code for {player.Name}: CodeId={entry.Id} RewardType={entry.Reward.Type}`)

	local success, response = pcall(function(): RedeemResponse
		local granted, errorCode, rewardType = grantReward(player, entry.Reward)
		if not granted then
			warnLog(`Reward grant failed for {player.Name}: CodeId={entry.Id} Error={tostring(errorCode)}`)
			return buildErrorResponse(errorCode or "RewardGrantFailed", entry.Id)
		end

		redeemedCodes[entry.Id] = true
		log(`Marked code as redeemed for {player.Name}: CodeId={entry.Id}`)

		return {
			Success = true,
			CodeId = entry.Id,
			RewardType = rewardType,
			RewardText = entry.SuccessText,
		}
	end)

	redeemLocks[player] = nil

	if not success then
		warnLog(`Unhandled redeem error for {player.Name}: CodeId={entry.Id} Error={tostring(response)}`)
		return buildErrorResponse("RewardGrantFailed", entry.Id)
	end

	if response.Success then
		log(`Redeem completed for {player.Name}: CodeId={entry.Id} RewardType={tostring(response.RewardType)}`)
	else
		log(`Redeem finished with failure for {player.Name}: CodeId={entry.Id} Error={tostring(response.Error)}`)
	end

	return response
end

function PromoCodeController:Init(controllers)
	PlayerController = controllers.PlayerController
	ItemManager = require(ServerScriptService.Modules.ItemManager)

	local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")
	local codesFolder = ensureFolder(remotesFolder, "Codes")
	redeemRemote = ensureRemoteFunction(codesFolder, "Redeem")
	log("Codes redeem remote initialized.")

	redeemRemote.OnServerInvoke = function(player, rawCode)
		return self:HandleRedeem(player, rawCode)
	end

	Players.PlayerRemoving:Connect(function(player)
		redeemLocks[player] = nil
	end)
end

return PromoCodeController
