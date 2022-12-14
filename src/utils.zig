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
const nativeToBig = std.mem.nativeToBig;
const log2_int = std.math.log2_int;

pub const VERSION_STRING = "randomutils version 53.10.19 (GNU General Public License)\n";

pub const EXIT_SUCCESS = 0;
pub const EXIT_FAILURE = 1;

pub fn strerror(err: anyerror) []const u8 {
        // Replicate libc's strerror()
        return switch (err) {
                error.AccessDenied => "Operation not permitted",
                error.BrokenPipe => "Broken pipe",
                error.ConnectionResetByPeer => "Connection reset by peer",
                error.DeviceBusy => "Device or resource busy",
                error.DiskQuota => "Disk quota exceeded",
                error.FileBusy => "Text file busy",
                error.FileLocksNotSupported => "Operation not supported",
                error.FileNotFound => "No such file or directory",
                error.FileTooBig => "File too large",
                error.InputOutput => "Input/output error",
                error.IsDir => "Is a directory",
                error.NameTooLong => "File name too long",
                error.NoDevice => "No such device",
                error.NoSpaceLeft => "No space left on device",
                error.NotDir => "Not a directory",
                error.NotOpenForWriting => "Bad file descriptor",
                error.OutOfMemory => "Cannot allocate memory",
                error.PathAlreadyExists => "File exists",
                error.ProcessFdQuotaExceeded => "Too many open files",
                error.SymLinkLoop => "Too many levels of symbolic links",
                error.SystemFdQuotaExceeded => "Too many open files in system",
                error.SystemResources => "Cannot allocate system resources",
                error.Unseekable => "Illegal seek",
                error.WouldBlock => "Resource temporarily unavailable",

                // Custom errors
                error.EmptyFile => "File is empty",
                error.WordNotFound => "Word not found",
                error.RewindNeeded => "Rewind needed",
                else => "Unknown error",
        };
}

// Some fast and small number formatters for fun.

fn len_d(value: u64) usize {
        // A fast decimal number length calculator.
        const DIGITS = [65]u8 {
                19, 19, 19, 19, 18, 18, 18, 17, 17, 17, 16, 16, 16, 16,
                15, 15, 15, 14, 14, 14, 13, 13, 13, 13, 12, 12, 12, 11,
                11, 11, 10, 10, 10, 10, 9, 9, 9, 8, 8, 8, 7, 7, 7, 7,
                6, 6, 6, 5, 5, 5, 4, 4, 4, 4, 3, 3, 3, 2, 2, 2, 1, 1,
                1, 1, 1,
        };
        const CHANGE = [65]u64 {
                10000000000000000000, 10000000000000000000, 10000000000000000000,
                10000000000000000000, 1000000000000000000, 1000000000000000000,
                1000000000000000000, 100000000000000000, 100000000000000000,
                100000000000000000, 10000000000000000, 10000000000000000,
                10000000000000000, 10000000000000000, 1000000000000000, 1000000000000000,
                1000000000000000, 100000000000000, 100000000000000, 100000000000000,
                10000000000000, 10000000000000, 10000000000000, 10000000000000,
                1000000000000, 1000000000000, 1000000000000, 100000000000, 100000000000,
                100000000000, 10000000000, 10000000000, 10000000000, 10000000000,
                1000000000, 1000000000, 1000000000, 100000000, 100000000, 100000000,
                10000000, 10000000, 10000000, 10000000, 1000000, 1000000, 1000000,
                100000, 100000, 100000, 10000, 10000, 10000, 10000, 1000, 1000, 1000,
                100, 100, 100, 10, 10, 10, 10, 10,
        };

        const z = @clz(u64, value);
        var d = DIGITS[z];
        if (value >= CHANGE[z])
                d += 1;

        return @intCast(usize, d);
}

pub fn fmt_d(buffer: []u8, value: u64) usize {
        // A well-known fast decimal number formatter (2 digit LUT, with backwards
        // buffer filling).
        const DIGITS =
                "000102030405060708091011121314151617181920212223242526272829" ++
                "303132333435363738394041424344454647484950515253545556575859" ++
                "606162636465666768697071727374757677787980818283848586878889" ++
                "90919293949596979899";
        const length: usize = len_d(value);

        var v = value;
        var l = length;
        while (l > 1) : (l -= 2) {
                var r = @truncate(usize, v % 100);
                v /= 100;
                // No safety check here, slice must have the proper range.
                @memcpy(buffer[l-2..l].ptr, DIGITS[r*2..r*2+2].ptr, 2);
        }
        if (l == 1)
                buffer[0] = DIGITS[@truncate(usize, (v % 10)*2+1)];

        return length;
}

