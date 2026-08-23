//! A GIF87a/89a decoder, written for Sakura's login wallpaper.
//!
//! Sakura draws on a character console, so the decoder never needs a
//! full-resolution RGB surface: it composes frames into an 8-bit index canvas
//! and samples that canvas down to the terminal's sub-pixel grid. Keeping
//! everything in palette indices holds a 2240x1085 animation to ~2.4 MB of
//! working memory instead of ~10 MB.
//!
//! Because a GIF may carry a local colour table per frame, all colour tables
//! are merged into one deduplicated palette up front. Every real-world GIF
//! fits in 256 distinct colours; if one doesn't, the surplus colours are
//! mapped to their nearest neighbour rather than failing.
//!
//! This file deliberately has no dependency on the UI layer so that it can be
//! tested on its own.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{
    NotAGifFile,
    UnsupportedGifVersion,
    TruncatedGif,
    NoFrames,
    InvalidLzwStream,
    FrameOutOfBounds,
};

pub const Rgb = packed struct(u32) {
    b: u8,
    g: u8,
    r: u8,
    _pad: u8 = 0,

    pub fn value(self: Rgb) u32 {
        return (@as(u32, self.r) << 16) | (@as(u32, self.g) << 8) | self.b;
    }
};

/// What to do with the frame's area once it has been displayed.
pub const Disposal = enum(u3) {
    unspecified = 0,
    keep = 1,
    restore_background = 2,
    restore_previous = 3,
    _,
};

pub const Frame = struct {
    /// Offset of the LZW minimum-code-size byte within the file.
    data_offset: usize,
    left: u16,
    top: u16,
    width: u16,
    height: u16,
    interlaced: bool,
    /// Local colour table remapped into the unified palette, if present.
    palette_map: ?[]u8,
    /// Index into the *local* table (pre-remap) that is transparent.
    transparent: ?u8,
    disposal: Disposal,
    delay_ms: u32,
};

pub const Gif = struct {
    allocator: Allocator,
    bytes: []u8,
    width: u16,
    height: u16,
    /// Unified palette; entries are 0x00RRGGBB.
    palette: []u32,
    /// Global colour table remapped into the unified palette.
    global_map: []u8,
    background: u8,
    frames: []Frame,

    pub fn deinit(self: *Gif) void {
        for (self.frames) |frame| {
            if (frame.palette_map) |m| self.allocator.free(m);
        }
        self.allocator.free(self.frames);
        self.allocator.free(self.palette);
        self.allocator.free(self.global_map);
        self.allocator.free(self.bytes);
    }
};

/// Reads `path` and indexes every frame in it, without running any LZW
/// decompression. Decoding a frame's pixels is deferred to `decodeFrame`.
pub fn open(allocator: Allocator, io: std.Io, path: []const u8) !Gif {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    const stat = try file.stat(io);
    var read_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    const bytes = try reader.interface.readAlloc(allocator, @intCast(stat.size));
    errdefer allocator.free(bytes);

    return parse(allocator, bytes);
}

