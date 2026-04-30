--!strict

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewardManager = require(script.Parent.DailyRewardManager)
local PlaytimeRewardManager = require(script.Parent.PlaytimeRewardManager)
local DailySpinConfiguration = require(ReplicatedStorage.Modules.DailySpinConfiguration)
local TutorialConfiguration = require(ReplicatedStorage.Modules.TutorialConfiguration)
local RebirthRequirements = require(ReplicatedStorage.Modules.RebirthRequirements)
local ProductConfigurations = require(ReplicatedStorage.Modules.ProductConfigurations)
local BombsConfigurations = require(ReplicatedStorage.Modules.BombsConfigurations)
local UpgradesConfiguration = require(ReplicatedStorage.Modules.UpgradesConfigurations)

type SessionState = {
	SessionId: string,
	Step: number,
}

type PurchaseAttribution = {
	ExpiresAt: number,
	Fields: {[string]: any},
}

local AnalyticsFunnelsService = {}

local PlayerController: any = nil
local reportIntentEvent: RemoteEvent? = nil
local activeSessions: {[Player]: {[string]: SessionState}} = {}
local purchaseAttributions: {[Player]: {[string]: PurchaseAttribution}} = {}
local autoBombToggleSurfaces: {[Player]: {Surface: string, ExpiresAt: number}} = {}
local initialized = false

local TUTORIAL_VERSION = "tutor_29_04"
local TUTORIAL_FUNNEL_KEY = "Tutor_29_04"
local TUTORIAL_FUNNEL_NAME = "Tutor_29/04"
local LEGACY_TUTORIAL_FUNNEL_KEYS = {"Tutor_28_04", "Tutor_27_04", "Tutor_24_04", "Tutor_23_04", "Tutor_22_04", "TutorialFTUE"}
local TUTORIAL_ENTERED_MARKER_KEY = "tutorial_entered"
local TUTORIAL_COMPLETED_MARKER_KEY = "tutorial_completed"
local TUTORIAL_SKIPPED_MARKER_KEY = "tutorial_skipped"
local BRAINROT_COLLECTION_FUNNEL_KEY = "BrainrotCollectionMilestones"
local BRAINROT_COLLECTION_STEP_THRESHOLDS = {
	[1] = 0,
	[2] = 1,
	[3] = 2,
	[4] = 3,
	[5] = 4,
	[6] = 5,
	[7] = 6,
	[8] = 7,
	[9] = 8,
	[10] = 9,
	[11] = 10,
	[12] = 20,
	[13] = 30,
	[14] = 50,
	[15] = 100,
}
local SECONDS_PER_DAY = 86400
local FREE_SPIN_COOLDOWN_SECONDS = math.max(0, tonumber(DailySpinConfiguration.FreeSpinCooldownSeconds) or (15 * 60))
local PURCHASE_ATTRIBUTION_TTL = 120
local OneTimeFunnels = {
	[TUTORIAL_FUNNEL_KEY] = {
		Kind = "Standard",
		FunnelName = TUTORIAL_FUNNEL_NAME,
		LegacyOneTimeKeys = LEGACY_TUTORIAL_FUNNEL_KEYS,
		Steps = {
			[1] = "JoinGame",
			[2] = "WalkToZone",
			[3] = "ThrowBomb",
			[4] = "PickupBrainrot",
			[5] = "BackToSurface",
			[6] = "PlaceBrainrot",
			[7] = "CollectCash",
			[8] = "OpenBombShop",
			[9] = "BuyBomb2",
			[10] = "OpenUpgrades",
			[11] = "BuyCharacterUpgrade",
			[12] = "BaseUpgradeComplete",
			[13] = "TutorialComplete",
		},
	},
	EarlyProgressionToFirstRebirth = {
		Kind = "Standard",
		FunnelName = "EarlyProgressionToFirstRebirth",
		Steps = {
			[1] = "TutorialComplete",
			[2] = "FirstExtraSlotsBought",
			[3] = "FirstSlotUpgrade",
			[4] = "Bomb3Bought",
			[5] = "Rebirth1",
		},
	},
	BaseEconomyActivation = {
		Kind = "Standard",
		FunnelName = "BaseEconomyActivation",
		Steps = {
			[1] = "FirstItemPlaced",
			[2] = "FirstStoredCashPositive",
			[3] = "FirstManualCollect",
			[4] = "FirstSlotUpgradeAfterCollect",
		},
	},
	[BRAINROT_COLLECTION_FUNNEL_KEY] = {
		Kind = "Standard",
		FunnelName = "BrainrotCollectionMilestones",
		Steps = {
			[1] = "JoinGame",
			[2] = "PickupBrainrot1",
			[3] = "PickupBrainrot2",
			[4] = "PickupBrainrot3",
			[5] = "PickupBrainrot4",
			[6] = "PickupBrainrot5",
			[7] = "PickupBrainrot6",
			[8] = "PickupBrainrot7",
			[9] = "PickupBrainrot8",
			[10] = "PickupBrainrot9",
			[11] = "PickupBrainrot10",
			[12] = "PickupBrainrot20",
			[13] = "PickupBrainrot30",
			[14] = "PickupBrainrot50",
			[15] = "PickupBrainrot100",
		},
	},
}

local RecurringFunnels = {
	MineRunLoop = {
		FunnelName = "MineRunLoop",
		Steps = {
			[1] = "EnterMine",
			[2] = "ThrowBomb",
			[3] = "PickupBrainrot",
			[4] = "ExitMineWithCarry",
			[5] = "ToolGrantedOnExit",
			[6] = "PlaceOrSellFirstItem",
		},
		ClearOnComplete = true,
	},
	BombShopConversion = {
		FunnelName = "BombShopConversion",
		Steps = {
			[1] = "ShopOpened",
			[2] = "BombSelected",
			[3] = "BuyPressed",
			[4] = "PurchaseSuccess",
		},
		ClearOnComplete = true,
	},
	StatUpgradesConversion = {
		FunnelName = "StatUpgradesConversion",
		Steps = {
			[1] = "UpgradesOpened",
			[2] = "UpgradeSelected",
			[3] = "CashBuyPressed",
			[4] = "UpgradeSuccess",
		},
		ClearOnComplete = true,
	},
	RebirthConversion = {
		FunnelName = "RebirthConversion",
		Steps = {
			[1] = "RebirthEligible",
			[2] = "RebirthUIOpened",
			[3] = "RebirthPressed",
			[4] = "RebirthSuccess",
		},
		ClearOnComplete = true,
	},
	DailyRewardClaim = {
		FunnelName = "DailyRewardClaim",
		Steps = {
			[1] = "ClaimAvailable",
			[2] = "DailyRewardsOpened",
			[3] = "RewardClicked",
			[4] = "ClaimSuccess",
		},
		ClearOnComplete = true,
	},
	PlaytimeRewards = {
		FunnelName = "PlaytimeRewards",
		Steps = {
			[1] = "FirstRewardClaimable",
			[2] = "PlaytimeRewardsOpened",
			[3] = "FirstRewardClaimed",
			[4] = "MultipleRewardsClaimed",
			[5] = "AllTodayClaimed",
		},
		ClearOnComplete = false,
	},
	DailySpin = {
		FunnelName = "DailySpin",
		Steps = {
			[1] = "SpinAvailable",
			[2] = "WheelOpened",
			[3] = "SpinPressed",
			[4] = "RewardGranted",
		},
		ClearOnComplete = true,
	},
}

local function getProfile(player: Player)
	if not PlayerController then
		return nil
	end

	return PlayerController:GetProfile(player)
end

local function ensureAnalyticsData(profile: any)
	if type(profile.Data.AnalyticsFunnels) ~= "table" then
		profile.Data.AnalyticsFunnels = {}
	end

	local analyticsData = profile.Data.AnalyticsFunnels
	if type(analyticsData.OneTime) ~= "table" then
		analyticsData.OneTime = {}
	end
	if type(analyticsData.Markers) ~= "table" then
		analyticsData.Markers = {}
	end

	return analyticsData
end

local function isTutorialSkipped(profile: any): boolean
	return profile ~= nil and profile.Data ~= nil and profile.Data.TutorialSkipped == true
