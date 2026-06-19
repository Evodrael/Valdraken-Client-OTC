local registredOpcodes = nil

local ServerPackets = {
	DailyRewardCollectionState = 0xDE,
	OpenRewardWall = 0xE2,
	CloseRewardWall = 0xE3,
	DailyRewardBasic = 0xE4,
	DailyRewardHistory = 0xE5,
	RestingAreaState = 0xA9,
	BestiaryData = 0xd5,
	BestiaryOverview = 0xd6,
	BestiaryMonsterData = 0xd7,
	BestiaryCharmsData = 0xd8,
	BestiaryTracker = 0xd9,
	BestiaryTrackerTab = 0xB9,
	OpenStashSupply = 0x29,
	UpdateLootTracker = 0xCF,
	UpdateTrackerAnalyzer = 0xCC,
	UpdateSupplyTracker = 0xCE,
	KillTracker = 0xD1,
	SpecialContainer = 0x2A,
	isUpdateCoinBalance = 0xF2,
	UpdateCoinBalance = 0xDF,
	PartyAnalyzer = 0x2B,
	GameNews = 0x98,
	ClientCheck = 0x63,
	LootStats = 0xCF,
	LootContainer = 0xC0,
	TournamentLeaderBoard = 0xC5,
	CyclopediaCharacterInfo = 0xDA,
	Tutorial = 0xDC,
	Highscores = 0xB1,
	Inspection = 0x76,
	TeamFinderList = 0x2D,
	TeamFinderLeader = 0x2C
}

-- Server Types
local DAILY_REWARD_TYPE_ITEM = 1
local DAILY_REWARD_TYPE_STORAGE = 2
local DAILY_REWARD_TYPE_PREY_REROLL = 3
local DAILY_REWARD_TYPE_XP_BOOST = 4

-- Client Types
local DAILY_REWARD_SYSTEM_SKIP = 1
local DAILY_REWARD_SYSTEM_TYPE_ONE = 1
local DAILY_REWARD_SYSTEM_TYPE_TWO = 2
local DAILY_REWARD_SYSTEM_TYPE_OTHER = 1
local DAILY_REWARD_SYSTEM_TYPE_PREY_REROLL = 2
local DAILY_REWARD_SYSTEM_TYPE_XP_BOOST = 3

function init()
  connect(g_game, { onEnterGame = registerProtocol,
                    onPendingGame = registerProtocol,
                    onGameEnd = unregisterProtocol })
  if g_game.isOnline() then
    registerProtocol()
  end
end

function terminate()
  disconnect(g_game, { onEnterGame = registerProtocol,
                    onPendingGame = registerProtocol,
                    onGameEnd = unregisterProtocol })

  unregisterProtocol()
end

function registerProtocol()
  if registredOpcodes ~= nil or not g_game.getFeature(GameTibia12Protocol) then
    return
  end

  -- Keep Lua listeners only for packets that are not already parsed natively in C++.
  registredOpcodes = {}

  registerOpcode(ServerPackets.TeamFinderLeader, function(protocol, msg)
	local bool = msg:getU8() -- reset
	if bool > 0 then
		return -- Server internal changes
	end

	msg:getU16() -- Min level
	msg:getU16() -- Max level
	msg:getU8() -- Vocation flag
	msg:getU16() -- Slots
	msg:getU16() -- Free slots
	msg:getU32() -- Timestamp
	local type = msg:getU8() -- Team type
	msg:getU16() -- Type flag
	if type == 2 then
		msg:getU16() -- Hunt area
	end

	local size = msg:getU16() -- Members size
	for i = 1, size do
		msg:getU32() -- Character id
		msg:getString() -- Character name
		msg:getU16() -- Character level
		msg:getU8() -- Vocation
		msg:getU8() -- Member type (Leader == 3)
	end
  end)

  registerOpcode(ServerPackets.TeamFinderList, function(protocol, msg)
	msg:getU8()
	local size = msg:getU32() -- List size
	for i = 1, size do
		msg:getU32() -- Leader Id
		msg:getString() -- Leader name
		msg:getU16() -- Min level
		msg:getU16() -- Max level
		msg:getU8() -- Vocations flag
		msg:getU16() -- Slots
		msg:getU16() -- Used slots
		msg:getU32() -- Timestamp
		local type = msg:getU8() -- Team type [1]: Boss, [2]: Hunt and [3]: Quest
		msg:getU16() -- Type flag
		if type == 2 then
			msg:getU16() -- Hunt area
		end
		msg:getU8() -- Player status
	end
  end)

  registerOpcode(ServerPackets.TournamentLeaderBoard, function(protocol, msg)
	msg:getU16()
	local capacity = msg:getU8() -- Worlds
	for i = 1, capacity do
		msg:getString() -- World name
	end

	msg:getString() -- World selected
	msg:getU16() -- Refresh rate
	msg:getU16() -- Current page
	msg:getU16() -- Total pages
	local size = msg:getU8() -- Players on page
	for u = 1, size do
		msg:getU32() -- Rank
		msg:getU32() -- Previous rank
		msg:getString() -- Name
		msg:getU8() -- Vocation
		msg:getU64() -- Points
		msg:getU8() -- Rank chance direction (arrow0
		msg:getU8() -- Rank chance bool
	end
	msg:getU8()
	msg:getString() -- Rewards
  end)
end

function readAddItem(msg)
	msg:getU16() -- Item client ID

	if g_game.getProtocolVersion() < 1150 then
		msg:getU8() -- Unmarked
	end

	local var = msg:getU8()
	if g_game.getProtocolVersion() > 1150 then
		if var == 1 then
			msg:getU32() -- Loot flag
		end

		if g_game.getProtocolVersion() >= 1260 then
			local isQuiver = msg:getU8()
			if isQuiver == 1 then
				msg:getU32() -- Quiver count
			end
		end
	else
		msg:getU8()
	end
end

function unregisterProtocol()
  if registredOpcodes == nil then
    return
  end
  for opcode, _ in pairs(registredOpcodes) do
    ProtocolGame.unregisterOpcode(opcode)
  end
  registredOpcodes = nil
end

function registerOpcode(code, func)
  if registredOpcodes[code] ~= nil then
    error("Duplicated registed opcode: " .. code)
  end
  registredOpcodes[code] = func
  ProtocolGame.registerOpcode(code, func)
end

function readDailyReward(msg)
	local systemType = msg:getU8()
	if (systemType == 1) then
    msg:getU8()
    local count = msg:getU8()
    for i = 1, count do
      msg:getU16()
      msg:getString()
      msg:getU32()
    end
	elseif (systemType == 2) then
    msg:getU8()
    local type = msg:getU8()

		if (type == DAILY_REWARD_SYSTEM_TYPE_PREY_REROLL) then
      msg:getU8()
		elseif (type == DAILY_REWARD_SYSTEM_TYPE_XP_BOOST) then
      msg:getU16()
		end
	end
end
