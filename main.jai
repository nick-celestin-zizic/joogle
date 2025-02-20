// TODO: multiple .procs files 
// TODO: generate from local modules folder
// TODO: generate from metaprogram plugin that is hooked up to your project
// TODO: single usage string for both interpreted and compiled search
// TODO: normalize queries
// TODO: search repl like fzf
// TODO: search is much slower than it should be, investigate
// TODO: be smarter about how modules get looked up
// TODO: think about how to show polymorphs because now we just duplicate every instantiation

#if !#exists(LOADED_FROM_METAPROGRAM) #run {
    usage :: #string _TXT
To generate a procedure listing from the standard jai modules directory (outputs modules.procs)
jai main.jai - generate

Compile the searching tool into an executable (runs much faster than the interpreted version)
jai main.jai - build

Perform an interpreted query (requires modules.procs to exist, and is also very slow)
jai main.jai - search <query> <limit>
    _TXT;
    
    command_line := Compiler.get_build_options().compile_time_command_line;
    Compiler.set_build_options_dc(.{do_output=false});
    if !command_line error("Provided no arguments!\n%", usage);
    if command_line[0] == {
        case "generate"; generate_module_procedure_list_file();
        case "search";   perform_query_on_modules(command_line);
        case "build";    compile_native_search_tool();
        case; error("Invalid argument %\n%", command_line[0], usage);
    }
}

// We compile all of the modules on all the major OSes to collect as many definitions as possible.
// This might not work for you (either you cannot compile a specific platform, don't want the names in your modules.procs)
// in which case you can just modify the following array to select whichever target(s) you want!
// Since this part of the script has to be run from source, command line arguments aren't needed
targets :: struct { os: Operating_System_Tag; cpu: CPU_Tag; }.[
    .{ .WINDOWS, CPU },
    .{ .LINUX, CPU },
    .{.MACOS, .ARM64 } // going with my system default crashed for me :(
];

// Trying to #import these modules causes bad things to happen! If you want to ignore more modules you can stick them in here.
ignored_modules :: string.["Preload", "Default_Metaprogram"];

// if your editor has a jump-to-error facility that requires a specific location format, you can change this string for that.
// Search this file for where it is used to see what the arguments are
location_format :: "%:%,%:";

generate_module_procedure_list_file :: () {
    using Basic;
    using Compiler;
    
    {   using context.print_style.default_format_struct;
        use_long_form_if_more_than_this_many_members = 0;
        use_newlines_if_long_form = true;
        draw_type_name = true;
    }
    
    base_path := compiler_get_base_path();
    modules_folder := path_join(base_path, "modules");
    
    modules: [..]string;
    ok := collect_modules_from_folder(modules_folder, *modules);
    assert(ok);
    
    unique: Hash_Table.Table(string, void);
    output: String_Builder;
    for modules process_module(it, *output, *unique);
    ok = File.write_entire_file("modules.procs", *output);
    assert(ok);
    
    log("Found % procedures in % modules", unique.count, modules.count);
    exit(0); // This exit is sometimes needed, the compiler really doesn't like being abused like this and can hang for some reason....
}

collect_modules_from_folder :: #bake_arguments File_Utilities.visit_files(
    recursive=false, visit_files=true, visit_directories=true,
    proc=(info: *File_Utilities.File_Visit_Info, modules: *[..]string) {
    using Basic;
    using File_Utilities;
    using String;
    
    name: string;
    if info.is_directory {
        for file_list(info.full_name) if ends_with(it, "module.jai") {
            name = info.short_name;
            break; // This currenty makes the Toolchains modules not imported, will make it recurcive later
        }
        if !name {
            // log_error("% is not a valid module directory! TODO: recurse", info.short_name);
            return;
        }
    } else if ends_with(info.short_name, ".jai") {
        name = .{info.short_name.count-4, info.short_name.data};
    } else {
        // log_error("WEIRD FILE IN JAI MODULES: %", info.short_name);
        return;
    }
    
    if array_find(ignored_modules, name) return;
    array_add(modules, copy_string(name));
});

