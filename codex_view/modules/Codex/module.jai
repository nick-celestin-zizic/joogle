//
// This module exports serialized information about your program so that it can be
// viewed by external tools. We figure if we provide a standard data format early,
// people can at least experiment with that without having to do this part of
// the work. (That said, if you want data that we don't export, you can of course
// make your own version of this plugin, or a different one from scratch.)
//


// By default if you use us from the metaprogram, we'll import in Usage_Mode.WRITE,
// which will include all the plugin code, and all the serialization code to write
// files.
//
// If you want to make a client that reads this data, import with USAGE_MODE==.READ,
// or (READ|WRITE).

#module_parameters(USAGE_MODE := Usage_Mode.WRITE) {
    Usage_Mode :: enum_flags u32 {
        WRITE :: 1;
        READ  :: 2;
    }
};

#if USAGE_MODE & .WRITE {
    #load "write.jai";
    #load "metrics.jai";
}

#if USAGE_MODE & .READ {
    #load "read.jai";
}


// Module_Record and File_Record can be used directly
// from the file data; they don't have to be unpacked.

// Is it a little weird that we have separate data structures
// for all this stuff, when there are already these Compiler_Message
// data structures that have what we want? Maybe. You might imagine
// that it's better to just write out Compiler_Message structs
// directly, or else have some magical conversion routine that
// generates *_Record below. Maybe we will end up doing that eventually,
// but for now I am going to be conservative and just do it the long
// way. There are three reasons:
//
//    (1) Having separate structures here means that our file format
//        is decoupled from the Compiler_* stuff, version-wise, so that
//        when those things change, we don't automatically have to revise
//        the file format. (That said, maybe when Compiler_* changes it's
//        because there is info there that is *useful* to put into the file
//        format. So what here is upside versus downside remains to be seen.
//
//    (2) Having separate structures means we can have nice efficiency
//        here, with regard to *_Record being stored contiguously in memory
//        and not requiring lots of heap operations to read the data,
//        without having to solve those problems for the (already very complex)
//        compiler runtime. *Maybe* the compiler runtime will eventually be
//        set up so that everything is packed contiguously; that seems nice
//        and seems like it might lead to faster metaprograms, but, for now
//        this is just not how things are, and that would be a significant
//        project of its own, the difficulties not even having been assessed yet.
//
//    (3) If we want a unified data structure that solves the needs of the compiler
//        runtime *and* data exporting to various external programs, its design should
//        be based on the experienced gained in both areas, so as to produce
//        the best result. But we don't have experience in the data exporting regime
//        yet. So we are doing this to get the experience, then if a lot of what we
//        are doing looks redundant and over-verbose, we can collapse it down and
//        we will be very happy with the simplification. But sometimes this is not
//        how it is -- sometimes it seems like maybe you could do such a collapse,
//        but if you did, a lot of things would get more icky and complicated
//        and you are not sure if you're better off.
//
//                                      -jblow, 5 May 2022
//

Header_Record :: struct {
    magic:   u32;
    version: u32;

    time_generated: Apollo_Time                   #align 1;  // Consensus time.
    
    revision_control_type: Revision_Control_Type  #align 1;
    revision_number:       u64                    #align 1;

    num_modules:    s32                           #align 1;
    num_files:      s32                           #align 1;
    num_procedures: s32                           #align 1;

    reserved: [256] u8 #align 1;

    OS: Operating_System_Tag;
    optimization_type: Optimization_Type; // Maybe it doesn't make sense to put this in the header, since optimization controls are actually much more granular? But hey.
    
    // Maybe we want to put large chunks of Build_Options here?
    
    project_name:              Relative_String(s16);
    executable_name:           Relative_String(s16);
    url_or_generation_command: Relative_String(s16);
    comment:                   Relative_String(s16);
}

Module_Record :: struct {
    module_type:           type_of(Message_Import.module_type) #align 1;
    module_name:           Relative_String(s16)  #align 1;
    fully_pathed_filename: Relative_String(s16)  #align 1;
}

File_Record :: struct {
    fully_pathed_filename: Relative_String(s16)  #align 1;
    module_index:          s32         #align 1;
    from_a_string:         bool        #align 1;   // Probably will be a flags field eventually.
}

Procedure_Record :: struct {
    file_index:      s32         #align 1;
    l0:              s32         #align 1;
    c0:              s32         #align 1;
    l1:              s32         #align 1;
    c1:              s32         #align 1;
    procedure_flags: type_of(Code_Procedure_Header.procedure_flags)  #align 1;
    num_expressions: u32         #align 1;

    metrics:         Metrics     #align 1;
    
    name:            Relative_String(s16)  #align 1;
}

Metrics :: struct {
    if_points:         s32         #align 1;
    maximum_if_depth:  s32         #align 1;
    maximum_loop_depth:s32         #align 1;
    total_calls:       s32         #align 1;
    same_file_calls:   s32         #align 1;
    same_module_calls: s32         #align 1;
    nonconstant_calls: s32         #align 1;

    allocations:       s32         #align 1;
    frees:             s32         #align 1;
    
    reassignments:     s32         #align 1;  // Including writing into structs and arrays.
    
    global_reads:      s32         #align 1;
    global_writes:     s32         #align 1;
}

Revision_Control_Type :: enum u64 {
    UNKNOWN   :: 0;
    SVN       :: 1;
    GIT       :: 2;
    KRAMPVS   :: 3;  // The Krampus Version System
    MERCURIAL :: 4;
    PERFORCE  :: 5;
}

#scope_module


MAGIC   :: "\x03\x00\x04\x05";  // Spells 'code' but not in text, so you don't get confused by text files.
VERSION :: 2;
TARGET_IS_LITTLE_ENDIAN :: true;  // @Incomplete @Endian. Probably should be a module parameter, or something. 

#import "Basic";
#import "Compiler";
#import "Code_Visit";
#import "Relative_Pointers";

#load "serialize.jai";
