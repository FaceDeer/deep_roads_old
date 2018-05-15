local CONFIG_FILE_PREFIX = "deep_roads_"

deep_roads.config = {}

local print_settingtypes = false

local function setting(stype, name, default, description)
	local value
	if stype == "bool" then
		value = minetest.setting_getbool(CONFIG_FILE_PREFIX..name)
	elseif stype == "string" then
		value = minetest.setting_get(CONFIG_FILE_PREFIX..name)
	elseif stype == "int" or stype == "float" then
		value = tonumber(minetest.setting_get(CONFIG_FILE_PREFIX..name))
	end
	if value == nil then
		value = default
	end
	deep_roads.config[name] = value
	
	if print_settingtypes then
		minetest.debug(CONFIG_FILE_PREFIX..name.." ("..description..") "..stype.." "..tostring(default))
	end	
end

setting("int", "gridscale_xz", 500, "X/Z grid scale")
setting("int", "gridscale_y", 200, "Y grid scale")

setting("int", "y_min", -2300, "Y minimum")
setting("int", "y_max", -10, "Y maximum")
