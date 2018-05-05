local c_air = minetest.get_content_id("air")
local c_lava = minetest.get_content_id("default:lava_source")
local c_water = minetest.get_content_id("default:water_source")
local c_rail = minetest.get_content_id("carts:rail")
local c_powerrail = minetest.get_content_id("carts:powerrail")
local c_torch_wall = minetest.get_content_id("default:torch_wall")

local nameparts = {}
local file = io.open(minetest.get_modpath(minetest.get_current_modname()).."/nameparts.txt", "r")
if file then
	for line in file:lines() do
		table.insert(nameparts, line)
	end
else
	nameparts = {"Unable to read nameparts.txt"}
end

deep_roads.Context = {}

-- Grid stuff
--------------------------------------------------

local scatter_3d = function(min_xyz, gridscale_xyz, min_output_size, max_output_size)
	local next_seed = math.random(1, 1000000000)
	math.randomseed(min_xyz.x + min_xyz.z * 2 ^ 8 + min_xyz.y * 2 ^ 16)
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


local get_grid_and_adjacent = function(min_xyz, gridscale_xyz, min_output_size, max_output_size, min_y, max_y)
	local result = {}
	
	for x_grid = -1, 1 do
		for y_grid = -1, 1 do
			for z_grid = -1, 1 do
				local grid = vector.multiply(gridscale_xyz, vector.add(min_xyz, {x=x_grid, y=y_grid, z=z_grid}))
				for _, point in pairs(scatter_3d(grid, gridscale_xyz, min_output_size, max_output_size)) do
					if (point.y >= min_y and point.y <= max_y) then
						table.insert(result, point)
					end
				end
			end
		end
	end
	
	return result
end

local road_points_around = function(pos, gridscale_xyz, min_y, max_y)
	local corner = {
		x = math.floor(pos.x / gridscale_xyz.x),
		y = math.floor(pos.y / gridscale_xyz.y),
		z = math.floor(pos.z / gridscale_xyz.z)}
	return get_grid_and_adjacent(corner, gridscale_xyz, 1, 4, min_y, max_y)
end

-- Connection stuff
------------------------------------------------------

local jitterval = 16
local jittervaldiv2 = 8

-- This ensures that all the roads don't converge into a single tunnel as they approach a junction. Makes junctions more interesting.
local jitter_point = function(jitter, point)
	return {x = point.x+jitter.x,
			y = point.y+jitter.y,
			z = point.z+jitter.z,
			val = point.val}
end

local find_connections = function(points, gridscale, odds)
	local connections = {}
	-- Do a triangular array comparison, ensuring that each pair is tested only once.
	for index1 = 1, table.getn(points) do
		for index2 = index1 + 1, table.getn(points) do
			local point1 = points[index1]
			local point2 = points[index2]
			local diff = vector.subtract(point1, point2)
			if math.abs(diff.x) < gridscale.x and math.abs(diff.y) < gridscale.y and math.abs(diff.z) < gridscale.z then -- Ensure no pair under consideration is more than a grid-length away on any axis.
				local combined = (point1.val * 100000 + point2.val * 100000) % 1 -- Combine the two random values and then take the fractional portion to get back to 0-1 range
				if combined < odds then
					local connection_val = combined/odds
					-- This moves the endpoints of the connection around a bit to hopefully make them collide less.
					local jitter = {
						x = math.floor((connection_val * 1000 % 1) * jitterval - jittervaldiv2),
						y = 0,
						z = math.floor((connection_val * 1000000 % 1) * jitterval - jittervaldiv2)
					}
					if point1.x + point1.y + point1.z > point2.x + point2.y + point2.z then -- always sort each pair of points the same way.
						table.insert(connections, {pt1 = jitter_point(jitter, point1), pt2 = jitter_point(jitter, point2), val = connection_val})
					else
						table.insert(connections, {pt1 = jitter_point(jitter, point2), pt2 = jitter_point(jitter, point1), val = connection_val})
					end
				end
			end
		end
	end
	return connections
end

--------------------------------------------------------------------

