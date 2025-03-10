proc_view_is_dirty := true;

current_filename: string;
current_filepath: string;
current_line_number: s64;

Proc_Info :: struct {
    record: *Procedure_Record;
    metric: float;
}

sorted_procs:   [..] Proc_Info;
proc_heights:   [] float;   // Parallel to sorted_procs.
height_highest: float;

metric_low  := 0.0;
metric_mean := 0.0;
metric_high := 0.0;

current_proc_info: *Proc_Info;
current_proc_rect: Rect;

cursor_pos: Vector2;
current_dx: float;

graph_scroll_value: float;
graph_minimum_size: s32 = 10;

MAX_PROCS_PER_ROW :: 270;

SIZE_NAMES :: string.["Linear", "Log", "Constant"];
SIZE_TYPES :: enum u8 {
    LINEAR   :: 0;
    LOG      :: 1;
    CONSTANT :: 2;
}

Primary_Key :: enum u8 {
    NONE   :: 0;
    MODULE :: 1;
    FILE   :: 2;
}

PRIMARY_KEY_NAMES :: string.["None", "Module", "File"];

Secondary_Key :: enum u8 {
    SIZE   :: 0;
    NAME   :: 1;
    METRIC :: 2;
}

SECONDARY_KEY_NAMES :: string.["Size", "Name", "Metric"];

primary_proc:   (a: Proc_Info, b: Proc_Info) -> s64;
secondary_proc: (a: Proc_Info, b: Proc_Info) -> s64;

get_file_record :: (a: *Procedure_Record) -> *File_Record {
    return codex_help.files[a.file_index];
}

sort_procs :: () {
    array_reset(*sorted_procs);

    for codex_help.procedures {
        if !should_include_modules {
            file := codex_help.files[it.file_index];
            module := codex_help.modules[file.module_index];
            if module.module_type != .MAIN_PROGRAM  continue;
        }

        if it.num_expressions < cast(u32) graph_minimum_size continue;
        
        info := array_add(*sorted_procs);
        info.record = it;
    }

    compare_by_module :: (a: Proc_Info, b: Proc_Info) -> s64 {
        file_a := get_file_record(a.record);
        file_b := get_file_record(b.record);

        module_a := codex_help.modules[file_a.module_index];
        module_b := codex_help.modules[file_b.module_index];
        
        name_a := decode(*module_a.fully_pathed_filename);
        name_b := decode(*module_b.fully_pathed_filename);

        string_diff := compare_strings(name_a, name_b);
        return string_diff;
    }

    compare_by_file :: (a: Proc_Info, b: Proc_Info) -> s64 {
        // @Speed: Could compare the *File_Records against each other first to skip a strcmp
        // if they are the same ... but is adding an unpredictable branch slower? Maybe.
        
        name_a := decode(*get_file_record(a.record).fully_pathed_filename);
        name_b := decode(*get_file_record(b.record).fully_pathed_filename);

        string_diff := compare_strings(name_a, name_b);
        return string_diff;
    }

    compare_by_size :: (a: Proc_Info, b: Proc_Info) -> s64 {
        delta := cast(s64)b.record.num_expressions - cast(s64)a.record.num_expressions;
        return delta;
    }

    compare_by_name :: (a: Proc_Info, b: Proc_Info) -> s64 {
        return compare_strings(decode(*a.record.name), decode(*b.record.name));
    }

    compare_by_metric :: (a: Proc_Info, b: Proc_Info) -> s64 {
        if a.metric < b.metric return -1;
        if a.metric > b.metric return  1;
        return 0;
    }

    compare_by_primary_and_secondary :: (a: Proc_Info, b: Proc_Info) -> s64 {
        if primary_proc {
            value := primary_proc(a, b);
            if value return value;
        }

        value := secondary_proc(a, b);
        return value;
    }
    
    pk := cast(Primary_Key)   current_primary_key;
    sk := cast(Secondary_Key) current_secondary_key;

    if pk == {
        case .NONE;    primary_proc = null;
        case .MODULE;  primary_proc = compare_by_module;
        case .FILE;    primary_proc = compare_by_file;
    }

    if sk == {
        case .SIZE;    secondary_proc = compare_by_size;
        case .NAME;    secondary_proc = compare_by_name;
        case .METRIC;  secondary_proc = compare_by_metric;
    }
        
    compute_metrics(sorted_procs);
    quick_sort(sorted_procs, compare_by_primary_and_secondary);
}

