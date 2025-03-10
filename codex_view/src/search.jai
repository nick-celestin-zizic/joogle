draw_search :: (region: Rect) {
    // if !codex_help_is_valid {
    //     draw_codex_view_selection(region);
    //     return;
    // }
    
    font := filename_font;

    label_theme: Label_Theme;
    label_theme.alignment = .Left;
    label_theme.font      = font;
    
    pixels := cast(float) font.character_height;
    line := cut_top(region, pixels);

    line.y += pixels;

    hpad := pixels * .7;
    line.x += hpad;
    line.w -= hpad;

    // header := codex_help.header;
    
    // label(line, decode(*header.project_name), *label_theme);
    // line.y += pixels;
    
    // label(line, decode(*header.executable_name), *label_theme);
    // line.y += pixels;

    line.y += pixels;

    // calendar := to_calendar(header.time_generated);
    // time_string := calendar_to_string(calendar);
    label(line, "TODO: show joogle stuff and search bar", *label_theme);
    line.y += pixels;
    line.y += pixels;

    // label(line, decode(*header.url_or_generation_command), *label_theme);
    // line.y += pixels;
    // label(line, decode(*header.comment), *label_theme);
    // line.y += pixels;
    // line.y += pixels;

    // label(line, tprint("Operating System: %", header.OS), *label_theme);
    // line.y += pixels;

    // label(line, tprint("Modules: %", header.num_modules), *label_theme);
    // line.y += pixels;

    // label(line, tprint("Files: %", header.num_files), *label_theme);
    // line.y += pixels;
    
    // label(line, tprint("Procedures: %", header.num_procedures), *label_theme);
    // line.y += pixels;

    // if header.revision_control_type != .UNKNOWN {
    //     label(line, tprint("Revision control %, revision number %.", header.revision_control_type, header.revision_number), *label_theme);
    // } else {
    //     label(line, "(no revision control info)", *label_theme);
    // }

    // line.y += pixels;
}