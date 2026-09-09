app = defines["app"]
background = defines["background"]
icon = defines["icon"]

files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = ["CaptionPeel.app"]

icon_locations = {
    "CaptionPeel.app": (168, 190),
    "Applications": (492, 190),
}

format = "UDZO"
filesystem = "HFS+"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
default_view = "icon-view"
window_rect = ((200, 120), (660, 400))
icon_size = 128
text_size = 12
label_pos = "bottom"
