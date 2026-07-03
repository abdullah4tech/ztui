const std = @import("std");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
const buffer = @import("../buffer.zig");

const Style = style.Style;
const Rect = layout.Rect;
const Buffer = buffer.Buffer;

/// Columnar data with an optional header row and a selectable, scrolling
/// highlight — process lists, file listings, anything with more than one
/// field per row. Column widths use the same `Constraint`s as `split()`.
///
/// Cell text is truncated to its column's byte width, so very wide
/// multi-byte UTF-8 cells may clip a codepoint early; this matches
/// `Paragraph`'s existing ASCII-width assumption.
pub const Table = struct {
    header: ?[]const []const u8 = null,
    rows: []const []const []const u8,
    widths: []const layout.Constraint,
    style: Style = .default,
    header_style: Style = Style.default.bold(),
    selected: ?usize = null,
    highlight_style: Style = Style.default.reverse(),
    column_spacing: u16 = 1,

    pub fn withSelected(self: Table, selected: ?usize) Table {
        var t = self;
        t.selected = selected;
        return t;
    }

    pub fn render(self: Table, area: Rect, buf: *Buffer, allocator: std.mem.Allocator) !void {
        if (area.width == 0 or area.height == 0 or self.widths.len == 0) return;

        const cols = try layout.split(allocator, area, .horizontal, self.widths);
        defer allocator.free(cols);

        var y = area.y;
        const bottom = area.y + area.height;

        if (self.header) |header| {
            if (y < bottom) {
                self.renderRow(header, cols, buf, y, self.header_style);
                y += 1;
            }
        }

        const body_height = bottom - y;
        const offset = self.scrollOffset(body_height);
        const visible = @min(self.rows.len -| offset, body_height);

        var i: usize = 0;
        while (i < visible) : (i += 1) {
            const idx = offset + i;
            const is_selected = self.selected != null and self.selected.? == idx;
            const row_style = if (is_selected) self.highlight_style else self.style;
            self.renderRow(self.rows[idx], cols, buf, y, row_style);
            y += 1;
        }
    }

    fn renderRow(self: Table, cells: []const []const u8, cols: []const Rect, buf: *Buffer, y: u16, row_style: Style) void {
        const first = cols[0];
        const last = cols[cols.len - 1];
        buf.fill(.{ .x = first.x, .y = y, .width = (last.x + last.width) - first.x, .height = 1 }, " ", row_style);

        for (cells, 0..) |cell, ci| {
            if (ci >= cols.len) break;
            const col = cols[ci];
            const width = col.width -| self.column_spacing;
            const shown = if (cell.len > width) cell[0..width] else cell;
            _ = buf.setString(col.x, y, shown, row_style);
        }
    }

    fn scrollOffset(self: Table, body_height: u16) usize {
        const selected = self.selected orelse return 0;
        if (body_height == 0 or selected < body_height) return 0;
        const max_offset = self.rows.len -| body_height;
        return @min(selected - body_height + 1, max_offset);
    }
};

test "table renders header and rows in their columns" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 20, .height = 3 });
    defer buf.deinit();

    const t: Table = .{
        .header = &.{ "name", "pid" },
        .rows = &.{
            &.{ "init", "1" },
            &.{ "sshd", "42" },
        },
        .widths = &.{ .{ .fill = 1 }, .{ .length = 6 } },
    };
    try t.render(buf.area, &buf, std.testing.allocator);

    try std.testing.expect(buf.get(0, 0).?.style.mods.bold);
    try std.testing.expectEqualStrings("i", buf.get(0, 1).?.text());
    try std.testing.expectEqualStrings("s", buf.get(0, 2).?.text());
}

test "table highlights the selected row and scrolls to keep it visible" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 2 });
    defer buf.deinit();

    const t: Table = .{
        .rows = &.{ &.{"a"}, &.{"b"}, &.{"c"}, &.{"d"} },
        .widths = &.{.{ .fill = 1 }},
        .selected = 3,
    };
    try t.render(buf.area, &buf, std.testing.allocator);

    try std.testing.expect(buf.get(0, 1).?.style.mods.reverse);
    try std.testing.expectEqualStrings("d", buf.get(0, 1).?.text());
}

test "table truncates cells wider than their column" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 1 });
    defer buf.deinit();

    const t: Table = .{
        .rows = &.{&.{"abcdef"}},
        .widths = &.{.{ .length = 4 }},
        .column_spacing = 0,
    };
    try t.render(buf.area, &buf, std.testing.allocator);

    // Column is fixed at length 4, so only "abcd" should be written; "ef"
    // must not leak past the column boundary.
    try std.testing.expectEqualStrings("d", buf.get(3, 0).?.text());
    try std.testing.expectEqualStrings(" ", buf.get(4, 0).?.text());
}
