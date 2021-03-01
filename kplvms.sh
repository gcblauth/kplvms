#!/bin/bash
verS=2.9b
# kplvms °°° keeplvmsafe v2.7b by gcblauth@gmail.com
# Snapshot an LVM or a list of LVMs then raw clone or mount.
#
# Advanced options: convert before send: convert .raw to .qcow2 compressed before sending to final destination
#                   benchmark: test run dd from LVM to your rotation dir with many block size options (bs=)
#
# Written and created by:   Gabriel Blauth
# Last Changed: 2021-3-01
#
# Poorly written but hey?! it works!
# Distribute freely
#
# todo: improve help and command list
#
# thanks to: many random sources and the only copied code for the dd benchmark from: tdg5 @dannyguinther
#
################################################################################
# Constant Definitions
# Change the values in this section to match your setup
#
# Functions:
# defS()        -       definitions
# loG()         -       log and display
# readL()       -       read previus log status
# moutT()      -        mount dest dir or prepare nfs/sshfs/luks
# spacE()       -       verify space
# exiT()        -       exit function after operations (besides benchmark)
# AraW()        -       raw main function
# DraW()        -       raw sub function
# tranS()       -       copy and transmission function
# DrsY()        -       rsync sub function
# ArsynC()      -       rsync main function
# AconverT()    -       convert function
# recY()        -       recycle function
# bencH()       -       benchmark function
# helP()        -       help function
# main code     -       the thing that makes this work
#############################################
## Visit this project page and share your results and feedback :) 
## https://github.com/kplvms
#############################################
#some colors
NC='\033[0m' # No Color
CYA='\033[0;36m'
CYAA='\033[1;35m'
LG='\033[1;32m'
RED='\033[0;31m'

##### Definitions:
#
defS() {
ddBS=524288                     # the dd block size (bs=) parameter - try the benchmark feature to test the best value for your enviroment !
MOFFSET=1048576                 # Mount offset for when mounting the snapshot (Here aligned to the beginning of partition 2048 * 512 = 1048576)
SZ=10G                          # snapshot size
ROTT=current                    # Rotation directory (* must exist)
dts=$(date '+%d_%m_%Y')         # Destination directory (in this case, 25_12_2021) (created if non existent)

## Logging variables
RLOGFILE=/root/vmrbackup.log    # RSYNC transfer log file
LOGFILE=/root/vmbackup.log      # log file
ERRFILE=/root/vmbackup.err      # error log file
oneLOG=/root/vmone.log          # one line log
Lverb=1                         # Lverb - 0 - (only log)  - 1 - (echo normal cmds to stdout) - 2 - (echo normal and error codes to stdout)
lFORMAT="[%05.f-%s] - %s\n"     # normal logging format: [00001-DD/MM/AAAA - 00:00:00] - cool log message
eFORMAT="%s\n"                  # normal output format : cool output message
eLFORMAT="ERRORLOG - %s\n"      # error output format  : ERRORLOG -  bad output message

dateF="+%d/%m/%Y %T"            # datetime format
logN=0                          # expected cycles var
logT=0                          # done cycles var
eCT=0                           # error counter var
lCT=0                           # log counter var
dtss=$(date "$dateF")           # our start date and time stamp
echo -e "rotation dir: $ROTT | dd blocksize: $ddBS | LVM snapsize: $SZ | log: $LOGFILE | error log: $ERRFILE | rsync log: $RLOGFILE | one line log: $oneLOG\nScript is starting...\n"
}

##### function handle display/logging outside of command execution
## 1 ) message
## 2 ) err (for error reg)
## Lverb "1" - echo normal cmds to stdout) "2" (echo normal and error codes to stdout)
##
loG() {
        # set the date-time
        dt=$(date "$dateF")
        #check if input is piped
        local in="$1"
        if [ -z "$in" ]; then read in; fi
        if [ "$2" = "err" ]; then
                eCT=$((eCT+1))
                printf "$lFORMAT" "$eCT" "$dt" "$in" >>$ERRFILE
                if [ "$Lverb" = 2 ]; then printf "$eLFORMAT" "$in"; fi
        return
        fi
        lCT=$((lCT+1))
                printf "$lFORMAT" "$lCT" "$dt" "$in" >>$LOGFILE
                if [ "$Lverb" -ge 1 ]; then printf "$eFORMAT" "$in"; fi
        return
}
##### function to read the log statuses
## sets variables with line count and bytes
##
##
##

