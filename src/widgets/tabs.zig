const std = @import("std");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
const buffer = @import("../buffer.zig");

const Style = style.Style;
const Rect = layout.Rect;
const Buffer = buffer.Buffer;

/// A horizontal tab bar for switching between views — the header row of
/// most multi-panel CLI tools.
pub const Tabs = struct {
    titles: []const []const u8,
    selected: usize = 0,
    style: Style = .default,
    highlight_style: Style = Style.default.reverse(),
    divider: []const u8 = " | ",

    pub fn withSelected(self: Tabs, selected: usize) Tabs {
        var t = self;
        t.selected = selected;
        return t;
    }

    pub fn render(self: Tabs, area: Rect, buf: *Buffer) void {
        if (area.width == 0 or area.height == 0 or self.titles.len == 0) return;

        buf.fill(.{ .x = area.x, .y = area.y, .width = area.width, .height = 1 }, " ", self.style);

        var x = area.x;
        const right = area.x + area.width;
        for (self.titles, 0..) |title, i| {
            if (x >= right) break;
            const tab_style = if (i == self.selected) self.highlight_style else self.style;
            x += buf.setString(x, area.y, title, tab_style);
            if (i != self.titles.len - 1 and x < right) {
                x += buf.setString(x, area.y, self.divider, self.style);
            }
        }
    }
};

test "tabs highlights the selected title" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 30, .height = 1 });
    defer buf.deinit();

    (Tabs{ .titles = &.{ "one", "two", "three" }, .selected = 1 }).render(buf.area, &buf);

    // "one" occupies 0..2, " | " occupies 3..5, "two" (selected) starts at 6.
    try std.testing.expect(!buf.get(0, 0).?.style.mods.reverse);
    try std.testing.expect(!buf.get(4, 0).?.style.mods.reverse);
    try std.testing.expect(buf.get(6, 0).?.style.mods.reverse);
}
