//! Renders an animated GIF as the login wallpaper.
//!
//! The console cannot show pixels, so every character cell is drawn as a block
//! glyph with two colours. Each cell is matched against the source at 2x2
//! resolution and the best of two families is chosen:
//!
//!   * the sixteen quadrant patterns (space, the halves, the quadrants and the
//!     full block), which place two flat colours spatially, and
//!
//!   * the shades U+2591/2/3, which dither two colours at 44%, 50% and 67% to
//!     fake a tone the sixteen-colour console does not have.
//!
//! Shades buy colour at the cost of visible stipple, so they are penalised in
//! proportion to how far apart the two mixed colours are -- and that penalty is
//! relaxed where the source is genuinely chromatic. A grey sky stays flat grey;
//! a pink sun, which has no equivalent in the palette, is allowed to dither.
//!
//! Frames are decoded on demand rather than up front. Decoding this GIF costs
//! about 8 ms per frame, comfortably inside its 70 ms cadence, so the first
//! pass through the animation decodes as it plays and every pass afterwards is
//! served from the sampled cache. Once every frame is cached the composition
//! canvas is released, leaving only the cache resident.

const std = @import("std");
const Allocator = std.mem.Allocator;

const sakura_ui = @import("sakura-ui");
const TerminalBuffer = sakura_ui.TerminalBuffer;
const Color = TerminalBuffer.Color;
const Widget = sakura_ui.Widget;

const sakura_core = sakura_ui.sakura_core;
const LogFile = sakura_core.LogFile;

const decoder = @import("gif/decoder.zig");
const GifScaling = @import("../enums.zig").GifScaling;

const Gif = @This();

/// Every 2x2 on/off arrangement a cell can take, as a codepoint plus the mask
/// of quadrants painted in the foreground colour. Bit 3 is top-left, then
/// top-right, bottom-left, bottom-right.
const Quadrant = struct { codepoint: u32, mask: u4 };
const quadrants = [16]Quadrant{
    .{ .codepoint = 0x0020, .mask = 0b0000 }, // space
    .{ .codepoint = 0x2597, .mask = 0b0001 }, // quadrant lower right
    .{ .codepoint = 0x2596, .mask = 0b0010 }, // quadrant lower left
    .{ .codepoint = 0x2584, .mask = 0b0011 }, // lower half
    .{ .codepoint = 0x259D, .mask = 0b0100 }, // quadrant upper right
    .{ .codepoint = 0x2590, .mask = 0b0101 }, // right half
    .{ .codepoint = 0x259E, .mask = 0b0110 }, // upper right + lower left
    .{ .codepoint = 0x259F, .mask = 0b0111 },
    .{ .codepoint = 0x2598, .mask = 0b1000 }, // quadrant upper left
    .{ .codepoint = 0x259A, .mask = 0b1001 }, // upper left + lower right
    .{ .codepoint = 0x258C, .mask = 0b1010 }, // left half
    .{ .codepoint = 0x2599, .mask = 0b1011 },
    .{ .codepoint = 0x2580, .mask = 0b1100 }, // upper half
    .{ .codepoint = 0x259C, .mask = 0b1101 },
    .{ .codepoint = 0x259B, .mask = 0b1110 },
    .{ .codepoint = 0x2588, .mask = 0b1111 }, // full block
};

/// Shade glyphs with their measured ink coverage in the shipped console fonts.
const Shade = struct { codepoint: u32, ratio: f32 };
const shades = [3]Shade{
    .{ .codepoint = 0x2591, .ratio = 0.444 },
    .{ .codepoint = 0x2592, .ratio = 0.500 },
    .{ .codepoint = 0x2593, .ratio = 0.667 },
};

/// Above this much chroma the source has a hue the palette cannot match with a
/// flat colour, so dithering is allowed to keep it. Below it, stipple is
/// suppressed in favour of a flat tone.
const chroma_ceiling: f32 = 80.0;

