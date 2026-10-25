#!/usr/bin/env bash
# hu-debloat.sh — debloat + tune headunit MediaTek AC8227L (Android 8.1, 1 GB RAM) lewat ADB.
# Semua reversible: `pm uninstall -k --user 0` (APK tetap di /system, cuma di-hide dari
# user 0), dicatat ke hu-removed.txt buat restore.
#
# Konek (ADB HU ini di port 8555, bukan 5555; terima prompt RSA di layar HU):
#   adb connect <IP_HU>:8555
#
#   ./hu-debloat.sh diag            # cek yang bikin lemot (RAM, CPU, suhu) -> file, kirim ke Claude
#   ./hu-debloat.sh scan            # list semua paket + label -> file, kirim ke Claude
#   ./hu-debloat.sh rootcheck       # cek apakah su bisa dipakai dari adb shell
#   ./hu-debloat.sh linkcheck       # cek app CarPlay/Android Auto bawaan + dukungan USB host
#   ./hu-debloat.sh apply           # hapus bloat tier-1 (AOSP + MTK sampah)
#   ./hu-debloat.sh apply --google  # + Google sampingan (Play Store/Maps tetap aman)
#   ./hu-debloat.sh apply --minimal # + Google sampingan + Play Store. GMS tetap (buat Google Maps).
#                                   #   App diinstall manual pakai `install`.
#   ./hu-debloat.sh apply --nogms   # + MATIIN Google Play Services/Store (hemat RAM paling gede,
#                                   #   tapi Google Maps ikut mati)
#   ./hu-debloat.sh install         # install semua APK di folder ./apk
#                                   #   (file .apk tunggal, atau subfolder isi split APK / .apkm diekstrak)
#   ./hu-debloat.sh extra           # hapus paket yang lu tulis di hu-extra.txt
#   ./hu-debloat.sh tune            # animasi off, scan background off, dll
#   ./hu-debloat.sh bgoff pkg1 pkg2 # larang app jalan di background
#   ./hu-debloat.sh compile         # precompile app (lama, sekali aja)
#   ./hu-debloat.sh restore         # balikin semua yang pernah dihapus
#
# IP/port beda:  DEVICE=192.168.43.50:8555 ./hu-debloat.sh scan
# Paksa hapus paket protected dari hu-extra.txt:  FORCE=1 ./hu-debloat.sh extra

set -uo pipefail

DEV="${DEVICE:-}"
LOG="hu-removed.txt"
EXTRA="hu-extra.txt"
STAMP="$(date +%Y%m%d-%H%M)"

A()  { if [ -n "$DEV" ]; then adb -s "$DEV" "$@"; else adb "$@"; fi; }
SH() { A shell "$@" 2>/dev/null | tr -d '\r'; }

# Jangan disentuh: servis mobil (Autochips/MTK car stack, kamera mundur, AVIN, DVR, MCU,
# setir, CAN), BT telpon, mirroring/CarPlay, radio, launcher, input, telephony, inti Android.
PROTECT='autochips|mediatek|mtk|backcar|reverse|camera|avm|avin|dvr|mcu|canbus|\.can\.|carservice|tpms|steer|swc|keyconfig|factory|bluetooth|\.bt|zlink|carplay|carlife|carbit|easyconn|phonelink|mirror|autokit|carlinkit|tlink|gb\.xxy|radio|\.fm|launcher|systemui|settings|inputmethod|latin|telephony|phone|dialer|incallui|contacts|permissioncontroller|packageinstaller|webview|providers\.(settings|media|downloads|contacts|telephony)|klikdash|shell|location|gms|gsf|vending|media|audio|keychain|certinstaller|externalstorage|documentsui|server|wifi|tethering|captiveportal|\.ota|update|gps|nlp'

# Tier 1: sampah AOSP + tools MTK yang gak dipakai di HU (dikurasi, bypass PROTECT).
TIER1="
com.android.printspooler
com.android.bips
com.android.bookmarkprovider
com.android.providers.partnerbookmarks
com.android.egg
com.android.dreams.basic
com.android.dreams.phototable
com.android.wallpaper.livepicker
com.android.wallpapercropper
com.android.wallpaperbackup
com.android.calendar
com.android.email
com.android.exchange
com.android.gallery3d
com.android.music
com.android.soundrecorder
com.android.deskclock
com.android.htmlviewer
com.android.quicksearchbox
com.android.managedprovisioning
com.android.onetimeinitializer
com.android.backupconfirm
com.android.sharedstoragebackup
com.android.calllogbackup
com.android.emergency
com.android.simappdialog
com.android.stk
com.android.cellbroadcastreceiver
com.android.camera2
com.android.smspush
com.android.companiondevicemanager
com.android.hotwordenrollment.okgoogle
com.android.hotwordenrollment.xgoogle
com.mediatek.mtklogger
com.mediatek.ygps
com.mediatek.calendarimporter
com.mediatek.datatransfer
com.mediatek.backuprestore
com.mediatek.schpwronoff
com.mediatek.callrecorder
com.mediatek.lbs.em2.ui
"

