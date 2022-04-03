const std = @import("std");
const c = @cImport({
    @cDefine("STB_IMAGE_IMPLEMENTATION", {});
    @cDefine("STBI_NO_STDIO", {});
    @cDefine("STBI_ONLY_PNG", {});

    @cInclude("stb_image.h");
});
const minimp3 = @import("minimp3");

var fs_dir: std.fs.Dir = undefined;

pub fn setup() !void {
    fs_dir = std.fs.cwd();
}

pub const Texture = struct { 
    width: u32, height: u32, 
    pitch: u32, raw: []u8 
};

pub const File = struct { 
    size: u64, raw: []u8 
};

pub const Sound = struct {
    handle: minimp3.Decoder,
    stream: []const u8,
    info: minimp3.FrameInfo = undefined,
    allocator: std.mem.Allocator,

    pub fn getFrames(self: *Sound, frames: usize) ![]f32 {
        var list = std.ArrayList(minimp3.Sample).init(self.allocator);
        var i: usize = 0;
        while (i < frames) {
            try list.appendSlice(try self.handle.decodeFrame(self.stream, &self.info));
            i += 1;
        }
        return list.toOwnedSlice();
    }
};

pub fn loadTexture(compressed_bytes: []const u8) !Texture {
    var pi: Texture = undefined;

    var width: c_int = 0;
    var height: c_int = 0;

    if (c.stbi_info_from_memory(compressed_bytes.ptr, @intCast(c_int, compressed_bytes.len), &width, &height, null) == 0) {
        return error.NotCompatibleFile;
    }

    if (width <= 0 or height <= 0) return error.NoPixels;
    pi.width = @intCast(u32, width);
    pi.height = @intCast(u32, height);

    if (c.stbi_is_16_bit_from_memory(compressed_bytes.ptr, @intCast(c_int, compressed_bytes.len)) != 0) {
        return error.InvalidFormat;
    }
    const bits_per_channel = 8;
    const channel_count = 4;

    const image_data = c.stbi_load_from_memory(compressed_bytes.ptr, @intCast(c_int, compressed_bytes.len), &width, &height, null, channel_count);

    if (image_data == null) return error.NoMem;

    pi.pitch = pi.width * bits_per_channel * channel_count / 8;
    pi.raw = image_data[0..(pi.height * pi.pitch)];

    return pi;
}

pub fn loadFile(name: []const u8) !File {
    var file = try fs_dir.openFile(name, .{ .read = true });
    var size = try file.getEndPos();
    var data = try file.readToEndAlloc(std.heap.c_allocator, size);
    file.close();

    return File{ .size = size, .raw = data };
}

pub fn loadMP3(raw: []const u8, alloc: std.mem.Allocator) !Sound {
    return Sound {
        .handle = minimp3.Decoder.init(),
        .stream = raw,
        .allocator = alloc
    };
}