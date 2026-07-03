const std = @import("std");
const posix = std.posix;
const Io = std.Io;
const layout = @import("layout.zig");
const buf_mod = @import("buffer.zig");

const Rect = layout.Rect;
const Buffer = buf_mod.Buffer;

/// Raw terminal size, in character cells.
pub const Size = struct { cols: u16, rows: u16 };

pub fn windowSize() !Size {
    var ws: posix.winsize = undefined;
    const rc = posix.system.ioctl(posix.STDOUT_FILENO, posix.T.IOCGWINSZ, @intFromPtr(&ws));
    if (posix.errno(rc) != .SUCCESS) return error.IoctlFailed;
    return .{ .cols = ws.col, .rows = ws.row };
}

/// Owns the terminal session: raw mode, alternate screen, cursor visibility,
/// and double-buffered rendering. Create one, draw into `buffer()` each
/// frame, then call `flush()` to write only what changed to the screen.
pub const Terminal = struct {
    allocator: std.mem.Allocator,
    out: Io.File,
    writer: Io.File.Writer,
    buffers: [2]Buffer,
    current: u1,
    original_termios: ?posix.termios,
    cursor_hidden: bool,

    pub fn init(allocator: std.mem.Allocator, io: Io, out_buffer: []u8) !Terminal {
        const win = try windowSize();
        const area: Rect = .{ .x = 0, .y = 0, .width = win.cols, .height = win.rows };
        var buffers: [2]Buffer = undefined;
        buffers[0] = try Buffer.init(allocator, area);
        errdefer buffers[0].deinit();
        buffers[1] = try Buffer.init(allocator, area);
        errdefer buffers[1].deinit();

        return .{
            .allocator = allocator,
            .out = .stdout(),
            .writer = .init(.stdout(), io, out_buffer),
            .buffers = buffers,
            .current = 0,
            .original_termios = null,
            .cursor_hidden = false,
        };
    }

    /// Restores the terminal to its original state (raw mode, alt screen,
    /// cursor) and frees internal buffers. Safe to call even if setup was
    /// only partially completed.
    pub fn deinit(self: *Terminal) void {
        self.showCursor() catch {};
        self.leaveAltScreen() catch {};
        self.exitRawMode() catch {};
        self.writer.interface.flush() catch {};
        self.buffers[0].deinit();
        self.buffers[1].deinit();
        self.* = undefined;
    }

    pub fn enterRawMode(self: *Terminal) !void {
        if (self.original_termios != null) return;
        const fd = posix.STDIN_FILENO;
        const orig = try posix.tcgetattr(fd);
        var raw = orig;

        raw.iflag.BRKINT = false;
        raw.iflag.ICRNL = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        raw.iflag.IXON = false;

        raw.oflag.OPOST = false;

        raw.cflag.CSIZE = .CS8;

        raw.lflag.ECHO = false;
        raw.lflag.ICANON = false;
        raw.lflag.IEXTEN = false;
        raw.lflag.ISIG = false;

        raw.cc[@intFromEnum(posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(posix.V.TIME)] = 1;

        try posix.tcsetattr(fd, .FLUSH, raw);
        self.original_termios = orig;
    }

    pub fn exitRawMode(self: *Terminal) !void {
        if (self.original_termios) |orig| {
            try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, orig);
            self.original_termios = null;
        }
    }

    pub fn enterAltScreen(self: *Terminal) !void {
        try self.writer.interface.writeAll("\x1b[?1049h");
        try self.writer.interface.flush();
    }

    pub fn leaveAltScreen(self: *Terminal) !void {
        try self.writer.interface.writeAll("\x1b[?1049l");
        try self.writer.interface.flush();
    }

    pub fn hideCursor(self: *Terminal) !void {
        try self.writer.interface.writeAll("\x1b[?25l");
        try self.writer.interface.flush();
        self.cursor_hidden = true;
    }

    pub fn showCursor(self: *Terminal) !void {
        if (!self.cursor_hidden) return;
        try self.writer.interface.writeAll("\x1b[?25h");
        try self.writer.interface.flush();
        self.cursor_hidden = false;
    }

    /// The buffer to draw the current frame into. Its content persists
    /// across frames only via what you draw — it starts cleared each time
    /// after `flush()`.
    pub fn buffer(self: *Terminal) *Buffer {
        return &self.buffers[self.current];
    }

    pub fn size(self: *const Terminal) Rect {
        return self.buffers[self.current].area;
    }

    /// Re-query the terminal size and resize both internal buffers,
    /// discarding their contents. Call this after receiving SIGWINCH.
    pub fn resize(self: *Terminal) !void {
        const s = try windowSize();
        const area: Rect = .{ .x = 0, .y = 0, .width = s.cols, .height = s.rows };
        try self.buffers[0].resize(area);
        try self.buffers[1].resize(area);
    }

    /// Diff the current frame against the previous one, write only the
    /// changed cells to the terminal, and rotate buffers for the next frame.
    pub fn flush(self: *Terminal) !void {
        const drawn = self.current;
        const prev = drawn ^ 1;

        const patches = try self.buffers[drawn].diff(&self.buffers[prev], self.allocator);
        defer self.allocator.free(patches);

        try self.writePatches(patches);
        try self.writer.interface.flush();

        self.current = prev;
        self.buffers[self.current].reset();
    }

    fn writePatches(self: *Terminal, patches: []const buf_mod.Patch) !void {
        const w = &self.writer.interface;
        var last_style: ?@import("style.zig").Style = null;
        var last_pos: ?struct { x: u16, y: u16 } = null;

        for (patches) |p| {
            const contiguous = if (last_pos) |lp| lp.y == p.y and lp.x + 1 == p.x else false;
            if (!contiguous) {
                try w.print("\x1b[{d};{d}H", .{ p.y + 1, p.x + 1 });
            }
            if (last_style == null or !last_style.?.eql(p.cell.style)) {
                try p.cell.style.writeAnsi(w);
                last_style = p.cell.style;
            }
            try w.writeAll(p.cell.text());
            last_pos = .{ .x = p.x, .y = p.y };
        }
    }
};
