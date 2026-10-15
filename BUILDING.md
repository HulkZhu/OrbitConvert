# Building OrbitConvert

## Requirements

- macOS and full Xcode with the macOS 26 SDK or newer (the UI uses NSGlassEffectView).
- Apple Silicon is the tested architecture. The build targets the current machine;
  the Swift target alone does not prove all bundled dependencies support older OSes.
- libwebp 1.6.0 with libsharpyuv, built for your architecture. End users do not
  install either library: the packaging script embeds both.

You can obtain WebP from its official source:
https://developers.google.com/speed/webp/docs/compiling
Or use the Homebrew formula: https://formulae.brew.sh/formula/webp

For an existing Homebrew installation:

```sh
brew install webp flac libogg
# Build the bundled LAME source first; see Vendor/LAME/README.md.
ORBIT_LAME_LIB=/absolute/path/to/lame-3.100/libmp3lame/.libs zsh build.sh
```

For another WebP build, point to the folder containing `libwebp.7.dylib` and
`libsharpyuv.0.dylib`:

```sh
ORBIT_WEBP_LIB=/absolute/path/to/webp/lib zsh build.sh
```

Check the installed WebP version before redistributing. Included notices were
reviewed for 1.6.0; review notices again when changing versions. The build rejects
unexpected non-system dynamic dependencies instead of silently omitting them.

## Output

Additional bundled codecs: build LAME using Vendor/LAME/README.md and set
ORBIT_LAME_LIB to its library directory. This build currently takes libFLAC 1.5.0
and libogg 1.3.5 from /opt/homebrew/lib. End users need none of these installed.
UnRAR 7.3.1 is built automatically from Vendor/UnRAR source with Xcode's C++ tools.
Its extraction-only license is included in the app and source export.

The script compiles Swift, builds an .icns from Assets/AppIcon.png, embeds license
resources and WebP libraries, applies a local ad-hoc signature, checks the bundle,
and creates a ZIP in dist/. The final app path is printed at the end.

Run the packaged executable with `--self-test` and `--license-self-test`. SwiftPM
alone compiles sources but does not assemble app resources or bundled libraries.

This is not a Developer ID / notarized release. Do not ask users to disable
Gatekeeper. Configure proper signing/notarization separately for public binaries.

## Source export

`zsh export-source.sh --preview` creates a clean local source preview ZIP. It does
not publish anything. The default export requires a project LICENSE first.
Only the allowlisted source, assets, build scripts and public documents are
included; local test reports, historical apps and signing files are excluded.
