#!/bin/bash

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
unset with_readline_include with_readline_lib without_readline
unset with_gmp_include with_gmp_lib without_gmp
unset dfltbindir dfltdatadir dfltemacsdir dfltincludedir
unset dfltlibdir dfltmandir dfltsysdatadir dfltobjdir

if [[ "$variant" == "pthread" ]]; then
  CONFIG_ARGS="--mt=pthread"
fi

chmod +x Configure
set -x
./Configure --prefix="$PREFIX" \
        --with-readline="$PREFIX" \
        --with-gmp="$PREFIX" \
        --with-runtime-perl="$PREFIX/bin/perl" \
        --kernel=gmp \
        --graphic=none $CONFIG_ARGS

make gp

if [ "$target_platform" == "linux-64" ]
then
    make test-all;
fi

make install install-lib-sta
cp "src/language/anal.h" "$PREFIX/include/pari/anal.h"
