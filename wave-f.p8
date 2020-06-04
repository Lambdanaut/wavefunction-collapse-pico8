pico-8 cartridge // http://www.pico-8.com
version 27
__lua__
-- wave-f 
-- by lambdanaut
-- wave function collapse generator in pico-8
-- more information: https://github.com/mxgmn/wavefunctioncollapse


-- Notes
-- Validated:
-- * valid_dirs() when used in parse_input()
-- * weight parsing
-- * parsed_compatibilities
-- * coefficients creation
-- * pop function
-- To Validate:
-- * min_entropy_point
-- * collapse
-- * propagate

-- constants
UP = {0, -1}
LEFT = {-1, 0}
DOWN = {0, 1}
RIGHT = {1, 0}
DIRS = {UP, DOWN, LEFT, RIGHT}

-- globals
LAST_CHECKED_TIME = 0.0
DELTA_TIME = 0.0
RUNTHROUGH_COUNT = 1


function _init()
  printd("\n\n\n\n\n\n\n\n\n\n")

  output_shape = {0, 0, 32, 32}
  local input_shapes = {
    {0,0,7,7},
    {8,0,7,7},
    {16,0,7,7},
  }
  input_shape = input_shapes[2]



  local patterns = collect_patterns()
  local model_inputs = parse_patterns(patterns)
  parsed_compatibilities = model_inputs[1]
  parsed_weights = model_inputs[2]

  compatibility_oracle = make_compatibility_oracle(parsed_compatibilities)
  model = make_model(parsed_weights, compatibility_oracle)

end

function _update()
  local t = time()
  DELTA_TIME = t - LAST_CHECKED_TIME
  LAST_CHECKED_TIME = t

  model:update()

  if btnp(4) then
    model:reset()
    RUNTHROUGH_COUNT += 1
  end
end

function _draw()
  cls()

  model:draw()
end

function make_compatibility_oracle(compatibilities)
  local o = {}

  o.compatibilities = compatibilities

  o.check = function(self, tile1, tile2, dir)
    return val_in({tile1, tile2, dir}, self.compatibilities)
  end

  return o
end

