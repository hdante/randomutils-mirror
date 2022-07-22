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

const builtin = @import("builtin");
const std = @import("std");
const os = std.os;
const math = std.math;
const mem = std.mem;

const sysdeps = @import("sysdeps.zig");
const Entropy = if (builtin.is_test) EntropyMock else sysdeps.Entropy;

const Chacha20NativeEndianVector = struct {
        const Self = @This();
        const BLOCK_COUNT = 16;
        const U64_COUNT = 8;
        const ALIGNMENT = 16;
        const SEED_SIZE = 48;

        state: [BLOCK_COUNT] u32 align(ALIGNMENT),

        const HEADER align(ALIGNMENT) = "expand 32-byte k".*;
        const HEADER_SIZE = 16;
        const HEADER_COUNT = 4;
        const COUNTER0 = 12;
        const COUNTER1 = 13;

        fn init() Self {
                var self: Self = undefined;
                @memcpy(@ptrCast([*] u8, &self.state), &HEADER, HEADER_SIZE);
                self.state[COUNTER0] = 0;
                return self;
        }

        fn deinit(_: *Self) void {
        }

        fn seed(self: *Self, entropy: *Entropy) !void {
                try entropy.get_entropy(mem.sliceAsBytes(self.state[HEADER_COUNT..]));
        }

        fn should_seed(self: Self) bool {
                return (self.state[COUNTER0] & 0x3fff == 0);
        }

        fn next(self: *Self) void {
                const overflow = @addWithOverflow(u32, self.state[COUNTER0], 1,
                        &self.state[COUNTER0]);
                self.state[COUNTER1] +%= @boolToInt(overflow);
        }

        fn round(a: *@Vector(4, u32), b: *@Vector(4, u32), c: *@Vector(4, u32),
                 d: *@Vector(4, u32)) void {
                a.* +%= b.*; d.* ^= a.*; d.* = math.rotl(@Vector(4, u32), d.*, 16);
                c.* +%= d.*; b.* ^= c.*; b.* = math.rotl(@Vector(4, u32), b.*, 12);
                a.* +%= b.*; d.* ^= a.*; d.* = math.rotl(@Vector(4, u32), d.*, 8);
                c.* +%= d.*; b.* ^= c.*; b.* = math.rotl(@Vector(4, u32), b.*, 7);
        }

        fn generate(self: Self, buffer: *[BLOCK_COUNT] u32) void {
                var a: @Vector(4, u32) = undefined;
                var b: @Vector(4, u32) = undefined;
                var c: @Vector(4, u32) = undefined;
                var d: @Vector(4, u32) = undefined;
                var x: @Vector(4, u32) = undefined;
                var y: @Vector(4, u32) = undefined;
                var z: @Vector(4, u32) = undefined;
                var w: @Vector(4, u32) = undefined;
                const rotl1 = @Vector(4, i32) { 1, 2, 3, 0 };
                const rotl2 = @Vector(4, i32) { 2, 3, 0, 1 };
                const rotl3 = @Vector(4, i32) { 3, 0, 1, 2 };

                for (self.state[0..4]) |v, i| { a[i] = v; }
                for (self.state[4..8]) |v, i| { b[i] = v; }
                for (self.state[8..12]) |v, i| { c[i] = v; }
                for (self.state[12..16]) |v, i| { d[i] = v; }
                x = a;
                y = b;
                z = c;
                w = d;

                var i: usize = 0;
                while (i < 10) : (i += 1) {
                        round(&a, &b, &c, &d);

                        b = @shuffle(u32, b, undefined, rotl1);
                        c = @shuffle(u32, c, undefined, rotl2);
                        d = @shuffle(u32, d, undefined, rotl3);

                        round(&a, &b, &c, &d);

                        b = @shuffle(u32, b, undefined, rotl3);
                        c = @shuffle(u32, c, undefined, rotl2);
                        d = @shuffle(u32, d, undefined, rotl1);
                }

                a +%= x;
                b +%= y;
                c +%= z;
                d +%= w;

                i = 0;
                while (i < 4) : (i += 1) {
                        buffer[i] = a[i];
                        buffer[4+i] = b[i];
                        buffer[8+i] = c[i];
                        buffer[12+i] = d[i];
                }
        }
};

