const std = @import("std");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
const buffer = @import("../buffer.zig");

const Style = style.Style;
const Rect = layout.Rect;
const Buffer = buffer.Buffer;

/// A vertical list of selectable text items. When `selected` falls outside
/// the visible window, rendering scrolls just enough to keep it in view.
pub const List = struct {
    items: []const []const u8,
    style: Style = .default,
    selected: ?usize = null,
    highlight_style: Style = Style.default.reverse(),
    highlight_symbol: []const u8 = "> ",

    pub fn withSelected(self: List, selected: ?usize) List {
        var l = self;
        l.selected = selected;
        return l;
    }

    pub fn withHighlightStyle(self: List, s: Style) List {
        var l = self;
        l.highlight_style = s;
        return l;
    }

    pub fn render(self: List, area: Rect, buf: *Buffer) void {
        if (area.width == 0 or area.height == 0 or self.items.len == 0) return;

        const offset = self.scrollOffset(area.height);
        const visible = @min(self.items.len - offset, area.height);

        var i: usize = 0;
        while (i < visible) : (i += 1) {
            const idx = offset + i;
            const row: u16 = @intCast(i);
            const is_selected = self.selected != null and self.selected.? == idx;
            const row_style = if (is_selected) self.highlight_style else self.style;

            buf.fill(.{ .x = area.x, .y = area.y + row, .width = area.width, .height = 1 }, " ", row_style);

            var x = area.x;
            if (is_selected and self.highlight_symbol.len > 0) {
                x += buf.setString(x, area.y + row, self.highlight_symbol, row_style);
            }
            _ = buf.setString(x, area.y + row, self.items[idx], row_style);
        }
    }

    fn scrollOffset(self: List, height: u16) usize {
        const selected = self.selected orelse return 0;
        if (selected < height) return 0;
        const max_offset = self.items.len -| height;
        return @min(selected - height + 1, max_offset);
    }
};

test "list renders items and highlights the selected row" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 3 });
    defer buf.deinit();

    const l: List = .{ .items = &.{ "one", "two", "three" }, .selected = 1 };
    l.render(buf.area, &buf);

    try std.testing.expectEqualStrings(">", buf.get(0, 1).?.text());
    try std.testing.expect(buf.get(0, 1).?.style.mods.reverse);
    try std.testing.expect(!buf.get(0, 0).?.style.mods.reverse);
}

test "list scrolls so the selected item stays visible" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 2 });
    defer buf.deinit();

    const l: List = .{ .items = &.{ "a", "b", "c", "d" }, .selected = 3 };
    l.render(buf.area, &buf);

    try std.testing.expect(buf.get(2, 1).?.style.mods.reverse);
}
