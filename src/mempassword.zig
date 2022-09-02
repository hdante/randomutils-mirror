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
const assert = std.debug.assert;
const cwd = std.fs.cwd;
const io = std.io;
const mem = std.mem;
const sort = std.sort;
const stderr = io.getStdErr().writer();
const stdout = io.getStdOut().writer();

const generator = @import("generator.zig");
const sysdeps = @import("sysdeps.zig");
const utils = @import("utils.zig");
const ArgvIterator = sysdeps.ArgvIterator;
const Generator = generator.Generator;

const PATH_MAX = @maximum(std.os.PATH_MAX, 4096);
const UNIX_WORDS = "/usr/share/dict/words";
const Config = struct {
        word_file: [PATH_MAX]u8 = undefined,
        word_file_len: usize = 0,
        num_passwords: u16,
        num_words: u16,
        num_symbols: u16,
        help: bool = false,
        version: bool = false,

        fn init() Config {
                // Initialize non-zero values on init() so that the full default Config
                // struct is not stored on the binary.
                return Config {
                        .num_passwords = 5,
                        .num_words = 4,
                        .num_symbols = 4,
                };
        }
};

fn count_trues(comptime S: usize, v: @Vector(S, bool)) u16 {
        const one = @splat(S, @as(u16, 1));
        const zero = @splat(S, @as(u16, 0));
        const to_int = @select(u16, v, one, zero);
        return @reduce(.Add, to_int);
}

fn count_lines(file: anytype) !u64 {
        const V = 128;
        const NL = @splat(V, @as(u8, '\n'));
        var buff: [65536]u8 align(128) = undefined;

        var count: u64 = 0;
        var len: usize = 0;
        var prev_len: usize = 0;
        while (true) {
                len = try file.read(&buff);
                if (len == 0) break;

                @memset(buff[len..].ptr, 0, buff.len-len);

                var i: usize = 0;
                while (i < buff.len) : (i += V) {
                        const v: @Vector(V, u8) = buff[i..i+V][0..V].*;
                        const n = count_trues(V, v == NL);
                        count += n;
                }

                prev_len = len;
        }

        // Final text without newline also counts as a line
        if (prev_len > 0 and buff[prev_len-1] != '\n')
                count += 1;

        return count;
}

fn LineIterator(comptime Reader: type) type { return struct {
        const Self = @This();
        const V = 128;
        buff: [65536] u8 align(V),
        buff_len: usize,
        buff_pos: u64,
        line: u64,
        file: Reader,

        fn init(file: Reader) Self {
                return Self {
                        .buff = undefined,
                        .buff_len = 0,
                        .buff_pos = 0,
                        .line = 0,
                        .file = file,
                };
        }

        fn deinit(_: Self) void {}

        fn refill_buffer(self: *Self) !void {
                const len = try self.file.readAll(self.buff[self.buff_len..]);
                self.buff_len += len;
                @memset(self.buff[self.buff_len..].ptr, 0, self.buff.len-self.buff_len);
        }

        fn clear_buffer(self: *Self) void {
                self.buff_len = 0;
                self.buff_pos = 0;
        }

        fn get(self: *Self, index: u64) ![]u8 {
                const NL = @splat(V, @as(u8, '\n'));
                if (index < self.line) return error.RewindNeeded;

                while(true) {
                        if (self.buff_len == 0) try self.refill_buffer();
                        if (self.buff_len == 0) return error.WordNotFound;

                        // Start with a vectorized loop
                        var next_line = self.line;
                        var next_pos = self.buff_pos;
                        while (next_pos < self.buff_len) {
                                const v: @Vector(V, u8) = self.buff[next_pos..next_pos+V][0..V].*;
                                const n = count_trues(V, v == NL);
                                self.line = next_line;
                                next_line += n;
                                self.buff_pos = next_pos;
                                next_pos += V;
                                if (next_line >= index) break;
                        }

                        // If line is found, switch to byte-by-byte loop
                        if (next_line >= index) {
                                var p: u64 = self.buff_pos;
                                var l: u64 = self.line;
                                while (l < index) : (p += 1) {
                                        if (self.buff[p] == '\n') l += 1;
                                }
                                var start = p;

                                while (p < self.buff_len and l == index) : (p += 1) {
                                        if (self.buff[p] == '\n') l += 1;
                                }

                                // Handle case when buffer is full
                                if (p == self.buff_len and l == index) {
                                        mem.copy(u8, &self.buff, self.buff[start..self.buff_len]);
                                        self.buff_len -= start;
                                        try self.refill_buffer();
                                        if (self.buff_len == 0) return error.WordNotFound;
                                        self.line = l;
                                        self.buff_pos = 0;
                                        p -= start;
                                        start = 0;
                                        while (p < self.buff_len and l == index) : (p += 1) {
                                                if (self.buff[p] == '\n') l += 1;
                                        }
                                }

                                if (p > 0 and self.buff[p-1] == '\n') p -= 1;

                                const end = p;

                                return self.buff[start..end];
                        }

                        self.line = next_line;
                        self.clear_buffer();
                }
        }
}; }

