# GitHub publication checklist

You can publish source code before an App Store release. Publishing source does
not require Apple Developer ID signing; distributing a usable public Mac binary
is a separate signing/notarization workflow.

## Confirmed project license

- Original code: MIT, Copyright (c) 2026 CHENGHAOZHU.
- GitHub username supplied by owner: CHENGHAOZHU. No account access verified.
- Artwork is excluded from the original-code grant until separately authorized.
- Third-party components keep their own licenses, including LGPL and UnRAR.
- Repository creation, public visibility and upload remain separate actions.

## Prepared locally

- Third-party MIT/BSD copyright, license texts and WebP patent grant.
- App-visible offline notices, original file headers and upstream revision.
- App icon, build instructions and source-only export allowlist.
- .gitignore excludes builds, local test reports, credentials and old packages.

## Before clicking Publish

1. Add the approved LICENSE and update README.md's licensing section.
2. Export a fresh source ZIP without --preview; review every included filename.
3. Upload only that source directory, not the enclosing development workspace.
4. Do not upload .p12/.p8/private keys, developer tokens, .env, user documents,
   generated test results, historical LibreOffice builds or the local work folder.
5. Create the repository under your own account with the approved visibility.
   A public repository is not automatically open source without a license.
6. Keep source in the repository; put deliberately released, verified app ZIPs
   in GitHub Releases, not in source-control history.
7. Review dependency licenses again whenever upgrading or adding components.

No repository has been created or uploaded by this task.

GitHub guidance:
https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository
