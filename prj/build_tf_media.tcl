set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
import_device eagle_s20.db -package EG4S20BG256
open_project {TF_MEDIA.al}
set_param gate pack_effort high -run syn_1
set_param place fix_hold off -run phy_1
set_param place pr_strategy 5 -run phy_1
set_param place seed 2 -run phy_1
set_param route effort routability -run phy_1
reset_runs {syn_1}
launch_runs {syn_1 phy_1} -jobs 2
wait_run syn_1
wait_run phy_1
save_best_bits
exit
