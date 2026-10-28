# Physical implementation of the current R2 synthesis with explicit PLL locations.
set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
import_device eagle_s20.db -package EG4S20BG256
import_db {TF_MEDIA_Runs/syn_1/TF_MEDIA_gate.db}
read_adc {../constraints/tf_media.adc}
set_param place fix_hold off
set_param place pr_strategy 5
set_param place seed 2
set_param route effort routability
place
report_timing_summary -file {SW4_R2_place.timing}
export_db {SW4_R2_place.db}
route
set_param route fix_hold on
fix_hold
update_timing -mode final
report_timing_summary -file {SW4_R2_final.timing}
report_area -io_info -file {SW4_R2_final.area}
export_db {SW4_R2_final.db}
bitgen -bit {SW4_R2_candidate.bit}
exit
