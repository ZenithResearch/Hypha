# Third-party notices

Hypha is licensed under GNU AGPL v3 or later. The notices below apply to third-party components distributed with the repository and packaged application; they do not change Hypha’s own license. Package-specific license and copyright text extracted from the exact dependency source files is preserved in `THIRD_PARTY_LICENSES.html`.

## Matrix Rust SDK binary

- Component: Matrix Rust SDK FFI for macOS arm64, iOS arm64, and Apple Silicon iOS Simulator arm64
- Upstream: https://github.com/matrix-org/matrix-rust-sdk
- Zenith fork: https://github.com/bananawalnut/matrix-rust-sdk
- Exact source commit: https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5
- Reviewed post-login QR source diff SHA-256: `16ef3f5f722a0f87b07b9de44c1c749d9d927a1223190871a8231e20ca176208`
- Artifact checksum: `bbb53ca9440b5ae11a25adf650cd7ce0fe134ee7c63dcb2da36dda8cf47716f0`
- Matrix Rust SDK code and fork modifications: Apache-2.0

The fork modifications and artifact build/verification boundary are documented in `Vendor/MatrixRustSDK/PROVENANCE.md`. The binary incorporates dependencies under the license families and attributions listed below and in `THIRD_PARTY_LICENSES.html`. No upstream `NOTICE` file was present at the exact source commit.

## Resolved Rust package notice inventory

This conservative notice inventory is the exact 507-package set emitted by cargo-about 0.9.1 from the locked `matrix-sdk-ffi` manifest for `aarch64-apple-darwin`. It intentionally includes every package cargo-about resolved for notice generation; build-time or otherwise non-linked packages may therefore be over-included rather than omitted. The canonical machine-readable source is `Vendor/MatrixRustSDK/license-inventory.json`, and the verifier requires exact field-for-field equality with this table.

Raw Cargo license fields are preserved and normalized to validated SPDX expressions. Registry packages link to immutable versioned source archives; Git packages and Matrix workspace packages link to exact commits.

`THIRD_PARTY_LICENSES.html` preserves the exact dependency-source license files discovered by cargo-about. When upstream source itself contains an unfilled license template field, that text remains verbatim; package metadata attribution is retained alongside it rather than inventing a copyright holder or year.

Canonical license and exception texts included by this repository:
- [`0BSD`](LICENSES/0BSD.txt)
- [`Apache-2.0`](LICENSES/Apache-2.0.txt)
- [`BSD-2-Clause`](LICENSES/BSD-2-Clause.txt)
- [`BSD-3-Clause`](LICENSES/BSD-3-Clause.txt)
- [`BSL-1.0`](LICENSES/BSL-1.0.txt)
- [`CC0-1.0`](LICENSES/CC0-1.0.txt)
- [`ISC`](LICENSES/ISC.txt)
- [`LLVM-exception`](LICENSES/LLVM-exception.txt)
- [`MIT`](LICENSES/MIT.txt)
- [`MIT-0`](LICENSES/MIT-0.txt)
- [`MPL-2.0`](LICENSES/MPL-2.0.txt)
- [`Unicode-3.0`](LICENSES/Unicode-3.0.txt)
- [`Unlicense`](LICENSES/Unlicense.txt)
- [`Zlib`](LICENSES/Zlib.txt)
- [`zlib-acknowledgement`](LICENSES/zlib-acknowledgement.txt)

