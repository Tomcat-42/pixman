const std = @import("std");

const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.builtin.LinkMode, "linkage", "Library linkage type") orelse .static;

    const upstream = b.dependency("upstream", .{});
    const version: std.SemanticVersion = try .parse(manifest.version);
    const src = upstream.path("pixman");

    const arch = target.result.cpu.arch;
    const os = target.result.os.tag;
    const is_posix = os != .windows;
    const is_macos = os == .macos;
    const is_x86 = arch == .x86_64 or arch == .x86;
    const is_arm32 = arch == .arm;

    const feat = target.result.cpu.features;
    const mmx = is_x86 and std.Target.x86.featureSetHas(feat, .mmx);
    const sse2 = is_x86 and std.Target.x86.featureSetHas(feat, .sse2);
    const ssse3 = is_x86 and std.Target.x86.featureSetHas(feat, .ssse3);
    const vmx = switch (arch) {
        .powerpc, .powerpc64, .powerpc64le => true,
        else => false,
    };
    const a64_neon = arch == .aarch64;
    const loongson_mmi = arch == .mips64 or arch == .mips64el;
    const mips_dspr2 = switch (arch) {
        .mips, .mipsel, .mips64, .mips64el => true,
        else => false,
    };
    const rvv = arch == .riscv64;

    const config_h = b.addConfigHeader(.{ .style = .blank, .include_path = "pixman-config.h" }, .{
        .PACKAGE = "foo",
        .SIZEOF_LONG = @as(i64, if (!is_posix) 4 else if (target.result.ptrBitWidth() == 64) 8 else 4),
        .WORDS_BIGENDIAN = opt(arch.endian() == .big),
        .USE_GCC_INLINE_ASM = opt(is_posix),
        .TOOLCHAIN_SUPPORTS_ATTRIBUTE_CONSTRUCTOR = opt(is_posix),
        .TOOLCHAIN_SUPPORTS_ATTRIBUTE_DESTRUCTOR = opt(is_posix),
        .HAVE_FLOAT128 = opt(arch == .x86_64 and is_posix),
        .HAVE_GCC_VECTOR_EXTENSIONS = opt(is_posix),
        .HAVE_BUILTIN_CLZ = opt(is_posix),
        .USE_LOONGSON_MMI = opt(loongson_mmi),
        .USE_X86_MMX = opt(mmx),
        .USE_SSE2 = opt(sse2),
        .USE_SSSE3 = opt(ssse3),
        .USE_VMX = opt(vmx),
        .USE_ARM_SIMD = opt(is_arm32),
        .USE_ARM_NEON = opt(is_arm32),
        .USE_ARM_A64_NEON = opt(a64_neon),
        .USE_MIPS_DSPR2 = opt(mips_dspr2),
        .USE_RVV = opt(rvv),
        .ASM_HAVE_FUNC_DIRECTIVE = opt(is_posix and !is_macos and (is_x86 or is_arm32)),
        .ASM_HAVE_SYNTAX_UNIFIED = opt(is_posix and is_arm32),
        .ASM_LEADING_UNDERSCORE = opt(is_macos),
        .HAVE_PTHREADS = opt(is_posix),
        .HAVE_SIGACTION = opt(is_posix),
        .HAVE_ALARM = opt(is_posix),
        .HAVE_MPROTECT = opt(is_posix),
        .HAVE_GETPAGESIZE = opt(is_posix),
        .HAVE_MMAP = opt(is_posix),
        .HAVE_GETTIMEOFDAY = opt(is_posix),
        .HAVE_POSIX_MEMALIGN = opt(is_posix),
        .HAVE_SYS_MMAN_H = opt(is_posix),
        .HAVE_FENV_H = opt(is_posix),
        .HAVE_UNISTD_H = opt(is_posix),
        .HAVE_FEDIVBYZERO = opt(is_posix),
    });

    const version_h = b.addConfigHeader(.{
        .style = .{ .autoconf_at = src.path(b, "pixman-version.h.in") },
        .include_path = "pixman-version.h",
    }, .{
        .PIXMAN_VERSION_MAJOR = @as(i64, @intCast(version.major)),
        .PIXMAN_VERSION_MINOR = @as(i64, @intCast(version.minor)),
        .PIXMAN_VERSION_MICRO = @as(i64, @intCast(version.patch)),
    });

    const flags: []const []const u8 = &.{
        "-DHAVE_CONFIG_H",
        "-fno-strict-aliasing",
        "-fvisibility=hidden",
        if (is_posix) "-DTLS=__thread" else "-DTLS=__declspec(thread)",
    };

    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    mod.addConfigHeader(config_h);
    mod.addConfigHeader(version_h);
    mod.addIncludePath(src);
    mod.addCSourceFiles(.{ .root = src, .files = core_sources, .flags = flags });

    const a = b.allocator;
    if (loongson_mmi) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-mmx.c"}, .flags = cf(a, flags, &.{"-mloongson-mmi"}) });
    if (mmx) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-mmx.c"}, .flags = cf(a, flags, &.{ "-mmmx", "-Winline" }) });
    if (sse2) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-sse2.c"}, .flags = cf(a, flags, &.{ "-msse2", "-Winline" }) });
    if (ssse3) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-ssse3.c"}, .flags = cf(a, flags, &.{ "-mssse3", "-Winline" }) });
    if (vmx) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-vmx.c"}, .flags = cf(a, flags, &.{ "-maltivec", "-mabi=altivec" }) });
    if (is_arm32) mod.addCSourceFiles(.{ .root = src, .files = &.{ "pixman-arm-simd.c", "pixman-arm-simd-asm.S", "pixman-arm-simd-asm-scaled.S", "pixman-arm-neon.c", "pixman-arm-neon-asm.S", "pixman-arm-neon-asm-bilinear.S" }, .flags = flags });
    if (a64_neon) mod.addCSourceFiles(.{ .root = src, .files = &.{ "pixman-arm-neon.c", "pixman-arma64-neon-asm.S", "pixman-arma64-neon-asm-bilinear.S" }, .flags = flags });
    if (mips_dspr2) mod.addCSourceFiles(.{ .root = src, .files = &.{ "pixman-mips-dspr2.c", "pixman-mips-dspr2-asm.S", "pixman-mips-memcpy-asm.S" }, .flags = cf(a, flags, &.{"-mdspr2"}) });
    if (rvv) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-rvv.c"}, .flags = cf(a, flags, &.{"-march=rv64gcv1p0"}) });

    const lib = b.addLibrary(.{
        .name = "pixman-1",
        .root_module = mod,
        .linkage = linkage,
        .version = .{ .major = 0, .minor = version.minor, .patch = version.patch },
    });
    lib.installHeader(src.path(b, "pixman.h"), "pixman.h");
    lib.installConfigHeader(version_h);
    b.installArtifact(lib);
}

