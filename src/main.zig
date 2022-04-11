const std   = @import("std");
const json  = std.json;

const sa    = @import("sokol").audio;
const sg    = @import("sokol").gfx;
const st    = @import("sokol").time;
const stxt  = @import("sokol").debugtext;
const sapp  = @import("sokol").app;
const sgapp = @import("sokol").app_gfx_glue;

const znt   = @import("znt");
const shd   = @import("shaders/main.glsl.zig");
const zl    = @import("math.zig");
const as    = @import("assets.zig");


var delta: f64 = 0;
var last:  u64 = 0;
var time:  u64 = 0;

const timestep: f64 = 0.033333333;
var lag: f64 = 0.033333333;

var audio_delta: f64 = 0;
var audio_last:  u64 = 0;


pub const TileData = struct {
    amount: u32,
    vertices: []f32,
    indices:  []u16
};

pub const ProtoLevel = struct {
    bg: struct { 
        r: f32, 
        g: f32, 
        b: f32, 
        a: f32
    },
    width: u32, height: u32,
    
    tiledata: TileData,
    entities: []Entity
};

pub const EntityArrayList = std.ArrayList(Entity);

pub const Level = struct {
    width: u32, height: u32,
    tiledata: TileData,
    entities: EntityArrayList,
    speakers: std.ArrayList(Speaker)
};

pub const Speaker = struct {
    sound: *as.Sound,
    position: zl.Vec3,
    area: f32 = 10,
    volume: f32 = 1,
    loops: bool = true,
    generation: u16 = 1
};

pub const Sprite = struct {
    sx: u16  = 0, sy: u16  = 0, 
    sw: u8   = 8, sh: u8   = 8, 
    x:  f32  = 0, y:  f32  = 0,
    w:  f32  = 8, h:  f32  = 8,
    scx: f32 = 1, scy: f32 = 1
};

const Texture = struct {
    texture: sg.Image,
    origin:  as.Texture
};

pub const Tile = struct {
    x: u16,  y: u16, z: u16 = 0,
    sx: u16, sy: u16
};

pub const Collider = struct {
    x: f32 = 0, y: f32 = 0, 
    w: f32, h: f32, 

    fn applyOffset(self: Collider, off: zl.Vec3) Collider {
        return Collider {
            .x = self.x + off.x, .y = self.y + off.y,
            .w = self.w, .h = self.h
        };
    }

    fn collidingWith(self: Collider, b: Collider) bool {
        return 
        self.x < b.x + b.w and
        self.x + self.w > b.x and
        self.y < b.y + b.h and
        self.y + self.h > b.y;
    }
};

pub const EntityTypes = enum {
    IGNORE, Player, SpeakerEnt
};

