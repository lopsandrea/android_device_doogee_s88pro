/*
 * initlog -- si mette davanti a init e salva i log dove li si possa
 * rileggere anche se il telefono non si avvia.
 *
 * Il ramdisk di primo stadio contiene soltanto init: niente shell, niente
 * strumenti. Questo programma prende il posto di /init, avvia due figli che
 * copiano i log sulla partizione cache GREZZA, e poi esegue l init vero.
 *
 * Due flussi, due punti della stessa partizione:
 *
 *   offset 300 MiB  l anello dei messaggi del kernel, letto con klogctl
 *   offset 350 MiB  i pacchetti di logd, cosi come arrivano dal suo socket
 *                   di lettura; si riconoscono da soli (hdr_size + len danno
 *                   la lunghezza) e si riparsano a freddo con leggi-logd.py
 *
 * Il secondo flusso e quello che conta quando un servizio muore in pochi
 * millisecondi: init dice soltanto "exited with status 1", il motivo lo
 * scrive il servizio stesso, e finisce in logd.
 *
 * Scelte fatte per non disturbare cio che si vuole osservare:
 *
 *   - klogctl() invece di /proc/kmsg: init monta /proc da se, e in Android 14
 *     un mount che torna EBUSY lo porta a InitFatalReboot. Meglio non
 *     montare niente.
 *
 *   - la partizione grezza invece di un filesystem su /cache: init monta
 *     /cache piu tardi, con check e formattable, e un filesystem montato da
 *     noi glielo troverebbe occupato. Si scrive pero OLTRE il filesystem,
 *     non sopra: vedi il commento agli offset.
 *
 *   - il nodo si crea nella radice del ramdisk, non in /dev, perche init
 *     monta un tmpfs su /dev e lo coprirebbe. I descrittori aperti prima
 *     sopravvivono comunque.
 *
 *   - il figlio di logd afferra subito un descrittore di directory su /dev e
 *     poi ci si sposta dentro con fchdir(), parlando a logd per percorso
 *     relativo. Init, in primo stadio, fa SwitchRoot(): sposta /dev, /proc e
 *     /sys nella radice nuova con MS_MOVE e fa chroot. Chi e stato generato
 *     prima resta nella radice vecchia, che da quel momento e un guscio
 *     vuoto: nessun percorso assoluto arriva piu a niente. Un descrittore
 *     aperto invece punta all inode, non al nome, e lo spostamento non lo
 *     tocca. Misurato: /dev/socket c era a 1,25 s e non c era piu a 91 s.
 *
 *   - ogni figlio apre la sua uscita PRIMA di mettersi ad aspettare
 *     qualunque cosa. Init, in primo stadio, chiama FreeRamdisk() e cancella
 *     tutto quello che sta nella radice dell initramfs per liberare memoria:
 *     il nodo compreso. Un descrittore aperto prima resta valido -- il nodo
 *     e solo un nome -- ma chi prova ad aprirlo dopo trova ENOENT. Questo e
 *     costato un avvio: il figlio di logd apriva l uscita a cosa fatta,
 *     dopo aver atteso il socket, e non scriveva mai niente.
 *
 *   - niente fsync a ogni pacchetto: logd ne consegna a migliaia e
 *     l attesa del supporto cambierebbe i tempi che si stanno misurando.
 *     Si sincronizza ogni 16 KiB, e al massimo si perde quello.
 */

#include <fcntl.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/klog.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/types.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#define CACHE_MAJOR 259
#define CACHE_MINOR 7
#define NODO "/initlog_cache"
#define VERO "/init.real"

/* I due flussi stanno OLTRE il filesystem di /cache, non sopra.
 *
 * Scrivere dall inizio della partizione distrugge il filesystem, e il fstab di
 * fabbrica monta /cache senza nofail: mount_all torna -1, queue_fs_event(-1) e
 * un errore, il portachiavi fscrypt non viene creato e vold -- che ha
 * reboot_on_failure -- spegne il telefono. Lo strumento faceva fallire proprio
 * l avvio che doveva osservare.
 *
 * La partizione e 432 MiB. Si crea il filesystem di 256 MiB (prepara-cache.sh)
 * e si scrive oltre: ext4 si ferma alla dimensione nel superblocco e non sa
 * nemmeno che il resto esiste. */
#define OFFSET_KERNEL (300L * 1024 * 1024)
#define OFFSET_LOGD (350L * 1024 * 1024)
#define SOCKET_LOGD "/dev/socket/logdr"
#define RICHIESTA "stream tail=99999"

/* SYSLOG_ACTION_READ: consuma i messaggi, e si blocca finche non ce ne sono */
#define SYSLOG_ACTION_READ 2

#define SOGLIA_SYNC (16 * 1024)

static void scrivi_tutto(int fd, const char *p, size_t n)
{
	while (n > 0) {
		ssize_t w = write(fd, p, n);
		if (w <= 0)
			return;
		p += w;
		n -= (size_t)w;
	}
}