fn len_x(value: u64) usize {
        if (value == 0) return 1;
        return log2_int(u64, value)/4 + 1;
}

pub fn fmt_x(buffer: []u8, value: u64, upper: bool) usize {
        const DIGITS  = [2][16]u8{ "0123456789abcdef".*, "0123456789ABCDEF".* };
        const length = len_x(value);
        const u = @boolToInt(upper);

        var v = value;
        var l = length;
        while (l > 0) : (l -= 1) {
                var r = @truncate(usize, v % 16);
                v /= 16;
                buffer[l-1] = DIGITS[u][r];
        }

        return length;
}

pub fn fmt_bin(buffer: []u8, value: u64) usize {
        const big = nativeToBig(u64, value);
        // @memcpy supports 64-bit movbe instruction on x86_64 (writeIntSliceBig
        // doesn't seem to support it).
        @memcpy(buffer.ptr, @ptrCast([*] const align(8) u8, &big), 8);
        return 8;
}

pub fn fmt_base64url(buffer: []u8, value: u64) usize {
        const DIGITS =
                "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

        var i: usize = 0;
        var shift: u6 = 58;
        while (i < 10) : (i += 1) {
                buffer[i] = DIGITS[@truncate(usize, (value >> shift) & 0x3f)];
                shift -%= 6;
        }

        buffer[10] = DIGITS[@truncate(usize, (value << 2) & 0x3f)];

        return 11;
}

fn fmt_ascii85_word(buffer: []u8, value: u32) usize {
        if (value == 0) {
                buffer[0] = 'z';
                return 1;
        }

        var i: usize = 1;
        var w = value;
        while (i <= 5) : (i += 1) {
                const q: u8 = @intCast(u8, w%85);
                w /= 85;
                buffer[5-i] = q + '!';
        }

        return 5;
}

pub fn fmt_ascii85(buffer: []u8, value: u64) usize {
        const high = @intCast(u32, (value >> 32) & 0xffffffff);
        const low = @intCast(u32, value & 0xffffffff);

        var len = fmt_ascii85_word(buffer, high);
        len += fmt_ascii85_word(buffer[len..], low);

        return len;
}

const expect = std.testing.expect;
const eql = std.mem.eql;

const TEST_VALUES = [_]u64 {
        0, 1, 2, 9, 10, 15, 16, 31, 32, 99, 100, 127, 128, 511, 512, 999, 1000, 1023,
        1024, 8191, 8192, 9999, 10000, 16383, 16384, 65535, 65536, 99999, 100000, 100001,
        131071, 131072, 524287, 524288, 524289, 999999, 1000000, 1000001, 1048575,
        1048576, 1048577, 8388607, 8388608, 8388609, 9999999, 10000000, 10000001,
        16777215, 16777216, 16777217, 67108863, 67108864, 67108865, 99999999, 100000000,
        100000001, 134217727, 134217728, 134217729, 536870911, 536870912, 536870913,
        999999999, 1000000000, 1000000001, 1073741823, 1073741824, 1073741825,
        8589934591, 8589934592, 8589834593, 9999999999, 10000000000, 10000000001,
        17179869183, 17179869184, 17179869185, 68719476735, 68719476736, 68719476737,
        99999999999, 100000000000, 100000000001, 137438953471, 137438953472,
        137438953473, 549755813887, 549755813888, 549755813889, 999999999999,
        1000000000000, 1000000000001, 1099511627775, 1099511627776, 1099511627777,
        8796093022207, 8796093022208, 8796093022209, 9999999999999, 10000000000000,
        10000000000001, 17592186044415, 17592186044416, 17592186044417, 70368744177663,
        70368744177664, 70368744177665, 99999999999999, 100000000000000, 100000000000001,
        140737488355327, 140737488355328, 140737488355329, 562949953421311,
        562949953421312, 562949953421313, 999999999999999, 1000000000000000,
        1000000000000001, 1125899906842623, 1125899906842624, 1125899906842625,
        9007199254740991, 9007199254740992, 9007199254740993, 9999999999999999,
        10000000000000000, 10000000000000001, 18014398509481983, 18014398509481984,
        18014398509481985, 72057594037927935, 72057594037927936, 72057594037927937,
        99999999999999999, 100000000000000000, 100000000000000001, 144115188075855871,
        144115188075855872, 144115188075855873, 576460752303423487, 576460752303423488,
        576460752303423489, 999999999999999999, 1000000000000000000, 1000000000000000001,
        1152921504606846975, 1152921504606846976, 1152921504606846977,
        9223372036854775807, 9223372036854775808, 9223372036854775809,
        9999999999999999999, 10000000000000000000, 10000000000000000001,
        18446744073709551614, 18446744073709551615,
    };

