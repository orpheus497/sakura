const std = @import("std");
const Allocator = std.mem.Allocator;

const keyboard = @import("../keyboard.zig");
const TerminalBuffer = @import("../TerminalBuffer.zig");
const Position = @import("../Position.zig");
const Widget = @import("../Widget.zig");

const page_size = std.heap.page_size_min;

// Action purpose: the whole-page ownership argument below only holds if the
// page size compiled in is the one the kernel actually uses. Zig gives FreeBSD
// the same value for page_size_min and page_size_max on every architecture it
// knows -- 4 KiB for x86, arm, aarch64, powerpc and riscv alike -- and Sakura
// builds for nothing else, so the two cannot diverge here. Nothing in the type
// system says that, though, so assert it: a future divergence, or an override
// of std.options.page_size_max, then fails the build instead of quietly
// producing a buffer that shares pages with its neighbours again.
comptime {
    std.debug.assert(page_size == std.heap.page_size_max);
}

/// The entry buffer is allocated page-aligned so that the pages it occupies
/// belong to it alone.
///
/// mlock(2) and munlock(2) work in whole pages. An ordinary heap allocation
/// starts wherever the allocator likes, so locking it means locking the pages
/// it straddles -- and *unlocking* it means unlocking them too, including any
/// part shared with a neighbouring allocation. With two `Text` widgets in play
/// and their teardown ordered by `defer`, destroying one could silently strip
/// the lock from the other's buffer. Owning whole pages outright removes the
/// question rather than reasoning about it.
const DynamicString = std.ArrayListAligned(u8, std.mem.Alignment.fromByteUnits(page_size));

/// Capacity reserved for the entry buffer at construction, as a whole number of
/// pages so the allocation keeps the exclusive ownership described above.
///
/// Reallocation is what leaks. `std.ArrayList` growth copies the bytes into a
/// fresh allocation and frees the old one **without wiping it**, so every
/// intermediate prefix of a typed password would survive in freed heap however
/// carefully `clear()` and `deinit()` wipe the allocation they can see. Taking
/// the whole buffer up front means there is only ever one allocation to wipe,
/// and only one to lock.
///
/// This is an over-provision, not a limit. Nothing rejects a longer entry: past
/// this point `growWiped` takes over, which is slower but keeps both guarantees
/// intact. A hard cap was considered and deliberately not taken, so that no one
/// is ever refused a password they can actually type.
const reserved_capacity = 4096;

/// Holds the buffer out of swap. The slice is page-aligned by construction and
/// a whole number of pages long, so the range handed to mlock(2) is exactly the
/// memory this buffer owns -- no widening, and nothing belonging to anyone else.
fn lockBuffer(slice: []align(page_size) u8) bool {
    if (slice.len == 0) return false;

    const addr: *align(page_size) const anyopaque = @ptrCast(slice.ptr);
    return std.c.mlock(addr, slice.len) == 0;
}

fn unlockBuffer(slice: []align(page_size) u8) void {
    if (slice.len == 0) return;

    const addr: *align(page_size) const anyopaque = @ptrCast(slice.ptr);
    _ = std.c.munlock(addr, slice.len);
}

const Text = @This();

instance: ?Widget,
allocator: Allocator,
buffer: *TerminalBuffer,
text: DynamicString,
end: usize,
cursor: usize,
visible_start: usize,
width: usize,
component_pos: Position,
children_pos: Position,
should_insert: bool,
masked: bool,
maybe_mask: ?u32,
fg: u32,
bg: u32,
keybinds: TerminalBuffer.KeybindMap,
/// Whether the entry buffer is held out of swap. Read by the caller so it can
/// say so; a failed lock is worth reporting but is not worth refusing to start
/// a login screen over.
locked: bool,

