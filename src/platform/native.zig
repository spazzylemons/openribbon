const music = @import("../music.zig");
const renderer = @import("../renderer.zig");
const SDL = @import("sdl2");
const std = @import("std");
const util = @import("../util.zig");
const window = @import("../window.zig");

const c = util.c;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

var window_object: SDL.Window = undefined;
var should_close: bool = undefined;

var channel: SDL.c.SDL_AudioDeviceID = undefined;
var playing_tracks: std.ArrayList(AudioHandle) = undefined;
var mix_buffer: []i16 = undefined;

var press_queue: std.TailQueue(window.PressedKey) = .{};
const PressNode = @TypeOf(press_queue).Node;

fn removeTrack(handle: AudioHandle) void {
    for (playing_tracks.items) |track, i| {
        if (track == handle) {
            _ = playing_tracks.swapRemove(i);
            break;
        }
    }
}

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
        const err = c.mpg123_read(track, mix_buffer.ptr, length, null);
        // check errors
        if (err > c.MPG123_OK) {
            const e = makeMpegError(err);
            std.debug.panic("playback error: {}", .{e});
        } else if (err == c.MPG123_DONE) {
            removeTrack(track);
            continue;
        }
        // mix into output
        for (mix_buffer) |b, i| {
            buffer[i] += b;
        }
    }
}

pub fn deinitAllocator() void {
    _ = gpa.deinit();
}

pub fn initIo() !void {
    try SDL.init(.{
        .video = true,
        .audio = true,
        .timer = true,
    });
    errdefer SDL.quit();

    // initialize mpg123
    const err = c.mpg123_init();
    if (err != c.MPG123_OK) {
        return makeMpegError(err);
    }

    playing_tracks = std.ArrayList(AudioHandle).init(util.allocator);
    errdefer playing_tracks.deinit();

    var desired = std.mem.zeroes(SDL.c.SDL_AudioSpec);
    desired.freq = music.SAMPLE_RATE;
    desired.format = SDL.c.AUDIO_S16SYS;
    desired.channels = music.CHANNEL_COUNT;
    desired.samples = 512;
    desired.callback = audioCallback;
    var obtained: SDL.c.SDL_AudioSpec = undefined;
    const id = SDL.c.SDL_OpenAudioDevice(null, 0, &desired, &obtained, 0);
    if (id == 0) {
        return SDL.makeError();
    }
    errdefer SDL.c.SDL_CloseAudioDevice(id);

    mix_buffer = try util.allocator.alloc(i16, obtained.size / @sizeOf(i16));
    errdefer util.allocator.free(mix_buffer);

    SDL.c.SDL_PauseAudioDevice(id, 0);
}

pub fn deinitIo() void {
    playing_tracks.deinit();
    util.allocator.free(mix_buffer);
    SDL.quit();
    while (press_queue.pop()) |node| {
        allocator.destroy(node);
    }
}

pub fn initWebGl(major: c_int, minor: c_int) !void {
    try SDL.gl.setAttribute(.{ .context_profile_mask = .es });
    try SDL.gl.setAttribute(.{ .context_major_version = @intCast(usize, major) });
    try SDL.gl.setAttribute(.{ .context_minor_version = @intCast(usize, minor) });
}

pub fn createWindow(width: c_int, height: c_int, title: [:0]const u8) !void {
    window_object = try SDL.createWindow(
        title,
        .centered,
        .centered,
        @intCast(usize, width),
        @intCast(usize, height),
        .{ .opengl = true },
    );
    errdefer destroyWindow();
    // create a context, discard it as it is automatically set as current
    _ = try SDL.gl.createContext(window_object);
    // set vsync
    // TODO how can we set a custom frame rate?
    try SDL.gl.setSwapInterval(.vsync);
    // should not yet close
    should_close = false;
}

pub fn destroyWindow() void {
    window_object.destroy();
}

pub fn getWindowSize() struct { width: c_int, height: c_int } {
    const size = window_object.getSize();
    return .{ .width = size.width, .height = size.height };
}

