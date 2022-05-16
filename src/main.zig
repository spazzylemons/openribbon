const builtin = @import("builtin");
const game = @import("game.zig");
const std = @import("std");
const window = @import("window.zig");

const c = @cImport({
    @cInclude("emscripten.h");
});

/// Run game loop for Emscripten.
fn emscriptenLoop() callconv(.C) void {
    game.loop();
}

/// Initialize game for Emscripten.
fn emscriptenInit(unused: ?*anyopaque) callconv(.C) void {
    // no arguments are passed
    _ = unused;
    // initialize game
    game.init() catch |err| {
        std.debug.panic("initialization error: {}", .{err});
    };
    // set the main loop
    c.emscripten_set_main_loop(emscriptenLoop, 0, 0);
}

/// Schedule the initialization function for Emscripten.
fn emscriptenMain() callconv(.C) c_int {
    // don't run init yet - we want to be in a sync context
    c.emscripten_async_call(emscriptenInit, null, 0);
    // done here
    return 0;
}

// select additional methods based on wasm
pub usingnamespace if (builtin.target.isWasm())
    struct {
        // javascript log implementation
        extern fn jsLogImpl(
            level: [*:0]const u8,
            scope: ?[*:0]const u8,
            message: [*:0]const u8,
        ) void;

        /// log implementation using emscripten to print to console
        pub fn log(
            comptime level: std.log.Level,
            comptime scope: @TypeOf(.EnumLiteral),
            comptime format: []const u8,
            args: anytype,
        ) void {
            // buffer to print to
            var buffer: [2048]u8 = undefined;
            var impl = std.heap.FixedBufferAllocator.init(&buffer);
            // print to console
            jsLogImpl(
                // select console method to use
                switch (level) {
                    .err => "error",
                    .warn => "warn",
                    .info => "info",
                    .debug => "debug",
                },
                if (scope == .default) null else @tagName(scope),
                (std.fmt.allocPrintZ(impl.allocator(), format, args) catch return).ptr,
            );
        }

        /// javascript panic implementation
        extern fn jsPanicImpl(ptr: [*]const u8, len: usize) noreturn;

        /// panic implementation using emscripten to print to console
        pub fn panic(message: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
            // discard it; we'll never get it anyway
            _ = error_return_trace;
            // show the error in the DOM
            jsPanicImpl(message.ptr, message.len);
        }
    }
else
    struct {
        pub fn main() !void {
            try game.init();
            defer game.deinit();

            while (!window.shouldClose()) {
                game.loop();
            }
        }
    };

comptime {
    if (builtin.target.isWasm()) {
        @export(emscriptenMain, .{ .name = "emscriptenMain" });
    }
}
