const std = @import("std");
const build = std.build;
const builtin = std.builtin;
const debug = std.debug;
const mem = std.mem;
const path = std.fs.path;

const ArrayList = std.ArrayList;

fn get_timestamp(file: []const u8) !i128 {
        const stat = try std.fs.cwd().statFile(file);
        return stat.mtime;
}

fn needs_update(dependency: []const u8, target: []const u8) !bool {
        const slack_ns = 1000000000;
        const time1 = try get_timestamp(dependency);
        const time2 = get_timestamp(target) catch |err| {
                if (err == error.FileNotFound) return true;
                return err;
        };
        const diff = time2 -| time1;
        return (diff <= slack_ns);
}

fn remove_extension(file: []const u8) []const u8 {
        const basename = path.basename(file);
        const pos = mem.lastIndexOfScalar(u8, basename, '.') orelse basename.len;
        return basename[0..pos];
}

const Manpage = struct {
        source: []const u8,
        dest: []const u8,
};

pub const ManpageStep = struct {
        step: build.Step,
        builder: *build.Builder,
        build_dir: []const u8,
        man_dir: []const u8,
        manpages: ArrayList(Manpage),
        a2x: []const u8 = A2X_PROGNAME,

        const BUILD_DIR = "build.BF62";
        const MAN_DIR = "share/man";
        const A2X_PROGNAME = "a2x";

        pub fn create(builder: *build.Builder, name: []const u8) *ManpageStep {
                const self = builder.allocator.create(ManpageStep) catch unreachable;

                self.* = ManpageStep {
                        .builder = builder,
                        .step = build.Step.init(.custom, name, builder.allocator, make),
                        .build_dir = builder.pathJoin(&.{builder.cache_root, BUILD_DIR}),
                        .man_dir = builder.pathJoin(&.{builder.install_prefix, MAN_DIR}),
                        .manpages = ArrayList(Manpage).init(builder.allocator),
                };

                return self;
        }

        pub fn add_manpage(self: *ManpageStep, dest: []const u8, source: []const u8) void {
                const dest_basename = path.basename(dest);
                const src_basename = path.basename(source);
                const src_no_extension = remove_extension(src_basename);

                debug.assert(mem.eql(u8, dest_basename, src_no_extension));

                self.manpages.append(Manpage{
                        .source = self.builder.dupe(source),
                        .dest = self.builder.dupe(dest),
                }) catch unreachable;
        }

        fn make_one(self: *ManpageStep, manpage: Manpage) !void {
                const build_path = self.builder.pathJoin(&.{self.build_dir, manpage.dest});
                const build_dir = path.dirname(build_path).?;
                const cmdline = &.{A2X_PROGNAME, "-d", "manpage", "-f", "manpage", "-D",
                        build_dir, manpage.source};
                try self.builder.makePath(build_dir);

                if (try needs_update(manpage.source, build_path))
                        _ = try self.builder.exec(cmdline);

                const install_path = self.builder.pathJoin(&.{self.man_dir, manpage.dest});
                const install_dir = path.dirname(install_path).?;
                try self.builder.makePath(install_dir);
                try self.builder.updateFile(build_path, install_path);
        }

        pub fn make(step: *build.Step) !void {
                const self = @fieldParentPtr(ManpageStep, "step", step);

                for (self.manpages.items) |manpage| {
                        try self.make_one(manpage);
                }
        }
};

pub const Builder = struct {
        builder: *build.Builder,
        default_mode: ?builtin.Mode = null,
        default_target: ?std.zig.CrossTarget = null,
        default_strip: bool = false,
        tests_toplevel: *build.Step,
        manpages_toplevel: *build.Step,
        manpages: *ManpageStep,

        pub fn init(builder: *build.Builder) Builder {
                const self = Builder {
                        .builder = builder,
                        .tests_toplevel = builder.step("test", "Run tests"),
                        .manpages_toplevel = builder.step("manpages", "Generate manual pages"),
                        .manpages = ManpageStep.create(builder, "create manpages"),
                };
                self.manpages_toplevel.dependOn(&self.manpages.step);
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

        pub fn manpage(self: *Builder, dest: []const u8, src: []const u8) void {
                self.manpages.add_manpage(dest, src);
        }
};
