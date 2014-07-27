-- Copyright © 2008-2014 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

local Engine = import("Engine")
local Game = import("Game")
local SpaceStation = import("SpaceStation")
local Event = import("Event")
local ChatForm = import("ChatForm")
local Lang = import("Lang")
local utils = import("utils")

local l = Lang.GetResource("ui-core")

local SmallLabeledButton = import("ui/SmallLabeledButton")

local ui = Engine.ui

local tabGroup

-- TODO: this needs to be inside the bbTable as a sort of bbsTableWidget
-- rowRef: array to tie the station adverts to the ui table
local rowRef = {}


-- ------ AVAILABLE_ONLY CHECK BOX ------ --
-- remember checked state
local enabledOnly = false

-- define a check box
local optionCheckBox = function (getter, setter, caption)
	local cb = ui:CheckBox()
	local initial = getter()
	cb:SetState(initial)
	cb.onClick:Connect(function () setter(cb.isChecked) end)
	return ui:HBox(5):PackEnd({ cb, ui:Label(caption)
			-- color #2CA3FF: r=0.17255, g=0.63922, b=1
			:SetColor({ r = 0.2, g = 0.6, b = 1.0 }) })
end

-- create a toggle to show only availible bbs items
local enabledOnlyToggle = optionCheckBox(
	-- getter anon fn
	function() return enabledOnly end,
	-- setter anon fn
	function(isChecked)
		enabledOnly = not enabledOnly
		if isChecked then
			-- set to enabled ads only
			Event.Queue("onAdvertRemoved",Game.player:GetDockedWith())
		else
			-- set to all ads
			Event.Queue("onAdvertAdded", Game.player:GetDockedWith())
		end
	end,
	-- caption
	l.AVAILABLE_ONLY
)

-- ------ BBS TABLE ------ --
-- create the table for bbs items
local bbTable = ui:Table()
	:SetRowSpacing(5)
	:SetColumnSpacing(10)
	:SetRowAlignment("CENTER")
	:SetMouseEnabled(true)

-- start our bbs chat item is clicked
bbTable.onRowClicked:Connect(function (row)
	local station = Game.player:GetDockedWith()
	local ref = rowRef[station][row+1]
	local ad = SpaceStation.adverts[station][ref]

	local chatFunc = function (form, option)
		return ad.onChat(form, ref, option)
	end
	local removeFunc = function ()
		station:RemoveAdvert(ref)
	end

	local form = ChatForm.New(chatFunc, removeFunc, ref, tabGroup)
	ui:NewLayer(form:BuildWidget())
end)

-- ------ BBS DISPLAY WIDGET ------ --
-- combines the controls and table together

-- TODO: need a pulldown of ad categories to filter by
-- TODO: add an ad description search so that you can find specific phrases
-- TODO: would like the controls at the bottom of the widget, but locked so they don't float up
-- TODO: need to find out if this is something like the right way to build the interface.
local bbsWidget = ui:VBox():PackEnd({enabledOnlyToggle}):PackEnd({bbTable})


-- EVENT HANDLERS --

local updateTable = function (station)
	if Game.player:GetDockedWith() ~= station then return end

	bbTable:ClearRows()

	local adverts = SpaceStation.adverts[station]
	if not adverts then return end

	-- not sure why this didn't enforce rowRef (like everything else)
	local rows = {}

	-- TODO: this "greying out" business is only needed if the availToggle is off
	for i = 1, #rowRef[station] do
		local ad = adverts[rowRef[station][i]]
		local ref = rowRef[station][i]
		local disabled = (type(ad.isEnabled) == "function" and not ad.isEnabled(ref))

		-- from here it's unchanged
		local icon = ad.icon or "default"
		local label = ui:Label(ad.description)
		if disabled then
			label:SetColor({ r = 0.4, g = 0.4, b = 0.4 })
		end
		table.insert(rows, {
			ui:Image("icons/bbs/"..icon..".png", { "PRESERVE_ASPECT" }),
			label,
		})
	end

	bbTable:AddRows(rows)
end

local updateRowRefs = function (station, ref)
	local adverts = SpaceStation.adverts[station]
	if not adverts then return end

	
	-- TODO: There is possibly a way to replace this with a smarttable
	-- TODO: This sort is run a lot and it's almost completely worst case everytime
	-- generate sort map for filling rowRef
	function genRefMapArray (stationAdTable)
		
		-- builds an sequential array of the keys from a passed table
		local function build_key_array(f, s, k)
			local v
			local t = {}
			while true do
			k, v = f(s, k)
			if k == nil then break end
			table.insert(t, k)
			end
			return t
		end
		-- attempt to use the utils given - make a map array and sort it by icons
		local map = build_key_array(pairs(stationAdTable))
		
		-- sort the map using the utils stable merge sort (slow but sure)
		--map = utils.stable_sort(map, function(a,b) return stationAdTable[a].icon < stationAdTable[b].icon end)
		-- for speed we might could use the following:
		table.sort(map, function(a,b) return stationAdTable[a].icon < stationAdTable[b].icon end)
		
		-- fold the (now sorted) map to just the enabled items is toggle button is active
		if enabledOnly then
			-- copy and clear the current ad ref map array (keep order, don't lose sort)
			local tmpMap = utils.build_array(ipairs(map))
 			map = {} -- clear map to be filtered
			
			-- create a predicate fn for filter: it is passed the pairs from the filter iterator
			local mapRefIsEnabled = function (_,ref)
				-- return bool "ad is enabled"
				return 
					-- invert disabled = enabled
					not (
						-- determine if isEnabled fn exists for ad (each can have it's own?)
						type(stationAdTable[ref].isEnabled) == "function" and

						-- determine if disabled: enabled would break fn chk
						not stationAdTable[ref].isEnabled(ref)
					)
			end
			
			-- filter iterates only enabled tmpMap ads, table.insert builds a new map
			for _,ref in utils.filter(mapRefIsEnabled, ipairs(tmpMap)) do table.insert(map,ref) end
		end
		return map
	end 

	-- enum into the rowRef array (which couples the display)
	rowRef[station] = {}
	local map = genRefMapArray(adverts)
	for rowNum = 1, #map do
		rowRef[station][rowNum] = map[rowNum]
	end

	updateTable(station)
end

-- event registration --
Event.Register("onAdvertAdded", updateRowRefs)
Event.Register("onAdvertRemoved", updateRowRefs) -- XXX close form if open
Event.Register("onAdvertChanged", updateTable)

-- main function --
local bulletinBoard = function (args, tg)
	tabGroup = tg
	updateTable(Game.player:GetDockedWith())
	return bbsWidget
end

-- return main fn
return bulletinBoard
