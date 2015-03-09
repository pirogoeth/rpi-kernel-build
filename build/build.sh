#!/bin/bash

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
#   UPDATE_EXISTING -> if USE_EXISTING_SRC=YES, do we also run a pull to update the sources? [default: NO]
#   USE_EXISTING_SRC -> make the build system use existing sources, if present [default: NO]
#   USE_HARDFLOAT -> build the kernel with armhf support instead of soft-float. [default: YES]

# Functions for parsing source,dest pairs out of an array.
function arr_get_source() {
  declare -a array=("${!1}")
  idx=$2
  echo "${array[$idx]}" | awk '{ split($0, spl, ","); print spl[1] }'
}

function arr_get_dest() {
  declare -a array=("${!1}")
  idx=$2
  echo "${array[$idx]}" | awk '{ split($0, spl, ","); print spl[2] }'
}

# Repositories for aufs, firmware, and kernel.
AUFS_GIT="git://aufs.git.sourceforge.net/gitroot/aufs/aufs3-standalone.git"
AUFS_BRANCH="3.18.1+"

RPI_FW_GIT="https://github.com/raspberrypi/firmware.git"
RPI_FW_BRANCH="master"

RPI_KERN_GIT="https://github.com/raspberrypi/linux.git"
RPI_KERN_BRANCH="master"

# Directories.
AUFS_SOURCE="/data/aufs"
KERN_SOURCE="/data/rpi-linux"
FW_SOURCE="/data/rpi-firmware"

KERN_OUTPUT="/kern/linux"
MOD_OUTPUT="/kern/linux/modules"
FW_OUTPUT="/kern/firmware"

# Cross-compiler prefix
ARMHF_CC_PFX="/usr/bin/arm-linux-gnueabihf-"
ARMSF_CC_PFX="/usr/bin/arm-linux-gnueabi-"
CROSS_COMPILE=""

# Environment variables / defaults.
AUFS_ENABLE=${AUFS_ENABLE:-"YES"}
PARALLEL_OPT=${PARALLEL_OPT:-3}
UPDATE_EXISTING=${UPDATE_EXISTING:-"NO"}
USE_EXISTING_SRC=${USE_EXISTING_SRC:-"NO"}
USE_HARDFLOAT=${USE_HARDFLOAT:-"YES"}

# Files to patch into the kernel source from aufs source.
declare -a AUFS_PATCHES=( "aufs3-base.patch" "aufs3-kbuild.patch" "aufs3-loopback.patch" "aufs3-mmap.patch" \
               "aufs3-standalone.patch" "tmpfs-idr.patch" "vfs-ino.patch" )

declare -a AUFS_KERN_CPY=( "/fs,/" "/Documentation,/" "/include/uapi/linux/aufs_type.h,/include/uapi/linux/aufs_type.h" )

declare -a FILE_APPEND_PATCH=( "header-y += aufs_type.h,${KERN_SOURCE}/include/uapi/linux/Kbuild" )

# Set the cross-compiler prefix.
# Set the cross-compiler prefix.
if [[ "${USE_HARDFLOAT}" == "YES" ]] ; then
  echo ' [!] Compiling with HardFP.'
  export CROSS_COMPILE="${ARMHF_CC_PFX}"
elif [[ "${USE_HARDFLOAT}" != "YES" ]] ; then
  echo ' [!] Compiling with SoftFP.'
  export CROSS_COMPILE="${ARMSF_CC_PFX}"
fi

# Echo out build settings.
echo " [!] ------------------- Repository Settings ------------------- [!]"
echo " [+] AUFS_GIT         => ${AUFS_GIT}"
echo " [+] AUFS_BRANCH      => ${AUFS_BRANCH}"
echo " [+] RPI_FW_GIT       => ${RPI_FW_GIT}"
echo " [+] RPI_FW_BRANCH    => ${RPI_FW_BRANCH}"
echo " [+] RPI_KERN_GIT     => ${RPI_KERN_GIT}"
echo " [+] RPI_KERN_BRANCH  => ${RPI_KERN_BRANCH}"
echo " [!] ------------------- Source Directories -------------------- [!]"
echo " [+] AUFS_SOURCE      => ${AUFS_SOURCE}"
echo " [+] FW_SOURCE        => ${FW_SOURCE}"
echo " [+] KERN_SOURCE      => ${KERN_SOURCE}"
echo " [!] ---------------- Build / Install Variables ---------------- [!]"
echo " [+] KERN_SOURCE      => ${KERN_SOURCE}"
echo " [+] KERN_OUTPUT      => ${KERN_OUTPUT}"
echo " [+] MOD_OUTPUT       => ${MOD_OUTPUT}"
echo " [+] FW_OUTPUT        => ${FW_OUTPUT}"
echo " [+] CROSS_COMPILE    => ${CROSS_COMPILE}"
echo " [!] ------------------ Environment Variables ------------------ [!]"
echo " [+] AUFS_ENABLE      => ${AUFS_ENABLE}"
echo " [+] PARALLEL_OPT     => ${PARALLEL_OPT}"
echo " [+] UPDATE_EXISTING  => ${UPDATE_EXISTING}"
echo " [+] USE_EXISTING_SRC => ${USE_EXISTING_SRC}"
echo " [+] USE_HARDFLOAT    => ${USE_HARDFLOAT}"

