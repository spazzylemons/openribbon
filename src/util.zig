const builtin = @import("builtin");
const game = @import("game.zig");
const std = @import("std");

const c = @cImport({
    if (builtin.target.isWasm()) {
        @cInclude("emscripten.h");
    }
});

extern fn jsMakeRequest(filename: [*:0]const u8) i32;
extern fn jsGetRequestReady(handle: i32) i32;
extern fn jsGetRequestFailed(handle: i32) i32;
extern fn jsCloseRequest(handle: i32) void;
extern fn jsGetRequestSize(handle: i32) usize;
extern fn jsCopyRequestContent(handle: i32, ptr: [*]u8) void;

/// Read the contents of a file.
pub fn readFile(filename: [:0]const u8) ![]u8 {
    if (comptime builtin.target.isWasm()) {
        // perform a fetch, wait for result
        const handle = jsMakeRequest(filename.ptr);
        while (jsGetRequestReady(handle) == 0) c.emscripten_sleep(0);
        defer jsCloseRequest(handle);
        // check for failure
        if (jsGetRequestFailed(handle) != 0) return error.FetchError;
        // allocate a buffer for the result
        const size = jsGetRequestSize(handle);
        const buf = try game.allocator().alloc(u8, size);
        // copy data to the buffer
        jsCopyRequestContent(handle, buf.ptr);
        // done here
        return buf;
    } else {
        // open the file
        const file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();
        // allocate a buffer to store the file's contents
        const size = try std.math.cast(u32, (try file.stat()).size);
        const buf = try game.allocator().alloc(u8, size);
        errdefer game.allocator().free(buf);
        // read into the buffer
        try file.reader().readNoEof(buf);
        // return the buffer
        return buf;
    }
}
