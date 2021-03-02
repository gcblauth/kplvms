# kplvms °°°

Keep LVM safe °°°

A fully customizabile (and improvable) bash script to automate live LVM backups.

The script will make a snapshot of an lvm (or a list of lvms) and either fully copy it or mount it as a filesystem and sync its contents.

 - Using local fast disks/mounts can make 10GiB VM LVM backup as quick as 10 seconds. 1 minute for a 120GiB VM OS /refer to my numbers to check my test enviroment
 - Having the latest copy on the rotation directory makes restore quick and effective in a few seconds
 - If a list file is presented for an RAW operation, all snapshots will be done to the rotation directory before transferring to the backup directory
 - Using rsync on large arrays will transfer all file properties and ACLs. Only syncing the changes (the default) or it can be changed to suit any case
 - A list can be used for an rsyncyng as many rsync operations as needed
 - The script is divided in functions so the backup directory can only be mounted/unlocked when the copy takes place and locked after.
 - There's a oneline logging option of all operations for quick alert/mail for when automated
 - A simple sendmail function to share the the run results and some basic system info

# Main Features

+ RAW DD from a lvm snapshot (or lvm list file) to a rotation directory and then move job to backup directory
        + Optional convert raw files to compressed qcow2 before send. (Takes 1 hour on a 120GiB raw to a 22GiB .qcow2)
+ RSYNC from a lvm snapshot (or a list file). mounts the snapshot with a preconfigured offset and rsync the contents with the backup directory
+ RECYCLE recycle the rotation directory (erase it or transfer it to archive location)
        + Optional transfer only qcow2 files
+ BENCHMARK test the optimal speed for your bytesize snapshot raw copy to your rotation directory (tests mounting a snapshot and DDing it to your rotation dir)


# Detailed raw single file actions

Concept: The steps for a raw copy of a running LVM:
```
My LVM: LVM1/os-saturn 10GB
My rotation mount: /mnt/rotation
My backup mount: /mnt/backup

imroot@galaxyone:/bin# date
Mon 01 Mar 2021 11:21:25 PM CET
imroot@galaxyone:/bin# kplvm.sh raw /dev/LVM1/os-saturn /mnt/backup /mnt/rotation -qcow2
  -actions
  1)test if /dev/LVM1/os-saturn is an LVM and what size it has.
  2)test if the rotation dir exists and what's the current free space
  3)test if the backup file /mnt/rotation/current/os-saturn.raw already exists
  4)create an snapshot of the lvm and and start a dd
  5)stop the snapshot 
  6)convert the os-saturn.raw to os-saturn.qcow2 [-qcow2 option passed]
  7)mount/unlock the backup dir and test for the free space
  8)create a date directory (01_03_2021) and transfer (rsync even if its local) the .qcow2 file [-qcow2 option passed]
  9)umount/lock backup directory
  10)report and exit
```

# Detailed raw list actions

Concept: The steps for a raw copy of a list of running LVMs:
```
My list of LVMs: /root/backup/lvmlist
list details: (3 LVMs separated by lines)
        /root/backup/lvmlist contents:
        /dev/LVM1/os-saturn
        /dev/LVM1/os-pluto
        /dev/LVM1/os-jupiter

My rotation mount: /mnt/rotation
My backup mount: /mnt/backup

imroot@galaxyone:/bin# date
Mon 01 Mar 2021 11:23:32 PM CET
imroot@galaxyone:/bin# kplvm.sh raw /root/backup/lvmlist /mnt/backup /mnt/rotation -qcow2
  -actions
  1)test if /dev/LVM1/os-saturn is an LVM and what size it has.
  2)test if the rotation dir exists and what's the current free space
  3)test if the backup file /mnt/rotation/current/os-saturn.raw already exists
  4)create an snapshot of the lvm and and start a dd
  5)stop the snapshot 
  6)test if /dev/LVM1/os-pluto is an LVM and what size it has.
  7)test if the rotation dir exists and what's the current free space
  8)test if the backup file /mnt/rotation/current/os-pluto.raw already exists
  9)create an snapshot of the lvm and and start a dd
  10)stop the snapshot 
  11)test if /dev/LVM1/os-jupiter is an LVM and what size it has.
  12)test if the rotation dir exists and what's the current free space
  13)test if the backup file /mnt/rotation/current/os-jupiter.raw already exists
  14)create an snapshot of the lvm and and start a dd
  15)stop the snapshot 
  16)convert the os-saturn.raw to os-saturn.qcow2 [-qcow2 option passed]
  17)convert the os-pluto.raw to os-pluto.qcow2 [-qcow2 option passed]
  18)convert the os-jupiter.raw to os-jupiter.qcow2 [-qcow2 option passed]
  19)mount/unlock the backup dir and test for the free space
  20)create a date directory (01_03_2021) and transfer (rsync even if its local) all the .qcow2 files [-qcow2 option passed]
  21)umount/lock backup directory
  22)report and exit
```