# Determine what to do with source directories.
if [[ "${USE_EXISTING_SRC}" == "NO" ]] ; then
  echo " [!] Cloning source...grab some popcorn because this will take a bit..."
  ( [[ -d ${AUFS_SOURCE} ]] && \
    rm -rf ${AUFS_SOURCE} && \
    echo " [*] Cloning AUFS source from ${AUFS_GIT}..." && \
    git clone --branch ${AUFS_BRANCH} ${AUFS_GIT} ${AUFS_SOURCE} )
  ( [[ -d ${FW_SOURCE} ]] && \
    rm -rf ${FW_SOURCE} && \
    echo " [*] Cloning RPI Firmware from ${RPI_FW_GIT}..." && \
    git clone --branch ${RPI_FW_BRANCH} ${RPI_FW_GIT} ${FW_SOURCE} )
  ( [[ -d ${KERN_SOURCE} ]] && \
    rm -rf ${KERN_SOURCE} && \
    echo " [*] Cloning RPI Linux Kernel source from ${RPI_KERN_GIT}..." && \
    git clone --branch ${RPI_KERN_BRANCH} ${RPI_KERN_GIT} ${KERN_SOURCE} )
elif [[ "${USE_EXISTING_SRC}" != "NO" ]] && [[ "${UPDATE_EXISTING}" != "NO" ]] ; then
  ( [[ -d ${AUFS_SOURCE} ]] && \
    cd ${AUFS_SOURCE} && \
    echo " [*] Attempting to update AUFS sources..."
    git pull origin && \
    git checkout origin/${AUFS_BRANCH} )
  ( [[ -d ${FW_SOURCE} ]] && \
    cd ${FW_SOURCE} && \
    echo " [*] Attempting to update RPI firmware..."
    git pull origin && \
    git checkout origin/${RPI_FW_BRANCH} )
  ( [[ -d ${KERN_SOURCE} ]] && \
    cd ${KERN_SOURCE} && \
    echo " [*] Attempting to update RPI Linux Kernel sources..."
    git pull origin && \
    git checkout origin/${RPI_KERN_BRANCH} )
fi

# Copy AUFS files into place.
for (( i=0 ; $i < ${#AUFS_KERN_CPY[@]}; i++ )) ; do
  srcpath="${AUFS_SOURCE}$(arr_get_source AUFS_KERN_CPY[@] $i)"
  destpath="${KERN_SOURCE}$(arr_get_dest AUFS_KERN_CPY[@] $i)"
  echo " [*] Copying ${srcpath} to ${destpath}.."
  cp -rp ${srcpath} ${destpath}
done

# Perform simple append patches. (eg., for Kbuild header things)
for (( i=0 ; $i < ${#FILE_APPEND_PATCH[@]}; i++ )) ; do
  patchdata="`arr_get_source FILE_APPEND_PATCH[@] $i`"
  patchfile="`arr_get_dest FILE_APPEND_PATCH[@] $i`"
  echo " [*] Appending '${patchdata}' to ${patchfile}.."
  echo ${patchdata} >> ${patchfile}
done

# Perform AUFS patches in the kernel directory.
( cd ${KERN_SOURCE} && \
  for (( i=0; $i < ${#AUFS_PATCHES[@]}; i++ )) ; do \
    patchpath="${AUFS_SOURCE}/${AUFS_PATCHES[$i]}" && \
    echo " [*] Applying patch '${patchpath}' to kernel source tree." && \
    patch -p1 < ${patchpath}
  done
)

# Create output directories.
( [[ ! -d ${KERN_OUTPUT} ]] && mkdir ${KERN_OUTPUT} )
( [[ ! -d ${MOD_OUTPUT} ]] && mkdir ${MOD_OUTPUT} )
( [[ ! -d ${FW_OUTPUT} ]] && mkdir ${FW_OUTPUT} )

# Load the config, if present.
( [[ -d /config ]] && [[ -f /config/rpi-config ]] && \
  cd /data/rpi-linux && \
  cp /config/rpi-config .config ) || \
  echo " [-] No /config volume or no rpi-config in /config"

# Create a kernel from the bcmrpi defaults if no kernel config was provided.
# If a kernel config was provided, tell the build system to use the "old"
#  configuration and use bcmrpi defaults for all NEW symbols.
( [[ ! -f ${KERN_SOURCE}/.config ]] && \
  cd ${KERN_SOURCE} && \
  echo " [!] Building kern. conf. with defaults from PLATFORM=bcmrpi." && \
  make ARCH=arm PLATFORM=bcmrpi CROSS_COMPILE=${CROSS_COMPILE} bcmrpi_defconfig ) ||
( [[ -f ${KERN_SOURCE}/.config ]] && \
  cd ${KERN_SOURCE} && \
  echo " [!] Building rpi-config with NEW symbol defaults from PLATFORM=bcmrpi." && \
  make ARCH=arm PLATFORM=bcmrpi CROSS_COMPILE=${CROSS_COMPILE} olddefconfig )

# ALWAYS enable loadable kernel module support
( [[ -z `grep CONFIG_MODULES= ${KERN_SOURCE}/.config` ]] && \
  cd ${KERN_SOURCE} && \
  echo "CONFIG_MODULES=y" >> .config )

# Set aufs to load as a module (aufs3-standalone)
( [[ "${AUFS_ENABLE}" == "YES" ]] && \
  cd ${KERN_SOURCE} && \
  echo "CONFIG_AUFS_FS=m" >> .config )

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