static int apri_uscita(off_t offset, const char *testa)
{
	int fd = open(NODO, O_WRONLY);

	if (fd < 0)
		return -1;
	if (offset != 0 && lseek(fd, offset, SEEK_SET) < 0) {
		close(fd);
		return -1;
	}
	scrivi_tutto(fd, testa, strlen(testa));
	return fd;
}

static void traccia(int fd, const char *messaggio)
{
	struct timespec ora;
	char riga[256];
	int n;

	clock_gettime(CLOCK_MONOTONIC, &ora);
	n = snprintf(riga, sizeof(riga), "[%5ld.%03ld] %s",
		     (long)ora.tv_sec, ora.tv_nsec / 1000000L, messaggio);
	if (n > 0)
		scrivi_tutto(fd, riga, (size_t)n);
	fsync(fd);
}

/* copia un file di /proc nella traccia: se non si riesce ad aprirlo, lo dice,
 * che e un fatto altrettanto utile */
static void copia_file(int fd, const char *percorso)
{
	char buf[4096];
	char riga[256];
	int in, n;

	n = snprintf(riga, sizeof(riga), "---- %s ----\n", percorso);
	scrivi_tutto(fd, riga, (size_t)n);

	in = open(percorso, O_RDONLY);
	if (in < 0) {
		scrivi_tutto(fd, "(non si apre)\n", 14);
		fsync(fd);
		return;
	}
	while ((n = (int)read(in, buf, sizeof(buf))) > 0)
		scrivi_tutto(fd, buf, (size_t)n);
	close(in);
	scrivi_tutto(fd, "---- fine ----\n", 15);
	fsync(fd);
}

/* le versioni che passano per un descrittore: /proc/1/root e la radice di
 * init, e da li si legge il sistema vivo anche dopo lo SwitchRoot */
static void copia_file_at(int fd, int dir, const char *percorso)
{
	char buf[4096];
	char riga[256];
	int in, n;

	n = snprintf(riga, sizeof(riga), "---- %s ----\n", percorso);
	scrivi_tutto(fd, riga, (size_t)n);

	in = openat(dir, percorso, O_RDONLY);
	if (in < 0) {
		scrivi_tutto(fd, "(non si apre)\n", 14);
		fsync(fd);
		return;
	}
	while ((n = (int)read(in, buf, sizeof(buf))) > 0)
		scrivi_tutto(fd, buf, (size_t)n);
	close(in);
	scrivi_tutto(fd, "---- fine ----\n", 15);
	fsync(fd);
}

static void sonda_at(int fd, int dir, const char *percorso)
{
	char riga[256];
	int n = snprintf(riga, sizeof(riga), "  %-62s %s\n", percorso,
			 faccessat(dir, percorso, F_OK, 0) == 0 ? "c e" : "manca");

	scrivi_tutto(fd, riga, (size_t)n);
}

static void sonda(int fd, const char *percorso)
{
	char riga[256];
	int n = snprintf(riga, sizeof(riga), "  %-40s %s\n", percorso,
			 access(percorso, F_OK) == 0 ? "c e" : "manca");

	scrivi_tutto(fd, riga, (size_t)n);
}

static void aspetta(long millesimi)
{
	struct timespec t;

	t.tv_sec = millesimi / 1000;
	t.tv_nsec = (millesimi % 1000) * 1000000L;
	nanosleep(&t, NULL);
}

static void copia_kernel(void)
{
	char buf[8192];
	int out, n;

	out = apri_uscita(OFFSET_KERNEL,
			  "=== s88pro: log del kernel, scritto da initlog ===\n");
	if (out < 0)
		_exit(1);

	/* qui il fsync a ogni giro si puo permettere: i messaggi del kernel
	 * arrivano a blocchi grandi e radi, e sono quelli che servono se il
	 * telefono si blocca del tutto */
	while ((n = klogctl(SYSLOG_ACTION_READ, buf, (int)sizeof(buf))) > 0) {
		scrivi_tutto(out, buf, (size_t)n);
		fsync(out);
	}
	_exit(0);
}