/// A cell that reads as one uniform tone: either a flat palette colour or a
/// shade mixing two of them.
const Uniform = struct {
    color: u32,
    slot: u8,
    fg: u4,
    bg: u4,
    /// Distance between the mixed colours; how much this stipples.
    separation: u32,
};

/// Resolution of the colour lookup cubes, in bits per channel.
const palette_lut_bits = 5;
const uniform_lut_bits = 4;

instance: ?Widget = null,
allocator: Allocator,
io: std.Io,
terminal_buffer: *TerminalBuffer,
log_file: *LogFile,

movie: decoder.Gif,
/// Released once every frame has been sampled into the cache.
compositor: ?decoder.Compositor,
/// The movie's palette as plain 0xRRGGBB, for matching against the console's.
movie_colors: []u32,

scaling: GifScaling,
font_aspect: f32,
stipple: f32,
/// Console palette index used where the image doesn't reach.
background: u4,

/// Cells that read as one tone: 16 flat colours plus every shade blend.
uniforms: []Uniform,
/// RGB cube -> nearest console colour, and -> nearest uniform.
palette_lut: []u4,
uniform_lut: []u16,

/// One rendered frame per movie frame: two bytes per cell, a glyph slot and a
/// packed colour pair. Allocated up front, filled lazily.
cache: [][]u8,
cached: []bool,
cache_count: usize,
/// Source column/row for each quadrant column/row, so sampling is two lookups
/// rather than two divisions per sample.
map_x: []u32,
map_y: []u32,
layout: Layout,
/// Codepoints referenced by the cache, indexed by its glyph slot.
glyphs: []u32,

current: usize,
time_previous: i64,
/// Monotonic milliseconds at construction, for the inactivity timeout. Same
/// clock as `time_previous`, so the two can never disagree.
start_ms: i64,
animate: *bool,
timeout_sec: u12,
failed: bool = false,

/// Where the scaled image sits on the quadrant grid, which is twice the
/// terminal's size in each direction.
const Layout = struct {
    /// Origin on the quadrant grid; the sampled region starts here.
    x: usize = 0,
    y: usize = 0,
    /// Size of the sampled region, already clipped to the grid.
    width: usize = 0,
    height: usize = 0,
    /// Terminal size the above was computed for.
    columns: usize = 0,
    rows: usize = 0,
};

pub fn init(
    allocator: Allocator,
    io: std.Io,
    terminal_buffer: *TerminalBuffer,
    log_file: *LogFile,
    file_path: []const u8,
    scaling: GifScaling,
    font_aspect: f32,
    stipple: f32,
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

    const movie_colors = try allocator.alloc(u32, movie.palette.len);
    errdefer allocator.free(movie_colors);
    @memcpy(movie_colors, movie.palette);

    // Glyph slots 0..15 are the quadrant patterns, 16..18 the shades.
    const glyphs = try allocator.alloc(u32, quadrants.len + shades.len);
    errdefer allocator.free(glyphs);
    for (quadrants, 0..) |q, i| glyphs[i] = q.codepoint;
    for (shades, 0..) |sh, i| glyphs[quadrants.len + i] = sh.codepoint;

    const uniforms = try buildUniforms(allocator);
    errdefer allocator.free(uniforms);

    const palette_lut = try buildPaletteLut(allocator);
    errdefer allocator.free(palette_lut);

    const uniform_lut = try buildUniformLut(allocator, uniforms);
    errdefer allocator.free(uniform_lut);

    const cache = try allocator.alloc([]u8, movie.frames.len);
    errdefer allocator.free(cache);
    @memset(cache, &.{});

    const cached = try allocator.alloc(bool, movie.frames.len);
    errdefer allocator.free(cached);
    @memset(cached, false);

    const started = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    var self = Gif{
        .allocator = allocator,
        .io = io,
        .terminal_buffer = terminal_buffer,
        .log_file = log_file,
        .movie = movie,
        .compositor = null,
        .movie_colors = movie_colors,
        .scaling = scaling,
        .font_aspect = font_aspect,
        .stipple = std.math.clamp(stipple, 0.0, 16.0),
        .background = 0,
        .uniforms = uniforms,
        .palette_lut = palette_lut,
        .uniform_lut = uniform_lut,
        .cache = cache,
        .cached = cached,
        .cache_count = 0,
        .map_x = &.{},
        .map_y = &.{},
        .layout = .{},
        .glyphs = glyphs,
        .current = 0,
        .time_previous = started,
        .start_ms = started,
        .animate = animate,
        .timeout_sec = timeout_sec,
    };

    // Whatever shows where the image doesn't reach has to be a console colour
    // too, so the letterbox matches the configured background.
    self.background = self.nearestPalette(background & 0x00FFFFFF);

    try self.rebuild();
    return self;
}

