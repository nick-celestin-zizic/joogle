graph_type: s32 = xx Graph_Type.TREEMAP;

Graph_Type :: enum u8 {
    ROWS    :: 0;
    TREEMAP :: 1;
}

graph_type_names :: string.["Rows", "Treemap"];



draw_metrics :: (region: Rect) {
    if !codex_help_is_valid {
        draw_codex_view_selection(region);
        return;
    }

    if proc_view_is_dirty {
        proc_view_is_dirty = false;
        sort_procs();
    }
    
    h_over_w := (window_height / cast(float) window_width);
    
    left\_margin := 0.014;
    right_margin := 0.02;
    ymargin := 0.05;
    
    graph_region := get_rect(region.x + left_margin * region.w, region.y + 0.15 * region.h, (1 - (left_margin + right_margin)) * region.w, .7 * region.h);

    label_color : Vector4;
    label_color = Vector4.{1, .7, .7, 1};

    gt := cast(Graph_Type) graph_type;
    if gt == .ROWS {
        draw_graph_rows(graph_region, label_color);
    } else if gt == .TREEMAP {
        draw_treemap(graph_region, label_color);
    }
    
    draw_graph_footer(graph_region);

    if current_proc_info { // This will be null if background is occluded, etc.
        state := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT];
        if state & .START {
            record := current_proc_info.record;
            open_editor_to_file_and_line(decode(*get_file_record(record).fully_pathed_filename), record.l0);
        }
    }
    
