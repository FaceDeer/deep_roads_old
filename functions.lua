local c_air = minetest.get_content_id("air")
local c_lava = minetest.get_content_id("default:lava_source")
local c_water = minetest.get_content_id("default:water_source")
local c_rail = minetest.get_content_id("carts:rail")
local c_powerrail = minetest.get_content_id("carts:powerrail")
local c_torch_wall = minetest.get_content_id("default:torch_wall")

local c_wood_sign = minetest.get_content_id("default:sign_wall_wood")
local c_mese_post = minetest.get_content_id("default:mese_post_light")

local nameparts_filename = "language.txt"

local nameparts = {}
local file = io.open(minetest.get_modpath(minetest.get_current_modname()).."/" .. nameparts_filename, "r")
if file then
	for line in file:lines() do
		table.insert(nameparts, line)
	end
else
	nameparts = {"Unable to read " .. nameparts_filename}
end

-- these get used a lot, predefine them and save on stack allocations
local intersectmin, intersectmax

local default_tunnel_def = 
{
	rail = false, -- places a single rail line down the center of the tunnel.
	powered_rail = false, -- if true, powered rail nodes will be placed at intervals to keep the carts moving
	liquid_block = nil, -- if set to a block, then instead of rails will fill the lowest level of the tunnel with this fluid.
	trench_block = nil, -- when non-nil, puts blocks along the base of the walls to make a depressed trench in the center of the tunnel. Useful for sewers, subways
	torch_spacing = nil, -- nil means no torches
	torch_height = 1,
	torch_probability = 1, -- allows for erratic torch spacing
	torch_arrangement = "1 wall", -- "1 wall" puts torches on one wall, "2 wall pairs" puts them on both walls at the same place, "2 wall alternating" puts them on alternating walls, "ceiling" puts them on the ceiling.
	sign_probability = 1, -- allows for erratic sign spacing
	bridge_block = nil, -- if not nil, replaces air in floor
	bridge_width = 0, -- width of bridge (same meaning as "width", so width of 1 gives a bridge 3 wide, and so forth)
	bridge_support_spacing = 12, -- Bridge supports are not guaranteed, if mapgen can't find a base below the bridge in the current chunk it won't draw a support. This limits the height supports can go.
	bridge_support_block = nil,
	stair_block = nil, -- also used for arches
	floor_block = nil, -- when non-nil, replaces floor with this block type. Does not bridge air gaps.
	wall_block = nil, -- when non-nil, replaces walls with this block type
	ceiling_block = nil, -- when non-nil, replaces ceiling with this block type
	landing_length = 0, -- when non-zero, a landing this many blocks long will be placed every stair_length interval
	stair_length = 1, -- interval between landings
	seal_lava_material = nil, -- replace lava blocks in walls with this material
	seal_water_material = nil, -- replace water blocks in walls with this material
	seal_air_material = nil, -- patch holes in walls and ceilings with this material. Use bridge material for patching floors.
	width = 1, -- note: this is the number of blocks added on either side of the center block. So width 1 gives a tunnel 3 blocks wide, width 2 gives a tunnel 5 blocks wide, etc.
	height = 3,
}

local simple_copy = function(t)
	local r = {}
	for k, v in pairs(t) do
		r[k] = v
	end
	return r
end

deep_roads.Context = {}

--------------------------------------------------------------------

local set_defaults = function(defaults, target)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = v
		end
	end
end

function deep_roads.Context:new(minp, maxp, area, data, data_param2, network_def)

--gridscale, ymin, ymax, intersection_def, connection_def, connection_probability)
	
	set_defaults(default_tunnel_def, network_def.tunnels)

	local context = {}
	setmetatable(context, self)
	self.__index = self
	context.locked_indices = {}
	context.data = data
	context.data_param2 = data_param2
	context.area = area
	context.chunk_min = minp
	context.chunk_max = maxp
	context.gridscale = network_def.gridscale
	context.ymin = network_def.ymin
	context.ymax = network_def.ymax
	context.seed = tonumber(minetest.get_mapgen_setting("seed"))
	
	context:road_points_around(network_def.intersections)
	context:find_connections(network_def.connection_probability, network_def.tunnels)
	
	return context
end


local get_sign = function(num)
	if num > 0 then return 1 else return -1 end
end

local random_sign = function()
	if math.random() > 0.5 then return 1 else return -1 end
end

deep_roads.random_name = function(rand)
	local prefix = math.floor(rand * 2^16) % table.getn(nameparts) + 1
	local suffix = math.floor(rand * 2^32) % table.getn(nameparts) + 1
	return (nameparts[prefix] .. nameparts[suffix]):gsub("^%l", string.upper)
end

local distance_within = function(pos1, pos2, distance)
	return math.abs(pos1.x-pos2.x) <= distance and
		math.abs(pos1.y-pos2.y) <= distance and
		math.abs(pos1.z-pos2.z) <= distance
end

