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

fn obCompare(ctx: void, lhs: Obstacle, rhs: Obstacle) bool {
    _ = ctx;
    return lhs.time < rhs.time;
}

pub fn load(filename: [:0]const u8) !Chart {
    const source = try util.readFile(filename);
    defer util.allocator.free(source);

    var tokens = std.json.TokenStream.init(source);

    const self = try std.json.parse(Chart, &tokens, .{
        .allocator = util.allocator,
    });
    errdefer self.deinit();

    std.sort.sort(Obstacle, self.obstacles, {}, obCompare);
    return self;
}

pub fn deinit(self: Chart) void {
    util.allocator.free(self.obstacles);
}
