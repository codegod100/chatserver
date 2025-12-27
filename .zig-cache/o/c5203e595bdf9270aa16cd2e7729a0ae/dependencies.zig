pub const packages = struct {
    pub const @"1220b9feb4652a62df95843e78a5db008401599366989b52d7cab421bf6263fa73d0" = struct {
        pub const build_root = "/home/nandi/.cache/zig/p/zstd-1.5.7-KEItkJ8vAAC5_rRlKmLflYQ-eKXbAIQBWZNmmJtS18q0";
        pub const build_zig = @import("1220b9feb4652a62df95843e78a5db008401599366989b52d7cab421bf6263fa73d0");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zstd", "N-V-__8AAGxifwAAGwXwvsnl_aOXFGLZTeYCu0WBhuEXr96u" },
        };
    };
    pub const @"N-V-__8AABnBVRNhZGWHvWKm8PO-N4Js4Zr65NnswmkZ0nYX" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAE9SyhMGHGnkgRenWYw-birLp2Nl-IYGqIbdlga3" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAEbXoBTC007kkcMVW2_P5yIKMxPKQ-L5sYEc3_qH" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAGXNmxEQQYT5QBEheV2NJzSQjwaBuUx8wj_tGdoy" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAGxifwAAGwXwvsnl_aOXFGLZTeYCu0WBhuEXr96u" = struct {
        pub const build_root = "/home/nandi/.cache/zig/p/N-V-__8AAGxifwAAGwXwvsnl_aOXFGLZTeYCu0WBhuEXr96u";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AAInnSA9gFeMzlB67m7Nu-NYBUOXqDrzYmYgatUHk" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAJuttw4mNdQg3ig107ac4uyAhcFPznGHmpnmX58C" = struct {
        pub const available = false;
    };
    pub const @"N-V-__8AAL1yjxS0Lef6Fv5mMGaqNa0rGcPJxOftYK0NYuJu" = struct {
        pub const available = true;
        pub const build_root = "/home/nandi/.cache/zig/p/N-V-__8AAL1yjxS0Lef6Fv5mMGaqNa0rGcPJxOftYK0NYuJu";
        pub const deps: []const struct { []const u8, []const u8 } = &.{};
    };
    pub const @"N-V-__8AANpEpBfszYPGDvz9XJK8VRBNG7eQzzK1iNSlkdVG" = struct {
        pub const available = false;
    };
    pub const @"afl_kit-0.1.0-NdJ3cncdAAA4154gtkRqNApovBYfOs-LWADNE-9BzzPC" = struct {
        pub const available = false;
    };
    pub const @"bytebox-0.0.1-SXc2seA2DwAUHbrqTMz_mAQQGqO0EVPYmZ89YZn4KsTi" = struct {
        pub const build_root = "/home/nandi/.cache/zig/p/bytebox-0.0.1-SXc2seA2DwAUHbrqTMz_mAQQGqO0EVPYmZ89YZn4KsTi";
        pub const build_zig = @import("bytebox-0.0.1-SXc2seA2DwAUHbrqTMz_mAQQGqO0EVPYmZ89YZn4KsTi");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zig-stable-array", "stable_array-0.1.0-3ihgvVxbAACET5MoiUn2T5ENunG_da_X3kGbji-f4QTF" },
        };
    };
    pub const @"roc-0.0.0-NAC9w-7vhQC7MudcZB29RgpMRABkoruyarLdUr5Nyh3s" = struct {
        pub const build_root = "/home/nandi/.cache/zig/p/roc-0.0.0-NAC9w-7vhQC7MudcZB29RgpMRABkoruyarLdUr5Nyh3s";
        pub const build_zig = @import("roc-0.0.0-NAC9w-7vhQC7MudcZB29RgpMRABkoruyarLdUr5Nyh3s");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "afl_kit", "afl_kit-0.1.0-NdJ3cncdAAA4154gtkRqNApovBYfOs-LWADNE-9BzzPC" },
            .{ "roc_deps_aarch64_macos_none", "N-V-__8AAJuttw4mNdQg3ig107ac4uyAhcFPznGHmpnmX58C" },
            .{ "roc_deps_aarch64_linux_musl", "N-V-__8AABnBVRNhZGWHvWKm8PO-N4Js4Zr65NnswmkZ0nYX" },
            .{ "roc_deps_aarch64_windows_gnu", "N-V-__8AAEbXoBTC007kkcMVW2_P5yIKMxPKQ-L5sYEc3_qH" },
            .{ "roc_deps_arm_linux_musleabihf", "N-V-__8AAE9SyhMGHGnkgRenWYw-birLp2Nl-IYGqIbdlga3" },
            .{ "roc_deps_x86_linux_musl", "N-V-__8AAGXNmxEQQYT5QBEheV2NJzSQjwaBuUx8wj_tGdoy" },
            .{ "roc_deps_x86_64_linux_musl", "N-V-__8AAL1yjxS0Lef6Fv5mMGaqNa0rGcPJxOftYK0NYuJu" },
            .{ "roc_deps_x86_64_macos_none", "N-V-__8AAInnSA9gFeMzlB67m7Nu-NYBUOXqDrzYmYgatUHk" },
            .{ "roc_deps_x86_64_windows_gnu", "N-V-__8AANpEpBfszYPGDvz9XJK8VRBNG7eQzzK1iNSlkdVG" },
            .{ "bytebox", "bytebox-0.0.1-SXc2seA2DwAUHbrqTMz_mAQQGqO0EVPYmZ89YZn4KsTi" },
            .{ "zstd", "1220b9feb4652a62df95843e78a5db008401599366989b52d7cab421bf6263fa73d0" },
        };
    };
    pub const @"stable_array-0.1.0-3ihgvVxbAACET5MoiUn2T5ENunG_da_X3kGbji-f4QTF" = struct {
        pub const build_root = "/home/nandi/.cache/zig/p/stable_array-0.1.0-3ihgvVxbAACET5MoiUn2T5ENunG_da_X3kGbji-f4QTF";
        pub const build_zig = @import("stable_array-0.1.0-3ihgvVxbAACET5MoiUn2T5ENunG_da_X3kGbji-f4QTF");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "roc", "roc-0.0.0-NAC9w-7vhQC7MudcZB29RgpMRABkoruyarLdUr5Nyh3s" },
};
