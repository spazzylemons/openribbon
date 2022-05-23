//! OpenRibbon Object Notation

const std = @import("std");
const util = @import("util.zig");

pub const Scalar = union(enum) {
    Boolean: bool,
    Integer: i64,
    Float: f32,
    String: []const u8,

    pub fn deinit(self: Scalar) void {
        if (self == .String) util.allocator.free(self.String);
    }
};

pub const ScalarTag = std.meta.Tag(Scalar);

// save wasm binary size by using js for float parsing
extern fn jsParseFloat(ptr: [*]const u8, len: usize) f32;

fn parseFloat(input: []const u8) f32 {
    if (util.is_wasm) {
        return jsParseFloat(input.ptr, input.len);
    } else {
        return std.fmt.parseFloat(f32, input) catch unreachable;
    }
}

fn addInt(x: i64, y: i64) !i64 {
    return std.math.add(i64, x, y);
}

fn subInt(x: i64, y: i64) !i64 {
    return std.math.sub(i64, x, y);
}

pub const Object = struct {
    /// The tag of this object, i.e. what kind of object this is
    tag: []const u8,
    /// The scalar attributes of this object
    attrs: std.StringHashMapUnmanaged(Scalar) = .{},
    /// The objects this object contains.
    children: std.ArrayListUnmanaged(Object) = .{},

    fn init(tag: []const u8) !Object {
        return Object{ .tag = try util.allocator.dupe(u8, tag) };
    }

    /// Get an attribute, verifying its type but not casting it.
    pub fn getAttrRuntime(self: Object, name: []const u8, ty: ScalarTag) !Scalar {
        // try to access the attribute
        const attr = self.attrs.get(name) orelse return error.MissingAttribute;
        // verify the type before returning
        if (attr != ty) return error.IncorrectAttributeType;
        return attr;
    }

    /// Get an attribute, verifying its type but not casting it, if it exists.
    pub fn getAttrOptRuntime(self: Object, name: []const u8, ty: ScalarTag) !?Scalar {
        if (self.getAttrRuntime(name, ty)) |value| {
            return value;
        } else |err| switch (err) {
            error.MissingAttribute => return null,
            else => |e| return e,
        }
    }

    fn scalarField(comptime ty: ScalarTag) std.builtin.TypeInfo.UnionField {
        return @typeInfo(Scalar).Union.fields[@enumToInt(ty)];
    }

    fn ScalarType(comptime ty: ScalarTag) type {
        return scalarField(ty).field_type;
    }

    /// Get an attribute, verifying its type and casting it.
    pub fn getAttr(self: Object, name: []const u8, comptime ty: ScalarTag) !ScalarType(ty) {
        const result = try self.getAttrRuntime(name, ty);
        return @field(result, scalarField(ty).name);
    }

    /// Get an attribute, verifying its type and casting it, if it exists.
    pub fn getAttrOpt(self: Object, name: []const u8, comptime ty: ScalarTag) !?ScalarType(ty) {
        const result = (try self.getAttrOptRuntime(name, ty)) orelse return null;
        return @field(result, scalarField(ty).name);
    }

    pub fn deinit(self: *Object) void {
        util.allocator.free(self.tag);
        var it = self.attrs.iterator();
        while (it.next()) |entry| {
            util.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.attrs.deinit(util.allocator);
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit(util.allocator);
    }
};

const TokenType = enum(u8) {
    Ident,
    String,
    Integer,
    Float,
    Comment,
    EOF,

    Open = '[',
    Close = ']',
    Equal = '=',
    False = 'F',
    True = 'T',
};

const Token = struct { value: []const u8, type: TokenType };

const Tokenizer = struct {
    /// remaining data to tokenize
    remaining: []const u8,

    fn atEof(self: Tokenizer) bool {
        return self.remaining.len == 0;
    }

    fn current(self: Tokenizer) ?u8 {
        if (self.atEof()) return null;
        return self.remaining[0];
    }

    fn advanceUnchecked(self: *Tokenizer) void {
        self.remaining = self.remaining[1..];
    }

    fn advance(self: *Tokenizer) !void {
        if (self.atEof()) return error.SyntaxError;
        self.advanceUnchecked();
    }

    fn eat(self: *Tokenizer, c: u8) bool {
        if (self.current()) |i| {
            if (i == c) {
                self.advanceUnchecked();
                return true;
            }
        }
        return false;
    }

    fn eatDigit(self: *Tokenizer) bool {
        if (self.current()) |c| {
            if ('0' <= c and c <= '9') {
                self.advanceUnchecked();
                return true;
            }
        }
        return false;
    }

    fn requireInt(self: *Tokenizer) !void {
        if (!self.eat('0')) {
            if (!self.eatDigit()) return error.SyntaxError;
            while (self.eatDigit()) {}
        }
    }

    /// returns null on comment tokens
    fn nextType(self: *Tokenizer) !TokenType {
        if (self.current()) |c| switch (c) {
            '[', ']', '=', 'T', 'F' => {
                self.advanceUnchecked();
                if (c == '[' and self.eat('[')) {
                    // double braces indicates a comment
                    while (true) {
                        if (self.eat(']') and self.eat(']')) break;
                        try self.advance();
                    }
                    return .Comment;
                }
                return @intToEnum(TokenType, c);
            },
            '"' => {
                self.advanceUnchecked();
                while (!self.eat('"')) {
                    // TODO escape codes
                    try self.advance();
                }
                return .String;
            },
            '-', '0'...'9' => {
                // negative sign
                _ = self.eat('-');
                // integer part
                try self.requireInt();
                // fraction part
                if (self.eat('.')) {
                    try self.requireInt();
                    // exponent part
                    if (self.eat('e')) {
                        _ = self.eat('-');
                        try self.requireInt();
                    }
                    return .Float;
                }
                return .Integer;
            },
            'a'...'z' => {
                while (self.current()) |i| switch (i) {
                    '0'...'9', 'a'...'z', '-' => self.advanceUnchecked(),
                    else => break,
                };
                return .Ident;
            },
            else => return error.SyntaxError,
        } else return .EOF;
    }

    fn next(self: *Tokenizer) !Token {
        while (true) {
            // skip whitespace
            while (self.current()) |i| switch (i) {
                ' ', '\n', '\r', '\t' => self.advanceUnchecked(),
                else => break,
            };
            // get token start position
            const start = self.remaining.ptr;
            // get token type
            const tt = try self.nextType();
            // skip comments
            if (tt == .Comment) continue;
            // get token length
            const diff = @ptrToInt(self.remaining.ptr) - @ptrToInt(start);
            // build slice around token
            const value = start[0..diff];
            // return token
            return Token{ .value = value, .type = tt };
        }
    }
};

const Parser = struct {
    const MAX_DEPTH = 100;

    const Error = error{
        OutOfMemory,
        Overflow,
        NestedTooDeep,
        SyntaxError,
    };

    /// tokenizer to feed tokens from
    tokenizer: Tokenizer,
    /// current token
    current: Token,
    /// depth counter to avoid stack overflow on deeply nested input
    depth: u16 = 0,

    fn init(src: []const u8) !Parser {
        var tokenizer = Tokenizer{ .remaining = src };
        const current = try tokenizer.next();
        return Parser{
            .current = current,
            .tokenizer = tokenizer,
        };
    }

    fn take(self: *Parser) !Token {
        const current = self.current;
        try self.advance();
        return current;
    }

    fn advance(self: *Parser) !void {
        self.current = try self.tokenizer.next();
    }

    fn eat(self: *Parser, tt: TokenType) !bool {
        if (self.current.type == tt) {
            try self.advance();
            return true;
        }
        return false;
    }

    fn require(self: *Parser, tt: TokenType) ![]const u8 {
        if (self.current.type != tt) return error.SyntaxError;
        const result = self.current.value;
        try self.advance();
        return result;
    }

    fn parseScalar(self: *Parser) !Scalar {
        const token = try self.take();
        switch (token.type) {
            .Integer => {
                var result: i64 = 0;
                var op = addInt;
                var digits = token.value;
                if (digits[0] == '-') {
                    op = subInt;
                    digits = digits[1..];
                }
                for (digits) |d| {
                    result = try std.math.mul(i64, result, 10);
                    result = try op(result, d - '0');
                }
                return Scalar{ .Integer = result };
            },

            .Float => {
                const result = parseFloat(token.value);
                return Scalar{ .Float = result };
            },

            .True => return Scalar{ .Boolean = true },

            .False => return Scalar{ .Boolean = false },

            .String => {
                // TODO escape codes
                const result = try util.allocator.dupe(u8, token.value[1 .. token.value.len - 1]);
                return Scalar{ .String = result };
            },

            else => return error.SyntaxError,
        }
    }

    fn parseObjectElement(self: *Parser, object: *Object) Error!void {
        const name = try self.require(.Ident);

        if (try self.eat(.Equal)) {
            // create space for new element
            try object.attrs.ensureUnusedCapacity(util.allocator, 1);
            // create owned copy of identifier
            const dupe = try util.allocator.dupe(u8, name);
            errdefer util.allocator.free(dupe);
            // parse value and store attribute
            object.attrs.putAssumeCapacity(dupe, try self.parseScalar());
        } else {
            // create space for new element
            try object.children.ensureUnusedCapacity(util.allocator, 1);
            // parse child and store
            object.children.appendAssumeCapacity(try self.parseObject(name));
        }
    }

    fn parseObjectElements(self: *Parser, object: *Object, close: TokenType) Error!void {
        while (!try self.eat(close)) {
            try self.parseObjectElement(object);
        }
    }

    fn parseObject(self: *Parser, tag: []const u8) Error!Object {
        if (self.depth == MAX_DEPTH) return error.NestedTooDeep;
        self.depth += 1;

        var object = try Object.init(tag);
        errdefer object.deinit();

        if (try self.eat(.Open)) {
            try self.parseObjectElements(&object, .Close);
        }

        self.depth -= 1;
        return object;
    }

    fn parseRoot(self: *Parser) !Object {
        var object = try Object.init("root");
        errdefer object.deinit();

        try self.parseObjectElements(&object, .EOF);

        return object;
    }
};

pub fn parse(src: []const u8) !Object {
    var parser = try Parser.init(src);
    return try parser.parseRoot();
}