/*
    button_theme: Button_Theme;  // This will have the default Button_Theme values.
    button_theme.font = button_font;
    button_theme.enable_variable_frame_thickness = true; 
    // 'k' is some resolution-adjusting unit of distance. Right now it is
    // 1/10 of the screen height, so, 108 pixels at 1920x1080.
    k := window_height * .1;
    r := get_rect(k*.5, 5.1*k, 3*k, k);

    button_theme.label_theme.alignment = .Left;
    pressed := button(r, "Hello, Sailor!", *button_theme);
    if pressed {
        sort_method += 1;
        if sort_method > .BY_NAME sort_method = 0;

        proc_view_is_dirty = true;
    }
*/
    
    //
    // Dropdown stuff.
    //
    // (Overwrites r, and we use it in the checkbox below.)
    //

    top_margin := region.w * .01;

    r: Rect;  // For widgets.
    l: Rect;  // For labels.

    w := region.w;
    h := region.h;
    
    label_theme: Label_Theme;
    label_theme.alignment = .Right;
    
    label_width_1 := w * .125;

    button_height := region.h * .03;
    top_y := top_margin + button_height;
    {
        right_dropdown_width := w*.15;
        r = get_rect(region.x + w - right_dropdown_width*1.1, button_height, right_dropdown_width, button_height);

        l = r;
        l.x -= label_width_1;
        l.w = r.x - l.x;
        
        dropdown_theme := *default_overall_theme.dropdown_theme;

        //
        // The metric choice dropdown:
        //
        if !metric_names {
            // Initialize these because 'dropdown' wants them in a separate array.
            // Not great I guess!
            array_resize(*metric_names, THE_METRICS.count);
            for THE_METRICS metric_names[it_index] = it.name;
        }

        left_dropdown_width := w*.08;
        
        {
            //
            // The dropdown to pick the view mode:
            //

            d := get_rect(region.x + label_width_1 + label_width_1/16, button_height, left_dropdown_width, button_height);
            dl := d;
            dl.x -= label_width_1;
            dl.w = d.x - dl.x;
            
            view_mode_dropdown_theme := default_overall_theme.dropdown_theme;
            {
                using view_mode_dropdown_theme;
                theme_for_current_value.surface_color        = .{.5, .07, .45, 1};
                theme_for_current_value.surface_color_over   = .{.7, .35, .65, 1};
                theme_for_current_value.surface_color_flash  = .{.85, .75, .95, 1};
                theme_for_current_value.surface_color_down   = .{.6, .4, .65, 1};

                theme_for_current_value.frame\  _color       = .{.7, .37, .75, 1};
                theme_for_current_value.frame\  _color_over  = .{.85, .6, .95, 1};
                theme_for_current_value.frame\  _color_flash = .{.95, .95, .95, 1};
                theme_for_current_value.frame\  _color_down  = .{.78, .6, .85, 1};

                theme_for_current_choice.surface_color       = .{.8, .2, .45, 1};
                theme_for_current_choice.surface_color_over  = .{.9, .5, .75, 1};
                theme_for_current_choice.surface_color_flash = .{.95, .75, .95, 1};
                theme_for_current_choice.surface_color_down  = .{.99, .4, .65, 1};

                theme_for_current_choice.frame\ _color       = .{.9, .5, .8, 1};
                theme_for_current_choice.frame\ _color_over  = .{.95, .7, .95, 1};
                theme_for_current_choice.frame\ _color_flash = .{.99, .95, .85, 1};
                theme_for_current_choice.frame\ _color_down  = .{.99, .7, .95, 1};

                theme_for_each\  _choice.surface_color       = .{.35, .05, .45, 1};
                theme_for_each\  _choice.surface_color_over  = .{.55, .32, .62, 1};
                theme_for_each\  _choice.surface_color_flash = .{.75, .55, .75, 1};
                theme_for_each\  _choice.surface_color_down  = .{.60, .20, .50, 1};

                theme_for_each\  _choice.frame\ _color       = .{.35, .30, .40, 1};
                theme_for_each\  _choice.frame\ _color_over  = .{.45, .35, .45, 1};
                theme_for_each\  _choice.frame\ _color_flash = .{.95, .85, .95, 1};
                theme_for_each\  _choice.frame\ _color_down  = .{.70, .55, .75, 1};
            }
            
            dropdown(d, graph_type_names, *graph_type, *view_mode_dropdown_theme);
            label(dl, "View Mode", *label_theme);
            // gt = cast(Graph_Type) graph_type;
        }
        
        if gt == .ROWS {
            dropdown(r, metric_names, *current_metric_index, dropdown_theme);
            label(l, "Metric", *label_theme);

            //
            // The bar height choice dropdown:
            //

            r.y += r.h * 1.2;
            l.y = r.y;
            dropdown(r, SIZE_NAMES, *current_height_index, dropdown_theme);
            label(l, "Bar Height", *label_theme);

            //
            // The primary and secondary key dropdowns:
            // 

            sort_margin := label_width_1 + right_dropdown_width;
            
            r = get_rect(region.x + sort_margin + label_width_1, region.y + top_y, left_dropdown_width, button_height);
            l = r;
            l.x -= label_width_1;
            l.w = r.x - l.x;
            
            dropdown(r, PRIMARY_KEY_NAMES, *current_primary_key, dropdown_theme);
            label(l, "Primary Sort", *label_theme);
            
            r.y += r.h * 1.2;
            l.y = r.y;
            dropdown(r, SECONDARY_KEY_NAMES, *current_secondary_key, dropdown_theme);
            label(l, "Secondary Sort", *label_theme);

            // Checkbox for whether we include modules.

            {
                checkbox_theme: Checkbox_Theme;

                s := r;
                s.y += s.h * 1.2;
                
                pressed := base_checkbox(s, "", should_include_modules, *checkbox_theme);
                l.y = s.y;
                label(l, "Include Modules", *label_theme);

                if pressed {
                    should_include_modules = !should_include_modules;
                    proc_view_is_dirty = true;
                }
            }

            {
                dx := r.w + l.w;
                r.x += dx;
                l.x += dx;

                r.y = top_y;
                l.y = top_y;
                
                text := tprint("%", graph_minimum_size);
                label(l, "Minimum Size", *label_theme);
                input_theme: Number_Input_Theme;
                changed_ir := number_input(r, text, *graph_minimum_size, 0, 90000, *input_theme);
                //        r.y -= line_height;
            }
        } else if gt == .TREEMAP {
            dropdown(r, metric_names, *current_metric_index, dropdown_theme);
            label(l, "Metric", *label_theme);

            
            sort_margin := label_width_1 + right_dropdown_width;
            
            r = get_rect(region.x + sort_margin + label_width_1, button_height, left_dropdown_width*1.7, button_height);
            l = r;
            l.x -= label_width_1;
            l.w = r.x - l.x;
            
            dropdown(r, BORDER_NAMES, *border_display_type_index, dropdown_theme);
            label(l, "Borders", *label_theme);
        }
    }

    /*
    //
    // Text Input stuff:
    //

    text_theme: Text_Input_Theme;
    text_theme.font = button_font;
    
    r = get_rect(1*k, 4*k, 5*k, button_font.character_height*1.35);
    input_a.rect = r;
    draw(*input_a.input, r, *text_theme);
*/    
}


pre_prepared_if_depth_max := -1.0;
pre_prepared_loop_depth_max := -1.0;
pre_prepared_allocations := -1.0;
pre_prepared_frees := -1.0;

