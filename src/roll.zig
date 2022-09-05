// randomutils: Generate 64-bit random numbers.
// Copyright © 2022 Henrique Dante de Almeida
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const maxInt = std.math.maxInt;
const parseUnsigned = std.fmt.parseUnsigned;
const sliceTo = std.mem.sliceTo;
var stdout: std.fs.File.Writer = undefined;
var stderr: std.fs.File.Writer = undefined;

const generator = @import("generator.zig");
const sysdeps = @import("sysdeps.zig");
const utils = @import("utils.zig");
const ArgvIterator = sysdeps.ArgvIterator;
const Generator = generator.Generator;

const Roll = struct {
        count: usize,
        max: u64,
};

const Format = enum {
        decimal,
        dice,
        cards,
};

const MAX_ROLLS = 500;
const Config = struct {
        roll_buff: [MAX_ROLLS]Roll = undefined,
        roll_count: usize = 0,
        format: Format = .decimal,
        help: bool = false,
        version: bool = false,
};

const DICE = [6][]const u8 { "⚀", "⚁", "⚂", "⚃", "⚄", "⚅" };
const CARDS = [4][13][]const u8 {
        .{ "🂡", "🂢", "🂣", "🂤", "🂥", "🂦", "🂧", "🂨", "🂩", "🂪", "🂫", "🂭", "🂮" },
        .{ "🂱", "🂲", "🂳", "🂴", "🂵", "🂶", "🂷", "🂸", "🂹", "🂺", "🂻", "🂽", "🂾" },
        .{ "🃁", "🃂", "🃃", "🃄", "🃅", "🃆", "🃇", "🃈", "🃉", "🃊", "🃋", "🃍", "🃎" },
        .{ "🃑", "🃒", "🃓", "🃔", "🃕", "🃖", "🃗", "🃘", "🃙", "🃚", "🃛", "🃝", "🃞" },
};

fn print_value(cfg: Config, gen: *Generator, roll: Roll, value: u64) !void {
        switch (cfg.format) {
                .decimal => try stdout.print("{}", .{value}),
                .dice => try stdout.writeAll(DICE[@truncate(usize, value-1)]),
                .cards => {
                        gen.randint_set_range(0, 3);
                        const suit = @truncate(usize, try gen.randint());
                        try stdout.writeAll(CARDS[suit][@truncate(usize, value-1)]);
                        gen.randint_set_range(1, roll.max);
                },
        }
}

fn roll_one(cfg: Config, gen: *Generator, roll: Roll) !void {
        gen.randint_set_range(1, roll.max);

        var i: usize = 1;
        while (i < roll.count) : (i += 1) {
                const v = try gen.randint();
                try print_value(cfg, gen, roll, v);
                try stdout.writeAll(" ");
        }

        const v = try gen.randint();
        try print_value(cfg, gen, roll, v);
        try stdout.writeAll("\n");
}

fn run(cfg: Config) !void {
        var gen = try Generator.init();
        defer gen.deinit();

        const rolls = cfg.roll_buff[0..cfg.roll_count];

        for (rolls) |roll| {
                try roll_one(cfg, &gen, roll);
        }
}

fn validate_config(cfg: Config) !void {
        if (cfg.help or cfg.version) return;

        const limit: u64 = switch (cfg.format) {
                .decimal => maxInt(u64),
                .dice => DICE.len,
                .cards => CARDS[0].len,
        };

        var i: usize = 0;
        while (i < cfg.roll_count) : (i += 1) {
                const roll = cfg.roll_buff[i];

                if (roll.count == 0) return error.InvalidParameters;
                if (roll.max == 0) return error.InvalidParameters;
                if (roll.max > limit) return error.InvalidParameters;
        }
}

fn parse_roll(arg: []const u8) !Roll {
        var roll: Roll = undefined;

        const x = sliceTo(arg, 'd');
        roll.count = try parseUnsigned(usize, x, 10);
        if (x.len < arg.len) {
                const y = arg[x.len+1..];
                roll.max = try parseUnsigned(u64, y, 10);
        }
        else {
                roll.max = DICE.len;
        }

        return roll;
}

fn parse_cmdline(cfg: *Config) !void {
        var arena: [2048]u8 = undefined;
        const allocator = FixedBufferAllocator.init(&arena).allocator();
        var args = try ArgvIterator.init(allocator);
        // don't free args, the fixed buffer allocator arena is on the stack.
        // defer args.deinit();

        var argidx: usize = 0;

        while (args.next()) |arg_| {
                const arg = try arg_;
                // don't free arg, the fixed buffer allocator arena is on the stack.
                // defer allocator.free(arg);

                if (argidx > 0 and arg[0] == '-') {
                        for (arg[1..]) |ch| {
                                switch (ch) {
                                        'h', '?' => cfg.help = true,
                                        'v' => cfg.version = true,
                                        'd' => cfg.format = .dice,
                                        'c' => cfg.format = .cards,
                                        else => return error.InvalidParameters,
                                }
                        }
                }
                else if (argidx > cfg.roll_buff.len) {
                        return error.OutOfMemory;
                }
                else {
                        if (argidx > 0)
                                cfg.roll_buff[argidx-1] = try parse_roll(arg);

                        argidx += 1;
                }
        }

        if (argidx <= 1) {
                cfg.roll_buff[0] = Roll { .count = 1, .max = 6 };
                cfg.roll_count = 1;
        }
        else {
                cfg.roll_count = argidx - 1;
        }

        try validate_config(cfg.*);
}

fn invalid_parameters() void {
        const INVALID =
      \\roll: Invalid parameters.
      \\Try 'roll -h' for more information.
      \\
      ;

        stderr.writeAll(INVALID) catch {};
}

fn show_help() !void {
        const HELP =
      \\Generate 64-bit random numbers.
      \\
      \\Usage:
      \\  roll [OPTION] (<x>|<x>d<y>)...
      \\  roll -h|-?
      \\  roll -v
      \\
      \\Options:
      \\   <x>          Generate <x> values.
      \\   <y>          Set range from 1 to <y> (default: 6).
      \\   -d           Output Unicode dice characters.
      \\   -c           Output Unicode French deck cards.
      \\   -h, -?	Show help message.
      \\   -v		Show program version number.
      \\
      \\Generates unsigned 64-bit numbers by using a cryptographically secure
      \\pseudorandom number generator (CSPRNG), seeded by the operating system-supplied
      \\entropy source, without bias. The parameter syntax is the same as used in RPG
      \\dice roll notation.
      \\
 ;
        try stdout.writeAll(HELP);
}

fn show_version() !void {
        try stdout.writeAll(utils.VERSION_STRING);
}

fn guarded_main() !u8 {
        var cfg = Config {};
        stdout = std.io.getStdOut().writer();
        stderr = std.io.getStdErr().writer();

        parse_cmdline(&cfg) catch {
                invalid_parameters();
                return utils.EXIT_FAILURE;
        };

        if (cfg.help) {
                try show_help();
                return utils.EXIT_SUCCESS;
        }

        if (cfg.version) {
                try show_version();
                return utils.EXIT_SUCCESS;
        }

        try run(cfg);

        return utils.EXIT_SUCCESS;
}

pub fn main() u8 {
        return guarded_main() catch |err| {
                stderr.print("roll: {s}\n", .{ utils.strerror(err) }) catch {};
                return utils.EXIT_FAILURE;
        };
}
