local modpath = minetest.get_modpath(minetest.get_current_modname())

local nameparts_filename = "language.txt"

local nameparts

deep_roads.random_name = function(rand)
	
	if nameparts == nil then
		nameparts = {}
		local file = io.open(modpath .. "/" .. nameparts_filename, "r")
		if file then
			for line in file:lines() do
				table.insert(nameparts, line)
			end
		else
			nameparts = {"Unable to read " .. nameparts_filename}
		end
	end

	local prefix = math.floor(rand * 2^16) % table.getn(nameparts) + 1
	local suffix = math.floor(rand * 2^32) % table.getn(nameparts) + 1
	return (nameparts[prefix] .. nameparts[suffix]):gsub("^%l", string.upper)
end

-- By Hamlet.
-- Suggested use: random_string()
deep_roads.random_string = function(seed)
	math.randomseed(seed*1000000000)
	
	local length = math.random(2, 8)

	local counter = 0
	local number = 0
	local initial_letter = true
	local string = ""
	local exchanger = ""
	local forced_choice = ""
	local vowels = {"a", "e", "i", "o", "u"}
	local semivowels = {"y", "w"}

	local simple_consonants = {
		"m", "n", "b", "p", "d", "t", "g", "k", "l", "r", "s", "z", "h"
	}

	local compound_consonants = {
		"nh", "v", "f", "dh", "th", "gh", "kh", "lh", "rh", "sh", "zh"
	}

	local compound_consonants_uppercase = {
		"Nh", "V", "F", "Dh", "Th", "Gh", "Kh", "Lh", "Rh", "Sh", "Zh"
	}

	local previous_letter = ""

	for initial_value = 1, length do

		counter = counter + 1

		local chosen_group = math.random(1, 4)

		if (exchanger == "vowel") then
			chosen_group = math.random(3, 4)

		elseif (exchanger == "semivowel") then
			chosen_group = 1

		elseif (exchanger == "simple consonant") then
			if (counter < length) then
				chosen_group = math.random(1, 2)
			else
				chosen_group = 1
			end

		elseif (exchanger == "compound consonant") then
			chosen_group = 1

		end


		if (chosen_group == 1) then

			number = math.random(1, 5)

			if (initial_letter == true) then
				initial_letter = false
				previous_letter = string.upper(vowels[number])
				string = string .. previous_letter

			else
				previous_letter = vowels[number]
				string = string .. previous_letter

			end

			exchanger = "vowel"


		elseif (chosen_group == 2) then

			number = math.random(1, 2)

			if (initial_letter == true) then
				initial_letter = false
				previous_letter = string.upper(semivowels[number])
				string = string .. previous_letter
			else
				previous_letter = semivowels[number]
				string = string .. previous_letter

			end

			exchanger = "semivowel"


		elseif (chosen_group == 3) then

			number = math.random(1, 13)

			if (initial_letter == true) then
				initial_letter = false
				previous_letter = string.upper(simple_consonants[number])
				string = string .. previous_letter

			else
				previous_letter = simple_consonants[number]
				string = string .. previous_letter

			end

			exchanger = "simple consonant"


		elseif (chosen_group == 4) then

			number = math.random(1, 11)

			if (initial_letter == true) then
				initial_letter = false
				previous_letter = compound_consonants_uppercase[number]
				string = string .. previous_letter

			else
				previous_letter = compound_consonants[number]
				string = string .. previous_letter
			end

			exchanger = "compound consonant"

		end
	end

	initial_letter = true

	return string
end