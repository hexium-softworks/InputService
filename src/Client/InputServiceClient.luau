--!strict
--[=[
	Client-side helpers for Roblox Input Action System contexts.

	Client mutations are local convenience only. They are non-authoritative and
	are not replicated to the server through this package.

	@class InputServiceClient
]=]

local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Maid = require("Maid")
local ServiceBag = require("ServiceBag")
local Signal = require("Signal")

local InputServiceConstants = require("InputServiceConstants")
local InputServiceInstanceUtils = require("InputServiceInstanceUtils")
local InputServiceTypes = require("InputServiceTypes")

type ServiceBag = ServiceBag.ServiceBag
type InputContextConfig = InputServiceTypes.InputContextConfig
type InputActionConfig = InputServiceTypes.InputActionConfig
type InputBindingConfig = InputServiceTypes.InputBindingConfig
type InputActionState = InputServiceTypes.InputActionState
type ActionSignalBundle = InputServiceTypes.ActionSignalBundle
type BindingDisplayInfo = InputServiceTypes.BindingDisplayInfo

local InputServiceClient = {}
InputServiceClient.ServiceName = "InputServiceClient"

local BINDING_DISPLAY_PROPERTIES = { "DisplayName", "DisplayImage", "KeyCode", "UIButton" }

export type InputServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag,
		_maid: Maid.Maid,
		_rootFolder: Folder?,
		_actionSignals: { [InputAction]: ActionSignalBundle },
	},
	{} :: typeof({ __index = InputServiceClient })
))

local function findRootFolder(): Folder?
	local child = ReplicatedStorage:FindFirstChild(InputServiceConstants.ROOT_FOLDER_NAME)
	if child == nil then
		return nil
	end

	assert(
		child:IsA(InputServiceConstants.ROOT_FOLDER_CLASS_NAME),
		string.format("%s must be a %s", child:GetFullName(), InputServiceConstants.ROOT_FOLDER_CLASS_NAME)
	)

	return child :: Folder
end

local function getContentNone(): any?
	local ok, value = pcall(function()
		return Content.none
	end)

	if ok then
		return value
	end

	return nil
end

local function contentFromUri(uri: string): any?
	local ok, value = pcall(function()
		return Content.fromUri(uri)
	end)

	if ok then
		return value
	end

	return nil
end

local function isEmptyKeyCode(keyCode: any): boolean
	if typeof(keyCode) ~= "EnumItem" then
		return true
	end

	return keyCode.Name == "Unknown" or keyCode.Name == "None"
end

local function hasDisplayImage(displayImage: any): boolean
	if displayImage == nil then
		return false
	elseif typeof(displayImage) == "string" then
		return displayImage ~= ""
	end

	local ok, sourceType = pcall(function()
		return displayImage.SourceType
	end)

	if not ok then
		return true
	end

	local noneOk, noneSourceType = pcall(function()
		return Enum.ContentSourceType.None
	end)

	return not noneOk or sourceType ~= noneSourceType
end

local function createActionSignalBundle(action: InputAction): ActionSignalBundle
	local maid = Maid.new()

	local bundle = {
		Pressed = Signal.new(),
		Released = Signal.new(),
		StateChanged = Signal.new(),
		EnabledChanged = Signal.new(),
		PreferredBindingChanged = Signal.new(),
	} :: any

	maid:GiveTask(bundle.Pressed)
	maid:GiveTask(bundle.Released)
	maid:GiveTask(bundle.StateChanged)
	maid:GiveTask(bundle.EnabledChanged)
	maid:GiveTask(bundle.PreferredBindingChanged)

	maid:GiveTask(action.Pressed:Connect(function()
		bundle.Pressed:Fire()
	end))

	maid:GiveTask(action.Released:Connect(function()
		bundle.Released:Fire()
	end))

	maid:GiveTask(action.StateChanged:Connect(function(value: any)
		bundle.StateChanged:Fire(value)
	end))

	maid:GiveTask(action:GetPropertyChangedSignal("Enabled"):Connect(function()
		bundle.EnabledChanged:Fire(action.Enabled)
	end))

	maid:GiveTask(action:GetPropertyChangedSignal("PreferredBinding"):Connect(function()
		bundle.PreferredBindingChanged:Fire(action.PreferredBinding)
	end))

	function bundle:Destroy()
		maid:DoCleaning()
	end

	return bundle :: ActionSignalBundle
