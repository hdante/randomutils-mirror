const std = @import("std");
const build = std.build;
const builtin = std.builtin;
const debug = std.debug;

pub const Builder = struct {
        builder: *build.Builder,
        default_mode: ?builtin.Mode = null,
        default_target: ?std.zig.CrossTarget = null,
        default_strip: bool = false,
        tests_toplevel: *build.Step,

        pub fn init(builder: *build.Builder) Builder {
                const self = Builder {
                        .builder = builder,
                        .tests_toplevel = builder.step("test", "Run tests"),
                };
                return self;
        }

        pub fn standard_target_options(self: *Builder) void {
               self.default_target = self.builder.standardTargetOptions(.{});
        }

        pub fn standard_build_mode(self: *Builder, default_mode: builtin.Mode) void {
                var mode = self.builder.standardReleaseOptions();
                const is_release = mode != .Debug;
                const is_debug = self.builder.option(bool, "debug", "Disable optimizations")
                        orelse false;
                const strip = self.builder.option(bool, "strip", "Remove debug information")
                        orelse false;

                if (is_release and is_debug) {
                        debug.print("Multiple build modes given (both release and debug)\n\n",
                                .{});
                        self.builder.invalid_user_input = true;
                        return;
                }
                if (!is_release and !is_debug)
                        mode = default_mode;

                self.default_mode = mode;
                self.default_strip = strip;
        }

        pub fn executable(self: *Builder, name: []const u8, src: []const u8) void {
                const exe = self.builder.addExecutable(name, src);
                if (self.default_target) |default_target| exe.setTarget(default_target);
                if (self.default_mode) |default_mode| exe.setBuildMode(default_mode);
                exe.strip = self.default_strip;
                exe.install();
        }

        pub fn test_(self: *Builder, src: []const u8) void {
                const test_step = self.builder.addTest(src);
                if (self.default_target) |default_target| test_step.setTarget(default_target);
                if (self.default_mode) |default_mode| test_step.setBuildMode(default_mode);
                self.tests_toplevel.dependOn(&test_step.step);
        }
};