static void copia_logd(void)
{
	struct sockaddr_un indirizzo;
	char buf[16384];
	char riga[256];
	size_t da_sincronizzare = 0;
	int s, out, i, dev = -1, proc = -1;
	ssize_t n;

	/* per prima cosa l uscita, finche il nodo esiste ancora */
	out = apri_uscita(OFFSET_LOGD,
			  "=== s88pro: pacchetti di logd, scritti da initlog ===\n");
	if (out < 0)
		_exit(1);

	/* da qui in avanti si lascia detto dove si e arrivati: se qualcosa
	 * non va, il motivo si legge nella partizione invece di dover
	 * indovinare da un avvio muto */
	traccia(out, "figlio di logd avviato\n");
	scrivi_tutto(out, "sonde iniziali:\n", 16);
	sonda(out, "/dev");
	sonda(out, "/dev/null");
	sonda(out, "/dev/kmsg");
	sonda(out, "/dev/socket");
	sonda(out, SOCKET_LOGD);
	sonda(out, "/proc/self/mountinfo");
	sonda(out, "/proc/1/root" SOCKET_LOGD);
	sonda(out, "/system/bin/logcat");
	copia_file(out, "/proc/self/mountinfo");

	/* Si afferra /dev finche il nome ci arriva ancora. La presenza di
	 * /dev/socket distingue il tmpfs montato da init dalla directory /dev
	 * statica del ramdisk, che contiene solo null, console e urandom. */
	proc = open("/proc", O_RDONLY | O_DIRECTORY);
	for (i = 0; i < 3000 && dev < 0; i++) {
		if (access("/dev/socket", F_OK) == 0)
			dev = open("/dev", O_RDONLY | O_DIRECTORY);
		if (dev < 0)
			aspetta(10);
	}
	if (dev < 0) {
		traccia(out, "non si e riusciti ad afferrare /dev\n");
		_exit(1);
	}
	n = snprintf(riga, sizeof(riga), "/dev afferrato dopo %d giri\n", i);
	scrivi_tutto(out, riga, (size_t)n);
	traccia(out, "da qui si lavora per percorso relativo\n");

	/* da adesso i nomi si risolvono rispetto a un descrittore, che
	 * nessuno puo spostare */
	if (fchdir(dev) != 0) {
		traccia(out, "fchdir su /dev non riesce\n");
		_exit(1);
	}

	/* logd non c e ancora: il suo socket compare quando init lo avvia */
	for (i = 0; i < 900 && access("socket/logdr", F_OK) != 0; i++)
		aspetta(100);
	if (i == 900) {
		traccia(out, "il socket di logd non e mai comparso\n");
		_exit(1);
	}
	traccia(out, "socket di logd trovato\n");

	memset(&indirizzo, 0, sizeof(indirizzo));
	indirizzo.sun_family = AF_UNIX;
	strncpy(indirizzo.sun_path, "socket/logdr",
		sizeof(indirizzo.sun_path) - 1);

	/* un socket nuovo a ogni tentativo: un connect fallito lascia quello
	 * vecchio inservibile, e tutti i tentativi dopo darebbero EINVAL */
	for (i = 0; i < 600; i++) {
		s = socket(AF_UNIX, SOCK_SEQPACKET, 0);
		if (s < 0) {
			traccia(out, "socket() non riesce\n");
			_exit(1);
		}
		if (connect(s, (struct sockaddr *)&indirizzo,
			    sizeof(indirizzo)) == 0)
			break;
		close(s);
		aspetta(100);
	}
	if (i == 600) {
		traccia(out, "connect al socket di logd non riesce\n");
		_exit(1);
	}

	/* Prima dei pacchetti, una fotografia del sistema vivo presa dalla
	 * radice di init: a questo punto linkerconfig ha gia scritto la sua
	 * configurazione, e questa e l unica occasione per leggerla. */
	if (proc >= 0) {
		traccia(out, "dalla radice di init:\n");
		sonda_at(out, proc, "1/root/linkerconfig/ld.config.txt");
		sonda_at(out, proc,
			 "1/root/apex/com.android.vndk.v29/lib64/libpuresoftkeymasterdevice.so");
		sonda_at(out, proc,
			 "1/root/system/lib64/libpuresoftkeymasterdevice.so");
		sonda_at(out, proc, "1/root/vendor/lib64/libkeymaster4.so");
		sonda_at(out, proc,
			 "1/root/apex/com.android.vndk.v29/etc/vndkcore.libraries.29.txt");
		copia_file_at(out, proc, "1/root/linkerconfig/ld.config.txt");
	} else {
		traccia(out, "/proc non afferrato: niente fotografia\n");
	}

	/* la richiesta va spedita col suo terminatore, come fa liblog */
	if (write(s, RICHIESTA, sizeof(RICHIESTA)) < 0) {
		traccia(out, "la richiesta a logd non parte\n");
		_exit(1);
	}

	while ((n = read(s, buf, sizeof(buf))) > 0) {
		scrivi_tutto(out, buf, (size_t)n);
		da_sincronizzare += (size_t)n;
		if (da_sincronizzare >= SOGLIA_SYNC) {
			fsync(out);
			da_sincronizzare = 0;
		}
	}
	fsync(out);
	_exit(0);
}

int main(int argc, char **argv)
{
	(void)argc;

	if (getpid() == 1) {
		mknod(NODO, S_IFBLK | 0600, makedev(CACHE_MAJOR, CACHE_MINOR));

		if (fork() == 0)
			copia_kernel();
		if (fork() == 0)
			copia_logd();
	}

	execv(VERO, argv);
	return 1;
}
