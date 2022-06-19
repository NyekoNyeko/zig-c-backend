const std = @import("std");
var EmergencyMemory: [1024 * 6]u8 = undefined;
var EmergencyAllacator = std.heap.FixedBufferAllocator.init(EmergencyMemory[0..]);
var DEBUG_MARKER: u64 = 0;

const argsAlloc = std.process.argsAlloc;

const stdOutBase = std.io.getStdOut().writer();
inline fn stdOutF(comptime fmt: []const u8, args: anytype) void {
    return stdOutBase.print(fmt, args) catch unreachable;
}
inline fn stdOutD(comptime fmt: []const u8, args: anytype) void {
    return std.debug.print(fmt, args);
}

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
    dir_path_list: std.ArrayListAligned([]const u8, null),
    config_path: ?[]u8,
    only_one_config: bool,
    first_arg_processed: bool,
};

const MenuEntries = struct {
    name: ?[]u8,
    comment: ?[]u8,
    exec_path: ?[]u8,
    categories: ?[][]u8,
    use_terminal: ?bool,
};

pub fn main() !void {

    //DEBUG DEBUG DEBUG

    // DEBUG_MARKER += 1; stdOutD("!!!DEBUG MARKER:{d}\n\n", .{DEBUG_MARKER}); // ME ME ME   ME ME ME me me ME

    //Create allocator and memory for directories
    var memory: [1024 * 768]u8 = undefined;
    var main_fba_struct = std.heap.FixedBufferAllocator.init(memory[0..]);
    const main_fba = main_fba_struct.allocator();

    //Get the args
    const args = try argsAlloc(main_fba);

    //Create the struct to hold the config and directory paths
    var dirs = Directories{
        .dir_path_list = std.ArrayList([]const u8).init(main_fba),
        .config_path = null,
        .only_one_config = true,
        .first_arg_processed = false,
    };
    defer dirs.dir_path_list.deinit();

    //Try and add the default dir path to the list
    const default_dir_path = "/usr/share/applications";
    {
        var base_dir_exists = true;
        const base_dir = std.fs.accessAbsolute(default_dir_path, .{}) catch |e| {
            base_dir_exists = false;
            if (e == std.fs.Dir.OpenError.FileNotFound) {
                stdOutD("Warning! The default directory \"{s}\" doesn't exist!\n\n", .{default_dir_path});
            } else {
                stdOutD("There's something wrong with directory \"{s}\", I won't search it!\n\n", .{default_dir_path});
            }
        };
        _ = base_dir;
        if (base_dir_exists) try dirs.dir_path_list.append(default_dir_path[0..]);
    }

    //Process the args, get directories to search
    {
        var index: usize = 1;
        if (args.len < 2) {
            stdOutF("You have to provide an argument for me to work!\n\n" ++ HelpScreenText, .{});
            return;
        }
        //TODO:: Probably should redo this because it's quite fugly ngl
        while (try ProcessArgument(args.len, index, &dirs, args[0..])) |distance_traveled| : (index += 1) {
            index += distance_traveled;
            dirs.first_arg_processed = true;
            if (index >= args.len) break;
        } else return;
    }

    //Process the directories, get files to read
    var file_paths_list = std.ArrayList([]const u8).init(main_fba);
    defer file_paths_list.deinit();
    {
        var index: usize = 0;
        while (index < dirs.dir_path_list.items.len) : (index += 1) {
            (try ProcessDirectory(dirs.dir_path_list.items[index], &file_paths_list, main_fba)) orelse {
                try emitNoFilesWarning(dirs.dir_path_list.items[index]);
            };
        }
    }
    if (file_paths_list.items.len < 1) return error.NoDesktopFilesFound;

    //Process the files, get list of applications and catagories
    //Applications hold x things
    //1. The name and description of the application
    //2. The command to run the application
    //3. That catagories (Plural!) that the application falls under
    var progam_info_list = std.ArrayList(MenuEntries).init(main_fba);
    {
        const buffer_size = 1024 * 128;
        var buffer: [buffer_size]u8 = undefined;
        var file_fba_struct = std.heap.FixedBufferAllocator.init(buffer[0..]);
        const file_fba = file_fba_struct.allocator();
        var index: usize = 0;
        while (index < file_paths_list.items.len) : (index += 1) {
            try parseFile(
                file_paths_list.items[index],
                &progam_info_list,
                file_fba,
                buffer_size,
                main_fba,
            );
            _ = file_fba_struct.reset;
        }
    }

    //debug stuff
    var index: usize = 0;
    while (index < file_paths_list.items.len) : (index += 1) {
        stdOutF("Name of TEST: {s}\n", .{file_paths_list.items[index]});
    }
}

