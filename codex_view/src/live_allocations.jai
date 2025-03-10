Memory_Item :: struct {  // Warning: Don't keep pointers to this across frames, as it's not memory-stable.
    union {
        // Use 'common' in a general routine where you don't know which this is:
        using common:       Summary_Common;

        // If you know where this came from, you can use these:
        summary:      Packed_Summary;
        allocs:       Allocs_This_Frame;
        frees:        Frees_This_Frame;
    }

    message_index_of_last_update: s64;

    bytes_per_allocation: float;  // Recomputed each update.
    metric: float;
    heat: float;
}

update_live_allocations :: () {
    if !memory_channel_initted return;

    while 1 {
        message_success, fatal_error, message := reader_poll_for_message(*memory_channel);
        if !message_success break;

        if fatal_error {
            respond_to_fatal_error();
            break;
        }

        handle_message(message);
        reader_done_with_message(*message);

        if !memory_channel_initted break;  // If we got a fatal error, please stop looping please.
    }
}

handle_message :: (message: Read_Message) {
    if message.user_read_bytes < 4 {
        log_error("In handle_message(), the message is too short! (It was % bytes.)\n", message.user_read_bytes);
        respond_to_fatal_error();
        return;
    }

    tag := << cast(*Vis_Protocol_Tag) message.user_read_pointer;
    array: [] u8;
    array.count = message.user_read_bytes;
    array.data  = message.user_read_pointer;

    if #complete tag == {
      case .ERROR;
        handle_message_error(array);
      case .RESET_AND_TELL_VERSION;
        handle_message_reset_and_tell_version(array);
      case .ADD_STACK_TRACE;
        handle_message_add_stack_trace(array);
      case .ADD_PROCEDURE_INFO;
        handle_message_add_procedure_info(array);
      case .ADD_STRING;
        handle_message_add_string(array);
      case .UPDATE_USAGE;
        handle_message_update_usage(array);
      case;
        log_error("In handle_message(): Received invalid message type %.\n", tag);
        respond_to_fatal_error();
    }
}

handle_message_error :: (array: [] u8) {
    log_error("Got a message of type ERROR, which happens to be 0, which means maybe someone didn't initialize their message? Or the memory is corrupted.\n");
    respond_to_fatal_error();
}

handle_message_reset_and_tell_version :: (array: [] u8) {
    info, data := check_minimum_size(array, Memory_Debugger_Version_Info);
    if !info return;

    if info.version != VIS_PROTOCOL_VERSION {
        log_error("RESET_AND_TELL_VERSION message wants version %, but we only do version %. Disabling.\n", info.version, VIS_PROTOCOL_VERSION);
        respond_to_fatal_error();
    }

    table_reset(*address_to_packed_stack_trace);
    table_reset(*index_to_string);
    table_reset(*address_to_packed_stack_trace_procedure_info);

    connection_is_live = true;
}

handle_message_add_stack_trace :: (array: [] u8) {
    info, data := check_minimum_size(array, Single_Stack_Trace_Info);
    if !info return;

    nodes_bytes := info.num_nodes * size_of(Stack_Trace_Node);
    okay := check_minimum_size(data, info, nodes_bytes);
    if !okay return;

    pst := New(Packed_Packed_Stack_Trace);
    pst.info = << info;
    array_resize(*pst.nodes, info.num_nodes);

    memcpy(pst.nodes.data, data.data, nodes_bytes);

    table_add(*address_to_packed_stack_trace, info.address, pst);
}

handle_message_add_procedure_info :: (array: [] u8) {
    info, data := check_minimum_size(array, Packed_Stack_Trace_Procedure_Info);
    if !info return;

    pi := New(Packed_Stack_Trace_Procedure_Info);  // @Speed!
    << pi = << info;

    table_add(*address_to_packed_stack_trace_procedure_info, info.remote_address, pi);
}

handle_message_add_string :: (array: [] u8) {
    info, data := check_minimum_size(array, String_Info);
    if !info return;

    okay := check_minimum_size(data, info, info.count);
    if !okay return;

    if info.count < 0 {
        log_error("Got an invalid string count of %.\n", info.count);
        respond_to_fatal_error();
        return;
    }

    s := alloc_string(info.count);  // @Speed!
    memcpy(s.data, data.data, info.count);

    table_add(*index_to_string, info.index, s);
}

