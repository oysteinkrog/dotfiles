// krdp-blank: paint every monitor black while an RDP client is connected.
//
// One wlr-layer-shell surface per output, on the overlay layer, with an empty input region,
// so clicks and keys still reach the windows underneath. It also asks KWin to keep the
// surface visible over the lock screen (kde_lockscreen_overlay_v1), so a session that locks
// during RDP stays black at the desk too.
//
// The black surface must not reach the RDP picture. The KWin script krdp-blank
// (~/.local/share/kwin/scripts/krdp-blank) sets excludeFromCapture on every window whose
// resource class is "krdp-blank", which is this binary's file name. KWin then leaves it
// out of screencasts and screenshots, and KRDP streams the desktop underneath.
//
// Started and stopped by ~/bin/krdp-remote-mode. Dies with its parent (PR_SET_PDEATHSIG).
// Build: ~/bin/krdp-remote-mode builds it on demand with build.sh in this folder.

#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <unistd.h>
#include <wayland-client.h>

#include "kde-lockscreen-overlay-v1-client-protocol.h"
#include "single-pixel-buffer-v1-client-protocol.h"
#include "viewporter-client-protocol.h"
#include "wlr-layer-shell-unstable-v1-client-protocol.h"

struct blank {
    struct wl_list link;
    uint32_t global_name;
    struct wl_output *output;
    struct wl_surface *surface;
    struct zwlr_layer_surface_v1 *layer;
    struct wp_viewport *viewport;
    char name[64];
};

static struct wl_compositor *compositor;
static struct zwlr_layer_shell_v1 *layer_shell;
static struct wp_viewporter *viewporter;
static struct wp_single_pixel_buffer_manager_v1 *pixel_manager;
static struct kde_lockscreen_overlay_v1 *lock_overlay;
static struct wl_buffer *black;
static struct wl_list blanks;
static int ready;  // globals bound; outputs announced after this get a surface at once

static void destroy_surface(struct blank *b)
{
    if (b->viewport) wp_viewport_destroy(b->viewport);
    if (b->layer) zwlr_layer_surface_v1_destroy(b->layer);
    if (b->surface) wl_surface_destroy(b->surface);
    b->viewport = NULL;
    b->layer = NULL;
    b->surface = NULL;
}

static void layer_configure(void *data, struct zwlr_layer_surface_v1 *layer, uint32_t serial,
                            uint32_t width, uint32_t height)
{
    struct blank *b = data;
    zwlr_layer_surface_v1_ack_configure(layer, serial);
    if (width == 0 || height == 0) return;
    wl_surface_attach(b->surface, black, 0, 0);
    wp_viewport_set_destination(b->viewport, (int32_t)width, (int32_t)height);
    wl_surface_damage_buffer(b->surface, 0, 0, INT32_MAX, INT32_MAX);
    wl_surface_commit(b->surface);
    fprintf(stderr, "krdp-blank: %s black at %ux%u\n", b->name[0] ? b->name : "output", width, height);
}

static void layer_closed(void *data, struct zwlr_layer_surface_v1 *layer)
{
    // The output went away or was turned off. A new global brings it back.
    destroy_surface(data);
}

static const struct zwlr_layer_surface_v1_listener layer_listener = {
    .configure = layer_configure,
    .closed = layer_closed,
};