pub fn init(
    allocator: Allocator,
    io: std.Io,
    buffer: *TerminalBuffer,
    should_insert: bool,
    masked: bool,
    maybe_mask: ?u32,
    width: usize,
    fg: u32,
    bg: u32,
) !*Text {
    var self = try allocator.create(Text);
    self.* = Text{
        .instance = null,
        .allocator = allocator,
        .buffer = buffer,
        .text = .empty,
        .end = 0,
        .cursor = 0,
        .visible_start = 0,
        .width = width,
        .component_pos = TerminalBuffer.START_POSITION,
        .children_pos = TerminalBuffer.START_POSITION,
        .should_insert = should_insert,
        .masked = masked,
        .maybe_mask = maybe_mask,
        .fg = fg,
        .bg = bg,
        .keybinds = .init(allocator),
        .locked = false,
    };

    // Action purpose: from here on the widget owns a heap allocation, a keybind
    // map and possibly a memory lock, and every step below can still fail.
    // deinit() already releases exactly those, in the right order, so it is
    // what the unwind should run -- otherwise a failed keybind registration
    // leaks the entry buffer and leaves its pages locked for the life of the
    // process.
    errdefer self.deinit();

    // Action purpose: take the whole buffer now, then lock it. Doing it here is
    // what makes the wipes in clear() and deinit() total rather than partial --
    // there is no later reallocation to strand an unwiped copy in freed heap.
    // A failed lock is recorded, not raised: the login screen still works
    // without it, and the caller reports it through `err_mlock`.
    try self.text.ensureTotalCapacityPrecise(allocator, reserved_capacity);
    self.locked = lockBuffer(self.text.allocatedSlice());

    try buffer.registerKeybind(io, &self.keybinds, "Left", &goLeft, self);
    try buffer.registerKeybind(io, &self.keybinds, "Right", &goRight, self);
    try buffer.registerKeybind(io, &self.keybinds, "Delete", &delete, self);
    try buffer.registerKeybind(io, &self.keybinds, "Backspace", &backspace, self);
    try buffer.registerKeybind(io, &self.keybinds, "Ctrl+U", &clearTextEntry, self);

    return self;
}

pub fn deinit(self: *Text) void {
    // Action purpose: wipe before handing the buffer back. An allocator reuses
    // freed memory, it does not erase it, so the typed password would otherwise
    // stay legible in the heap of a root process. See clear() for why
    // secureZero rather than @memset.
    std.crypto.secureZero(u8, self.text.allocatedSlice());
    if (self.locked) unlockBuffer(self.text.allocatedSlice());
    self.text.deinit(self.allocator);
    self.keybinds.deinit();
    self.allocator.destroy(self);
}

pub fn widget(self: *Text) *Widget {
    if (self.instance) |*instance| return instance;
    self.instance = Widget.init(
        "Text",
        &self.keybinds,
        self,
        deinit,
        null,
        draw,
        null,
        handle,
        null,
    );
    return &self.instance.?;
}

pub fn positionX(self: *Text, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = original_pos.addX(self.width);
}

pub fn positionY(self: *Text, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = original_pos.addY(1);
}

pub fn positionXY(self: *Text, original_pos: Position) void {
    self.component_pos = original_pos;
    self.children_pos = Position.init(
        self.width,
        1,
    ).add(original_pos);
}

pub fn childrenPosition(self: Text) Position {
    return self.children_pos;
}

pub fn clear(self: *Text) void {
    // Action purpose: the whole allocation is wiped, not merely the part in
    // use. This buffer holds the typed password, and clearRetainingCapacity()
    // only moves the length to zero -- every byte stayed readable in the heap
    // of a process that runs as root for as long as the login screen is up, and
    // so could reach swap or a core file. secureZero is used rather than
    // @memset because the write is dead by ordinary analysis and is exactly the
    // kind of store an optimiser is entitled to remove.
    std.crypto.secureZero(u8, self.text.allocatedSlice());
    self.text.clearRetainingCapacity();
    self.end = 0;
    self.cursor = 0;
    self.visible_start = 0;
}

pub fn toggleMask(self: *Text) void {
    self.masked = !self.masked;
}

pub fn handle(self: *Text, maybe_key: ?keyboard.Key) !void {
    if (maybe_key) |key| {
        if (self.should_insert) {
            const maybe_character = key.getEnabledPrintableAscii();
            if (maybe_character) |character| try self.write(character);
        }
    }

    if (self.masked and self.maybe_mask == null) {
        try TerminalBuffer.setCursor(
            self.component_pos.x,
            self.component_pos.y,
        );
        return;
    }

    try TerminalBuffer.setCursor(
        self.component_pos.x + (self.cursor - self.visible_start),
        self.component_pos.y,
    );
}

pub fn writeText(self: *Text, str: []const u8) !void {
    for (str) |c| try self.write(c);
}

