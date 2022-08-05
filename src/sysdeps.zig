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
const Allocator = std.mem.Allocator;
const ArgIterator = std.process.ArgIterator;
const argsWithAllocator = std.process.argsWithAllocator;
const os = std.os;

pub const ArgvIterator = struct {
        inner: ArgIterator,
        allocator: Allocator,

        pub fn init(allocator: Allocator) !ArgvIterator {
                return ArgvIterator {
                        .inner = try argsWithAllocator(allocator),
                        .allocator = allocator,
                };
        }

        pub fn deinit(self: *ArgvIterator) void {
                self.inner.deinit();
        }

        pub fn next(self: *ArgvIterator) ?(anyerror![:0]const u8) {
                // Some effort is necessary here to avoid unnecessary dynamic allocations
                // and to work around API changes of the Zig standard library.
                if (@typeInfo(@TypeOf(ArgIterator.next)).Fn.args.len == 1) {
                        // Zig >= 0.10
                        return self.inner.next();
                }
                if (builtin.os.tag != .wasi and builtin.os.tag != .windows) {
                        // Zig < 0.10 and POSIX OS
                        return self.inner.nextPosix() orelse null;
                }
                return self.inner.next(self.allocator);
        }
};

extern "c" fn getentropy(buffer: [*]u8, length: usize) c_int;

pub const Entropy = struct {
        fd: os.fd_t,

        const USE_FILE = switch (builtin.os.tag) {
                .windows, .linux, .freebsd, .netbsd, .openbsd, .macos, .ios, .tvos,
                .watchos, .wasi => false,
                else => true,
        };

        const USE_GETENTROPY = switch(builtin.os.tag) {
                .netbsd, .openbsd, .macos => true,
                else => false,
        };

        fn init_file(self: *Entropy) !void {
                self.fd = try os.openZ("/dev/urandom", os.O.RDONLY | os.O.CLOEXEC, 0);
        }

        fn deinit_file(self: *Entropy) void {
                os.close(self.fd);
        }

        pub fn init() !Entropy {
                var self: Entropy = undefined;
                // std.os.getrandom() keeps opening and closing /dev/urandom on some
                // systems. We can avoid that by opening it and holding a handle to it.
                if (USE_FILE)
                        try self.init_file();

                return self;
        }

        pub fn deinit(self: *Entropy) void {
                if (USE_FILE)
                        self.deinit_file();
        }

        pub fn get_entropy(self: *Entropy, buffer: []u8) !void {
                if (buffer.len >= 256) unreachable;

                // std.os.getrandom() does not directly call the OS for entropy in some
                // systems, so use a custom implementation in those systems, so that
                // we get as much entropy as possible.
                if (USE_GETENTROPY) {
                        if (getentropy(buffer.ptr, buffer.len) < 0) unreachable;
                }
                else if (USE_FILE) {
                        const r = try os.read(self.fd, buffer);
                        if (r < buffer.len) unreachable;
                }
                else {
                        try os.getrandom(buffer);
                }
        }
};