-- Finds an intersection between two AABBs, or nil if there's no overlap
local intersect = function(minpos1, maxpos1, minpos2, maxpos2)
	--checking x and z first since they're more likely to fail to overlap
	if minpos1.x <= maxpos2.x and maxpos1.x >= minpos2.x and
		minpos1.z <= maxpos2.z and maxpos1.z >= minpos2.z and
		minpos1.y <= maxpos2.y and maxpos1.y >= minpos2.y then
		
		return {
				x = math.max(minpos1.x, minpos2.x),
				y = math.max(minpos1.y, minpos2.y),
				z = math.max(minpos1.z, minpos2.z)
			},
			{
				x = math.min(maxpos1.x, maxpos2.x),
				y = math.min(maxpos1.y, maxpos2.y),
				z = math.min(maxpos1.z, maxpos2.z)
			}
	end
	return nil, nil
end


-- Grid stuff
--------------------------------------------------

function deep_roads.Context:scatter_3d(min_xyz, min_output_size, max_output_size)
	local gridscale_xyz = self.gridscale
	
	local next_seed = math.random(1, 1000000000)
	math.randomseed(min_xyz.x + min_xyz.z * 2 ^ 8 + min_xyz.y * 2 ^ 16 + self.seed * 2 ^ 24)
	local count = math.random(min_output_size, max_output_size)
	local result = {}
	while count > 0 do
		local point = {}
		point.val = math.random()
		point.x = math.floor(math.random() * gridscale_xyz.x + min_xyz.x)
		point.y = math.floor(math.random() * gridscale_xyz.y + min_xyz.y)
		point.z = math.floor(math.random() * gridscale_xyz.z + min_xyz.z)
		table.insert(result, point)
		count = count - 1
	end
	
	math.randomseed(next_seed)
	return result
end


function deep_roads.Context:road_points_around(intersection_def)
	local min_output_size = intersection_def.min_count
	local max_output_size = intersection_def.max_count
	local pos = self.chunk_min
	local gridscale_xyz = self.gridscale
	local min_y = self.ymin
	local max_y = self.ymax
	
	local min_xyz = {
		x = math.floor(pos.x / gridscale_xyz.x),
		y = math.floor(pos.y / gridscale_xyz.y),
		z = math.floor(pos.z / gridscale_xyz.z)}

	local result = {}
	
	for x_grid = -1, 1 do
		for y_grid = -1, 1 do
			for z_grid = -1, 1 do
				local grid = vector.multiply(gridscale_xyz, vector.add(min_xyz, {x=x_grid, y=y_grid, z=z_grid}))
				for _, point in pairs(self:scatter_3d(grid, min_output_size, max_output_size)) do
					if (point.y >= min_y and point.y <= max_y) then
						point.def = intersection_def
						table.insert(result, point)
					end
				end
			end
		end
	end
	
	self.points = result
end

-- Connection stuff
------------------------------------------------------

function deep_roads.Context:find_connections(odds, tunnel_def)
	local points = self.points
	local gridscale = self.gridscale
	local connections = {}
	-- Do a triangular array comparison, ensuring that each pair is tested only once.
	for index1 = 1, table.getn(points) do
		for index2 = index1 + 1, table.getn(points) do
			local point1 = simple_copy(points[index1])
			local point2 = simple_copy(points[index2])
			local diff = vector.subtract(point1, point2)
			if math.abs(diff.x) < gridscale.x and math.abs(diff.y) < gridscale.y and math.abs(diff.z) < gridscale.z then -- Ensure no pair under consideration is more than a grid-length away on any axis.
				local combined = (point1.val * 100000 + point2.val * 100000) % 1 -- Combine the two random values and then take the fractional portion to get back to 0-1 range
				if combined < odds then
					local connection_val = combined/odds
					local dir = vector.direction(point1, point2)
					
					local radius1 = math.floor(point1.val*(point1.def.max_radius-point1.def.min_radius)+ point1.def.min_radius)+2
					local radius2 = math.floor(point2.val*(point2.def.max_radius-point2.def.min_radius)+ point2.def.min_radius)+2
										
					point1.x = point1.x + math.ceil(dir.x * radius1)
					point1.z = point1.z + math.ceil(dir.z * radius1)
					
					point2.x = point2.x + math.ceil(dir.x * radius2)
					point2.z = point2.z + math.ceil(dir.z * radius2)

					if point1.x + point1.y + point1.z > point2.x + point2.y + point2.z then -- always sort each pair of points the same way.
						table.insert(connections, {pt1 = point1, pt2 = point2, val = connection_val, def=tunnel_def})
					else
						table.insert(connections, {pt1 = point2, pt2 = point1, val = connection_val, def=tunnel_def})
					end
				end
			end
		end
	end
	self.connections = connections
end

-----------------------------------------------------------------
-- Map-drawing stuff

function deep_roads.Context:modify_slab(corner1, corner2, tunnel_def, slab_block, seal_air_material, seal_water_material, seal_lava_material)
	intersectmin, intersectmax = intersect(corner1, corner2, self.chunk_min, self.chunk_max)
	
	if intersectmin ~= nil then
		local data = self.data
		local locked_indices = self.locked_indices
		for pi in self.area:iterp(intersectmin, intersectmax) do
			if not locked_indices[pi] then
				local current_material = data[pi]
			
				if seal_air_material and current_material == c_air then
					data[pi] = seal_air_material
				elseif seal_lava_material and current_material == c_lava then
					data[pi] = seal_lava_material
				elseif seal_water_material and current_material == c_water then
					data[pi] = seal_water_material
				elseif slab_block and current_material ~= c_air and current_material ~= c_lava and current_material ~= c_water then
					data[pi] = slab_block
				end
			end
		end
	end
