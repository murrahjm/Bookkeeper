local _, ns = ...

ns.ICON = "Interface\\Icons\\INV_Misc_Book_09"
ns.PLAQUE_ICON = "Interface\\Icons\\INV_Misc_StoneTablet_05"

local LIST_WIDTH = 250
local ROW_HEIGHT = 40
local HEADER_HEIGHT = 24
local HTML_TAGS = { "P", "H1", "H2", "H3" }

-- Mirrors ItemTextFrame's default fonts when the global isn't available.
local FALLBACK_FONTS = { P = QuestFont, H1 = QuestFont, H2 = QuestFont, H3 = QuestFont }

local panels = {}

function ns.OnBooksChanged()
	for _, panel in ipairs(panels) do
		if panel:IsShown() then
			panel:Refresh()
		end
	end
	if ns.UpdateTabGlow then
		ns.UpdateTabGlow()
	end
end

-- Books stay "new" (glowing) until clicked in the library.
function ns.MarkRead(key)
	local book = ns.db.books[key]
	if book and book.unread then
		book.unread = nil
		ns.OnBooksChanged()
	end
end

local function FormatZone(book)
	local loc = book.location
	if not loc or not loc.zone then
		return ""
	end
	if loc.subzone and loc.subzone ~= "" and loc.subzone ~= loc.zone then
		return loc.subzone .. ", " .. loc.zone
	end
	return loc.zone
end