| Package | Version | Raw Cargo license | Normalized SPDX | Package metadata attribution | Immutable source |
|---|---:|---|---|---|---|
| `addr2line` | `0.25.1` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/addr2line/0.25.1/download) |
| `adler2` | `2.0.1` | `0BSD OR MIT OR Apache-2.0` | `0BSD OR MIT OR Apache-2.0` | Jonas Schievink <jonasschievink@gmail.com>; oyvindln <oyvindln@users.noreply.github.com> | [source](https://crates.io/api/v1/crates/adler2/2.0.1/download) |
| `aead` | `0.5.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/aead/0.5.2/download) |
| `aes` | `0.8.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/aes/0.8.4/download) |
| `aho-corasick` | `1.1.3` | `Unlicense OR MIT` | `Unlicense OR MIT` | Andrew Gallant <jamslam@gmail.com> | [source](https://crates.io/api/v1/crates/aho-corasick/1.1.3/download) |
| `allocator-api2` | `0.2.18` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Zakarum <zaq.dev@icloud.com> | [source](https://crates.io/api/v1/crates/allocator-api2/0.2.18/download) |
| `anyhow` | `1.0.103` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/anyhow/1.0.103/download) |
| `anymap2` | `0.13.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Chris Morgan <me@chrismorgan.info>; Azriel Hoh <azriel91@gmail.com> | [source](https://crates.io/api/v1/crates/anymap2/0.13.0/download) |
| `aquamarine` | `0.6.0` | `MIT` | `MIT` | Mike Lubinets <git@mkl.dev>; Frank Rehberger <frehberg@gmail.com> | [source](https://crates.io/api/v1/crates/aquamarine/0.6.0/download) |
| `arc-swap` | `1.7.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Michal 'vorner' Vaner <vorner@vorner.cz> | [source](https://crates.io/api/v1/crates/arc-swap/1.7.1/download) |
| `archery` | `1.2.1` | `MPL-2.0` | `MPL-2.0` | Diogo Sousa <diogogsousa@gmail.com> | [source](https://crates.io/api/v1/crates/archery/1.2.1/download) |
| `arrayref` | `0.3.8` | `BSD-2-Clause` | `BSD-2-Clause` | David Roundy <roundyd@physics.oregonstate.edu> | [source](https://crates.io/api/v1/crates/arrayref/0.3.8/download) |
| `arrayvec` | `0.7.6` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | bluss | [source](https://crates.io/api/v1/crates/arrayvec/0.7.6/download) |
| `as_variant` | `1.3.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/as_variant/1.3.0/download) |
| `askama` | `0.14.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/askama/0.14.0/download) |
| `askama_derive` | `0.14.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/askama_derive/0.14.0/download) |
| `askama_parser` | `0.14.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/askama_parser/0.14.0/download) |
| `asn1-rs` | `0.7.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Pierre Chifflier <chifflier@wzdftpd.net> | [source](https://crates.io/api/v1/crates/asn1-rs/0.7.2/download) |
| `asn1-rs-derive` | `0.6.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Pierre Chifflier <chifflier@wzdftpd.net> | [source](https://crates.io/api/v1/crates/asn1-rs-derive/0.6.0/download) |
| `asn1-rs-impl` | `0.2.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Pierre Chifflier <chifflier@wzdftpd.net> | [source](https://crates.io/api/v1/crates/asn1-rs-impl/0.2.0/download) |
| `assert-json-diff` | `2.0.2` | `MIT` | `MIT` | David Pedersen <david.pdrsn@gmail.com> | [source](https://crates.io/api/v1/crates/assert-json-diff/2.0.2/download) |
| `assert_matches` | `1.5.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Murarth <murarth@gmail.com> | [source](https://crates.io/api/v1/crates/assert_matches/1.5.0/download) |
| `assert_matches2` | `0.1.2` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/assert_matches2/0.1.2/download) |
| `assign` | `1.1.1` | `MIT` | `MIT` | Alan Darmasaputra <kelerchian@gmail.com>; Jonas Platte <jplatte@posteo.de> | [source](https://crates.io/api/v1/crates/assign/1.1.1/download) |
| `async-channel` | `2.5.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Stjepan Glavina <stjepang@gmail.com> | [source](https://crates.io/api/v1/crates/async-channel/2.5.0/download) |
| `async-compat` | `0.2.5` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Stjepan Glavina <stjepang@gmail.com> | [source](https://github.com/element-hq/async-compat/commit/5a27c8b290f1f1dcfc0c4ec22c464e38528aa591) |
| `async-compression` | `0.4.12` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Wim Looman <wim@nemo157.com>; Allen Bui <fairingrey@gmail.com> | [source](https://crates.io/api/v1/crates/async-compression/0.4.12/download) |
| `async-rx` | `0.2.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/async-rx/0.2.0/download) |
| `async-stream` | `0.3.6` | `MIT` | `MIT` | Carl Lerche <me@carllerche.com> | [source](https://crates.io/api/v1/crates/async-stream/0.3.6/download) |
| `async-stream-impl` | `0.3.6` | `MIT` | `MIT` | Carl Lerche <me@carllerche.com> | [source](https://crates.io/api/v1/crates/async-stream-impl/0.3.6/download) |
| `async-trait` | `0.1.89` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/async-trait/0.1.89/download) |
| `async_cell` | `0.2.3` | `MIT` | `MIT` | Sam Sartor <me@samsartor.com> | [source](https://crates.io/api/v1/crates/async_cell/0.2.3/download) |
| `atomic-waker` | `1.1.2` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Stjepan Glavina <stjepang@gmail.com>; Contributors to futures-rs | [source](https://crates.io/api/v1/crates/atomic-waker/1.1.2/download) |
| `autocfg` | `1.3.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Josh Stone <cuviper@gmail.com> | [source](https://crates.io/api/v1/crates/autocfg/1.3.0/download) |
| `aws-lc-rs` | `1.16.2` | `ISC AND (Apache-2.0 OR ISC)` | `ISC AND (Apache-2.0 OR ISC)` | AWS-LibCrypto | [source](https://crates.io/api/v1/crates/aws-lc-rs/1.16.2/download) |
| `aws-lc-sys` | `0.39.0` | `ISC AND (Apache-2.0 OR ISC) AND Apache-2.0 AND MIT AND BSD-3-Clause AND (Apache-2.0 OR ISC OR MIT) AND (Apache-2.0 OR ISC OR MIT-0)` | `ISC AND (Apache-2.0 OR ISC) AND Apache-2.0 AND MIT AND BSD-3-Clause AND (Apache-2.0 OR ISC OR MIT) AND (Apache-2.0 OR ISC OR MIT-0)` | AWS-LC | [source](https://crates.io/api/v1/crates/aws-lc-sys/0.39.0/download) |
| `backon` | `1.6.0` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/backon/1.6.0/download) |
| `backtrace` | `0.3.76` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers | [source](https://crates.io/api/v1/crates/backtrace/0.3.76/download) |
| `base64` | `0.22.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Marshall Pierce <marshall@mpierce.org> | [source](https://crates.io/api/v1/crates/base64/0.22.1/download) |
| `base64ct` | `1.8.3` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/base64ct/1.8.3/download) |
| `basic-toml` | `0.1.9` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com>; David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/basic-toml/0.1.9/download) |
| `bit-set` | `0.8.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Alexis Beingessner <a.beingessner@gmail.com> | [source](https://crates.io/api/v1/crates/bit-set/0.8.0/download) |
| `bit-vec` | `0.8.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Alexis Beingessner <a.beingessner@gmail.com> | [source](https://crates.io/api/v1/crates/bit-vec/0.8.0/download) |
| `bitflags` | `2.10.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers | [source](https://crates.io/api/v1/crates/bitflags/2.10.0/download) |
| `bitmaps` | `3.2.1` | `MPL-2.0+` | `MPL-2.0-or-later` | Bodil Stokke <bodil@bodil.org> | [source](https://crates.io/api/v1/crates/bitmaps/3.2.1/download) |
| `bitpacking` | `0.9.3` | `MIT` | `MIT` | Paul Masurel <paul.masurel@gmail.com> | [source](https://crates.io/api/v1/crates/bitpacking/0.9.3/download) |
| `blake3` | `1.8.2` | `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception` | `CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception` | Jack O'Connor <oconnor663@gmail.com>; Samuel Neves | [source](https://crates.io/api/v1/crates/blake3/1.8.2/download) |
| `block-buffer` | `0.10.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/block-buffer/0.10.4/download) |
| `block-padding` | `0.3.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/block-padding/0.3.3/download) |
| `bon` | `3.6.5` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/bon/3.6.5/download) |
| `bon-macros` | `3.6.5` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/bon-macros/3.6.5/download) |
| `bs58` | `0.5.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/bs58/0.5.1/download) |
| `bumpalo` | `3.16.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Nick Fitzgerald <fitzgen@gmail.com> | [source](https://crates.io/api/v1/crates/bumpalo/3.16.0/download) |
| `byteorder` | `1.5.0` | `Unlicense OR MIT` | `Unlicense OR MIT` | Andrew Gallant <jamslam@gmail.com> | [source](https://crates.io/api/v1/crates/byteorder/1.5.0/download) |
| `bytes` | `1.11.1` | `MIT` | `MIT` | Carl Lerche <me@carllerche.com>; Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/bytes/1.11.1/download) |
| `bytesize` | `2.3.0` | `Apache-2.0` | `Apache-2.0` | Hyunsik Choi <hyunsik.choi@gmail.com>; MrCroxx <mrcroxx@outlook.com>; Rob Ede <robjtede@icloud.com> | [source](https://crates.io/api/v1/crates/bytesize/2.3.0/download) |
| `camino` | `1.2.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Without Boats <saoirse@without.boats>; Ashley Williams <ashley666ashley@gmail.com>; Steve Klabnik <steve@steveklabnik.com>; Rain <rain@sunshowers.io> | [source](https://crates.io/api/v1/crates/camino/1.2.2/download) |
| `cargo-platform` | `0.1.9` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/cargo-platform/0.1.9/download) |
| `cargo_metadata` | `0.19.2` | `MIT` | `MIT` | Oliver Schneider <git-spam-no-reply9815368754983@oli-obk.de> | [source](https://crates.io/api/v1/crates/cargo_metadata/0.19.2/download) |
| `cast` | `0.3.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jorge Aparicio <jorge@japaric.io> | [source](https://crates.io/api/v1/crates/cast/0.3.0/download) |
| `cbc` | `0.1.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/cbc/0.1.2/download) |
| `cc` | `1.2.52` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com> | [source](https://crates.io/api/v1/crates/cc/1.2.52/download) |
| `census` | `0.4.2` | `MIT` | `MIT` | Paul Masurel <paul.masurel@gmail.com> | [source](https://crates.io/api/v1/crates/census/0.4.2/download) |
| `cfg-if` | `1.0.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com> | [source](https://crates.io/api/v1/crates/cfg-if/1.0.4/download) |
| `chacha20` | `0.10.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/chacha20/0.10.0/download) |
| `chacha20` | `0.9.1` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/chacha20/0.9.1/download) |
| `chacha20poly1305` | `0.10.1` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/chacha20poly1305/0.10.1/download) |
| `chrono` | `0.4.42` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/chrono/0.4.42/download) |
| `cipher` | `0.4.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/cipher/0.4.4/download) |
| `cmake` | `0.1.57` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com> | [source](https://crates.io/api/v1/crates/cmake/0.1.57/download) |
| `concurrent-queue` | `2.5.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Stjepan Glavina <stjepang@gmail.com>; Taiki Endo <te316e89@gmail.com>; John Nunley <dev@notgull.net> | [source](https://crates.io/api/v1/crates/concurrent-queue/2.5.0/download) |
| `console` | `0.15.8` | `MIT` | `MIT` | Armin Ronacher <armin.ronacher@active-4.com> | [source](https://crates.io/api/v1/crates/console/0.15.8/download) |
| `const-oid` | `0.9.6` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/const-oid/0.9.6/download) |
| `const_panic` | `0.2.15` | `Zlib` | `Zlib` | rodrimati1992 <rodrimatt1985@gmail.com> | [source](https://github.com/jplatte/const_panic/commit/e0b317a9a7bde2d48a7d15b6a60d70e4a41d3b5f) |
| `constant_time_eq` | `0.3.1` | `CC0-1.0 OR MIT-0 OR Apache-2.0` | `CC0-1.0 OR MIT-0 OR Apache-2.0` | Cesar Eduardo Barros <cesarb@cesarb.eti.br> | [source](https://crates.io/api/v1/crates/constant_time_eq/0.3.1/download) |
| `core-foundation` | `0.10.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Servo Project Developers | [source](https://crates.io/api/v1/crates/core-foundation/0.10.1/download) |
| `core-foundation-sys` | `0.8.6` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Servo Project Developers | [source](https://crates.io/api/v1/crates/core-foundation-sys/0.8.6/download) |
| `cpufeatures` | `0.2.12` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/cpufeatures/0.2.12/download) |
| `crc32fast` | `1.4.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Sam Rijs <srijs@airpost.net>; Alex Crichton <alex@alexcrichton.com> | [source](https://crates.io/api/v1/crates/crc32fast/1.4.2/download) |
| `crossbeam-channel` | `0.5.15` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/crossbeam-channel/0.5.15/download) |
| `crossbeam-deque` | `0.8.5` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/crossbeam-deque/0.8.5/download) |
| `crossbeam-epoch` | `0.9.20` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/crossbeam-epoch/0.9.20/download) |
| `crossbeam-utils` | `0.8.20` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/crossbeam-utils/0.8.20/download) |
| `crunchy` | `0.2.2` | `MIT` | `MIT` | Vurich <jackefransham@hotmail.co.uk> | [source](https://crates.io/api/v1/crates/crunchy/0.2.2/download) |
| `crypto-common` | `0.1.6` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/crypto-common/0.1.6/download) |
| `ctor` | `0.2.9` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Matt Mastracci <matthew@mastracci.com> | [source](https://crates.io/api/v1/crates/ctor/0.2.9/download) |
| `ctr` | `0.9.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/ctr/0.9.2/download) |
| `curve25519-dalek` | `4.1.3` | `BSD-3-Clause` | `BSD-3-Clause` | Isis Lovecruft <isis@patternsinthevoid.net>; Henry de Valence <hdevalence@hdevalence.ca> | [source](https://crates.io/api/v1/crates/curve25519-dalek/4.1.3/download) |
| `darling` | `0.20.10` | `MIT` | `MIT` | Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/darling/0.20.10/download) |
| `darling` | `0.21.1` | `MIT` | `MIT` | Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/darling/0.21.1/download) |
| `darling_core` | `0.20.10` | `MIT` | `MIT` | Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/darling_core/0.20.10/download) |
| `darling_core` | `0.21.1` | `MIT` | `MIT` | Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/darling_core/0.21.1/download) |
| `darling_macro` | `0.20.10` | `MIT` | `MIT` | Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/darling_macro/0.20.10/download) |
| `darling_macro` | `0.21.1` | `MIT` | `MIT` | Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/darling_macro/0.21.1/download) |
| `data-encoding` | `2.11.0` | `MIT` | `MIT` | Julien Cretin <git@ia0.eu> | [source](https://crates.io/api/v1/crates/data-encoding/2.11.0/download) |
| `datasketches` | `0.2.0` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/datasketches/0.2.0/download) |
| `date_header` | `1.0.5` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jayshua Nelson <me@jayshuanelson.com> | [source](https://crates.io/api/v1/crates/date_header/1.0.5/download) |
| `deadpool` | `0.12.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Michael P. Jung <michael.jung@terreon.de> | [source](https://crates.io/api/v1/crates/deadpool/0.12.3/download) |
| `deadpool` | `0.13.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Michael P. Jung <michael.jung@terreon.de> | [source](https://crates.io/api/v1/crates/deadpool/0.13.0/download) |
| `deadpool-runtime` | `0.1.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Michael P. Jung <michael.jung@terreon.de> | [source](https://crates.io/api/v1/crates/deadpool-runtime/0.1.4/download) |
| `deadpool-runtime` | `0.3.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Michael P. Jung <michael.jung@terreon.de> | [source](https://crates.io/api/v1/crates/deadpool-runtime/0.3.1/download) |
| `deadpool-sync` | `0.2.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Michael P. Jung <michael.jung@terreon.de> | [source](https://crates.io/api/v1/crates/deadpool-sync/0.2.0/download) |
| `decancer` | `3.3.3` | `MIT` | `MIT` | null (https://github.com/null8626) | [source](https://crates.io/api/v1/crates/decancer/3.3.3/download) |
| `der` | `0.7.9` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/der/0.7.9/download) |
| `der-parser` | `10.0.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Pierre Chifflier <chifflier@wzdftpd.net> | [source](https://crates.io/api/v1/crates/der-parser/10.0.0/download) |
| `deranged` | `0.5.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jacob Pratt <jacob@jhpratt.dev> | [source](https://crates.io/api/v1/crates/deranged/0.5.3/download) |
| `derive_builder` | `0.20.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Colin Kiegel <kiegel@gmx.de>; Pascal Hertleif <killercup@gmail.com>; Jan-Erik Rediger <janerik@fnordig.de>; Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/derive_builder/0.20.2/download) |
| `derive_builder_core` | `0.20.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Colin Kiegel <kiegel@gmx.de>; Pascal Hertleif <killercup@gmail.com>; Jan-Erik Rediger <janerik@fnordig.de>; Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/derive_builder_core/0.20.2/download) |
| `derive_builder_macro` | `0.20.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Colin Kiegel <kiegel@gmx.de>; Pascal Hertleif <killercup@gmail.com>; Jan-Erik Rediger <janerik@fnordig.de>; Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/derive_builder_macro/0.20.2/download) |
| `digest` | `0.10.7` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/digest/0.10.7/download) |
| `dirs` | `6.0.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Simon Ochsenreither <simon@ochsenreither.de> | [source](https://crates.io/api/v1/crates/dirs/6.0.0/download) |
| `dirs-sys` | `0.5.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Simon Ochsenreither <simon@ochsenreither.de> | [source](https://crates.io/api/v1/crates/dirs-sys/0.5.0/download) |
| `displaydoc` | `0.2.5` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jane Lusby <jlusby@yaah.dev> | [source](https://crates.io/api/v1/crates/displaydoc/0.2.5/download) |
| `downcast-rs` | `2.0.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/downcast-rs/2.0.1/download) |
| `dunce` | `1.0.5` | `CC0-1.0 OR MIT-0 OR Apache-2.0` | `CC0-1.0 OR MIT-0 OR Apache-2.0` | Kornel <kornel@geekhood.net> | [source](https://crates.io/api/v1/crates/dunce/1.0.5/download) |
| `ed25519` | `2.2.3` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/ed25519/2.2.3/download) |
| `ed25519-dalek` | `2.1.1` | `BSD-3-Clause` | `BSD-3-Clause` | isis lovecruft <isis@patternsinthevoid.net>; Tony Arcieri <bascule@gmail.com>; Michael Rosenberg <michael@mrosenberg.pub> | [source](https://crates.io/api/v1/crates/ed25519-dalek/2.1.1/download) |
| `either` | `1.13.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | bluss | [source](https://crates.io/api/v1/crates/either/1.13.0/download) |
| `emojis` | `0.8.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Ross MacArthur <ross@macarthur.io> | [source](https://crates.io/api/v1/crates/emojis/0.8.0/download) |
| `equivalent` | `1.0.1` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/equivalent/1.0.1/download) |
| `erased-serde` | `0.4.10` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/erased-serde/0.4.10/download) |
| `errno` | `0.3.13` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Chris Wong <lambda.fairy@gmail.com>; Dan Gohman <dev@sunfishcode.online> | [source](https://crates.io/api/v1/crates/errno/0.3.13/download) |
| `event-listener` | `5.4.1` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Stjepan Glavina <stjepang@gmail.com>; John Nunley <dev@notgull.net> | [source](https://crates.io/api/v1/crates/event-listener/5.4.1/download) |
| `event-listener-strategy` | `0.5.4` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | John Nunley <dev@notgull.net> | [source](https://crates.io/api/v1/crates/event-listener-strategy/0.5.4/download) |
| `extension-trait` | `1.0.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Konrad Borowski <konrad@borowski.pw> | [source](https://crates.io/api/v1/crates/extension-trait/1.0.2/download) |
| `eyeball` | `0.8.8` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/eyeball/0.8.8/download) |
| `eyeball-im` | `0.8.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/eyeball-im/0.8.0/download) |
| `eyeball-im-util` | `0.10.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/eyeball-im-util/0.10.0/download) |
| `fallible-iterator` | `0.3.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Steven Fackler <sfackler@gmail.com> | [source](https://crates.io/api/v1/crates/fallible-iterator/0.3.0/download) |
| `fallible-streaming-iterator` | `0.1.9` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Steven Fackler <sfackler@gmail.com> | [source](https://crates.io/api/v1/crates/fallible-streaming-iterator/0.1.9/download) |
| `fancy-regex` | `0.18.0` | `MIT` | `MIT` | Raph Levien <raph@google.com>; Robin Stocker <robin@nibor.org>; Keith Hall <keith.hall@available.systems> | [source](https://crates.io/api/v1/crates/fancy-regex/0.18.0/download) |
| `fastdivide` | `0.4.2` | `zlib-acknowledgement OR MIT` | `zlib-acknowledgement OR MIT` | Paul Masurel <paul.masurel@gmail.com> | [source](https://crates.io/api/v1/crates/fastdivide/0.4.2/download) |
| `fastrand` | `2.2.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Stjepan Glavina <stjepang@gmail.com> | [source](https://crates.io/api/v1/crates/fastrand/2.2.0/download) |
| `find-msvc-tools` | `0.1.7` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/find-msvc-tools/0.1.7/download) |
| `flate2` | `1.1.5` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com>; Josh Triplett <josh@joshtriplett.org> | [source](https://crates.io/api/v1/crates/flate2/1.1.5/download) |
| `fnv` | `1.0.7` | `Apache-2.0  OR  MIT` | `Apache-2.0  OR  MIT` | Alex Crichton <alex@alexcrichton.com> | [source](https://crates.io/api/v1/crates/fnv/1.0.7/download) |
| `foldhash` | `0.1.5` | `Zlib` | `Zlib` | Orson Peters <orsonpeters@gmail.com> | [source](https://crates.io/api/v1/crates/foldhash/0.1.5/download) |
| `foldhash` | `0.2.0` | `Zlib` | `Zlib` | Orson Peters <orsonpeters@gmail.com> | [source](https://crates.io/api/v1/crates/foldhash/0.2.0/download) |
| `form_urlencoded` | `1.2.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The rust-url developers | [source](https://crates.io/api/v1/crates/form_urlencoded/1.2.2/download) |
| `fs-err` | `2.11.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Andrew Hickman <andrew.hickman1@sky.com> | [source](https://crates.io/api/v1/crates/fs-err/2.11.0/download) |
| `fs4` | `0.13.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Dan Burkert <dan@danburkert.com>; Al Liu <scygliu1@gmail.com> | [source](https://crates.io/api/v1/crates/fs4/0.13.1/download) |
| `fs_extra` | `1.3.0` | `MIT` | `MIT` | Denis Kurilenko <webdesus@gmail.com> | [source](https://crates.io/api/v1/crates/fs_extra/1.3.0/download) |
| `futures` | `0.3.31` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/futures/0.3.31/download) |
| `futures-channel` | `0.3.31` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/futures-channel/0.3.31/download) |
| `futures-core` | `0.3.31` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/futures-core/0.3.31/download) |
| `futures-executor` | `0.3.31` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/futures-executor/0.3.31/download) |
| `futures-io` | `0.3.31` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/futures-io/0.3.31/download) |
| `futures-macro` | `0.3.31` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/futures-macro/0.3.31/download) |
| `futures-sink` | `0.3.31` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/futures-sink/0.3.31/download) |
| `futures-task` | `0.3.31` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/futures-task/0.3.31/download) |
| `futures-util` | `0.3.31` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/futures-util/0.3.31/download) |
| `fuzzy-matcher` | `0.3.7` | `MIT` | `MIT` | Jinzhou Zhang <lotabout@gmail.com> | [source](https://crates.io/api/v1/crates/fuzzy-matcher/0.3.7/download) |
| `generic-array` | `0.14.7` | `MIT` | `MIT` | Bartłomiej Kamiński <fizyk20@gmail.com>; Aaron Trent <novacrazy@gmail.com> | [source](https://crates.io/api/v1/crates/generic-array/0.14.7/download) |
| `getrandom` | `0.2.15` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers | [source](https://crates.io/api/v1/crates/getrandom/0.2.15/download) |
| `getrandom` | `0.3.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers | [source](https://crates.io/api/v1/crates/getrandom/0.3.4/download) |
| `getrandom` | `0.4.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers | [source](https://crates.io/api/v1/crates/getrandom/0.4.2/download) |
| `gimli` | `0.32.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/gimli/0.32.3/download) |
| `glob` | `0.3.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers | [source](https://crates.io/api/v1/crates/glob/0.3.3/download) |
| `goblin` | `0.8.2` | `MIT` | `MIT` | m4b <m4b.github.io@gmail.com>; seu <seu@panopticon.re>; Will Glynn <will@willglynn.com>; Philip Craig <philipjcraig@gmail.com>; Lzu Tao <taolzu@gmail.com> | [source](https://crates.io/api/v1/crates/goblin/0.8.2/download) |
| `growable-bloom-filter` | `2.1.1` | `MIT` | `MIT` | David Briggs <david@dpbriggs.ca>; Arthur Silva <arthurprs@gmail.com> | [source](https://crates.io/api/v1/crates/growable-bloom-filter/2.1.1/download) |
| `h2` | `0.4.5` | `MIT` | `MIT` | Carl Lerche <me@carllerche.com>; Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/h2/0.4.5/download) |
| `hashbrown` | `0.15.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Amanieu d'Antras <amanieu@gmail.com> | [source](https://crates.io/api/v1/crates/hashbrown/0.15.2/download) |
| `hashbrown` | `0.16.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Amanieu d'Antras <amanieu@gmail.com> | [source](https://crates.io/api/v1/crates/hashbrown/0.16.1/download) |
| `hashlink` | `0.10.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | kyren <kerriganw@gmail.com> | [source](https://crates.io/api/v1/crates/hashlink/0.10.0/download) |
| `headers` | `0.4.1` | `MIT` | `MIT` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/headers/0.4.1/download) |
| `headers-core` | `0.3.0` | `MIT` | `MIT` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/headers-core/0.3.0/download) |
| `heck` | `0.5.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/heck/0.5.0/download) |
| `hkdf` | `0.12.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/hkdf/0.12.4/download) |
| `hmac` | `0.12.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/hmac/0.12.1/download) |
| `html5ever` | `0.39.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The html5ever Project Developers | [source](https://crates.io/api/v1/crates/html5ever/0.39.0/download) |
| `htmlescape` | `0.3.1` | `Apache-2.0  OR  MIT  OR  MPL-2.0` | `Apache-2.0  OR  MIT  OR  MPL-2.0` | Viktor Dahl <pazaconyoman@gmail.com> | [source](https://crates.io/api/v1/crates/htmlescape/0.3.1/download) |
| `http` | `1.3.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com>; Carl Lerche <me@carllerche.com>; Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/http/1.3.1/download) |
| `http-auth` | `0.1.10` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/http-auth/0.1.10/download) |
| `http-body` | `1.0.1` | `MIT` | `MIT` | Carl Lerche <me@carllerche.com>; Lucio Franco <luciofranco14@gmail.com>; Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/http-body/1.0.1/download) |
| `http-body-util` | `0.1.2` | `MIT` | `MIT` | Carl Lerche <me@carllerche.com>; Lucio Franco <luciofranco14@gmail.com>; Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/http-body-util/0.1.2/download) |
| `httparse` | `1.9.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/httparse/1.9.4/download) |
| `httpdate` | `1.0.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Pyfisch <pyfisch@posteo.org> | [source](https://crates.io/api/v1/crates/httpdate/1.0.3/download) |
| `hyper` | `1.7.0` | `MIT` | `MIT` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/hyper/1.7.0/download) |
| `hyper-rustls` | `0.27.2` | `Apache-2.0 OR ISC OR MIT` | `Apache-2.0 OR ISC OR MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/hyper-rustls/0.27.2/download) |
| `hyper-util` | `0.1.16` | `MIT` | `MIT` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/hyper-util/0.1.16/download) |
| `iana-time-zone` | `0.1.60` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Andrew Straw <strawman@astraw.com>; René Kijewski <rene.kijewski@fu-berlin.de>; Ryan Lopopolo <rjl@hyperbo.la> | [source](https://crates.io/api/v1/crates/iana-time-zone/0.1.60/download) |
| `icu_collections` | `1.5.0` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_collections/1.5.0/download) |
| `icu_locid` | `1.5.0` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_locid/1.5.0/download) |
| `icu_locid_transform` | `1.5.0` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_locid_transform/1.5.0/download) |
| `icu_locid_transform_data` | `1.5.0` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_locid_transform_data/1.5.0/download) |
| `icu_normalizer` | `1.5.0` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_normalizer/1.5.0/download) |
| `icu_normalizer_data` | `1.5.0` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_normalizer_data/1.5.0/download) |
| `icu_properties` | `1.5.1` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_properties/1.5.1/download) |
| `icu_properties_data` | `1.5.0` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_properties_data/1.5.0/download) |
| `icu_provider` | `1.5.0` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_provider/1.5.0/download) |
| `icu_provider_macros` | `1.5.0` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/icu_provider_macros/1.5.0/download) |
| `ident_case` | `1.0.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Ted Driggs <ted.driggs@outlook.com> | [source](https://crates.io/api/v1/crates/ident_case/1.0.1/download) |
| `idna` | `1.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The rust-url developers | [source](https://crates.io/api/v1/crates/idna/1.1.0/download) |
| `idna_adapter` | `1.2.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | The rust-url developers | [source](https://crates.io/api/v1/crates/idna_adapter/1.2.0/download) |
| `imbl` | `6.1.0` | `MPL-2.0+` | `MPL-2.0-or-later` | Bodil Stokke <bodil@bodil.org>; Joe Neeman <joeneeman@gmail.com>; Arthur Silva <arthurprs@gmail.com> | [source](https://crates.io/api/v1/crates/imbl/6.1.0/download) |
| `imbl-sized-chunks` | `0.1.3` | `MPL-2.0+` | `MPL-2.0-or-later` | Bodil Stokke <bodil@bodil.org>; Joe Neeman <joeneeman@gmail.com> | [source](https://crates.io/api/v1/crates/imbl-sized-chunks/0.1.3/download) |
| `include_dir` | `0.7.4` | `MIT` | `MIT` | Michael Bryan <michaelfbryan@gmail.com> | [source](https://crates.io/api/v1/crates/include_dir/0.7.4/download) |
| `include_dir_macros` | `0.7.4` | `MIT` | `MIT` | Michael Bryan <michaelfbryan@gmail.com> | [source](https://crates.io/api/v1/crates/include_dir_macros/0.7.4/download) |
| `indexmap` | `2.12.1` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/indexmap/2.12.1/download) |
| `inout` | `0.1.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/inout/0.1.3/download) |
| `insta` | `1.44.1` | `Apache-2.0` | `Apache-2.0` | Armin Ronacher <armin.ronacher@active-4.com> | [source](https://crates.io/api/v1/crates/insta/1.44.1/download) |
| `inventory` | `0.3.24` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/inventory/0.3.24/download) |
| `ipnet` | `2.9.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Kris Price <kris@krisprice.nz> | [source](https://crates.io/api/v1/crates/ipnet/2.9.0/download) |
| `iri-string` | `0.7.8` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | YOSHIOKA Takuma <nop_thread@nops.red> | [source](https://crates.io/api/v1/crates/iri-string/0.7.8/download) |
| `itertools` | `0.10.5` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | bluss | [source](https://crates.io/api/v1/crates/itertools/0.10.5/download) |
| `itertools` | `0.14.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | bluss | [source](https://crates.io/api/v1/crates/itertools/0.14.0/download) |
| `itoa` | `1.0.11` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/itoa/1.0.11/download) |
| `jobserver` | `0.1.32` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com> | [source](https://crates.io/api/v1/crates/jobserver/0.1.32/download) |
| `js-sys` | `0.3.91` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The wasm-bindgen Developers | [source](https://crates.io/api/v1/crates/js-sys/0.3.91/download) |
| `js_int` | `0.2.2` | `MIT` | `MIT` | Jonas Platte <jplatte+git@posteo.de> | [source](https://crates.io/api/v1/crates/js_int/0.2.2/download) |
| `js_option` | `0.2.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/js_option/0.2.0/download) |
| `konst` | `0.4.3` | `Zlib` | `Zlib` | rodrimati1992 <rodrimatt1985@gmail.com> | [source](https://crates.io/api/v1/crates/konst/0.4.3/download) |
| `language-tags` | `0.3.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Pyfisch <pyfisch@gmail.com>; Tpt <thomas@pellissier-tanon.fr> | [source](https://crates.io/api/v1/crates/language-tags/0.3.2/download) |
| `lazy_static` | `1.5.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Marvin Löbel <loebel.marvin@gmail.com> | [source](https://crates.io/api/v1/crates/lazy_static/1.5.0/download) |
| `levenshtein_automata` | `0.2.1` | `MIT` | `MIT` | Paul Masurel <paul.masurel@gmail.com> | [source](https://crates.io/api/v1/crates/levenshtein_automata/0.2.1/download) |
| `libc` | `0.2.175` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers | [source](https://crates.io/api/v1/crates/libc/0.2.175/download) |
| `libm` | `0.2.15` | `MIT` | `MIT` | Jorge Aparicio <jorge@japaric.io> | [source](https://crates.io/api/v1/crates/libm/0.2.15/download) |
| `libsqlite3-sys` | `0.35.0` | `MIT` | `MIT` | The rusqlite developers | [source](https://crates.io/api/v1/crates/libsqlite3-sys/0.35.0/download) |
| `litemap` | `0.7.4` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/litemap/0.7.4/download) |
| `lock_api` | `0.4.12` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Amanieu d'Antras <amanieu@gmail.com> | [source](https://crates.io/api/v1/crates/lock_api/0.4.12/download) |
| `log` | `0.4.27` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers | [source](https://crates.io/api/v1/crates/log/0.4.27/download) |
| `log-panics` | `2.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Steven Fackler <sfackler@gmail.com> | [source](https://crates.io/api/v1/crates/log-panics/2.1.0/download) |
| `lru` | `0.16.4` | `MIT` | `MIT` | Jerome Froelich <jeromefroelic@hotmail.com> | [source](https://crates.io/api/v1/crates/lru/0.16.4/download) |
| `lz4_flex` | `0.13.1` | `MIT` | `MIT` | Pascal Seitz <pascal.seitz@gmail.com>; Arthur Silva <arthurprs@gmail.com>; ticki <Ticki@users.noreply.github.com> | [source](https://crates.io/api/v1/crates/lz4_flex/0.13.1/download) |
| `maplit` | `1.0.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | bluss | [source](https://crates.io/api/v1/crates/maplit/1.0.2/download) |
| `markup5ever` | `0.39.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The html5ever Project Developers | [source](https://crates.io/api/v1/crates/markup5ever/0.39.0/download) |
| `matchers` | `0.2.0` | `MIT` | `MIT` | Eliza Weisman <eliza@buoyant.io> | [source](https://crates.io/api/v1/crates/matchers/0.2.0/download) |
| `matrix-pickle` | `0.2.3` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/matrix-pickle/0.2.3/download) |
| `matrix-pickle-derive` | `0.2.3` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/matrix-pickle-derive/0.2.3/download) |
| `matrix-sdk` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Damir Jelić <poljar@termina.org.uk> | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-base` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Damir Jelić <poljar@termina.org.uk> | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-common` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Damir Jelić <poljar@termina.org.uk> | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-contentscanner` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Jorge Martín Espinosa <jorgem@element.io> | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-crypto` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Damir Jelić <poljar@termina.org.uk> | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-ffi` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-ffi-macros` | `0.7.0` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-search` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Shrey Patel <shreyrg14@gmail.com> | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-sqlite` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-store-encryption` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-test` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Damir Jelić <poljar@termina.org.uk> | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-test-macros` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | stoically <stoically@protonmail.com> | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-test-utils` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `matrix-sdk-ui` | `0.18.0` | `Apache-2.0` | `Apache-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/bananawalnut/matrix-rust-sdk/commit/99d79bdde4bb2ff87c015e50d3537b4f512c5bf5) |
| `measure_time` | `0.9.0` | `MIT` | `MIT` | Pascal Seitz <pascal.seitz@gmail.com> | [source](https://crates.io/api/v1/crates/measure_time/0.9.0/download) |
| `memchr` | `2.7.4` | `Unlicense OR MIT` | `Unlicense OR MIT` | Andrew Gallant <jamslam@gmail.com>; bluss | [source](https://crates.io/api/v1/crates/memchr/2.7.4/download) |
| `memmap2` | `0.9.7` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Dan Burkert <dan@danburkert.com>; Yevhenii Reizner <razrfalcon@gmail.com> | [source](https://crates.io/api/v1/crates/memmap2/0.9.7/download) |
| `mime` | `0.3.17` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/mime/0.3.17/download) |
| `mime2ext` | `0.1.54` | `MIT` | `MIT` | Jan Verbeek <jan.verbeek@posteo.nl> | [source](https://crates.io/api/v1/crates/mime2ext/0.1.54/download) |
| `minimal-lexical` | `0.2.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Huszagh <ahuszagh@gmail.com> | [source](https://crates.io/api/v1/crates/minimal-lexical/0.2.1/download) |
| `miniz_oxide` | `0.8.9` | `MIT OR Zlib OR Apache-2.0` | `MIT OR Zlib OR Apache-2.0` | Frommi <daniil.liferenko@gmail.com>; oyvindln <oyvindln@users.noreply.github.com>; Rich Geldreich richgel99@gmail.com | [source](https://crates.io/api/v1/crates/miniz_oxide/0.8.9/download) |
| `mio` | `1.0.2` | `MIT` | `MIT` | Carl Lerche <me@carllerche.com>; Thomas de Zeeuw <thomasdezeeuw@gmail.com>; Tokio Contributors <team@tokio.rs> | [source](https://crates.io/api/v1/crates/mio/1.0.2/download) |
| `murmurhash32` | `0.3.1` | `MIT` | `MIT` | Paul Masurel <paul.masurel@gmail.com> | [source](https://crates.io/api/v1/crates/murmurhash32/0.3.1/download) |
| `new_debug_unreachable` | `1.0.6` | `MIT` | `MIT` | Matt Brubeck <mbrubeck@limpet.net>; Jonathan Reem <jonathan.reem@gmail.com> | [source](https://crates.io/api/v1/crates/new_debug_unreachable/1.0.6/download) |
| `nom` | `7.1.3` | `MIT` | `MIT` | contact@geoffroycouprie.com | [source](https://crates.io/api/v1/crates/nom/7.1.3/download) |
| `nu-ansi-term` | `0.50.1` | `MIT` | `MIT` | ogham@bsago.me; Ryan Scheel (Havvy) <ryan.havvy@gmail.com>; Josh Triplett <josh@joshtriplett.org>; The Nushell Project Developers | [source](https://crates.io/api/v1/crates/nu-ansi-term/0.50.1/download) |
| `num-bigint` | `0.4.8` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers | [source](https://crates.io/api/v1/crates/num-bigint/0.4.8/download) |
| `num-conv` | `0.2.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jacob Pratt <jacob@jhpratt.dev> | [source](https://crates.io/api/v1/crates/num-conv/0.2.0/download) |
| `num-integer` | `0.1.46` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers | [source](https://crates.io/api/v1/crates/num-integer/0.1.46/download) |
| `num-traits` | `0.2.19` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers | [source](https://crates.io/api/v1/crates/num-traits/0.2.19/download) |
| `num_cpus` | `1.17.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/num_cpus/1.17.0/download) |
| `num_threads` | `0.1.7` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jacob Pratt <open-source@jhpratt.dev> | [source](https://crates.io/api/v1/crates/num_threads/0.1.7/download) |
| `oauth2` | `5.0.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com>; Florin Lipan <florinlipan@gmail.com>; David A. Ramos <ramos@cs.stanford.edu> | [source](https://crates.io/api/v1/crates/oauth2/5.0.0/download) |
| `oauth2-reqwest` | `0.1.0-alpha.3` | `MIT` | `MIT` | David A. Ramos <ramos@cs.stanford.edu> | [source](https://crates.io/api/v1/crates/oauth2-reqwest/0.1.0-alpha.3/download) |
| `object` | `0.37.3` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/object/0.37.3/download) |
| `oid-registry` | `0.8.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Pierre Chifflier <chifflier@wzdftpd.net> | [source](https://crates.io/api/v1/crates/oid-registry/0.8.1/download) |
| `once_cell` | `1.21.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Aleksey Kladov <aleksey.kladov@gmail.com> | [source](https://crates.io/api/v1/crates/once_cell/1.21.4/download) |
| `oneshot` | `0.1.13` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Linus Färnstrand <faern@faern.net> | [source](https://crates.io/api/v1/crates/oneshot/0.1.13/download) |
| `oorandom` | `11.1.5` | `MIT` | `MIT` | Simon Heath <icefox@dreamquest.io> | [source](https://crates.io/api/v1/crates/oorandom/11.1.5/download) |
| `opaque-debug` | `0.3.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/opaque-debug/0.3.1/download) |
| `option-ext` | `0.2.0` | `MPL-2.0` | `MPL-2.0` | Simon Ochsenreither <simon@ochsenreither.de> | [source](https://crates.io/api/v1/crates/option-ext/0.2.0/download) |
| `ordered-float` | `5.3.0` | `MIT` | `MIT` | Jonathan Reem <jonathan.reem@gmail.com>; Matt Brubeck <mbrubeck@limpet.net> | [source](https://crates.io/api/v1/crates/ordered-float/5.3.0/download) |
| `ownedbytes` | `0.9.0` | `MIT` | `MIT` | Paul Masurel <paul@quickwit.io>; Pascal Seitz <pascal@quickwit.io> | [source](https://crates.io/api/v1/crates/ownedbytes/0.9.0/download) |
| `parking` | `2.2.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Stjepan Glavina <stjepang@gmail.com>; The Rust Project Developers | [source](https://crates.io/api/v1/crates/parking/2.2.0/download) |
| `parking_lot` | `0.12.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Amanieu d'Antras <amanieu@gmail.com> | [source](https://crates.io/api/v1/crates/parking_lot/0.12.3/download) |
| `parking_lot_core` | `0.9.10` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Amanieu d'Antras <amanieu@gmail.com> | [source](https://crates.io/api/v1/crates/parking_lot_core/0.9.10/download) |
| `pbkdf2` | `0.12.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/pbkdf2/0.12.2/download) |
| `pem` | `3.0.6` | `MIT` | `MIT` | Jonathan Creekmore <jonathan@thecreekmores.org> | [source](https://crates.io/api/v1/crates/pem/3.0.6/download) |
| `percent-encoding` | `2.3.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The rust-url developers | [source](https://crates.io/api/v1/crates/percent-encoding/2.3.2/download) |
| `pest` | `2.8.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Dragoș Tiselice <dragostiselice@gmail.com> | [source](https://crates.io/api/v1/crates/pest/2.8.0/download) |
| `pest_derive` | `2.8.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Dragoș Tiselice <dragostiselice@gmail.com> | [source](https://crates.io/api/v1/crates/pest_derive/2.8.0/download) |
| `pest_generator` | `2.8.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Dragoș Tiselice <dragostiselice@gmail.com> | [source](https://crates.io/api/v1/crates/pest_generator/2.8.0/download) |
| `pest_meta` | `2.8.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Dragoș Tiselice <dragostiselice@gmail.com> | [source](https://crates.io/api/v1/crates/pest_meta/2.8.0/download) |
| `phf` | `0.13.1` | `MIT` | `MIT` | Steven Fackler <sfackler@gmail.com> | [source](https://crates.io/api/v1/crates/phf/0.13.1/download) |
| `phf_codegen` | `0.13.1` | `MIT` | `MIT` | Steven Fackler <sfackler@gmail.com> | [source](https://crates.io/api/v1/crates/phf_codegen/0.13.1/download) |
| `phf_generator` | `0.13.1` | `MIT` | `MIT` | Steven Fackler <sfackler@gmail.com> | [source](https://crates.io/api/v1/crates/phf_generator/0.13.1/download) |
| `phf_shared` | `0.13.1` | `MIT` | `MIT` | Steven Fackler <sfackler@gmail.com> | [source](https://crates.io/api/v1/crates/phf_shared/0.13.1/download) |
| `pin-project-lite` | `0.2.16` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/pin-project-lite/0.2.16/download) |
| `pin-utils` | `0.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Josef Brandl <mail@josefbrandl.de> | [source](https://crates.io/api/v1/crates/pin-utils/0.1.0/download) |
| `pkcs8` | `0.10.2` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/pkcs8/0.10.2/download) |
| `pkg-config` | `0.3.30` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com> | [source](https://crates.io/api/v1/crates/pkg-config/0.3.30/download) |
| `plain` | `0.2.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | jzr | [source](https://crates.io/api/v1/crates/plain/0.2.3/download) |
| `poly1305` | `0.8.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/poly1305/0.8.0/download) |
| `powerfmt` | `0.2.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jacob Pratt <jacob@jhpratt.dev> | [source](https://crates.io/api/v1/crates/powerfmt/0.2.0/download) |
| `ppv-lite86` | `0.2.17` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The CryptoCorrosion Contributors | [source](https://crates.io/api/v1/crates/ppv-lite86/0.2.17/download) |
| `precomputed-hash` | `0.1.1` | `MIT` | `MIT` | Emilio Cobos Álvarez <emilio@crisal.io> | [source](https://crates.io/api/v1/crates/precomputed-hash/0.1.1/download) |
| `prettyplease` | `0.2.34` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/prettyplease/0.2.34/download) |
| `proc-macro-crate` | `3.5.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Bastian Köcher <git@kchr.de> | [source](https://crates.io/api/v1/crates/proc-macro-crate/3.5.0/download) |
| `proc-macro-error-attr2` | `2.0.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | CreepySkeleton <creepy-skeleton@yandex.ru>; GnomedDev <david2005thomas@gmail.com> | [source](https://crates.io/api/v1/crates/proc-macro-error-attr2/2.0.0/download) |
| `proc-macro-error2` | `2.0.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | CreepySkeleton <creepy-skeleton@yandex.ru>; GnomedDev <david2005thomas@gmail.com> | [source](https://crates.io/api/v1/crates/proc-macro-error2/2.0.1/download) |
| `proc-macro2` | `1.0.106` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com>; Alex Crichton <alex@alexcrichton.com> | [source](https://crates.io/api/v1/crates/proc-macro2/1.0.106/download) |
| `proptest` | `1.9.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jason Lingle | [source](https://crates.io/api/v1/crates/proptest/1.9.0/download) |
| `prost` | `0.14.3` | `Apache-2.0` | `Apache-2.0` | Dan Burkert <dan@danburkert.com>; Lucio Franco <luciofranco14@gmail.com>; Casper Meijn <casper@meijn.net>; Tokio Contributors <team@tokio.rs> | [source](https://crates.io/api/v1/crates/prost/0.14.3/download) |
| `prost-derive` | `0.14.3` | `Apache-2.0` | `Apache-2.0` | Dan Burkert <dan@danburkert.com>; Lucio Franco <luciofranco14@gmail.com>; Casper Meijn <casper@meijn.net>; Tokio Contributors <team@tokio.rs> | [source](https://crates.io/api/v1/crates/prost-derive/0.14.3/download) |
| `pulldown-cmark` | `0.13.0` | `MIT` | `MIT` | Raph Levien <raph.levien@gmail.com>; Marcus Klaas de Vries <mail@marcusklaas.nl> | [source](https://crates.io/api/v1/crates/pulldown-cmark/0.13.0/download) |
| `pulldown-cmark-escape` | `0.11.0` | `MIT` | `MIT` | Raph Levien <raph.levien@gmail.com>; Marcus Klaas de Vries <mail@marcusklaas.nl> | [source](https://crates.io/api/v1/crates/pulldown-cmark-escape/0.11.0/download) |
| `quote` | `1.0.46` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/quote/1.0.46/download) |
| `rand` | `0.10.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers; The Rust Project Developers | [source](https://crates.io/api/v1/crates/rand/0.10.1/download) |
| `rand` | `0.8.6` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers; The Rust Project Developers | [source](https://crates.io/api/v1/crates/rand/0.8.6/download) |
| `rand` | `0.9.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers; The Rust Project Developers | [source](https://crates.io/api/v1/crates/rand/0.9.4/download) |
| `rand_chacha` | `0.3.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers; The Rust Project Developers; The CryptoCorrosion Contributors | [source](https://crates.io/api/v1/crates/rand_chacha/0.3.1/download) |
| `rand_chacha` | `0.9.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers; The Rust Project Developers; The CryptoCorrosion Contributors | [source](https://crates.io/api/v1/crates/rand_chacha/0.9.0/download) |
| `rand_core` | `0.10.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers | [source](https://crates.io/api/v1/crates/rand_core/0.10.0/download) |
| `rand_core` | `0.6.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers; The Rust Project Developers | [source](https://crates.io/api/v1/crates/rand_core/0.6.4/download) |
| `rand_core` | `0.9.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers; The Rust Project Developers | [source](https://crates.io/api/v1/crates/rand_core/0.9.3/download) |
| `rand_xorshift` | `0.4.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers; The Rust Project Developers | [source](https://crates.io/api/v1/crates/rand_xorshift/0.4.0/download) |
| `rand_xoshiro` | `0.7.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rand Project Developers | [source](https://crates.io/api/v1/crates/rand_xoshiro/0.7.0/download) |
| `rayon` | `1.10.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Niko Matsakis <niko@alum.mit.edu>; Josh Stone <cuviper@gmail.com> | [source](https://crates.io/api/v1/crates/rayon/1.10.0/download) |
| `rayon-core` | `1.12.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Niko Matsakis <niko@alum.mit.edu>; Josh Stone <cuviper@gmail.com> | [source](https://crates.io/api/v1/crates/rayon-core/1.12.1/download) |
| `rcgen` | `0.14.8` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/rcgen/0.14.8/download) |
| `readlock` | `0.1.8` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/readlock/0.1.8/download) |
| `readlock-tokio` | `0.1.3` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/readlock-tokio/0.1.3/download) |
| `regex` | `1.12.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers; Andrew Gallant <jamslam@gmail.com> | [source](https://crates.io/api/v1/crates/regex/1.12.2/download) |
| `regex-automata` | `0.4.14` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers; Andrew Gallant <jamslam@gmail.com> | [source](https://crates.io/api/v1/crates/regex-automata/0.4.14/download) |
| `regex-syntax` | `0.8.5` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Rust Project Developers; Andrew Gallant <jamslam@gmail.com> | [source](https://crates.io/api/v1/crates/regex-syntax/0.8.5/download) |
| `reqwest` | `0.13.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/reqwest/0.13.2/download) |
| `ring` | `0.17.14` | `Apache-2.0 AND ISC` | `Apache-2.0 AND ISC` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/ring/0.17.14/download) |
| `rmp` | `0.8.15` | `MIT` | `MIT` | Evgeny Safronov <division494@gmail.com>; Kornel <kornel@geekhood.net> | [source](https://crates.io/api/v1/crates/rmp/0.8.15/download) |
| `rmp-serde` | `1.3.0` | `MIT` | `MIT` | Evgeny Safronov <division494@gmail.com> | [source](https://crates.io/api/v1/crates/rmp-serde/1.3.0/download) |
| `ruma` | `0.16.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://github.com/ruma/ruma/commit/db24422e03aea7c7974230098fe9aeb5481cddc6) |
| `ruma-client-api` | `0.24.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://github.com/ruma/ruma/commit/db24422e03aea7c7974230098fe9aeb5481cddc6) |
| `ruma-common` | `0.19.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://github.com/ruma/ruma/commit/db24422e03aea7c7974230098fe9aeb5481cddc6) |
| `ruma-events` | `0.34.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://github.com/ruma/ruma/commit/db24422e03aea7c7974230098fe9aeb5481cddc6) |
| `ruma-federation-api` | `0.15.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://github.com/ruma/ruma/commit/db24422e03aea7c7974230098fe9aeb5481cddc6) |
| `ruma-html` | `0.8.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://github.com/ruma/ruma/commit/db24422e03aea7c7974230098fe9aeb5481cddc6) |
| `ruma-identifiers-validation` | `0.12.1` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://github.com/ruma/ruma/commit/db24422e03aea7c7974230098fe9aeb5481cddc6) |
| `ruma-macros` | `0.19.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://github.com/ruma/ruma/commit/db24422e03aea7c7974230098fe9aeb5481cddc6) |
| `ruma-signatures` | `0.21.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://github.com/ruma/ruma/commit/db24422e03aea7c7974230098fe9aeb5481cddc6) |
| `rusqlite` | `0.37.0` | `MIT` | `MIT` | The rusqlite developers | [source](https://crates.io/api/v1/crates/rusqlite/0.37.0/download) |
| `rust-stemmers` | `1.2.0` | `MIT OR BSD-3-Clause` | `MIT OR BSD-3-Clause` | Jakob Demler <jdemler@curry-software.com>; CurrySoftware <info@curry-software.com> | [source](https://crates.io/api/v1/crates/rust-stemmers/1.2.0/download) |
| `rustc-demangle` | `0.1.24` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com> | [source](https://crates.io/api/v1/crates/rustc-demangle/0.1.24/download) |
| `rustc-hash` | `2.0.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | The Rust Project Developers | [source](https://crates.io/api/v1/crates/rustc-hash/2.0.0/download) |
| `rustc_version` | `0.4.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Dirkjan Ochtman <dirkjan@ochtman.nl>; Marvin Löbel <loebel.marvin@gmail.com> | [source](https://crates.io/api/v1/crates/rustc_version/0.4.0/download) |
| `rusticata-macros` | `4.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Pierre Chifflier <chifflier@wzdftpd.net> | [source](https://crates.io/api/v1/crates/rusticata-macros/4.1.0/download) |
| `rustix` | `1.0.8` | `Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT` | `Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT` | Dan Gohman <dev@sunfishcode.online>; Jakub Konka <kubkon@jakubkonka.com> | [source](https://crates.io/api/v1/crates/rustix/1.0.8/download) |
| `rustls` | `0.23.42` | `Apache-2.0 OR ISC OR MIT` | `Apache-2.0 OR ISC OR MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/rustls/0.23.42/download) |
| `rustls-pki-types` | `1.14.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/rustls-pki-types/1.14.0/download) |
| `rustls-platform-verifier` | `0.6.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/rustls-platform-verifier/0.6.2/download) |
| `rustls-webpki` | `0.103.13` | `ISC` | `ISC` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/rustls-webpki/0.103.13/download) |
| `rustversion` | `1.0.22` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/rustversion/1.0.22/download) |
| `ryu` | `1.0.18` | `Apache-2.0 OR BSL-1.0` | `Apache-2.0 OR BSL-1.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/ryu/1.0.18/download) |
| `scopeguard` | `1.2.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | bluss | [source](https://crates.io/api/v1/crates/scopeguard/1.2.0/download) |
| `scroll` | `0.12.0` | `MIT` | `MIT` | m4b <m4b.github.io@gmail.com>; Ted Mielczarek <ted@mielczarek.org> | [source](https://crates.io/api/v1/crates/scroll/0.12.0/download) |
| `scroll_derive` | `0.12.0` | `MIT` | `MIT` | m4b <m4b.github.io@gmail.com>; Ted Mielczarek <ted@mielczarek.org>; Systemcluster <me@systemcluster.me> | [source](https://crates.io/api/v1/crates/scroll_derive/0.12.0/download) |
| `security-framework` | `3.5.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Steven Fackler <sfackler@gmail.com>; Kornel <kornel@geekhood.net> | [source](https://crates.io/api/v1/crates/security-framework/3.5.1/download) |
| `security-framework-sys` | `2.15.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Steven Fackler <sfackler@gmail.com>; Kornel <kornel@geekhood.net> | [source](https://crates.io/api/v1/crates/security-framework-sys/2.15.0/download) |
| `semver` | `1.0.27` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/semver/1.0.27/download) |
| `serde` | `1.0.228` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Erick Tryzelaar <erick.tryzelaar@gmail.com>; David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/serde/1.0.228/download) |
| `serde_bytes` | `0.11.19` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/serde_bytes/0.11.19/download) |
| `serde_core` | `1.0.228` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Erick Tryzelaar <erick.tryzelaar@gmail.com>; David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/serde_core/1.0.228/download) |
| `serde_derive` | `1.0.228` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Erick Tryzelaar <erick.tryzelaar@gmail.com>; David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/serde_derive/1.0.228/download) |
| `serde_html_form` | `0.4.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/serde_html_form/0.4.0/download) |
| `serde_json` | `1.0.145` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Erick Tryzelaar <erick.tryzelaar@gmail.com>; David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/serde_json/1.0.145/download) |
| `serde_path_to_error` | `0.1.20` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/serde_path_to_error/0.1.20/download) |
| `serde_spanned` | `1.1.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/serde_spanned/1.1.1/download) |
| `serde_urlencoded` | `0.7.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Anthony Ramine <n.oxyde@gmail.com> | [source](https://crates.io/api/v1/crates/serde_urlencoded/0.7.1/download) |
| `sha1` | `0.10.6` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/sha1/0.10.6/download) |
| `sha2` | `0.10.9` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/sha2/0.10.9/download) |
| `sharded-slab` | `0.1.7` | `MIT` | `MIT` | Eliza Weisman <eliza@buoyant.io> | [source](https://crates.io/api/v1/crates/sharded-slab/0.1.7/download) |
| `shlex` | `1.3.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | comex <comexk@gmail.com>; Fenhl <fenhl@fenhl.net>; Adrian Taylor <adetaylor@chromium.org>; Alex Touchet <alextouchet@outlook.com>; Daniel Parks <dp+git@oxidized.org>; Garrett Berg <googberg@gmail.com> | [source](https://crates.io/api/v1/crates/shlex/1.3.0/download) |
| `signature` | `2.2.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/signature/2.2.0/download) |
| `simd-adler32` | `0.3.7` | `MIT` | `MIT` | Marvin Countryman <me@maar.vin> | [source](https://crates.io/api/v1/crates/simd-adler32/0.3.7/download) |
| `similar` | `2.6.0` | `Apache-2.0` | `Apache-2.0` | Armin Ronacher <armin.ronacher@active-4.com>; Pierre-Étienne Meunier <pe@pijul.org>; Brandon Williams <bwilliams.eng@gmail.com> | [source](https://crates.io/api/v1/crates/similar/2.6.0/download) |
| `similar-asserts` | `1.7.0` | `Apache-2.0` | `Apache-2.0` | Armin Ronacher <armin.ronacher@active-4.com> | [source](https://crates.io/api/v1/crates/similar-asserts/1.7.0/download) |
| `siphasher` | `1.0.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Frank Denis <github@pureftpd.org> | [source](https://crates.io/api/v1/crates/siphasher/1.0.1/download) |
| `sketches-ddsketch` | `0.4.0` | `Apache-2.0` | `Apache-2.0` | Mike Heffner <mikeh@fesnel.com> | [source](https://crates.io/api/v1/crates/sketches-ddsketch/0.4.0/download) |
| `slab` | `0.4.9` | `MIT` | `MIT` | Carl Lerche <me@carllerche.com> | [source](https://crates.io/api/v1/crates/slab/0.4.9/download) |
| `smallvec` | `1.13.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Servo Project Developers | [source](https://crates.io/api/v1/crates/smallvec/1.13.2/download) |
| `smawk` | `0.3.2` | `MIT` | `MIT` | Martin Geisler <martin@geisler.net> | [source](https://crates.io/api/v1/crates/smawk/0.3.2/download) |
| `socket2` | `0.6.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alex Crichton <alex@alexcrichton.com>; Thomas de Zeeuw <thomasdezeeuw@gmail.com> | [source](https://crates.io/api/v1/crates/socket2/0.6.0/download) |
| `spki` | `0.7.3` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/spki/0.7.3/download) |
| `stable_deref_trait` | `1.2.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Robert Grosse <n210241048576@gmail.com> | [source](https://crates.io/api/v1/crates/stable_deref_trait/1.2.0/download) |
| `static_assertions` | `1.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Nikolai Vazquez | [source](https://crates.io/api/v1/crates/static_assertions/1.1.0/download) |
| `stream_assert` | `0.1.1` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/stream_assert/0.1.1/download) |
| `string_cache` | `0.9.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Servo Project Developers | [source](https://crates.io/api/v1/crates/string_cache/0.9.0/download) |
| `string_cache_codegen` | `0.6.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The Servo Project Developers | [source](https://crates.io/api/v1/crates/string_cache_codegen/0.6.1/download) |
| `strsim` | `0.11.1` | `MIT` | `MIT` | Danny Guo <danny@dannyguo.com>; maxbachmann <oss@maxbachmann.de> | [source](https://crates.io/api/v1/crates/strsim/0.11.1/download) |
| `subtle` | `2.6.1` | `BSD-3-Clause` | `BSD-3-Clause` | Isis Lovecruft <isis@patternsinthevoid.net>; Henry de Valence <hdevalence@hdevalence.ca> | [source](https://crates.io/api/v1/crates/subtle/2.6.1/download) |
| `syn` | `2.0.118` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/syn/2.0.118/download) |
| `sync_wrapper` | `1.0.1` | `Apache-2.0` | `Apache-2.0` | Actyx AG <developer@actyx.io> | [source](https://crates.io/api/v1/crates/sync_wrapper/1.0.1/download) |
| `synstructure` | `0.13.1` | `MIT` | `MIT` | Nika Layzell <nika@thelayzells.com> | [source](https://crates.io/api/v1/crates/synstructure/0.13.1/download) |
| `tantivy` | `0.26.1` | `MIT` | `MIT` | Paul Masurel <paul.masurel@gmail.com> | [source](https://crates.io/api/v1/crates/tantivy/0.26.1/download) |
| `tantivy-bitpacker` | `0.10.0` | `MIT` | `MIT` | Paul Masurel <paul.masurel@gmail.com> | [source](https://crates.io/api/v1/crates/tantivy-bitpacker/0.10.0/download) |
| `tantivy-columnar` | `0.7.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/tantivy-columnar/0.7.0/download) |
| `tantivy-common` | `0.11.0` | `MIT` | `MIT` | Paul Masurel <paul@quickwit.io>; Pascal Seitz <pascal@quickwit.io> | [source](https://crates.io/api/v1/crates/tantivy-common/0.11.0/download) |
| `tantivy-fst` | `0.5.0` | `Unlicense OR MIT` | `Unlicense OR MIT` | Andrew Gallant <jamslam@gmail.com> | [source](https://crates.io/api/v1/crates/tantivy-fst/0.5.0/download) |
| `tantivy-query-grammar` | `0.26.0` | `MIT` | `MIT` | Paul Masurel <paul.masurel@gmail.com> | [source](https://crates.io/api/v1/crates/tantivy-query-grammar/0.26.0/download) |
| `tantivy-sstable` | `0.7.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/tantivy-sstable/0.7.0/download) |
| `tantivy-stacker` | `0.7.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/tantivy-stacker/0.7.0/download) |
| `tantivy-tokenizer-api` | `0.7.0` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/tantivy-tokenizer-api/0.7.0/download) |
| `tempfile` | `3.23.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Steven Allen <steven@stebalien.com>; The Rust Project Developers; Ashley Mannix <ashleymannix@live.com.au>; Jason White <me@jasonwhite.io> | [source](https://crates.io/api/v1/crates/tempfile/3.23.0/download) |
| `tendril` | `0.5.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Keegan McAllister <mcallister.keegan@gmail.com>; Simon Sapin <simon.sapin@exyr.org>; Chris Morgan <me@chrismorgan.info> | [source](https://crates.io/api/v1/crates/tendril/0.5.0/download) |
| `textwrap` | `0.16.2` | `MIT` | `MIT` | Martin Geisler <martin@geisler.net> | [source](https://crates.io/api/v1/crates/textwrap/0.16.2/download) |
| `thiserror` | `1.0.63` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/thiserror/1.0.63/download) |
| `thiserror` | `2.0.18` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/thiserror/2.0.18/download) |
| `thiserror-impl` | `1.0.63` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/thiserror-impl/1.0.63/download) |
| `thiserror-impl` | `2.0.18` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/thiserror-impl/2.0.18/download) |
| `thread_local` | `1.1.8` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Amanieu d'Antras <amanieu@gmail.com> | [source](https://crates.io/api/v1/crates/thread_local/1.1.8/download) |
| `time` | `0.3.47` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jacob Pratt <open-source@jhpratt.dev>; Time contributors | [source](https://crates.io/api/v1/crates/time/0.3.47/download) |
| `time-core` | `0.1.8` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jacob Pratt <open-source@jhpratt.dev>; Time contributors | [source](https://crates.io/api/v1/crates/time-core/0.1.8/download) |
| `time-macros` | `0.2.27` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jacob Pratt <open-source@jhpratt.dev>; Time contributors | [source](https://crates.io/api/v1/crates/time-macros/0.2.27/download) |
| `tinystr` | `0.7.6` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/tinystr/0.7.6/download) |
| `tinyvec` | `1.8.0` | `Zlib OR Apache-2.0 OR MIT` | `Zlib OR Apache-2.0 OR MIT` | Lokathor <zefria@gmail.com> | [source](https://crates.io/api/v1/crates/tinyvec/1.8.0/download) |
| `tinyvec_macros` | `0.1.1` | `MIT OR Apache-2.0 OR Zlib` | `MIT OR Apache-2.0 OR Zlib` | Soveu <marx.tomasz@gmail.com> | [source](https://crates.io/api/v1/crates/tinyvec_macros/0.1.1/download) |
| `tokio` | `1.48.0` | `MIT` | `MIT` | Tokio Contributors <team@tokio.rs> | [source](https://crates.io/api/v1/crates/tokio/1.48.0/download) |
| `tokio-macros` | `2.6.0` | `MIT` | `MIT` | Tokio Contributors <team@tokio.rs> | [source](https://crates.io/api/v1/crates/tokio-macros/2.6.0/download) |
| `tokio-rustls` | `0.26.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/tokio-rustls/0.26.0/download) |
| `tokio-stream` | `0.1.17` | `MIT` | `MIT` | Tokio Contributors <team@tokio.rs> | [source](https://crates.io/api/v1/crates/tokio-stream/0.1.17/download) |
| `tokio-test` | `0.4.4` | `MIT` | `MIT` | Tokio Contributors <team@tokio.rs> | [source](https://crates.io/api/v1/crates/tokio-test/0.4.4/download) |
| `tokio-util` | `0.7.17` | `MIT` | `MIT` | Tokio Contributors <team@tokio.rs> | [source](https://crates.io/api/v1/crates/tokio-util/0.7.17/download) |
| `toml` | `0.9.7` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/toml/0.9.7/download) |
| `toml` | `1.1.2+spec-1.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/toml/1.1.2%2Bspec-1.1.0/download) |
| `toml_datetime` | `0.7.2` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/toml_datetime/0.7.2/download) |
| `toml_datetime` | `1.1.1+spec-1.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/toml_datetime/1.1.1%2Bspec-1.1.0/download) |
| `toml_edit` | `0.25.6+spec-1.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/toml_edit/0.25.6%2Bspec-1.1.0/download) |
| `toml_parser` | `1.1.2+spec-1.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/toml_parser/1.1.2%2Bspec-1.1.0/download) |
| `toml_writer` | `1.0.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/toml_writer/1.0.4/download) |
| `tower` | `0.5.2` | `MIT` | `MIT` | Tower Maintainers <team@tower-rs.com> | [source](https://crates.io/api/v1/crates/tower/0.5.2/download) |
| `tower-http` | `0.6.8` | `MIT` | `MIT` | Tower Maintainers <team@tower-rs.com> | [source](https://crates.io/api/v1/crates/tower-http/0.6.8/download) |
| `tower-layer` | `0.3.3` | `MIT` | `MIT` | Tower Maintainers <team@tower-rs.com> | [source](https://crates.io/api/v1/crates/tower-layer/0.3.3/download) |
| `tower-service` | `0.3.3` | `MIT` | `MIT` | Tower Maintainers <team@tower-rs.com> | [source](https://crates.io/api/v1/crates/tower-service/0.3.3/download) |
| `tracing` | `0.1.41` | `MIT` | `MIT` | Eliza Weisman <eliza@buoyant.io>; Tokio Contributors <team@tokio.rs> | [source](https://github.com/tokio-rs/tracing/commit/20f5b3d8ba057ca9c4ae00ad30dda3dce8a71c05) |
| `tracing-appender` | `0.2.3` | `MIT` | `MIT` | Zeki Sherif <zekshi@amazon.com>; Tokio Contributors <team@tokio.rs> | [source](https://github.com/tokio-rs/tracing/commit/20f5b3d8ba057ca9c4ae00ad30dda3dce8a71c05) |
| `tracing-attributes` | `0.1.30` | `MIT` | `MIT` | Tokio Contributors <team@tokio.rs>; Eliza Weisman <eliza@buoyant.io>; David Barsky <dbarsky@amazon.com> | [source](https://github.com/tokio-rs/tracing/commit/20f5b3d8ba057ca9c4ae00ad30dda3dce8a71c05) |
| `tracing-core` | `0.1.34` | `MIT` | `MIT` | Tokio Contributors <team@tokio.rs> | [source](https://github.com/tokio-rs/tracing/commit/20f5b3d8ba057ca9c4ae00ad30dda3dce8a71c05) |
| `tracing-subscriber` | `0.3.20` | `MIT` | `MIT` | Eliza Weisman <eliza@buoyant.io>; David Barsky <me@davidbarsky.com>; Tokio Contributors <team@tokio.rs> | [source](https://github.com/tokio-rs/tracing/commit/20f5b3d8ba057ca9c4ae00ad30dda3dce8a71c05) |
| `try-lock` | `0.2.5` | `MIT` | `MIT` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/try-lock/0.2.5/download) |
| `typeid` | `1.0.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/typeid/1.0.3/download) |
| `typenum` | `1.17.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Paho Lurie-Gregg <paho@paholg.com>; Andre Bogus <bogusandre@gmail.com> | [source](https://crates.io/api/v1/crates/typenum/1.17.0/download) |
| `typetag` | `0.2.22` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/typetag/0.2.22/download) |
| `typetag-impl` | `0.2.22` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/typetag-impl/0.2.22/download) |
| `typewit` | `1.14.2` | `Zlib` | `Zlib` | rodrimati1992 <rodrimatt1985@gmail.com> | [source](https://crates.io/api/v1/crates/typewit/1.14.2/download) |
| `ucd-trie` | `0.1.7` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Andrew Gallant <jamslam@gmail.com> | [source](https://crates.io/api/v1/crates/ucd-trie/0.1.7/download) |
| `ulid` | `1.1.4` | `MIT` | `MIT` | dylanhart <dylan96hart@gmail.com> | [source](https://crates.io/api/v1/crates/ulid/1.1.4/download) |
| `unarray` | `0.1.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/unarray/0.1.4/download) |
| `unicase` | `2.7.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/unicase/2.7.0/download) |
| `unicode-ident` | `1.0.22` | `(MIT OR Apache-2.0) AND Unicode-3.0` | `(MIT OR Apache-2.0) AND Unicode-3.0` | David Tolnay <dtolnay@gmail.com> | [source](https://crates.io/api/v1/crates/unicode-ident/1.0.22/download) |
| `unicode-normalization` | `0.1.25` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | kwantam <kwantam@gmail.com>; Manish Goregaokar <manishsmail@gmail.com> | [source](https://crates.io/api/v1/crates/unicode-normalization/0.1.25/download) |
| `unicode-segmentation` | `1.12.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | kwantam <kwantam@gmail.com>; Manish Goregaokar <manishsmail@gmail.com> | [source](https://crates.io/api/v1/crates/unicode-segmentation/1.12.0/download) |
| `uniffi` | `0.31.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `uniffi_bindgen` | `0.31.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `uniffi_build` | `0.31.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `uniffi_core` | `0.31.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `uniffi_internal_macros` | `0.31.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `uniffi_macros` | `0.31.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `uniffi_meta` | `0.31.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `uniffi_pipeline` | `0.31.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `uniffi_udl` | `0.31.0` | `MPL-2.0` | `MPL-2.0` | Upstream project contributors; see immutable source | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `universal-hash` | `0.5.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | RustCrypto Developers | [source](https://crates.io/api/v1/crates/universal-hash/0.5.1/download) |
| `untrusted` | `0.7.1` | `ISC` | `ISC` | Brian Smith <brian@briansmith.org> | [source](https://crates.io/api/v1/crates/untrusted/0.7.1/download) |
| `untrusted` | `0.9.0` | `ISC` | `ISC` | Brian Smith <brian@briansmith.org> | [source](https://crates.io/api/v1/crates/untrusted/0.9.0/download) |
| `url` | `2.5.7` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The rust-url developers | [source](https://crates.io/api/v1/crates/url/2.5.7/download) |
| `urlencoding` | `2.1.3` | `MIT` | `MIT` | Kornel <kornel@geekhood.net>; Bertram Truong <b@bertramtruong.com> | [source](https://crates.io/api/v1/crates/urlencoding/2.1.3/download) |
| `utf-8` | `0.7.6` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Simon Sapin <simon.sapin@exyr.org> | [source](https://crates.io/api/v1/crates/utf-8/0.7.6/download) |
| `utf16_iter` | `1.0.5` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Henri Sivonen <hsivonen@hsivonen.fi> | [source](https://crates.io/api/v1/crates/utf16_iter/1.0.5/download) |
| `utf8-ranges` | `1.0.5` | `Unlicense OR MIT` | `Unlicense OR MIT` | Andrew Gallant <jamslam@gmail.com> | [source](https://crates.io/api/v1/crates/utf8-ranges/1.0.5/download) |
| `utf8_iter` | `1.0.4` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Henri Sivonen <hsivonen@hsivonen.fi> | [source](https://crates.io/api/v1/crates/utf8_iter/1.0.4/download) |
| `uuid` | `1.18.1` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Ashley Mannix<ashleymannix@live.com.au>; Dylan DPC<dylan.dpc@gmail.com>; Hunar Roop Kahlon<hunar.roop@gmail.com> | [source](https://crates.io/api/v1/crates/uuid/1.18.1/download) |
| `vcpkg` | `0.2.15` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jim McGrath <jimmc2@gmail.com> | [source](https://crates.io/api/v1/crates/vcpkg/0.2.15/download) |
| `vergen` | `9.0.6` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jason Ozias <jason.g.ozias@gmail.com> | [source](https://crates.io/api/v1/crates/vergen/9.0.6/download) |
| `vergen-gitcl` | `1.0.8` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jason Ozias <jason.g.ozias@gmail.com> | [source](https://crates.io/api/v1/crates/vergen-gitcl/1.0.8/download) |
| `vergen-lib` | `0.1.6` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Jason Ozias <jason.g.ozias@gmail.com> | [source](https://crates.io/api/v1/crates/vergen-lib/0.1.6/download) |
| `version_check` | `0.9.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Sergio Benitez <sb@sergio.bz> | [source](https://crates.io/api/v1/crates/version_check/0.9.4/download) |
| `vodozemac` | `0.10.0` | `Apache-2.0` | `Apache-2.0` | Damir Jelić <poljar@termina.org.uk>; Denis Kasak <dkasak@termina.org.uk> | [source](https://crates.io/api/v1/crates/vodozemac/0.10.0/download) |
| `want` | `0.3.1` | `MIT` | `MIT` | Sean McArthur <sean@seanmonstar.com> | [source](https://crates.io/api/v1/crates/want/0.3.1/download) |
| `wasm-bindgen` | `0.2.114` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The wasm-bindgen Developers | [source](https://crates.io/api/v1/crates/wasm-bindgen/0.2.114/download) |
| `wasm-bindgen-futures` | `0.4.64` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The wasm-bindgen Developers | [source](https://crates.io/api/v1/crates/wasm-bindgen-futures/0.4.64/download) |
| `wasm-bindgen-macro` | `0.2.114` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The wasm-bindgen Developers | [source](https://crates.io/api/v1/crates/wasm-bindgen-macro/0.2.114/download) |
| `wasm-bindgen-macro-support` | `0.2.114` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The wasm-bindgen Developers | [source](https://crates.io/api/v1/crates/wasm-bindgen-macro-support/0.2.114/download) |
| `wasm-bindgen-shared` | `0.2.114` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The wasm-bindgen Developers | [source](https://crates.io/api/v1/crates/wasm-bindgen-shared/0.2.114/download) |
| `wasm-bindgen-test` | `0.3.64` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The wasm-bindgen Developers | [source](https://crates.io/api/v1/crates/wasm-bindgen-test/0.3.64/download) |
| `wasm-bindgen-test-macro` | `0.3.64` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The wasm-bindgen Developers | [source](https://crates.io/api/v1/crates/wasm-bindgen-test-macro/0.3.64/download) |
| `wasm-bindgen-test-shared` | `0.2.114` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The wasm-bindgen Developers | [source](https://crates.io/api/v1/crates/wasm-bindgen-test-shared/0.2.114/download) |
| `web-time` | `1.1.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/web-time/1.1.0/download) |
| `web_atoms` | `0.2.3` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | The html5ever Project Developers | [source](https://crates.io/api/v1/crates/web_atoms/0.2.3/download) |
| `weedle2` | `5.0.0` | `MIT` | `MIT` | Sharad Chand <sharad.d.chand@gmail.com>; Jan-Erik Rediger <jrediger@mozilla.com> | [source](https://github.com/mozilla/uniffi-rs/commit/e5f4821410bea19e71984ea5e06a7bc8b11ed9e5) |
| `wildmatch` | `2.6.1` | `MIT` | `MIT` | Armin Becher <armin.becher@gmail.com> | [source](https://crates.io/api/v1/crates/wildmatch/2.6.1/download) |
| `winnow` | `0.7.13` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/winnow/0.7.13/download) |
| `winnow` | `1.0.1` | `MIT` | `MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/winnow/1.0.1/download) |
| `wiremock` | `0.6.5` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Luca Palmieri <rust@lpalmieri.com> | [source](https://crates.io/api/v1/crates/wiremock/0.6.5/download) |
| `write16` | `1.0.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | Upstream project contributors; see immutable source | [source](https://crates.io/api/v1/crates/write16/1.0.0/download) |
| `writeable` | `0.5.5` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/writeable/0.5.5/download) |
| `x25519-dalek` | `2.0.1` | `BSD-3-Clause` | `BSD-3-Clause` | Isis Lovecruft <isis@patternsinthevoid.net>; DebugSteven <debugsteven@gmail.com>; Henry de Valence <hdevalence@hdevalence.ca> | [source](https://crates.io/api/v1/crates/x25519-dalek/2.0.1/download) |
| `x509-parser` | `0.18.1` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Pierre Chifflier <chifflier@wzdftpd.net> | [source](https://crates.io/api/v1/crates/x509-parser/0.18.1/download) |
| `xxhash-rust` | `0.8.11` | `BSL-1.0` | `BSL-1.0` | Douman <douman@gmx.se> | [source](https://crates.io/api/v1/crates/xxhash-rust/0.8.11/download) |
| `yasna` | `0.6.0` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Masaki Hara <ackie.h.gmai@gmail.com> | [source](https://crates.io/api/v1/crates/yasna/0.6.0/download) |
| `yoke` | `0.7.5` | `Unicode-3.0` | `Unicode-3.0` | Manish Goregaokar <manishsmail@gmail.com> | [source](https://crates.io/api/v1/crates/yoke/0.7.5/download) |
| `yoke-derive` | `0.7.5` | `Unicode-3.0` | `Unicode-3.0` | Manish Goregaokar <manishsmail@gmail.com> | [source](https://crates.io/api/v1/crates/yoke-derive/0.7.5/download) |
| `zerofrom` | `0.1.5` | `Unicode-3.0` | `Unicode-3.0` | Manish Goregaokar <manishsmail@gmail.com> | [source](https://crates.io/api/v1/crates/zerofrom/0.1.5/download) |
| `zerofrom-derive` | `0.1.5` | `Unicode-3.0` | `Unicode-3.0` | Manish Goregaokar <manishsmail@gmail.com> | [source](https://crates.io/api/v1/crates/zerofrom-derive/0.1.5/download) |
| `zeroize` | `1.9.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | The RustCrypto Project Developers | [source](https://crates.io/api/v1/crates/zeroize/1.9.0/download) |
| `zeroize_derive` | `1.5.0` | `Apache-2.0 OR MIT` | `Apache-2.0 OR MIT` | The RustCrypto Project Developers | [source](https://crates.io/api/v1/crates/zeroize_derive/1.5.0/download) |
| `zerovec` | `0.10.4` | `Unicode-3.0` | `Unicode-3.0` | The ICU4X Project Developers | [source](https://crates.io/api/v1/crates/zerovec/0.10.4/download) |
| `zerovec-derive` | `0.10.3` | `Unicode-3.0` | `Unicode-3.0` | Manish Goregaokar <manishsmail@gmail.com> | [source](https://crates.io/api/v1/crates/zerovec-derive/0.10.3/download) |
| `zstd` | `0.13.3` | `MIT` | `MIT` | Alexandre Bury <alexandre.bury@gmail.com> | [source](https://crates.io/api/v1/crates/zstd/0.13.3/download) |
| `zstd-safe` | `7.2.4` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alexandre Bury <alexandre.bury@gmail.com> | [source](https://crates.io/api/v1/crates/zstd-safe/7.2.4/download) |
| `zstd-sys` | `2.0.15+zstd.1.5.7` | `MIT OR Apache-2.0` | `MIT OR Apache-2.0` | Alexandre Bury <alexandre.bury@gmail.com> | [source](https://crates.io/api/v1/crates/zstd-sys/2.0.15%2Bzstd.1.5.7/download) |
| `zxcvbn` | `3.1.1` | `MIT` | `MIT` | Josh Holmer <jholmer.in@gmail.com> | [source](https://github.com/shssoichiro/zxcvbn-rs/commit/4e8e784b23541d118800df84feedf8160879d1af) |

## Repository assets

- `Resources/ZenithOSIcon.icns` is rendered from the project-owned Zenith vector design preserved in `Resources/ZenithOSIcon.svg` and `scripts/generate_zenith_icon.py`. The generator, SVG, and generated icon are distributed under AGPL-3.0-or-later; see `docs/asset-provenance.md`.
- `docs/evidence/issue-2/native-shell.png` is a synthetic Hypha screenshot generated by the project and distributed under the repository’s AGPL-3.0-or-later terms.

If a new binary, source copy, font, image, fixture, or other third-party asset is added, update this file and include every required license or notice before merge.
