deep_roads = {} --create a container for functions and constants

--grab a shorthand for the filepath of the mod
local modpath = minetest.get_modpath(minetest.get_current_modname())

dofile(modpath.."/voxelarea_iterator.lua")
dofile(modpath.."/functions.lua") --function definitions
dofile(modpath.."/config.lua")

deep_roads.buildable_to = {}

-- As soon as the server fires up, build a list of all registered buildable_to nodes.
-- By using minetest.after we don't have to worry about the order in which mods are initialized
minetest.after(0, function()
	for name, def in pairs(minetest.registered_nodes) do
		if def.buildable_to then
			deep_roads.buildable_to[minetest.get_content_id(name)] = true
		end
	end
end)

local gridscale = {x=deep_roads.config.gridscale_xz, y=deep_roads.config.gridscale_y, z=deep_roads.config.gridscale_xz}
local ymin = deep_roads.config.y_min
local ymax = deep_roads.config.y_max
local connection_probability = 0.75

local data = {}
local data_param2 = {}

local c_water = minetest.get_content_id("default:water_source")
local c_wood = minetest.get_content_id("default:wood")
local c_stone = minetest.get_content_id("default:stone")
local c_stonebrick = minetest.get_content_id("default:stonebrick")
local c_stonebrickstair = minetest.get_content_id("stairs:stair_stonebrick")
local c_gravel = minetest.get_content_id("default:gravel")
local c_glass = minetest.get_content_id("default:glass")
local c_fence = minetest.get_content_id("default:fence_wood")
local c_stonestair = minetest.get_content_id("stairs:stair_stone")

local sewer_def =
{
	trench_block = c_stonebrick,
	stair_block = c_stonebrickstair,
	floor_block = c_stonebrick,
	liquid_block = c_water,
	bridge_block = c_stonebrick,
	bridge_width = 1,
	torch_spacing = 16,
	torch_height = 3,
	landing_length = 2,
	stair_length = 1,
}

deep_roads.register_network = function(network_def)

	-- On generated function
	minetest.register_on_generated(function(minp, maxp, seed)
	
		--if out of range of cave definition limits, abort
	--	if minp.y > ymax or maxp.y < ymin then
	--		return
	--	end
		
		--easy reference to commonly used values
		local t_start = os.clock()
	--	local x_max = maxp.x
	--	local y_max = maxp.y
	--	local z_max = maxp.z
	--	local x_min = minp.x
	--	local y_min = minp.y
	--	local z_min = minp.z
	--	
	--	--mandatory values
	--	local sidelen = x_max - x_min + 1 --length of a mapblock
	--	local chunk_lengths = {x = sidelen, y = sidelen, z = sidelen} --table of chunk edges
	--	local chunk_lengths2D = {x = sidelen, y = sidelen, z = 1}
	--	local minposxyz = {x = x_min, y = y_min, z = z_min} --bottom corner
	--	local minposxz = {x = x_min, y = z_min} --2D bottom corner
	
		
		minetest.debug ("[deep_roads] ".. network_def.name .. " chunk ".. minetest.pos_to_string(minp) .. " " .. minetest.pos_to_string(maxp)) --tell people you are generating a chunk
		
		local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
		local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
		vm:get_data(data)
		vm:get_param2_data(data_param2)
	
		local context = deep_roads.Context:new(minp, maxp, area, data, data_param2, network_def)
		
		for _, pt in ipairs(context.points) do
			--minetest.debug(minetest.pos_to_string(pt) .. " named " .. deep_roads.random_name(pt.val))
			context:carve_intersection(pt)
		end
		
		for _, conn in ipairs(context.connections) do
			--minetest.debug(deep_roads.random_name(conn.pt1.val) .. " connected to " .. deep_roads.random_name(conn.pt2.val) .. " with val " .. tostring(conn.val))
			context:segmentize_connection(conn)
		end
		
		--send data back to voxelmanip
		vm:set_data(data)
		vm:set_param2_data(data_param2)
	--	--calc lighting
		vm:set_lighting({day = 0, night = 0})
		vm:calc_lighting()
		vm:update_liquids()
	--	--write it to world
		vm:write_to_map()
	
		local chunk_generation_time = math.ceil((os.clock() - t_start) * 1000) --grab how long it took
		minetest.debug ("[deep_roads] "..chunk_generation_time.." ms") --tell people how long
	end)
end



local network_pedestrian_spaghetti =
{
	name = "Pedestrian spaghetti",
	gridscale = {x=200, y=100, z=200},
	intersections = {
		min_radius = 4,
		max_radius = 8,
		min_count = 1,
		max_count = 3,
	},
	tunnels = {
		width=0,
		height=2,
		bridge_block = c_wood,
		stair_block = c_stonestair,
		torch_spacing = 16,
		torch_height = 1,
		bridge_support_block = c_fence,
		bridge_support_spacing = 6,
	},
	ymax = 0,
	ymin = -400,
	connection_probability = 0.75,
}

local network_long_rails =
{
	name = "Long rails",
	gridscale = {x=1000, y=200, z=1000},
	intersections = {
		min_radius = 8,
		max_radius = 16,
		min_count = 1,
		max_count = 6,
	},
	tunnels = {
		rail = true,
		powered_rail = true,
		bridge_block = c_wood,
		seal_lava_material = c_stonebrick,
		seal_water_material = c_glass,
		
		bridge_support_block = c_fence,
		bridge_support_spacing = 3,
		bridge_width = 1,
		
		wall_block = c_stonebrick,
		ceiling_block = c_stonebrick,
		floor_block = c_stonebrick,
		
		stair_block = c_stonebrickstair,
		
		torch_spacing = 8,
		torch_height = 2,

		landing_length = 3,
		stair_length = 14,
	},
	ymax = -20,
	ymin = -2300,
	connection_probability = 0.75,
}

deep_roads.register_network(network_pedestrian_spaghetti)
deep_roads.register_network(network_long_rails)

print("[deep_roads] loaded!")
