local _, ns = ...

local function SortedKeys()
	local keys = {}
	for key in pairs(ns.db.books) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		return ns.db.books[a].title < ns.db.books[b].title
	end)
	return keys
end

local function StripMarkup(text)
	return (text:gsub("<[^>]+>", ""):gsub("|n", "\n"))
end

local function ListBooks()
	local keys = SortedKeys()
	if #keys == 0 then
		ns.Print("No books saved yet.")
		return
	end
	ns.Print("%d book%s saved:", #keys, #keys == 1 and "" or "s")
	for i, key in ipairs(keys) do
		local book = ns.db.books[key]
		local zone = book.location and book.location.zone or "?"
		print(string.format("  %d. %s |cff888888(%d pages, %s, %s%s)|r", i, book.title, #book.pages, zone,
			tostring(book.material), book.complete and "" or ", incomplete"))
	end
end

-- Temporary chat reader until the real UI exists.
local function ReadBook(index)
	local key = SortedKeys()[index]
	if not key then
		ns.Print("No book #%s. Use /bk list.", tostring(index))
		return
	end
	local book = ns.db.books[key]
	ns.Print("|cffffd100%s|r", book.title)
	for i, page in ipairs(book.pages) do
		print(string.format("|cffffd100-- Page %d --|r", i))
		print(StripMarkup(page))
	end
end

local function Probe()
	local version, build, date, interface = GetBuildInfo()
	ns.Print("Probe: build %s.%s (%s), interface %s, WOW_PROJECT_ID=%s", version, build, date, tostring(interface),
		tostring(WOW_PROJECT_ID))

	local apis = {
		"ItemTextGetItem", "ItemTextGetText", "ItemTextGetPage", "ItemTextGetMaterial", "ItemTextHasNextPage",
		"ItemTextNextPage", "ItemTextPrevPage", "ItemTextGetCreator", "issecretvalue",
	}
	local missing = {}
	for _, name in ipairs(apis) do
		if type(_G[name]) ~= "function" then
			missing[#missing + 1] = name
		end
	end
	ns.Print("ItemText APIs: %s", #missing == 0 and "all present" or ("MISSING " .. table.concat(missing, ", ")))
	ns.Print("C_Map: %s, OpenMailFrame: %s", tostring(C_Map ~= nil), tostring(OpenMailFrame ~= nil))

	-- Don't load Blizzard_Collections ourselves: loading it from addon code taints it.
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded("Blizzard_Collections")
	if not loaded or not CollectionsJournal then
		ns.Print("Collections UI not loaded yet. Press Shift-P once, then run /bk probe again.")
		return
	end
	local container = CollectionsJournal.TabContainer
	for i, tab in ipairs(container and container.Tabs or {}) do
		print(string.format("  Tab %d: %s shown=%s", i, tostring(tab.tooltipText), tostring(tab:IsShown())))
	end
	ns.Print("Books tab: %s", BookkeeperCollectionsTab and "present" or "MISSING")
end

local function Help()
	ns.Print("Commands:")
	print("  /bk - open the library window (also a tab in Collections, Shift-P)")
	print("  /bk list - list saved books")
	print("  /bk read <number> - print a saved book to chat")
	print("  /bk plaques - toggle saving plaques, graves and monuments (off by default)")
	print("  /bk debug - toggle debug messages")
	print("  /bk probe - check this client for the APIs the addon needs")
	print("  /bk wipe confirm - delete ALL saved books (all characters)")
end

SLASH_BOOKKEEPER1 = "/bk"
SLASH_BOOKKEEPER2 = "/bookkeeper"
SlashCmdList.BOOKKEEPER = function(msg)
	local cmd, arg = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		ns.ToggleWindow()
	elseif cmd == "list" then
		ListBooks()
	elseif cmd == "read" then
		ReadBook(tonumber(arg))
	elseif cmd == "debug" then
		ns.db.settings.debug = not ns.db.settings.debug
		ns.Print("Debug %s.", ns.db.settings.debug and "on" or "off")
	elseif cmd == "plaques" then
		ns.db.settings.includePlaques = not ns.db.settings.includePlaques
		ns.Print("Plaques, graves and monuments will %s.",
			ns.db.settings.includePlaques and "now be saved too" or "no longer be saved")
	elseif cmd == "probe" then
		Probe()
	elseif cmd == "wipe" and arg == "confirm" then
		wipe(ns.db.books)
		ns.OnBooksChanged()
		ns.Print("All saved books deleted.")
	else
		Help()
	end
end
