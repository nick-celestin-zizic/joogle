// To-Do List:

// Enable reconnects.
// Record a second time crashes.

// New allocations this frame should get sent by the client so that we can track those.
// Frame index should be sent by the client because we can start recording at non-zero frame index...!

// Resizable window.

// The metrics for calling into other files and other modules.
// should care about *how many* other files and modules.

// Draw metric description.

// Don't draw rectangle if GetRect has us occluded by a widget.



#load "graphs.jai";
#load "draw_metrics.jai";
#load "sidebar.jai";
#load "settings.jai";
#load "info.jai";
#load "live_allocations.jai";
#load "draw_live_allocations.jai";
#load "recording.jai";
#load "treemap.jai";
#load "search.jai";

SCALE :: 1;  // I use this during development to quickly make the window real big.

my_window: Window_Type;
window_width  : s32 = 1920*SCALE;
window_height : s32 = 1080*SCALE;

COMPILE_FONT_SIZE :: 80;
COMPILE_SMALL_FONT_SIZE :: 54;
COMPILE_SMALLER_FONT_SIZE :: 30;
STAT_FONT_SIZE :: 55;
STAT_SMALL_FONT_SIZE :: 22;
STACK_TRACE_HEADER_FONT_SIZE :: 30;
FILENAME_FONT_SIZE :: 38;
SIDEBAR_FONT_SIZE :: 18;
SECTION_HEADER_FONT_SIZE :: 55;

compile_font: *Font;
compile_small_font: *Font;
compile_smaller_font: *Font;
filename_font: *Font;
stat_font: *Font;
stat_small_font: *Font;
stack_trace_header_font: *Font;
sidebar_font: *Font;
section_header_font: *Font;


//
// Stuff that gets set by UI widgets:
//
current_metric_index := cast(s32) (THE_METRICS.count - 1); // This is Blend.
current_height_index := cast(s32) SIZE_TYPES.LOG;
should_include_modules := true;

current_primary_key := cast(s32) Primary_Key.MODULE;
current_secondary_key: s32;

load_error_string: string;


current_time: float64;
last\  _time: float64;
current_dt:   float;

dropped_files: [..] string;

codex_help: Codex_Help;
codex_help_is_valid := false;

background_occluded := false;

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    my_window = create_window(window_width, window_height, "A Window");

    #if OS == .WINDOWS {
        // @Feature: Add user-specific typelist support.
        Windows.DragAcceptFiles(my_window, cast(Windows.BOOL) true);
    } else #if OS == .LINUX {
        X11 :: #import "X11";
        typelist := string.["url/url", "text/uri-list", "text/plain", "application/octet-stream"];
        X11.enable_drag_and_drop(my_window, typelist);
    } else #if OS == .MACOS {
        #import "Objective_C";
        #import "Objective_C/AppKit";
        types := NSArray(NSPasteboardType).arrayWithObject(NSPasteboardTypeFileURL);
        NSView.registerForDraggedTypes(my_window, types);
    }

    Simp.set_render_target(my_window, .LEFT_HANDED);
    my_init_fonts();
    ui_init();

    init_editor_command();

    init_live_allocations();

    border_display_type_index = cast(s32) border_display_type;  // Initialize this because the default dropdown setting is not 0.
    
    args := get_command_line_arguments(,, temp);
    args.count -= 1;
    args.data  += 1;
    for args try_load_file(it);
    
    quit := false;
    while !quit {
        at := current_time_monotonic();
        current_time = to_float64_seconds(at);
        dt := cast(float)(current_time - last_time);
        Clamp(*dt, 0, 0.1);
        current_dt = dt;

        last_time = current_time;

        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);

            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

                if should_reinit  my_init_fonts();  // Resize the font for the new window size.
            }
        }

        for event: Input.events_this_frame {
            if event.type == .QUIT then quit = true;

            getrect_handle_event(event);

            if event.type == {
              case .KEYBOARD;
                if event.key_pressed && event.key_code == .ESCAPE {
                    active_widget_deactivate_all();
                }

                if event.key_code == {
                    case #char "W"; north = event.key_pressed;
                    case #char "A"; west  = event.key_pressed;
                    case #char "S"; south = event.key_pressed;
                    case #char "D"; east  = event.key_pressed;

                    case .ARROW_UP;    north_alt = event.key_pressed;
                    case .ARROW_LEFT;  west_alt  = event.key_pressed;
                    case .ARROW_DOWN;  south_alt = event.key_pressed;
                    case .ARROW_RIGHT; east_alt  = event.key_pressed;

                    case .ESCAPE; if event.key_pressed quit = true;
                }

              case .MOUSE_WHEEL;
                if event.wheel_delta {
                    factor := event.wheel_delta / cast(float) event.typical_wheel_delta;
                    zoom := pow(1.2, factor);

                    zoom_target *= zoom;

                    Clamp(*zoom_target, 1, ZOOM_FACTOR_MAX);
                }

              case .DRAG_AND_DROP_FILES;
                for dropped_files free(it);
                array_reset(*dropped_files);
                for event.files array_add(*dropped_files, copy_string(it));
            }
        }

        handle_dropped_files();
        draw_one_frame(dt);

        reset_temporary_storage();
        update_live_allocations();
        sleep_milliseconds(10);
    }
}

