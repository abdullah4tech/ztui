const std = @import("std");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
const buffer = @import("../buffer.zig");

const Style = style.Style;
const Rect = layout.Rect;
const Buffer = buffer.Buffer;

/// A horizontal progress/usage bar — CPU, memory, disk, download progress,
/// anything expressed as a ratio of a whole. The fraction of the bar under
/// `ratio` is drawn in `gauge_style`; the rest in `style`. A label (default:
/// the percentage) is centered on top of both.
pub const Gauge = struct {
    /// Clamped to [0, 1] at render time.
    ratio: f64,
    label: ?[]const u8 = null,
    style: Style = .default,
    gauge_style: Style = Style.default.reverse(),

    pub fn withRatio(self: Gauge, ratio: f64) Gauge {
        var g = self;
        g.ratio = ratio;
        return g;
    }

    pub fn withLabel(self: Gauge, label: []const u8) Gauge {
        var g = self;
        g.label = label;
        return g;
    }

    pub fn withGaugeStyle(self: Gauge, s: Style) Gauge {
        var g = self;
        g.gauge_style = s;
        return g;
    }

    pub fn render(self: Gauge, area: Rect, buf: *Buffer) void {
        if (area.width == 0 or area.height == 0) return;

        const ratio = std.math.clamp(self.ratio, 0.0, 1.0);
        const filled: u16 = @intFromFloat(@round(@as(f64, @floatFromInt(area.width)) * ratio));

        buf.fill(area, " ", self.style);
        if (filled > 0) {
            buf.fill(.{ .x = area.x, .y = area.y, .width = filled, .height = area.height }, " ", self.gauge_style);
        }

        var label_buf: [16]u8 = undefined;
        const label = self.label orelse blk: {
            const pct: u32 = @intFromFloat(@round(ratio * 100));
            break :blk std.fmt.bufPrint(&label_buf, "{d}%", .{pct}) catch return;
        };

        const width: u16 = @intCast(@min(label.len, area.width));
        const start_x = area.x + (area.width - width) / 2;
        const row = area.y + area.height / 2;

        var i: u16 = 0;
        while (i < width) : (i += 1) {
            const cell_style = if (start_x + i < area.x + filled) self.gauge_style else self.style;
            buf.set(start_x + i, row, label[i .. i + 1], cell_style);
        }
    }
};

test "gauge fills proportionally to ratio" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 1 });
    defer buf.deinit();

    (Gauge{ .ratio = 0.5, .label = "" }).render(buf.area, &buf);

    try std.testing.expect(buf.get(2, 0).?.style.mods.reverse);
    try std.testing.expect(!buf.get(8, 0).?.style.mods.reverse);
}

test "gauge default label shows percentage" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 1 });
    defer buf.deinit();

    (Gauge{ .ratio = 1.0 }).render(buf.area, &buf);

    var found = false;
    for (0..10) |x| {
        if (std.mem.eql(u8, buf.get(@intCast(x), 0).?.text(), "1")) found = true;
    }
    try std.testing.expect(found);
}

test "gauge clamps out-of-range ratios" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 1 });
    defer buf.deinit();

    (Gauge{ .ratio = 5.0, .label = "" }).render(buf.area, &buf);
    try std.testing.expect(buf.get(9, 0).?.style.mods.reverse);
}
