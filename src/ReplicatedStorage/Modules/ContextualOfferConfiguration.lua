--!strict
-- LOCATION: ReplicatedStorage/Modules/ContextualOfferConfiguration

local ContextualOfferConfiguration = {}

export type OfferAction = {
	Type: "Product" | "GamePass" | "OpenFrame",
	Target: string,
	ProductId: number?,
}

export type OfferDefinition = {
	Title: string,
	Description: string,
	ButtonText: string,
	BadgeText: string?,
	AccentColor: Color3,
	Action: OfferAction,
}

local DEFINITIONS: {[string]: OfferDefinition} = {
	StarterPack = {
		Title = "Starter Pack",
		Description = "Start strong with a cool bundle to help you grow faster!",
		ButtonText = "Open Offer",
		BadgeText = "Starter",
		AccentColor = Color3.fromRGB(255, 176, 64),
		Action = {
			Type = "GamePass",
			Target = "StarterPack",
		},
	},
	NukeBooster = {
		Title = "Too Many Players?",
		Description = "Clear everyone around you with one big explosion!",
		ButtonText = "Use Robux",
		BadgeText = "Power",
		AccentColor = Color3.fromRGB(255, 92, 92),
		Action = {
			Type = "Product",
			Target = "NukeBooster",
		},
	},
	Shield = {
		Title = "Got Blasted?",
		Description = "Stay safe for 10 minutes. No knockback, no ragdoll, no losing brainrot!",
		ButtonText = "Get Shield",
		BadgeText = "Defense",
		AccentColor = Color3.fromRGB(90, 196, 255),
		Action = {
			Type = "Product",
			Target = "Shield",
		},
	},
	AutoCollect = {
		Title = "Takes too long?",
		Description = "Collect your money automatically and save time!",
		ButtonText = "Unlock Pass",
		BadgeText = "Utility",
		AccentColor = Color3.fromRGB(110, 255, 170),
		Action = {
			Type = "GamePass",
			Target = "CollectAll",
		},
	},
	AutoBomb = {
		Title = "Farm Hands-Free?",
		Description = "Let your bomb throw automatically while you keep moving.",
		ButtonText = "Unlock Pass",
		BadgeText = "Automation",
		AccentColor = Color3.fromRGB(255, 214, 92),
		Action = {
			Type = "GamePass",
			Target = "AutoBomb",
		},
	},
	HackerLB = {
		Title = "Need Better Luck?",
		Description = "Grab a Hacker Lucky Block for a stronger surprise reward.",
		ButtonText = "Buy Lucky Block",
		BadgeText = "Lucky",
		AccentColor = Color3.fromRGB(96, 255, 194),
		Action = {
			Type = "Product",
			Target = "HackerLuckyBlock",
		},
	},
	BrainrotGodLB = {
		Title = "Go For The Best?",
		Description = "Buy a Brainrot God Lucky Block for a top-tier reward shot.",
		ButtonText = "Buy Lucky Block",
		BadgeText = "Premium",
		AccentColor = Color3.fromRGB(255, 120, 205),
		Action = {
			Type = "Product",
			Target = "BrainrotGodLuckyBlock",
		},
	},
	CarrySlot = {
		Title = "Need More Carry Space?",
		Description = "Buy +1 carry slot and hold more brainrots before selling.",
		ButtonText = "Buy Upgrade",
		BadgeText = "Upgrade",
		AccentColor = Color3.fromRGB(124, 184, 255),
		Action = {
			Type = "Product",
			Target = "Carry1",
			ProductId = 3567800676,
		},
	},
	BombUpgrade = {
		Title = "Block Too Strong?",
		Description = "Your bomb is too weak. Upgrade it to break this layer!",
		ButtonText = "Open Bombs",
		BadgeText = "Upgrade",
		AccentColor = Color3.fromRGB(255, 133, 70),
		Action = {
			Type = "OpenFrame",
			Target = "Pickaxes",
		},
	},
}

function ContextualOfferConfiguration.GetDefinition(offerKey: string?): OfferDefinition?
	if type(offerKey) ~= "string" or offerKey == "" then
		return nil
	end

	return DEFINITIONS[offerKey]
end

return ContextualOfferConfiguration
