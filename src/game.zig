const builtin = @import("builtin");
const music = @import("music.zig");
const ribbon = @import("ribbon.zig");
const renderer = @import("renderer.zig");
const std = @import("std");
const window = @import("window.zig");
const zlm = @import("zlm");

/// allocator implementation for non-wasm targets
var gpa = std.heap.GeneralPurposeAllocator(.{}){};

/// Get the game's allocator.
pub fn allocator() std.mem.Allocator {
    if (builtin.target.isWasm()) {
        // wasm does not support mmap
        return std.heap.c_allocator;
    } else {
        // other targets should
        return gpa.allocator();
    }
}

fn deinitAllocator() void {
    if (!builtin.target.isWasm()) {
        // another wasm specialization
        _ = gpa.deinit();
    }
}

var audio: ?music.Audio = null;

/// Initialize the game.
pub fn init() !void {
    errdefer deinitAllocator();
    // window context
    try window.init();
    errdefer window.deinit();
    // rendering context
    try renderer.init();
    errdefer renderer.deinit();
    // ribbon
    try ribbon.init();
    errdefer ribbon.deinit();
}

/// Free resources allocated by the game.
pub fn deinit() void {
    if (audio) |a| a.deinit();
    ribbon.deinit();
    renderer.deinit();
    window.deinit();
    deinitAllocator();
}

/// Run the game loop for one render frame.
pub fn loop() !void {
    // clear the screen
    renderer.clear();
    // set up camera
    renderer.setCamera(zlm.vec3(0, 0, -16), zlm.vec3(0, 0, 0));
    // draw some obstacles
    ribbon.render(&.{
        ribbon.Obstacle{ .type = .Block, .pos = -7.0 },
        ribbon.Obstacle{ .type = .Pit, .pos = -3.0 },
        ribbon.Obstacle{ .type = .Loop, .pos = 1.0 },
        ribbon.Obstacle{ .type = .Wave, .pos = 5.0 },
    });
    if (window.isKeyDown(.space) and audio == null) {
        audio = try music.Audio.init("music/fresh.mp3");
        try audio.?.play();
    }
    // update window
    window.update();
}