pub const Entity = struct {
    generation: u16 = 1,
    visible:  bool = true,
    active:   bool = true,
    hasMass:  bool = false,

    position: zl.Vec3  = .{ .x = 0, .y = 0, .z = 0 },
    lerped_position: zl.Vec3  = .{ .x = 0, .y = 0, .z = 0 },
    velocity: ?zl.Vec3 = null,
    collider: ?Collider = null,

    sprite: ?Sprite = null,

    extra: union(EntityTypes) {
        IGNORE: struct { 
            _nothing_: bool = true
        },
        Player: struct {
            can_move: bool = true,
            animation: f64 = 0,
            flip: f32 = 1,
            acceleration: f32 = 1.5,
            moving: bool = false
        },
        SpeakerEnt: struct {
            source: []const u8 = undefined,
            area: f32 = 10,
            volume: f32 = 1,
            loops: bool = true
        }
    } = .{ .IGNORE = .{} },

    pub fn init(self: *Entity) !void {
        switch (self.extra) {
            else => return,
            .Player => {
                self.velocity = zl.Vec3{ .x = 0, .y = 0, .z = 0 };

                self.collider = Collider {
                    .x = 4, .y = 0, .w = 8, .h = 16
                };

                self.sprite = Sprite {
                    .sx = 6*8, .sy = 0,
                    .sw = 16,  .sh = 16,
                    .x  = 0,   .y  = 0,
                    .w  = 16,  .h  = 16
                };
            },
            .SpeakerEnt => |*e| {
                try state.map[state.level].speakers.append(Speaker {
                    .sound = undefined,
                    .position = self.position,
                    .area = e.area,
                    .volume = e.volume,
                    .loops = e.loops
                });
                self.active = false;
                self.collider = null;
            }
        }
    }

    pub fn process(self: *Entity) !void {
        self.lerped_position = self.position;
        switch (self.extra) {
            else => {},
            .Player => |*extra| {
                var vel = zl.Vec3.zero();

                if (extra.can_move) {
                    if (state.keys.left) {
                        vel.x -= extra.acceleration;
                        extra.flip = -1;
                    }

                    if (state.keys.right) {
                        vel.x += extra.acceleration;
                        extra.flip = 1;
                    }

                    if (state.keys.up) 
                        vel.y -= extra.acceleration;
                    

                    if (state.keys.down)
                        vel.y += extra.acceleration;
                }

                self.sprite.?.scx = zl.lerp(self.sprite.?.scx, extra.flip, 
                    @floatCast(f32, timestep*12*extra.acceleration));

                var moving = (vel.x != 0 or vel.y != 0);
                if (moving and !extra.moving) {
                    extra.animation = 1;
                }

                if (moving) {
                    extra.animation += 4;
                    extra.acceleration = std.math.min(extra.acceleration + @floatCast(f32, timestep*2), 2.3);

                } else {
                    extra.animation = 0;
                    extra.acceleration = 1.5;

                }
                extra.moving = moving;

                self.velocity = self.velocity.?.linear(vel, @floatCast(f32, timestep*8));

                self.sprite.?.sy = @floatToInt(u16, @mod(extra.animation, 4))*16;

                state.target_camera.x = @round(self.position.x+8);
                state.target_camera.y = @round(self.position.y+8);
            }
        } 
        
        if (self.velocity != null) {
            var collisions = try state.space.getColliders(self.*);
            var expected = self.position.add(self.velocity.?.mul(@floatCast(f32, timestep*32)));

            if (collisions != null) {                 
                var intersections: usize = 0;
                for (collisions.?) | item | {
                    var object: ?Entity = null;
                    for (state.map[state.level].entities.items) | ent | {
                        if (ent.generation == item) {
                            object = ent;
                            break;
                        }
                    }
                    if (object == null) {
                        _ = state.map[state.level].entities.orderedRemove(@intCast(usize, item));
                        continue;
                    }

                    var a = self.collider.?.applyOffset(expected);
                    var b = object.?.collider.?.applyOffset(object.?.position);
                    if (a.collidingWith(b)) 
                        intersections += 1;
                }
                try state.print(expected.add(.{ .y = 4 }), "{}", .{intersections});
            } 

            self.position = expected;           
        }
    }

    pub fn draw(self: *Entity) !void {
        // https://www.youtube.com/watch?v=0m4tQgALw34

        var alpha = @floatCast(f32, std.math.clamp(lag / timestep, 0.0, 1.0));
        self.lerped_position = self.lerped_position.linear(self.position, alpha);

        // debug bullshintah.
        if (self.collider != null) {
            try state.addSprite(.{
                .x = self.lerped_position.x + self.collider.?.x,
                .y = self.lerped_position.y + self.collider.?.y,
                .sx = 54, .sy = 42,
                .sw = 1, .sh = 1,
                .w = self.collider.?.w, 
                .h = self.collider.?.h
            });
        
            try state.print(.{
                .x = self.lerped_position.x + self.collider.?.x+1,
                .y = self.lerped_position.y + self.collider.?.y+1,
            }, "{}", .{self.generation});
        }

        if (self.sprite != null) {
            var sprite = self.sprite.?;
            sprite.x += self.lerped_position.x;
            sprite.y += self.lerped_position.y;
        }
        //try state.addSprite(sprite);
    }
};

fn divCeil(a: u32, b: u32) u32 {
    return @floatToInt(u32, 
        @ceil(@intToFloat(f32, a) / @intToFloat(f32, b))
    );
}

