const std = @import("std");
const posix = std.posix;
const ztui = @import("ztui");

const menu_items = [_][]const u8{
    "Overview",
    "Buffers",
    "Widgets",
    "Layout engine",
    "Terminal backend",
    "Examples",
};

const descriptions = [_][]const u8{
    "ztui renders into an in-memory cell buffer, diffs it against the previous frame, and writes only what changed to the terminal.",
    "A Buffer is a flat grid of Cells. Widgets never touch the terminal directly — they only ever write into a Buffer.",
    "Block, Paragraph, List, Gauge, Sparkline, Table, Tabs, and Scrollbar ship in the core. Each widget just exposes render(area, buffer) — no inheritance, no vtables.",
    "split() divides a Rect along an axis using Length, Percentage, Min, Max, and Fill constraints, the same model as ratatui.",
    "Raw mode, the alternate screen, and cursor visibility are handled directly through termios and ANSI escapes — no dependencies.",
    "Run `zig build run-hello` for the minimal example, or `zig build create -- myapp` to scaffold your own project.",
};

/// Live system stats, sampled once per frame from /proc — this panel is
/// real data, not a mockup, to show what a genuine system-monitor-style
/// tool looks like built on ztui.
const Stats = struct {
    load_history: [60]u64 = [_]u64{0} ** 60,
    load_len: usize = 0,
    mem_ratio: f64 = 0,

    fn sample(self: *Stats, io: std.Io) void {
        self.mem_ratio = readMemRatio(io);
        self.pushLoad(readLoadSample(io));
    }

    fn pushLoad(self: *Stats, value: u64) void {
        if (self.load_len < self.load_history.len) {
            self.load_history[self.load_len] = value;
            self.load_len += 1;
        } else {
            std.mem.copyForwards(u64, self.load_history[0 .. self.load_history.len - 1], self.load_history[1..]);
            self.load_history[self.load_history.len - 1] = value;
        }
    }

    fn loadSlice(self: *const Stats) []const u64 {
        return self.load_history[0..self.load_len];
    }
};

fn readMemRatio(io: std.Io) f64 {
    var buf: [4096]u8 = undefined;
    const text = std.Io.Dir.cwd().readFile(io, "/proc/meminfo", &buf) catch return 0;

    var total: u64 = 0;
    var avail: u64 = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            total = parseKb(line) orelse 0;
        } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            avail = parseKb(line) orelse 0;
        }
    }
    if (total == 0) return 0;
    return 1.0 - @as(f64, @floatFromInt(avail)) / @as(f64, @floatFromInt(total));
}

fn parseKb(line: []const u8) ?u64 {
    var it = std.mem.tokenizeScalar(u8, line, ' ');
    _ = it.next() orelse return null; // label, e.g. "MemTotal:"
    const num = it.next() orelse return null;
    return std.fmt.parseInt(u64, num, 10) catch null;
}

/// Reads the 1-minute load average and scales it to an integer so it can
/// feed the (integer-valued) Sparkline; two decimal places of precision.
fn readLoadSample(io: std.Io) u64 {
    var buf: [256]u8 = undefined;
    const text = std.Io.Dir.cwd().readFile(io, "/proc/loadavg", &buf) catch return 0;
    var it = std.mem.tokenizeScalar(u8, text, ' ');
    const first = it.next() orelse return 0;
    const value = std.fmt.parseFloat(f64, first) catch return 0;
    return @intFromFloat(@round(value * 100));
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var out_buffer: [8192]u8 = undefined;
    var term = try ztui.Terminal.init(allocator, io, &out_buffer);
    defer term.deinit();

    try term.enterRawMode();
    try term.enterAltScreen();
    try term.hideCursor();

    var selected: usize = 0;
    var stats: Stats = .{};
    var stdin_buf: [16]u8 = undefined;

    while (true) {
        stats.sample(io);
        try render(&term, allocator, selected, &stats);
        try term.flush();

        const n = try posix.read(posix.STDIN_FILENO, &stdin_buf);
        if (n == 0) continue;

        if (stdin_buf[0] == 'q') break;
        if (stdin_buf[0] == 'j' or (n >= 3 and stdin_buf[0] == 0x1b and stdin_buf[2] == 'B')) {
            selected = @min(selected + 1, menu_items.len - 1);
        }
        if (stdin_buf[0] == 'k' or (n >= 3 and stdin_buf[0] == 0x1b and stdin_buf[2] == 'A')) {
            selected -|= 1;
        }
    }
}