const WordMap = struct {
        const MAX_WORDS = 128;
        const WORD_BUFF_SIZE = 2048;

        const Hash = std.hash.Wyhash;
        const SEED = 11900405843962615283;

        const MicroSlice = [2]u16;
        const EMPTY = MicroSlice { 65535, 65535 };

        keys: [MAX_WORDS]u64 = undefined,
        values: [MAX_WORDS]MicroSlice = .{ EMPTY } ** MAX_WORDS,
        count: usize = 0,
        word_buff: [WORD_BUFF_SIZE]u8 = undefined,
        word_buff_end: usize = 0,

        fn init() WordMap {
                return .{};
        }

        fn deinit(_: WordMap) void {}

        fn is_empty(value: MicroSlice) bool {
                return mem.eql(u16, &value, &EMPTY);
        }

        fn hash(self: WordMap, index: u64) usize {
                assert(self.count <= MAX_WORDS);

                const h = Hash.hash(SEED, mem.asBytes(&index));
                const base = @truncate(usize, h % MAX_WORDS);
                var i: usize = 0;
                while (i < MAX_WORDS) : (i += 1) {
                        const idx = (base + i) % MAX_WORDS;
                        if (is_empty(self.values[idx])) return idx;
                        if (self.keys[idx] == index) return idx;
                }
                unreachable;
        }

        fn put(self: *WordMap, index: u64, word: []const u8) !void {
                assert(WORD_BUFF_SIZE < EMPTY[0]);

                const free = self.word_buff.len - self.word_buff_end;
                if (word.len > free) return error.OutOfMemory;
                if (self.count == MAX_WORDS) return error.OutOfMemory;

                const pos = self.hash(index);

                if (is_empty(self.values[pos])) {
                        const start = self.word_buff_end;
                        const end = start + word.len;
                        mem.copy(u8, self.word_buff[start..end], word);
                        self.keys[pos] = index;
                        self.values[pos] = .{@truncate(u16, start), @truncate(u16, end)};
                        self.word_buff_end = end;
                        self.count += 1;
                }
        }

        fn get(self: WordMap, index: u64) []const u8 {
                const pos = self.hash(index);
                const v = self.values[pos];
                assert(!is_empty(v));
                return self.word_buff[v[0].. v[1]];
        }
};

fn print_symbols(cfg: Config, gen: *Generator, writer: anytype) !void
{
        // ASCII '!' to '~'
        gen.randint_set_range(33, 126);
        var i: usize = 0;
        while (i < cfg.num_symbols) : (i += 1) {
                const ch: u8 = @truncate(u8, try gen.randint());
                try writer.writeByte(ch);
        }
}

fn print_separator(_: Config, writer: anytype) !void
{
        try writer.writeAll(":-");
}