/// Every cell that reads as a single tone: the sixteen flat colours, plus each
/// shade glyph mixing every ordered pair of them.
fn buildUniforms(allocator: Allocator) ![]Uniform {
    const palette = TerminalBuffer.vt_palette;
    const count = palette.len + shades.len * palette.len * (palette.len - 1);
    const list = try allocator.alloc(Uniform, count);
    errdefer allocator.free(list);

    var n: usize = 0;
    for (palette, 0..) |color, i| {
        list[n] = .{
            .color = color,
            .slot = quadrants.len - 1, // the full block
            .fg = @intCast(i),
            .bg = @intCast(i),
            .separation = 0,
        };
        n += 1;
    }

    for (shades, 0..) |shade, si| {
        for (palette, 0..) |fg, fi| {
            for (palette, 0..) |bg, bi| {
                if (fi == bi) continue;
                list[n] = .{
                    .color = blend(bg, fg, shade.ratio),
                    .slot = @intCast(quadrants.len + si),
                    .fg = @intCast(fi),
                    .bg = @intCast(bi),
                    .separation = TerminalBuffer.colorDistance(fg, bg),
                };
                n += 1;
            }
        }
    }

    std.debug.assert(n == count);
    return list;
}

fn blend(from: u32, to: u32, ratio: f32) u32 {
    var out: u32 = 0;
    var shift: u5 = 0;
    while (shift < 24) : (shift += 8) {
        const a: f32 = @floatFromInt((from >> shift) & 0xFF);
        const b: f32 = @floatFromInt((to >> shift) & 0xFF);
        const v: u32 = @intFromFloat(@round(a + ratio * (b - a)));
        out |= @as(u32, @min(v, 255)) << shift;
    }
    return out;
}

fn cubeColor(index: usize, bits: u5) u32 {
    const levels = @as(usize, 1) << bits;
    const step = 256 / levels;
    const half = step / 2;
    const b = (index % levels) * step + half;
    const g = ((index / levels) % levels) * step + half;
    const r = ((index / (levels * levels)) % levels) * step + half;
    return @intCast((r << 16) | (g << 8) | b);
}

fn cubeIndex(color: u32, bits: u5) usize {
    const shift: u5 = 8 - bits;
    const r = ((color >> 16) & 0xFF) >> shift;
    const g = ((color >> 8) & 0xFF) >> shift;
    const b = (color & 0xFF) >> shift;
    return (((@as(usize, r) << bits) | g) << bits) | b;
}

fn buildPaletteLut(allocator: Allocator) ![]u4 {
    const size = @as(usize, 1) << (3 * palette_lut_bits);
    const lut = try allocator.alloc(u4, size);
    errdefer allocator.free(lut);

    for (lut, 0..) |*slot, i| {
        const color = cubeColor(i, palette_lut_bits);
        var best: u4 = 0;
        var best_distance: u32 = std.math.maxInt(u32);
        for (TerminalBuffer.vt_palette, 0..) |candidate, k| {
            const distance = TerminalBuffer.colorDistance(color, candidate);
            if (distance < best_distance) {
                best_distance = distance;
                best = @intCast(k);
            }
        }
        slot.* = best;
    }
    return lut;
}

