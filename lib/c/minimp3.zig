const std = @import("std");

pub const mp3dec_frame_info_t = extern struct {
    frame_bytes: c_int,
    frame_offset: c_int,
    channels: c_int,
    hz: c_int,
    layer: c_int,
    bitrate_kbps: c_int,
};
pub const FrameInfo = mp3dec_frame_info_t;

pub const mp3dec_t = extern struct {
    mdct_overlap: [2][288]f32,
    qmf_state: [960]f32,
    reserv: c_int,
    free_format_bytes: c_int,
    header: [4]u8,
    reserv_buf: [511]u8,

    pub fn init() Decoder {
        var mp3dec: mp3dec_t = undefined;
        mp3dec_init(&mp3dec);
        return mp3dec;
    }

    pub fn decodeFrame(self: *Decoder, mp3: []const u8, info: *FrameInfo) ![]Sample {
        var pcm: [MAX_SAMPLES_PER_FRAME]Sample = undefined;
        var status = mp3dec_decode_frame(self, mp3.ptr, @intCast(c_int, mp3.len), &pcm, info);
        if (info.frame_bytes == 0 and status == 0) return error.couldNotDecode;
        return pcm[0..];
    }
};
pub const Decoder = mp3dec_t;

pub const MAX_SAMPLES_PER_FRAME = 2304;

pub const Sample = f32;
pub extern fn mp3dec_init(dec: [*c]mp3dec_t) void;
pub extern fn mp3dec_f32_to_s16(in: [*c]const f32, out: [*c]i16, num_samples: c_int) void;
pub extern fn mp3dec_decode_frame(dec: [*c]mp3dec_t, mp3: [*c]const u8, mp3_bytes: c_int, pcm: [*c]Sample, info: [*c]mp3dec_frame_info_t) c_int;
