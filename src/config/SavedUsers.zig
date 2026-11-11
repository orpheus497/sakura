const std = @import("std");

const SavedUsers = @This();

const User = struct {
    username: []const u8,
    session_index: usize,
    first_run: bool,
    allocated_username: bool,
    /// Field purpose: The name of the saved session, where one is known, so the
    /// selection can be restored by identity instead of by position.
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
    /// thing that produces a name, and it dupes both strings together.
    session_name: ?[]const u8 = null,
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
            if (user.session_name) |session_name| allocator.free(session_name);
        }
    }

    self.user_list.deinit(allocator);
}
