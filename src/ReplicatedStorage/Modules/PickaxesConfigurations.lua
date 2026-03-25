--!strict
-- Compatibility shim for older UI/controllers that still expect PickaxesConfigurations.

local BombsConfigurations = require(script.Parent:WaitForChild("BombsConfigurations"))

return {
	Pickaxes = BombsConfigurations.Bombs,
}
