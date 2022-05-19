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
var track_data: ribbon.TrackData = undefined;
var track: ?ribbon.Track = undefined;

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
    // read track data
    track_data = try ribbon.TrackData.parseFile("music/fresh.json");
    errdefer track_data.deinit();
}

/// Free resources allocated by the game.
pub fn deinit() void {
    if (audio) |a| a.deinit();
    track_data.deinit();
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
    if (window.isKeyDown(.space) and audio == null) {
        audio = try music.Audio.init("music/fresh.mp3");
        track = ribbon.Track{ .data = &track_data };
        try audio.?.play();
    }
    if (audio) |a| {
        if (a.getPos() >= (try a.getDuration())) {
            // audio is finished, stop playing it
            a.deinit();
            audio = null;
        } else {
            try track.?.draw(a.getPos());
        }
    }
    // update window
    window.update();
}
