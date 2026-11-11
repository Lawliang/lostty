//! `lostty-hook` (src/main_hook.zig): Claude Code's hot hook actions as
//! their own small program. It links only libSystem, and the Mac app
//! bundles it beside `lostty`.
const LosttyHook = @This();

const std = @import("std");
const Config = @import("Config.zig");
const LipoStep = @import("LipoStep.zig");

output: std.Build.LazyPath,

/// Always optimized, whatever the engine's mode: it runs on every tool
/// call of every agent, in Debug apps too.
pub fn init(b: *std.Build, cfg: *const Config) LosttyHook {
    return .{ .output = switch (cfg.xcframework_target) {
        .native => exe(b, null).getEmittedBin(),
        .universal => LipoStep.create(b, .{
            .name = "lostty-hook",
            .out_name = "lostty-hook",
            .input_a = exe(b, .aarch64).getEmittedBin(),
            .input_b = exe(b, .x86_64).getEmittedBin(),
        }).output,
    } };
}

fn exe(b: *std.Build, arch: ?std.Target.Cpu.Arch) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "lostty-hook",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main_hook.zig"),
            .target = Config.genericMacOSTarget(b, arch),
            .optimize = .ReleaseFast,
            .strip = true,
            .link_libc = true,
        }),
    });
}

/// Installs `zig-out/bin/lostty-hook`, which the Xcode project copies
/// into the app, as part of `step`.
pub fn install(self: *const LosttyHook, step: *std.Build.Step) void {
    const b = step.owner;
    step.dependOn(&b.addInstallBinFile(self.output, "lostty-hook").step);
}