fn emitNoFilesWarning(dir_path: []const u8) !void {
    if (dir_path[0] == '/') {
        stdOutD("Warning! There are no '.desktop' files in the directory!\n\"{s}\"\n\n", .{dir_path});
    } else {
        const relative_dir_location = try std.fs.cwd().realpathAlloc(EmergencyAllacator.allocator(), "./");
        stdOutD("Warning! There are no '.desktop' files in the directory!\n\"{s}/{s}\"\n\n", .{ relative_dir_location, dir_path });
        EmergencyAllacator.reset();
    }
}

//Processes the arguments ('-d' '-c' '-h') into either
//Slices of directory paths or a slice of the config path or provides a help screen
//Errors out if-
//1. there are multiple -c's
//2. there are multiple -c arguments
//3. there are no arguments for -c or -d
//4. there are no arguments ( returns -h )
//5. there is a -h after -d or -c
//6. there is an option that isn't -d -c or -h
//7. Out of Memory
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
            try dirs.dir_path_list.append(args[index + i]);
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
//Errors out if directory is not real/openable or out of memory
fn ProcessDirectory(current_dir: []const u8, file_paths_list: *std.ArrayListAligned([]const u8, null), allocator: std.mem.Allocator) !?void {
    var directory: std.fs.Dir = undefined;
    if (current_dir[0] != '/') {
        directory = std.fs.cwd().openDir(current_dir, .{ .iterate = true }) catch |err| {
            const relative_dir_location: ?[]const u8 = try std.fs.cwd().realpathAlloc(EmergencyAllacator.allocator(), "./");
            handleOpeningDirError(err, relative_dir_location, current_dir);
            return err;
        };
    } else {
        directory = std.fs.openDirAbsolute(current_dir, .{ .iterate = true }) catch |err| {
            handleOpeningDirError(err, null, current_dir);
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

//Error function for cleanliness
fn handleOpeningDirError(err: anyerror, relative_dir_location: ?[]const u8, current_dir: []const u8) void {
    if (relative_dir_location == null) {
        switch (err) {
            std.fs.Dir.OpenError.FileNotFound => {
                stdOutD("Error! Unable to find the directory!\n\"{s}\"\n\n", .{current_dir});
            },
            std.fs.Dir.OpenError.NotDir => {
                stdOutD("Error! The file path is not a directory!\n\"{s}\"\n\n", .{current_dir});
            },
            else => {
                stdOutD("Error! Something weird happened, see returned error for details!\n\n", .{});
            },
        }
    } else {
        switch (err) {
            std.fs.Dir.OpenError.FileNotFound => {
                stdOutD("Error! Unable to find the directory!\n\"{s}/{s}\"\n\n", .{ relative_dir_location.?, current_dir });
            },
            std.fs.Dir.OpenError.NotDir => {
                stdOutD("Error! The file path is not a directory!\n\"{s}/{s}\"\n\n", .{ relative_dir_location.?, current_dir });
            },
            else => {
                stdOutD("Error! Something weird happened, see returned error for details!\n\n", .{});
            },
        }
    }
}

//Check if the extension for the file is correct
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

// Looking for :: "Name" "Type=Application" "Categories" "[Desktop Entry]" "Exec"(Ignore anything after %) "Terminal" "Comment" "Hidden"
// If outside of "[Desktop Entry]" ->
// BEFORE: Ignore until find it. If no "[Desktop Entry]" spit warning and .desktop file is ignored.
// AFTER: If you find a new [Thing] then stop searching the file basically immediately.
// If no name spit warning and .desktop file is ignored
// If no "Type=Application" spit warning and .desktop file is ignored
// If no catagories place in catagory "Other"
// If no exec spit warning and .desktop file is ignored ->
// NOTE: If there is anything after the exec like %xyz, remove the white space from your copying of the exec path and just skip to the nextline
// If no terminal false or true spit warning and assume false ( also if they put something that's other then false or true )
// If no comment add the default comment "Generic Program!" and spit warning
// If no hidden assume NOT hidden
const LinePosition = struct {
    line: usize,
    column: usize,
};

fn parseFile(file_path: []const u8, progam_info_list: *std.ArrayListAligned(MenuEntries, null), file_allocator: std.mem.Allocator, max_file_size: usize, extra_allocator: std.mem.Allocator) !void {
    var buffer: [512]u8 = undefined;
    var opened_file = try std.fs.openFileAbsolute(file_path, .{});
    const file_buffer = try opened_file.readToEndAlloc(file_allocator, max_file_size);
    var index: usize = 0;
    var file_index: usize = 0;
    var text_slice: []const u8 = undefined;
    var dont_incr = false;
    var found_desktop_entry = false;
    var current_pos = LinePosition{
        .line = 0,
        .column = 0,
    };
    var program_info = MenuEntries{
        .name = null,
        .comment = null,
        .exec_path = null,
        .categories = null,
        .use_terminal = null,
    };
    //Start the loop of finding key-value pairs
    main: while (file_index < file_buffer.len) {
        //Search for either a section marker or key
        index = 0;
        var section = false;
        var key = false;
        while (file_index < file_buffer.len) : ({
            index += 1;
            if (dont_incr) {
                index -= 1;
                dont_incr = false;
            }
            file_index += 1;
            current_pos.column += 1;
        }) {
            //Skip Comment
            if (file_buffer[file_index] == '#') {
                while (file_buffer[file_index] == '\n') {
                    if (file_index == file_buffer.len) break :main;
                    file_index += 1;
                }
                dont_incr = true;
                continue;
            }
            //Skip NewLine
            if (file_buffer[file_index] == '\n') {
                current_pos.line += 1;
                current_pos.column = 0;
                index = 0;
                dont_incr = true;
                continue;
            } else if (file_buffer[file_index] == ' ') { //Skip Space
                dont_incr = true;
                continue;
            } else if (file_buffer[file_index] == '=') {
                text_slice = buffer[0 .. index - 1];
                file_index += 1;
                key = true;
                break;
            } else if (file_buffer[file_index] == '[') {
                section = true;
                file_index += 1;
                break;
            }
            buffer[index] = file_buffer[file_index];
        }

        index = 0;
        var succeeded = false;
        //Process the section inbetween brackets and if it is the main section continue like normal, if not skip until next section.
        if (section) {
            while (file_index < file_buffer.len) : ({
                index += 1;
                if (dont_incr) {
                    index -= 1;
                    dont_incr = false;
                }
                file_index += 1;
                current_pos.column += 1;
            }) {
                //Skip NewLine
                if (file_buffer[file_index] == '\n') {
                    current_pos.line += 1;
                    current_pos.column = 0;
                    index = 0;
                    dont_incr = true;
                    continue;
                } else if (file_buffer[file_index] == ' ') { //Skip Space
                    dont_incr = true;
                    continue;
                } else if (file_buffer[file_index] == ']') {
                    text_slice = buffer[0 .. index - 1];
                    file_index += 1;
                    succeeded = true;
                    break;
                }
                buffer[index] = file_buffer[file_index];
            }
            //Check if Desktop Entry, if not skip entire section until next open Bracket
            if (strCompare(text_slice, "DesktopEntry")) {
                found_desktop_entry = true;
                continue :main;
            } else {
                //Ignore until next bracket
                while (true) : ({
                    file_index += 1;
                    current_pos.column += 1;
                }) {
                    //Skip NewLine
                    if (file_buffer[file_index] == '\n') {
                        current_pos.line += 1;
                        current_pos.column = 0;
                        index = 0;
                        dont_incr = true;
                        continue;
                    } else if (file_buffer[file_index] == '[') {
                        continue :main;
                    } else if (file_index == file_buffer.len) {
                        stdOutD("Warning!! There was no [Desktop Entry] in the file '{s}'! I won't parse it!\n", .{file_path});
                        return;
                    }
                }
            }
            //Check which key it is and place the value inside of the struct
        } else if (key) {
            if (strCompare(text_slice, "Name")) {
                stdOutD("!!!!! Name did a thing!!\n", .{});
            } else if (strCompare(text_slice, "Type")) {
                stdOutD("Warning!! The file {s} is not an application and will not be parsed!\n", .{file_path});
                return;
            } else if (strCompare(text_slice, "Categories")) {
                stdOutD("!!!!! Categories did a thing!!\n", .{});
            } else if (strCompare(text_slice, "Exec")) {
                stdOutD("!!!!! Exec did a thing!!\n", .{});
            } else if (strCompare(text_slice, "Terminal")) {
                stdOutD("!!!!! Terminal did a thing!!\n", .{});
            } else if (strCompare(text_slice, "Comment")) {
                stdOutD("!!!!! Comment did a thing!!\n", .{});
            } else if (strCompare(text_slice, "Hidden")) {
                stdOutD("Warning!! The file {s} is hidden and will not be parsed!\n", .{file_path});
                return;
            } else {
                while (file_index < file_buffer.len) {
                    if (file_buffer[file_index] == '\n') {
                        file_index += 1;
                        current_pos.line += 1;
                        current_pos.column = 0;
                        continue :main;
                    }
                    file_index += 1;
                }
                stdOutD("Warning!! The file {s} is improperly formatted!\n", .{file_path});
                return;
            }
        } else {
            //Emit warning about improper .desktop file using current_pos struct
        }
    }
    //if it reaches the basic requirements to be listed as a program
    if (program_info.name != null and
        program_info.exec_path != null)
    {
        if (program_info.comment == null) program_info.comment = try strCopy(&.{"Generic Program!!"}, extra_allocator);
        if (program_info.use_terminal == null) program_info.use_terminal = false;
        if (program_info.categories == null) program_info.categories = &.{try strCopy(&.{"Other"}, extra_allocator)};

        try progam_info_list.append(program_info);
        return;
    }
    stdOutD("Warning!! The file {s} has no name or exec path!!\n", .{file_path});
}

//Compare strings
fn strCompare(str1: []const u8, str2: []const u8) bool {
    if (str1.len != str2.len) return false;
    var index: usize = 0;
    while (index < str1.len) {
        if (str1[index] != str2[index]) return false;
        index += 1;
    }
    return true;
}

//Copy any set of strings, combining them all together at runtime into one newly allocated slice
fn strCopy(source_strs: []const []const u8, allocator: std.mem.Allocator) ![]u8 {
    if (source_strs.len == 0) return error.AttemptedToCopyEmptyString;
    var dest_str_len: usize = 0;

    var i: usize = 0;
    while (i < source_strs.len) : (i += 1) {
        dest_str_len += source_strs[i].len;
    }

    var dest_str = try allocator.alloc(u8, dest_str_len);

    var overall_index: usize = 0;
    var index: usize = 0;
    while (index < source_strs.len) : (index += 1) {
        if (source_strs[index].len == 0) return error.AttemptedToCopyEmptyString;
        var inner_index: usize = 0;
        while (inner_index < source_strs[index].len) : (inner_index += 1) {
            dest_str[overall_index] = source_strs[index][inner_index];
            overall_index += 1;
        }
    }

    return dest_str;
}
