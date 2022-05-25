const ActiveChart = @import("ActiveChart.zig");
const Chart = @import("Chart.zig");
const ribbon = @import("ribbon.zig");
const renderer = @import("renderer.zig");
const util = @import("util.zig");
const window = @import("window.zig");
const zlm = @import("zlm");

var chart: Chart = undefined;
var active: ?ActiveChart = null;

/// Initialize the game.
pub fn init() !void {
    errdefer util.deinit();
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
    chart = try Chart.load("music/fresh.oron");
    errdefer chart.deinit();
}

/// Free resources allocated by the game.
pub fn deinit() void {
    if (active) |a| a.deinit();
    chart.deinit();
    ribbon.deinit();
    renderer.deinit();
    window.deinit();
    util.deinit();
}

/// Run the game loop for one render frame.
pub fn loop() !void {
    // process key events
    while (window.nextPressedKey()) |key| {
        if (active) |*a| a.handleKeyPress(key);
    }
    // clear the screen
    renderer.clear();
    // set up camera
    renderer.setCamera(zlm.vec3(0, 0, -16), zlm.vec3(0, 0, 0));
    // draw some obstacles
    if (window.isKeyDown(.space) and active == null) {
        active = try ActiveChart.init(&chart, "music/fresh.mp3");
    }
    if (active) |*a| {
        if (a.song_pos >= (try a.audio.getDuration())) {
            // audio is finished, stop playing it
            a.deinit();
            active = null;
        } else {
            try a.update();
            try a.render();
        }
    }
    // update window
    try window.update();
}
