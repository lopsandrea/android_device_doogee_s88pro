# The prebuilt kernel

`kernel` is an `Image.gz-dtb` kept for anyone who wants to install without
rebuilding. `BoardConfig.mk` points `TARGET_PREBUILT_KERNEL` at it, but the
build only uses it with `TARGET_FORCE_PREBUILT_KERNEL`: by default the kernel
is compiled from source, as the charter requires.

**It is not an opaque binary**: the sources are in
[android_kernel_doogee_s88pro](https://github.com/lopsandrea/android_kernel_doogee_s88pro),
and this file is regenerated with the LineageOS toolchain.

## How it was built

    clang r487747c (17.0.2) + ld.lld + llvm-ar from the LineageOS prebuilts
    make ARCH=arm64 lineage_s88pro_defconfig
    make ARCH=arm64 Image.gz-dtb LLVM_IAS=0 KCFLAGS="-gdwarf-4 <the -Wno- flags from BoardConfig>"

    9,986,048 bytes
    sha256 a75670c5cc5f8f42...

Note: the in-tree build uses clang r450784d (14.0.6), the version LineageOS 20
ships — see `TARGET_KERNEL_CLANG_VERSION` in `BoardConfig.mk`. This binary
predates that switch, which is why the versions differ.

## Verified

It is byte for byte the same kernel that runs on the phone: extracted from the
`boot` partition with `tools/bootimg.py unpack` and compared with `cmp`.

On the device: ten screen off/on cycles without reboots, zero panics, zero
WARNINGs, and `/proc/driver/camera_info` identical line by line to the stock
kernel's.
