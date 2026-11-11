const ini = @import("sakura-ui").sakura_core.ini;
const Ini = ini.Ini;

const enums = @import("enums.zig");
const DisplayServer = enums.DisplayServer;

pub const DesktopEntry = struct {
    Exec: []const u8 = "",
    Name: []const u8 = "",
    DesktopNames: ?[]u8 = null,
    Terminal: ?bool = null,

    // Both keys mean "do not offer this entry", and both are read because a
    // package that retires a session relies on them: the Desktop Entry
    // Specification calls Hidden "strictly equivalent to the .desktop file not
    // existing at all", and names installing a file with Hidden=true as the way
    // to uninstall an entry that has been renamed. NoDisplay is the weaker form
    // -- the program exists but belongs in no menu. Ignoring them left a
    // retired session in the list, where picking it runs an Exec line whose
    // target was deliberately removed.
    NoDisplay: ?bool = null,
    Hidden: ?bool = null,
};

pub const Entry = struct { @"Desktop Entry": DesktopEntry = .{} };

entry_ini: ?Ini(Entry) = null,
file_name: []const u8 = "",
name: []const u8 = "",
xdg_session_desktop: ?[]const u8 = null,
xdg_desktop_names: ?[]const u8 = null,
cmd: ?[]const u8 = null,
specifier: []const u8 = "",
display_server: DisplayServer = .wayland,
is_terminal: bool = false,
