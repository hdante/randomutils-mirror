# randomutils

<figure align="center">
 <img src="/meme.jpg" width="50%">
</figure>

Welcome to the **randomutils** source code repository. The project is a set of
tools for generating 64-bit random numbers and is focused on allowing easy, fast
and secure random number generation in shell scripts.

Basic usage is trivial:

```
$ random
17238208024543540576
```

## Features
- Random number generation is done with a [cryptographically secure
  pseudo-random number generator][1] (CSPRNG), seeded by the operating system
  supplied entropy source. The seed is unpredictable and randomly refreshed.
- The tools may generate multiple numbers from a specified interval and they
  attempt to remove any bias when generating numbers from ranges that are not a
  power of 2.
- Multiple output formats are available for different uses: decimal numbers,
  hexadecimal, base64url encoded, ascii85 and binary.
- Care was taken to ensure that the programs are small and fast, so that they
  can be used multiple times within scripts, and available in very small
  embedded systems:
  - The `random` binary is statically linked (not depending on any shared
    library) and when compiled for linux with speed optimizations enabled and
    debug information stripped out, has only 17 KiB, uses a fixed amount of
    memory of less than 48 KiB, without dynamic memory allocations (including
    code, data and stack).
  - The code-base contains some optimized code to allow generating a large
    amount of random numbers very fast.  It's able to generate and print 25
    million decimal 64-bit random numbers per second on an old Intel Haswell
    laptop, or one 64-bit random number every 40 nanoseconds (so that, in case
    something really random happens to you and you find yourself in need of 25
    million random numbers, you'll have them in 1 second).
  - On a more pragmatic side, when generating 1 random number per execution, it
    can be executed around 2800 times per second, most of the time being spent
    on the shell interpreter and program execution (the `manyrandom.sh` script
    in the [examples directory](examples/) can be used for this measurement).
- The code for the cryptographic primitive used is software-based, not depending
  on accellerated hardware instructions (except that it supports vector
  instructions), so it's trivially portable. Currently, **randomutils** uses the
  20-round [Chacha20 cipher][2] (the same cipher used by OpenBSD
  [arc4random][3]).
- There are tools for generating a set of independent numbers (`random`) and a
  set of numbers without repetition (`lottery`).

## List of utilities
- `random`: Generate 64-bit random numbers.
- `lottery`: Generate random numbers without repetition.
- `roll`: Generate random numbers using [RPG dice notation][8].
- `mempassword`: Generate hard to guess, easy to remember passwords.

## Supported platforms
**randomutils** is cross-platform and should be easily portable to Unix-like
systems, as long as they provide an entropy source, such as the [`urandom`
device][9].  It has been tested in the following environments:

- Linux, amd64
- Linux, arm (armv6 and armv7)
- Linux, mips (mips32)
- Linux, riscv64 (qemu rv64gc, emulated)
- macOS, amd64
- Windows, amd64

## Build requirements
- [Zig][4] compiler (tested with version 0.9.1)
- [AsciiDoc][5] (optional, required for building manual pages)

## Build and install instructions
```
$ zig build
$ zig build test
$ zig build manpages
$ sudo zig build -p /usr/local
$ sudo zig build -p /usr/local manpages
```

Optionally, pass options when calling the build command:
```
$ zig build -Drelease-small -Dstrip    # optimize for size, strip debug
$ sudo zig build -p /usr/local -Drelease-small -Dstrip
```

## Usage
Basic usage:

```
$ random
17238208024543540576
```

The distribution is uniform over all range. To generate multiple random numbers
and with different ranges, pass the count, first and last parameters:

```
$ random 3   # generate 3 numbers
16857467820784418359
7646074587060241103
13522815382703413120
$ random 3 1000 1100 # 3 numbers, starting from 1000, up to 1100
1015
1014
1100
```

When generating numbers with limited range, `random` will attempt to remove all
biasing that typically appears when the range is not a power of 2.

Different output formats may be used by passing command-line options:

```
$ random -X 2   # upper case hexadecimal
5F329100EA7D807A
D9FE99AACDE28EEB
$ random -s -x 10 0x400 0x500 # lower case hexadecimal, single line
486 4b0 477 4cf 4a6 464 432 43e 43d 4f5
$ random -6     # base64url encoded
Ja6iZYw1zTg
$ random -8 2   # ascii85 encoded
rO5;3VWI?W
;?9Rc5t>)^
```

The random numbers may be also output in binary format and passed to other
programs that process binary input. Here's an example of piping the binary
output to the [od(1)][6] program:

```
$ random 4 55000 56000 -b | od --endian=big -t u8
0000000                55090                55674
0000020                55355                55097
0000040
```

When generating multiple numbers, they're generated independently, so they may
arbitrarily repeat. To generate numbers without repetition, use the `lottery`
program instead:

```
$ lottery 6 1 60    # generate 6 numbers from 1 to 60, no repetition
46 20 21 13 44 32
```

The `roll` program may also be used to generate random numbers and accepts
parameters in common RPG dice notation:

```
$ roll 3d6    # generate 3 numbers from 1 to 6
4 1 5
```

The `mempassword` program is used to generate random passwords. A text
dictionary must be available (by default it reads /usr/share/dict/words):

```
$ mempassword
z$#F:-expressway,felicities,folksinger,sedimentation's
Kd6_:-browner,enrichment's,dog,factorial
5D'D:-lasted,butlers,barrios,refuting
(&P.:-secularists,delinquency's,displacement's,reconsigning
'7<x:-worthy,confidences,railroading's,fizz's
```

## Cryptanalysis
The code was not reviewed by a cryptanalyst.

It's known that the performance characteristics of the programs change with
the requested ranges and options.

## License
The software is released under the [GNU General Public License][7]. This is free
software: you are free to change and redistribute it. There is NO WARRANTY, to
the extent permitted by law.

[1]: https://en.wikipedia.org/wiki/Cryptographically_secure_pseudorandom_number_generator
[2]: https://cr.yp.to/chacha.html
[3]: https://man.openbsd.org/arc4random.3
[4]: https://ziglang.org/
[5]: https://asciidoc.org/
[6]: https://www.gnu.org/software/coreutils/manual/html_node/od-invocation.html
[7]: https://www.gnu.org/licenses/gpl-3.0.en.html
[8]: https://en.wikipedia.org/wiki/Dice_notation
[9]: https://en.wikipedia.org/wiki//dev/random
