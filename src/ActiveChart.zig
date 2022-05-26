const Chart = @import("Chart.zig");
const font = @import("font.zig");
const music = @import("music.zig");
const renderer = @import("renderer.zig");
const ribbon = @import("ribbon.zig");
const std = @import("std");
const util = @import("util.zig");
const window = @import("window.zig");
const zlm = @import("zlm");

const ActiveChart = @This();

/// chart to reference for timings
chart: *const Chart,
/// Track playing audio
audio: music.Audio,
/// Index into obstacles to start at when drawing
draw_cursor: usize = 0,
/// Index into obstacles for checking inputs
play_cursor: usize = 0,
/// Set to false when the music starts
in_countdown: bool = true,
/// Last game timestamp seen by this chart
last_time: u64 = 0,
/// Current position in song
song_pos: i64,
/// Last song timestamp seen by this chart
last_timestamp: i64,
/// Maximum value to add to last timestamp, if no song updates beyond this,
/// stall song position waiting for song to continue playing
max_prediction: i64,
/// last time a key was pressed, for input cooldown preventing spamming keys
last_input_time: ?u32 = null,
/// points earned
score: u32 = 0,

pub fn init(chart: *const Chart, track_filename: [*:0]const u8) !ActiveChart {
    const audio = try music.Audio.init(track_filename);
    errdefer audio.deinit();

    const countdown_length = @floatToInt(i64, 240000 / chart.bpm);

    return ActiveChart{
        .chart = chart,
        .audio = audio,
        .song_pos = -countdown_length,
        .last_timestamp = -countdown_length,
        .max_prediction = countdown_length,
    };
}

pub fn deinit(self: ActiveChart) void {
    self.audio.deinit();
}

fn getOffset(self: ActiveChart, offset: usize) ?Chart.Obstacle {
    const index = offset + self.draw_cursor;
    if (index >= self.chart.obstacles.len) return null;
    return self.chart.obstacles[index];
}

const BPM_ADJUST = (1000 * 60) / 4;
const DRAW_RADIUS = 32;

pub fn render(self: *ActiveChart) !void {
    var list = std.ArrayList(ribbon.Obstacle).init(util.allocator);
    defer list.deinit();
    var offset: usize = 0;
    while (self.getOffset(offset)) |obstacle| {
        const unscaled_relative = @intToFloat(f32, obstacle.time) - @intToFloat(f32, self.song_pos);
        const relative = (unscaled_relative * self.chart.bpm / BPM_ADJUST) + ribbon.PLAYER_POS;
        if (relative < -DRAW_RADIUS) {
            self.draw_cursor += 1;
            continue;
        }
        if (relative <= DRAW_RADIUS) {
            try list.append(.{
                .type = obstacle.type,
                .pos = relative,
            });
        }
        offset += 1;
    }

    ribbon.render(list.items);
}

fn setSongPos(self: *ActiveChart, pos: i64) void {
    // mustn't go backwards in the song
    if (pos > self.song_pos) self.song_pos = pos;
}

fn predictPos(self: *ActiveChart) void {
    // find out time elapsed this frame
    const new = window.getTicks();
    const diff = new - self.last_time;
    self.last_time = new;
    // don't set song pos further than max predicted timestamp
    const new_pos = self.song_pos + @intCast(i64, diff);
    const max_pos = self.last_timestamp + self.max_prediction;
    self.setSongPos(std.math.min(new_pos, max_pos));
}

/// Update the current song position to be in sync with the playing audio.
fn updatePos(self: *ActiveChart) !void {
    if (self.in_countdown) {
        self.predictPos();
        if (self.song_pos >= 0) {
            try self.audio.play();
            self.in_countdown = false;
        }
    } else {
        // check if timestamp is further than last timestamp
        const pos = @intCast(i64, self.audio.getPos());
        if (pos > self.last_timestamp) {
            // difference between timestamps determines how long we may predict
            self.max_prediction = pos - self.last_timestamp;
            self.last_timestamp = pos;
            self.setSongPos(pos);
        } else {
            self.predictPos();
        }
    }
}

fn currentObstacle(self: ActiveChart) ?Chart.Obstacle {
    if (self.play_cursor >= self.chart.obstacles.len) return null;
    return self.chart.obstacles[self.play_cursor];
}

pub fn handleKeyPress(self: *ActiveChart, key: window.PressedKey) void {
    // minimum time between inputs is currently a quarter of a beat
    if (self.last_input_time) |last| {
        if (key.time - last < @floatToInt(u32, 15000 / self.chart.bpm)) {
            // don't handle the input them
            return;
        }
    }
    self.last_input_time = key.time;
    // determine when the key was pressed in the song
    const press_time = self.song_pos - @intCast(i64, window.getTicks() - key.time);
    // get obstacle to check
    if (self.currentObstacle()) |ob| {
        // check if correct key and within leniance
        if (ob.key() == key.id and ob.minTime() <= press_time and press_time <= ob.maxTime()) {
            self.score += 1;
            self.play_cursor += 1;
        }
    }
}

pub fn update(self: *ActiveChart) !void {
    try self.updatePos();
    // check upcoming obstacles
    while (self.currentObstacle()) |ob| {
        // check if we've passed the obstacle
        if (self.song_pos > ob.maxTime()) {
            self.play_cursor += 1;
        } else {
            break;
        }
    }
    renderer.reseed();
    renderer.setColor(zlm.vec3(1, 1, 1));
    renderer.setWobble(0.05);
    font.print("SCORE: {}", .{self.score}, zlm.vec3(-12, 6, 0));
}
