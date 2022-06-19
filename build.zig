const std = @import("std");
const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;

pub fn build(b: *Builder) void {
    // const source = "src/simple-ref-code.c";
    const source = "src/simple-ref-code-debug.c";
    // const source = "src/simple-ref-code.zig";

    // const source = "src/complex-ref-code.c";
    // const source = "src/complex-ref-code-debug.c";
    // const source = "src/complex-ref-code.zig";

    // Allow for args like -Drelease-fast and -Dtarget=native-linux
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("ref-executable", source);

    // Builds the code
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    // Runs the exe if specified and gives it args
    const exe_run = exe.run();
    exe_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        exe_run.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&exe_run.step);

    // Runs the tests if specified
    const exe_tests = b.addTest(source);
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
