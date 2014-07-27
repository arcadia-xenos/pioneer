-- -- Copyright © 2008-2014 Pioneer Developers. See AUTHORS.txt for details
-- -- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt
-- 
-- v 1.0 (7/19/2014) written by xeno (arcadia_xenos @ irc://irc.freenode.net/#pioneer)
-- v 1.0	Basic functionality: ad creation, play menu, ticket generation, examine tickets,
-- v 1.0	lang / serialization support, play rules.

	-- TODO: instalot should make a window that "spins" large numbers and stops them
	-- 	in a showy way. It would add a lot to playing and should be cheap as soon
	--	as I have a handle on the timing and ui features

	-- TODO: should also make a news message that reports the player win on the bbs
	-- I would think this would run about 1 to 3 months. Unsure how ads run in the system now.
	-- Will have to ask about that at some point.

	-- TODO: the lang elements could be cleaned. There is a ton of one or two word translations.
	-- while writing this I avoided the string.interp method of adding process info into the strings
	-- but I might have a better handle on it now.

	-- NOTE: there is a possiblity of having the lottery setup to buy a # of tickets, then play.
	-- I've thought about this but discarded it as it adds an extra click into the chat processing,
	-- and several more checks including some arbitrary ticket limit. I also disagree with the
	-- idea that would add fun to the game.

	-- NOTE: the odds on this lottery are extremely low vs. payout. If real-life lotteries work this
	-- way they couldn't survive =) I'm sure a revist to add digits to the lottery values will be
	-- needed as pioneer matures.

	-- NOTE: most of the sloppy bits are here because I used the donate to cranks ad as a template
	-- and learned tons while I was making this. It's a first attempt, cut me some slack.

	-- NOTE: I don't know if bitwise is in the version of, or availible to, the pioneer lua stuff.
	-- I considered bit flagging the options because there is no CONST concept, but it may be just
	-- as well that they are the way they are.

local Engine = import("Engine")
local Lang = import("Lang")
local Game = import("Game")
local Comms = import("Comms")
local Event = import("Event")
local Serializer = import("Serializer")
-- local Character = import("Character")
-- local Format = import("Format")

local l = Lang.GetResource("module-lottery")

-- option values to express the Chat area better
local OPTION_HANG_UP		= -1
local OPTION_DEFAULT		= 0
local OPTION_EXAMINE_TICKETS	= 1
local OPTION_PLAY		= 500
local OPTION_PLAY_SHIP_ID	= 501
local OPTION_PLAY_1		= 502
local OPTION_PLAY_5		= 503
local OPTION_PLAY_10		= 504
local OPTION_PLAY_50		= 505

-- unit player money cost per ticket
local ticketCost = 1

-- Useful  between functions
local numberTickets = 0
local purchaseCost = 0

-- Primary lottery components
local ticketsHeld = {}
local winningNumber = 0
local payout = 0

-- load up the titles and messages for the bbs layout
local flavours = {}
for i = 0,5 do
	table.insert(flavours, {
		title     = l["FLAVOUR_" .. i .. "_TITLE"],
		message   = l["FLAVOUR_" .. i .. "_MESSAGE"],
	})
end

-- make a blank table for ads
local ads = {}

-- here is the actual lottery game rules
local playLottery = function (option)

	-- This creates a value number to be used in the lottery
	local genLotteryValue = function ()
		-- By way of analysis: P=(1/10)*(1/10)*(1/10)*(1/10)
		-- which should be something like 1 per ticket in 10000
		local rtnString = ""
		-- 4 digits from 0 to 9
		for i = 1,4,1 do
			rtnString = rtnString .. tostring(Engine.rand:Integer(0,9))
		end
		return rtnString
	end
	
	-- This should match the held tickets to the winning number, or not
	local matchNumbers = function (win, tickets)
		local match = nil
		for digits,_ in pairs(tickets) do
			if digits == win then match = true end
		end
		return match
		--return true
	end

	-- ticket generator
	local genTickets = function ()
		-- select a unique lottery value for each ticket bought
		for i = 1, numberTickets, 1 do
			local digits = genLotteryValue()
			
			-- This value prevents generation from an unlikely, but
			-- potential infinite loop
			local count = 10000
			
			-- generate lottery numbers until we have one not used before
			while ticketsHeld[digits] and count > 0 do
				digits = genLotteryValue()
				count = count - 1
			end
			
			-- the unlikely "generation error"
			if count == 0 then
				-- refund money
				Game.player:AddMoney(purchaseCost)
				-- error back to forms
				return l.ERROR_INSTALOT_TICKET_GEN
			end
			
			-- enter a non-nil value to placehold the key (the ticket digits)
			ticketsHeld[digits] = true
		end
	end

	-- Generate players ticket numbers at random or play ship id digits
	if (option == OPTION_PLAY_SHIP_ID) then
		-- set ticket to ship id (XX-####, so grab the 4th char on, result: ####)
		ticketsHeld[string.sub(Game.player.label,4)] = true
	else
		genTickets()
	end
	
	-- Set the winning number
	winningNumber = genLotteryValue()
	
	-- Construct message by win or lose, set payouts
	local formMessage = l.WINNING_NUMBERS_ARE .. " " .. winningNumber .. '\n\n\n'

	if (matchNumbers(winningNumber, ticketsHeld)) then
		-- winner, winner, chicken dinner!
		formMessage = formMessage .. l.RESULT .. ": " ..
				l["YOU_WIN_" .. Engine.rand:Integer(1,2)]
		-- This results in less payout for more tickets
		payout = (8000000 + Engine.rand:Integer(-1000000,1000000)) * (1 / math.log(numberTickets + 1))
	else
		-- awww!
		formMessage = formMessage .. l.RESULT .. ": " ..
				l["SORRY_" .. Engine.rand:Integer(1,4)]
		payout = 0
	end

	-- pay the winnings
	Game.player:AddMoney(payout)

	return formMessage
end

-- this seems to be the primary bbs interaction session
local onChat = function (form, ref, option)
	local ad = ads[ref]

	if option == OPTION_DEFAULT then
		-- *** Default option *** --
		form:Clear()
		ticketsHeld = {}

		form:SetTitle(ad.title)
		form:SetFace({ seed = ad.faceseed })
		form:SetMessage(ad.message .. '\n\n\n')

		form:AddOption(l.PLAY_SHIP_ID_DIGITS .. " (1 " .. l.TICKET .. ")",  OPTION_PLAY_SHIP_ID)
		form:AddOption("1 "   ..    l.TICKET, OPTION_PLAY_1)
		form:AddOption("5 "   ..   l.TICKETS, OPTION_PLAY_5)
		form:AddOption("10 "  ..   l.TICKETS, OPTION_PLAY_10)
		form:AddOption("50 "  ..   l.TICKETS, OPTION_PLAY_50)

		return

	elseif option == OPTION_HANG_UP then
		-- *** Handle the "hang up" option *** --
		form:Close()
		return

	elseif option == OPTION_EXAMINE_TICKETS then
		-- *** Handle examine tickets option *** --
		local digits = ""
		-- start message: winning number
		local formMessage = l.INSTALOT .. ": " .. l.WINNING_NUMBERS_ARE
					.. " " .. winningNumber .. '\n'
					
		-- add to message: list of tickets
		local digitsList = l.YOU_HELD_TICKET_NUMBERS .. ":"
		for digits,_ in pairs(ticketsHeld) do
			digitsList = digitsList .. " " .. digits
		end
		formMessage = formMessage .. digitsList .. '\n'
		
		-- add to message: payout amount
		--TODO: payout money should be properly formatted
		formMessage = formMessage .. l.PAYOUT .. ": " .. payout

		form:Clear()
		form:SetTitle(l.INSTALOT)
		form:SetMessage(formMessage)
		form:AddOption(l.GO_BACK, OPTION_DEFAULT)

	elseif option > OPTION_PLAY then
		--  *** Handle play options from here out *** --
		if 	option == OPTION_PLAY_SHIP_ID then
			numberTickets = 1
		elseif  option == OPTION_PLAY_1 then
			numberTickets = 1
		elseif  option == OPTION_PLAY_5 then
			numberTickets = 5
		elseif  option == OPTION_PLAY_10 then
			numberTickets = 10
		elseif  option == OPTION_PLAY_50 then
			numberTickets = 50
		end
	
		-- set the play price
		purchaseCost = ticketCost * numberTickets
	
		-- Check for funds, deduct money, continue to play
		if Game.player:GetMoney() < purchaseCost then

			-- Not enough money, y'know.. go dump rada lol
			form:Clear()
			form:SetTitle(l.INSTALOT)
			form:SetMessage(l.YOU_DO_NOT_HAVE_ENOUGH_MONEY)
			form:AddOption(l.GO_BACK, OPTION_DEFAULT)

		else
			-- deduct ticket cost
			Game.player:AddMoney(-purchaseCost)
		
			-- run the play rules
			local rtnMessage = playLottery(option)
		
			-- Construct form to let player know play results
			form:Clear()
			form:SetTitle(l.INSTALOT)
			form:SetMessage(rtnMessage)
			form:AddOption(l.EXAMINE_TICKETS, OPTION_EXAMINE_TICKETS)
			form:AddOption(l.GO_BACK, OPTION_DEFAULT)
		end
	end
end

-- Ive seen this done differently elsewhere
-- Its clean up for removing the ad
local onDelete = function (ref)
	ads[ref] = nil
end

-- This creates the bbs entry
local onCreateBB = function (station)
	local n = Engine.rand:Integer(1, #flavours)
  
	local ad = {
		title    = flavours[n].title,
		message  = flavours[n].message,
		station  = station,
		faceseed = Engine.rand:Integer()
	}

	local ref = station:AddAdvert({
		description = ad.title,
		icon        = "gambling",
		onChat      = onChat,
		onDelete    = onDelete})
	ads[ref] = ad
end

local loaded_data

-- runs during the game load phase
local onGameStart = function ()
	ads = {}

	if not loaded_data then return end

	for k,ad in pairs(loaded_data.ads) do
		local ref = ad.station:AddAdvert({
			description = ad.title,
			icon        = "gambling",
			onChat      = onChat,
			onDelete    = onDelete})
		ads[ref] = ad
	end

	loaded_data = nil
end

-- I do not know about the serialization stuff well enough to know
-- but this was lifted from a working model, so I leave it
local serialize = function ()
	return { ads = ads }
end

local unserialize = function (data)
	loaded_data = data
end

-- submit registrations
Event.Register("onCreateBB", onCreateBB)
Event.Register("onGameStart", onGameStart)

Serializer:Register("Lottery", serialize, unserialize)
