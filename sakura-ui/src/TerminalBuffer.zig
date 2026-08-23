const std = @import("std");
const Allocator = std.mem.Allocator;
const Random = std.Random;

const sakura_core = @import("sakura-core");
const interop = sakura_core.interop;
const LogFile = sakura_core.LogFile;
const SharedError = sakura_core.SharedError;
pub const termbox = @import("termbox2");

const Cell = @import("Cell.zig");
const keyboard = @import("keyboard.zig");
const Position = @import("Position.zig");
const Widget = @import("Widget.zig");

const TerminalBuffer = @This();

pub const KeybindCallbackFn = *const fn (*anyopaque) anyerror!bool;
pub const KeybindMap = std.AutoHashMap(keyboard.Key, struct {
    callback: KeybindCallbackFn,
    context: *anyopaque,
});

pub const InitOptions = struct {
    fg: u32,
    bg: u32,
    border_fg: u32,
    full_color: bool,
    is_tty: bool,
};

pub const Styling = struct {
    pub const BOLD = termbox.TB_BOLD;
    pub const UNDERLINE = termbox.TB_UNDERLINE;
    pub const REVERSE = termbox.TB_REVERSE;
    pub const ITALIC = termbox.TB_ITALIC;
    pub const BLINK = termbox.TB_BLINK;
    pub const HI_BLACK = termbox.TB_HI_BLACK;
    pub const BRIGHT = termbox.TB_BRIGHT;
    pub const DIM = termbox.TB_DIM;
};

pub const Color = struct {
    pub const DEFAULT = 0x00000000;
    pub const TRUE_BLACK = Styling.HI_BLACK;
    pub const TRUE_RED = 0x00FF0000;
    pub const TRUE_GREEN = 0x0000FF00;
    pub const TRUE_YELLOW = 0x00FFFF00;
    pub const TRUE_BLUE = 0x000000FF;
    pub const TRUE_MAGENTA = 0x00FF00FF;
    pub const TRUE_CYAN = 0x0000FFFF;
    pub const TRUE_WHITE = 0x00FFFFFF;
    pub const TRUE_DIM_RED = 0x00800000;
    pub const TRUE_DIM_GREEN = 0x00008000;
    pub const TRUE_DIM_YELLOW = 0x00808000;
    pub const TRUE_DIM_BLUE = 0x00000080;
    pub const TRUE_DIM_MAGENTA = 0x00800080;
    pub const TRUE_DIM_CYAN = 0x00008080;
    pub const TRUE_DIM_WHITE = 0x00C0C0C0;
    pub const ECOL_BLACK = 1;
    pub const ECOL_RED = 2;
    pub const ECOL_GREEN = 3;
    pub const ECOL_YELLOW = 4;
    pub const ECOL_BLUE = 5;
    pub const ECOL_MAGENTA = 6;
    pub const ECOL_CYAN = 7;
    pub const ECOL_WHITE = 8;
};

pub const START_POSITION = Position.init(0, 0);

log_file: *LogFile,
random: Random,
width: usize,
height: usize,
fg: u32,
bg: u32,
border_fg: u32,
box_chars: struct {
    left_up: u32,
    left_down: u32,
    right_up: u32,
    right_down: u32,
    top: u32,
    bottom: u32,
    left: u32,
    right: u32,
},
blank_cell: Cell,
full_color: bool,
termios: ?std.posix.termios,
keybinds: KeybindMap,
handlable_widgets: std.ArrayList(*Widget),
run: bool,
update: bool,
active_widget_index: usize,

