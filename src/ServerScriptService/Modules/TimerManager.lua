local TimerManager = {}

local FinishTime = game.ReplicatedStorage.Remotes.Timer.FinishTime

task.delay(5, function()
	while true do
		task.wait(15)
		FinishTime:Fire()
	end
end)

return TimerManager