fn print_words(cfg: Config, gen: *Generator, lines: u64, reader: anytype, writer: anytype) !void
{
        // The goal here is to generate random unordered words, but iterate through the
        // input file in a sorted way, so that file reading is sequential. An auxiliary
        // hash map is used to collect the desired words while the file is being iterated.

        assert(cfg.num_words <= WordMap.MAX_WORDS);

        var word_idx_buff: [WordMap.MAX_WORDS]u64 = undefined;
        const word_idx = word_idx_buff[0..cfg.num_words];

        gen.randint_set_range(0, lines-1);
        for (word_idx) |*w| {
                w.* = try gen.randint();
        }

        var sorted_words_buff: [WordMap.MAX_WORDS]u64 = undefined;
        const sorted_words = sorted_words_buff[0..word_idx.len];
        mem.copy(u64, sorted_words, word_idx);
        sort.insertionSort(u64, sorted_words, {}, comptime sort.asc(u64));

        var word_map = WordMap.init();
        defer word_map.deinit();

        var line_iter = LineIterator(@TypeOf(reader)).init(reader);
        defer line_iter.deinit();

        for (sorted_words) |w| {
                try word_map.put(w, try line_iter.get(w));
        }

        for (word_idx) |w, j| {
                try writer.writeAll(word_map.get(w));
                if (j < word_idx.len-1)
                        try writer.writeByte(',');
        }
}

fn print_password(cfg: Config, gen: *Generator, lines: u64, reader: anytype, writer: anytype)
!void {
        assert(WordMap.MAX_WORDS >= cfg.num_words);

        try print_symbols(cfg, gen, writer);
        try print_separator(cfg, writer);
        try print_words(cfg, gen, lines, reader, writer);
        try writer.writeByte('\n');
}

fn run(cfg: Config) !void {
        var gen = try Generator.init();
        defer gen.deinit();

        const word_file = cfg.word_file[0..cfg.word_file_len];
        const reader = (try cwd().openFile(word_file, .{})).reader();
        defer reader.context.close();

        const lines = try count_lines(reader);
        if (lines == 0) return error.EmptyFile;

        const writer = io.bufferedWriter(stdout).writer();

        var i: usize = 0;
        while (i < cfg.num_passwords) : (i += 1) {
                try reader.context.seekTo(0);
                try print_password(cfg, &gen, lines, reader, writer);
        }

        try writer.context.flush();
}

fn parse_cmdline(cfg: *Config) !void {
        const ARENA_SIZE = @minimum(PATH_MAX + 2048, 1<<18);
        var arena: [ARENA_SIZE]u8 = undefined;
        const allocator = FixedBufferAllocator.init(&arena).allocator();
        var args = try ArgvIterator.init(allocator);
        // don't free args, the fixed buffer allocator arena is on the stack.
        // defer args.deinit();

        var forcearg = false;
        var argidx: u8 = 0;

        while (args.next()) |arg_| {
                const arg = try arg_;
                // don't free arg, the fixed buffer allocator arena is on the stack.
                // defer allocator.free(arg);

                if (argidx > 0 and arg[0] == '-' and !forcearg) {
                        for (arg[1..]) |ch| {
                                switch (ch) {
                                        'h', '?' => cfg.help = true,
                                        'v' => cfg.version = true,
                                        '-' => forcearg = true,
                                        else => return error.InvalidParameters,
                                }
                        }
                }
                else {
                        if (argidx > 1) return error.InvalidParameters;
                        if (argidx == 1) {
                                if (arg.len > cfg.word_file.len) return error.OutOfMemory;
                                std.mem.copy(u8, &cfg.word_file, arg);
                                cfg.word_file_len = arg.len;
                        }

                        argidx += 1;
                }
        }

        if (argidx <= 1) {
                std.mem.copy(u8, &cfg.word_file, UNIX_WORDS);
                cfg.word_file_len = UNIX_WORDS.len;
        }
}

fn invalid_parameters() void {
        const INVALID =
      \\mempassword: Invalid parameters.
      \\Try 'mempassword -h' for more information.
      \\
      ;

        stderr.writeAll(INVALID) catch {};
}

