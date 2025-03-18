max_signature_width: int;
search_criteria: enum s32 { SIGNATURE; NAME; };
draw_search :: (region: Rect) {
    if !codex_help_is_valid {
        array_reset(*sorted_procs);
        draw_codex_view_selection(region);
        return;
    }
    if !sorted_procs {
        sorted_procs = array_copy(codex_help.procedures);
        max_signature_width = 0;
        for sorted_procs max_signature_width = max(max_signature_width, decode(*it.type).count);
    }
    
    font := compile_smaller_font;

    label_theme: Label_Theme;
    label_theme.alignment = .Left;
    label_theme.font      = font;
    
    pixels := cast(float) font.character_height;
    line := cut_top(region, pixels);
    line.y += pixels;

    hpad := pixels * .7;
    line.x += hpad;
    line.w -= hpad*2;
    
    // TODO: dropdown for either by type or by name
    {
        rect   := Rect.{line.x, line.y, line.w*0.08, line.h};
        rect.x += 2*hpad + label(rect, "Search by: ", *(Label_Theme.{alignment=.Right}));
        
        rect.w *= 1.25;
        
        dropdown(rect, .["Signature", "Name"], xx *search_criteria);
        line.y += pixels+hpad;
    }
    
    {   push_state(line.h, line.h*2.0);
        theme := Text_Input_Theme.{label_theme = label_theme};
        result_action, new_string, state := text_input(line, "", *theme);
        if result_action == .ENTERED {
            capture: struct {
                query: string;
                dp_allocation: []int;
            } = .{ new_string, NewArray((max_signature_width+1) * (max_signature_width+1), int,, temp) };
            if #complete search_criteria == {
            case .SIGNATURE; quick_sort(
                sorted_procs, xx (a: *Procedure_Record, b: *Procedure_Record, using user_data: *type_of(capture)) -> int {
                    return lev(decode(*a.type), query, dp_allocation) - lev(decode(*b.type), query, dp_allocation);
                }, *capture
            );
            case .NAME; quick_sort(
                sorted_procs, xx (a: *Procedure_Record, b: *Procedure_Record, using user_data: *type_of(capture)) -> int {
                    return lev(decode(*a.name), query, dp_allocation) - lev(decode(*b.name), query, dp_allocation);
                }, *capture
            );
            }
        }
        line.y += line.h;
    }
    
    scroll_region := Rect.{
        line.x, line.y + pixels,
        line.w, 0.65 * region.h,
    };
    
    K :: .7;
    color := Vector4.{K, K, K, 1};

    pad := floor(font.default_line_spacing * .5 + .5);

    vertical_theme := our_scroll_theme();
    vertical_theme.margin_flags = 0;
    vertical_theme.region_background.frame_color.w = 0;

    horizontal_theme := vertical_theme;
    {   using horizontal_theme;
        direction = .HORIZONTAL;
        scrollbar_nib_theme.rectangle_shape.frame_thickness_type = .RELATIVE_TO_HEIGHT;
        scrollbar_nib_theme.rectangle_shape.roundedness_type =     .RELATIVE_TO_HEIGHT;
        region_background.shape.roundedness_type =                 .RELATIVE_TO_HEIGHT;
        scrollbar_background.shape.roundedness_type =              .RELATIVE_TO_HEIGHT;
        region_background.shape.rounding_flags =    .NORTHWEST | .NORTHEAST;
        scrollbar_background.shape.rounding_flags = .SOUTHWEST | .SOUTHEAST;
    }

    horizontal_region, inside_horizontal := begin_scrollable_region(scroll_region, *horizontal_theme);
    vertical_region, inside := begin_scrollable_region(inside_horizontal, *vertical_theme);

    scrollbar_width := inside_horizontal.w - inside.w;

    x := inside.x + pad - search_scroll_value_horizontal;
    y := inside.y  - search_scroll_value_vertical;
    
    x1 := x+inside.w;
    max_width := 0;
    hovered_record: *Procedure_Record;
    for sorted_procs {
        c  := color;
        y1 := y+font.default_line_spacing;
        if (cursor_pos.y >= y) && (cursor_pos.y <= y1)
        && (cursor_pos.x >= x) && (cursor_pos.x <= x1) {
            hovered_record = it;
            c = .{1, 1, 1, 1};
        }
        
        y += xx font.default_line_spacing;
        line  := tprint("% :: %", decode(*it.name), decode(*it.type));
        width := Simp.draw_text(font, xx x, xx y, line, c);
        if width > max_width then max_width = width;
    }
    if (cursor_pos.y < inside.y) || (cursor_pos.y > inside.y+inside.h)
    || (cursor_pos.x < inside.x) || (cursor_pos.x > inside.x+inside.w)
    then hovered_record = null;
    
    // (Allocator_Mode, s64, s64, *void, *void) -> (*void)

    max_y := y - font.default_line_spacing + 2 * font.character_height;
    max_x := x + max_width + scrollbar_width + pad;

    end_scrollable_region(vertical_region, 0, max_y, *search_scroll_value_vertical);
    end_scrollable_region(horizontal_region, max_x, 0, *search_scroll_value_horizontal);
    
    if hovered_record {
        // push_state(font, stat_font);
        font := stat_font;
        push_state(label_theme, .{font=stat_font, text_color=.{1, 1, 1, 1}, alignment=.Left});
        // push_state(label_theme, .{text_color=.{1, 0, 1, 1}, alignment=.Left});
        rect := Rect.{
            region.x,
            scroll_region.y + scroll_region.h + pad,
            scroll_region.w,
            xx label_theme.font.default_line_spacing
        };
        label(rect, decode(*hovered_record.name), *label_theme);
        
        rect.y += font.default_line_spacing * 1.2;
        
        label_theme.font = filename_font; 
        label_theme.text_color = .{.6, .6, .6, 1};
        file := get_file_record(hovered_record);
        text := tprint("%:%", decode(*file.fully_pathed_filename), hovered_record.l0);
        label(rect, text, *label_theme);
        
        state := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT];
        if   state & .START
        then open_editor_to_file_and_line(decode(*file.fully_pathed_filename), hovered_record.l0);
    }
}

#scope_file
search_scroll_value_horizontal : float;
search_scroll_value_vertical   : float;
sorted_procs: []*Procedure_Record;
current_proc_info: *Procedure_Record;;
current_proc_rect: Rect;

Print_Vars :: #import "Print_Vars";
pv :: Print_Vars.print_vars;

push_state :: ($var: Code, val: var.type) #expand {
    old := (#insert var);
    (#insert var) = val;
    `defer (#insert var) = old;
}

lev :: (a: string, b: string, dp_allocation: []int) -> int {
    n, m := a.count, b.count;
    dp: []int = .{(n+1)*(m+1), dp_allocation.data};
    assert(dp.count <= dp_allocation.count);
    memset(dp.data, 0, dp.count*size_of(type_of(dp.data.*)));
    
    for i: 0..n dp[i*(m+1)+0] = i;
    for j: 0..m dp[j] = j;
    for i: 1..n for j: 1..m {
        if a[i-1] == b[j-1]
        then dp[i*(m+1)+j] = dp[(i-1)*(m+1)+(j-1)];
        else dp[i*(m+1)+j] = 1 + min(
            dp[(i-0)*(m+1)+(j-1)],
            dp[(i-1)*(m+1)+(j-0)],
            dp[(i-1)*(m+1)+(j-1)],
        );
    }
    
    return dp[dp.count-1];
}

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