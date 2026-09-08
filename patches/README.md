# Patch all'albero LineageOS

Modifiche che non stanno nel device tree perché toccano progetti comuni. Vanno riapplicate
dopo ogni `repo sync`.

## frameworks_opt_telephony-baseband-version-length.patch

**Progetto**: `frameworks/opt/telephony`

**Sintomo**: `com.android.phone` va in crash appena il modem risponde, riparte, ricrasha, finché
`ActivityManager` si arrende ("crashed too many times, killing"). Nessuna SIM utilizzabile.

```
java.lang.IllegalArgumentException: value of system property 'gsm.version.baseband'
  is longer than 91 characters: E977_VSIM_71_Q0_L...
    at android.sysprop.TelephonyProperties.baseband_version(TelephonyProperties.java:177)
    at android.telephony.TelephonyManager.setBasebandVersionForPhone(TelephonyManager.java:10838)
    at com.android.internal.telephony.GsmCdmaPhone.handleMessage(GsmCdmaPhone.java:3040)
```

**Causa**: AOSP tronca la stringa di versione del baseband a `PROP_VALUE_MAX/2` (46 caratteri),
ma lo fa **per ciascun telefono**; i valori vengono poi concatenati in un'unica proprietà, che
non può superare i 91 caratteri. Questo device dichiara `ro.telephony.sim.count=3`, e il RIL
MediaTek restituisce stringhe lunghe: 3 × 46 supera il limite e `SystemProperties.set` solleva
l'eccezione. Con due sole SIM il conto sarebbe comunque 93 caratteri.

**Modifica**: quota per telefono da `PROP_VALUE_MAX/2` a `PROP_VALUE_MAX/4` (23 caratteri):
3 × 23 più due virgole fanno 71, dentro il limite. Il troncamento tiene la **coda** della
stringa, che è la parte che identifica la build del modem.

## packages_apps_Nfc-null-native-data.patch

**Progetto**: `packages/apps/Nfc`

**Sintomo**: `com.android.nfc` muore e riparte circa ogni 0,8 secondi, all'infinito, con un crash
nativo:

```
signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x10
Cause: null pointer dereference
  #00 libnfc_nci_jni.so (android::nfaDeviceManagementCallback(...)+808)
  #01 libnfc-nci.so (nfa_dm_nfc_response_cback(...))
  #02 libnfc-nci.so (nfc_ncif_proc_rf_field_ntf(unsigned char))
```

**Causa**: in `nfaDeviceManagementCallback` il codice chiama `getNative(NULL, NULL)` e usa subito
il risultato con `ScopedAttach attach(nat->vm, &e)`, senza verificare che non sia `NULL`. La HAL
ST invia la notifica di campo RF prima che il lato JNI sia inizializzato: `nat` è `NULL` e
`nat->vm` dereferenzia l'offset `0x10` — l'indirizzo esatto riportato nel tombstone.

**Modifica**: controllo di `nat == NULL` prima dell'uso, nei due punti che hanno lo stesso difetto
(`NFA_DM_RF_FIELD_EVT` e `NFA_DM_NFCC_TRANSPORT_ERR_EVT`/`TIMEOUT`). La notifica arrivata troppo
presto viene ignorata invece di far cadere il processo.

## packages_apps_Nfc-mifare-classic-extras.patch — RIMOSSA, non serve piu'

Aggiungeva a `NativeNfcTag.java` il `case TagTechnology.MIFARE_CLASSIC` che
mancava: senza, il `Bundle` degli extras restava null e ogni app che apriva una
carta Mifare moriva con `NullPointerException` dentro `NfcA.<init>`.

**LineageOS 20 ora lo ha di suo.** Alla riga 756 di quel file c'e' lo stesso
identico codice -- SAK preso da `mTechActBytes[i][0]`, ATQA da
`mTechPollBytes[i]` -- e la patch non si applicava piu'. Verificato sull'albero
sincronizzato l'8 settembre 2026.


## packages_apps_FMRadio-antenna-selection.patch

**Progetto**: `packages/apps/FMRadio`

**A cosa serve**: scegliere quale percorso di antenna usa il tuner FM, su un telefono che non ha
la presa per gli auricolari.

L'app seleziona l'antenna solo quando riceve il broadcast `HEADSET_PLUG`:

```java
mValueHeadSetPlug = (intent.getIntExtra("state", -1) == HEADSET_PLUG_IN) ? 0 : 1;
switchAntennaAsync(mValueHeadSetPlug);
```

Qui quel broadcast non arriva mai — non c'è una presa in cui infilare qualcosa — e il chip resta
sul valore predefinito. La patch chiama `switchAntenna` all'accensione, quando il device dichiara
l'antenna interna, leggendo il valore da una proprietà:

```bash
setprop persist.vendor.fm.antenna 0    # antenna lunga: il cavo nel connettore
setprop persist.vendor.fm.antenna 1    # antenna corta: quella interna (predefinita)
```

È una proprietà e non una costante proprio per poter confrontare le due senza ricompilare.

**Stato**: con la sola antenna interna la ricezione resta debole — si sente rumore. Il tuner però
funziona: si accende, sintonizza e riconosce l'RDS. Serve un'antenna vera, cioè un cavo collegato.

## frameworks_base-screenrecord-encoder-limits.patch

**Progetto**: `frameworks/base`

**Sintomo**: la registrazione dello schermo produce un video **nero**, senza un solo messaggio di
errore.

**Causa**: un difetto di AOSP, che qui viene allo scoperto. `ScreenMediaRecorder.getSupportedSize()`
chiede le dimensioni massime al **decoder**:

```java
// Get max size from the decoder, to ensure recordings will be playable on device
MediaCodec decoder = MediaCodec.createDecoderByType(videoType);
```

L'intenzione è assicurarsi che il video sia riproducibile, ma nessuno chiede all'**encoder** se sia
in grado di produrlo. Su questo telefono il decoder arriva a 3840×2176 e l'encoder si ferma molto
prima: la risoluzione nativa (1080×2340) risulta quindi "supportata", non viene ridimensionata, e
la registrazione esce vuota. Dove i due limiti coincidono il difetto non si manifesta.

**Modifica**: interroga anche l'encoder e usa il limite più stretto dei due, sia per le dimensioni
massime sia per l'allineamento, e verifica `isSizeSupported` su entrambi.

## frameworks_av-wfd-encoder-choice.patch

**Progetto**: `frameworks/av`

**A cosa serve**: rendere scegliibile l'encoder del WiFi Display, che altrimenti non lo è.
`Converter::initEncoder()` prende il primo encoder disponibile con `CreateByType` e, a differenza di
`MediaCodecSource`, non ha alcun ripiego se quello fallisce. La patch legge prima la proprietà

```
media.wfd.video-encoder
```

e, se è impostata, usa quel codec.

**Serve ancora?** Non per far funzionare Miracast: da quando AFBC è spento
(`debug.gpu.afbc.disable=1` nel device tree) l'encoder hardware codifica correttamente anche i
buffer che arrivano da una Surface, e il WiFi Display va in accelerazione senza che gli si dica
nulla. La proprietà nel device tree infatti non è più impostata.

Resta in albero perché è la sola leva su quel percorso: se un domani un encoder desse problemi su
una risoluzione particolare, è l'unico modo per ripiegare sul software senza ricompilare —

```bash
setprop media.wfd.video-encoder c2.android.avc.encoder
```

La storia completa del difetto AFBC, con il reverse engineering del blob e le ipotesi scartate, è in
`docs/bringup/hardware-riferimento.md`.
