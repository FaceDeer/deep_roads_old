deep_roads = {} --create a container for functions and constants

--grab a shorthand for the filepath of the mod
local modpath = minetest.get_modpath(minetest.get_current_modname())

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

dofile(modpath.."/functions.lua") --function definitions

local gridscale = {x=500, y=200, z=500}
local ymin = -2300
local ymax = -10
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


local tunnel_def = 
{
	rail = true,-- math.random() < 0.75,
	powered_rail = true,
	bridge_block = c_wood,
	seal_lava_material = c_stonebrick,
	seal_water_material = c_glass,
	
	bridge_support_block = c_fence,
	bridge_support_spacing = 3,
	--bridge_width = 3,
	
	--wall_block = c_stonebrick,
	--ceiling_block = c_stonebrick,
	
	stair_block = c_stonebrickstair,
	
	torch_spacing = 8,
	torch_height = 2,
	--width = 2,
	--height = 4,
	
	landing_length = 3,
	stair_length = 14,
	
}
local narrow_tunnel = 
{
	width=0,
	height=2,
	bridge_block = c_wood,
}
local sewer_def =
{
	trench_block = c_stonebrick,
	floor_block = c_stonebrick,
	liquid_block = c_water,
	bridge_block = c_stonebrick,
	bridge_width = 1,
	torch_spacing = 16,
	torch_height = 3,
}

local intersection_def =
{
	min_radius = 8,
	max_radius = 16,
}

-- On generated function
minetest.register_on_generated(function(minp, maxp, seed)

	--if out of range of cave definition limits, abort
--	if minp.y > ymax or maxp.y < ymin then
--		return
--	end
	
	--easy reference to commonly used values
	local t_start = os.clock()
	local x_max = maxp.x
	local y_max = maxp.y
	local z_max = maxp.z
	local x_min = minp.x
	local y_min = minp.y
	local z_min = minp.z
	
	minetest.debug ("[deep_roads] chunk ".. minetest.pos_to_string(minp) .. " " .. minetest.pos_to_string(maxp)) --tell people you are generating a chunk
	
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local area = VoxelArea:new{MinEdge=emin, MaxEdge=emax}
	vm:get_data(data)
	vm:get_param2_data(data_param2)

	local context = deep_roads.Context:new(minp, maxp, area, data, data_param2, gridscale, ymin, ymax, intersection_def, tunnel_def, connection_probability)
	
	for _, pt in ipairs(context.points) do
		--minetest.debug(minetest.pos_to_string(pt) .. " named " .. deep_roads.random_name(pt.val))
		context:carve_intersection(pt)
	end
	
	for _, conn in ipairs(context.connections) do
		--minetest.debug(deep_roads.random_name(conn.pt1.val) .. " connected to " .. deep_roads.random_name(conn.pt2.val) .. " with val " .. tostring(conn.val))
		context:segmentize_connection(conn)
	end
	
	--mandatory values
	local sidelen = x_max - x_min + 1 --length of a mapblock
	local chunk_lengths = {x = sidelen, y = sidelen, z = sidelen} --table of chunk edges
	local chunk_lengths2D = {x = sidelen, y = sidelen, z = 1}
	local minposxyz = {x = x_min, y = y_min, z = z_min} --bottom corner
	local minposxz = {x = x_min, y = z_min} --2D bottom corner

	
	--send data back to voxelmanip
	vm:set_data(data)
	vm:set_param2_data(data_param2)
--	--calc lighting
	vm:set_lighting({day = 0, night = 0})
	vm:calc_lighting()
--	--write it to world
	vm:write_to_map()

	local chunk_generation_time = math.ceil((os.clock() - t_start) * 1000) --grab how long it took
	minetest.debug ("[deep_roads] "..chunk_generation_time.." ms") --tell people how long
end)


print("[deep_roads] loaded!")
