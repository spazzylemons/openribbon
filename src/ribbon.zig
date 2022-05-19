const renderer = @import("renderer.zig");
const std = @import("std");
const util = @import("util.zig");
const zlm = @import("zlm");

const ObstacleModel = struct {
    model: renderer.Model,
    start_x: f32,
    end_x: f32,

    fn loadCommon(model: renderer.Model) !ObstacleModel {
        errdefer model.deinit(util.allocator);
        // dynamically calculate endpoints
        var start_x = std.math.inf_f32;
        var end_x = -std.math.inf_f32;
        for (model.vertices) |vertex| {
            if (vertex.y == 0) {
                if (vertex.x < start_x) start_x = vertex.x;
                if (vertex.x > end_x) end_x = vertex.x;
            }
        }
        // ensure we found them
        if (start_x == std.math.inf_f32 or end_x == -std.math.inf_f32) {
            return error.InvalidObstacleModel;
        }
        // package endpoints with model
        return ObstacleModel{
            .model = model,
            .start_x = start_x,
            .end_x = end_x,
        };
    }

    fn load(comptime src: []const u8) !ObstacleModel {
        return loadCommon(try renderer.Model.loadEmbedded(util.allocator, src));
    }

    fn deinit(self: ObstacleModel) void {
        self.model.deinit(util.allocator);
    }
};

var block_model: ObstacleModel = undefined;
var pit_model: ObstacleModel = undefined;
var loop_model: ObstacleModel = undefined;
var wave_model: ObstacleModel = undefined;

const WOBBLE = 0.05;

pub fn init() !void {
    block_model = try ObstacleModel.load("ribbon/b.bin");
    errdefer block_model.deinit();
    pit_model = try ObstacleModel.load("ribbon/p.bin");
    errdefer pit_model.deinit();
    loop_model = try ObstacleModel.load("ribbon/l.bin");
    errdefer loop_model.deinit();
    wave_model = try ObstacleModel.load("ribbon/w.bin");
    errdefer wave_model.deinit();
}

pub fn deinit() void {
    block_model.deinit();
    pit_model.deinit();
    loop_model.deinit();
    wave_model.deinit();
}

pub const ObstacleType = enum { Block, Pit, Loop, Wave };

pub const Obstacle = struct {
    type: ObstacleType,
    pos: f32,
};

fn renderLine(from: f32, to: f32) void {
    renderer.drawLines(
        &.{ zlm.vec3(from, 0, 0), zlm.vec3(to, 0, 0) },
        zlm.Vec3.zero,
        zlm.Vec3.zero,
    );
}

/// Render obstacles. Must be in sorted order from left to right.
pub fn render(obstacles: []const Obstacle) void {
    // set seed for entire obstacle group
    renderer.reseed();
    // set color for ribbon
    renderer.setColor(zlm.vec3(1, 1, 1));
    // set wobble for ribbon
    renderer.setWobble(WOBBLE);
    // draw each obstacle
    var last_pos: f32 = -256;
    for (obstacles) |obstacle| {
        // select the obstacle
        const model = switch (obstacle.type) {
            .Block => block_model,
            .Pit => pit_model,
            .Loop => loop_model,
            .Wave => wave_model,
        };
        // draw line connecting obstacle to ribbon
        renderLine(last_pos, obstacle.pos + model.start_x);
        // set next line location
        last_pos = obstacle.pos + model.end_x;
        // draw the obstacle itself
        model.model.render(zlm.vec3(obstacle.pos, 0, 0), zlm.Vec3.zero);
    }
    // finish drawing line
    renderLine(last_pos, 256);
}

pub const TrackData = struct {
    const ObstacleEvent = struct {
        time: u64,
        type: ObstacleType,
    };

    obstacles: []ObstacleEvent,

    fn obCompare(ctx: void, lhs: ObstacleEvent, rhs: ObstacleEvent) bool {
        _ = ctx;
        return lhs.time < rhs.time;
    }

    pub fn parse(source: []const u8) !TrackData {
        // TODO custom file format
        var tokens = std.json.TokenStream.init(source);
        const self = try std.json.parse(TrackData, &tokens, .{
            .allocator = util.allocator,
        });
        errdefer self.deinit();
        // obstacle timings should be sorted
        std.sort.sort(ObstacleEvent, self.obstacles, {}, obCompare);
        // everything is good
        return self;
    }

    pub fn parseFile(filename: [:0]const u8) !TrackData {
        const contents = try util.readFile(filename);
        defer util.allocator.free(contents);
        return try parse(contents);
    }

    pub fn deinit(self: TrackData) void {
        util.allocator.free(self.obstacles);
    }
};

pub const Track = struct {
    data: *TrackData,
    cursor: usize = 0,

    fn getOffset(self: Track, offset: usize) ?TrackData.ObstacleEvent {
        const index = offset + self.cursor;
        if (index >= self.data.obstacles.len) return null;
        return self.data.obstacles[index];
    }

    pub fn draw(self: *Track, pos: u64) !void {
        var list = std.ArrayList(Obstacle).init(util.allocator);
        defer list.deinit();
        // TODO less hardcoded stuff
        var offset: usize = 0;
        while (self.getOffset(offset)) |obstacle| {
            const relative = if (obstacle.time < pos)
                @intToFloat(f32, pos - obstacle.time) / -50.0
            else
                @intToFloat(f32, obstacle.time - pos) / 50.0;
            if (relative < -32.0) {
                self.cursor += 1;
                continue;
            }
            if (relative <= 32.0) {
                try list.append(.{
                    .type = obstacle.type,
                    .pos = relative,
                });
            }
            offset += 1;
        }

        render(list.items);
    }
};
