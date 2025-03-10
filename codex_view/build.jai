#load "src/main.jai";

#run {
    Compiler :: #import "Compiler";
    Compiler.set_build_options_dc(.{output_path="run", output_executable_name="codex_view"});
}
