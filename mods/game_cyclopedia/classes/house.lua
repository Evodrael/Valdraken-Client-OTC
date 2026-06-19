---------------------------
-- Lua code author: R1ck --
-- Company: VICTOR HUGO PERENHA - JOGOS ON LINE --
---------------------------

House = {}
House.__index = House

local lastSelectedHouse = nil
local selectedHouseId = 0
local currentHouseList = {}
local houseList = {}

-- Sort fields
local currentStateSort = 1 -- All states
local currentStatusSort = 1 -- Name

local showGuildHalls = false
local currentTownName = ""
local infoWindow = nil
local housesInfo = {}
local ownHousesFallbackRequested = false
local selectedHouseMarkerId = nil
local cyclopediaMapHouseMarkerId = nil
local houseStaticIdAliases = nil
local selectedHousePosition = nil
local houseSatelliteAssetsDir = nil
local houseSatelliteResolvedAssetsDir = nil
local houseSatelliteLoadedFloors = {}
local staticHouseCache = nil
local staticHouseNameIndex = nil
local getStaticHouseList = nil

local HOUSE_MINIMAP_MARKER_ICON = "data/images/game/minimap/icon/icon-map-house.png"
local HOUSE_MINIMAP_MARKER_SIZE = { width = 11, height = 11 }

local function getCurrentHouseData(houseId)
	houseId = tonumber(houseId) or 0
	return currentHouseList[houseId] or currentHouseList[tostring(houseId)]
end

-- Resolve the houseId tied to a list-row widget. Reads widget.data first (set by
-- onRecvHousesData) and falls back to getActionId for compatibility. Centralized so
-- every action handler stays correct even on builds where setActionId is a no-op.
local function resolveRowHouseId(rowWidget)
	if not rowWidget then return 0 end
	local data = rowWidget.data
	if not data and rowWidget.main then data = rowWidget.main.data end
	local id = data and tonumber(data.houseId) or 0
	if id ~= 0 then return id end
	if rowWidget.getActionId then
		id = tonumber(rowWidget:getActionId()) or 0
		if id ~= 0 then return id end
	end
	if rowWidget.main and rowWidget.main.getActionId then
		id = tonumber(rowWidget.main:getActionId()) or 0
	end
	return id or 0
end

local function listResourceDirectory(path)
	if not g_resources or not g_resources.listDirectoryFiles then
		return {}
	end

	local ok, files = pcall(g_resources.listDirectoryFiles, path)
	if ok and type(files) == "table" then
		return files
	end

	return {}
end

local function resourceDirectoryHasMapChunks(path)
	for _, fileName in pairs(listResourceDirectory(path)) do
		fileName = tostring(fileName)
		if fileName:find("satellite%-") or fileName:find("minimap%-") or fileName:find("realmap%-") then
			return true
		end
	end
	return false
end

local function resolveHouseSatelliteAssetsDir()
	if houseSatelliteResolvedAssetsDir then
		return houseSatelliteResolvedAssetsDir
	end

	local candidates = {}
	local seen = {}
	local function addCandidate(path)
		if path and not seen[path] then
			seen[path] = true
			table.insert(candidates, path)
		end
	end

	-- IMPORTANT: order must match RealMap.load() (realmap first, then things, etc.).
	-- The satellite chunk cache is keyed by directory: if the houses tab picks a different
	-- directory than the HUD minimap, loadFloors() drops the cache and the HUD's HD Map Mode
	-- goes dark until the client restarts.
	local clientVersion = g_game and g_game.getClientVersion and tonumber(g_game.getClientVersion()) or 0
	if clientVersion > 0 then
		addCandidate(string.format("/realmap/%d", clientVersion))
		addCandidate(string.format("/things/%d", clientVersion))
		addCandidate(string.format("/data/realmap/%d", clientVersion))
		addCandidate(string.format("/data/things/%d", clientVersion))
	end

	local versions = {}
	for _, root in ipairs({"/realmap", "/things", "/data/realmap", "/data/things"}) do
		for _, entry in pairs(listResourceDirectory(root)) do
			local version = tonumber(tostring(entry):match("(%d+)$"))
			if version then
				table.insert(versions, { root = root, version = version })
			end
		end
	end
	table.sort(versions, function(a, b) return a.version > b.version end)

	for _, entry in ipairs(versions) do
		addCandidate(string.format("%s/%d", entry.root, entry.version))
	end
	addCandidate("/realmap/1524")
	addCandidate("/things/1524")
	addCandidate("/data/realmap/1524")
	addCandidate("/data/things/1524")

	for _, path in ipairs(candidates) do
		if resourceDirectoryHasMapChunks(path) then
			houseSatelliteResolvedAssetsDir = path
			return path
		end
	end

	houseSatelliteResolvedAssetsDir = candidates[1]
	return houseSatelliteResolvedAssetsDir
end

local function getHouseRequestTownName(townName)
	return townName == "Own Houses" and "" or townName
end

local function normalizeStaticHouseData(houseId, house)
	if type(house) ~= "table" then
		return nil
	end

	house.id = house.id or houseId
	house.name = house.name or house[1] or ("House #" .. tostring(houseId))
	house.rent = tonumber(house.rent or house[2]) or 0
	house.beds = house.beds or house[3] or 0
	house.sqms = house.sqms or house.size or house[4] or 0
	if not house.position then
		local entryX = tonumber(house.entryx or house.entryX)
		local entryY = tonumber(house.entryy or house.entryY)
		local entryZ = tonumber(house.entryz or house.entryZ)
		if entryX and entryY and entryZ then
			house.position = { x = entryX, y = entryY, z = entryZ }
		end
	end
	house.guildHall = house.guildHall
	if house.guildHall == nil then
		house.guildHall = house.GH == 1 or house[5] == true
	end
	house[1] = house.name
	house[2] = house.rent
	house[3] = house.beds
	house[4] = house.sqms
	house[5] = house.guildHall
	return house
end

local function isSamePlayerName(first, second)
	return string.lower(first or "") == string.lower(second or "")
end

local function normalizePosition(position)
	if type(position) ~= "table" then
		return nil
	end

	local x = tonumber(position.x or position[1] or 0) or 0
	local y = tonumber(position.y or position[2] or 0) or 0
	local z = tonumber(position.z or position[3] or -1) or -1
	if x <= 0 or y <= 0 or z < 0 then
		return nil
	end

	return { x = x, y = y, z = z }
end

local function isAuctionState(state)
	local value = tonumber(state) or -1
	return value == 0 or value == 1
end

local function isRentedState(state)
	local value = tonumber(state) or -1
	return value == 2 or value == 3 or value == 4
end

local function bindHouseListWidget(widget)
	if not widget then
		return
	end

	-- Click resolves the houseId from widget.data, not getActionId(). The C++ setActionId
	-- on UIWidget was historically a no-op stub that always returned 0, which silently
	-- broke house selection (the click handler bailed at the actionId==0 guard). Reading
	-- widget.data is robust regardless of which build of the source the user is running.
	widget.onClick = function(self)
		House.onSelectHouse(self)
	end

	if widget.main then
		widget.main.onClick = function(self)
			-- Propagate data from main → parent so onSelectHouse can use widget.data
			-- whether the click originated on main or on the HouseData wrapper.
			House.onSelectHouse(self)
		end

		for _, child in pairs(widget.main:getChildren()) do
			if child.setPhantom then
				child:setPhantom(true)
			end
		end
	end
end

local function ensureHouseSatelliteFloorsLoaded(virtualFloor)
	virtualFloor = tonumber(virtualFloor)
	if not virtualFloor or not g_satelliteMap or not g_satelliteMap.loadFloors or not g_game or not g_game.getClientVersion then
		return
	end

	local assetsDir = resolveHouseSatelliteAssetsDir()
	if not assetsDir then
		return
	end

	-- Never call g_satelliteMap.clear() here. The chunk cache is global, so wiping it would
	-- disable the HUD minimap's HD Map Mode (only restored by restarting the client).
	-- loadFloors() already handles directory transitions internally without dropping unrelated chunks.
	if assetsDir ~= houseSatelliteAssetsDir then
		houseSatelliteAssetsDir = assetsDir
		houseSatelliteLoadedFloors = {}
	end

	local floorMax = virtualFloor <= 7 and 7 or virtualFloor
	local minNeeded, maxNeeded = nil, nil
	for floor = virtualFloor, floorMax do
		if not houseSatelliteLoadedFloors[floor] then
			minNeeded = minNeeded or floor
			maxNeeded = floor
		end
	end

	if minNeeded then
		g_satelliteMap.loadFloors(assetsDir, minNeeded, maxNeeded)
		for floor = minNeeded, maxNeeded do
			houseSatelliteLoadedFloors[floor] = true
		end
	end
end

