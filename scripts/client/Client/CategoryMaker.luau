local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Building = require(script.Parent.Build)

local Player = Players.LocalPlayer
local Main: ScreenGui = Player.PlayerGui.Main
local blocksFolder = ReplicatedStorage:WaitForChild("BuildingBlocks")

local blockMenu = Main.BlockMenu
local categoriesFrame = blockMenu:WaitForChild("Categories")
local menuFrame = blockMenu:WaitForChild("Menu")

local categoryTemplate = categoriesFrame:WaitForChild("Template")
local blockTemplate = menuFrame:WaitForChild("Template")

categoryTemplate.Visible = false
blockTemplate.Visible = false

local categories = {}
local categoryButtons = {}
local blockButtons = {}
local selectedCategory = nil

local function clearBlocks()
	for _, button in ipairs(blockButtons) do
		button:Destroy()
	end
	table.clear(blockButtons)
end

local function setupViewport(viewport: ViewportFrame, model: Model)
	local clone = model:Clone()

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	clone.Parent = viewport

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local boundsSize, centerLocal = Building.GetBounds(clone)
	local boundsCFrame = clone:GetPivot() * CFrame.new(centerLocal)
	local radius = boundsSize.Magnitude / 2
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2))
	local direction = Vector3.new(1, 0.7, 1).Unit

	camera.CFrame = CFrame.lookAt(boundsCFrame.Position + direction * distance * 1.1, boundsCFrame.Position)
end

local function setHighlight(button: GuiButton, selected: boolean)
	button.Parent.BackgroundTransparency = selected and 0 or 0.35
end

local function selectCategory(name: string)
	if selectedCategory == name then
		return
	end

	selectedCategory = name
	clearBlocks()

	for categoryName, button in pairs(categoryButtons) do
		setHighlight(button, categoryName == name)
	end

	for index, model in ipairs(categories[name]) do
		local cloned = blockTemplate:Clone()
		cloned.Name = model.Name
		cloned.LayoutOrder = index
		cloned.Visible = true

		cloned.BlockName.Text = model.Name
		setupViewport(cloned.ViewportFrame, model)

		cloned.Sinker.MouseButton1Click:Connect(function()
			Building.SetCurrent(model)
		end)

		cloned.Parent = menuFrame
		table.insert(blockButtons, cloned)
	end
end

local order = 0

for _, category in ipairs(blocksFolder:GetChildren()) do
	local models = {}

	for _, child in ipairs(category:GetChildren()) do
		if child:IsA("Model") then
			table.insert(models, child)
		end
	end

	table.sort(models, function(a, b)
		return a.Name < b.Name
	end)

	categories[category.Name] = models

	order += 1

	local cloned = categoryTemplate:Clone()
	cloned.Name = category.Name
	cloned.LayoutOrder = order
	cloned.Visible = true

	local icon = category:GetAttribute("Icon")
	if icon then
		cloned.ImageLabel.Image = icon
	end

	local button = cloned.Sinker
	categoryButtons[category.Name] = button
	setHighlight(button, false)

	button.MouseButton1Click:Connect(function()
		selectCategory(category.Name)
	end)

	cloned.Parent = categoriesFrame
end

for _, category in ipairs(blocksFolder:GetChildren()) do
	selectCategory(category.Name)
	break
end

return {
	SelectCategory = selectCategory,
	Open = function()
		blockMenu.Visible = true
	end,
	Close = function()
		blockMenu.Visible = false
	end,
	Toggle = function()
		blockMenu.Visible = not blockMenu.Visible
	end,
}
