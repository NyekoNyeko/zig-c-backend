const std = @import("std");
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
var EmergencyMemory: [1024 * 6]u8 = undefined;
var EmergencyAllacator = std.heap.FixedBufferAllocator.init(EmergencyMemory[0..]);
var DEBUG_MARKER: u64 = 0;

const stdOutBase = std.io.getStdOut().writer();
const stdInBase = std.io.getStdIn().reader();
const gp_allocator = std.heap.GeneralPurposeAllocator().allocator();
inline fn stdOutF(comptime fmt: []const u8, args: anytype) void {
    return stdOutBase.print(fmt, args) catch unreachable;
}
inline fn stdOutD(comptime fmt: []const u8, args: anytype) void {
    return std.debug.print(fmt, args);
}
inline fn stdIn(allocator: std.mem.Allocator, delimiter: u8, max_size: usize) !void {
    return try stdInBase.readUntilDelimiterAlloc(allocator, delimiter, max_size);
}
const parseInt = std.fmt.parseInt;
const parseUnsigned = std.fmt.parseUnsigned;
const argsAlloc = std.process.argsAlloc;

const absFileManager = std.fs;
const Error = error{ NoFilesInDir, NoArgumentProvided, InvalidArgumentProvided, NotEnoughArguments, TooManyArguments };

const HelpScreenText =
    \\Openbox Zig Menus Version 0.1
    \\About:
    \\    This is a program an extremely fast, zero dependency
    \\    openbox menu creator. It parses .desktop files to determine what
    \\    programs should be in the menu and can be customized easily
    \\    with a config file.
    \\Options:
    \\    -d <path>   This is the directory paths the program will search
    \\                to find .desktop files to parse. You can add as many
    \\                of these as wanted.
    \\    -c <path>   This is the file path for the config file the program
    \\                details on how to config can be found at
    \\                <github link here>
    \\    -h          Shows this screen.
    \\
;
const Directories = struct {
    desktop_dir_path_list: std.ArrayListAligned([]const u8, null),
    config_path: ?[]u8,
    only_one_config: bool,
    first_arg_processed: bool,
};

fn strCompare(str1: []const u8, str2: []const u8) bool {
    if (str1.len != str2.len) return false;
    var index: usize = 0;
    while (index < str1.len) {
        if (str1[index] != str2[index]) return false;
        index += 1;
    }
    return true;
}

fn strCopy(source_strs: []const []const u8, allocator: std.mem.Allocator) ![]u8 {
    var dest_str_len: usize = 0;

    var i: usize = 0;
    while (i < source_strs.len) : (i += 1) {
        dest_str_len += source_strs[i].len;
    }

    var dest_str = try allocator.alloc(u8, dest_str_len);

    var overall_index: usize = 0;
    var index: usize = 0;
    while (index < source_strs.len) : (index += 1) {
        var inner_index: usize = 0;
        while (inner_index < source_strs[index].len) : (inner_index += 1) {
            dest_str[overall_index] = source_strs[index][inner_index];
            overall_index += 1;
        }
    }

    return dest_str;
}

pub fn main() !void {

    //DEBUG DEBUG DEBUG

    // DEBUG_MARKER += 1; stdOutD("!!!DEBUG MARKER:{d}\n\n", .{DEBUG_MARKER}); // ME ME ME   ME ME ME me me ME

    //Create allocator and memory for directories
    var memory: [1024 * 512]u8 = undefined;
    var dirs_fixed_buffer_allocator = std.heap.FixedBufferAllocator.init(memory[0..]);
    const dirs_fba = dirs_fixed_buffer_allocator.allocator();

    const base_dir_loc = "/usr/share/applications";

    //Get the args
    const args = try argsAlloc(dirs_fba);

    var dirs = Directories{
        .desktop_dir_path_list = std.ArrayList([]const u8).init(dirs_fba),
        .config_path = null,
        .only_one_config = true,
        .first_arg_processed = false,
    };
    defer dirs.desktop_dir_path_list.deinit();
    {
        var base_dir_exists = true;
        const base_dir = std.fs.accessAbsolute(base_dir_loc, .{}) catch |e| {
            base_dir_exists = false;
            if (e == std.fs.Dir.OpenError.FileNotFound) {
                stdOutD("Warning! The default directory \"{s}\" doesn't exist!\n\n", .{base_dir_loc});
            } else {
                stdOutD("There's something wrong with directory \"{s}\", I won't search it!\n\n", .{base_dir_loc});
            }
        };
        _ = base_dir;
        if (base_dir_exists) try dirs.desktop_dir_path_list.append(base_dir_loc[0..]);
    }

    //Process the args, get directories to search
    {
        var index: usize = 1;
        if (args.len < 2) {
            stdOutF("You have to provide an argument for me to work!\n\n" ++ HelpScreenText, .{});
            return;
        }
        while (try ProcessArgument(args.len, index, &dirs, args[0..])) |distance_traveled| : (index += 1) {
            index += distance_traveled;
            dirs.first_arg_processed = true;
            if (index >= args.len) break;
        } else return;
    }

    //Process the directories, get files to read
    var file_paths_list = std.ArrayList([]const u8).init(dirs_fba);
    defer file_paths_list.deinit();
    {
        var index: usize = 0;
        while (index < dirs.desktop_dir_path_list.items.len) : (index += 1) {
            (try ProcessDirectory(dirs.desktop_dir_path_list.items[index], &file_paths_list, dirs_fba)) orelse {
                stdOutD("Warning! There are no '.desktop' files in the directory!\n\"{s}\"\n\n", .{dirs.desktop_dir_path_list.items[index]});
            };
        }
    }

    //Process the files, get list of applications and catagories
    //Applications hold x things
    //1. The name and description of the application
    //2. The command to run the application
    //3. That catagories (Plural!) that the application falls under

    //debug stuff
    var index: usize = 0;
    while (index < file_paths_list.items.len) : (index += 1) {
        stdOutF("Name of TEST: {s}\n", .{file_paths_list.items[index]});
    }
}

