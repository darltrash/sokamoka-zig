#!/usr/bin/env lua

local status, json = pcall(require, "dkjson")
if not status then
    error("'dkjson' is not installed!\ntry:   sudo luarocks install dkjson")
end

local function readFile(name)
    local file = io.open(name, "rb")
    local data = file:read("*a")
    file:close()

    return data
end

local function writeFile(name, contents)
    local file = io.open(name, "w+")
    file:write(contents)
    file:close()
end

local function hex(hex, a)
    hex = hex:gsub("#","")
    return {
        r = tonumber("0x"..hex:sub(1,2))/255,
        g = tonumber("0x"..hex:sub(3,4))/255,
        b = tonumber("0x"..hex:sub(5,6))/255,
        a = (a or 255)/255
    }
end

local function copy(tab, ...)
    for k, v in ipairs({...}) do
        table.insert(tab, v)
    end
end

for line in io.popen("find assets/*.ldtk"):lines() do
    print("> Compiling '"..line.."'")
    local data = json.decode(readFile(line))

    local world = {}
    local world_data = {
        tilesets = {}
    }

    for _, tileset in ipairs(data.defs.tilesets) do
        world_data.tilesets[tileset.uid] = tileset
    end

    for _, raw_level in ipairs(data.levels) do
        local level = {
            bg = hex(raw_level.__bgColor),
            width  = raw_level.pxWid,
            height = raw_level.pxHei,
            tiledata = {
                vertices = {},
                indices = {},
                amount = 0
            },
            
            entities = {}
        }

        local tiles = {}
        for _, layer in ipairs(raw_level.layerInstances) do
            if layer.__type == "Tiles" then
                for k, tile in ipairs(layer.gridTiles) do
                    table.insert(tiles, {
                        x = tile.px[1],
                        y = tile.px[2],
                        sx = tile.src[1],
                        sy = tile.src[2],

                        tileset = world_data.tilesets[layer.__tilesetDefUid],
                        grid_size = layer.__gridSize
                    })
                end

            elseif layer.__type == "Entities" then
                for _, ent in ipairs(layer.entityInstances) do
                    local fields = {}
                    local c

                    for _, field in ipairs(ent.fieldInstances) do
                        fields[field.__identifier] = field.__value
                        c = true
                    end

                    if not c then 
                        fields._nothing_ = true
                    end

                    table.insert(level.entities, {
                        --[ent.__identifier] = {
                        position = {
                            x = ent.px[1],
                            y = ent.px[2],
                            z = 0
                        },
                        collider = {
                            x = 0, y = 0, 
                            w = ent.width, h = ent.height
                        },
                        extra = fields
                        --}
                    })
                end

            end
        end

        local tileset = { pxWid = 8, pxHei = 8 }
        local grid_size = 8
        for k, item in ipairs(tiles) do
            tileset = item.tileset or tileset
            grid_size = item.grid_size or grid_size

            local x, y = item.x, item.y

            local sx = item.sx / tileset.pxWid;
            local sy = item.sy / tileset.pxHei;
            local sw = sx + (grid_size / tileset.pxWid);
            local sh = sy + (grid_size / tileset.pxHei);

            local g = grid_size
            copy(level.tiledata.vertices, 
                x+g, y+g, 1, sw, sh,
                x+g, y,   1, sw, sy,
                x,   y,   1, sx, sy,
                x,   y+g, 1, sx, sh
            )

            local e = (k-1)*4;
            copy(level.tiledata.indices,
                e, e+1, e+2, e, e+2, e+3
            )
            level.tiledata.amount = k
        end

        table.insert(world, level)
    end

    writeFile(line..".map", json.encode(world))
end