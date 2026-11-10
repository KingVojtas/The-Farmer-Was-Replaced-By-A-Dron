--!strict
--[[
	ShopController
	==============
	The Shop panel (layout spec: docs/UI_UX_GUIDE.md, "Shop").

	  [ Featured | Gamepasses | Lithium Batteries | Boosts | Drone Hangar ]   + card grid

	PURCHASE FLOW (the client never grants anything)
	  Developer Product  -> MarketplaceService:PromptProductPurchase. Roblox charges the player
	                        and calls the SERVER's ProcessReceipt, which grants + saves and only
	                        then returns PurchaseGranted; the server then fires PurchaseGranted
	                        to us (toast). Until PromptProductPurchaseFinished the card shows "...".
	  Gamepass           -> MarketplaceService:PromptGamePassPurchase. The server hears
	                        PromptGamePassPurchaseFinished itself and sets Pass_<Key>; the card
	                        flips to OWNED when that attribute changes.
	  Cosmetics          -> BuyCosmetic / EquipCosmetic remotes with an enum id; the server
	                        checks the SAVED Battery balance and ownership.

	Prices shown come from GetProductInfo (cached, pcall'd); MonetizationConfig.price is only
	the fallback. Products/passes whose id is still 0 show "Coming soon".
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticConfig = require(ReplicatedStorage.Shared.Config.CosmeticConfig)
local IconConfig = require(ReplicatedStorage.Shared.Config.IconConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
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

type Card = {
	frame: Frame,
	button: TextButton,
	status: TextLabel,
	-- showRobux = true puts the official Robux icon in front of the price
	setButton: (text: string, color: Color3, enabled: boolean, showRobux: boolean?) -> (),
}

type CardOptions = {
	title: string,
	description: string,
	icon: string, -- IconConfig key
	glow: boolean?, -- neon outline for premium items
	accent: Color3,
	badge: string?,
	perks: { string }?,
	order: number,
	wide: boolean?,
}

local TABS = {
	{ id = "featured", label = "Featured" },
	{ id = "passes", label = "Gamepasses" },
	{ id = "batteries", label = "Lithium Batteries" },
	{ id = "boosts", label = "Boosts" },
	{ id = "hangar", label = "Drone Hangar" },
}

local ShopController = {}

local modal: Components.Modal
local pages: { [string]: ScrollingFrame } = {}
local tabButtons: { [string]: TextButton } = {}
local refreshers: { () -> () } = {}
local priceCache: { [string]: number } = {}
local pendingProducts: { [number]: boolean } = {}
local confirmUntil: { [string]: number } = {}

---------------------------------------------------------------- prices
local function fetchPrice(kind: "Product" | "GamePass", id: number, fallback: number, onPrice: (number) -> ())
	onPrice(fallback)
	if id == 0 then
		return
	end
	local key = kind .. id
	local cached = priceCache[key]
	if cached ~= nil then
		onPrice(cached)
		return
	end
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(
				id,
				if kind == "Product" then Enum.InfoType.Product else Enum.InfoType.GamePass
			)
		end)
		if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
			priceCache[key] = info.PriceInRobux
			onPrice(info.PriceInRobux)
		end
	end)
end

---------------------------------------------------------------- card
local function buildCard(parent: Instance, options: CardOptions): Card
	local frame = Components.panel({
		Name = options.title,
		BackgroundColor3 = C.PanelLight,
		LayoutOrder = options.order,
		Size = UDim2.fromOffset(if options.wide then 452 else 218, 252),
		Parent = parent,
	})
	if options.glow then
		-- Premium items get a neon outline in their accent colour.
		local outline = frame:FindFirstChildOfClass("UIStroke")
		if outline ~= nil then
			outline.Color = options.accent
			outline.Thickness = 2
		end
	end
	-- Art area: the product icon (IconConfig) on a tinted gradient.
	local art: Frame = Theme.create("Frame", {
		Name = "Art",
		BackgroundColor3 = options.accent,
		BackgroundTransparency = 0.82,
		Size = UDim2.new(1, -16, 0, 92),
		Position = UDim2.fromOffset(8, 8),
		Parent = frame,
	}, { Theme.corner(Theme.Radius.S), Theme.gradient(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)) })
	local tile = Icon.tile(options.icon, 68, { glow = options.glow, color = options.accent })
	tile.frame.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.frame.Position = UDim2.fromScale(0.5, 0.5)
	tile.frame.Parent = art
	if options.badge ~= nil then
		local badge = Components.badge(options.badge, C.Gold)
		badge.Position = UDim2.fromOffset(8, 8)
		badge.Parent = art
	end

	local content: Frame = Theme.create("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 108),
		Size = UDim2.new(1, -24, 1, -160),
		Parent = frame,
	}, { Theme.list(Enum.FillDirection.Vertical, 2) })
	Components.label({
		Text = options.title,
		Font = Theme.UIFontHeavy,
		TextSize = 17,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = 1,
		Parent = content,
	})
	Components.label({
		Text = options.description,
		TextSize = 13,
		TextColor3 = C.Muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = content,
	})
	local perks: { string } = options.perks or {}
	for index, perk in perks do
		Components.label({
			Text = "+ " .. perk,
			TextSize = 12,
			TextColor3 = options.accent,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Size = UDim2.new(1, 0, 0, 16),
			LayoutOrder = 2 + index,
			Parent = content,
		})
	end
	local status = Components.label({
		Text = "",
		TextSize = 12,
		TextColor3 = C.Gold,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = 99,
		Parent = content,
	})

	local button = Theme.button("", C.Accent, {
		Name = "Buy",
		Font = Theme.UIFontHeavy,
		TextSize = 15,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -24, 0, 36),
		Parent = frame,
	})
	-- Button content: [Robux icon] [price], centred by a horizontal UIListLayout.
	Theme.list(Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}).Parent =
		button
	local robuxIcon = Icon.robux(20, C.Background)
	robuxIcon.LayoutOrder = 1
	robuxIcon.Parent = button
	local priceLabel = Components.label({
		Name = "Price",
		Font = Theme.UIFontHeavy,
		TextSize = 15,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 36),
		LayoutOrder = 2,
		Parent = button,
	})
	Components.hover(button)
	return {
		frame = frame,
		button = button,
		status = status,
		setButton = function(text: string, color: Color3, enabled: boolean, showRobux: boolean?)
			priceLabel.Text = text
			robuxIcon.Visible = showRobux == true
			button.BackgroundColor3 = if enabled then color else C.Raised
			priceLabel.TextColor3 = if enabled then C.Background else C.Muted
			robuxIcon.ImageColor3 = priceLabel.TextColor3
			button.AutoButtonColor = enabled
			button.Active = enabled
		end,
	}