end

function InputServiceClient.Init(self: InputServiceClient, serviceBag: ServiceBag): ()
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._rootFolder = findRootFolder()
	self._actionSignals = {}
end

function InputServiceClient.Start(_self: InputServiceClient): () end

function InputServiceClient._getRootFolder(self: InputServiceClient, createIfMissing: boolean): Folder?
	local rootFolder = self._rootFolder
	if rootFolder and rootFolder.Parent then
		return rootFolder
	end

	rootFolder = findRootFolder()
	if rootFolder then
		self._rootFolder = rootFolder
		return rootFolder
	end

	if not createIfMissing then
		return nil
	end

	self._rootFolder = InputServiceInstanceUtils.getOrCreateRootFolder(ReplicatedStorage)
	return self._rootFolder
end

function InputServiceClient.GetRootFolder(self: InputServiceClient): Folder
	local rootFolder = self:_getRootFolder(true)
	assert(rootFolder, "Input root folder is not available")

	return rootFolder
end

function InputServiceClient.GetContext(self: InputServiceClient, contextName: string): InputContext?
	assert(typeof(contextName) == "string", "Context name must be a string")

	local rootFolder = self:_getRootFolder(false)
	if not rootFolder then
		return nil
	end

	return InputServiceInstanceUtils.getContext(rootFolder, contextName)
end

function InputServiceClient.WaitForContext(
	self: InputServiceClient,
	contextName: string,
	timeoutSeconds: number?
): InputContext?
	assert(typeof(contextName) == "string", "Context name must be a string")
	if timeoutSeconds ~= nil then
		assert(typeof(timeoutSeconds) == "number", "Timeout must be a number")
	end

	local context = self:GetContext(contextName)
	if context then
		return context
	end

	local rootFolder = self:_getRootFolder(false)
	if not rootFolder then
		local child = ReplicatedStorage:WaitForChild(InputServiceConstants.ROOT_FOLDER_NAME, timeoutSeconds)
		if child == nil then
			return nil
		end

		assert(
			child:IsA(InputServiceConstants.ROOT_FOLDER_CLASS_NAME),
			string.format("%s must be a %s", child:GetFullName(), InputServiceConstants.ROOT_FOLDER_CLASS_NAME)
		)

		rootFolder = child :: Folder
		self._rootFolder = rootFolder
	end

	local child = rootFolder:WaitForChild(contextName, timeoutSeconds)
	if child == nil then
		return nil
	end

	assert(child:IsA("InputContext"), string.format("%s must be an InputContext", child:GetFullName()))
	return child :: InputContext
end

function InputServiceClient.DefineLocalContext(self: InputServiceClient, config: InputContextConfig): InputContext
	return InputServiceInstanceUtils.upsertContext(self:GetRootFolder(), config)
end

function InputServiceClient.ConfigureAction(
	self: InputServiceClient,
	contextName: string,
	actionConfig: InputActionConfig
): InputAction
	local context = self:GetContext(contextName)
	assert(context, string.format("InputContext %q does not exist", contextName))

	return InputServiceInstanceUtils.upsertAction(context, actionConfig)
end

function InputServiceClient.ConfigureBinding(
	self: InputServiceClient,
	contextName: string,
	actionName: string,
	bindingConfig: InputBindingConfig
): InputBinding
	local action = self:GetAction(contextName, actionName)
	assert(action, string.format("InputAction %q.%q does not exist", contextName, actionName))

	return InputServiceInstanceUtils.upsertBinding(action, bindingConfig)
end

function InputServiceClient.GetAction(self: InputServiceClient, contextName: string, actionName: string): InputAction?
	assert(typeof(actionName) == "string", "Action name must be a string")

	local context = self:GetContext(contextName)
	if not context then
		return nil
	end

	return InputServiceInstanceUtils.getAction(context, actionName)
end

