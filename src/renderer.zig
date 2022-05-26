const std = @import("std");
const util = @import("util.zig");
const window = @import("window.zig");
const zlm = @import("zlm");

const c = util.c;

const FOV = 70.0;
const NEAR = 0.01;
const FAR = 1000.0;

var program: c.GLuint = undefined;
var vao: c.GLuint = undefined;
var vbo: c.GLuint = undefined;

var params: struct {
    model: c.GLint,
    view: c.GLint,
    projection: c.GLint,

    color: c.GLint,

    seed: c.GLint,
    scale: c.GLint,
} = undefined;

var rng = std.rand.DefaultPrng.init(1);

fn checkFailure(
    object: c.GLuint,
    status_type: c.GLenum,
    getStatus: fn (c.GLuint, c.GLenum, [*c]c.GLint) callconv(.C) void,
    getLog: fn (c.GLuint, c.GLsizei, [*c]c.GLsizei, [*c]c.GLchar) callconv(.C) void,
) !void {
    var status: c.GLint = undefined;
    getStatus(object, status_type, &status);
    if (status == 0) {
        // buffer to write errors to
        var buffer: [512]u8 = undefined;
        var length: c.GLsizei = undefined;
        getLog(object, buffer.len, &length, &buffer);
        std.log.err("glsl errors:\n{s}", .{buffer[0..@intCast(usize, length)]});
        return error.ShaderError;
    }
}

fn createShader(kind: c.GLenum, src: []const u8) !c.GLuint {
    const shader = c.glCreateShader(kind);
    errdefer c.glDeleteShader(shader);

    var len = @intCast(c.GLint, src.len);
    var ptr = src.ptr;
    c.glShaderSource(shader, 1, &ptr, &len);
    c.glCompileShader(shader);

    try checkFailure(
        shader,
        c.GL_COMPILE_STATUS,
        c.glGetShaderiv,
        c.glGetShaderInfoLog,
    );

    return shader;
}

fn createProgram() !void {
    const vert_shader = try createShader(c.GL_VERTEX_SHADER, @embedFile("vert.glsl"));
    defer c.glDeleteShader(vert_shader);

    const frag_shader = try createShader(c.GL_FRAGMENT_SHADER, @embedFile("frag.glsl"));
    defer c.glDeleteShader(frag_shader);

    program = c.glCreateProgram();
    errdefer c.glDeleteProgram(program);

    c.glAttachShader(program, vert_shader);
    c.glAttachShader(program, frag_shader);
    c.glLinkProgram(program);

    try checkFailure(
        program,
        c.GL_LINK_STATUS,
        c.glGetProgramiv,
        c.glGetProgramInfoLog,
    );
}

/// Initialize the renderer. Expects the window to be initialized.
pub fn init() !void {
    c.glEnable(c.GL_DEPTH_TEST);

    try createProgram();
    errdefer c.glDeleteProgram(program);

    c.glUseProgram(program);

    inline for (@typeInfo(@TypeOf(params)).Struct.fields) |field| {
        const name = (comptime field.name[0..field.name.len].*) ++ [0:0]u8{};
        const location = c.glGetUniformLocation(program, name[0.. :0]);
        if (location < 0) {
            return error.ShaderError;
        }
        @field(params, field.name) = location;
    }

    c.glGenVertexArrays(1, &vao);
    c.glBindVertexArray(vao);

    c.glGenBuffers(1, &vbo);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);

    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, @sizeOf(zlm.Vec3), null);
    c.glEnableVertexAttribArray(0);

    updateResolution();
}

/// Free the renderer's resources.
pub fn deinit() void {
    c.glDeleteVertexArrays(1, &vao);
    c.glDeleteBuffers(1, &vbo);
    c.glDeleteProgram(program);
}

fn uniformMat4(param: c.GLint, matrix: zlm.Mat4) void {
    c.glUniformMatrix4fv(param, 1, c.GL_FALSE, @ptrCast(*const f32, &matrix.fields));
}

