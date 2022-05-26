const builtin = @import("builtin");
const platform = @import("platform.zig");

pub const is_wasm = builtin.target.isWasm();

pub const c = @cImport({
    @cInclude("GLES3/gl3.h");
    if (builtin.target.isWasm()) {
        @cInclude("emscripten.h");
        @cInclude("emscripten/html5.h");
    } else {
        @cInclude("mpg123.h");
    }
});

/// Free resources allocated by the utilities.
pub fn deinit() void {
    platform.deinitAllocator();
}

/// The global game allocator.
pub const allocator = platform.allocator;

/// Read the contents of a file.
pub const readFile = platform.readFile;
