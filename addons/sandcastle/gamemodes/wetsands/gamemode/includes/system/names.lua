-- Bot players' names, after the games and shows they come from. A bot takes
-- one no player on the server has (Source would number a second one), drawn
-- at random; features/aiwar/sv_bots.lua names the war's bots by it.
local ipairs = ipairs
module (...)

FRANCHISES =
{
	{
		name = "Undertale",
		names =
		{
			"Sans", "Papyrus", "Frisk", "Chara", "Toriel", "Asgore", "Asriel", "Flowey", "Undyne", "Alphys",
			"Mettaton EX", "Napstablook", "Muffet", "Temmie", "Grillby", "Gerson", "Burgerpants", "Monster Kid",
			"Annoying Dog", "Lesser Dog", "Greater Dog", "Royal Guard 01", "Shyren", "Clover", "Tutorial",
			"Tutorial Undertale"
		}
	},
	{
		name = "Deltarune",
		names =
		{
			"Kris", "Susie", "Ralsei", "Lancer", "Noelle", "Berdly", "Queen", "King of Spades", "Jevil", "Seam",
			"Spamton NEO", "[[BIG SHOT]]", "Rouxls Kaard", "Tasque Manager", "Rudinn Ranger", "Hathy", "Ponman",
			"Swatchling", "Starwalker", "Tenna", "Mike", "Catti", "Jockington", "Snowgrave Enjoyer"
		}
	},
	{
		name = "Steven Universe",
		names =
		{
			"Steven", "Pearl Universe", "Garnet Universe", "Amethyst Universe", "Connie Maheswaran",
			"Greg Universe", "Lapis Lazuli", "Peridot", "Bismuth", "Lars Barriga", "Sadie Miller", "Onion",
			"Ronaldo Fryman", "Jasper", "Spinel", "Stevonnie", "Sugilite", "Alexandrite", "Lion", "Mr. Smiley",
			"Sour Cream", "Kiki Pizza", "Centipeetle", "Yellow Diamond", "Blue Diamond", "Cookie Cat"
		}
	},
	{
		name = "Team Fortress 2",
		names =
		{
			"Scout", "Pyromancer", "Soldier Guy", "Heavy Weapons Guy 2", "Demoman Fortress", "The Engineer",
			"World's #2 Best Sniper", "The Spy", "Medic Who Heals", "Saxton Hale", "Miss Pauling", "Merasmus",
			"Redmond Mann", "Blutarch Mann", "Gray Mann", "The Administrator", "Horseless Headless Horsemann",
			"MONOCULUS", "Pootis", "Sandvich Thief", "Mentlegen", "Dispenser Here", "Crit-a-Cola", "Australium"
		}
	},
	{
		name = "Left 4 Dead 2",
		names =
		{
			"Coach", "Ellis", "Nick", "Rochelle", "Bill", "Zoey", "Louis", "Francis", "Virgil", "Whitaker",
			"Keith", "Tank", "Witch", "Boomer", "Jockey", "Spitter", "Charger", "Smoker", "Hunter",
			"Gnome Chompski", "Midnight Rider", "CEDA Agent", "Riot Cop", "Mudman", "Clown Car"
		}
	},
	{
		name = "Stardew Valley",
		names =
		{
			"Abigail", "Sebastian", "Haley", "Elliott", "Harvey", "Leah", "Maru", "Penny", "Sam", "Emily",
			"Shane", "Pierre", "Gus", "Clint", "Robin", "Demetrius", "Linus", "Willy", "Marnie", "Pam",
			"Mayor Lewis", "Krobus", "The Wizard", "Mr. Qi", "Gunther", "Morris", "Junimo", "Grandpa's Note"
		}
	},
	{
		name = "Code Lyoko",
		names =
		{
			"Jeremie Belpois", "Aelita Schaeffer", "Ulrich Stern", "Odd Della Robbia", "Yumi Ishiyama",
			"William Dunbar", "XANA", "Franz Hopper", "Jim Morales", "Sissi Delmas", "Herb Pichon",
			"Nicolas Poliakoff", "Hiroki Ishiyama", "Kiwi", "Kankrelat", "Krabe", "Megatank", "Tarantula",
			"Blok", "Hornet", "Scyphozoa", "Kolossus", "Return to the Past", "Supercomputer"
		}
	}
}

BOT_NAMES = {}
for _, franchise in ipairs (FRANCHISES) do
	for _, name in ipairs (franchise.names) do BOT_NAMES [#BOT_NAMES + 1] = name end
end

-- A name not in taken (name → true, the players' names now), drawn by the
-- caller's randomInt (low, high); nil when every one is taken.
function Pick (taken, randomInt)
	local free = {}
	for _, name in ipairs (BOT_NAMES) do
		if not taken [name] then free [#free + 1] = name end
	end
	if #free == 0 then return nil end
	return free [randomInt (1, #free)]
end