compute_proc_heights :: () {
    heights: [..] float;
    heights.allocator = temp;
    array_resize(*heights, sorted_procs.count);
    
    highest := 1.0;
    for sorted_procs {
        height: float = ---;
        height_kind := cast(SIZE_TYPES) current_height_index;

        proc := it.record;
        
        if height_kind == {
            case .LINEAR;    height = cast(float) proc.num_expressions;
            case .LOG;       MIN_SIZE :: 10;  height = Math.log(cast(float) (1 + (max(proc.num_expressions, MIN_SIZE) - (MIN_SIZE-1)))); // @Hardcode: Consider anything under 10 the same size, so as not to pollute the dynamic range.
            case .CONSTANT;  height = 1;
            case;            height = 0;  // Should not happen!
        }
        
        highest = max(highest, height);
        heights[it_index] = height;
    }

    proc_heights = heights;
    height_highest = highest;
}


draw_graph_rows :: (entire_region: Rect, fg: Vector4) {
    current_proc_info = null;
    
    line_height := 0.15 * window_height;
    if sorted_procs.count > MAX_PROCS_PER_ROW * 5  line_height *= .6;  // Fit more rows!

    line_stride := line_height * 1.2;
    
    compute_proc_heights();

    scroll_theme := our_scroll_theme();
    
    scroll_state, inside := begin_scrollable_region(entire_region, *scroll_theme);

    can_pick := !events_occluded();
    if !is_inside(cursor_pos.x, cursor_pos.y, inside) can_pick = false;
    if background_occluded  can_pick = false;

    top, remainder := cut_top(inside, line_height);

    i0 := cast(s32) 0;

    denom := min(sorted_procs.count, MAX_PROCS_PER_ROW);
    denom =  max(denom, 1);
        
    dx := top.w / cast(float) denom;
    current_dx = dx;

    top.y -= graph_scroll_value;
    
    {
        // scrollable_region already does scissor, but it doesn't clip the bottom for us... probably because
        // when we set up the region we do not know where the bottom is?! Worth thinking about if we can do
        // something better here.

        // Anyway, to clip the bottom, we need to set scissor ourselves.

        push_scissor(inside);
        defer pop_scissor();
        
        while 1 {
            to_display := cast(s32) min(MAX_PROCS_PER_ROW, sorted_procs.count - 1 - i0);
            if to_display <= 0 break;

            if top.y + top.h >= inside.y {
                i1 := i0 + to_display - 1;
                draw_graph_line(top, i0, i1, dx, fg, can_pick);
            }

            top.y += line_stride;
            i0 += to_display;
        }
    }

    end_scrollable_region(scroll_state, inside.x + inside.w, top.y + line_stride, *graph_scroll_value);
}

