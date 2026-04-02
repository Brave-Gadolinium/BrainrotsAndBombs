--!strict
-- LOCATION: ReplicatedStorage/Modules/ItemConfigurations

local ItemConfigurations = {}

local RarityUtils = require(script.Parent:WaitForChild("RarityUtils"))

type Item = {
	Rarity: string,
	Income: number,
	ImageId: string
}

ItemConfigurations.Items = {
	["noobini_pizzanini"] = { Rarity = "Common", Income = 2, ImageId = "rbxassetid://84990680447246", DisplayName = "Noobini Pizzanini" },
	["pipi_kiwi"] = { Rarity = "Common", Income = 3, ImageId = "rbxassetid://76570018794551", DisplayName = "Pipi Kiwi" },
	["tim_cheese"] = { Rarity = "Common", Income = 5, ImageId = "rbxassetid://104606290053588", DisplayName = "Tim Cheese" },
	["svinina_bombardino"] = { Rarity = "Common", Income = 7, ImageId = "rbxassetid://81179045456353", DisplayName = "Svinina Bombardino" },
	["talpa_di_fero"] = { Rarity = "Common", Income = 9, ImageId = "rbxassetid://137336457665277", DisplayName = "Talpa Di Fero" },

	["bananini_kittini"] = { Rarity = "Uncommon", Income = 10, ImageId = "rbxassetid://120806800069853", DisplayName = "Bananini Kittini" },
	["bobrito_bandito"] = { Rarity = "Uncommon", Income = 12, ImageId = "rbxassetid://113160598209328", DisplayName = "Bobrito Bandito" },
	["boneca_ambalabu"] = { Rarity = "Uncommon", Income = 15, ImageId = "rbxassetid://95525702570083", DisplayName = "Boneca Ambalabu" },
	["fluri_flura"] = { Rarity = "Uncommon", Income = 18, ImageId = "rbxassetid://91890383303705", DisplayName = "Fluri Flura" },
	["gangster_footera"] = { Rarity = "Uncommon", Income = 20, ImageId = "rbxassetid://89199964787184", DisplayName = "Gangster Footera" },

	["banana_dancana"] = { Rarity = "Rare", Income = 22, ImageId = "rbxassetid://83201035411535", DisplayName = "Banana Dancana" },
	["bananita_dolphinita"] = { Rarity = "Rare", Income = 25, ImageId = "rbxassetid://116936102156121", DisplayName = "Bananita Dolphinita" },
	["brr_brr_patapim"] = { Rarity = "Rare", Income = 30, ImageId = "rbxassetid://73732151757451", DisplayName = "Brr Brr Patapim" },
	["cacto_hipopotamo"] = { Rarity = "Rare", Income = 40, ImageId = "rbxassetid://125554621399518", DisplayName = "Cacto Hipopotamo" },
	["ta_ta_ta_ta_sahur"] = { Rarity = "Rare", Income = 50, ImageId = "rbxassetid://135776228957110", DisplayName = "Ta Ta Ta Ta Sahur" },

	["avocadini_guffo"] = { Rarity = "Epic", Income = 75, ImageId = "rbxassetid://129544300092744", DisplayName = "Avocadini Guffo" },
	["ballerina_cappuccina"] = { Rarity = "Epic", Income = 130, ImageId = "rbxassetid://123741024874755", DisplayName = "Ballerina Cappuccina" },
	["bambini_crostini"] = { Rarity = "Epic", Income = 180, ImageId = "rbxassetid://71314504479361", DisplayName = "Bambini Crostini" },
	["brri_brri_bicus_dicus"] = { Rarity = "Epic", Income = 230, ImageId = "rbxassetid://91960379994870", DisplayName = "Brri Brri Bicus Dicus" },
	["cappuccino_assassino"] = { Rarity = "Epic", Income = 250, ImageId = "rbxassetid://125384494829028", DisplayName = "Cappuccino Assassino" },

	["blueberrinni_octopusini"] = { Rarity = "Legendary", Income = 300, ImageId = "rbxassetid://103228128564161", DisplayName = "Blueberrinni Octopusini" },
	["bombombini_gusini"] = { Rarity = "Legendary", Income = 350, ImageId = "rbxassetid://135238195278096", DisplayName = "Bombombini Gusini" },
	["burbaloni_luliloli"] = { Rarity = "Legendary", Income = 400, ImageId = "rbxassetid://84791223223147", DisplayName = "Burbaloni Luliloli" },
	["cavallo_virtuoso"] = { Rarity = "Legendary", Income = 450, ImageId = "rbxassetid://132024020072422", DisplayName = "Cavallo Virtuoso" },
	["chimpanzini_bananini"] = { Rarity = "Legendary", Income = 500, ImageId = "rbxassetid://100324087260160", DisplayName = "Chimpanzini Bananini" },

	["bombardiro_crocodilo"] = { Rarity = "Mythic", Income = 1000, ImageId = "rbxassetid://118911944523229", DisplayName = "Bombardiro Crocodilo" },
	["cocofanto_elefanto"] = { Rarity = "Mythic", Income = 2000, ImageId = "rbxassetid://120394923537076", DisplayName = "Cocofanto Elefanto" },
	["girafa_celeste"] = { Rarity = "Mythic", Income = 3000, ImageId = "rbxassetid://77772493536107", DisplayName = "Girafa Celeste" },
	["gorillo_watermelondrillo"] = { Rarity = "Mythic", Income = 4000, ImageId = "rbxassetid://116519696815043", DisplayName = "Gorillo Watermelondrillo" },
	["illuminato_triangolo"] = { Rarity = "Mythic", Income = 5000, ImageId = "rbxassetid://101531753361317", DisplayName = "Illuminato Triangolo" },

	["chicleteira_bicicleteira"] = { Rarity = "Secret", Income = 6000, ImageId = "rbxassetid://77473927217129", DisplayName = "Chicleteira Bicicleteira" },
	["chicleteirina_bicicleteirina"] = { Rarity = "Secret", Income = 7000, ImageId = "rbxassetid://126839206846142", DisplayName = "Chicleteirina Bicicleteirina" },
	["chillin_chili"] = { Rarity = "Secret", Income = 8000, ImageId = "rbxassetid://87737648998225", DisplayName = "Chillin Chili" },
	["karkerkar_kurkur"] = { Rarity = "Secret", Income = 9000, ImageId = "rbxassetid://84036458438934", DisplayName = "Karkerkar Kurkur" },
	["la_grande_combinasion"] = { Rarity = "Secret", Income = 10000, ImageId = "rbxassetid://135016116276627", DisplayName = "La Grande Combinasion" },

	["ballerino_lololo"] = { Rarity = "Brainrotgod", Income = 11000, ImageId = "rbxassetid://118372366016209", DisplayName = "Ballerino Lololo" },
	["dragon_cannelloni"] = { Rarity = "Brainrotgod", Income = 12000, ImageId = "rbxassetid://98933904891382", DisplayName = "Dragon Cannelloni" },
	["esok_sekolah"] = { Rarity = "Brainrotgod", Income = 13000, ImageId = "rbxassetid://134121437161569", DisplayName = "Esok Sekolah" },
	["espresso_signora"] = { Rarity = "Brainrotgod", Income = 14000, ImageId = "rbxassetid://81414971322891", DisplayName = "Espresso Signora" },
	["matteo"] = { Rarity = "Brainrotgod", Income = 15000, ImageId = "rbxassetid://86343149465023", DisplayName = "Matteo" },
} :: { [string]: Item }

function ItemConfigurations.GetItemsByRarity(rarity: string): {string}
	local normalizedRarity = RarityUtils.Normalize(rarity)
	local foundItems = {}
	for itemName, data in pairs(ItemConfigurations.Items) do
		if RarityUtils.Normalize(data.Rarity) == normalizedRarity then
			table.insert(foundItems, itemName)
		end
	end
	return foundItems
end

function ItemConfigurations.GetItemData(itemName: string): Item
	return ItemConfigurations.Items[itemName]
end

return ItemConfigurations
