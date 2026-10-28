# Resume routing from the R2 placement checkpoint without changing constraints.
set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
import_device eagle_s20.db -package EG4S20BG256
import_db {SW4_R2_place.db}
set_param route effort routability
route
set_param route fix_hold on
fix_hold
update_timing -mode final
report_timing_summary -file {SW4_R2_final.timing}
report_area -io_info -file {SW4_R2_final.area}
export_db {SW4_R2_final.db}
bitgen -bit {SW4_R2_candidate.bit}
exit
