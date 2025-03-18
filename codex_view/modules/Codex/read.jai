Codex_Help :: struct {
    memory: [] u8;
    
    header: *Header_Record;

    // For convenience, we scan through the file and give you these
    // pointers to the various records so you don't need to worry about
    // cursoring.

    // They are pointers to the records, rather than copies, because
    // if we were to copy them, the relative pointers that we use for strings
    // would not reach.
    
    modules:    [] *Module_Record;
    files:      [] *File_Record;
    procedures: [] *Procedure_Record;
}

deinit :: (using help: *Codex_Help) {
    // We don't release the memory; we leave that up to the caller.

    array_free(modules);
    array_free(files);
    array_free(procedures);
}

make_help :: (memory: [] u8) -> (success: bool, help: Codex_Help, error_string: string) {
    help: Codex_Help;
    help.memory = memory;

    if memory.count < size_of(Header_Record) {
        log_error("In make_help(), the input memory is too short!\n");
        error_string :: "The input is too short, meaning the file is probably corrupted.";
        return false, help, error_string;
    }

    // @Endian: Byte-swap if necessary.
    
    header := cast(*Header_Record) memory.data;
    help.header = header;

    if header.magic != << cast(*u32) MAGIC.data {
        error_string :: "The file's magic number is wrong, meaning the file is probably the wrong type.";
        return false, help, error_string;
    }
    
    if header.version > VERSION  {
        error_string :: "The file has a version number that is not understood by this client. Maybe the client is too old.";
        return false, help, error_string;
    }

    if header.version < VERSION  {
        error_string :: "The file is from an old version. We don't currently load old files.";
        return false, help, error_string;
    }
    
    modules:    [..] *Module_Record;
    files:      [..] *File_Record;
    procedures: [..] *Procedure_Record;

    array_resize(*modules,    header.num_modules);
    array_resize(*files,      header.num_files);
    array_resize(*procedures, header.num_procedures);
    
    help.modules    = modules; 
    help.files      = files;
    help.procedures = procedures;

    forward := size_of(type_of(<<header)) + header.project_name.count + header.executable_name.count + header.url_or_generation_command.count + header.comment.count + 4;

    cursor := memory.data + forward;

    // This is where the module info starts.

    for 0..header.num_modules-1 {
        record := cast(*Module_Record) cursor;
        modules[it] = record;
        cursor += size_of(type_of(record.*)) + record.fully_pathed_filename.count + record.module_name.count + 2;
    }

    for 0..header.num_files-1 {
        record := cast(*File_Record) cursor;
        files[it] = record;
        cursor += size_of(type_of(record.*)) + record.fully_pathed_filename.count + 1;
    }

    for 0..header.num_procedures-1 {
        record := cast(*Procedure_Record) cursor;
        procedures[it] = record;
        cursor += size_of(type_of(record.*)) + record.name.count + 1 + record.type.count + 1;
    }
    
    return true, help, "";
}



// dump_file() here is just an example. We'll probably remove it once we have more code
// built up that people can reference.
dump_file :: (name: string) -> bool {  
    data, success := read_entire_file(name);
    if !success {
        log_error("Unable to read file '%'!\n", name);
        return false;
    }

    help_success, help := make_help(cast([] u8)data);
    if !help_success return false;

    defer deinit(*help);
    
    print("Header: %\n", << help.header);

    for help.modules    print("Import %: %\n",    it_index, << it);
    for help.files      print("File %: %\n",      it_index, << it);
    for help.procedures print("Procedure %: %\n", it_index, << it);
    return true;
}

#scope_module

#import "File";
#import "Basic";