end

---------------------------------------------------------------- product / pass cards
local function productCard(parent: Instance, key: string, order: number, wide: boolean?): Card
	local product = MonetizationConfig.Products[key]
	local accent = if product.category == "currency"
		then C.Premium
		elseif product.category == "boost" then C.Accent
		else C.Gold
	local card = buildCard(parent, {
		title = product.name,
		description = product.description,
		icon = product.icon,
		glow = product.category ~= "boost",
		accent = accent,
		badge = product.badge,
		order = order,
		wide = wide,
	})
	local price = product.price
	local function refresh()
		if product.id == 0 then
			card.setButton("COMING SOON", C.Raised, false)
		elseif pendingProducts[product.id] then
			card.setButton("...", accent, false)
		else
			card.setButton(tostring(price), accent, true, true)
		end
	end
	fetchPrice("Product", product.id, product.price, function(value: number)
		price = value
		refresh()
	end)
	card.button.Activated:Connect(function()
		if product.id == 0 or pendingProducts[product.id] then
			return
		end
		pendingProducts[product.id] = true
		refresh()
		local ok = pcall(function()
			MarketplaceService:PromptProductPurchase(player, product.id)
		end)
		if not ok then
			pendingProducts[product.id] = nil
			refresh()
			NotifyController.show("error", "The purchase window couldn't open. Please try again.")
		end
	end)
	table.insert(refreshers, refresh)
	return card
end

local function passCard(parent: Instance, key: string, order: number): Card
	local pass = MonetizationConfig.GamePasses[key]
	local card = buildCard(parent, {
		title = pass.name,
		description = pass.description,
		icon = pass.icon,
		glow = true,
		accent = if key == "VIP" then C.Gold else C.Info,
		badge = pass.badge,
		perks = pass.perks,
		order = order,
	})
	local price = pass.price
	local function refresh()
		if player:GetAttribute("Pass_" .. key) == true then
			card.setButton("OWNED", C.Accent, false)
		elseif pass.id == 0 then
			card.setButton("COMING SOON", C.Raised, false)
		else
			card.setButton(tostring(price), C.Gold, true, true)
		end
	end
	fetchPrice("GamePass", pass.id, pass.price, function(value: number)
		price = value
		refresh()
	end)
	card.button.Activated:Connect(function()
		if pass.id == 0 or player:GetAttribute("Pass_" .. key) == true then
			return
		end
		local ok = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, pass.id)
		end)
		if not ok then
			NotifyController.show("error", "The purchase window couldn't open. Please try again.")
		end
	end)
	player:GetAttributeChangedSignal("Pass_" .. key):Connect(refresh)
	table.insert(refreshers, refresh)
	return card
