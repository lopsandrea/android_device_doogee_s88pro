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

### Chiusa nel kernel, non qui

`network_stack -> fs_bpf : file read`, quattordici occorrenze, era stata messa
fra le "vietate da un neverallow" -- `bpfloader.te:36` vieta proprio a
`network_stack` di leggere `fs_bpf`. Il divieto pero' era giusto e il difetto
stava altrove: quelle mappe **non dovevano avere quel tipo**. Le mappe erano
gia' al posto giusto (`/sys/fs/bpf/tethering/`), ma il kernel dava a tutto
quello che sta in bpffs il tipo della radice, ignorando i `genfscon` per
sotto-percorso che la policy ha da sempre:

    policy   genfscon bpf /tethering u:object_r:fs_bpf_tethering:s0
    device   /sys/fs/bpf/tethering -> u:object_r:fs_bpf:s0

Manca una riga in `security/selinux/hooks.c`, ed e' upstream dal 2020:
4ca54d3d3022, *"security: selinux: allow per-file labeling for bpffs"*. Con
quella, le sei sottodirectory prendono il tipo che gli spetta, i quattordici
denial spariscono e l'offload del tethering parte. Sta nel repo del kernel.

**La lezione**: un denial vietato da un `neverallow` non significa "da
lasciare aperto". Significa che AOSP si aspetta un'altra configurazione, e
vale la pena chiedersi quale sia prima di rassegnarsi.

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

## Perche' i denial del vendor non si chiudono, e come si e' verificato

Le regole servirebbero a domini o tipi che definisce la policy MediaTek. Prima
di lasciarli aperti sono state provate tutte le strade, e vale la pena
scriverle: sembrano tutte praticabili finche' non le si prova.

### Le regole erano pronte e valide

Trentatre' `allow` che chiudono novantatre' delle centoventinove righe, fra cui
tutte e quarantanove quelle di `vold` sul nodo `uevent`. Sono state validate
sul serio: prese le policy dal telefono (`plat`, `mapping/29.0`,
`plat_pub_versioned`, `vendor`, `system_ext`) e date a `secilc` con i
neverallow **attivi**, contando le violazioni.

| | violazioni |
|---|---|
| senza le nostre regole | 196 |
| con le nostre regole | 196 |

Le 196 sono preesistenti: sono conflitti fra la policy MediaTek di Android 10 e
la piattaforma 13 (`llkd` contro `teeregistryd_app` e simili), ed e' il motivo
per cui init compila con i neverallow disattivati. Il primo giro ne aggiungeva
sette: quelle regole -- proprieta' riservate per `rild`, `mtk_hal_camera`,
`stflashtool`, `mtk_hal_wifi`, e `dac_override` per `kernel` -- sono state
tolte, perche' li' il divieto e' voluto.

### Il muro: dove metterle

init, quando ricompila la policy all'avvio, unisce cinque file. Nessuno dei
tre che potrebbero ospitarle e' raggiungibile:

**`/vendor/etc/selinux/vendor_sepolicy.cil`** e' il blob MediaTek. Modificarlo
vorrebbe dire alterare una partizione di fabbrica: non lo fa il build, non e'
riproducibile, e non e' una cosa da sottomettere.

**`/odm/etc/selinux/odm_sepolicy.cil`** sembra la via giusta -- e' il posto che
AOSP prevede per aggiungere regole senza toccare il vendor -- ma qui
`/odm/etc` e' un collegamento a `/vendor/odm/etc`, quindi si torna nella
partizione di fabbrica. Se ne accorge solo chi guarda:

    lrw-r--r-- 1 root root 15 /odm/etc -> /vendor/odm/etc

Prima di scoprirlo il file era stato messo nel ramdisk del boot.img, il che non
serve a niente per un secondo motivo: la "/" del telefono acceso e' `dm-0`,
cioe' la partizione system montata come radice, e il ramdisk sparisce dopo il
first stage init.

**`/product/etc/selinux/product_sepolicy.cil`** e' l'unico che sta dentro la
system.img (`/product` e' un collegamento a `/system/product`), e infatti si
puo' scrivere. Ma le regole non ci arrivano lo stesso: quel percorso e' gia' un
target di soong (`overriding commands for target ...`), e usando il meccanismo
previsto (`PRODUCT_PRIVATE_SEPOLICY_DIRS`) il compilatore si ferma sul primo
tipo del vendor:

    sepolicy/product/private/vendor_bridge.te:3:
      ERROR 'unknown type sysfs_mmcblk'

Dichiararlo in `sepolicy/vendor/` non aiuta: la conf della policy product non
include le directory del vendor. **E' la separazione di Treble che funziona
come previsto**: la policy del lato sistema non puo' nominare i tipi del
vendor, per costruzione. Non e' un ostacolo da aggirare con piu' ingegno.

### Cosa resterebbe da fare, se un giorno servisse

Costruire la policy del vendor invece di prenderla dal blob, portando dentro le
regole delle HAL MediaTek. E' il lavoro che
`TARGET_USES_PREBUILT_VENDOR_SEPOLICY` evita, e il commento in `BoardConfig.mk`
racconta com'e' andata l'ultima volta che la si e' sostituita: i servizi del
vendor sono rimasti muti e `system_server` e' rimasto appeso ad aspettarli.
