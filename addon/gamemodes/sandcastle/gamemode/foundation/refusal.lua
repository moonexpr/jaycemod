-- Refusals: a request declined for the caller's mistake, raised as a plain
-- table { refusal = true, kind, detail } so it is told apart from our own
-- bugs by value. The marker is only ever set here, and a kind is a string,
-- so a refusal raised by code loaded before a reload of any module is still
-- recognised by the code after it; nothing is compared by table identity.
local error, type = error, type
module(...)

function Raise(kind, detail)
	error({
		refusal = true,
		kind = kind,
		detail = detail,
	}, 0)
end

-- Whether err is a refusal of one of kinds, a set of kind strings.
function Is(err, kinds)
	return type(err) == "table" and err.refusal == true and kinds[err.kind] == true
end

function Message(err)
	return err.kind .. ": " .. err.detail
end

-- The message of a refusal of one of kinds; anything else, our bug, is
-- rethrown unchanged.
function Explain(err, kinds)
	if not Is(err, kinds) then error(err, 0) end
	return Message(err)
end
