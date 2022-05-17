//! Copy the music folder into the web folder.

const std = @import("std");

const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const GeneratedFile = std.build.GeneratedFile;
const Step = std.build.Step;

const CopyMusicFolderStep = @This();

/// Build step
step: Step,
/// Builder
b: *Builder,
/// Music directory
src: FileSource,
/// Target to copy music folder inside
dst: FileSource,

pub fn create(
    b: *Builder,
    src: FileSource,
    dst: FileSource,
) !*CopyMusicFolderStep {
    const self = try b.allocator.create(CopyMusicFolderStep);
    self.* = .{
        .step = Step.init(.custom, "copy music folder", b.allocator, make),
        .b = b,
        .src = src,
        .dst = dst,
    };
    src.addStepDependencies(&self.step);
    dst.addStepDependencies(&self.step);
    return self;
}

fn make(step: *Step) anyerror!void {
    const self = @fieldParentPtr(CopyMusicFolderStep, "step", step);

    const src_path = self.src.getPath(self.b);
    const base = std.fs.path.basename(src_path);

    var src = try std.fs.cwd().openDir(src_path, .{ .iterate = true });
    defer src.close();

    var dst = blk: {
        var dst_base = try std.fs.cwd().openDir(self.dst.getPath(self.b), .{});
        defer dst_base.close();

        dst_base.makeDir(base) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => |e| return e,
        };
        break :blk try dst_base.openDir(base, .{});
    };
    defer dst.close();

    var it = src.iterate();
    while (try it.next()) |entry| {
        if (entry.kind == .File) {
            try src.copyFile(entry.name, dst, entry.name, .{});
        }
    }
}
