const builtin = @import("builtin");
const game = @import("game.zig");
const SDL = @import("sdl2");
const std = @import("std");

const is_wasm = builtin.target.isWasm();

const c = @cImport({
    if (is_wasm) {
        @cInclude("emscripten.h");
    } else {
        @cInclude("mpg123.h");
    }
});

var channel: SDL.c.SDL_AudioDeviceID = undefined;

var playing_tracks: std.ArrayList(Audio) = undefined;
var mix_buffer: []i16 = undefined;

const MpegError = error{
    GenericError,

    IOError,
    OutOfMemory,
    InvalidRvaMode,
    InsufficientBufferSpace,
    BadEqualizerBand,
    OutOfSync,
    ResyncFail,
    No8BitEncoding,
    BadAlignment,
    Overflow,
};

fn makeMpegError(code: c_int) MpegError {
    return switch (code) {
        c.MPG123_ERR => error.GenericError,

        c.MPG123_ERR_READER => error.IOError,
        c.MPG123_NO_SEEK_FROM_END => error.IOError,
        c.MPG123_BAD_FILE => error.IOError,
        c.MPG123_LSEEK_FAILED => error.IOError,
        c.MPG123_BAD_CUSTOM_IO => error.IOError,

        c.MPG123_ERR_16TO8TABLE => error.OutOfMemory,
        c.MPG123_OUT_OF_MEM => error.OutOfMemory,
        c.MPG123_NO_BUFFERS => error.OutOfMemory,

        c.MPG123_LFS_OVERFLOW => error.Overflow,
        c.MPG123_INT_OVERFLOW => error.Overflow,

        c.MPG123_BAD_RVA => error.InvalidRvaMode,
        c.MPG123_NO_SPACE => error.InsufficientBufferSpace,
        c.MPG123_BAD_BAND => error.BadEqualizerBand,
        c.MPG123_OUT_OF_SYNC => error.OutOfSync,
        c.MPG123_RESYNC_FAIL => error.ResyncFail,
        c.MPG123_NO_8BIT => error.No8BitEncoding,
        c.MPG123_BAD_ALIGN => error.BadAlignment,

        else => std.debug.panic("unexpected mpg123 error: '{s}'", .{c.mpg123_plain_strerror(code)}),
    };
}

const SAMPLE_RATE = 44100;
const CHANNEL_COUNT = 2;
// should match
const SDL_FORMAT = SDL.c.AUDIO_S16SYS;
const MPG_FORMAT = c.MPG123_ENC_SIGNED_16;

fn audioCallback(userdata: ?*anyopaque, stream: ?[*]u8, len: c_int) callconv(.C) void {
    _ = userdata;
    // cast to unsigned
    const length = @intCast(usize, len);
    // assert that the buffer isn't larger than we said we'd support
    std.debug.assert(length <= mix_buffer.len * @sizeOf(i16));
    // assert that the buffer doesn't split samples
    std.debug.assert(length % @sizeOf(i16) == 0);
    // cast the buffer to the sample type
    const buffer = @ptrCast([*]align(1) i16, stream.?)[0 .. length / @sizeOf(i16)];
    // clear out the buffer
    @memset(stream.?, 0, length);
    // linearly mix each track
    for (playing_tracks.items) |track| {
        // read into auxillary buffer
        const err = c.mpg123_read(track.handle, mix_buffer.ptr, length, null);
        // check errors
        if (err > c.MPG123_OK) {
            const e = makeMpegError(err);
            std.debug.panic("playback error: {}", .{e});
        } else if (err == c.MPG123_DONE) {
            track.remove();
            continue;
        }
        // mix into output
        for (mix_buffer) |b, i| {
            buffer[i] += b;
        }
    }
}

