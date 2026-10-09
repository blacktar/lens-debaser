Lens Debaser — Apple Silicon

1. Fully quit DaVinci Resolve.
2. Double-click “Install Lens Debaser.command”.
3. Approve the administrator-password request.
4. Launch Resolve and find Lens Debaser in the OpenFX library.

If macOS blocks installation

The current release is not yet notarized by Apple. If macOS blocks the
installer, try opening it once, then go to System Settings > Privacy & Security
and choose Open Anyway for the installer. Confirm Open and authenticate when
requested.

Alternatively, for the release you downloaded from the official Lens Debaser
GitHub repository, open Terminal and run:

    xattr -cr "/path/to/Lens-Debaser-release-folder"

Replace the quoted path with the extracted release folder's actual path; you
can drag that folder from Finder into Terminal after typing `xattr -cr `.
Then open “Install Lens Debaser.command” again. You can also target a specific
installer or plug-in bundle instead of the folder. This removes quarantine and
other extended attributes only from the specified path; it does not disable
Gatekeeper system-wide. The installer handles the installed plug-in bundle.

User guide:
https://vidarandersen.com/dmz/lens-debaser-ofx/

Lens Debaser is distributed under CC BY-NC-SA 4.0. See the online user guide
and the repository LICENSE file for the project terms. Third-party
acknowledgements and the OpenFX BSD 3-Clause notice are in
THIRD-PARTY-NOTICES.txt.
