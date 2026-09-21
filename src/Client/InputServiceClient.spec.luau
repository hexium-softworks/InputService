--!strict
--[=[
	@class InputServiceClient.spec
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputServiceClient = require("InputServiceClient")
local InputServiceConstants = require("InputServiceConstants")
local Jest = require("Jest")

local describe = Jest.Globals.describe
local expect = Jest.Globals.expect
local it = Jest.Globals.it

local function canCreateInputActionInstances(): boolean
	local ok, instance = pcall(Instance.new, InputServiceConstants.CONTEXT_CLASS_NAME, nil)
	if ok and typeof(instance) == "Instance" then
		instance:Destroy()
		return true
	end

	return false
end

local function canCreateInputActionLabel(): boolean
	local ok, instance = pcall(Instance.new, "InputActionLabel")
	if ok and typeof(instance) == "Instance" then
		instance:Destroy()
		return true
	end

	return false
end

local function newClient()
	local service = setmetatable({}, { __index = InputServiceClient }) :: any
	service:Init({} :: any)
	return service
end

describe("InputServiceClient", function()
	it("guards unsupported runtimes", function()
		expect(typeof(canCreateInputActionInstances())).toEqual("boolean")
	end)

	if canCreateInputActionInstances() then
		it("caches action signals and disconnects them on destroy", function()
			local existingRoot = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
			if existingRoot then
				existingRoot:Destroy()
			end

			local service = newClient()
			service:DefineLocalContext({
				Name = "SpecContext",
				Actions = {
					{ Name = "SpecAction" },
				},
			})

			local firstSignals = service:GetActionSignals("SpecContext", "SpecAction")
			local secondSignals = service:GetActionSignals("SpecContext", "SpecAction")
			local connection = service:BindPressed("SpecContext", "SpecAction", function() end)

			expect(firstSignals == secondSignals).toEqual(true)
			expect(connection:IsConnected()).toEqual(true)

			service:Destroy()

			expect(connection:IsConnected()).toEqual(false)

			local root = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
			if root then
				root:Destroy()
			end
		end)

		it("returns display info from binding overrides", function()
			local existingRoot = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
			if existingRoot then
				existingRoot:Destroy()
			end

			local service = newClient()
			service:DefineLocalContext({
				Name = "SpecContext",
				Actions = {
					{
						Name = "SpecAction",
						Bindings = {
							{
								Name = "Keyboard",
								KeyCode = Enum.KeyCode.E,
								DisplayName = "Use",
							},
						},
					},
				},
			})

			local binding = service:GetBinding("SpecContext", "SpecAction", "Keyboard")
			local info = InputServiceClient.GetDisplayInfoForBinding(binding)

			expect(info.Text).toEqual("Use")
			expect(info.HasText).toEqual(true)
			expect(info.TextSource).toEqual("DisplayName")

			service:Destroy()

			local root = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
			if root then
				root:Destroy()
			end
		end)

		if canCreateInputActionLabel() then
			it("creates InputActionLabels attached to actions", function()
				local existingRoot = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
				if existingRoot then
					existingRoot:Destroy()
				end

				local service = newClient()
				service:DefineLocalContext({
					Name = "SpecContext",
					Actions = {
						{ Name = "SpecAction" },
					},
				})

				local action = service:GetAction("SpecContext", "SpecAction")
				local label = service:CreateActionLabel("SpecContext", "SpecAction", {
					Name = "SpecLabel",
					Visible = false,
				})

				expect(label.Name).toEqual("SpecLabel")
				expect(label.Visible).toEqual(false)
				expect(label.InputAction).toEqual(action)

				label:Destroy()
				service:Destroy()

				local root = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
				if root then
					root:Destroy()
				end
			end)
		end

		it("wires multi-press helpers through action signals", function()
			local existingRoot = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
			if existingRoot then
				existingRoot:Destroy()
			end

			local service = newClient()
			service:DefineLocalContext({
				Name = "SpecContext",
				Actions = {
					{ Name = "SpecAction" },
				},
			})

			local fireCount = 0
			local maid = service:BindMultiPressed("SpecContext", "SpecAction", {
				WindowSeconds = 1,
			}, function()
				fireCount += 1
			end)

			local signals = service:GetActionSignals("SpecContext", "SpecAction")
			signals.Pressed:Fire()
			signals.Pressed:Fire()

			expect(fireCount).toEqual(1)

			maid:DoCleaning()
			service:Destroy()

			local root = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
			if root then
				root:Destroy()
			end
		end)

		it("wires action sequence helpers through action signals", function()
			local existingRoot = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
			if existingRoot then
				existingRoot:Destroy()
			end

			local service = newClient()
			service:DefineLocalContext({
				Name = "SpecContext",
				Actions = {
					{ Name = "First" },
					{ Name = "Second" },
				},
			})

			local fireCount = 0
			local maid = service:BindActionSequence({
				{ ContextName = "SpecContext", ActionName = "First" },
				{ ContextName = "SpecContext", ActionName = "Second" },
			}, {
				WindowSeconds = 1,
			}, function()
				fireCount += 1
			end)

			service:GetActionSignals("SpecContext", "First").Pressed:Fire()
			service:GetActionSignals("SpecContext", "Second").Pressed:Fire()

			expect(fireCount).toEqual(1)

			maid:DoCleaning()
			service:Destroy()

			local root = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
			if root then
				root:Destroy()
			end
		end)
	end
end)
