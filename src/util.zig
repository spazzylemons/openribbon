const builtin = @import("builtin");
const std = @import("std");

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

extern fn jsReqOpen(filename: [*:0]const u8) i32;
extern fn jsReqReady(handle: i32) i32;
extern fn jsReqError(handle: i32) i32;
extern fn jsReqClose(handle: i32) void;
extern fn jsReqStat(handle: i32) usize;
extern fn jsReqRead(handle: i32, ptr: [*]u8) void;

/// allocator implementation for non-wasm targets
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Free resources allocated by the utilities.
pub fn deinit() void {
    if (!is_wasm) _ = gpa.deinit();
}

/// The global game allocator.
pub const allocator = if (is_wasm)
    std.heap.c_allocator
else
    gpa.allocator();

/// Read the contents of a file.
pub fn readFile(filename: [:0]const u8) ![]u8 {
    if (is_wasm) {
        // perform a fetch, wait for result
        const handle = jsReqOpen(filename.ptr);
        while (jsReqReady(handle) == 0) yield();
        defer jsReqClose(handle);
        // check for failure
        if (jsReqError(handle) != 0) return error.FetchError;
        // allocate a buffer for the result
        const size = jsReqStat(handle);
        const buf = try allocator.alloc(u8, size);
        // copy data to the buffer
        jsReqRead(handle, buf.ptr);
        // done here
        return buf;
    } else {
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
}

/// Yield execution to the browser.
pub fn yield() void {
    c.emscripten_sleep(0);
}
