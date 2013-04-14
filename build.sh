#!/bin/bash -e

msg() {
    echo
    echo ==== $* ====
    echo
}

# -----------------------

. build-config

TOOLS_DIR=`dirname "$0"`
MAKE=$TOOLS_DIR/make.sh

# -----------------------

ZIP=$TARGET_DIR/$VERSION.zip
SHA1=$TOOLS_DIR/sha1.sh
FTP=$LOCAL_BUILD_DIR/ftp.sh
UPDATE_ROOT=$LOCAL_BUILD_DIR/update
KEYS=$LOCAL_BUILD_DIR/keys
CERT=$KEYS/certificate.pem
KEY=$KEYS/key.pk8
ANYKERNEL=$LOCAL_BUILD_DIR/kernel
GLOBAL=$LOCAL_BUILD_DIR/global
POSTBOOT=$LOCAL_BUILD_DIR/postboot
VIDEOFIX=$LOCAL_BUILD_DIR/videofix
ZIMAGE=arch/arm/boot/zImage
GOVERNOR=CONFIG_CPU_FREQ_DEFAULT_GOV_$DEFAULT_GOVERNOR
SCHEDULER=CONFIG_DEFAULT_$DEFAULT_SCHEDULER

msg Building: $VERSION
echo "   Defconfig:       $DEFCONFIG"
echo "   Local build dir: $LOCAL_BUILD_DIR"
echo "   Target dir:      $TARGET_DIR"
echo "   Tools dir:       $TOOLS_DIR"
echo
echo "   Target system partition: $SYSTEM_PARTITION"
echo

if [ -e $CERT -a -e $KEY ]
then
    msg Reusing existing $CERT and $KEY
else
    msg Regenerating keys, pleae enter the required information.

    (
	mkdir -p $KEYS
	cd $KEYS
	openssl genrsa -out key.pem 1024 && \
	openssl req -new -key key.pem -out request.pem && \
	openssl x509 -req -days 9999 -in request.pem -signkey key.pem -out certificate.pem && \
	openssl pkcs8 -topk8 -outform DER -in key.pem -inform PEM -out key.pk8 -nocrypt
    )
fi

if [ -e $UPDATE_ROOT ]
then
    rm -rf $UPDATE_ROOT
fi

if [ -e $LOCAL_BUILD_DIR/update.zip ]
then
    rm -f $LOCAL_BUILD_DIR/update.zip
fi

$MAKE $DEFCONFIG

perl -pi -e 's/(CONFIG_LOCALVERSION="[^"]*)/\1-'"$VERSION"'"/' .config
echo "$GOVERNOR=y" >> .config
echo "$SCHEDULER=y" >> .config
SCHEDULER=CONFIG_IOSCHED_$DEFAULT_SCHEDULER
echo "$SCHEDULER=y" >> .config

$MAKE -j$N_CORES

msg Kernel built successfully, building $ZIP

mkdir -p $UPDATE_ROOT/system/lib/modules
find . -name '*.ko' -exec cp {} $UPDATE_ROOT/system/lib/modules/ \;

mkdir -p $UPDATE_ROOT/META-INF/com/google/android
cp $TOOLS_DIR/update-binary $UPDATE_ROOT/META-INF/com/google/android

cp build-config $LOCAL_BUILD_DIR/build-config

$SHA1

SUM=`sha1sum $ZIMAGE | cut --delimiter=' ' -f 1`
 
(
    cat <<EOF
$BANNER
EOF
  sed -e "s|@@SYSTEM_PARTITION@@|$SYSTEM_PARTITION|" \
      -e "s|@@FLASH_BOOT@@|$FLASH_BOOT|" \
      -e "s|@@SUM@@|$SUM|" \
      < $TOOLS_DIR/updater-script
) > $UPDATE_ROOT/META-INF/com/google/android/updater-script

mkdir -p $UPDATE_ROOT/kernel
mkdir -p $UPDATE_ROOT/global
mkdir -p $UPDATE_ROOT/postboot
mkdir -p $UPDATE_ROOT/videofix
cp $ZIMAGE $ANYKERNEL
cp $ANYKERNEL/* $UPDATE_ROOT/kernel
cp $GLOBAL/* $UPDATE_ROOT/global
cp $POSTBOOT/* $UPDATE_ROOT/postboot
cp $VIDEOFIX/* $UPDATE_ROOT/videofix

(
    cd $UPDATE_ROOT
    zip -r ../update.zip .
)
java -jar $TOOLS_DIR/signapk.jar $CERT $KEY $LOCAL_BUILD_DIR/update.zip $ZIP

$FTP
make mrproper
msg COMPLETE
