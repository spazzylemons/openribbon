//! Rename symbols in a WebAssembly object created by LLVM.

const std = @import("std");

const renameSymbols = @import("../rename_symbols.zig").renameSymbols;

const Builder = std.build.Builder;
const FileSource = std.build.FileSource;
const Step = std.build.Step;

const RenameSymbolsStep = @This();

step: Step,
b: *Builder,
obj: FileSource,

pub fn create(b: *Builder, obj: FileSource) !*RenameSymbolsStep {
    const step_name = b.fmt("rename symbols in {s}", .{obj.getDisplayName()});
    const self = try b.allocator.create(RenameSymbolsStep);
    self.* = .{
        .step = Step.init(.custom, step_name, b.allocator, make),
        .b = b,
        .obj = obj.dupe(b),
    };
    obj.addStepDependencies(&self.step);
    return self;
}

fn make(step: *Step) anyerror!void {
    const self = @fieldParentPtr(RenameSymbolsStep, "step", step);
    try renameSymbols(self.obj.getPath(self.b), self.b.allocator);
}
