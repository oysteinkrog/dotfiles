// Freeze and Thaw for a whole space (krog layout). Opened by space-folders:
//   props { menu: spaceId }    the space's right-click menu: Freeze or Thaw, then Herdr's own items
//   props { confirm: spaceId } the dialog that lists what Freeze stops, and does it
// The work is done by freeze.sh beside this file, on the machine that owns the space, which
// keeps the frozen state in ~/.local/state/space-freeze/<space>.json there. This mod mirrors
// that into shared("space-freeze.frozen") ({ spaceId: { count, at } }) for the spaces list.
//
// Freeze stops the programs (they exit: Claude is resumed later with --resume); shells and tabs
// stay. Not the cgroup freeze of freeze-job.sh. Nothing freezes or thaws on its own.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { run, props, closeOverlay, openOverlay, theme, spaces, panes, exec, shared, setShared, notify, appHome } from "herdr";

const KEY = "space-freeze.frozen";

const machineOf = (space) => space?.machine ?? null;
const localId = (space) => (space.machine ? space.id.slice(space.machine.length + 1) : space.id);

// freeze.sh on the space's machine; resolves with its JSON output.
async function freezeSh(space, ...args) {
  const on = machineOf(space);
  // Here: this app's own folder. Another machine: its herdr-app folder (herdr-setup installs the mod there too).
  const script = on ? '"${HERDR_APP_HOME:-$HOME/.config/herdr-app}/mods/space-freeze/freeze.sh"' : `"${appHome()}/mods/space-freeze/freeze.sh"`;
  const r = await exec("bash", ["-c", `${script} "$@"`, "freeze.sh", ...args], { on, timeout: 120000 });
  let out = null;
  try { out = JSON.parse(r.stdout); } catch { /* not JSON */ }
  if (r.code !== 0 || out === null) throw new Error(out?.error ?? (r.stderr.trim() || `freeze.sh ${args[0]} failed`));
  return out;
}

// Re-read the frozen spaces of one machine into the shared mirror.
export async function refresh(machine) {
  const any = spaces().find((s) => (s.machine ?? null) === machine) ?? { machine };
  const list = await freezeSh(any, "list");
  const prefix = machine ? `${machine}/` : "";
  const mirror = Object.fromEntries(Object.entries(shared(KEY) ?? {}).filter(([id]) => (id.includes("/") ? id.split("/")[0] : null) !== machine));
  for (const f of list) mirror[prefix + f.space] = { count: f.count, at: f.frozen_at };
  setShared(KEY, mirror);
}

export const isFrozen = (id) => Boolean((shared(KEY) ?? {})[id]);

// Where a space is now, for the worktree items (as Herdr's menu does).
function place(s) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return panes().find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}

async function checkout(folder, on) {
  const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd: folder, on });
  const common = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: folder, on });
  if (top.code !== 0 || common.code !== 0) return null;
  return common.stdout.trim() === `${top.stdout.trim()}/.git` ? "main" : "linked";
}

const what = (e) => (e.kind === "claude" ? "Claude Code" : e.kind === "codex" ? "Codex" : (e.argv ?? []).join(" ") || "program");

async function thaw(space) {
  try {
    const r = await freezeSh(space, "thaw", localId(space));
    notify({ title: `Thawed ${space.name}`, body: r.left ? `${r.thawed} started again, ${r.left} could not start (their terminal is busy).` : `${r.thawed} started again.`, level: r.left ? "warning" : "success" });
  } catch (e) {
    notify({ title: `Could not thaw ${space.name}`, body: String(e.message ?? e), level: "error" });
  }
  await refresh(machineOf(space)).catch(() => null);
}

export default class SpaceFreeze extends View {
  init(_props, cx) {
    const p = props() ?? {};
    this.space = spaces().find((s) => s.id === (p.menu ?? p.confirm)) ?? null;
    this.at = 0;
    this.handle = cx.focus_handle();
    this.handle.focus();
    if (!this.space) return;
    if (p.menu) {
      this.git = null;
      const folder = place(this.space);
      cx.spawn(async (cx) => {
        if (folder) this.git = await checkout(folder, machineOf(this.space)).catch(() => null);
        // Another Herdr window may have frozen or thawed it.
        await refresh(machineOf(this.space)).catch(() => null);
        cx.notify();
      });
    } else {
      this.plan = null;
      this.error = null;
      this.working = false;
      cx.spawn(async (cx) => {
        try { this.plan = await freezeSh(this.space, "plan", localId(this.space)); } catch (e) { this.error = String(e.message ?? e); }
        cx.notify();
      });
    }
  }

  items() {
    const s = this.space;
    const frozen = isFrozen(s.id);
    return [
      frozen ? ["Thaw space", () => thaw(s)] : ["Freeze space…", () => openOverlay({ mod: "space-freeze", kind: "dialog", width: 480, props: { confirm: s.id } })],
      ["Rename", () => run("space.rename", { id: s.id })],
      ...(this.git ? [["New worktree", () => this.worktree("new")], ["Open worktree", () => this.worktree("open")]] : []),
      ...(this.git === "linked" ? [["Remove worktree", () => this.worktree("remove")]] : []),
      ["Close", () => run("space.close", { id: s.id })],
    ];
  }

  worktree(action) {
    openOverlay({ mod: "worktree", kind: "dialog", ...(action === "open" ? { width: 560, height: 480 } : { width: 440, height: 260 }), props: { space: this.space.id, action } });
  }

