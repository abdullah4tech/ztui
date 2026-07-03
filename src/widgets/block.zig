const std = @import("std");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
const buffer = @import("../buffer.zig");

const Style = style.Style;
const Rect = layout.Rect;
const Buffer = buffer.Buffer;

pub const Borders = packed struct {
    top: bool = false,
    bottom: bool = false,
    left: bool = false,
    right: bool = false,

    pub const none: Borders = .{};
    pub const all: Borders = .{ .top = true, .bottom = true, .left = true, .right = true };
};

/// A bordered, optionally-titled frame. Draw it first, then render other
/// widgets into `block.inner(area)`.
pub const Block = struct {
    title: ?[]const u8 = null,
    borders: Borders = .all,
    border_style: Style = .default,
    title_style: Style = .default,
    style: Style = .default,

    pub fn withTitle(self: Block, title: []const u8) Block {
        var b = self;
        b.title = title;
        return b;
    }

    pub fn withBorders(self: Block, borders: Borders) Block {
        var b = self;
        b.borders = borders;
        return b;
    }

    pub fn withBorderStyle(self: Block, s: Style) Block {
        var b = self;
        b.border_style = s;
        return b;
    }

    pub fn withStyle(self: Block, s: Style) Block {
        var b = self;
        b.style = s;
        return b;
    }

    /// The area available for content, after subtracting borders that are present.
    pub fn inner(self: Block, area: Rect) Rect {
        var r = area;
        if (self.borders.left and r.width > 0) {
            r.x += 1;
            r.width -= 1;
        }
        if (self.borders.right and r.width > 0) {
            r.width -= 1;
        }
        if (self.borders.top and r.height > 0) {
            r.y += 1;
            r.height -= 1;
        }
        if (self.borders.bottom and r.height > 0) {
            r.height -= 1;
        }
        return r;
    }

    pub fn render(self: Block, area: Rect, buf: *Buffer) void {
        if (area.width == 0 or area.height == 0) return;

        buf.fill(area, " ", self.style);

        const right = area.x + area.width - 1;
        const bottom = area.y + area.height - 1;

        if (self.borders.top) {
            var x = area.x;
            while (x <= right) : (x += 1) buf.set(x, area.y, "─", self.border_style);
        }
        if (self.borders.bottom and bottom != area.y) {
            var x = area.x;
            while (x <= right) : (x += 1) buf.set(x, bottom, "─", self.border_style);
        }
        if (self.borders.left) {
            var y = area.y;
            while (y <= bottom) : (y += 1) buf.set(area.x, y, "│", self.border_style);
        }
        if (self.borders.right and right != area.x) {
            var y = area.y;
            while (y <= bottom) : (y += 1) buf.set(right, y, "│", self.border_style);
        }

        if (self.borders.top and self.borders.left) buf.set(area.x, area.y, "┌", self.border_style);
        if (self.borders.top and self.borders.right and right != area.x) buf.set(right, area.y, "┐", self.border_style);
        if (self.borders.bottom and self.borders.left and bottom != area.y) buf.set(area.x, bottom, "└", self.border_style);
        if (self.borders.bottom and self.borders.right and bottom != area.y and right != area.x) buf.set(right, bottom, "┘", self.border_style);

        if (self.title) |title| {
            if (self.borders.top and area.width > 2) {
                const start = area.x + 1;
                _ = buf.setString(start, area.y, " ", self.title_style);
                const written = buf.setString(start + 1, area.y, title, self.title_style);
                _ = buf.setString(start + 1 + written, area.y, " ", self.title_style);
            }
        }
    }
};

test "block inner shrinks by border thickness" {
    const b: Block = .{ .borders = .all };
    const area: Rect = .{ .x = 0, .y = 0, .width = 10, .height = 5 };
    const in = b.inner(area);
    try std.testing.expectEqual(@as(u16, 1), in.x);
    try std.testing.expectEqual(@as(u16, 1), in.y);
    try std.testing.expectEqual(@as(u16, 8), in.width);
    try std.testing.expectEqual(@as(u16, 3), in.height);
}

test "block render draws corners" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 4, .height = 3 });
    defer buf.deinit();
    const b: Block = .{ .borders = .all };
    b.render(buf.area, &buf);

    try std.testing.expectEqualStrings("┌", buf.get(0, 0).?.text());
    try std.testing.expectEqualStrings("┐", buf.get(3, 0).?.text());
    try std.testing.expectEqualStrings("└", buf.get(0, 2).?.text());
    try std.testing.expectEqualStrings("┘", buf.get(3, 2).?.text());
}

test "block title with multi-byte utf8 doesn't leak border dashes" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 12, .height = 3 });
    defer buf.deinit();
    const b: Block = (Block{}).withTitle("a\u{2014}b");
    b.render(buf.area, &buf);

    // Title occupies 3 display columns ("a", "—", "b") regardless of the
    // em dash's 3-byte UTF-8 encoding; the cell right after it must be the
    // trailing space the widget adds, not a leftover border dash.
    try std.testing.expectEqualStrings(" ", buf.get(1, 0).?.text());
    try std.testing.expectEqualStrings("a", buf.get(2, 0).?.text());
    try std.testing.expectEqualStrings("\u{2014}", buf.get(3, 0).?.text());
    try std.testing.expectEqualStrings("b", buf.get(4, 0).?.text());
    try std.testing.expectEqualStrings(" ", buf.get(5, 0).?.text());
    try std.testing.expectEqualStrings("─", buf.get(6, 0).?.text());
}