//Processes the argument into slices of directory paths
//Looks for args '-d' or '-c' or '-h' and errors out if
//1. there are multiple -c's
//2. there are multiple -c arguments
//3. there are no arguments for -c or -d
//4. there are no arguments ( returns -h )
//5. there is a -h after -d or -c
fn ProcessArgument(amount_of_args: usize, index: usize, dirs: *Directories, args: [][]u8) !?usize {
    if (strCompare(args[index], "-d")) {
        if (index + 1 >= amount_of_args) {
            stdOutD("Error! Expected an argument after \"-d\" but found nothing!\n\n", .{});
            return error.NotEnoughArguments;
        } else if (args[index + 1][0] == '-') {
            stdOutD("Error! Expected an argument after \"-d\" but found \"{s}\"!\n\n", .{args[index + 1]});
            return error.InvalidArgumentProvided;
        }

        var i: usize = 1;
        while (args[index + i][0] != '-') {
            try dirs.desktop_dir_path_list.append(args[index + i]);
            i += 1;
            if (index + i >= amount_of_args) break;
        }
        return i;
    } else if (strCompare(args[index], "-c")) {
        if (index + 1 >= amount_of_args) {
            stdOutD("Error! Expected an argument after \"-c\" but found nothing!\n\n", .{});
            return error.NotEnoughArguments;
        } else if (args[index + 1][0] == '-') {
            stdOutD("Error! Expected an argument after \"-c\" but found \"{s}\"!\n\n", .{args[index + 1]});
            return error.InvalidArgumentProvided;
        } else if (!dirs.only_one_config) {
            stdOutD("Error! Expected only one \"-c\" argument but found multiple!\n\n", .{});
            return error.TooManyArguments;
        }

        if (index + 2 < amount_of_args) {
            if (args[index + 2][0] != '-') {
                stdOutD("Error! Expected only one \"-c\" argument but found multiple!\n\n", .{});
                return error.TooManyArguments;
            }
        }

        dirs.config_path = args[index + 1];
        dirs.only_one_config = false;
        return 1;
    } else if (strCompare(args[index], "-h")) {
        if (dirs.first_arg_processed) {
            stdOutD("Error! Unexpected \"-h\" argument!\n\n", .{});
            return error.InvalidArgumentProvided;
        }
        stdOutF(HelpScreenText, .{});
        return null;
    } else {
        stdOutD("Error! The option \"{s}\" is unknown!\n(Do -h to see list of options)\n\n", .{args[index]});
        return error.InvalidArgumentProvided;
    }
}

//Search through each directory path and collects all file paths( not dir or other paths, non recursively TODO:: add recursive option )
fn ProcessDirectory(dirs: []const u8, file_paths_list: *std.ArrayListAligned([]const u8, null), allocator: std.mem.Allocator) !?void {
    var directory: std.fs.Dir = undefined;
    if (dirs[0] != '/') {
        directory = std.fs.cwd().openDir(dirs, .{ .iterate = true }) catch |err| {
            const current_dir = try std.fs.cwd().realpathAlloc(EmergencyAllacator.allocator(), "./");
            switch (err) {
                std.fs.Dir.OpenError.FileNotFound => {
                    stdOutD("Error! Unable to find the directory!\n\"{s}/{s}\"\n\n", .{ current_dir, dirs });
                },
                std.fs.Dir.OpenError.NotDir => {
                    stdOutD("Error! The file path is not a directory!\n\"{s}/{s}\"\n\n", .{ current_dir, dirs });
                },
                else => {
                    stdOutD("Error! Something weird happened, see returned error for details!\n\n", .{});
                },
            }
            return err;
        };
    } else {
        directory = std.fs.openDirAbsolute(dirs, .{ .iterate = true }) catch |err| {
            switch (err) {
                std.fs.Dir.OpenError.FileNotFound => {
                    stdOutD("Error! Unable to find the directory!\n\"{s}\"\n\n", .{dirs});
                },
                std.fs.Dir.OpenError.NotDir => {
                    stdOutD("Error! The file path is not a directory!\n\"{s}\"\n\n", .{dirs});
                },
                else => {
                    stdOutD("Error! Something weird happened, see returned error for details!\n\n", .{});
                },
            }
            return err;
        };
    }

    var buffer: [1024]u8 = undefined;
    const buffer_slice = try directory.realpath("./", buffer[0..]);
    var dir_iterator = directory.iterate();
    var first_pass = true;
    var index: usize = 0;
    while (try dir_iterator.next()) |new_entry| : (index += 1) {
        if (@enumToInt(new_entry.kind) != 5) continue;
        if (!fileIsDotDesktop(new_entry.name)) continue;
        const things_to_be_combined = [_][]const u8{ buffer_slice, "/", new_entry.name };
        try file_paths_list.append(try strCopy(things_to_be_combined[0..], allocator));
        first_pass = false;
    } else if (first_pass) return null;
}

fn fileIsDotDesktop(filename: []const u8) bool {
    var index: usize = 0;
    var last_dot_loc: ?usize = null;
    while (index < filename.len) {
        if (filename[index] == '.') last_dot_loc = index;
        index += 1;
    }
    if (last_dot_loc == null) return false;
    return strCompare(filename[last_dot_loc.?..], ".desktop");
}
