set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
import_device eagle_s20.db -package EG4S20BG256
open_project {TF_MEDIA_OLED.al}
import_db {TF_MEDIA_OLED_Runs/phy_1/TF_MEDIA_OLED_pr.db}
# Reapply the current SDC to the routed database before final checks.
clear_sdc
read_sdc ../constraints/tf_media_oled.sdc
set_param route fix_hold on
fix_hold
update_timing -mode final
report_timing_summary -file {TF_MEDIA_OLED_Runs/phy_1/TF_MEDIA_OLED_hold.timing}
report_area -io_info -file {TF_MEDIA_OLED_Runs/phy_1/TF_MEDIA_OLED_hold.area}
bitgen -bit {TF_MEDIA_OLED_Runs/phy_1/TF_MEDIA_OLED_hold.bit}
exit
