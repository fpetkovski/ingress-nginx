package.path = io.popen("pwd"):read('*l') .. "/test/lua/?.lua;" .. package.path

local utils = require("plugins.opentelemetry.shopify_utils")

describe("shopify codec", function()
  it("should encode decimal to hex as string", function()
    local test_cases = {
      { '0000000000000001', '1' },
      { '000000000000000f', '15' },
      { '000000000000ffff', '65535' },
      { '00000000ffffffff', '4294967295' },
      { '00000007ffffffff', '34359738367' },
      { 'ffffffffffffffff', '18446744073709551615' }
    }

    for _, v in ipairs(test_cases) do
      assert.are.same(utils.decimal_to_hex_string(v[2]), v[1])
    end

    -- non-decimal input
    local hex, err = utils.decimal_to_hex_string('foobar')
    assert.is_nil(hex)
    assert.are.same('sscanf(foobar, ...) returned 0', err)
  end)

  it("should encode hex to decimal as number", function()
    local test_cases = {
      { '1', '1' },
      { 'ff', '255' },
      { '1', '1' },
      { 'f', '15' },
      { 'ffff', '65535' },
      { 'ffffffff', '4294967295' },
      { '00000007ffffffff', '34359738367' },
      { 'ffffffffffffffff', '18446744073709551615' }
    }
    for _, v in ipairs(test_cases) do
      assert.are.same(v[2], utils.hex_to_decimal_string(v[1]))
    end

    -- non-hex input
    local decimal, err = utils.hex_to_decimal_string('00000007fffffffz')
    assert.is_nil(decimal)
    assert.are.same('input 00000007fffffffz is an invalid hex', err)
  end)
end)

describe("w3c_baggage_to_table", function()
    it("returns empty table when string is empty", function()
        assert.are.same(utils.w3c_baggage_to_table(""), {})
    end)

    it("returns appropriate table when string has one k/v pair", function()
        assert.are.same(utils.w3c_baggage_to_table("key1=val1"), { key1 = "val1" })
    end)

    it("returns appropriate table when string has three k/v pairs", function()
        assert.are.same(utils.w3c_baggage_to_table("key1=val1;key2=val2;key3=val3"),
            { key1 = "val1", key2 = "val2", key3 = "val3" })
    end)

    it("returns empty table when input string is malformed", function()
        assert.are.same(utils.w3c_baggage_to_table("foobar"), {})
    end)

    it("returns well-formed entries when one entry is malformed", function()
        assert.are.same(utils.w3c_baggage_to_table("key1=val1;foobar"), { key1 = "val1" })
    end)
end)
