#!/bin/bash
source ~/.bash_profile

export Z88DK_DIR=z88dk-2018-08-24
export Z88DK=${HOME}/${Z88DK_DIR}
export Z80_OZFILES=$HOME/${Z88DK_DIR}/lib/clibs
export ZCCCFG=${HOME}/${Z88DK_DIR}/lib/config
export PATH=${HOME}/${Z88DK_DIR}/bin:${PATH}

#echo -ne "Assembling file:" $1 "\n"

#make clean

# NextDAW editor
make
#make dotcommand_cd
#make dotcommand_mkdir
#make dotcommand_rmdir
#make dotcommand_rm

make package
make copy_flashair

#z88dk-dis -mz80-zxn -o 0x2000 -s 0x21BB RMDIR2 | more 

echo -ne "Complete!\n"
