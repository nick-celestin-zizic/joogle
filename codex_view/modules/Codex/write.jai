get_plugin :: () -> *Metaprogram_Plugin {
    my := New(My_Plugin);  // We are making this on the heap so you could have more than one instance of this plugin running.

    // Reserve some size in the procedures table.
    init(*my.procedures, 1000);
    
    my.message           = message;
    my.finish            = finish;
    my.shutdown          = shutdown;
    my.handle_one_option = handle_one_option;

    return my;
}

message :: (p: *Metaprogram_Plugin, message: *Message) {
    my := cast(*My_Plugin) p;
    
    if message.kind == {
      case .FILE;
        note_file(my, cast(*Message_File) message);
      case .IMPORT;
        note_import(my, cast(*Message_Import) message);
      case .TYPECHECKED;
        note_typechecked(my, cast(*Message_Typechecked) message);
    }
}

finish :: (p: *Metaprogram_Plugin) {
    my := cast(*My_Plugin) p;
    filename := my.export_filename;
    if !filename  filename = "exported.codex";

    // The file format is:

    // (all numbers are little-endian; all strings are UTF-8 string~s16 with a zero after. All strings
    // are stored immediately after the record that points at them, and the next record starts after
    // those strings are done.)

    // Header_Record, followed by its strings.

    // num_modules Module_Records, with strings packed inline with them.
    // (You know where the next record is by adding the size of the struct
    // to the lengths of the strings, plus one zero termination byte for each
    // string, which we put there to help our C brothers and sisters).

    // num_files File_Records. Ibid.

    // num_procedures Procedure_Records. Ibid.
    
    builder := *my.builder;

    w_options := get_build_options(p.workspace);
    exe_name := w_options.output_executable_name;

    project_name              := s16_truncate("The Sailor Project");
    executable_name           := s16_truncate(exe_name);
    comment                   := s16_truncate("Hello, Sailor!");
    url_or_generation_command := s16_truncate("frob://jai.exe rezrov.jai 69105");

    // @Robustness: actually s16_truncate is not good enough when there are more than one string.
    // We need to make sure the relative pointers can actually reach their targets, which could
    // easily be made not to happen. @Incomplete.
    
    contiguous := size_of(Header_Record) + project_name.count + 1 + executable_name.count + 1 + comment.count + 1 + url_or_generation_command.count + 1;
    pointer := ensure_contiguous_space(builder, contiguous);
    
    header := cast(*Header_Record) pointer;
    header.magic   = << cast(*u32) MAGIC.data;
    header.version = VERSION;

    header.time_generated = current_time_consensus();

    header.OS = OS;  // @Incomplete: When we cross-compile, we need to get the OS of the target workspace.

    // header.revision_control_type = .SVN;
    // header.revision_number       = 0;   // @Incomplete: Provide a way to fill this out?

    header.num_modules    = cast(s32) my.imports.count;
    header.num_files      = cast(s32) my.files.count;
    header.num_procedures = cast(s32) my.procedures.count;
    
    // @Robustness: Truncate if we exceed u32 counts for some reason?
    // @Incomplete @Endian: Byte-swap 'header' if necessary.
    // code to do this from your struct.

    
    url_16     := *header.url_or_generation_command;
    comment_16 := *header.comment;

    // Write out the strings.
    
    cursor := pointer + size_of(type_of(<<header));
    
    cursor = write_string_s16(builder, *header.project_name,              cursor, project_name);
    cursor = write_string_s16(builder, *header.executable_name,           cursor, executable_name);
    cursor = write_string_s16(builder, *header.comment,                   cursor, comment);
    cursor = write_string_s16(builder, *header.url_or_generation_command, cursor, url_or_generation_command);

    advance_through_ensured_space(builder, cursor - pointer);
    assert(cursor - pointer == contiguous);
    
    // print("Header: %\n", <<header);
    
    for import: my.imports {
        module_name           := s16_truncate(import.module_name);
        fully_pathed_filename := s16_truncate(import.fully_pathed_filename);

        contiguous := size_of(Module_Record) + module_name.count + 1 + fully_pathed_filename.count + 1;
        pointer := ensure_contiguous_space(builder, contiguous);

        record := cast(*Module_Record) pointer;

        record.module_type = import.module_type;

        cursor := pointer + size_of(type_of(<<record));

        cursor = write_string_s16(builder, *record.module_name, cursor, module_name);
        cursor = write_string_s16(builder, *record.fully_pathed_filename, cursor, fully_pathed_filename);
        
        advance_through_ensured_space(builder, cursor - pointer);
        assert(cursor - pointer == contiguous);
        
        // print("Module_Record %:\n%\n", it_index, << record);
    }

    for file: my.files {
        fully_pathed_filename := s16_truncate(file.fully_pathed_filename);

        contiguous := size_of(File_Record) + fully_pathed_filename.count + 1;
        pointer := ensure_contiguous_space(builder, contiguous);

        record := cast(*File_Record) pointer;

        module_index := 0;
        if file.enclosing_import {  // @Robustness: Should we reserve an index for 'not found'?
            success: bool = ---;
            module_index, success = table_find(*my.import_indices, file.enclosing_import);
            assert(success);
        }
        
        record.module_index = cast(s32) module_index;

        record.from_a_string = file.from_a_string;

        cursor := pointer + size_of(type_of(<<record));
        cursor = write_string_s16(builder, *record.fully_pathed_filename, cursor, fully_pathed_filename);
        
        advance_through_ensured_space(builder, cursor - pointer);
        assert(cursor - pointer == contiguous);
        
        // print("File_Record %:\n%\n", it_index, << record);
    }

    index := 0;
    for tc: my.procedures {
        body := tc.expression;
        header := body.header;
        assert(header != null);

        name := s16_truncate(header.name);

        contiguous := size_of(Procedure_Record) + name.count + 1;
        pointer := ensure_contiguous_space(builder, contiguous);

        record := cast(*Procedure_Record) pointer;
        record.l0 = header.l0;
        record.c0 = header.c0;
        record.l1 = body.l1;
        record.c1 = body.c1;

        // @Speed: We would like to do metrics earlier, in parallel
        // with the rest of compilation, but this would cause us to do them twice
        // when procedures are modified and we'd have to throw the old metrics
        // away. But maybe this is fine, actually?
        record.metrics = collect_metrics(tc);

        
        record.procedure_flags = header.procedure_flags;
        record.num_expressions = cast(u32) tc.subexpressions.count;

        file_index := 0;
        if body.enclosing_load {  // @Robustness: Should we reserve an index for 'not found'?
            success: bool = ---;
            file_index, success = table_find(*my.file_indices, body.enclosing_load);

            // We are not necessarily 100% sure we have this? Unclear.
            // assert(success);

            if !success  file_index = 0;
        }

        record.file_index = cast(s32) file_index;

        cursor := pointer + size_of(type_of(<<record));
        cursor = write_string_s16(builder, *record.name, cursor, name);
        
        advance_through_ensured_space(builder, cursor - pointer);
        assert(cursor - pointer == contiguous);
        
//        print("Procedure_Record %:\n%\n", index, << record);
        index += 1;
    }

    log("[Codex] Writing file '%'.\n", filename);
    success := write_entire_file(filename, builder);
    if !success log_error("Export plugin was unable to write the output file '%'!\n", filename);
}

