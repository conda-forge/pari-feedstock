#!/bin/bash

if [[ "$target_platform" == "win-64" ]]; then
  export PREFIX=$(cygpath -u ${PREFIX}/Library)
  cp ${BUILD_PREFIX}/Library/bin/win_bison.exe ${BUILD_PREFIX}/Library/bin/bison.exe
fi

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

# On Windows (MSYS2), conda-build's huge environment (hundreds of
# CONDA_BACKUP_*, __CONDA_SAVED_*, etc. variables) exceeds the exec()
# size limit, breaking xargs and other tools invoked by make.
# Work around this by running make through env -i with only the
# variables it actually needs.
if [[ "$target_platform" == win-* ]]; then
  echo "=== Environment debug info ==="
  echo "Total env vars: $(env | wc -l)"
  echo "Total env size (bytes): $(env | wc -c)"
  echo "Top variable prefixes:"
  env | cut -d= -f1 | sed 's/_[^_]*$//' | sort | uniq -c | sort -rn | head -20
  echo "Largest variables (top 20):"
  env | awk -F= '{printf "%6d %s\n", length($0), $1}' | sort -rn | head -20
  echo "==============================="
  _make() {
    env -i \
      PATH="$PATH" \
      HOME="$HOME" \
      SHELL="${SHELL:-/bin/bash}" \
      MSYSTEM="${MSYSTEM:-}" \
      MSYS2_PATH_TYPE="${MSYS2_PATH_TYPE:-}" \
      PREFIX="$PREFIX" \
      HOST="${HOST:-}" \
      make "$@"
  }
else
  _make() { make "$@"; }
fi

_make gp AR=${AR} RANLIB=${RANLIB} STRIP=${STRIP} || true

# Workaround: dlltool --export-all-symbols segfaults on Windows with many
# object files (binutils 2.45.x). If the .def files were not generated,
# create them manually using nm with proper DATA annotations.
if [[ "$target_platform" == win-* ]]; then
  cd O*
  if [ ! -f libpari.def ] || [ ! -f libpari_exe.def ]; then
    echo "=== dlltool segfault workaround: generating .def files via nm ==="
    # Extract OBJS list from Makefile (library objects only, not OBJSGP)
    OBJS=$(grep '^OBJS ' Makefile | sed 's/^OBJS *= *//' | sed 's/\$(_O)/.o/g')

    # Text/code symbols
    ${HOST}-nm -g --defined-only $OBJS 2>/dev/null | grep ' [T] ' | awk '{print $3}' | sort -u > _text_syms.txt
    # Data symbols (BSS, Data, Read-only) — must be marked DATA in .def
    ${HOST}-nm -g --defined-only $OBJS 2>/dev/null | grep ' [BDR] ' | awk '{print $3}' | sort -u > _data_syms.txt

    echo "Found $(wc -l < _text_syms.txt) text + $(wc -l < _data_syms.txt) data symbols"

    for deftype in lib exe; do
      if [ "$deftype" = "lib" ]; then
        deffile="libpari.def"
        echo "LIBRARY libpari" > "$deffile"
      else
        deffile="libpari_exe.def"
        echo "NAME libpari_exe" > "$deffile"
      fi
      echo "EXPORTS" >> "$deffile"
      i=1
      while read sym; do
        echo "    $sym @ $i" >> "$deffile"
        i=$((i + 1))
      done < _text_syms.txt
      while read sym; do
        if [ "$deftype" = "lib" ]; then
          echo "    $sym @ $i DATA" >> "$deffile"
        else
          echo "    $sym @ $i" >> "$deffile"
        fi
        i=$((i + 1))
      done < _data_syms.txt
    done

    rm -f _text_syms.txt _data_syms.txt
    echo "Generated libpari.def and libpari_exe.def"

    # Rebuild with the manually generated .def files
    _make gp AR=${AR} RANLIB=${RANLIB} STRIP=${STRIP}
  fi
  cd ..
fi

if [[ "${CONDA_BUILD_CROSS_COMPILATION:-}" != "1" ]]; then
    _make test-all
fi

_make install install-lib-sta AR=${AR} RANLIB=${RANLIB} STRIP=${STRIP}
cp "src/language/anal.h" "$PREFIX/include/pari/anal.h"

# Relocate Windows libraries from bin -> lib so that linkers find them
# in the conventional location.
if [[ "$target_platform" == win-* ]]; then
  mkdir -p "$PREFIX/lib"

  # Relocate static library (libpari.a) from bin to lib
  if [ -f "$PREFIX/bin/libpari.a" ]; then
    echo "Relocating static library libpari.a to /lib/"
    mv "$PREFIX/bin/libpari.a" "$PREFIX/lib/" || exit 1
  fi

  # Relocate import libraries (libpari*.dll.a) and create MSVC .lib files
  for implib in "$PREFIX"/bin/libpari*.dll.a; do
    [ -e "$implib" ] || continue
    basename=$(basename "$implib" .dll.a)
    echo "Relocating import library $implib to /lib/";
    mv "$implib" "$PREFIX/lib/" || exit 1

    echo "Generating lib file for $basename"
    gendef "$PREFIX/bin/$basename.dll"
    $HOST-dlltool -d "$basename.def" -l "$PREFIX/lib/$basename.lib"
  done
fi