process_module :: (module: string, output: *Basic.String_Builder, unique: *Hash_Table.Table(string, void)) {
    using Basic; using Compiler;
    ws: [targets.count]Workspace;
    for target, target_index: targets {
        w := *ws[target_index];
        w.* = compiler_create_workspace(tprint("% %", module, target.os));
        using options := get_build_options(w.*);
        output_type = .NO_OUTPUT;
        os_target = target.os;
        lazy_foreign_function_lookups = true;
        cpu_target = target.cpu;
        write_added_strings = false;
        text_output_flags = 0;
        dead_code_elimination = .NONE;
        set_build_options(options, w.*);
        compiler_begin_intercept(w.*, .SKIP_PROCEDURE_BODIES | .SKIP_STRUCTS | .SKIP_OTHERS);
        add_build_string(tprint("#import \"%\";\n", module), w.*);
    }
        
    while true {
        m := compiler_wait_for_message();
        if m.kind == {
        // case; log("%", m.kind);
        case .ERROR; compiler_set_workspace_status(.OK, m.workspace);//log("%", m.*);
        case .TYPECHECKED; for m.(*Message_Typechecked).procedure_headers {
            using,only(name, procedure_flags, location) it.expression;
            using,only(argument_types, return_types) it.expression.type.(*Type_Info_Procedure);
            if procedure_flags & .TYPE_ONLY 
            || procedure_flags & .COMPILER_GENERATED
            then continue;
            if !name continue;
            
            name_builder: String_Builder;
            print(*name_builder, location_format, location.enclosing_load.fully_pathed_filename, location.l0, location.c0);
            print(*name_builder, " % :: (", name);
            for argument_types {
                print_type_to_builder(*name_builder, it);
                if it_index != argument_types.count-1 append(*name_builder, ", ");
            }
            print(*name_builder, ") -> (");
            for return_types {
                print_type_to_builder(*name_builder, it);
                if it_index != return_types.count-1 append(*name_builder, ", ");
            }
            print(*name_builder, ")\n");
            
            normalized_name := builder_to_string(*name_builder);
            if !Hash_Table.table_find_pointer(unique, normalized_name) {
                the_void: void;
                Hash_Table.table_add(unique, normalized_name, the_void);
                append(output, normalized_name);
            } else {
                free(normalized_name);
            }
        }
        case .COMPLETE; {
            compiler_set_workspace_status(.OK, m.workspace);
            // log("Complete %", m.(*Message_Complete).*);
            break;
        }
        }
    }
    
    for ws {
        compiler_end_intercept(it);
        compiler_destroy_workspace(it);
    }
}