fn buildUniformLut(allocator: Allocator, uniforms: []const Uniform) ![]u16 {
    const size = @as(usize, 1) << (3 * uniform_lut_bits);
    const lut = try allocator.alloc(u16, size);
    errdefer allocator.free(lut);

    for (lut, 0..) |*slot, i| {
        const color = cubeColor(i, uniform_lut_bits);
        var best: u16 = 0;
        var best_distance: u32 = std.math.maxInt(u32);
        for (uniforms, 0..) |candidate, k| {
            const distance = TerminalBuffer.colorDistance(color, candidate.color);
            if (distance < best_distance) {
                best_distance = distance;
                best = @intCast(k);
            }
        }
        slot.* = best;
    }
    return lut;
}

fn nearestPalette(self: *const Gif, color: u32) u4 {
    return self.palette_lut[cubeIndex(color, palette_lut_bits)];
}

fn nearestUniform(self: *const Gif, color: u32) Uniform {
    return self.uniforms[self.uniform_lut[cubeIndex(color, uniform_lut_bits)]];
}

fn chromaOf(color: u32) f32 {
    const r = (color >> 16) & 0xFF;
    const g = (color >> 8) & 0xFF;
    const b = color & 0xFF;
    return @floatFromInt(@max(r, @max(g, b)) - @min(r, @min(g, b)));
}

fn meanColor(colors: []const u32) u32 {
    var r: u32 = 0;
    var g: u32 = 0;
    var b: u32 = 0;
    for (colors) |c| {
        r += (c >> 16) & 0xFF;
        g += (c >> 8) & 0xFF;
        b += c & 0xFF;
    }
    const n: u32 = @intCast(colors.len);
    return ((r / n) << 16) | ((g / n) << 8) | (b / n);
}

const Choice = struct { slot: u8, fg: u4, bg: u4 };

/// Picks the glyph and colour pair that best reproduces one cell, given its
/// four quadrant colours.
fn chooseCell(self: *const Gif, quad: [4]u32) Choice {
    const mean = meanColor(&quad);

    // Candidate one: a single tone, flat or dithered.
    const uniform = self.nearestUniform(mean);
    var best_error: u64 = 0;
    for (quad) |c| best_error += TerminalBuffer.colorDistance(c, uniform.color);

    // Dithering is only objectionable where the source is near-neutral; where
    // it has real hue the palette has nothing flat to offer, so let it stipple.
    const relief = 1.0 - @min(chromaOf(mean) / chroma_ceiling, 1.0);
    const penalty = self.stipple * @as(f32, @floatFromInt(uniform.separation)) * relief;
    best_error += @intFromFloat(@max(penalty, 0.0));

    var best = Choice{ .slot = uniform.slot, .fg = uniform.fg, .bg = uniform.bg };

    // Candidate two: two flat colours arranged over the cell's quadrants.
    for (quadrants, 0..) |pattern, i| {
        var on: [4]u32 = undefined;
        var off: [4]u32 = undefined;
        var on_count: usize = 0;
        var off_count: usize = 0;
        for (quad, 0..) |c, k| {
            if (pattern.mask & (@as(u4, 1) << @intCast(3 - k)) != 0) {
                on[on_count] = c;
                on_count += 1;
            } else {
                off[off_count] = c;
                off_count += 1;
            }
        }

        var fg = if (on_count > 0) self.nearestPalette(meanColor(on[0..on_count])) else 0;
        var bg = if (off_count > 0) self.nearestPalette(meanColor(off[0..off_count])) else 0;
        // A full block has no background and a space has no foreground; give
        // the unused half the same colour so the pair always describes what is
        // actually on screen.
        if (on_count == 0) fg = bg;
        if (off_count == 0) bg = fg;

        var err: u64 = 0;
        for (quad, 0..) |c, k| {
            const lit = pattern.mask & (@as(u4, 1) << @intCast(3 - k)) != 0;
            err += TerminalBuffer.colorDistance(c, TerminalBuffer.vt_palette[if (lit) fg else bg]);
        }

        if (err < best_error) {
            best_error = err;
            best = .{ .slot = @intCast(i), .fg = fg, .bg = bg };
        }
    }

    return best;
}