local function buildHouseAliasIndex()
	if houseStaticIdAliases then
		return houseStaticIdAliases
	end

	houseStaticIdAliases = {}
	local function addAlias(fromId, toId)
		fromId = tonumber(fromId) or 0
		toId = tonumber(toId) or 0
		if fromId == 0 or toId == 0 or fromId == toId then
			return
		end

		houseStaticIdAliases[fromId] = houseStaticIdAliases[fromId] or {}
		table.insert(houseStaticIdAliases[fromId], toId)
	end

	if not HOUSE then
		return houseStaticIdAliases
	end

	for scriptId, house in pairs(HOUSE) do
		local keyId = tonumber(scriptId) or 0
		local serverId = tonumber(house and house.id) or keyId
		addAlias(serverId, keyId)
		addAlias(keyId, serverId)
	end

	return houseStaticIdAliases
end

local function getHouseAliasIds(houseId)
	local ids = {}
	local seen = {}
	local function addId(id)
		id = tonumber(id) or 0
		if id == 0 or seen[id] then
			return
		end
		seen[id] = true
		table.insert(ids, id)
	end

	addId(houseId)
	if HOUSE and HOUSE[tonumber(houseId) or 0] and HOUSE[tonumber(houseId) or 0].id then
		addId(HOUSE[tonumber(houseId) or 0].id)
	end

	local aliases = buildHouseAliasIndex()[tonumber(houseId) or 0]
	if aliases then
		for _, aliasId in ipairs(aliases) do
			addId(aliasId)
		end
	end

	return ids
end

local function getStaticHousePositionByName(houseName)
	if type(houseName) ~= "string" or houseName:len() == 0 then
		return nil
	end

	local target = houseName:lower()
	getStaticHouseList()

	local staticData = staticHouseNameIndex and staticHouseNameIndex[target] or nil
	if not staticData and staticHouseNameIndex then
		local normalizedTarget = target:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
		for name, data in pairs(staticHouseNameIndex) do
			local normalizedName = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
			if normalizedName == normalizedTarget then
				staticData = data
				break
			end
		end
	end
	local position = staticData and normalizePosition(staticData.position)
	if position then
		return position
	end

	return nil
end

getStaticHouseList = function()
	if staticHouseCache then
		return staticHouseCache
	end

	local staticHouse = {}
	staticHouseNameIndex = {}

	local function addStaticHouse(houseId, house)
		local normalized = normalizeStaticHouseData(houseId, house)
		if not normalized then
			return nil
		end

		staticHouse[houseId] = normalized
		if type(normalized[1]) == "string" and normalized[1]:len() > 0 then
			staticHouseNameIndex[normalized[1]:lower()] = normalized
		end
		return normalized
	end

	local thingHouseList = g_things and g_things.getHouseList and g_things.getHouseList() or {}
	for houseId, house in pairs(thingHouseList) do
		addStaticHouse(houseId, house)
	end

	for houseId, house in pairs(staticHouse) do
		normalizeStaticHouseData(houseId, house)
	end
	if HOUSE then
		for scriptId, house in pairs(HOUSE) do
			local scriptHouseId = tonumber(scriptId) or 0
			local serverHouseId = tonumber(house and house.id) or scriptHouseId
			if serverHouseId ~= 0 then
				local normalized = normalizeStaticHouseData(serverHouseId, {
				id = serverHouseId,
				name = house.name,
				description = house.description,
				rent = house.rent,
				beds = house.beds,
				sqms = house.sqm or house.sqms,
				guildHall = house.GH == 1,
				city = house.townId,
				shop = house.shop == 1,
				entryx = house.entryx,
				entryy = house.entryy,
				entryz = house.entryz,
				position = {x = house.entryx, y = house.entryy, z = house.entryz}
			})
				if normalized then
					normalized.scriptId = scriptHouseId
					addStaticHouse(serverHouseId, normalized)
					if scriptHouseId ~= 0 and staticHouse[scriptHouseId] == nil then
						staticHouse[scriptHouseId] = normalized
					end
				end
			end
		end
	end
	if g_houses and g_houses.getHouseList then
		for _, house in pairs(g_houses.getHouseList() or {}) do
			local houseId = house and house.getId and house:getId() or 0
			if houseId ~= 0 then
				local normalized = addStaticHouse(houseId, staticHouse[houseId] or {
					house:getName(),
					house:getRent(),
					0,
					house:getSize(),
					false
				})
				if normalized and not normalized.position and house.getEntry then
					normalized.position = house:getEntry()
				end
			end
		end
	end
	staticHouseCache = staticHouse
	return staticHouse
end

local function getHouseImagePath(houseId)
	local ids = getHouseAliasIds(houseId)
	for _, id in ipairs(ids) do
		local candidates = {
			string.format("/mods/game_cyclopedia/images/houses/%s.png", id),
			string.format("/game_cyclopedia/images/houses/%s.png", id)
		}

		for _, path in ipairs(candidates) do
			if g_resources.fileExists(path) then
				return path
			end
		end
	end

	return nil
end

local function getStaticHousePosition(houseId)
	local staticHouse = getStaticHouseList()
	for _, id in ipairs(getHouseAliasIds(houseId)) do
		local staticData = staticHouse[id]
		local position = staticData and normalizePosition(staticData.position)
		if position then
			return position
		end
	end
	return nil
end

local function getStaticHouseData(houseId)
	local staticHouse = getStaticHouseList()
	for _, id in ipairs(getHouseAliasIds(houseId)) do
		local staticData = staticHouse[id]
		if staticData then
			return staticData
		end
	end
	return nil
end

local bidButtonError = {
	[2] = "You don't have permission to rent houses.",
	[3] = "Characters on the beginner's island are not allowed to rent houses.",
	[5] = "Only premium accounts may bid on houses.",
	[6] = "Your account does not have a valid subscription.",
	[7] = "The transfer has already been accepted.",
	[8] = "You don't meet the level requirement to rent a house.",
	[9] = "Your character does not belong to the right vocation to rent this house.",
	[10] = "This house can only be rented by guild leaders.",
	[11] = "A character of your account already holds the highest bid for\nanother house. You may only bid for one house at the same time.",
	[12] = "The characters of your account already own 1 houses. You may\nonly own 1 house at the same time.",
	[13] = "A character of this account has already accepted a house transfer.\nYou need to wait until the first transfer has been completed before you can transfer this house.",
	[14] = "You cannot bid on this house right now.",
	[17] = "Your bank balance is too low to bid on this house.",
	[21] = "An internal error has occurred. Please try again later."
}

local messageTypes = {
	[1] = { -- bid
		[0] = "Your bid was successful. You are currently holding the highest bid.",
		[1] = "You have successfully placed a bid but you are not holding the highest bid. Another character's bid limit was\nhigher than your maximum."
	},

	[2] = { -- move out
		[0] = "You have successfully initiated your move out."
	},

	[3] = { -- transfer
		[0] = "You have successfully initiated the transfer of your house.",
		[2] = "Setting up a house transfer failed.\nYou are not the owner of this house.",
		[4] = "Setting up a house transfer failed.\nA character with this name does not exist.",
		[8] = "Setting up a house transfer failed.\nA guildhall may only be transferred to a leader of an active guild.",
		[10] = "Setting up a house transfer failed.\nThe characters of this account may not rent more houses.",
		[12] = "Setting up a house transfer failed.\nThis character cannot accept a house transfer because a character of this account is currently bidding for a house.",
		[15] = "Setting up a house transfer failed.\nThe transfer has already been accepted.",
		[16] = "Setting up a house transfer failed.\nCharacters on the beginner's island are not allowed to rent houses.",
		[21] = "Setting up a house transfer failed.\nInternal error."
	},

	[4] = { -- cancel move out
		[0] = "You have successfully cancelled your move out. You will keep the house."
	},

	[5] = { -- cancel transfer
		[0] = "You have successfully cancelled the transfer. You will keep the house.",
		[21] = "An internal error has ocurred."
	},

	[6] = { -- accept transfer
		[0] = "You have successfully accepted the transfer.",
		[2] = "Accepting the transfer failed.\nThis character is not the designated new owner of this house.",
		[3] = "Accepting the transfer failed.\nYou cannot accept a house transfer as long as one of your characters is bidding for a house.",
		[7] = "Accepting the transfer failed.\nThe transfer has already been accepted.",
		[8] = "Accepting the transfer failed.\nCharacters on the beginner's island are not allowed to rent houses.",
		[11] = "Accepting the transfer failed.\nYou may not rent more houses.",
		[21] = "An internal error has ocurred."
	},

	[7] = { -- reject transfer
		[0] = "You rejected the house transfer successfully.\nThe old owner will keep the house.",
		[21] = "An internal error has ocurred."
	}
}

