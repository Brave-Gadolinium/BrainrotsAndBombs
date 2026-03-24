--!strict
-- A class for managing the cleanup of events and other objects.

local Maid = {}
Maid.__index = Maid

function Maid.new()
	local self = setmetatable({}, Maid)
	self._tasks = {}
	return self
end

function Maid:GiveTask(task: RBXScriptConnection | Instance | (() -> ()))
	if not task then
		return
	end

	local index = #self._tasks + 1
	self._tasks[index] = task
	return index
end

function Maid:DoCleaning()
	for _, task in ipairs(self._tasks) do
		if typeof(task) == "function" then
			task()
		elseif typeof(task) == "RBXScriptConnection" then
			task:Disconnect()
		elseif typeof(task) == "Instance" then
			task:Destroy()
		end
	end
	table.clear(self._tasks)
end

function Maid:Destroy()
	self:DoCleaning()
	table.clear(self)
end

return Maid