handle_message_update_usage :: (array: [] u8) {
    info, data := check_minimum_size(array, Summary_Info);
    if !info return;

    summaries_bytes := info.num_live * size_of(Packed_Summary) + info.num_allocs_this_frame * size_of(Allocs_This_Frame) + info.num_frees_this_frame * size_of(Frees_This_Frame);
    okay := check_minimum_size(data, info, summaries_bytes);
    if !okay return;


    assert(snapshots.count > 0);
    snap := *snapshots[0];

    num_live: s64;  // WARNING: This is a little confusing. This 'num_live' is the sum of all counts in all summaries, whereas info.num_live is just the number of summaries. We should clean this up by renaming in some way.
    bytes_live: s64;

    cursor := data.data;
    for 1..info.num_live {
        // The hash table keeps state from frame-to-frame.

        p := cast(*Packed_Summary) cursor;
        item := table_find_pointer(*snap.memory_items_table, p.alloc_site_trace);
        if !item  item = table_add(*snap.memory_items_table, p.alloc_site_trace, .{});

        item.message_index_of_last_update = index_of_this_usage_update;

        source := cast(*Packed_Summary) cursor;
        num_live   += source.count;
        bytes_live += source.bytes;

        item.summary = << source;

        cursor += size_of(Packed_Summary);
    }

    num_allocations_this_frame: s64;
    bytes_allocated_this_frame: s64;

    table_reset(*snap.allocs_this_frame_table);
    for 1..info.num_allocs_this_frame {
        p := cast(*Allocs_This_Frame) cursor;
        item := find_or_add(*snap.allocs_this_frame_table, p.alloc_site_trace);
        item.allocs = <<p;

        num_allocations_this_frame += p.count;
        bytes_allocated_this_frame += p.bytes;

        cursor += size_of(Allocs_This_Frame);
    }

    num_frees_this_frame:       s64;
    bytes_freed_this_frame:     s64;

    table_reset(*snap.frees_this_frame_table);  // We don't remember frees past 1 frame... this is mostly about just looking for flailing.
    table_reset(*snap.frees_this_frame_by_alloc_site_only_table);
    for 1..info.num_frees_this_frame {
        p := cast(*Frees_This_Frame) cursor;

        traces: Alloc_And_Free_Traces = ---;
        traces.alloc_site_trace = p.alloc_site_trace;
        traces.free\_site_trace = p.free\_site_trace;
        item := find_or_add(*snap.frees_this_frame_table, traces);

        orig_count := item.count;
//        assert(item.count == 0);
//        item.frees = <<p;

        item.count += p.count;
        item.bytes += p.bytes;
        item.alloc_site_trace = p.alloc_site_trace;
        item.allocator_proc   = p.allocator_proc;
        item.frees.free_site_trace  = p.free_site_trace;

        table_add(*snap.frees_this_frame_by_alloc_site_only_table, p.alloc_site_trace, << item);

        num_frees_this_frame   += p.count;
        bytes_freed_this_frame += p.bytes;

        // log("[a] index % count % bytes %\n", it, num_frees_this_frame, bytes_freed_this_frame);
        cursor += size_of(Frees_This_Frame);
    }

    assert(cursor == array.data + array.count);


    //
    // Update derived properties:
    //

    if info.num_live {
        for * item: snap.memory_items_table {
            x := *item.summary;

            per := x.bytes / cast(float) max(x.count, 1);
            item.bytes_per_allocation = per;

            // @Incomplete: We aren't really making things hotter if they have more allocations per frame,
            // we are just caring about any allocations per frame, for heat...

            // @Incomplete: Frame-rate dependent!

            factor := 0.0;
            heat_type := cast(Compute_Heat_Type) current_compute_heat;
            if #complete heat_type == {
                case .SLOW;     factor = .05;
                case .MEDIUM;   factor = .15;
                case .FAST;     factor = .3;
                case .INSTANT;  factor = 1;
            }

            // target := ifx  x.allocations_since_last_visualizer_update then 1.0;
            target := cast(float) x.allocations_since_last_visualizer_update;
            item.heat = lerp(item.heat, target, factor);
        }
    }

    // We don't use heat the same way on these, now...
    // copy_heat_from_live_items(*snap.memory_items_table, *snap.allocs_this_frame_table);
    // copy_heat_from_live_items(*snap.memory_items_table, *snap.frees_this_frame_table);

    snap.num_live                   = num_live;
    snap.bytes_live                 = bytes_live;
    snap.num_allocations_this_frame = num_allocations_this_frame;
    snap.num_frees_this_frame       = num_frees_this_frame;
    snap.bytes_allocated_this_frame = bytes_allocated_this_frame;
    snap.bytes_freed_this_frame     = bytes_freed_this_frame;

    snap.frame_index = index_of_this_usage_update;

    if currently_recording add_current_snapshot_to_recording();

    index_of_this_usage_update += 1;
}