pub fn init(
    allocator: Allocator,
    io: std.Io,
    options: InitOptions,
    log_file: *LogFile,
    random: Random,
) !TerminalBuffer {
    // Initialize termbox
    var err = termbox.tb_init();
    if (err != 0) {
        try log_file.err(
            io,
            "tui",
            "failed to initialise termbox2: {s}, term: {s}",
            .{ termbox.tb_strerror(err), std.c.getenv("TERM").? },
        );
        return error.TermboxInitFailed;
    }

    if (options.full_color) {
        err = termbox.tb_set_output_mode(termbox.TB_OUTPUT_256);
        if (err != 0) {
            try log_file.err(
                io,
                "tui",
                "failed to set termbox2 output mode to 256 color: {s}",
                .{termbox.tb_strerror(err)},
            );
            return error.TermboxSetOutputModeFailed;
        }
        color_mode = .palette_256;
        try log_file.info(
            io,
            "tui",
            "termbox2 set to 256-color output mode",
            .{},
        );
    } else {
        color_mode = .eight;
        try log_file.info(
            io,
            "tui",
            "termbox2 set to eight-color output mode",
            .{},
        );
    }

    // Let's take some precautions here and clear the back buffer as well
    try clearScreen(true);

    const width = getWidth();
    const height = getHeight();

    try log_file.info(
        io,
        "tui",
        "screen resolution is {d}x{d}",
        .{ width, height },
    );

    return .{
        .log_file = log_file,
        .random = random,
        .width = width,
        .height = height,
        .fg = options.fg,
        .bg = options.bg,
        .border_fg = options.border_fg,
        .box_chars = if (interop.supportsUnicode()) .{
            .left_up = 0x250C,
            .left_down = 0x2514,
            .right_up = 0x2510,
            .right_down = 0x2518,
            .top = 0x2500,
            .bottom = 0x2500,
            .left = 0x2502,
            .right = 0x2502,
        } else .{
            .left_up = '+',
            .left_down = '+',
            .right_up = '+',
            .right_down = '+',
            .top = '-',
            .bottom = '-',
            .left = '|',
            .right = '|',
        },
        .blank_cell = Cell.init(' ', options.fg, options.bg),
        .full_color = options.full_color,
        // Needed to reclaim the TTY after giving up its control
        .termios = try std.posix.tcgetattr(std.posix.STDIN_FILENO),
        .keybinds = KeybindMap.init(allocator),
        .handlable_widgets = .empty,
        .run = true,
        .update = true,
        .active_widget_index = 0,
    };
}

pub fn deinit(self: *TerminalBuffer) void {
    self.keybinds.deinit();
    TerminalBuffer.shutdown() catch {};
}

pub fn runEventLoop(
    self: *TerminalBuffer,
    allocator: Allocator,
    io: std.Io,
    shared_error: SharedError,
    layers: [][]*Widget,
    active_widget: *Widget,
    inactivity_delay: u16,
    position_widgets_fn: *const fn (*anyopaque) anyerror!void,
    inactivity_event_fn: ?*const fn (*anyopaque) anyerror!void,
    context: *anyopaque,
) !void {
    try self.registerGlobalKeybind(io, "Ctrl+K", &moveCursorUp, self);
    try self.registerGlobalKeybind(io, "Up", &moveCursorUp, self);

    try self.registerGlobalKeybind(io, "Ctrl+J", &moveCursorDown, self);
    try self.registerGlobalKeybind(io, "Down", &moveCursorDown, self);

    try self.registerGlobalKeybind(io, "Tab", &wrapCursor, self);
    try self.registerGlobalKeybind(io, "Shift+Tab", &wrapCursorReverse, self);

    defer self.handlable_widgets.deinit(allocator);

    var i: usize = 0;
    for (layers) |layer| {
        for (layer) |widget| {
            try widget.update(context);

            if (widget.vtable.handle_fn != null) {
                try self.handlable_widgets.append(allocator, widget);

                if (widget.id == active_widget.id) self.active_widget_index = i;
                i += 1;
            }
        }
    }

    try @call(.auto, position_widgets_fn, .{context});

    var event: termbox.tb_event = undefined;
    var inactivity_cmd_ran = false;
    var inactivity_time_start = try interop.getTimeOfDay();

    while (self.run) {
        var maybe_timeout: ?usize = null;

        if (self.update) {
            try TerminalBuffer.clearScreen(false);

            // Reset cursor
            const current_widget = self.getActiveWidget();
            current_widget.handle(null) catch |err| {
                shared_error.writeError(error.SetCursorFailed);
                try self.log_file.err(
                    io,
                    "tui",
                    "failed to set cursor in active widget '{s}': {s}",
                    .{ current_widget.display_name, @errorName(err) },
                );
            };

            for (layers) |layer| {
                for (layer) |widget| {
                    try widget.update(context);
                    widget.draw();

                    if (try widget.calculateTimeout(context)) |widget_timeout| {
                        if (maybe_timeout == null or widget_timeout < maybe_timeout.?) maybe_timeout = widget_timeout;
                    }
                }
            }

            // We don't care about present errors here
            TerminalBuffer.presentBuffer() catch {};
        }

        if (inactivity_event_fn) |inactivity_fn| {
            const time = try interop.getTimeOfDay();

            if (!inactivity_cmd_ran and time.seconds - inactivity_time_start.seconds > inactivity_delay) {
                try @call(.auto, inactivity_fn, .{context});
                inactivity_cmd_ran = true;
            }
        }

        const event_error = if (maybe_timeout) |timeout| termbox.tb_peek_event(&event, @intCast(timeout)) else termbox.tb_poll_event(&event);

        self.update = maybe_timeout != null or event_error >= 0;

        if (event_error < 0) continue;

        // Input of some kind was detected, so reset the inactivity timer
        inactivity_time_start = try interop.getTimeOfDay();

        if (event.type == termbox.TB_EVENT_RESIZE) {
            self.width = TerminalBuffer.getWidth();
            self.height = TerminalBuffer.getHeight();

            try self.log_file.info(
                io,
                "tui",
                "screen resolution updated to {d}x{d}",
                .{ self.width, self.height },
            );

            for (layers) |layer| {
                for (layer) |widget| {
                    widget.realloc() catch |err| {
                        shared_error.writeError(error.WidgetReallocationFailed);
                        try self.log_file.err(
                            io,
                            "tui",
                            "failed to reallocate widget '{s}': {s}",
                            .{ widget.display_name, @errorName(err) },
                        );
                    };
                }
            }

            try @call(.auto, position_widgets_fn, .{context});

            self.update = true;
            continue;
        }

        var maybe_keys = try self.handleKeybind(allocator, event);
        if (maybe_keys) |*keys| {
            defer keys.deinit(allocator);

            const current_widget = self.getActiveWidget();
            for (keys.items) |key| {
                current_widget.handle(key) catch |err| {
                    shared_error.writeError(error.CurrentWidgetHandlingFailed);
                    try self.log_file.err(
                        io,
                        "tui",
                        "failed to handle active widget '{s}': {s}",
                        .{ current_widget.display_name, @errorName(err) },
                    );
                };
            }

            self.update = true;
        }
    }
}

