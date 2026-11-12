--!strict
--[[
	TechTreeController
	==================
	The Tech Tree as a pannable, zoomable GRAPH (layout spec: docs/UI_UX_GUIDE.md, "Tech Tree").

	                          [ CORE: while True: -> Wheat / Grid Expansion I..III ]
	  [ BOTANY column ]          [ SYSTEM & DRONE column ]          [ LOGIC & DATA column ]

	Node positions come from the data (TechTree.tier / lane / branch column), connector lines
	from Tech.Edges. Statuses (researched / available / locked, affordable or not) are computed
	with the shared Tech module from replicated attributes (Tech_*, Cur_*) - purely for display.
	RESEARCH only sends the node id; the server re-checks prerequisites and the full
	multi-currency cost against SAVED data and answers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local TweenService = game:GetService("TweenService")

local Currencies = require(ReplicatedStorage.Shared.Config.Currencies)
local IconConfig = require(ReplicatedStorage.Shared.Config.IconConfig)
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Components = require(Client.UI.Components)
local Icon = require(Client.UI.Icon)
local Theme = require(Client.UI.Theme)
local UIState = require(Client.UI.UIState)
local NotifyController = require(script.Parent.NotifyController)

local C = Theme.Colors
local player = Players.LocalPlayer

local CARD_W, CARD_H = 168, 86
local LANE_W, ROW_H = 186, 136
local COLUMN_W = 4 * LANE_W
local MARGIN, TOP = 48, 56
local MAX_TIER = 7
local CANVAS_W = MARGIN * 2 + 3 * COLUMN_W
local CANVAS_H = TOP + (MAX_TIER + 1) * ROW_H + MARGIN
local ZOOMS = { 0.5, 0.65, 0.8, 1 }

type Card = {
	button: TextButton,
	stroke: UIStroke,
	status: TextLabel, -- "READY" text for nodes you can afford right now
	chips: Frame,
	tile: Icon.TileHandle, -- the node's icon (what it unlocks)
	lockOverlay: Frame, -- padlock over the icon while the node is locked
	badge: Frame, -- corner badge: checkmark (researched) or glowing star (max tier)
	badgeIcon: Icon.IconHandle,
	badgeStroke: UIStroke,
	glow: Tween?, -- the star's endless glow pulse (only while shown)
}
type Line = { frame: Frame, from: string, to: string }

local TechTreeController = {}

local modal: Components.Modal
local scroller: ScrollingFrame
local canvas: Frame
local canvasScale: UIScale
local zoomIndex = 2
local cards: { [string]: Card } = {}
local lines: { Line } = {}
local selectedId: string? = nil
local busy = false

-- Detail drawer widgets
local detail: {
	frame: Frame,
	icon: Icon.TileHandle,
	code: TextLabel,
	name: TextLabel,
	branch: TextLabel,
	description: TextLabel,
	unlocks: TextLabel,
	requires: TextLabel,
	cost: Frame,
	button: TextButton,
	message: TextLabel,
}

local function unlocks(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, id in Tech.NodeIds do
		if player:GetAttribute("Tech_" .. id) == true then
			set[id] = true
		end
	end
	return set
end

local function wallet(): { [string]: number }
	local amounts: { [string]: number } = {}
	for _, currency in Currencies.List do
		local value = player:GetAttribute("Cur_" .. currency.id)
		amounts[currency.id] = if type(value) == "number" then value else 0
	end
	return amounts
end

-- Centre of a node's card on the canvas (in unscaled canvas pixels).
local function nodeCenter(id: string): Vector2
	local node = Tech.Nodes[id]
	local column = Tech.BranchColumn[node.branch] or 2
	local x = MARGIN + (column - 1) * COLUMN_W + COLUMN_W / 2 + node.lane * LANE_W
	local y = TOP + node.tier * ROW_H + CARD_H / 2
	return Vector2.new(x, y)
end

local function statsText(node: Tech.Node): { string }
	local out: { string } = {}
	local stats = node.stats
	if stats == nil then
		return out
	end
	if stats.gridSize then
		table.insert(out, string.format("Field grows to %d x %d", stats.gridSize, stats.gridSize))
	end
	if stats.batteryCapacity then
		table.insert(out, string.format("+%d battery", stats.batteryCapacity))
	end
	if stats.waterCapacity then
		table.insert(out, string.format("+%d water tank", stats.waterCapacity))
	end
	if stats.cargoCapacity then
		table.insert(out, string.format("+%d cargo space", stats.cargoCapacity))
	end
	if stats.speedBonus then
		table.insert(out, string.format("+%d%% action speed", math.floor(stats.speedBonus * 100 + 0.5)))
	end
	if stats.chargeRateBonus then
		table.insert(out, string.format("%dx charging speed", 1 + stats.chargeRateBonus))
	end
	if stats.waterRadius then
		table.insert(out, "water() also waters neighbours")
	end
	return out
end

---------------------------------------------------------------- canvas
local function drawBands()
	-- Core band across the top two rows.
	Theme.create("Frame", {
		Name = "CoreBand",
		BackgroundColor3 = C.Root,
		BackgroundTransparency = 0.94,
		Position = UDim2.fromOffset(MARGIN / 2, TOP - 30),
		Size = UDim2.fromOffset(CANVAS_W - MARGIN, 2 * ROW_H - 12),
		Parent = canvas,
	}, { Theme.corner(Theme.Radius.L) })
	Components.label({
		Text = "CORE",
		Font = Theme.UIFontHeavy,
		TextSize = 18,
		TextColor3 = C.Root,
		Position = UDim2.fromOffset(MARGIN, TOP - 26),
		Size = UDim2.fromOffset(300, 22),
		Parent = canvas,
	})
	for _, branch in { "Botany", "System", "Logic" } do
		local column = Tech.BranchColumn[branch]
		local color = Theme.branchColor(branch)
		local x = MARGIN + (column - 1) * COLUMN_W
		local y = TOP + 2 * ROW_H - 34
		Theme.create("Frame", {
			Name = branch .. "Band",
			BackgroundColor3 = color,
			BackgroundTransparency = 0.95,
			Position = UDim2.fromOffset(x + 6, y),
			Size = UDim2.fromOffset(COLUMN_W - 12, CANVAS_H - y - MARGIN / 2),
			Parent = canvas,
		}, { Theme.corner(Theme.Radius.L) })
		Components.label({
			Text = string.upper(Tech.BranchNames[branch]),
			Font = Theme.UIFontHeavy,
			TextSize = 18,
			TextColor3 = color,
			Position = UDim2.fromOffset(x + 20, y + 4),
			Size = UDim2.fromOffset(COLUMN_W - 40, 22),
			Parent = canvas,
		})
	end
end

local function drawLines()
	for _, edge in Tech.Edges do
		local a, b = nodeCenter(edge.from), nodeCenter(edge.to)
		local fromNode, toNode = Tech.Nodes[edge.from], Tech.Nodes[edge.to]
		local p1: Vector2
		local p2: Vector2
		if fromNode.tier == toNode.tier then
			local dir = if b.X >= a.X then 1 else -1
			p1 = a + Vector2.new(dir * CARD_W / 2, 0)
			p2 = b - Vector2.new(dir * CARD_W / 2, 0)
		else
			p1 = a + Vector2.new(0, CARD_H / 2)
			p2 = b - Vector2.new(0, CARD_H / 2)
		end
		local delta = p2 - p1
		local frame: Frame = Theme.create("Frame", {
			Name = edge.from .. "->" .. edge.to,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((p1.X + p2.X) / 2, (p1.Y + p2.Y) / 2),
			Size = UDim2.fromOffset(delta.Magnitude, 3),
			Rotation = math.deg(math.atan2(delta.Y, delta.X)),
			BackgroundColor3 = C.Faint,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = canvas,
		})
		table.insert(lines, { frame = frame, from = edge.from, to = edge.to })
	end
end

local function selectNode(id: string)
	selectedId = id
	local node = Tech.Nodes[id]
	local color = Theme.branchColor(node.branch)
	detail.icon.setIcon(node.icon)
	detail.icon.setColor(color)
	detail.code.Text = node.code or node.name
	detail.code.TextColor3 = color
	detail.name.Text = if node.code ~= nil then node.name else ""
	detail.branch.Text = string.upper(Tech.BranchNames[node.branch] or node.branch)
	detail.branch.TextColor3 = color
	detail.description.Text = node.description

	local unlockLines: { string } = {}
	local features: { string } = node.unlocks or {}
	for _, feature in features do
		table.insert(unlockLines, "+ " .. Tech.featureLabel(feature))
	end
	for _, line in statsText(node) do
		table.insert(unlockLines, "+ " .. line)
	end
	detail.unlocks.Text = table.concat(unlockLines, "\n")

	local owned = unlocks()
	local requireLines: { string } = {}
	for _, req in node.requires do
		local done = owned[req] == true
		table.insert(
			requireLines,
			string.format(
				'<font color="#%s">%s %s</font>',
				if done then "7fd962" else "ff6b6b",
				if done then "[x]" else "[ ]",
				Tech.Nodes[req].name
			)
		)
	end
	detail.requires.Text = if #requireLines > 0
		then table.concat(requireLines, "\n")
		else "Nothing - start here!"
	for _, child in detail.cost:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local money = wallet()
	local order = 0
	for _, currency in Currencies.List do
		local amount = node.cost[currency.id]
		if amount ~= nil then
			order += 1
			local row: Frame = Theme.create("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 26),
				LayoutOrder = order,
				Parent = detail.cost,
			})
			local costIcon = Icon.tile(IconConfig.forCurrency(currency.id), 22)
			costIcon.frame.AnchorPoint = Vector2.new(0, 0.5)
			costIcon.frame.Position = UDim2.fromScale(0, 0.5)
			costIcon.frame.Parent = row
			Components.label({
				Text = currency.name,
				TextSize = 14,
				Position = UDim2.fromOffset(30, 0),
				Size = UDim2.new(1, -130, 1, 0),
				Parent = row,
			})
			local have = money[currency.id] or 0
			Components.label({
				Text = string.format("%d / %d", math.min(have, 999999), amount),
				Font = Theme.UIFontBold,
				TextSize = 14,
				TextColor3 = if have >= amount then C.Accent else C.Danger,
				TextXAlignment = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.new(0, 100, 1, 0),
				Parent = row,
			})
		end
	end

	local status = Tech.status(owned, id)
	if status == "researched" then
		detail.button.Text = "RESEARCHED"
		detail.button.BackgroundColor3 = C.AccentDark
		detail.button.AutoButtonColor = false
	elseif status == "locked" then
		detail.button.Text = "LOCKED"
		detail.button.BackgroundColor3 = C.Raised
		detail.button.AutoButtonColor = false
	elseif Tech.canAfford(money, id) then
		detail.button.Text = "RESEARCH"
		detail.button.BackgroundColor3 = C.Accent
		detail.button.AutoButtonColor = true
	else
		detail.button.Text = "NOT ENOUGH RESOURCES"
		detail.button.BackgroundColor3 = C.Raised
		detail.button.AutoButtonColor = false
	end
	detail.frame.Visible = true
	for cardId, card in cards do
		card.stroke.Thickness = if cardId == id then 3 else 1.5
	end
end

local function refresh()
	local owned = unlocks()
	local money = wallet()
	for id, card in cards do
		local node = Tech.Nodes[id]
		local branchColor = Theme.branchColor(node.branch)
		local status = Tech.status(owned, id)
		local affordable = Tech.canAfford(money, id)
		local star = status == "researched" and node.maxTier == true
		if status == "researched" then
			card.button.BackgroundColor3 = Color3.fromRGB(26, 42, 30)
			card.button.BackgroundTransparency = 0
			card.stroke.Color = if star then C.Gold else C.Accent
			card.stroke.Transparency = 0
			card.status.Text = ""
		elseif status == "available" then
			card.button.BackgroundColor3 = C.PanelLight
			card.button.BackgroundTransparency = 0
			card.stroke.Color = if affordable then branchColor else C.BorderBright
			card.stroke.Transparency = 0
			card.status.Text = if affordable then "READY" else ""
			card.status.TextColor3 = branchColor
		else
			card.button.BackgroundColor3 = C.Panel
			card.button.BackgroundTransparency = 0.25
			card.stroke.Color = C.Border
			card.stroke.Transparency = 0.4
			card.status.Text = ""
		end

		-- Status iconography: padlock over the icon (locked), corner checkmark (researched),
		-- glowing star (researched max-tier upgrade).
		card.lockOverlay.Visible = status == "locked"
		card.badge.Visible = status == "researched"
		if status == "researched" then
			card.badgeIcon.setIcon(if star then "star" else "check")
			card.badge.BackgroundColor3 = if star
				then Color3.fromRGB(70, 56, 14)
				else Color3.fromRGB(20, 52, 26)
			card.badgeStroke.Color = if star then C.Gold else C.Accent
		end
		if star and card.glow == nil then
			local glow = TweenService:Create(
				card.badgeStroke,
				TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Thickness = 4, Transparency = 0.5 }
			)
			card.glow = glow
			glow:Play()
		elseif not star and (card.glow :: Tween?) ~= nil then
			(card.glow :: any):Cancel()
			card.glow = nil
			card.badgeStroke.Thickness = 2
			card.badgeStroke.Transparency = 0
		end
		for _, chip in card.chips:GetChildren() do
			if chip:IsA("Frame") then
				chip:Destroy()
			end
		end
		local order = 0
		for _, currency in Currencies.List do
			local amount = node.cost[currency.id]
			if amount ~= nil and status ~= "researched" then
				order += 1
				local chip = Components.costChip(currency.id, amount, (money[currency.id] or 0) >= amount)
				chip.LayoutOrder = order
				chip.Parent = card.chips
			end
		end
	end
	for _, line in lines do
		local fromDone, toDone = owned[line.from] == true, owned[line.to] == true
		line.frame.BackgroundColor3 = if fromDone and toDone
			then C.Accent
			elseif fromDone then C.BorderBright
			else C.Faint
	end
	if selectedId ~= nil then
		selectNode(selectedId)
	end
end

-- BUG-20: the star glow is endless, so it only runs while the panel is open; refresh() on the
-- next open starts it again.
local function stopGlows()
	for _, card in cards do
		local glow = card.glow
		if glow ~= nil then
			glow:Cancel()
			card.glow = nil
			card.badgeStroke.Thickness = 2
			card.badgeStroke.Transparency = 0
		end
	end
end

local function buildCard(id: string)
	local node = Tech.Nodes[id]
	local center = nodeCenter(id)
	local branchColor = Theme.branchColor(node.branch)
	local button: TextButton = Theme.create("TextButton", {
		Name = id,
		Text = "",
		AutoButtonColor = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(center.X, center.Y),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		BackgroundColor3 = C.PanelLight,
		ZIndex = 2,
		Parent = canvas,
	}, { Theme.corner(Theme.Radius.M) })
	local stroke: UIStroke = Theme.stroke(branchColor, 1.5)
	stroke.Parent = button
	-- High-tech fill: a light top-to-bottom sheen over the card colour.
	Theme.create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 195, 205)),
		Rotation = 90,
		Parent = button,
	})

	-- The node's icon (the crop / command / upgrade it unlocks) on a branch-coloured tile.
	local tile = Icon.tile(node.icon, 38, { color = branchColor })
	tile.frame.Position = UDim2.fromOffset(8, 8)
	tile.frame.ZIndex = 3
	tile.frame.Parent = button
	-- Padlock overlay: darkens the icon and shows a lock while the node is locked.
	local lockOverlay: Frame = Theme.create("Frame", {
		Name = "Lock",
		BackgroundColor3 = C.Overlay,
		BackgroundTransparency = 0.3,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Visible = false,
		Parent = tile.frame,
	}, { Theme.corner(10) })
	local lockIcon = Icon.new("lock", 20)
	lockIcon.image.AnchorPoint = Vector2.new(0.5, 0.5)
	lockIcon.image.Position = UDim2.fromScale(0.5, 0.5)
	lockIcon.image.ZIndex = 5
	lockIcon.image.Parent = lockOverlay

	Components.label({
		Text = node.code or node.name,
		Font = if node.code ~= nil then Theme.CodeFont else Theme.UIFontHeavy,
		TextSize = 15,
		TextColor3 = if node.code ~= nil then branchColor else C.Text,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(54, 8),
		Size = UDim2.new(1, -86, 0, 18),
		ZIndex = 3,
		Parent = button,
	})
	Components.label({
		Text = if node.code ~= nil then node.name else (Tech.BranchNames[node.branch] or ""),
		TextSize = 12,
		TextColor3 = C.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(54, 28),
		Size = UDim2.new(1, -62, 0, 16),
		ZIndex = 3,
		Parent = button,
	})
	local status = Components.label({
		Text = "",
		Font = Theme.UIFontHeavy,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(40, 14),
		ZIndex = 3,
		Parent = button,
	})

	-- Corner badge (checkmark / glowing star), sitting on the card's top-right corner.
	local badge: Frame = Theme.create("Frame", {
		Name = "Badge",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = C.Panel,
		ZIndex = 6,
		Visible = false,
		Parent = button,
	}, { Theme.corner(13) })
	local badgeStroke: UIStroke = Theme.stroke(C.Accent, 2, 0)
	badgeStroke.Parent = badge
	local badgeIcon = Icon.new("check", 16)
	badgeIcon.image.AnchorPoint = Vector2.new(0.5, 0.5)
	badgeIcon.image.Position = UDim2.fromScale(0.5, 0.5)
	badgeIcon.image.ZIndex = 7
	badgeIcon.image.Parent = badge
	local chips: Frame = Theme.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 1, -28),
		Size = UDim2.new(1, -16, 0, 20),
		ZIndex = 3,
		Parent = button,
	}, { Theme.list(Enum.FillDirection.Horizontal, 4) })
	button.Activated:Connect(function()
		selectNode(id)
	end)
	cards[id] = {
		button = button,
		stroke = stroke,
		status = status,
		chips = chips,
		tile = tile,
		lockOverlay = lockOverlay,
		badge = badge,
		badgeIcon = badgeIcon,
		badgeStroke = badgeStroke,
		glow = nil,
	}
