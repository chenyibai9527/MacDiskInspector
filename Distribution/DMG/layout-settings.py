import os


source = defines["source"]
assets = defines["assets"]

format = "UDZO"
filesystem = "HFS+"
compression_level = 9
background = os.path.join(source, ".background", "background.png")
icon = os.path.join(assets, "VolumeIcon.icns")
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
# Finder on macOS 26 reserves space for the window chrome and may keep the
# status strip visible despite the saved preference. The extra 16 × 48 points
# leave the 760 × 480 artwork fully visible without scrollbars.
window_rect = ((120, 120), (776, 528))
icon_size = 92
text_size = 13
label_pos = "bottom"
show_icon_preview = True

files = [
    (os.path.join(source, "Mac 磁盘扫描助手.app"), "Mac 磁盘扫描助手.app"),
    (os.path.join(source, "使用说明.pdf"), "使用说明.pdf"),
    (os.path.join(source, "打不开？双击这里.pdf"), "打不开？双击这里.pdf"),
    (os.path.join(source, "打不开请看这里.txt"), "打不开请看这里.txt"),
]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    "Mac 磁盘扫描助手.app": (190, 225),
    "Applications": (570, 225),
    "使用说明.pdf": (140, 365),
    "打不开？双击这里.pdf": (380, 365),
    "打不开请看这里.txt": (620, 365),
}
hide_extensions = [
    "使用说明.pdf",
    "打不开？双击这里.pdf",
    "打不开请看这里.txt",
]