end

local function getBombTierFromName(bombName: string?): number
	if type(bombName) ~= "string" then
		return 0
	end

	return tonumber(bombName:match("(%d+)")) or 0
end

local function getUpgradeConfigById(upgradeId: string): any
	for _, config in ipairs(UpgradesConfiguration.Upgrades) do
		if config.Id == upgradeId then
			return config
		end
	end

	return nil
end

local function toSnakeCase(value: any): string
	if type(value) ~= "string" then
		return "unknown"
	end

	local normalized = value
		:gsub("([a-z0-9])([A-Z])", "%1_%2")
		:gsub("%s+", "_")
		:gsub("[^%w_]+", "_")
		:gsub("_+", "_")
		:gsub("^_+", "")
		:gsub("_+$", "")
		:lower()

	if normalized == "" then
		return "unknown"
	end

	return normalized
end

local function getEquippedBombTier(player: Player): number
	local profile = getProfile(player)
	local equippedBomb = profile and profile.Data and profile.Data.EquippedPickaxe or nil
	return getBombTierFromName(equippedBomb)
end

local function getRebirthBucket(player: Player): string
	local profile = getProfile(player)
	local rebirths = profile and profile.Data and tonumber(profile.Data.Rebirths) or 0

	if rebirths <= 0 then
		return "0"
	end
	if rebirths < 5 then
		return "1-4"
	end
	if rebirths < 10 then
		return "5-9"
	end

	return "10+"
end

local function isVip(player: Player): boolean
	if PlayerController and PlayerController.IsVIP then
		return PlayerController:IsVIP(player) == true
	end

	return player:GetAttribute("IsVIP") == true
end

local function sanitizeCustomFields(fields: {[string]: any}?): {[string]: any}?
	if not fields then
		return nil
	end

	local sanitized = {}
	for key, value in pairs(fields) do
		local valueType = typeof(value)
		if value ~= nil and (valueType == "string" or valueType == "number" or valueType == "boolean") then
			sanitized[key] = value
		end
	end

	if next(sanitized) == nil then
		return nil
	end

	return sanitized
end

local function buildFirstStepFields(player: Player, customFields: {[string]: any}?): {[string]: any}?
	local fields = {
		tutorial_version = TUTORIAL_VERSION,
		bomb_tier = getEquippedBombTier(player),
		rebirth_bucket = getRebirthBucket(player),
		vip = isVip(player),
	}

	for key, value in pairs(customFields or {}) do
		fields[key] = value
	end

	return sanitizeCustomFields(fields)
end

local function shallowCopyFields(fields: {[string]: any}?): {[string]: any}
	local copy = {}
	for key, value in pairs(fields or {}) do
		copy[key] = value
	end

	return copy
end

local function getPurchaseAttributionBucket(player: Player): {[string]: PurchaseAttribution}
	local bucket = purchaseAttributions[player]
	if bucket then
		return bucket
	end

	bucket = {}
	purchaseAttributions[player] = bucket
	return bucket
end

local function buildPurchaseAttributionKey(purchaseKind: string, purchaseId: any): string
	return `{toSnakeCase(purchaseKind)}:{tostring(purchaseId)}`
end

local function getPurchaseIdFieldName(purchaseKind: string): string
	local normalizedKind = toSnakeCase(purchaseKind)
	if normalizedKind == "gamepass" then
		return "pass_id"
	end
	if normalizedKind == "subscription" then
		return "subscription_id"
	end

	return "product_id"
end

local function resolvePurchaseName(purchaseKind: string, purchaseId: any): string?
	local normalizedKind = toSnakeCase(purchaseKind)
	if normalizedKind == "gamepass" then
		return ProductConfigurations.GetGamePassById(purchaseId)
	end

	if normalizedKind == "product" then
		return ProductConfigurations.GetProductById(purchaseId)
	end

	if normalizedKind == "subscription" and ProductConfigurations.GetSubscriptionById then
		return ProductConfigurations.GetSubscriptionById(purchaseId)
	end

	return nil
end

local function getPayloadPurchaseId(fields: {[string]: any}?, purchaseKind: string): any?
	if not fields then
		return nil
	end

	local normalizedKind = toSnakeCase(purchaseKind)
	local purchaseIdField = getPurchaseIdFieldName(normalizedKind)
	local rawId = fields[purchaseIdField]
	if normalizedKind == "subscription" then
		if type(rawId) == "string" and rawId ~= "" then
			return rawId
		end
		local numericId = tonumber(rawId)
		if type(numericId) == "number" and numericId > 0 then
			return tostring(math.floor(numericId))
		end
		return nil
	end

	local numericId = tonumber(rawId)
	if type(numericId) == "number" and numericId > 0 then
		return math.floor(numericId)
	end
	return nil
end

local function pruneExpiredPurchaseAttributions(player: Player)
	local bucket = purchaseAttributions[player]
	if not bucket then
		return
	end

	local now = os.clock()
	for key, entry in pairs(bucket) do
		if entry.ExpiresAt <= now then
			bucket[key] = nil
		end
	end
end

local function cachePurchaseAttribution(player: Player, purchaseKind: string, purchaseId: any, fields: {[string]: any}?)
	if purchaseId == nil or tostring(purchaseId) == "" then
		return
	end

	local bucket = getPurchaseAttributionBucket(player)
	bucket[buildPurchaseAttributionKey(purchaseKind, purchaseId)] = {
		ExpiresAt = os.clock() + PURCHASE_ATTRIBUTION_TTL,
		Fields = shallowCopyFields(sanitizeCustomFields(fields)),
	}
end

local function getPurchaseAttribution(player: Player, purchaseKind: string, purchaseId: any, consume: boolean): {[string]: any}?
	if purchaseId == nil or tostring(purchaseId) == "" then
		return nil
	end

	pruneExpiredPurchaseAttributions(player)

	local bucket = purchaseAttributions[player]
	if not bucket then
		return nil
	end

	local key = buildPurchaseAttributionKey(purchaseKind, purchaseId)
	local entry = bucket[key]
	if not entry then
		return nil
	end

	if consume then
		bucket[key] = nil
	end

	return shallowCopyFields(entry.Fields)
end

local function getPlayerSessions(player: Player): {[string]: SessionState}
	local sessions = activeSessions[player]
	if sessions then
		return sessions
	end

	sessions = {}
	activeSessions[player] = sessions
	return sessions
end

local function clearRecurringSession(player: Player, funnelKey: string)
	local sessions = activeSessions[player]
	if sessions then
		sessions[funnelKey] = nil
	end
end

local function clearPurchaseAttribution(player: Player, purchaseKind: string, purchaseId: any)
	if purchaseId == nil or tostring(purchaseId) == "" then
		return
	end

	local bucket = purchaseAttributions[player]
	if not bucket then
		return
	end

	bucket[buildPurchaseAttributionKey(purchaseKind, purchaseId)] = nil
end

local function getShortGuidToken(): string
	return HttpService:GenerateGUID(false):gsub("%-", ""):sub(1, 12)
end

