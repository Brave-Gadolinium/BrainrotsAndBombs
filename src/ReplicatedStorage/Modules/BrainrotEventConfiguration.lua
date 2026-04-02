--!strict

local BrainrotEventConfiguration = {}

export type EventDefinition = {
	Id: string,
	Rarity: string,
	Message: string,
}

BrainrotEventConfiguration.EventTypes = {
	{
		Id = "Mythic",
		Rarity = "Mythic",
		Message = "Mythic Brainrot spawned! Go get it!",
	},
	{
		Id = "Secret",
		Rarity = "Secret",
		Message = "Secret Brainrot spawned! Hurry!",
	},
	{
		Id = "Brainrotgod",
		Rarity = "Brainrotgod",
		Message = "Brainrot God spawned! Only one wins!",
	},
} :: {EventDefinition}

BrainrotEventConfiguration.RoundSpawnDelaySeconds = 30
BrainrotEventConfiguration.SpawnZoneName = "Zone5"
BrainrotEventConfiguration.DefaultMutation = "Normal"

BrainrotEventConfiguration.WorkspaceAttributes = {
	Active = "BrainrotEventActive",
	Message = "BrainrotEventMessage",
	Token = "BrainrotEventToken",
	ItemName = "BrainrotEventItemName",
	Rarity = "BrainrotEventRarity",
	CarrierUserId = "BrainrotEventCarrierUserId",
}

BrainrotEventConfiguration.ItemAttributes = {
	IsEventBrainrot = "IsEventBrainrot",
	Token = "EventBrainrotToken",
	Rarity = "EventBrainrotRarity",
	ItemName = "EventBrainrotItemName",
}

function BrainrotEventConfiguration.GetEventDefinition(eventId: string?): EventDefinition?
	if type(eventId) ~= "string" or eventId == "" then
		return nil
	end

	for _, definition in ipairs(BrainrotEventConfiguration.EventTypes) do
		if definition.Id == eventId then
			return definition
		end
	end

	return nil
end

function BrainrotEventConfiguration.GetEventTypeIds(): {string}
	local ids = {}

	for _, definition in ipairs(BrainrotEventConfiguration.EventTypes) do
		table.insert(ids, definition.Id)
	end

	return ids
end

return BrainrotEventConfiguration
