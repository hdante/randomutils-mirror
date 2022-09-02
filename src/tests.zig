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

test {
        _ = @import("generator.zig");
        _ = @import("lottery.zig");
        _ = @import("mempassword.zig");
        _ = @import("random.zig");
        _ = @import("sysdeps.zig");
        _ = @import("utils.zig");
}
