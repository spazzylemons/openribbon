const oron = @import("oron.zig");
const ribbon = @import("ribbon.zig");
const std = @import("std");
const util = @import("util.zig");
const window = @import("window.zig");

const Chart = @This();

const LENIANCE = 100;

pub const Obstacle = struct {
    time: i64,
    type: ribbon.ObstacleType,

    /// The minimum time that the obstacle may be cleared.
    pub fn minTime(self: Obstacle) i64 {
        return self.time - LENIANCE;
    }

    /// The maximum time thta the obstacle may be cleared.
    pub fn maxTime(self: Obstacle) i64 {
        return self.time + LENIANCE;
    }

    /// The key that must be pressed to clear the obstacle.
    pub fn key(self: Obstacle) window.KeyCode {
        return switch (self.type) {
            .Block => .block,
            .Pit => .pit,
            .Loop => .loop,
            .Wave => .wave,
        };
    }
};

bpm: f32,
obstacles: []Obstacle,

const obstacle_map = std.ComptimeStringMap(ribbon.ObstacleType, .{
    .{ "b", .Block },
    .{ "p", .Pit },
    .{ "l", .Loop },
    .{ "w", .Wave },
});

fn obCompare(ctx: void, lhs: Obstacle, rhs: Obstacle) bool {
    _ = ctx;
    return lhs.time < rhs.time;
}

pub fn load(filename: [:0]const u8) !Chart {
    const source = try util.readFile(filename);
    defer util.allocator.free(source);

    var chart = try oron.parse(source);
    defer chart.deinit();

    const bpm = try chart.getAttr("bpm", .Float);
    if (bpm <= 0) return error.InvalidChart;

    var obstacles = std.ArrayList(Obstacle).init(util.allocator);
    defer obstacles.deinit();

    var min_time: i64 = -1;

    for (chart.children.items) |child| {
        if (std.mem.eql(u8, child.tag, "obstacle")) {
            const time = try child.getAttr("time", .Integer);
            if (time <= min_time) {
                return error.InvalidChart;
            }
            min_time = time;
            const ty = obstacle_map.get(try child.getAttr("type", .String)) orelse return error.InvalidChart;
            try obstacles.append(.{ .time = time, .type = ty });
        }
    }

    return Chart{
        .bpm = bpm,
        .obstacles = obstacles.toOwnedSlice(),
    };
}

pub fn deinit(self: Chart) void {
    util.allocator.free(self.obstacles);
}