function House.resetWindow()
	showGuildHalls = false
	currentTownName = ""
	infoWindow = nil
	currentStateSort = 1
	currentStatusSort = 1
	lastSelectedHouse = nil
	currentHouseList = {}
	houseList = {}
	housesInfo = {}
	ownHousesFallbackRequested = false
	selectedHouseMarkerId = nil
	cyclopediaMapHouseMarkerId = nil
	houseStaticIdAliases = nil
	selectedHousePosition = nil
	houseSatelliteAssetsDir = nil
	houseSatelliteLoadedFloors = {}
	staticHouseCache = nil
	staticHouseNameIndex = nil
end

function House.onParseCyclopediaHousesInfo(currentHouseId, accountHouseCount, highlightedEntries, housesList, maxTownHouses, maxGuildHouses, unknownHeaderA, unknownHeaderB)
	housesInfo = {
		currentHouseId = currentHouseId or 0,
		accountHouseCount = accountHouseCount or 0,
		highlightedEntries = highlightedEntries or {},
		housesList = housesList or {},
		maxTownHouses = maxTownHouses or 0,
		maxGuildHouses = maxGuildHouses or 0,
		unknownHeaderA = unknownHeaderA or 0,
		unknownHeaderB = unknownHeaderB or 0
	}
end

function House.onParseCyclopediaHouseList(houses, extraData)
end

function House.refresh()
	if VisibleCyclopediaPanel and VisibleCyclopediaPanel.selectedBackground and VisibleCyclopediaPanel.selectedBackground.panelHouse and VisibleCyclopediaPanel.selectedBackground.panelHouse:isVisible() then
		if string.empty(currentTownName or "") then
			local townFilter = VisibleCyclopediaPanel.checkboxBackground and VisibleCyclopediaPanel.checkboxBackground.ownHouses and VisibleCyclopediaPanel.checkboxBackground.ownHouses:getCurrentOption().text
			currentTownName = townFilter or currentTownName
		end
		House.selectTown(currentTownName)
	end
end

-- Parse functions
local function normalizeHouseEntry(entry, extra)
	if type(entry) ~= "table" then
		return nil
	end

	local ownerName = entry.owner or entry.ownerName or ""
	local bidderName = entry.bidderName or entry.bidName or ""
	local targetPlayer = entry.targetPlayer or entry.transferPlayerName or ""
	if type(extra) == "table" then
		ownerName = ownerName ~= "" and ownerName or extra.ownerName or extra[1] or ""
		bidderName = bidderName ~= "" and bidderName or extra.bidderName or extra.bidName or extra[2] or ""
		targetPlayer = targetPlayer ~= "" and targetPlayer or extra.targetPlayer or extra.transferPlayerName or extra[3] or ""
	end

	local houseId = tonumber(entry.houseId or entry[1]) or 0
	if not houseId or houseId == 0 then
		return nil
	end

	ownerName = tostring(ownerName or "")
	bidderName = tostring(bidderName or "")
	targetPlayer = tostring(targetPlayer or "")

	local holderLimit = tonumber(entry.holderLimit or entry.bidHolderLimit or entry[3]) or 0
	local state = tonumber(entry.state or entry[2]) or 0
	local localPlayer = g_game.getLocalPlayer()
	local localName = localPlayer and localPlayer:getName() or ""
	if ownerName == "" and currentTownName == "Own Houses" and isRentedState(state) then
		ownerName = localName
	end

	local rented = ownerName ~= "" and isSamePlayerName(ownerName, localName)
	if not rented and currentTownName == "Own Houses" and isRentedState(state) then
		rented = true
	end

	return {
		houseId = houseId,
		state = state,
		holderLimit = holderLimit,
		bidEnd = tonumber(entry.bidEnd or entry[4]) or 0,
		highestBid = tonumber(entry.highestBid or entry[5]) or 0,
		canBidError = tonumber(entry.canBidError or entry.selfCanBid or entry[6]) or 0,
		paidUntil = tonumber(entry.paidUntil or entry[7]) or 0,
		scheduleTime = tonumber(entry.scheduleTime or entry.transferTime or entry[8]) or 0,
		transferValue = tonumber(entry.transferValue or entry[9]) or 0,
		hasTransferOwner = tonumber(entry.hasTransferOwner or entry[10]) or 0,
		canAcceptTransfer = tonumber(entry.canAcceptTransfer or entry[11]) or 0,
		canRejectTransfer = tonumber(entry.canRejectTransfer or entry[12]) or 0,
		ownerError = tonumber(entry.ownerError or entry.canCancelTransfer or entry[13]) or 0,
		canCancelMoveOut = tonumber(entry.canCancelMoveOut or entry[14]) or 0,
		owner = ownerName,
		bidderName = bidderName,
		targetPlayer = targetPlayer,
		bidOwner = holderLimit > 0,
		rented = rented
	}
end

local function normalizeHouseList(houses, extraData)
	local normalized = {}
	for index, entry in ipairs(houses or {}) do
		local house = normalizeHouseEntry(entry, extraData and extraData[index])
		if house then
			normalized[#normalized + 1] = house
		end
	end
	return normalized
end

function House.onRecvHousesData(houses, extraData)
	getStaticHouseList()
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground then
		return true
	end

	houses = normalizeHouseList(houses, extraData)

	local ownPanel = VisibleCyclopediaPanel.selectedBackground and VisibleCyclopediaPanel.selectedBackground.panelHouse or nil
	if not ownPanel then
		return true
	end

	ownPanel:destroyChildren()
	currentHouseList = {}

	if #houses == 0 and currentTownName == "Own Houses" and housesInfo.currentHouseId and housesInfo.currentHouseId ~= 0 then
		local player = g_game.getLocalPlayer()
		houses = {{
			houseId = housesInfo.currentHouseId,
			state = 2,
			owner = player and player:getName() or "",
			paidUntil = 0
		}}
	end

	if #houses == 0 then
		ownPanel:setText("No result.")
		if VisibleCyclopediaPanel.mapViewBackground.noSelected then
			VisibleCyclopediaPanel.mapViewBackground.noSelected:setText("No house selected")
		end
		House.setupMinimap(0)
		return true
	end

	for _, data in ipairs(houses) do
		data.staticData = getStaticHouseData(data.houseId)
	end

	for _, data in ipairs(House.sortDataByStatus(houses)) do
		local static = data.staticData
		if not static then
			-- fallback: create minimal static data from server info
			static = normalizeStaticHouseData(data.houseId, {
				data.name or ("House #" .. data.houseId),
				data.rent or 0,
				data.beds or "?",
				data.size or "?",
				data.guildHall or false
			})
			data.staticData = static
		end

		local guildHall = static[5]
		if (showGuildHalls and not guildHall) or (not showGuildHalls and guildHall) then
			goto continue
		end

		if (currentStateSort == 2 and not isAuctionState(data.state)) or (currentStateSort == 3 and not isRentedState(data.state)) then
			goto continue
		end

		local widget = g_ui.createWidget('HouseData', ownPanel)
		widget.main:setText("")
		widget.main.houseNameText:setText(string.capitalize(tostring(static[1])))
		local sizeStr = type(static[4]) == "number" and (static[4] .. " sqm") or tostring(static[4])
		local rentStr = type(static[2]) == "number" and (static[2] > 0 and (static[2] / 1000 .. " k") or "?") or tostring(static[2])
		widget.main.sizeValueText:setText(sizeStr)
		widget.main.maxBedsValueText:setText(tostring(static[3]))
		widget.main.rentValueText:setText(rentStr)

		if isAuctionState(data.state) then
			-- available
			local t = {}
			local statusText = "auctioned "
			setStringColor(t, "auctioned ", "#00f000")

			if #data.bidderName == 0 then
				setStringColor(t, "(no bid yet)", "#c0c0c0")
				statusText = statusText .. "(no bid yet)"
			else
				local timeLeft = data.bidEnd - os.time()
				local hours = math.floor(timeLeft / 3600)
				local minutes = math.floor((timeLeft % 3600) / 60)
				local seconds = timeLeft % 60

				local timeLeftStr = ""
				if hours > 0 then
					timeLeftStr = hours .. "h "
				end

				if hours < 1 then
					timeLeftStr = timeLeftStr .. minutes .. "min " .. seconds .. "s"
				else
					timeLeftStr = timeLeftStr .. minutes .. "min"
				end

				setStringColor(t, "(Bid: " .. comma_value(data.highestBid) .. " Ends in: " .. timeLeftStr .. ")", "#c0c0c0")
				statusText = statusText .. "(Bid: " .. comma_value(data.highestBid) .. " Ends in: " .. timeLeftStr .. ")"
			end

			widget.main.statusValueText:setText(statusText)
			widget.main.statusValueText:setColor("#00f000")
		elseif isRentedState(data.state) then
			widget.main.statusValueText:setText("rented by " .. data.owner)
			local playerName = g_game.getLocalPlayer():getName()
			if isSamePlayerName(data.owner, playerName) or currentTownName == "Own Houses" then
				widget.main.imageOwnHouse:setVisible(true)
			end
		end

		widget.main:setActionId(data.houseId)
		widget:setActionId(data.houseId)
		widget.data = data
		widget.main.data = data
		bindHouseListWidget(widget)
		currentHouseList[data.houseId] = {mainData = data, staticData = static};
		:: continue ::
	end
	if ownPanel.updateScrollBars then
		ownPanel:updateScrollBars()
	end

	if #ownPanel:getChildren() == 0 then
		ownPanel:setText("No result.")
		VisibleCyclopediaPanel.mapViewBackground.noSelected:setText("No house selected")
		House.setupMinimap(0)
	else
		if not VisibleCyclopediaPanel.bidHouseWindow:isVisible() then
			House.onSelectHouse(ownPanel:getChildren()[1].main)
			ownPanel:setText("")
		end
	end

	houseList = houses
end

function House.onRecvHouseMessage(houseId, bidType, messageType)
	if infoWindow ~= nil then
		return true
	end

	cyclopediaWindow:hide()
	local okFunction = function()
		if g_game.requestShowHouses then
			g_game.requestShowHouses(getHouseRequestTownName(currentTownName))
		else
			g_game.sendHouseAction(0, getHouseRequestTownName(currentTownName))
		end
		House.updateHouseView(bidType)
		if bidType == 1 then
			-- Bid response: always return the user to the house list (success or error),
			-- otherwise the bid form stays open over the list and looks like Bid is broken.
			VisibleCyclopediaPanel.bidHouseWindow:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		elseif bidType == 2 and messageType == 0 then
			VisibleCyclopediaPanel.moveDate:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		elseif bidType == 3 and messageType == 0 then
			VisibleCyclopediaPanel.configureHouseTransfer:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		elseif bidType == 4 then
			VisibleCyclopediaPanel.keepHouse:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		elseif bidType == 5 then
			VisibleCyclopediaPanel.cancelTransferHouse:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)

		elseif bidType == 7 and messageType == 0 then
			VisibleCyclopediaPanel.rejectTransferHouse:setVisible(false)
			VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		end

		cyclopediaWindow:show(true)
		infoWindow:destroy()
		infoWindow = nil end

	local messageGroup = messageTypes[bidType] or {}
	local message = messageGroup[messageType] or bidButtonError[messageType] or "The house action could not be completed."
	infoWindow = displayGeneralBox(tr('Summary'), tr("%s", message), {{text = tr('Ok'), callback = okFunction}}, okFunction)
