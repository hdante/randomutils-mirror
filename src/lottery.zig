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
const parseUnsigned = std.fmt.parseUnsigned;
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const generator = @import("generator.zig");
const sysdeps = @import("sysdeps.zig");
const utils = @import("utils.zig");
const ArgvIterator = sysdeps.ArgvIterator;
const Generator = generator.Generator;

const Number = u64;
const LogNumber = u6;
const MAX_RANGE = 1<<20;
const NUMBER_BITS = @sizeOf(Number)*8;
const ARRAY_COUNT = MAX_RANGE/NUMBER_BITS;
var bit_array = [1]Number { 0 } ** ARRAY_COUNT;

const Config = struct {
        first: u32 = 1,
        last: u32 = 60,
        count: u32 = 6,
        help: bool = false,
        version: bool = false,
};

const BitAddress = struct {
        byte: u32,
        bit: Number,
};

fn bit_address(idx: u32) BitAddress {
        const byte = idx / NUMBER_BITS;
        const bit = @intCast(LogNumber, idx % NUMBER_BITS);
        const v = @as(Number, 1) << bit;

        return BitAddress { .byte = byte, .bit = v };
}

fn check_bit(addr: BitAddress) bool {
        return (bit_array[addr.byte] & addr.bit == 0);
}

fn set_bit(addr: BitAddress) void {
        bit_array[addr.byte] |= addr.bit;
}

fn run(cfg: Config) !void {
        var gen = try Generator.init();
        defer gen.deinit();

        gen.randint_set_range(cfg.first, cfg.last);

        var i: u32 = 0;
        while (i < cfg.count) {
                const r = try gen.randint();
                const idx = @truncate(u32, r-gen.first);
                const addr = bit_address(idx);

                if (check_bit(addr)) {
                        set_bit(addr);
                        i += 1;
                        if (i < cfg.count) {
                                try stdout.print("{} ", .{r});
                        }
                        else {
                                try stdout.print("{}", .{r});
                        }
                }
        }
        try stdout.writeAll("\n");
}

fn parse_cmdline(cfg: *Config) !void {
        var arena: [2048]u8 = undefined;
        const allocator = FixedBufferAllocator.init(&arena).allocator();
        var args = try ArgvIterator.init(allocator);
        // don't free args, the fixed buffer allocator arena is on the stack.
        // defer args.deinit();

        var argidx: u8 = 0;

        while (args.next()) |arg_| {
                const arg = try arg_;
                // don't free arg, the fixed buffer allocator arena is on the stack.
                // defer allocator.free(arg);

                if (argidx > 0 and arg[0] == '-') {
                        for (arg[1..]) |ch| {
                                switch (ch) {
                                        'h', '?' => cfg.help = true,
                                        'v' => cfg.version = true,
                                        else => return error.InvalidParameters,
                                }
                        }
                }
                else if (argidx == 0) {
                        argidx += 1;
                }
                else if (argidx > 3) {
                        return error.InvalidParameters;
                }
                else {
                        const value = try parseUnsigned(u32, arg, 0);

                        if (argidx == 1) {
                                cfg.count = value;
                                if (cfg.count == 0) return error.InvalidParameters;
                                if (cfg.count > MAX_RANGE) return error.InvalidParameters;
                        }
                        else if (argidx == 2) {
                                cfg.first = value;
                        }
                        else if (argidx == 3) {
                                cfg.last = value;
                        }

                        argidx += 1;
                }
        }

        if (cfg.last < cfg.first) return error.InvalidParameters;
        const range = cfg.last - cfg.first +| 1;
        if (range > MAX_RANGE) return error.InvalidParameters;
        if (range <= cfg.count) return error.InvalidParameters;
}

fn invalid_parameters() void {
        const INVALID =
      \\lottery: Invalid parameters.
      \\Try 'lottery -h' for more information.
      \\
      ;

        stderr.writeAll(INVALID) catch {};
}

fn show_help() !void {
        const HELP =
      \\Generate numbers for lottery tickets.
      \\
      \\Usage:
      \\  lottery [<count> [<first> [<last>]]]
      \\  lottery -h|-?
      \\  lottery -v
      \\
      \\Options:
      \\   <count>	Generate <count> numbers [default: 6].
      \\   <first>	Set the range starting from <first> [default: 1].
      \\   <last>	Set the range up to <last> [default: 60].
      \\   -h, -?	Show help message.
      \\   -v		Show program version number.
      \\
      \\Generates random numbers for lottery tickets without repetition, without bias.
      \\Accepts numbers with a maximum range of 1048576 (slightly more than 1 million).
      \\<first> must be smaller than <last> and <count> must be smaller than the
      \\requested range.
      \\
 ;
        try stdout.writeAll(HELP);
}

fn show_version() !void {
        try stdout.writeAll(utils.VERSION_STRING);
}

fn guarded_main() !u8 {
        var cfg = Config {};

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
                stderr.print("lottery: {s}\n", .{ utils.strerror(err) }) catch {};
                return utils.EXIT_FAILURE;
        };
}
