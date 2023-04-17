local _M = {}

local _M = {}

function _M.new()
    return setmetatable({
        spans = {}
    }, { __index = _M })
end

function _M.on_end(self, span)
    table.insert(self.spans, span)
end


function _M.finished_spans(self)
    return self.spans
end

return _M
