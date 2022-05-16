const std = @import("std");
const window = @import("window.zig");
const zlm = @import("zlm");

const gl = @cImport({
    @cInclude("GLES3/gl3.h");
});

const FOV = 70.0;
const NEAR = 0.01;
const FAR = 1000.0;

var program: gl.GLuint = undefined;
var vao: gl.GLuint = undefined;
var vbo: gl.GLuint = undefined;

var params: struct {
    model: gl.GLint,
    view: gl.GLint,
    projection: gl.GLint,

    color: gl.GLint,
} = undefined;

fn checkFailure(
    object: gl.GLuint,
    status_type: gl.GLenum,
    getStatus: fn (gl.GLuint, gl.GLenum, [*c]gl.GLint) callconv(.C) void,
    getLog: fn (gl.GLuint, gl.GLsizei, [*c]gl.GLsizei, [*c]gl.GLchar) callconv(.C) void,
) !void {
    var status: gl.GLint = undefined;
    getStatus(object, status_type, &status);
    if (status == 0) {
        // buffer to write errors to
        var buffer: [512]u8 = undefined;
        var length: gl.GLsizei = undefined;
        getLog(object, buffer.len, &length, &buffer);
        std.log.err("glsl errors:\n{s}", .{buffer[0..@intCast(usize, length)]});
        return error.ShaderError;
    }
}

fn createShader(kind: gl.GLenum, src: []const u8) !gl.GLuint {
    const shader = gl.glCreateShader(kind);
    errdefer gl.glDeleteShader(shader);

    var len = @intCast(gl.GLint, src.len);
    var ptr = src.ptr;
    gl.glShaderSource(shader, 1, &ptr, &len);
    gl.glCompileShader(shader);

    try checkFailure(
        shader,
        gl.GL_COMPILE_STATUS,
        gl.glGetShaderiv,
        gl.glGetShaderInfoLog,
    );

    return shader;
}

fn createProgram() !void {
    const vert_shader = try createShader(gl.GL_VERTEX_SHADER, @embedFile("vert.glsl"));
    defer gl.glDeleteShader(vert_shader);

    const frag_shader = try createShader(gl.GL_FRAGMENT_SHADER, @embedFile("frag.glsl"));
    defer gl.glDeleteShader(frag_shader);

    program = gl.glCreateProgram();
    errdefer gl.glDeleteProgram(program);

    gl.glAttachShader(program, vert_shader);
    gl.glAttachShader(program, frag_shader);
    gl.glLinkProgram(program);

    try checkFailure(
        program,
        gl.GL_LINK_STATUS,
        gl.glGetProgramiv,
        gl.glGetProgramInfoLog,
    );
}

/// Initialize the renderer. Expects the window to be initialized.
pub fn init() !void {
    gl.glEnable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_CULL_FACE);

    try createProgram();
    errdefer gl.glDeleteProgram(program);

    gl.glUseProgram(program);

    inline for (@typeInfo(@TypeOf(params)).Struct.fields) |field| {
        const name = (comptime field.name[0..field.name.len].*) ++ [0:0]u8{};
        const location = gl.glGetUniformLocation(program, name[0.. :0]);
        if (location < 0) {
            return error.ShaderError;
        }
        @field(params, field.name) = location;
    }

    gl.glGenVertexArrays(1, &vao);
    gl.glBindVertexArray(vao);

    gl.glGenBuffers(1, &vbo);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);

    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, @sizeOf(zlm.Vec3), null);
    gl.glEnableVertexAttribArray(0);

    updateResolution();
}

/// Free the renderer's resources.
pub fn deinit() void {
    gl.glDeleteVertexArrays(1, &vao);
    gl.glDeleteBuffers(1, &vbo);
    gl.glDeleteProgram(program);
}

fn uniformMat4(param: gl.GLint, matrix: zlm.Mat4) void {
    gl.glUniformMatrix4fv(param, 1, gl.GL_FALSE, @ptrCast(*const f32, &matrix.fields));
}

/// Update the renderer's resolution to match the window size.
pub fn updateResolution() void {
    const size = window.getResolution();
    if (size.width == 0 or size.height == 0) {
        // who knows, maybe some window manager will allow it
        @panic("window has a zero dimension");
    }
    // update viewport to fill screen
    gl.glViewport(0, 0, size.width, size.height);
    const ratio = @intToFloat(f32, size.width) / @intToFloat(f32, size.height);
    const projection = zlm.Mat4.createPerspective(FOV, ratio, NEAR, FAR);
    uniformMat4(params.projection, projection);
}

/// Clear the screen.
pub fn clear() void {
    gl.glClearColor(0.0, 0.0, 0.0, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT | gl.GL_DEPTH_BUFFER_BIT);
}

/// Set the camera's position and target.
pub fn setCamera(position: zlm.Vec3, target: zlm.Vec3) void {
    const view = zlm.Mat4.createLookAt(position, target, zlm.Vec3.unitY);
    uniformMat4(params.view, view);
}

fn drawCommon(vertices: []const zlm.Vec3, color: zlm.Vec3, offset: zlm.Vec3, rotation: zlm.Vec3, mode: gl.GLenum) void {
    // apply color
    gl.glUniform3f(params.color, color.x, color.y, color.z);
    // rotation matrices
    // TODO make sure the angle order is correct
    const rot_x = zlm.Mat4.createAngleAxis(zlm.Vec3.unitX, rotation.x);
    const rot_y = zlm.Mat4.createAngleAxis(zlm.Vec3.unitY, rotation.y);
    const rot_z = zlm.Mat4.createAngleAxis(zlm.Vec3.unitZ, rotation.z);
    // translation matrix
    const offset_matrix = zlm.Mat4.createTranslation(offset);
    // model matrix
    const model = rot_x.mul(rot_y).mul(rot_z).mul(offset_matrix);
    // send model matrix to gpu
    uniformMat4(params.model, model);
    // send vertices to gpu
    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(gl.GLsizei, @sizeOf(zlm.Vec3) * vertices.len),
        vertices.ptr,
        gl.GL_STATIC_DRAW,
    );
    gl.glDrawArrays(mode, 0, @intCast(gl.GLsizei, vertices.len));
}

pub fn drawLineLoop(vertices: []const zlm.Vec3, color: zlm.Vec3, offset: zlm.Vec3, rotation: zlm.Vec3) void {
    drawCommon(vertices, color, offset, rotation, gl.GL_LINE_LOOP);
}

pub fn drawLineStrip(vertices: []const zlm.Vec3, color: zlm.Vec3, offset: zlm.Vec3, rotation: zlm.Vec3) void {
    drawCommon(vertices, color, offset, rotation, gl.GL_LINE_STRIP);
}
