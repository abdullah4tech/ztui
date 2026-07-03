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
    "Block, Paragraph, and List ship in the core. Each widget just exposes render(area, buffer) — no inheritance, no vtables.",
    "split() divides a Rect along an axis using Length, Percentage, Min, Max, and Fill constraints, the same model as ratatui.",
    "Raw mode, the alternate screen, and cursor visibility are handled directly through termios and ANSI escapes — no dependencies.",
    "Run `zig build run-hello` for the minimal example, or `zig build create -- myapp` to scaffold your own project.",
};

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
    var stdin_buf: [16]u8 = undefined;

    while (true) {
        try render(&term, allocator, selected);
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

fn render(term: *ztui.Terminal, allocator: std.mem.Allocator, selected: usize) !void {
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
        .{ .percentage = 30 },
        .{ .fill = 1 },
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

    (ztui.Paragraph{
        .text = "↑/↓ or j/k to move   q to quit",
        .style = ztui.Style.default.dim(),
        .alignment = .center,
    }).render(rows[2], buf);
}
