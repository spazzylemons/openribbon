const platform = @import("../platform.zig");
const std = @import("std");
const util = @import("../util.zig");
const window = @import("../window.zig");

extern fn jsInitWebGl(major: i32, minor: i32) i32;
extern fn jsGetCanvasSize(width: *i32, height: *i32) void;
extern fn jsSetCanvasSize(width: i32, height: i32) void;
extern fn jsNextPressedKey(id_ptr: *u8, time_ptr: *u32) i32;
extern fn jsGetTicks() u64;

extern fn jsAudioOpen(src: [*:0]const u8) i32;
extern fn jsAudioReady(handle: i32) i32;
extern fn jsAudioClose(handle: i32) void;
extern fn jsAudioPlay(handle: i32) void;
extern fn jsAudioTell(handle: i32) u64;
extern fn jsAudioStat(handle: i32) i64;

extern fn jsReqOpen(filename: [*:0]const u8) i32;
extern fn jsReqReady(handle: i32) i32;
extern fn jsReqError(handle: i32) i32;
extern fn jsReqClose(handle: i32) void;
extern fn jsReqStat(handle: i32) usize;
extern fn jsReqRead(handle: i32, ptr: [*]u8) void;

/// Yield execution to the browser.
fn yield() void {
    util.c.emscripten_sleep(0);
}

pub const allocator = std.heap.c_allocator;

pub fn deinitAllocator() void {
    // no-op
}

pub fn initIo() !void {
    // no-op
}

pub fn deinitIo() void {
    // no-op
}

pub fn initWebGl(major: c_int, minor: c_int) !void {
    if (jsInitWebGl(major, minor) != 0) return error.NoWebGl;
}

pub fn createWindow(width: c_int, height: c_int, title: [:0]const u8) !void {
    // could set as webpage title?
    _ = title;
    jsSetCanvasSize(width, height);
}

pub fn destroyWindow() void {
    // no-op
}

pub fn getWindowSize() struct { width: c_int, height: c_int } {
    var width: c_int = undefined;
    var height: c_int = undefined;
    jsGetCanvasSize(&width, &height);
    return .{ .width = width, .height = height };
}

pub fn pollEvents() !void {
    // no-op
}

pub fn shouldClose() bool {
    return false;
}

pub const KeyCode = enum {
    block,
    pit,
    loop,
    wave,
    space,
};

pub fn getTicks() u64 {
    return jsGetTicks();
}

pub const AudioHandle = i32;

pub fn openAudio(src: [*:0]const u8) !AudioHandle {
    const handle = jsAudioOpen(src);
    while (jsAudioReady(handle) == 0) yield();
    return handle;
}

pub fn closeAudio(handle: AudioHandle) void {
    jsAudioClose(handle);
}

pub fn playAudio(handle: AudioHandle) !void {
    jsAudioPlay(handle);
}

pub fn getAudioPos(handle: AudioHandle) u64 {
    return jsAudioTell(handle);
}

pub fn getAudioDuration(handle: AudioHandle) !u64 {
    const result = jsAudioStat(handle);
    if (result < 0) return error.UnknownTrackLength;
    return @intCast(u64, result);
}

pub fn readFile(filename: [:0]const u8) ![]u8 {
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
}

pub fn nextPressedKey() ?window.PressedKey {
    var id: u8 = undefined;
    var time: u32 = undefined;
    if (jsNextPressedKey(&id, &time) == 0) return null;
    return window.PressedKey{ .id = @intToEnum(KeyCode, id), .time = time };
}
