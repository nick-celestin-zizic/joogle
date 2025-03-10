treemap_initted := false;
treemap: Treemap;
treemap_display: Treemap_Display;

simulate_treemap :: () {
    // First, zoom:
    
    move_toward(*zoom_current, zoom_target, current_dt, zoom_current*5, zoom_current*15);

    // Now, linear motion:
    
    // First, make a unit vector for movement direction,
    // independent of time.

    fnorth := cast(float)(north || north_alt);
    fsouth := cast(float)(south || south_alt);
    feast  := cast(float)(east  || east_alt);
    fwest  := cast(float)(west  || west_alt);

    dir := unit_vector(Vector2.{fwest - feast, fnorth - fsouth});

    SPEED_BASE :: .7;
    delta := SPEED_BASE * (dir * cast(float) current_dt) / zoom_current;
    treemap_offset += delta;

    aspect := window_height / ifx cast(float) window_width else 1;

    Clamp(*treemap_offset.x, -.5, .5);
    Clamp(*treemap_offset.y, -.5*aspect, .5*aspect);

    treemap_offset_in_pixels = treemap_offset*cast(float)window_width;


    //
    // See if our thickness settings changed.
    //

    border_type := cast(Border_Display_Type) border_display_type_index;
    if border_type != border_display_type {
        border_display_type = border_type;

        // We must rebuild the Treemap_Display when the borders change,
        // since aspect ratios of some things will change. That said,
        // maybe this is bad because you don't want the data changing
        // just because you tweaked borders? I dunno man.
        
        treemap_display.dirty = true;
    }

    module_border_size = 0;
    file\ _border_size = 0;

    if border_type == {
        case .MODULES;
            module_border_size = get_pixels(false);
        case .MODULES_AND_FILES;
            module_border_size = get_pixels(false);
            file\ _border_size = get_pixels(true);
    }
}

