local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BombToolClient = require(ReplicatedStorage.Modules:WaitForChild("BombToolClient"))

BombToolClient.Bind(script.Parent)
