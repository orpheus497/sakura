//! Renders an animated GIF as the login wallpaper.
//!
//! The console cannot show pixels, so each character cell is drawn as an upper
//! half block (U+2580): the foreground colour paints the cell's top half and
//! the background its bottom half, which doubles the vertical resolution and
//! turns the terminal into a crude framebuffer of `columns x (rows * 2)`
//! sub-pixels.
//!
//! Frames are decoded on demand rather than up front. Decoding this GIF costs
//! about 8 ms per frame, comfortably inside its 70 ms cadence, so the first
//! pass through the animation decodes as it plays and every pass afterwards is
//! served from the sampled cache. Once every frame is cached the composition
//! canvas is released, leaving only the cache resident.

const std = @import("std");
const Allocator = std.mem.Allocator;

const sakura_ui = @import("sakura-ui");
const Cell = sakura_ui.Cell;
const TerminalBuffer = sakura_ui.TerminalBuffer;
const Color = TerminalBuffer.Color;
const Widget = sakura_ui.Widget;

const sakura_core = sakura_ui.sakura_core;
const interop = sakura_core.interop;
const TimeOfDay = interop.TimeOfDay;
const LogFile = sakura_core.LogFile;

const decoder = @import("gif/decoder.zig");
const GifScaling = @import("../enums.zig").GifScaling;

const Gif = @This();

/// U+2580 UPPER HALF BLOCK.
const HALF_BLOCK: u32 = 0x2580;

/// The eight-colour codes, used when the terminal isn't in true-colour mode.
const eight_colors = [8]struct { rgb: u32, code: u32 }{
    .{ .rgb = 0x000000, .code = Color.ECOL_BLACK },
    .{ .rgb = 0xFF0000, .code = Color.ECOL_RED },
    .{ .rgb = 0x00FF00, .code = Color.ECOL_GREEN },
    .{ .rgb = 0xFFFF00, .code = Color.ECOL_YELLOW },
    .{ .rgb = 0x0000FF, .code = Color.ECOL_BLUE },
    .{ .rgb = 0xFF00FF, .code = Color.ECOL_MAGENTA },
    .{ .rgb = 0x00FFFF, .code = Color.ECOL_CYAN },
    .{ .rgb = 0xFFFFFF, .code = Color.ECOL_WHITE },
};

instance: ?Widget = null,
allocator: Allocator,
io: std.Io,
terminal_buffer: *TerminalBuffer,
log_file: *LogFile,

movie: decoder.Gif,
/// Released once every frame has been sampled into the cache.
compositor: ?decoder.Compositor,
/// The movie's palette, pre-resolved to termbox colour values.
cell_palette: []u32,

scaling: GifScaling,
font_aspect: f32,
background: u32,

/// One sampled frame per movie frame, `layout.width * layout.height` bytes of
/// palette indices each. Allocated up front, filled lazily.
cache: [][]u8,
cached: []bool,
cache_count: usize,
/// Source column/row for each sampled column/row, so sampling is two lookups
/// rather than two divisions per sub-pixel.
map_x: []u32,
map_y: []u32,
layout: Layout,

current: usize,
time_previous: i64,
start_time: TimeOfDay,
animate: *bool,
timeout_sec: u12,
failed: bool = false,

/// Where the scaled image sits on the sub-pixel grid.
const Layout = struct {
    /// Origin on the sub-pixel grid; the sampled region starts here.
    x: usize = 0,
    y: usize = 0,
    /// Size of the sampled region, already clipped to the grid.
    width: usize = 0,
    height: usize = 0,
};

