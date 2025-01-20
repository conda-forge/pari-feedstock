#!/bin/bash

if [[ "$target_platform" == "win-64" ]]; then
  export PREFIX=${PREFIX}/Library
  cp ${BUILD_PREFIX}/Library/bin/win_bison.exe ${BUILD_PREFIX}/Library/bin/bison.exe
fi

export LD_LIBRARY_PATH="$PREFIX/lib:$LD_LIBRARY_PATH"
export CFLAGS="-g $CFLAGS"
export CXXFLAGS="-g $CXXFLAGS"
# pari sends LDFLAGS to LD if set, but LDFLAGS are meant for the compiler to pass to linker.
unset LD

unset GP_INSTALL_PREFIX # we do not want this to be set by the user

# In addition, a lot of variables used (internally) by PARI might un-
# intentionally get their values from the "global" environment, so it's
# safer to clear them here (not further messing up PARI's scripts):
unset static tune timing_fun error
unset enable_tls
unset with_fltk with_qt
unset with_ncurses_lib
unset with_readline_include with_readline_lib without_readline readline
unset with_gmp_include with_gmp_lib without_gmp
unset dfltbindir dfltdatadir dfltemacsdir dfltincludedir
unset dfltlibdir dfltmandir dfltsysdatadir dfltobjdir

if [[ "$variant" == "pthread" ]]; then
  CONFIG_ARGS="--mt=pthread"
fi

if [[ "$target_platform" == "win-"* ]]; then
  CONFIG_ARGS="$CONFIG_ARGS --without-readline"
else
  CONFIG_ARGS="$CONFIG_ARGS --with-readline=$PREFIX"
fi

case $target_platform in
  osx-64)
    export target_host="x86_64-darwin" ;;
  osx-arm64)
    export target_host="arm64-darwin" ;;
  linux-ppc64le)
    export target_host="ppc64le-linux" ;;
  linux-aarch64)
    export target_host="aarch64-linux" ;;
  linux-64)
    export target_host="x86_64-linux" ;;
  win-64)
    export target_host="x86_64-mingw" ;;
  *)
    echo "Unknown architecture. Fix build.sh"
    exit 1
    ;;
esac

chmod +x Configure
set -x
./Configure --prefix="$PREFIX" \
        --with-gmp="$PREFIX" \
        --with-runtime-perl="$PREFIX/bin/perl" \
        --kernel=gmp \
        --host=$target_host \
        --graphic=none $CONFIG_ARGS

echo "paricfg.h"
find . -name "paricfg.h" -exec cat {} +

echo "Makefile"
find Omingw* -name "Makefile" -exec cat {} +

make gp

if [ "$target_platform" == "linux-64" ]
then
    make test-all;
fi

make install install-lib-sta
cp "src/language/anal.h" "$PREFIX/include/pari/anal.h"
