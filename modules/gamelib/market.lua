MarketCategory = {
	All = 0,
	Armors = 1,
	Amulets = 2,
	Boots = 3,
	Containers = 4,
	Decoration = 5,
	Food = 6,
	HelmetsHats = 7,
	Legs = 8,
	Others = 9,
	Potions = 10,
	Rings = 11,
	Runes = 12,
	Shields = 13,
	Tools = 14,
	Valuables = 15,
	Ammunition = 16,
	Axes = 17,
	Clubs = 18,
	DistanceWeapons = 19,
	Swords = 20,
	WandsRods = 21,
	PremiumScrolls = 22,
	TibiaCoins = 23,
	CreatureProducs = 24,
	Quivers = 25,
	SoulCore = 26,
	FistWeapons = 27,
	Unknown3 = 28,
	Unknown4 = 29,
	Gold = 30,
	Unassigned = 31,
	WeaponsAll = 32,
	MetaWeapons = 255
}

MarketCategory.First = MarketCategory.Armors
MarketCategory.Last = MarketCategory.Unassigned

MarketCategory.Ammunitions = MarketCategory.Ammunition
MarketCategory.CreatureProducts = MarketCategory.CreatureProducs
MarketCategory.Quiver = MarketCategory.Quivers
MarketCategory.SoulCores = MarketCategory.SoulCore
MarketCategory.Fist = MarketCategory.FistWeapons

MarketCategoryNames = {
	[MarketCategory.All] = "All",
	[MarketCategory.Armors] = "Armors",
	[MarketCategory.Amulets] = "Amulets",
	[MarketCategory.Boots] = "Boots",
	[MarketCategory.Containers] = "Containers",
	[MarketCategory.Decoration] = "Decoration",
	[MarketCategory.Food] = "Food",
	[MarketCategory.HelmetsHats] = "Helmets and Hats",
	[MarketCategory.Legs] = "Legs",
	[MarketCategory.Others] = "Others",
	[MarketCategory.Potions] = "Potions",
	[MarketCategory.Rings] = "Rings",
	[MarketCategory.Runes] = "Runes",
	[MarketCategory.Shields] = "Shields",
	[MarketCategory.Tools] = "Tools",
	[MarketCategory.Valuables] = "Valuables",
	[MarketCategory.Ammunition] = "Ammunition",
	[MarketCategory.Axes] = "Weapons: Axes",
	[MarketCategory.Clubs] = "Weapons: Clubs",
	[MarketCategory.DistanceWeapons] = "Weapons: Distance",
	[MarketCategory.Swords] = "Weapons: Swords",
	[MarketCategory.WandsRods] = "Weapons: Wands/Rods",
	[MarketCategory.PremiumScrolls] = "Premium Scrolls",
	[MarketCategory.TibiaCoins] = "Tibia Coins",
	[MarketCategory.CreatureProducs] = "Creature Products",
	[MarketCategory.Quivers] = "Quivers",
	[MarketCategory.SoulCore] = "Soul Cores",
	[MarketCategory.FistWeapons] = "Weapons: Fist",
	[MarketCategory.Gold] = "Gold",
	[MarketCategory.Unassigned] = "Unsorted",
	[MarketCategory.WeaponsAll] = "Weapons: All",
	[MarketCategory.MetaWeapons] = "Meta Weapons"
}

function getMarketCategoryName(category)
	return MarketCategoryNames[category]
end

MarketDetailNames = {
	[1] = "Armor: ",
	[2] = "Attack: ",
	[3] = "Capacity: ",
	[4] = "Defence: ",
	[5] = "Description: ",
	[6] = "Expires after: ",
	[7] = "Protection: ",
	[8] = "Minimum Required Level: ",
	[9] = "Minimum Required Magic Level: ",
	[10] = "Vocations: ",
	[11] = "Spell: ",
	[12] = "Skill Boost: ",
	[13] = "Charges: ",
	[14] = "Weapon Type: ",
	[15] = "Weight: ",
	[16] = "Augments: ",
	[17] = "Imbuement Slots: ",
	[18] = "Magic Shield Capacity: ",
	[19] = "Cleave: ",
	[20] = "Damage Reflection: ",
	[21] = "Perfect Shot: ",
	[22] = "Classification: ",
	[23] = "Tier: ",
	[24] = "Elemental Bond: ",
	[25] = "Mantra: ",
	[26] = "Imbuement Effect: ",
}

MarketSellStatus = {
	"cancelled",
	"expired",
	"sold"
}

MarketBuyStatus = {
	"cancelled",
	"expired",
	"bought"
}

function getCoinStepValue(itemId)
	if itemId == 22118 then
		return 25 -- need packet
	end
	return 1
end

function getCoinMultiply(value)
    if value % 25 == 0 then
        return value
	end

	local nextBigger = math.ceil(value / 25) * 25
	local nextLower = math.floor(value / 25) * 25

	if math.abs(nextBigger - value) < math.abs(nextLower - value) then
		return nextBigger
	else
		return nextLower
	end
end