test "Decimal number length" {
        const TEST_LENGTHS = [TEST_VALUES.len]usize {
                1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5,
                5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8,
                8, 8, 8, 8, 8, 8, 9, 9, 9, 9, 9, 9, 9, 9, 9, 10, 10, 10, 10, 10, 10, 10,
                10, 10, 11, 11, 11, 11, 11, 11, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12,
                12, 12, 13, 13, 13, 13, 13, 13, 13, 13, 13,  14, 14, 14, 14, 14, 14, 14,
                14, 14, 15, 15, 15, 15, 15, 15, 15, 15, 15, 16, 16, 16, 16, 16, 16, 16,
                16, 16, 17, 17, 17, 17, 17, 17, 17, 17, 17, 18, 18, 18, 18, 18, 18, 18,
                18, 18, 19, 19, 19, 19, 19, 19, 19, 19, 19, 20, 20, 20, 20,
        };

        for (TEST_VALUES) |v, i|
                try expect(len_d(v) == TEST_LENGTHS[i]);
}

test "Decimal number formatting" {
        const TEST_STRINGS = [_][]const u8 {
                "0", "1", "2", "9", "10", "15", "16", "31", "32", "99", "100", "127",
                "128", "511", "512", "999", "1000", "1023", "1024", "8191", "8192",
                "9999", "10000", "16383", "16384", "65535", "65536", "99999", "100000",
                "100001", "131071", "131072", "524287", "524288", "524289", "999999",
                "1000000", "1000001", "1048575", "1048576", "1048577", "8388607",
                "8388608", "8388609", "9999999", "10000000", "10000001", "16777215",
                "16777216", "16777217", "67108863", "67108864", "67108865", "99999999",
                "100000000", "100000001", "134217727", "134217728", "134217729",
                "536870911", "536870912", "536870913", "999999999", "1000000000",
                "1000000001", "1073741823", "1073741824", "1073741825", "8589934591",
                "8589934592", "8589834593", "9999999999", "10000000000", "10000000001",
                "17179869183", "17179869184", "17179869185", "68719476735",
                "68719476736", "68719476737", "99999999999", "100000000000",
                "100000000001", "137438953471", "137438953472", "137438953473",
                "549755813887", "549755813888", "549755813889", "999999999999",
                "1000000000000", "1000000000001", "1099511627775", "1099511627776",
                "1099511627777", "8796093022207", "8796093022208", "8796093022209",
                "9999999999999", "10000000000000", "10000000000001", "17592186044415",
                "17592186044416", "17592186044417", "70368744177663", "70368744177664",
                "70368744177665", "99999999999999", "100000000000000", "100000000000001",
                "140737488355327", "140737488355328", "140737488355329",
                "562949953421311", "562949953421312", "562949953421313",
                "999999999999999", "1000000000000000", "1000000000000001",
                "1125899906842623", "1125899906842624", "1125899906842625",
                "9007199254740991", "9007199254740992", "9007199254740993",
                "9999999999999999", "10000000000000000", "10000000000000001",
                "18014398509481983", "18014398509481984", "18014398509481985",
                "72057594037927935", "72057594037927936", "72057594037927937",
                "99999999999999999", "100000000000000000", "100000000000000001",
                "144115188075855871", "144115188075855872", "144115188075855873",
                "576460752303423487", "576460752303423488", "576460752303423489",
                "999999999999999999", "1000000000000000000", "1000000000000000001",
                "1152921504606846975", "1152921504606846976", "1152921504606846977",
                "9223372036854775807", "9223372036854775808", "9223372036854775809",
                "9999999999999999999", "10000000000000000000", "10000000000000000001",
                "18446744073709551614", "18446744073709551615",
            };

        var buff: [20]u8 = undefined;
        for (TEST_VALUES) |v, i| {
                const length = fmt_d(&buff, v);
                try expect(eql(u8, TEST_STRINGS[i], buff[0..length]));
        }
}

test "Hexadecimal number length" {
        const TEST_LENGTHS = [TEST_VALUES.len]usize {
                1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4,
                4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6,
                7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 8, 8, 8, 9, 9, 9, 9,
                9, 9, 9, 9, 9, 9, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
                10, 11, 11, 11, 11, 11, 11, 11, 11, 11, 12, 12, 12, 12, 12, 12, 12, 12,
                12, 12, 12, 13, 13, 13, 13, 13, 13, 13, 13, 13, 14, 14, 14, 14, 14, 14,
                14, 14, 14, 14, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
                15, 16, 16, 16, 16, 16, 16, 16, 16, 16, 16,
        };

        for (TEST_VALUES) |v, i|
                try expect(len_x(v) == TEST_LENGTHS[i]);
}

