const std = @import("std");
const LinkMode = std.builtin.LinkMode;

const manifest = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const arch = target.result.cpu.arch;
    const os = target.result.os.tag;

    const options = .{
        .linkage = b.option(LinkMode, "linkage", "Library linkage type") orelse
            .static,
    };

    const upstream = b.dependency("pixman_c", .{});
    const version: std.SemanticVersion = try .parse(manifest.version);
    const src = upstream.path("pixman");

    const feat = target.result.cpu.features;
    const mmx = (arch == .x86_64 or arch == .x86) and std.Target.x86.featureSetHas(feat, .mmx);
    const sse2 = (arch == .x86_64 or arch == .x86) and std.Target.x86.featureSetHas(feat, .sse2);
    const ssse3 = (arch == .x86_64 or arch == .x86) and std.Target.x86.featureSetHas(feat, .ssse3);
    const vmx = switch (arch) {
        .powerpc, .powerpc64, .powerpc64le => true,
        else => false,
    };
    const mips_dspr2 = switch (arch) {
        .mips, .mipsel, .mips64, .mips64el => true,
        else => false,
    };

    const config_h = b.addConfigHeader(.{ .style = .blank, .include_path = "pixman-config.h" }, .{
        .PACKAGE = "foo",
        .SIZEOF_LONG = @as(i64, if (os == .windows) 4 else if (target.result.ptrBitWidth() == 64) 8 else 4),
        .WORDS_BIGENDIAN = opt(arch.endian() == .big),
        .USE_GCC_INLINE_ASM = opt(os != .windows),
        .TOOLCHAIN_SUPPORTS_ATTRIBUTE_CONSTRUCTOR = opt(os != .windows),
        .TOOLCHAIN_SUPPORTS_ATTRIBUTE_DESTRUCTOR = opt(os != .windows),
        .HAVE_FLOAT128 = opt(arch == .x86_64 and os != .windows),
        .HAVE_GCC_VECTOR_EXTENSIONS = opt(os != .windows),
        .HAVE_BUILTIN_CLZ = opt(os != .windows),
        .USE_LOONGSON_MMI = opt(arch == .mips64 or arch == .mips64el),
        .USE_X86_MMX = opt(mmx),
        .USE_SSE2 = opt(sse2),
        .USE_SSSE3 = opt(ssse3),
        .USE_VMX = opt(vmx),
        .USE_ARM_SIMD = opt(arch == .arm),
        .USE_ARM_NEON = opt(arch == .arm),
        .USE_ARM_A64_NEON = opt(arch == .aarch64),
        .USE_MIPS_DSPR2 = opt(mips_dspr2),
        .USE_RVV = opt(arch == .riscv64),
        .ASM_HAVE_FUNC_DIRECTIVE = opt(os != .windows and os != .macos and (arch == .x86_64 or arch == .x86 or arch == .arm)),
        .ASM_HAVE_SYNTAX_UNIFIED = opt(os != .windows and arch == .arm),
        .ASM_LEADING_UNDERSCORE = opt(os == .macos),
        .HAVE_PTHREADS = opt(os != .windows),
        .HAVE_SIGACTION = opt(os != .windows),
        .HAVE_ALARM = opt(os != .windows),
        .HAVE_MPROTECT = opt(os != .windows),
        .HAVE_GETPAGESIZE = opt(os != .windows),
        .HAVE_MMAP = opt(os != .windows),
        .HAVE_GETTIMEOFDAY = opt(os != .windows),
        .HAVE_POSIX_MEMALIGN = opt(os != .windows),
        .HAVE_SYS_MMAN_H = opt(os != .windows),
        .HAVE_FENV_H = opt(os != .windows),
        .HAVE_UNISTD_H = opt(os != .windows),
        .HAVE_FEDIVBYZERO = opt(os != .windows),
    });

    const version_h = b.addConfigHeader(.{
        .style = .{ .autoconf_at = upstream.path(b.pathJoin(&.{ "pixman", "pixman-version.h.in" })) },
        .include_path = "pixman-version.h",
    }, .{
        .PIXMAN_VERSION_MAJOR = @as(i64, @intCast(version.major)),
        .PIXMAN_VERSION_MINOR = @as(i64, @intCast(version.minor)),
        .PIXMAN_VERSION_MICRO = @as(i64, @intCast(version.patch)),
    });

    const mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    mod.addConfigHeader(config_h);
    mod.addConfigHeader(version_h);
    mod.addIncludePath(src);
    mod.addCMacro("HAVE_CONFIG_H", "");
    mod.addCMacro("TLS", if (os != .windows) "__thread" else "__declspec(thread)");
    mod.addCSourceFiles(.{
        .root = src,
        .files = srcs,
        .flags = &flags,
    });

    if (arch == .mips64 or arch == .mips64el) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-mmx.c"}, .flags = &(flags ++ .{"-mloongson-mmi"}) });
    if (mmx) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-mmx.c"}, .flags = &(flags ++ .{ "-mmmx", "-Winline" }) });
    if (sse2) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-sse2.c"}, .flags = &(flags ++ .{ "-msse2", "-Winline" }) });
    if (ssse3) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-ssse3.c"}, .flags = &(flags ++ .{ "-mssse3", "-Winline" }) });
    if (vmx) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-vmx.c"}, .flags = &(flags ++ .{ "-maltivec", "-mabi=altivec" }) });
    if (arch == .arm) mod.addCSourceFiles(.{ .root = src, .files = &.{ "pixman-arm-simd.c", "pixman-arm-simd-asm.S", "pixman-arm-simd-asm-scaled.S", "pixman-arm-neon.c", "pixman-arm-neon-asm.S", "pixman-arm-neon-asm-bilinear.S" }, .flags = &flags });
    if (arch == .aarch64) mod.addCSourceFiles(.{ .root = src, .files = &.{ "pixman-arm-neon.c", "pixman-arma64-neon-asm.S", "pixman-arma64-neon-asm-bilinear.S" }, .flags = &flags });
    if (mips_dspr2) mod.addCSourceFiles(.{ .root = src, .files = &.{ "pixman-mips-dspr2.c", "pixman-mips-dspr2-asm.S", "pixman-mips-memcpy-asm.S" }, .flags = &(flags ++ .{"-mdspr2"}) });
    if (arch == .riscv64) mod.addCSourceFiles(.{ .root = src, .files = &.{"pixman-rvv.c"}, .flags = &(flags ++ .{"-march=rv64gcv1p0"}) });

    const lib = b.addLibrary(.{
        .name = "pixman-1",
        .root_module = mod,
        .linkage = options.linkage,
        .version = version,
    });
    lib.installHeader(upstream.path(b.pathJoin(&.{ "pixman", "pixman.h" })), "pixman.h");
    lib.installConfigHeader(version_h);
    b.installArtifact(lib);
}

inline fn opt(v: bool) ?bool {
    return if (v) true else null;
}

const flags = [_][]const u8{
    "-fno-strict-aliasing",
    "-fvisibility=hidden",
};

const srcs: []const []const u8 = &.{
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
