# Regole SELinux fra tipi di sistema

Qui c'e' solo `file_contexts`.

## Perche' non ci sono le regole `allow`

Ci avevo messo due regole, per due denial misurati sul telefono:

    allow system_app sysfs_leds:dir search;          # i LED di S88ProParts
    allow nfc system_data_file:file { ... };         # lo stato NFC

**Non compilano**: violano i `neverallow` di AOSP, e il build si ferma su
`checkpolicy`:

    neverallow check failed ... from system/sepolicy/private/coredomain.te:32
      (neverallow base_typeattr_636 sysfs_leds (file (... write ...)))
        allow (allow system_app sysfs_leds (file (... write ...)))

    neverallow check failed ... from system/sepolicy/public/domain.te:1123
      (neverallow base_typeattr_293 system_data_file (file (write create ...)))
        allow (allow nfc system_data_file (file (read write getattr open)))

Sono divieti voluti: un `coredomain` non deve toccare `sysfs_leds` da solo, e
nessuno deve scrivere su `system_data_file`, che e' il tipo generico.

## Come si chiudono davvero

- **NFC**: la via corretta e' etichettare `/data/nfc` come `nfc_data_file`, che
  e' proprio quello che fa il `file_contexts` qui accanto. I file gia' creati
  col tipo vecchio si ri-etichettano con `restorecon -R /data/nfc`.

- **LED**: `S88ProParts` non dovrebbe scrivere direttamente in
  `/sys/class/leds`, ma passare per l'HAL delle luci. In alternativa si dichiara
  un tipo proprio del device per quei file e si concede l'accesso a quello --
  ma va fatto nella sepolicy del vendor, non fra i tipi di sistema.

Finche' non si fa una delle due, i denial restano nel registro. Nessuno dei due
impedisce l'avvio.

## La mappa dei denial in enforcing (9 settembre)

Misurati sul telefono con SELinux Enforcing, dopo un avvio e un giro d'uso
vero (foto, video, torcia, LED, Bluetooth, NFC, radio FM, impostazioni):
194 righe, 41 combinazioni distinte. Divise per **chi puo' chiuderle**, che
non e' una distinzione accademica: tre quarti non dipendono da noi.

### Chiuse qui

| denial | come |
|---|---|
| `init -> socket_device : sock_file create` | `init.te`. Sono i socket `volte_imsa2`, `volte_ut`, `vendor.bip`, dichiarati nei `.rc` del vendor senza contesto esplicito |
| `system_server -> unlabeled : dir write` | `restorecon_recursive` in `s88pro-cache.rc`. E' `/cache/recovery`, cioe' la strada dell'aggiornamento. Le etichette AOSP le ha gia' (`private/file_contexts:794`, che mappa `/data/cache` perche' qui `/cache` e' un collegamento): mancava solo di applicarle a quel che c'era gia' |
| `system_app -> sysfs_leds : dir search` | `system_app.te`. I nodi LED non sono sysfs_leds ma tipi a se', gia' concessi dalla policy MediaTek: mancava solo attraversare la directory, e il neverallow di `coredomain.te:32` e' su `:file` |
| `system_app -> sysfs_batteryinfo : dir r_dir_perms` | `system_app.te`. Serve solo a sapere se il device ha la ricarica inversa; lo stato si legge altrove, vedi sotto |
| `system_app -> sysfs_rvs : file rw` | `file.te` e `genfs_contexts`. Il nodo della ricarica inversa aveva il tipo generico `sysfs`, che nessuno puo' scrivere -- nemmeno init, e AOSP spiega perche': *"Init should not access sysfs node that are not explicitly labeled"*. Etichettato, il problema sparisce |

### Vietate da un neverallow di AOSP

Non e' una limitazione nostra: AOSP dichiara esplicitamente che quei domini
non devono avere quell'accesso, e `secilc` rifiuta la regola. Attenzione pero'
a leggere *cosa* vieta: i divieti su sysfs sono quasi sempre sulla classe
`file` e non su `dir`, e quella distinzione e' bastata a recuperare i LED.

| denial | occorrenze | il divieto |
|---|---|---|
| `network_stack -> fs_bpf : file read` | 7 | `bpfloader.te:36`. AOSP vuole le mappe del tethering in `/sys/fs/bpf/tethering` (tipo `fs_bpf_tethering`, per cui la regola c'e' gia'); il bpfloader di questo kernel 4.14 le crea nella radice, dove il tipo e' `fs_bpf` generico. Sono `map_offload_tether_*`: senza, il tethering non ha l'offload, ma funziona lo stesso via software |
| `kernel -> capability dac_override` | 6 | il worker `mtk_wmtd_worker` del driver Wi-Fi MediaTek |

### Non esprimibili: il tipo lo definisce il vendor

Con `TARGET_USES_PREBUILT_VENDOR_SEPOLICY` la policy del vendor arriva gia'
compilata, e i suoi tipi non esistono nella policy di piattaforma: una
`allow` che li nomina non compila. Il dominio invece e' nostro, quindi non
si possono nemmeno mettere altrove.

| denial | occorrenze |
|---|---|
| `vold -> sysfs_mmcblk : file write` | 49 |
| `mediaswcodec -> proc_ged : file read` | 28 |
| `cameraserver -> vendor_default_prop : file read` | 6 |
| `mediacodec -> default_prop : file read` | 5 |
| `mediaserver`, `nfc` -> `debugfs_ion : dir search` | 6 |
| `system_server -> tkcore_systa_file : dir getattr` | 1 |

### Del vendor, dominio compreso

`ccci_mdinit` (8), `stflashtool` (6), `rild` (6), `mtk_hal_camera` (6),
`aee_aedv` (4), `nvram_daemon` (4), `mnld` (4), `fuelgauged_nvram` (3),
`mtk_hal_audio` (3), `mtk_hal_wifi` (2), `mtk_hal_sensors` (2),
`mtk_hal_bluetooth` (1). Qui non si tocca niente: le regole starebbero nel
blob MediaTek.

**Nessuno di questi blocca una funzione misurata.** La batteria di
`tools/prova-driver.sh` eseguita con `setenforce 0` e `setenforce 1` sullo
stesso boot non mostra una sola differenza funzionale.