pub fn init(
    allocator: Allocator,
    io: std.Io,
    terminal_buffer: *TerminalBuffer,
    log_file: *LogFile,
    file_path: []const u8,
    scaling: GifScaling,
    font_aspect: f32,
    full_color: bool,
    background: u32,
    animate: *bool,
    timeout_sec: u12,
) !Gif {
    var movie = decoder.open(allocator, io, file_path) catch |err| {
        switch (err) {
            error.FileNotFound => try log_file.err(io, "tui", "gif_file was not found at: {s}", .{file_path}),
            error.NotAGifFile => try log_file.err(io, "tui", "gif_file is not a GIF: {s}", .{file_path}),
            error.UnsupportedGifVersion => try log_file.err(io, "tui", "gif_file is not GIF87a or GIF89a: {s}", .{file_path}),
            error.NoFrames => try log_file.err(io, "tui", "gif_file contains no frames: {s}", .{file_path}),
            else => try log_file.err(io, "tui", "failed to read gif_file {s}: {s}", .{ file_path, @errorName(err) }),
        }
        return err;
    };
    errdefer movie.deinit();

    const cell_palette = try allocator.alloc(u32, movie.palette.len);
    errdefer allocator.free(cell_palette);
    for (movie.palette, 0..) |rgb, i| {
        cell_palette[i] = toCellColor(rgb, full_color);
    }

    const cache = try allocator.alloc([]u8, movie.frames.len);
    errdefer allocator.free(cache);
    @memset(cache, &.{});

    const cached = try allocator.alloc(bool, movie.frames.len);
    errdefer allocator.free(cached);
    @memset(cached, false);

    var self = Gif{
        .allocator = allocator,
        .io = io,
        .terminal_buffer = terminal_buffer,
        .log_file = log_file,
        .movie = movie,
        .compositor = null,
        .cell_palette = cell_palette,
        .scaling = scaling,
        .font_aspect = font_aspect,
        .background = background,
        .cache = cache,
        .cached = cached,
        .cache_count = 0,
        .map_x = &.{},
        .map_y = &.{},
        .layout = .{},
        .current = 0,
        .time_previous = std.Io.Timestamp.now(io, .real).toMilliseconds(),
        .start_time = try interop.getTimeOfDay(),
        .animate = animate,
        .timeout_sec = timeout_sec,
    };

    try self.rebuild();
    return self;
}

/// Converts a 0xRRGGBB triple into the value termbox expects.
fn toCellColor(rgb: u32, full_color: bool) u32 {
    if (!full_color) {
        var best = eight_colors[0];
        var best_distance: i32 = std.math.maxInt(i32);
        const r: i32 = @intCast((rgb >> 16) & 0xFF);
        const g: i32 = @intCast((rgb >> 8) & 0xFF);
        const b: i32 = @intCast(rgb & 0xFF);
        for (eight_colors) |candidate| {
            const dr = r - @as(i32, @intCast((candidate.rgb >> 16) & 0xFF));
            const dg = g - @as(i32, @intCast((candidate.rgb >> 8) & 0xFF));
            const db = b - @as(i32, @intCast(candidate.rgb & 0xFF));
            const distance = dr * dr + dg * dg + db * db;
            if (distance < best_distance) {
                best_distance = distance;
                best = candidate;
            }
        }
        return best.code;
    }

    // 0x00000000 means "whatever the terminal defaults to", so real black has
    // to be asked for with the high-black style bit instead.
    return if (rgb == 0) Color.TRUE_BLACK else rgb;
}