test "Lower case hexadecimal number formatting" {
        const TEST_STRINGS = [_][]const u8 {
                "0", "1", "2", "9", "a", "f", "10", "1f", "20", "63", "64", "7f", "80",
                "1ff", "200", "3e7", "3e8", "3ff", "400", "1fff", "2000", "270f", "2710",
                "3fff", "4000", "ffff", "10000", "1869f", "186a0", "186a1", "1ffff",
                "20000", "7ffff", "80000", "80001", "f423f", "f4240", "f4241", "fffff",
                "100000", "100001", "7fffff", "800000", "800001", "98967f", "989680",
                "989681", "ffffff", "1000000", "1000001", "3ffffff", "4000000",
                "4000001", "5f5e0ff", "5f5e100", "5f5e101", "7ffffff", "8000000",
                "8000001", "1fffffff", "20000000", "20000001", "3b9ac9ff", "3b9aca00",
                "3b9aca01", "3fffffff", "40000000", "40000001", "1ffffffff", "200000000",
                "1fffe7961", "2540be3ff", "2540be400", "2540be401", "3ffffffff",
                "400000000", "400000001", "fffffffff", "1000000000", "1000000001",
                "174876e7ff", "174876e800", "174876e801", "1fffffffff", "2000000000",
                "2000000001", "7fffffffff", "8000000000", "8000000001", "e8d4a50fff",
                "e8d4a51000", "e8d4a51001", "ffffffffff", "10000000000", "10000000001",
                "7ffffffffff", "80000000000", "80000000001", "9184e729fff",
                "9184e72a000", "9184e72a001", "fffffffffff", "100000000000",
                "100000000001", "3fffffffffff", "400000000000", "400000000001",
                "5af3107a3fff", "5af3107a4000", "5af3107a4001", "7fffffffffff",
                "800000000000", "800000000001", "1ffffffffffff", "2000000000000",
                "2000000000001", "38d7ea4c67fff", "38d7ea4c68000", "38d7ea4c68001",
                "3ffffffffffff", "4000000000000", "4000000000001", "1fffffffffffff",
                "20000000000000", "20000000000001", "2386f26fc0ffff", "2386f26fc10000",
                "2386f26fc10001", "3fffffffffffff", "40000000000000", "40000000000001",
                "ffffffffffffff", "100000000000000", "100000000000001",
                "16345785d89ffff", "16345785d8a0000", "16345785d8a0001",
                "1ffffffffffffff", "200000000000000", "200000000000001",
                "7ffffffffffffff", "800000000000000", "800000000000001",
                "de0b6b3a763ffff", "de0b6b3a7640000", "de0b6b3a7640001",
                "fffffffffffffff", "1000000000000000", "1000000000000001",
                "7fffffffffffffff", "8000000000000000", "8000000000000001",
                "8ac7230489e7ffff", "8ac7230489e80000", "8ac7230489e80001",
                "fffffffffffffffe", "ffffffffffffffff",
            };

        var buff: [16]u8 = undefined;
        for (TEST_VALUES) |v, i| {
                const length = fmt_x(&buff, v, false);
                try expect(eql(u8, TEST_STRINGS[i], buff[0..length]));
        }
}