pub const Space = struct {
    const EntityType = u16;
    const ListType = std.ArrayList(EntityType);
    const HashType = std.AutoHashMap(EntityType, bool);

    grid: []?ListType,
    cell_size: u32,
    w: u32, h: u32,
    alloc: std.mem.Allocator,

    pub fn init(w: u32, h: u32, s: u32, alloc: std.mem.Allocator) !Space {
        var wr = divCeil(w, s)+1;
        var hr = divCeil(h, s)+1;
        var grid = try alloc.alloc(?ListType, @intCast(usize, wr*hr));

        return Space {
            .w = wr-1, 
            .h = hr-1, 
            .cell_size = s,
            .grid = grid, 
            .alloc = alloc
        };
    }

    fn toHash(self: *Space, position: zl.Vec3) callconv(.Inline) usize {
        var g = @intToFloat(f32, self.cell_size);
        var x = @floatToInt(usize, @floor(position.x/g));
        var y = @floatToInt(usize, @floor(position.y/g));

        return y * self.w + x;
    }

    fn getCell(self: *Space, position: zl.Vec3) callconv(.Inline) *ListType {
        var hash = self.toHash(position);
        self.grid[hash] = self.grid[hash] orelse ListType.init(self.alloc);

        return &self.grid[hash].?;
    }

    fn remFromCell(self: *Space, position: zl.Vec3, id: EntityType) void {
        var cell = self.getCell(position);
    
        var cleared = true;
        while (cleared) {
            cleared = false;
            for (cell.items) | item, idx | {
                if (item == id) {
                    _ = cell.orderedRemove(idx);
                    cleared = true;
                    break;
                }
            }
        }
    }

    fn addToCell(self: *Space, position: zl.Vec3, id: u16) !void {
        var cell = self.getCell(position);
        for (cell.items) | item | {
            if (item == id) return;
        }
        try cell.append(id);
    }

    fn inBounds(self: *Space, entity: Entity) bool {
        var x = entity.position.x + entity.collider.?.x;
        var y = entity.position.y + entity.collider.?.y;

        return x >= 0 and y >= 0 and
            entity.collider.?.w <= @intToFloat(f32, self.w*self.cell_size) and 
            entity.collider.?.h <= @intToFloat(f32, self.h*self.cell_size);
    }

    fn addEntity(self: *Space, entity: Entity) !void {
        if (entity.collider == null) return;
        if (!self.inBounds(entity)) return;

        var g = @intToFloat(f32, self.cell_size);

        const fcx = (entity.position.x + entity.collider.?.x) / g;
        const fcy = (entity.position.y + entity.collider.?.y) / g;

        var cw = @ceil(fcx + entity.collider.?.w / g)-1;
        var ch = @ceil(fcy + entity.collider.?.h / g)-1;
        var cx = std.math.max(0, @floor(fcx));
        var cy = std.math.max(0, @floor(fcy));

        while (cx <= cw) {
            defer cx += 1;
            cy = @floor(fcy);

            while (cy <= ch) {
                defer cy += 1;
                try self.addToCell(.{ .x = cx*g, .y = cy*g }, entity.generation);
   
            }            
        }
    }

    fn delEntity(self: *Space, entity: Entity) !void {
        if (entity.collider == null) return;
        if (!self.inBounds(entity)) return;

        var g = @intToFloat(f32, self.cell_size);

        const fcx = (entity.position.x + entity.collider.?.x) / g;
        const fcy = (entity.position.y + entity.collider.?.y) / g;

        var cw = @ceil(fcx + entity.collider.?.w / g)-1;
        var ch = @ceil(fcy + entity.collider.?.h / g)-1;
        var cx = std.math.max(0, @floor(fcx));
        var cy = std.math.max(0, @floor(fcy));

        while (cx <= cw) {
            defer cx += 1;
            cy = @floor(fcy);

            while (cy <= ch) {
                defer cy += 1;
                self.remFromCell(.{ .x = cx*g, .y = cy*g }, entity.generation);
   
            }            
        }
    }

    pub fn getColliders(self: *Space, entity: Entity) !?[]EntityType {
        if (entity.collider == null) return null;
        if (!self.inBounds(entity)) return null;

        var g = @intToFloat(f32, self.cell_size);

        const fcx = (entity.position.x + entity.collider.?.x) / g;
        const fcy = (entity.position.y + entity.collider.?.y) / g;

        var cw = @ceil(fcx + entity.collider.?.w / g);
        var ch = @ceil(fcy + entity.collider.?.h / g);
        var cx = std.math.max(0, @floor(fcx)-1);
        var cy = std.math.max(0, @floor(fcy)-1);

        var out = ListType.init(self.alloc);
        var map = HashType.init(self.alloc);

        while (cx <= cw) {
            defer cx += 1;
            cy = @floor(fcy);

            while (cy <= ch) {
                defer cy += 1;
                for (self.getCell(.{ .x = cx*g, .y = cy*g }).items) |item| {
                    if (map.get(item) == null)
                        try out.append(item);

                    try map.put(item, true);
                }
            }            
        }

        map.deinit();
        return out.toOwnedSlice();
    }
};

