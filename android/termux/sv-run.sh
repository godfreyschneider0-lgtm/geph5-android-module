#!/data/data/com.termux/files/usr/bin/sh
# geph5 manager under runit supervision (termux-services).
# Installed by geph5's android/termux/install.sh; do not edit in place,
# re-run the installer to change @@PAC_PORT@@.

# runsv inherits a minimal environment; make the install self-describing.
export HOME=/data/data/com.termux/files/home
export PREFIX=/data/data/com.termux/files/usr
export PATH="$PREFIX/bin:$PATH"

# Distinct PAC port so this Termux install can be connected at the same time
# as the root-module install (which keeps the historical 12223).
export GEPH5_PAC_PORT=@@PAC_PORT@@

# Optional verbosity knob: RUST_LOG="geph=trace" etc.
exec "$PREFIX/bin/geph5" manager 2>&1
