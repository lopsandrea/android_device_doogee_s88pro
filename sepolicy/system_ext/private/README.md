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
