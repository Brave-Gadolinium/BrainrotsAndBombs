--!strict
-- LOCATION: ReplicatedStorage/Modules/MutationConfigurations

local MutationConfigurations = {
	Normal = {
		DisplayName = "Normal",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(0, 0, 0),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(155, 155, 155)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
		})
	},
	Neon = {
		DisplayName = "Neon",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(25, 75, 0),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(85, 255, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 0)),
		})
	},
	Ruby = {
		DisplayName = "Ruby",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(145, 0, 0),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 85, 127)),
		})
	},
	Diamond = {
		DisplayName = "Diamond",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(0, 53, 80),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 170, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 255, 255)),
		})
	},
	Golden = {
		DisplayName = "Golden",
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeColor = Color3.fromRGB(120, 78, 0),
		StrokeThickness = 3,
		GradientColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 170, 0)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 0)),
		})
	},
}

return MutationConfigurations