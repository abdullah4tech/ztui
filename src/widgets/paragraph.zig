const std = @import("std");
const style = @import("../style.zig");
const layout = @import("../layout.zig");
const buffer = @import("../buffer.zig");

const Style = style.Style;
const Rect = layout.Rect;
const Buffer = buffer.Buffer;

pub const Alignment = enum { left, center, right };

/// Plain styled text, split on explicit newlines and greedily word-wrapped
/// to the render width. No rich per-span styling — one `Style` for the
/// whole block, which covers the common case without the complexity of a
/// span model.
pub const Paragraph = struct {
    text: []const u8,
    style: Style = .default,
    alignment: Alignment = .left,

    pub fn withStyle(self: Paragraph, s: Style) Paragraph {
        var p = self;
        p.style = s;
        return p;
    }

    pub fn withAlignment(self: Paragraph, a: Alignment) Paragraph {
        var p = self;
        p.alignment = a;
        return p;
    }

    pub fn render(self: Paragraph, area: Rect, buf: *Buffer) void {
        if (area.width == 0 or area.height == 0) return;

        var row: u16 = 0;
        var line_it = std.mem.splitScalar(u8, self.text, '\n');
        while (line_it.next()) |line| {
            if (row >= area.height) break;
            row = self.renderWrapped(line, area, buf, row);
        }
    }

    /// Word-wraps one logical line into `area`, starting at `row`, and
    /// returns the next free row. Tracks byte offsets into `line` directly
    /// (rather than copying words into a scratch buffer) since each word
    /// slice from `tokenizeScalar` shares `line`'s backing memory.
    fn renderWrapped(self: Paragraph, line: []const u8, area: Rect, buf: *Buffer, start_row: u16) u16 {
        var row = start_row;
        if (line.len == 0) {
            if (row < area.height) row += 1;
            return row;
        }

        var word_it = std.mem.tokenizeScalar(u8, line, ' ');
        var row_start: usize = 0;
        var row_end: usize = 0;
        var has_word = false;

        while (word_it.next()) |word| {
            const word_start = @intFromPtr(word.ptr) - @intFromPtr(line.ptr);
            const word_end = word_start + word.len;

            if (has_word and word_end - row_start > area.width) {
                if (row >= area.height) return row;
                self.renderLine(line[row_start..row_end], area, buf, row);
                row += 1;
                has_word = false;
            }
            if (!has_word) {
                row_start = word_start;
                has_word = true;
            }
            row_end = word_end;
        }
        if (has_word and row < area.height) {
            self.renderLine(line[row_start..row_end], area, buf, row);
            row += 1;
        }
        return row;
    }

    fn renderLine(self: Paragraph, text: []const u8, area: Rect, buf: *Buffer, row: u16) void {
        const width: u16 = @intCast(@min(text.len, area.width));
        const x_offset: u16 = switch (self.alignment) {
            .left => 0,
            .center => (area.width - width) / 2,
            .right => area.width - width,
        };
        _ = buf.setString(area.x + x_offset, area.y + row, text, self.style);
    }
};

test "paragraph wraps long lines to width" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 5, .height = 3 });
    defer buf.deinit();

    const p: Paragraph = .{ .text = "one two three" };
    p.render(buf.area, &buf);

    try std.testing.expectEqualStrings("o", buf.get(0, 0).?.text());
    try std.testing.expectEqualStrings("t", buf.get(0, 1).?.text());
}

test "paragraph respects explicit newlines" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 3 });
    defer buf.deinit();

    const p: Paragraph = .{ .text = "first\nsecond" };
    p.render(buf.area, &buf);

    try std.testing.expectEqualStrings("f", buf.get(0, 0).?.text());
    try std.testing.expectEqualStrings("s", buf.get(0, 1).?.text());
}

test "paragraph center alignment" {
    var buf = try Buffer.init(std.testing.allocator, .{ .x = 0, .y = 0, .width = 10, .height = 1 });
    defer buf.deinit();

    const p: Paragraph = .{ .text = "hi", .alignment = .center };
    p.render(buf.area, &buf);

    try std.testing.expectEqualStrings("h", buf.get(4, 0).?.text());
}
