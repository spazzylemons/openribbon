const ActiveChart = @import("ActiveChart.zig");
const Chart = @import("Chart.zig");
const music = @import("music.zig");
const ribbon = @import("ribbon.zig");
const renderer = @import("renderer.zig");
const util = @import("util.zig");
const window = @import("window.zig");
const zlm = @import("zlm");

var audio: ?music.Audio = null;
var chart: Chart = undefined;
var active: ActiveChart = undefined;
var time_to_start: ?u64 = undefined;

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
    chart = try Chart.load("music/fresh.json");
    errdefer chart.deinit();
}

/// Free resources allocated by the game.
pub fn deinit() void {
    if (audio) |a| a.deinit();
    chart.deinit();
    ribbon.deinit();
    renderer.deinit();
    window.deinit();
    util.deinit();
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
        active = ActiveChart{ .chart = &chart };
        // give a second before the song starts
        time_to_start = window.getTicks() + 1000;
    }
    if (audio) |a| {
        var game_time: ?i64 = null;
        if (time_to_start) |t| {
            const now = window.getTicks();
            if (now < t) {
                game_time = -@intCast(i64, t - now);
            } else {
                time_to_start = null;
                try a.play();
            }
        }
        if (time_to_start == null) {
            if (a.getPos() >= (try a.getDuration())) {
                // audio is finished, stop playing it
                a.deinit();
                audio = null;
            } else {
                game_time = @intCast(i64, a.getPos());
            }
        }
        if (game_time) |gt| {
            active.update(gt);
            try active.render(gt);
        }
    }
    // update window
    window.update();
}