pub fn stopEventLoop(self: *TerminalBuffer) void {
    self.run = false;
}

pub fn drawNextFrame(self: *TerminalBuffer, value: bool) void {
    self.update = value;
}

pub fn getActiveWidget(self: *TerminalBuffer) *Widget {
    return self.handlable_widgets.items[self.active_widget_index];
}

pub fn setActiveWidget(self: *TerminalBuffer, widget: *Widget) void {
    for (self.handlable_widgets.items, 0..) |widg, i| {
        if (widg.id == widget.id) self.active_widget_index = i;
    }
}

pub fn getWidth() usize {
    return @intCast(termbox.tb_width());
}

pub fn getHeight() usize {
    return @intCast(termbox.tb_height());
}

pub fn setCursor(x: usize, y: usize) !void {
    if (termbox.tb_set_cursor(@intCast(x), @intCast(y)) != 0) {
        return error.TermboxSetCursorFailed;
    }
}

pub fn clearScreen(clear_back_buffer: bool) !void {
    if (termbox.tb_clear() != 0) return error.TermboxClearFailed;
    if (clear_back_buffer) try clearBackBuffer();
}

pub fn shutdown() !void {
    if (termbox.tb_shutdown() != 0) return error.TermboxShutdownFailed;
}

pub fn presentBuffer() !void {
    if (termbox.tb_present() != 0) return error.TermboxPresentFailed;
}

pub fn getCell(x: usize, y: usize) ?Cell {
    var maybe_cell: ?*termbox.tb_cell = undefined;
    if (termbox.tb_get_cell(
        @intCast(x),
        @intCast(y),
        1,
        &maybe_cell,
    ) != 0) {
        return null;
    }

    if (maybe_cell) |cell| {
        return Cell.init(cell.ch, cell.fg, cell.bg);
    }

    return null;
}