test "Upper case hexadecimal number formatting" {
        const TEST_STRINGS = [_][]const u8 {
                "0", "1", "2", "9", "A", "F", "10", "1F", "20", "63", "64", "7F", "80",
                "1FF", "200", "3E7", "3E8", "3FF", "400", "1FFF", "2000", "270F", "2710",
                "3FFF", "4000", "FFFF", "10000", "1869F", "186A0", "186A1", "1FFFF",
                "20000", "7FFFF", "80000", "80001", "F423F", "F4240", "F4241", "FFFFF",
                "100000", "100001", "7FFFFF", "800000", "800001", "98967F", "989680",
                "989681", "FFFFFF", "1000000", "1000001", "3FFFFFF", "4000000",
                "4000001", "5F5E0FF", "5F5E100", "5F5E101", "7FFFFFF", "8000000",
                "8000001", "1FFFFFFF", "20000000", "20000001", "3B9AC9FF", "3B9ACA00",
                "3B9ACA01", "3FFFFFFF", "40000000", "40000001", "1FFFFFFFF", "200000000",
                "1FFFE7961", "2540BE3FF", "2540BE400", "2540BE401", "3FFFFFFFF",
                "400000000", "400000001", "FFFFFFFFF", "1000000000", "1000000001",
                "174876E7FF", "174876E800", "174876E801", "1FFFFFFFFF", "2000000000",
                "2000000001", "7FFFFFFFFF", "8000000000", "8000000001", "E8D4A50FFF",
                "E8D4A51000", "E8D4A51001", "FFFFFFFFFF", "10000000000", "10000000001",
                "7FFFFFFFFFF", "80000000000", "80000000001", "9184E729FFF",
                "9184E72A000", "9184E72A001", "FFFFFFFFFFF", "100000000000",
                "100000000001", "3FFFFFFFFFFF", "400000000000", "400000000001",
                "5AF3107A3FFF", "5AF3107A4000", "5AF3107A4001", "7FFFFFFFFFFF",
                "800000000000", "800000000001", "1FFFFFFFFFFFF", "2000000000000",
                "2000000000001", "38D7EA4C67FFF", "38D7EA4C68000", "38D7EA4C68001",
                "3FFFFFFFFFFFF", "4000000000000", "4000000000001", "1FFFFFFFFFFFFF",
                "20000000000000", "20000000000001", "2386F26FC0FFFF", "2386F26FC10000",
                "2386F26FC10001", "3FFFFFFFFFFFFF", "40000000000000", "40000000000001",
                "FFFFFFFFFFFFFF", "100000000000000", "100000000000001",
                "16345785D89FFFF", "16345785D8A0000", "16345785D8A0001",
                "1FFFFFFFFFFFFFF", "200000000000000", "200000000000001",
                "7FFFFFFFFFFFFFF", "800000000000000", "800000000000001",
                "DE0B6B3A763FFFF", "DE0B6B3A7640000", "DE0B6B3A7640001",
                "FFFFFFFFFFFFFFF", "1000000000000000", "1000000000000001",
                "7FFFFFFFFFFFFFFF", "8000000000000000", "8000000000000001",
                "8AC7230489E7FFFF", "8AC7230489E80000", "8AC7230489E80001",
                "FFFFFFFFFFFFFFFE", "FFFFFFFFFFFFFFFF",
            };

        var buff: [16]u8 = undefined;
        for (TEST_VALUES) |v, i| {
                const length = fmt_x(&buff, v, true);
                try expect(eql(u8, TEST_STRINGS[i], buff[0..length]));
        }
}

