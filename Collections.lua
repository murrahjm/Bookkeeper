local _, ns = ...

-- Adds a "Books" side tab to the Collections journal (Shift-P).
-- Our tab is deliberately NOT added to TabContainer.Tabs, so Blizzard's tab code
-- never iterates over it; we only react to their functions via hooksecurefunc.

local BLIZZARD_PANELS = {
	"MountJournal", "PetJournal", "ToyBox", "HeirloomsJournal", "WardrobeCollectionFrame", "WarbandSceneJournal",
}

local tab, panel
local active = false
-- Set when the journal opened in combat while Books was the remembered tab.
local activateAfterCombat = false

local function PositionTab()
	local container = CollectionsJournal.TabContainer
	local last
	for _, blizzTab in ipairs(container.Tabs) do
		if blizzTab:IsShown() then
			last = blizzTab
		end
	end
	tab:ClearAllPoints()
	if last then
		tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -2)
	else
		tab:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -60)
	end
end

local function Deactivate()
	if not active then
		return
	end
	active = false
	tab:SetChecked(false)
	panel:Hide()
end

local function Activate()
	if InCombatLockdown() then
		ns.Print("The Books tab can't be opened during combat.")
		return
	end
	active = true
	ns.db.settings.collectionsTabBooks = true

	for _, blizzTab in ipairs(CollectionsJournal.TabContainer.Tabs) do
		blizzTab:SetChecked(false)
	end
	tab:SetChecked(true)
	for _, name in ipairs(BLIZZARD_PANELS) do
		local frame = _G[name]
		if frame and frame:IsShown() then
			frame:Hide()
		end
	end
	CollectionsJournal:SetTitle("Books")

	panel = panel or ns.CreateLibraryPanel(CollectionsJournal)
	panel:Show()
end

-- Pulse the Books tab while any book is still unread.
function ns.UpdateTabGlow()
	if tab then
		local _, unread = ns.CountBooks()
		tab:SetTabGlowAnimationPlaying(unread > 0)
	end
end

local function Setup()
	local cj = CollectionsJournal
	if not (cj and cj.TabContainer and cj.TabContainer.Tabs) then
		ns.Debug("Collections journal layout not recognized; Books tab disabled.")
		return
	end

	tab = CreateFrame("Frame", "BookkeeperCollectionsTab", cj.TabContainer, "LargeSideTabButtonTemplate")
	tab.tooltipText = "Books"
	tab.Icon:SetTexture(ns.ICON)
	if tab.SetFillToInterior then
		tab:SetFillToInterior(true)
	end
	tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
		if button == "LeftButton" and upInside then
			Activate()
		end
	end)
	tab:SetChecked(false)

	hooksecurefunc("CollectionsJournal_CheckAndDisplayTabs", PositionTab)
	hooksecurefunc("CollectionsJournal_UpdateSelectedTab", Deactivate)
	-- Only user tab clicks go through SetTab, so this tracks "last tab chosen".
	hooksecurefunc("CollectionsJournal_SetTab", function()
		ns.db.settings.collectionsTabBooks = false
	end)
	-- Runs after Blizzard's OnShow, which has already re-selected its own tab.
	cj:HookScript("OnShow", function()
		if not ns.db.settings.collectionsTabBooks then
			return
		end
		if InCombatLockdown() then
			-- Quietly show Blizzard's tab for now and switch once combat ends.
			activateAfterCombat = true
		else
			Activate()
		end
	end)
	cj:HookScript("OnHide", function()
		activateAfterCombat = false
	end)
	ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if activateAfterCombat and cj:IsShown() and ns.db.settings.collectionsTabBooks then
			Activate()
		end
		activateAfterCombat = false
	end)

	PositionTab()
	ns.UpdateTabGlow()
	ns.Debug("Books tab added to the Collections journal.")
end

function ns.SetupCollectionsTab()
	EventUtil.ContinueOnAddOnLoaded("Blizzard_Collections", Setup)
end
