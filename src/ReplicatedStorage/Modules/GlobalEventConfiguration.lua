--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UpgradesConfigurations = require(ReplicatedStorage.Modules.UpgradesConfigurations)

local GlobalEventConfiguration = {}

export type EventDefinition = {
	Id: string,
	DisplayName: string,
	RuntimeEffect: string,
	SkyboxName: string?,
	UiFrameName: string?,
	StartText: string,
	EndText: string,
	Color: Color3,
	DurationSeconds: number,
}

export type PublicState = {
	activeEventId: string?,
	endsAt: number?,
	serverNow: number,
	transition: string?,
	endedEventId: string?,
}

GlobalEventConfiguration.SchedulePeriodSeconds = 60
GlobalEventConfiguration.EventDurationSeconds = 60
GlobalEventConfiguration.SuperRunWalkSpeed = 60

GlobalEventConfiguration.WorkspaceAttributes = {
	ActiveEventId = "TimedGlobalEventId",
	EndsAt = "TimedGlobalEventEndsAt",
	ScheduleStartedAt = "TimedGlobalEventScheduleStartedAt",
}

GlobalEventConfiguration.Events = {
	{
		Id = "SuperRun",
		DisplayName = "SUPER RUN",
		RuntimeEffect = "SuperRun",
		SkyboxName = "SpeedEvent",
		UiFrameName = "SpeedEvent",
		StartText = "RUN SUPER FAST!",
		EndText = "SLOW AGAIN",
		Color = Color3.fromRGB(0, 145, 255),
		DurationSeconds = GlobalEventConfiguration.EventDurationSeconds,
	},
	{
		Id = "CarryMore",
		DisplayName = "CARRY MORE",
		RuntimeEffect = "CarryMore",
		SkyboxName = "CarryEvent",
		UiFrameName = "CarryEvent",
		StartText = "CARRY MORE BRAINROTS!",
		EndText = "CARRY LIMIT BACK",
		Color = Color3.fromRGB(28, 220, 85),
		DurationSeconds = GlobalEventConfiguration.EventDurationSeconds,
	},
	{
		Id = "TntBomb",
		DisplayName = "TNT Bomb",
		RuntimeEffect = "TntBomb",
		SkyboxName = "TNTEvent",
		UiFrameName = "TNTEvent",
		StartText = "TNT TIME!",
		EndText = "BOOM TIME OVER",
		Color = Color3.fromRGB(255, 140, 28),
		DurationSeconds = GlobalEventConfiguration.EventDurationSeconds,
	},
	{
		Id = "NukeAll",
		DisplayName = "Nuke All",
		RuntimeEffect = "NukeAll",
		SkyboxName = "NukeEvent",
		UiFrameName = "NukeEvent",
		StartText = "NUKE EVERYONE!",
		EndText = "NUKE IS GONE",
		Color = Color3.fromRGB(255, 52, 52),
		DurationSeconds = GlobalEventConfiguration.EventDurationSeconds,
	},
} :: {EventDefinition}

local eventById: {[string]: EventDefinition} = {}
for _, eventDefinition in ipairs(GlobalEventConfiguration.Events) do
	eventById[eventDefinition.Id] = eventDefinition
end

function GlobalEventConfiguration.GetEventDefinition(eventId: string?): EventDefinition?
	if type(eventId) ~= "string" or eventId == "" then
		return nil
	end

	return eventById[eventId]
end

function GlobalEventConfiguration.GetRandomEvent(randomObject: Random): EventDefinition?
	if #GlobalEventConfiguration.Events == 0 then
		return nil
	end

	return GlobalEventConfiguration.Events[randomObject:NextInteger(1, #GlobalEventConfiguration.Events)]
end

function GlobalEventConfiguration.GetMaxCarryCapacity(): number
	if UpgradesConfigurations.GetMaxCarryCapacity then
		return UpgradesConfigurations.GetMaxCarryCapacity()
	end

	return 4
end

return GlobalEventConfiguration