end

function House.updateHouseView(bidType)
	if not lastSelectedHouse then
		return true
	end

	-- After a bid response (success or error) just refresh the selected house panel.
	-- Previous behavior re-opened the bid form which made the feature feel broken.
	House.onSelectHouse(lastSelectedHouse)
end

function House.selectTown(index)
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground then
		return true
	end

	House.resetData()
	currentTownName = index
	if currentTownName ~= "Own Houses" then
		ownHousesFallbackRequested = false
	end
	if g_game.requestShowHouses then
		g_game.requestShowHouses(getHouseRequestTownName(index))
	else
		g_game.sendHouseAction(0, getHouseRequestTownName(index))
	end
	House.setupMinimap(0)

	lastSelectedHouse = nil
	currentHouseList = {}
	if VisibleCyclopediaPanel.mapViewBackground.noSelected then
		VisibleCyclopediaPanel.mapViewBackground.noSelected:setText("")
	end

	if VisibleCyclopediaPanel.bidHouseWindow and VisibleCyclopediaPanel.bidHouseWindow:isVisible() then
		VisibleCyclopediaPanel.selectedBackground:setVisible(true)
		VisibleCyclopediaPanel.bidHouseWindow:setVisible(false)
	end
end

function House.setZoom(upper)
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground or not VisibleCyclopediaPanel.mapViewBackground.houseView then
		return
	end

	local minimap = VisibleCyclopediaPanel.mapViewBackground.houseView.houseImage
	if not minimap then
		return
	end

	if upper then
		minimap:zoomIn()
	else
		minimap:zoomOut()
	end
end

local function getHouseDisplayName(houseId)
	local staticHouse = getStaticHouseList()
	for _, id in ipairs(getHouseAliasIds(houseId)) do
		local staticData = staticHouse[id]
		if staticData and type(staticData[1]) == "string" and #staticData[1] > 0 then
			return staticData[1]
		end
	end

	local fromCurrent = currentHouseList[houseId]
	if fromCurrent and fromCurrent.staticData and type(fromCurrent.staticData[1]) == "string" and #fromCurrent.staticData[1] > 0 then
		return fromCurrent.staticData[1]
	end

	return "House #" .. tostring(houseId or 0)
end

local function getHouseMapPosition(houseId, allowLiveLookup)
	local housePos = getStaticHousePosition(houseId)
	if housePos then
		return housePos
	end

	local current = currentHouseList[houseId] or currentHouseList[tostring(houseId)]
	local currentName = current and current.staticData and current.staticData[1] or nil
	local byName = getStaticHousePositionByName(currentName)
	if byName then
		return byName
	end

	if allowLiveLookup and g_realMinimap and g_realMinimap.getHousePosition then
		local livePos = normalizePosition(g_realMinimap.getHousePosition())
		if livePos then
			return livePos
		end
	end

	return nil
end

local function clearSelectedHouseMarker(minimap)
	if minimap and minimap.removeWidget and selectedHouseMarkerId then
		minimap:removeWidget(selectedHouseMarkerId)
	end
	selectedHouseMarkerId = nil
end

local function setSelectedHouseMarker(minimap, position, tooltip)
	clearSelectedHouseMarker(minimap)
	if not minimap or not minimap.addWidget or not position then
		return
	end

	selectedHouseMarkerId = minimap:addWidget(HOUSE_MINIMAP_MARKER_ICON, HOUSE_MINIMAP_MARKER_SIZE, position, tooltip or "")
end

local function setCyclopediaMapHouseMarker(minimap, position, tooltip)
	if minimap and minimap.removeWidget and cyclopediaMapHouseMarkerId then
		minimap:removeWidget(cyclopediaMapHouseMarkerId)
	end
	cyclopediaMapHouseMarkerId = nil

	if not minimap or not minimap.addWidget or not position then
		return
	end

	cyclopediaMapHouseMarkerId = minimap:addWidget(HOUSE_MINIMAP_MARKER_ICON, HOUSE_MINIMAP_MARKER_SIZE, position, tooltip or "")
end

local function setHouseActionButtonsEnabled(enabled, tooltip)
	-- markHouseButton/viewHouseButton/panelConfig were removed from the otui to
	-- declutter the panel. Function kept (and called) for backwards compatibility
	-- with the existing flow; it is now a no-op other than guarding nil widgets.
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground then
		return
	end
	-- intentionally empty: only the Bid button remains and its visibility is
	-- managed inside House.onSelectHouse based on the auction state.
end

local function setMinimapView(minimap, housePosZ, forceSatellite)
	if not minimap or not housePosZ then
		return
	end

	housePosZ = tonumber(housePosZ) or 7
	local canUseRealMap = false
	local canUseSatellite = false
	local canUseStaticMinimap = false
	if g_satelliteMap then
		ensureHouseSatelliteFloorsLoaded(housePosZ)
		if g_satelliteMap.hasRealMapChunksForFloor then
			canUseRealMap = g_satelliteMap.hasRealMapChunksForFloor(housePosZ)
		end
		if g_satelliteMap.hasChunksForView and (forceSatellite or housePosZ <= 7) then
			canUseSatellite = g_satelliteMap.hasChunksForView(housePosZ)
		end
		if g_satelliteMap.hasMinimapChunksForFloor then
			canUseStaticMinimap = g_satelliteMap.hasMinimapChunksForFloor(housePosZ)
		end
	end

	if canUseRealMap and minimap.setCurrentView then
		minimap:setCurrentView("realmap")
	elseif canUseSatellite and minimap.setCurrentView then
		minimap:setCurrentView("satellite")
	elseif canUseStaticMinimap and minimap.setCurrentView then
		minimap:setCurrentView("minimap")
	else
		if minimap.setRealMapMode then
			minimap:setRealMapMode(false)
		end
		if minimap.setSatelliteMode then
			minimap:setSatelliteMode(false)
		end
		if minimap.setUseStaticMinimap then
			minimap:setUseStaticMinimap(false)
		end
	end

	if minimap.setBackgroundColor then
		minimap:setBackgroundColor((canUseRealMap or canUseSatellite or canUseStaticMinimap) and "#274DA6" or "#000000ff")
	end

	local floorWidget = VisibleCyclopediaPanel.mapViewBackground:recursiveGetChildById("floorPosition")
	if floorWidget then
		floorWidget:setImageClip(14 * housePosZ .. " 0 14 67")
	end
end