# Tier 2 (--google): Google sampingan. GMS/Play Store/Maps TIDAK disentuh.
TIER2="
com.google.android.feedback
com.google.android.partnersetup
com.google.android.syncadapters.calendar
com.google.android.syncadapters.contacts
com.google.android.backuptransport
com.google.android.onetimeinitializer
com.google.android.printservice.recommendation
com.google.android.marvin.talkback
com.google.android.apps.restore
com.google.android.setupwizard
com.google.android.tts
com.google.android.videos
com.google.android.music
com.google.android.apps.photos
com.google.android.apps.docs
com.google.android.gm
com.google.android.apps.tachyon
com.google.android.googlequicksearchbox
com.google.android.apps.googleassistant
"

# Tier 3 (--nogms): Google Play Services. Makan RAM 150-250 MB di HU 1 GB.
TIER3="
com.google.android.gms
com.google.android.gsf
com.android.vending
"

need_device() {
  if ! A get-state >/dev/null 2>&1; then
    echo "✗ HU gak kebaca. Jalanin: adb connect <IP>:8555 lalu tap 'Allow' di layar HU."
    exit 1
  fi
}

installed_list() { SH pm list packages --user 0 | sed 's/^package://' | sort; }
is_protected()   { echo "$1" | grep -Eqi "$PROTECT"; }

remove_pkg() {
  local p="$1" force="${2:-0}"
  if [ "$force" != "1" ] && is_protected "$p"; then
    echo "  ⛔ skip (protected) $p"; return
  fi
  local r; r="$(SH pm uninstall -k --user 0 "$p")"
  if echo "$r" | grep -q Success; then
    echo "  ✓ $p"; grep -qx "$p" "$LOG" 2>/dev/null || echo "$p" >> "$LOG"
  else
    echo "  ✗ $p ($r)"
  fi
}

cmd_diag() {
  local f="hu-diag-$STAMP.txt"
  {
    echo "== device"; SH getprop ro.product.model; SH getprop ro.build.version.release; SH getprop ro.board.platform
    echo "== uptime"; SH uptime
    echo "== RAM";    SH grep -E 'MemTotal|MemFree|MemAvailable|Cached|SwapTotal|SwapFree' /proc/meminfo
    echo "== zram";   SH cat /sys/block/zram0/disksize
    echo "== LMK minfree"; SH cat /sys/module/lowmemorykiller/parameters/minfree
    echo "== suhu (thermal zones)"
    SH 'for z in /sys/class/thermal/thermal_zone*; do echo "$(cat $z/type 2>/dev/null) $(cat $z/temp 2>/dev/null)"; done'
    echo "== CPU governor/freq"
    SH 'for c in /sys/devices/system/cpu/cpu[0-9]*; do echo "$(basename $c) $(cat $c/cpufreq/scaling_governor 2>/dev/null) $(cat $c/cpufreq/scaling_cur_freq 2>/dev/null)"; done'
    echo "== top CPU (snapshot)"; SH top -b -n 1 -m 25
    echo "== RAM per proses (PSS)"; SH dumpsys meminfo | sed -n '/Total PSS by process/,/Total PSS by OOM/p' | head -45
    echo "== servis jalan (3rd-party)"; SH dumpsys activity services | grep -E 'ServiceRecord' | grep -v -E 'com\.android\.|android\.' | head -40
    echo "== MTK log"; SH getprop | grep -iE 'mtklog|log\.tag|debug\.' | head -20
    echo "== storage"; SH df /data
    echo "== animasi"; SH settings get global window_animation_scale
    echo "== jumlah paket"; SH pm list packages | wc -l
    echo "== app 3rd-party"; SH pm list packages -3
  } > "$f"
  echo "✓ Disimpan ke $f — kirim isinya ke Claude."
}

cmd_scan() {
  local f="hu-packages-$STAMP.txt" third
  third="$(SH pm list packages -3 | sed 's/^package://')"
  : > "$f"
  installed_list | while read -r p; do
    [ -z "$p" ] && continue
    if   echo "$TIER1" | grep -qx "$p"; then tag="BLOAT-T1"
    elif echo "$TIER2" | grep -qx "$p"; then tag="GOOGLE-T2"
    elif echo "$TIER3" | grep -qx "$p"; then tag="GMS-T3"
    elif is_protected "$p";               then tag="protected"
    elif echo "$third" | grep -qx "$p";  then tag="3RD-PARTY"
    else tag="review"; fi
    printf "%-10s %s\n" "$tag" "$p" >> "$f"
  done
  echo "✓ $f — kirim isinya ke Claude buat dipilihin."
  for t in BLOAT-T1 GOOGLE-T2 3RD-PARTY review; do
    echo; echo "— $t:"; grep "^$t" "$f" | awk '{print "  "$2}'
  done
}