end

-------------------------------------------------------------------
-- Bridges

function deep_roads.Context:draw_bridge_support(pi, x, y, z, length_axis, bridge_support_spacing, bridge_support_block)
	local area = self.area
	if (length_axis == "x" and x % bridge_support_spacing == 0) or (length_axis == "z" and z % bridge_support_spacing == 0) then
		local data = self.data
		local bridge_start = nil
		local bridge_end = nil
		-- start looking one y-level below the bridge pos
		for support_y = y-1, self.chunk_min.y, -1 do
			local content = data[area:index(x, support_y, z)]
			if deep_roads.buildable_to[content] then
				if bridge_start == nil then
					bridge_start = vector.new(x, support_y, z)
				end
			else
				bridge_end = vector.new(x, support_y+1, z)
				break
			end
		end
		
		if bridge_start ~= nil and bridge_end ~= nil then
			local locked_indices = self.locked_indices
			for si in area:iterp(bridge_end, bridge_start) do
				if not locked_indices[si] then
					data[si] = bridge_support_block
				end
			end
		end
	end
end

function deep_roads.Context:draw_bridge(path1, path2, width_axis, length_axis, tunnel_def)
	local bridge_block = tunnel_def.bridge_block
	local bridge_support_block = tunnel_def.bridge_support_block
	local bridge_support_spacing = tunnel_def.bridge_support_spacing
	local area = self.area
	local data = self.data
	local locked_indices = self.locked_indices
	local bridge1 = vector.new(path1.x, path1.y-1, path1.z)
	local bridge2 = vector.new(path2.x, path2.y-1, path2.z)
	bridge1[width_axis] = bridge1[width_axis] - tunnel_def.bridge_width
	bridge2[width_axis] = bridge2[width_axis] + tunnel_def.bridge_width
	intersectmin, intersectmax = intersect(bridge1, bridge2, self.chunk_min, self.chunk_max)
	if intersectmin ~= nil then
		for pi, x, y, z in area:iterp_xyz(intersectmin, intersectmax) do
			if deep_roads.buildable_to[data[pi]] then
				data[pi] = bridge_block
				locked_indices[pi] = true
				if bridge_support_block ~= nil then
					self:draw_bridge_support(pi, x, y, z, length_axis, bridge_support_spacing, bridge_support_block)
				end
			end
		end
	end
end

----------------------------------------------------------------------------
-- Torches

function deep_roads.Context:place_torch(intersectmin, intersectmax, axis, intermittency, backing_axis, backing_dir, node, param2)
	local area = self.area
	local data = self.data
	local data_param2 = self.data_param2
	local locked_indices = self.locked_indices
	for pi, x, y, z in area:iterp_xyz(intersectmin, intersectmax) do
		if not locked_indices[pi] then
			if (axis == "x" and x % intermittency == 0) or (axis == "z" and z % intermittency == 0) then
				if backing_axis == "x" then x = x + backing_dir else z = z + backing_dir end
				if not area:contains(x, y, z) or not deep_roads.buildable_to[data[area:index(x, y, z)]] then
					data[pi] = node
					data_param2[pi] = param2
					locked_indices[pi] = true
				end
			end
		end
	end
end

function deep_roads.Context:draw_torches(path1, path2, width_axis, length_axis, tunnel_def, boost_height)
	local torch1 = vector.new(path1)
	local torch2 = vector.new(path2)
	local area = self.area
	if tunnel_def.torch_arrangement == "1 wall" or tunnel_def.torch_arrangement == "2 wall pairs" then
		torch1.y = torch1.y + tunnel_def.torch_height + boost_height
		torch2.y = torch2.y + tunnel_def.torch_height + boost_height
		torch1[width_axis] = torch1[width_axis] + tunnel_def.width
		torch2[width_axis] = torch2[width_axis] + tunnel_def.width
		intersectmin, intersectmax = intersect(torch1, torch2, self.chunk_min, self.chunk_max)
		if intersectmin ~= nil then
			local torch_param2
			if length_axis == "z" then
				torch_param2 = 2
			else
				torch_param2 = 4
			end
			self:place_torch(intersectmin, intersectmax,
				length_axis, tunnel_def.torch_spacing, width_axis, 1, c_torch_wall, torch_param2)
		end
	end		
end

-----------------------------------------------------------------------------
-- Trench and liquid