function deep_roads.Context:new(minp, maxp, area, data, data_param2, gridscale, ymin, ymax, connection_probability)
	context = {}
	setmetatable(context, self)
	self.__index = self
	context.locked_indices = {}
	context.data = data
	context.data_param2 = data_param2
	context.area = area
	context.chunk_min = minp
	context.chunk_max = maxp
	
	context.points = road_points_around(minp, gridscale, ymin, ymax)
	context.connections = find_connections(context.points, gridscale, connection_probability)

	
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

-- Finds an intersection between two AABBs, or nil if there's no overlap
local intersect = function(minpos1, maxpos1, minpos2, maxpos2)
	if minpos1.x <= maxpos2.x and maxpos1.x >= minpos2.x and
		minpos1.y <= maxpos2.y and maxpos1.y >= minpos2.y and
		minpos1.z <= maxpos2.z and maxpos1.z >= minpos2.z then
		
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

function deep_roads.Context:place_every(iterator, axis, intermittency, node, else_node, param2, else_param2)
	local area = self.area
	local data = self.data
	local data_param2 = self.data_param2
	local locked_indices = self.locked_indices
	for pi in iterator do
		if area:position(pi)[axis] % intermittency == 0 then
			data[pi] = node
			if param2 ~= nil then data_param2[pi] = param2 end
		elseif else_node ~= nil then
			data[pi] = else_node
			if else_param2 ~= nil then data_param2[pi] = else_param2 end
		end
		locked_indices[pi] = true
	end
end

function deep_roads.Context:modify_slab(corner1, corner2, tunnel_def, slab_block, seal_air_material, seal_water_material, seal_lava_material)
	intersectmin, intersectmax = intersect(corner1, corner2, self.chunk_min, self.chunk_max)
	local data = self.data
	local locked_indices = self.locked_indices
	
	if intersectmin ~= nil then
		for pi in self.area:iterp(intersectmin, intersectmax) do
			if not locked_indices[pi] then
				if seal_air_material and data[pi] == c_air then
					data[pi] = seal_air_material
				elseif seal_lava_material and data[pi] == c_lava then
					data[pi] = seal_lava_material
				elseif seal_water_material and data[pi] == c_water then
					data[pi] = seal_water_material
				elseif data[pi] ~= c_air then
					data[pi] = slab_block
				end
			end
		end
	end
end

-- from_dir leaves the wall on that side open
function deep_roads.Context:drawcorner(pos, tunnel_def, from_dir)
	local corner1 = vector.new(pos.x - tunnel_def.width, pos.y, pos.z - tunnel_def.width)
	local corner2 = vector.new(pos.x + tunnel_def.width, pos.y + tunnel_def.height - 1, pos.z + tunnel_def.width)
		
	local intersectmin, intersectmax = intersect(corner1, corner2, self.chunk_min, self.chunk_max)
	local locked_indices = self.locked_indices
	local data = self.data
	
	if intersectmin ~= nil then
		for pi in self.area:iterp(intersectmin, intersectmax) do
			if not locked_indices[pi] then
				data[pi] = c_air
			end
		end		
	end
end

