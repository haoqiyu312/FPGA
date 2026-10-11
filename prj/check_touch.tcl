# Standalone synthesis only: does not build/replace the media player bitstream.
# TOUCH_CHECK_TOP selects a standalone module (default: touch_menu_control).
if {[catch {
    set root [file normalize [file join [file dirname [info script]] ..]]
    set top touch_menu_control
    if {[info exists env(TOUCH_CHECK_TOP)]} {set top $env(TOUCH_CHECK_TOP)}
    if {$top ni {touch_menu_control touch_menu_overlay i2c_register_master gt911_touch_reader touch_coordinate_map touch_player_frontend}} {error "Invalid touch check top"}
    import_device eagle_s20.db -package EG4S20BG256
    set source_files "$root/rtl/touch_menu_hit.v $root/rtl/touch_menu_control.v $root/rtl/touch_menu_overlay.v $root/rtl/i2c_register_master.v $root/rtl/gt911_touch_reader.v $root/rtl/touch_coordinate_map.v $root/rtl/touch_player_frontend.v"
    read_hdl -file $source_files -top $top
    optimize_rtl
    optimize_gate
    puts "TOUCH_SYNTHESIS_PASSED: $top"
} err]} {
    puts "TOUCH_SYNTHESIS_FAILED: $err"
    exit 1
}
exit 0