test "Binary number formatting" {
        const TEST_STRINGS = [_][8]u8 {
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 2, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 9, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 10, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 15, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 16, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 31, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 32, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 99, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 100, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 127, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 0, 128, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 1, 255, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 2, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 3, 231, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 3, 232, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 3, 255, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 4, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 31, 255, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 32, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 39, 15, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 39, 16, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 63, 255, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 64, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 0, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 0, 1, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 1, 134, 159, },
                [8]u8 { 0, 0, 0, 0, 0, 1, 134, 160, },
                [8]u8 { 0, 0, 0, 0, 0, 1, 134, 161, },
                [8]u8 { 0, 0, 0, 0, 0, 1, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 0, 2, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 7, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 0, 8, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 8, 0, 1, },
                [8]u8 { 0, 0, 0, 0, 0, 15, 66, 63, },
                [8]u8 { 0, 0, 0, 0, 0, 15, 66, 64, },
                [8]u8 { 0, 0, 0, 0, 0, 15, 66, 65, },
                [8]u8 { 0, 0, 0, 0, 0, 15, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 0, 16, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 16, 0, 1, },
                [8]u8 { 0, 0, 0, 0, 0, 127, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 0, 128, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 0, 128, 0, 1, },
                [8]u8 { 0, 0, 0, 0, 0, 152, 150, 127, },
                [8]u8 { 0, 0, 0, 0, 0, 152, 150, 128, },
                [8]u8 { 0, 0, 0, 0, 0, 152, 150, 129, },
                [8]u8 { 0, 0, 0, 0, 0, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 1, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 1, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 0, 3, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 4, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 4, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 0, 5, 245, 224, 255, },
                [8]u8 { 0, 0, 0, 0, 5, 245, 225, 0, },
                [8]u8 { 0, 0, 0, 0, 5, 245, 225, 1, },
                [8]u8 { 0, 0, 0, 0, 7, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 8, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 8, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 0, 31, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 32, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 32, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 0, 59, 154, 201, 255, },
                [8]u8 { 0, 0, 0, 0, 59, 154, 202, 0, },
                [8]u8 { 0, 0, 0, 0, 59, 154, 202, 1, },
                [8]u8 { 0, 0, 0, 0, 63, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 0, 64, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 0, 64, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 1, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 2, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 1, 255, 254, 121, 97, },
                [8]u8 { 0, 0, 0, 2, 84, 11, 227, 255, },
                [8]u8 { 0, 0, 0, 2, 84, 11, 228, 0, },
                [8]u8 { 0, 0, 0, 2, 84, 11, 228, 1, },
                [8]u8 { 0, 0, 0, 3, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 4, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 4, 0, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 15, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 16, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 16, 0, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 23, 72, 118, 231, 255, },
                [8]u8 { 0, 0, 0, 23, 72, 118, 232, 0, },
                [8]u8 { 0, 0, 0, 23, 72, 118, 232, 1, },
                [8]u8 { 0, 0, 0, 31, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 32, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 32, 0, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 127, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 0, 128, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 0, 128, 0, 0, 0, 1, },
                [8]u8 { 0, 0, 0, 232, 212, 165, 15, 255, },
                [8]u8 { 0, 0, 0, 232, 212, 165, 16, 0, },
                [8]u8 { 0, 0, 0, 232, 212, 165, 16, 1, },
                [8]u8 { 0, 0, 0, 255, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 1, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 1, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 0, 7, 255, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 8, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 8, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 0, 9, 24, 78, 114, 159, 255, },
                [8]u8 { 0, 0, 9, 24, 78, 114, 160, 0, },
                [8]u8 { 0, 0, 9, 24, 78, 114, 160, 1, },
                [8]u8 { 0, 0, 15, 255, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 16, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 16, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 0, 63, 255, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 64, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 64, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 0, 90, 243, 16, 122, 63, 255, },
                [8]u8 { 0, 0, 90, 243, 16, 122, 64, 0, },
                [8]u8 { 0, 0, 90, 243, 16, 122, 64, 1, },
                [8]u8 { 0, 0, 127, 255, 255, 255, 255, 255, },
                [8]u8 { 0, 0, 128, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 0, 128, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 1, 255, 255, 255, 255, 255, 255, },
                [8]u8 { 0, 2, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 2, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 3, 141, 126, 164, 198, 127, 255, },
                [8]u8 { 0, 3, 141, 126, 164, 198, 128, 0, },
                [8]u8 { 0, 3, 141, 126, 164, 198, 128, 1, },
                [8]u8 { 0, 3, 255, 255, 255, 255, 255, 255, },
                [8]u8 { 0, 4, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 4, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 31, 255, 255, 255, 255, 255, 255, },
                [8]u8 { 0, 32, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 32, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 35, 134, 242, 111, 192, 255, 255, },
                [8]u8 { 0, 35, 134, 242, 111, 193, 0, 0, },
                [8]u8 { 0, 35, 134, 242, 111, 193, 0, 1, },
                [8]u8 { 0, 63, 255, 255, 255, 255, 255, 255, },
                [8]u8 { 0, 64, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 0, 64, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 0, 255, 255, 255, 255, 255, 255, 255, },
                [8]u8 { 1, 0, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 1, 0, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 1, 99, 69, 120, 93, 137, 255, 255, },
                [8]u8 { 1, 99, 69, 120, 93, 138, 0, 0, },
                [8]u8 { 1, 99, 69, 120, 93, 138, 0, 1, },
                [8]u8 { 1, 255, 255, 255, 255, 255, 255, 255, },
                [8]u8 { 2, 0, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 2, 0, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 7, 255, 255, 255, 255, 255, 255, 255, },
                [8]u8 { 8, 0, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 8, 0, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 13, 224, 182, 179, 167, 99, 255, 255, },
                [8]u8 { 13, 224, 182, 179, 167, 100, 0, 0, },
                [8]u8 { 13, 224, 182, 179, 167, 100, 0, 1, },
                [8]u8 { 15, 255, 255, 255, 255, 255, 255, 255, },
                [8]u8 { 16, 0, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 16, 0, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 127, 255, 255, 255, 255, 255, 255, 255, },
                [8]u8 { 128, 0, 0, 0, 0, 0, 0, 0, },
                [8]u8 { 128, 0, 0, 0, 0, 0, 0, 1, },
                [8]u8 { 138, 199, 35, 4, 137, 231, 255, 255, },
                [8]u8 { 138, 199, 35, 4, 137, 232, 0, 0, },
                [8]u8 { 138, 199, 35, 4, 137, 232, 0, 1, },
                [8]u8 { 255, 255, 255, 255, 255, 255, 255, 254, },
                [8]u8 { 255, 255, 255, 255, 255, 255, 255, 255, },
            };

        var buff: [8]u8 = undefined;
        for (TEST_VALUES) |v, i| {
                const length = fmt_bin(&buff, v);
                try expect(eql(u8, &TEST_STRINGS[i], buff[0..length]));
        }
}

