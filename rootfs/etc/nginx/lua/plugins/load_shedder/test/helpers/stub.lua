local registered_stubs = {}

function stub(t, sym, func)
  local old_func = t[sym]
  t[sym] = func
  return { unstub = function() t[sym] = old_func end }
end

function register_stub(t, sym, func)
  local s = stub(t, sym, func)
  table.insert(registered_stubs, s)
end

function reset_stubs()
  for index=#registered_stubs,1,-1 do
    local stub = registered_stubs[index]
    stub.unstub()
    table.remove(registered_stubs, index)
  end
end

function stub_now(t, use_register_stub)
  local f = function() return t; end
  if use_register_stub then
    return register_stub(ngx, 'now', f)
  else
    return stub(ngx, 'now', f)
  end
end