fn show_help() !void {
        const HELP =
      \\Generate easy to memorize, hard to guess password.
      \\
      \\Usage:
      \\  mempassword [--] [<wordfile>]
      \\  mempassword -h|-?
      \\  mempassword -v
      \\
      \\Options:
      \\   <wordfile>   Text file with words to choose from (default:
      \\                /usr/share/dict/words).
      \\   -h, -?	Show help message.
      \\   -v		Show program version number.
      \\
      \\Generates passwords composed of random symbols, followed by a fixed separator,
      \\followed by words randomly selected from a word file separated by commas. The
      \\word file must be a text file with one word per line.
      \\
 ;
        try stdout.writeAll(HELP);
}

fn show_version() !void {
        try stdout.writeAll(utils.VERSION_STRING);
}

var global_cfg: Config = undefined;

fn guarded_main() !u8 {
        global_cfg = Config.init();

        parse_cmdline(&global_cfg) catch {
                invalid_parameters();
                return utils.EXIT_FAILURE;
        };

        if (global_cfg.help) {
                try show_help();
                return utils.EXIT_SUCCESS;
        }

        if (global_cfg.version) {
                try show_version();
                return utils.EXIT_SUCCESS;
        }

        try run(global_cfg);

        return utils.EXIT_SUCCESS;
}

pub fn main() u8 {
        return guarded_main() catch |err| {
                stderr.print("mempassword: {s}\n", .{ utils.strerror(err) }) catch {};
                return utils.EXIT_FAILURE;
        };
}

const expect = std.testing.expect;
const expectError = std.testing.expectError;
const words = @embedFile("../test/words.slice");
const TestFixedBufferStream = io.FixedBufferStream([]const u8);
const TestLineIterator = LineIterator(TestFixedBufferStream.Reader);

test "Vectorized count trues" {
        try expect(count_trues(2, @splat(2, false)) == 0);
        try expect(count_trues(128, @splat(128, false)) == 0);
        try expect(count_trues(4096, @splat(4096, false)) == 0);
        try expect(count_trues(2, @splat(2, true)) == 2);
        try expect(count_trues(128, @splat(128, true)) == 128);
        try expect(count_trues(4096, @splat(4096, true)) == 4096);

        const A = @Vector(8, bool) { false, true, false, true, false, true, false, true };
        const B = @Vector(8, bool) { true, false, true, false, true, false, true, false };
        const C = @Vector(8, bool) { true, false, false, false, false, false, false, false };
        const D = @Vector(8, bool) { false, true, true, true, true, true, true, true };
        const E = @Vector(8, bool) { false, false, false, false, false, false, false, true };
        const F = @Vector(8, bool) { true, true, true, true, true, true, true, false };
        const G = @Vector(8, bool) { true, true, false, true, true, true, false, false };

        try expect(count_trues(8, A) == 4);
        try expect(count_trues(8, B) == 4);
        try expect(count_trues(8, C) == 1);
        try expect(count_trues(8, D) == 7);
        try expect(count_trues(8, E) == 1);
        try expect(count_trues(8, F) == 7);
        try expect(count_trues(8, G) == 5);
}

test "Count file lines" {
        const A = [_][]const u8 {
                "", "a", "\n", "a\n", "a\na", "a\na\n", "a\na\na",
                "a" ** 65536, "\n" ** 65536, "a" ** 65535 ++ "\n", "aa\n" ** 1024, "aa\n" ** 99999,
                "A\na\nAA\nAAA\nAachen\nAachen's\naah\nAaliyah\nAaliyah's\naardvark\n",
                "A\na\nAA\nAAA\nAachen\nAachen's\naah\nAaliyah\nAaliyah's\naardvark\n" ** 100000,
                "a" ** 65535 ++ "\n" ++ "a", "abcd" ** 8192 ++ "\n" ++ "abcd" ** 8192,
                "abcd" ** 8192 ++ "\n" ++ "abcd" ** 8192 ++ "\n",
                "abcd" ** 8192 ++ "\n" ++ "abcd" ** 8192 ++ "\n" ++ "abcd" ** 8192,
                "abcd" ** 8192 ++ "\n" ++ "abcd" ** 8192 ++ "\n" ++ "abcd" ** 8192 ++ "\n",
                "\n" ++ "a" ** 65536, "\n" ++ "a" ** 65535 ++ "\n",
        };

        const R = [A.len]u64 {
                0, 1, 1, 1, 2, 2, 3,
                1, 65536, 1, 1024, 99999,
                10,
                1000000,
                2, 2,
                2,
                3,
                3,
                2, 2,
        };

        for (A) |a, i| {
                try expect((try count_lines(io.fixedBufferStream(a).reader())) == R[i]);
        }

        try expect((try count_lines(io.fixedBufferStream(words).reader())) == 20539);
}