end

local function research(id: string)
	if busy then
		return
	end
	busy = true
	detail.message.Text = "Researching..."
	detail.message.TextColor3 = C.Muted
	local ok, response = Net.invoke("Research", id)
	if ok and type(response) == "table" then
		detail.message.Text = tostring(response.message or "")
		detail.message.TextColor3 = if response.ok then C.Accent else C.Warning
		if not response.ok then
			NotifyController.show("warning", tostring(response.message or "Research failed."))
		end
	else
		detail.message.Text = "Couldn't reach the server."
		detail.message.TextColor3 = C.Danger
	end
	task.wait(0.5) -- stay well under the server's Research rate limit
	busy = false
end

local function applyZoom()
	local zoom = ZOOMS[zoomIndex]
	canvasScale.Scale = zoom
	scroller.CanvasSize = UDim2.fromOffset(CANVAS_W * zoom, CANVAS_H * zoom)
end

local function buildDetail(body: Frame)
	local frame = Components.panel({
		Name = "Detail",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Space.M, 0, 0),
		Size = UDim2.new(0, 300, 1, -Theme.Space.M),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = body,
	})
	Theme.padding(Theme.Space.L).Parent = frame
	Theme.list(Enum.FillDirection.Vertical, 6).Parent = frame
	local function text(order: number, props: { [string]: any }): TextLabel
		local base: { [string]: any } = {
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = order,
			Parent = frame,
		}
		for key, value in props do
			base[key] = value
		end
		return Components.label(base)
	end
	local headerIcon = Icon.tile("unknown", 56, { glow = true })
	headerIcon.frame.LayoutOrder = 0
	headerIcon.frame.Parent = frame
	local widgets = {
		frame = frame,
		icon = headerIcon,
		branch = text(1, { Font = Theme.UIFontHeavy, TextSize = 12 }),
		code = text(2, { Font = Theme.CodeFont, TextSize = 22 }),
		name = text(3, { Font = Theme.UIFontBold, TextSize = 16, TextColor3 = C.Muted }),
		description = text(4, { TextSize = 14 }),
		unlocks = text(6, { TextSize = 13, TextColor3 = C.Accent }),
		requires = text(8, { TextSize = 13, RichText = true }),
		cost = Theme.create("Frame", {
			BackgroundTransparency = 1,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = 10,
			Parent = frame,
		}, { Theme.list(Enum.FillDirection.Vertical, 2) }),
		button = Theme.button("RESEARCH", C.Accent, {
			Font = Theme.UIFontHeavy,
			TextSize = 15,
			Size = UDim2.new(1, 0, 0, 42),
			LayoutOrder = 11,
			Parent = frame,
		}),
		message = text(12, { TextSize = 13, TextColor3 = C.Muted }),
	}
	text(5, { Text = "UNLOCKS", Font = Theme.UIFontHeavy, TextSize = 11, TextColor3 = C.Faint })
	text(7, { Text = "REQUIRES", Font = Theme.UIFontHeavy, TextSize = 11, TextColor3 = C.Faint })
	text(9, { Text = "COST", Font = Theme.UIFontHeavy, TextSize = 11, TextColor3 = C.Faint })
	widgets.button.Activated:Connect(function()
		local id = selectedId
		if id ~= nil and Tech.status(unlocks(), id) == "available" then
			research(id)
		end
	end)
	detail = widgets :: any
