Draw_Info :: struct {
    item: *Memory_Item;
    box: Rect;         // Recomputed each frame.
    temp_width: float; // A temporary variable used for computing box rects. (It seemed messy to use box coordinates for that, though we could.)
}

draw_live_allocations :: (_region: Rect) {
    region := _region;
    button_height := region.h * .03;  // We should centralize this?

    scroll_theme := our_scroll_theme();
    scroll_state, inside := begin_scrollable_region(region, *scroll_theme);

    bottom_y := region.y + region.h;

    defer end_scrollable_region(scroll_state, inside.x + inside.w, bottom_y, *live_allocations_scroll_value);

    scrolled_region := inside;
    scrolled_region.y -= live_allocations_scroll_value;

    section_header_theme.font = section_header_font;
    pixels := cast(float) section_header_font.character_height;
    section_header_height = pixels * 1.9;

    if !memory_channel_initted {
        font := filename_font;
        label_theme: Label_Theme;
        label_theme.alignment = .Left;
        label_theme.font      = font;

        pixels := cast(float) font.character_height;
        line := cut_top(region, pixels);
        line.y -= pixels;

        hpad := pixels * .7;
        line.x += hpad;
        line.w -= hpad;

        label(line, "Error while initializing the memory channel.", *label_theme);
        return;
    }
    if !connection_is_live {
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

        label(line, "No Memory_Debugger client program is connected.", *label_theme);

        label_theme_code := label_theme;
        label_theme_code.text_color = .{.95, .5, .8, 1};

        line_stride     := line.h * 1.4;
        line_stride_big := line.h * 2;

        line.y += line_stride_big;
        label(line, "To set this up, compile a program with", *label_theme);
        line.y += line_stride;
        label(line, "    #import \"Basic\"()(MEMORY_DEBUGGER=true);", *label_theme_code);
        line.y += line_stride_big;
        label(line, "and, once per frame, call", *label_theme);
        line.y += line_stride;
        label(line, "    memory_visualizer_per_frame_update();", *label_theme_code);

        bottom_y = line.y;

        return;
    }

    left\_margin := 0.014;
    right_margin := 0.02;
    ymargin := 0.05;

    live_boxes_height  := 0.14 * window_height;
    alloc_boxes_height := 0.08 * window_height;
    freed_boxes_height := alloc_boxes_height;

    next_snapshot_region := scrolled_region;
    desired_y1 := next_snapshot_region.y + next_snapshot_region.h;
    if snapshots { // Should always have at least 1, but let's be paranoid.
        // Draw the first snapshot (the live view). Then draw the recording controls.
        // Then draw the rest of the snapshots...

        {
            it := *snapshots[0];
            it_index := 0;
            update_metrics(it);
            next_snapshot_region, desired_y1 = draw_one_snapshot(it, next_snapshot_region, "Current Heap", button_height, live_boxes_height, freed_boxes_height, it_index);
        }

        recording_title: Rect = ---;
        recording_title, next_snapshot_region = cut_top(next_snapshot_region, section_header_height);

        draw_section_title(recording_title, "Recording");

        next_snapshot_region, desired_y1 = draw_recording_controls(next_snapshot_region, button_height);

        for * snapshots {
            if it_index == 0  continue;

            update_metrics(it);
            next_snapshot_region, desired_y1 = draw_one_snapshot(it, next_snapshot_region, tprint("Snapshot of Frame %", it.frame_index), button_height, live_boxes_height, freed_boxes_height, it_index);
        }
    }

    bottom_y = next_snapshot_region.y;  // So the scrollable region knows where to end.
    if next_snapshot_region.h >= 0  bottom_y += next_snapshot_region.h;  // This goes massively < 0 when we have stuff open. Is that bad?
    if bottom_y < desired_y1  bottom_y = desired_y1;             // end_scrollable_region uses bottom_y.

    if want_snapshot do_snapshot();

    if want_deletion { // You can't delete the live snapshot, which is index 0, so it's fine that 0 means we want no deletion.
        fini(*snapshots[want_deletion]);
        array_ordered_remove_by_index(*snapshots, want_deletion);
        want_deletion = 0;
    }
}

to_array :: (table: $T/Table, allocator: Allocator = .{}) -> [..] T.Value_Type {
    result: [..] T.Value_Type;
    result.allocator = allocator;

    array_resize(*result, table.count);

    for table  result[it_index] = it;

    return result;
}

to_array_by_pointer :: (table: $T/Table, allocator: Allocator = .{}) -> [..] *T.Value_Type {
    result: [..] *T.Value_Type;
    result.allocator = allocator;

    array_reserve(*result, table.count);  // @Speed: Could be faster if we just resize and then assign.
    for * table  array_add(*result, it);

    return result;
}

filter_items :: (using snap: *Snapshot, items: *[..] *$T) {
    #if T == Memory_Item {
        if #complete cast(Show_Heat_Type) current_show_heat == {
            case .ALL;
            case .COLD_ONLY;  for <<items if it.heat >= 0.05 remove;
            case .WARM_ONLY;  for <<items if it.heat <  0.05 remove;
            case .HOT_ONLY;   for <<items if it.heat <  0.95 remove;
        }
    }

    if snap.restriction.enabled {
        r := *snap.restriction;
        for << items {
            found := find_restriction_in_trace(r, it.common.alloc_site_trace);
            #if T == Frees_This_Frame {
                if !found  found = find_restriction_in_trace(r, it.free_site_trace);
            }

            if !found remove it;
        }
    }
}

