const std = @import("std");

const build_functions = @import("build_functions.zig");
const Builder = build_functions.Builder;

pub fn build(std_builder: *std.build.Builder) void {
        var builder = Builder.init(std_builder);
        builder.standard_target_options();
        builder.standard_build_mode(.ReleaseFast);
        builder.executable("random", "src/random.zig");
        builder.executable("lottery", "src/lottery.zig");
        builder.test_("src/tests.zig");
        builder.manpage("man1/random.1", "doc/random.1.txt");
        builder.manpage("man1/lottery.1", "doc/lottery.1.txt");
}
