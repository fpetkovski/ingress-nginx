-- TODO

-- local original_ngx = ngx

-- local REQUEST_METHODS_TO_BLOCK = { "GET", "OPTION", "HEAD" }

-- local function mock_ngx(mock)
--   local _ngx = mock
--   setmetatable(_ngx, { __index = ngx })
--   _G.ngx = _ngx
-- end

-- local mock_exit = spy.new(function(status)
--   assert.are.equal(400, status)
-- end)

-- local function reset_ngx()
--   _G.ngx = original_ngx
--   mock_exit:clear()
-- end

-- describe('Block reqeusts ', function()
--   before_each(function()
--     package.loaded['plugins.block_requests.main'] = nil
--   end)

--   after_each(function()
--     reset_ngx()
--   end)

--   it('dissallows any request with a blocked sni', function()
--     for _, method in ipairs(REQUEST_METHODS_TO_BLOCK) do
--       reset_ngx()
--       mock_ngx({
--         var = {
--           body_length = 1,
--           request_method = method,
--         },
--         exit = mock_exit,
--       })
--       local plugin = require('plugins.block_requests.main')
--       plugin.rewrite()

--       assert.spy(mock_exit).was.called(1)
--     end
--   end)
-- end)