prep_global_bound_metrics :: (procs: [] Proc_Info) {
    // Some metrics, in order to be used in 'blend', require us to
    // rate them relative to the program as a whole, otherwise there
    // is no way to control scale for the blend. Currently 'maximum_if_depth'
    // is one of these but there will probably be more.

    pre_prepared_if_depth_max   = 1.0;  // Because we divide by this in metric_blend!
    pre_prepared_loop_depth_max = 1.0;  // Because we divide by this in metric_blend!

    for * info: procs {
        f := cast(float) info.record.metrics.maximum_if_depth;
        pre_prepared_if_depth_max = max(pre_prepared_if_depth_max, f);

        f = cast(float) info.record.metrics.maximum_loop_depth;
        pre_prepared_loop_depth_max = max(pre_prepared_loop_depth_max, f);

        f = cast(float) info.record.metrics.allocations;
        pre_prepared_allocations = max(pre_prepared_allocations, f);
        
        f = cast(float) info.record.metrics.frees;
        pre_prepared_frees = max(pre_prepared_frees, f);
    }

}


prep_global_bound_metrics :: (procs: [] *Procedure_Record) {
    // @Copypasta from other prep_global_bound_metrics().
    // @Cleanup: We only need this one, so long as we have that other array.

    pre_prepared_if_depth_max   = 1.0;  // Because we divide by this in metric_blend!
    pre_prepared_loop_depth_max = 1.0;  // Because we divide by this in metric_blend!

    for record: procs {
        m := *record.metrics;
        
        f := cast(float) m.maximum_if_depth;
        pre_prepared_if_depth_max = max(pre_prepared_if_depth_max, f);

        f = cast(float) m.maximum_loop_depth;
        pre_prepared_loop_depth_max = max(pre_prepared_loop_depth_max, f);

        f = cast(float) m.allocations;
        pre_prepared_allocations = max(pre_prepared_allocations, f);
        
        f = cast(float) m.frees;
        pre_prepared_frees = max(pre_prepared_frees, f);
    }
}

compute_metrics :: (procs: [] Proc_Info) {
    current_metric := THE_METRICS[current_metric_index].proc;

    if current_metric == metric_blend {
        prep_global_bound_metrics(procs);
    }

    for * info: procs {
        metric := current_metric(info.record);
        info.metric = metric;
    }

    // sorted_metrics may contain -1 in any of its slots; in that case we need to
    // skip that element, rather than incorporating it into the mean.

    valid_count := 0;

    metric_sum: float;
    
    for * info: procs {
        metric := info.metric;
        
        if metric < 0 continue;

        if valid_count == 0 {
            metric_low  = metric;
            metric_high = metric;
        } else {
            metric_low  = min(metric_low, metric);
            metric_high = max(metric_high, metric);
        }

        metric_sum += metric;
        valid_count += 1;
    }

    if !valid_count {
        metric_low  = 0;
        metric_high = 0;
        metric_mean = 0;

        return;
    }

    metric_mean = metric_sum / cast(float) valid_count;
}

get_color_for_current_metric :: (metric: float64, low: float64, mean: float64, high: float64) -> Vector4 {
    // For now, we hardcode. We may later factor this out.

    cold :: Vector4.{0.05, .8, 1, 1};
    hot  :: Vector4.{.95, .5, .01, 1};

    mid  :: Vector4.{.85, .85, .85, 1};
    gray :: Vector4.{.45, .45, .45, 1};    

    if metric < 0    return gray;
    if mean == 0     return mid;
    if mean == high  return mid;
    
    if metric <= mean {
        t := cast(float)(metric / mean);
        return lerp(cold, mid, t);
    } else {
        t := cast(float)((metric - mean) / (high - mean));
        return lerp(mid, hot, t);
    }
}


//
// The metrics are below:
//

Metric_Info :: struct {
    proc: (*Procedure_Record) -> float;
    name:    string;   // Displayed in the UI.
    comment: string;   // Displayed in the UI.
}

metric_names: [..] string;  // Used for dropdown(). Messy.

THE_METRICS :: Metric_Info.[
        .{ metric_if_density,
           "'if' Density",
           "The number of if/else statements per expression." },
        .{ metric_if_depth,
           "Maximum 'if' Depth",
           "The deepest nesting of 'if' in the function." },
        .{ metric_loop_depth,
           "Maximum Loop Depth",
           "The deepest nesting of for/while loops in the function." },
        .{ metric_reassignment_density,
           "Assignments",
           "The number of assignments (not counting declarations)." },
        .{ metric_global_reads_density,
           "Global Reads",
           "Read operations on global variables." },
        .{ metric_global_writes_density,
           "Global Writes",
           "Write operations on global variables." },
        .{ metric_allocations,
           "Heap Allocations",
           "Call to heap allocations in modules/Basic." },
        .{ metric_frees,
           "Heap Frees",
           "Call to heap frees in modules/Basic." },
        .{ metric_call_locality_module,
           "Call Locality (module)",
           "Are calls within the same module?" },
        .{ metric_call_locality_file,
           "Call Locality (file)",
           "Are calls within the same file?" },
        .{ metric_call_constancy,
           "Call Constancy",
           "Are we calling procedures that are compile-time constants?" },
        .{ metric_blend,
           "Blend",
           "A blend of all the other metrics." }
];
    