update_metrics :: (using snap: *Snapshot) {
    for * item: snap.memory_items_table {
        item.metric = item.heat;
    }

    for * item: snap.allocs_this_frame_table {
        item.metric = item.heat;
    }

    for * item: snap.frees_this_frame_table {
        item.metric = item.heat;
    }

    if snap.memory_items_table.count {
        vis_metric_low  =  FLOAT32_INFINITY;
        vis_metric_high = -FLOAT32_INFINITY;
        vis_metric_sum  := 0.0;

        for * x: snap.memory_items_table {
            metric := x.metric;
            vis_metric_low  = min(vis_metric_low,  metric);
            vis_metric_high = max(vis_metric_high, metric);
            vis_metric_sum += metric;
        }

        vis_metric_mean = vis_metric_sum / cast(float) snap.memory_items_table.count;
    }
}

check_minimum_size :: (array: [] u8, $type: Type) -> (info: *type, data: [] u8) {
    size := size_of(type);
    if array.count < size {
        log_error("When handling a message, it was too short; we only got % bytes, but we need at least % to hold a %.\n", array.count, size, type);
        respond_to_fatal_error();
        return null, .[];
    }

    info := cast(*type) array.data;

    return info, advance(array, size);
}

Any_Tag_Haver :: struct {
    tag: Vis_Protocol_Tag;
}

check_minimum_size :: (array: [] u8, info: *$T/interface Any_Tag_Haver, bytes: s64) -> bool {
    if array.count < bytes {
        log_error("When handling a message, it was too short; the data area was only % bytes, but we need at least % bytes. The message type was %: %\n", array.count, bytes, info.tag, <<info);
        respond_to_fatal_error();
        return false;
    }

    return true;
}

init_live_allocations :: () {
    s := array_add(*snapshots);  // This is the initial snapshot, which shall always exist!
    s.primary = true;

    success, channel := reader_create_channel(MEMORY_VISUALIZATION_CHANNEL_NAME, CHANNEL_DATA_BYTES);

    if success {
        memory_channel_initted = true;
        memory_channel = channel;
    }
}

fini_live_allocations :: () {
    reader_release_channel(*memory_channel);
}

advance :: (array: [] u8, bytes: s64) -> result: [] u8 {
    assert(array.count >= bytes);

    result := array;
    result.data  += bytes;
    result.count -= bytes;

    return result;
}


#scope_module

address_to_packed_stack_trace: Table(*void, *Packed_Packed_Stack_Trace);

address_to_packed_stack_trace_procedure_info: Table(*void, Packed_Stack_Trace_Procedure_Info);
index_to_string: Table(s32, string);  // This should probably just be a consecutive array but we are doing this for now.

connection_is_live := false;

snapshots: [..] Snapshot;

memory_channel_initted := false;

#scope_file

index_of_this_usage_update: s64;

memory_channel: Read_Channel;
CHANNEL_DATA_BYTES :: 64 * 1024 * 1024;

#import "Shared_Memory_Channel";
#import "Hash_Table";
#import "Protocol_For_Memory_Visualization";

respond_to_fatal_error :: () {
    memory_channel_initted = false;
    connection_is_live     = false;
    live_allocations_scroll_value     = 0;
}

copy_heat_from_live_items :: (source: *Table(*Packed_Packed_Stack_Trace, Memory_Item), dest: *Table(*Packed_Packed_Stack_Trace, Memory_Item)) {
    // Copy heat values from the allocations.
    // Maybe there is some other definition of heat such that freed guys should have their own,
    // but, ehh.  Note that if something is allocated and freed on the same frame, we won't have
    // an allocation record for it, since it went away before the report, so we call it 1.0 hot.

    for * item: << source {
        alloc_item := table_find_pointer(source, item.common.alloc_site_trace);
        if alloc_item {
            item.heat = alloc_item.heat;
        } else {
            item.heat = cast(float) item.common.count;
        }
    }
}