// Non-vectorized chacha20 primitive (unused, kept for reference).
const Chacha20NativeEndian = struct {
        const Self = @This();
        const BLOCK_COUNT = 16;
        const U64_COUNT = 8;
        const ALIGNMENT = 16;

        state: [BLOCK_COUNT] u32,

        const HEADER align(ALIGNMENT) = "expand 32-byte k".*;
        const HEADER_SIZE = 16;
        const HEADER_COUNT = 4;
        const COUNTER0 = 12;
        const COUNTER1 = 13;

        fn init() Self {
                var self = Self { .state = undefined };
                @memcpy(@ptrCast([*] u8, &self.state), &HEADER, HEADER_SIZE);
                self.state[COUNTER0] = 0;
                return self;
        }

        fn deinit(_: *Self) void {
        }

        fn seed(self: *Self, entropy: *Entropy) !void {
                try entropy.get_entropy(mem.sliceAsBytes(self.state[HEADER_COUNT..]));
        }

        fn should_seed(self: Self) bool {
                return (self.state[COUNTER0] & 0x3fff == 0);
        }

        fn next(self: *Self) void {
                const overflow = @addWithOverflow(u32, self.state[COUNTER0], 1,
                        &self.state[COUNTER0]);
                self.state[COUNTER1] +%= @boolToInt(overflow);
        }

        fn quarter_round(a: *u32, b: *u32, c: *u32, d: *u32) void {
                a.* +%= b.*; d.* ^= a.*; d.* = math.rotl(u32, d.*, 16);
                c.* +%= d.*; b.* ^= c.*; b.* = math.rotl(u32, b.*, 12);
                a.* +%= b.*; d.* ^= a.*; d.* = math.rotl(u32, d.*, 8);
                c.* +%= d.*; b.* ^= c.*; b.* = math.rotl(u32, b.*, 7);
        }

        fn generate(self: Self, buffer: *[BLOCK_COUNT] u32) void {
                mem.copy(u32, buffer, &self.state);

                var i: usize = 0;
                while (i < 10) : (i += 1) {
                        quarter_round(&buffer[0], &buffer[4], &buffer[8], &buffer[12]);
                        quarter_round(&buffer[1], &buffer[5], &buffer[9], &buffer[13]);
                        quarter_round(&buffer[2], &buffer[6], &buffer[10], &buffer[14]);
                        quarter_round(&buffer[3], &buffer[7], &buffer[11], &buffer[15]);
                        quarter_round(&buffer[0], &buffer[5], &buffer[10], &buffer[15]);
                        quarter_round(&buffer[1], &buffer[6], &buffer[11], &buffer[12]);
                        quarter_round(&buffer[2], &buffer[7], &buffer[8], &buffer[13]);
                        quarter_round(&buffer[3], &buffer[4], &buffer[9], &buffer[14]);
                }

                i = 0;
                while (i < 16) : (i += 1) {
                        buffer[i] +%= self.state[i];
                }
        }
};

pub const Generator = struct {
        const Source = Chacha20NativeEndianVector;
        const RANDOM_COUNT = Source.U64_COUNT;

        source: Source,
        data: [RANDOM_COUNT] u64 align(Source.ALIGNMENT),
        entropy: Entropy,
        count: usize,
        first: u64,
        range: u64,
        excluded: u64,

        pub fn init(first: u64, last: u64) !Generator {
                const range = last -% first +% 1;

                var gen = Generator {
                        .source = Source.init(),
                        .data = undefined,
                        .entropy = try Entropy.init(),
                        .count = 0,
                        .first = first,
                        .range = range,
                        .excluded = undefined,
                };

                if (range == 0) {
                        gen.excluded = 0;
                }
                else {
                        // Detect the bias generated by a potential modular division with
                        // a range that is not a power of 2 by defining an exclusion
                        // range. If the random value falls in the excluded range, return
                        // failure to prohibit the bias. The remaining range will be a
                        // multiple of the user requested range, so any result will not be
                        // biased by the modular remainder operation.
                        //
                        // gen.excluded = (math.maxInt(64)+1) % range;
                        // gen.excluded = (math.maxInt(64)+1-range) % range;
                        // gen.excluded = (0-range) % range;
                        gen.excluded = (-%range) % range;
                }

                return gen;
        }

        pub fn deinit(self: *Generator) void {
                self.entropy.deinit();
                self.source.deinit();
        }

        fn fill(self: *Generator) !void {
                if (self.source.should_seed()) {
                        try self.source.seed(&self.entropy);
                }

                const p = @ptrCast(*[Source.BLOCK_COUNT] u32, &self.data);
                self.source.generate(p);
                self.source.next();
                self.count = RANDOM_COUNT;
        }

        fn get_random(self: *Generator) !u64 {
                if (self.count == 0)
                        try self.fill();

                self.count -= 1;
                return self.data[self.count];
        }

        pub fn randint(self: *Generator) !u64 {
                var i: usize = 0;
                // Try a few times to get an unbiased result (disallow the excluded range)
                while (i < 10) : (i += 1) {
                        const random = try self.get_random();
                        if (self.range == 0) return random;
                        if (random < self.excluded) continue;
                        return (self.first +% random%self.range);
                }
                return self.first +% try self.get_random()%self.range;
        }
};