-- Draws a horizontal tunnel from pos1 to pos2.
function deep_roads.Context:drawxz(pos1, pos2, tunnel_def)
	local locked_indices = self.locked_indices
	local data = self.data
	local data_param2 = self.data_param2
	local area = self.area
	
	local displace = tunnel_def.width
	local height = tunnel_def.height

	local corner1 = {x = math.min(pos1.x, pos2.x), y = pos1.y, z = math.min(pos1.z, pos2.z)}
	local corner2 = {x = math.max(pos1.x, pos2.x), y = pos1.y, z = math.max(pos1.z, pos2.z)}

	local path1 = vector.new(corner1)
	local path2 = vector.new(corner2)

	corner2.y = corner2.y + height-1

	local length_axis
	local width_axis
	if corner1.x == corner2.x then
		length_axis = "z"
		width_axis = "x"
	else
		length_axis = "x"
		width_axis = "z"
	end
	corner1[width_axis] = corner1[width_axis] - displace
	corner2[width_axis] = corner2[width_axis] + displace
	
	local intersectmin, intersectmax = intersect(corner1, corner2, self.chunk_min, self.chunk_max)
	
	if intersectmin ~= nil then
		--minetest.debug("drawing xz from "..minetest.pos_to_string(pos1) .. " to " .. minetest.pos_to_string(pos2))
	
		for pi in area:iterp(intersectmin, intersectmax) do
			if not locked_indices[pi] then
				data[pi] = c_air
			end
		end
		
		-- Decorations inside the tunnel itself
		if tunnel_def.rail then
			local powered_rail
			if tunnel_def.powered_rail then powered_rail = c_powerrail else powered_rail = c_rail end
			intersectmin, intersectmax = intersect(path1, path2, self.chunk_min, self.chunk_max)
			if intersectmin ~= nil then
				self:place_every(area:iterp(intersectmin, intersectmax),
					length_axis, 14, powered_rail, c_rail, nil, nil)
			end
		end
		
		if tunnel_def.torch_spacing then
			torch1 = vector.new(path1)
			torch2 = vector.new(path2)
			if tunnel_def.torch_arrangement == "1 wall" or tunnel_def.torch_arrangement == "2 wall pairs" then
				torch1.y = torch1.y + tunnel_def.torch_height
				torch2.y = torch2.y + tunnel_def.torch_height
				torch1[width_axis] = torch1[width_axis] + displace
				torch2[width_axis] = torch2[width_axis] + displace
				intersectmin, intersectmax = intersect(torch1, torch2, self.chunk_min, self.chunk_max)
				if intersectmin ~= nil then
					local torch_param2
					if length_axis == "z" then
						torch_param2 = 2
					else
						torch_param2 = 4
					end
					self:place_every(area:iterp(intersectmin, intersectmax),
						length_axis, tunnel_def.torch_spacing, c_torch_wall, nil, torch_param2)
				end
			end		
		end
		
		local trench_block = tunnel_def.trench_block
		local liquid_block = tunnel_def.liquid_block
		
		-- If there's a trench block defined, put it on the sides of the tunnel
		if trench_block and displace > 0 and corner2[length_axis]-corner1[length_axis] > displace*2 then
			local trenchside1 = vector.new(path1)
			local trenchside2 = vector.new(path2)
--			trenchside1[length_axis] = trenchside1[length_axis]+displace -- to ensure trench walls don't overlap in corners
--			trenchside2[length_axis] = trenchside2[length_axis]-displace
			trenchside1[width_axis] = trenchside1[width_axis]-displace
			trenchside2[width_axis] = trenchside2[width_axis]-displace
			intersectmin, intersectmax = intersect(trenchside1, trenchside2, self.chunk_min, self.chunk_max)
			if intersectmin ~= nil then
				for pi in area:iterp(intersectmin, intersectmax) do
					if not locked_indices[pi] then
						data[pi] = trench_block
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
					end
				end	
			end
		end
		if liquid_block then
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
	end
	
	local floor_block = tunnel_def.floor_block
	local seal_lava_material = tunnel_def.seal_lava_material
	local seal_water_material = tunnel_def.seal_water_material
	local seal_air_material = tunnel_def.seal_air_material
	local bridge_block = tunnel_def.bridge_block
	local ceiling_block = tunnel_def.ceiling_block
	local wall_block = tunnel_def.wall_block
	
	--walls, floor, ceiling modifications
	if floor_block or seal_lava_material or seal_water_material then
		local floor1 = vector.new(path1.x, path1.y-1, path1.z)
		local floor2 = vector.new(path2.x, path2.y-1, path2.z)
		floor1[width_axis] = floor1[width_axis] - (displace)
		floor2[width_axis] = floor2[width_axis] + (displace)

		self:modify_slab(floor1, floor2, tunnel_def, floor_block, nil, seal_water_material, seal_lava_material)
	end
	if bridge_block then
		local bridge1 = vector.new(path1.x, path1.y-1, path1.z)
		local bridge2 = vector.new(path2.x, path2.y-1, path2.z)
		bridge1[width_axis] = bridge1[width_axis] - tunnel_def.bridge_width
		bridge2[width_axis] = bridge2[width_axis] + tunnel_def.bridge_width
		intersectmin, intersectmax = intersect(bridge1, bridge2, self.chunk_min, self.chunk_max)
		if intersectmin ~= nil then
			for pi in area:iterp(intersectmin, intersectmax) do
				if data[pi] == c_air then
					data[pi] = bridge_block
					locked_indices[pi] = true
				end
			end
		end
	end
	
	if ceiling_block or seal_lava_material or seal_water_material then
		local ceiling1 = vector.new(path1.x, path1.y+height, path1.z)
		local ceiling2 = vector.new(path2.x, path2.y+height, path2.z)
		ceiling1[width_axis] = ceiling1[width_axis] - (displace)
		ceiling2[width_axis] = ceiling2[width_axis] + (displace)
		self:modify_slab(ceiling1, ceiling2, tunnel_def, ceiling_block, seal_air_material, seal_water_material, seal_lava_material)
	end

	if wall_block or seal_lava_material or seal_water_material then
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

