draw_settings :: (region: Rect) {
    w := region.w;
    h := region.h;
    
    label_theme: Label_Theme;
    label_theme.alignment = .Right;
    
    label_width_1 := w * .125;

    button_height := region.h * .03;
    right_margin := region.w * .05;
    
    top := cut_top(region, button_height);
    _, mid := cut_right(top, right_margin);
                        
    l, r := cut_left(mid, label_width_1);
    
    top_margin := region.w * .01;

    l.y += top_margin;
    r.y += top_margin;

    text_input_theme: Text_Input_Theme;
    label(l, "Editor Command", *label_theme);
    old_text := "Hello, Sailor!";
    changed, new_text := text_input(r, editor_command, *text_input_theme);
    if changed {
        free(editor_command);
        editor_command = copy_string(new_text);

        strings := Process.break_command_into_strings(new_text);
        print("strings: %\n", strings);
    }

    under_theme := label_theme;
    under_theme.alignment = .Left;
    under_theme.text_color = .{.7, .7, .85, 1};
    under := r;
    under.y += r.h;
    label(under, "Command to run when you left-click a procedure in graph view.", *under_theme);
    under.y += r.h;
    label(under, "%1 means line number; %2 means filename.", *under_theme);
}

DEFAULT_EDITOR_COMMAND :: #string DONE
"C:/Program Files/Emacs/x86_64/bin/emacsclient.exe" +%1 %2 --server-file C:/Users/Jonathan/AppData/Roaming/.emacs.d/server/server -n
DONE