test "Try to get line on empty file" {
        const reader = io.fixedBufferStream("").reader();
        var iter = LineIterator(@TypeOf(reader)).init(reader);
        defer iter.deinit();
        try expectError(error.WordNotFound, iter.get(0));
        try expectError(error.WordNotFound, iter.get(0));
        try expectError(error.WordNotFound, iter.get(1));
        try expectError(error.WordNotFound, iter.get(2));
        try expectError(error.WordNotFound, iter.get(3));
        try expectError(error.WordNotFound, iter.get(10));
        try expectError(error.WordNotFound, iter.get(100));
        try expectError(error.WordNotFound, iter.get(1));
}

test "Get single file lines" {
        const A = [_][]const u8 {
                "a", "a\n", "a\nb", "a\nb\n", "\nb\n", "\nb", "\n",
                "a\nb", "a\nb\n", "\nb\n", "\nb",
                "a" ** 65536, "\n" ** 65536, "a" ** 65535 ++ "\n", "aa\n" ** 1024, "aa\n" ** 99999,
                "A\na\nAA\nAAA\nAachen\nAachen's\naah\nAaliyah\nAaliyah's\naardvark\n",
                "A\na\nAA\nAAA\nAachen\nAachen's\naah\nAaliyah\nAaliyah's\naardvark\n" ** 100000,
                "a" ** 65535 ++ "\n" ++ "b",
                "a" ** 65535 ++ "\n" ++ "b" ** 65536,
                "a" ** 65535 ++ "\n" ++ "b" ** 65535 ++ "\n",
                "abcd" ** 8192 ++ "\n" ++ "efgh" ** 8192,
                "abcd" ** 8192 ++ "\n" ++ "efgh" ** 8192 ++ "\n",
                "abcd" ** 8192 ++ "\n" ++ "efgh" ** 8192 ++ "\n" ++ "ijkl" ** 8192,
                "abcd" ** 8192 ++ "\n" ++ "efgh" ** 8192 ++ "\n" ++ "ijkl" ** 8192 ++ "\n",
                "\n" ++ "a" ** 65536, "\n" ++ "a" ** 65535 ++ "\n",
        };

        const L = [A.len]u64 {
                0, 0, 0, 0, 0, 0, 0,
                1, 1, 1, 1,
                0, 300, 0, 511, 32768,
                9,
                54534,
                1,
                1,
                1,
                1,
                1,
                2,
                2,
                1, 1,
        };

        const R = [A.len][]const u8 {
                "a", "a", "a", "a", "", "", "",
                "b", "b", "b", "b",
                "a" ** 65536, "", "a" ** 65535, "aa", "aa",
                "aardvark",
                "Aachen",
                "b",
                "b" ** 65536,
                "b" ** 65535,
                "efgh" ** 8192,
                "efgh" ** 8192,
                "ijkl" ** 8192,
                "ijkl" ** 8192,
                "a" ** 65536, "a" ** 65535,
        };

        for (A) |a, i| {
                const reader = io.fixedBufferStream(a).reader();
                var iter = TestLineIterator.init(reader);
                defer iter.deinit();
                const line = try iter.get(L[i]);
                try expect(mem.eql(u8, R[i], line));
        }
}