/// Recomputes the layout for the current terminal size and drops any frames
/// rendered at the old size.
fn rebuild(self: *Gif) !void {
    const columns = self.terminal_buffer.width;
    const rows = self.terminal_buffer.height;
    if (columns == 0 or rows == 0) return;

    // Cells are matched at 2x2, so the sampling grid is twice the terminal.
    const grid_w: f32 = @floatFromInt(columns * 2);
    const grid_h: f32 = @floatFromInt(rows * 2);
    const source_w: f32 = @floatFromInt(self.movie.width);
    const source_h: f32 = @floatFromInt(self.movie.height);

    // A quadrant is half a cell in each direction, so it has the same aspect as
    // the cell itself: `font_aspect` times taller than it is wide. Fold that
    // into the target ratio, otherwise the image comes out stretched.
    const ratio = (source_w / source_h) * self.font_aspect;

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
        .columns = columns,
        .rows = rows,
    };
    if (layout.width == 0 or layout.height == 0) return;

    // Nearest-neighbour sampling: the source is pixel art, so averaging would
    // only blur it.
    const map_x = try self.allocator.alloc(u32, layout.width);
    errdefer self.allocator.free(map_x);
    for (map_x, 0..) |*slot, i| {
        const at: f32 = @floatFromInt(layout.x + i);
        const t = (at - origin_x) / width * source_w;
        slot.* = @min(@as(u32, @intFromFloat(@max(t, 0))), self.movie.width - 1);
    }

    const map_y = try self.allocator.alloc(u32, layout.height);
    errdefer self.allocator.free(map_y);
    for (map_y, 0..) |*slot, j| {
        const at: f32 = @floatFromInt(layout.y + j);
        const t = (at - origin_y) / height * source_h;
        slot.* = @min(@as(u32, @intFromFloat(@max(t, 0))), self.movie.height - 1);
    }

    // Two bytes per cell: the glyph slot, then the colour pair. Build the
    // replacement cache in full before touching any of the live state: if an
    // allocation fails part way through, the errdefers above would otherwise
    // free maps that self had already been pointed at.
    const new_frames = try self.allocator.alloc([]u8, self.cache.len);
    errdefer self.allocator.free(new_frames);
    var built: usize = 0;
    errdefer {
        for (new_frames[0..built]) |frame| self.allocator.free(frame);
    }
    while (built < new_frames.len) : (built += 1) {
        new_frames[built] = try self.allocator.alloc(u8, columns * rows * 2);
    }

    // Nothing below can fail, so the swap is all-or-nothing.
    for (self.cache) |frame| {
        if (frame.len > 0) self.allocator.free(frame);
    }
    @memcpy(self.cache, new_frames);
    self.allocator.free(new_frames);

    @memset(self.cached, false);
    self.cache_count = 0;

    if (self.map_x.len > 0) self.allocator.free(self.map_x);
    if (self.map_y.len > 0) self.allocator.free(self.map_y);
    self.map_x = map_x;
    self.map_y = map_y;
    self.layout = layout;

    // Note: the compositor is created lazily in ensureCached(), never here.
    // rebuild() also runs from init(), where `self` is a local that gets copied
    // on return, so a compositor built here would hold a dangling &self.movie.
    if (self.compositor) |*compositor| compositor.reset();

    self.current = 0;
}

