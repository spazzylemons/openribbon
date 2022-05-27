const ActiveChart = @import("ActiveChart.zig");
const Chart = @import("Chart.zig");
const font = @import("font.zig");
const ribbon = @import("ribbon.zig");
const renderer = @import("renderer.zig");
const util = @import("util.zig");
const window = @import("window.zig");
const zlm = @import("zlm");

var chart: Chart = undefined;
var active: ?ActiveChart = null;

const COMPONENTS = [_]type{ util, window, renderer, ribbon, font };

fn initComponents(comptime components: []const type) !void {
    if (components.len > 0) {
        const c = components[0];
        // try to initialize, if needed
        if (@hasDecl(c, "init")) {
            try c.init();
        }
        // initialize the next components, and deinitialize the current on failure
        initComponents(components[1..]) catch |err| {
            c.deinit();
            return err;
        };
    }
}

fn deinitComponents(comptime components: []const type) void {
    if (components.len > 0) {
        components[components.len - 1].deinit();
        deinitComponents(components[0 .. components.len - 1]);
    }
}

/// Initialize the game.
pub fn init() !void {
    try initComponents(&COMPONENTS);
    // read track data
    chart = try Chart.load("music/fresh.oron");
    errdefer chart.deinit();
    // set up the camera
    renderer.setCamera(zlm.vec3(0, 0, -16), zlm.vec3(0, 0, 0));
}

/// Free resources allocated by the game.
pub fn deinit() void {
    if (active) |a| a.deinit();
    chart.deinit();
    deinitComponents(&COMPONENTS);
}

/// Run the game loop for one render frame.
pub fn loop() !void {
    // process key events
    while (window.nextPressedKey()) |key| {
        if (active) |*a| {
            a.handleKeyPress(key);
        } else if (key.id == .space) {
            active = try ActiveChart.init(&chart, "music/fresh.mp3");
        }
    }
    renderer.begin(0.05);
    // run chart
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
