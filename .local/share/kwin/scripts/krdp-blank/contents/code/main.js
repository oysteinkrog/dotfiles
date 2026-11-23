// Keep the krdp-blank overlay out of screencasts and screenshots.
//
// krdp-blank (~/.dotfiles/misc/krdp-blank) paints every monitor black while an RDP client
// is connected, so nobody at the desk sees the session. KRDP streams a monitor through a
// KWin screencast, which leaves out windows with excludeFromCapture set, so the client
// still sees the desktop underneath. Without this script the client would get a black
// picture, so ~/bin/krdp-remote-mode loads it over D-Bus before it starts the overlay.
//
// KWin sets a Wayland window's resource class to its executable's file name.

function hide(window) {
    if (window.resourceClass === "krdp-blank" && !window.excludeFromCapture) {
        window.excludeFromCapture = true;
        print("krdp-blank: excluded from capture");
    }
}

workspace.windowList().forEach(hide);
workspace.windowAdded.connect(hide);
