#!/bin/bash
# VoodooHDA を OpenCore の EFI に導入する（EFIバックアップ付き）
set -e

URL="https://github.com/CloverHackyColor/VoodooHDA/releases/download/v3.7.1-alpha/VoodooHDA-v3.7.1-RELEASE-alpha-d9e642d.zip"
PB=/usr/libexec/PlistBuddy

pause() { echo; read -n 1 -s -r -p "何かキーを押すと閉じます..."; echo; }
trap 'echo "エラーで中断しました"; pause' ERR

# EFI のマウント
if [ ! -d /Volumes/EFI/EFI/OC ]; then
  EFI_ID=disk0s2
  sudo diskutil mount "$EFI_ID"
fi

OC=/Volumes/EFI/EFI/OC
P="$OC/config.plist"
[ -f "$P" ] || { echo "config.plist が見つかりません"; pause; exit 1; }

# バックアップ
BK=~/EFI_backup_$(date +%m%d%H%M)
cp -R /Volumes/EFI/EFI "$BK"
cp "$P" "$P.bak_$(date +%m%d%H%M)"
echo "バックアップ: $BK （config.plist は EFI 内にも .bak を作成）"

# ダウンロードと展開
cd ~/Downloads
curl -L -o VoodooHDA.zip "$URL"
rm -rf VoodooHDA_x
unzip -q VoodooHDA.zip -d VoodooHDA_x
K=$(find VoodooHDA_x -name VoodooHDA.kext -not -path "*__MACOSX*" | head -1)
[ -n "$K" ] || { echo "VoodooHDA.kext が見つかりません"; pause; exit 1; }
EXE=$(ls "$K/Contents/MacOS" | head -1)
echo "kext: $K / exe: $EXE"

rm -rf "$OC/Kexts/VoodooHDA.kext"
cp -R "$K" "$OC/Kexts/"

# Kernel>Add を走査: SimpleHDA を無効化、既存の VoodooHDA を削除、件数を取得
i=0
while $PB -c "Print :Kernel:Add:$i:BundlePath" "$P" >/dev/null 2>&1; do
  b=$($PB -c "Print :Kernel:Add:$i:BundlePath" "$P")
  case "$b" in
    *impleHDA*|*AppleALC*) $PB -c "Set :Kernel:Add:$i:Enabled false" "$P"; echo "無効化: $b" ;;
  esac
  i=$((i+1))
done

# 既に VoodooHDA が登録されていないか確認
for ((j=0; j<i; j++)); do
  b=$($PB -c "Print :Kernel:Add:$j:BundlePath" "$P")
  if [ "$b" = "VoodooHDA.kext" ]; then
    $PB -c "Set :Kernel:Add:$j:Enabled true" "$P"
    echo "既に登録済みのため有効化のみ行いました"
    pause; exit 0
  fi
done

# VoodooHDA を追加
$PB \
 -c "Add :Kernel:Add:$i dict" \
 -c "Add :Kernel:Add:$i:Arch string Any" \
 -c "Add :Kernel:Add:$i:BundlePath string VoodooHDA.kext" \
 -c "Add :Kernel:Add:$i:Comment string VoodooHDA" \
 -c "Add :Kernel:Add:$i:Enabled bool true" \
 -c "Add :Kernel:Add:$i:ExecutablePath string Contents/MacOS/$EXE" \
 -c "Add :Kernel:Add:$i:MinKernel string" \
 -c "Add :Kernel:Add:$i:MaxKernel string" \
 -c "Add :Kernel:Add:$i:PlistPath string Contents/Info.plist" "$P"

echo "完了。再起動して確認してください。"
echo "パニック時はバックアップ($BK)から EFI を戻せます。"
pause
