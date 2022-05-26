const Chart = @import("Chart.zig");
const renderer = @import("renderer.zig");
const std = @import("std");
const util = @import("util.zig");
const zlm = @import("zlm");

const glyph_files = blk: {
    var files = [_]?[]const u8{null} ** 256;

    // TODO create more of font
    var i = 0x41;
    while (i <= 0x5a) : (i += 1) {
        const filename = std.fmt.comptimePrint("assets/font/{x:0>2}.bin", .{i});
        files[i] = @embedFile(filename);
    }
    i = 0x30;
    while (i <= 0x39) : (i += 1) {
        const filename = std.fmt.comptimePrint("assets/font/{x:0>2}.bin", .{i});
        files[i] = @embedFile(filename);
    }

    break :blk files;
};

var glyphs = [_]?renderer.Model{null} ** 256;

pub fn init() !void {
    errdefer deinit();

    for (glyph_files) |file, i| {
        if (file) |f| {
            var stream = std.io.fixedBufferStream(f);
            glyphs[i] = try renderer.Model.load(stream.reader());
        }
    }
}

pub fn deinit() void {
    for (glyphs) |glyph| {
        if (glyph) |g| g.deinit();
    }
}

const WriterContext = struct {
    const Error = error{};

    location: zlm.Vec3,

    fn write(self: *WriterContext, buf: []const u8) Error!usize {
        for (buf) |c| {
            if (glyphs[c]) |glyph| {
                glyph.render(self.location);
            }
            self.location.x += 0.75;
        }
        return buf.len;
    }

    const Writer = std.io.Writer(*WriterContext, Error, write);

    fn writer(self: *WriterContext) Writer {
        return .{ .context = self };
    }
};

pub fn print(comptime fmt: []const u8, args: anytype, location: zlm.Vec3) void {
    var ctx = WriterContext{ .location = location };
    std.fmt.format(ctx.writer(), fmt, args) catch unreachable;
}