const expect = std.testing.expect;
const eql = std.mem.eql;

fn test_chacha_init(comptime Type: type) !void {
        var chacha = Type.init();
        defer chacha.deinit();
        const bytes = mem.sliceAsBytes(chacha.state[0..Type.HEADER_COUNT]);
        try expect(eql(u8, bytes, &Type.HEADER));
        try expect(chacha.state[Type.COUNTER0] == 0);
}

const EntropyMock = struct {
        const GetEntropyFn = fn([]u8) void;
        real: sysdeps.Entropy,
        mock_fn: ?GetEntropyFn,

        fn init() !EntropyMock {
                var real = try sysdeps.Entropy.init();
                return EntropyMock { .mock_fn = null, .real = real };
        }

        fn deinit(self: *EntropyMock) void {
                self.real.deinit();
        }

        fn get_entropy(self: *EntropyMock, buffer: []u8) !void {
                if (self.mock_fn) |func| {
                        return func(buffer);
                }
                return self.real.get_entropy(buffer);
        }

        fn mock(self: *EntropyMock, func: ?GetEntropyFn) void {
                self.mock_fn = func;
        }

        fn entropy_all_ones(buffer: []u8) void {
                @memset(buffer.ptr, '1', buffer.len);
        }

        fn entropy_sequence(buffer: []u8) void {
                for (buffer) |*ch, i| {
                        ch.* = @intCast(u8, i);
                }
        }
};

fn test_chacha_seeding(comptime Type: type) !void {
        var chacha = Type.init();
        defer chacha.deinit();
        var entropy = try Entropy.init();
        defer entropy.deinit();
        entropy.mock(Entropy.entropy_all_ones);
        try chacha.seed(&entropy);
        const bytes = mem.sliceAsBytes(chacha.state[Type.HEADER_COUNT..]);
        try expect(eql(u8, bytes, "111111111111111111111111111111111111111111111111"));
        entropy.mock(Entropy.entropy_sequence);
        try chacha.seed(&entropy);
        for (bytes) |ch, i| {
                try expect(ch == i);
        }
}

fn test_chacha_header_integrity(comptime Type: type) !void {
        var chacha = Type.init();
        defer chacha.deinit();
        var entropy = try Entropy.init();
        defer entropy.deinit();
        var i: usize = 0;
        while (i < 100) : (i += 1) {
                try chacha.seed(&entropy);
        }
        const bytes = mem.sliceAsBytes(chacha.state[0..Type.HEADER_COUNT]);
        try expect(eql(u8, bytes, &Type.HEADER));
}

fn test_chacha_check_for_seeding(comptime Type: type) !void {
        var chacha = Type.init();
        defer chacha.deinit();
        try expect(chacha.should_seed() == true);
        chacha.state[Type.COUNTER0] = 0x3fffffff;
        try expect(chacha.should_seed() == false);
        chacha.state[Type.COUNTER0] = 0x80000000;
        try expect(chacha.should_seed() == true);
}