draw_graph_footer :: (r: Rect) {
    p0, p1, p2, p3 := get_quad(r);
    current_filename = "";
    if current_proc_info {
        proc := current_proc_info.record;

        // @Incomplete
        filename := get_file_record(proc).fully_pathed_filename;
        l0       := proc.l0;

        current_filename = decode(*filename);
        current_filepath = decode(*filename);
        current_line_number = l0;
        
        {
            extra: float;  // How many pixels outward to expand the rect.
            fg: Vector4 = ---;

            gt := cast(Graph_Type) graph_type;
            if gt == .ROWS {
                fg = Vector4.{.9, .9, .9, 1};
                extra = floor(current_dx * .4 + .5);
            } else if gt == .TREEMAP {
                fg = Vector4.{.08, .08, .08, 1};
                extra = get_pixels(false) * .85;
            }

            if extra < 1  extra = 1;
            
            e := expand(current_proc_rect, extra);

            west, remainder0 := cut_left  (e, extra);
            east, remainder1 := cut_right (remainder0, extra);
            top,  remainder2 := cut_top   (remainder1, extra);
            bottom           := cut_bottom(remainder2, extra);

            draw_quad(west,   fg);
            draw_quad(east,   fg);
            draw_quad(top,    fg);
            draw_quad(bottom, fg);
        }

        // Draw text!
        Simp.set_shader_for_text();

        get_name :: (p: *Procedure_Record) -> string {
            return decode(*p.name);
        }
        
        effect: Font_Effects;
        text := get_name(proc);
        font := stat_font;

        yy := p3.y + font.character_height;
        color  := Vector4.{1, 1, 1, 1};
        color2 := Vector4.{.6, .6, .6, 1};
        Simp.draw_text(font, xx p0.x, xx yy, text, color, effect);

        mp := THE_METRICS[current_metric_index].proc;
        m := *proc.metrics;

        score_string := get_score_string(m, mp);
        
        if mp == metric_blend {
            font := stat_small_font;

            metric_x_1 := p0.x + window_width * .68;
            metric_x_2 := p0.x + window_width * .81;
            metric_top_y := p3.y + font.character_height;

            metric_x := metric_x_1;
            metric_y := metric_top_y;

            size_string := tprint("%  size: %", score_string, proc.num_expressions);
            size_width := Simp.prepare_text(font, size_string, effect);
            Simp.draw_prepared_text(font, xx metric_x, xx metric_y, color2, effect);
            metric_y += xx font.character_height * 1.2;
            
            for THE_METRICS {
                if it.proc == metric_blend continue;
                s := get_score_string(m, it.proc);
                Simp.draw_text(font, xx metric_x, xx metric_y, s, color2, effect);
                metric_y += xx font.character_height * 1.2;
                if it_index == 5 {
                    metric_y = metric_top_y;
                    metric_x = metric_x_2;
                }
            }
        } else {
            size_string := tprint("%  size: %", score_string, proc.num_expressions);
            size_width := Simp.prepare_text(font, size_string, effect);
            Simp.draw_prepared_text(font, xx (p1.x - size_width), xx yy, color2, effect);
        }

        
        yy += xx font.character_height * 1.2;

        file := get_file_record(proc);
        text = tprint("%:%", decode(*file.fully_pathed_filename), proc.l0);
        Simp.draw_text(filename_font, xx p0.x, xx yy, text, color2, effect);
    }
}

get_score_string :: (m: *Metrics, proc: type_of(Metric_Info.proc)) -> string { // In temporary storage.
    // Warning: If you call this with Blend, it looks at current_proc_info, not m.
    
    if proc == {
      case metric_if_density;
        return tprint("if points: %", m.if_points);
      case metric_if_depth;
        return tprint("Maximum 'if' depth: %", m.maximum_if_depth);
      case metric_loop_depth;
        return tprint("Maximum loop depth: %", m.maximum_loop_depth);
      case metric_reassignment_density;
        return tprint("Assignments: %", m.reassignments);
      case metric_global_reads_density;
        return tprint("Global Reads: %", m.global_reads);
      case metric_global_writes_density;
        return tprint("Global Writes: %", m.global_writes);
      case metric_allocations;
        return tprint("Allocations: %", m.allocations);
      case metric_frees;
        return tprint("Frees: %", m.frees);
      case metric_call_locality_module;
        return tprint("Call out-module points: %", m.total_calls - m.same_module_calls);
      case metric_call_locality_file;
        return tprint("Call out-file points: %", m.total_calls - m.same_file_calls);
      case metric_call_constancy;
        return tprint("Nonconstant calls: %", m.nonconstant_calls);
      case metric_blend;
        return tprint("Blend: %", formatFloat(current_proc_info.metric, trailing_width=3));
    }

    return "";
}

