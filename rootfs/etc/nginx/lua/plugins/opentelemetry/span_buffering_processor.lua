------------------------------------------------------------------------------------------------------------------------
-- The span buffering processor caches spans on ngx.ctx until spans are either cleared or flushed, which should happen
-- during the request's log phase. It is modeled on the BufferedTraceProducer found in Storefront Renderer. ngx.ctx is
-- local to each individual request fielded by OpenResty, so we store the spans there, instead of on the module itself,
-- which is shared across requests.
------------------------------------------------------------------------------------------------------------------------
local ipairs = ipairs
local ngx = ngx
local setmetatable = setmetatable
local table = table

local _M = {
}

local mt = {
    __index = _M
}

------------------------------------------------------------------------------------------------------------------------
-- Create a span buffering processor.
--
-- @param[type=BatchSpanProcessor] next_span_processor batch span processor, which this processor hands off spans to
--
-- @return[type=SpanBufferingProcessor]
------------------------------------------------------------------------------------------------------------------------
function _M.new(next_span_processor)
    return setmetatable({ next_span_processor = next_span_processor }, mt)
end

------------------------------------------------------------------------------------------------------------------------
-- Handle spans ending by adding them to the ngx.ctx.
--
-- @param _self Unused parameter, needed to adhere to interface
-- @param span Span that we add to ngx.ctx
--
-- @return nil
------------------------------------------------------------------------------------------------------------------------
function _M.on_end(_self, span)
    if ngx.ctx.opentelemetry_spans then
        table.insert(ngx.ctx.opentelemetry_spans, span)
    else
        ngx.ctx.opentelemetry_spans = { span }
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Send spans to the next span processor, which should be a batch span processor.
--
-- @param update_span_ctx Whether or not we should update the span context to sample the span in.
-- Used for deferred sampling.
--
-- @return nil
------------------------------------------------------------------------------------------------------------------------
function _M:send_spans(update_span_ctx)
    for _, span in ipairs(ngx.ctx.opentelemetry_spans or {}) do
        if update_span_ctx == true then
            span:context().trace_flags = 1
        end

        self.next_span_processor:on_end(span)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Handle shutdown signals by forwarding to next span processor.
------------------------------------------------------------------------------------------------------------------------
function _M:shutdown()
    self.next_span_processor:shutdown()
end

------------------------------------------------------------------------------------------------------------------------
-- Handle force_flush by forwarding to next span processor.
------------------------------------------------------------------------------------------------------------------------
function _M:force_flush()
    self.next_span_processor:force_flush(true)
end

return _M