handle_dropped_files :: () {
    // @Incomplete: Later we will put multiple files in a list on the left side
    // of the UI, or something. For now we keep stomping the last file with the
    // next one.

    for dropped_files {
        try_load_file(it);
    }

    array_reset(*dropped_files);
}

set_load_error_string :: (s: string) {
    if load_error_string free(load_error_string);
    load_error_string = copy_string(s);
}

try_load_file :: (name: string) -> bool {
    data, success := read_entire_file(name);
    if !success {
        s := tprint("Unable to read file '%'!", name);
        set_load_error_string(s);
        log_error("%", s);
        return false;
    }

    if codex_help.header {
        deinit(*codex_help);
        codex_help.header = null;
    }

    help_success, help, fail_string := make_help(cast([] u8)data);
    if help_success {
        codex_help = help;
        codex_help_is_valid = true;
        proc_view_is_dirty  = true;
        current_view_mode = .GRAPHS;
        current_view_mode = .SEARCH;
    } else {
        set_load_error_string(fail_string);
    }

    return true;
}

draw_one_frame :: (dt: float) {
    Simp.clear_render_target(.15, .11, .11, 1);

    x, y, width, height := get_dimensions(my_window, true);
    background_occluded = ui_per_frame_update(my_window, width, height, current_time);

    old_metric_index := current_metric_index;
    old_height_index := current_height_index;
    old_primary_key := current_primary_key;
    old_secondary_key := current_secondary_key;

    draw_one_client_frame();

    draw_popups();  // This draws Subwindows as well.

    if (current_metric_index != old_metric_index) || (current_height_index != old_height_index) || (current_primary_key != old_primary_key) || (current_secondary_key != old_secondary_key) {
        proc_view_is_dirty = true;
    }

    //
    // Swap buffers!
    //

    Simp.swap_buffers(my_window);
}

draw_one_client_frame :: () {
    screen := get_rect(0, 0, xx window_width, xx window_height);

    sidebar_width := window_height / 15.0;
    sidebar, content_rect := cut_left(screen, sidebar_width);

    update_cursor_pos();

    draw_sidebar(sidebar);

    if #complete current_view_mode == {
      case .SETTINGS;
        draw_settings(content_rect);
      case .INFO;
        draw_info(content_rect);
      case .GRAPHS;
        draw_metrics(content_rect);
      case .LIVE_ALLOCATIONS;
        draw_live_allocations(content_rect);
      case .SEARCH;
        draw_search(content_rect);
    }
}

my_init_fonts :: () {
    if !working_directory_set {
        // So that we can load our font, set to path of running executable.
        path := path_strip_filename(get_path_of_running_executable());
        set_working_directory(path);

        working_directory_set = true;
    }

    dir := "data";

    // path := sprint("%../run_tree/data/fonts", #filepath);
    ratio := window_height / 1080.0;
    compile_font =         Simp.get_font_at_size(dir, "KarminaBold.otf", xx(COMPILE_FONT_SIZE * ratio));
    compile_small_font =   Simp.get_font_at_size(dir, "KarminaBold.otf", xx(COMPILE_SMALL_FONT_SIZE * ratio));
    compile_smaller_font = Simp.get_font_at_size(dir, "KarminaBold.otf", xx(COMPILE_SMALLER_FONT_SIZE * ratio));
    stat_font =            Simp.get_font_at_size(dir, "KarminaBold.otf", xx(STAT_FONT_SIZE * ratio));
    stat_small_font =      Simp.get_font_at_size(dir, "KarminaBold.otf", xx(STAT_SMALL_FONT_SIZE * ratio));
    stack_trace_header_font = Simp.get_font_at_size(dir, "KarminaBold.otf", xx(STACK_TRACE_HEADER_FONT_SIZE * ratio));
    filename_font =        Simp.get_font_at_size(dir, "KarminaBold.otf", xx(FILENAME_FONT_SIZE * ratio));
    sidebar_font =         Simp.get_font_at_size(dir, "KarminaBold.otf", xx(SIDEBAR_FONT_SIZE * ratio));
    section_header_font =  Simp.get_font_at_size(dir, "KarminaBoldItalic.otf", xx(SECTION_HEADER_FONT_SIZE*ratio));
}

init_editor_command :: () {
    s := trim_right(DEFAULT_EDITOR_COMMAND, "\d010\d013\d032"); // Strip newlines, etc.
    editor_command = copy_string(s);
}

update_cursor_pos :: () {
    x, y := get_mouse_pointer_position(my_window, false);
    cursor_pos.x = cast(float) x;
    cursor_pos.y = cast(float) y;
}


Font         :: Simp.Dynamic_Font;
Font_Effects :: Simp.Font_Effects;

working_directory_set := false;
editor_command: string;


Simp  :: #import "Simp";
Input :: #import "Input";
Process :: #import "Process";

#import "Window_Creation";

#import "Basic";
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";
#import "GetRect_LeftHanded";

#import "Codex"(USAGE_MODE=.READ);
#import "File";
#import "Sort";
#import "Relative_Pointers";




//
// Stuff for Treemap mode UI (may want to factor it into treemap.jai):
//

zoom_target  := 1.0;
zoom_current := 1.0;
ZOOM_FACTOR_MAX :: 50.0;

north, south, east, west: u32;
north_alt, south_alt, east_alt, west_alt: u32;

treemap_offset: Vector2;  // In screen units where -1 is the screen width... why? So it doesn't change discontinuously when the window size changes.
treemap_offset_in_pixels: Vector2;