fn loadImage(data: []const u8) !Texture {
    var texture_raw = try as.loadTexture(data);

    var image_desc: sg.ImageDesc = .{
        .width  = @intCast(i32, texture_raw.width ),
        .height = @intCast(i32, texture_raw.height),

        .min_filter = .NEAREST,
        .mag_filter = .NEAREST,
    };
    image_desc.data.subimage[0][0] = sg.asRange(texture_raw.raw);
    return Texture {
        .texture = sg.makeImage(image_desc),
        .origin = texture_raw
    };
}

fn entitySort(_: *@TypeOf(state), a: Entity, b: Entity) bool {
    return a.position.z > b.position.z;
}

var allocator = std.heap.c_allocator;
var state: struct {
    bind: sg.Bindings = .{},
    pip:  sg.Pipeline = .{},

    vertex_array: std.ArrayList(f32) = undefined,
    index_array:  std.ArrayList(u16) = undefined,
    sprite_amount: u32 = undefined,

    camera: zl.Vec3 = .{ .x = 0, .y = 0, .z = 5 },
    target_camera: zl.Vec3 = .{ .x = 0, .y = 0, .z = 5 },

    atlas: Texture = undefined,
    pass_action: sg.PassAction = undefined,

    map:   []Level = undefined,
    space: Space = undefined,

    level: u8 = 0,
    keys:  struct {
        up:    bool = false,
        down:  bool = false,
        left:  bool = false,
        right: bool = false,
    } = .{},

    key_assoc: struct {
        up: sapp.Keycode = .UP,
        down: sapp.Keycode = .DOWN,
        left: sapp.Keycode = .LEFT,
        right: sapp.Keycode = .RIGHT,
    } = .{},

    sounds:   std.ArrayList(as.Sound) = undefined,
    speakers: std.ArrayList(Speaker)  = undefined, 

    font: [255]Sprite = undefined,
    generation: u16 = 1,
    paused: bool = false,

    pub fn fetchItem(self: *@This(), id: u16) ?*Entity {
        for (self.map[self.level].entities.items) |*ent| {
            if (ent.generation == id) return ent;
        }
        return null;
    }

    fn addSprite(self: *@This(), item: Sprite) !void {
        var w = item.w * item.scx;
        var h = item.h * item.scy;

        var model = zl.Mat4.mul(
            zl.Mat4.translate((zl.Vec3{
                .x = item.x - (w/2) + (item.w/2), 
                .y = item.y - (h/2) + (item.h/2), 
                .z = 0
            }).round(1/self.camera.z)), 
            zl.Mat4.scale(
                w, h, 1
            )
        );

        var a = model.mulByVec3(zl.Vec3.new(1, 1, 1));
        var b = model.mulByVec3(zl.Vec3.new(1, 0, 1));
        var c = model.mulByVec3(zl.Vec3.new(0, 0, 1));
        var d = model.mulByVec3(zl.Vec3.new(0, 1, 1));

        var sx: f32 = @intToFloat(f32, item.sx) / 
                      @intToFloat(f32, self.atlas.origin.width);

        var sy: f32 = @intToFloat(f32, item.sy) / 
                      @intToFloat(f32, self.atlas.origin.height);

        var sw: f32 = sx + (@intToFloat(f32, item.sw) / 
                      @intToFloat(f32, self.atlas.origin.width));

        var sh: f32 = sy + (@intToFloat(f32, item.sh) / 
                      @intToFloat(f32, self.atlas.origin.height));

        const vertex = [_]f32{
            a.x, a.y, 1,   sw, sh, 
            b.x, b.y, 1,   sw, sy,
            c.x, c.y, 1,   sx, sy,
            d.x, d.y, 1,   sx, sh,
        };
        try self.vertex_array.appendSlice(vertex[0..20]);

        var e = @intCast(u16, (self.sprite_amount)*4);
        const indices = [_]u16{
            e, e+1, e+2, e, e+2, e+3
        };
        try self.index_array.appendSlice(indices[0..]);

        self.sprite_amount += 1;
    }

    pub fn addRectangle(self: *@This(), x: f32, y: f32, w: f32, h: f32, px: u16, py: u16) !void {
        try self.addSprite(.{
            .x = x, .y = y, .w = w, .h = h,
            .sx = px, .sy = py, .sw = 1, .sh = 1
        });
    }

    fn loadMap(self: *@This(), src: []const u8) !void {
        @setEvalBranchQuota(1024*8);

        var raw = try as.loadFile(src);
        var tknstream = json.TokenStream.init(raw.raw);
        var map = try json.parse([]ProtoLevel, &tknstream, .{ 
            .allocator = allocator 
        });

        var end_map = std.ArrayList(Level).init(allocator);
        for (map) | level | {
            var entities = EntityArrayList.init(allocator);
            var speakers = std.ArrayList(Speaker).init(allocator);

            for (level.entities) |*item| {
                item.generation = self.generation;
                self.generation += 1;
            }
            try entities.appendSlice(level.entities);

            try end_map.append(Level{
                .width = level.width, .height = level.height,
                .tiledata = level.tiledata, 
                .entities = entities,
                .speakers = speakers
            });
        }

        self.map = end_map.toOwnedSlice();
        end_map.deinit();

        //self.map[self.level].scene = Scene.init(&allocator);
        //for (self.map[self.level].entities) | ent | {
        //    self.map[self.level].scene.add(ent.Player);
        //}
    }

    fn loadLevel(self: *@This(), to: u8) !void {
        self.level = to;
        //if (self.space != undefined) self.space.deinit();
        self.space = try Space.init(self.map[to].width, self.map[to].height, 32, allocator);

        for (self.map[to].entities.items) | *item | {
            try item.init();

            if (item.collider != null and item.velocity == null) {
                try self.space.addEntity(item.*);
            }
        }
    }

    pub fn print(self: *@This(), position: zl.Vec3, comptime fmt: []const u8, etc: anytype) !void {
        var real_position = position.copy();
        var buffer = try allocator.alloc(u8, 256);

        for (try std.fmt.bufPrint(buffer, fmt, etc)) |char| {
            switch (char) {
                else => {
                    var spr = self.font[char];
                    spr.x = real_position.x;
                    spr.y = real_position.y;

                    if (self.camera.z > 1.2) {
                        spr.w = @floor(spr.w/2);
                        spr.h = @floor(spr.h/2);
                    }

                    try self.addSprite(spr);
                    real_position.x += spr.w +1;
                }
            }
        }
        allocator.free(buffer);
    }

    fn init(self: *@This()) !void {
        //defer {
        //    const leaked = gpa.deinit();
        //    if (leaked) expect(false) catch @panic("TEST FAIL"); //fail test; can't try in defer as defer is executed after we return
        //}

        for ("abcdefghijklmnopqrstuvwxyz0123456789!?.,") | char, key | {
            var k = @intToFloat(f32, key);
            self.font[char] = Sprite {
                .sx = 64 + @floatToInt(u16, @mod(k, 8)*8) +
                switch(char) {
                    else => 1
                },
                .sy = @floatToInt(u16, @floor(k / 8))*8,
                .sw = switch (char) {
                    'i', '!', ',', '.' => 1,
                    'm', 'n', 'o' => 7,
                    else => 6
                }
            };

            self.font[char].w = @intToFloat(f32, self.font[char].sw);
            self.font[char].h = @intToFloat(f32, self.font[char].sh);
        }

        self.sounds  = std.ArrayList(as.Sound).init(allocator);
        self.vertex_array = std.ArrayList(f32).init(allocator);
        self.index_array  = std.ArrayList(u16).init(allocator);

        self.pass_action.colors[0] = .{
            .action = .CLEAR,
            .value = .{ .r = 0.08, .g = 0.08, .b = 0.11, .a = 1.0 }, // HELLO EIGENGRAU!
        };

        try self.sounds.append(try as.loadMP3(@embedFile("../assets/angst.mp3"), allocator));

        try as.setup();
        sg.setup(.{ .context = sgapp.context() });
        st.setup();
    
        self.bind.vertex_buffers[0] = sg.makeBuffer(.{ 
            .usage = .STREAM,
            .size = 2048*16
        });

        self.bind.index_buffer = sg.makeBuffer(.{ 
            .type = .INDEXBUFFER,
            .usage = .STREAM,
            .size = 2048*16,
        });

        self.atlas = try loadImage(@embedFile("../assets/tileset_main.png"));
        self.bind.fs_images[shd.SLOT_tex] = self.atlas.texture;

        var pip_desc: sg.PipelineDesc = .{
            .shader = sg.makeShader(shd.mainShaderDesc(sg.queryBackend())),
            .index_type = .UINT16,
            .depth = .{
                .compare = .LESS_EQUAL,
                .write_enabled = true,
            },
        };

        pip_desc.colors[0].blend = .{
            .enabled = true,
            .src_factor_rgb = .SRC_ALPHA,
            .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
            .src_factor_alpha = .SRC_ALPHA,
            .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
        };

        pip_desc.layout.attrs[0].format = .FLOAT3;
        pip_desc.layout.attrs[1].format = .FLOAT2;
        self.pip = sg.makePipeline(pip_desc);

        try self.loadMap("assets/map_test.ldtk.map");
        try self.loadLevel(0);

        sa.setup(.{
            .num_channels = 2,
            .stream_cb = audio_wrap,
        });
    }

    fn drawGrid(self: *@This()) !void {
        var x: f32 = 0;
        var y: f32 = 0;
        var w: f32 = @intToFloat(f32, self.space.w);
        var h: f32 = @intToFloat(f32, self.space.h);
        var g: f32 = @intToFloat(f32, self.space.cell_size);

        while (x < w+1) {
            try self.addSprite(.{ 
                .x = x*g, .y = 0, 
                .w = 1, .h = h*g, 
                .sx = 26, .sy = 22,
                .sw = 1, .sh = 1
            });

            x += 1;
        }

        while (y < h+1) {
            try self.addSprite(.{ 
                .x = 0, .y = y*g, 
                .w = w*g, .h = 1,
                .sx = 26, .sy = 22,
                .sw = 1, .sh = 1
            });

            y += 1;
        }

        x = 0;

        while(x < w) {
            defer x += 1;
            y = 0;

            while (y < h) {
                defer y += 1;
                var pos = zl.Vec3 {
                    .x = (x * g) + 4,
                    .y = (y * g) + 4
                };

                var items = self.space.getCell(pos).items;
                try self.print(pos, "{any}", .{items});
            }
        }
    }

    fn frame(self: *@This()) !void {
        self.sprite_amount = self.map[self.level].tiledata.amount;

        try self.vertex_array.appendSlice(self.map[self.level].tiledata.vertices);
        try self.index_array. appendSlice(self.map[self.level].tiledata.indices);

        if (!self.paused)
            self.camera = self.camera.linear(self.target_camera, @floatCast(f32, delta)*4);

        var w = sapp.widthf();
        var h = sapp.heightf();

        self.target_camera.z = @floor(std.math.min(w, h)/120);
        self.camera.z = zl.lerp(self.camera.z, self.target_camera.z, @floatCast(f32, delta*4));

        lag += delta;
        var n: u8 = 0;

        // Thanks, Shakesoda :)
        while (lag > timestep and n < 5) {
            if (!self.paused)
                for (self.map[self.level].entities.items) | *item | {
                    try item.process();
                };

            lag -= timestep;
            n += 1;
        }

        if (n >= 5) {
            lag = 0;
        }
        
        for (self.map[self.level].entities.items) | *item | {
            try item.draw();
        }

        std.sort.sort(Entity, self.map[self.level].entities.items, self, entitySort);

        if (self.paused) {
            try self.addRectangle(self.camera.x-(w/2/self.camera.z), self.camera.y-9, (w/self.camera.z), 18, 24, 17);
            try self.addRectangle(self.camera.x-(w/2/self.camera.z), self.camera.y-8, (w/self.camera.z), 16, 26, 20);
        }

        try self.drawGrid();
        try self.print(.{ .x = 0, .y = -6 }, "{}", .{time});

        sg.updateBuffer(
            self.bind.vertex_buffers[0], 
            sg.asRange(self.vertex_array.toOwnedSlice())
        );

        sg.updateBuffer(
            self.bind.index_buffer, 
            sg.asRange(self.index_array.toOwnedSlice())
        );

        var scale = self.camera.z;
        var proj = zl.Mat4.orthogonal(0, w, h, 0, 2, -2);
        var view = zl.Mat4.mul(
            zl.Mat4.scale(scale, scale, 1),
            zl.Mat4.translate((zl.Vec3{
                .x = -self.camera.x+(w/scale/2), 
                .y = -self.camera.y+(h/scale/2), 
                .z = 0
            }).round(1/scale))
        );

        sg.beginDefaultPass(self.pass_action, sapp.width(), sapp.height());
            sg.applyPipeline(self.pip);
            sg.applyBindings(self.bind);

            sg.applyUniforms(.VS, shd.SLOT_vs_params, sg.asRange(
                shd.VsParams{
                    .pv = proj.mul(view)
                }
            ));

            sg.draw(0, @intCast(u32, self.sprite_amount+1)*6, 1);
        sg.endPass();
        self.sprite_amount = 0;

        sg.commit();
    }

    fn event(self: *@This(), _ev: [*c]const sapp.Event) !void {
        var ev = _ev.*;

        switch(ev.type) {
            .KEY_UP => {
                inline for (@typeInfo(@TypeOf(self.keys)).Struct.fields) |field| {
                    if (@field(self.key_assoc, field.name) == ev.key_code)
                        @field(self.keys, field.name) = false;
                }
            },

            .KEY_DOWN => {
                if (ev.key_code == sapp.Keycode.ESCAPE)
                    self.paused = !self.paused;

                inline for (@typeInfo(@TypeOf(self.keys)).Struct.fields) |field| {
                    if (@field(self.key_assoc, field.name) == ev.key_code)
                        @field(self.keys, field.name) = true;
                }
            },

            .UNFOCUSED =>
                self.paused = true,

            .FOCUSED =>
                self.paused = false,

            else => return
        }
    }

    pub fn audio(self: *@This(), out: [*c]f32, frames: i32, channel: i32) !void {
        var i: usize = 0;
        audio_delta = st.sec(st.laptime(&audio_last));
        
        while (i < frames*channel) {
            out[i] = 0;
            i += 1;
        }

        for (self.map[self.level].speakers.items) |speaker| {
            
            //std.log.info("{}", .{speaker});
            var distance = speaker.position.dist(self.target_camera);
            if (distance > speaker.area) continue;

            var amplitude = std.math.pow(f32, 1-(std.math.min(distance, speaker.area)/speaker.area), 2)*speaker.volume;

            i = 0;
            while (i < frames*channel) {
                out[i] = (@intToFloat(f32, zl.randomi32(100))/100)*amplitude*4;
                i += 1;
            }
        }
    }

    fn cleanup(_: *@This()) !void {
        sg.shutdown();
        sa.shutdown();
    }

} = .{};