draw_treemap :: (entire_region: Rect, fg: Vector4) {
    simulate_treemap();
    
    current_proc_info = null;

    if !treemap_initted {
        treemap_initted = true;
        incept_treemap_data(*treemap);
        treemap_display = init_treemap_display(*treemap);
    }

    {
        // Draw a rectangle across entire_region, because we might pan off it; this also
        // serves as a border color due to the shrink operation to compute 'inner'.

        Simp.set_shader_for_color(false);
        p0, p1, p2, p3 := get_quad(entire_region);

        color := Vector4.{0.1, .07, .07, 1};
        Simp.immediate_quad(p0, p1, p2, p3, color);
    }
    
    inner := shrink(entire_region, max(entire_region.w * .005, 1));
    
    recompute_if_dirty(*treemap);
    recompute_if_dirty(*treemap_display, .{inner.w, inner.h}, treemap_border_proc);

    p0, p1, p2, p3 := get_quad(inner);

    Simp.set_scissor(p0, p2);
    defer Simp.clear_scissor();

    new_current_node := null;

    cx := cursor_pos.x;
    cy := cursor_pos.y;

    corner := Vector2.{inner.x, inner.y};
    
    center := (p0 + p2) * .5;

    ToRelative := Matrix3_Identity;
    ToRelative._13 = -center.x;
    ToRelative._23 = -center.y;

    Scale := Matrix3_Identity;
    Scale._11 = zoom_current;
    Scale._22 = zoom_current;

    off := treemap_offset_in_pixels;
    Offset := Matrix3_Identity;
    Offset._13 = off.x;
    Offset._23 = off.y;

    ToWorld := Matrix3_Identity;
    ToWorld._13 = center.x;
    ToWorld._23 = center.y;


    T := ToWorld * Scale * Offset * ToRelative;

    Simp.set_shader_for_color(false);

    current_metric := THE_METRICS[current_metric_index].proc;
    { // @Copypasta
        if current_metric == metric_blend {
            prep_global_bound_metrics(codex_help.procedures);
        }
    }

    can_pick := !events_occluded();
    if !is_inside(cursor_pos.x, cursor_pos.y, inner) can_pick = false;
    if background_occluded  can_pick = false;
    
    for * node: treemap_display.nodes {
        q := corner + node.corner;

        p0: Vector3;
        p0.xy = q;
        p0.z = 1;
        
        p1, p2, p3 := p0;
        p1.x  += node.size.x;
        p2.xy += node.size;
        p3.y  += node.size.y;

        p0 = T * p0;
        p1 = T * p1;
        p2 = T * p2;
        p3 = T * p3;

        if node.node.children {
            if node.border {
                color: Vector4;
                type := cast(Treemap_Node_Type) node.node.user_data_s64;

                if type == {
                    case .MODULE;  color = module_border_color;
                    case .FILE;    color = file\ _border_color;
                }

                // @Cleanup: Being lazy here in ways that elevate fill rate (but also
                // avoiding hairline cracks...!) In principle we should just draw 4
                // rectangles around... and that would look better too if we are making
                // things look nice.
                
                Simp.immediate_quad(p0.xy, p1.xy, p2.xy, p3.xy, color);
            }
        } else {
            c0, c1, c2, c3: Vector4 = ---;
            if node.node.user_data_s64 == xx Treemap_Node_Type.PROCEDURE {
                proc := cast(*Procedure_Record) node.node.user_data_pointer;
                metric := current_metric(proc);  // @Speed: Store this?
                color := get_color_for_current_metric(metric, metric_low, metric_mean, metric_high);

                c1, c3 = color;

                c0 = color;
                c0.xyz *= .85;
                
                c2 = color;
                c2.xyz *= 1.1;
                K :: 0.05;
                c2.x += K;
                c2.y += K;
                c2.z += K;
                Clamp(*c2.x, 0, 1);
                Clamp(*c2.y, 0, 1);
                Clamp(*c2.z, 0, 1);
                
                if can_pick && (cx >= p0.x) && (cx < p2.x) && (cy >= p0.y) && (cy < p2.y) {
                    info, found := table_find(*proc_to_treemap_proc_info, proc);
                    if found {
                        current_proc_info = info;
                        current_proc_rect = get_rect(p0.x, p0.y, p2.x-p0.x, p2.y-p0.y);
                    }
                }
            } else {
                c0, c1, c2, c3 = .{.1, .1, .1, 1};
            }

            Simp.immediate_quad(p0.xy, p1.xy, p2.xy, p3.xy, c0, c1, c2, c3);
        }

    }

    Simp.immediate_flush();

//    if new_current_node  current_node = new_current_node;
    
}

incept_treemap_data :: (treemap: *Treemap) {
    root := add_node(treemap, "Root", null);
    
    for module: codex_help.modules {
        node := add_node(treemap, copy_string(decode(*module.module_name)), root);
        node.user_data_pointer = module;
        node.user_data_s64     = xx Treemap_Node_Type.MODULE;

        table_add(*module_nodes, module, node);
    }

    for file: codex_help.files {
        module_node, found := table_find(*module_nodes, codex_help.modules[file.module_index]);
        assert(found);
        if !found continue;
        
        node := add_node(treemap, copy_string(decode(*file.fully_pathed_filename)), module_node);
        node.user_data_pointer = file;
        node.user_data_s64     = xx Treemap_Node_Type.FILE;
        
        table_add(*file_nodes, file, node);
    }

    array_reset(*treemap_proc_infos);
    
    for proc: codex_help.procedures {
        file_node, found := table_find(*file_nodes, codex_help.files[proc.file_index]);
        assert(found);
        if !found continue;
        
        node := add_node(treemap, copy_string(decode(*proc.name)), file_node);
        size := cast(float64) proc.num_expressions;
        node.size = size;
        node.user_data_pointer = proc;
        node.user_data_s64     = xx Treemap_Node_Type.PROCEDURE;

        info := array_add(*treemap_proc_infos);
        info.record = proc;
    }

    for * treemap_proc_infos {
        // These will no longer be added to, so we can just put the pointers
        // into the hash table.

        table_add(*proc_to_treemap_proc_info, it.record, it);
    }
    
    compute_metrics(treemap_proc_infos);
}

module_nodes: Table(*Module_Record, *Treemap_Node);
file\ _nodes: Table(*File_Record,   *Treemap_Node);