// FreeBSD's console terminal emulator accepts at most eight parameters in a
// CSI sequence (T_NUMSIZE in sys/teken/teken.h) and abandons the escape at the
// ninth, printing everything after it as literal text. termbox2's 24-bit SGR
// needs ten of them -- 38;2;R;G;B;48;2;R;G;B -- so true colour is unusable on
// the console: the tail of every sequence lands on screen as digits. The
// 256-colour form, 38;5;N;48;5;M, needs six and teken implements it, so colours
// are quantised to the xterm palette on the way out.
const ColorMode = enum { eight, palette_256 };
var color_mode: ColorMode = .eight;

/// The six levels the xterm 6x6x6 colour cube is built from.
const cube_levels = [6]u8{ 0, 95, 135, 175, 215, 255 };

fn cubeLevel(value: u8) usize {
    var best: usize = 0;
    var best_distance: u16 = std.math.maxInt(u16);
    for (cube_levels, 0..) |level, i| {
        const distance = @abs(@as(i16, value) - @as(i16, level));
        if (distance < best_distance) {
            best_distance = distance;
            best = i;
        }
    }
    return best;
}

fn channelDistance(r: u8, g: u8, b: u8, cr: u8, cg: u8, cb: u8) u32 {
    const dr = @as(i32, r) - @as(i32, cr);
    const dg = @as(i32, g) - @as(i32, cg);
    const db = @as(i32, b) - @as(i32, cb);
    return @intCast(dr * dr + dg * dg + db * db);
}

/// Nearest xterm-256 index, considering both the colour cube and the grayscale
/// ramp. Never returns 0..15, so it can't collide with "terminal default".
fn index256(r: u8, g: u8, b: u8) u32 {
    const ri = cubeLevel(r);
    const gi = cubeLevel(g);
    const bi = cubeLevel(b);
    const cube_error = channelDistance(r, g, b, cube_levels[ri], cube_levels[gi], cube_levels[bi]);

    // The grayscale ramp runs 232..255 as 8, 18, ... 238.
    const average = (@as(u32, r) + @as(u32, g) + @as(u32, b)) / 3;
    const step: u32 = if (average <= 8) 0 else @min((average - 8 + 5) / 10, 23);
    const gray: u8 = @intCast(8 + 10 * step);
    const gray_error = channelDistance(r, g, b, gray, gray, gray);

    if (gray_error < cube_error) return 232 + step;
    return 16 + 36 * @as(u32, @intCast(ri)) + 6 * @as(u32, @intCast(gi)) + @as(u32, @intCast(bi));
}

/// Maps a 0xSSRRGGBB value onto what the current output mode expects, keeping
/// the styling byte intact.
fn toTerminalColor(value: u32) u32 {
    // In eight-colour mode the low bits are already palette indices.
    if (color_mode == .eight) return value;

    const rgb = value & 0x00FFFFFF;
    // Zero means "the terminal's default colour"; real black is asked for with
    // TB_HI_BLACK, which termbox2 resolves by itself. Either way, leave it be.
    if (rgb == 0) return value;

    const styling = value & 0xFF000000;
    return styling | index256(
        @intCast((rgb >> 16) & 0xFF),
        @intCast((rgb >> 8) & 0xFF),
        @intCast(rgb & 0xFF),
    );
}

pub fn setCell(x: usize, y: usize, cell: Cell) !void {
    if (termbox.tb_set_cell(
        @intCast(x),
        @intCast(y),
        cell.ch,
        toTerminalColor(cell.fg),
        toTerminalColor(cell.bg),
    ) != 0) {
        return error.TermboxSetCellFailed;
    }
}

pub fn setCellBoundsChecked(self: *TerminalBuffer, x: isize, y: isize, cell: Cell) !void {
    if (0 <= x and x < self.width and 0 <= y and y < self.height) {
        try cell.put(@intCast(x), @intCast(y));
    }
}

pub fn reclaim(self: TerminalBuffer) !void {
    if (self.termios) |termios| {
        // Take back control of the TTY
        const err = termbox.tb_init();
        if (err != 0 and err != termbox.TB_ERR_INIT_ALREADY) return error.TermboxReinitFailed;

        if (self.full_color and termbox.tb_set_output_mode(termbox.TB_OUTPUT_256) != 0) {
            return error.TermboxSetOutputModeFailed;
        }

        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, termios);
    }
}

