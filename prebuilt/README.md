# Il kernel precompilato

`kernel` è l'`Image.gz-dtb` che `BoardConfig.mk` cerca in
`TARGET_PREBUILT_KERNEL`.

**Non è un binario opaco**: i sorgenti sono in
[android_kernel_doogee_s88pro](https://github.com/lopsandrea/android_kernel_doogee_s88pro),
e questo file si rigenera con la catena di LineageOS.

## Come è stato costruito

    clang r487747c (17.0.2) + ld.lld + llvm-ar dai prebuilts di LineageOS
    make ARCH=arm64 lineage_s88pro_defconfig
    make ARCH=arm64 Image.gz-dtb LLVM_IAS=0 KCFLAGS="-gdwarf-4 <i -Wno- del BoardConfig>"

    9.986.048 byte
    sha256 a75670c5cc5f8f42...

## Verificato

È byte per byte lo stesso kernel che gira sul telefono: estratto dalla
partizione `boot` con `tools/bootimg.py unpack` e confrontato con `cmp`.

Sul dispositivo: dieci cicli di spegnimento e riaccensione dello schermo senza
riavvii, zero panici, zero WARNING, e `/proc/driver/camera_info` identico riga
per riga a quello del kernel di fabbrica.