local vertical_power_spacing = 1

--Draw a sloped tunnel from pos1 to pos2. Assumes 45 degree slope and aligned to x or z axis.
function deep_roads.Context:drawy(pos1, pos2, tunnel_def)
	--minetest.debug("drawing y from " .. minetest.pos_to_string(pos1) .. " to " .. minetest.pos_to_string(pos2))
	local corner1 = {x = math.min(pos1.x, pos2.x), y = math.min(pos1.y, pos2.y), z = math.min(pos1.z, pos2.z)}
	local corner2 = {x = math.max(pos1.x, pos2.x), y = math.max(pos1.y, pos2.y) + 3, z = math.max(pos1.z, pos2.z)}
	
	local chunk_min = self.chunk_min
	local chunk_max = self.chunk_max
	local data = self.data
	local area = self.area
	local locked_indices = self.locked_indices
	
	local bridge_block = tunnel_def.bridge_block
	
	local displace = tunnel_def.width
	local height = tunnel_def.height
	local add_rail = tunnel_def.rail
	
	local length_axis
	local width_axis
	if pos1.x == pos2.x then
		--drawing z-direction slope, widen along the x axis
		length_axis = "z"
		width_axis = "x"
	else
		--drawing x-direction slope
		length_axis = "x"
		width_axis = "z"
	end
	corner1[width_axis] = corner1[width_axis] - displace
	corner2[width_axis] = corner2[width_axis] + displace
	
	local intersectmin, intersectmax = intersect(corner1, corner2, chunk_min, chunk_max) -- Check bounding box of overall ramp corridor
	if intersectmin == nil then return end -- There's no way that this can be in the area

	local y_dist = pos2.y - pos1.y
	local y_dir
	if y_dist > 0 then y_dir = 1 else y_dir = -1 end
	local length_dist = pos2[length_axis] - pos1[length_axis]
	local length_dir = get_sign(length_dist)

	local current1 = vector.new(pos1)
	current1[width_axis] = current1[width_axis] - displace
	local current2 = vector.new(pos1)
	current2[width_axis] = current2[width_axis] + displace
	local midpoint = vector.new(pos1)
	
	for i = 0, math.abs(length_dist) do
		current1.y = pos1.y + i * y_dir
		midpoint.y = current1.y
		current2.y = pos1.y + i * y_dir + height -- TODO: omit this +1 for the highest point in the run, that will remove the hole in the ceiling
		current1[length_axis] = pos1[length_axis] + i * length_dir
		current2[length_axis] = current1[length_axis]
		midpoint[length_axis] = current1[length_axis]
		
		intersectmin, intersectmax = intersect(current1, current2, chunk_min, chunk_max)
		if intersectmin ~= nil then
			for pi in area:iterp(intersectmin, intersectmax) do
				if not locked_indices[pi] then
					data[pi] = c_air
				end
			end
			
			if add_rail then
				local railnode = c_rail
				if midpoint.y % vertical_power_spacing == 0 then
					railnode = c_powerrail
				end
			
				if area:containsp(midpoint) then
					pi = area:indexp(midpoint)
					data[pi] = railnode
					locked_indices[pi] = true
				end
			end
			
			if bridge_block then
				intersectmin, intersectmax = intersect(
					vector.new(midpoint.x, midpoint.y-2, midpoint.z),
					vector.new(midpoint.x, midpoint.y-1, midpoint.z),
					chunk_min, chunk_max)
				if intersectmin ~= nil then
					for pi in area:iterp(intersectmin, intersectmax) do
						if data[pi] == c_air then
							data[pi] = bridge_block
							locked_indices[pi] = true
						end
					end
				end
			end
		end
	end
