local _, ns = ...

-- The server only sends the page currently shown, so when a book opens we flip
-- forward through every page (saving each), then flip back to page 1.
-- Longest book object in Forever is 18 pages (War of the Three Hammers, per
-- Wowhead, Oct 2026); 30 leaves room for readable items and future books.
local MAX_PAGES = 30
-- Forward and back through MAX_PAGES, plus slack; a hard stop if paging misbehaves.
local MAX_STEPS = MAX_PAGES * 2 + 10

local session

-- Turn the page on the next frame, never from inside ITEM_TEXT_READY. When pages
-- are cached the client fires ITEM_TEXT_READY synchronously inside
-- ItemTextNextPage/PrevPage, so turning from the handler nests every page (plus
-- Blizzard's ItemTextFrame redraw) on the C stack - a 14-page book overflowed it.
local function TurnPage(s, turn)
	s.steps = (s.steps or 0) + 1
	if s.steps > MAX_STEPS then
		ns.Debug("Stopped paging '%s' after %d steps", s.title, s.steps)
		session = nil
		return
	end
	C_Timer.After(0, function()
		-- Skip if the book was closed or another one opened in the meantime.
		if session == s then
			turn()
		end
	end)
end

local function IsReadingMail()
	return OpenMailFrame and OpenMailFrame:IsShown()
end

local function GetLocation()
	local loc = {
		zone = ns.Safe(GetZoneText()),
		subzone = ns.Safe(GetSubZoneText()),
	}
	local mapID = ns.Safe(C_Map.GetBestMapForUnit("player"))
	if mapID then
		loc.mapID = mapID
		local pos = C_Map.GetPlayerMapPosition(mapID, "player")
		if pos then
			local x, y = pos:GetXY()
			loc.x, loc.y = ns.Safe(x), ns.Safe(y)
		end
	end
	return loc
end

local function GetObjectGUID()
	local guid = ns.Safe(UnitGUID("npc"))
	if guid and guid:match("^GameObject") then
		return guid
	end
	return nil
end

local function SaveSession(s, complete)
	local first = s.pages[1]
	if not first then
		ns.Debug("Nothing captured for '%s'", s.title)
		return
	end

	local key = s.title .. ":" .. ns.Hash(first)
	local now = time()
	local char = ns.CharacterKey()
	local book = ns.db.books[key]
	local isNew = not book

	if isNew then
		book = {
			title = s.title,
			material = s.material,
			pages = {},
			location = s.location,
			objectGUID = s.objectGUID,
			firstFound = now,
			foundBy = {},
			unread = true,
		}
		ns.db.books[key] = book
	end

	-- Never replace a complete copy with a partial one.
	if complete or not book.complete then
		book.pages = s.pages
		book.complete = complete
	end
	book.material = book.material or s.material
	book.creator = book.creator or s.creator
	if book.fullPage == nil then
		book.fullPage = s.fullPage
	end
	book.lastRead = now
	book.foundBy[char] = book.foundBy[char] or now

	if ns.OnBooksChanged then
		ns.OnBooksChanged()
	end

	if isNew then
		ns.Print("Saved \"%s\" (%d page%s)%s.", s.title, #s.pages, #s.pages == 1 and "" or "s",
			complete and "" or ", incomplete")
	else
		ns.Debug("Updated \"%s\"", s.title)
	end
end

ns.RegisterEvent("ITEM_TEXT_BEGIN", function()
	if IsReadingMail() then
		session = nil
		return
	end
	session = {
		title = ns.Safe(ItemTextGetItem()) or "Untitled",
		pages = {},
		phase = "forward",
		location = GetLocation(),
		objectGUID = GetObjectGUID(),
	}
	ns.Debug("Begin: '%s' guid=%s", session.title, tostring(session.objectGUID))
end)

ns.RegisterEvent("ITEM_TEXT_READY", function()
	local s = session
	if not s then
		return
	end

	-- Secret values can't be compared, hashed or saved; if the client ever hides
	-- book text this way, drop the book rather than erroring.
	local text = ItemTextGetText()
	if issecretvalue and issecretvalue(text) then
		ns.Debug("Page text for '%s' is restricted by the client; not saving", s.title)
		session = nil
		return
	end

	local page = ns.Safe(ItemTextGetPage()) or 1
	s.material = s.material or ns.Safe(ItemTextGetMaterial())

	if not ns.ShouldKeep(s.material) then
		ns.Debug("Skipping '%s': material %s is not a book", s.title, tostring(s.material))
		session = nil
		return
	end

	if s.phase == "forward" then
		-- A page we already have means the client didn't advance; treat it as the end.
		local repeated = s.pages[page] ~= nil
		s.pages[page] = text or ""
		if page == 1 and not repeated then
			s.creator = ns.Safe(ItemTextGetCreator())
			s.fullPage = ItemTextIsFullPage and ItemTextIsFullPage() or nil
		end
		ns.Debug("Page %d captured (material=%s)", page, tostring(s.material))
		local hasNext = not repeated and ItemTextHasNextPage()
		if hasNext and page < MAX_PAGES then
			TurnPage(s, ItemTextNextPage)
			return
		end
		-- Stopping at the cap with pages left means the copy is truncated.
		if hasNext then
			ns.Debug("'%s' has more than %d pages; saved as incomplete", s.title, MAX_PAGES)
		end
		SaveSession(s, not hasNext)
		if page > 1 then
			s.phase = "rewind"
			TurnPage(s, ItemTextPrevPage)
		else
			session = nil
		end
	elseif s.phase == "rewind" then
		if page > 1 then
			TurnPage(s, ItemTextPrevPage)
		else
			session = nil
		end
	end
end)

ns.RegisterEvent("ITEM_TEXT_CLOSED", function()
	local s = session
	session = nil
	if s and s.phase == "forward" then
		SaveSession(s, false)
	end
end)
