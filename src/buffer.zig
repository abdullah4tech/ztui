const std = @import("std");
const style = @import("style.zig");
const layout = @import("layout.zig");

const Style = style.Style;
const Rect = layout.Rect;

/// A single character cell: the grapheme drawn in it plus its style.
pub const Cell = struct {
    /// UTF-8 bytes for the symbol occupying this cell. Almost always one
    /// codepoint; stored inline to avoid allocating per cell.
    symbol: [4]u8 = .{ ' ', 0, 0, 0 },
    symbol_len: u3 = 1,
    style: Style = .default,

    pub const empty: Cell = .{};

    pub fn set(self: *Cell, bytes: []const u8, cell_style: Style) void {
        const len = @min(bytes.len, self.symbol.len);
        @memcpy(self.symbol[0..len], bytes[0..len]);
        self.symbol_len = @intCast(len);
        self.style = cell_style;
    }

    pub fn text(self: *const Cell) []const u8 {
        return self.symbol[0..self.symbol_len];
    }

    pub fn eql(a: Cell, b: Cell) bool {
        return a.symbol_len == b.symbol_len and
            std.mem.eql(u8, a.symbol[0..a.symbol_len], b.symbol[0..b.symbol_len]) and
            a.style.eql(b.style);
    }
};

/// A single position + cell, used when reporting the diff between two buffers.
pub const Patch = struct {
    x: u16,
    y: u16,
    cell: Cell,
};

/// A 2D grid of `Cell`s representing everything drawn in one frame.
/// Widgets render into a `Buffer`; the `Terminal` diffs it against the
/// previous frame and only writes the cells that actually changed.
pub const Buffer = struct {
    area: Rect,
    cells: []Cell,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, area: Rect) !Buffer {
        const cells = try allocator.alloc(Cell, @as(usize, area.width) * @as(usize, area.height));
        @memset(cells, Cell.empty);
        return .{ .area = area, .cells = cells, .allocator = allocator };
    }

    pub fn deinit(self: *Buffer) void {
        self.allocator.free(self.cells);
        self.* = undefined;
    }

    /// Resize in place, discarding contents (used when the terminal is resized).
    pub fn resize(self: *Buffer, area: Rect) !void {
        const new_cells = try self.allocator.alloc(Cell, @as(usize, area.width) * @as(usize, area.height));
        @memset(new_cells, Cell.empty);
        self.allocator.free(self.cells);
        self.cells = new_cells;
        self.area = area;
    }

    pub fn reset(self: *Buffer) void {
        @memset(self.cells, Cell.empty);
    }

    fn index(self: *const Buffer, x: u16, y: u16) ?usize {
        if (x < self.area.x or y < self.area.y) return null;
        const local_x = x - self.area.x;
        const local_y = y - self.area.y;
        if (local_x >= self.area.width or local_y >= self.area.height) return null;
        return @as(usize, local_y) * @as(usize, self.area.width) + @as(usize, local_x);
    }

    pub fn get(self: *const Buffer, x: u16, y: u16) ?Cell {
        const i = self.index(x, y) orelse return null;
        return self.cells[i];
    }

    pub fn set(self: *Buffer, x: u16, y: u16, bytes: []const u8, cell_style: Style) void {
        const i = self.index(x, y) orelse return;
        self.cells[i].set(bytes, cell_style);
    }

    /// Write `text` starting at (x, y), stopping at the buffer's right edge.
    /// Returns the number of columns actually written.
    pub fn setString(self: *Buffer, x: u16, y: u16, text: []const u8, cell_style: Style) u16 {
        var col = x;
        var it = (std.unicode.Utf8View.init(text) catch return 0).iterator();
        while (it.nextCodepointSlice()) |grapheme| {
            if (col >= self.area.x + self.area.width) break;
            self.set(col, y, grapheme, cell_style);
            col += 1;
        }
        return col - x;
    }

    /// Fill a rectangular region with a single styled symbol (e.g. a background fill).
    pub fn fill(self: *Buffer, area: Rect, symbol: []const u8, cell_style: Style) void {
        var y = area.y;
        while (y < area.y + area.height) : (y += 1) {
            var x = area.x;
            while (x < area.x + area.width) : (x += 1) {
                self.set(x, y, symbol, cell_style);
            }
        }
    }

    /// Compute the list of cells that differ between `self` (new) and `prev` (old).
    /// Both buffers must share the same area. Caller owns the returned slice.
    pub fn diff(self: *const Buffer, prev: *const Buffer, allocator: std.mem.Allocator) ![]Patch {
        var patches: std.ArrayList(Patch) = .empty;
        errdefer patches.deinit(allocator);

        std.debug.assert(self.cells.len == prev.cells.len);
        for (self.cells, prev.cells, 0..) |new_cell, old_cell, i| {
            if (!new_cell.eql(old_cell)) {
                const local_x: u16 = @intCast(i % self.area.width);
                const local_y: u16 = @intCast(i / self.area.width);
                try patches.append(allocator, .{
                    .x = self.area.x + local_x,
                    .y = self.area.y + local_y,
                    .cell = new_cell,
                });
            }
        }
        return patches.toOwnedSlice(allocator);
    }
};

test "buffer set and get roundtrip" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 3 });
    defer buf.deinit();

    buf.set(2, 1, "x", Style.default.bold());
    const cell = buf.get(2, 1).?;
    try std.testing.expectEqualStrings("x", cell.text());
    try std.testing.expect(cell.style.mods.bold);
}

test "buffer setString writes across columns and clips" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 5, .height = 1 });
    defer buf.deinit();

    const written = buf.setString(0, 0, "hello world", .default);
    try std.testing.expectEqual(@as(u16, 5), written);
    try std.testing.expectEqualStrings("o", buf.get(4, 0).?.text());
}

test "buffer diff reports only changed cells" {
    var a = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 3, .height = 1 });
    defer a.deinit();
    var b = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 3, .height = 1 });
    defer b.deinit();

    b.set(1, 0, "z", .default);

    const patches = try b.diff(&a, std.testing.allocator);
    defer std.testing.allocator.free(patches);

    try std.testing.expectEqual(@as(usize, 1), patches.len);
    try std.testing.expectEqual(@as(u16, 1), patches[0].x);
    try std.testing.expectEqualStrings("z", patches[0].cell.text());
}
