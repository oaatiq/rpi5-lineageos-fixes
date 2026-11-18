#!/sbin/sh
#
# ADDOND_VERSION=3
#
# /system/addon.d/60-cec.sh
# During a LineageOS upgrade, this script backs up the CEC boot files (cecport and
# cecannounce, see pi/README.md), /vendor is rewritten, then the files are restored.
#

. /tmp/backuptool.functions

list_files() {
cat <<EOF
/vendor/bin/cecport
/vendor/etc/init/cecport.rc
/vendor/bin/cecannounce
/vendor/etc/init/cecannounce.rc
EOF
}

case "$1" in
  backup)
    list_files | while read FILE DUMMY; do
      backup_file "$FILE"
    done
  ;;
  restore)
    list_files | while read FILE DUMMY; do
      [ -f "$C/$FILE" ] && restore_file "$FILE"
    done
  ;;
  pre-backup)
    # Stub
  ;;
  post-backup)
    # Stub
  ;;
  pre-restore)
    # Stub
  ;;
  post-restore)
    list_files | while read FILE DUMMY; do
      [ -f "$FILE" ] || continue
      case "$FILE" in
        */bin/*)
          chmod 755 "$FILE"
          chown root:shell "$FILE"
        ;;
        *)
          chmod 644 "$FILE"
          chown root:root "$FILE"
        ;;
      esac
    done
  ;;
esac

# A missing file must not fail the update.
exit 0