function House.changeFloor(upper)
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground or not VisibleCyclopediaPanel.mapViewBackground.houseView then
		return
	end

	local minimap = VisibleCyclopediaPanel.mapViewBackground.houseView.houseImage
	if not minimap then
		return
	end
	local staticPosition = getStaticHousePosition(selectedHouseId)
	if staticPosition then
		local currentView = minimap:getCameraPosition()
		if not currentView then
			return
		end
		currentView.z = math.max(0, math.min(15, currentView.z + (upper and -1 or 1)))
		setMinimapView(minimap, currentView.z)
		RealMap.setCameraPosition(minimap, currentView)
		return
	end

	if not g_realMinimap or not g_realMinimap.changeHouseFloor or not g_realMinimap.getHousePosition then
		return
	end

	local newFloor = g_realMinimap.changeHouseFloor(upper)
	local currentView = minimap:getCameraPosition()
	local housePos = g_realMinimap.getHousePosition()
	if not housePos then
		return
	end

	setMinimapView(minimap, newFloor)
	currentView.z = (newFloor > 7) and newFloor or housePos.z

	RealMap.setCameraPosition(minimap, currentView)
end

function House.setupMinimap(houseId)
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground or not VisibleCyclopediaPanel.mapViewBackground.houseView then
		return
	end

	if RealMap and RealMap.load then
		RealMap.load()
	end

	local minimap = VisibleCyclopediaPanel.mapViewBackground.houseView.houseImage
	if not minimap then
		return
	end
	local previewImage = VisibleCyclopediaPanel.mapViewBackground.houseView:recursiveGetChildById("housePreviewImage")
	selectedHouseId = tonumber(houseId) or 0
	selectedHousePosition = nil

	if minimap.setupHouse then
		minimap:setupHouse(selectedHouseId)
	end
	clearSelectedHouseMarker(minimap)
	local imagePath = selectedHouseId ~= 0 and getHouseImagePath(selectedHouseId) or nil
	if selectedHouseId == 0 then
		if previewImage then
			previewImage:setVisible(false)
		end
		minimap:setVisible(true)
		setMinimapView(minimap, 7, false)
		RealMap.setCameraPosition(minimap, {x = 0, y = 0, z = 0})
		setHouseActionButtonsEnabled(false)
		return true
	end

	local housePos = getHouseMapPosition(selectedHouseId, true)
	selectedHousePosition = housePos
	if housePos then
		if previewImage then
			previewImage:setVisible(false)
		end
		minimap.housePosition = housePos
		if g_realMinimap and g_realMinimap.setHousePosition then
			g_realMinimap.setHousePosition(housePos)
		end
		minimap:setVisible(true)
		setMinimapView(minimap, housePos.z, true)
		RealMap.setRegion(minimap)
		RealMap.setCameraPosition(minimap, housePos)
		RealMap.hideCross(minimap)
		RealMap.setZoom(minimap, 3)
		setSelectedHouseMarker(minimap, housePos, getHouseDisplayName(selectedHouseId))
		setHouseActionButtonsEnabled(true)
		return true
	end

	if not housePos then
		if g_logger and g_logger.warning then
			g_logger.warning(string.format("[Cyclopedia/Houses] Missing map position for houseId=%s (%s)", tostring(selectedHouseId), getHouseDisplayName(selectedHouseId)))
		end
		if previewImage and imagePath then
			previewImage:setImageSource(imagePath)
			previewImage:setVisible(true)
			minimap:setVisible(false)
		else
			if previewImage then
				previewImage:setVisible(false)
			end
			minimap:setVisible(true)
			setMinimapView(minimap, 7, false)
			RealMap.setCameraPosition(minimap, {x = 0, y = 0, z = 0})
		end
		setHouseActionButtonsEnabled(false)
		return true
	end
end

function House.openSelectedHouseInMap()
	if selectedHouseId == 0 then
		return
	end

	local housePos = selectedHousePosition or getHouseMapPosition(selectedHouseId, true)
	if not housePos then
		displayInfoBox("House View", "This house has no valid position in map data.")
		return
	end

	modules.game_cyclopedia.toggleRedirect("Map")
	scheduleEvent(function()
		if not modules.game_cyclopedia.MapCyclopedia or not modules.game_cyclopedia.MapCyclopedia.getMinimapWidget then
			return
		end

		local minimapWidget = modules.game_cyclopedia.MapCyclopedia.getMinimapWidget()
		if not minimapWidget then
			return
		end

		minimapWidget:setCameraPosition(housePos)
		minimapWidget:setZoom(3)
		setCyclopediaMapHouseMarker(minimapWidget, housePos, getHouseDisplayName(selectedHouseId))
	end, 20)
end

function House.onMarkHouseButton()
	if selectedHouseId == 0 then
		return
	end

	local housePos = selectedHousePosition or getHouseMapPosition(selectedHouseId, true)
	if not housePos then
		displayInfoBox("House Mark", "This house has no valid position in map data.")
		return
	end

	modules.game_cyclopedia.toggleRedirect("Map")
	scheduleEvent(function()
		if not modules.game_cyclopedia.MapCyclopedia or not modules.game_cyclopedia.MapCyclopedia.getMinimapWidget then
			return
		end

		local minimapWidget = modules.game_cyclopedia.MapCyclopedia.getMinimapWidget()
		if not minimapWidget then
			return
		end

		minimapWidget:setCameraPosition(housePos)
		minimapWidget:setZoom(3)
		setCyclopediaMapHouseMarker(minimapWidget, housePos, getHouseDisplayName(selectedHouseId))
		displayInfoBox("House Mark", string.format("Map marker updated: %s", getHouseDisplayName(selectedHouseId)))
	end, 20)
end