fn parse(allocator: Allocator, bytes: []u8) !Gif {
    if (bytes.len < 13) return Error.TruncatedGif;
    if (!std.mem.eql(u8, bytes[0..3], "GIF")) return Error.NotAGifFile;
    if (!std.mem.eql(u8, bytes[3..6], "87a") and !std.mem.eql(u8, bytes[3..6], "89a")) {
        return Error.UnsupportedGifVersion;
    }

    const width = readU16(bytes, 6);
    const height = readU16(bytes, 8);
    const flags = bytes[10];
    const background_index = bytes[11];

    var palette: std.ArrayList(u32) = .empty;
    errdefer palette.deinit(allocator);
    // Maps a packed RGB value to its slot in the unified palette.
    var seen: std.AutoHashMapUnmanaged(u32, u8) = .empty;
    defer seen.deinit(allocator);

    var pos: usize = 13;
    var global_map: []u8 = &.{};
    errdefer if (global_map.len > 0) allocator.free(global_map);

    if (flags & 0x80 != 0) {
        const count = @as(u16, 2) << @intCast(flags & 0x07);
        global_map = try mergeTable(allocator, bytes, pos, count, &palette, &seen);
        pos += 3 * @as(usize, count);
    }

    // A GIF with no global table still needs at least one palette entry so the
    // canvas has something to be cleared to.
    if (palette.items.len == 0) try palette.append(allocator, 0);

    var frames: std.ArrayList(Frame) = .empty;
    errdefer {
        for (frames.items) |f| if (f.palette_map) |m| allocator.free(m);
        frames.deinit(allocator);
    }

    // Graphic control extensions apply to the next image descriptor.
    var pending_transparent: ?u8 = null;
    var pending_disposal: Disposal = .unspecified;
    var pending_delay_ms: u32 = 0;

    while (pos < bytes.len) {
        switch (bytes[pos]) {
            0x3B => break, // trailer
            0x21 => { // extension
                if (pos + 2 > bytes.len) return Error.TruncatedGif;
                const label = bytes[pos + 1];
                pos += 2;
                if (label == 0xF9 and pos < bytes.len and bytes[pos] >= 4) {
                    const gce = bytes[pos + 1 ..];
                    pending_disposal = @enumFromInt((gce[0] >> 2) & 0x07);
                    pending_transparent = if (gce[0] & 0x01 != 0) gce[3] else null;
                    // GIF stores the delay in hundredths of a second. A zero or
                    // one-tick delay means "as fast as possible", which every
                    // renderer clamps; 100ms is the long-standing convention.
                    const ticks = @as(u32, gce[1]) | (@as(u32, gce[2]) << 8);
                    pending_delay_ms = if (ticks < 2) 100 else ticks * 10;
                }
                pos = try skipBlocks(bytes, pos);
            },
            0x2C => { // image descriptor
                if (pos + 10 > bytes.len) return Error.TruncatedGif;
                const left = readU16(bytes, pos + 1);
                const top = readU16(bytes, pos + 3);
                const frame_width = readU16(bytes, pos + 5);
                const frame_height = readU16(bytes, pos + 7);
                const local_flags = bytes[pos + 9];
                pos += 10;

                var palette_map: ?[]u8 = null;
                if (local_flags & 0x80 != 0) {
                    const count = @as(u16, 2) << @intCast(local_flags & 0x07);
                    palette_map = try mergeTable(allocator, bytes, pos, count, &palette, &seen);
                    pos += 3 * @as(usize, count);
                }
                errdefer if (palette_map) |m| allocator.free(m);

                if (pos >= bytes.len) return Error.TruncatedGif;
                const data_offset = pos;
                pos += 1; // LZW minimum code size
                pos = try skipBlocks(bytes, pos);

                if (@as(u32, left) + frame_width > width or
                    @as(u32, top) + frame_height > height)
                {
                    return Error.FrameOutOfBounds;
                }

                try frames.append(allocator, .{
                    .data_offset = data_offset,
                    .left = left,
                    .top = top,
                    .width = frame_width,
                    .height = frame_height,
                    .interlaced = local_flags & 0x40 != 0,
                    .palette_map = palette_map,
                    .transparent = pending_transparent,
                    .disposal = pending_disposal,
                    .delay_ms = pending_delay_ms,
                });

                pending_transparent = null;
                pending_disposal = .unspecified;
                pending_delay_ms = 0;
            },
            else => return Error.TruncatedGif,
        }
    }

    if (frames.items.len == 0) return Error.NoFrames;

    return .{
        .allocator = allocator,
        .bytes = bytes,
        .width = width,
        .height = height,
        .palette = try palette.toOwnedSlice(allocator),
        .global_map = global_map,
        .background = if (global_map.len > background_index) global_map[background_index] else 0,
        .frames = try frames.toOwnedSlice(allocator),
    };
}

/// Folds one colour table into the unified palette, returning the index
/// translation for that table.
fn mergeTable(
    allocator: Allocator,
    bytes: []const u8,
    offset: usize,
    count: u16,
    palette: *std.ArrayList(u32),
    seen: *std.AutoHashMapUnmanaged(u32, u8),
) ![]u8 {
    if (offset + 3 * @as(usize, count) > bytes.len) return Error.TruncatedGif;

    const map = try allocator.alloc(u8, count);
    errdefer allocator.free(map);

    for (0..count) |i| {
        const base = offset + 3 * i;
        const rgb = (@as(u32, bytes[base]) << 16) |
            (@as(u32, bytes[base + 1]) << 8) |
            @as(u32, bytes[base + 2]);

        if (seen.get(rgb)) |slot| {
            map[i] = slot;
            continue;
        }

        if (palette.items.len < 256) {
            const slot: u8 = @intCast(palette.items.len);
            try palette.append(allocator, rgb);
            try seen.put(allocator, rgb, slot);
            map[i] = slot;
        } else {
            // Astronomically rare: more than 256 distinct colours across all
            // tables. Fall back to the closest colour already in the palette
            // rather than refusing to display the image.
            map[i] = nearest(palette.items, rgb);
        }
    }

    return map;
}

