const Chart = @import("Chart.zig");
const music = @import("music.zig");
const ribbon = @import("ribbon.zig");
const std = @import("std");
const util = @import("util.zig");

const ActiveChart = @This();

chart: *const Chart,
cursor: usize = 0,

fn getOffset(self: ActiveChart, offset: usize) ?Chart.Obstacle {
    const index = offset + self.cursor;
    if (index >= self.chart.obstacles.len) return null;
    return self.chart.obstacles[index];
}

const DRAW_SCALE = 50;
const DRAW_RADIUS = 32;

pub fn render(self: *ActiveChart, pos: i64) !void {
    var list = std.ArrayList(ribbon.Obstacle).init(util.allocator);
    defer list.deinit();
    // TODO less hardcoded stuff
    var offset: usize = 0;
    while (self.getOffset(offset)) |obstacle| {
        const relative = ((@intToFloat(f32, obstacle.time) - @intToFloat(f32, pos)) / DRAW_SCALE) + ribbon.PLAYER_POS;
        if (relative < -DRAW_RADIUS) {
            self.cursor += 1;
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