end

local function sortedKeys(map: { [string]: any }, filter: ((any) -> boolean)?): { string }
	local keys: { string } = {}
	for key, value in map do
		if filter == nil or filter(value) then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a: string, b: string): boolean
		return (map[a].order or 0) < (map[b].order or 0)
	end)
	return keys
end

---------------------------------------------------------------- hangar (cosmetics)
local function cosmeticOwned(item: CosmeticConfig.Cosmetic): boolean
	local unlock: any = item.unlock
	if unlock.kind == "free" then
		return true
	elseif unlock.kind == "tech" then
		local owner = Tech.FeatureOwner[unlock.feature]
		return owner == nil or player:GetAttribute("Tech_" .. owner) == true
	end
	return player:GetAttribute("Owned_" .. item.id) == true
end

local function cosmeticTile(parent: Instance, item: CosmeticConfig.Cosmetic, order: number)
	local frame = Components.panel({
		Name = item.id,
		BackgroundColor3 = C.PanelLight,
		LayoutOrder = order,
		Size = UDim2.fromOffset(160, 196),
		Parent = parent,
	})
	local preview: Frame = Theme.create("Frame", {
		BackgroundColor3 = C.Background,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.new(1, -16, 0, 74),
		Parent = frame,
	}, { Theme.corner(Theme.Radius.S) })
	if item.slot == "paint" then
		Theme.list(Enum.FillDirection.Horizontal, 6, {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}).Parent =
			preview
		for index, color in { item.primary, item.secondary, item.accent } do
			if color ~= nil then
				Theme.create("Frame", {
					BackgroundColor3 = Theme.rgb(color),
					Size = UDim2.fromOffset(if index == 1 then 40 else 24, if index == 1 then 40 else 24),
					LayoutOrder = index,
					Parent = preview,
				}, { Theme.corner(20), Theme.stroke(C.Border) })
			end
		end
	else
		-- Hat icon (IconConfig "hat_<style>"; "No Hat" shows a plain lock-free tile).
		local color = if item.color ~= nil then Theme.rgb(item.color) else C.Muted
		local hatIcon = Icon.tile(
			if item.style ~= nil then "hat_" .. item.style else "unknown",
			54,
			{ color = color, glow = item.unlock.kind == "premium" }
		)
		hatIcon.frame.AnchorPoint = Vector2.new(0.5, 0.5)
		hatIcon.frame.Position = UDim2.fromScale(0.5, 0.5)
		hatIcon.frame.Parent = preview
	end
	Components.label({
		Text = item.name,
		Font = Theme.UIFontHeavy,
		TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(10, 88),
		Size = UDim2.new(1, -20, 0, 18),
		Parent = frame,
	})
	Components.label({
		Text = item.description,
		TextSize = 11,
		TextColor3 = C.Muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(10, 108),
		Size = UDim2.new(1, -20, 0, 32),
		Parent = frame,
	})
	local button = Theme.button("", C.Accent, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, 30),
		Parent = frame,
	})
	-- [Lithium icon] [price] for premium prices, centred by a horizontal UIListLayout.
	Theme.list(Enum.FillDirection.Horizontal, 4, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}).Parent =
		button
	local priceIcon = Icon.new(IconConfig.forCurrency("batteries"), 18)
	priceIcon.image.LayoutOrder = 1
	priceIcon.image.Parent = button
	local buttonLabel = Components.label({
		Font = Theme.UIFontHeavy,
		TextSize = 13,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 2,
		Parent = button,
	})

	local unlock: any = item.unlock
	local function setButton(text: string, color: Color3, enabled: boolean, showPrice: boolean?)
		buttonLabel.Text = text
		priceIcon.image.Visible = showPrice == true
		button.BackgroundColor3 = if enabled then color else C.Raised
		buttonLabel.TextColor3 = if enabled then C.Background else C.Muted
		button.AutoButtonColor = enabled
	end
	local function refresh()
		local equipped = player:GetAttribute("Equipped_" .. item.slot) == item.id
		if equipped then
			setButton("EQUIPPED", C.Accent, false)
		elseif cosmeticOwned(item) then
			setButton("EQUIP", C.Info, true)
		elseif unlock.kind == "tech" then
			local owner = Tech.FeatureOwner[unlock.feature]
			setButton(
				"RESEARCH " .. (if owner ~= nil then string.upper(Tech.Nodes[owner].name) else "?"),
				C.Raised,
				false
			)
		elseif os.clock() < (confirmUntil[item.id] or 0) then
			setButton("CONFIRM " .. unlock.price .. "?", C.Gold, true, true)
		else
			setButton(tostring(unlock.price), C.Premium, true, true)
		end
	end
	button.Activated:Connect(function()
		if player:GetAttribute("Equipped_" .. item.slot) == item.id then
			return
		end
		if cosmeticOwned(item) then
			local ok, response = Net.invoke("EquipCosmetic", item.slot, item.id)
			if not ok or type(response) ~= "table" or not response.ok then
				NotifyController.show(
					"warning",
					if type(response) == "table" then tostring(response.message) else "Couldn't equip that."
				)
			end
			return
		end
		if unlock.kind ~= "premium" then
			return
		end
		if os.clock() >= (confirmUntil[item.id] or 0) then
			confirmUntil[item.id] = os.clock() + 3 -- spending premium currency needs a second click
			refresh()
			task.delay(3.1, refresh)
			return
		end
		confirmUntil[item.id] = nil
		local ok, response = Net.invoke("BuyCosmetic", item.id)
		if ok and type(response) == "table" and response.ok then
			NotifyController.show("purchase", tostring(response.message))
		else
			NotifyController.show(
				"warning",
				if type(response) == "table" then tostring(response.message) else "Purchase failed."
			)
		end
		refresh()
	end)
	player:GetAttributeChangedSignal("Equipped_" .. item.slot):Connect(refresh)
	player:GetAttributeChangedSignal("Owned_" .. item.id):Connect(refresh)
	if unlock.kind == "tech" then
		local owner = Tech.FeatureOwner[unlock.feature]
		if owner ~= nil then
			player:GetAttributeChangedSignal("Tech_" .. owner):Connect(refresh)
		end
	end
	table.insert(refreshers, refresh)