/// Recomputes the layout for the current terminal size and drops any cached
/// frames sampled at the old size.
fn rebuild(self: *Gif) !void {
    const columns = self.terminal_buffer.width;
    const rows = self.terminal_buffer.height;
    if (columns == 0 or rows == 0) return;

    const grid_w: f32 = @floatFromInt(columns);
    const grid_h: f32 = @floatFromInt(rows * 2);
    const source_w: f32 = @floatFromInt(self.movie.width);
    const source_h: f32 = @floatFromInt(self.movie.height);

    // A half cell is `font_aspect / 2` times taller than it is wide, so the
    // sub-pixel grid is not square. Fold that into the target ratio, otherwise
    // the image comes out stretched vertically on most console fonts.
    const ratio = (source_w / source_h) * (self.font_aspect / 2.0);

    var width: f32 = undefined;
    var height: f32 = undefined;
    switch (self.scaling) {
        .stretch => {
            width = grid_w;
            height = grid_h;
        },
        .none => {
            width = source_w;
            height = source_h;
        },
        .fit => {
            width = @min(grid_w, grid_h * ratio);
            height = width / ratio;
        },
        .fill => {
            width = @max(grid_w, grid_h * ratio);
            height = width / ratio;
        },
    }

    if (width < 1 or height < 1) return;

    // Centre the image, then clip whatever falls outside the grid.
    const origin_x = (grid_w - width) / 2.0;
    const origin_y = (grid_h - height) / 2.0;

    const clip_x0 = @max(origin_x, 0);
    const clip_y0 = @max(origin_y, 0);
    const clip_x1 = @min(origin_x + width, grid_w);
    const clip_y1 = @min(origin_y + height, grid_h);
    if (clip_x1 <= clip_x0 or clip_y1 <= clip_y0) return;

    const layout = Layout{
        .x = @intFromFloat(clip_x0),
        .y = @intFromFloat(clip_y0),
        .width = @intFromFloat(clip_x1 - clip_x0),
        .height = @intFromFloat(clip_y1 - clip_y0),
    };
    if (layout.width == 0 or layout.height == 0) return;

    // Nearest-neighbour sampling: the source is pixel art, so averaging would
    // only blur it.
    const map_x = try self.allocator.alloc(u32, layout.width);
    errdefer self.allocator.free(map_x);
    for (map_x, 0..) |*slot, i| {
        const sub_x: f32 = @floatFromInt(layout.x + i);
        const t = (sub_x - origin_x) / width * source_w;
        slot.* = @min(@as(u32, @intFromFloat(@max(t, 0))), self.movie.width - 1);
    }

    const map_y = try self.allocator.alloc(u32, layout.height);
    errdefer self.allocator.free(map_y);
    for (map_y, 0..) |*slot, j| {
        const sub_y: f32 = @floatFromInt(layout.y + j);
        const t = (sub_y - origin_y) / height * source_h;
        slot.* = @min(@as(u32, @intFromFloat(@max(t, 0))), self.movie.height - 1);
    }

    // Everything sampled at the old size is now wrong.
    for (self.cache) |frame| {
        if (frame.len > 0) self.allocator.free(frame);
    }
    @memset(self.cache, &.{});
    @memset(self.cached, false);
    self.cache_count = 0;

    if (self.map_x.len > 0) self.allocator.free(self.map_x);
    if (self.map_y.len > 0) self.allocator.free(self.map_y);
    self.map_x = map_x;
    self.map_y = map_y;
    self.layout = layout;

    for (self.cache) |*frame| {
        frame.* = try self.allocator.alloc(u8, layout.width * layout.height);
    }

    // Note: the compositor is created lazily in ensureCached(), never here.
    // rebuild() also runs from init(), where `self` is a local that gets copied
    // on return, so a compositor built here would hold a dangling &self.movie.
    if (self.compositor) |*compositor| compositor.reset();

    self.current = 0;
}

/// Decodes forward until `index` has been sampled into the cache.
fn ensureCached(self: *Gif, index: usize) !void {
    if (self.cached[index]) return;

    if (self.compositor == null) {
        self.compositor = try decoder.Compositor.init(self.allocator, &self.movie);
    }
    const compositor = &self.compositor.?;

    // The compositor can only move forward, so wind back if it has already
    // passed the frame we want.
    if (compositor.next_frame > index) compositor.reset();

    while (true) {
        const decoded = try compositor.advance();
        if (!self.cached[decoded]) {
            self.sample(self.cache[decoded], compositor.canvas);
            self.cached[decoded] = true;
            self.cache_count += 1;
        }
        if (decoded == index) break;
    }

    // Every frame is cached, so the composition canvas is dead weight now.
    if (self.cache_count == self.movie.frames.len) {
        if (self.compositor) |*c| c.deinit();
        self.compositor = null;
    }
}

