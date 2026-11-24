// Ctrl-click on a web link in a terminal opens it in the Chrome profile that fits the terminal:
//   1. the terminal's label herdr.browser=work|personal, if set;
//   2. else the machine that runs the terminal: "home" opens personal, any other opens work.
// Chrome always starts on the desktop whose window was clicked (exec without `on`), through the
// launchers ~/.local/bin/chrome-work and ~/.local/bin/chrome-personal (dotfiles).
//
// A local terminal has no machine name in the click, so this desktop's own name is worked out
// from the machines it knows: one that knows "home" is not home, one that knows "office" is.
// ~/.config/herdr-browser (one word, work or personal) overrides it for local terminals.
import { exec, machines, terminals } from "herdr";

const PROFILES = ["work", "personal"];
const forMachine = (name) => (name === "home" ? "personal" : "work");

async function localProfile() {
  const r = await exec("sh", ["-c", 'cat "$HOME/.config/herdr-browser" 2>/dev/null']).catch(() => null);
  const set = r?.stdout?.trim();
  if (PROFILES.includes(set)) return set;
  const names = new Set(machines().map((m) => m.name).filter(Boolean));
  if (names.has("home")) return "work";
  if (names.has("office")) return "personal";
  return "work";
}

function label(source) {
  const want = [source.terminal, source.machine ? `${source.machine}/${source.terminal}` : null];
  const t = terminals().find((x) => want.includes(x.address));
  const b = t?.labels?.["herdr.browser"];
  return PROFILES.includes(b) ? b : null;
}

export async function handleLink({ link, source }) {
  if (link.kind !== "url") return "pass";
  const profile = label(source) ?? (source.machine ? forMachine(source.machine) : await localProfile());
  // setsid -f: Chrome may stay in front of its launcher when it was not running yet.
  const r = await exec("sh", ["-c", 'setsid -f "$HOME/.local/bin/chrome-$1" "$2" >/dev/null 2>&1 </dev/null', "sh", profile, link.url]);
  return r.code === 0 ? "handled" : "pass";
}
