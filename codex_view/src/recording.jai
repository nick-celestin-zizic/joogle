draw_recording_controls :: (starting_region: Rect, button_height: float) -> (reaminder: Rect, desired_y1: float) {
    scrollbar_height := button_height;
    pips_height := 3 * button_height;
    vmargin := .5 * button_height;
    
    margin, below_top_margin := cut_top(starting_region, vmargin);

    buttons_area, below_buttons_area := cut_top(below_top_margin, button_height * 2);
    
    button_width := button_height * 10;
    left_buttons := cut_left(buttons_area, button_width);
    record_rect, remainder := cut_top(left_buttons, button_height);
    stop_rect := cut_top(remainder, button_height);

    right_widgets     := cut_right(buttons_area, button_width*4);
    right_widgets_top := cut_top(right_widgets, button_height);

    checkbox_rect, _1 := cut_right(right_widgets_top, button_width*.6);
    spacer, _1a       := cut_right(_1,  button_width*.1);
    metric_dropdown_rect, _2  := cut_right(_1a, button_width);
    metric_dropdown_label, _3 := cut_right(_2, button_width * .4);
    sort_dropdown_rect, _4    := cut_right(_3, button_width);
    sort_dropdown_label, _5   := cut_right(_4, button_width * .4);
    
    button_theme: Button_Theme;  // This will have the default Button_Theme values.

    gray := Vector4.{.25, .25, .25, 1};
    gray_frame := Vector4.{.08, .08, .08, 1};
    
    if currently_recording {
        pressed_stop := button(stop_rect, "Stop Recording", *button_theme);
        rounded_rectangle(record_rect, button_theme.rectangle_shape, gray, gray_frame);
        if pressed_stop do_stop_recording();
    } else {
        pressed_record := button(record_rect, "Record", *button_theme);
        rounded_rectangle(stop_rect, button_theme.rectangle_shape, gray, gray_frame);
        if pressed_record do_start_recording();
    }


    checkbox_theme := *default_overall_theme.checkbox_theme;
    checkbox_pressed := base_checkbox(checkbox_rect, "Differential", full_frame_metric_is_differential, checkbox_theme);
    if checkbox_pressed full_frame_metric_is_differential = !full_frame_metric_is_differential;

    dropdown_theme := *default_overall_theme.dropdown_theme;
    dropdown(metric_dropdown_rect, FULL_FRAME_METRIC_NAMES, *current_full_frame_metric, dropdown_theme);

    label_theme: Label_Theme;
    label_theme.alignment = .Right;
    label(metric_dropdown_label, "Metric", *label_theme);
    

    dropdown(sort_dropdown_rect, RECORDING_SORT_NAMES, *current_recording_sort, dropdown_theme);
    label(sort_dropdown_label, "Sort", *label_theme);

    _vert_spacer, below_vert_spacer := cut_top(below_buttons_area, button_height*.2);
    pips, below_pips := cut_top(below_vert_spacer, pips_height);

    hovering_over_index: s32 = -1;
    
    r := the_recording;
    if r {
        evaluate_metric(r);

        sorted: [..] *Recording_Snapshot;
        sorted.allocator = temp;
        array_resize(*sorted, r.recording_snapshots.count);

        for * r.recording_snapshots  sorted[it_index] = it;
        
        if cast(Recording_Sort) current_recording_sort == {
          case .FRAME_INDEX;
            // No need to do anything; they are sorted.
          case .METRIC;
            quick_sort(sorted, x => x.metric);
        }
        
        can_pick_boxes := !events_occluded();
        if !is_inside(cursor_pos.x, cursor_pos.y, pips) can_pick_boxes = false;
        
        denom := cast(float) r.recording_snapshots.count;
        if denom < 1  denom = 1;
        
        PIP_WIDTH_MIN :: 4.0;
        pip_width_max := pips.w / 200;
        pip_width := pips.w / denom;
        Clamp(*pip_width, PIP_WIDTH_MIN, pip_width_max);

        pip_rect := cut_left(pips, pip_width);

        selected_drawn_index: s32 = -1;
        newly_selected_index: s32 = -1;
        
        Simp.set_shader_for_color(false);
        x1 := pips.x + pips.w;
        for rs: sorted {
            if pip_rect.x + pip_rect.w < pips.x continue;

            rs.pip_rect = pip_rect;

            // @Copypasta from draw_live_allocations.
            if can_pick_boxes && is_inside(cursor_pos.x, cursor_pos.y, pip_rect) {
                hovering_over_index = rs.unsorted_index;
                state := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT];
                if state & .START {
                    newly_selected_index = rs.unsorted_index;
                    selected_drawn_index = newly_selected_index;
                }
            }

            if (rs.unsorted_index == r.selected_index) && (newly_selected_index == -1) {
                selected_drawn_index = r.selected_index;
            }
            
            draw_quad(pip_rect, rs.metric_color);

            pip_rect.x += pip_width;
            if pip_rect.x >= x1 break;
        }

        if newly_selected_index != -1 {
            r.selected_index = newly_selected_index;
        }
        
        if hovering_over_index  != -1 draw_box_selection(r.recording_snapshots[hovering_over_index] .pip_rect, .{.5, .9, .7, 1});
        if selected_drawn_index != -1 draw_box_selection(r.recording_snapshots[selected_drawn_index].pip_rect, .{1, 1, 1, 1});
    }
    
    scrollbar_region, below_scrollbar_region := cut_top(below_pips, scrollbar_height);

    desired_y1 := scrollbar_region.y + scrollbar_region.h;
    remaining_region := below_scrollbar_region;
    drew_snapshot := false;
    if r {
        to_show := hovering_over_index;
        if to_show == -1  to_show = r.selected_index;

        if to_show != -1 {
            snap := *r.recording_snapshots[to_show].snapshot;
            update_metrics(snap);
            alloc_boxes_height := 0.14 * window_height;  // @Copypasta
            freed_boxes_height := 0.10 * window_height;  // @Copypasta
            remaining_region, desired_y1 = draw_one_snapshot(snap, remaining_region, tprint("Recorded Frame %", snap.frame_index), button_height, alloc_boxes_height, freed_boxes_height, 0x70ff_ffff_ffff_ffff); // Other calls to draw_one_snapshot use identifier >= 0. So we'd like to use -1, but @DebugMe: When we do that the identifier doesn't work. Is there some constraint forcing it to be nonnegative? We do 0x70ff* because if we do 0x7fff* then some widgets don't work but others do. So there is definitely a problem here.  -jblow, 3 August 2022
            drew_snapshot = true;
        }
    }

    if !drew_snapshot {  // Snapshot-drawing adds its own offset to desired_y0. If we didn't do that, do it here.
        vertical_space_to_reserve := button_height * 20; // :VerticalSpace
        desired_y1 += vertical_space_to_reserve;
    }
    
    return remaining_region, desired_y1;
}

