draw_info :: (region: Rect) {
    if !codex_help_is_valid {
        draw_codex_view_selection(region);
        return;
    }
    
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

    header := codex_help.header;
    
    label(line, decode(*header.project_name), *label_theme);
    line.y += pixels;
    
    label(line, decode(*header.executable_name), *label_theme);
    line.y += pixels;

    line.y += pixels;

    calendar := to_calendar(header.time_generated);
    time_string := calendar_to_string(calendar);
    label(line, tprint("Generation time: %", time_string), *label_theme);
    line.y += pixels;
    line.y += pixels;

    label(line, decode(*header.url_or_generation_command), *label_theme);
    line.y += pixels;
    label(line, decode(*header.comment), *label_theme);
    line.y += pixels;
    line.y += pixels;

    label(line, tprint("Operating System: %", header.OS), *label_theme);
    line.y += pixels;

    label(line, tprint("Modules: %", header.num_modules), *label_theme);
    line.y += pixels;

    label(line, tprint("Files: %", header.num_files), *label_theme);
    line.y += pixels;
    
    label(line, tprint("Procedures: %", header.num_procedures), *label_theme);
    line.y += pixels;

    if header.revision_control_type != .UNKNOWN {
        label(line, tprint("Revision control %, revision number %.", header.revision_control_type, header.revision_number), *label_theme);
    } else {
        label(line, "(no revision control info)", *label_theme);
    }

    line.y += pixels;
}


draw_codex_view_selection :: (region: Rect) {
    // Tell the people what to do.

    font := stat_font;
    
    label_theme: Label_Theme;
    label_theme.font       = font;
    label_theme.text_color = .{.9, .7, .7, 1};
    label_height := font.character_height*1.5;

    if load_error_string {
        r := get_rect(0, region.h * .25 - label_height, xx region.w, label_height);
        label(r, load_error_string, *label_theme);
    }

    TEXT :: "Drag and drop a .codex file to view it.";
    r := get_rect(0, region.h * .4 - label_height, xx region.w, label_height);
    label(r, TEXT, *label_theme);

    #if OS == .WINDOWS {
        U :: #import "Windows_Utf8";
        
        r.y += cast(float)font.default_line_spacing;
        label(r, "or...", *label_theme);

        
        button_theme: Button_Theme;  // This will have the default Button_Theme values.
        // button_theme.font = button_font;
        button_theme.enable_variable_frame_thickness = true; 

        r.y += 2*cast(float)font.default_line_spacing;

        k := region.w * .2;
        r.x = region.w*.5-k*.5;
        r.w = k;
        button_theme.label_theme.alignment = .Center;
        pressed := button(r, "Browse", *button_theme);
        if pressed {
            wfilter := U.utf8_to_wide("Codex files\0*.codex",, temp);

            buffer: [512] u16;
            
            ofn: Windows.OPENFILENAMEW;
            ofn.lStructSize = size_of(Windows.OPENFILENAMEW);
            ofn.lpstrFilter = wfilter;
            ofn.lpstrFile   = buffer.data;
            ofn.nMaxFile    = buffer.count;
            ofn.Flags       = Windows.OFN_NOCHANGEDIR;

            open_success := Windows.GetOpenFileNameW(*ofn);

            if open_success {
                result, success := U.wide_to_utf8(buffer.data,, temp);
                if success {
                    narrow := U.wide_to_utf8(buffer.data,, temp);
                    try_load_file(narrow);
                }
            }
        }
    }
}
