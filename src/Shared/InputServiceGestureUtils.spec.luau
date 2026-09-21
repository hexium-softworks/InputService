--!strict
--[=[
	@class InputServiceGestureUtils.spec
]=]

local require = require(script.Parent.loader).load(script)

local InputServiceGestureUtils = require("InputServiceGestureUtils")
local Jest = require("Jest")

local describe = Jest.Globals.describe
local expect = Jest.Globals.expect
local it = Jest.Globals.it

describe("InputServiceGestureUtils", function()
	it("fires a double press inside the window", function()
		local fireCount = 0
		local tracker = InputServiceGestureUtils.createMultiPressTracker({
			WindowSeconds = 1,
		}, function()
			fireCount += 1
		end)

		expect(tracker(0)).toEqual(false)
		expect(tracker(0.5)).toEqual(true)
		expect(fireCount).toEqual(1)
	end)

	it("resets a double press after the window", function()
		local fireCount = 0
		local tracker = InputServiceGestureUtils.createMultiPressTracker({
			WindowSeconds = 1,
		}, function()
			fireCount += 1
		end)

		tracker(0)
		expect(tracker(1.25)).toEqual(false)
		expect(fireCount).toEqual(0)
	end)

	it("supports triple press", function()
		local fireCount = 0
		local tracker = InputServiceGestureUtils.createMultiPressTracker({
			PressCount = 3,
			WindowSeconds = 1,
		}, function()
			fireCount += 1
		end)

		expect(tracker(0)).toEqual(false)
		expect(tracker(0.25)).toEqual(false)
		expect(tracker(0.5)).toEqual(true)
		expect(fireCount).toEqual(1)
	end)

	it("fires ordered action sequences", function()
		local fireCount = 0
		local tracker = InputServiceGestureUtils.createActionSequenceTracker({
			{ ContextName = "Gameplay", ActionName = "Dash" },
			{ ContextName = "Gameplay", ActionName = "Jump" },
		}, {
			WindowSeconds = 1,
		}, function()
			fireCount += 1
		end)

		expect(tracker("Gameplay", "Dash", 0)).toEqual(false)
		expect(tracker("Gameplay", "Jump", 0.5)).toEqual(true)
		expect(fireCount).toEqual(1)
	end)

	it("resets ordered sequences on wrong actions", function()
		local fireCount = 0
		local tracker = InputServiceGestureUtils.createActionSequenceTracker({
			{ ContextName = "Gameplay", ActionName = "Dash" },
			{ ContextName = "Gameplay", ActionName = "Jump" },
		}, {
			WindowSeconds = 1,
		}, function()
			fireCount += 1
		end)

		tracker("Gameplay", "Dash", 0)
		tracker("Gameplay", "Reload", 0.25)
		expect(tracker("Gameplay", "Jump", 0.5)).toEqual(false)
		expect(fireCount).toEqual(0)
	end)

	it("supports repeated same-action sequences", function()
		local fireCount = 0
		local tracker = InputServiceGestureUtils.createActionSequenceTracker({
			{ ContextName = "Gameplay", ActionName = "Map" },
			{ ContextName = "Gameplay", ActionName = "Map" },
		}, {
			WindowSeconds = 1,
		}, function()
			fireCount += 1
		end)

		expect(tracker("Gameplay", "Map", 0)).toEqual(false)
		expect(tracker("Gameplay", "Map", 0.4)).toEqual(true)
		expect(fireCount).toEqual(1)
	end)

	it("suppresses repeated fires during cooldown", function()
		local fireCount = 0
		local tracker = InputServiceGestureUtils.createMultiPressTracker({
			WindowSeconds = 1,
			CooldownSeconds = 2,
		}, function()
			fireCount += 1
		end)

		expect(tracker(0)).toEqual(false)
		expect(tracker(0.25)).toEqual(true)
		expect(tracker(0.5)).toEqual(false)
		expect(tracker(0.75)).toEqual(false)
		expect(fireCount).toEqual(1)
	end)
end)
