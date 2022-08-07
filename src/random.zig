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
const stdout = std.io.getStdOut();
const stderr = std.io.getStdErr().writer();

const generator = @import("generator.zig");
const sysdeps = @import("sysdeps.zig");
const utils = @import("utils.zig");
const ArgvIterator = sysdeps.ArgvIterator;
const Generator = generator.Generator;

const Format = enum {
        d64,
        x64,
        X64,
        binary,
        base64url,
        ascii85,
};

const Config = struct {
        first: u64 = 0,
        last: u64 = maxInt(u64),
        count: u64 = 1,
        format: Format = .d64,
        help: bool = false,
        version: bool = false,
        separator: u8 = '\n',
};

fn print_one(cfg: Config, buffer: []u8, value: u64) usize {
        if (cfg.format == .x64) return utils.fmt_x(buffer, value, false);
        if (cfg.format == .X64) return utils.fmt_x(buffer, value, true);
        if (cfg.format == .binary) return utils.fmt_bin(buffer, value);
        if (cfg.format == .base64url) return utils.fmt_base64url(buffer, value);
        if (cfg.format == .ascii85) return utils.fmt_ascii85(buffer, value);
        return utils.fmt_d(buffer, value);
}

fn more(cfg: Config, gen: *Generator, count: u64) !usize {
        // Hot loop is in this function. Loop condition is kept very simple.
        const MAX_NUMBERS = 700;
        const MAX_LENGTH = 21;
        const BUFFER_LENGTH = MAX_NUMBERS*MAX_LENGTH;
        var buffer: [BUFFER_LENGTH]u8 = undefined;

        var i: u64 = 0;
        var p: usize = 0;
        var n = @minimum(count, MAX_NUMBERS);

        while (i < n-1) : (i += 1) {
                const r = try gen.randint();
                p += print_one(cfg, buffer[p..], r);
                if (cfg.format != .binary) {
                        buffer[p] = cfg.separator;
                        p += 1;
                }
        }

        const r = try gen.randint();
        p += print_one(cfg, buffer[p..], r);

        if (cfg.format != .binary) {
                if (n == count and cfg.separator != '\x00') {
                        // Final newline terminator is only for plain text output.
                        buffer[p] = '\n';
                }
                else
                        buffer[p] = cfg.separator;

                p += 1;
        }

        try stdout.writeAll(buffer[0..p]);

        return n;
}

fn run(cfg: Config) !void {
        var gen = try Generator.init();
        defer gen.deinit();

        gen.randint_set_range(cfg.first, cfg.last);

        var count = cfg.count;
        while (count > 0) {
                count -= try more(cfg, &gen, count);
        }
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
                                        'x' => cfg.format = .x64,
                                        'X' => cfg.format = .X64,
                                        'b' => cfg.format = .binary,
                                        '6' => cfg.format = .base64url,
                                        '8' => cfg.format = .ascii85,
                                        '0' => cfg.separator = '\x00',
                                        's' => cfg.separator = ' ',
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
                        const value = try parseUnsigned(u64, arg, 0);

                        if (argidx == 1) {
                                cfg.count = value;
                                if (cfg.count == 0) return error.InvalidParameters;
                        }
                        else if (argidx == 2) {
                                cfg.first = value;
                        }
                        else if (argidx == 3) {
                                cfg.last = value;
                                if (cfg.last < cfg.first)
                                        return error.InvalidParameters;
                        }

                        argidx += 1;
                }
        }
}

fn invalid_parameters() void {
        const INVALID =
      \\random: Invalid parameters.
      \\Try 'random -h' for more information.
      \\
      ;

        stderr.writeAll(INVALID) catch {};
}

fn show_help() !void {
        const HELP =
      \\Generate 64-bit random numbers.
      \\
      \\Usage:
      \\  random [OPTION] [<count> [<first> [<last>]]]
      \\  random -h|-?
      \\  random -v
      \\
      \\Options:
      \\   <count>	Generate <count> numbers [default: 1].
      \\   <first>	Set the range starting from <first> [default: 0].
      \\   <last>	Set the range up to <last> [default: 18446744073709551615].
      \\   -x		Print numbers in hexadecimal format with lower case digits.
      \\   -X		Print numbers in hexadecimal format with upper case digits.
      \\   -b		Print numbers as a contiguous array of fixed length 64-bit
      \\		binary numbers in network byte order (big-endian).
      \\   -6		Print numbers as 64-bit binary numbers stored in network byte
      \\		order (big-endian), encoded in RFC 4648 base64url format
      \\		without padding.
      \\   -8		Print numbers as 64-bit binary numbers stored in network byte
      \\		order (big-endian), encoded in Ascii85 format without framing.
      \\   -s		Use space as the number separator.
      \\   -0		Use the zero (null) character as the number separator.
      \\   -h, -?	Show help message.
      \\   -v		Show program version number.
      \\
      \\Generates unsigned 64-bit numbers by using a cryptographically secure
      \\pseudorandom number generator (CSPRNG), seeded by the operating system-supplied
      \\entropy source, trying to remove any biasing generated by calculations to fit
      \\them within the requested range.
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
                stderr.print("random: {s}\n", .{ utils.strerror(err) }) catch {};
                return utils.EXIT_FAILURE;
        };
}