# Why ?

This script was born out of need. I was performing most of its operations by hand or with individual scripts copied and edited among servers.
I've been managing some servers for many years now. They are in different countries and with the most random hardware / configs / age. 
The only thing they share along is me and how they are setup. They all have Debian with QEMU KVM with virtio LVM disks. Some run as little as 4 VMs and others as many as 50 VMs.
I needed a way of centralizing (in an inexpensive and controlled way) how the backups were made. Some system already had their own live backup sollutions (paid or not - veeam, norton backup. ecc) but I was never too confident about them  and had more than a couple of situations where my backups saved the day and the pockets of my costumers.
Finally one day I decided I should write a complete solution that fits my needs and this has been helping me flawlessly ever since. 

Maybe this can help you too and we can improve it together to help even more people.

# Usage

kplvms.sh [raw rsync recycle benchmark] [LVMDEV (with /dev) or LISTFILE (with lvms listed line by line)] [final backup dir] [rotation dir] [-qcow2]
```
-qcow2 switch will convert raw files before sending to final backup directory
raw /dev/VG1/os-saturn /mnt/backup /mnt/rotation          raw backup an LVM to a raw file and transfer it
raw /root/listfile /mnt/backup /mnt/rotation              raw backup a list of LVMs to raw files and transfer them
rsync /dev/VG1/hd-saturn /backup /mnt/vmtemp              mount LVM and rsync it to /mnt/backup/lvmnam
raw /root/listfile /mnt/backup /mnt/rotation -qcow2       raw backup a list of LVMs to raw files, convert and transfer them
recycle /mnt/rotation /mnt/archive                        recycle rotation dir /mnt/rotation/current - copy it's contents to another directory
benchmark /dev/VG2/os-r2d2 /mnt/faststorage               do a series of raw dd if=LVM of=ROTATION DIR with different BS choose the best one
```

# My enviroment and my numbers

Server HPDL380 Gen10 Xeon 4114 128RAM

23 VMs
    18 Linux/BSD/others
     5 Microsoft

2 LVMs VGs
    1 NVME (for the OSs) /dev/FAST
    1 Raid10 (for the storages) /dev/ARRAY

1 rotation disk
    1 NVME 2TB /mnt/rotation
    
1 Backup mounted via iSCSI (dedicated ptp 10GBe) locked with luks controlled by the hypervisor (the mount function unlocks the disk with a file)
    1 32TB Volume (raid 10) /mnt/backup

kplvms /root/list /mnt/backup /mnt/rotation -qcow2

12:42:11 -- 22:56:15 -- RAW+QCOW2 Multi run /root/backups/nvmes/23 -- Activities: 23/23 OK

Total RAW size:

Total raw run time
(from snapshot to end dd in rotation dir: minutes

Total qemu2 compress time
(

Total QEMU Conv size:

Total transfer time
(from rotation dir to backup dir)

(i'll finish this later... im tired...)

# Todos:
(I have a dream)

+ Improve bash code and check for dummy coding (I use this myself so I never destroyed anything. Help me keep it that way :)
+ Improve commments, variable names and syntaxes all along (Expect to find different systaxes for doing same things... should standarize to a more efficient way)
+ Improve logging options
+ Create optional backup testing/hashing function
+ Incorporate Guest VM database/cache write to disk before snapshot
+ Integrate with rsnaphot or rsyncnapshot (great backup scripts https://github.com/rsnapshot/rsnapshot and https://github.com/Stonyx/RSyncSnapshot)
+ Integrate with pixz (such an great idea for multithreaded highly compressed tape archiving www.github.com/vasi/pixz )
+ Create an anonynous stats for usage and benchmarks
+ Separate config files
+ Create small db with operations and stats
+ Improve email/alert system
+ Set backup function for the hypervisor itself (backup mdadm info, luks headers, config files, disk/partition mappings, ecc) - today I backup the whole lvm disk
+ Measure impact with different configurations

# Disclaimer

If this helps you, consider sharing your experience and wno knows ? Buy me a beer ? ;)

This script is free software. You can redistribute it and/or modify it under the terms of the GNU
General Public License Version 3 (or at your option any later version) as published by The Free
Software Foundation.

This script is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

If you did not received a copy of the GNU General Public License along with this script see
http://www.gnu.org/copyleft/gpl.html or write to The Free Software Foundation, 675 Mass Ave,
Cambridge, MA 02139, USA.