end

function deep_roads.Context:carve_intersection(point, radius)
	local corner1 = {x=point.x - radius, y= point.y, z=point.z - radius}
	local corner2 = {x=point.x + radius, y= point.y+3, z=point.z + radius}
	local chunk_min = self.chunk_min
	local chunk_max = self.chunk_max
	local area = self.area
	local data = self.data
	
	local intersectmin, intersectmax = intersect(corner1, corner2, chunk_min, chunk_max)
	if intersectmin ~= nil then
		for pi in area:iterp(intersectmin, intersectmax) do
			data[pi] = c_air
		end
	end
	

end

local draw_tunnel_segment -- initial declaration to allow recursion
function deep_roads.Context:draw_tunnel_segment(source, destination, tunnel_def, prev_dir)
	if vector.equals(source, destination) then return end
	
	local area = self.area
	local data = self.data
	local data_param2 = self.data_param2
	local locked_indices = self.locked_indices
	
	local width = tunnel_def.width

	local diff = vector.subtract(destination, source)
	local dir_x = get_sign(diff.x)
	local dir_y = get_sign(diff.y)
	local dir_z = get_sign(diff.z)

	local change_y
	if source.y == destination.y then
		change_y = false
	elseif source.x == destination.x and source.z == destination.z then
		change_y = true -- we're directly over/under our destination, don't want to squiggle around aimlessly so force an elevation change.
	else
		change_y = math.random() > 0.5
	end
	
	local change_x
	if source.x == destination.x then
		change_x = false
	elseif source.z == destination.z then
		change_x = true
	else
		change_x = math.random() > 0.5
	end
	
	local next_location

	--we may need to jink to the side to avoid retracing previous steps
	if prev_dir then
		if change_x and ((prev_dir.x < 0 and dir_x > 0) or (prev_dir.x > 0 and dir_x < 0)) then
			next_location = vector.new(source.x, source.y, source.z + (width*2+2)*random_sign())
			self:drawxz(source, next_location, tunnel_def)
			if not vector.equals(destination, next_location) then self:drawcorner(next_location, tunnel_def, nil) end
			source = vector.new(next_location)
		elseif (not change_x) and ((prev_dir.z < 0 and dir_z > 0) or (prev_dir.z > 0 and dir_z < 0)) then
			next_location = vector.new(source.x + (width*2+2)*random_sign(), source.y, source.z)
			self:drawxz(source, next_location, tunnel_def)
			if not vector.equals(destination, next_location) then self:drawcorner(next_location, tunnel_def, nil) end
			source = vector.new(next_location)
		end
	end
	
	if not change_y then
		if change_x then
			local dist = math.min(math.random(10, 1000), math.abs(diff.x)) * dir_x
			next_location = vector.new(source.x+dist, source.y, source.z)
			self:drawxz(source, next_location, tunnel_def)
		else
			local dist = math.min(math.random(10, 1000), math.abs(diff.z)) * dir_z
			next_location = vector.new(source.x, source.y, source.z+dist)
			self:drawxz(source, next_location, tunnel_def)
		end
		if not vector.equals(destination, next_location) then self:drawcorner(next_location, tunnel_def, nil) end
	else
		local slope = tunnel_def.slope
		if change_x then
			if prev_dir and not ((prev_dir.x > 0 and dir_x > 0) or (prev_dir.x < 0 and dir_x < 0)) then
				-- if we're changing direction first go width nodes in this direction to make the corner nicer.
				next_location = vector.new(source.x + width*dir_x, source.y, source.z)
				--drawxz(source, next_location, area, data, data_param2, tunnel_def)
				if not vector.equals(destination, next_location) then self:drawcorner(next_location, tunnel_def, nil) end
				source = vector.new(next_location)
			end
			-- then do the sloped part
			local dist = math.min(math.random(10, 1000), math.abs(diff.y))
			next_location = vector.new(source.x+(dist*dir_x), source.y+(dist*dir_y), source.z)
			self:drawy(source, next_location, tunnel_def)
			source = vector.new(next_location)
			-- then the last bit to make the bottom nicer
			next_location = vector.new(source.x + width*dir_x, source.y, source.z)
			--drawxz(source, next_location, area, data, data_param2, tunnel_def)
			if not vector.equals(destination, next_location) then self:drawcorner(next_location, tunnel_def, nil) end
		else
			if prev_dir and not ((prev_dir.z > 0 and dir_z > 0) or (prev_dir.z < 0 and dir_z < 0)) then
				-- if we're changing direction first go width nodes in this direction to make the corner nicer
				next_location = vector.new(source.x, source.y, source.z + width*dir_z)
				--drawxz(source, next_location, area, data, data_param2, tunnel_def)
				if not vector.equals(destination, next_location) then self:drawcorner(next_location, tunnel_def, nil) end
				source = vector.new(next_location)
			end
			-- then do the sloped part
			local dist = math.min(math.random(10, 1000), math.abs(diff.y))
			next_location = vector.new(source.x, source.y+(dist*dir_y), source.z+(dist*dir_z))
			self:drawy(source, next_location, tunnel_def)
			source = vector.new(next_location)
			-- then the last bit to make the bottom nicer
			next_location = vector.new(source.x, source.y, source.z + width*dir_z)
			--drawxz(source, next_location, area, data, data_param2, tunnel_def)
			if not vector.equals(destination, next_location) then self:drawcorner(next_location, tunnel_def, nil) end
		end
	end
	prev_dir = vector.subtract(next_location, source)
	self:draw_tunnel_segment(next_location, destination, tunnel_def, prev_dir)
