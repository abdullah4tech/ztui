const std = @import("std");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
const buffer = @import("../buffer.zig");

const Style = style.Style;
const Rect = layout.Rect;
const Buffer = buffer.Buffer;

/// A vertical scroll position indicator — draw it in a 1-column strip
/// beside a `List`, `Table`, or `Paragraph` to show there's more content
/// than fits. Renders nothing if everything already fits (`content_length
/// <= viewport_length`).
pub const Scrollbar = struct {
    content_length: usize,
    position: usize,
    viewport_length: usize,
    track_style: Style = Style.default.dim(),
    thumb_style: Style = .default,
    track_symbol: []const u8 = "\u{2502}",
    thumb_symbol: []const u8 = "\u{2588}",

    pub fn render(self: Scrollbar, area: Rect, buf: *Buffer) void {
        if (area.width == 0 or area.height == 0) return;
        if (self.content_length <= self.viewport_length) return;

        var y = area.y;
        while (y < area.y + area.height) : (y += 1) {
            buf.set(area.x, y, self.track_symbol, self.track_style);
        }

        const track_len = area.height;
        const thumb_len: u16 = @max(1, @as(u16, @intCast((self.viewport_length * track_len) / self.content_length)));
        const max_scroll = self.content_length - self.viewport_length;
        const track_room = track_len - thumb_len;
        const thumb_start: u16 = if (max_scroll == 0 or track_room == 0)
            0
        else
            @intCast((self.position * track_room) / max_scroll);

        var i: u16 = 0;
        while (i < thumb_len) : (i += 1) {
            buf.set(area.x, area.y + thumb_start + i, self.thumb_symbol, self.thumb_style);
        }
    }
};

test "scrollbar renders nothing when content fits" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 1, .height = 5 });
    defer buf.deinit();

    (Scrollbar{ .content_length = 5, .position = 0, .viewport_length = 5 }).render(buf.area, &buf);
    try std.testing.expectEqualStrings(" ", buf.get(0, 0).?.text());
}

test "scrollbar thumb moves toward the bottom as position increases" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 1, .height = 10 });
    defer buf.deinit();

    (Scrollbar{ .content_length = 100, .position = 90, .viewport_length = 10 }).render(buf.area, &buf);
    try std.testing.expectEqualStrings("\u{2588}", buf.get(0, 9).?.text());
}

test "scrollbar thumb starts at the top when position is zero" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 1, .height = 10 });
    defer buf.deinit();

    (Scrollbar{ .content_length = 100, .position = 0, .viewport_length = 10 }).render(buf.area, &buf);
    try std.testing.expectEqualStrings("\u{2588}", buf.get(0, 0).?.text());
}
