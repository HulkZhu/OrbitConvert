# App icon provenance

## Current icon — v0.19

Version 0.19 increases ring stroke width from 30 to 42 and reduces neighbor center spacing from 218 to 208 on the 1024-pixel canvas, leaving a 10-pixel gap between rings. The geometry and palette are otherwise unchanged.

AppIcon.png now contains a deterministic geometric design drawn by DrawHoneycomb.swift: seven white circular outlines in a hexagonal cluster on a dark, softly rounded hexagon, with transparent outer margins. The user requested the same visual vocabulary as the existing menu-bar honeycomb symbol. The artwork is constructed from circles and a polygon; no SF Symbols vector or bitmap is exported into the app icon. No fonts or third-party image assets are used. This geometric artwork replaces the previous generated image, whose prompts are retained below only as history. No trademark clearance or exclusivity is asserted.

Packaging uses sips for resizing and PackIcon.swift for the ICNS container, validating every representation with ImageIO.

## Historical v0.17 icon (no longer used)

The PNG is a newly generated bitmap concept for OrbitConvert, created using the built-in image generation tool. No competitor icon, logo or screenshot was supplied as a reference. Generative output is not a trademark search or a guarantee of exclusivity.

The macOS .icns is produced from this PNG with Apple's sips and iconutil during packaging. No third-party fonts or brand logos are embedded.

## Initial prompt

Use case: logo-brand. Asset type: final macOS desktop app icon for OrbitConvert, a local file-format converter with a circular format chooser. Create ONE original production-ready icon, square 1024x1024 canvas. Subject: a bold simple folded document silhouette nested inside a single expressive orbital loop; one end of the loop subtly transforms into a second document edge, suggesting conversion, not a generic refresh button. Style: premium clean dimensional liquid glass with crisp refractive beveled edges, restrained luminous highlights, strong readable silhouette at 32 pixels. Front-facing centered composition, rounded-square tile occupying about 86% of canvas, comfortable equal outer padding, genuinely transparent pixels outside the rounded tile. Rich contrasting cool translucent glass and a softly illuminated neutral tile; restrained colors, no busy background, no tiny decorative dots. No text, letters, format labels, watermark, brand marks or existing app logos. No multiple concepts, no mockup device, no perspective view. This must be a new original design, not a recreation of any competitor icon.

## Refinement prompts

Use case: precise-object-edit. Edit this macOS app icon only to clean the outer silhouette. Preserve the central glass documents, orbital arrows, colors, lighting, layout and rounded-square tile exactly. Remove ALL scattered white specks, jagged fragments, mottled residue and irregular glow outside the rounded-square tile. The entire outside margin must be truly transparent with clean smooth anti-aliased edges, not a checkerboard or painted background. Keep the tile centered with equal padding and a smooth continuous perimeter. Output one square production icon, no text, no new shapes.

Use case: precise-object-edit. Refine the provided OrbitConvert macOS icon. Keep the recognizable two folded documents and orbiting conversion arrows, centered composition, glass material and overall silhouette. Change the tile behind them to a SOLID deep midnight-blue rounded square with a perfectly smooth edge. Make the front document pale icy translucent glass so it contrasts against the navy tile; arrows remain luminous cyan-blue. Remove every floating fleck, white residue, outer glow, cloud and rough edge. Use a clean hard silhouette with only anti-aliasing, absolutely no shadow or bloom outside the tile. Outside the tile is true transparent alpha with a clear uniform empty margin. One finished square app icon, no text, no labels, no mockup.

## License decision

The project's owner has not yet confirmed the project's license or copyright attribution. This provenance note does not grant a separate trademark license. Resolve code/artwork licensing before publishing the repository.
