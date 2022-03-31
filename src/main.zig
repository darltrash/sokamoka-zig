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
var last: u64 = 0;

const grid_size = 16;

pub const Sprite = struct {
    sx: u16 = 0, sy: u16 = 0, 
    sw: u8  = 8, sh: u8  = 8, 
    x:  f32 = 0, y:  f32 = 0,
    w:  f32 = 8, h:  f32 = 8,
    scx: f32 = 1, scy: f32 = 1
};

const Texture = struct {
    texture: sg.Image,
    origin: as.Texture
};

pub const Tile = struct {
    x: u16,  y: u16, z: u16 = 0,
    sx: u16, sy: u16
};

pub const Collider = struct {
    x: u16 = 0, y: u16 = 0, 
    w: u16, h: u16, 
};

pub const EntityTypes = enum {
    IGNORE, Player
};

pub const Entity = struct {
    generation: u16 = 0,
    visible:  bool = true,
    active:   bool = true,
    hasMass:  bool = false,

    position: zl.Vec3  = .{ .x = 0, .y = 0, .z = 0 },
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
    } = .{ .IGNORE = .{} },

    pub fn init(self: *Entity) void {
        switch (self.extra) {
            .IGNORE => return,
            .Player => {
                self.velocity = zl.Vec3{ .x = 0, .y = 0, .z = 0 };

                self.collider = Collider {
                    .x = 4, .y = 0, .w = 8, .h = 16
                };

                self.sprite = Sprite {
                    .sx = 6*8,  .sy = 0,
                    .sw = 16, .sh = 16,
                    .x  = 0,  .y  = 0,
                    .w  = 16, .h  = 16
                };
            }
        }
    }

    pub fn process(self: *Entity) !void {
        switch (self.extra) {
            .IGNORE => {},
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
                    @floatCast(f32, delta*12*extra.acceleration));

                var moving = (vel.x != 0 or vel.y != 0);
                if (moving and !extra.moving) {
                    extra.animation = 1;
                }

                if (moving) {
                    extra.animation += delta*4;
                    extra.acceleration = std.math.min(extra.acceleration + @floatCast(f32, delta/2), 2.3);

                } else {
                    extra.animation = 0;
                    extra.acceleration = 1.5;

                }
                extra.moving = moving;

                self.velocity = self.velocity.?.linear(vel, @floatCast(f32, delta*8));

                self.sprite.?.sy = @floatToInt(u16, @mod(extra.animation, 4))*16;

                state.target_camera.x = self.position.x+8;
                state.target_camera.y = self.position.y+8;
            }
        } 
        
        if (self.velocity != null) {
            if (false and self.collider != null and std.math.absFloat(self.velocity.?.len()) > 0.2) { 

            } else
                self.position = self.position.add(self.velocity.?.mul(@floatCast(f32, delta*32)));
        }
    }

    pub fn draw(self: *Entity) !void {
        // https://www.youtube.com/watch?v=0m4tQgALw34

        if (self.collider != null) {
            try state.addSprite(.{
                .x = self.position.x + @intToFloat(f32, self.collider.?.x),
                .y = self.position.y + @intToFloat(f32, self.collider.?.y),
                .sx = 54, .sy = 42,
                .sw = 1, .sh = 1,
                .w = @intToFloat(f32, self.collider.?.w), 
                .h = @intToFloat(f32, self.collider.?.h)
            });

            try state.print(.{
                .x = self.position.x + @intToFloat(f32, self.collider.?.x)+1,
                .y = self.position.y + @intToFloat(f32, self.collider.?.y)+1,
            }, "{}", .{self.generation});
        }

        if (self.sprite == null) 
            return;

        var sprite = self.sprite.?;
        sprite.x += self.position.x;
        sprite.y += self.position.y;
        try state.addSprite(sprite);
    }
};

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

pub const Sound = struct {
    stream: []u32,

};

pub const Cell = struct {
    items: []u16,
    amount: usize
};

pub const Space = struct {
    const ListType = std.ArrayList(u16);

    grid: []?ListType,
    grid_size: u32,
    w: u32, h: u32,
    alloc: std.mem.Allocator,

    pub fn init(w: u32, h: u32, s: u32, alloc: std.mem.Allocator) !Space {
        var _grid_size = @intToFloat(f32, s);
        var length = @floatToInt(usize, @intToFloat(f32, w*h)/_grid_size);
        var grid = try alloc.alloc(?ListType, length);
        
        return Space {
            .w = @floatToInt(u32, @intToFloat(f32, w)/_grid_size), 
            .h = @floatToInt(u32, @intToFloat(f32, h)/_grid_size), 
            .grid_size = s,
            .grid = grid, .alloc = alloc
        };
    }

    fn toHash(self: *Space, position: zl.Vec3) callconv(.Inline) usize {
        var s = @intToFloat(f32, self.grid_size);
        return @floatToInt(usize, (@floor(position.x/s)*@intToFloat(f32, self.w)) + 
               @floor(position.y/s));
    }

    fn getCell(self: *Space, position: zl.Vec3) callconv(.Inline) *ListType {
        var hash = self.toHash(position);
        return &(self.grid[hash] orelse {
            var cell = ListType.init(self.alloc);
            self.grid[hash] = cell;

            return &cell;
        });
    }

    fn addEntity(self: *Space, entity: Entity) !void {
        if (entity.collider == null) return;

        var x = entity.position.x + @intToFloat(f32, entity.collider.?.x);
        var y = entity.position.y + @intToFloat(f32, entity.collider.?.y);
        var w = x + @intToFloat(f32, entity.collider.?.w);
        var h = y + @intToFloat(f32, entity.collider.?.h);

        var a: u8 = 0;
        while (x <= w) {
            while (y <= h) {
                try self.getCell(.{ .x = x, .y = y }).append(entity.generation);

                y += grid_size;
                a += 1;
            }

            x += grid_size;
        }
    }
};