static void create_surface(struct blank *b)
{
    b->surface = wl_compositor_create_surface(compositor);
    struct wl_region *none = wl_compositor_create_region(compositor);
    wl_surface_set_input_region(b->surface, none);  // empty: input passes through
    wl_region_destroy(none);
    struct wl_region *all = wl_compositor_create_region(compositor);
    wl_region_add(all, 0, 0, INT32_MAX, INT32_MAX);
    wl_surface_set_opaque_region(b->surface, all);
    wl_region_destroy(all);
    b->viewport = wp_viewporter_get_viewport(viewporter, b->surface);
    b->layer = zwlr_layer_shell_v1_get_layer_surface(layer_shell, b->surface, b->output,
                                                     ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "krdp-blank");
    if (lock_overlay) kde_lockscreen_overlay_v1_allow(lock_overlay, b->surface);  // before the first map
    zwlr_layer_surface_v1_set_anchor(b->layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                                                   ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_size(b->layer, 0, 0);
    zwlr_layer_surface_v1_set_exclusive_zone(b->layer, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(b->layer, 0 /* none */);
    zwlr_layer_surface_v1_add_listener(b->layer, &layer_listener, b);
    wl_surface_commit(b->surface);
}

static void output_geometry(void *d, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph,
                            int32_t sub, const char *make, const char *model, int32_t transform) {}
static void output_mode(void *d, struct wl_output *o, uint32_t flags, int32_t w, int32_t h, int32_t r) {}
static void output_done(void *d, struct wl_output *o) {}
static void output_scale(void *d, struct wl_output *o, int32_t f) {}
static void output_name(void *data, struct wl_output *o, const char *name)
{
    struct blank *b = data;
    snprintf(b->name, sizeof b->name, "%s", name);
}
static void output_description(void *d, struct wl_output *o, const char *desc) {}

static const struct wl_output_listener output_listener = {
    .geometry = output_geometry,
    .mode = output_mode,
    .done = output_done,
    .scale = output_scale,
    .name = output_name,
    .description = output_description,
};

static void global_add(void *data, struct wl_registry *reg, uint32_t name, const char *iface, uint32_t version)
{
    if (!strcmp(iface, wl_compositor_interface.name)) {
        compositor = wl_registry_bind(reg, name, &wl_compositor_interface, 4);
    } else if (!strcmp(iface, zwlr_layer_shell_v1_interface.name)) {
        layer_shell = wl_registry_bind(reg, name, &zwlr_layer_shell_v1_interface, version < 4 ? version : 4);
    } else if (!strcmp(iface, wp_viewporter_interface.name)) {
        viewporter = wl_registry_bind(reg, name, &wp_viewporter_interface, 1);
    } else if (!strcmp(iface, wp_single_pixel_buffer_manager_v1_interface.name)) {
        pixel_manager = wl_registry_bind(reg, name, &wp_single_pixel_buffer_manager_v1_interface, 1);
    } else if (!strcmp(iface, kde_lockscreen_overlay_v1_interface.name)) {
        lock_overlay = wl_registry_bind(reg, name, &kde_lockscreen_overlay_v1_interface, 1);
    } else if (!strcmp(iface, wl_output_interface.name) && version >= 4) {
        struct blank *b = calloc(1, sizeof *b);
        b->global_name = name;
        b->output = wl_registry_bind(reg, name, &wl_output_interface, 4);
        wl_output_add_listener(b->output, &output_listener, b);
        wl_list_insert(&blanks, &b->link);
        if (ready) create_surface(b);
    }
}

static void global_remove(void *data, struct wl_registry *reg, uint32_t name)
{
    struct blank *b, *tmp;
    wl_list_for_each_safe(b, tmp, &blanks, link) {
        if (b->global_name != name) continue;
        destroy_surface(b);
        wl_output_release(b->output);
        wl_list_remove(&b->link);
        free(b);
    }
}

static const struct wl_registry_listener registry_listener = {.global = global_add, .global_remove = global_remove};

int main(void)
{
    prctl(PR_SET_PDEATHSIG, SIGTERM);
    if (getppid() == 1) return 0;  // parent already gone

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "krdp-blank: cannot connect to the Wayland display\n");
        return 1;
    }
    wl_list_init(&blanks);
    struct wl_registry *reg = wl_display_get_registry(display);
    wl_registry_add_listener(reg, &registry_listener, NULL);
    wl_display_roundtrip(display);  // globals
    wl_display_roundtrip(display);  // output names
    if (!compositor || !layer_shell || !viewporter || !pixel_manager) {
        fprintf(stderr, "krdp-blank: compositor lacks layer-shell, viewporter or single-pixel-buffer\n");
        return 1;
    }
    if (!lock_overlay) fprintf(stderr, "krdp-blank: no kde_lockscreen_overlay_v1; the lock screen will show\n");
    black = wp_single_pixel_buffer_manager_v1_create_u32_rgba_buffer(pixel_manager, 0, 0, 0, UINT32_MAX);
    ready = 1;
    struct blank *b;
    wl_list_for_each(b, &blanks, link) create_surface(b);
    while (wl_display_dispatch(display) != -1) {
    }
    fprintf(stderr, "krdp-blank: Wayland connection lost\n");
    return 1;
}