local function buildSessionId(player: Player, prefix: string, suffix: string): string
	local cleanPrefix = tostring(prefix):gsub("[^%w]", ""):sub(1, 8)
	local cleanSuffix = tostring(suffix):gsub("[^%w_]", "")
	local base = `u{player.UserId}_{cleanPrefix}_`
	local maxSuffixLength = math.max(1, 50 - #base)

	if #cleanSuffix > maxSuffixLength then
		cleanSuffix = cleanSuffix:sub(1, maxSuffixLength)
	end

	return base .. cleanSuffix
end

local function getOneTimeSessionId(player: Player, funnelKey: string): string
	return buildSessionId(player, "once", funnelKey)
end

local function getOneTimeStep(profile: any, funnelKey: string): number
	local analyticsData = ensureAnalyticsData(profile)
	local funnelConfig = OneTimeFunnels[funnelKey]
	local storedStep = tonumber(analyticsData.OneTime[funnelKey]) or 0

	if funnelConfig and type(funnelConfig.LegacyOneTimeKeys) == "table" then
		for _, legacyKey in ipairs(funnelConfig.LegacyOneTimeKeys) do
			storedStep = math.max(storedStep, tonumber(analyticsData.OneTime[legacyKey]) or 0)
		end
	end

	if funnelConfig and funnelConfig.LegacyKey then
		storedStep = math.max(storedStep, tonumber(profile.Data[funnelConfig.LegacyKey]) or 0)
	end

	local maxStep = funnelConfig and #funnelConfig.Steps or storedStep
	return math.clamp(storedStep, 0, maxStep)
end

local function setOneTimeStep(profile: any, funnelKey: string, step: number)
	local analyticsData = ensureAnalyticsData(profile)
	analyticsData.OneTime[funnelKey] = step

	local funnelConfig = OneTimeFunnels[funnelKey]
	if funnelConfig and type(funnelConfig.LegacyOneTimeKeys) == "table" then
		for _, legacyKey in ipairs(funnelConfig.LegacyOneTimeKeys) do
			analyticsData.OneTime[legacyKey] = nil
		end
	end

	if funnelConfig and funnelConfig.LegacyKey then
		profile.Data[funnelConfig.LegacyKey] = step
	end
end

local function hasMarker(profile: any, markerKey: string): boolean
	local analyticsData = ensureAnalyticsData(profile)
	return analyticsData.Markers[markerKey] == true
end

local function setMarker(profile: any, markerKey: string)
	local analyticsData = ensureAnalyticsData(profile)
	analyticsData.Markers[markerKey] = true
end

local function safeLogCustomEvent(player: Player, eventName: string, value: number?, customFields: {[string]: any}?)
	local success, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, eventName, value or 1, sanitizeCustomFields(customFields))
	end)
	if not success then
		warn(`[AnalyticsFunnelsService] Failed to log custom event {eventName} for {player.Name}: {err}`)
		return false
	end

	return true
end

local function safeLogOnboardingStep(player: Player, step: number, stepName: string, customFields: {[string]: any}?)
	local success, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName, customFields)
	end)
	if not success then
		warn(`[AnalyticsFunnelsService] Failed to log onboarding step {stepName} for {player.Name}: {err}`)
		return false
	end

	return true
end

local function safeLogFunnelStep(
	player: Player,
	funnelName: string,
	funnelSessionId: string,
	step: number,
	stepName: string,
	customFields: {[string]: any}?
)
	local success, err = pcall(function()
		AnalyticsService:LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields)
	end)
	if not success then
		warn(`[AnalyticsFunnelsService] Failed to log funnel step {funnelName}/{stepName} for {player.Name}: {err}`)
		return false
	end

	return true
end

