pub const Mp3decFrameInfo = extern struct {
    frame_bytes: c_int,
    frame_offset: c_int,
    channels: c_int,
    hz: c_int,
    layer: c_int,
    bitrate_kbps: c_int,
};
pub const Mp3dec = extern struct {
    mdct_overlap: [2][288]f32,
    qmf_state: [960]f32,
    reserv: c_int,
    free_format_bytes: c_int,
    header: [4]u8,
    reserv_buf: [511]u8,
};

pub const Mp3dSample = i16;
pub const MaxSamplesPerFrame: c_int = 2304;

extern fn mp3dec_init(dec: [*c]Mp3dec) void;
pub fn init(dec: *Mp3dec) void {
    mp3dec_init(dec);
}

extern fn mp3dec_decode_frame(dec: [*c]Mp3dec, mp3: [*c]const u8, mp3_bytes: c_int, pcm: [*c]mp3d_sample_t, info: [*c]Mp3decFrameInfo) c_int;
pub fn decodeFrame(dec: *mp3dec, mp3: [*c]const u8, mp3_bytes: c_int, pcm: [*c]Mp3dSample, info: *Mp3decFrameInfo) c_int {
    return mp3dec_decode_frame(dec, mp3, mp3_bytes, pcm, info);
}