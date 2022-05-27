const platform = @import("platform.zig");

const Audio = @This();

pub const SAMPLE_RATE = 44100;
pub const CHANNEL_COUNT = 2;

handle: platform.AudioHandle,

pub fn init(src: [*:0]const u8) !Audio {
    const handle = try platform.openAudio(src);
    return Audio{ .handle = handle };
}

pub fn deinit(self: Audio) void {
    platform.closeAudio(self.handle);
}

/// Play the track.
pub fn play(self: Audio) !void {
    try platform.playAudio(self.handle);
}

/// Get the position in the track, in milliseconds.
pub fn getPos(self: Audio) u64 {
    return platform.getAudioPos(self.handle);
}

/// Get the duration of the track, in milliseconds.
pub fn getDuration(self: Audio) !u64 {
    return try platform.getAudioDuration(self.handle);
}