pub const EntityArrayList = std.ArrayList(Entity);

pub const Level = struct {
    width: u32, height: u32,
    tiledata: TileData,
    entities: EntityArrayList,
    generation: u16 = 1,
};

fn loadImage(str: []const u8) !Texture {
    var file = try as.loadFile(str);
    var texture_raw = try as.loadTexture(file.raw);

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

const allocator = std.heap.c_allocator;
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

    tick_rate: f64 = 1/30,
    lag: f64 = 1/30,

    font: [255]Sprite = undefined,

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

            var generation: u16 = 0;
            for (level.entities) |*item| {
                item.generation = generation;
                generation += 1;
            }
            try entities.appendSlice(level.entities);

            try end_map.append(Level{
                .width = level.width, .height = level.height,
                .tiledata = level.tiledata, 
                .entities = entities,
                .generation = generation,
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
        self.space = try Space.init(self.map[to].width, self.map[to].height, 32, allocator);

        for (self.map[to].entities.items) | *item | {
            item.init();

            if (item.collider != null) {
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

                    try self.addSprite(spr);
                    real_position.x += @intToFloat(f32, spr.sw) +1;
                }
            }
        }
        allocator.free(buffer);
    }

    fn init(self: *@This()) !void {
        for ("abcdefghijklmnopqrstuvwxyz0123456789!?.,") | char, key | {
            var k = @intToFloat(f32, key);
            self.font[char] = Sprite {
                .sx = 64 + @floatToInt(u16, @mod(k, 8)*8) +
                switch(char) {
                    else => 1
                },
                .sy = @floatToInt(u16, @floor(k / 8))*8,
                .sw = switch (char) {
                    'i', '!' => 1,
                    'm', 'n', 'o' => 7,
                    else => 6
                }
            };

            self.font[char].w = @intToFloat(f32, self.font[char].sw);
            self.font[char].h = @intToFloat(f32, self.font[char].sh);
        }

        self.vertex_array = std.ArrayList(f32).init(allocator);
        self.index_array  = std.ArrayList(u16).init(allocator);

        self.pass_action.colors[0] = .{
            .action = .CLEAR,
            .value = .{ .r = 0.08, .g = 0.08, .b = 0.11, .a = 1.0 }, // HELLO EIGENGRAU!
        };

        try as.setup();
        sg.setup(.{ .context = sgapp.context() });
        st.setup();
        sa.setup(.{
            .num_channels = 2,
            .stream_cb = audio_wrap
        });

        self.bind.vertex_buffers[0] = sg.makeBuffer(.{ 
            .usage = .STREAM,
            .size = 2048*8
        });

        self.bind.index_buffer = sg.makeBuffer(.{ 
            .type = .INDEXBUFFER,
            .usage = .STREAM,
            .size = 2048*8,
        });

        self.atlas = try loadImage("assets/tileset_main.png");
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
    }

    fn drawGrid(self: *@This()) !void {
        var x: f32 = 0;
        var y: f32 = 0;
        var w: f32 = @intToFloat(f32, self.space.w)+1;
        var h: f32 = @intToFloat(f32, self.space.h)+1;
        var g: f32 = @intToFloat(f32, self.space.grid_size);

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

        var c: f32 = 0;
        while(c <= (w*h)-1) {
            var pos = zl.Vec3 {
                .x = (@floor(c / h) * g)+4,
                .y = (@mod(c, h) * g)+4
            };
            var items = self.space.getCell(pos).items;

            try self.print(pos, "{any}", .{items});

            c += 1;
        }
    }

    fn frame(self: *@This()) !void {
        self.sprite_amount = self.map[self.level].tiledata.amount;

        try self.vertex_array.appendSlice(self.map[self.level].tiledata.vertices);
        try self.index_array. appendSlice(self.map[self.level].tiledata.indices);

        if (!self.paused)
            self.camera = self.camera.linear(self.target_camera, @floatCast(f32, delta)*4);

        std.sort.sort(Entity, self.map[self.level].entities.items, self, entitySort);

        var w = sapp.widthf();
        var h = sapp.heightf();

        self.target_camera.z = @floor(std.math.min(w, h)/120);
        self.camera.z = zl.lerp(self.camera.z, self.target_camera.z, @floatCast(f32, delta*4));

        for (self.map[self.level].entities.items) | *item | {
            if (!self.paused)
                try item.process();

            try item.draw();
        }
        
        try self.drawGrid();

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

    pub fn audio(_: *@This(), _: [*c]f32, _: i32, _: i32) !void {
        return;
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
    delta = st.sec(st.laptime(&last));
    state.frame() catch |err| errorHandler(err);
}

export fn cleanup_wrap() void {
    state.cleanup() catch |err| errorHandler(err);
}

export fn event_wrap(event: [*c]const sapp.Event) void {
    state.event(event) catch |err| errorHandler(err);
}

export fn audio_wrap(buffer: [*c]f32, frames: c_int, channels: c_int) void {
    state.audio(
        buffer, @intCast(i32, frames), 
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
        .swap_interval = 1,
        .window_title = "sokamoka!"
    });
}