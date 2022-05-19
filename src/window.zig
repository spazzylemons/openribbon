//! Abstractions for user interface components.

const music = @import("music.zig");
const renderer = @import("renderer.zig");
const SDL = @import("sdl2");
const util = @import("util.zig");

var window: SDL.Window = undefined;
var should_close: bool = undefined;

pub const WIDTH = 640;
pub const HEIGHT = 360;
pub const TITLE = "rhythm";

const c = util.c;

const EmHtml5Error = error{
    Deferred,
    NotSupported,
    FailedNotDeferred,
    InvalidTarget,
    UnknownTarget,
    InvalidParameter,
    Failed,
    NoData,
};

fn emHtml5Error(code: c_int) EmHtml5Error {
    return switch (code) {
        c.EMSCRIPTEN_RESULT_DEFERRED => error.Deferred,
        c.EMSCRIPTEN_RESULT_NOT_SUPPORTED => error.NotSupported,
        c.EMSCRIPTEN_RESULT_FAILED_NOT_DEFERRED => error.FailedNotDeferred,
        c.EMSCRIPTEN_RESULT_INVALID_TARGET => error.InvalidTarget,
        c.EMSCRIPTEN_RESULT_UNKNOWN_TARGET => error.UnknownTarget,
        c.EMSCRIPTEN_RESULT_INVALID_PARAM => error.InvalidParameter,
        c.EMSCRIPTEN_RESULT_FAILED => error.Failed,
        c.EMSCRIPTEN_RESULT_NO_DATA => error.NoData,
        else => unreachable,
    };
}

/// Light wrapper for WASM WebGL code, for readability.
const WebGLContext = struct {
    handle: c_int,

    fn init(id: [:0]const u8, attrs: Attrs) !WebGLContext {
        const handle = c.emscripten_webgl_create_context(id.ptr, &attrs.data);
        if (handle < 0) return emHtml5Error(-handle);
        return WebGLContext{ .handle = handle };
    }

    fn deinit(self: WebGLContext) void {
        _ = c.emscripten_webgl_destroy_context(self.handle);
    }

    fn makeCurrent(self: WebGLContext) !void {
        const result = c.emscripten_webgl_make_context_current(self.handle);
        if (result != c.EMSCRIPTEN_RESULT_SUCCESS) return emHtml5Error(result);
    }

    const Attrs = struct {
        data: c.EmscriptenWebGLContextAttributes,

        fn init() Attrs {
            var data: c.EmscriptenWebGLContextAttributes = undefined;
            c.emscripten_webgl_init_context_attributes(&data);
            return .{ .data = data };
        }
    };
};

/// Initialize the window.
pub fn init() !void {
    // initialize SDL
    try SDL.init(.{
        .video = true,
        .audio = !util.is_wasm,
    });
    errdefer SDL.quit();
    // expecting GLES3
    try SDL.gl.setAttribute(.{ .context_profile_mask = .es });
    try SDL.gl.setAttribute(.{ .context_major_version = 2 });
    try SDL.gl.setAttribute(.{ .context_minor_version = 0 });
    // create window for SDL
    window = try SDL.createWindow(
        TITLE,
        .centered,
        .centered,
        WIDTH,
        HEIGHT,
        .{ .opengl = true },
    );
    errdefer window.destroy();
    // initialize music subsystem
    try music.init();
    errdefer music.deinit();
    // should not yet close
    should_close = false;
    // wasm specialization
    if (util.is_wasm) {
        // set attributes
        var attrs = WebGLContext.Attrs.init();
        // create a context
        const context = try WebGLContext.init("canvas", attrs);
        errdefer context.deinit();
        // make it current
        try context.makeCurrent();
    } else {
        // create a context, discard it as it is automatically set as current
        _ = try SDL.gl.createContext(window);
        // set vsync
        // TODO how can we set a custom frame rate?
        try SDL.gl.setSwapInterval(.vsync);
    }
}

/// Destroy the window.
pub fn deinit() void {
    // close audio resources
    music.deinit();
    // close SDL and free related resources
    SDL.quit();
}

/// Get the dimensions of the window.
pub fn getResolution() struct { width: c_int, height: c_int } {
    const size = window.getSize();
    // update renderer with new resolution
    return .{
        .width = size.width,
        .height = size.height,
    };
}

/// Update the window.
pub fn update() void {
    // swap buffers
    SDL.gl.swapWindow(window);
    // handle events
    while (SDL.pollEvent()) |event| switch (event) {
        .window => |e| {
            switch (e.type) {
                // when the window is requested to close, set should_close
                .close => should_close = true,
                .size_changed => renderer.updateResolution(),
                else => {},
            }
        },

        else => {},
    };
}

/// Check if a key is pressed.
pub fn isKeyDown(key: SDL.Scancode) bool {
    // check keyboard state
    return SDL.getKeyboardState().isPressed(key);
}

/// Return true if the window has been requested to close.
pub fn shouldClose() bool {
    return should_close;
}
