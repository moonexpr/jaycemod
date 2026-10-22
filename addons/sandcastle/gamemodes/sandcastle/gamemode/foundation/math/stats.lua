-- Summary figures of a list of numbers. An empty list's figures are 0.
local ceil, ipairs, max, sort, unpack = math.ceil, ipairs, math.max, table.sort, unpack
module(...)

function Mean(list)
	if #list == 0 then return 0 end
	local sum = 0
	for _, v in ipairs(list) do sum = sum + v end
	return sum / #list
end

-- The nearest-rank percentile: the value at rank ceil(p * n), p in [0, 1].
-- The list is left in its order.
function Percentile(list, p)
	if #list == 0 then return 0 end
	local sorted = { unpack(list) }
	sort(sorted)
	return sorted[max(1, ceil(p * #sorted))]
end