fn nearest(palette: []const u32, rgb: u32) u8 {
    const r: i32 = @intCast((rgb >> 16) & 0xFF);
    const g: i32 = @intCast((rgb >> 8) & 0xFF);
    const b: i32 = @intCast(rgb & 0xFF);

    var best_index: u8 = 0;
    var best_distance: i32 = std.math.maxInt(i32);
    for (palette, 0..) |candidate, i| {
        const dr = r - @as(i32, @intCast((candidate >> 16) & 0xFF));
        const dg = g - @as(i32, @intCast((candidate >> 8) & 0xFF));
        const db = b - @as(i32, @intCast(candidate & 0xFF));
        const distance = dr * dr + dg * dg + db * db;
        if (distance < best_distance) {
            best_distance = distance;
            best_index = @intCast(i);
        }
    }
    return best_index;
}

/// Walks a chain of GIF sub-blocks and returns the offset just past its
/// terminating zero-length block.
fn skipBlocks(bytes: []const u8, start: usize) !usize {
    var pos = start;
    while (true) {
        if (pos >= bytes.len) return Error.TruncatedGif;
        const len = bytes[pos];
        pos += 1;
        if (len == 0) return pos;
        pos += len;
    }
}

fn readU16(bytes: []const u8, offset: usize) u16 {
    return @as(u16, bytes[offset]) | (@as(u16, bytes[offset + 1]) << 8);
}

/// Reads LZW codes out of a GIF sub-block chain.
const BitReader = struct {
    bytes: []const u8,
    pos: usize,
    remaining: u8 = 0,
    bit_buffer: u32 = 0,
    bit_count: u5 = 0,
    exhausted: bool = false,

    fn nextByte(self: *BitReader) ?u8 {
        if (self.remaining == 0) {
            if (self.exhausted or self.pos >= self.bytes.len) return null;
            const len = self.bytes[self.pos];
            self.pos += 1;
            if (len == 0) {
                self.exhausted = true;
                return null;
            }
            self.remaining = len;
        }
        if (self.pos >= self.bytes.len) return null;
        const byte = self.bytes[self.pos];
        self.pos += 1;
        self.remaining -= 1;
        return byte;
    }

    fn read(self: *BitReader, bits: u5) ?u16 {
        while (self.bit_count < bits) {
            const byte = self.nextByte() orelse return null;
            self.bit_buffer |= @as(u32, byte) << self.bit_count;
            self.bit_count += 8;
        }
        const mask = (@as(u32, 1) << bits) - 1;
        const code: u16 = @intCast(self.bit_buffer & mask);
        self.bit_buffer >>= bits;
        self.bit_count -= bits;
        return code;
    }
};

/// Row order for the four passes of an interlaced GIF.
const interlace_start = [4]u16{ 0, 4, 2, 1 };
const interlace_step = [4]u16{ 8, 8, 4, 2 };

/// Decompresses `frame` and composites it onto `canvas`, which holds unified
/// palette indices for the whole logical screen. Pixels equal to the frame's
/// transparent index are left untouched, which is what makes GIF deltas work.
pub fn decodeFrame(gif: *const Gif, frame: Frame, canvas: []u8) !void {
    std.debug.assert(canvas.len == @as(usize, gif.width) * gif.height);

    const map = frame.palette_map orelse gif.global_map;
    if (map.len == 0) return Error.InvalidLzwStream;

    const min_code_size: u4 = @intCast(gif.bytes[frame.data_offset]);
    if (min_code_size < 2 or min_code_size > 11) return Error.InvalidLzwStream;

    const clear_code: u16 = @as(u16, 1) << min_code_size;
    const end_code: u16 = clear_code + 1;

    var prefix: [4096]u16 = undefined;
    var suffix: [4096]u8 = undefined;
    var stack: [4096]u8 = undefined;

    var code_size: u5 = @as(u5, min_code_size) + 1;
    var next_code: u16 = end_code + 1;
    var previous_code: i32 = -1;
    var first_byte: u8 = 0;

    var reader = BitReader{ .bytes = gif.bytes, .pos = frame.data_offset + 1 };

    // Where the next decoded pixel lands inside the frame's rectangle.
    var x: u16 = 0;
    var y: u16 = 0;
    var pass: usize = 0;
    const total = @as(usize, frame.width) * frame.height;
    var written: usize = 0;

    while (written < total) {
        const code = reader.read(code_size) orelse break;

        if (code == clear_code) {
            code_size = @as(u5, min_code_size) + 1;
            next_code = end_code + 1;
            previous_code = -1;
            continue;
        }
        if (code == end_code) break;

        var stack_len: usize = 0;
        var current = code;

        if (code >= next_code) {
            // The KwKwK case: the encoder used a code it defined with this
            // very output. Emit the previous string plus its own first byte.
            if (previous_code < 0) return Error.InvalidLzwStream;
            stack[stack_len] = first_byte;
            stack_len += 1;
            current = @intCast(previous_code);
        }

        while (current >= clear_code) {
            if (stack_len >= stack.len) return Error.InvalidLzwStream;
            stack[stack_len] = suffix[current];
            stack_len += 1;
            current = prefix[current];
        }
        first_byte = @intCast(current);
        stack[stack_len] = first_byte;
        stack_len += 1;

        // The stack holds the string reversed.
        while (stack_len > 0 and written < total) {
            stack_len -= 1;
            const local_index = stack[stack_len];

            const is_transparent = if (frame.transparent) |t| local_index == t else false;
            if (!is_transparent) {
                const canvas_x = @as(usize, frame.left) + x;
                const canvas_y = @as(usize, frame.top) + y;
                canvas[canvas_y * gif.width + canvas_x] =
                    if (local_index < map.len) map[local_index] else 0;
            }
            written += 1;

            x += 1;
            if (x == frame.width) {
                x = 0;
                if (frame.interlaced) {
                    y += interlace_step[pass];
                    while (y >= frame.height and pass < 3) {
                        pass += 1;
                        y = interlace_start[pass];
                    }
                } else {
                    y += 1;
                }
            }
        }

        if (previous_code >= 0 and next_code < 4096) {
            prefix[next_code] = @intCast(previous_code);
            suffix[next_code] = first_byte;
            next_code += 1;
            if (next_code == (@as(u16, 1) << @intCast(code_size)) and code_size < 12) {
                code_size += 1;
            }
        }
        previous_code = code;
    }

    return;
}