pub fn init() !void {
    if (!is_wasm) {
        // initialize mpg123
        const err = c.mpg123_init();
        if (err != c.MPG123_OK) {
            return makeMpegError(err);
        }

        playing_tracks = std.ArrayList(Audio).init(game.allocator());
        errdefer playing_tracks.deinit();

        var desired = std.mem.zeroes(SDL.c.SDL_AudioSpec);
        desired.freq = SAMPLE_RATE;
        desired.format = SDL.c.AUDIO_S16SYS;
        desired.channels = CHANNEL_COUNT;
        desired.samples = 512;
        desired.callback = audioCallback;
        var obtained: SDL.c.SDL_AudioSpec = undefined;
        const id = SDL.c.SDL_OpenAudioDevice(null, 0, &desired, &obtained, 0);
        if (id == 0) {
            return SDL.makeError();
        }
        errdefer SDL.c.SDL_CloseAudioDevice(id);

        mix_buffer = try game.allocator().alloc(i16, obtained.size / @sizeOf(i16));
        errdefer game.allocator().free(mix_buffer);

        SDL.c.SDL_PauseAudioDevice(id, 0);
    }
}

pub fn deinit() void {
    if (!is_wasm) {
        playing_tracks.deinit();
        game.allocator().free(mix_buffer);
    }
}

pub const Audio = if (is_wasm)
    struct {
        const Self = @This();

        handle: i32,

        extern fn jsNewAudio(src: [*:0]const u8) i32;

        extern fn jsIsAudioReady(handle: i32) i32;

        pub fn init(src: [*:0]const u8) !Self {
            const handle = jsNewAudio(src);
            if (handle == -1) return error.AudioError;
            while (jsIsAudioReady(handle) == 0) {
                c.emscripten_sleep(0);
            }
            return Self{ .handle = handle };
        }

        extern fn jsFreeAudio(handle: i32) void;

        pub fn deinit(self: Self) void {
            jsFreeAudio(self.handle);
        }

        extern fn jsPlayAudio(handle: i32) void;

        pub fn play(self: Self) !void {
            jsPlayAudio(self.handle);
        }

        extern fn jsGetAudioPos(handle: i32) u64;

        pub fn getPos(self: Self) u64 {
            return jsGetAudioPos(self.handle);
        }

        extern fn jsGetAudioDuration(handle: i32) u64;

        pub fn getDuration(self: Self) !u64 {
            const result = jsGetAudioDuration(self.handle);
            if (result < 0) return error.UnknownTrackLength;
            return result;
        }
    }
else
    struct {
        const Self = @This();

        // zig was getting a bit too eagev to evaluate this type
        handle: *if (is_wasm) anyopaque else c.mpg123_handle,

        pub fn init(src: [*:0]const u8) !Self {
            var err: c_int = undefined;
            const handle = c.mpg123_new(null, &err) orelse return makeMpegError(err);
            const self = Self{ .handle = handle };
            errdefer self.deinit();
            // force sample rate
            err = c.mpg123_param2(self.handle, c.MPG123_FORCE_RATE, SAMPLE_RATE, undefined);
            if (err != c.MPG123_OK) {
                return makeMpegError(err);
            }
            // open file, with settings matching SDL audio device
            // TODO what is the endianness of mpg123
            err = c.mpg123_open_fixed(self.handle, src, CHANNEL_COUNT, c.MPG123_ENC_SIGNED_16);
            if (err != c.MPG123_OK) {
                return makeMpegError(err);
            }
            // since the sample rate is forced, we don't need this info, but we
            // do need to feed it through mpg123's decoder
            err = c.mpg123_getformat(self.handle, null, null, null);
            if (err != c.MPG123_OK) {
                return makeMpegError(err);
            }
            return self;
        }

        fn remove(self: Self) void {
            for (playing_tracks.items) |track, i| {
                if (track.handle == self.handle) {
                    _ = playing_tracks.swapRemove(i);
                    break;
                }
            }
        }

        pub fn deinit(self: Self) void {
            self.remove();
            _ = c.mpg123_close(self.handle);
            _ = c.mpg123_delete(self.handle);
        }

        /// Play the track.
        pub fn play(self: Self) !void {
            try playing_tracks.append(self);
        }

        fn samplesToMillis(samples: c.off_t) u64 {
            return (@intCast(u64, samples) * 1000) / SAMPLE_RATE;
        }

        /// Get the position in the track, in milliseconds.
        pub fn getPos(self: Self) u64 {
            return samplesToMillis(c.mpg123_tell(self.handle));
        }

        /// Get the duration of the track, in milliseconds.
        pub fn getDuration(self: Self) !u64 {
            const samples = c.mpg123_length(self.handle);
            if (samples < 0) return error.UnknownTrackLength;
            return samplesToMillis(samples);
        }
    };