local function FormatInfo(book)
	local parts = {}
	local zone = FormatZone(book)
	if zone ~= "" then
		local loc = book.location
		if loc.x and loc.y then
			zone = string.format("%s (%.1f, %.1f)", zone, loc.x * 100, loc.y * 100)
		end
		parts[#parts + 1] = "Found in " .. zone
	end
	if book.firstFound then
		parts[#parts + 1] = date("%b %d, %Y", book.firstFound)
	end
	if not book.complete then
		parts[#parts + 1] = "incomplete - reopen to finish"
	end
	return table.concat(parts, "  -  ")
end

local function Matches(book, query)
	if query == "" or book.title:lower():find(query, 1, true) then
		return true
	end
	-- Zone and subzone, so "thunder" finds everything found in Thunder Bluff.
	if FormatZone(book):lower():find(query, 1, true) then
		return true
	end
	for _, page in ipairs(book.pages) do
		if page:lower():find(query, 1, true) then
			return true
		end
	end
	return false
end

-- HTML pages can't be joined into one document, so the scrolling view flattens them to plain text.
local function ToPlain(text)
	if not text:find("^%s*<[Hh][Tt][Mm][Ll]>") then
		return text
	end
	text = text:gsub("<[Bb][Rr]%s*/?>", "\n")
	text = text:gsub("</[PpHh]%d?>", "\n")
	text = text:gsub("<[^>]+>", "")
	text = text:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\""):gsub("&amp;", "&")
	return text
end

local function CreatorText(book)
	if not book.creator then
		return ""
	end
	return "\n\n" .. (ITEM_TEXT_FROM or "From") .. "\n" .. book.creator .. "\n"
end

-- Where each original page starts in the joined text, as a fraction of its length.
-- Used to keep your place when switching between paged and scrolling views.
local function PageStartFractions(book)
	local lengths, total = {}, 0
	for i, raw in ipairs(book.pages) do
		lengths[i] = #strtrim(ToPlain(raw))
		total = total + lengths[i]
	end
	local fractions, before = {}, 0
	for i, length in ipairs(lengths) do
		fractions[i] = total > 0 and before / total or 0
		before = before + length
	end
	return fractions
end

local LibraryPanelMixin = {}

function LibraryPanelMixin:GetPages(book)
	if ns.db.settings.continuous then
		local parts = {}
		for i, raw in ipairs(book.pages) do
			parts[i] = strtrim(ToPlain(raw))
		end
		return { table.concat(parts, "\n\n") .. CreatorText(book) }
	end

	local from = CreatorText(book)
	if from == "" then
		return book.pages
	end
	local pages = {}
	for i, text in ipairs(book.pages) do
		pages[i] = text .. from
	end
	return pages
end

function LibraryPanelMixin:SetContinuous(enabled)
	local book = self:GetSelectedBook()
	local page = 1
	if book then
		local fractions = PageStartFractions(book)
		if enabled then
			self.pendingScrollFraction = fractions[self.page or 1]
		else
			-- Find the original page whose text is at the top of the view.
			local r = self.Reader
			local height = r.Text:GetHeight()
			local position = height > 0 and r.Scroll:GetVerticalScroll() / height or 0
			for i, start in ipairs(fractions) do
				if start <= position then
					page = i
				end
			end
		end
	end
	ns.db.settings.continuous = enabled
	self:ShowPage(page)
end

function LibraryPanelMixin:GetSelectedBook()
	return self.selectedKey and ns.db.books[self.selectedKey]
end

local function SortByTitle(a, b)
	return a.book.title:lower() < b.book.title:lower()
end

function LibraryPanelMixin:Refresh()
	local query = strtrim(self.SearchBox:GetText() or ""):lower()
	local books, others = {}, {}
	for key, book in pairs(ns.db.books) do
		if Matches(book, query) then
			local section = ns.IsBookMaterial(book.material) and books or others
			section[#section + 1] = { key = key, book = book }
		end
	end
	table.sort(books, SortByTitle)
	table.sort(others, SortByTitle)

	-- Section headers only appear once there's something besides books.
	local list = {}
	local showHeaders = #others > 0
	local function AddSection(id, title, items)
		if #items == 0 then
			return
		end
		local collapsed = showHeaders and ns.db.settings.collapsed[id]
		if showHeaders then
			list[#list + 1] = { header = id, title = title, count = #items, collapsed = collapsed }
		end
		if not collapsed then
			for _, item in ipairs(items) do
				list[#list + 1] = item
			end
		end
	end
	AddSection("books", "Books", books)
	AddSection("other", "Plaques & Monuments", others)

	local retain = ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition
	self.ScrollBox:SetDataProvider(CreateDataProvider(list), retain)
	local total, unread = ns.CountBooks()
	self.CountText:SetFormattedText("%d collected%s", total,
		unread > 0 and string.format(" (|cff40ff40%d new|r)", unread) or "")
	-- The setting is shared, so the window and the Collections tab stay in sync.
	self.ContinuousCheck:SetChecked(ns.db.settings.continuous)

	if not self:GetSelectedBook() then
		local first = books[1] or others[1]
		self.selectedKey = first and first.key
		self.page = 1
	end
	self:UpdateSelection()
	self:ShowPage(self.page or 1)
end

function LibraryPanelMixin:SelectBook(key)
	self.selectedKey = key
	self.page = 1
	self:UpdateSelection()
	self:ShowPage(1)
end

function LibraryPanelMixin:UpdateSelection()
	local key = self.selectedKey
	self.ScrollBox:ForEachFrame(function(row)
		row.Selected:SetShown(row.key ~= nil and row.key == key)
	end)
end

function LibraryPanelMixin:SetMaterialBackground(material)
	local r = self.Reader
	if material == "Parchment" or material == "ParchmentLarge" then
		for _, corner in ipairs(r.Corners) do
			corner:Hide()
		end
		local atlas = "Book-bg"
		if material == "Parchment" then
			atlas = QuestTextContrast and QuestTextContrast.GetDefaultBackgroundAtlas() or "QuestBG-Parchment"
		end
		r.PageBg:SetAtlas(atlas)
		r.PageBg:Show()
	else
		r.PageBg:Hide()
		local base = "Interface\\ItemTextFrame\\ItemText-" .. material .. "-"
		for _, corner in ipairs(r.Corners) do
			corner:SetTexture(base .. corner.suffix)
			corner:Show()
		end
	end
end

function LibraryPanelMixin:ShowPage(page)
	local r = self.Reader
	local book = self:GetSelectedBook()
	r.Content:SetShown(book ~= nil)
	r.Empty:SetShown(book == nil)
	if not book then
		self:SetMaterialBackground("Parchment")
		return
	end

	local material = book.material or "Parchment"
	local fonts = ITEM_TEXT_FONTS and (ITEM_TEXT_FONTS[material] or ITEM_TEXT_FONTS.default) or FALLBACK_FONTS
	for _, tag in ipairs(HTML_TAGS) do
		r.Text:SetFontObject(tag, fonts[tag] or QuestFont)
	end

	local pages = self:GetPages(book)
	local numPages = math.max(#pages, 1)
	page = math.min(math.max(page, 1), numPages)
	self.page = page

	local textColor, titleColor = { 0.18, 0.12, 0.06 }, { 0, 0, 0 }
	if GetMaterialTextColors then
		local light = QuestTextContrast and QuestTextContrast.UseLightText()
		textColor, titleColor = GetMaterialTextColors(light and "Stone" or material)
	end
	for _, tag in ipairs(HTML_TAGS) do
		local c = (material == "ParchmentLarge" and tag ~= "P") and titleColor or textColor
		r.Text:SetTextColor(tag, c[1], c[2], c[3])
	end
	r.Title:SetTextColor(titleColor[1], titleColor[2], titleColor[3])
	-- Light titles (Bronze, Silver) need a strong shadow to read on bright art;
	-- dark parchment titles only get a faint one so they don't look heavy.
	local luminance = 0.299 * titleColor[1] + 0.587 * titleColor[2] + 0.114 * titleColor[3]
	if luminance > 0.5 then
		r.Title:SetShadowColor(0, 0, 0, 1)
		r.Title:SetShadowOffset(1.5, -1.5)
	else
		r.Title:SetShadowColor(0, 0, 0, 0.25)
		r.Title:SetShadowOffset(1, -1)
	end
	r.Info:SetTextColor(textColor[1], textColor[2], textColor[3], 0.8)
	r.PageText:SetTextColor(textColor[1], textColor[2], textColor[3])

	self:SetMaterialBackground(material)

	r.Title:SetText(book.title)
	r.Info:SetText(FormatInfo(book))

	r.Text:SetText(pages[page] or "")
	self:UpdateTextHeight()
	r.Scroll:SetVerticalScroll(0)
	-- SimpleHTML may not know its height until it has laid out, so finish next frame.
	local fraction = self.pendingScrollFraction
	self.pendingScrollFraction = nil
	C_Timer.After(0, function()
		self:UpdateTextHeight()
		local offset = 0
		if fraction then
			offset = math.min(fraction * r.Text:GetHeight(), r.Scroll:GetVerticalScrollRange())
		end
		r.Scroll:SetVerticalScroll(offset)
	end)

	r.PageText:SetFormattedText("Page %d of %d", page, numPages)
	r.PageText:SetShown(numPages > 1)
	r.Prev:SetShown(numPages > 1)
	r.Next:SetShown(numPages > 1)
	r.Prev:SetEnabled(page > 1)
	r.Next:SetEnabled(page < numPages)
end

function LibraryPanelMixin:UpdateTextHeight()
	local r = self.Reader
	r.Text:SetWidth(math.max(r.Scroll:GetWidth(), 50))
	r.Text:SetHeight(math.max(r.Text:GetContentHeight() or 0, 1) + 20)
	r.Scroll:UpdateScrollChildRect()
end

local function InitRow(row, data)
	if not row.Title then
		row.Selected = row:CreateTexture(nil, "BACKGROUND")
		row.Selected:SetAllPoints()
		row.Selected:SetColorTexture(1, 0.82, 0, 0.18)

		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.08)

		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetSize(32, 32)
		row.Icon:SetPoint("LEFT", 4, 0)

		-- Same pulsing glow the bags put on new items.
		row.NewGlow = row:CreateTexture(nil, "OVERLAY")
		row.NewGlow:SetAtlas("bags-glow-white")
		row.NewGlow:SetBlendMode("ADD")
		row.NewGlow:SetAllPoints(row.Icon)
		local pulse = row.NewGlow:CreateAnimationGroup()
		pulse:SetLooping("REPEAT")
		pulse:SetToFinalAlpha(true)
		local fade = pulse:CreateAnimation("Alpha")
		fade:SetFromAlpha(1)
		fade:SetToAlpha(0.2)
		fade:SetDuration(0.5)
		fade:SetOrder(1)
		local brighten = pulse:CreateAnimation("Alpha")
		brighten:SetFromAlpha(0.2)
		brighten:SetToAlpha(1)
		brighten:SetDuration(0.5)
		brighten:SetOrder(2)
		row.NewGlowPulse = pulse

		row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		row.Title:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -2)
		row.Title:SetPoint("RIGHT", -6, 0)
		row.Title:SetJustifyH("LEFT")
		row.Title:SetWordWrap(false)

		row.Sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.Sub:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -3)
		row.Sub:SetPoint("RIGHT", -6, 0)
		row.Sub:SetJustifyH("LEFT")
		row.Sub:SetWordWrap(false)

		-- Section header parts. Rows are recycled between headers and books,
		-- so every row has both sets and shows one.
		row.HeaderBg = row:CreateTexture(nil, "BACKGROUND")
		row.HeaderBg:SetAllPoints()
		row.HeaderBg:SetColorTexture(1, 1, 1, 0.06)
		row.Expand = row:CreateTexture(nil, "ARTWORK")
		row.Expand:SetSize(14, 14)
		row.Expand:SetPoint("LEFT", 6, 0)
		row.HeaderText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		row.HeaderText:SetPoint("LEFT", row.Expand, "RIGHT", 6, 0)

		row:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			if self.header then
				local collapsed = ns.db.settings.collapsed
				collapsed[self.header] = not collapsed[self.header] or nil
				self.panel:Refresh()
				return
			end
			self.panel:SelectBook(self.key)
			ns.MarkRead(self.key)
		end)
	end

	local isHeader = data.header ~= nil
	row.header = data.header
	row.key = data.key
	for _, region in ipairs({ row.HeaderBg, row.Expand, row.HeaderText }) do
		region:SetShown(isHeader)
	end
	for _, region in ipairs({ row.Icon, row.Title, row.Sub }) do
		region:SetShown(not isHeader)
	end
	if isHeader then
		row.NewGlow:Hide()
		row.NewGlowPulse:Stop()
		row.HeaderText:SetFormattedText("%s (%d)", data.title, data.count)
		row.Expand:SetTexture(data.collapsed and "Interface\\Buttons\\UI-PlusButton-Up"
			or "Interface\\Buttons\\UI-MinusButton-Up")
		return
	end

	row.Icon:SetTexture(ns.IsBookMaterial(data.book.material) and ns.ICON or ns.PLAQUE_ICON)
	row.NewGlow:SetShown(data.book.unread == true)
	if data.book.unread then
		row.NewGlowPulse:Play()
	else
		row.NewGlowPulse:Stop()
	end
	row.Title:SetText(data.book.title)
	row.Sub:SetText(FormatZone(data.book))
end

local function CreatePageButton(parent, direction)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(32, 32)
	local base = "Interface\\Buttons\\UI-SpellbookIcon-" .. direction .. "Page-"
	button:SetNormalTexture(base .. "Up")
	button:SetPushedTexture(base .. "Down")
	button:SetDisabledTexture(base .. "Disabled")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	return button
end

local function CreateReader(panel)
	local r = CreateFrame("Frame", nil, panel)
	r:SetPoint("TOPLEFT", panel.ListInset, "TOPRIGHT", 6, 0)
	r:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -6, 26)
	r:SetClipsChildren(true)

	r.PageBg = r:CreateTexture(nil, "BACKGROUND")
	r.PageBg:SetAllPoints()

	-- Stone/Marble/etc. pages come as four corner textures (256x256, 64x256, 256x128, 64x128).
	r.Corners = {}
	for _, info in ipairs({
		{ "TopLeft", "TOPLEFT", 0.8, 2 / 3 },
		{ "TopRight", "TOPRIGHT", 0.2, 2 / 3 },
		{ "BotLeft", "BOTTOMLEFT", 0.8, 1 / 3 },
		{ "BotRight", "BOTTOMRIGHT", 0.2, 1 / 3 },
	}) do
		local corner = r:CreateTexture(nil, "BACKGROUND")
		corner.suffix, corner.wScale, corner.hScale = info[1], info[3], info[4]
		corner:SetPoint(info[2])
		corner:Hide()
		r.Corners[#r.Corners + 1] = corner
	end
	r:SetScript("OnSizeChanged", function(self, width, height)
		for _, corner in ipairs(self.Corners) do
			corner:SetSize(width * corner.wScale, height * corner.hScale)
		end
		-- Can fire while CreateReader is still running (layout is forced by the
		-- scroll bar setup), before panel.Reader has been assigned.
		if panel.Reader then
			panel:UpdateTextHeight()
		end
	end)

	r.Empty = r:CreateFontString(nil, "ARTWORK", "QuestFont")
	r.Empty:SetPoint("CENTER")
	r.Empty:SetWidth(300)
	r.Empty:SetText("No books yet.\n\nOpen any book in the world and it will be saved here automatically.")

	local content = CreateFrame("Frame", nil, r)
	content:SetAllPoints()
	r.Content = content

	r.Title = content:CreateFontString(nil, "ARTWORK", "QuestTitleFont")
	r.Title:SetPoint("TOPLEFT", 24, -20)
	r.Title:SetPoint("TOPRIGHT", -24, -20)

	r.Info = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	r.Info:SetPoint("TOPLEFT", r.Title, "BOTTOMLEFT", 0, -6)
	r.Info:SetPoint("TOPRIGHT", r.Title, "BOTTOMRIGHT", 0, -6)

	r.Scroll = CreateFrame("ScrollFrame", nil, content, "ScrollFrameTemplate")
	r.Scroll:SetPoint("TOPLEFT", r.Info, "BOTTOMLEFT", 0, -14)
	r.Scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -30, 44)

	-- ScrollFrameTemplate leaves this off by default (its KeyValue is commented out).
	r.Scroll.ScrollBar:SetHideIfUnscrollable(true)

	r.Text = CreateFrame("SimpleHTML", nil, r.Scroll)
	r.Text:SetSize(300, 1)
	-- Match ItemTextPageText; books with their own HTML alignment still override this.
	for _, tag in ipairs(HTML_TAGS) do
		r.Text:SetJustifyH(tag, "LEFT")
	end
	r.Scroll:SetScrollChild(r.Text)

	r.Prev = CreatePageButton(content, "Prev")
	r.Prev:SetPoint("BOTTOMLEFT", 16, 8)
	r.Prev:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		panel:ShowPage(panel.page - 1)
	end)

	r.Next = CreatePageButton(content, "Next")
	r.Next:SetPoint("BOTTOMRIGHT", -16, 8)
	r.Next:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		panel:ShowPage(panel.page + 1)
	end)

	-- In page mode the wheel scrolls within a long page first, then turns the page
	-- once you're at its top or bottom edge.
	local defaultWheel = r.Scroll:GetScript("OnMouseWheel")
	local function OnMouseWheel(_, delta)
		local scroll = r.Scroll
		if not ns.db.settings.continuous and panel:GetSelectedBook() then
			local position, range = scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()
			local target = panel.page - delta
			local atEdge = (delta > 0 and position <= 1) or (delta < 0 and position >= range - 1)
			if atEdge then
				if target >= 1 and target <= #panel:GetPages(panel:GetSelectedBook()) then
					PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
					-- Going back lands at the bottom of the previous page.
					panel.pendingScrollFraction = delta > 0 and 1 or nil
					panel:ShowPage(target)
				end
				return
			end
		end
		if defaultWheel then
			defaultWheel(scroll, delta)
		else
			local range = scroll:GetVerticalScrollRange()
			scroll:SetVerticalScroll(math.min(math.max(scroll:GetVerticalScroll() - delta * 40, 0), range))
		end
	end
	r.Scroll:SetScript("OnMouseWheel", OnMouseWheel)
	-- Also catch the wheel over the title and page buttons, not just the text.
	r:EnableMouseWheel(true)
	r:SetScript("OnMouseWheel", OnMouseWheel)

	r.PageText = content:CreateFontString(nil, "ARTWORK", "QuestFont")
	r.PageText:SetPoint("BOTTOM", 0, 16)

	return r
