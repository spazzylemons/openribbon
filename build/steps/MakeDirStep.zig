//! Create a directory.

const std = @import("std");

const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const GeneratedFile = std.build.GeneratedFile;
const Step = std.build.Step;

const MakeDirStep = @This();

/// Build step
step: Step,
/// Directory name
name: []const u8,
/// Output directory
dir: GeneratedFile,

pub fn create(
    b: *Builder,
    name: []const u8,
) !*MakeDirStep {
    const step_name = b.fmt("create directory {s}", .{name});
    const self = try b.allocator.create(MakeDirStep);
    self.* = .{
        .step = Step.init(.custom, step_name, b.allocator, make),
        .name = b.dupe(name),
        .dir = GeneratedFile{ .step = &self.step },
    };
    return self;
}

fn make(step: *Step) anyerror!void {
    const self = @fieldParentPtr(MakeDirStep, "step", step);

    std.fs.cwd().makePath(self.name) catch |err| switch (err) {
        // don't care if it already exists
        error.PathAlreadyExists => {},
        else => |e| return e,
    };

    self.dir.path = self.name;
}

pub fn directory(self: *const MakeDirStep) FileSource {
    return FileSource{ .generated = &self.dir };
}
