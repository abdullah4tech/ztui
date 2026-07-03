//! ztui — a small, dependency-free terminal UI toolkit for Zig.
const std = @import("std");

pub const style = @import("style.zig");
pub const layout = @import("layout.zig");
pub const buffer = @import("buffer.zig");
pub const terminal = @import("terminal.zig");

pub const block = @import("widgets/block.zig");
pub const paragraph = @import("widgets/paragraph.zig");
pub const list = @import("widgets/list.zig");
pub const gauge = @import("widgets/gauge.zig");
pub const sparkline = @import("widgets/sparkline.zig");
pub const table = @import("widgets/table.zig");
pub const tabs = @import("widgets/tabs.zig");
pub const scrollbar = @import("widgets/scrollbar.zig");

pub const Color = style.Color;
pub const Style = style.Style;
pub const Modifiers = style.Modifiers;

pub const Rect = layout.Rect;
pub const Direction = layout.Direction;
pub const Constraint = layout.Constraint;
pub const split = layout.split;

pub const Cell = buffer.Cell;
pub const Buffer = buffer.Buffer;
pub const Patch = buffer.Patch;

pub const Terminal = terminal.Terminal;
pub const windowSize = terminal.windowSize;

pub const Block = block.Block;
pub const Borders = block.Borders;
pub const Paragraph = paragraph.Paragraph;
pub const Alignment = paragraph.Alignment;
pub const List = list.List;
pub const Gauge = gauge.Gauge;
pub const Sparkline = sparkline.Sparkline;
pub const Table = table.Table;
pub const Tabs = tabs.Tabs;
pub const Scrollbar = scrollbar.Scrollbar;

test {
    std.testing.refAllDecls(@This());
}
