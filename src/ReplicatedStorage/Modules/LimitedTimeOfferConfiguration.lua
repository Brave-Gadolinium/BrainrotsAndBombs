--!strict
-- LOCATION: ReplicatedStorage/Modules/LimitedTimeOfferConfiguration

local timerPrefix = utf8.char(40, 51, 32, 1076, 1085, 1103, 41)

local LimitedTimeOfferConfiguration = {
	Enabled = true,
	FrameName = "LimitedTimeOffer",
	OfferDurationSeconds = 3 * 24 * 60 * 60,
	TimerPrefix = timerPrefix,
	GamePassName = "CollectAll",
	PurchaseAttribute = "HasCollectAll",
	StartAttribute = "LimitedTimeOfferCollectAllStartTime",
	EndAttribute = "LimitedTimeOfferCollectAllEndTime",
	ReadyAttribute = "LimitedTimeOfferCollectAllReady",
	Surface = "limited_time_offer",
	Section = "limited_time_offer",
	Entrypoint = "collect_all_limited_time_offer",
}

return LimitedTimeOfferConfiguration