fn draw(self: *Text) void {
    if (self.masked) {
        if (self.maybe_mask) |mask| {
            if (self.width < 1) return;

            const length = @min(TerminalBuffer.strWidth(self.text.items), self.width - 1);
            if (length == 0) return;

            TerminalBuffer.drawCharMultiple(
                mask,
                self.component_pos.x,
                self.component_pos.y,
                length,
                self.fg,
                self.bg,
            ) catch {};
        }
        return;
    }

    const str_length = TerminalBuffer.strWidth(self.text.items);
    const length = @min(str_length, self.width);
    if (length == 0) return;

    const visible_slice = vs: {
        if (str_length > self.width and self.cursor < str_length) {
            break :vs self.text.items[self.visible_start..(self.width + self.visible_start)];
        } else {
            break :vs self.text.items[self.visible_start..];
        }
    };

    TerminalBuffer.drawText(
        visible_slice,
        self.component_pos.x,
        self.component_pos.y,
        self.fg,
        self.bg,
    ) catch {};
}

fn goLeft(ptr: *anyopaque) !bool {
    var self: *Text = @ptrCast(@alignCast(ptr));

    if (self.cursor == 0) return false;
    if (self.visible_start > 0) self.visible_start -= 1;

    self.cursor -= 1;
    return false;
}

fn goRight(ptr: *anyopaque) !bool {
    var self: *Text = @ptrCast(@alignCast(ptr));

    if (self.cursor >= self.end) return false;
    // A degenerate width leaves no column to move into, and self.width - 1
    // would wrap around.
    if (self.width == 0) return false;
    if (self.cursor - self.visible_start == self.width - 1) self.visible_start += 1;

    self.cursor += 1;
    return false;
}

fn delete(ptr: *anyopaque) !bool {
    var self: *Text = @ptrCast(@alignCast(ptr));

    if (self.cursor >= self.end or !self.should_insert) return false;

    _ = self.text.orderedRemove(self.cursor);

    self.end -= 1;
    return false;
}

fn backspace(ptr: *anyopaque) !bool {
    const self: *Text = @ptrCast(@alignCast(ptr));

    if (self.cursor == 0 or !self.should_insert) return false;

    _ = try goLeft(ptr);
    _ = try delete(ptr);
    return false;
}

// Function purpose: extends the entry buffer by hand once the reserve is used
// up, so that the allocation being retired is wiped and unlocked before it is
// released. Letting `std.ArrayList` grow on its own copies the bytes into a new
// allocation and frees the old one untouched, stranding a readable copy of
// everything typed so far in freed heap -- reintroducing precisely what
// `reserved_capacity` exists to prevent, at the moment the entry is longest.
// Growing by whole reserves keeps the replacement page-aligned and page-sized,
// which is what `lockBuffer` depends on for exclusive ownership of its pages.
fn growWiped(self: *Text) !void {
    var grown: DynamicString = .empty;
    errdefer grown.deinit(self.allocator);

    try grown.ensureTotalCapacityPrecise(self.allocator, self.text.capacity + reserved_capacity);

    // Action purpose: lock the replacement before anything is copied into it,
    // not after the copy has landed. Locking afterwards left the new allocation
    // holding a complete copy of the entry in swappable memory for the width of
    // the copy -- the one window the lock exists to close, at the moment the
    // entry is longest. Nothing between here and the assignment below can fail,
    // so the lock cannot be stranded on a buffer that is then discarded.
    const grown_locked = lockBuffer(grown.allocatedSlice());
    grown.appendSliceAssumeCapacity(self.text.items);

    const retired = self.text.allocatedSlice();
    std.crypto.secureZero(u8, retired);
    if (self.locked) unlockBuffer(retired);

    self.text.deinit(self.allocator);
    self.text = grown;
    self.locked = grown_locked;
}

fn write(self: *Text, char: u8) !void {
    if (char == 0) return;

    // Action purpose: never let the insert below be the thing that grows the
    // buffer. It would hand the old allocation back unwiped and unlocked;
    // growWiped retires it properly first.
    if (self.text.items.len == self.text.capacity) try self.growWiped();

    try self.text.insert(self.allocator, self.cursor, char);

    self.end += 1;
    _ = try goRight(self);
}

fn clearTextEntry(ptr: *anyopaque) !bool {
    var self: *Text = @ptrCast(@alignCast(ptr));

    if (!self.should_insert) return false;

    self.clear();
    self.buffer.drawNextFrame(true);
    return false;
}
