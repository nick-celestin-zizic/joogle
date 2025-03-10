View_Mode :: enum u8 {
    SETTINGS         :: 0;
    INFO             :: 1;
    GRAPHS           :: 2;
    LIVE_ALLOCATIONS :: 3;
}

current_view_mode := View_Mode.GRAPHS;

draw_sidebar :: (sidebar: Rect) {
    k :: .5;
    bg := Vector4.{.15*k, .13*k, .13*k, 1};
    Simp.set_shader_for_color(false);
    draw_quad(sidebar, bg);

    outer_margin := sidebar.w / 14;
    left, right := cut_left(sidebar, outer_margin);
    scrap, mid  := cut_right(right, outer_margin);

    _, strip := cut_top(mid, outer_margin);

    button_w := strip.w;

    button_theme: Button_Theme;  // This will have the default Button_Theme values.
    button_theme.enable_variable_frame_thickness = true;
    button_theme.font = sidebar_font;
    
    button_margin := button_w / 12;

    r := strip;
    r.y = strip.y + button_margin;
    r.h = button_w;

    pressed_settings := button(r, "Settings", *button_theme);
    if pressed_settings  current_view_mode = .SETTINGS;
    
    r.y += button_w + button_margin;
    pressed_info := button(r, "Info", *button_theme);
    if pressed_info  current_view_mode = .INFO;
    
    r.y += button_w + button_margin;
    pressed_graphs := button(r, "Graphs", *button_theme);
    if pressed_graphs  current_view_mode = .GRAPHS;

    r.y += button_w + button_margin;
    pressed_allocs := button(r, "Allocs", *button_theme);
    if pressed_allocs  current_view_mode = .LIVE_ALLOCATIONS;
}
