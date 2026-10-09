local addonName, ns = ...

ns.DB_VERSION = 1

local PREFIX = "|cffc8a2ffBookkeeper|r: "

function ns.Print(fmt, ...)
	print(PREFIX .. string.format(fmt, ...))
end

function ns.Debug(fmt, ...)
	if ns.db and ns.db.settings.debug then
		print("|cff888888[BK debug]|r " .. string.format(fmt, ...))
	end
end

-- Midnight-era APIs may hand back "secret" values that can't be stored or compared.
function ns.Safe(value)
	if issecretvalue and issecretvalue(value) then
		return nil
	end
	return value
end

-- djb2 string hash; plain arithmetic since Lua 5.1 has no bitwise operators.
function ns.Hash(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + s:byte(i)) % 4294967296
	end
	return string.format("%08x", h)
end

function ns.CharacterKey()
	local name = ns.Safe(UnitName("player")) or "Unknown"
	local realm = ns.Safe(GetRealmName()) or "Unknown"
	return name .. "-" .. realm
end

-- Books are printed on parchment; plaques, graves and monuments report Stone,
-- Marble, Silver, Bronze, etc. A nil material means the client default, Parchment.
function ns.IsBookMaterial(material)
	return material == nil or material == "Parchment" or material == "ParchmentLarge"
end

function ns.ShouldKeep(material)
	return ns.db.settings.includePlaques or ns.IsBookMaterial(material)
end

function ns.CountBooks()
	local total, unread = 0, 0
	for _, book in pairs(ns.db.books) do
		total = total + 1
		if book.unread then
			unread = unread + 1
		end
	end
	return total, unread
end

local function InitDB()
	BookkeeperDB = BookkeeperDB or {}
	local db = BookkeeperDB
	db.version = db.version or ns.DB_VERSION
	db.books = db.books or {}
	db.settings = db.settings or {}
	if db.settings.debug == nil then
		db.settings.debug = false
	end
	db.settings.collapsed = db.settings.collapsed or {}
	if db.settings.continuous == nil then
		db.settings.continuous = true
	end
	db.settings.reflow = nil -- replaced by settings.continuous in 0.3.1

	-- 0.4.0 started skipping plaques; drop any saved before that.
	if not db.plaquesPruned then
		for key, book in pairs(db.books) do
			if not ns.IsBookMaterial(book.material) then
				db.books[key] = nil
			end
		end
		db.plaquesPruned = true
	end
	ns.db = db
end

local frame = CreateFrame("Frame")
ns.eventFrame = frame
ns.handlers = {}

frame:SetScript("OnEvent", function(_, event, ...)
	local handler = ns.handlers[event]
	if handler then
		handler(...)
	end
end)

function ns.RegisterEvent(event, handler)
	ns.handlers[event] = handler
	frame:RegisterEvent(event)
end

ns.RegisterEvent("ADDON_LOADED", function(name)
	if name ~= addonName then
		return
	end
	InitDB()
	frame:UnregisterEvent("ADDON_LOADED")
	ns.SetupCollectionsTab()
end)