/// Plays a `Gif` forward, keeping the composed logical screen in `canvas`.
///
/// GIF frames are deltas: each one paints into a sub-rectangle and may leave
/// pixels transparent, and the *previous* frame's disposal method decides what
/// the area underneath looks like first. Callers step with `advance` and read
/// `canvas` after each step.
pub const Compositor = struct {
    allocator: Allocator,
    gif: *const Gif,
    canvas: []u8,
    /// Snapshot for `restore_previous`, allocated only if a frame asks for it.
    saved: ?[]u8 = null,
    /// The frame `advance` will decode next.
    next_frame: usize = 0,
    /// Cleanup owed to the frame that was decoded last.
    pending: ?Frame = null,

    pub fn init(allocator: Allocator, gif: *const Gif) !Compositor {
        const canvas = try allocator.alloc(u8, @as(usize, gif.width) * gif.height);
        @memset(canvas, gif.background);
        return .{ .allocator = allocator, .gif = gif, .canvas = canvas };
    }

    pub fn deinit(self: *Compositor) void {
        if (self.saved) |s| self.allocator.free(s);
        self.allocator.free(self.canvas);
    }

    /// Rewinds to the first frame. Needed when the animation loops and the
    /// caller has not cached every frame yet.
    pub fn reset(self: *Compositor) void {
        @memset(self.canvas, self.gif.background);
        self.next_frame = 0;
        self.pending = null;
    }

    /// Composes the next frame. Returns its index.
    pub fn advance(self: *Compositor) !usize {
        if (self.pending) |previous| {
            switch (previous.disposal) {
                .restore_background => self.fill(previous, self.gif.background),
                .restore_previous => if (self.saved) |s| self.restore(previous, s),
                else => {},
            }
            self.pending = null;
        }

        const index = self.next_frame;
        const frame = self.gif.frames[index];

        if (frame.disposal == .restore_previous) {
            if (self.saved == null) {
                self.saved = try self.allocator.alloc(u8, self.canvas.len);
            }
            @memcpy(self.saved.?, self.canvas);
        }

        try decodeFrame(self.gif, frame, self.canvas);

        self.pending = frame;
        self.next_frame = (index + 1) % self.gif.frames.len;
        return index;
    }

    fn fill(self: *Compositor, frame: Frame, value: u8) void {
        for (0..frame.height) |row| {
            const start = (@as(usize, frame.top) + row) * self.gif.width + frame.left;
            @memset(self.canvas[start .. start + frame.width], value);
        }
    }

    fn restore(self: *Compositor, frame: Frame, source: []const u8) void {
        for (0..frame.height) |row| {
            const start = (@as(usize, frame.top) + row) * self.gif.width + frame.left;
            @memcpy(self.canvas[start .. start + frame.width], source[start .. start + frame.width]);
        }
    }
};
