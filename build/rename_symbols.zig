//! Renames local symbols to avoid Emscripten issues.
//! In the Emscripten process, one function that reads symbols from the object
//1 file parses in such a way that Zig symbols containing ':' characters can
//! cause Emscripten to crash. To avoid this, we go through LLVM's linking table
//! in the generated object file, and rename all local symbols to generic names.
//! All global symbols are untouched to allow imports and exports to link
//! properly.

const std = @import("std");

/// The possible types of a WASM symbol.
const SymbolType = enum(u32) {
    Function = 0,
    Data = 1,
    Global = 2,
    Section = 3,
    Tag = 4,
    Table = 5,

    _,
};

/// The possible flags of a WASM symbol/
const Flags = struct {
    const weak = 1 << 0;
    const local = 1 << 1;
    const hidden = 1 << 2;
    const undef = 1 << 4;
    const exported = 1 << 5;
    const explicit = 1 << 6;
    const no_strip = 1 << 7;
    const tls = 1 << 8;
};

/// A section in a WASM file.
const Section = struct {
    /// The array of data in the section.
    array: std.ArrayList(u8),
    /// The read index.
    i: usize,

    /// Create a section.
    fn init(allocator: std.mem.Allocator) Section {
        return .{
            .array = std.ArrayList(u8).init(allocator),
            .i = 0,
        };
    }

    /// Free section resources.
    fn deinit(self: Section) void {
        self.array.deinit();
    }

    /// Return true if data remains to be read.
    fn hasData(self: Section) bool {
        return self.i < self.array.items.len;
    }

    /// Read n bytes, if available.
    fn read(self: *Section, n: usize) ![]const u8 {
        const start = self.i;
        const end = start + n;
        if (end > self.array.items.len) return error.Overflow;
        self.i = end;
        return self.array.items[start..end];
    }

    /// Read one byte.
    fn readByte(self: *Section) !u8 {
        return (try self.read(1))[0];
    }

    /// Read an unsigned LEB128 encoded integer.
    fn readInt(self: *Section) !usize {
        var result: usize = 0;
        var shift: usize = 0;
        while (true) {
            const byte = try self.readByte();
            const value = @as(usize, (byte & 0x7f));
            // check bounds only when necessary. LLVM may unnecessarily pad values
            if (value != 0) {
                const casted_shift = try std.math.cast(std.math.Log2Int(usize), shift);
                const shifted_value = try std.math.shlExact(usize, value, casted_shift);
                result |= shifted_value;
            }
            // check continuation
            if ((byte & 0x80) == 0) return result;
            // add to shift
            shift += 7;
        }
    }

    /// Read a WASM name object.
    fn readName(self: *Section) ![]const u8 {
        const length = try self.readInt();
        return try self.read(length);
    }

    /// Read a subsection.
    fn readSection(self: *Section, id: *usize) !Section {
        id.* = try self.readInt();
        const data = try self.readName();

        var new_section = Section.init(self.array.allocator);
        errdefer new_section.deinit();
        try new_section.write(data);

        return new_section;
    }

    /// Write data.
    fn write(self: *Section, data: []const u8) !void {
        try self.array.appendSlice(data);
    }

    /// Write a byte.
    fn writeByte(self: *Section, byte: u8) !void {
        try self.array.append(byte);
    }

    /// Write an unsigned LEB128 encoded integer.
    fn writeInt(self: *Section, n: usize) !void {
        var value = n;
        while (true) {
            const byte: u8 = @truncate(u7, value);
            value >>= 7;
            if (value != 0) {
                try self.writeByte(byte | 0x80);
            } else {
                try self.writeByte(byte);
                return;
            }
        }
    }

    /// Write a WASM name.
    fn writeName(self: *Section, n: []const u8) !void {
        try self.writeInt(n.len);
        try self.array.appendSlice(n);
    }

    /// Write a subsection.
    fn writeSection(self: *Section, id: usize, new_section: Section) !void {
        try self.writeInt(id);
        try self.writeName(new_section.array.items);
    }

    /// Copy an int from another section.
    fn transferInt(self: *Section, other: *Section) !void {
        try self.writeInt(try other.readInt());
    }

    /// Copy a name from another section.
    fn transferName(self: *Section, other: *Section) !void {
        try self.writeName(try other.readName());
    }

    /// Copy the remaining contents of another section.
    fn transferRemaining(self: *Section, other: Section) !void {
        try self.write(other.array.items[other.i..]);
    }
};