test "Get lines from Enligh dictionary" {
        const L = [_]u64 {
                0, 1, 2, 3, 4, 5,
                10, 100, 1000, 1001, 6620, 6621,
                7080, 7081, 7082, 7083, 7084, 7085,
                7086, 7087, 7088, 7089, 7090, 7091,
                7092, 7093, 7094, 7095,
                7134, 7223, 7230,
                10000,

        };

        const R = [L.len][]const u8 {
                "A", "a", "AA", "AAA", "Aachen", "Aachen's",
                "aardvark's", "abdominal", "actuary", "actuary's", "Audubon", "Audubon's",
                "awesomeness's", "awestruck", "awful", "awfuller", "awfullest", "awfully",
                "awfulness", "awfulness's", "awhile", "awing", "awkward", "awkwarder",
                "awkwardest", "awkwardly", "awkwardness", "awkwardness's",
                "axon's", "babe", "babe's",
                "betaken",
        };

        const reader = io.fixedBufferStream(words).reader();
        var iter = TestLineIterator.init(reader);
        defer iter.deinit();

        for (L) |l, i| {
                const line = try iter.get(l);
                try expect(mem.eql(u8, R[i], line));
        }
}

test "Simple word map" {
        assert(WordMap.MAX_WORDS >= 4);
        assert(WordMap.WORD_BUFF_SIZE >= 9);

        var word_map = WordMap.init();
        defer word_map.deinit();

        for (word_map.values) |v| {
                try expect(WordMap.is_empty(v));
        }
        try expect(word_map.count == 0);
        try word_map.put(1, "a");
        try expect(word_map.count == 1);
        try expect(mem.eql(u8, word_map.get(1), "a"));
        try word_map.put(1, "a");
        try expect(word_map.count == 1);
        try expect(mem.eql(u8, word_map.get(1), "a"));
        try word_map.put(1, "a");
        try expect(word_map.count == 1);
        try expect(mem.eql(u8, word_map.get(1), "a"));
        try word_map.put(2, "a");
        try expect(word_map.count == 2);
        try expect(mem.eql(u8, word_map.get(1), "a"));
        try expect(mem.eql(u8, word_map.get(2), "a"));

        var count: usize = 0;
        for (word_map.values) |v| {
                if (!WordMap.is_empty(v)) count += 1;
        }
        try expect(count == 2);

        try word_map.put(3, "abcd");
        try word_map.put(4, "");
        try expect(mem.eql(u8, word_map.get(3), "abcd"));
        try expect(mem.eql(u8, word_map.get(4), ""));
}

test "Full word map items" {
        assert(WordMap.WORD_BUFF_SIZE >= WordMap.MAX_WORDS);

        var word_map = WordMap.init();
        defer word_map.deinit();

        const BASE = 1000000;
        var i: u64 = 0;
        while (i < WordMap.MAX_WORDS) : (i += 1) {
                try word_map.put(BASE+i, "a");
        }
        i = 0;
        while (i < WordMap.MAX_WORDS) : (i += 1) {
                try expect(mem.eql(u8, word_map.get(BASE+i), "a"));
        }

        try expectError(error.OutOfMemory, word_map.put(BASE+i, "a"));
        try expectError(error.OutOfMemory, word_map.put(BASE+i+1, ""));
}

test "Full word map buffer" {
        assert(WordMap.WORD_BUFF_SIZE >= WordMap.MAX_WORDS);

        var word_map = WordMap.init();
        defer word_map.deinit();

        const LARGE_MSG = "a" ** 512;
        const LARGE_MSG_COUNT = @minimum(WordMap.WORD_BUFF_SIZE / LARGE_MSG.len,
                WordMap.MAX_WORDS - 2);
        const REMAINING = WordMap.WORD_BUFF_SIZE - LARGE_MSG_COUNT*LARGE_MSG.len;
        const REMAINING_MSG = "b" ** REMAINING;

        assert(REMAINING == 0);

        var i: usize = 0;
        while (i < LARGE_MSG_COUNT) : (i += 1) {
                try word_map.put(i, LARGE_MSG);
        }
        try word_map.put(0xffffffffffffffff, REMAINING_MSG);

        i = 0;
        while (i < LARGE_MSG_COUNT) : (i += 1) {
                try expect(mem.eql(u8, word_map.get(i), LARGE_MSG));
        }

        try expect(mem.eql(u8, word_map.get(0xffffffffffffffff), REMAINING_MSG));

        try expectError(error.OutOfMemory, word_map.put(0xfffffffffffffffe, "c"));
}