perform_query_on_modules :: (args: []string) {
    using Basic;
    using String;
    
    if args.count < 3 error("Expected query and limit!");
    program := args[0];
    query   := args[1];
    limit, ok := string_to_int(args[2]);
    if !ok error("argument limit has to be an integer!");
    
    procs:, ok = File.read_entire_file("modules.procs");
    if !ok error("could not find modules.procs!");
    
    items := 0; for procs.([]u8) if it == #char "\n" items += 1;
    Line :: struct {
        signature   : string;
        info_length : int;
    };
    lines: [..]Line;
    array_reserve(*lines, items);
    
    
    rhs := procs;
    while true {
        found:, line:, rhs = split_from_left(rhs, #char "\n");
        if !found break;
        assert(xx line);
        delim :: " :: ";
        found, info:, _ = split_from_left(line, delim);
        info_length := info.count+delim.count;
        signature := advance(line, info_length);
        
        array_add(*lines, .{ signature, info_length, });
    }
    
    lev :: (a: string, b: string) -> int {
        n := a.count;
        m := b.count;
        dp := NewArray((n+1)*(m+1), int); // TODO: just preallocate an array big enough for all
        defer array_free(dp);
        
        for i: 0..n dp[i*(m+1)+0] = i;
        for j: 0..m dp[j] = j;
        for i: 1..n for j: 1..m {
            if a[i-1] == b[j-1]
            then dp[i*(m+1)+j] = dp[(i-1)*(m+1)+(j-1)];
            else dp[i*(m+1)+j] = 1 + Basic.min(
                dp[(i-0)*(m+1)+(j-1)],
                dp[(i-1)*(m+1)+(j-0)],
                dp[(i-1)*(m+1)+(j-1)],
            );
        }
        
        return dp[dp.count-1];
    }
    
    quick_sort(lines, (a: Line, b: Line, user_data: *void) -> int {
        query := user_data.(*string).*;
        return lev(a.signature, query) - lev(b.signature, query);
    }, *query);
    
    // this sucks lol but im tired and it works
    get_location :: inline (using line: Line) -> string, string {
        sig := signature;
        len := info_length;
        str := string.{sig.count+len, sig.data-len};
        lhs := string.{str.count-sig.count-1, str.data};
        found:, lhs, _ = split_from_right(lhs, ": ");
        lhs.count += 1;
        rhs := string.{str.count-lhs.count, lhs.data+lhs.count};
        return lhs, rhs;
    }
    
    longest_location := 0;
    for 0..min(lines.count, limit)-1 {
        location, rest := get_location(lines[it]);
        longest_location = max(longest_location, location.count);
    }
    
    log(query);
    for 0..min(lines.count, limit)-1 {
        location, rest := get_location(lines[it]);
        print(location);
        for 1..(longest_location - location.count) print(" ");
        print(rest);
        print("\n");
    }
}

compile_native_search_tool :: () {
    using Compiler;
    
    w := compiler_create_workspace("Search Tool");
    defer compiler_destroy_workspace(w);
    
    {   using options := get_build_options(w);
        defer set_build_options(options, w);
        
        output_type = .EXECUTABLE;
        output_executable_name = "search";
        dead_code_elimination = .ALL;
        set_optimization(*options, .VERY_OPTIMIZED);
        // write_added_strings = false;
        // text_output_flags = 0;
    }
    
    compiler_begin_intercept(w);
    defer compiler_end_intercept(w);
    
    add_build_string(Basic.tprint(#string _JAI
        LOADED_FROM_METAPROGRAM: void;
        #load "%";
        main :: () {
            perform_query_on_modules(Basic.get_command_line_arguments());
        }
    _JAI, #file), w);
    
    while compiler_wait_for_message().kind != .COMPLETE {}
}

Compiler       :: #import "Compiler";
Basic          :: #import "Basic";
System         :: #import "System";
Hash_Table     :: #import "Hash_Table";
String         :: #import "String";
File_Utilities :: #import "File_Utilities";
File           :: #import "File";

error :: (fmt: string, args: ..Any, loc := #caller_location) #expand {
    if #compile_time
    then Compiler.compiler_report(Basic.tprint(fmt, ..args), loc=loc);
    else Basic.log_error(fmt, ..args, loc=loc);
    Basic.exit(1);
} @PrintLike

path_join :: #bake_arguments String.join(separator="/");

// Copied version of quicksort, but with userdata
// @Speed: This version of quick_sort (and probably the other one)
// seems to compare items to themselves a lot, which is clearly pointless.
// Fix that!
quick_sort :: (array: [] $T, f: (T, T, *void) -> $R, user_data: *void) -> [] T {  // R is an integer type, but may be e.g. 32-bit.
    quicksort_helper :: (a: *T, n: s64, f: (T, T, *void) -> R, user_data: *void) {
        if n < 2 return;

        p := a[n / 2];

        i := 0;
        j := n-1;

        while true {
            while f(a[i], p, user_data) < 0  {i += 1;}
            while f(p, a[j], user_data) < 0  {j -= 1;}

            if i >= j break;

            t := a[i];
            a[i] = a[j];
            a[j] = t;

            i += 1;
            j -= 1;
        }
        
        quicksort_helper(a, i, f, user_data);
        quicksort_helper(a + i, n - i, f, user_data);
    }

    quicksort_helper(array.data, array.count, f, user_data);
    return array;    
}