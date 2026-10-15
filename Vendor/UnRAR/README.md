# UnRAR 7.3.1

Official archive: https://www.rarlab.com/rar/unrarsrc-7.3.1.tar.gz
SHA-256: 634900842a3737d9cc15bbcc71d4c74cc713437e0bca296a573424fe5f2660ab

The `unrar` directory is the unmodified upstream source. `OrbitUnRAR.cpp` is
the local streaming bridge. The build copies sources to `.build/UnRAR`, builds
the upstream RARDLL static library, and links it into libOrbitUnRAR.dylib.
Only this dylib is embedded in the app; no command-line RAR program is installed.

License: see `unrar/license.txt` and ../../UNRAR_LICENSE.txt. UnRAR is
source-available under its own extraction-only license, not MIT/BSD. Do not
use this code to create a RAR-compatible compressor or reconstruct proprietary
RAR compression algorithms. The complete required notice is retained in the
bridge source and THIRD_PARTY.md.

Archive bytes are decoded with RAR_TEST callbacks; UnRAR never writes archive
paths. Swift validates names, duplicates, sizes and deadlines, rejects links and
split volumes, stages bytes privately, and publishes only verified results.
Passwords are supplied in memory through callbacks, never command arguments.