/// Decodes forward until `index` has been rendered into the cache.
fn ensureCached(self: *Gif, index: usize) !void {
    if (self.cached[index]) return;
    if (self.cache[index].len == 0) return error.GifCacheUnavailable;

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
            self.renderFrame(self.cache[decoded], compositor.canvas);
            self.cached[decoded] = true;
            self.cache_count += 1;
        }
        if (decoded == index) break;
    }

    // Every frame is rendered, so the composition canvas is dead weight now.
    if (self.cache_count == self.movie.frames.len) {
        if (self.compositor) |*c| c.deinit();
        self.compositor = null;
    }
}

/// Colour of one quadrant of the sampling grid, or the background outside it.
fn quadrantColor(self: *const Gif, canvas: []const u8, x: usize, y: usize) u32 {
    if (x < self.layout.x or y < self.layout.y) return TerminalBuffer.vt_palette[self.background];
    const i = x - self.layout.x;
    const j = y - self.layout.y;
    if (i >= self.layout.width or j >= self.layout.height) return TerminalBuffer.vt_palette[self.background];

    const index = canvas[@as(usize, self.map_y[j]) * self.movie.width + self.map_x[i]];
    if (index >= self.movie_colors.len) return TerminalBuffer.vt_palette[self.background];
    return self.movie_colors[index];
}

fn renderFrame(self: *const Gif, destination: []u8, canvas: []const u8) void {
    for (0..self.layout.rows) |row| {
        for (0..self.layout.columns) |column| {
            const quad = [4]u32{
                self.quadrantColor(canvas, column * 2, row * 2),
                self.quadrantColor(canvas, column * 2 + 1, row * 2),
                self.quadrantColor(canvas, column * 2, row * 2 + 1),
                self.quadrantColor(canvas, column * 2 + 1, row * 2 + 1),
            };
            const choice = self.chooseCell(quad);
            const at = (row * self.layout.columns + column) * 2;
            destination[at] = choice.slot;
            destination[at + 1] = (@as(u8, choice.fg) << 4) | choice.bg;
        }
    }
}

fn update(self: *Gif, _: *anyopaque) !void {
    if (self.failed) return;

    // One monotonic reading drives both the timeout and the frame cadence, so
    // an NTP step on the real clock can neither cut the animation short nor
    // leave it running forever.
    const now = std.Io.Timestamp.now(self.io, .awake).toMilliseconds();

    if (self.timeout_sec > 0 and now - self.start_ms > @as(i64, self.timeout_sec) * std.time.ms_per_s) {
        self.animate.* = false;
        return;
    }
    if (!self.animate.*) return;

    // The layout is built for one terminal size. realloc() refreshes it on a
    // resize, but rebuild it here too so a size that wasn't known yet at
    // startup heals on the next tick rather than disabling the wallpaper.
    if (self.layout.columns != self.terminal_buffer.width or
        self.layout.rows != self.terminal_buffer.height)
    {
        self.rebuild() catch |err| {
            try self.log_file.err(self.io, "tui", "failed to lay out the gif wallpaper: {s}", .{@errorName(err)});
            self.failed = true;
            self.animate.* = false;
            return;
        };
        if (self.layout.columns == 0) return;
    }

    // Advance if this frame has been on screen for its full delay.
    const delay: i64 = @intCast(self.movie.frames[self.current].delay_ms);
    var next = self.current;
    if (now - self.time_previous >= delay) {
        self.time_previous = now;
        next = (self.current + 1) % self.movie.frames.len;
    }

    self.ensureCached(next) catch |err| {
        // A broken stream shouldn't take the greeter down with it; stop
        // animating and leave whatever is on screen.
        try self.log_file.err(self.io, "tui", "failed to render gif frame {d}: {s}", .{ next, @errorName(err) });
        self.failed = true;
        self.animate.* = false;
        return;
    };

    self.current = next;
}