/// Update the renderer's resolution to match the window size.
pub fn updateResolution() void {
    const size = window.getResolution();
    if (size.width == 0 or size.height == 0) {
        // who knows, maybe some window manager will allow it
        @panic("window has a zero dimension");
    }
    // update viewport to fill screen
    c.glViewport(0, 0, size.width, size.height);
    const ratio = @intToFloat(f32, size.width) / @intToFloat(f32, size.height);
    const projection = zlm.Mat4.createPerspective(FOV, ratio, NEAR, FAR);
    uniformMat4(params.projection, projection);
}

/// Clear the screen.
pub fn clear() void {
    c.glClearColor(0.0, 0.0, 0.0, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
}

/// Set the camera's position and target.
pub fn setCamera(position: zlm.Vec3, target: zlm.Vec3) void {
    const view = zlm.Mat4.createLookAt(position, target, zlm.Vec3.unitY);
    uniformMat4(params.view, view);
}

/// Reseed the wobble parameter.
pub fn reseed() void {
    c.glUniform1f(params.seed, rng.random().float(f32));
}

pub fn drawLines(vertices: []const zlm.Vec3, offset: zlm.Vec3) void {
    // rotation matrices
    // const rot_x = zlm.Mat4.createAngleAxis(zlm.Vec3.unitX, rotation.x);
    // const rot_y = zlm.Mat4.createAngleAxis(zlm.Vec3.unitY, rotation.y);
    // const rot_z = zlm.Mat4.createAngleAxis(zlm.Vec3.unitZ, rotation.z);
    // rot_x.mul(rot_y).mul(rot_z);
    // model matrix
    const model = zlm.Mat4.createTranslation(offset);
    // send model matrix to gpu
    uniformMat4(params.model, model);
    // send vertices to gpu
    c.glBufferData(
        c.GL_ARRAY_BUFFER,
        @intCast(c.GLsizei, @sizeOf(zlm.Vec3) * vertices.len),
        vertices.ptr,
        c.GL_STATIC_DRAW,
    );
    c.glDrawArrays(c.GL_LINES, 0, @intCast(c.GLsizei, vertices.len));
}

/// Set the drawing color.
pub fn setColor(color: zlm.Vec3) void {
    c.glUniform3f(params.color, color.x, color.y, color.z);
}

/// Set the drawing wobble.
pub fn setWobble(wobble: f32) void {
    c.glUniform1f(params.scale, wobble);
}

/// A 3D model.
pub const Model = struct {
    /// The vertices in the model.
    vertices: []const zlm.Vec3,

    fn readFixedPoint(reader: anytype) !f32 {
        const int = try reader.readIntBig(i16);
        return @intToFloat(f32, int) / 256;
    }

    /// Load a model from a reader. Checks if the model is valid while loading.
    pub fn load(reader: anytype) !Model {
        var vertices = try util.allocator.alloc(zlm.Vec3, try reader.readByte());
        defer util.allocator.free(vertices);

        for (vertices) |*vertex| {
            vertex.x = try readFixedPoint(reader);
            vertex.y = try readFixedPoint(reader);
            vertex.z = try readFixedPoint(reader);
        }

        var model_vertices = std.ArrayList(zlm.Vec3).init(util.allocator);
        defer model_vertices.deinit();

        var group_count = try reader.readByte();
        while (group_count > 0) : (group_count -= 1) {
            var group_length = @as(u16, try reader.readByte()) + 1;
            try model_vertices.ensureUnusedCapacity(2 * group_length);

            var last = try reader.readByte();
            if (last >= vertices.len) return error.Overflow;
            while (group_length > 0) : (group_length -= 1) {
                const current = try reader.readByte();
                if (current >= vertices.len) return error.Overflow;
                model_vertices.appendAssumeCapacity(vertices[last]);
                model_vertices.appendAssumeCapacity(vertices[current]);
                last = current;
            }
        }

        return Model{ .vertices = model_vertices.toOwnedSlice() };
    }

    /// Load the model from an embedded file.
    pub fn loadEmbedded(comptime src: []const u8) !Model {
        var stream = std.io.fixedBufferStream(@embedFile("assets/" ++ src));
        return load(stream.reader());
    }

    /// Free the model's vertices.
    pub fn deinit(self: Model) void {
        util.allocator.free(self.vertices);
    }

    pub fn render(self: Model, offset: zlm.Vec3) void {
        drawLines(self.vertices, offset);
    }
};