-- also used for putting stairs on top of trench blocks, when param2 is defined
function deep_roads.Context:draw_trench(path1, path2, width_axis, trench_block, displace, param2)
	local data = self.data
	local data_param2 = self.data_param2
	local locked_indices = self.locked_indices
	local area = self.area
	
	local trenchside1 = vector.new(path1)
	local trenchside2 = vector.new(path2)

	trenchside1[width_axis] = trenchside1[width_axis]-displace
	trenchside2[width_axis] = trenchside2[width_axis]-displace
	intersectmin, intersectmax = intersect(trenchside1, trenchside2, self.chunk_min, self.chunk_max)
	if intersectmin ~= nil then
		for pi in area:iterp(intersectmin, intersectmax) do
			if not locked_indices[pi] then
				data[pi] = trench_block
				if param2 ~= nil then
					data_param2[pi] = param2
				end
			end
		end				
	end			
	trenchside1[width_axis] = trenchside1[width_axis]+displace*2 -- move the endpoints back over to the other side of the tunnel
	trenchside2[width_axis] = trenchside2[width_axis]+displace*2
	intersectmin, intersectmax = intersect(trenchside1, trenchside2, self.chunk_min, self.chunk_max)
	if intersectmin ~= nil then
		for pi in area:iterp(intersectmin, intersectmax) do
			if not locked_indices[pi] then
				data[pi] = trench_block
				if param2 ~= nil then
					data_param2[pi] = param2
				end
			end
		end	
	end
end

function deep_roads.Context:draw_liquid(path1, path2, width_axis, tunnel_def)
	local displace = tunnel_def.width
	local trench_block = tunnel_def.trench_block
	local liquid_block = tunnel_def.liquid_block
	local area = self.area
	local data = self.data
	local locked_indices = self.locked_indices

	local liquidside1 = vector.new(path1)
	local liquidside2 = vector.new(path2)
	if trench_block then -- subtract one from the width to account for the space filled by trench wall blocks
		liquidside1[width_axis] = liquidside1[width_axis]-(displace-1)
		liquidside2[width_axis] = liquidside2[width_axis]+(displace-1)
	else
		liquidside1[width_axis] = liquidside1[width_axis]-displace
		liquidside2[width_axis] = liquidside2[width_axis]+displace
	end
	intersectmin, intersectmax = intersect(liquidside1, liquidside2, self.chunk_min, self.chunk_max)
	if intersectmin ~= nil then
		for pi in area:iterp(intersectmin, intersectmax) do
			if not locked_indices[pi] then
				data[pi] = liquid_block
				locked_indices[pi] = true
			end
		end				
	end
end

------------------------------------------------------------------------------------
-- Rail

function deep_roads.Context:draw_rail(path1, path2, length_axis, tunnel_def, rise_dir)
	intersectmin, intersectmax = intersect(path1, path2, self.chunk_min, self.chunk_max)
	if intersectmin ~= nil then
		local powered_rail = tunnel_def.powered_rail
		local area = self.area
		local data = self.data
		local locked_indices = self.locked_indices
		for pi, x, y, z in area:iterp_xyz(intersectmin, intersectmax) do
			if not locked_indices[pi] then
				if powered_rail and (rise_dir ~= nil or ((length_axis == "x" and x % 14 == 0) or (length_axis == "z" and z % 14 == 0))) then
					data[pi] = c_powerrail
				else
					data[pi] = c_rail
				end
				locked_indices[pi] = true
			end
		end
	end
end

-----------------------------------------------------------
-- Stairs

function deep_roads.Context:draw_stairs(path1, path2, width_axis, tunnel_def, distance, rise_dir)
	local displace = tunnel_def.width
	local trench_block = tunnel_def.trench_block
	local stair_block = tunnel_def.stair_block
	local area = self.area
	local data = self.data
	local data_param2 = self.data_param2
	local locked_indices = self.locked_indices
	
	local distance = get_sign(distance)

	local param2
	if rise_dir == distance then
		if width_axis == "x" then
			param2 = 0
		else
			param2 = 1
		end
	else
		if width_axis == "x" then
			param2 = 2
		else
			param2 = 3
		end
	end
	
	local stairside1 = vector.new(path1)
	local stairside2 = vector.new(path2)
	if trench_block then
		stairside1.y = stairside1.y + 1
		stairside2.y = stairside2.y + 1
		self:draw_trench(stairside1, stairside2, width_axis, stair_block, displace, param2)
	else
		stairside1[width_axis] = stairside1[width_axis]-displace
		stairside2[width_axis] = stairside2[width_axis]+displace
		intersectmin, intersectmax = intersect(stairside1, stairside2, self.chunk_min, self.chunk_max)
		if intersectmin ~= nil then
			for pi in area:iterp(intersectmin, intersectmax) do
				if not locked_indices[pi] then
					data[pi] = stair_block
					data_param2[pi] = param2
					locked_indices[pi] = true
				end
			end				
		end
	end
end

--------------------------------------------------------------------------------------
-- Base tunnel drawing code

