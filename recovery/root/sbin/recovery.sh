#!/sbin/sh

### Recovery service bootstrap for better Treble support
# Purpose:
#  - Prevent recovery from being restarted when it's killed (equivalent to a one-shot service)
#  - symlink to the correct fstab depending on Treble partition state
#

source /zenfone_manager/constants.sh
source /zenfone_manager/tools.sh

chmod -R 777 /zenfone_manager/*

# check for dualboot mode (second userdata partition)
if [ -b "$userdata_b_blockdev" ]; then
	mv /etc/recovery.fstab /etc/recovery.fstab.singleboot
	mv /etc/recovery.fstab.dualboot /etc/recovery.fstab
fi

# check mount situation and use appropriate fstab

# insert binary bootstraps
if [ -f /sbin/update_engine_sideload -a -f /sbin/update_engine_sideload.sh ]; then
	mv /sbin/update_engine_sideload /sbin/update_engine_sideload_real
	mv /sbin/update_engine_sideload.sh /sbin/update_engine_sideload
fi;

# replace system symlink with directory (can't do this in build shell for whatever reason)
if [ -L /system ]; then
	rm /system
	mkdir /system
fi

# Needed for boot control HAL to update GPT partition info
ln -s /dev/block/mmcblk0 /dev/mmcblk0

# start recovery
/sbin/recovery &

# idle around
while kill -0 `pidof recovery`; do sleep 1; done

# stop self
stop recovery