function House.onSelectHouse(widget)
	if not widget then
		return
	end

	-- Resolve the row: walk to whichever ancestor has the data table attached.
	-- Click may land on the inner "main" widget or on the HouseData wrapper.
	local function pickRow(w)
		if not w then return nil end
		if w.data and tonumber(w.data.houseId) then return w end
		if w.main and w.main.data and tonumber(w.main.data.houseId) then return w end
		local parent = w.getParent and w:getParent() or nil
		if parent and parent.data and tonumber(parent.data.houseId) then return parent end
		return nil
	end

	local row = pickRow(widget)
	if not row then
		return
	end

	local data = row.data or (row.main and row.main.data) or nil
	local houseId = data and tonumber(data.houseId) or 0
	if houseId == 0 then
		-- fallback to getActionId for older deployments
		houseId = tonumber(row:getActionId()) or 0
		if houseId == 0 and row.main then
			houseId = tonumber(row.main:getActionId()) or 0
		end
	end
	if houseId == 0 then
		return
	end

	if lastSelectedHouse then
		lastSelectedHouse:setBorderWidth(0)
		lastSelectedHouse:setBorderColor('#00000000')
	end

	lastSelectedHouse = row
	selectedHouseId = houseId
	row:setBorderWidth(2)
	row:setBorderColor('white')

	House.setupMinimap(selectedHouseId)

	VisibleCyclopediaPanel.mapViewBackground.noSelected:setText("")

	VisibleCyclopediaPanel.moveDate:setVisible(false)
	VisibleCyclopediaPanel.keepHouse:setVisible(false)
	VisibleCyclopediaPanel.cancelTransferHouse:setVisible(false)
	VisibleCyclopediaPanel.rejectTransferHouse:setVisible(false)
	VisibleCyclopediaPanel.acceptTransferHouse:setVisible(false)
	VisibleCyclopediaPanel.configureHouseTransfer:setVisible(false)
	if not VisibleCyclopediaPanel.selectedBackground:isVisible() then
		VisibleCyclopediaPanel.selectedBackground:setVisible(true)
	end

	House.resetData()
	setHouseActionButtonsEnabled(false)
	local dataList = currentHouseList[selectedHouseId] or currentHouseList[tostring(selectedHouseId)]
	if not dataList then
		return
	end

	local currentInfo = dataList.mainData
	if not currentInfo then
		return
	end

	local panel = VisibleCyclopediaPanel.mapViewBackground:recursiveGetChildById("panelTextsRents")
	panel:setVisible(true)
	panel:raise()
	setHouseActionButtonsEnabled((selectedHousePosition or getHouseMapPosition(selectedHouseId, true)) ~= nil)
	if (currentInfo.owner == nil or currentInfo.owner == "") and currentTownName == "Own Houses" then
		local localPlayer = g_game.getLocalPlayer()
		currentInfo.owner = localPlayer and localPlayer:getName() or currentInfo.owner
	end
	panel.rental.imageOwnHouse:setVisible(false)

	if isAuctionState(currentInfo.state) then
		panel.noBidHouseHeader:setVisible(#currentInfo.bidderName == 0)
		panel.noBidHouseText:setVisible(#currentInfo.bidderName == 0)
		panel.bidButton:setVisible(true)
		panel.bidButton:raise()

		-- The bidButton image has 3 states baked in: normal (0..20), pressed (20..40)
		-- and disabled (40..60, shown via $!on). Lua drives setOn() to reflect whether
		-- the player is actually allowed to bid; the opaque/disabled look comes from
		-- "off" (setOn(false)) and the click handler gates submission on :isOn(). Do
		-- NOT call setEnabled(false) — disabled widgets swallow hover events, which
		-- kills the tooltip explaining why the button is opaque.
		-- Also note: setText("Bid") would double the label, since the PNG already
		-- contains the text.
		local canBid = (currentInfo.canBidError == 0)
		panel.bidButton:setOn(canBid)
		if canBid then
			panel.bidButton:setTooltip("")
		else
			local errorMsg = bidButtonError[currentInfo.canBidError]
				or string.format("You cannot bid on this house. (server code %d)", currentInfo.canBidError or -1)
			panel.bidButton:setTooltip(errorMsg)
		end

		if #currentInfo.bidderName > 0 then
			panel.bidInfo:setVisible(true)
			panel.bidInfo.bidderName:setText(short_text(currentInfo.bidderName, 16))
			if #currentInfo.bidderName >= 16 then
				panel.bidInfo.bidderName:setTooltip(currentInfo.bidderName)
			end

			panel.bidInfo.endValue:setText(formatHouseDate(currentInfo.bidEnd))
			panel.bidInfo.highestBidValue:setText(comma_value(currentInfo.highestBid))

			if currentInfo.bidOwner then
				panel.bidInfo.auctionImage:setImageClip("0 0 234 54")
				panel.bidInfo.auctionImage:setSize(tosize("234 54"))
				panel.bidInfo.yourLimitValue:setText(comma_value(currentInfo.holderLimit))
			else
				panel.bidInfo.auctionImage:setImageClip("0 0 234 41")
				panel.bidInfo.auctionImage:setSize(tosize("234 41"))
				panel.bidInfo.yourLimitValue:clearText()
			end
		else
			panel.noBidHouseHeader:setVisible(true)
			panel.noBidHouseText:setVisible(true)
		end

	elseif isRentedState(currentInfo.state) then
		panel.rental:setVisible(true)
		panel.rental.tenantValue:setText(short_text(currentInfo.owner, 16))
		if #currentInfo.owner >= 16 then
			panel.rental.tenantValue:setTooltip(currentInfo.owner)
		end

		panel.rental.moveImage:setVisible(false)
		panel.rental.pendingImage:setVisible(false)

		panel.rental.paidValue:setText(formatHouseDate(currentInfo.paidUntil))
		if tonumber(currentInfo.state) == 4 and isSamePlayerName(currentInfo.owner, g_game.getLocalPlayer():getName()) then
			panel.rental.moveImage:setVisible(true)
			panel.rental.moveImage.moveValue:setText(formatHouseDate(currentInfo.scheduleTime))
			panel.rental.keepButton:setVisible(true)
		elseif tonumber(currentInfo.state) == 2 and (currentInfo.rented or currentTownName == "Own Houses") then
			panel.rental.imageOwnHouse:setVisible(true)
			panel.rental.moveButton:setVisible(true)
			panel.rental.transferButton:setVisible(true)
		elseif tonumber(currentInfo.state) == 3 then
			panel.rental.pendingImage:setVisible(true)
			panel.rental.pendingImage.newOwnerValue:setText(short_text(currentInfo.targetPlayer, 16))
			if #currentInfo.targetPlayer >= 16 then
				panel.rental.pendingImage.newOwnerValue:setTooltip(currentInfo.targetPlayer)
			end

			panel.rental.pendingImage.dateValue:setText(formatHouseDate(currentInfo.scheduleTime))
			panel.rental.pendingImage.priceValue:setText(comma_value(currentInfo.transferValue))

			if isSamePlayerName(currentInfo.owner, g_game.getLocalPlayer():getName()) then
				panel.rental.cancelTransferButton:setVisible(true)
				panel.rental.cancelTransferButton:setOn(true)
				panel.rental.cancelTransferButton:setTooltip("")
				if currentInfo.ownerError > 0 then
					panel.rental.cancelTransferButton:setOn(false)
					panel.rental.cancelTransferButton:setTooltip(bidButtonError[currentInfo.ownerError])
				end
			elseif isSamePlayerName(currentInfo.targetPlayer, g_game.getLocalPlayer():getName()) then
				local acceptError = currentInfo.canAcceptTransfer or 0
				local rejectError = currentInfo.canRejectTransfer or 0
				if acceptError > 0 or rejectError > 0 then
					panel.rental.acceptTransferButton:setOn(false)
					panel.rental.acceptTransferButton:setTooltip(bidButtonError[acceptError] or "")
					panel.rental.rejectTransferButton:setOn(false)
					panel.rental.rejectTransferButton:setTooltip(bidButtonError[rejectError] or "")
				else
					panel.rental.acceptTransferButton:setOn(true)
					panel.rental.acceptTransferButton:setTooltip("")
					panel.rental.rejectTransferButton:setOn(true)
					panel.rental.rejectTransferButton:setTooltip("")
				end

				panel.rental.acceptTransferButton:setVisible(true)
				panel.rental.rejectTransferButton:setVisible(true)
			end
		end
	end
end

function House.onBidButton(button)
	-- Only open the bid form when the button is "on" (enabled). When the server
	-- reports canBidError != 0 we drive setOn(false) and the player sees the
	-- opaque art + reason tooltip; allowing the click in that state used to
	-- pop up "You cannot bid this house" with no further feedback.
	if button and not button:isOn() then
		return true
	end

	if not lastSelectedHouse then
		return true
	end

	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local houseData = getCurrentHouseData(selectHouseId)
	if not houseData then
		return true
	end
	local static = houseData.staticData
	local currentInfo = houseData.mainData
	if not static or not currentInfo then
		return true
	end

	local bidWindow = VisibleCyclopediaPanel.bidHouseWindow

	bidWindow.limitBox:setText(0)
	bidWindow.nameValue:setText(string.capitalize(static[1]))
	bidWindow.sizeValue:setText(static[4] .. " sqm")
	bidWindow.bedsValue:setText(static[3])
	bidWindow.rentValue:setText(static[2] / 1000 .. " k")

	if #currentInfo.bidderName == 0 then
		bidWindow.currentAcution:setVisible(false)
		bidWindow.thereFar:setVisible(true)
		bidWindow.limitText:setMarginTop(5)
	else
		bidWindow.thereFar:setVisible(false)
		bidWindow.currentAcution:setVisible(true)
		bidWindow.currentAcution.highestBidder:setText(currentInfo.bidderName)
		bidWindow.currentAcution.endTime:setText(formatHouseDate(currentInfo.bidEnd))
		bidWindow.currentAcution.highestBid:setText(comma_value(currentInfo.highestBid))

		if currentInfo.bidOwner then
			bidWindow.currentAcution.bidLimitBid:setText(comma_value(currentInfo.holderLimit))
			bidWindow.limitBox:setText(currentInfo.holderLimit)
			bidWindow.currentAcution:setImageClip("0 0 217 54")
			bidWindow.currentAcution:setSize(tosize("217 54"))
			bidWindow.limitText:setMarginTop(47)
		else
			bidWindow.currentAcution:setImageClip("0 0 217 41")
			bidWindow.currentAcution:setSize(tosize("217 41"))
			bidWindow.limitText:setMarginTop(31)
		end
	end

	-- Pull fresh balances so onBidChangeValue's red/green decision matches the
	-- coinsAmount footer; resources can lag if the player just spent/earned gold.
	g_game.requestResource(ResourceBank)
	g_game.requestResource(ResourceInventary)

	VisibleCyclopediaPanel.bidHouseWindow:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onMoveOutButton()
	if not lastSelectedHouse then
		return true
	end

	if VisibleCyclopediaPanel.configureHouseTransfer:isVisible() then
		VisibleCyclopediaPanel.configureHouseTransfer:setVisible(false)
	end

	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local houseData = getCurrentHouseData(selectHouseId)
	if not houseData then
		return true
	end
	local static = houseData.staticData
	local currentInfo = houseData.mainData
	if not static or not currentInfo then
		return true
	end

	local currentDate = os.date("*t")
	local day, month, year = currentDate.day, currentDate.month, currentDate.year
	local nextDay, nextMonth, nextYear = getNextDay(day, month, year)

	VisibleCyclopediaPanel.moveDate.data.yearBox:addOption(nextYear)
	VisibleCyclopediaPanel.moveDate.data.monthBox:addOption(nextMonth)
	VisibleCyclopediaPanel.moveDate.data.dayBox:addOption(nextDay)
	VisibleCyclopediaPanel.moveDate.data.nameValue:setText(string.capitalize(static[1]))
	VisibleCyclopediaPanel.moveDate.data.sizeValue:setText(static[4] .. " sqm")
	VisibleCyclopediaPanel.moveDate.data.bedsValue:setText(static[3])
	VisibleCyclopediaPanel.moveDate.data.rentValue:setText(static[2] / 1000 .. " k")
	VisibleCyclopediaPanel.moveDate.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	VisibleCyclopediaPanel.moveDate:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onDoMoveOut(moveCancel)
	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local houseData = getCurrentHouseData(selectHouseId)
	if not houseData then
		return true
	end
	local static = houseData.staticData
	local currentInfo = houseData.mainData
	if not static or not currentInfo then
		return true
	end

	cyclopediaWindow:hide()

	local actionType = moveCancel and 4 or 2
	local yesFunction = function() g_game.sendHouseAction(actionType, "", selectHouseId) cyclopediaWindow:show() moveOutWindow:destroy() moveOutWindow = nil end
	local noFunction = function() cyclopediaWindow:show() moveOutWindow:destroy() moveOutWindow = nil end

	local message = tr("Do you really want to move out of the house '%s'?\nClick on \"Yes\" to move out on %s", string.capitalize(static[1]), formatHouseDate(os.time()))
	if moveCancel then
		message = tr("Do you really want to keep your house '%s'?\nYou will no longer move out on %s", string.capitalize(static[1]), formatHouseDate(currentInfo.scheduleTime))
	end

	moveOutWindow = displayGeneralBox('Confirm House Action', message,
		{ { text=tr('Yes'), callback=yesFunction }, { text=tr('No'), callback=noFunction }
	}, yesFunction, noFunction)
end

function House.onDoTransfer(cancel)
	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local houseData = getCurrentHouseData(selectHouseId)
	if not houseData then
		return true
	end
	local static = houseData.staticData
	local currentInfo = houseData.mainData
	if not static or not currentInfo then
		return true
	end

	cyclopediaWindow:hide()
	local window = VisibleCyclopediaPanel.configureHouseTransfer.data
	local targetName = window.newOwnerName:getText()
	local transferValue = tonumber(window.presetName:getText())

	local message = tr("Do you really want to transfer your house '%s' to %s?\nThe transfer is scheduled for %s.\nYou have set the transfer price to %s gold coins.\nThe transfer will only take place if %s accepts it!\n\nPlease take all your personal belongings out of the house before the daily server save on the day you move\nout. Everything that remains in the house becomes the property of the new owner after the transfer. The only\nexception are items which have been purchased in the Store. They will be wrapped back up and sent to your\ninbox.", string.capitalize(static[1]), targetName, formatHouseDate(os.time()), transferValue, targetName)
	if cancel then
		message = tr("Do you really want to keep your house '%s'?\nYou will no longer transfer the house to %s on %s", string.capitalize(static[1]), currentInfo.targetPlayer, formatHouseDate(currentInfo.scheduleTime))
	end

	local yesFunction = function() if cancel then g_game.sendHouseAction(5, "", selectHouseId) else g_game.sendHouseAction(3, targetName, selectHouseId, transferValue) end cyclopediaWindow:show() transferWindow:destroy() transferWindow = nil end
	local noFunction = function() cyclopediaWindow:show() transferWindow:destroy() transferWindow = nil end

	transferWindow = displayGeneralBox('Confirm House Action', message,
		{ { text=tr('Yes'), callback=yesFunction }, { text=tr('No'), callback=noFunction }
	}, yesFunction, noFunction)

end

function House.onKeepHouseButton()
	if not lastSelectedHouse then
		return true
	end

	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local houseData = getCurrentHouseData(selectHouseId)
	if not houseData then
		return
	end
	local static = houseData.staticData
	local currentInfo = houseData.mainData
	if not static or not currentInfo then
		return true
	end

	VisibleCyclopediaPanel.keepHouse.data.nameValue:setText(string.capitalize(static[1]))
	VisibleCyclopediaPanel.keepHouse.data.sizeValue:setText(static[4] .. " sqm")
	VisibleCyclopediaPanel.keepHouse.data.bedsValue:setText(static[3])
	VisibleCyclopediaPanel.keepHouse.data.rentValue:setText(static[2] / 1000 .. " k")
	VisibleCyclopediaPanel.keepHouse.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	VisibleCyclopediaPanel.keepHouse.data.moveDate:setText(formatHouseDate(currentInfo.scheduleTime))

	VisibleCyclopediaPanel.keepHouse:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onTransferButton()
	if not lastSelectedHouse then
		return true
	end

	if VisibleCyclopediaPanel.moveDate:isVisible() then
		VisibleCyclopediaPanel.moveDate:setVisible(false)
	end

	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	local currentDate = os.date("*t")
	local day, month, year = currentDate.day, currentDate.month, currentDate.year
	local nextDay, nextMonth, nextYear = getNextDay(day, month, year)

	VisibleCyclopediaPanel.configureHouseTransfer.data.yearBox:addOption(nextYear)
	VisibleCyclopediaPanel.configureHouseTransfer.data.monthBox:addOption(nextMonth)
	VisibleCyclopediaPanel.configureHouseTransfer.data.dayBox:addOption(nextDay)
	VisibleCyclopediaPanel.configureHouseTransfer.data.nameValue:setText(string.capitalize(static[1]))
	VisibleCyclopediaPanel.configureHouseTransfer.data.sizeValue:setText(static[4] .. " sqm")
	VisibleCyclopediaPanel.configureHouseTransfer.data.bedsValue:setText(static[3])
	VisibleCyclopediaPanel.configureHouseTransfer.data.rentValue:setText(static[2] / 1000 .. " k")
	VisibleCyclopediaPanel.configureHouseTransfer.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	VisibleCyclopediaPanel.configureHouseTransfer:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onCancelTransferButton(button)
	if not lastSelectedHouse or not button:isOn() then
		return true
	end

	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	VisibleCyclopediaPanel.cancelTransferHouse.data.nameValue:setText(static[1])
	VisibleCyclopediaPanel.cancelTransferHouse.data.sizeValue:setText(static[4] .. " sqm")
	VisibleCyclopediaPanel.cancelTransferHouse.data.bedsValue:setText(static[3])
	VisibleCyclopediaPanel.cancelTransferHouse.data.rentValue:setText(static[2] / 1000 .. " k")
	VisibleCyclopediaPanel.cancelTransferHouse.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	VisibleCyclopediaPanel.cancelTransferHouse.data.transferDate:setText(formatHouseDate(currentInfo.scheduleTime))
	VisibleCyclopediaPanel.cancelTransferHouse.data.price:setText(comma_value(currentInfo.transferValue))
	VisibleCyclopediaPanel.cancelTransferHouse.data.newOwner:setText(currentInfo.targetPlayer)
	VisibleCyclopediaPanel.cancelTransferHouse:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onManageTransferButton(button, reject)
	if not lastSelectedHouse or not button:isOn() then
		return true
	end

	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	if reject and VisibleCyclopediaPanel.acceptTransferHouse:isVisible() then
		VisibleCyclopediaPanel.acceptTransferHouse:setVisible(false)
	end

	if not reject and VisibleCyclopediaPanel.rejectTransferHouse:isVisible() then
		VisibleCyclopediaPanel.rejectTransferHouse:setVisible(false)
	end

	local widget = reject and VisibleCyclopediaPanel.rejectTransferHouse or VisibleCyclopediaPanel.acceptTransferHouse

	widget.data.nameValue:setText(string.capitalize(static[1]))
	widget.data.sizeValue:setText(static[4] .. " sqm")
	widget.data.bedsValue:setText(static[3])
	widget.data.rentValue:setText(static[2] / 1000 .. " k")
	widget.data.paidUntilDate:setText(formatHouseDate(currentInfo.paidUntil))
	widget.data.transferDate:setText(formatHouseDate(currentInfo.scheduleTime))
	widget.data.price:setText(comma_value(currentInfo.transferValue))
	widget.data.newOwner:setText(currentInfo.targetPlayer)
	widget:setVisible(true)
	VisibleCyclopediaPanel.selectedBackground:setVisible(false)
end

function House.onDoAcceptTransfer(reject)
	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local static = currentHouseList[selectHouseId].staticData
	local currentInfo = currentHouseList[selectHouseId].mainData
	if not static or not currentInfo then
		return true
	end

	cyclopediaWindow:hide()

	local message = tr("Do you want to accept the house transfer offered by %s for the property '%s'?\nThe transfer is scheduled for %s.\nThe transfer price was set to %s gold coins.\n\nMake sure to have enough gold in your bank account to pay the costs for this house transfer and the next rent.\nRemember to edit the door rights as only the guest list will be reset after the transfer!", currentInfo.owner, string.capitalize(static[1]), formatHouseDate(currentInfo.scheduleTime), comma_value(currentInfo.transferValue))
	if reject then
		message = tr("Do you really want to reject the transfer for the house '%s' offered by %s?\nYou will not get the house. %s will keep the house and can set up a new transfer anytime.", string.capitalize(static[1]), currentInfo.targetPlayer, currentInfo.targetPlayer)
	end

	local packetType = reject and 7 or 6
	local yesFunction = function() g_game.sendHouseAction(packetType, "", selectHouseId) cyclopediaWindow:show() transferWindow:destroy() transferWindow = nil end
	local noFunction = function() cyclopediaWindow:show() transferWindow:destroy() transferWindow = nil end

	transferWindow = displayGeneralBox('Confirm House Action', message,
		{ { text=tr('Yes'), callback=yesFunction }, { text=tr('No'), callback=noFunction }
	}, yesFunction, noFunction)
end

function House.onPlaceBid(button)
	-- Bail when the submit button is in its disabled ($!on) state — the bid value
	-- failed local validation (e.g. balance too low). The server is still the
	-- final authority, but blocking obviously invalid bids here is what the user
	-- expects when the art is opaque.
	if button and not button:isOn() then
		return true
	end

	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local houseData = getCurrentHouseData(selectHouseId)
	if not houseData then
		return true
	end
	local static = houseData.staticData
	local currentInfo = houseData.mainData
	if not static or not currentInfo then
		return true
	end

	local limit = tonumber(VisibleCyclopediaPanel.bidHouseWindow.limitBox:getText())

	cyclopediaWindow:hide()
	local yesFunction = function()
		if g_game.requestBidHouse then
			g_game.requestBidHouse(selectHouseId, limit)
		else
			g_game.sendHouseAction(1, "", selectHouseId, limit)
		end
		cyclopediaWindow:show()
		placeBidWindow:destroy()
		placeBidWindow = nil
	end
	local noFunction = function() cyclopediaWindow:show() placeBidWindow:destroy() placeBidWindow = nil end

	placeBidWindow = displayGeneralBox(tr('Confirm House Action'), tr("Do you really want to bid on the house '%s' ?\n\nYou have set your bid limit to %s.\nWhen the auction ends, the winning bid plus the rent of %s for the first month will be debited from your\nbank account.", string.capitalize(static[1]), limit, (static[2] / 1000 .. " k")),
		{ { text=tr('Yes'), callback=yesFunction }, { text=tr('No'), callback=noFunction }
	}, yesFunction, noFunction)
end

function House.onStateSort(widget, currentIndex)
	currentStateSort = currentIndex;
	House.onRecvHousesData(houseList)
end

function House.onStatusSort(widget, currentIndex)
	currentStatusSort = currentIndex;
	House.onRecvHousesData(houseList)
end

function House.sortDataByStatus(houses)
	table.sort(houses, function(a, b)
		local a_static = a.staticData or getStaticHouseData(a.houseId)
		local b_static = b.staticData or getStaticHouseData(b.houseId)

		if currentStatusSort == 1 then
			local firstNameA = (a_static and a_static[1] or tostring(a.houseId)):split(" ")[1]
			local firstNameB = (b_static and b_static[1] or tostring(b.houseId)):split(" ")[1]
			if firstNameA == firstNameB then return a.houseId < b.houseId end
			return firstNameA < firstNameB
		end

		if currentStatusSort == 2 then
			return (a_static and a_static[4] or 0) < (b_static and b_static[4] or 0)
		end

		if currentStatusSort == 3 then
			return (a_static and a_static[2] or 0) < (b_static and b_static[2] or 0)
		end

		if currentStatusSort == 4 then
			return a.highestBid > b.highestBid
		end

		if currentStatusSort == 5 then
			return a.bidEnd > b.bidEnd
		end
		return false
	end)
	return houses
end

function House.toggleHouseChecked(guildHall)
	local checkHouses = g_ui.getRootWidget():recursiveGetChildById('checkHouses')
	local checkGuildhalls = g_ui.getRootWidget():recursiveGetChildById('checkGuildhalls')

	if guildHall then
		checkHouses:setChecked(false)
		checkGuildhalls:setChecked(true)
		showGuildHalls = true
	else
		checkHouses:setChecked(true)
		checkGuildhalls:setChecked(false)
		showGuildHalls = false
	end
	House.onRecvHousesData(houseList)
end

function House.onBidChangeValue(widget)
	local currentText = widget:getText()
	if #currentText == 0 then
		return
	end

    currentText = currentText:gsub("[^%d]", "")
    widget:setText(currentText)

    if #currentText > 11 then
        currentText = currentText:sub(1, -2)
        widget:setText(currentText)
    end

    local numericValue = tonumber(currentText) or 0
    if numericValue and numericValue >= 99999999999 then
		currentText = "99999999999"
		widget:setText(currentText)
    end

	local localPlayer = g_game.getLocalPlayer()
	-- Use bank + carried gold to match the "coinsAmount" footer the player sees
	-- in the cyclopedia (map.lua does the same sum). Checking only ResourceBank
	-- left the bid limit stuck in red whenever the player kept gold in inventory.
	local bankMoney = localPlayer:getResourceValue(ResourceBank) + localPlayer:getResourceValue(ResourceInventary)
	local bidWindow = VisibleCyclopediaPanel.bidHouseWindow
	local selectHouseId = resolveRowHouseId(lastSelectedHouse)
	local houseData = getCurrentHouseData(selectHouseId)
	if not houseData then
		return
	end
	local static = houseData.staticData
	local currentInfo = houseData.mainData

	bidWindow.infoRed:setVisible(false)
	bidWindow.infoRed:setTooltip("")
	bidWindow.infoOrange:setVisible(false)
	bidWindow.infoOrange:setTooltip("")
	bidWindow.limitBox:setColor("#c0c0c0")
	bidWindow.bidButtonHouseWindow:setOn(true)
	bidWindow.bidButtonHouseWindow:setTooltip("")

	if tonumber(numericValue) < currentInfo.highestBid then
		bidWindow.infoOrange:setVisible(true)
		bidWindow.infoOrange:setTooltip("Your bid limit must be higher than the current highest bid.")
	end

	if tonumber(numericValue) + static[2] > bankMoney then
		bidWindow.infoRed:setVisible(true)
		bidWindow.infoRed:setTooltip("Your account balance is too low to pay the bid and the rent for the\nfirst month.")
		bidWindow.limitBox:setColor("#d33c3c")
		bidWindow.bidButtonHouseWindow:setOn(false)
		bidWindow.bidButtonHouseWindow:setTooltip("You need to fill in the form correctly")
	end
end

function House.onTransferTarget(widget)
	local transferWindow = VisibleCyclopediaPanel.configureHouseTransfer.data
	local currentText = widget:getText()
	if #currentText == 0 then
		transferWindow.redInfo:setVisible(true)
		return
	end

	transferWindow.redInfo:setVisible(false)
	currentText = currentText:gsub("%d", "")
    widget:setText(currentText)

    if #currentText > 28 then
        currentText = currentText:sub(1, -2)
        widget:setText(currentText)
    end
end

function House.onTransferValue(widget)
	local transferWindow = VisibleCyclopediaPanel.configureHouseTransfer.data
	local currentText = widget:getText()
	if #currentText == 0 then
		transferWindow.redInfo:setVisible(true)
		return
	end

	currentText = currentText:gsub("[^%d]", "")
    widget:setText(currentText)

    if #currentText > 11 then
        currentText = currentText:sub(1, -2)
        widget:setText(currentText)
    end

	local numericValue = tonumber(currentText)
    if numericValue and numericValue >= 99999999999 then
        currentText = "99999999999"
        widget:setText(currentText)
    end
end

function House.resetData()
	if not VisibleCyclopediaPanel or not VisibleCyclopediaPanel.mapViewBackground then
		return true
	end

	local panel = VisibleCyclopediaPanel.mapViewBackground:recursiveGetChildById("panelTextsRents")
	panel.bidButton:setVisible(false)
	if panel.markHouseButton then
		panel.markHouseButton:setVisible(false)
	end
	if panel.viewHouseButton then
		panel.viewHouseButton:setVisible(false)
	end
	panel.noBidHouseHeader:setVisible(false)
	panel.noBidHouseText:setVisible(false)
	panel.rental:setVisible(false)
	panel.bidInfo:setVisible(false)
	panel.rental.moveButton:setVisible(false)
	panel.rental.transferButton:setVisible(false)
	panel.rental.moveImage:setVisible(false)
	panel.rental.keepButton:setVisible(false)
	panel.rental.acceptTransferButton:setVisible(false)
	panel.rental.rejectTransferButton:setVisible(false)
	panel.rental.cancelTransferButton:setVisible(false)
end

function formatHouseDate(timestamp)
    local t = os.date("!*t", timestamp)
    local months = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    }
    local month = months[t.month]
    local day = t.day
    local hour = string.format("%02d", t.hour)
    local min = string.format("%02d", t.min)
    hour = string.format("%02d", (t.hour + 1) % 24)
    return month .. " " .. day .. ", " .. hour .. ":" .. min .. " CET"
end