test "Base64 number formatting" {
        const TEST_STRINGS = [_][]const u8 {
                "AAAAAAAAAAA", "AAAAAAAAAAE", "AAAAAAAAAAI", "AAAAAAAAAAk",
                "AAAAAAAAAAo", "AAAAAAAAAA8", "AAAAAAAAABA", "AAAAAAAAAB8",
                "AAAAAAAAACA", "AAAAAAAAAGM", "AAAAAAAAAGQ", "AAAAAAAAAH8",
                "AAAAAAAAAIA", "AAAAAAAAAf8", "AAAAAAAAAgA", "AAAAAAAAA-c",
                "AAAAAAAAA-g", "AAAAAAAAA_8", "AAAAAAAABAA", "AAAAAAAAH_8",
                "AAAAAAAAIAA", "AAAAAAAAJw8", "AAAAAAAAJxA", "AAAAAAAAP_8",
                "AAAAAAAAQAA", "AAAAAAAA__8", "AAAAAAABAAA", "AAAAAAABhp8",
                "AAAAAAABhqA", "AAAAAAABhqE", "AAAAAAAB__8", "AAAAAAACAAA",
                "AAAAAAAH__8", "AAAAAAAIAAA", "AAAAAAAIAAE", "AAAAAAAPQj8",
                "AAAAAAAPQkA", "AAAAAAAPQkE", "AAAAAAAP__8", "AAAAAAAQAAA",
                "AAAAAAAQAAE", "AAAAAAB___8", "AAAAAACAAAA", "AAAAAACAAAE",
                "AAAAAACYln8", "AAAAAACYloA", "AAAAAACYloE", "AAAAAAD___8",
                "AAAAAAEAAAA", "AAAAAAEAAAE", "AAAAAAP___8", "AAAAAAQAAAA",
                "AAAAAAQAAAE", "AAAAAAX14P8", "AAAAAAX14QA", "AAAAAAX14QE",
                "AAAAAAf___8", "AAAAAAgAAAA", "AAAAAAgAAAE", "AAAAAB____8",
                "AAAAACAAAAA", "AAAAACAAAAE", "AAAAADuayf8", "AAAAADuaygA",
                "AAAAADuaygE", "AAAAAD____8", "AAAAAEAAAAA", "AAAAAEAAAAE",
                "AAAAAf____8", "AAAAAgAAAAA", "AAAAAf_-eWE", "AAAAAlQL4_8",
                "AAAAAlQL5AA", "AAAAAlQL5AE", "AAAAA_____8", "AAAABAAAAAA",
                "AAAABAAAAAE", "AAAAD_____8", "AAAAEAAAAAA", "AAAAEAAAAAE",
                "AAAAF0h25_8", "AAAAF0h26AA", "AAAAF0h26AE", "AAAAH_____8",
                "AAAAIAAAAAA", "AAAAIAAAAAE", "AAAAf_____8", "AAAAgAAAAAA",
                "AAAAgAAAAAE", "AAAA6NSlD_8", "AAAA6NSlEAA", "AAAA6NSlEAE",
                "AAAA______8", "AAABAAAAAAA", "AAABAAAAAAE", "AAAH______8",
                "AAAIAAAAAAA", "AAAIAAAAAAE", "AAAJGE5yn_8", "AAAJGE5yoAA",
                "AAAJGE5yoAE", "AAAP______8", "AAAQAAAAAAA", "AAAQAAAAAAE",
                "AAA_______8", "AABAAAAAAAA", "AABAAAAAAAE", "AABa8xB6P_8",
                "AABa8xB6QAA", "AABa8xB6QAE", "AAB_______8", "AACAAAAAAAA",
                "AACAAAAAAAE", "AAH_______8", "AAIAAAAAAAA", "AAIAAAAAAAE",
                "AAONfqTGf_8", "AAONfqTGgAA", "AAONfqTGgAE", "AAP_______8",
                "AAQAAAAAAAA", "AAQAAAAAAAE", "AB________8", "ACAAAAAAAAA",
                "ACAAAAAAAAE", "ACOG8m_A__8", "ACOG8m_BAAA", "ACOG8m_BAAE",
                "AD________8", "AEAAAAAAAAA", "AEAAAAAAAAE", "AP________8",
                "AQAAAAAAAAA", "AQAAAAAAAAE", "AWNFeF2J__8", "AWNFeF2KAAA",
                "AWNFeF2KAAE", "Af________8", "AgAAAAAAAAA", "AgAAAAAAAAE",
                "B_________8", "CAAAAAAAAAA", "CAAAAAAAAAE", "DeC2s6dj__8",
                "DeC2s6dkAAA", "DeC2s6dkAAE", "D_________8", "EAAAAAAAAAA",
                "EAAAAAAAAAE", "f_________8", "gAAAAAAAAAA", "gAAAAAAAAAE",
                "iscjBInn__8", "iscjBInoAAA", "iscjBInoAAE", "__________4",
                "__________8",
            };

        var buff: [11]u8 = undefined;
        for (TEST_VALUES) |v, i| {
                const length = fmt_base64url(&buff, v);
                try expect(eql(u8, TEST_STRINGS[i], buff[0..length]));
        }
}