fn render(term: *ztui.Terminal, allocator: std.mem.Allocator, selected: usize, stats: *const Stats) !void {
    const area = term.size();
    const buf = term.buffer();

    const rows = try ztui.split(allocator, area, .vertical, &.{
        .{ .length = 3 },
        .{ .fill = 1 },
        .{ .length = 1 },
    });
    defer allocator.free(rows);

    const header_style = ztui.Style.default.withFg(.bright_white).withBg(.blue).bold();
    (ztui.Block{ .style = header_style, .borders = .none }).render(rows[0], buf);
    (ztui.Paragraph{
        .text = "ztui — a small terminal UI toolkit for Zig",
        .style = header_style,
        .alignment = .center,
    }).render(.{ .x = rows[0].x, .y = rows[0].y + 1, .width = rows[0].width, .height = 1 }, buf);

    const cols = try ztui.split(allocator, rows[1], .horizontal, &.{
        .{ .percentage = 22 },
        .{ .fill = 1 },
        .{ .length = 28 },
    });
    defer allocator.free(cols);

    const menu_block: ztui.Block = (ztui.Block{})
        .withTitle("menu")
        .withBorderStyle(ztui.Style.default.withFg(.cyan));
    menu_block.render(cols[0], buf);

    (ztui.List{
        .items = &menu_items,
        .selected = selected,
        .highlight_style = ztui.Style.default.withFg(.black).withBg(.cyan).bold(),
        .highlight_symbol = "❯ ",
    }).render(menu_block.inner(cols[0]), buf);

    const detail_block: ztui.Block = (ztui.Block{})
        .withTitle("details")
        .withBorderStyle(ztui.Style.default.withFg(.magenta));
    detail_block.render(cols[1], buf);

    (ztui.Paragraph{
        .text = descriptions[selected],
    }).render(detail_block.inner(cols[1]), buf);

    renderStats(cols[2], buf, allocator, stats);

    (ztui.Paragraph{
        .text = "↑/↓ or j/k to move   q to quit",
        .style = ztui.Style.default.dim(),
        .alignment = .center,
    }).render(rows[2], buf);
}

fn renderStats(area: ztui.Rect, buf: *ztui.Buffer, allocator: std.mem.Allocator, stats: *const Stats) void {
    const stats_block: ztui.Block = (ztui.Block{})
        .withTitle("system")
        .withBorderStyle(ztui.Style.default.withFg(.green));
    stats_block.render(area, buf);
    const inner = stats_block.inner(area);

    const parts = ztui.split(allocator, inner, .vertical, &.{
        .{ .length = 1 },
        .{ .length = 1 },
        .{ .length = 1 },
        .{ .length = 1 },
        .{ .length = 1 },
        .{ .fill = 1 },
    }) catch return;
    defer allocator.free(parts);

    (ztui.Paragraph{ .text = "memory", .style = ztui.Style.default.dim() }).render(parts[0], buf);
    (ztui.Gauge{
        .ratio = stats.mem_ratio,
        .gauge_style = ztui.Style.default.withFg(.black).withBg(.green),
    }).render(parts[1], buf);

    (ztui.Paragraph{ .text = "load avg (1m)", .style = ztui.Style.default.dim() }).render(parts[3], buf);
    (ztui.Sparkline{
        .data = stats.loadSlice(),
        .style = ztui.Style.default.withFg(.yellow),
    }).render(parts[4], buf);
}
