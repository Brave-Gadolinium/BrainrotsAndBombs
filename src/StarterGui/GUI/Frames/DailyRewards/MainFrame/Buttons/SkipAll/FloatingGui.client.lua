local textObject = script.Parent
local tweenService = game:GetService("TweenService")

local function tweenPosition()
	while true do
		textObject:TweenPosition(UDim2.new(textObject.Position.X.Scale, textObject.Position.X.Offset, textObject.Position.Y.Scale - 0.02, textObject.Position.Y.Offset), "Out", "Sine", 1, true)
		task.wait(1)
		textObject:TweenPosition(UDim2.new(textObject.Position.X.Scale, textObject.Position.X.Offset, textObject.Position.Y.Scale + 0.02, textObject.Position.Y.Offset), "Out", "Sine", 1, true)
		task.wait(1)
	end
end

task.spawn(tweenPosition)