-- from_dir leaves the wall on that side open
--TODO: all the detail work (wall material, trench material - no need for rail, liquid, torches, etc)
function deep_roads.Context:drawcorner(pos, tunnel_def)
	local displace = tunnel_def.width

	local corner1 = vector.new(pos.x - displace, pos.y, pos.z - displace)
	local corner2 = vector.new(pos.x + displace, pos.y + tunnel_def.height - 1, pos.z + displace)
	
	local overall1 = vector.add(vector.new(corner1), -1)
	local overall2 = vector.add(vector.new(corner2), 1)
	
	intersectmin, intersectmax = intersect(overall1, overall2, self.chunk_min, self.chunk_max)
	if intersectmin == nil then return end
	
	intersectmin, intersectmax = intersect(corner1, corner2, self.chunk_min, self.chunk_max)
	local locked_indices = self.locked_indices
	local data = self.data
	
	if intersectmin ~= nil then
		for pi in self.area:iterp(intersectmin, intersectmax) do
			if not locked_indices[pi] then
				data[pi] = c_air
			end
		end
		
		-- TODO: trenches
	end
	
	local wall_block = tunnel_def.wall_block
	local floor_block = tunnel_def.floor_block
	local ceiling_block = tunnel_def.ceiling_block
	local bridge_block = tunnel_def.bridge_block
	local seal_air_block = tunnel_def.seal_air_block
	local seal_water_block = tunnel_def.seal_water_block
	local seal_lava_block = tunnel_def.seal_lava_block

	--walls, floor, ceiling modifications
	if floor_block or seal_lava_block or seal_water_block then
		self:modify_slab(vector.new(pos.x - displace, pos.y - 1, pos.z - displace),
			vector.new(pos.x + displace, pos.y + 1, pos.z + displace),
			tunnel_def, floor_block, nil, seal_water_block, seal_lava_block)
	end

	if tunnel_def.bridge_block then
		local bridge_width = tunnel_def.bridge_width
		self:modify_slab(vector.new(pos.x - bridge_width, pos.y -1, pos.z - bridge_width),
			vector.new(pos.x + bridge_width, pos.y -1, pos.z + bridge_width),
			tunnel_def, nil, bridge_block, seal_water_block, seal_lava_block)
	end

	if ceiling_block or seal_lava_block or seal_water_block or seal_air_block then
		self:modify_slab(vector.new(pos.x - displace, pos.y + tunnel_def.height, pos.z - displace),
			vector.new(pos.x + displace, pos.y + tunnel_def.height, pos.z + displace),
			tunnel_def, ceiling_block, seal_air_block, seal_water_block, seal_lava_block)
	end
	
	if wall_block or seal_lava_block or seal_water_block or seal_air_block then
		local wall_displace = displace + 1
	
		self:modify_slab(vector.new(pos.x - wall_displace, pos.y, pos.z + wall_displace),
			vector.new(pos.x + wall_displace, pos.y + tunnel_def.height, pos.z + wall_displace),
			tunnel_def, wall_block, seal_air_block, seal_water_block, seal_lava_block)
		self:modify_slab(vector.new(pos.x - wall_displace, pos.y, pos.z - wall_displace),
			vector.new(pos.x + wall_displace, pos.y + tunnel_def.height, pos.z - wall_displace),
			tunnel_def, wall_block, seal_air_block, seal_water_block, seal_lava_block)
		self:modify_slab(vector.new(pos.x + wall_displace, pos.y, pos.z - wall_displace),
			vector.new(pos.x + wall_displace, pos.y + tunnel_def.height, pos.z + wall_displace),
			tunnel_def, wall_block, seal_air_block, seal_water_block, seal_lava_block)
		self:modify_slab(vector.new(pos.x - wall_displace, pos.y, pos.z - wall_displace),
			vector.new(pos.x - wall_displace, pos.y + tunnel_def.height, pos.z + wall_displace),
			tunnel_def, wall_block, seal_air_block, seal_water_block, seal_lava_block)
	end	
end 

