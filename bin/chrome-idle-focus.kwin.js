// KWin script for chrome-idle-close. Loaded by chrome-idle-close through
// org.kde.KWin /Scripting under the plugin name "chrome-idle-focus".
// It writes one journal line each time the active window changes, plus one
// line for the current window when it loads:
//   chrome-idle-focus pid=<pid or -1> class=<resourceClass>
// chrome-idle-close reads these lines with journalctl.
function report(w) {
    var pid = w ? w.pid : -1;
    var cls = w ? String(w.resourceClass) : "";
    console.info("chrome-idle-focus pid=" + pid + " class=" + cls);
}
report(workspace.activeWindow);
workspace.windowActivated.connect(report);