local function advanceOneTimeFunnel(player: Player, funnelKey: string, targetStep: number, firstStepFields: {[string]: any}?): boolean
	local profile = getProfile(player)
	local funnelConfig = OneTimeFunnels[funnelKey]
	if not profile or not funnelConfig then
		return false
	end

	local clampedTarget = math.clamp(targetStep, 1, #funnelConfig.Steps)
	local currentStep = getOneTimeStep(profile, funnelKey)
	if clampedTarget <= currentStep then
		return false
	end

	for step = currentStep + 1, clampedTarget do
		local stepName = funnelConfig.Steps[step]
		local customFields = if step == 1 then buildFirstStepFields(player, firstStepFields) else nil
		local logged = false

		if funnelConfig.Kind == "Onboarding" then
			logged = safeLogOnboardingStep(player, step, stepName, customFields)
		else
			logged = safeLogFunnelStep(
				player,
				funnelConfig.FunnelName,
				getOneTimeSessionId(player, funnelKey),
				step,
				stepName,
				customFields
			)
		end

		if not logged then
			return false
		end

		setOneTimeStep(profile, funnelKey, step)
	end

	return true
end

local function logOneTimeMarkerEvent(player: Player, markerKey: string, eventName: string, customFields: {[string]: any}?): boolean
	local profile = getProfile(player)
	if not profile or hasMarker(profile, markerKey) then
		return false
	end

	local logged = safeLogCustomEvent(player, eventName, 1, buildFirstStepFields(player, customFields))
	if not logged then
		return false
	end

	setMarker(profile, markerKey)
	return true
end

local function startRecurringSession(player: Player, funnelKey: string, sessionId: string, firstStepFields: {[string]: any}?): boolean
	local funnelConfig = RecurringFunnels[funnelKey]
	if not funnelConfig then
		return false
	end

	local sessions = getPlayerSessions(player)
	local session = sessions[funnelKey]
	if not session or session.SessionId ~= sessionId then
		session = {
			SessionId = sessionId,
			Step = 0,
		}
		sessions[funnelKey] = session
	end

	if session.Step >= 1 then
		return false
	end

	local logged = safeLogFunnelStep(
		player,
		funnelConfig.FunnelName,
		session.SessionId,
		1,
		funnelConfig.Steps[1],
		buildFirstStepFields(player, firstStepFields)
	)
	if not logged then
		return false
	end

	session.Step = 1
	return true
end

local function advanceRecurringFunnel(player: Player, funnelKey: string, targetStep: number): boolean
	local funnelConfig = RecurringFunnels[funnelKey]
	if not funnelConfig then
		return false
	end

	local sessions = getPlayerSessions(player)
	local session = sessions[funnelKey]
	if not session then
		return false
	end

	local clampedTarget = math.clamp(targetStep, 1, #funnelConfig.Steps)
	if clampedTarget <= session.Step then
		return false
	end

	for step = session.Step + 1, clampedTarget do
		local logged = safeLogFunnelStep(player, funnelConfig.FunnelName, session.SessionId, step, funnelConfig.Steps[step], nil)
		if not logged then
			return false
		end

		session.Step = step
	end

	if funnelConfig.ClearOnComplete and session.Step >= #funnelConfig.Steps then
		clearRecurringSession(player, funnelKey)
	end

	return true
end

-- Used by tutorial automation paths that should record the terminal conversion
-- without synthesizing intermediate click steps.
local function logRecurringFunnelStepWithoutBackfill(player: Player, funnelKey: string, targetStep: number): boolean
	local funnelConfig = RecurringFunnels[funnelKey]
	if not funnelConfig then
		return false
	end

	local sessions = getPlayerSessions(player)
	local session = sessions[funnelKey]
	if not session then
		return false
	end

	local clampedTarget = math.clamp(targetStep, 1, #funnelConfig.Steps)
	if clampedTarget <= session.Step then
		return false
	end

	local logged = safeLogFunnelStep(
		player,
		funnelConfig.FunnelName,
		session.SessionId,
		clampedTarget,
		funnelConfig.Steps[clampedTarget],
		nil
	)
	if not logged then
		return false
	end

	session.Step = clampedTarget
	if funnelConfig.ClearOnComplete and session.Step >= #funnelConfig.Steps then
		clearRecurringSession(player, funnelKey)
	end

	return true
end

local function hasSpinAvailable(profile: any): boolean
	local spins = tonumber(profile.Data.SpinNumber) or 0
	if spins > 0 then
		return true
	end

	local lastFreeSpin = tonumber(profile.Data.LastDailySpin) or 0
	return (os.time() - lastFreeSpin) >= FREE_SPIN_COOLDOWN_SECONDS
end

local function getCurrentDayKey(): number
	return math.floor(os.time() / SECONDS_PER_DAY)
end

local function getDailyRewardSessionId(player: Player): string
	return buildSessionId(player, "daily", tostring(getCurrentDayKey()))
end

local function getPlaytimeRewardSessionId(player: Player, dayKey: number): string
	return buildSessionId(player, "play", tostring(dayKey))
end

local function getRebirthSessionId(player: Player, targetRebirth: number): string
	return buildSessionId(player, "rebirth", tostring(targetRebirth))
end

local function getDailySpinSessionId(player: Player): string
	local profile = getProfile(player)
	if not profile then
		return buildSessionId(player, "spin", getShortGuidToken())
	end

	local lastDailySpin = tonumber(profile.Data.LastDailySpin) or 0
	local spins = tonumber(profile.Data.SpinNumber) or 0
	return buildSessionId(player, "spin", `{lastDailySpin}_{spins}`)
end

local function getGuidSessionId(player: Player, prefix: string): string
	return buildSessionId(player, prefix, getShortGuidToken())
end

local function getBrainrotCollectionFunnelStep(totalCollected: number): number
	local collectedCount = math.max(0, math.floor(tonumber(totalCollected) or 0))
	local targetStep = 1

	for step, threshold in ipairs(BRAINROT_COLLECTION_STEP_THRESHOLDS) do
		if collectedCount >= threshold then
			targetStep = step
		else
			break
		end
	end

	return targetStep
end

local function canAdvanceOneTime(player: Player, funnelKey: string, requiredStep: number): boolean
	local profile = getProfile(player)
	if not profile then
		return false
	end

	return getOneTimeStep(profile, funnelKey) >= requiredStep
end

local function getRebirthInfo(player: Player): (number, number, number, boolean)
	local profile = getProfile(player)
	if not profile then
		return 0, 0, 1, false
	end

	local rebirths = tonumber(profile.Data.Rebirths) or 0
	local money = tonumber(profile.Data.Money) or 0
	local targetRebirth = rebirths + 1
	local requirement = RebirthRequirements.Get(targetRebirth)
	local cost = requirement and (tonumber(requirement.soft_required) or 0) or 0

	return money, cost, targetRebirth, requirement ~= nil
end

local function buildStoreFields(player: Player, payload: {[string]: any}?): {[string]: any}?
	local fields = shallowCopyFields(payload)
	fields.surface = if type(fields.surface) == "string" and fields.surface ~= "" then toSnakeCase(fields.surface) else nil
	fields.section = if type(fields.section) == "string" and fields.section ~= "" then toSnakeCase(fields.section) else nil
	fields.entrypoint = if type(fields.entrypoint) == "string" and fields.entrypoint ~= "" then toSnakeCase(fields.entrypoint) else nil

	if type(fields.offer_key) ~= "string" or fields.offer_key == "" then
		fields.offer_key = if type(fields.offerKey) == "string" and fields.offerKey ~= "" then fields.offerKey else nil
	end
	fields.offer_key = if type(fields.offer_key) == "string" then toSnakeCase(fields.offer_key) else nil
	fields.offerKey = nil

	if type(fields.action) == "string" then
		fields.action = toSnakeCase(fields.action)
	end

	if type(fields.reason) == "string" then
		fields.reason = toSnakeCase(fields.reason)
	end

	if type(fields.purchase_kind) ~= "string" or fields.purchase_kind == "" then
		fields.purchase_kind = if type(fields.purchaseKind) == "string" and fields.purchaseKind ~= "" then fields.purchaseKind else nil
	end
	fields.purchase_kind = if type(fields.purchase_kind) == "string" then toSnakeCase(fields.purchase_kind) else nil
	fields.purchaseKind = nil

	if type(fields.payment_type) ~= "string" or fields.payment_type == "" then
		fields.payment_type = if type(fields.paymentType) == "string" and fields.paymentType ~= "" then fields.paymentType else nil
	end
	fields.payment_type = if type(fields.payment_type) == "string" then toSnakeCase(fields.payment_type) else nil
	fields.paymentType = nil

	local productName = nil
	if type(fields.product_name) == "string" and fields.product_name ~= "" then
		productName = fields.product_name
	elseif type(fields.productName) == "string" and fields.productName ~= "" then
		productName = fields.productName
	end
	fields.productName = nil

	local productId = tonumber(fields.product_id or fields.productId)
	fields.productId = nil
	local passId = tonumber(fields.pass_id or fields.passId)
	fields.passId = nil
	local subscriptionId = fields.subscription_id or fields.subscriptionId
	fields.subscriptionId = nil
	fields.subscription_id = nil

	if type(fields.id) == "number" then
		if fields.purchase_kind == "gamepass" then
			passId = passId or fields.id
		elseif fields.purchase_kind == "subscription" then
			subscriptionId = subscriptionId or fields.id
		else
			productId = productId or fields.id
		end
	elseif type(fields.id) == "string" and fields.purchase_kind == "subscription" then
		subscriptionId = subscriptionId or fields.id
	end
	fields.id = nil

	if type(productId) == "number" and productId > 0 then
		fields.product_id = math.floor(productId)
	elseif type(passId) == "number" and passId > 0 then
		fields.pass_id = math.floor(passId)
	else
		if type(subscriptionId) == "number" and subscriptionId > 0 then
			fields.subscription_id = tostring(math.floor(subscriptionId))
		elseif type(subscriptionId) == "string" and subscriptionId ~= "" then
			fields.subscription_id = subscriptionId
		end
	end

	local resolvedName = productName
	if type(resolvedName) ~= "string" or resolvedName == "" then
		if type(fields.pass_id) == "number" then
			resolvedName = resolvePurchaseName("gamepass", fields.pass_id)
		elseif type(fields.product_id) == "number" then
			resolvedName = resolvePurchaseName("product", fields.product_id)
		elseif type(fields.subscription_id) == "string" then
			resolvedName = resolvePurchaseName("subscription", fields.subscription_id)
		end
	end

	fields.product_name = if type(resolvedName) == "string" and resolvedName ~= "" then resolvedName else nil

	if type(fields.purchase_kind) ~= "string" or fields.purchase_kind == "" then
		if type(fields.pass_id) == "number" then
			fields.purchase_kind = "gamepass"
		elseif type(fields.product_id) == "number" then
			fields.purchase_kind = "product"
		elseif type(fields.subscription_id) == "string" then
			fields.purchase_kind = "subscription"
		end
	end

	if type(fields.payment_type) ~= "string" or fields.payment_type == "" then
		if fields.purchase_kind == "product" or fields.purchase_kind == "gamepass" then
			fields.payment_type = "robux"
		elseif fields.purchase_kind == "subscription" then
			fields.payment_type = "subscription"
		end
	end

	return sanitizeCustomFields(fields)
end

function AnalyticsFunnelsService:LogFailure(player: Player, reason: string, customFields: {[string]: any}?)
	safeLogCustomEvent(player, reason, 1, buildFirstStepFields(player, customFields))
end

function AnalyticsFunnelsService:SyncTutorial(player: Player, tutorialStep: number)
	local profile = getProfile(player)
	if not profile then
		return
	end

	local tutorialFunnelConfig = OneTimeFunnels[TUTORIAL_FUNNEL_KEY]
	local funnelFinalStep = tutorialFunnelConfig and #tutorialFunnelConfig.Steps or TutorialConfiguration.FinalStep
	local funnelStep = math.clamp(tutorialStep, 1, funnelFinalStep)
	local currentFunnelStep = getOneTimeStep(profile, TUTORIAL_FUNNEL_KEY)
	local tutorialSkipped = isTutorialSkipped(profile)

	if not tutorialSkipped
		and currentFunnelStep <= 0
		and tutorialStep > 0
		and tutorialStep < TutorialConfiguration.FinalStep then
		logOneTimeMarkerEvent(player, TUTORIAL_ENTERED_MARKER_KEY, "tutorial_entered", {
			zone = "tutorial",
		})
	end

	if tutorialSkipped and tutorialStep >= TutorialConfiguration.FinalStep then
		return
	end

	if advanceOneTimeFunnel(player, TUTORIAL_FUNNEL_KEY, funnelStep, {
		zone = "tutorial",
	}) and tutorialStep >= TutorialConfiguration.FinalStep then
		advanceOneTimeFunnel(player, "EarlyProgressionToFirstRebirth", 1, {
			zone = "base",
		})
	end
end

function AnalyticsFunnelsService:HandleTutorialCompleted(player: Player)
	local profile = getProfile(player)
	if not profile or isTutorialSkipped(profile) or hasMarker(profile, TUTORIAL_SKIPPED_MARKER_KEY) then
		return
	end

	logOneTimeMarkerEvent(player, TUTORIAL_COMPLETED_MARKER_KEY, "tutorial_completed", {
		zone = "tutorial",
	})
end

function AnalyticsFunnelsService:HandleTutorialSkipped(player: Player, skippedStep: number)
	local profile = getProfile(player)
	if not profile or hasMarker(profile, TUTORIAL_COMPLETED_MARKER_KEY) then
		return
	end

	logOneTimeMarkerEvent(player, TUTORIAL_SKIPPED_MARKER_KEY, "tutorial_skipped", {
		zone = "tutorial",
		skip_step = math.max(1, math.floor(tonumber(skippedStep) or 1)),
	})
end

function AnalyticsFunnelsService:HandleBrainrotsCollectedChanged(player: Player, totalCollected: number)
	local collectedCount = math.max(0, math.floor(tonumber(totalCollected) or 0))
	advanceOneTimeFunnel(player, BRAINROT_COLLECTION_FUNNEL_KEY, getBrainrotCollectionFunnelStep(collectedCount), {
		zone = "game",
		brainrots_collected = collectedCount,
	})
end

function AnalyticsFunnelsService:HandleMoneyBalanceChanged(player: Player)
	local money, cost, targetRebirth, hasRequirement = getRebirthInfo(player)
	if not hasRequirement or money < cost then
		return
	end

	startRecurringSession(player, "RebirthConversion", getRebirthSessionId(player, targetRebirth), {
		zone = "base",
		target_rebirth = targetRebirth,
	})
end

function AnalyticsFunnelsService:HandleExtraSlotsBought(player: Player, newUnlockedSlots: number)
	if canAdvanceOneTime(player, "EarlyProgressionToFirstRebirth", 1) then
		advanceOneTimeFunnel(player, "EarlyProgressionToFirstRebirth", 2, {
			zone = "base",
			unlocked_slots = newUnlockedSlots,
		})
	end
end

function AnalyticsFunnelsService:HandleSlotUpgraded(player: Player, floorName: string, slotName: string, upgradeId: string)
	if canAdvanceOneTime(player, "EarlyProgressionToFirstRebirth", 2) then
		advanceOneTimeFunnel(player, "EarlyProgressionToFirstRebirth", 3, {
			zone = "base",
			upgrade_id = upgradeId,
		})
	end

	if canAdvanceOneTime(player, "BaseEconomyActivation", 3) then
		advanceOneTimeFunnel(player, "BaseEconomyActivation", 4, {
			zone = "base",
			upgrade_id = upgradeId,
			floor = floorName,
			slot = slotName,
		})
	end
end

function AnalyticsFunnelsService:HandleStatUpgradePurchased(player: Player, upgradeId: string, paymentType: string?, surface: string?)
	advanceRecurringFunnel(player, "StatUpgradesConversion", 4)
	safeLogCustomEvent(player, "stat_upgrade_purchase_success", 1, buildFirstStepFields(player, {
		zone = "base",
		upgrade_id = upgradeId,
		payment_type = if type(paymentType) == "string" then toSnakeCase(paymentType) else nil,
		surface = if type(surface) == "string" then toSnakeCase(surface) else nil,
	}))
end

function AnalyticsFunnelsService:HandleBombPurchased(player: Player, pickaxeName: string, paymentType: string?, surface: string?)
	local bombTier = getBombTierFromName(pickaxeName)
	if canAdvanceOneTime(player, "EarlyProgressionToFirstRebirth", 3) and bombTier >= 3 then
		advanceOneTimeFunnel(player, "EarlyProgressionToFirstRebirth", 4, {
			zone = "base",
			bomb_tier = bombTier,
			payment_type = if type(paymentType) == "string" then toSnakeCase(paymentType) else nil,
			surface = if type(surface) == "string" then toSnakeCase(surface) else nil,
		})
	end

	advanceRecurringFunnel(player, "BombShopConversion", 4)
end

function AnalyticsFunnelsService:HandleBombTutorialAutoPurchased(player: Player)
	logRecurringFunnelStepWithoutBackfill(player, "BombShopConversion", 4)
end

function AnalyticsFunnelsService:HandleMineZoneEntered(player: Player)
	startRecurringSession(player, "MineRunLoop", getGuidSessionId(player, "mine-run"), {
		zone = "mine",
	})
end

function AnalyticsFunnelsService:HandleMineBombThrown(player: Player)
	advanceRecurringFunnel(player, "MineRunLoop", 2)
end

function AnalyticsFunnelsService:HandleMineBrainrotPickedUp(player: Player)
	advanceRecurringFunnel(player, "MineRunLoop", 3)
end

function AnalyticsFunnelsService:HandleMineZoneExited(player: Player, hadItems: boolean)
	if hadItems then
		advanceRecurringFunnel(player, "MineRunLoop", 4)
	end
end

function AnalyticsFunnelsService:HandleMineExitToolGranted(player: Player)
	advanceRecurringFunnel(player, "MineRunLoop", 5)
end

function AnalyticsFunnelsService:HandlePlaceBrainrot(player: Player)
	advanceRecurringFunnel(player, "MineRunLoop", 6)
	advanceOneTimeFunnel(player, "BaseEconomyActivation", 1, {
		zone = "base",
	})
end

function AnalyticsFunnelsService:HandleSellSuccess(player: Player, actionType: string, soldCount: number)
	if soldCount > 0 then
		advanceRecurringFunnel(player, "MineRunLoop", 6)
	end

	safeLogCustomEvent(player, "sell_success", 1, buildFirstStepFields(player, {
		zone = "base",
		sell_action = actionType,
		sold_count = soldCount,
	}))
end

function AnalyticsFunnelsService:HandleStoredCashPositive(player: Player, floorName: string, slotName: string)
	if canAdvanceOneTime(player, "BaseEconomyActivation", 1) then
		advanceOneTimeFunnel(player, "BaseEconomyActivation", 2, {
			zone = "base",
			floor = floorName,
			slot = slotName,
		})
	end
end

function AnalyticsFunnelsService:HandleManualCollect(player: Player, amount: number)
	if amount > 0 and canAdvanceOneTime(player, "BaseEconomyActivation", 2) then
		advanceOneTimeFunnel(player, "BaseEconomyActivation", 3, {
			zone = "base",
		})
	end
end

function AnalyticsFunnelsService:HandleBombShopOpened(player: Player)
	startRecurringSession(player, "BombShopConversion", getGuidSessionId(player, "bomb-shop"), {
		zone = "base",
	})
end

function AnalyticsFunnelsService:HandleBombSelected(player: Player, pickaxeName: string)
	local sessions = getPlayerSessions(player)
	if not sessions.BombShopConversion then
		return
	end

	advanceRecurringFunnel(player, "BombShopConversion", 2)
	safeLogCustomEvent(player, "bomb_shop_selection", 1, buildFirstStepFields(player, {
		zone = "base",
		target_bomb_tier = getBombTierFromName(pickaxeName),
	}))
end

function AnalyticsFunnelsService:HandleBombPurchaseRequested(player: Player, pickaxeName: string, paymentType: string?, surface: string?)
	local sessions = getPlayerSessions(player)
	if not sessions.BombShopConversion then
		if type(paymentType) ~= "string" or toSnakeCase(paymentType) ~= "robux" then
			return
		end
	end

	if sessions.BombShopConversion then
		advanceRecurringFunnel(player, "BombShopConversion", 3)
	end

	local normalizedPaymentType = if type(paymentType) == "string" then toSnakeCase(paymentType) else "soft"
	local normalizedSurface = if type(surface) == "string" then toSnakeCase(surface) else nil
	safeLogCustomEvent(player, "bomb_shop_buy_pressed", 1, buildFirstStepFields(player, {
		zone = "base",
		target_bomb_tier = getBombTierFromName(pickaxeName),
		payment_type = normalizedPaymentType,
		surface = normalizedSurface,
	}))

	if normalizedPaymentType == "robux" then
		local bombConfig = BombsConfigurations.Bombs[pickaxeName]
		local productId = bombConfig and tonumber(bombConfig.RobuxProductId) or nil
		if type(productId) == "number" and productId > 0 then
			self:HandleStoreOfferPrompted(player, {
				surface = normalizedSurface or "pickaxes",
				section = "bombs",
				entrypoint = "robux_button",
				productName = pickaxeName,
				productId = productId,
				purchaseKind = "product",
				paymentType = "robux",
			})
		end
	end
end

function AnalyticsFunnelsService:HandleUpgradesOpened(player: Player)
	startRecurringSession(player, "StatUpgradesConversion", getGuidSessionId(player, "upgrades"), {
		zone = "base",
	})
end

function AnalyticsFunnelsService:HandleUpgradePurchaseRequested(player: Player, upgradeId: string, paymentType: string?, surface: string?)
	local sessions = getPlayerSessions(player)
	if not sessions.StatUpgradesConversion then
		if type(paymentType) ~= "string" or toSnakeCase(paymentType) ~= "robux" then
			return
		end
	end

	if sessions.StatUpgradesConversion then
		advanceRecurringFunnel(player, "StatUpgradesConversion", 3)
	end

	local normalizedPaymentType = if type(paymentType) == "string" then toSnakeCase(paymentType) else "soft"
	local normalizedSurface = if type(surface) == "string" then toSnakeCase(surface) else nil
	safeLogCustomEvent(player, "upgrade_buy_pressed", 1, buildFirstStepFields(player, {
		zone = "base",
		upgrade_id = upgradeId,
		payment_type = normalizedPaymentType,
		surface = normalizedSurface,
	}))

	if normalizedPaymentType == "robux" then
		local upgradeConfig = getUpgradeConfigById(upgradeId)
		local productId = upgradeConfig and tonumber(upgradeConfig.RobuxProductId) or nil
		if type(productId) == "number" and productId > 0 then
			self:HandleStoreOfferPrompted(player, {
				surface = normalizedSurface or "upgrades",
				section = "upgrades",
				entrypoint = "robux_button",
				productName = upgradeId,
				productId = productId,
				purchaseKind = "product",
				paymentType = "robux",
			})
		end
	end
end

function AnalyticsFunnelsService:HandleUpgradeSelected(player: Player, upgradeId: string)
	local sessions = getPlayerSessions(player)
	if not sessions.StatUpgradesConversion then
		return
	end

	advanceRecurringFunnel(player, "StatUpgradesConversion", 2)
	safeLogCustomEvent(player, "upgrade_selected", 1, buildFirstStepFields(player, {
		zone = "base",
		upgrade_id = upgradeId,
	}))
end

function AnalyticsFunnelsService:HandleRebirthUIOpened(player: Player)
	local money, cost, targetRebirth, hasRequirement = getRebirthInfo(player)
	if not hasRequirement or money < cost then
		return
	end

	startRecurringSession(player, "RebirthConversion", getRebirthSessionId(player, targetRebirth), {
		zone = "base",
		target_rebirth = targetRebirth,
	})
	advanceRecurringFunnel(player, "RebirthConversion", 2)
end

function AnalyticsFunnelsService:HandleRebirthRequested(player: Player)
	local money, cost, targetRebirth, hasRequirement = getRebirthInfo(player)
	if not hasRequirement or money < cost then
		return
	end

	local sessions = getPlayerSessions(player)
	local session = sessions.RebirthConversion
	if not session or session.SessionId ~= getRebirthSessionId(player, targetRebirth) then
		return
	end

	advanceRecurringFunnel(player, "RebirthConversion", 3)
end

function AnalyticsFunnelsService:HandleRebirthSuccess(player: Player, newRebirthCount: number)
	local targetRebirth = math.max(1, newRebirthCount)
	local sessionId = getRebirthSessionId(player, targetRebirth)
	local sessions = getPlayerSessions(player)
	local session = sessions.RebirthConversion
	if session and session.SessionId == sessionId then
		advanceRecurringFunnel(player, "RebirthConversion", 4)
	end

	if canAdvanceOneTime(player, "EarlyProgressionToFirstRebirth", 4) and newRebirthCount >= 1 then
		advanceOneTimeFunnel(player, "EarlyProgressionToFirstRebirth", 5, {
			zone = "base",
		})
	end
end

function AnalyticsFunnelsService:HandleDailyRewardStatus(player: Player, status: any)
	if not status or status.CanClaim ~= true then
		return
	end

	startRecurringSession(player, "DailyRewardClaim", getDailyRewardSessionId(player), {
		zone = "base",
		reward_day = status.ClaimDay,
		reward_id = status.ClaimDay,
	})
end

function AnalyticsFunnelsService:HandleDailyRewardsOpened(player: Player)
	local profile = getProfile(player)
	if not profile then
		return
	end

	local status = DailyRewardManager.GetStatus(profile.Data)
	if status.CanClaim ~= true then
		return
	end

	startRecurringSession(player, "DailyRewardClaim", getDailyRewardSessionId(player), {
		zone = "base",
		reward_day = status.ClaimDay,
		reward_id = status.ClaimDay,
	})
	advanceRecurringFunnel(player, "DailyRewardClaim", 2)
end

function AnalyticsFunnelsService:HandleDailyRewardClaimAttempt(player: Player, day: number)
	local sessions = getPlayerSessions(player)
	if not sessions.DailyRewardClaim then
		return
	end

	advanceRecurringFunnel(player, "DailyRewardClaim", 3)
	safeLogCustomEvent(player, "daily_reward_claim_clicked", 1, buildFirstStepFields(player, {
		zone = "base",
		reward_day = day,
		reward_id = day,
	}))
end

function AnalyticsFunnelsService:HandleDailyRewardClaimSuccess(player: Player, day: number)
	advanceRecurringFunnel(player, "DailyRewardClaim", 4)
	safeLogCustomEvent(player, "daily_reward_claim_success", 1, buildFirstStepFields(player, {
		zone = "base",
		reward_day = day,
		reward_id = day,
	}))
end

function AnalyticsFunnelsService:HandleDailyRewardClaimFailure(player: Player, day: number, reason: string)
	local normalizedReason = toSnakeCase(reason)
	safeLogCustomEvent(player, "daily_reward_claim_failure", 1, buildFirstStepFields(player, {
		zone = "base",
		reward_day = day,
		reward_id = day,
		reason = normalizedReason,
	}))

	if normalizedReason == "reward_locked" then
		self:LogFailure(player, "reward_locked", {
			zone = "base",
			funnel = "DailyRewardClaim",
			reward_day = day,
			reward_id = day,
		})
	end
end

function AnalyticsFunnelsService:HandlePlaytimeRewardStatus(player: Player, status: any)
	if not status or not status.ClaimableRewardIds or #status.ClaimableRewardIds <= 0 then
		return
	end

	startRecurringSession(player, "PlaytimeRewards", getPlaytimeRewardSessionId(player, status.DayKey), {
		zone = "base",
		reward_id = status.ClaimableRewardIds[1],
	})
end

function AnalyticsFunnelsService:HandlePlaytimeRewardsOpened(player: Player)
	local profile = getProfile(player)
	if not profile then
		return
	end

	local status = PlaytimeRewardManager.GetStatus(profile.Data)
	if not status.ClaimableRewardIds or #status.ClaimableRewardIds <= 0 then
		return
	end

	startRecurringSession(player, "PlaytimeRewards", getPlaytimeRewardSessionId(player, status.DayKey), {
		zone = "base",
		reward_id = status.ClaimableRewardIds[1],
	})
	advanceRecurringFunnel(player, "PlaytimeRewards", 2)
end

function AnalyticsFunnelsService:HandlePlaytimeRewardClaimSuccess(player: Player, rewardId: number, status: any)
	advanceRecurringFunnel(player, "PlaytimeRewards", 3)

	local claimedCount = 0
	for _, claimed in pairs(status.ClaimedRewards or {}) do
		if claimed == true then
			claimedCount += 1
		end
	end

	if claimedCount >= 2 then
		advanceRecurringFunnel(player, "PlaytimeRewards", 4)
	end

	if claimedCount >= #(status.Rewards or {}) and #(status.Rewards or {}) > 0 then
		advanceRecurringFunnel(player, "PlaytimeRewards", 5)
	end

	safeLogCustomEvent(player, "playtime_reward_claim_success", 1, buildFirstStepFields(player, {
		zone = "base",
		reward_id = rewardId,
	}))
end

function AnalyticsFunnelsService:HandlePlaytimeRewardClaimFailure(player: Player, rewardId: number, reason: string)
	local normalizedReason = toSnakeCase(reason)
	safeLogCustomEvent(player, "playtime_reward_claim_failure", 1, buildFirstStepFields(player, {
		zone = "base",
		reward_id = rewardId,
		reason = normalizedReason,
	}))

	if normalizedReason == "reward_locked" then
		self:LogFailure(player, "reward_locked", {
			zone = "base",
			funnel = "PlaytimeRewards",
			reward_id = rewardId,
		})
	end
end

function AnalyticsFunnelsService:HandleDailySpinWheelOpened(player: Player)
	local profile = getProfile(player)
	if not profile or not hasSpinAvailable(profile) then
		return
	end

	self:HandleDailySpinAvailable(player)
	advanceRecurringFunnel(player, "DailySpin", 2)
end

function AnalyticsFunnelsService:HandleDailySpinAvailable(player: Player)
	local profile = getProfile(player)
	if not profile or not hasSpinAvailable(profile) then
		return
	end

	startRecurringSession(player, "DailySpin", getDailySpinSessionId(player), {
		zone = "base",
	})
end

function AnalyticsFunnelsService:HandleDailySpinAttempt(player: Player)
	local sessions = getPlayerSessions(player)
	if not sessions.DailySpin then
		return
	end

	advanceRecurringFunnel(player, "DailySpin", 3)
end

function AnalyticsFunnelsService:HandleDailySpinRewardGranted(player: Player, rewardData: any)
	advanceRecurringFunnel(player, "DailySpin", 4)

	safeLogCustomEvent(player, "daily_spin_reward_granted", 1, buildFirstStepFields(player, {
		zone = "base",
		reward_id = rewardData.Name or rewardData.Type or "Unknown",
	}))

	self:HandleDailySpinAvailable(player)
end

function AnalyticsFunnelsService:HandleDailySpinNoSpins(player: Player)
	self:LogFailure(player, "no_spins_available", {
		zone = "base",
		funnel = "DailySpin",
	})
end

function AnalyticsFunnelsService:HandleGroupRewardRejected(player: Player)
	self:LogFailure(player, "not_in_group", {
		zone = "base",
		funnel = "GroupReward",
	})
end

function AnalyticsFunnelsService:HandleCodesOpened(player: Player)
	safeLogCustomEvent(player, "codes_opened", 1, buildFirstStepFields(player, {
		zone = "base",
	}))
end

function AnalyticsFunnelsService:HandleStoreOpened(player: Player, payload: {[string]: any}?)
	local fields = buildStoreFields(player, payload)
	if fields then
		fields.surface = fields.surface or "unknown"
		fields.section = fields.section or "unknown"
		fields.entrypoint = fields.entrypoint or "unknown"
	end
	safeLogCustomEvent(player, "store_opened", 1, buildFirstStepFields(player, fields))
end

function AnalyticsFunnelsService:HandleStoreOfferPrompted(player: Player, payload: {[string]: any}?)
	local fields = buildStoreFields(player, payload)
	if fields then
		fields.surface = fields.surface or "unknown"
		fields.section = fields.section or "unknown"
		fields.entrypoint = fields.entrypoint or "unknown"
	end
	safeLogCustomEvent(player, "store_offer_prompted", 1, buildFirstStepFields(player, fields))

	local purchaseKind = fields and fields.purchase_kind
	local purchaseId = if type(purchaseKind) == "string" then getPayloadPurchaseId(fields, purchaseKind) else nil
	if type(purchaseKind) == "string" and purchaseId ~= nil then
		cachePurchaseAttribution(player, purchaseKind, purchaseId, fields)
	end

	if fields and fields.product_name == "SkipRebirth" then
		safeLogCustomEvent(player, "skip_rebirth_prompted", 1, buildFirstStepFields(player, fields))
	end
end

function AnalyticsFunnelsService:HandleStorePromptFailed(player: Player, payload: {[string]: any}?)
	local fields = buildStoreFields(player, payload)
	if fields then
		fields.surface = fields.surface or "unknown"
		fields.section = fields.section or "unknown"
		fields.entrypoint = fields.entrypoint or "unknown"
		local purchaseKind = fields.purchase_kind
		local purchaseId = if type(purchaseKind) == "string" then getPayloadPurchaseId(fields, purchaseKind) else nil
		if type(purchaseKind) == "string" and purchaseId ~= nil then
			clearPurchaseAttribution(player, purchaseKind, purchaseId)
		end
	end
	safeLogCustomEvent(player, "store_prompt_failed", 1, buildFirstStepFields(player, fields))
end

function AnalyticsFunnelsService:HandleStorePurchaseSuccess(player: Player, payload: {[string]: any}?)
	local baseFields = buildStoreFields(player, payload)
	local purchaseKind = baseFields and baseFields.purchase_kind or "product"
	local purchaseId = getPayloadPurchaseId(baseFields, purchaseKind)
	local attributedFields = if purchaseId ~= nil then getPurchaseAttribution(player, purchaseKind, purchaseId, true) else nil
	local mergedFields = shallowCopyFields(attributedFields)

	for key, value in pairs(baseFields or {}) do
		if value ~= nil then
			mergedFields[key] = value
		end
	end

	if type(mergedFields.surface) ~= "string" or mergedFields.surface == "" then
		mergedFields.surface = "unknown"
	end
	if type(mergedFields.product_name) ~= "string" or mergedFields.product_name == "" then
		mergedFields.product_name = "Unknown"
	end

	safeLogCustomEvent(player, "store_purchase_success", 1, buildFirstStepFields(player, mergedFields))

	if mergedFields.product_name == "SkipRebirth" then
		safeLogCustomEvent(player, "skip_rebirth_success", 1, buildFirstStepFields(player, mergedFields))
	end
end

function AnalyticsFunnelsService:HandleAutoBombToggleRequested(player: Player, surface: string, enabled: boolean)
	autoBombToggleSurfaces[player] = {
		Surface = toSnakeCase(surface),
		ExpiresAt = os.clock() + 30,
	}
	safeLogCustomEvent(player, "auto_bomb_toggle_requested", 1, buildFirstStepFields(player, {
		zone = "base",
		surface = toSnakeCase(surface),
		enabled = enabled,
	}))
end

function AnalyticsFunnelsService:HandleAutoBombToggleSuccess(player: Player, surface: string?, enabled: boolean)
	local resolvedSurface = if type(surface) == "string" and surface ~= "" then toSnakeCase(surface) else "unknown"
	local storedRequest = autoBombToggleSurfaces[player]
	if storedRequest and storedRequest.ExpiresAt > os.clock() then
		resolvedSurface = storedRequest.Surface
	end
	autoBombToggleSurfaces[player] = nil

	safeLogCustomEvent(player, "auto_bomb_toggle_success", 1, buildFirstStepFields(player, {
		zone = "base",
		surface = resolvedSurface,
		enabled = enabled,
	}))
end

function AnalyticsFunnelsService:HandleContextualOfferShown(player: Player, offerKey: string, payload: {[string]: any}?)
	local resolvedOfferKey = offerKey
	if type(payload) == "table" then
		if type(payload.ResolvedOfferKey) == "string" and payload.ResolvedOfferKey ~= "" then
			resolvedOfferKey = payload.ResolvedOfferKey
		elseif type(payload.resolvedOfferKey) == "string" and payload.resolvedOfferKey ~= "" then
			resolvedOfferKey = payload.resolvedOfferKey
		end
	end

	safeLogCustomEvent(player, "contextual_offer_shown", 1, buildFirstStepFields(player, {
		zone = "base",
		offer_key = toSnakeCase(offerKey),
		resolved_offer_key = toSnakeCase(resolvedOfferKey),
	}))
end

function AnalyticsFunnelsService:HandleContextualOfferClicked(player: Player, payload: {[string]: any}?)
	local rawOfferKey = if type(payload) == "table" then payload.offerKey else nil
	local resolvedOfferKey = if type(payload) == "table" then payload.resolvedOfferKey else nil
	local action = if type(payload) == "table" then payload.action else nil
	safeLogCustomEvent(player, "contextual_offer_clicked", 1, buildFirstStepFields(player, {
		zone = "base",
		offer_key = toSnakeCase(rawOfferKey),
		resolved_offer_key = toSnakeCase(resolvedOfferKey or rawOfferKey),
		action = toSnakeCase(action),
	}))
end

function AnalyticsFunnelsService:HandleProductTouchPrompted(player: Player, payload: {[string]: any}?)
	local productId = type(payload) == "table" and tonumber(payload.productId) or nil
	local productName = type(payload) == "table" and payload.productName or nil
	local isLimited = type(payload) == "table" and payload.limited == true or false

	safeLogCustomEvent(player, "product_touch_prompted", 1, buildFirstStepFields(player, {
		zone = "mine",
		product_name = productName or "Unknown",
		product_id = productId,
		limited = isLimited,
	}))

	self:HandleStoreOfferPrompted(player, {
		surface = "product_touch",
		section = "world",
		entrypoint = "touch",
		productName = productName,
		productId = productId,
		purchaseKind = "product",
		paymentType = "robux",
	})
end

function AnalyticsFunnelsService:HandleRewardBulkClaimClicked(player: Player, surface: string)
	safeLogCustomEvent(player, "reward_bulk_claim_clicked", 1, buildFirstStepFields(player, {
		zone = "base",
		surface = toSnakeCase(surface),
	}))
end

function AnalyticsFunnelsService:HandlePromoCodeRedeemAttempt(player: Player, codeId: string)
	safeLogCustomEvent(player, "promo_code_redeem_attempt", 1, buildFirstStepFields(player, {
		zone = "base",
		code_id = if codeId ~= "" then codeId else "Unknown",
	}))
end

function AnalyticsFunnelsService:HandlePromoCodeRedeemSuccess(player: Player, codeId: string, rewardType: string?)
	safeLogCustomEvent(player, "promo_code_redeem_success", 1, buildFirstStepFields(player, {
		zone = "base",
		code_id = if codeId ~= "" then codeId else "Unknown",
		reward_type = if type(rewardType) == "string" and rewardType ~= "" then toSnakeCase(rewardType) else nil,
	}))
end

function AnalyticsFunnelsService:HandlePromoCodeRedeemFailure(player: Player, codeId: string, reason: string)
	safeLogCustomEvent(player, "promo_code_redeem_failure", 1, buildFirstStepFields(player, {
		zone = "base",
		code_id = if codeId ~= "" then codeId else "Unknown",
		reason = toSnakeCase(reason),
	}))
end

function AnalyticsFunnelsService:HandleLuckyBlockOpenStarted(player: Player, blockId: string)
	safeLogCustomEvent(player, "lucky_block_open_started", 1, buildFirstStepFields(player, {
		zone = "base",
		block_id = blockId,
		source = "slot",
	}))
end

function AnalyticsFunnelsService:HandleLuckyBlockOpenReward(player: Player, blockId: string, rewardItem: string, rewardRarity: string?)
	safeLogCustomEvent(player, "lucky_block_open_reward", 1, buildFirstStepFields(player, {
		zone = "base",
		block_id = blockId,
		reward_item = rewardItem,
		reward_rarity = if type(rewardRarity) == "string" and rewardRarity ~= "" then rewardRarity else nil,
		source = "slot",
	}))
end

function AnalyticsFunnelsService:HandleGroupRewardClaimAttempt(player: Player, source: string?)
	safeLogCustomEvent(player, "group_reward_claim_attempt", 1, buildFirstStepFields(player, {
		zone = "base",
		source = if type(source) == "string" and source ~= "" then toSnakeCase(source) else "unknown",
	}))
end

function AnalyticsFunnelsService:HandleGroupRewardClaimSuccess(player: Player, source: string?)
	safeLogCustomEvent(player, "group_reward_claim_success", 1, buildFirstStepFields(player, {
		zone = "base",
		source = if type(source) == "string" and source ~= "" then toSnakeCase(source) else "unknown",
	}))
end

function AnalyticsFunnelsService:HandleGroupRewardClaimFailure(player: Player, source: string?, reason: string)
	safeLogCustomEvent(player, "group_reward_claim_failure", 1, buildFirstStepFields(player, {
		zone = "base",
		source = if type(source) == "string" and source ~= "" then toSnakeCase(source) else "unknown",
		reason = toSnakeCase(reason),
	}))
end

function AnalyticsFunnelsService:HandleAutoGroupRewardGranted(player: Player)
	safeLogCustomEvent(player, "group_reward_auto_granted", 1, buildFirstStepFields(player, {
		zone = "base",
		source = "onboarding",
	}))
end

function AnalyticsFunnelsService:ReportIntent(player: Player, intentName: string, payload: any)
	if intentName == "BombShopOpened" then
		self:HandleBombShopOpened(player)
	elseif intentName == "BombSelected" and type(payload) == "table" and type(payload.pickaxeName) == "string" then
		self:HandleBombSelected(player, payload.pickaxeName)
	elseif intentName == "BombPurchaseRequested" and type(payload) == "table" and type(payload.pickaxeName) == "string" then
		self:HandleBombPurchaseRequested(player, payload.pickaxeName, payload.paymentType, payload.surface)
	elseif intentName == "UpgradeSelected" and type(payload) == "table" and type(payload.upgradeId) == "string" then
		self:HandleUpgradeSelected(player, payload.upgradeId)
	elseif intentName == "UpgradePurchaseRequested" and type(payload) == "table" and type(payload.upgradeId) == "string" then
		self:HandleUpgradePurchaseRequested(player, payload.upgradeId, payload.paymentType, payload.surface)
	elseif intentName == "UpgradesOpened" then
		self:HandleUpgradesOpened(player)
	elseif intentName == "RebirthUIOpened" then
		self:HandleRebirthUIOpened(player)
	elseif intentName == "DailyRewardsOpened" then
		self:HandleDailyRewardsOpened(player)
	elseif intentName == "PlaytimeRewardsOpened" then
		self:HandlePlaytimeRewardsOpened(player)
	elseif intentName == "CodesOpened" then
		self:HandleCodesOpened(player)
	elseif intentName == "DailySpinWheelOpened" then
		self:HandleDailySpinWheelOpened(player)
	elseif intentName == "StoreOpened" and type(payload) == "table" then
		self:HandleStoreOpened(player, payload)
	elseif intentName == "StoreOfferPrompted" and type(payload) == "table" then
		self:HandleStoreOfferPrompted(player, payload)
	elseif intentName == "StorePromptFailed" and type(payload) == "table" then
		self:HandleStorePromptFailed(player, payload)
	elseif intentName == "AutoBombToggleRequested" and type(payload) == "table" then
		self:HandleAutoBombToggleRequested(player, payload.surface or "unknown", payload.enabled == true)
	elseif intentName == "ContextualOfferClicked" and type(payload) == "table" then
		self:HandleContextualOfferClicked(player, payload)
	elseif intentName == "ProductTouchPrompted" and type(payload) == "table" then
		self:HandleProductTouchPrompted(player, payload)
	elseif intentName == "RewardBulkClaimClicked" and type(payload) == "table" then
		self:HandleRewardBulkClaimClicked(player, payload.surface or "unknown")
	end
end

function AnalyticsFunnelsService:Init(controllers)
	if initialized then
		return
	end
	initialized = true

	PlayerController = controllers.PlayerController

	local events = ReplicatedStorage:WaitForChild("Events")
	reportIntentEvent = events:FindFirstChild("ReportAnalyticsIntent") :: RemoteEvent
	if not reportIntentEvent then
		reportIntentEvent = Instance.new("RemoteEvent")
		reportIntentEvent.Name = "ReportAnalyticsIntent"
		reportIntentEvent.Parent = events
	end

	reportIntentEvent.OnServerEvent:Connect(function(player, intentName, payload)
		if type(intentName) == "string" then
			self:ReportIntent(player, intentName, payload)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		activeSessions[player] = nil
		purchaseAttributions[player] = nil
		autoBombToggleSurfaces[player] = nil
	end)
end

return AnalyticsFunnelsService