the_recording: *Recording;
currently_recording: bool;

do_start_recording :: () {
    if the_recording {
        fini(the_recording);
    }
    
    the_recording = New(Recording);
    currently_recording = true;
}

do_stop_recording :: () {
    currently_recording = false;
}

add_current_snapshot_to_recording :: () {
    assert(currently_recording);
    assert(the_recording != null);

    snap := *snapshots[0];

    new := array_add(*the_recording.recording_snapshots);
    new.snapshot = copy_snapshot(snap);
    new.snapshot.is_recorded_frame = true;
    new.unsorted_index = cast(s32) the_recording.recording_snapshots.count-1;
}

Recording :: struct {
    first_frame_index: s32; // Currently unused.
    selected_index: s32 = -1;
    recording_snapshots: [..] Recording_Snapshot;
}

Recording_Snapshot :: struct {
    snapshot: Snapshot;
    pip_rect: Rect;

//    frame_index: s32; // This frame index is generated by the client here.
    unsorted_index: s32;  // This is the index in Recording.recording_snapshots.
    
    metric: float64;
    // temporary_value: float;  // Used when computing 'metric'.
    metric_color: Vector4;
}

fini :: (using r: *Recording) {
    for * recording_snapshots fini(*it.snapshot);
    free(recording_snapshots.data);
}
 