-- Draws a horizontal tunnel starting from pos1 and extending distance nodes in the given direction axis.
-- Return the position vector one node *beyond* the dug out area, such that repeated calls would not overlap.
function deep_roads.Context:drawxz(pos1, length_axis, distance, tunnel_def, rise_dir)
	--minetest.debug("Draw XZ params: " .. minetest.pos_to_string(pos1) .. ", " .. direction  .. ", " .. tostring(distance))

	local pos2 = vector.new(pos1)
	pos2[length_axis] = pos2[length_axis] + distance - get_sign(distance)

	local locked_indices = self.locked_indices
	local data = self.data
	local data_param2 = self.data_param2
	local area = self.area
	
	local displace = tunnel_def.width
	local height = tunnel_def.height
	local boost_torch_height = 0
	if rise_dir ~= nil then
		height = height + 1
		if height < 4 and tunnel_def.stair_block ~= nil then
			height = height + 1 -- need some extra head space when there are stairs and a low ceiling
			boost_torch_height = 1
		end
	end

	local tunnel1 = {x = math.min(pos1.x, pos2.x), y = pos1.y, z = math.min(pos1.z, pos2.z)}
	local tunnel2 = {x = math.max(pos1.x, pos2.x), y = pos1.y, z = math.max(pos1.z, pos2.z)}

	-- this is the pair of points that traces the path down the center of the tunnel. Used for drawing a variety of things.
	local path1 = vector.new(tunnel1)
	local path2 = vector.new(tunnel2)
	
	tunnel2.y = tunnel2.y + height-1
	
	local width_axis
	if length_axis == "z" then
		width_axis = "x"
	else
		width_axis = "z"
	end
	tunnel1[width_axis] = tunnel1[width_axis] - displace
	tunnel2[width_axis] = tunnel2[width_axis] + displace
	
	-- includes the wall layers around the tunnel
	local overall1 = vector.new(tunnel1)
	local overall2 = vector.new(tunnel2)

	overall1.y = overall1.y - 1
	overall2.y = overall2.y + 1
	overall1[width_axis] = overall1[width_axis] - 1
	overall2[width_axis] = overall2[width_axis] + 1

	intersectmin, intersectmax = intersect(overall1, overall2, self.chunk_min, self.chunk_max)
	if intersectmin ~= nil then
		intersectmin, intersectmax = intersect(tunnel1, tunnel2, self.chunk_min, self.chunk_max)
		if intersectmin ~= nil then
			--minetest.debug("drawing xz from "..minetest.pos_to_string(pos1) .. " to " .. minetest.pos_to_string(pos2))
		
			-- hollow out the tunnel
			for pi in area:iterp(intersectmin, intersectmax) do
				if not locked_indices[pi] then
					data[pi] = c_air
				end
			end
			
			-- Decorations inside the tunnel itself
			if tunnel_def.rail then
				self:draw_rail(path1, path2, length_axis, tunnel_def, rise_dir)
			end
			
			if rise_dir ~= nil and tunnel_def.stair_block then
				self:draw_stairs(path1, path2, width_axis, tunnel_def, distance, rise_dir)
			end
			
			if tunnel_def.torch_spacing then
				self:draw_torches(path1, path2, width_axis, length_axis, tunnel_def, boost_torch_height)
			end
			
			if tunnel_def.trench_block and displace > 0 then
				self:draw_trench(path1, path2, width_axis, tunnel_def.trench_block, tunnel_def.width)
			end
			
			if tunnel_def.liquid_block and rise_dir == nil then
				self:draw_liquid(path1, path2, width_axis, tunnel_def)
			end
		end
		
		local floor_block = tunnel_def.floor_block
		local seal_lava_material = tunnel_def.seal_lava_material
		local seal_water_material = tunnel_def.seal_water_material
		local seal_air_material = tunnel_def.seal_air_material
		local ceiling_block = tunnel_def.ceiling_block
		local wall_block = tunnel_def.wall_block
		
		if tunnel_def.bridge_block then
			self:draw_bridge(path1, path2, width_axis, length_axis, tunnel_def)
		end
		
		--walls, floor, ceiling modifications
		if floor_block or seal_lava_material or seal_water_material then
			local floor1 = vector.new(path1.x, path1.y-1, path1.z)
			local floor2 = vector.new(path2.x, path2.y-1, path2.z)
			floor1[width_axis] = floor1[width_axis] - displace
			floor2[width_axis] = floor2[width_axis] + displace
	
			self:modify_slab(floor1, floor2, tunnel_def, floor_block, nil, seal_water_material, seal_lava_material)
		end
		
		if ceiling_block or seal_lava_material or seal_water_material or seal_air_material then
			local ceiling1 = vector.new(path1.x, path1.y+height, path1.z)
			local ceiling2 = vector.new(path2.x, path2.y+height, path2.z)
			ceiling1[width_axis] = ceiling1[width_axis] - displace
			ceiling2[width_axis] = ceiling2[width_axis] + displace
			self:modify_slab(ceiling1, ceiling2, tunnel_def, ceiling_block, seal_air_material, seal_water_material, seal_lava_material)
		end
	
		if wall_block or seal_lava_material or seal_water_material or seal_air_material then
			local wall1 = vector.new(path1.x, path1.y, path1.z)
			local wall2 = vector.new(path2.x, path2.y+height-1, path2.z)
			wall1[width_axis] = wall1[width_axis] - (displace+1)
			wall2[width_axis] = wall2[width_axis] - (displace+1)
			self:modify_slab(wall1, wall2, tunnel_def, wall_block, seal_air_material, seal_water_material, seal_lava_material)
			wall1[width_axis] = wall1[width_axis] + 2*displace+2
			wall2[width_axis] = wall2[width_axis] + 2*displace+2
			self:modify_slab(wall1, wall2, tunnel_def, wall_block, seal_air_material, seal_water_material, seal_lava_material)
		end
	end
	
	pos2[length_axis] = pos2[length_axis] + get_sign(distance)
	--minetest.debug("returning " .. minetest.pos_to_string(pos2))
	return pos2
end

local landings_between = function (y1, y2, interval)
	local absy1 = math.abs(y1)
	local absy2 = math.abs(y2)
	
	if get_sign(y1) ~= get_sign(y2) then
		-- The staircase crosses the 0 line. Add the two. Subtract 1 because of the duplicate landing at 0.
		return math.floor(absy1/interval) + math.floor(absy2/interval) - 1
	else
		local maxy = math.max(absy1, absy2)
		local miny = math.min(absy1, absy2)
		-- imagine the stair runs from 20 to 300. find the number of landings between 0 and 300 and subtract the number of landings between 0 and 19.
		return math.floor(maxy/interval) - math.floor((miny-1)/interval)
	end
end

