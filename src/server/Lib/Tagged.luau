-- Tagged.luau
-- Runs `setup` for every instance that has a CollectionService tag,
-- including instances tagged later (e.g. streamed in or added at runtime).
-- `setup` may return an RBXScriptConnection or a cleanup function, which is
-- called automatically when the tag is removed or the instance is destroyed.

local CollectionService = game:GetService("CollectionService")

type Cleanup = RBXScriptConnection | () -> () | nil

local function runCleanup(cleanup: Cleanup)
	if typeof(cleanup) == "RBXScriptConnection" then
		cleanup:Disconnect()
	elseif type(cleanup) == "function" then
		cleanup()
	end
end

return function(tag: string, setup: (Instance) -> Cleanup)
	local cleanups: { [Instance]: Cleanup } = {}

	local function onAdded(instance: Instance)
		if cleanups[instance] then
			return
		end
		local ok, result = pcall(setup, instance)
		if not ok then
			warn(
				string.format("[Tagged] Failed to set up '%s' (%s): %s", instance:GetFullName(), tag, tostring(result))
			)
			return
		end
		cleanups[instance] = result or false
	end

	local function onRemoved(instance: Instance)
		local cleanup = cleanups[instance]
		cleanups[instance] = nil
		if cleanup then
			runCleanup(cleanup)
		end
	end

	CollectionService:GetInstanceAddedSignal(tag):Connect(onAdded)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(onRemoved)
	for _, instance in CollectionService:GetTagged(tag) do
		onAdded(instance)
	end
end