  choose(i) {
    const it = this.items()[i];
    if (!it) return;
    closeOverlay(props()?.overlay);
    it[1]();
  }

  menuView(t) {
    const list = this.items();
    return v_flex().id("space-freeze-menu").track_focus(this.handle).w_full().min_h(0).p(5).bg(t.popover).text_size(12.8)
      .on_key_down((e, cx) => {
        if (e.key === "down") this.at = (this.at + 1) % list.length;
        else if (e.key === "up") this.at = (this.at + list.length - 1) % list.length;
        else if (e.key === "enter") this.choose(this.at);
        else if (e.key === "escape") closeOverlay(props().overlay);
        else return;
        cx.notify();
      })
      .children(list.map((it, i) => v_flex()
        .when(i === 1 || it[0] === "Close", (el) => el.child(div().mx(7).my(4).h(1).bg(t.border)))
        .child(h_flex().id(`sf-${i}`).h(31).px(8).gap(9).rounded(7).items_center().text_color(t.foreground)
          .when(i === this.at, (el) => el.bg(t.selected))
          .hover((s) => s.bg(t.hover))
          .on_click(() => this.choose(i))
          .when(i === 0, (el) => el.child(svg("mods/space-freeze/snowflake.svg").size(14).flex_none().text_color(t.ansi4 ?? t.muted)))
          .when(i !== 0, (el) => el.child(div().size(14).flex_none()))
          .child(div().flex_1().child(it[0])))));
  }

  async doFreeze(cx) {
    this.working = true;
    cx.notify();
    const s = this.space;
    try {
      const r = await freezeSh(s, "freeze", localId(s), s.name);
      notify({ title: `Froze ${s.name}`, body: r.failed.length ? `${r.frozen} stopped. Could not stop: ${r.failed.join(", ")}.` : `${r.frozen} stopped. Right-click the space and pick Thaw to start them again.`, level: r.failed.length ? "warning" : "success" });
      closeOverlay(props().overlay);
    } catch (e) {
      this.error = String(e.message ?? e);
      this.working = false;
    }
    await refresh(machineOf(s)).catch(() => null);
    cx.notify();
  }

  confirmView(t) {
    const overlay = props().overlay;
    const button = (key, label, primary, enabled, action) => h_flex().id(key).h(32).px(14).flex_none().items_center().rounded(8).border_1()
      .border_color(primary ? t.solid : t.input).bg(primary ? t.solid : t.raised).text_color(primary ? t.solid_foreground : t.foreground)
      .text_size(12.5).font_medium().when(!enabled, (el) => el.opacity(0.4)).when(enabled, (el) => el.cursor_pointer().hover((s) => s.opacity(0.88)).on_click(action))
      .child(label);
    const progs = (this.plan?.terminals ?? []).filter((e) => e.kind !== "shell");
    const busy = progs.filter((e) => e.status === "working" || e.status === "blocked");
    const can = Boolean(this.plan) && progs.length > 0 && busy.length === 0 && !this.working;
    const row = (e) => h_flex().gap(8).items_center().min_w(0)
      .child(div().flex_none().text_color(t.foreground).child(what(e)))
      .child(div().min_w(0).truncate().text_color(t.dim).child(e.name ?? e.address))
      .when(Boolean(e.status), (el) => el.child(div().flex_none().text_color(busy.includes(e) ? t.ansi1 : t.dim).child(e.status)));
    let body;
    if (this.error) body = div().text_color(t.ansi1).child(this.error);
    else if (!this.plan) body = div().text_color(t.dim).child("Looking at what runs in this space…");
    else if (!progs.length) body = div().text_color(t.dim).child("Nothing runs in this space: there is nothing to freeze.");
    else body = v_flex().gap(6)
      .child(div().text_color(t.muted).child("These programs will exit. Their shells and tabs stay. Thaw starts them again in the same panes (Claude Code with --resume)."))
      .child(v_flex().gap(4).p(10).rounded(8).bg(t.background).children(progs.map(row)))
      .when(busy.length > 0, (el) => el.child(div().text_color(t.ansi1).child("An agent here is working or waiting for an answer. Freeze is off until it is idle.")));
    return v_flex().id("space-freeze-confirm").track_focus(this.handle).w_full().p(20).gap(14).bg(t.popover).text_color(t.foreground).text_size(12.5)
      .on_key_down((e, cx) => { if (e.key === "escape") { closeOverlay(overlay); cx.stop_propagation(); } })
      .child(h_flex().gap(8).items_center()
        .child(svg("mods/space-freeze/snowflake.svg").size(16).text_color(t.ansi4 ?? t.foreground))
        .child(div().text_size(15).font_semibold().child(`Freeze ${this.space.name}`)))
      .child(body)
      .child(h_flex().pt(4).gap(8).justify_end()
        .child(button("sf-cancel", "Cancel", false, true, () => closeOverlay(overlay)))
        .child(button("sf-freeze", this.working ? "Freezing…" : "Freeze", true, can, (_e, cx) => this.doFreeze(cx))));
  }

  render() {
    const t = theme();
    if (!this.space) return div().p(10).bg(t.popover).text_color(t.dim).child("That space is gone.");
    return (props() ?? {}).menu ? this.menuView(t) : this.confirmView(t);
  }
}