function deep_roads.Context:drawy(pos1, length_axis, distance, rise, tunnel_def)
	--minetest.debug("Draw Y params: " .. minetest.pos_to_string(pos1) .. ", " .. length_axis  .. ", " .. tostring(distance) .. ", " .. tostring(rise))

	local landing_length = tunnel_def.landing_length
	local stair_length = tunnel_def.stair_length
	
	local y_dir = get_sign(rise)
	local landings
	if landing_length > 0 then landings = landings_between(pos1.y, pos1.y+rise, stair_length) else landings = 0 end
	local dir = get_sign(distance)

	local pos2 = vector.new(pos1)
	pos2[length_axis] = pos2[length_axis] + dir*(math.abs(rise) + landings*landing_length)
	pos2.y = pos2.y + rise

	-- get the bounding box for the stair as a whole
	local corner1 = {x = math.min(pos1.x, pos2.x), y = math.min(pos1.y, pos2.y), z = math.min(pos1.z, pos2.z)}
	local corner2 = {x = math.max(pos1.x, pos2.x), y = math.max(pos1.y, pos2.y) + 3, z = math.max(pos1.z, pos2.z)}
	local width_axis
	if length_axis == "z" then
		width_axis = "x"
	else
		width_axis = "z"
	end
	local displace = tunnel_def.width + 1
	corner1[width_axis] = corner1[width_axis] - displace
	corner2[width_axis] = corner2[width_axis] + displace
	corner1.y = corner1.y - 1
	corner2.y = corner2.y + tunnel_def.height
	
	local chunk_min = self.chunk_min
	local chunk_max = self.chunk_max
		
	intersectmin, intersectmax = intersect(corner1, corner2, chunk_min, chunk_max) -- Check bounding box of overall ramp corridor
	if intersectmin ~= nil then
	
		local top_y
		if y_dir < 0 then top_y = pos1.y else top_y = pos2.y end
		
		local counted_landings = 0
		local current_location = vector.new(pos1)
		while current_location.y ~= pos2.y do
			if y_dir < 0 then
				-- going down. move, then draw stairs, then draw landing
				current_location.y = current_location.y + y_dir
				current_location = self:drawxz(current_location, length_axis, dir, tunnel_def, y_dir)
				if landing_length > 0 and current_location.y % stair_length == 0 then
					counted_landings = counted_landings + 1
					current_location = self:drawxz(current_location, length_axis, landing_length*dir, tunnel_def)
				end
			end
			if y_dir > 0 then
				-- going up. draw landing then draw stairs then move
				if landing_length > 0 and current_location.y % stair_length == 0 then
					counted_landings = counted_landings + 1
					current_location = self:drawxz(current_location, length_axis, landing_length*dir, tunnel_def)
				end
				current_location = self:drawxz(current_location, length_axis, dir, tunnel_def, y_dir)
				current_location.y = current_location.y + y_dir
			end
		end
--		if not vector.equals(current_location, pos2) then
--			minetest.debug("Not equal drawy results! current location, predicted location: " .. minetest.pos_to_string(current_location) .. " " .. minetest.pos_to_string(pos2))
--		end
	end

	--minetest.debug("returning " .. minetest.pos_to_string(pos2))
	return pos2
end


---------------------------------------------------------------------------
-- Recursive master tunnel drawing function

local draw_tunnel_segment -- initial declaration to allow recursion
function deep_roads.Context:draw_tunnel_segment(source, destination, tunnel_def, prev_dir)
	--minetest.debug("draw tunnel segment with parameters " .. minetest.pos_to_string(source) .. ", " .. minetest.pos_to_string(destination))

	if vector.equals(source, destination) then return end
	
	local area = self.area
	local data = self.data
	local data_param2 = self.data_param2
	local locked_indices = self.locked_indices
	
	local width = tunnel_def.width

	local diff = vector.subtract(destination, source)
	local dir = vector.new(get_sign(diff.x), get_sign(diff.y), get_sign(diff.z))

	local change_y
	if source.y == destination.y then
		change_y = false
	elseif source.x == destination.x and source.z == destination.z then
		change_y = true -- we're directly over/under our destination, don't want to squiggle around aimlessly so force an elevation change.
	else
		change_y = math.random() > 0.5
	end
	
	local change_axis
	if source.x == destination.x then
		change_axis = "z"
	elseif source.z == destination.z then
		change_axis = "x"
	elseif math.random() > 0.5 then
		change_axis = "x"
	else
		change_axis = "z"
	end
	
	local tunnel_diameter = width*2+1
	
	local next_location = vector.new(source) -- will be used to track our cursor location as we "draw" a tunnel.

	--we may need to jink to the side to avoid retracing previous steps
	if prev_dir then
		local distance = tunnel_diameter*random_sign()
		if change_axis == "x" and ((prev_dir.x < 0 and dir.x > 0) or (prev_dir.x > 0 and dir.x < 0)) then
			next_location = self:drawxz(next_location, "z", distance, tunnel_def)
			if distance_within(destination, next_location, tunnel_diameter+1) then return end
			self:drawcorner(next_location, tunnel_def)
		elseif change_axis == "z" and ((prev_dir.z < 0 and dir.z > 0) or (prev_dir.z > 0 and dir.z < 0)) then
			next_location = self:drawxz(next_location, "x", distance, tunnel_def)
			if distance_within(destination, next_location, tunnel_diameter+1) then return end
			self:drawcorner(next_location, tunnel_def)
		end
	end
	
	if not change_y then
		local dist = math.min(math.random(10, self.gridscale.x), math.abs(diff[change_axis])) * dir[change_axis]
		next_location = self:drawxz(next_location, change_axis, dist, tunnel_def)
		if distance_within(destination, next_location, tunnel_diameter+1) then return end
		self:drawcorner(next_location, tunnel_def)
	else
		-- if we're changing direction first go width nodes in this direction to make the corner nicer.
		local aglet_distance = (width+1)*dir[change_axis]
		next_location = self:drawxz(next_location, change_axis, aglet_distance, tunnel_def)
		if distance_within(destination, next_location, tunnel_diameter+1) then return end
		-- then do the sloped part
		local dist = math.min(math.random(10, self.gridscale.y), math.abs(diff.y)) * dir[change_axis]
		next_location = self:drawy(next_location, change_axis, dist, math.abs(dist)*dir.y, tunnel_def)
		-- then the last bit to make the bottom nicer
		next_location = self:drawxz(next_location, change_axis, aglet_distance, tunnel_def)
		if distance_within(destination, next_location, tunnel_diameter+1) then return end
		self:drawcorner(next_location, tunnel_def)

	end
	prev_dir = vector.subtract(next_location, source)
	self:draw_tunnel_segment(next_location, destination, tunnel_def, prev_dir)
