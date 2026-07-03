const std = @import("std");
const posix = std.posix;
const ztui = @import("ztui");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var out_buffer: [4096]u8 = undefined;
    var term = try ztui.Terminal.init(allocator, io, &out_buffer);
    defer term.deinit();

    try term.enterRawMode();
    try term.enterAltScreen();
    try term.hideCursor();

    var stdin_buf: [16]u8 = undefined;

    while (true) {
        const area = term.size();
        const buf = term.buffer();

        const frame: ztui.Block = (ztui.Block{})
            .withTitle("ztui \u{2014} hello")
            .withBorderStyle(ztui.Style.default.withFg(.cyan).bold());
        frame.render(area, buf);

        const p: ztui.Paragraph = .{
            .text = "Hello from ztui!\n\nPress q to quit.",
            .alignment = .center,
        };
        p.render(frame.inner(area), buf);

        try term.flush();

        const n = try posix.read(posix.STDIN_FILENO, &stdin_buf);
        if (n > 0 and stdin_buf[0] == 'q') break;
    }
}
