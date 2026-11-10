-- Create.luau
-- Tiny helper to build Instances in one expression:
--   Create("TextLabel", { Text = "Hi", Parent = frame }, { Create("UICorner", {}) })
-- "Parent" is applied last so the instance is fully set up first.

return function(className: string, props: { [string]: any }?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end
