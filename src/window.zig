//! Abstractions for user interface components.

const platform = @import("platform.zig");

pub const WIDTH = 640;
pub const HEIGHT = 360;
pub const TITLE = "rhythm";

/// Initialize the window.
pub fn init() !void {
    // initialize I/O
    try platform.initIo();
    errdefer platform.deinitIo();
    // expecting GLES2
    try platform.initWebGl(2, 0);
    // create window
    try platform.createWindow(WIDTH, HEIGHT, TITLE);
    errdefer platform.destroyWindow();
}

/// Destroy the window.
pub fn deinit() void {
    // close I/O
    platform.deinitIo();
}

/// Get the dimensions of the window.
pub const getResolution = platform.getWindowSize;

/// Update the window.
pub const update = platform.pollEvents;

/// Return true if the window has been requested to close.
pub const shouldClose = platform.shouldClose;

/// Get the number of ticks that have elapsed since the program began.
pub const getTicks = platform.getTicks;

/// A code for a keyboard key.s
pub const KeyCode = platform.KeyCode;

/// A key and its time of being pressed.
pub const PressedKey = struct { id: platform.KeyCode, time: u32 };

/// Get the next pressed key and when it was pressed.
pub const nextPressedKey = platform.nextPressedKey;