end

function deep_roads.Context:segmentize_connection(connection)
	math.randomseed(connection.val*1000000000)

	self:place_sign_on_ceiling(connection.pt1, "To " .. deep_roads.random_name(connection.pt2.val), 3)
	self:place_sign_on_ceiling(connection.pt2, "To " .. deep_roads.random_name(connection.pt1.val), 3)
	
	self:draw_tunnel_segment(connection.pt1, connection.pt2, connection.def, nil)
end

--------------------------------------------------------------------
-- Signs

function deep_roads.Context:place_sign(pos, name, param2)
	local area = self.area
	local data = self.data
	local data_param2 = self.data_param2
	if area:containsp(pos) then
		local pi = area:indexp(pos)
		if not self.locked_indices[pi] then
			self.locked_indices[pi] = true
			data[pi] = c_wood_sign
			data_param2[pi] = param2
			local meta = minetest.get_meta(pos)
			meta:set_string("formspec","field[text;;${text}]")
			meta:set_string("infotext", '"' .. name .. '"')
			meta:set_string("text", name)
		end
	end
end

function deep_roads.Context:place_sign_on_post(posparam, name)
	local pos = vector.new(posparam)
	local area = self.area
	local data = self.data
	local data_param2 = self.data_param2
	if area:containsp(pos) then
		local pi = area:indexp(pos)
		if not self.locked_indices[pi] then
			self.locked_indices[pi] = true
			data[pi] = c_mese_post
		end
	end
	pos.y = pos.y + 1
	if area:containsp(pos) then
		local pi = area:indexp(pos)
		if not self.locked_indices[pi] then
			self.locked_indices[pi] = true
			data[pi] = c_wood_sign
			data_param2[pi] = 1
			local meta = minetest.get_meta(pos)
			meta:set_string("formspec","field[text;;${text}]")
			meta:set_string("infotext", '"' .. name .. '"')
			meta:set_string("text", name)
		end
	end
end

function deep_roads.Context:place_sign_on_ceiling(posparam, name, height)
	local pos = vector.new(posparam)
	pos.y = pos.y + height
	local area = self.area
	local data = self.data
	local data_param2 = self.data_param2
	if area:containsp(pos) then
		local pi = area:indexp(pos)
		if not self.locked_indices[pi] then
			self.locked_indices[pi] = true
			data[pi] = c_mese_post
		end
	end
	pos.y = pos.y - 1
	if area:containsp(pos) then
		local pi = area:indexp(pos)
		if not self.locked_indices[pi] then
			self.locked_indices[pi] = true
			data[pi] = c_wood_sign
			data_param2[pi] = 0
			local meta = minetest.get_meta(pos)
			meta:set_string("formspec","field[text;;${text}]")
			meta:set_string("infotext", '"' .. name .. '"')
			meta:set_string("text", name)
		end
	end
end

--------------------------------------------------------------------------
-- Intersection

function deep_roads.Context:carve_intersection(point)

	local radius = math.floor(point.val*(point.def.max_radius-point.def.min_radius)+ point.def.min_radius)
	
	local corner1 = {x=point.x - radius, y= point.y, z=point.z - radius}
	local corner2 = {x=point.x + radius, y= point.y+3, z=point.z + radius}
	local chunk_min = self.chunk_min
	local chunk_max = self.chunk_max
	local area = self.area
	local data = self.data
	
	intersectmin, intersectmax = intersect(corner1, corner2, chunk_min, chunk_max)
	if intersectmin ~= nil then
		for pi in area:iterp(intersectmin, intersectmax) do
			data[pi] = c_air
		end
		self:place_sign_on_post(point, "Welcome to " .. deep_roads.random_name(point.val))
	end
end
