const std = @import("std");

/// A terminal color: one of the 16 standard ANSI colors, a 256-color
/// palette index, or a 24-bit RGB value.
pub const Color = union(enum) {
    default,
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bright_black,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,
    indexed: u8,
    true_color: struct { r: u8, g: u8, b: u8 },

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .true_color = .{ .r = r, .g = g, .b = b } };
    }

    fn writeFgCode(self: Color, writer: *std.Io.Writer) !void {
        switch (self) {
            .default => try writer.writeAll("39"),
            .black => try writer.writeAll("30"),
            .red => try writer.writeAll("31"),
            .green => try writer.writeAll("32"),
            .yellow => try writer.writeAll("33"),
            .blue => try writer.writeAll("34"),
            .magenta => try writer.writeAll("35"),
            .cyan => try writer.writeAll("36"),
            .white => try writer.writeAll("37"),
            .bright_black => try writer.writeAll("90"),
            .bright_red => try writer.writeAll("91"),
            .bright_green => try writer.writeAll("92"),
            .bright_yellow => try writer.writeAll("93"),
            .bright_blue => try writer.writeAll("94"),
            .bright_magenta => try writer.writeAll("95"),
            .bright_cyan => try writer.writeAll("96"),
            .bright_white => try writer.writeAll("97"),
            .indexed => |i| try writer.print("38;5;{d}", .{i}),
            .true_color => |c| try writer.print("38;2;{d};{d};{d}", .{ c.r, c.g, c.b }),
        }
    }

    fn writeBgCode(self: Color, writer: *std.Io.Writer) !void {
        switch (self) {
            .default => try writer.writeAll("49"),
            .black => try writer.writeAll("40"),
            .red => try writer.writeAll("41"),
            .green => try writer.writeAll("42"),
            .yellow => try writer.writeAll("43"),
            .blue => try writer.writeAll("44"),
            .magenta => try writer.writeAll("45"),
            .cyan => try writer.writeAll("46"),
            .white => try writer.writeAll("47"),
            .bright_black => try writer.writeAll("100"),
            .bright_red => try writer.writeAll("101"),
            .bright_green => try writer.writeAll("102"),
            .bright_yellow => try writer.writeAll("103"),
            .bright_blue => try writer.writeAll("104"),
            .bright_magenta => try writer.writeAll("105"),
            .bright_cyan => try writer.writeAll("106"),
            .bright_white => try writer.writeAll("107"),
            .indexed => |i| try writer.print("48;5;{d}", .{i}),
            .true_color => |c| try writer.print("48;2;{d};{d};{d}", .{ c.r, c.g, c.b }),
        }
    }
};

/// Text attributes that can be layered on top of foreground/background colors.
pub const Modifiers = packed struct {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    reverse: bool = false,
    strikethrough: bool = false,

    pub const none: Modifiers = .{};

    pub fn eql(a: Modifiers, b: Modifiers) bool {
        return @as(u6, @bitCast(a)) == @as(u6, @bitCast(b));
    }
};

/// A visual style: foreground color, background color, and text modifiers.
/// `null` fields mean "inherit whatever the terminal already has" rather
/// than "default color", which lets styles be layered/patched.
pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    mods: Modifiers = .none,

    pub const default: Style = .{};

    pub fn withFg(self: Style, color: Color) Style {
        var s = self;
        s.fg = color;
        return s;
    }

    pub fn withBg(self: Style, color: Color) Style {
        var s = self;
        s.bg = color;
        return s;
    }

    pub fn bold(self: Style) Style {
        var s = self;
        s.mods.bold = true;
        return s;
    }

    pub fn dim(self: Style) Style {
        var s = self;
        s.mods.dim = true;
        return s;
    }

    pub fn italic(self: Style) Style {
        var s = self;
        s.mods.italic = true;
        return s;
    }

    pub fn underline(self: Style) Style {
        var s = self;
        s.mods.underline = true;
        return s;
    }

    pub fn reverse(self: Style) Style {
        var s = self;
        s.mods.reverse = true;
        return s;
    }

    /// Overlay `patch` on top of `self`: any field set in `patch` wins.
    pub fn patch(self: Style, over: Style) Style {
        return .{
            .fg = over.fg orelse self.fg,
            .bg = over.bg orelse self.bg,
            .mods = .{
                .bold = over.mods.bold or self.mods.bold,
                .dim = over.mods.dim or self.mods.dim,
                .italic = over.mods.italic or self.mods.italic,
                .underline = over.mods.underline or self.mods.underline,
                .reverse = over.mods.reverse or self.mods.reverse,
                .strikethrough = over.mods.strikethrough or self.mods.strikethrough,
            },
        };
    }

    pub fn eql(a: Style, b: Style) bool {
        return colorEql(a.fg, b.fg) and colorEql(a.bg, b.bg) and a.mods.eql(b.mods);
    }

    fn colorEql(a: ?Color, b: ?Color) bool {
        if (a == null and b == null) return true;
        if (a == null or b == null) return false;
        return std.meta.eql(a.?, b.?);
    }

    /// Write the ANSI SGR escape sequence that transitions the terminal
    /// from an unstyled state directly into this style.
    pub fn writeAnsi(self: Style, writer: *std.Io.Writer) !void {
        try writer.writeAll("\x1b[0");
        if (self.mods.bold) try writer.writeAll(";1");
        if (self.mods.dim) try writer.writeAll(";2");
        if (self.mods.italic) try writer.writeAll(";3");
        if (self.mods.underline) try writer.writeAll(";4");
        if (self.mods.reverse) try writer.writeAll(";7");
        if (self.mods.strikethrough) try writer.writeAll(";9");
        if (self.fg) |fg| {
            try writer.writeAll(";");
            try fg.writeFgCode(writer);
        }
        if (self.bg) |bg| {
            try writer.writeAll(";");
            try bg.writeBgCode(writer);
        }
        try writer.writeAll("m");
    }
};

test "style patch overlays only set fields" {
    const base = Style.default.withFg(.red).bold();
    const patched = base.patch(Style.default.withBg(.blue));
    try std.testing.expect(patched.fg.? == .red);
    try std.testing.expect(patched.bg.? == .blue);
    try std.testing.expect(patched.mods.bold);
}

test "style ansi rendering" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try Style.default.withFg(.red).bold().writeAnsi(&writer);
    try std.testing.expectEqualStrings("\x1b[0;1;31m", writer.buffered());
}

test "rgb color ansi rendering" {
    var buf: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buf);
    try Style.default.withFg(Color.rgb(10, 20, 30)).writeAnsi(&writer);
    try std.testing.expectEqualStrings("\x1b[0;38;2;10;20;30m", writer.buffered());
}
