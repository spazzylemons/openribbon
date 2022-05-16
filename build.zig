const deps = @import("deps.zig");
const Sdk = @import("SDL.zig/Sdk.zig");
const std = @import("std");

const EmccStep = @import("build/steps/EmccStep.zig");
const MakeDirStep = @import("build/steps/MakeDirStep.zig");
const RenameSymbolsStep = @import("build/steps/RenameSymbolsStep.zig");

pub fn build(b: *std.build.Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const is_wasm = target.getCpuArch().isWasm();

    const exe = if (is_wasm)
        b.addObject("rhythm", "src/main.zig")
    else
        b.addExecutable("rhythm", "src/main.zig");
    // set target and build mode
    exe.setTarget(target);
    exe.setBuildMode(mode);
    // link libc as we use it for SDL2 and OpenGL
    exe.linkLibC();
    // add managed packages
    deps.addAllTo(exe);
    // add the SDL2 wrapper package
    const sdk = Sdk.init(b);
    exe.addPackage(sdk.getWrapperPackage("sdl2"));
    // more wasm-specific processing
    if (is_wasm) {
        // get sysroot location
        const sysroot = b.sysroot orelse {
            std.log.err("please use --sysroot to set the EMSDK sysroot", .{});
            return error.NoSysroot;
        };
        // add Emscripten include path
        exe.addIncludeDir(b.pathJoin(&.{ sysroot, "include" }));
        // rename the symbols
        const rename = try RenameSymbolsStep.create(b, exe.getOutputSource());
        // create the output directory
        const mkdir = try MakeDirStep.create(b, b.pathJoin(&.{ b.install_path, "web" }));
        // compile the executable
        const compile = try EmccStep.create(
            b,
            mkdir.directory(),
            exe.getOutputSource(),
            "index.html",
            std.build.FileSource.relative("src/emscripten.c"),
            std.build.FileSource.relative("src/shell.html"),
            std.build.FileSource.relative("src/library.js"),
        );
        // compilation depends on renaming symbols
        compile.step.dependOn(&rename.step);
        // install step depends on compilation
        b.getInstallStep().dependOn(&compile.step);
    } else {
        // dynamically link SDL2
        sdk.link(exe, .dynamic);
        // link OpenGL
        exe.linkSystemLibrary("GL");
        // if compiling to native target, also allow running it
        if (target.isNative()) {
            const run_cmd = exe.run();
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step("run", "Run the app");
            run_step.dependOn(&run_cmd.step);
        }
        // build and install the app
        exe.install();
    }
}
