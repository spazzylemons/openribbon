const builtin = @import("builtin");
const std = @import("std");

const c = @cImport({
    @cInclude("emscripten.h");
});

/// Run game loop for Emscripten.
fn emscriptenLoop() callconv(.C) void {
    // nothing at the moment
}

/// Initialize the game and set the loop callback for Emscripten.
fn emscriptenMain() callconv(.C) c_int {
    // set the main loop
    c.emscripten_set_main_loop(emscriptenLoop, 0, 0);
    // done here
    return 0;
}

// select additional methods based on wasm
pub usingnamespace if (builtin.target.isWasm())
    struct {
        /// common code for logging to reduce code size
        fn logCommon(
            em_level: c_int,
            level_text: [*:0]const u8,
            scope: [*:0]const u8,
            message: [*:0]const u8,
        ) void {
            c.emscripten_log(em_level, "%s%s: %s", level_text, scope, message);
        }

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
            logCommon(
                switch (level) {
                    .err => c.EM_LOG_ERROR,
                    .warn => c.EM_LOG_WARN,
                    .info => c.EM_LOG_INFO,
                    .debug => c.EM_LOG_DEBUG,
                },
                @as([:0]const u8, level.asText()).ptr,
                @as([:0]const u8, if (scope == .default) "" else "(" ++ @tagName(scope) ++ ")").ptr,
                (std.fmt.allocPrintZ(impl.allocator(), format, args) catch return).ptr,
            );
        }

        /// panic implementation using emscripten to print to console
        pub fn panic(message: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
            // discard it; we'll never get it anyway
            _ = error_return_trace;
            // console.error the panic message
            c.emscripten_log(c.EM_LOG_ERROR, "panic: %.*s", @intCast(c_int, message.len), message.ptr);
            // raise emscripten unreachable trap
            asm volatile ("unreachable");
            unreachable;
        }
    }
else
    struct {
        pub fn main() !void {
            // nothing at the moment
        }
    };

comptime {
    if (builtin.target.isWasm()) {
        @export(emscriptenMain, .{ .name = "emscriptenMain" });
    }
}