pub fn registerKeybind(
    self: *TerminalBuffer,
    io: std.Io,
    keybinds: *KeybindMap,
    keybind: []const u8,
    callback: KeybindCallbackFn,
    context: *anyopaque,
) !void {
    const key = try self.parseKeybind(io, keybind);

    keybinds.put(key, .{
        .callback = callback,
        .context = context,
    }) catch |err| {
        try self.log_file.err(
            io,
            "tui",
            "failed to register keybind {s}: {s}",
            .{ keybind, @errorName(err) },
        );
    };
}

pub fn registerGlobalKeybind(
    self: *TerminalBuffer,
    io: std.Io,
    keybind: []const u8,
    callback: KeybindCallbackFn,
    context: *anyopaque,
) !void {
    try self.registerKeybind(io, &self.keybinds, keybind, callback, context);
}

pub fn simulateKeybind(self: *TerminalBuffer, io: std.Io, keybind: []const u8) !bool {
    const key = try self.parseKeybind(io, keybind);

    if (self.keybinds.get(key)) |binding| {
        return try @call(
            .auto,
            binding.callback,
            .{binding.context},
        );
    }

    const current_widget = self.getActiveWidget();
    if (current_widget.keybinds) |keybinds| {
        if (keybinds.get(key)) |binding| {
            return try @call(
                .auto,
                binding.callback,
                .{binding.context},
            );
        }
    }

    return true;
}

pub fn drawText(
    text: []const u8,
    x: usize,
    y: usize,
    fg: u32,
    bg: u32,
) !void {
    const utf8view = std.unicode.Utf8View.init(text) catch return;
    var utf8 = utf8view.iterator();

    var i = x;
    while (utf8.nextCodepoint()) |codepoint| : (i += @intCast(termbox.tb_wcwidth(codepoint))) {
        const cell = Cell.init(codepoint, fg, bg);
        try cell.put(i, y);
    }
}

pub fn drawConfinedText(
    text: []const u8,
    x: usize,
    y: usize,
    max_length: usize,
    fg: u32,
    bg: u32,
) !void {
    const utf8view = std.unicode.Utf8View.init(text) catch return;
    var utf8 = utf8view.iterator();

    var i = x;
    while (utf8.nextCodepoint()) |codepoint| : (i += @intCast(termbox.tb_wcwidth(codepoint))) {
        if (i - x >= max_length) break;

        const cell = Cell.init(codepoint, fg, bg);
        try cell.put(i, y);
    }
}

pub fn drawCharMultiple(
    char: u32,
    x: usize,
    y: usize,
    length: usize,
    fg: u32,
    bg: u32,
) !void {
    const cell = Cell.init(char, fg, bg);
    for (0..length) |xx| try cell.put(x + xx, y);
}

// Every codepoint is assumed to have a width of 1.
// Since Sakura is normally running in a TTY, this should be fine.
pub fn strWidth(str: []const u8) usize {
    const utf8view = std.unicode.Utf8View.init(str) catch return str.len;
    var utf8 = utf8view.iterator();
    var length: c_int = 0;

    while (utf8.nextCodepoint()) |codepoint| {
        length += termbox.tb_wcwidth(codepoint);
    }

    return @intCast(length);
}

fn clearBackBuffer() !void {
    if (termbox.global.initialized == 0) return;

    // Clear the TTY because termbox2 doesn't seem to do it properly
    const capability = termbox.global.caps[termbox.TB_CAP_CLEAR_SCREEN];
    const capability_slice = std.mem.span(capability);
    const result = std.posix.system.write(termbox.global.ttyfd, capability_slice.ptr, capability_slice.len);

    if (result != capability_slice.len) return error.PartialClearBackBuffer;
    if (result < 0) return error.ClearBackBufferFailed;
}

fn parseKeybind(self: *TerminalBuffer, io: std.Io, keybind: []const u8) !keyboard.Key {
    var key = std.mem.zeroes(keyboard.Key);
    var iterator = std.mem.splitScalar(u8, keybind, '+');

    while (iterator.next()) |item| {
        var found = false;

        inline for (comptime std.meta.fieldNames(keyboard.Key)) |name| {
            if (std.ascii.eqlIgnoreCase(name, item)) {
                @field(key, name) = true;
                found = true;
                break;
            }
        }

        if (!found) {
            try self.log_file.err(
                io,
                "tui",
                "failed to parse key {s} of keybind {s}",
                .{ item, keybind },
            );
        }
    }

    return key;
}

