deep_roads = {} --create a container for functions and constants

--grab a shorthand for the filepath of the mod
local modpath = minetest.get_modpath(minetest.get_current_modname())

dofile(modpath.."/functions.lua") --function definitions

local gridscale = {x=1000, y=200, z=1000}

local data = {}
local data_param2 = {}

-- On generated function
minetest.register_on_generated(function(minp, maxp, seed)

	--if out of range of cave definition limits, abort
--	if minp.y > YMAX or maxp.y < YMIN then
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

	
	local points = deep_roads.road_points_around(minp, gridscale, -2000, -10)
	
	for _, pt in ipairs(points) do
		--minetest.debug(minetest.pos_to_string(pt) .. " named " .. deep_roads.random_name(pt.val))
		deep_roads.carve_intersection(pt, 8, area, data)
	end
	
	local connections = deep_roads.find_connections(points, gridscale, 0.75)

	for _, conn in ipairs(connections) do
		--minetest.debug(deep_roads.random_name(conn.pt1.val) .. " connected to " .. deep_roads.random_name(conn.pt2.val) .. " with val " .. tostring(conn.val))
		deep_roads.segmentize_connection(conn, area, data, data_param2)
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
