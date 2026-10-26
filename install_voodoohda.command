#!/bin/bash
# VoodooHDA を OpenCore の EFI に導入する（EFIバックアップ付き）
set -e

URL="https://github.com/CloverHackyColor/VoodooHDA/releases/download/v3.7.1-alpha/VoodooHDA-v3.7.1-RELEASE-alpha-d9e642d.zip"
PB=/usr/libexec/PlistBuddy
EFI_ID=disk0s2

pause() { echo; read -n 1 -s -r -p "何かキーを押すと閉じます..."; echo; }
trap 'echo "エラーで中断しました"; pause' ERR

# EFI のマウント
if [ ! -d /Volumes/EFI/EFI/OC ]; then
  sudo diskutil mount "$EFI_ID"
fi

OC=/Volumes/EFI/EFI/OC
P="$OC/config.plist"
[ -f "$P" ] || { echo "config.plist が見つかりません"; pause; exit 1; }

# バックアップ
STAMP=$(date +%m%d%H%M)
BK=~/EFI_backup_$STAMP
cp -R /Volumes/EFI/EFI "$BK"
cp "$P" "$P.bak_$STAMP"
echo "バックアップ: $BK （config.plist は EFI 内にも .bak を作成）"

# ダウンロードと展開
cd ~/Downloads
curl -fL -o VoodooHDA.zip "$URL"
rm -rf VoodooHDA_x
unzip -q VoodooHDA.zip -d VoodooHDA_x
K=$(find VoodooHDA_x -iname "VoodooHDA*.kext" -not -path "*__MACOSX*" | head -1)
if [ -z "$K" ]; then
  echo "kext が見つかりません。zip の中身:"
  find VoodooHDA_x
  pause; exit 1
fi
KNAME=$(basename "$K")
EXE=$($PB -c "Print :CFBundleExecutable" "$K/Contents/Info.plist")
echo "kext: $KNAME / exe: $EXE"

# HDAS 以外の名前のオーディオデバイスにもマッチさせる
$PB -c "Delete :IOKitPersonalities:VoodooHDA:IONameMatch" "$K/Contents/Info.plist" 2>/dev/null || true
$PB -c "Add :IOKitPersonalities:VoodooHDA:IONameMatch array" \
    -c "Add :IOKitPersonalities:VoodooHDA:IONameMatch:0 string HDAS" \
    -c "Add :IOKitPersonalities:VoodooHDA:IONameMatch:1 string HDEF" \
    -c "Add :IOKitPersonalities:VoodooHDA:IONameMatch:2 string AZAL" \
    -c "Add :IOKitPersonalities:VoodooHDA:IONameMatch:3 string HDAU" \
    "$K/Contents/Info.plist"

rm -rf "$OC/Kexts/$KNAME"
cp -R "$K" "$OC/Kexts/"

# Kernel>Add を走査: SimpleHDA / AppleALC を無効化、件数と既存登録を確認
i=0
FOUND=-1
while $PB -c "Print :Kernel:Add:$i:BundlePath" "$P" >/dev/null 2>&1; do
  b=$($PB -c "Print :Kernel:Add:$i:BundlePath" "$P")
  case "$b" in
    *impleHDA*|*AppleALC*) $PB -c "Set :Kernel:Add:$i:Enabled false" "$P"; echo "無効化: $b" ;;
    "$KNAME") FOUND=$i ;;
  esac
  i=$((i+1))
done

if [ "$FOUND" -ge 0 ]; then
  $PB -c "Set :Kernel:Add:$FOUND:Enabled true" "$P"
  echo "既に登録済みのため有効化のみ行いました"
else
  $PB \
   -c "Add :Kernel:Add:$i dict" \
   -c "Add :Kernel:Add:$i:Arch string Any" \
   -c "Add :Kernel:Add:$i:BundlePath string $KNAME" \
   -c "Add :Kernel:Add:$i:Comment string VoodooHDA" \
   -c "Add :Kernel:Add:$i:Enabled bool true" \
   -c "Add :Kernel:Add:$i:ExecutablePath string Contents/MacOS/$EXE" \
   -c "Add :Kernel:Add:$i:MinKernel string" \
   -c "Add :Kernel:Add:$i:MaxKernel string" \
   -c "Add :Kernel:Add:$i:PlistPath string Contents/Info.plist" "$P"
fi

echo
echo "登録状況:"
$PB -c "Print :Kernel:Add" "$P" | grep -E "BundlePath|Enabled"
echo
echo "完了。再起動して確認してください。"
echo "パニック時はバックアップ($BK)から EFI を戻せます。"
pause