find_restriction_in_trace :: (r: *Restriction, _trace: *void) -> bool {
    trace, trace_found := table_find(*address_to_packed_stack_trace, _trace);
    if !trace_found return false;  // Should not happen. Log an error?

    found := false;
    for * node: trace.nodes {
        pi := table_find_pointer(*address_to_packed_stack_trace_procedure_info, node.info);
        if !pi continue;

        if pi.remote_address != r.remote_address       continue;
        if node.line_number  != cast(u32)r.line_number continue;

        return true;
    }

    return false;
}

size_and_sort_items :: (using snap: *Snapshot, items: [] *Memory_Item, r: Rect, freed_items := false, orig_selected_item: *Memory_Item = null, orig_hovering_over: *Memory_Item = null) -> (draw: [] Draw_Info, selected_item: *Memory_Item, hovering_over: *Memory_Item) {
    draw: [..] Draw_Info;
    draw.allocator = temp;
    array_resize(*draw, items.count);

    total_bytes := 0;
    total_count := 0;

    width_sum := 0.0;
    newly_selected_item := orig_selected_item; // Can't keep this across frames since the pointer will change.

    for items {  // @Cleanup: Could just put the boxes on the items.
        width := cast(float) it.common.bytes;
        if width < 0   width = 0;  // Deal with potential bad data.

        draw[it_index].temp_width = width;
        draw[it_index].item       = it;

        width_sum += width;

        total_bytes += it.common.bytes;
        total_count += it.common.count;
    }

    if width_sum < 1  width_sum = 1;

    sort_type := cast(Allocation_Sort) current_sort_type;
    if #complete sort_type == {
      case .BYTES;
        quick_sort(draw, x => -x.item.bytes);
      case .ALLOCATIONS;
        quick_sort(draw, x => -x.item.count);
      case .BYTES_PER_ALLOCATION;
        quick_sort(draw, x => -x.item.bytes_per_allocation);
      case .HEAT;
        quick_sort(draw, x => -x.item.heat);
      case .AGE;
        denom := cast(float64) total_bytes;
        if denom < 1 denom = 1;
        sort_idenom = 1 / denom;

        quick_sort(draw, (x: Draw_Info) -> float64 {
            // Primary sort by which message index last gave us an update.
            // (Which is kind of like age, but different). Secondary sort
            // by number of allocations. This should be the most stable display?

            item := x.item;
            age := cast(float64) item.message_index_of_last_update;
            age += item.count * sort_idenom; // This will be in [0, 1].
            return age;
        });
    }

    // Pass 2: normalize to pixel width of 'boxes' and compute it.box. See if we are hovering over this item;
    // if so, select.

    can_pick_boxes := !events_occluded();
    if !is_inside(cursor_pos.x, cursor_pos.y, r) can_pick_boxes = false;
    hovering_over := orig_hovering_over;


    x_prev := r.x;
    for * draw {
        w := (it.temp_width / width_sum) * r.w;

        box: Rect = ---;
        box.x = x_prev;
        box.y = r.y;
        box.w = w;
        box.h = r.h;

        if can_pick_boxes && is_inside(cursor_pos.x, cursor_pos.y, box) {
            hovering_over = it.item;
            state := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT];
            if state & .START {
                newly_selected_item = it.item;
            }
        }

        it.box = box;

        x_prev += w;
    }

    return draw, newly_selected_item, hovering_over;
}

get_color_for_liveness :: (using snap: *Snapshot, item: *Memory_Item) -> Vector4 {
    // If this item is in live_allocations, t = 1.
    // If it is not, t = 0.
    // If a fraction is in live_allocations, fractional t.
    // We then use this to generate a color.
    // @Robustness: We just do the fraction by bytes, which is not necessarily
    // accurate and may be confusing: why not by allocations? Really you would want
    // to track all the separate allocations and just report what fraction of them
    // are still live.

    t := 0.0;

    item_live := table_find_pointer(*memory_items_table, item.alloc_site_trace);
    if item_live {
        t = item_live.bytes / cast(float) item.bytes;
        Clamp(*t, 0, 1);
    }

    color_0 := Vector4.{.05, .7, .7, 1};
    color_1 := Vector4.{.85, .05, .85, 1};

    color := lerp(color_0, color_1, t);

    return color;
}

draw_memory_items :: (using snap: *Snapshot, selected: *Memory_Item, hovering_over: *Memory_Item, draw: [] Draw_Info, outer_region: Rect, region: Rect, $color_proc_code := #code,null) {
    Simp.set_shader_for_color(false);

    fg := Vector4.{.03, .03, .03, 1};
    draw_quad(outer_region, fg);

    r := region;

    hovering_over_drawn := false;
    selected_drawn      := false;

    hovering_over_box: Rect;
    selected_box:      Rect;

    for * draw {
        item := it.item;

        #if color_proc_code {
            box_color := #insert,scope() color_proc_code;
        } else {
            box_color := get_color_for_current_metric(item.metric, vis_metric_low, vis_metric_mean, vis_metric_high);
        }

        p0, p1, p2, p3 := get_quad(it.box);
        c0 := darken(box_color, .2);
        c1 := darken(box_color, .05);
        c2 := whiten(box_color, .065);
        c3 := box_color;

        // :ErrorOutputSpam Simp.immediate_quad(r, p0, p1, p2, p3, c0, c1, c2, c3);
        Simp.immediate_quad(p0, p1, p2, p3, c0, c1, c2, c3);

        if item == hovering_over  { hovering_over_drawn = true; hovering_over_box = it.box; }
        if item == selected       { selected_drawn      = true; selected_box      = it.box; }
    }

    if hovering_over && hovering_over_drawn  draw_box_selection(hovering_over_box, .{.5, .9, .7, 1});
    if selected      && selected_drawn       draw_box_selection(selected_box,      .{1, 1, 1, 1});
}

