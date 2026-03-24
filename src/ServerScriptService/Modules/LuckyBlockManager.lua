--!strict
-- LOCATION: ServerScriptService/Modules/LuckyBlockManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LuckyBlockConfiguration = require(ReplicatedStorage.Modules.LuckyBlockConfiguration)
local ItemConfigurations = require(ReplicatedStorage.Modules.ItemConfigurations)

local LuckyBlocksFolder = ReplicatedStorage:WaitForChild("Luckyblocks")

local LuckyBlockManager = {}

export type RolledReward = {
	ItemName: string,
	Weight: number,
	ItemData: any,
}

local randomGenerator = Random.new()

local function getTotalWeight(rewards)
	local totalWeight = 0
	for _, reward in ipairs(rewards) do
		if type(reward.Weight) == "number" and reward.Weight > 0 then
			totalWeight += reward.Weight
		end
	end
	return totalWeight
end

local function getRootPart(model: Model): BasePart?
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
end

function LuckyBlockManager.GetBlockConfig(blockId: string)
	return LuckyBlockConfiguration.GetBlockConfig(blockId)
end

function LuckyBlockManager.GetAllBlocks()
	return LuckyBlockConfiguration.GetAllBlocks()
end

function LuckyBlockManager.HasBlockModel(blockId: string): boolean
	local blockConfig = LuckyBlockConfiguration.GetBlockConfig(blockId)
	if not blockConfig then
		return false
	end

	return LuckyBlocksFolder:FindFirstChild(blockConfig.ModelName) ~= nil
end

function LuckyBlockManager.RollReward(blockId: string): RolledReward?
	local blockConfig = LuckyBlockConfiguration.GetBlockConfig(blockId)
	if not blockConfig then
		warn("[LuckyBlockManager] Missing block config:", blockId)
		return nil
	end

	local rewards = blockConfig.Rewards
	local totalWeight = getTotalWeight(rewards)
	if totalWeight <= 0 then
		warn("[LuckyBlockManager] Invalid reward pool for block:", blockId)
		return nil
	end

	local roll = randomGenerator:NextNumber(0, totalWeight)
	local cumulativeWeight = 0

	for _, reward in ipairs(rewards) do
		local weight = math.max(0, reward.Weight or 0)
		cumulativeWeight += weight
		if roll <= cumulativeWeight then
			local itemData = ItemConfigurations.GetItemData(reward.ItemName)
			if not itemData then
				warn("[LuckyBlockManager] Missing item configuration:", reward.ItemName, "for block", blockId)
				return nil
			end

			return {
				ItemName = reward.ItemName,
				Weight = weight,
				ItemData = itemData,
			}
		end
	end

	local fallbackReward = rewards[#rewards]
	if not fallbackReward then
		return nil
	end

	local fallbackItemData = ItemConfigurations.GetItemData(fallbackReward.ItemName)
	if not fallbackItemData then
		warn("[LuckyBlockManager] Missing fallback item configuration:", fallbackReward.ItemName, "for block", blockId)
		return nil
	end

	return {
		ItemName = fallbackReward.ItemName,
		Weight = math.max(0, fallbackReward.Weight or 0),
		ItemData = fallbackItemData,
	}
end

function LuckyBlockManager.PlayOpeningAnimation(model: Model): boolean
	local rootPart = getRootPart(model)
	if not rootPart then
		warn("[LuckyBlockManager] Lucky block model has no root part for animation")
		return false
	end

	if not model.PrimaryPart then
		model.PrimaryPart = rootPart
	end

	local spinDuration = 1.35
	local startSpeed = 720
	local endSpeed = 2880
	local scaleStart = model:GetScale()
	local scaleValue = Instance.new("NumberValue")
		scaleValue.Value = scaleStart
		scaleValue.Parent = model

	local scaleConnection = scaleValue.Changed:Connect(function(value)
		if model.Parent then
			model:ScaleTo(value)
		end
	end)

	local elapsed = 0
	while elapsed < spinDuration and model.Parent do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		local alpha = math.clamp(elapsed / spinDuration, 0, 1)
		local speed = startSpeed + ((endSpeed - startSpeed) * alpha)
		local pivot = model:GetPivot()
		model:PivotTo(pivot * CFrame.Angles(0, math.rad(speed * dt), 0))
	end

	if not model.Parent then
		scaleConnection:Disconnect()
		scaleValue:Destroy()
		return false
	end

	local shrinkTween = TweenService:Create(
		scaleValue,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Value = scaleStart * 0.08 }
	)
	shrinkTween:Play()
	shrinkTween.Completed:Wait()

	scaleConnection:Disconnect()
	scaleValue:Destroy()
	return model.Parent ~= nil
end

function LuckyBlockManager.ValidateConfiguration(): (boolean, {string})
	local errors = {}

	for blockId, blockConfig in pairs(LuckyBlockConfiguration.GetAllBlocks()) do
		if LuckyBlocksFolder:FindFirstChild(blockConfig.ModelName) == nil then
			table.insert(errors, string.format("Missing lucky block model: %s", blockConfig.ModelName))
		end

		for _, reward in ipairs(blockConfig.Rewards) do
			if ItemConfigurations.GetItemData(reward.ItemName) == nil then
				table.insert(errors, string.format("Missing reward item %s for block %s", reward.ItemName, blockId))
			end
		end
	end

	return #errors == 0, errors
end

return LuckyBlockManager