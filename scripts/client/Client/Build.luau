local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local DEFAULTS = {
	GridSize = 2,
	PreviewTransparency = 0.5,
	MaxReach = 1000,
	MaxStackHeight = 10,
	ValidColor = Color3.fromRGB(50, 255, 100),
	InvalidColor = Color3.fromRGB(255, 60, 60),
	PlotName = "Plot1",
	FolderName = "PlacedBlocks",
}

local Building = {}

local session = nil
local pendingModel = nil

local function isModel(value)
	return typeof(value) == "Instance" and value:IsA("Model")
end

local function getBounds(model)
	local inverse = model:GetPivot():Inverse()
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			found = true
			local relative = inverse * descendant.CFrame
			local half = descendant.Size / 2

			for _, x in ipairs({ -1, 1 }) do
				for _, y in ipairs({ -1, 1 }) do
					for _, z in ipairs({ -1, 1 }) do
						local corner = relative * Vector3.new(half.X * x, half.Y * y, half.Z * z)
						minX, maxX = math.min(minX, corner.X), math.max(maxX, corner.X)
						minY, maxY = math.min(minY, corner.Y), math.max(maxY, corner.Y)
						minZ, maxZ = math.min(minZ, corner.Z), math.max(maxZ, corner.Z)
					end
				end
			end
		end
	end

	if not found then
		return Vector3.new(1, 1, 1), Vector3.zero
	end

	local size = Vector3.new(maxX - minX, maxY - minY, maxZ - minZ)
	local center = Vector3.new((minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2)

	return size, center
end

function Building.activate(options)
	if session then
		return
	end

	local config = table.clone(DEFAULTS)
	if options then
		for key, value in pairs(options) do
			config[key] = value
		end
	end

	local player = Players.LocalPlayer
	local mouse = player:GetMouse()

	local plot = workspace:WaitForChild(config.PlotName)

	local placedFolder = workspace:FindFirstChild(config.FolderName)
	if not placedFolder then
		placedFolder = Instance.new("Folder")
		placedFolder.Name = config.FolderName
		placedFolder.Parent = workspace
	end

	local rotation = 0
	local validPlacement = false
	local lastValid = nil
	local building = true
	local connections = {}

	local current = nil
	local preview = nil
	local previewParts = {}
	local highlight = nil
	local lastCenter = Vector3.zero
	local lastSize = Vector3.zero

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = { placedFolder }

	local function setPreviewState(valid)
		validPlacement = valid
		if lastValid == valid then
			return
		end
		lastValid = valid
		local color = valid and config.ValidColor or config.InvalidColor
		if highlight then
			highlight.FillColor = color
			highlight.OutlineColor = color
		end
		for _, part in ipairs(previewParts) do
			part.Color = color
		end
	end

	local function loadModel(model)
		local boundsSize, centerLocal = getBounds(model)

		current = {
			template = model,
			size = boundsSize,
			offset = CFrame.new(-centerLocal),
		}

		if preview then
			preview:Destroy()
		end

		preview = model:Clone()
		preview.Name = "BuildingPreview"
		previewParts = {}

		for _, descendant in ipairs(preview:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.Transparency = math.max(descendant.Transparency, config.PreviewTransparency)
				table.insert(previewParts, descendant)
			elseif descendant:IsA("BaseScript") then
				descendant:Destroy()
			end
		end

		highlight = nil
		local ok, created = pcall(function()
			local instance = Instance.new("Highlight")
			instance.Adornee = preview
			instance.FillTransparency = 0.5
			instance.OutlineTransparency = 0
			instance.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			instance.Parent = preview
			return instance
		end)
		if ok then
			highlight = created
		end

		lastValid = nil
		validPlacement = false
		preview.Parent = building and workspace or nil
	end

	local function setCurrent(model)
		if not isModel(model) then
			return false
		end

		loadModel(model)
		return true
	end

	local function getRotatedSize()
		local size = current.size
		if rotation % 180 == 90 then
			return Vector3.new(size.Z, size.Y, size.X)
		end
		return size
	end

	local function snap(value)
		return math.floor(value / config.GridSize + 0.5) * config.GridSize
	end

	local function isInsidePlot(localX, localZ, size)
		local halfPlot = plot.Size / 2
		local halfObject = size / 2
		return math.abs(localX) + halfObject.X <= halfPlot.X + 0.001
			and math.abs(localZ) + halfObject.Z <= halfPlot.Z + 0.001
	end

	local function isOverlapping(center, size)
		local epsilon = 0.05

		for _, block in ipairs(placedFolder:GetChildren()) do
			local otherCenter = block:GetAttribute("LocalCenter")
			local otherSize = block:GetAttribute("BoxSize")

			if otherCenter and otherSize then
				local delta = center - otherCenter
				local half = (size + otherSize) / 2

				if math.abs(delta.X) < half.X - epsilon
					and math.abs(delta.Y) < half.Y - epsilon
					and math.abs(delta.Z) < half.Z - epsilon then
					return true
				end
			end
		end

		return false
	end

	local function getLayer(localY, size)
		local bottom = localY - size.Y / 2 - plot.Size.Y / 2
		return math.floor(bottom / size.Y + 0.5)
	end

	local function getPlacedModel(instance)
		local node = instance
		while node and node.Parent ~= placedFolder do
			node = node.Parent
		end
		if node and node:IsA("Model") then
			return node
		end
		return nil
	end

	local function updatePreview()
		if not building or not current then
			return
		end

		local ray = mouse.UnitRay
		local size = getRotatedSize()

		local plotUp = plot.CFrame.UpVector
		local planePoint = plot.CFrame.Position + plotUp * (plot.Size.Y / 2)
		local planeDistance = nil

		local denominator = ray.Direction:Dot(plotUp)
		if math.abs(denominator) > 0.0001 then
			local t = (planePoint - ray.Origin):Dot(plotUp) / denominator
			if t > 0 and t <= config.MaxReach then
				planeDistance = t
			end
		end

		local blockResult = workspace:Raycast(ray.Origin, ray.Direction * config.MaxReach, rayParams)
		local hitModel = blockResult and getPlacedModel(blockResult.Instance) or nil
		local useBlock = hitModel ~= nil and (planeDistance == nil or blockResult.Distance < planeDistance)

		local worldPoint
		local worldNormal

		if useBlock then
			worldPoint = blockResult.Position
			worldNormal = blockResult.Normal
		elseif planeDistance then
			worldPoint = ray.Origin + ray.Direction * planeDistance
			worldNormal = plotUp
		else
			setPreviewState(false)
			return
		end

		local localNormal = plot.CFrame:VectorToObjectSpace(worldNormal)
		local point = worldPoint + worldNormal * (config.GridSize * 0.25)
		local localPoint = plot.CFrame:PointToObjectSpace(point)

		local localX = snap(localPoint.X)
		local localZ = snap(localPoint.Z)
		local localY

		if not useBlock then
			localY = plot.Size.Y / 2 + size.Y / 2
		else
			local otherCenter = hitModel:GetAttribute("LocalCenter")
			local otherSize = hitModel:GetAttribute("BoxSize")

			if not otherCenter or not otherSize then
				setPreviewState(false)
				return
			end

			if localNormal.Y > 0.5 then
				localY = otherCenter.Y + otherSize.Y / 2 + size.Y / 2
			elseif math.abs(localNormal.Y) < 0.5 then
				localY = otherCenter.Y - otherSize.Y / 2 + size.Y / 2
			else
				setPreviewState(false)
				return
			end
		end

		local center = Vector3.new(localX, localY, localZ)
		local centerCFrame = plot.CFrame
			* CFrame.new(center)
			* CFrame.Angles(0, math.rad(rotation), 0)

		preview:PivotTo(centerCFrame * current.offset)

		lastCenter = center
		lastSize = size

		setPreviewState(
			isInsidePlot(localX, localZ, size)
				and getLayer(localY, size) < config.MaxStackHeight
				and not isOverlapping(center, size)
		)
	end

	local function placeBlock()
		if not validPlacement or not current then
			return
		end

		local placed = current.template:Clone()

		for _, descendant in ipairs(placed:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
			end
		end

		placed:SetAttribute("LocalCenter", lastCenter)
		placed:SetAttribute("BoxSize", lastSize)
		placed:PivotTo(preview:GetPivot())
		placed.Parent = placedFolder
	end

	local function setBuilding(state)
		building = state
		if preview then
			preview.Parent = state and workspace or nil
		end
	end

	local function getCurrent()
		return current and current.template or nil
	end

	local function cleanup()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		if preview then
			preview:Destroy()
		end
	end

	if pendingModel then
		setCurrent(pendingModel)
	end

	table.insert(connections, RunService.RenderStepped:Connect(updatePreview))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end

		if input.KeyCode == Enum.KeyCode.B then
			setBuilding(not building)
			return
		end

		if not building then
			return
		end

		if input.KeyCode == Enum.KeyCode.R then
			rotation = (rotation + 90) % 360
		elseif input.KeyCode == Enum.KeyCode.X then
			setBuilding(false)
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			placeBlock()
		end
	end))

	session = {
		setCurrent = setCurrent,
		getCurrent = getCurrent,
		cleanup = cleanup,
	}
end

Building.GetBounds = getBounds

function Building.SetCurrent(model)
	if not isModel(model) then
		warn("Building.SetCurrent expects a Model")
		return false
	end

	pendingModel = model

	if session then
		return session.setCurrent(model)
	end

	return true
end

function Building.GetCurrent()
	if session then
		return session.getCurrent()
	end
	return pendingModel
end

function Building.deactivate()
	if not session then
		return
	end

	session.cleanup()
	session = nil
end

return Building