end

local function enableDragPan()
	local dragging = false
	local last: Vector3? = nil
	scroller.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3
		then
			dragging = true
			last = input.Position
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3
		then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local previous = last
		if dragging and previous ~= nil and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - previous
			last = input.Position
			scroller.CanvasPosition = scroller.CanvasPosition - Vector2.new(delta.X, delta.Y)
		end
	end)
end

function TechTreeController:Init()
	local gui = Theme.create("ScreenGui", {
		Name = "TechTree",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})
	modal = Components.modal(gui, "TECH TREE", UDim2.fromScale(0.86, 0.8))
	modal.title.TextColor3 = C.Accent

	-- Zoom buttons + legend in the header.
	local header = modal.root:FindFirstChild("Header") :: Frame
	local tools: Frame = Theme.create("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -48, 0.5, 0),
		Size = UDim2.fromOffset(300, 30),
		Parent = header,
	}, {
		Theme.list(
			Enum.FillDirection.Horizontal,
			6,
			{ HorizontalAlignment = Enum.HorizontalAlignment.Right }
		),
	})
	Components.label({
		Text = "Right-drag to pan",
		TextSize = 12,
		TextColor3 = C.Faint,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromOffset(120, 30),
		LayoutOrder = 1,
		Parent = tools,
	})
	local zoomOut =
		Components.ghostButton("-", { Size = UDim2.fromOffset(30, 30), LayoutOrder = 2, Parent = tools })
	local zoomIn =
		Components.ghostButton("+", { Size = UDim2.fromOffset(30, 30), LayoutOrder = 3, Parent = tools })

	scroller = Theme.create("ScrollingFrame", {
		Name = "Graph",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(Theme.Space.M, 0),
		Size = UDim2.new(1, -(300 + 3 * Theme.Space.M), 1, -Theme.Space.M),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Border,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		CanvasSize = UDim2.fromOffset(CANVAS_W, CANVAS_H),
		Parent = modal.body,
	})
	canvas = Theme.create("Frame", {
		Name = "Canvas",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(CANVAS_W, CANVAS_H),
		Parent = scroller,
	})
	canvasScale = Theme.create("UIScale", { Scale = ZOOMS[zoomIndex], Parent = canvas })

	drawBands()
	drawLines()
	for _, id in Tech.NodeIds do
		buildCard(id)
	end
	buildDetail(modal.body)
	applyZoom()
	enableDragPan()

	zoomIn.Activated:Connect(function()
		zoomIndex = math.min(#ZOOMS, zoomIndex + 1)
		applyZoom()
	end)
	zoomOut.Activated:Connect(function()
		zoomIndex = math.max(1, zoomIndex - 1)
		applyZoom()
	end)

	local function onClosed()
		stopGlows()
		UIState.notifyClosed("TechTree")
	end
	modal.onClose = onClosed
	UIState.register("TechTree", {
		open = function()
			modal.open()
			refresh()
			if selectedId == nil then
				selectNode("loops")
			end
		end,
		close = function()
			stopGlows()
			modal.onClose = nil
			modal.close()
			modal.onClose = onClosed
		end,
	})
	gui.Parent = player:WaitForChild("PlayerGui")
end

--[[
	Research unlock (ANIM-6): the card that just became owned pings ONCE: UIScale 1 -> 1.08 -> 1
	and a 0.3 s lime stroke flash back to its refreshed (owned) look. Only while the panel is
	open (that's where research is bought), so late-replicating saved unlocks on join never
	ping a whole column.
]]
local UNLOCK_POP = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
local UNLOCK_FLASH = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function pingCard(id: string)
	local card = cards[id]
	if card == nil then
		return
	end
	local scale = card.button:FindFirstChildOfClass("UIScale")
	if scale == nil then
		scale = Theme.create("UIScale", { Name = "UnlockScale", Scale = 1, Parent = card.button })
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = 1
	TweenService:Create(uiScale, UNLOCK_POP, { Scale = 1.08 }):Play()
	local stroke = card.stroke
	local color, thickness = stroke.Color, stroke.Thickness -- set by refresh() just before
	stroke.Color = C.Accent
	stroke.Thickness = 4
	TweenService:Create(stroke, UNLOCK_FLASH, { Color = color, Thickness = thickness }):Play()
end

function TechTreeController:Start()
	local function refreshIfOpen()
		if modal.isOpen() then
			refresh()
		end
	end
	for _, id in Tech.NodeIds do
		local attribute = "Tech_" .. id
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if not modal.isOpen() then
				return
			end
			refresh()
			if player:GetAttribute(attribute) == true then
				pingCard(id)
			end
		end)
	end
	for _, currency in Currencies.List do
		player:GetAttributeChangedSignal("Cur_" .. currency.id):Connect(refreshIfOpen)
	end
end

return TechTreeController
