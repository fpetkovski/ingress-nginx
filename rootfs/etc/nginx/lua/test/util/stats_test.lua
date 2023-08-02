local stats = require("util.stats")

describe("stats.stddev", function()
    it("should return 0 for an empty table", function()
        local values = {}
        local sd = stats.stddev(values)
        assert.is_equal(0, sd)
    end)

    it("should return 0 for a table with a single value", function()
        local values = {5}
        local sd = stats.stddev(values)
        assert.is_equal(0, sd)
    end)

    it("should calculate the correct standard deviation for a table of values", function()
        local values = {1, 2, 3, 4, 5}
        local sd = stats.stddev(values)
        assert.is_equal(1.4142135623730951455, sd)
    end)

    it("should handle negative values correctly", function()
        local values = {-1, -2, -3, -4, -5}
        local sd = stats.stddev(values)
        assert.is_equal(1.4142135623730951455, sd)
    end)

    it("should handle decimal values correctly", function()
        local values = {1.5, 2.5, 3.5, 4.5, 5.5}
        local sd = stats.stddev(values)
        assert.is_equal(1.4142135623730951455, sd)
    end)

    it("should return the value above the mean when offset is passed", function()
        local values = {1, 2, 3, 4, 5}
        local sd = stats.stddev(values, 1)
        assert.is_equal(4.4142135623730949234, sd)
    end)

    it("should return the value below the mean when offset is passed", function()
        local values = {1, 2, 3, 4, 5}
        local sd = stats.stddev(values, -1)
        assert.is_equal(1.5857864376269048545, sd)
    end)
end)

describe("stats.mean", function()
    it("should return 0 for an empty table", function()
        local values = {}
        local mean = stats.mean(values)
        assert.is_equal(0, mean)
    end)

    it("should calculate the correct mean for a table of values", function()
        local values = {1, 2, 3, 4, 5}
        local mean = stats.mean(values)
        assert.is_equal(3, mean)
    end)

    it("should handle negative values correctly", function()
        local values = {-1, -2, -3, -4, -5}
        local mean = stats.mean(values)
        assert.is_equal(-3, mean)
    end)

    it("should handle decimal values correctly", function()
        local values = {1.5, 2.5, 3.5, 4.5, 5.5}
        local mean = stats.mean(values)
        assert.is_equal(3.5, mean)
    end)
end)