// four bytes magic, four bytes version
const MAGIC: [8]u8 = "\x00asm\x01\x00\x00\x00".*;

fn readFile(file_name: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const size = try std.math.cast(usize, (try file.stat()).size);

    const buffer = try allocator.alloc(u8, size);
    errdefer allocator.free(buffer);

    try file.reader().readNoEof(buffer);

    return buffer;
}

pub fn renameSymbols(file_name: []const u8, allocator: std.mem.Allocator) !void {
    var src_root = Section.init(allocator);
    defer src_root.deinit();

    {
        const src_contents = try readFile(file_name, allocator);
        defer allocator.free(src_contents);

        if (src_contents.len < 8 or !std.mem.eql(u8, src_contents[0..8], &MAGIC)) {
            return error.UnsupportedFile;
        }

        // write contents of source file to root
        try src_root.write(src_contents[8..]);
    }

    var dst_root = Section.init(allocator);
    defer dst_root.deinit();

    while (src_root.hasData()) {
        var id: usize = undefined;
        var section = try src_root.readSection(&id);
        defer section.deinit();

        if (id == 0 and std.mem.eql(u8, try section.readName(), "linking")) {
            var new_linking = Section.init(allocator);
            defer new_linking.deinit();

            const version = try section.readInt();

            // we've written this for version 2, if LLVM changes the format it
            // may need a rewrite
            if (version != 2) {
                return error.UnsupportedFile;
            }

            if (section.hasData()) {
                var linking_type: usize = undefined;
                var old_linking = try section.readSection(&linking_type);
                defer old_linking.deinit();

                const num_symbols = try old_linking.readInt();
                try new_linking.writeInt(num_symbols);

                var local_counter: usize = 0;

                var symbols_processed: usize = 0;
                while (symbols_processed < num_symbols) : (symbols_processed += 1) {
                    const kind = try old_linking.readByte();
                    try new_linking.writeByte(kind);

                    const flags = try old_linking.readInt();
                    try new_linking.writeInt(flags);

                    switch (@intToEnum(SymbolType, kind)) {
                        .Function, .Global, .Tag, .Table => {
                            try new_linking.transferInt(&old_linking);

                            if ((flags & Flags.explicit) != 0 or (flags & Flags.undef) == 0) {
                                const name = try old_linking.readName();
                                if ((flags & Flags.local) == 0) {
                                    // name is not local, should use as-is
                                    try new_linking.writeName(name);
                                } else {
                                    // name is a zig identifier which may have invalid chars
                                    const new_name = try std.fmt.allocPrint(allocator, ".zig_local_{}", .{local_counter});
                                    defer allocator.free(new_name);
                                    local_counter += 1;
                                    try new_linking.writeName(new_name);
                                }
                            }
                        },

                        .Data => {
                            try new_linking.transferName(&old_linking);

                            if ((flags & Flags.undef) == 0) {
                                try new_linking.transferInt(&old_linking);
                                try new_linking.transferInt(&old_linking);
                                try new_linking.transferInt(&old_linking);
                            }
                        },

                        .Section => {
                            try new_linking.transferInt(&old_linking);
                        },

                        else => return error.UnsupportedFile,
                    }
                }

                var new_section = Section.init(allocator);
                errdefer new_section.deinit();

                try new_section.writeName("linking");
                try new_section.writeInt(version);
                try new_section.writeSection(linking_type, new_linking);

                // remaining contents we can keep
                try new_section.transferRemaining(section);

                // load new section
                section.deinit();
                section = new_section;
            }
        }

        try dst_root.writeSection(id, section);
    }

    const file = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();

    try file.writeAll(&MAGIC);
    try file.writeAll(dst_root.array.items);
}