//////////////////////////////////////////////

fn errorHandler(err: anyerror) void  {
    std.debug.print("Something went AWFULLY WRONG, please send help :(\n", .{});
    std.debug.print("Error code: {s}\n\n", .{@errorName(err)});

    var trace = @errorReturnTrace() orelse std.os.abort();
    std.debug.dumpStackTrace(trace.*);

    std.os.abort();
}

export fn init_wrap() void {
    state.init() catch |err| errorHandler(err);
}

export fn frame_wrap() void {
    time = st.laptime(&last);
    delta = st.sec(time);
    state.frame() catch |err| errorHandler(err);
}

export fn cleanup_wrap() void {
    state.cleanup() catch |err| errorHandler(err);
}

export fn event_wrap(event: [*c]const sapp.Event) void {
    state.event(event) catch |err| errorHandler(err);
}

export fn audio_wrap(out_buffer: [*c]f32, frames: c_int, channels: c_int) void {
    state.audio(
        out_buffer,
        @intCast(i32, frames), 
        @intCast(i32, channels)
    ) catch |err| errorHandler(err);
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init_wrap,
        .frame_cb = frame_wrap,
        .cleanup_cb = cleanup_wrap,
        .event_cb = event_wrap,
        .width = 800,
        .height = 600,
        .icon = .{
            .sokol_default = true,
        },
        .swap_interval = 0,
        .window_title = "sokamoka!"
    });
}