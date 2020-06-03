pico-8 cartridge // http://www.pico-8.com
version 27
__lua__
-- wave-f 
-- by lambdanaut
-- wave function collapse generator in pico-8
-- more information: https://github.com/mxgmn/wavefunctioncollapse

-- constants
UP = {0, 1}
LEFT = {-1, 0}
DOWN = {0, -1}
RIGHT = {1, 0}
DIRS = {UP, DOWN, LEFT, RIGHT}

-- globals
LAST_CHECKED_TIME = 0.0
DELTA_TIME = 0.0
FRAME_COUNT = 0

function _init()
  cls()

  dprint("\n\n\n\n\n\n\n\n\n\n")

  output_shape = {0, 0, 24, 24}
  local input_shapes = {
    {0,0,4,4},
    {8,0,4,4},
  }

  local input = parse_input(input_shapes[2])
  parsed_compatibilities = input[1]
  parsed_weights = input[2]

  compatibility_oracle = make_compatibility_oracle(parsed_compatibilities)
  model = make_model(output_shape, parsed_weights, compatibility_oracle)

end

function _update()
  FRAME_COUNT += 1
  -- print("frame: " .. FRAME_COUNT)

  local t = time()
  DELTA_TIME = t - LAST_CHECKED_TIME
  LAST_CHECKED_TIME = t

  model:update()
end

function _draw()
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

function make_wavefunction(size, weights)
  -- size: a 2-tuple of (width, height)
  -- weights: a dict of tile -> weight of tile

  local f = {}
  f.weights = weights

  -- create 128x128 array of boolean `coefficients`  
  -- {{{color1: true, color2: false, color3: true, color4: false... }, { }, {} ...}}
  local coefficients = {}
  for y=1,size[4] do
    local coefficients_row = {}
    for x=1,size[3] do 
      add(coefficients_row, {})
      for tile, _ in pairs(weights) do
        coefficients_row[x][tile] = true
      end
    end
    add(coefficients, coefficients_row)
  end
  f.coefficients = coefficients

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

    local tile_options = self:get(p)
    local valid_weights = {}
    local total_weights = 0
    for tile, weight in pairs(self.weights) do
      if val_in(tile, keys(tile_options)) then
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

function make_model(output_size, weights, compatibility_oracle)
  local m = {}

  dprint("Initializing model id-" .. flr(rnd()*10000) .. " \n========================")
  m.output_size = output_size
  m.compatibility_oracle = compatibility_oracle
  m.wavefunction = make_wavefunction(output_size, weights)
  m.iteration = 0

  m.update = function(self)
    if not self.wavefunction:is_fully_collapsed() then
      self:iterate()
    end
  end

  m.iterate = function(self)
    self.iteration += 1
    -- 1. Find the coordinates of minimum entropy
    local p = self:min_entropy_point()
    dprint("Iteration: " .. self.iteration)
    dprint(p)

    -- 2. Collapse the wavefunction at these co-ordinates
    self.wavefunction:collapse(p)

    -- 3. Propagate the consequences of this collapse
    self:propagate(p)
  end

  m.draw = function(self)
    for y = 1, self.output_size[4] do
      for x = 1, self.output_size[3] do
        local colors = self.wavefunction:get_true_tiles({x, y})
        local choice = colors[flr(rnd(#colors)) + 1]
        pset(x - 1, y - 1, choice)
      end
    end

  end

  m.propagate = function(self, p)

    -- Propagates the consequences of the wavefunction at `p`
    -- collapsing. If the wavefunction at {x,y} collapses to a fixed tile,
    -- then some tiles may not longer be theoretically possible at
    -- surrounding locations.

    -- This method keeps propagating the consequences of the consequences,
    -- and so on until no consequences remain.

    local stack = {p}

    while count(stack) > 0 do
      local cur_p = pop(stack)

      -- Get the set of all possible tiles at the current location
      local cur_possible_tiles = self.wavefunction:get_true_tiles(cur_p)

      -- Iterate through each location immediately adjacent to the current location.
      for d in all(valid_dirs(cur_p, self.output_size)) do
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

  m.min_entropy_point = function(self)
    -- Returns the point of the location whose wavefunction has the lowest entropy
    local min_entropy
    local min_entropy_p

    for y = 1, self.output_size[4] do
      for x = 1, self.output_size[3] do
        if count_table(self.wavefunction:get({x,y})) ~= 1 then
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

  return m
end

function valid_dirs(p, rect, offset)
  -- returns valid directions from a point within a rect.
  -- keeps point in bounds.
  if not offset then offset = 0 end

  dirs = {}

  if p[1] > rect[1] + 1 - offset then add(dirs, LEFT) end
  if p[1] < rect[1] + rect[3] then add(dirs, RIGHT) end
  if p[2] > rect[2] + 1 - offset then add(dirs, DOWN) end
  if p[2] < rect[2] + rect[4] then add(dirs, UP) end

  return dirs
end

function parse_input(sprite_rect)
  -- returns 2 tables: {compatibilities, weights}

  local compatibilities = {}  -- set of all compatibilites of form: {from_tile, to_tile, direction}
  local weights = {}  -- counts of each color used: {tile: count}

  -- get 2d matrix of input colors
  local matrix = {}
  for y=sprite_rect[2], sprite_rect[2] + sprite_rect[4] do
    add(matrix, {})
    for x=sprite_rect[1], sprite_rect[1] + sprite_rect[3] do
      cur_tile = sget(x, y)

      if not key_in(cur_tile, weights) then
        weights[cur_tile] = 0
      end
      weights[cur_tile] += 1

      for d in all(valid_dirs({x, y}, sprite_rect, 1)) do
        local other_tile = sget(x+d[1], y+d[2])
        local compatibility = {cur_tile, other_tile, d}
        if not val_in(compatibility, compatibilities) then
          add(compatibilities, compatibility)
        end
      end

    end
  end

  return {compatibilities, weights}
end


-- helper functions 
function keys(table)
  -- returns keys of a table
  local keyset={}
  local n=0

  for k, v in pairs(table) do
    n=n+1
    keyset[n]=k
  end
  return keyset
end

function key_in(key, table)
  for k, _ in pairs(table) do
    if k == key then return true end
  end
end

function count_table(table)
  local c = 0
  for _, _ in pairs(table) do
    c += 1
  end
  return c
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
function dprint(...)
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
333fc000333fc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
33fcc00033fcc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3fccc0003fccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
fcccc000fcccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ccccc000ccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
