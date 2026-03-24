--!strict
local RarityConfigurations = {
	Common = {
		DisplayName = "Common",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(50, 50, 50),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 100, 100)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 200, 200)),
		})
	},
	Uncommon = {
		DisplayName = "Uncommon",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(44, 90, 67),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(83, 170, 127)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(85, 255, 142)),
		})
	},
	Rare = {
		DisplayName = "Rare",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(0, 67, 100),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 255)),
		})
	},
	Epic = {
		DisplayName = "Epic",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(125, 0, 125),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 255)),
		})
	},
	Legendary = {
		DisplayName = "Legendary",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(125, 0, 0),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 0)),
		})
	},
	Mythical = {
		DisplayName = "Mythical",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(100, 33, 50),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 127)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 170, 127)),
		})
	},
}

return RarityConfigurations