inline fn cf(a: std.mem.Allocator, base: []const []const u8, extra: []const []const u8) []const []const u8 {
    const r = a.alloc([]const u8, base.len + extra.len) catch @panic("OOM");
    @memcpy(r[0..base.len], base);
    @memcpy(r[base.len..], extra);
    return r;
}

inline fn opt(v: bool) ?bool {
    return if (v) true else null;
}

const core_sources: []const []const u8 = &.{
    "pixman.c",                "pixman-access.c",           "pixman-access-accessors.c",
    "pixman-arm.c",            "pixman-bits-image.c",       "pixman-combine32.c",
    "pixman-combine-float.c",  "pixman-conical-gradient.c", "pixman-edge.c",
    "pixman-edge-accessors.c", "pixman-fast-path.c",        "pixman-filter.c",
    "pixman-glyph.c",          "pixman-general.c",          "pixman-gradient-walker.c",
    "pixman-image.c",          "pixman-implementation.c",   "pixman-linear-gradient.c",
    "pixman-matrix.c",         "pixman-mips.c",             "pixman-noop.c",
    "pixman-ppc.c",            "pixman-radial-gradient.c",  "pixman-region16.c",
    "pixman-region32.c",       "pixman-region64f.c",        "pixman-riscv.c",
    "pixman-solid-fill.c",     "pixman-timer.c",            "pixman-trap.c",
    "pixman-utils.c",          "pixman-x86.c",
};