draw_box_selection :: (rect: Rect, color: Vector4) {
    border := rect.h * .1;

    top    := cut_top   (rect, border);
    bottom := cut_bottom(rect, border);

    k := border * .35;
    top.y    -= k;
    bottom.y += k;

    minimum := window_width / 400.0;
    if top.w < minimum {
        mid := top.x + top.w + .5;
        top.x = mid - minimum*.5;
        top.w = minimum;
        bottom.x = top.x;
        bottom.w = top.w;
    }

    Simp.set_shader_for_color(false);

    draw_quad(top,    color);
    draw_quad(bottom, color);
}


draw_one_snapshot :: (using snap: *Snapshot, region: Rect, title_text: string, button_height: float, live_boxes_height: float, freed_boxes_height: float, index: s64) -> (remainder: Rect, desired_y1: float) {
    //
    // Add up all the sizes in bytes, then normalize, dividing by the sum.
    //

    live_items  := to_array_by_pointer(snap.memory_items_table,      allocator=temp);
    alloc_items := to_array_by_pointer(snap.allocs_this_frame_table, allocator=temp);
    freed_items := to_array_by_pointer(snap.frees_this_frame_table,  allocator=temp);


    new_and_not_freed_items: [..] *Memory_Item;
    new_and_not_freed_items.allocator = temp;

    new_and_freed_items: [..] *Memory_Item;
    new_and_freed_items.allocator = temp;

    freed_and_not_new_items: [..] *Memory_Item;
    freed_and_not_new_items.allocator = temp;

    // We notice allocation groups as being partially freed, partially not, etc,
    // so we keep separate byte counters for these:
    bytes_new_and_freed:     s64;
    count_new_and_freed:     s64;
    bytes_new_and_not_freed: s64;
    count_new_and_not_freed: s64;
    bytes_freed_and_not_new: s64;
    count_freed_and_not_new: s64;

    for a: alloc_items {
        found := table_find_multiple(*snap.frees_this_frame_by_alloc_site_only_table, a.alloc_site_trace);

        freed_bytes := 0;
        freed_count := 0;
        for found {
            freed_bytes += it.bytes;
            freed_count += it.count;
        }

        if freed_bytes >= 0 {
            array_add(*new_and_freed_items, a);
            bytes_new_and_freed += freed_bytes;
            count_new_and_freed += freed_count;  // @Robustness: This is wrong. What do we do?
        }

        if freed_bytes < a.bytes {
            array_add(*new_and_not_freed_items, a);
            bytes_new_and_not_freed += a.bytes - freed_bytes;
            count_new_and_not_freed += a.count - freed_count;  // @Robustness: This is wrong. What do we do?
        }
    }


    for f: freed_items {
        value, found := table_find(*snap.allocs_this_frame_table, f.alloc_site_trace);

        alloc_bytes := ifx found then value.bytes;
		alloc_count := ifx found then value.count;

        if f.bytes > alloc_bytes {
            bytes_freed_and_not_new += f.bytes - alloc_bytes;
            count_freed_and_not_new += f.count - alloc_count;  // @Robustness: This is wrong. What do we do?
            array_add(*freed_and_not_new_items, f);
        }
    }


    filter_items(snap, *live_items);

    // Right now the filtering is only hot/cold, which is not relevant or useful for
    // newly allocated/freed, so, skip it for now.
    // filter_items(snap, *alloc_items);
    // filter_items(snap, *freed_items);



    label_theme: Label_Theme;
    label_theme.alignment = .Left;
    label_theme.font      = stat_font;

    pixels := cast(float) label_theme.font.character_height;
    top_padding := pixels * .6;

    _, below_padding := cut_top(region, top_padding);
    title_current, below_title_current := cut_top(below_padding, section_header_height);

    headline, below_headline := cut_top(below_title_current, pixels);

    widget_area, below_widget_area := cut_top(below_headline, button_height*1.2);

    live_outer_region, below_live_outer_region := cut_top(below_widget_area, live_boxes_height);
    boxes_shrink_amount := live_outer_region.h * .04;
    live_region := shrink(live_outer_region, boxes_shrink_amount);

    freed_headline_font := filename_font;
    area_text_height := cast(float) freed_headline_font.character_height;

    alloc_text_area, below_alloc_text_area := cut_top(below_live_outer_region, area_text_height);
    alloc_outer_region, below_alloc_outer_region := cut_top(below_alloc_text_area, freed_boxes_height);
    alloc_region := shrink(alloc_outer_region, boxes_shrink_amount);

    freed_text_area, below_freed_text_area := cut_top(below_alloc_outer_region, area_text_height);
    freed_outer_region, below_freed_outer_region := cut_top(below_freed_text_area, freed_boxes_height);
    freed_region := shrink(freed_outer_region, boxes_shrink_amount);


    // Here, we have 'below_all_memory_items' represent whatever the screen area is
    // after we draw all Memory_Items. But we have a variable number of them to draw
    // depending on a dropdown, so, as we draw them we carve chunks off below_all_memory_items
    // and update it.

    below_all_memory_items := below_freed_outer_region;

    additional := cast(Additional_Alloc_View) current_additional_alloc_view;

    do_new_and_freed     := snap.is_recorded_frame && ((additional == .ALL) || (additional == .NEW_AND_FREED));
    do_new_and_not_freed := snap.is_recorded_frame && ((additional == .ALL) || (additional == .NEW_AND_NOT_FREED));
    do_freed_and_not_new := snap.is_recorded_frame && ((additional == .ALL) || (additional == .FREED_AND_NOT_NEW));

    new_and_freed_text_area,     new_and_freed_outer_region,     new_and_freed_region:     Rect = ---;
    new_and_not_freed_text_area, new_and_not_freed_outer_region, new_and_not_freed_region: Rect = ---;
    freed_and_not_new_text_area, freed_and_not_new_outer_region, freed_and_not_new_region: Rect = ---;

    __ := below_all_memory_items;

    if do_new_and_freed {
        new_and_freed_text_area,    __ = cut_top(__, area_text_height);
        new_and_freed_outer_region, __ = cut_top(__, freed_boxes_height);

        new_and_freed_region = shrink(new_and_freed_outer_region, boxes_shrink_amount);
    }

    if do_new_and_not_freed {
        new_and_not_freed_text_area,    __ = cut_top(__, area_text_height);
        new_and_not_freed_outer_region, __ = cut_top(__, freed_boxes_height);

        new_and_not_freed_region = shrink(new_and_not_freed_outer_region, boxes_shrink_amount);
    }

    if do_freed_and_not_new {
        freed_and_not_new_text_area,    __ = cut_top(__, area_text_height);
        freed_and_not_new_outer_region, __ = cut_top(__, freed_boxes_height);

        freed_and_not_new_region = shrink(freed_and_not_new_outer_region, boxes_shrink_amount);
    }

    below_all_memory_items = __;

    draw_live,  newly_selected_item_live,  hovering_over_item_live  := size_and_sort_items(snap, live_items, live_region);
    draw_alloc, newly_selected_item_alloc, hovering_over_item_alloc := size_and_sort_items(snap, alloc_items, alloc_region, true);
    draw_freed, newly_selected_item_freed, hovering_over_item_freed := size_and_sort_items(snap, freed_items, freed_region, true);

    draw_new_and_freed, draw_new_and_not_freed, draw_freed_and_not_new: [] Draw_Info;
    if do_new_and_freed {
        draw_new_and_freed, newly_selected_item_alloc, hovering_over_item_alloc = size_and_sort_items(snap, new_and_freed_items, new_and_freed_region, true, newly_selected_item_alloc, hovering_over_item_alloc);
    }

    if do_new_and_not_freed {
        draw_new_and_not_freed, newly_selected_item_alloc, hovering_over_item_alloc = size_and_sort_items(snap, new_and_not_freed_items, new_and_not_freed_region, true, newly_selected_item_alloc, hovering_over_item_alloc);
    }

    if do_freed_and_not_new {
        draw_freed_and_not_new, newly_selected_item_freed, hovering_over_item_freed = size_and_sort_items(snap, freed_and_not_new_items, freed_and_not_new_region, true, newly_selected_item_freed, hovering_over_item_freed);
    }


    if newly_selected_item_live {
        selected_pst_live = newly_selected_item_live.common.alloc_site_trace;
        selected_pst_free = null;
    }

    if newly_selected_item_alloc {
        selected_pst_live = newly_selected_item_alloc.common.alloc_site_trace;
        selected_pst_free = null;
    }

    if newly_selected_item_freed {
        selected_pst_live = newly_selected_item_freed.common.alloc_site_trace;
        selected_pst_free = newly_selected_item_freed.frees.free_site_trace;
    }


    // If we did not find a selected item, it might be that we had one selected
    // but didn't draw it. If this happened, let the user know, and draw the data
    // anyway.
    // @Cleanup: These are not currently used.
    selected_item_live_not_drawn_this_frame  := false;
    selected_item_freed_not_drawn_this_frame := false;

    // @Copypasta between alloc and freed: refactor.
    // These are old. Make them good!
    pst_free := selected_pst_free;

    selected_item_live:  *Memory_Item;
    selected_item_alloc: *Memory_Item;
    if selected_pst_live {
        selected_item_live  = table_find_pointer(*memory_items_table, selected_pst_live);
        selected_item_alloc = table_find_pointer(*allocs_this_frame_table, selected_pst_live);  // We overload selected_pst_live to maybe be pointing to an alloc that was also freed this frame...!
    }

    selected_item_freed: *Memory_Item;

    if (!pst_free) && selected_pst_live {
        // Search the frees table for anything corresponding to the thing we have selected.
        // (If it's one of the new allocs, maybe it got freed after the alloc.)
        for * value, key: frees_this_frame_table {
            if value.common.alloc_site_trace == selected_pst_live {
                pst_free = value.frees.free_site_trace;
                break;
            }
        }
    }

    if pst_free {
        pointer: *Memory_Item;
        if selected_pst_live {
            aft: Alloc_And_Free_Traces;
            aft.alloc_site_trace = selected_pst_live;
            aft.free\_site_trace = pst_free;
            pointer = table_find_pointer(*frees_this_frame_table, aft);
        } else {
            // @Cleanup: Should not need to do this?
            // Scan through the table and look for the first thing
            // with this free_site_trace...

            for * frees_this_frame_table {
                if it.frees.free_site_trace == pst_free {
                    pointer = it;
                    break;
                }
            }
        }

        if pointer {
            selected_item_freed_not_drawn_this_frame = true;
            selected_item_freed = pointer;
        }
    }

    draw_section_title(title_current, title_text);

    {
        hpad := pixels * .2;
        headline.x += hpad;
        headline.w -= 2*hpad;

        text := bytes_in_allocations_string(snap.bytes_live, snap.num_live, "Live: ");
        label(headline, text, *label_theme);
    }

    label_theme.font = freed_headline_font;

    {
        count := snap.num_allocations_this_frame;
        bytes := snap.bytes_allocated_this_frame;
        text := bytes_in_allocations_string(bytes, count, "New: ");
        label(alloc_text_area, text, *label_theme);
    }

    {
        count := snap.num_frees_this_frame;
        bytes := snap.bytes_freed_this_frame;
        text := bytes_in_allocations_string(bytes, count, "Freed: ");
        label(freed_text_area, text, *label_theme);
    }

    if do_new_and_freed {
        count := count_new_and_freed;
        bytes := bytes_new_and_freed;
        text := bytes_in_allocations_string(bytes, count, "New and Freed: ");
        label(new_and_freed_text_area, text, *label_theme);
    }

    if do_new_and_not_freed {
        count := count_new_and_not_freed;
        bytes := bytes_new_and_not_freed;
        text := bytes_in_allocations_string(bytes, count, "New and Not Freed: ");
        label(new_and_not_freed_text_area, text, *label_theme);
    }

    if do_freed_and_not_new {
        count := count_freed_and_not_new;
        bytes := bytes_freed_and_not_new;
        text := bytes_in_allocations_string(bytes, count, "Freed and Not New: ");
        label(freed_and_not_new_text_area, text, *label_theme);
    }


    {
        w := widget_area.w;
        label_width_1 := w * .05;
        sort_dropdown_width := w*.15;
        r := get_rect(widget_area.x + widget_area.w - sort_dropdown_width - boxes_shrink_amount, widget_area.y + boxes_shrink_amount, sort_dropdown_width, button_height);

        l := r;
        l.x -= label_width_1;
        l.w = r.x - l.x;

        dropdown_theme := *default_overall_theme.dropdown_theme;

        dropdown(r, SORT_NAMES, *current_sort_type, dropdown_theme, identifier=index);

        label_theme: Label_Theme;
        label_theme.alignment = .Right;
        label(l, "Sort", *label_theme);


        heat_dropdown_width := sort_dropdown_width * .6;

        s := r;
        s.w = heat_dropdown_width;
        s.x = l.x - s.w;

        dropdown(s, SHOW_HEAT_NAMES, *current_show_heat, dropdown_theme, identifier=index);

        if snap.restriction.enabled {
            r := *snap.restriction;
            l := get_rect(widget_area.x + boxes_shrink_amount, widget_area.y + boxes_shrink_amount, widget_area.w, button_height);
            restriction_text := tprint("Restriction: %, line %", r.proc_name, r.line_number);
            label_theme.alignment = .Left;
            label_theme.text_color = Vector4.{.85, .4, .4, 1};
            label(l, restriction_text, *label_theme);
        }

/*
        Controlling heat speed does not seem to be very useful right now.
        if primary {
            t := s;
            t.x = s.x - t.w - label_width_1;
            dropdown(t, COMPUTE_HEAT_NAMES, *current_compute_heat, dropdown_theme, identifier=index);
        }
*/
    }

    draw_memory_items(snap, selected_item_live,  hovering_over_item_live,  draw_live, live_outer_region,  live_region);
    draw_memory_items(snap, selected_item_alloc, hovering_over_item_alloc, draw_alloc, alloc_outer_region, alloc_region,
                      color_proc_code = #code get_color_for_liveness(snap, item));

    draw_memory_items(snap, selected_item_freed, hovering_over_item_freed, draw_freed, freed_outer_region, freed_region,
                      color_proc_code = #code get_color_for_liveness(snap, item));

    if do_new_and_freed {
        draw_memory_items(snap, selected_item_alloc, hovering_over_item_alloc, draw_new_and_freed, new_and_freed_outer_region, new_and_freed_region,
                          color_proc_code = #code get_color_for_liveness(snap, item));
    }

    if do_new_and_not_freed {
        draw_memory_items(snap, selected_item_alloc, hovering_over_item_alloc, draw_new_and_not_freed, new_and_not_freed_outer_region, new_and_not_freed_region,
                          color_proc_code = #code get_color_for_liveness(snap, item));
    }

    if do_freed_and_not_new {
        draw_memory_items(snap, selected_item_freed, hovering_over_item_freed, draw_freed_and_not_new, freed_and_not_new_outer_region, freed_and_not_new_region,
                          color_proc_code = #code get_color_for_liveness(snap, item));
    }


    junk, info_area  := cut_top(below_all_memory_items, live_region.h * .1);

    controls: Rect;
    controls, info_area = cut_top(info_area, button_height * 1.2);

    _margin: Rect = ---;
    _margin, info_area = cut_top(info_area, button_height * .25);  // Just give us some more margin.

    controls = cut_bottom(controls, button_height);

    button_width := controls.w * .15;
    button_rect := cut_right(controls, button_width);

    button_theme: Button_Theme;  // This will have the default Button_Theme values.
    button_theme.enable_variable_frame_thickness = true;
    if primary {
        // Draw some controls that only apply to the primary snapshot.
        pressed_snapshot := button(button_rect, "Snapshot", *button_theme, identifier=index);
        if pressed_snapshot {
            want_snapshot = true; // So that we don't resize the snapshots array while iterating! We could use a Bucket_Array or other pointer-stable thing instead.
        }
    } else if is_recorded_frame {
        dropdown_theme := *default_overall_theme.dropdown_theme;
        dropdown(button_rect, ADDITIONAL_ALLOC_VIEW_NAMES, *current_additional_alloc_view, dropdown_theme);
    } else {
        pressed_delete := button(button_rect, "(delete)", *button_theme, identifier=index);
        if pressed_delete  want_deletion = index;
    }

    if current_additional_alloc_view {
        info_area = draw_additional_alloc_view(snap, info_area);
    }

    return_rect := info_area;

    middle_margin_half :: 0.02;

    alloc_trace_region := cut_left (info_area, info_area.w * (.5 - middle_margin_half));
    freed_trace_region := cut_right(info_area, info_area.w * (.5 - middle_margin_half));

    item_not_drawn_this_frame := false;

    top_y := info_area.y;
    bottom_y := top_y;

    if selected_item_freed {
        bottom_y_left  := draw_stack_trace(snap, selected_item_live, selected_item_alloc,
                                           alloc_trace_region,
                                           item_not_drawn_this_frame,
                                           selected_pst_live);
        bottom_y_right := draw_stack_trace(snap, null, selected_item_freed,
                                           freed_trace_region,
                                           item_not_drawn_this_frame,
                                           selected_item_freed.frees.free_site_trace, for_the_free_column=true);
        bottom_y = max(bottom_y_left, bottom_y_right);
    } else if selected_item_live {
        item := selected_item_live;
        bottom_y = draw_stack_trace(snap, selected_item_live, selected_item_alloc,
                                    alloc_trace_region,
                                    item_not_drawn_this_frame,
                                    selected_pst_live);
    }

    vertical_space_to_reserve := button_height * 20; // :VerticalSpace  Leave some space for the dropdown to go into, and also so that we don't pop the scrollbar too much when no stack trace. (We will probably also want to implement some other scrollbar stability thing.)
    desired_y1 := bottom_y;

    if desired_y1 - top_y < vertical_space_to_reserve {
        desired_y1 = top_y + vertical_space_to_reserve;
    }

    if bottom_y > return_rect.y {
        _, return_rect = cut_top(return_rect, bottom_y - return_rect.y);
    }

    return return_rect, desired_y1;
}

draw_additional_alloc_view :: (using snap: *Snapshot, rect: Rect) -> (remainder: Rect) {
    return rect;
}

draw_stack_trace :: (snap: *Snapshot, item_1: *Memory_Item, item_2: *Memory_Item, region: Rect, not_drawn: bool, _trace: *void, for_the_free_column := false) -> (bottom_y: float) {
    label_theme: Label_Theme;
    label_theme.alignment = .Left;
    label_theme.font      = stack_trace_header_font;

    headline_height := cast(float) label_theme.font.default_line_spacing;
    headline_1, _rest := cut_top(region, headline_height);
    headline_2, rest  := cut_top(_rest,  headline_height);

    //
    // Draw the stack trace. First pass, we buffer the lines so that we can draw them
    // one column at a time with scissoring.
    //

    Display_Line :: struct {
        name:     string;
        filename: string;

        line_number: s32;
        procedure_info: *Packed_Stack_Trace_Procedure_Info;

        color: Vector4;
    }

    lines: [..] Display_Line;
    lines.allocator = temp;

    header_1, header_2: string;
    if for_the_free_column {
        if item_2 header_2 = bytes_in_allocations_string(item_2.bytes, item_2.common.count, "Freed: ");
    } else {
        if item_1 header_1 = bytes_in_allocations_string(item_1.common.bytes, item_1.common.count, "Live: ");
        if item_2 header_2 = bytes_in_allocations_string(item_2.common.bytes, item_2.common.count, "New: ");
    }


    if not_drawn {
        label_theme.text_color = .{.4, .4, .4, 1};
    } else {
        label_theme.text_color = .{.9, .9, .8, 1};
    }

    label(headline_1, header_1, *label_theme);
    label(headline_2, header_2, *label_theme);

    bottom_y := headline_2.y + headline_2.h;

    label_theme.font      = stat_small_font;

    trace, found := table_find(*address_to_packed_stack_trace, _trace);
    if found {
        // We actually might not find this, if that stack trace has not been sent?!
        for * trace.nodes {
            name     := "(unknown)";
            filename := "(unknown)";
            packed := table_find_pointer(*address_to_packed_stack_trace_procedure_info, it.info);
            if packed {
                name_value,     name_found     := table_find(*index_to_string, packed.name);
                filename_value, filename_found := table_find(*index_to_string, packed.filename);

                if name_found      name     = name_value;
                if filename_found  filename = filename_value;
            }

            line := array_add(*lines);
            line.name           = name;
            line.filename       = filename;
            line.line_number    = cast(s32) it.line_number;
            line.procedure_info = packed;
        }
    }

    if lines {
        // 3 loops, one to draw each column.

        stack_line_stride := label_theme.font.character_height * 1.2;

        col1, col23 := cut_left(rest, rest.w  * .35);
        col2, col3  := cut_left(col23, col23.w * .9);

        selected_line_index := -1;
        bg    := Vector4.{.45, .45, .45, 1};
        hilit := Vector4.{.95, .95, .85, 1};

        bg_restricted       := Vector4.{.75, .33, .33, 1};
        bg_restricted_hilit := Vector4.{.85, .25, .65, 1};

        row := cut_top(col1, stack_line_stride);
        full_line := row;
        full_line.x = rest.x;
        full_line.w = rest.w;

        can_pick_stack := !events_occluded();

        for * lines { // By pointer because we set the color in this first loop. When we init the lines we are not walking coordinates yet so we can't know what is hilit.
            text := it.name;

            if can_pick_stack && is_inside(cursor_pos.x, cursor_pos.y, full_line) {
                selected_line_index = it_index;
            }

            color := ifx it_index == selected_line_index then hilit else bg;
            if snap.restriction.enabled && (snap.restriction.remote_address == it.procedure_info.remote_address) && (snap.restriction.line_number == it.line_number) {
                color = ifx it_index == selected_line_index then bg_restricted_hilit else bg_restricted;
            }

            it.color = color;
            label_theme.text_color = color;

            label(row, text, *label_theme);
            row.y += stack_line_stride;
            full_line.y = row.y;
        }

        bottom_y = row.y + row.h;

        row = cut_top(col2, stack_line_stride);
        for lines {
            text := it.filename;

            label_theme.text_color = it.color;

            label(row, text, *label_theme);
            row.y += stack_line_stride;
        }

        row = cut_top(col3, stack_line_stride);
        for lines {
            text := tprint("%", it.line_number);

            label_theme.text_color = it.color;

            label(row, text, *label_theme);
            row.y += stack_line_stride;
        }

        if selected_line_index != -1 {
            line := lines[selected_line_index];

            // Left mouse button:
            {
                state := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_LEFT];
                if state & .START {
                    open_editor_to_file_and_line(line.filename, line.line_number);
                }
            }

            // Right mouse button:
            {
                state := Input.input_button_states[Input.Key_Code.MOUSE_BUTTON_RIGHT];
                if state & .START {
                    info := line.procedure_info;
                    if info {
                        if snap.restriction.enabled && (snap.restriction.remote_address == info.remote_address) && (snap.restriction.line_number == line.line_number) {
                            // We right-clicked the same thing; toggle it off.
                            snap.restriction.enabled = false;
                        } else {
                            snap.restriction.remote_address = info.remote_address;
                            snap.restriction.line_number    = line.line_number;
                            snap.restriction.proc_name      = line.name;
                            snap.restriction.enabled        = true;
                        }
                    }
                }
            }
        }
    }

    return bottom_y;
}


do_snapshot :: () {
    snap := *snapshots[0];  // Do this *after* the array_add, otherwise it might move.
    array_add(*snapshots, copy_snapshot(snap));
    want_snapshot = false;
}

copy_snapshot :: (source: Snapshot) -> Snapshot {
    dest: Snapshot;

    dest.current_sort_type  = source.current_sort_type;
    dest.current_show_heat  = source.current_show_heat;
    dest.selected_pst_live  = source.selected_pst_live;
    dest.selected_pst_free  = source.selected_pst_free;
    dest.restriction        = source.restriction;

    dest.num_live   = source.num_live;
    dest.bytes_live = source.bytes_live;

    dest.num_allocations_this_frame = source.num_allocations_this_frame;
    dest.num_frees_this_frame       = source.num_frees_this_frame;
    dest.bytes_allocated_this_frame = source.bytes_allocated_this_frame;
    dest.bytes_freed_this_frame     = source.bytes_freed_this_frame;

    dest.frame_index = source.frame_index;

    for * value, key: source.memory_items_table {
        table_set(*dest.memory_items_table, key, value);
    }

    for * value, key: source.allocs_this_frame_table {
        table_set(*dest.allocs_this_frame_table, key, value);
    }

    for * value, key: source.frees_this_frame_table {
        table_set(*dest.frees_this_frame_table, key, value);
    }

    for * value, key: source.frees_this_frame_by_alloc_site_only_table {
        // table_add, rather than table_set, because we can have multiple entries
        // for one key.
        table_add(*dest.frees_this_frame_by_alloc_site_only_table, key, value);
    }

    return dest;
}

#import "Random";
#import "Sort";

live_allocations_scroll_value: float;

#scope_module

Allocation_Sort :: enum u8 {
    BYTES                :: 0;
    ALLOCATIONS          :: 1;
    BYTES_PER_ALLOCATION :: 2;
    HEAT                 :: 3;
    AGE                  :: 4;  // This is age according to the client, not the originator...
}

Show_Heat_Type :: enum u8 {
    ALL       :: 0;
    COLD_ONLY :: 1;
    WARM_ONLY :: 2;
    HOT_ONLY  :: 3;
}

Compute_Heat_Type :: enum u8 {
    SLOW    :: 0;
    MEDIUM  :: 1;
    FAST    :: 2;
    INSTANT :: 3;
}

current_compute_heat: s32;

Restriction :: struct {
    remote_address: *void;
    line_number:    s32;
    proc_name:      string;  // Used only for display to the user.
    enabled :=      false;
}

Snapshot :: struct {
    current_sort_type: s32;
    current_show_heat: s32;

    selected_pst_live:  *void;  // This is the pointer we get from the remote program, that is not in our address space.
    selected_pst_free: *void;

    vis_metric_low:  float;
    vis_metric_mean: float;
    vis_metric_high: float;

    memory_items_table: Table(*Packed_Packed_Stack_Trace, Memory_Item);
    allocs_this_frame_table: Table(*Packed_Packed_Stack_Trace, Memory_Item);  // Does this need to be a table, actually?
    frees_this_frame_table: Table(Alloc_And_Free_Traces, Memory_Item, hash_alloc_and_free_traces, compare_alloc_and_free_traces);  // Does this need to be a table, actually?
    frees_this_frame_by_alloc_site_only_table: Table(*Packed_Packed_Stack_Trace, Memory_Item);  // So that we can look up stuff by call site for new_and_not_freed kinds of stuff.

    restriction: Restriction;

    // These this_frame values are computed when reading the tables.
    num_allocations_this_frame: s64;
    bytes_allocated_this_frame: s64;

    num_frees_this_frame:   s64;
    bytes_freed_this_frame: s64;

    num_live: s64;
    bytes_live: s64;

    frame_index: s64;
    primary := false;  // If this is the snapshot that receives live data.
    is_recorded_frame := false;
}

fini :: (s: *Snapshot) {
    table_reset(*s.memory_items_table);
    table_reset(*s.allocs_this_frame_table);
    table_reset(*s.frees\_this_frame_table);
}

#scope_file

SORT_NAMES         :: string.["Bytes", "Allocations", "Bytes per Allocation", "Heat", "Age"];
SHOW_HEAT_NAMES    :: string.["All", "Cold Only", "Warm Only", "Hot Only"];
COMPUTE_HEAT_NAMES :: string.["Slow", "Medium", "Fast", "Instant"];

want_snapshot := false;
want_deletion := 0;

#assert SORT_NAMES.count == #run enum_highest_value(Allocation_Sort) + 1;

sort_idenom: float64;

bytes_in_allocations_string :: (bytes: s64, allocations: s64, prefix := "") -> string /* Temporary Storage */ {
    plural :: inline (x: int) -> string {
        if x == 1 return "";
        return "s";
    }

    per_string := ".";
    per := cast(s64) floor(bytes / cast(float) max(allocations, 1) + .5);
    if (allocations != 1) && (bytes != 0)  per_string = tprint(" (% bytes average).", formatInt(per, digits_per_comma=3, comma_string=","));

    text := tprint("%0% byte% in % allocation%0%", prefix, formatInt(bytes, digits_per_comma=3, comma_string=","), plural(bytes), formatInt(allocations, digits_per_comma=3, comma_string=","), plural(allocations), per_string);
    return text;
}


hash_alloc_and_free_traces :: (traces: Alloc_And_Free_Traces) -> u32 { // @Copypasta from Memory_Debugger.jai. We could factor it together, but Protocol_For* does nto know about fnv1a_hash.
    a := fnv1a_hash(cast(u64) traces.alloc_site_trace);
    b := fnv1a_hash(cast(u64) traces.free_site_trace);

    return cast,trunc(u32) a ^ b;  // xor seems fine here (?) since they cannot be swapped. But maybe this is bad.
}

section_header_theme: Label_Theme;
section_header_height: float;

draw_section_title :: (_r: Rect, text: string) {
    INDENT :: .7;
    r := _r;
    r.w *= INDENT;
    r.x += _r.w * (1 - INDENT) * .5;

    font := section_header_font;

    text_width := cast(float) Simp.prepare_text(font, text);
    xpad := cast(float) font.em_width;
    text_width_padded := text_width + 2.0 * xpad;
    w_sides := (r.w - text_width_padded) * .5;

    band_height := r.h * .06;

    band := r;
    band.h = band_height;
    band.y += (r.h - band_height) * .5;

    band_left  := cut_left (band, w_sides);
    band_right := cut_right(band, w_sides);

    band_color := Vector4.{.7, .7, .7, 1};
    Simp.set_shader_for_color(false);
    draw_quad(band_left,  band_color);
    draw_quad(band_right, band_color);

    text_color := Vector4.{.9, .9, .7, 1};

    x := band.x + band.w * .5 - text_width * .5;
    y := band.y + band.h * .5 + cast(float) font.y_offset_for_centering;

    Simp.generate_quads_for_prepared_text(font, xx x, xx y, 0);
    Simp.draw_generated_quads(font, text_color);
}


#import "Hash";  // For fnv1a_hash.
