#!/sbin/sh

# Credits to @CosmicDan & @Oki XDA users

dbg() {
    # EXECUTES COMMAND AND REDIRECT OUTPUT TO LOG FILE
    echo -e -n "\nPARTY:" >> $LOGFILE
    echo -e -n "`pwd`" >> $LOGFILE
    echo -e " # $*" >> $LOGFILE
    echo "" >> $LOGFILE
    $* 1>> $LOGFILE 2>&1
}
log() {
    # OUTPUT ARGS TO LOG FILE
    echo -e "LOG: $*" >> $LOGFILE
    echo "" >> $LOGFILE
}

ui_print() {
	if [ "$OUT_FD" ]; then
		if [ "$1" ]; then
			echo "ui_print $1" > "$OUT_FD"
		else
			echo "ui_print  " > "$OUT_FD"
		fi
	else
		echo "$1"
	fi
}

pauseTwrp() {
	for pid in `pidof recovery`; do 
		kill -SIGSTOP $pid
	done;
}

resumeTwrp() {
	for pid in `pidof recovery`; do 
		kill -SIGCONT $pid
	done;
}

unmountAllAndRefreshPartitions() {
	stop sbinqseecomd
	sleep 1
	kill `pidof qseecomd`
	mount | grep /dev/block/mmcblk0p | while read -r line ; do
		thispart=`echo "$line" | awk '{ print $3 }'`
		umount -f $thispart
		sleep 0.5
	done
	mount | grep /dev/block/bootdevice/ | while read -r line ; do
		thispart=`echo "$line" | awk '{ print $3 }'`
		umount -f $thispart
		sleep 0.5
	done
	sleep 2
	blockdev --rereadpt /dev/block/mmcblk0
}

doSelinuxCheck() {
	result="unknown"
	cmdline=`cat /proc/cmdline`
	if echo $cmdline | grep -Fqe "androidboot.selinux=permissive"; then
		result="permissive"
	fi
	if echo $cmdline | grep -Fqe "androidboot.selinux=enforcing"; then
		result="enforcing"
	fi
	echo -n "$result"
	echo "result=$result" > /tmp/result.prop
}

dumpAndSplitBoot() {
	dd if=/dev/block/bootdevice/by-name/boot of=/tmp/boot.img
	bootimg xvf /tmp/boot.img /tmp/boot_split
	rm /tmp/boot.img
}

backupTwrp() {
	if isHotBoot; then
		# Don't do anything if we're on a hotboot
		ui_print "[!] Skipping TWRP survival (unsupported in hotboot)"
		return
	fi
	ui_print "[#] Backing up current RAMDisk from boot"
	ui_print "    (automatic TWRP survival)..."
	dumpAndSplitBoot
	mv /tmp/boot_split/boot.img-ramdisk /tmp/ramdisk-twrp-backup.img
	rm -rf /tmp/boot_split
	if [ ! -f "/tmp/ramdisk-twrp-backup.img" ]; then
		ui_print "    [!] Failed. Check Recovery log for details."
	fi
}

restoreTwrp() {
	if isHotBoot; then
		# Don't do anything if we're on a hotboot
		return
	fi
	if [ -f "/tmp/ramdisk-twrp-backup.img" ]; then
		ui_print "[#] Reinstalling TWRP to boot"
		ui_print "    (automatic TWRP survival)..."
		dumpAndSplitBoot
		if [ -f "/tmp/boot_split/boot.img-ramdisk" ]; then
			rm "/tmp/boot_split/boot.img-ramdisk"
			mv "/tmp/ramdisk-twrp-backup.img" "/tmp/boot_split/boot.img-ramdisk"
			bootimg cvf "/tmp/boot-new.img" "/tmp/boot_split"
			if [ -f "/tmp/boot-new.img" ]; then
				dd if=/tmp/boot-new.img of=/dev/block/bootdevice/by-name/boot
				rm /tmp/boot-new.img
				touch /tmp/twrp_survival_success
				return
			fi
		fi
		ui_print "    [!] Failed. Check Recovery log for details."
	else
		ui_print "[!] Unable to perform TWRP survival: backup missing!"
	fi
}

