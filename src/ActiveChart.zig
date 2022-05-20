const Chart = @import("Chart.zig");
const music = @import("music.zig");
const ribbon = @import("ribbon.zig");
const SDL = @import("sdl2");
const std = @import("std");
const util = @import("util.zig");
const window = @import("window.zig");

const ActiveChart = @This();

chart: *const Chart,
draw_cursor: usize = 0,
play_cursor: usize = 0,

fn getOffset(self: ActiveChart, offset: usize) ?Chart.Obstacle {
    const index = offset + self.draw_cursor;
    if (index >= self.chart.obstacles.len) return null;
    return self.chart.obstacles[index];
}

const BPM_ADJUST = (1000 * 60) / 4;
const DRAW_RADIUS = 32;

pub fn render(self: *ActiveChart, pos: i64) !void {
    var list = std.ArrayList(ribbon.Obstacle).init(util.allocator);
    defer list.deinit();
    // TODO less hardcoded stuff
    var offset: usize = 0;
    while (self.getOffset(offset)) |obstacle| {
        const unscaled_relative = @intToFloat(f32, obstacle.time) - @intToFloat(f32, pos);
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

const LENIANCE = 100;

pub fn update(self: *ActiveChart, pos: i64) void {
    while (true) {
        if (self.play_cursor >= self.chart.obstacles.len) return;
        const next_obstacle = self.chart.obstacles[self.play_cursor];
        if (next_obstacle.time > pos + LENIANCE) return;
        if (next_obstacle.time < pos - LENIANCE) {
            std.log.info("miss", .{});
            self.play_cursor += 1;
            continue;
        }
        const key: SDL.Scancode = switch (next_obstacle.type) {
            .Block => .a,
            .Pit => .z,
            .Loop => .apostrophe,
            .Wave => .slash,
        };
        // TODO limit inputs so that you can't just spam every button press
        if (window.isKeyDown(key)) {
            std.log.info("hit", .{});
            self.play_cursor += 1;
        }
        break;
    }
}
