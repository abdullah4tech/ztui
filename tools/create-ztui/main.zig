const std = @import("std");
const Io = std.Io;
const Dir = Io.Dir;

const usage =
    \\create-ztui — scaffold a new Zig project that uses the ztui library
    \\
    \\Usage:
    \\  create-ztui <project-name> [path-to-ztui]
    \\  create-ztui -h | --help
    \\
    \\Arguments:
    \\  project-name   Name of the directory to create for the new project
    \\  path-to-ztui   Path to a ztui checkout to depend on
    \\                 (default: the current directory)
    \\
    \\Options:
    \\  -h, --help     Show this help message
    \\
;

pub fn main(init: std.process.Init) !void {
    run(init) catch |err| switch (err) {
        error.HelpRequested => std.process.exit(0),
        error.NoProjectName, error.ProjectAlreadyExists, error.ZigInitFailed => std.process.exit(1),
        else => {
            std.debug.print("create-ztui: unexpected error: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        },
    };
}

fn run(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    if (args.len < 2) {
        std.debug.print("create-ztui: no project name supplied\n\n{s}", .{usage});
        return error.NoProjectName;
    }
    if (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "--help")) {
        std.debug.print("{s}", .{usage});
        return error.HelpRequested;
    }
    const name = args[1];

    var path_buf: [Dir.max_path_bytes]u8 = undefined;
    const ztui_path = if (args.len >= 3)
        args[2]
    else blk: {
        const len = try Dir.cwd().realPath(io, &path_buf);
        break :blk path_buf[0..len];
    };

    const cwd = Dir.cwd();
    cwd.createDir(io, name, .default_dir) catch |err| {
        switch (err) {
            error.PathAlreadyExists => std.debug.print("create-ztui: '{s}' already exists\n", .{name}),
            else => std.debug.print("create-ztui: could not create '{s}': {s}\n", .{ name, @errorName(err) }),
        }
        return error.ProjectAlreadyExists;
    };

    std.debug.print("Scaffolding {s}...\n", .{name});

    const result = try std.process.run(gpa, io, .{
        .argv = &.{ "zig", "init" },
        .cwd = .{ .path = name },
    });
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) {
            std.debug.print("create-ztui: `zig init` failed ({d}):\n{s}\n", .{ code, result.stderr });
            return error.ZigInitFailed;
        },
        else => {
            std.debug.print("create-ztui: `zig init` did not exit cleanly:\n{s}\n", .{result.stderr});
            return error.ZigInitFailed;
        },
    }

    var project_dir = try cwd.openDir(io, name, .{});
    defer project_dir.close(io);

    var proj_path_buf: [Dir.max_path_bytes]u8 = undefined;
    const proj_len = try project_dir.realPath(io, &proj_path_buf);
    const rel_ztui_path = try Dir.path.relative(arena, "/", null, proj_path_buf[0..proj_len], ztui_path);

    const zon_buf = try arena.alloc(u8, 64 * 1024);
    const zon_text = try project_dir.readFile(io, "build.zig.zon", zon_buf);
    const dep_marker = ".dependencies = .{";
    const dep_replacement = try std.fmt.allocPrint(arena,
        \\.dependencies = .{{
        \\        .ztui = .{{ .path = "{s}" }},
    , .{rel_ztui_path});
    const patched_zon = try std.mem.replaceOwned(u8, arena, zon_text, dep_marker, dep_replacement);
    try project_dir.writeFile(io, .{ .sub_path = "build.zig.zon", .data = patched_zon });

    try project_dir.writeFile(io, .{ .sub_path = "build.zig", .data = build_zig_template });
    try project_dir.writeFile(io, .{ .sub_path = "src/main.zig", .data = main_zig_template });
    project_dir.deleteFile(io, "src/root.zig") catch {};

    std.debug.print(
        \\
        \\Done! Your project is ready:
        \\
        \\  cd {s}
        \\  zig build run
        \\
        \\
    , .{name});
}

const build_zig_template =
    \\const std = @import("std");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    const target = b.standardTargetOptions(.{});
    \\    const optimize = b.standardOptimizeOption(.{});
    \\
    \\    const ztui = b.dependency("ztui", .{ .target = target, .optimize = optimize });
    \\
    \\    const exe = b.addExecutable(.{
    \\        .name = "app",
    \\        .root_module = b.createModule(.{
    \\            .root_source_file = b.path("src/main.zig"),
    \\            .target = target,
    \\            .optimize = optimize,
    \\            .imports = &.{
    \\                .{ .name = "ztui", .module = ztui.module("ztui") },
    \\            },
    \\        }),
    \\    });
    \\    b.installArtifact(exe);
    \\
    \\    const run_cmd = b.addRunArtifact(exe);
    \\    run_cmd.step.dependOn(b.getInstallStep());
    \\    if (b.args) |args| run_cmd.addArgs(args);
    \\
    \\    const run_step = b.step("run", "Run the app");
    \\    run_step.dependOn(&run_cmd.step);
    \\}
    \\
;

const main_zig_template =
    \\const std = @import("std");
    \\const posix = std.posix;
    \\const ztui = @import("ztui");
    \\
    \\pub fn main(init: std.process.Init) !void {
    \\    const allocator = init.gpa;
    \\    const io = init.io;
    \\
    \\    var out_buffer: [4096]u8 = undefined;
    \\    var term = try ztui.Terminal.init(allocator, io, &out_buffer);
    \\    defer term.deinit();
    \\
    \\    try term.enterRawMode();
    \\    try term.enterAltScreen();
    \\    try term.hideCursor();
    \\
    \\    var stdin_buf: [16]u8 = undefined;
    \\
    \\    while (true) {
    \\        const area = term.size();
    \\        const buf = term.buffer();
    \\
    \\        const frame: ztui.Block = (ztui.Block{})
    \\            .withTitle("welcome to ztui")
    \\            .withBorderStyle(ztui.Style.default.withFg(.cyan).bold());
    \\        frame.render(area, buf);
    \\
    \\        const p: ztui.Paragraph = .{
    \\            .text = "Your terminal UI starts here.\n\nPress q to quit.",
    \\            .alignment = .center,
    \\        };
    \\        p.render(frame.inner(area), buf);
    \\
    \\        try term.flush();
    \\
    \\        const n = try posix.read(posix.STDIN_FILENO, &stdin_buf);
    \\        if (n > 0 and stdin_buf[0] == 'q') break;
    \\    }
    \\}
    \\
;