end


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
	sign_spacing = nil, -- nil means no signs
	sign_probability = 1, -- allows for erratic sign spacing
	bridge_block = nil, -- if not nil, replaces air in floor
	bridge_width = 0, -- width of bridge (same meaning as "width", so width of 1 gives a bridge 3 wide, and so forth)
	stair_block = nil, -- also used for arches
	floor_block = nil, -- when non-nil, replaces floor with this block type. Does not bridge air gaps.
	wall_block = nil, -- when non-nil, replaces walls with this block type
	ceiling_block = nil, -- when non-nil, replaces ceiling with this block type
	slope = 2,
	seal_lava_material = nil, -- replace lava blocks in walls with this material
	seal_water_material = nil, -- replace water blocks in walls with this material
	seal_air_material = nil, -- patch holes in walls and ceilings with this material. Use bridge material for patching floors.
	width = 1, -- note: this is the number of blocks added on either side of the center block. So width 1 gives a tunnel 3 blocks wide, width 2 gives a tunnel 5 blocks wide, etc.
	height = 3,
	arch_spacing = nil, -- when 1, continuous arch. When 0 or nil, no arch.
}

local set_defaults = function(defaults, target)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = v
		end
	end
end

function deep_roads.Context:segmentize_connection(connection, tunnel_def)

	local next_seed = math.random(1, 1000000000)
	math.randomseed(connection.val*1000000000)
	
	set_defaults(default_tunnel_def, tunnel_def)
	
	self:draw_tunnel_segment(connection.pt1, connection.pt2, tunnel_def, nil)
	
	math.randomseed(next_seed)
end