end

---------------------------------------------------------------- pages
local function newPage(parent: Instance, id: string): ScrollingFrame
	local page: ScrollingFrame = Theme.create("ScrollingFrame", {
		Name = id,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Border,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		Parent = parent,
	}, {
		Theme.padding(Theme.Space.L),
		Theme.create("UIGridLayout", {
			CellPadding = UDim2.fromOffset(Theme.Space.M, Theme.Space.M),
			CellSize = UDim2.fromOffset(218, 252),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	})
	pages[id] = page
	return page
end

local function sectionTitle(parent: Instance, text: string, order: number)
	Components.label({
		Text = text,
		Font = Theme.UIFontHeavy,
		TextSize = 13,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = order,
		Parent = parent,
	})
end

local function buildPages(body: Frame)
	local content: Frame = Theme.create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(200, 0),
		Size = UDim2.new(1, -200, 1, 0),
		Parent = body,
	})

	-- Featured: Starter Pack (while offered), Overclock, best-value Batteries.
	local featured = newPage(content, "featured")
	local starter = productCard(featured, "StarterPack", 1)
	local function refreshStarter()
		local endsAt = player:GetAttribute("StarterPackEndsAt")
		local remaining = if type(endsAt) == "number" then endsAt - os.time() else 0
		starter.frame.Visible = remaining > 0
		if remaining > 0 then
			local h = math.floor(remaining / 3600)
			local m = math.floor(remaining % 3600 / 60)
			local s = remaining % 60
			starter.status.Text = string.format("Offer ends in %d:%02d:%02d", h, m, s)
		end
	end
	table.insert(refreshers, refreshStarter)
	passCard(featured, "Overclock", 2)
	productCard(featured, "BatteriesReactor", 3)
	productCard(featured, "GridBoost", 4)

	local passes = newPage(content, "passes")
	for index, key in sortedKeys(MonetizationConfig.GamePasses) do
		passCard(passes, key, index)
	end

	local batteries = newPage(content, "batteries")
	for index, key in
		sortedKeys(MonetizationConfig.Products, function(p: any): boolean
			return p.category == "currency"
		end)
	do
		productCard(batteries, key, index)
	end

	local boosts = newPage(content, "boosts")
	for index, key in
		sortedKeys(MonetizationConfig.Products, function(p: any): boolean
			return p.category == "boost"
		end)
	do
		local card = productCard(boosts, key, index)
		table.insert(refreshers, function()
			local now = os.time()
			local growth = player:GetAttribute("GrowthBoostUntil")
			local remaining = if type(growth) == "number" then growth - now else 0
			card.status.Text = if remaining > 0
				then string.format(
					"Active: %d:%02d left (buying extends it)",
					math.floor(remaining / 60),
					remaining % 60
				)
				else ""
		end)
	end

	-- Hangar: own layout (smaller tiles, two sections).
	local hangar: ScrollingFrame = Theme.create("ScrollingFrame", {
		Name = "hangar",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Border,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Visible = false,
		Parent = content,
	}, { Theme.padding(Theme.Space.L), Theme.list(Enum.FillDirection.Vertical, Theme.Space.S) })
	pages.hangar = hangar
	for sectionIndex, slot in CosmeticConfig.Slots do
		sectionTitle(
			hangar,
			if slot == "paint" then "PAINT JOBS" else "HATS & ANTENNAS",
			sectionIndex * 2 - 1
		)
		local grid: Frame = Theme.create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = sectionIndex * 2,
			Parent = hangar,
		}, {
			Theme.create("UIGridLayout", {
				CellPadding = UDim2.fromOffset(Theme.Space.M, Theme.Space.M),
				CellSize = UDim2.fromOffset(160, 196),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for index, item in CosmeticConfig.BySlot[slot] do
			cosmeticTile(grid, item, index)
		end
	end
end

local function selectTab(id: string)
	for tabId, page in pages do
		page.Visible = tabId == id
	end
	for tabId, button in tabButtons do
		local active = tabId == id
		button.BackgroundColor3 = if active then C.Raised else C.Panel
		button.TextColor3 = if active then C.Text else C.Muted
	end
	for _, refresh in refreshers do
		refresh()
	end
end

function ShopController:Init()
	local gui = Theme.create("ScreenGui", {
		Name = "Shop",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})
	modal = Components.modal(gui, "SHOP", UDim2.fromScale(0.74, 0.74))
	modal.title.TextColor3 = C.Gold

	local sidebar: Frame = Theme.create("Frame", {
		Name = "Tabs",
		BackgroundColor3 = C.Panel,
		Size = UDim2.new(0, 188, 1, -Theme.Space.M),
		Position = UDim2.fromOffset(Theme.Space.M, 0),
		Parent = modal.body,
	}, {
		Theme.corner(Theme.Radius.M),
		Theme.padding(Theme.Space.S),
		Theme.list(Enum.FillDirection.Vertical, 4),
	})
	for index, tab in TABS do
		local button: TextButton = Theme.create("TextButton", {
			Name = tab.id,
			Text = tab.label,
			Font = Theme.UIFontBold,
			TextSize = 15,
			TextColor3 = C.Muted,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundColor3 = C.Panel,
			AutoButtonColor = true,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = index,
			Parent = sidebar,
		}, { Theme.corner(Theme.Radius.S), Theme.padding(0, Theme.Space.M) })
		button.Activated:Connect(function()
			selectTab(tab.id)
		end)
		tabButtons[tab.id] = button
	end
	buildPages(modal.body)
	modal.onClose = function()
		UIState.notifyClosed("Shop")
	end

	UIState.register("Shop", {
		open = function(tab: string?)
			modal.open()
			selectTab(if tab ~= nil and pages[tab] then tab else "featured")
		end,
		close = function()
			modal.onClose = nil
			modal.close()
			modal.onClose = function()
				UIState.notifyClosed("Shop")
			end
		end,
	})
	gui.Parent = player:WaitForChild("PlayerGui")
end

function ShopController:Start()
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, productId: number, _isPurchased: boolean)
			if userId == player.UserId then
				pendingProducts[productId] = nil
				for _, refresh in refreshers do
					refresh()
				end
			end
		end
	)
	player:GetAttributeChangedSignal("StarterPackEndsAt"):Connect(function()
		for _, refresh in refreshers do
			refresh()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			if modal.isOpen() then
				for _, refresh in refreshers do
					refresh()
				end
			end
		end
	end)
end

return ShopController
