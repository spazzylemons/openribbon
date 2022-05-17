const builtin = @import("builtin");

const is_wasm = builtin.target.isWasm();

const c = @cImport({
    if (is_wasm) {
        @cInclude("emscripten.h");
    } else {
        @cInclude("SDL2/SDL_mixer.h");
    }
});

pub const Audio = if (is_wasm)
    struct {
        const Self = @This();

        handle: i32,

        extern fn jsNewAudio(src: [*:0]const u8) i32;

        extern fn jsIsAudioReady(handle: i32) i32;

        pub fn init(src: [*:0]const u8) !Self {
            const handle = jsNewAudio(src);
            if (handle == -1) return error.FailedToLoadAudio;
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
    }
else
    struct {
        const Self = @This();

        // zig was getting a bit too eagev to evaluate this type
        handle: *if (is_wasm) anyopaque else c.Mix_Music,

        pub fn init(src: [*:0]const u8) !Self {
            const handle = c.Mix_LoadMUS(src) orelse return error.FailedToLoadAudio;
            return Self{ .handle = handle };
        }

        pub fn deinit(self: Self) void {
            c.Mix_FreeMusic(self.handle);
        }

        pub fn play(self: Self) !void {
            if (c.Mix_PlayMusic(self.handle, 1) == -1) {
                return error.FailedToPlayAudio;
            }
        }
    };
