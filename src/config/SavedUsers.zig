const std = @import("std");

const SavedUsers = @This();

const User = struct {
    username: []const u8,
    session_index: usize,
    first_run: bool,
    allocated_username: bool,
    /// Field purpose: The identity of the saved session, where one is known, so
    /// the selection can be restored by it instead of by position.
    ///
    /// Written as "<display server>/<desktop file name stem>", for example
    /// "wayland/hikari-sakura". The stem alone is not unique: `waylandsessions`
    /// and the x11 equivalent each take a list of directories, so the same stem
    /// can appear in two of them, and the same stem can appear under two
    /// different session types -- a `hikari.desktop` in both the Wayland and
    /// the X11 directories would otherwise be indistinguishable here, and
    /// restoring the wrong one starts the wrong kind of session. Neither a type
    /// tag nor a path component can contain '/', so the first one separates the
    /// two parts unambiguously.
    ///
    /// A value with no '/' is a bare stem written by an earlier build and is
    /// matched on the stem alone.
    ///
    /// `session_index` alone cannot do that. It is an offset into a list whose
    /// composition is decided at startup -- which entries are installed, and
    /// which of them ask not to be listed -- so the moment that composition
    /// changes, the same number points at a different session and nothing in
    /// the number says so. Retiring one entry silently shifts every entry after
    /// it up by one.
    ///
    /// Owned by this entry whenever `allocated_username` is set, which is the
    /// case for every entry read from the save file; that reader is the only
    /// thing that produces a key, and it dupes both strings together.
    session_key: ?[]const u8 = null,
};

user_list: std.ArrayList(User),
last_username_index: ?usize,

pub fn init() SavedUsers {
    return .{
        .user_list = .empty,
        .last_username_index = null,
    };
}

pub fn deinit(self: *SavedUsers, allocator: std.mem.Allocator) void {
    for (self.user_list.items) |user| {
        if (user.allocated_username) {
            allocator.free(user.username);
            if (user.session_key) |session_key| allocator.free(session_key);
        }
    }

    self.user_list.deinit(allocator);
}