test "Ascii85 number formatting" {
        const TEST_STRINGS = [_][]const u8 {
                "zz", "z!!!!\"", "z!!!!#", "z!!!!*", "z!!!!+", "z!!!!0", "z!!!!1",
                "z!!!!@", "z!!!!A", "z!!!\"/", "z!!!\"0", "z!!!\"K", "z!!!\"L",
                "z!!!'\"", "z!!!'#", "z!!!,a", "z!!!,b", "z!!!-$", "z!!!-%", "z!!\",@",
                "z!!\",A", "z!!\"AW", "z!!\"AX", "z!!#7`", "z!!#7a", "z!!*'!", "z!!*'\"",
                "z!!.hH", "z!!.hI", "z!!.hJ", "z!!3-\"", "z!!3-#", "z!!iQ(", "z!!iQ)",
                "z!!iQ*", "z!\"VC\\", "z!\"VC]", "z!\"VC^", "z!\"],0", "z!\"],1",
                "z!\"],2", "z!.Y%K", "z!.Y%L", "z!.Y%M", "z!19(%", "z!19(&", "z!19('",
                "z!<<*!", "z!<<*\"", "z!<<*#", "z\"98E$", "z\"98E%", "z\"98E&",
                "z\"nggR", "z\"nggS", "z\"nggT", "z#QOi(", "z#QOi)", "z#QOi*", "z+92B@",
                "z+92BA", "z+92BB", "z4.=:k", "z4.=:l", "z4.=:m", "z5QCc`", "z5QCca",
                "z5QCcb", "!!!!\"s8W-!", "!!!!#z", "!!!!\"s8I:P", "!!!!#<\"%ad",
                "!!!!#<\"%ae", "!!!!#<\"%af", "!!!!$s8W-!", "!!!!%z", "!!!!%!!!!\"",
                "!!!!0s8W-!", "!!!!1z", "!!!!1!!!!\"", "!!!!889X1r", "!!!!889X1s",
                "!!!!889X1t", "!!!!@s8W-!", "!!!!Az", "!!!!A!!!!\"", "!!!\"Ks8W-!",
                "!!!\"Lz", "!!!\"L!!!!\"", "!!!#_e>3]U", "!!!#_e>3]V", "!!!#_e>3]W",
                "!!!$!s8W-!", "!!!$\"z", "!!!$\"!!!!\"", "!!!9(s8W-!", "!!!9)z",
                "!!!9)!!!!\"", "!!!<B:3*!,", "!!!<B:3*!-", "!!!<B:3*!.", "!!!Q0s8W-!",
                "!!!Q1z", "!!!Q1!!!!\"", "!!#7`s8W-!", "!!#7az", "!!#7a!!!!\"",
                "!!$3o&:-S@", "!!$3o&:-SA", "!!$3o&:-SB", "!!%NKs8W-!", "!!%NLz",
                "!!%NL!!!!\"", "!!3-\"s8W-!", "!!3-#z", "!!3-#!!!!\"", "!!A40UrIoa",
                "!!A40UrIob", "!!A40UrIoc", "!!E9$s8W-!", "!!E9%z", "!!E9%!!!!\"",
                "!$D7@s8W-!", "!$D7Az", "!$D7A!!!!\"", "!$d6hDnuDQ", "!$d6hDnuDR",
                "!$d6hDnuDS", "!'gM`s8W-!", "!'gMaz", "!'gMa!!!!\"", "!<<*!s8W-!",
                "!<<*\"z", "!<<*\"!!!!\"", "!FnQC?&AU]", "!FnQC?&AU^", "!FnQC?&AU_",
                "!WW3\"s8W-!", "!WW3#z", "!WW3#!!!!\"", "#QOi(s8W-!", "#QOi)z",
                "#QOi)!!!!\"", "%H+\\$Vdoc,", "%H+\\$Vdoc-", "%H+\\$Vdoc.",
                "&-)\\0s8W-!", "&-)\\1z", "&-)\\1!!!!\"", "J,fQKs8W-!", "J,fQLz",
                "J,fQL!!!!\"", "MT6qEM<Fp=", "MT6qEM<Fp>", "MT6qEM<Fp?", "s8W-!s8W,u",
                "s8W-!s8W-!",
            };

        var buff: [10]u8 = undefined;
        for (TEST_VALUES) |v, i| {
                const length = fmt_ascii85(&buff, v);
                try expect(eql(u8, TEST_STRINGS[i], buff[0..length]));
        }
}