fn handleKeybind(
    self: *TerminalBuffer,
    allocator: Allocator,
    tb_event: termbox.tb_event,
) !?std.ArrayList(keyboard.Key) {
    var keys = try keyboard.getKeyList(allocator, tb_event);

    for (keys.items) |key| {
        if (self.keybinds.get(key)) |binding| {
            const passthrough_event = try @call(
                .auto,
                binding.callback,
                .{binding.context},
            );

            if (!passthrough_event) {
                keys.deinit(allocator);
                return null;
            }

            return keys;
        }

        const current_widget = self.getActiveWidget();
        if (current_widget.keybinds) |keybinds| {
            if (keybinds.get(key)) |binding| {
                const passthrough_event = try @call(
                    .auto,
                    binding.callback,
                    .{binding.context},
                );

                if (!passthrough_event) {
                    keys.deinit(allocator);
                    return null;
                }

                return keys;
            }
        }
    }

    return keys;
}

fn moveCursorUp(ptr: *anyopaque) !bool {
    var state: *TerminalBuffer = @ptrCast(@alignCast(ptr));
    if (state.active_widget_index == 0) return false;

    state.active_widget_index -= 1;
    state.update = true;
    return false;
}

fn moveCursorDown(ptr: *anyopaque) !bool {
    var state: *TerminalBuffer = @ptrCast(@alignCast(ptr));
    if (state.active_widget_index == state.handlable_widgets.items.len - 1) return false;

    state.active_widget_index += 1;
    state.update = true;
    return false;
}

fn wrapCursor(ptr: *anyopaque) !bool {
    var state: *TerminalBuffer = @ptrCast(@alignCast(ptr));

    state.active_widget_index = (state.active_widget_index + 1) % state.handlable_widgets.items.len;
    state.update = true;
    return false;
}

fn wrapCursorReverse(ptr: *anyopaque) !bool {
    var state: *TerminalBuffer = @ptrCast(@alignCast(ptr));

    state.active_widget_index = if (state.active_widget_index == 0) state.handlable_widgets.items.len - 1 else state.active_widget_index - 1;
    state.update = true;
    return false;
}

test "index256 maps onto the xterm palette" {
    const expectEqual = std.testing.expectEqual;

    // Corners of the 6x6x6 colour cube.
    try expectEqual(@as(u32, 16), index256(0, 0, 0));
    try expectEqual(@as(u32, 231), index256(255, 255, 255));
    // 95,135,175 are cube levels 1, 2 and 3: 16 + 36*1 + 6*2 + 3.
    try expectEqual(@as(u32, 67), index256(95, 135, 175));

    // A neutral grey is served better by the 232..255 ramp than by the cube.
    try expectEqual(@as(u32, 244), index256(128, 128, 128));

    // Never produces an index that could be mistaken for "terminal default"
    // or for one of the eight ANSI colours.
    var r: u32 = 0;
    while (r < 256) : (r += 17) {
        var g: u32 = 0;
        while (g < 256) : (g += 17) {
            var b: u32 = 0;
            while (b < 256) : (b += 17) {
                const index = index256(@intCast(r), @intCast(g), @intCast(b));
                try std.testing.expect(index >= 16 and index <= 255);
            }
        }
    }
}

test "toTerminalColor keeps styling and passes defaults through" {
    const expectEqual = std.testing.expectEqual;

    color_mode = .palette_256;
    defer color_mode = .eight;

    // Terminal default stays default.
    try expectEqual(@as(u32, 0), toTerminalColor(Color.DEFAULT));
    // Explicit black is requested with the style bit and must survive intact.
    try expectEqual(@as(u32, Styling.HI_BLACK), toTerminalColor(Color.TRUE_BLACK));

    // The styling byte is preserved and the colour lands in the low byte.
    const bold_white = toTerminalColor(Styling.BOLD | Color.TRUE_WHITE);
    try expectEqual(@as(u32, Styling.BOLD), bold_white & 0xFF000000);
    try expectEqual(@as(u32, 231), bold_white & 0xFF);

    // Eight-colour mode must not touch the value at all.
    color_mode = .eight;
    try expectEqual(@as(u32, Color.ECOL_RED), toTerminalColor(Color.ECOL_RED));
    try expectEqual(@as(u32, Color.TRUE_WHITE), toTerminalColor(Color.TRUE_WHITE));
}