fn test_chacha_increment_counter(comptime Type: type) !void {
        var chacha = Type.init();
        defer chacha.deinit();
        chacha.state[Type.COUNTER1] = 10;
        try expect(chacha.state[Type.COUNTER0] == 0);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 1);
        try expect(chacha.state[Type.COUNTER1] == 10);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 2);
        try expect(chacha.state[Type.COUNTER1] == 10);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 3);
        try expect(chacha.state[Type.COUNTER1] == 10);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 4);
        try expect(chacha.state[Type.COUNTER1] == 10);
        chacha.state[Type.COUNTER0] = 3869551298;
        chacha.state[Type.COUNTER1] = 1421690919;
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 3869551299);
        try expect(chacha.state[Type.COUNTER1] == 1421690919);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 3869551300);
        try expect(chacha.state[Type.COUNTER1] == 1421690919);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 3869551301);
        try expect(chacha.state[Type.COUNTER1] == 1421690919);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 3869551302);
        try expect(chacha.state[Type.COUNTER1] == 1421690919);
        chacha.state[Type.COUNTER0] = 0xfffffffd;
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 0xfffffffe);
        try expect(chacha.state[Type.COUNTER1] == 1421690919);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 0xffffffff);
        try expect(chacha.state[Type.COUNTER1] == 1421690919);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 0);
        try expect(chacha.state[Type.COUNTER1] == 1421690920);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 1);
        try expect(chacha.state[Type.COUNTER1] == 1421690920);
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 2);
        try expect(chacha.state[Type.COUNTER1] == 1421690920);
        chacha.state[Type.COUNTER0] = 0xffffffff;
        chacha.state[Type.COUNTER1] = 0xffffffff;
        chacha.next();
        try expect(chacha.state[Type.COUNTER0] == 0);
        try expect(chacha.state[Type.COUNTER1] == 0);
}

fn test_chacha_test_vector_1(comptime Type: type) !void {
        var chacha = Type.init();
        defer chacha.deinit();
        chacha.state[0] = 16;
        chacha.state[1] = 32;
        chacha.state[2] = 48;
        chacha.state[3] = 64;
        chacha.state[4] = 80;
        chacha.state[5] = 96;
        chacha.state[6] = 112;
        chacha.state[7] = 128;
        chacha.state[8] = 144;
        chacha.state[9] = 160;
        chacha.state[10] = 176;
        chacha.state[11] = 192;
        chacha.state[12] = 208;
        chacha.state[13] = 224;
        chacha.state[14] = 240;
        chacha.state[15] = 1;
        var buffer: [16] u32 = undefined;
        chacha.generate(&buffer);
        try expect(buffer[0] == 0xa14250d1);
        try expect(buffer[1] == 0xe3bfa265);
        try expect(buffer[2] == 0xe08b84d5);
        try expect(buffer[3] == 0xc0fd2dde);
        try expect(buffer[4] == 0xd3997ccb);
        try expect(buffer[5] == 0x0b322984);
        try expect(buffer[6] == 0x89de5fd1);
        try expect(buffer[7] == 0x78a26774);
        try expect(buffer[8] == 0xe2653855);
        try expect(buffer[9] == 0x2d05d178);
        try expect(buffer[10] == 0xe0c5de94);
        try expect(buffer[11] == 0x6a6ceea5);
        try expect(buffer[12] == 0xc6ee532b);
        try expect(buffer[13] == 0xd98dd622);
        try expect(buffer[14] == 0xe65abfc5);
        try expect(buffer[15] == 0xcc0cd958);
}

fn test_chacha_test_identity(comptime Type: type) !void {
        var chacha = Type.init();
        defer chacha.deinit();
        for (chacha.state) |*v| v.* = 0;
        var buffer: [16] u32 = undefined;
        chacha.generate(&buffer);
        for (buffer) |v| {
                try expect(v == 0);
        }
}

