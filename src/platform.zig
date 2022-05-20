const util = @import("util.zig");

pub usingnamespace if (util.is_wasm)
    @import("platform/emscripten.zig")
else
    @import("platform/native.zig");
