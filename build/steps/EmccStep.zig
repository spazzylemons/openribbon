//! Link a program using Emscripten.

const std = @import("std");

const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const Step = std.build.Step;

const EmccStep = @This();

/// Build step
step: Step,
/// Builder
b: *Builder,
/// Output directory
dir: FileSource,
/// Output webpage name
name: []const u8,
/// Object to link
obj: FileSource,
/// Entry point C file
entry: FileSource,
/// Shell webpage
shell: FileSource,

pub fn create(
    b: *Builder,
    dir: FileSource,
    obj: FileSource,
    name: []const u8,
    entry: FileSource,
    shell: FileSource,
) !*EmccStep {
    const step_name = b.fmt("compile {s} with emscripten", .{dir.getDisplayName()});
    const self = try b.allocator.create(EmccStep);
    self.* = .{
        .step = Step.init(.custom, step_name, b.allocator, make),
        .b = b,
        .dir = dir,
        .obj = obj,
        .name = b.dupe(name),
        .entry = entry,
        .shell = shell,
    };
    dir.addStepDependencies(&self.step);
    obj.addStepDependencies(&self.step);
    entry.addStepDependencies(&self.step);
    shell.addStepDependencies(&self.step);
    return self;
}

fn make(step: *Step) anyerror!void {
    const self = @fieldParentPtr(EmccStep, "step", step);

    const emsdk = std.os.getenv("EMSDK") orelse {
        std.log.err("please set and export the $EMSDK environment variable", .{});
        return error.NoEmsdk;
    };

    var child = std.ChildProcess.init(&.{
        // invoke emscripten compiler
        self.b.pathJoin(&.{ emsdk, "upstream/emscripten/emcc" }),
        // pass in entry point
        self.entry.getPath(self.b),
        // add zig object file
        self.obj.getPath(self.b),
        // optimize size
        "-Os",
        // run closure compiler to optimize javascript
        "--closure",
        "1",
        // output to web folder in zig-out
        "-o",
        self.b.pathJoin(&.{ self.dir.getPath(self.b), self.name }),
        // use shell webpage
        "--shell-file",
        self.shell.getPath(self.b),
        // link WebGL
        "-lGL",
        // link SDL2
        "-sUSE_SDL=2",
        // require WebGL2
        "-sMAX_WEBGL_VERSION=2",
        "-sMIN_WEBGL_VERSION=2",
    }, self.b.allocator);

    const term = try child.spawnAndWait();
    if (term != .Exited or term.Exited != 0) {
        return error.UnexpectedExitCode;
    }
}