function InputServiceClient.GetBinding(
	self: InputServiceClient,
	contextName: string,
	actionName: string,
	bindingName: string
): InputBinding?
	assert(typeof(bindingName) == "string", "Binding name must be a string")

	local action = self:GetAction(contextName, actionName)
	if not action then
		return nil
	end

	return InputServiceInstanceUtils.getBinding(action, bindingName)
end

function InputServiceClient.GetPreferredBinding(
	self: InputServiceClient,
	contextName: string,
	actionName: string
): InputBinding?
	local action = self:GetAction(contextName, actionName)
	assert(action, string.format("InputAction %q.%q does not exist", contextName, actionName))

	return action.PreferredBinding
end

function InputServiceClient.GetDisplayInfoForBinding(binding: InputBinding?): BindingDisplayInfo
	local imageContent = getContentNone()
	local info: BindingDisplayInfo = {
		Binding = binding,
		Text = "",
		Image = "",
		ImageContent = imageContent,
		HasText = false,
		HasImage = false,
		TextSource = "None",
		ImageSource = "None",
	}

	if not binding then
		return info
	end

	if binding.DisplayName ~= "" then
		info.Text = binding.DisplayName
		info.HasText = true
		info.TextSource = "DisplayName"
	elseif not isEmptyKeyCode(binding.KeyCode) then
		local keyText = UserInputService:GetStringForKeyCode(binding.KeyCode)
		info.Text = if keyText ~= "" then keyText else binding.KeyCode.Name
		info.HasText = info.Text ~= ""
		info.TextSource = "KeyCode"
	elseif binding.UIButton then
		info.Text = binding.UIButton.Name
		info.HasText = info.Text ~= ""
		info.TextSource = "UIButton"
	end

	if hasDisplayImage(binding.DisplayImage) then
		info.ImageContent = binding.DisplayImage
		info.HasImage = true
		info.ImageSource = "DisplayImage"
	elseif not isEmptyKeyCode(binding.KeyCode) then
		local keyImage = UserInputService:GetImageForKeyCode(binding.KeyCode)
		if keyImage ~= "" then
			info.Image = keyImage
			info.ImageContent = contentFromUri(keyImage)
			info.HasImage = true
			info.ImageSource = "KeyCode"
		end
	end

	return info
end

function InputServiceClient.GetBindingDisplayInfo(
	self: InputServiceClient,
	contextName: string,
	actionName: string
): BindingDisplayInfo
	return InputServiceClient.GetDisplayInfoForBinding(self:GetPreferredBinding(contextName, actionName))
end

function InputServiceClient.BindBindingDisplayChanged(
	self: InputServiceClient,
	contextName: string,
	actionName: string,
	callback: (BindingDisplayInfo) -> (),
	fireImmediately: boolean?
): Maid.Maid
	assert(typeof(callback) == "function", "Callback must be a function")

	local maid = Maid.new()
	local bindingMaid = Maid.new()
	maid:GiveTask(bindingMaid)

	local function fire()
		callback(self:GetBindingDisplayInfo(contextName, actionName))
	end

	local function connectBindingProperties(shouldFire: boolean)
		bindingMaid:DoCleaning()

		local binding = self:GetPreferredBinding(contextName, actionName)
		if binding then
			for _, propertyName in BINDING_DISPLAY_PROPERTIES do
				bindingMaid:GiveTask(binding:GetPropertyChangedSignal(propertyName):Connect(fire))
			end
		end

		if shouldFire then
			fire()
		end
	end

	maid:GiveTask(self:GetActionSignals(contextName, actionName).PreferredBindingChanged:Connect(function()
		connectBindingProperties(true)
	end))

	connectBindingProperties(fireImmediately ~= false)

	return maid
end

