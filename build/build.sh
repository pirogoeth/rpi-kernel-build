#!/bin/bash -x

# This is the actual build script that runs as the entrypoint for the
# container.  This will actually build the kernel and such,
#
# Build output will go to /kern.
# After this script completes, /kern will contain the config used to build the kernel,
# the actual kernel image, and the updated raspberry pi firmware.
# When build can be modified by environment variables, they will be listed below.
#
# Available env variables:
#   AUFS_ENABLE -> make the setup part patch the kernel source with aufs3.1-standalone and enable kern module. [default: YES]
#   PARALLEL_OPT -> set the value that make uses for -j (parallel execution) [default: 3]
#   USE_HARDFLOAT -> build the kernel with armhf support instead of soft-float. [default: YES]

KERN_SOURCE="/data/rpi-linux"
KERN_OUTPUT="/kern/linux"
MOD_OUTPUT="/kern/linux/modules"
FW_OUTPUT="/kern/firmware"

ARMHF_CC_PFX="/usr/bin/arm-linux-gnueabihf-"
ARMSF_CC_PFX="/usr/bin/arm-linux-gnueabi-"
CROSS_COMPILE=""

AUFS_ENABLE=${AUFS_ENABLE:-"YES"}
PARALLEL_OPT=${PARALLEL_OPT:-3}
USE_HARDFLOAT=${USE_HARDFLOAT:-"YES"}

# Set the cross-compiler prefix.
# Set the cross-compiler prefix.
if [[ "${USE_HARDFLOAT}" == "YES" ]] ; then
  export CROSS_COMPILE="${ARMHF_CC_PFX}"
elif [[ "${USE_HARDFLOAT}" != "YES" ]] ; then
  export CROSS_COMPILE="${ARMSF_CC_PFX}"
fi

# Create output directories.
( [[ ! -d ${KERN_OUTPUT} ]] && mkdir ${KERN_OUTPUT} )
( [[ ! -d ${MOD_OUTPUT} ]] && mkdir ${MOD_OUTPUT} )
( [[ ! -d ${FW_OUTPUT} ]] && mkdir ${FW_OUTPUT} )

# Create a kernel from the bcmrpi defaults if no kernel config was provided.
# If a kernel config was provided, tell the build system to use the "old"
#  configuration and use bcmrpi defaults for all NEW symbols.
( [[ ! -f ${KERN_SOURCE}/.config ]] && \
  cd ${KERN_SOURCE} && \
  make ARCH=arm PLATFORM=bcmrpi CROSS_COMPILE=${CROSS_COMPILE} bcmrpi_defconfig ) ||
( [[ -f ${KERN_SOURCE}/.config ]] && \
  cd ${KERN_SOURCE} && \
  make ARCH=arm PLATFORM=bcmrpi CROSS_COMPILE=${CROSS_COMPILE} olddefconfig )

# Set aufs to load as a module (aufs3-standalone)
( [[ "${AUFS_ENABLE}" == "YES" ]] && \
  cd ${KERN_SOURCE} && \
  echo "CONFIG_AUFS_FS=m" >> .config )

# ALWAYS enable loadable kernel module support
( [[ -z `grep CONFIG_MODULES= ${KERN_SOURCE}/.config` ]] && \
  cd ${KERN_SOURCE} && \
  echo "CONFIG_MODULES=y" >> .config )

# Cross-compile kernel.
( cd ${KERN_SOURCE} && \
  make ARCH=arm PLATFORM=bcmrpi CROSS_COMPILE=${CROSS_COMPILE} -k -j ${PARALLEL_OPT} )

# Copy the kernel output to $KERN_OUTPUT
( cd ${KERN_SOURCE} && \
  cp -v arch/arm/boot/Image ${KERN_OUTPUT}/kernel.img )

# Build kernel modules.
( cd ${KERN_SOURCE} && \
  make ARCH=arm PLATFORM=bcmrpi modules_install INSTALL_MOD_PATH=${MOD_OUTPUT} )

# Copy new firmware.
( cd /data/rpi-firmware && \
  cp /data/rpi-firmware/boot/*.dtb ${FW_OUTPUT} && \
  cp /data/rpi-firmware/boot/*.elf ${FW_OUTPUT} && \
  cp /data/rpi-firmware/boot/*.dat ${FW_OUTPUT} && \
  cp /data/rpi-firmware/boot/bootcode.bin ${FW_OUTPUT} )