readL() {
        logLIN=$(wc -l < $LOGFILE)
        logSZ=$(find $LOGFILE -printf "%s\n")
        elogLIN=$(wc -l < $ERRFILE)
        elogSZ=$(find $ERRFILE -printf "%s\n")
        return
}
##### function to u/mount / un/lock our backup partition
##
## also sets size variable for backup volume
## default is commented if mount/umount is managed from outside the script
## 
## moutT ("" unlocks and mounts | "lock" locks and umounts)
##
moutT() {
        if [ "$1" = "lock" ]; then
                sync
                # read size before closing
                freeBBa=$(numfmt --to iec --format "%8.4f" "$(df "$BB" | awk '{print $4"000"}'| tail -1)")
##  Example for using luks
##                umount $BB
##                cryptsetup luksClose sda_crypt >>$LOGFILE 2>>$ERRFILE
##  Example umount nfs
##                umount $BB

        else
##  Example for using luks
##                cryptsetup luksOpen /dev/sda sda_crypt --key-file=/root/backup/backup.key >>$LOGFILE 2>>$ERRFILE
##                mount /dev/mapper/sda_crypt $BB >>$LOGFILE 2>>$ERRFILE 
##  Example for using nfs
##                mount -t nfs -o options host:/remote/export $BB >>$LOGFILE 2>>$ERRFILE 
                  sync
                # read size after opening
                freeBB=$(numfmt --to iec --format "%8.4f" "$(df "$BB" | awk '{print $4"000"}'| tail -1)")
                lopB=1  # let our exit know it can display the partition size when we quit.
        fi
}
##### function to check space
##
##
## spacE (lvm or *.file) (destination) ("transfer" - compare to existing files)
##
spacE() {
        declare -i totalspace=0
        declare -i freespace
        DEST=$2
        oktT=0
        FILELIST=$(find ${1})
        if [ "$3" == "transfer" ]; then
                for file in $FILELIST;do
                        [ "$file" = "." ] || [ "$file" = ".." ] && continue
                        [ -f "$file" ] && totalspace+=$(find "$file" -printf "%s\n")
                done
        else
                Bit=$(lvdisplay -v --units b "$1" | grep Size | awk '{print $3}')
                totalspace+=$Bit
        fi
        freespace=$(df "$DEST" | awk '{print $4"000"}'| tail -1)
        [ "$totalspace" -lt "$freespace" ] && oktT=1 && loG "Good! $(numfmt --to iec --format "%8.4f" "$totalspace") is less than $(numfmt --to iec --format "%8.4f" "$freespace")" || loG "OH NO! $(numfmt --to iec --format "%8.4f" "$totalspace") is more than $(numfmt --to iec --format "%8.4f" "$freespace")"
        totaL="Required space for $1: $(numfmt --to iec --format "%8.4f" $totalspace) || Free space in $2: $(numfmt --to iec --format "%8.4f" $freespace)"
}
##### normal termination
##
##
##
## Gives output on log files and space used. Both in stdout and logfile
##
exiT() {
        if [ "$staT" == "rawB" ]; then
                loG "Free ROTATION memory before start: $freeBT"
                logBT=$freeBT
                freeBT=$(numfmt --to iec --format "%8.4f" "$(df "$BT" | awk '{print $4"000"}'| tail -1)")
                loG "Free ROTATION memory        after: $freeBT"
        fi
                loG "Free BACKUP memory before start: $freeBB"
                loG "Free BACKUP memory        after: $freeBBa"
        loG "Log lines before start: $logLIN size: $logSZ  |  Errorlog lines before: $elogLIN size: $elogSZ"
        logER=$elogSZ
        readL
        loG "Log lines          now: $logLIN size: $logSZ  |  Errorlog lines    now: $elogLIN size: $elogSZ"
        loG "Script started : $dtss -- ended : $dt"
        echo "$dtss -- $dt -- $logE -- Activities: $logN/$logT OK -- Disks: $logBT/$freeBT rot Now -- $freeBB/$freeBBa bkp -- errors: $((elogSZ-logER))" >>$oneLOG
        loG "$dtss -- $dt -- $logE -- Activities: $logN/$logT OK -- Disks: $logBT/$freeBT rot Now -- $freeBB/$freeBBa bkp -- errors: $((elogSZ-logER))"
        loG "This is the end. For now ;)"
        loG "END --- keep lvm safe v$verS--------------------------------------------------------------------"
        exit
}
##### raw function
##
## 1)Test if directories exist and define if its a list file or a an LVM link
## 2)Performs all raw actions
##
##
AraW() {
        # check if directories exist
        if [ -d "$2" ]; then echo "backup dir $2"; else echo "backup dir $2 NOT FOUND!" && exit; fi
        if [ -d "$3" ]; then echo "rotation dir $3";else echo "rotation dir $3 NOT FOUND" && exit; fi
        BB=$2
        BT=$3
        # remember the free space of rotation dir before we start
        freeBT=$(numfmt --to iec --format "%8.4f" "$(df "$3" | awk '{print $4"000"}'| tail -1)")
        # tell our exit script to display our rotation dir info on exit
        staT="rawB"
        # remember the log sizes
        readL
        # define if its a LVM Link or a List file
        if [ -h "$1" ]; then
                loG "Single run. Just one LVM to backup."
                logE="RAW Single run $1"
                DraW "$1" "$2" "$3"/${ROTT} "$4"
                if [ "$4" == "-qcow2" ]; then
                        loG "+ Convert to qcow2 before transfer"
                        logE="RAW+QCOW2 Single run $1"
                        vmname=$(basename "$1")
                        AconverT "$3"/${ROTT}/"${vmname}".raw "$3"/${ROTT} single
                        tranS "$1" "$2" "$3"/${ROTT} -qcow2 crypt
                        exiT
                else
                        tranS "$1" "$2" "$3"/${ROTT} raw crypt
                        exiT
                fi
        fi
        if [ -f "$1" ]; then echo "Multi LVM list to backup: $1 Number of files: $(egrep -cv '#|^$' "$1")"; else echo -e "List file $1 not fount!\nAborting..." && exit; fi
        loG "--- LIST file $1 exists, going on. There are $(egrep -cv '#|^$' "$1") lines to execute"
        logE="RAW Multi run $1 | $(egrep -cv'#|^$' "$1") runs"
        while read -r arg_1; do
                # lets avoid all commented and empty lines please
                [[ "$arg_1" =~ ^#.*$ ]] && continue
                [[ "$arg_1" = "" ]] && continue
                DraW "${arg_1}" "$2" "$3"/${ROTT} "$4"
        done < "${1}"
        if [ "$4" == "-qcow2" ]; then
                loG "+ Convert to qcow2 before transfer"
                logE="RAW+QCOW2 Multi run $1 | $(egrep -cv '#|^$' "$1") runs"
                AconverT "$3"/${ROTT} "$3"/${ROTT}
                tranS listMultiple "$2" "$3"/${ROTT} -qcow2 crypt
                exiT
        else
                tranS listMultiple "$2" "$3"/${ROTT} raw crypt
                exiT
        fi
        exiT
}
##### Snapshot and Raw capture function
##
## 1)Test if directories exist and define if its a list file or a an LVM link
## 2)Performs all raw actions
##
##
DraW() {
        cdtss=$(date '+%d/%m/%Y %T')
        if [ -h "$1" ]; then loG "LVM to backup: $1"; else loG "LVM $1 NOT FOUND!" && return; fi
        vmname=$(basename "$1")
        [ -e "$3/$vmname.raw" ] && loG "ERROR! Rotation file: $3/$vmname.raw - ALREADY EXISTS!" && return || loG "Rotation file: $3/$vmname.raw"
        loG "input file: $1"
        if [ "$4" == "-qcow2" ]; then ttype="qcow2" && loG "+ Convert to qcow2 flag set to ON"; else ttype="raw"; fi
        loG "dest file: $2/${dts}/${vmname}.${ttype}"
        if  [ -e "$1" ]; then
                loG "Script starts RAW mode for $1 - $cdtss"
                loG "Testing space required for DD"
                spacE "$1" "$3"
                if [ "$oktT" -eq 0 ]; then loG "+++ ABORT DD for $1. $totaL" err && return; else loG "Space for $1 OK. $totaL"; fi
                loG "--- LOCAL LVM exists, going on..."
                loG "Creating snapshot --- output:"
                lvcreate --size ${SZ} --snapshot --name "${vmname}"-snapshot "${1}" >>$LOGFILE 2>>$ERRFILE
                # display to stdout the result of lvcreate
                if [ "$Lverb" -ge 1 ]; then tail -n 1 $LOGFILE; fi
                if  [ -e "${1}-snapshot" ]; then
                        loG "--- DD start: DD started for $1 --- output:"
                        # let Error output of dd to logfile (it logs speed at the err output)
                        dd if="${1}"-snapshot of="${3}"/"${vmname}".raw bs=$ddBS >>$LOGFILE 2>>$LOGFILE
                        # display to stdout the result of dd if we should
                        if [ "$Lverb" -ge 1 ]; then tail -n 2 $LOGFILE; fi
                        logN=$((logN+1))
                        loG "--- DD end : DD ended for $1"
                        loG "Removing snapshot --- output:"
                        lvremove --force "${1}"-snapshot >>$LOGFILE 2>>$ERRFILE
                        # display to stdout the result of lvcreate
                        if [ "$Lverb" -ge 1 ]; then tail -n 1 $LOGFILE; fi
                else
                        loG "--- SNAPSHOT NOT FOUND!!!"
                        loG "$1-snapshot does not exist. Cant continue $1 backup!" err
                        loG "Removing snapshot --- output:"
                        lvremove --force "${1}"-snapshot >>$LOGFILE 2>>$ERRFILE
                        # display to stdout the result of lvcreate
                        if [ "$Lverb" -ge 1 ]; then tail -n 1 $LOGFILE; fi
                        loG "STOP. Cant continue $1 backup!" err
                        loG "quitted with errors $1 backup not complete !!!"
                        return
                fi
                loG "$1 raw copy complete to ${3}/${vmname}.raw !"
                loG "LVM $vmname ------------------------------------------------------------------ started : $cdtss"
                ls -lah "${3}"/"${vmname}".raw | loG
                loG "LVM $vmname ----------------------------------------------------------- ended"
        else
                loG "--- LOCAL LVM DOES NOT EXIST!!!"
                loG "LVM ${1} does not exist. Cant continue backup!"
                return
        fi
        return
}
##### Transfer function
##
## 1)Test if directories exist and define if its a list file or a an LVM link
## 2)Performs all raw actions
##
## to-do: ssh target
##
tranS() {
        if [ ! "$1" = "listMultiple" ]; then
                true
                if [ ! "$1" = "file" ]; then
                        cdtss=$(date '+%d/%m/%Y %T')
                        vmname=$(basename "$1")
                        if [ "$4" == "-qcow2" ]; then ttype="qcow2"; else ttype="raw"; fi
                        loG "--- Single file to transfer. $3/${vmname}.${ttype} to ${2}/${dts}"
                        #check if we have to mount the disk moutT
                        if [ "$5" == "crypt" ]; then loG "unlocking backup --- output:" && moutT; fi
                        loG "Testing space required for TRANSFER"
                        spacE "${3}/${vmname}.${ttype}" "$2" transfer
                        if [ "$oktT" -eq 0 ]; then loG "+++ NO SPACE - ABORT RSYNC for $1. $totaL " err && loG "+++ ABORT NO SPACE - RSYNC for $1. $totaL" && return; else loG "Space for $1 OK. $totaL "; fi
                        loG "--- Creating dir ${2}/${dts} ---"
                        mkdir -p "${2}"/"${dts}"
                        loG "--- Starting rsync for ${3}/${vmname}.${ttype} --- output:"
                        rsync -avh "${3}"/"${vmname}".${ttype} "${2}"/"${dts}"/ | grep "\S">>$LOGFILE 2>>$ERRFILE
                        # display to stdout the result of lvcreate
                        if [ "$Lverb" -ge 1 ]; then tail -n 2 $LOGFILE; fi
                        loG "$1 Transfer complete to ${2}/${dts}/${vmname}.${ttype} !"
                        loG "Transfer ------- started : $cdtss"
                        ls -lah "${2}"/"${dts}"/"${vmname}"."${ttype}" | loG
                        logT=$(find "${2}"/"${dts}"/"${vmname}"."${ttype}" | wc -l)
                        loG "Transfer ------- ended"
                        #check if we have to umount the disk moutT
                        if [ "$5" == "crypt" ]; then loG "--- locking backup" && moutT lock; fi
                        return
                fi
        fi
        cdtss=$(date '+%d/%m/%Y %T')
        if [ "$4" == "-qcow2" ]; then ttype="qcow2"; else ttype="raw"; fi
        if [[ "$1" = "file" ]]; then loG "--- Single file to transfer. ${3}.${ttype} to ${2}/${dts} ---"; else loG "--- Multiple files to transfer. ${3}/*.${ttype} to ${2}/${dts} ---"; fi
        #check if we have to mount the disk moutT
        if [ "$5" == "crypt" ]; then loG "unlocking backup" && moutT; fi
        loG "Testing space required for transfer..."
        if [[ "$1" = "file" ]]; then spacE "$3".${ttype} "$2" transfer; else spacE "${3}/*.${ttype}" "$2" transfer; fi
        if [ "$oktT" -eq 0 ]; then loG "+++ NO SPACE ABORT RSYNC for $1. $totaL" err && loG "+++ NO SPACE ABORT - RSYNC for $1. $totaL " && return; else loG "Space for $2 OK. $totaL"; fi
        loG "--- Creating dir ${2}/${dts} ---"
        mkdir -p ${2}/${dts}
        if [ "$1" == "file" ]; then loG "--- Starting rsync from ${3}.${ttype} to ${2}/${dts}/ --- output:" && rsync -avh ${3}.${ttype} ${2}/${dts}/ | grep "\S" >>$LOGFILE 2>>$ERRFILE; else loG "--- Starting rsync from ${3}/*.${ttype} to ${2}/${dts}/ --- output:" && rsync -avh ${3}/*.${ttype} ${2}/${dts}/ | grep "\S">>$LOGFILE 2>>$ERRFILE; fi
        # display to stdout the result of lvcreate
        if [ "$Lverb" -ge 1 ]; then tail -n 2 $LOGFILE; fi
        loG "Transfer complete to ${2}/${dts}/ !"
        loG "Transfer ------- started : ""$cdtss"
        if [ "$1" = "file" ]; then vmname=$(basename "$3".${ttype}) && loG "ls -lah "${2}"/"${dts}"/ --- output:" && ls -lah "${2}"/"${dts}"/"${vmname}" >>$LOGFILE; else loG "ls -lah ${2}/${dts}/*.${ttype} --- output:" && ls -lah "${2}"/"${dts}"/*."${ttype}" >>$LOGFILE; fi
        if [ "$1" = "file" ]; then vmname=$(basename "$3".${ttype}) && logT=$(find "$2"/"${dts}"/"${vmname}" | wc -l); else logT=$(find "$2"/"${dts}"/*.${ttype} | wc -l); fi
        loG "Transfer ------- ended"
        #check if we have to mount the disk moutT
        if [ "$5" == "crypt" ]; then loG "--- locking backup" && moutT lock; fi
        return
}
##### RSYNC mount and transfer
##
## 1)Test if directories exist and define if its a list file or a an LVM link
## 2)Performs all raw actions
##
##
DrsY() {
        cdtss=$(date '+%d/%m/%Y %T')
        if [ -h "$1" ]; then echo "LVM to rsync: $1"; else echo "LVM $1 NOT FOUND!" && return; fi
        vmname=$(basename "$1")
        [ ! -d "$3" ] && echo "ERROR! Mount point does not exist: $3/" && return || echo "Mount point: $3/"
        echo -e "input file: $1\nDest dir: $2/${vmname}\nMount dir: $3/"
        if  [ -e "$1" ]; then
                loG "Script starts RSYNC mode - $1"
                loG "--- LVM exists, going on ..."
                loG "Creating snapshot --- output:"
                lvcreate --size ${SZ} --snapshot --name "${vmname}"-snapshot "${1}" >>$LOGFILE 2>>$ERRFILE
                # display to stdout the result of lvcreate
                if [ "$Lverb" -ge 1 ]; then tail -n 1 $LOGFILE; fi
                if  [ -e "${1}-snapshot" ]; then
                        loG "--- mounting $vmname-snapshot on ${3} --- output:"
                        mount -o offset=${MOFFSET} "${1}"-snapshot "${3}" >>$LOGFILE 2>>$ERRFILE
                        loG "--- unlocking bkp disk"
                        moutT
                        [ ! -d "$2/$vmname/" ] && loG "ERROR! Rsync destination dir does not exist: $2/$vmname/" && umount "${3}" && moutT lock &&  lvremove --force "${1}"-snapshot >>$LOGFILE 2>>$ERRFILE && return || loG "Rsync destination: $2/$vmname/"
                        loG "--- rsync starting: for $1 rsync output saved to $RLOGFILE"
                        echo "--- rsync starting: for $1 $dt" >>$RLOGFILE
                        logN=$((logN+1))
                        rsync -raH --inplace --stats --human-readable --progress --exclude=".rec" "${3}"/ "${2}"/"${vmname}"/ >>$RLOGFILE 2>>$ERRFILE
                        if [ "$?" -eq "0" ]; then logT=$((logT+1)); fi
                        #add last lines of Rsync log to Logfile
                        loG "--- last 16 lines of rsync resuls $RLOGFILE ---"
                        tail -n 16 $RLOGFILE | grep "\S">> $LOGFILE
                        # display to stdout the result of rsync
                        if [ "$Lverb" -ge 1 ]; then tail -n 16 $LOGFILE; fi
                        loG "--- EOF rsync resuls $RLOGFILE ---"
                        echo "--- rsync ended: for $1 $dt" >>$RLOGFILE
                        loG "--- umounting $3"
                        umount "${3}" >>$LOGFILE 2>>$ERRFILE
                        loG "Removing snapshot ${1}-snapshot --- output:"
                        lvremove --force "${1}"-snapshot >>$LOGFILE 2>>$ERRFILE
                        # display to stdout the result of lvremove
                        if [ "$Lverb" -ge 1 ]; then tail -n 1 $LOGFILE; fi
                else
                        loG "--- SNAPSHOT NOT FOUND!!!"
                        loG "$1-snapshot does not exist. Cant continue $1 rsync!" err
                        loG "Removing snapshot"
                        lvremove --force "${1}"-snapshot >>$LOGFILE 2>>$ERRFILE
                        loG "STOP. Cant continue $1 rsync!" err
                        loG "quitted with errors $1 rsync not complete !!!"
                        return
                fi
                loG "$1 RSYNC complete to ${2}/$vmname/ !"
                loG "RSYNC $vmname ------------------------------------------------------------------------------- started : $cdtss"
                loG "ls -lah ${2}/${vmname} --- output:"
                ls -lah ${2}/${vmname} >>$LOGFILE
                # display to stdout the result of ls
                if [ "$Lverb" -ge 1 ]; then tail -n$(ls -lah ${2}/${vmname} | wc -l) $LOGFILE; fi
                loG "RSYNC $vmname ------------------------------------------------------------------ ended"
                loG "--- locking bkp disk"
                moutT lock
        else
                loG "--- ${1} LVM DOES NOT EXIST!!!"
                loG "LVM ${1} does not exist. Cant continue backup!" err
                return
        fi
        return
}
##### RSYNC main function
##
## 1)Test if directories exist and define if its a list file or a an LVM link
## 2)Performs all raw actions
##
##
ArsynC() {
        dt=$(date '+%d/%m/%Y %T')
        # check if directories exist
        if [ -d "$2" ]; then echo "rsync destination backup dir $2"; else echo "rsync destination backup dir $2 NOT FOUND!" && exit; fi
        if [ -d "$3" ]; then echo "mount dir $3";else echo "mount dir $3 NOT FOUND" && exit; fi
        # remember the log sizes
        readL
        # tell what device to display size when quit
        BB="$2"
        # define if its a LVM Link or a List file
        if [ -h "$1" ]; then echo "Single run. Just one LVM to rsync." && logE="RSYNC -- Single run $1 " && DrsY "$1" "$2" "$3" && exiT; fi
        if [ -f "$1" ]; then echo "Multi LVM list to rsync: $1 Number of files: $(egrep -cv '#|^$' "$1")"; fi
        loG "--- LIST file $1 exists, going on. $(egrep -cv '#|^$' "$1") lines to execute"
        logE="RSYNC -- Multi run $1 | $(egrep -cv '#|^$' "$1") runs"
        while read -r arg_1; do
                # lets avoid all commented and empty lines please
                [[ "$arg_1" =~ ^#.*$ ]] && continue
                [[ "$arg_1" = "" ]] && continue
                DrsY "${arg_1}" "$2" "$3"
        done < "${1}"
        exiT
}
##### Convert function
##
## 1)Test if directories exist and define if its a list file or a an LVM link
## 2)Performs all raw actions
##
##
AconverT() {
        dt=$(date '+%d/%m/%Y %T')
        if [ "$3" = "single" ]; then
                vmname=$(basename "${1}")
                Qname=${vmname:0:${#vmname}-4}
                loG "--- Convert single file started. from $1 to $2/${Qname}.qcow2 --- "
                loG "--- QEMU-CONV start ${Qname} --- output:"
                qemu-img convert -p -c -O qcow2 "${1}" "${2}"/"${Qname}".qcow2 >>$LOGFILE
                loG "--- QEMU-CONV end ${Qname} --- "
        else
                loG "--- Convert started. from $1/ to $2/ --- "
                if [ -d "$1" ]; then loG "-- Convert: Raw files dir $1";else loG "-- Convert: raw file dir $1 NOT FOUND" err && return; fi
                fltbc=$(find "$1"/*.raw | wc -l)
                if [ "$fltbc" -eq 0 ]; then loG "-- Convert: No raw files found in $1" && return; else loG "--- files to be converted: ${fltbc} --- "; fi
                if [ -d "$2" ]; then loG "-- Convert: Destination dir $2";else loG "-- Convert: Destination dir $2 NOT FOUND err" && return; fi
                # simple create a list of files to convert
                ls "$1"/*.raw > "$1"/toconvert
                while read -r arg_1; do
                        dt=$(date '+%d/%m/%Y %T')
                        vmname=$(basename "${arg_1}")
                        Qname=${vmname:0:${#vmname}-4}
                        loG "--- QEMU-CONV start ${Qname} --- output:"
                        qemu-img convert -p -c -O qcow2 "${arg_1}" "${2}"/"${Qname}".qcow2 >>$LOGFILE
                        if [ "$?" -eq "0" ]; then logT=$((logT+1)); fi
                        ls -lah "${2}"/"${Qname}".qcow2 | loG
                        loG "--- QEMU-CONV end ${Qname} ---"
                done < "${1}"/toconvert
                # remove that list
                rm -f "${1}"/toconvert
        fi
        return
}
##### Recycle function
##
## 1 Current rotation directory
## 2 Directory to transfer
## 3 -date (transfer with date)
##
recY() {
        # check if directories exist
        if [ -d "$1"/${ROTT} ]; then echo "rotation dir $1/$ROTT"; else echo "ABORT! current rotation dir $1 NOT FOUND!" && exit; fi
        staT=rawB
        BT="$1"
        freeBT=$(numfmt --to iec --format "%8.4f" "$(df "$1" | awk '{print $4"000"}'| tail -1)")
        if [ "$2" == "-force" ]; then loG "FORCE CLEAR $1/$ROTT" && rm -rf "${1:?}/${ROTT}" && mkdir "${1}"/${ROTT} && logE="RECYCLE -- FORCE CLEAR $1/$ROTT" && logT=1 && logN=1 && exiT; fi
        if [ -d "$2" ]; then echo "destination dir $2";else echo "ABORT! destination dir $2 NOT FOUND!" && exit; fi
        expecQ=$(find "${1}"/${ROTT}/*.qcow2 2>>/dev/null | wc -l)
        expecR=$(find "${1}"/${ROTT}/*.raw 2>>/dev/null | wc -l)
        if [ "$3" == "-qcow2" ]; then
                loG "Transfer only $1/$ROTT/*.qcow2 . We will delete $expecR raw files."              
        fi
        if [ "$3" == "-raw" ]; then loG "Transfer only $1/$ROTT/*.raw will delete $expecQ qcow2 files" && expecQ=0; fi
        logN=$((expecQ+expecR))
        if [ "$logN" -eq "0" ]; then loG "ABORT! No files found. Nothing to do..." && exit; fi
        loG "Total qcow2 files to transfer in $1/$ROTT: $expecQ || Total raw to transfer: $expecR || Total: $logN"
        # remember the log sizes and quick log settings
        readL
        logE="RECYCLE -- move $1 to $2"
        logTT=0
        if [ $expecQ -ge "1" ]; then
                tranS listMultiple "$2" "$1"/${ROTT} -qcow2 none
                logTT=$logT
        fi
        if [ $expecR -ge "1" ]; then tranS listMultiple "$2" "$1"/${ROTT} raw none && logT=$((logT+logTT)); fi
        if [ $logT -eq $logN ]; then
                loG "Cleaning directory $1/$ROTT"
                rm -rf "${1:?}/${ROTT}" && mkdir "${1}"/${ROTT}
                loG "Created new directory $1/$ROTT"
        else
                loG "+++ ERROR Could not verify all files where transfered."
                loG "Expected files to transfer: $logN     Files actually transferred: $logT"
                loG "Did not touch $1/$ROTT"
        fi
        exiT
}
##### Benchmark function
##
## 1) Test if directories and LVM exists
## 2) Creates a snapshot
## 3) Fires the tests
##
bencH() {
        # The bSIZE variable tells how many bits should we transfer during our tests. Here are some examples:
        #bSIZE=1073741824                                                       # test data size. here 1GiB
        bSIZE=536870912                                                         # test data size. here 512MiB
        #bSIZE=134217728                                                        # test data size. here 128MiB
        #bSIZE=$(lvdisplay -v --units b "$1" | grep Size | awk '{print $3}')    # test data size. here the size of our snapshot.
        benT=3                                                                  # number of runs (must be within 2 - 9)
        if [ -d "$2/$ROTT" ]; then echo "Rotation dir $2/$ROTT"; else echo "Rotation dir $2/$ROTT NOT FOUND! aborting benchmark..." && exit; fi
        if [ -h "$1" ]; then echo "LVM to benchmark: $1"; else echo "LVM $1 NOT FOUND! aborting benchmark..." && exit; fi
        vmname=$(basename "$1")
        if [ -e "$2/$ROTT/$vmname.ben" ]; then echo "ERROR! Benchmark file: $2/$ROTT/$vmname.ben - ALREADY EXISTS! aborting benchmark..." && exit; else  echo "Benchmark test file: $2/$ROTT/$vmname.ben"; fi
        echo -e "\nBenchmarking mode. We will do many runs with different block size (bs=). $benT runs with the same size to get an proper average. Note that for this check, the sync cache will be emptied during each run"
        echo "You can edit the bencH() function to adjust the test file sizes, number of runs and the block sizes. (512 1024 2048 tend to perform badly in my experience.)"
        echo "original benchmark code: by tdg5 @dannyguinther https://github.com/tdg5/blog/blob/master/_includes/scripts/dd_ibs_test.sh"
        echo "Creating snapshot "${vmname}"-snapbench"
        lvcreate --size ${SZ} --snapshot --name "${vmname}"-snapbench "${1}"
        Bit=$(lvdisplay -v --units b "$1" | grep Size | awk '{print $3}')
        echo "LVM size is: $(numfmt --to iec --format "%8.4f" "$Bit") and we will use $(numfmt --to iec --format "%8.4f" "$bSIZE") data for our tests."
        if  [ -e "${1}-snapbench" ]; then
        echo -e "\nCurrent configured bs=$ddBS (for running raw operations with kplvms ${CYA}°°°${NC}\n"
        echo "Starting... Press CTRL+C anytime to quit..."
        echo "dd command line: dd if=${1}-snapbench of=${2}/${ROTT}/${vmname}.ben bs=\$BLOCK_SIZE count=\$COUNT oflag=direct"
        ## original code: by tdg5 @dannyguinther https://github.com/tdg5/blog/blob/master/_includes/scripts/dd_ibs_test.sh
        PRINTF_FORMAT="%9s : %s"
        # Block sizes of 512b 1K 2K 4K 8K 16K 32K 64K 128K 256K 512K 1M 2M 4M 8M 16M 32M 64M
        # for BLOCK_SIZE in 4096 2048 8192 16384 1024 512 32768 65536 131072 262144 524288 1048576 2097152 4194304 8388608 16777216 33554432 67108864; do
        for BLOCK_SIZE in 4096 8192 16384 32768 65536 131072 262144 524288 33554432; do
#        for BLOCK_SIZE in 16384 32768 65536 131072 262144 524288 33554432 67108864; do
                trap 'sleep 1 && rm -f ${2}/${ROTT}/${vmname}.ben && sleep 1 && lvremove --force "${1}"-snapbench && echo "CTRL+C Aborted..." && exit' 2
                benN=1
                COUNT=$(($bSIZE / $BLOCK_SIZE))
                        printf "$PRINTF_FORMAT" 'block size' 'transfer rate'
                        while [ ! "$benN" -gt "$benT" ]; do
                        # Clear kernel cache to ensure more accurate test
                        [ $EUID -eq 0 ] && [ -e /proc/sys/vm/drop_caches ] && echo 3 > /proc/sys/vm/drop_caches
                        sync
                        # Read benchmark file out to rotation directory with specified block size
                        DD_RESULT=$(dd if=${1}-snapbench of=${2}/${ROTT}/${vmname}.ben bs=$BLOCK_SIZE count=$COUNT oflag=direct 2>&1 1>/dev/null)
                        # Extract transfer rate
                        TRANSFER_RATE=$(echo $DD_RESULT | \grep --only-matching -E '[0-9]+ ([MGk]?B|bytes)/s(ec)?')
                        export "T$benN"=$(echo $DD_RESULT | \grep --only-matching -E '[0-9]+ ([MGk]?B|bytes)/s(ec)?' | awk '{print $1}')
                        printf "$PRINTF_FORMAT" "$BLOCK_SIZE" "$TRANSFER_RATE"
                        benN=$((benN+1))
                done
                TT=$(echo $DD_RESULT | \grep --only-matching -E '[0-9]+ ([MGk]?B|bytes)/s(ec)?' | awk '{print $2}')
                echo -e "\ndd bs=$BLOCK_SIZE average in $benT ${CYA}runs${NC}: ${LG}$(((T1+T2+T3+T4+T5+T6+T7+T8+T9)/$benT)) $TT${NC}"
        done
                echo "Removing snapshot ---"
                lvremove --force "${1}"-snapbench
                echo "Removing benchmark test file: ${2}/${ROTT}/${vmname}.ben"
                rm -f ${2}/${ROTT}/${vmname}.ben
                echo -e "Finished benchmark. Edit the configuration file and change the ddBS variable with the value that suits you best...\nkplvms ${CYA}°°°${NC} keeplvmsafe v${verS} by gcblauth@gmail.com\nThis is the end. For now ;)"
        else
                echo "--- SNAPSHOT NOT FOUND!!! aborting benchmark..."
                echo "Removing snapshot ---"
                lvremove --force "${1}"-snapbench
                echo "STOP. Cant continue benchmark!"
        fi
        exit
}
##### Help function
##
##   a function that needs no introduction
##
##                   :)
## consider donating (: paypal: gcblauth@gmail.com
##                   :)
##                   (:
helP() {
        echo -e "\nkplvms ${CYA}°°°${NC} keeplvmsafe v${verS} by gcblauth@gmail.com\nScript to batch backup LVMs that are in use to raw or to rsync their contents.\nThis script will snapshot your LVMs and dd them to raw or mount them to rsync their contents.\n"
        echo -e "Usage: $0 [raw rsync recycle benchmark] [LVMDEV (with /dev) or LISTFILE (with lvms listed line by line)] [final backup dir] [rotation dir] -qcow2"
        echo -e "Add -qcow2 switch to convert raw files before sending to final backup directory.\n"
        echo -e "ex. $0 raw /dev/VG2/os-r2d2 /mnt/backup /mnt/faststorage         raw backup an LVM to a raw file and transfer it"
        echo -e "ex. $0 raw /listfile /mnt/backup /mnt/faststorage                raw backup a list of LVMs to raw files and transfer them"
        echo -e "ex. $0 rsync /dev/VG1/array-marina /backup /mnt/point2           mount LVM and rsync it to /mnt/backup/lvmnam "
        echo -e "ex. $0 raw /listfile /mnt/backup /mnt/faststorage -qcow2         raw backup a list of LVMs to raw files, convert and transfer them"
        echo -e "ex. $0 recycle /mnt/faststorage /mnt/slowstorage                 recycle rotation dir now:$ROTT - copy it's contents to another location\n"
        echo -e "ex. $0 benchmark /dev/VG2/os-r2d2 /mnt/faststorage               do a series of raw dd if=LVM of=ROTATION DIR with different BS choose the best one\n"
        exit
}
##### MAIN ######################################################################################
if [ "$1" == "--help" ]; then helP; fi
echo -e "\nkplvms ${CYA}°°°${NC} keeplvmsafe v${verS} by gcblauth@gmail.com\n"
if [ "$1" == "" ]; then echo "Missing arguments. '$0 --help' for help" && exit; fi
if [ "$1" == "raw" ]; then defS && AraW "$2" "$3" "$4" "$5"; fi
if [ "$1" == "rsync" ]; then defS && ArsynC "$2" "$3" "$4"; fi
if [ "$1" == "recycle" ]; then defS && readL && recY "$2" "$3" "$4"; fi
if [ "$1" == "benchmark" ]; then defS && bencH "$2" "$3"; fi
echo -e "Invalid option. $1 is not recognized. Here's the help and the disclaimer one more time ${RED}(:${NC}\n"
helP