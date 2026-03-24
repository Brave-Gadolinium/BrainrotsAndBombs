--!strict
-- LOCATION: ReplicatedStorage/Modules/NumberFormatter

local NumberFormatter = {}

local SUFFIXES = {"k", "M", "B", "T", "qd", "Qn", "sx", "Sp", "O", "N", "de"}

function NumberFormatter.Format(n: number): string
	if not n then return "0" end
	n = math.floor(n)

	if n < 1000 then
		return tostring(n)
	end

	-- Calculate the index for the suffix
	local i = math.floor(math.log(n, 1000))

	-- Calculate the value to display (e.g., 1.5 for 1500)
	local v = math.pow(10, (i * 3))
	local num = n / v

	-- Format to 1 or 2 decimal places
	local text = string.format("%.1f", num)

	-- Remove .0 if it exists (e.g., "1.0k" becomes "1k")
	text = text:gsub("%.0$", "")

	-- Return formatted string (e.g., "1.5k")
	-- Fallback to scientific notation if number is huge and we run out of suffixes
	return text .. (SUFFIXES[i] or "??")
end

return NumberFormatter