function InputServiceClient.CreateActionLabel(
	self: InputServiceClient,
	contextName: string,
	actionName: string,
	parentOrProperties: any?,
	properties: { [string]: any }?
): any
	local action = self:GetAction(contextName, actionName)
	assert(action, string.format("InputAction %q.%q does not exist", contextName, actionName))

	local parent: Instance? = nil
	local labelProperties = properties

	if typeof(parentOrProperties) == "Instance" then
		parent = parentOrProperties
	elseif typeof(parentOrProperties) == "table" and labelProperties == nil then
		labelProperties = parentOrProperties
	elseif parentOrProperties ~= nil then
		error("Parent must be an Instance or properties table", 2)
	end

	local ok, labelOrError = pcall(Instance.new, "InputActionLabel")
	assert(ok, string.format("InputActionLabel is not available in this Roblox runtime: %s", tostring(labelOrError)))

	local label = labelOrError :: any
	label.InputAction = action

	if labelProperties then
		for propertyName, value in labelProperties do
			assert(typeof(propertyName) == "string", "InputActionLabel property names must be strings")
			assert(propertyName ~= "InputAction", "InputActionLabel.InputAction is controlled by InputServiceClient")

			if propertyName == "Parent" then
				assert(typeof(value) == "Instance", "InputActionLabel.Parent must be an Instance")
				parent = value
			else
				label[propertyName] = value
			end
		end
	end

	if parent then
		label.Parent = parent
	end

	return label
end

function InputServiceClient.GetActionSignals(
	self: InputServiceClient,
	contextName: string,
	actionName: string
): ActionSignalBundle
	local action = self:GetAction(contextName, actionName)
	assert(action, string.format("InputAction %q.%q does not exist", contextName, actionName))

	local existing = self._actionSignals[action]
	if existing then
		return existing
	end

	local bundle = createActionSignalBundle(action)
	self._actionSignals[action] = bundle
	self._maid:GiveTask(bundle)
	self._maid:GiveTask(action.Destroying:Connect(function()
		self._actionSignals[action] = nil
		bundle:Destroy()
	end))

	return bundle
end

function InputServiceClient.BindPressed(
	self: InputServiceClient,
	contextName: string,
	actionName: string,
	callback: () -> ()
): any
	assert(typeof(callback) == "function", "Callback must be a function")

	return self:GetActionSignals(contextName, actionName).Pressed:Connect(callback)
end

function InputServiceClient.BindReleased(
	self: InputServiceClient,
	contextName: string,
	actionName: string,
	callback: () -> ()
): any
	assert(typeof(callback) == "function", "Callback must be a function")

	return self:GetActionSignals(contextName, actionName).Released:Connect(callback)
end

function InputServiceClient.BindStateChanged(
	self: InputServiceClient,
	contextName: string,
	actionName: string,
	callback: (InputActionState) -> ()
): any
	assert(typeof(callback) == "function", "Callback must be a function")

	return self:GetActionSignals(contextName, actionName).StateChanged:Connect(callback)
end

function InputServiceClient.SetContextEnabled(self: InputServiceClient, contextName: string, enabled: boolean): ()
	assert(typeof(enabled) == "boolean", "Enabled must be a boolean")

	local context = self:GetContext(contextName)
	assert(context, string.format("InputContext %q does not exist", contextName))

	context.Enabled = enabled
end

function InputServiceClient.SetActionEnabled(
	self: InputServiceClient,
	contextName: string,
	actionName: string,
	enabled: boolean
): ()
	assert(typeof(enabled) == "boolean", "Enabled must be a boolean")

	local action = self:GetAction(contextName, actionName)
	assert(action, string.format("InputAction %q.%q does not exist", contextName, actionName))

	action.Enabled = enabled
end

function InputServiceClient.FireBinding(
	self: InputServiceClient,
	contextName: string,
	actionName: string,
	bindingName: string,
	state: InputActionState
): ()
	local binding = self:GetBinding(contextName, actionName, bindingName)
	assert(binding, string.format("InputBinding %q.%q.%q does not exist", contextName, actionName, bindingName))

	local ok, err = pcall(function()
		binding:Fire(state)
	end)

	assert(
		ok,
		string.format(
			"Failed to fire scriptable InputBinding %q.%q.%q: %s",
			contextName,
			actionName,
			bindingName,
			tostring(err)
		)
	)
end

function InputServiceClient.Destroy(self: InputServiceClient): ()
	self._maid:DoCleaning()
	table.clear(self._actionSignals)
end

return InputServiceClient
