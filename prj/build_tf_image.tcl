set project_dir [file dirname [file normalize [info script]]]
cd $project_dir
import_device eagle_s20.db -package EG4S20BG256
open_project {TF_IMAGE.al}
reset_runs {syn_1}
launch_runs {syn_1 phy_1} -jobs 2
wait_run syn_1
wait_run phy_1
save_best_bits
exit
