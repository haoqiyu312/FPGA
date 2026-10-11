# Standalone synthesis only: does not build/replace the media player bitstream.
# TOUCH_CHECK_TOP may be touch_menu_control (default) or touch_menu_overlay.
if {[catch {
    set root [file normalize [file join [file dirname [info script]] ..]]
    set top touch_menu_control
    if {[info exists env(TOUCH_CHECK_TOP)]} {set top $env(TOUCH_CHECK_TOP)}
    if {$top ni {touch_menu_control touch_menu_overlay}} {error "Invalid touch check top"}
    import_device eagle_s20.db -package EG4S20BG256
    set source_files "$root/rtl/touch_menu_hit.v $root/rtl/${top}.v"
    read_hdl -file $source_files -top $top
    optimize_rtl
    optimize_gate
    puts "TOUCH_SYNTHESIS_PASSED: $top"
} err]} {
    puts "TOUCH_SYNTHESIS_FAILED: $err"
    exit 1
}
exit 0
