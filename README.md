rpi-kernel-build
================

This Docker container was built with one idea in mind (similar to most other containers...)

Its entire purpose is to build and expose a Linux kernel, specifically for the Raspberry Pi.
The build system pulls the kernel source and raspi firmware from the raspi Github account.
AUFS source also gets pulled from Sourceforge and patched in to the kernel. 

You can pass some environment variables in to the container when you run it:

  - AUFS_ENABLE => Whether or not to build the AuFS module with the kernel.
    - Default: **YES**
  - PARALLEL_OPT => Specify how many jobs / recipes Make should execute at once.
    - Default: **3**
  - UPDATE_EXISTING => If USE_EXISTING_SRC=YES, also run a pull to update the sources.
    - Default: **NO**
  - USE_EXISTING_SRC => Make the build system use existing sources, if present.
    - Default: **NO**
  - USE_HARDFLOAT => Tells the build system whether or not to compile with gnueabihf or just use gnueabi.
    - Default: **YES**

This is still a work in progress, but it's making its way to a workable, usable state.  Some things
need to be migrated out of the build parts and into the actual build script that executes when the 
container is run.  

Super easy to run.  Just expose a volume for the kernel build and off you go:

    docker run -it -d -v /hostpath/kernel:/kern maiome/rpi-kernel-build