shutdown :: (p: *Metaprogram_Plugin) {
    my := cast(*My_Plugin) p;

    free_buffers(*my.builder);

    array_free(my.files);
    array_free(my.imports);

    deinit(*my.procedures);

    deinit(*my.import_indices);
    deinit(*my.file\ _indices);

    free(p);
}

handle_one_option :: (p: *Metaprogram_Plugin, options: [] string, cursor: int) -> new_cursor: int {
    s := options[cursor];

    my := cast(*My_Plugin) p;
    
    if s == {
      case "-export_file";
        if cursor >= options.count-1 {
            log_error("Command line: Missing argument to -export_file.\n");
            return cursor + 1;
        }

        my.export_filename = options[cursor+1];
        return cursor + 2;  // This tells the caller that the next argument to process is at cursor + 2.
    }

    return cursor;  // We did not handle anything, so we return the same cursor to tell the caller to try the next plugin.
}

log_help :: (p: *Metaprogram_Plugin) {
    log(HELP_STRING);
}

HELP_STRING :: #string DONE
-option arg        This is just an option. You pass it one argument.
DONE


#scope_module

My_Plugin :: struct {
    #as using base: Metaprogram_Plugin;

    export_filename: string;
    builder: String_Builder;

    imports:    [..] *Message_Import;
    files:      [..] *Message_File;

    // We may see a procedure twice, if it gets modified and comes back through again.
    // So instead of storing procedures in an array, we store them in a Table, which
    // makes it easy to deduplicate. (We could rely on the ALREADY_MODIFIED procedure flag,
    // but this seems tweakier and more error-prone in the long term.)
    procedures: Table(*Code_Procedure_Body, Typechecked(Code_Procedure_Body));

    import_indices: Table(*Message_Import, s64);
    file\ _indices: Table(*Message_File,   s64);
}


note_file :: (my: *My_Plugin, m: *Message_File) {
    index := my.files.count;
    table_add(*my.file_indices, m, index);
    array_add(*my.files, m);
}

note_import :: (my: *My_Plugin, m: *Message_Import) {
    index := my.imports.count;
    table_add(*my.import_indices, m, index);
    array_add(*my.imports, m);

    if m.module_name == "Basic" {
        // Yeah, this is kind of a hack!
        basic_module = m;
    }
}

note_typechecked :: (my: *My_Plugin, m: *Message_Typechecked) {
    for m.procedure_bodies {
        table_set(*my.procedures, it.expression, it);
    }
}


write_string_s16 :: (builder: *String_Builder, target: *Relative_String(s16), cursor: *u8, s: string) -> (new_cursor: *u8) {
    assert(s.count < 32768);  // You need to call s16_truncate on this before passing it in (since you need to know the actual truncated length to compute the necessary contiguous space.)

    target.count = cast(s16) s.count;
    write_relative_pointer(s16, *target.data, cursor);
    assert(cursor > xx *target.data);
    
    memcpy(cursor, s.data, s.count);
    cursor[s.count] = 0;

    return cursor + s.count + 1;
}

s16_truncate :: (s: string) -> string {
    t := s;
    if t.count > 32767  t.count = 32767;
    return t;
}

#import "File";
#import "Hash_Table";
Basic :: #import "Basic";  // So we can get at ENABLE_ASSERT.
// String :: #import "String";  // For "contains"

basic_module: *Message_Import;  // Used for gathering metrics.