metric_if_density :: (proc: *Procedure_Record) -> float {
    size := proc.num_expressions;

    if size == 0  return -1;  // Non-measurable!

    return proc.metrics.if_points / cast(float) size;
}

metric_if_depth :: (proc: *Procedure_Record) -> float {
    return cast(float) proc.metrics.maximum_if_depth;
}

metric_loop_depth :: (proc: *Procedure_Record) -> float {
    return cast(float) proc.metrics.maximum_loop_depth;
}

metric_allocations :: (proc: *Procedure_Record) -> float {
    return cast(float) proc.metrics.allocations;
}

metric_frees :: (proc: *Procedure_Record) -> float {
    return cast(float) proc.metrics.frees;
}

metric_reassignment_density :: (proc: *Procedure_Record) -> float {
    size := proc.num_expressions;

    if size == 0  return -1;  // Non-measurable!

    return proc.metrics.reassignments / cast(float) size;
}

metric_global_reads_density :: (proc: *Procedure_Record) -> float {
    size := proc.num_expressions;

    if size == 0  return -1;  // Non-measurable!

    return proc.metrics.global_reads / cast(float) size;
}

metric_global_writes_density :: (proc: *Procedure_Record) -> float {
    size := proc.num_expressions;

    if size == 0  return -1;  // Non-measurable!

    return proc.metrics.global_writes / cast(float) size;
}

metric_call_locality_module :: (proc: *Procedure_Record) -> float {
    calls := proc.metrics.total_calls;

    if calls == 0 return -1;  // Non-measurable!

    return 1 - proc.metrics.same_module_calls / cast(float) calls;
}

metric_call_locality_file :: (proc: *Procedure_Record) -> float {
    calls := proc.metrics.total_calls;

    if calls == 0 return -1;  // Non-measurable!

    return 1 - proc.metrics.same_file_calls / cast(float) calls;
}

metric_call_constancy :: (proc: *Procedure_Record) -> float {
    calls := proc.metrics.total_calls;

    if calls == 0 return -1;  // Non-measurable!

    return proc.metrics.nonconstant_calls / cast(float) calls;
}

metric_blend :: (proc: *Procedure_Record) -> float {
    assert(pre_prepared_if_depth_max >= 0);  // We must have run this before running the metrics!
    assert(pre_prepared_loop_depth_max >= 0);  // We must have run this before running the metrics!

    ifs         := metric_if_density(proc);
    if_depth    := metric_if_depth(proc) / pre_prepared_if_depth_max; 
    loop_depth  := metric_loop_depth(proc) / pre_prepared_loop_depth_max; 
    allocations := metric_allocations(proc) / pre_prepared_allocations; 
    frees       := metric_frees(proc) / pre_prepared_frees; 
    assigns     := metric_reassignment_density(proc);
    reads       := metric_global_reads_density(proc);
    writes      := metric_global_writes_density(proc);
    call_module := metric_call_locality_module(proc);
    call_file   := metric_call_locality_file(proc);
    call_const  := metric_call_constancy(proc);

    // We have the difficulty that if some of these are -1, we want to ignore them!

    num_valid := 0;
    sum: float;

    Sum :: (metric: float, factor: float) #expand {
        if metric >= 0 {
            num_valid += 1;
            sum += metric * factor;
        }
    }

    Sum(ifs,         1);
    Sum(if_depth,    2);
    Sum(loop_depth,  1.5);
    Sum(assigns,     1);
    Sum(reads,       2);
    Sum(writes,      2);
    Sum(allocations, 3);
    Sum(frees,       3);
    Sum(call_module, .7);
    Sum(call_file,   .5);
    Sum(call_const,  .7);
    if !num_valid return -1;

    return sum;
}



editor_process: Process.Process;
open_editor_to_file_and_line :: (filename: string, line: s64) {
    // command := tprint(editor_command, line, tprint("\"%\"", filename));
    command := tprint(editor_command, line, filename);
    strings := Process.break_command_into_strings(command);
    log("Running: %\n", strings);
    
    ok, result := Process.get_process_result(*editor_process, 0);
    if ok && result.type == .STILL_RUNNING {
        Process.kill_process(*editor_process);
        Process.deinit(*editor_process);
        editor_process = .{};
    }
    Process.create_process(*editor_process, ..strings);
    // Process.run_command(..strings);
}    
