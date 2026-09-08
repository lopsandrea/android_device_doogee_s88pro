Albero di dispositivo per DOOGEE S88 Pro (s88pro)
=================================================

Il DOOGEE S88 Pro e' uno smartphone rugged del 2020. Questo albero costruisce
LineageOS 20.

Caratteristiche, misurate sul dispositivo
-----------------------------------------

| voce | valore | come e' stato letto |
|------|--------|---------------------|
| SoC | MediaTek Helio P70 (MT6771) | `ro.board.platform` |
| CPU | 8 core, fino a 2.106 GHz | `/proc/cpuinfo`, `cpufreq/cpuinfo_max_freq` |
| GPU | Mali-G72 MP3 | `glGetString(GL_RENDERER)` |
| RAM | 6 GB | `MemTotal: 5900900 kB` |
| Archiviazione | 128 GB | `df` su `/data`: 107 GiB utili |
| Schermo | 1080x2340, densita' 480 | `wm size`, `wm density` |
| Camera posteriore | Sony IMX230, cattura 5344x4016 | driver imgsensor |
| Camera frontale | Samsung S5K3P3SX | driver imgsensor |

Compilare
---------

Finche' i repo non stanno sotto l'organizzazione LineageOS serve il manifest
locale (vedi il commento dentro `s88pro.xml` per il perche'):

    mkdir -p .repo/local_manifests
    curl -o .repo/local_manifests/s88pro.xml \
      https://raw.githubusercontent.com/lopsandrea/android_device_doogee_s88pro/lineage-20/s88pro.xml
    repo sync

    source build/envsetup.sh
    breakfast lineage_s88pro-userdebug
    mka bacon

Prima di compilare, applicare le sei patch in [`patches/`](patches): toccano
progetti comuni, quindi non possono stare nel device tree, e senza tre di esse
il telefono non e' usabile -- SIM inutilizzabile e NFC in crash a ripetizione.
Il README li' accanto spiega, per ciascuna, sintomo, causa e modifica.

Il kernel
---------

`prebuilt/kernel` e' un `Image.gz-dtb` gia' compilato, ed e' quello che
`BoardConfig.mk` usa. I sorgenti stanno in
[android_kernel_doogee_s88pro](https://github.com/lopsandrea/android_kernel_doogee_s88pro):
sono un albero ALPS 4.14.141 in cui i driver mancanti sono stati ricostruiti
facendo reverse engineering del kernel di fabbrica, verificando ogni
correzione contro il binario originale. `prebuilt/README.md` dice come
rigenerarlo.

Cosa non funziona
-----------------

- **registrazione video con la camera posteriore**: il file esce con ogni
  fotogramma di un colore uniforme. Non e' il kernel -- quello di fabbrica
  sbaglia allo stesso modo -- e non e' l'HAL, perche' OpenCamera e Telegram
  registrano bene sulla stessa camera.
- **52 denial SELinux all'avvio**, fra tipi del vendor MediaTek: non chiudibili
  dal device tree perche' la policy del vendor arriva precompilata. Nessuno
  impedisce qualcosa. Vedi `sepolicy/`.
