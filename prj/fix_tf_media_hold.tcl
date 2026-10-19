set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
import_device eagle_s20.db -package EG4S20BG256
open_project {TF_MEDIA.al}
import_db {TF_MEDIA_Runs/phy_1/TF_MEDIA_pr.db}
set_param route fix_hold on
fix_hold
update_timing -mode final
report_timing_summary -file {TF_MEDIA_Runs/phy_1/TF_MEDIA_hold.timing}
report_area -io_info -file {TF_MEDIA_Runs/phy_1/TF_MEDIA_hold.area}
bitgen -bit {TF_MEDIA_Runs/phy_1/TF_MEDIA_hold.bit}
exit