const used_keys = blk: {
    var set = std.bit_set.StaticBitSet(SDL.c.SDL_NUM_SCANCODES).initEmpty();
    inline for (@typeInfo(KeyCode).Enum.fields) |field| {
        set.set(field.value);
    }
    break :blk set;
};

pub fn pollEvents() !void {
    SDL.gl.swapWindow(window_object);
    // handle events - not using wrapper to minimize overhead
    var event: SDL.c.SDL_Event = undefined;
    while (SDL.c.SDL_PollEvent(&event) != 0) switch (event.type) {
        SDL.c.SDL_WINDOWEVENT => switch (event.window.event) {
            SDL.c.SDL_WINDOWEVENT_CLOSE => should_close = true,
            SDL.c.SDL_WINDOWEVENT_SIZE_CHANGED => renderer.updateResolution(),
            else => {},
        },
        SDL.c.SDL_KEYDOWN => {
            if (used_keys.isSet(@intCast(usize, event.key.keysym.scancode))) {
                const node = try allocator.create(PressNode);
                node.data.id = @intToEnum(KeyCode, event.key.keysym.scancode);
                node.data.time = event.key.timestamp;
                press_queue.prepend(node);
            }
        },
        else => {},
    };
}

pub fn shouldClose() bool {
    return should_close;
}

pub const KeyCode = enum(c_int) {
    block = SDL.c.SDL_SCANCODE_A,
    pit = SDL.c.SDL_SCANCODE_Z,
    loop = SDL.c.SDL_SCANCODE_APOSTROPHE,
    wave = SDL.c.SDL_SCANCODE_SLASH,
    space = SDL.c.SDL_SCANCODE_SPACE,
};

pub fn getTicks() u64 {
    return SDL.getTicks64();
}

pub const AudioHandle = *c.mpg123_handle;

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

pub fn openAudio(src: [*:0]const u8) !AudioHandle {
    var err: c_int = undefined;
    const handle = c.mpg123_new(null, &err) orelse {
        return makeMpegError(err);
    };
    errdefer _ = c.mpg123_delete(handle);
    // force sample rate
    err = c.mpg123_param2(handle, c.MPG123_FORCE_RATE, music.SAMPLE_RATE, undefined);
    if (err != c.MPG123_OK) {
        return makeMpegError(err);
    }
    // open file, with settings matching SDL audio device
    err = c.mpg123_open_fixed(handle, src, music.CHANNEL_COUNT, c.MPG123_ENC_SIGNED_16);
    if (err != c.MPG123_OK) {
        return makeMpegError(err);
    }
    errdefer _ = c.mpg123_close(handle);
    // since the sample rate is forced, we don't need this info, but we
    // do need to feed it through mpg123's decoder
    err = c.mpg123_getformat(handle, null, null, null);
    if (err != c.MPG123_OK) {
        return makeMpegError(err);
    }
    return handle;
}

pub fn closeAudio(handle: AudioHandle) void {
    removeTrack(handle);
    _ = c.mpg123_close(handle);
    _ = c.mpg123_delete(handle);
}

pub fn playAudio(handle: AudioHandle) !void {
    try playing_tracks.append(handle);
}

fn samplesToMillis(samples: c.off_t) u64 {
    return (@intCast(u64, samples) * 1000) / music.SAMPLE_RATE;
}

pub fn getAudioPos(handle: AudioHandle) u64 {
    return samplesToMillis(c.mpg123_tell(handle));
}

pub fn getAudioDuration(handle: AudioHandle) !u64 {
    const samples = c.mpg123_length(handle);
    if (samples < 0) return error.UnknownTrackLength;
    return samplesToMillis(samples);
}

pub fn readFile(filename: [:0]const u8) ![]u8 {
    // open the file
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    // allocate a buffer to store the file's contents
    const size = try std.math.cast(u32, (try file.stat()).size);
    const buf = try allocator.alloc(u8, size);
    errdefer allocator.free(buf);
    // read into the buffer
    try file.reader().readNoEof(buf);
    // return the buffer
    return buf;
}

pub fn nextPressedKey() ?window.PressedKey {
    if (press_queue.pop()) |node| {
        const result = node.data;
        allocator.destroy(node);
        return result;
    }
    return null;
}