treemap_proc_infos: [..] Proc_Info;
proc_to_treemap_proc_info: Table(*Procedure_Record, *Proc_Info);


Treemap_Node_Type :: enum u8 {
    ROOT      :: 0;
    MODULE    :: 1;
    FILE      :: 2;
    PROCEDURE :: 3;
}

#import "Treemap";


move_toward :: (a_pointer: *float, target: float, dt: float, rate_up: float, rate_down: float = -1.0) {
    a := << a_pointer;

    if a > target {
        if rate_down == -1 rate_down = rate_up;
        a -= dt * rate_down;
        if a < target  a = target;
        << a_pointer = a;
    } else if a < target {
        a += dt * rate_up;
        if a > target  a = target;
        << a_pointer = a;
    }
}


treemap_border_proc :: (corner: Vector2, outer_dimensions: Vector2, node: *Treemap_Node, parent: *Display_Node, border: *[4] float) {
    type := cast(Treemap_Node_Type) node.user_data_s64;
    if type == .PROCEDURE return;

    if !parent return;

    // Here we write into only the WEST and SOUTH border slots, in order to prevent doubling up
    // when two nodes are next to each other. (It looks bad to have borders be twice as THICC
    // sometimes, for no good reason).

    // There are some other stipulations behind whether we write a border. We know that the Display_Node generation
    // starts at corner (0, 0) and these coordinates are remapped later for display. So if x or y are 0, we know
    // we are on the west or south edge, and choose also not to output a border (because such borders are goofy and
    // kinda unnecessary).
    
    if type == .MODULE {
        bx, by := module_border_size;

        // If the region is very thin, step down the border. But we don't want to do this
        // continuously, since that looks bad (?). So we do it in discrete steps. But hey,
        // let's do a max of 5 steps because of floating-point error and stuff.
        // We do bx and by separately since we want them to match neighboring regions without
        // discontinuities, and if we size both in tandem we tend to introduce visual discontinuities.
        
        for 1..5 {
            if bx < .125 * outer_dimensions.x  break;
            bx *= .5;
        }

        for 1..5 {
            if by < .125 * outer_dimensions.y  break;
            by *= .5;
        }

        if corner.x > 0 {
            (<<border)[Border_Direction.WEST]  = bx;
        }

        if corner.y > 0 {
            (<<border)[Border_Direction.SOUTH] = by;
        }
    } else if type == .FILE {
        // We know each FILE's parent is a MODULE, so we don't
        // even bother to check that. Just, are we on the edge
        // of that parent's space?
        b := file_border_size;
        parent_west  := parent.corner.x + parent.border[Border_Direction.WEST];
        parent_south := parent.corner.y + parent.border[Border_Direction.SOUTH];

        // If we are on the west or south border of our group, don't draw the border in that direction,
        // since it will double up with the module border, which looks bad.
        // *BUT*, if module border size is 0, go ahead and write anyway
        // (because if the module borders do not exist, doubling up is not a concern, and in fact some stuff
        // will look bad!)
        EPSILON :: 0.0001;

        if corner.x > 0 {
            if (corner.x - parent_west  > EPSILON) || !module_border_size { (<<border)[Border_Direction.WEST]  = b; }
        }

        if corner.y > 0 {
            if (corner.y - parent_south > EPSILON) || !module_border_size { (<<border)[Border_Direction.SOUTH] = b; }
        }
    }
}



Border_Display_Type :: enum {
    NONE              :: 0;
    MODULES           :: 1;
    MODULES_AND_FILES :: 2;
}

BORDER_NAMES :: string.["None", "Modules", "Modules and Files"];

get_pixels :: (file_border: bool) -> float {
    // If file_border == false, it's a module.
    
    mean := sqrt(cast(float)(window_width * window_height));

    factor := ifx file_border then .0015 else .003;
    pixels := factor * mean;
    if pixels < 1  pixels = 1;

    return pixels;
}

module_border_size := 0.0; 
file\ _border_size := 0.0;

module_border_color := Vector4.{.37, .37, .37, 1};
file\ _border_color := Vector4.{.95, .95, .95, 1};

border_display_type := Border_Display_Type.MODULES_AND_FILES;
border_display_type_index: s32;