cmd_rootcheck() {
  echo "su -c id     : $(SH su -c id)"
  echo "su 0 id      : $(SH su 0 id)"
  echo "ls -l su     : $(SH ls -l /system/xbin/su)"
  echo "(kalau ada 'uid=0(root)', berarti bisa tweak RAM/zram/LMK lebih dalam)"
}

cmd_linkcheck() {
  echo "== App CarPlay/Android Auto/mirroring yang terinstall"
  SH pm list packages | sed 's/^package://' \
    | grep -Ei 'zlink|zjinnova|carplay|carlife|carbit|easyconn|phonelink|autokit|carlinkit|tlink|gb\.xxy|androidauto|projection|mirror' \
    || echo "  (gak ada)"
  echo "== USB host (wajib buat dongle Carlinkit / CarPlay kabel)"
  SH pm list features | grep -i usb || echo "  (gak kebaca)"
  echo "== Perangkat USB yang lagi nyolok"
  SH ls /dev/bus/usb/* 2>/dev/null || echo "  (gak kebaca)"
}

cmd_apply() {
  local list="$TIER1"
  for a in "$@"; do
    case "$a" in
      --google) list="$list$TIER2" ;;
      --minimal) list="$list$TIER2
com.android.vending
com.google.android.youtube
com.google.android.apps.youtube.music" ;;
      --nogms)  list="$list$TIER2$TIER3" ;;
    esac
  done
  local have; have="$(installed_list)"
  echo "Debloat (reversible, log: $LOG)"
  echo "$list" | while read -r p; do
    [ -z "$p" ] && continue
    echo "$have" | grep -qx "$p" && remove_pkg "$p" 1
  done
  echo "Selesai. Reboot HU: adb reboot"
}

cmd_extra() {
  [ -f "$EXTRA" ] || { echo "Buat $EXTRA dulu, 1 nama paket per baris."; exit 1; }
  grep -Ev '^\s*(#|$)' "$EXTRA" | while read -r p; do remove_pkg "$p" "${FORCE:-0}"; done
}

cmd_restore() {
  [ -f "$LOG" ] || { echo "Gak ada $LOG, gak ada yang perlu di-restore."; exit 0; }
  while read -r p; do
    [ -z "$p" ] && continue
    echo "  ↺ $p  $(SH pm install-existing "$p")"
  done < "$LOG"
  mv "$LOG" "$LOG.restored-$STAMP"
}

cmd_tune() {
  SH settings put global window_animation_scale 0
  SH settings put global transition_animation_scale 0
  SH settings put global animator_duration_scale 0
  SH settings put global wifi_scan_always_enabled 0
  SH settings put global ble_scan_always_enabled 0
  SH settings put global network_recommendations_enabled 0
  SH settings put global package_verifier_enable 0
  SH settings put global verifier_verify_adb_installs 0
  echo "✓ Animasi off, wifi/ble background scan off, package verifier off."
}

cmd_bgoff() {
  [ $# -gt 0 ] || { echo "Kasih nama paket: ./hu-debloat.sh bgoff com.foo com.bar"; exit 1; }
  for p in "$@"; do
    if is_protected "$p"; then echo "  ⛔ skip (protected) $p"; continue; fi
    SH cmd appops set "$p" RUN_IN_BACKGROUND ignore
    SH am force-stop "$p"
    echo "  ✓ $p gak boleh jalan di background"
  done
}

cmd_install() {
  [ -d apk ] || { echo "Bikin folder ./apk, taruh APK di situ."; exit 1; }
  for f in apk/*.apk; do
    [ -e "$f" ] || continue
    echo "→ $f"; A install -r -g "$f"
  done
  for d in apk/*/; do
    [ -d "$d" ] || continue
    ls "$d"*.apk >/dev/null 2>&1 || continue
    echo "→ $d (split)"; A install-multiple -r -g "$d"*.apk
  done
}

cmd_compile() {
  echo "Precompile app (speed-profile). Lama, HU jangan dimatiin..."
  A shell cmd package compile -m speed-profile -a
}

need_device
case "${1:-}" in
  diag)      cmd_diag ;;
  scan)      cmd_scan ;;
  rootcheck) cmd_rootcheck ;;
  apply)     shift; cmd_apply "$@" ;;
  extra)     cmd_extra ;;
  restore)   cmd_restore ;;
  tune)      cmd_tune ;;
  bgoff)     shift; cmd_bgoff "$@" ;;
  compile)   cmd_compile ;;
  install)   cmd_install ;;
  linkcheck) cmd_linkcheck ;;
  *) sed -n '2,30p' "$0" ;;
esac