//
// I am doing these metrics in a structurally different way
// than what is going on in draw_metrics.jai, where we register
// procedures instead of enums. I'll just see which I like better
// and then convert them for uniformity.  -jblow, 31 July 2022.
//
Full_Frame_Metric :: enum u8 {
    LIVE_HEAP_SIZE             :: 0;
    LIVE_HEAP_ALLOCATIONS      :: 1;
    BYTES_ALLOCATED_THIS_FRAME :: 2;
    NUM_ALLOCATIONS_THIS_FRAME :: 3;
    BYTES_FREED_THIS_FRAME     :: 4;
    NUM_FREES_THIS_FRAME       :: 5;
}

FULL_FRAME_METRIC_NAMES :: string.[
    "Live Heap Size",
    "Live Heap Allocations",
    "New Bytes Allocated",
    "New Allocations",
    "Bytes Freed",
    "Number of Frees"
];

#assert FULL_FRAME_METRIC_NAMES.count == enum_highest_value(Full_Frame_Metric) + 1;


Recording_Sort :: enum u8 {
    FRAME_INDEX :: 0;
    METRIC      :: 1;
}

RECORDING_SORT_NAMES :: string.[
    "Frame Index",
    "Metric"
];

#assert RECORDING_SORT_NAMES.count == enum_highest_value(Recording_Sort) + 1;


Additional_Alloc_View :: enum u8 {
    NONE              :: 0;
    NEW_AND_FREED     :: 1;
    NEW_AND_NOT_FREED :: 2;
    FREED_AND_NOT_NEW :: 3;
    ALL               :: 4;
}

ADDITIONAL_ALLOC_VIEW_NAMES :: string.[
    "No Additional View",
    "New and Freed",
    "New and Not Freed",
    "Freed and Not New",
    "All Additional Views"
];

#assert ADDITIONAL_ALLOC_VIEW_NAMES.count == enum_highest_value(Additional_Alloc_View) + 1;

current_full_frame_metric: s32; // Full_Frame_Metric;
current_recording_sort: s32;  // Recording_Sort;
current_additional_alloc_view: s32;  // Additional_Alloc_View

full_frame_metric_is_differential  := false;

evaluate_metric :: (r: *Recording) {
    diff := full_frame_metric_is_differential;

    // Our metric values are float64 because e.g. total heap size could be a big number,
    // and we don't want to lose precision...
    value_min: float64;
    value_max: float64;
    value_sum: float64;

    previous_value: float64;
    
    for * rs: r.recording_snapshots {
        value: float64;

        if cast(Full_Frame_Metric) current_full_frame_metric == {
          case .LIVE_HEAP_SIZE;
            value = cast(float64)rs.snapshot.bytes_live;
          case .LIVE_HEAP_ALLOCATIONS;
            value = cast(float64)rs.snapshot.num_live;
          case .BYTES_ALLOCATED_THIS_FRAME;
            value = cast(float64)rs.snapshot.bytes_allocated_this_frame;
          case .NUM_ALLOCATIONS_THIS_FRAME;
            value = cast(float64)rs.snapshot.num_allocations_this_frame;
          case .BYTES_FREED_THIS_FRAME;
            value = cast(float64)rs.snapshot.bytes_freed_this_frame;
          case .NUM_FREES_THIS_FRAME;
            value = cast(float64)rs.snapshot.num_frees_this_frame;
        }

        copy_of_previous_value := previous_value;
        previous_value = value;
        if full_frame_metric_is_differential {
            if it_index == 0 {
                value = 0;
            } else {
                value -= copy_of_previous_value;
            }
        }
         
        if it_index == 0 {
            value_min = value;
            value_max = value;
        } else {
            value_min = min(value_min, value);
            value_max = max(value_max, value);
        }

        value_sum += value;

        rs.metric = value;
    }

    denom := max(cast(float64) r.recording_snapshots.count, 1);
    value_mean := value_sum / denom;

    value_denom := max(value_max - value_min, 1);
    
    for * rs: r.recording_snapshots {
        // metric := (rs.temporary_value - value_min) / value_denom;
        // rs.metric = metric;

        rs.metric_color = get_color_for_current_metric(rs.metric, value_min, value_mean, value_max);
    }
}