isHotBoot() {
	if cat /proc/cmdline | grep -Fqe " gpt "; then
		# " gpt " in kernel cmdline = real boot
		return 1
	else
		# no " gpt " = fastboot hotboot
		return 0
	fi
}

set_progress() {
	echo "set_progress $1" > "$OUT_FD"
}

calc(){
  awk "BEGIN { print "$*" }"
}
getpart(){
  # given the partition label, returns the partition
  readlink `find /dev/block/platform/ -name $1`
}
getdisk(){
  # given the partition label, returns the disk
  # old and buggy >>>>>  echo "`readlink /dev/block/bootdevice/by-name/$1 | sed -e's/[0-9]//g'`"
  getpart $1 | rev | sed -e's:[0-9]*::' -e's:p::I' | rev
}
getnode(){
  # given the disk node and partition number, returns the fs node for the partition
  echo -n $1 | rev | sed 's:[0-9]:p&:' | rev ; echo $2
}
getalign(){
  # given the partition label, returns the sector align
  $GDSK --print $(getdisk $1) | grep 'aligned' | tr -dc '0-9'
}
getsecsize(){
  # given the partition label, returns the sector size in bytes
  $GDSK --print $(getdisk $1) | grep 'sector size' | tr -s ' ' | cut -d' ' -f4
}
getsizemb(){
  echo $(( ( 1 + $(getend $1) - $(getini $1) ) * $(getsecsize $1) / 1024 / 1024 ))
}
getslots(){
  # given the partition label, returns the total number of slots in partition table
  $GDSK --print $(getdisk $1) | grep 'holds up to' | tr -s ' ' | cut -d' ' -f6
}
getlast(){
  # given the partition label, returns the last partition number
  $GDSK --print $(getdisk $1) | tail -1 |tr -s ' ' |cut -d' ' -f2
}
getnum(){
  # given the partition label, returns the partition number
  $GDSK --print $(getdisk $1) | grep $1 | tr -s ' ' | cut -d' ' -f2
}
getini(){
  # given the partition label, returns its initial sector
  $GDSK --print $(getdisk $1) | grep $1 | tr -s ' ' | cut -d' ' -f3
}
getend(){
  # given the partition label, returns its last sector
  $GDSK --print $(getdisk $1) | grep $1 | tr -s ' ' | cut -d' ' -f4
}
distance(){
  # returns the distance between two numbers
  echo $(( $1 - $2 )) | tr -d -
}
consecutive(){
  # SYNTAX: consecutive $partition_label1 $partition_label2
  # Returns true (0) if the partition labels are in the same disk and are consecutive
  if  [ $(getdisk $1) != $(getdisk $2) ] ; then
    return 1
  fi
  if [ $( distance $(getini $1) $(getend $2) ) -le $(getalign $1) ]; then
    return 0
  fi
  if [ $( distance $(getini $2) $(getend $1) ) -le $(getalign $1) ]; then
    return 0
  fi
  return 1
}

unmount(){
  # SYNTAX: unmount $partition_label
  if cat /proc/mounts | grep $(getpart $1) > /dev/null ; then
    # if partition is mounted
    log " - unmounting $1 ($(getpart $1))"
    umount $(getpart $1)
    return 0
  else
    log " - $1 ($(getpart $1)) was already unmounted"
    return 1
  fi
}

## ENTRYPOINTS FOR ZENFONE MANAGER
if [ "$1" == "isHotBoot" ]; then
	isHotBoot
	exit $?
elif [ "$1" == "doSelinuxCheck" ]; then
	doSelinuxCheck
	exit 0
elif [ "$1" == "doEncryptionCheck" ]; then
	doEncryptionCheck
	exit 0
elif [ "$1" == "doEncryptionPatch" ]; then
	doEncryptionPatch
	exit 0
fi
