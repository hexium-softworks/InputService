--!strict
--[=[
	Client-local temporal gesture helpers for InputService.

	These helpers are intentionally pure so the timing rules can be tested
	without Roblox input instances.

	@class InputServiceGestureUtils
]=]

local require = require(script.Parent.loader).load(script)

local InputServiceTypes = require("InputServiceTypes")

type InputActionRef = InputServiceTypes.InputActionRef
type MultiPressOptions = InputServiceTypes.MultiPressOptions
type ActionSequenceOptions = InputServiceTypes.ActionSequenceOptions
type TimedOptions = {
	WindowSeconds: number?,
	CooldownSeconds: number?,
}

local InputServiceGestureUtils = {}

local DEFAULT_PRESS_COUNT = 2
local DEFAULT_WINDOW_SECONDS = 1
local DEFAULT_COOLDOWN_SECONDS = 0

local function validatePositiveNumber(value: number, fieldName: string): ()
	assert(typeof(value) == "number", string.format("%s must be a number", fieldName))
	assert(value > 0, string.format("%s must be greater than 0", fieldName))
end

local function validateNonNegativeNumber(value: number, fieldName: string): ()
	assert(typeof(value) == "number", string.format("%s must be a number", fieldName))
	assert(value >= 0, string.format("%s must be greater than or equal to 0", fieldName))
end

local function isSameActionRef(ref: InputActionRef, contextName: string, actionName: string): boolean
	return ref.ContextName == contextName and ref.ActionName == actionName
end

local function getPressCount(options: MultiPressOptions?): number
	local pressCount = if options and options.PressCount ~= nil then options.PressCount else DEFAULT_PRESS_COUNT

	assert(typeof(pressCount) == "number", "PressCount must be a number")
	assert(pressCount >= 2, "PressCount must be at least 2")
	assert(pressCount % 1 == 0, "PressCount must be an integer")

	return pressCount
end

local function getWindowSeconds(options: TimedOptions?): number
	local windowSeconds = DEFAULT_WINDOW_SECONDS
	if options and options.WindowSeconds ~= nil then
		windowSeconds = options.WindowSeconds
	end

	validatePositiveNumber(windowSeconds, "WindowSeconds")

	return windowSeconds
end

local function getCooldownSeconds(options: TimedOptions?): number
	local cooldownSeconds = DEFAULT_COOLDOWN_SECONDS
	if options and options.CooldownSeconds ~= nil then
		cooldownSeconds = options.CooldownSeconds
	end

	validateNonNegativeNumber(cooldownSeconds, "CooldownSeconds")

	return cooldownSeconds
end

function InputServiceGestureUtils.createMultiPressTracker(
	options: MultiPressOptions?,
	callback: () -> ()
): (number) -> boolean
	assert(typeof(callback) == "function", "Callback must be a function")

	local pressCountGoal = getPressCount(options)
	local windowSeconds = getWindowSeconds(options)
	local cooldownSeconds = getCooldownSeconds(options)

	local currentPressCount = 0
	local lastPressTime: number? = nil
	local lastFireTime = -math.huge

	return function(now: number): boolean
		validateNonNegativeNumber(now, "now")

		if lastPressTime == nil or now - lastPressTime > windowSeconds then
			currentPressCount = 1
		else
			currentPressCount += 1
		end

		lastPressTime = now

		if currentPressCount < pressCountGoal then
			return false
		end

		currentPressCount = 0
		lastPressTime = nil

		if now - lastFireTime < cooldownSeconds then
			return false
		end

		lastFireTime = now
		callback()

		return true
	end
end

function InputServiceGestureUtils.validateActionSequence(sequence: { InputActionRef }): ()
	assert(typeof(sequence) == "table", "Sequence must be a table")
	assert(#sequence > 0, "Sequence must contain at least one action")

	for index, ref in sequence do
		assert(typeof(index) == "number", "Sequence must be an array")
		assert(typeof(ref) == "table", string.format("Sequence[%d] must be an action ref", index))
		assert(typeof(ref.ContextName) == "string", string.format("Sequence[%d].ContextName must be a string", index))
		assert(typeof(ref.ActionName) == "string", string.format("Sequence[%d].ActionName must be a string", index))
		assert(ref.ContextName ~= "", string.format("Sequence[%d].ContextName must not be empty", index))
		assert(ref.ActionName ~= "", string.format("Sequence[%d].ActionName must not be empty", index))
	end
end

function InputServiceGestureUtils.createActionSequenceTracker(
	sequence: { InputActionRef },
	options: ActionSequenceOptions?,
	callback: () -> ()
): (string, string, number) -> boolean
	InputServiceGestureUtils.validateActionSequence(sequence)
	assert(typeof(callback) == "function", "Callback must be a function")

	local windowSeconds = getWindowSeconds(options)
	local cooldownSeconds = getCooldownSeconds(options)
	local resetOnWrongAction = if options and options.ResetOnWrongAction ~= nil then options.ResetOnWrongAction else true
	assert(typeof(resetOnWrongAction) == "boolean", "ResetOnWrongAction must be a boolean")

	local nextIndex = 1
	local sequenceStartTime: number? = nil
	local lastFireTime = -math.huge

	local function reset()
		nextIndex = 1
		sequenceStartTime = nil
	end

	local function startFromFirstIfMatched(contextName: string, actionName: string, now: number): boolean
		if isSameActionRef(sequence[1], contextName, actionName) then
			nextIndex = 2
			sequenceStartTime = now
			return #sequence == 1
		end

		return false
	end

	return function(contextName: string, actionName: string, now: number): boolean
		assert(typeof(contextName) == "string", "Context name must be a string")
		assert(typeof(actionName) == "string", "Action name must be a string")
		validateNonNegativeNumber(now, "now")

		if sequenceStartTime ~= nil and now - sequenceStartTime > windowSeconds then
			reset()
		end

		local expected = sequence[nextIndex]
		if expected and isSameActionRef(expected, contextName, actionName) then
			if nextIndex == 1 then
				sequenceStartTime = now
			end

			if nextIndex >= #sequence then
				reset()

				if now - lastFireTime < cooldownSeconds then
					return false
				end

				lastFireTime = now
				callback()

				return true
			end

			nextIndex += 1
			return false
		end

		if resetOnWrongAction then
			reset()
			if startFromFirstIfMatched(contextName, actionName, now) then
				reset()

				if now - lastFireTime < cooldownSeconds then
					return false
				end

				lastFireTime = now
				callback()

				return true
			end
		end

		return false
	end
end

return InputServiceGestureUtils
