const std = @import("std");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
const buffer = @import("../buffer.zig");

const Style = style.Style;
const Rect = layout.Rect;
const Buffer = buffer.Buffer;

const bars = [_][]const u8{ "\u{2581}", "\u{2582}", "\u{2583}", "\u{2584}", "\u{2585}", "\u{2586}", "\u{2587}", "\u{2588}" };

/// A single-row trend line rendered with Unicode block characters —
/// CPU/network/latency history, anything you'd otherwise need a real chart
/// library for. Right-aligned: the most recent sample is always the
/// rightmost column. Anchors to the bottom row of `area`, so it composes
/// with a label placed above it in a taller area.
pub const Sparkline = struct {
    data: []const u64,
    style: Style = .default,
    /// Scale ceiling; auto-computed from `data`'s max when null.
    max: ?u64 = null,

    pub fn render(self: Sparkline, area: Rect, buf: *Buffer) void {
        if (area.width == 0 or area.height == 0 or self.data.len == 0) return;

        const max_val = self.max orelse blk: {
            var m: u64 = 0;
            for (self.data) |v| m = @max(m, v);
            break :blk m;
        };

        const visible = @min(self.data.len, area.width);
        const start = self.data.len - visible;
        const x_offset = area.width - visible;
        const row = area.y + area.height - 1;

        var i: u16 = 0;
        while (i < visible) : (i += 1) {
            const v = self.data[start + i];
            const level: usize = if (max_val == 0)
                0
            else
                @min(bars.len - 1, (v * (bars.len - 1)) / max_val);
            buf.set(area.x + x_offset + i, row, bars[level], self.style);
        }
    }
};

test "sparkline shows the most recent samples right-aligned" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 3, .height = 1 });
    defer buf.deinit();

    (Sparkline{ .data = &.{ 1, 2, 3, 4, 5 } }).render(buf.area, &buf);

    // last 3 samples (3, 4, 5) should be visible, oldest two dropped.
    // max is 5 (from the full dataset), so 3/5 and 5/5 map to bars[4] and bars[7].
    try std.testing.expectEqualStrings(bars[4], buf.get(0, 0).?.text());
    try std.testing.expectEqualStrings(bars[7], buf.get(2, 0).?.text());
}

test "sparkline handles all-zero data without dividing by zero" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 3, .height = 1 });
    defer buf.deinit();

    (Sparkline{ .data = &.{ 0, 0, 0 } }).render(buf.area, &buf);
    try std.testing.expectEqualStrings(bars[0], buf.get(0, 0).?.text());
}
