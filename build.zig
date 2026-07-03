const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ztui = b.addModule("ztui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{ .root_module = ztui });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_lib_tests.step);

    const example_names = [_][]const u8{ "hello", "dashboard" };
    const examples_step = b.step("examples", "Build all examples");
    for (example_names) |name| {
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "ztui", .module = ztui },
                },
            }),
        });
        const install_exe = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install_exe.step);
        examples_step.dependOn(&install_exe.step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| run_cmd.addArgs(args);

        const run_step = b.step(b.fmt("run-{s}", .{name}), b.fmt("Run the {s} example", .{name}));
        run_step.dependOn(&run_cmd.step);
    }

    const create_exe = b.addExecutable(.{
        .name = "create-ztui",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/create-ztui/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(create_exe);

    const create_run = b.addRunArtifact(create_exe);
    create_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| create_run.addArgs(args);
    const create_step = b.step("create", "Scaffold a new ztui project: zig build create -- <name>");
    create_step.dependOn(&create_run.step);
}
