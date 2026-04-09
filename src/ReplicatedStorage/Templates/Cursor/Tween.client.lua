local TweenService = game:GetService("TweenService")

local imageLabel = script.Parent

local originalSize = imageLabel.Size
local shrinkSize = originalSize - UDim2.fromScale(0.5, 0.5)

local tweenInfo = TweenInfo.new(
	0.8, -- длительность
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	0, -- без repeat (мы сами будем лупить цикл)
	false
)

local function tweenTo(size)
	local tween = TweenService:Create(imageLabel, tweenInfo, {
		Size = size
	})
	tween:Play()
	return tween
end

while true do
	local t1 = tweenTo(shrinkSize)
	t1.Completed:Wait()

	local t2 = tweenTo(originalSize)
	t2.Completed:Wait()
end