fn sample(self: *Gif, destination: []u8, canvas: []const u8) void {
    for (self.map_y, 0..) |source_y, j| {
        const source_row = @as(usize, source_y) * self.movie.width;
        const destination_row = j * self.layout.width;
        for (self.map_x, 0..) |source_x, i| {
            destination[destination_row + i] = canvas[source_row + source_x];
        }
    }
}

/// Colour of one sub-pixel, or the configured background outside the image.
fn subPixel(self: *const Gif, frame: []const u8, x: usize, y: usize) u32 {
    if (x < self.layout.x or y < self.layout.y) return self.background;
    const i = x - self.layout.x;
    const j = y - self.layout.y;
    if (i >= self.layout.width or j >= self.layout.height) return self.background;

    const index = frame[j * self.layout.width + i];
    if (index >= self.cell_palette.len) return self.background;
    return self.cell_palette[index];
}

fn update(self: *Gif, _: *anyopaque) !void {
    if (self.failed) return;

    const time = try interop.getTimeOfDay();
    if (self.timeout_sec > 0 and time.seconds - self.start_time.seconds > self.timeout_sec) {
        self.animate.* = false;
        return;
    }
    if (!self.animate.*) return;

    // Advance if this frame has been on screen for its full delay.
    const now = std.Io.Timestamp.now(self.io, .real).toMilliseconds();
    const delay: i64 = @intCast(self.movie.frames[self.current].delay_ms);
    var next = self.current;
    if (now - self.time_previous >= delay) {
        self.time_previous = now;
        next = (self.current + 1) % self.movie.frames.len;
    }

    self.ensureCached(next) catch |err| {
        // A broken stream shouldn't take the greeter down with it; stop
        // animating and leave whatever is on screen.
        try self.log_file.err(self.io, "tui", "failed to decode gif frame {d}: {s}", .{ next, @errorName(err) });
        self.failed = true;
        self.animate.* = false;
        return;
    };

    self.current = next;
}

fn draw(self: *Gif) void {
    if (!self.animate.* or self.failed) return;
    if (!self.cached[self.current]) return;

    const frame = self.cache[self.current];

    for (0..self.terminal_buffer.height) |row| {
        for (0..self.terminal_buffer.width) |column| {
            const top = self.subPixel(frame, column, row * 2);
            const bottom = self.subPixel(frame, column, row * 2 + 1);
            const cell = Cell.init(HALF_BLOCK, top, bottom);
            self.terminal_buffer.setCellBoundsChecked(
                @intCast(column),
                @intCast(row),
                cell,
            ) catch {};
        }
    }
}

fn realloc(self: *Gif) !void {
    try self.rebuild();
}

fn calculateTimeout(self: *Gif, _: *anyopaque) !?usize {
    if (!self.animate.* or self.failed) return null;

    // Wake up when this frame is due to be replaced, not on a fixed tick.
    const now = std.Io.Timestamp.now(self.io, .real).toMilliseconds();
    const delay: i64 = @intCast(self.movie.frames[self.current].delay_ms);
    const remaining = delay - (now - self.time_previous);
    return @intCast(@max(remaining, 1));
}

fn deinit(self: *Gif) void {
    if (self.compositor) |*compositor| compositor.deinit();
    for (self.cache) |frame| {
        if (frame.len > 0) self.allocator.free(frame);
    }
    self.allocator.free(self.cache);
    self.allocator.free(self.cached);
    if (self.map_x.len > 0) self.allocator.free(self.map_x);
    if (self.map_y.len > 0) self.allocator.free(self.map_y);
    self.allocator.free(self.cell_palette);
    self.movie.deinit();
}

pub fn widget(self: *Gif) *Widget {
    if (self.instance) |*instance| return instance;
    self.instance = Widget.init(
        "Gif",
        null,
        self,
        deinit,
        realloc,
        draw,
        update,
        null,
        calculateTimeout,
    );
    return &self.instance.?;
}
