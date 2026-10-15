# LAME 3.100

Original source: https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
Project: https://lame.sourceforge.io/
License: GNU Library General Public License v2 or later; see ../../LAME_LICENSE.txt.

The unmodified source archive accompanies the distributed app in its Resources
directory. Only the encoder shared library is included, without the command-line
frontend or MP3 decoder. macOS supplies the decoder.

Build on the target architecture:

```
tar -xzf lame-3.100.tar.gz
cd lame-3.100
./configure --disable-frontend --disable-decoder --disable-static --enable-shared
make -j4
```

On current Apple linkers the upstream export list references disabled decoder
symbols. After compilation, link the encoder objects directly (no source patch):

```
clang -dynamiclib -install_name @rpath/libmp3lame.0.dylib -o libmp3lame/.libs/libmp3lame.0.dylib libmp3lame/.libs/{VbrTag,bitstream,encoder,fft,gain_analysis,id3tag,lame,mpglib_interface,newmdct,presets,psymodel,quantize,quantize_pvt,reservoir,set_get,tables,takehiro,util,vbrquantize,version}.o -lm
```

Set ORBIT_LAME_LIB to the resulting libmp3lame/.libs directory when running
OrbitConvert's build.sh. Library changes can be rebuilt and substituted in
Contents/Frameworks/libmp3lame.0.dylib; locally re-sign the library and app after
replacement. Reverse engineering for debugging modifications to this LGPL
library is permitted. OrbitConvert dynamically loads this separate library.