fn draw(self: *Gif) void {
    if (!self.animate.* or self.failed) return;
    if (!self.cached[self.current]) return;

    // A resize between rendering and drawing would make the cache the wrong
    // shape; realloc() rebuilds it, but be safe about the interim.
    if (self.layout.columns != self.terminal_buffer.width or
        self.layout.rows != self.terminal_buffer.height) return;

    const frame = self.cache[self.current];

    for (0..self.layout.rows) |row| {
        for (0..self.layout.columns) |column| {
            const at = (row * self.layout.columns + column) * 2;
            const slot = frame[at];
            const pair = frame[at + 1];
            self.terminal_buffer.setPaletteCell(
                column,
                row,
                self.glyphs[slot],
                @intCast(pair >> 4),
                @intCast(pair & 0x0F),
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
    // Same monotonic clock as update(), or the two would disagree.
    const now = std.Io.Timestamp.now(self.io, .awake).toMilliseconds();
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
    self.allocator.free(self.glyphs);
    self.allocator.free(self.uniforms);
    self.allocator.free(self.palette_lut);
    self.allocator.free(self.uniform_lut);
    self.allocator.free(self.movie_colors);
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

test "blend mixes two colours by ink coverage" {
    try std.testing.expectEqual(@as(u32, 0x000000), blend(0x000000, 0xFFFFFF, 0.0));
    try std.testing.expectEqual(@as(u32, 0xFFFFFF), blend(0x000000, 0xFFFFFF, 1.0));
    try std.testing.expectEqual(@as(u32, 0x808080), blend(0x000000, 0xFFFFFF, 0.5));
}

test "the colour cube round-trips" {
    for (0..(@as(usize, 1) << (3 * uniform_lut_bits))) |i| {
        try std.testing.expectEqual(i, cubeIndex(cubeColor(i, uniform_lut_bits), uniform_lut_bits));
    }
}

test "every quadrant arrangement is covered exactly once" {
    var seen = [_]bool{false} ** 16;
    for (quadrants) |q| {
        try std.testing.expect(!seen[q.mask]);
        seen[q.mask] = true;
    }
    for (seen) |s| try std.testing.expect(s);
}

/// Builds a Gif with only the pieces chooseCell needs, so the cell matcher can
/// be exercised without a GIF file or a terminal.
fn testMatcher(allocator: Allocator, stipple: f32) !Gif {
    var self: Gif = undefined;
    self.uniforms = try buildUniforms(allocator);
    self.palette_lut = try buildPaletteLut(allocator);
    self.uniform_lut = try buildUniformLut(allocator, self.uniforms);
    self.stipple = stipple;
    return self;
}

fn freeMatcher(self: *Gif, allocator: Allocator) void {
    allocator.free(self.uniforms);
    allocator.free(self.palette_lut);
    allocator.free(self.uniform_lut);
}

test "chooseCell picks a flat block for a uniform cell" {
    const allocator = std.testing.allocator;
    var matcher = try testMatcher(allocator, 0.6);
    defer freeMatcher(&matcher, allocator);

    const white = matcher.chooseCell(.{ 0xFFFFFF, 0xFFFFFF, 0xFFFFFF, 0xFFFFFF });
    try std.testing.expectEqual(@as(u4, 15), white.fg);
    try std.testing.expectEqual(@as(u4, 15), white.bg);

    const black = matcher.chooseCell(.{ 0x000000, 0x000000, 0x000000, 0x000000 });
    try std.testing.expectEqual(TerminalBuffer.vt_palette[black.fg], @as(u32, 0x000000));
    try std.testing.expectEqual(TerminalBuffer.vt_palette[black.bg], @as(u32, 0x000000));
}

/// The four quadrant colours a choice actually paints. Complementary glyphs
/// (upper vs lower half with the colours swapped) render identically, so tests
/// compare what lands on screen rather than which codepoint was picked.
fn painted(choice: Choice) [4]u32 {
    const mask = quadrants[choice.slot].mask;
    var out: [4]u32 = undefined;
    for (0..4) |k| {
        const lit = mask & (@as(u4, 1) << @intCast(3 - k)) != 0;
        out[k] = TerminalBuffer.vt_palette[if (lit) choice.fg else choice.bg];
    }
    return out;
}

test "chooseCell splits a cell that differs top from bottom" {
    const allocator = std.testing.allocator;
    var matcher = try testMatcher(allocator, 0.6);
    defer freeMatcher(&matcher, allocator);

    const split = matcher.chooseCell(.{ 0xFFFFFF, 0xFFFFFF, 0x000000, 0x000000 });
    try std.testing.expect(split.slot < quadrants.len);
    try std.testing.expectEqual(
        [4]u32{ 0xFFFFFF, 0xFFFFFF, 0x000000, 0x000000 },
        painted(split),
    );
}

test "chooseCell splits left from right too" {
    const allocator = std.testing.allocator;
    var matcher = try testMatcher(allocator, 0.6);
    defer freeMatcher(&matcher, allocator);

    const split = matcher.chooseCell(.{ 0xFFFFFF, 0x000000, 0xFFFFFF, 0x000000 });
    try std.testing.expect(split.slot < quadrants.len);
    try std.testing.expectEqual(
        [4]u32{ 0xFFFFFF, 0x000000, 0xFFFFFF, 0x000000 },
        painted(split),
    );
}

test "chooseCell resolves a single bright quadrant" {
    const allocator = std.testing.allocator;
    var matcher = try testMatcher(allocator, 0.6);
    defer freeMatcher(&matcher, allocator);

    const corner = matcher.chooseCell(.{ 0xFFFFFF, 0x000000, 0x000000, 0x000000 });
    try std.testing.expect(corner.slot < quadrants.len);
    try std.testing.expectEqual(
        [4]u32{ 0xFFFFFF, 0x000000, 0x000000, 0x000000 },
        painted(corner),
    );
}

/// How far apart the two colours a choice mixes are; zero for a flat cell.
fn separationOf(choice: Choice) u32 {
    if (choice.fg == choice.bg) return 0;
    return TerminalBuffer.colorDistance(
        TerminalBuffer.vt_palette[choice.fg],
        TerminalBuffer.vt_palette[choice.bg],
    );
}

test "a colour the palette already has stays flat" {
    const allocator = std.testing.allocator;
    var matcher = try testMatcher(allocator, 0.6);
    defer freeMatcher(&matcher, allocator);

    // Light grey is a console colour, so there is nothing to gain by dithering.
    const on_palette = TerminalBuffer.vt_palette[7];
    const choice = matcher.chooseCell(.{ on_palette, on_palette, on_palette, on_palette });
    try std.testing.expectEqual(@as(u32, 0), separationOf(choice));
}

test "a hue the palette lacks is dithered rather than flattened" {
    const allocator = std.testing.allocator;
    var matcher = try testMatcher(allocator, 0.6);
    defer freeMatcher(&matcher, allocator);

    // Salmon: the nearest flat colour is a grey, which would drop the hue
    // entirely, so mixing is worth the stipple.
    const salmon: u32 = 0xF08080;
    const choice = matcher.chooseCell(.{ salmon, salmon, salmon, salmon });
    try std.testing.expect(choice.slot >= quadrants.len);
    try std.testing.expect(choice.fg != choice.bg);
}

test "the stipple penalty prefers closer colour pairs on neutral tones" {
    const allocator = std.testing.allocator;

    // A desaturated blue-grey, the sort of tone that can be faked either by
    // mixing two near neighbours or by mixing two distant colours. The penalty
    // should steer away from the distant pair, which is what reads as stipple.
    const neutral: u32 = 0x9FA8B0;

    var loose = try testMatcher(allocator, 0.0);
    defer freeMatcher(&loose, allocator);
    const unpenalised = loose.chooseCell(.{ neutral, neutral, neutral, neutral });

    var tuned = try testMatcher(allocator, 4.0);
    defer freeMatcher(&tuned, allocator);
    const penalised = tuned.chooseCell(.{ neutral, neutral, neutral, neutral });

    try std.testing.expect(separationOf(penalised) <= separationOf(unpenalised));
}