function make_model(weights, compatibility_oracle)
  local m = {}

  printd("Initializing model id-" .. flr(rnd()*10000) .. " \n========================")
  m.compatibility_oracle = compatibility_oracle
  m.wavefunction = make_wavefunction(weights)
  m.iteration = 0

  m.update = function(self)
    if not self.wavefunction:is_fully_collapsed() then
      self:iterate()
    end
  end

  m.iterate = function(self)
    self.iteration += 1
    printd("Iteration: " .. self.iteration)

    -- 1. Find the coordinates of minimum entropy
    local p = self:min_entropy_point()
    printd(p)

    -- 2. Collapse the wavefunction at these co-ordinates
    self.wavefunction:collapse(p)

    -- 3. Propagate the consequences of this collapse
    self:propagate(p)
  end

  m.reset = function(self)
    self.wavefunction:initialize_coefficients()
    self.iteration = 0
  end

  m.min_entropy_point = function(self)
    -- Returns the point of the location whose wavefunction has the lowest entropy
    local min_entropy
    local min_entropy_p

    for y = 1, output_shape[4] do
      for x = 1, output_shape[3] do
        if #self.wavefunction:get_true_tiles({x,y}) ~= 1 then
          local entropy = self.wavefunction:entropy_f({x, y})

          -- Add some noise to mix things up a little
          local entropy_plus_noise = entropy - (rnd() / 1000)
          if not min_entropy or entropy_plus_noise < min_entropy then
            min_entropy = entropy_plus_noise
            min_entropy_p = {x, y}
          end

        end
      end
    end

    return min_entropy_p
  end

  m.propagate = function(self, p)

    -- Propagates the consequences of the wavefunction at `p`
    -- collapsing. If the wavefunction at {x,y} collapses to a fixed tile,
    -- then some tiles may no longer be theoretically possible at
    -- surrounding locations.

    -- This method keeps propagating the consequences of the consequences,
    -- and so on until no consequences remain.

    local stack = {p}

    while count(stack) > 0 do
      local cur_p = pop(stack)

      -- Get the set of all possible tiles at the current location
      local cur_possible_tiles = self.wavefunction:get_true_tiles(cur_p)

      -- Iterate through each location immediately adjacent to the current location.
      for d in all(valid_dirs(cur_p, output_shape)) do
        local other_p = {cur_p[1] + d[1], cur_p[2] + d[2]}

        -- Iterate through each possible tile in the adjacent location's wavefunction.
        for other_tile in all(self.wavefunction:get_true_tiles(other_p)) do
          -- Check whether the tile is compatible with any tile in
          -- the current location's wavefunction.
          local other_tile_is_possible
          for cur_tile in all(cur_possible_tiles) do
            if self.compatibility_oracle:check(cur_tile, other_tile, d) then
              other_tile_is_possible = true
              break
            end
          end

          -- If the tile is not compatible with any of the tiles in
          -- the current location's wavefunction then it is impossible
          -- for it to ever get chosen. We therefore remove it from
          -- the other location's wavefunction.
          if not other_tile_is_possible then
            self.wavefunction:set(other_p, other_tile, false)
            add(stack, other_p)
          end
        end
      end
    end
  end

  m.draw = function(self)
    -- draw output shape
    rectfill(0, 0, output_shape[3] + 1, output_shape[4] + 1, 7)
    for y = 1, output_shape[4] do
      for x = 1, output_shape[3] do
        local colors = self.wavefunction:get_true_tiles({x, y})
        local choice = colors[flr(rnd(#colors)) + 1]
        if #colors == 0 then choice = 4 end
        pset(x, y, choice)
      end
    end
    print("output texture", 0, output_shape[4] + 8, 7)

    -- draw input shape
    rectfill(127, 0, 127 - input_shape[3] - 2, input_shape[4] + 2, 7)
    spr(input_shape[1]/8, 127 - input_shape[3] - 1, 1)
    print("input texture", 76, input_shape[4] + 8, 7)

    -- draw information
    print("wavefunction collapse", 0, 100)
    print("iteration: " .. RUNTHROUGH_COUNT, 0, 110)
    print("frame: " .. self.iteration, 0, 120)
  end

  return m
end

function make_wavefunction(weights)
  -- size: a 2-tuple of (width, height)
  -- weights: a dict of tile -> weight of tile

  local f = {}
  f.weights = weights

  f.initialize_coefficients = function(self)
    -- create 128x128 array of boolean `coefficients`  
    -- {{{color1: true, color2: false, color3: true, color4: false... }, { }, {} ...}}
    local coefficients = {}
    for y=1, output_shape[4] do
      local coefficients_row = {}
      for x=1, output_shape[3] do
        add(coefficients_row, {})
        for tile, _ in pairs(weights) do
          coefficients_row[x][tile] = true
        end
      end
      add(coefficients, coefficients_row)
    end
    self.coefficients = coefficients
  end
  f.initialize_coefficients(f)

  f.get = function(self, p)
    return self.coefficients[p[2]][p[1]]
  end

  f.get_true_tiles = function(self, p)
    local true_tiles = {}
    for tile, coefficient in pairs(self:get(p)) do
      if coefficient then
        add(true_tiles, tile)
      end
    end
    return true_tiles
  end

  f.set = function(self, p, k, v)
    -- sets a coefficient at point `p` of color/tile value `k` equal to the boolean `v`
    self.coefficients[p[2]][p[1]][k] = v
  end

  f.entropy_f = function(self, p)
    local sum_of_weights = 0
    local sum_of_weight_log_weights = 0
    for tile_option in all(self:get_true_tiles(p)) do
      local weight = self.weights[tile_option]
      sum_of_weights += weight
      sum_of_weight_log_weights += weight * log(weight)
    end

    return log(sum_of_weights) - (sum_of_weight_log_weights / sum_of_weights)
  end

  f.is_fully_collapsed = function(self)
    -- Returns true if every element in Wavefunction is fully collapsed, and false otherwise
    for y, row in pairs(self.coefficients) do
      for x, coefficients in pairs(row) do
        local count = 0
        for _, coefficient in pairs(coefficients) do
          if coefficient then count += 1 end
          if count > 1 then
            return false
          end
        end
      end
    end

    return true
  end

  f.collapse = function(self, p)
    -- Collapses the wavefunction at `p` to a single, definite tile.
    -- The tile is chosen randomly from the remaining possible tiles at `p`, 
    -- weighted according to the Wavefunction's `weights`.

    -- This method mutates the Wavefunction, and does not return anything.

    local tile_options = self:get_true_tiles(p)
    local valid_weights = {}
    local total_weights = 0
    for tile, weight in pairs(self.weights) do
      if val_in(tile, tile_options) then
        valid_weights[tile] = weight
        total_weights += weight
      end
    end

    local randval = rnd() * total_weights

    local chosen
    for tile, weight in pairs(valid_weights) do
      randval -= weight
      if randval < 0 then
        chosen = tile
        break
      end
    end

    for tile_option, coefficient in pairs(self:get(p)) do
      self:set(p, tile_option, false)
    end

    self:set(p, chosen, true)
  end

  return f
end

function valid_dirs(p, rect, offset)
  -- returns valid directions from a point within a rect.
  -- keeps point in bounds.
  if not offset then offset = 0 end

  dirs = {}

  if p[1] > rect[1] + 1 - offset then add(dirs, LEFT) end
  if p[1] < rect[1] + rect[3] then add(dirs, RIGHT) end
  if p[2] > rect[2] + 1 - offset then add(dirs, UP) end
  if p[2] < rect[2] + rect[4] then add(dirs, DOWN) end

  return dirs
end

function parse_patterns(patterns)
  -- returns 2 tables: {compatibilities, weights}

  local compatibilities = {}  -- set of all compatibilites of form: {from_tile, to_tile, direction}
  local weights = {}  -- counts of each color used: {tile: count}

  -- take off the x/y components of the input_shape for the valid_dirs function call
  local adjusted_input_shape = {0, 0, input_shape[3], input_shape[4]}

  for pattern in all(patterns) do
    for y=1, input_shape[4] do
      for x=1, input_shape[3] do
        local cur_tile = pattern[y][x]

        if not key_in(cur_tile, weights) then
          weights[cur_tile] = 0
        end
        weights[cur_tile] += 1

        for d in all(valid_dirs({x, y}, adjusted_input_shape)) do
          local other_tile = pattern[y+d[2]][x+d[1]]
          local compatibility = {cur_tile, other_tile, d}
          if not val_in(compatibility, compatibilities) then
            add(compatibilities, compatibility)
          end
        end
      end
    end
  end

  printd(compatibilities)
  return {compatibilities, weights}
end

function pattern_from_sample()
  -- get 2d matrix of input colors from spritesheet
  local pattern = {}
  local list_y = 1
  for y=input_shape[2], input_shape[2] + input_shape[4] do
    add(pattern, {})
    for x=input_shape[1], input_shape[1] + input_shape[3] do
      add(pattern[list_y], sget(x, y))
    end
    list_y += 1
  end
  return pattern
end

function collect_patterns()
  local patterns = {}
  local p1 = pattern_from_sample(input_shape)

  add(patterns, p1)
  return patterns
end

-- helper functions 
function key_in(key, table)
  for k, _ in pairs(table) do
    if k == key then return true end
  end
end

function val_in(val, table)
  if type(val) == "table" then
    for _, v in pairs(table) do
      local return_true = true
      for i, v2 in pairs(v) do
        if val[i] ~= v2 then 
          return_true = false
          break
        end
      end
      if return_true then return true end
    end
  else
    for _, v in pairs(table) do
      if v == val then return true end
    end
  end
end

function sum(table)
  local result = 0
  for v in all(table) do
    result += v
  end
  return result
end

log10_table = {
  0, 0.3, 0.475,
  0.6, 0.7, 0.775,
  0.8375, 0.9, 0.95, 1
}
function log(n)
  if (n < 1) return nil
  local e = 0
  while n > 10 do
    n /= 10
    e += 1
  end
  return (log10_table[flr(n)] + e) * 2.302581787109375
end

function pop(table)
  local v = table[#table]
  table[#table] = nil
  return v
end

function tstr(t, indent)
 indent = indent or 0
 local indentstr = ''
 for i=0,indent do
  indentstr = indentstr .. ' '
 end
 local str = ''
 for k, v in pairs(t) do
  if type(v) == 'table' then
   str = str .. indentstr .. k .. '\n' .. tstr(v, indent + 1) .. '\n'
  else
   str = str .. indentstr .. tostr(k) .. ': ' .. tostr(v) .. '\n'
  end
 end
  str = sub(str, 1, -2)
 return str
end
function printd(...)
 printh("\n")
 for v in all{...} do
  if type(v) == "table" then
   printh(tstr(v))
  elseif type(v) == "nil" then
    printh("nil")
  else
   printh(v)
  end
 end
end


__gfx__
cc333999333333333333333333333333333333330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c3999999333333333333333333333333333333330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c399999933ff333333ff333333ff333333ff33330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c39999993fccf3333fccf3333fccf3333fccf3330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cc333999fccccf3ffccccf3ffccccf3ffccccf3f0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c3999999ccccccfcccccccfcccccccfcccccccfc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c3999999cccccccccccccccccccccccccccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
c3999999cccccccccccccccccccccccccccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
