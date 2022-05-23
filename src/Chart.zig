const oron = @import("oron.zig");
const ribbon = @import("ribbon.zig");
const std = @import("std");
const util = @import("util.zig");

const Chart = @This();

pub const Obstacle = struct {
    time: u64,
    type: ribbon.ObstacleType,
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
    var obstacles = std.ArrayList(Obstacle).init(util.allocator);
    defer obstacles.deinit();

    for (chart.children.items) |child| {
        if (std.mem.eql(u8, child.tag, "obstacle")) {
            const time = try std.math.cast(u64, try child.getAttr("time", .Integer));
            const ty = obstacle_map.get(try child.getAttr("type", .String)) orelse return error.InvalidObstacle;
            try obstacles.append(.{ .time = time, .type = ty });
        }
    }

    std.sort.sort(Obstacle, obstacles.items, {}, obCompare);

    return Chart{
        .bpm = bpm,
        .obstacles = obstacles.toOwnedSlice(),
    };
}

pub fn deinit(self: Chart) void {
    util.allocator.free(self.obstacles);
}
