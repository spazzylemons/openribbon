const builtin = @import("builtin");
const renderer = @import("renderer.zig");
const std = @import("std");
const window = @import("window.zig");
const zlm = @import("zlm");

/// Initialize the game.
pub fn init() !void {
    // window context
    try window.init();
    errdefer window.deinit();
    // rendering context
    try renderer.init();
    errdefer renderer.deinit();
}

/// Free resources allocated by the game.
pub fn deinit() void {
    renderer.deinit();
    window.deinit();
}

/// Run the game loop for one render frame.
pub fn loop() void {
    // clear the screen
    renderer.clear();
    // set up camera
    renderer.setCamera(zlm.vec3(0, 5, -10), zlm.vec3(0, 0, 0));
    // draw a square on the floor
    renderer.drawLineLoop(&.{
        zlm.vec3(-1, 0, -1),
        zlm.vec3(1, 0, -1),
        zlm.vec3(1, 0, 1),
        zlm.vec3(-1, 0, 1),
    }, zlm.vec3(1, 1, 1), zlm.Vec3.zero, zlm.Vec3.zero, 0.125);
    // update window
    window.update();
}
