const std = @import("std");

/// An axis-aligned rectangular region of the terminal, in cell coordinates.
pub const Rect = struct {
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,

    pub fn area(self: Rect) u32 {
        return @as(u32, self.width) * @as(u32, self.height);
    }

    /// Shrink the rect by `n` cells on every side. Clamps to zero size
    /// rather than underflowing if the rect is too small.
    pub fn inset(self: Rect, n: u16) Rect {
        const shrink_w = @min(self.width, n * 2);
        const shrink_h = @min(self.height, n * 2);
        return .{
            .x = self.x + @min(n, self.width / 2 + self.width % 2),
            .y = self.y + @min(n, self.height / 2 + self.height % 2),
            .width = self.width - shrink_w,
            .height = self.height - shrink_h,
        };
    }
};

pub const Direction = enum { horizontal, vertical };

/// A sizing rule for one segment of a layout split, evaluated in the order:
/// `length` and `percentage` are satisfied first, then remaining space is
/// divided among `fill` segments proportionally to their factor, `min`/`max`
/// then clamp the result.
pub const Constraint = union(enum) {
    length: u16,
    percentage: u16,
    min: u16,
    max: u16,
    fill: u16,
};

/// Split `area` along `direction` according to `constraints`, mimicking
/// ratatui's `Layout`. Returns one `Rect` per constraint; caller owns the
/// returned slice.
pub fn split(
    allocator: std.mem.Allocator,
    area: Rect,
    direction: Direction,
    constraints: []const Constraint,
) ![]Rect {
    const total: u16 = switch (direction) {
        .horizontal => area.width,
        .vertical => area.height,
    };

    const sizes = try allocator.alloc(u16, constraints.len);
    defer allocator.free(sizes);
    @memset(sizes, 0);

    var used: u32 = 0;
    var fill_total: u32 = 0;

    for (constraints, 0..) |c, i| {
        switch (c) {
            .length => |v| {
                sizes[i] = @min(v, total);
                used += sizes[i];
            },
            .percentage => |p| {
                const v: u16 = @intCast((@as(u32, total) * @min(p, 100)) / 100);
                sizes[i] = v;
                used += v;
            },
            .min => |v| {
                sizes[i] = v;
                used += v;
            },
            .max => {
                // resolved after fill space is known
            },
            .fill => |factor| {
                fill_total += factor;
            },
        }
    }

    const remaining: u32 = if (used > total) 0 else total - used;
    var fill_used: u32 = 0;
    if (fill_total > 0) {
        for (constraints, 0..) |c, i| {
            if (c == .fill) {
                const share: u16 = @intCast((remaining * c.fill) / fill_total);
                sizes[i] = share;
                fill_used += share;
            }
        }
    }

    // Anything left over (rounding, or no fill segments at all) goes to the
    // last non-`max` segment so the layout always covers the full area.
    const leftover_pool = remaining - fill_used;
    if (leftover_pool > 0) {
        var i = constraints.len;
        while (i > 0) {
            i -= 1;
            if (constraints[i] != .max) {
                sizes[i] += @intCast(leftover_pool);
                break;
            }
        }
    }

    for (constraints, 0..) |c, i| {
        if (c == .max) {
            sizes[i] = @min(c.max, total);
        }
    }

    const rects = try allocator.alloc(Rect, constraints.len);
    var offset: u16 = switch (direction) {
        .horizontal => area.x,
        .vertical => area.y,
    };
    for (sizes, 0..) |size, i| {
        rects[i] = switch (direction) {
            .horizontal => .{ .x = offset, .y = area.y, .width = size, .height = area.height },
            .vertical => .{ .x = area.x, .y = offset, .width = area.width, .height = size },
        };
        offset += size;
    }
    return rects;
}

test "split divides fill segments evenly" {
    const area: Rect = .{ .x = 0, .y = 0, .width = 100, .height = 10 };
    const rects = try split(std.testing.allocator, area, .horizontal, &.{
        .{ .fill = 1 },
        .{ .fill = 1 },
    });
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(u16, 50), rects[0].width);
    try std.testing.expectEqual(@as(u16, 50), rects[1].width);
    try std.testing.expectEqual(@as(u16, 50), rects[1].x);
}

test "split honors fixed length then fills remainder" {
    const area: Rect = .{ .x = 0, .y = 0, .width = 100, .height = 10 };
    const rects = try split(std.testing.allocator, area, .vertical, &.{
        .{ .length = 3 },
        .{ .fill = 1 },
    });
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(u16, 3), rects[0].height);
    try std.testing.expectEqual(@as(u16, 7), rects[1].height);
    try std.testing.expectEqual(@as(u16, 3), rects[1].y);
}

test "split honors percentage" {
    const area: Rect = .{ .x = 0, .y = 0, .width = 40, .height = 10 };
    const rects = try split(std.testing.allocator, area, .horizontal, &.{
        .{ .percentage = 25 },
        .{ .fill = 1 },
    });
    defer std.testing.allocator.free(rects);

    try std.testing.expectEqual(@as(u16, 10), rects[0].width);
    try std.testing.expectEqual(@as(u16, 30), rects[1].width);
}

test "rect inset shrinks symmetrically" {
    const r: Rect = .{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const inner = r.inset(1);
    try std.testing.expectEqual(@as(u16, 1), inner.x);
    try std.testing.expectEqual(@as(u16, 1), inner.y);
    try std.testing.expectEqual(@as(u16, 8), inner.width);
    try std.testing.expectEqual(@as(u16, 8), inner.height);
}
