--!strict

local PlotRuntimeBridge = {}

local refreshHandler: ((Player) -> ())? = nil

function PlotRuntimeBridge.SetRefreshHandler(handler: (Player) -> ())
	refreshHandler = handler
end

function PlotRuntimeBridge.RefreshPlayerPlot(player: Player)
	if refreshHandler then
		refreshHandler(player)
	end
end

return PlotRuntimeBridge
