# pixman zig

[pixman](https://gitlab.freedesktop.org/pixman/pixman), packaged for the Zig build system.

## Using

First, update your `build.zig.zon`:

```
zig fetch --save git+https://github.com/allyourcodebase/pixman.git
```

Then in your `build.zig`:

```zig
const dep = b.dependency("pixman", .{ .target = target, .optimize = optimize });
exe.linkLibrary(dep.artifact("pixman-1"));
```