fn test_chacha_test_draft_agl_tls_chacha20poly1305(comptime Type: type) !void {
        const INPUT = [_][48] u8 {
                ("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
                 "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
                 "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00").*,
                ("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
                 "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00" ++
                 "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00").*,
                ("\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
                 "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" ++
                 "\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00").*,
                ("\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10" ++
                 "\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f\x00\x00" ++
                 "\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07").*,
        };

        const OUTPUT = [INPUT.len][64] u8 {
                ("\x76\xb8\xe0\xad\xa0\xf1\x3d\x90\x40\x5d\x6a\xe5\x53\x86\xbd\x28\xbd" ++
                 "\xd2\x19\xb8\xa0\x8d\xed\x1a\xa8\x36\xef\xcc\x8b\x77\x0d\xc7\xda\x41" ++
                 "\x59\x7c\x51\x57\x48\x8d\x77\x24\xe0\x3f\xb8\xd8\x4a\x37\x6a\x43\xb8" ++
                 "\xf4\x15\x18\xa1\x1c\xc3\x87\xb6\x69\xb2\xee\x65\x86").*,
                ("\x45\x40\xf0\x5a\x9f\x1f\xb2\x96\xd7\x73\x6e\x7b\x20\x8e\x3c\x96\xeb" ++
                 "\x4f\xe1\x83\x46\x88\xd2\x60\x4f\x45\x09\x52\xed\x43\x2d\x41\xbb\xe2" ++
                 "\xa0\xb6\xea\x75\x66\xd2\xa5\xd1\xe7\xe2\x0d\x42\xaf\x2c\x53\xd7\x92" ++
                 "\xb1\xc4\x3f\xea\x81\x7e\x9a\xd2\x75\xae\x54\x69\x63").*,
                ("\xef\x3f\xdf\xd6\xc6\x15\x78\xfb\xf5\xcf\x35\xbd\x3d\xd3\x3b\x80\x09" ++
                 "\x63\x16\x34\xd2\x1e\x42\xac\x33\x96\x0b\xd1\x38\xe5\x0d\x32\x11\x1e" ++
                 "\x4c\xaf\x23\x7e\xe5\x3c\xa8\xad\x64\x26\x19\x4a\x88\x54\x5d\xdc\x49" ++
                 "\x7a\x0b\x46\x6e\x7d\x6b\xbd\xb0\x04\x1b\x2f\x58\x6b").*,
                ("\xf7\x98\xa1\x89\xf1\x95\xe6\x69\x82\x10\x5f\xfb\x64\x0b\xb7\x75\x7f" ++
                 "\x57\x9d\xa3\x16\x02\xfc\x93\xec\x01\xac\x56\xf8\x5a\xc3\xc1\x34\xa4" ++
                 "\x54\x7b\x73\x3b\x46\x41\x30\x42\xc9\x44\x00\x49\x17\x69\x05\xd3\xbe" ++
                 "\x59\xea\x1c\x53\xf1\x59\x16\x15\x5c\x2b\xe8\x24\x1a").*,
        };

        var chacha = Type.init();
        defer chacha.deinit();
        const bytes = mem.sliceAsBytes(chacha.state[Type.HEADER_COUNT..]);
        for (INPUT) |input, i| {
                @memcpy(bytes.ptr, &input, 48);
                for (chacha.state) |*v| {
                        v.* = mem.littleToNative(u32, v.*);
                }
                var buffer: [16] u32 = undefined;
                chacha.generate(&buffer);
                for (buffer) |*v| {
                        v.* = mem.nativeToLittle(u32, v.*);
                }
                try expect(eql(u8, &OUTPUT[i], mem.sliceAsBytes(buffer[0..])));
        }
}

test "Chacha20NativeEndianVector initialization" {
        try test_chacha_init(Chacha20NativeEndianVector);
}

test "Chacha20NativeEndian initialization" {
        try test_chacha_init(Chacha20NativeEndian);
}

test "Chacha20NativeEndianVector seeding" {
        try test_chacha_seeding(Chacha20NativeEndianVector);
}

test "Chacha20NativeEndian seeding" {
        try test_chacha_seeding(Chacha20NativeEndian);
}

test "Chacha20NativeEndianVector header integrity after seeding" {
        try test_chacha_header_integrity(Chacha20NativeEndianVector);
}

test "Chacha20NativeEndian header integrity after seeding" {
        try test_chacha_header_integrity(Chacha20NativeEndian);
}

test "Chacha20NativeEndianVector check for seeding" {
        try test_chacha_check_for_seeding(Chacha20NativeEndianVector);
}

test "Chacha20NativeEndian check for seeding" {
        try test_chacha_check_for_seeding(Chacha20NativeEndian);
}

test "Chacha20NativeEndianVector increment counter" {
        try test_chacha_increment_counter(Chacha20NativeEndianVector);
}

test "Chacha20NativeEndian increment counter" {
        try test_chacha_increment_counter(Chacha20NativeEndian);
}

test "Chacha20NativeEndianVector test vector 1" {
        try test_chacha_test_vector_1(Chacha20NativeEndianVector);
}

test "Chacha20NativeEndian test vector 1" {
        try test_chacha_test_vector_1(Chacha20NativeEndian);
}

test "Chacha20NativeEndianVector test identity" {
        try test_chacha_test_identity(Chacha20NativeEndianVector);
}

test "Chacha20NativeEndian test identity" {
        try test_chacha_test_identity(Chacha20NativeEndian);
}

test "Chacha20NativeEndianVector test vectors draft-agl-tls-chacha20poly1305-04" {
        try test_chacha_test_draft_agl_tls_chacha20poly1305(Chacha20NativeEndianVector);
}

test "Chacha20NativeEndian test vectors draft-agl-tls-chacha20poly1305-04" {
        try test_chacha_test_draft_agl_tls_chacha20poly1305(Chacha20NativeEndian);
}