end

-- Builds a library panel filling `host`. Each host gets its own panel so the
-- standalone window and the Collections tab never fight over one frame.
function ns.CreateLibraryPanel(host)
	local panel = Mixin(CreateFrame("Frame", nil, host), LibraryPanelMixin)
	panel:SetAllPoints(host)
	panel:Hide()

	panel.SearchBox = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
	panel.SearchBox:SetSize(LIST_WIDTH - 76, 20)
	panel.SearchBox:SetPoint("TOPLEFT", 76, -33)
	panel.SearchBox:HookScript("OnTextChanged", function()
		panel:Refresh()
	end)

	panel.ContinuousCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	panel.ContinuousCheck:SetSize(26, 26)
	panel.ContinuousCheck:SetPoint("LEFT", panel.SearchBox, "RIGHT", 20, 0)
	panel.ContinuousCheck.Text:SetText("Single scrolling page")
	panel.ContinuousCheck:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		panel:SetContinuous(self:GetChecked())
	end)
	panel.ContinuousCheck:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Single scrolling page")
		GameTooltip:AddLine("Shows the whole book as one page you can scroll with the mouse wheel.", 1, 1, 1, true)
		GameTooltip:Show()
	end)
	panel.ContinuousCheck:SetScript("OnLeave", GameTooltip_Hide)

	panel.ListInset = CreateFrame("Frame", nil, panel, "InsetFrameTemplate")
	panel.ListInset:SetWidth(LIST_WIDTH)
	panel.ListInset:SetPoint("TOPLEFT", 4, -60)
	panel.ListInset:SetPoint("BOTTOMLEFT", 4, 26)

	panel.ScrollBox = CreateFrame("Frame", nil, panel.ListInset, "WowScrollBoxList")
	panel.ScrollBox:SetPoint("TOPLEFT", 4, -4)
	panel.ScrollBox:SetPoint("BOTTOMRIGHT", -22, 4)

	panel.ScrollBar = CreateFrame("EventFrame", nil, panel.ListInset, "MinimalScrollBar")
	panel.ScrollBar:SetPoint("TOPLEFT", panel.ScrollBox, "TOPRIGHT", 6, -2)
	panel.ScrollBar:SetPoint("BOTTOMLEFT", panel.ScrollBox, "BOTTOMRIGHT", 6, 2)

	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(function(_, data)
		return data.header and HEADER_HEIGHT or ROW_HEIGHT
	end)
	view:SetElementInitializer("Button", function(row, data)
		row.panel = panel
		InitRow(row, data)
		row.Selected:SetShown(data.key ~= nil and data.key == panel.selectedKey)
	end)
	ScrollUtil.InitScrollBoxListWithScrollBar(panel.ScrollBox, panel.ScrollBar, view)

	panel.CountText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	panel.CountText:SetPoint("BOTTOMLEFT", 12, 8)

	panel.Reader = CreateReader(panel)

	panel:SetScript("OnShow", panel.Refresh)
	panels[#panels + 1] = panel
	return panel
end

-- Standalone window, opened with /bk.
function ns.ToggleWindow()
	local window = ns.window
	if not window then
		window = CreateFrame("Frame", "BookkeeperFrame", UIParent, "PortraitFrameTemplate")
		window:SetSize(703, 606)
		window:SetPoint("CENTER")
		window:SetFrameStrata("HIGH")
		window:SetToplevel(true)
		window:EnableMouse(true)
		window:SetMovable(true)
		window:SetClampedToScreen(true)
		window:RegisterForDrag("LeftButton")
		window:SetScript("OnDragStart", window.StartMoving)
		window:SetScript("OnDragStop", window.StopMovingOrSizing)
		window:SetTitle("Bookkeeper")
		window:SetPortraitToAsset(ns.ICON)
		window:SetScript("OnShow", function()
			PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN)
		end)
		window:SetScript("OnHide", function()
			PlaySound(SOUNDKIT.IG_SPELLBOOK_CLOSE)
		end)
		tinsert(UISpecialFrames, "BookkeeperFrame")
		window:Hide()
		ns.CreateLibraryPanel(window):Show()
		ns.window = window
	end
	window:SetShown(not window:IsShown())
end
