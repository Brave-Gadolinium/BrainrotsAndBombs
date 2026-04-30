--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SharedInstancesBootstrap = {}

type RemoteDescriptor = {
	Name: string,
	ClassName: "RemoteEvent" | "RemoteFunction",
}

type NamespaceDescriptor = {
	Name: string,
	Children: {RemoteDescriptor},
}

local EVENT_DESCRIPTORS: {RemoteDescriptor} = {
	{Name = "ShowNotification", ClassName = "RemoteEvent"},
	{Name = "RequestSlotPurchase", ClassName = "RemoteEvent"},
	{Name = "RequestRebirth", ClassName = "RemoteEvent"},
	{Name = "UpdateRebirthUI", ClassName = "RemoteEvent"},
	{Name = "RefreshIndex", ClassName = "RemoteEvent"},
	{Name = "ReportTutorialAction", ClassName = "RemoteEvent"},
	{Name = "ReportAnalyticsIntent", ClassName = "RemoteEvent"},
	{Name = "TriggerUIEffect", ClassName = "RemoteEvent"},
	{Name = "ShowPostTutorialCompletion", ClassName = "RemoteEvent"},
	{Name = "RequestRewardedAd", ClassName = "RemoteEvent"},
	{Name = "RewardedAdResult", ClassName = "RemoteEvent"},
	{Name = "RequestAutoBombState", ClassName = "RemoteEvent"},
	{Name = "RequestUseBoosterCharge", ClassName = "RemoteEvent"},
	{Name = "RequestVipSubscriptionStudioGrant", ClassName = "RemoteEvent"},
	{Name = "ShowContextualOffer", ClassName = "RemoteEvent"},
	{Name = "RequestDropItem", ClassName = "RemoteEvent"},
	{Name = "RequestClearCarry", ClassName = "RemoteEvent"},
	{Name = "RequestSell", ClassName = "RemoteEvent"},
	{Name = "RequestUpgradeAction", ClassName = "RemoteEvent"},
	{Name = "UpdateUpgradesUI", ClassName = "RemoteEvent"},
	{Name = "RequestSlotUpgrade", ClassName = "RemoteEvent"},
	{Name = "ShowCashPopUp", ClassName = "RemoteEvent"},
	{Name = "ShowCandyPopUp", ClassName = "RemoteEvent"},
	{Name = "RequestJetpackState", ClassName = "RemoteEvent"},
	{Name = "RequestPickaxeAction", ClassName = "RemoteEvent"},
	{Name = "GetPickaxeData", ClassName = "RemoteFunction"},
	{Name = "UpdatePickaxeUI", ClassName = "RemoteEvent"},
	{Name = "RequestGroupReward", ClassName = "RemoteFunction"},
	{Name = "RequestLimitedProductPrompt", ClassName = "RemoteFunction"},
	{Name = "RequestSpin", ClassName = "RemoteFunction"},
	{Name = "GetIndexData", ClassName = "RemoteFunction"},
}

local REMOTE_NAMESPACES: {NamespaceDescriptor} = {
	{
		Name = "Helper",
		Children = {
			{Name = "TeleportPlayer", ClassName = "RemoteEvent"},
			{Name = "ConfirmExitGame", ClassName = "RemoteEvent"},
		},
	},
	{
		Name = "OfflineIncome",
		Children = {
			{Name = "GetStatus", ClassName = "RemoteFunction"},
			{Name = "Claim", ClassName = "RemoteFunction"},
			{Name = "StartPlay15", ClassName = "RemoteFunction"},
			{Name = "StatusUpdated", ClassName = "RemoteEvent"},
		},
	},
	{
		Name = "DailyRewards",
		Children = {
			{Name = "GetStatus", ClassName = "RemoteFunction"},
			{Name = "ClaimReward", ClassName = "RemoteFunction"},
			{Name = "StatusUpdated", ClassName = "RemoteEvent"},
		},
	},
	{
		Name = "PlaytimeRewards",
		Children = {
			{Name = "GetStatus", ClassName = "RemoteFunction"},
			{Name = "ClaimReward", ClassName = "RemoteFunction"},
			{Name = "StatusUpdated", ClassName = "RemoteEvent"},
		},
	},
	{
		Name = "Codes",
		Children = {
			{Name = "Redeem", ClassName = "RemoteFunction"},
		},
	},
	{
		Name = "QuestChain",
		Children = {
			{Name = "GetState", ClassName = "RemoteFunction"},
			{Name = "ClaimQuest", ClassName = "RemoteFunction"},
			{Name = "StateUpdated", ClassName = "RemoteEvent"},
		},
	},
	{
		Name = "CandyEvent",
		Children = {
			{Name = "GetState", ClassName = "RemoteFunction"},
			{Name = "Spin", ClassName = "RemoteFunction"},
			{Name = "StateUpdated", ClassName = "RemoteEvent"},
		},
	},
	{
		Name = "JoinGiftBrainrot",
		Children = {
			{Name = "GetState", ClassName = "RemoteFunction"},
			{Name = "MarkPreviewShown", ClassName = "RemoteEvent"},
			{Name = "RequestPickup", ClassName = "RemoteFunction"},
			{Name = "StateUpdated", ClassName = "RemoteEvent"},
		},
	},
}

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

local function ensureRemote(parent: Instance, descriptor: RemoteDescriptor): RemoteEvent | RemoteFunction
	local existing = parent:FindFirstChild(descriptor.Name)
	if existing and existing.ClassName == descriptor.ClassName then
		return existing :: RemoteEvent | RemoteFunction
	end

	if existing then
		existing:Destroy()
	end

	local remote = Instance.new(descriptor.ClassName)
	remote.Name = descriptor.Name
	remote.Parent = parent
	return remote :: RemoteEvent | RemoteFunction
end

function SharedInstancesBootstrap:Ensure()
	local eventsFolder = ensureFolder(ReplicatedStorage, "Events")
	for _, descriptor in ipairs(EVENT_DESCRIPTORS) do
		ensureRemote(eventsFolder, descriptor)
	end

	local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")
	for _, namespace in ipairs(REMOTE_NAMESPACES) do
		local namespaceFolder = ensureFolder(remotesFolder, namespace.Name)
		for _, descriptor in ipairs(namespace.Children) do
			ensureRemote(namespaceFolder, descriptor)
		end
	end

	return {
		Events = eventsFolder,
		Remotes = remotesFolder,
	}
end

return SharedInstancesBootstrap