draw_graph_line :: (line_region: Rect, index0: s32, index1: s32, dx: float, fg: Vector4, can_pick: bool) {
    Simp.set_shader_for_color(false);

    bg := darken(fg, 0.8);
    
    cursor_color := whiten(fg, 0.67);
    cursor_color_bg := Vector4.{w=.7};
    
    Simp.set_shader_for_color(true);
    draw_quad(line_region, bg);
    
    n := sorted_procs.count;
    if !n {
        return;
    }
    
    ilength := 1 / cast(float) n;

    x  := line_region.x;
    y0 := line_region.y;
    y1 := line_region.y + line_region.h;

    for index: index0..index1 {
        proc := *sorted_procs[index];
        
        x0 := x;
        x1 := x + dx;

        if (cursor_pos.x >= x0) && (cursor_pos.x <= x1) && (cursor_pos.y >= y0) && (cursor_pos.y <= y1) && can_pick {
            current_proc_info = proc;
            current_proc_rect = get_rect(x, line_region.y, dx, line_region.h);
        }

        fraction := proc_heights[index] / cast(float) height_highest;
        Clamp(*fraction, 0, 1);

        filled := fraction * line_region.h;
        r := get_rect(x, y0 + (line_region.h - filled), dx, filled);
        
        color := get_color_for_current_metric(proc.metric, metric_low, metric_mean, metric_high);
        //print("scale % quad % %\n", scale, q0, q2);

        q0, q1, q2, q3 := get_quad(r);
        draw_quad(q0, q1, q2, q3, color);
        
        x = x1;
    }
}



draw_quad :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, color: Vector4) {
    Simp.immediate_quad(p0, p1, p2, p3, color);  //  @Speed
}

draw_quad :: (p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
              u0: Vector2, u1: Vector2, u2: Vector2, u3: Vector2,
              color: Vector4) {
    Simp.immediate_quad(p0, p1, p2, p3, color, u0, u1, u2, u3);  //  @Speed
}


darken :: (color: Vector4, amount: float) -> Vector4 {
    result: Vector4;

    result.x = lerp(color.x, 0, amount);
    result.y = lerp(color.y, 0, amount);
    result.z = lerp(color.z, 0, amount);
    result.w = color.w;

    return result;
}

whiten :: (color: Vector3, amount: float) -> Vector3 {
    result: Vector3;

    result.x = lerp(color.x, 1, amount);
    result.y = lerp(color.y, 1, amount);
    result.z = lerp(color.z, 1, amount);

    return result;
}

whiten :: (color: Vector4, amount: float) -> Vector4 {
    result: Vector4;

    result.xyz = whiten(color.xyz, .5);
    result.w = color.w;

    return result;
}

draw_quad :: (r: Rect, color: Vector4) {
    p0, p1, p2, p3 := get_quad(r);
    draw_quad(p0, p1, p2, p3, color);
}


Math :: #import "Math";

our_scroll_theme :: () -> Scrollable_Region_Theme {
    scroll_theme: Scrollable_Region_Theme;

    scroll_theme.region_background.frame_color.w = 0;
    scroll_theme.region_background.color = .{.15, .02, .02, 1};
    scroll_theme.region_background.shape.rounding_flags = 0;
    
    // Colors @Copypasta from Dropdown_Theme. We should do
    // a whole theme on these?!
    nib := *scroll_theme.scrollbar_nib_theme;
    nib.surface_color       = .{.8, .2, .05, 1};
    nib.surface_color_over  = .{.9, .3, .15, 1};
    nib.surface_color_flash = .{.95, .75, .55, 1};
    nib.surface_color_down  = .{.99, .4, .25, 1};

    nib.frame\ _color       = .{.9, .5, .35, 1};
    nib.frame\ _color_over  = .{.95, .6, .45, 1};
    nib.frame\ _color_flash = .{.99, .95, .85, 1};
    nib.frame\ _color_down  = .{.99, .7, .55, 1};

    b := *scroll_theme.scrollbar_background;
    
    b.color             = .{.3, .07, .05, 1};
    b.frame_color       = .{.6, .37, .35, 1};

    return scroll_theme;
}
