#!/usr/bin/env python3
"""
Production icon generator for LidaPay:
- Google Play Store 512x512 standard
- Android Adaptive Icons (Oreo to Android 15+)
- Android 13+ Monochrome Themed Icons
- Android Legacy & Round Icons
- Android Notification Icons
- iOS App Icon Set (Xcode / App Store standard)
"""

import os
from PIL import Image, ImageDraw, ImageOps
import numpy as np

WORKSPACE = '/Users/nana/SCEnv/DevOps/lida-shop'
SOURCE_LOGO = '/Users/nana/.gemini/antigravity-ide/brain/7463eb5f-4125-4200-b99f-b6cfb144a9f9/.user_uploaded/media_1792857945626.png'

def main():
    print("Starting LidaPay official icon generation...")
    os.chdir(WORKSPACE)

    # 1. Load source
    src_img = Image.open(SOURCE_LOGO).convert('RGBA')
    arr = np.array(src_img)

    r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
    dots_mask = (r > 180) & (g > 180) & (b > 180) & (a > 30)

    # Version with navy dots (#2A2550: 42, 37, 80)
    arr_navy = arr.copy()
    for y, x in zip(*np.where(dots_mask)):
        arr_navy[y, x, 0] = 42
        arr_navy[y, x, 1] = 37
        arr_navy[y, x, 2] = 80

    logo_navy = Image.fromarray(arr_navy)

    # Monochrome silhouette (for Material You dynamic theming and notification icons)
    # The whole mark (crimson + navy) becomes opaque white or black with source alpha
    arr_mono = np.zeros_like(arr)
    mark_mask = a > 30
    arr_mono[mark_mask, 0] = 255
    arr_mono[mark_mask, 1] = 255
    arr_mono[mark_mask, 2] = 255
    arr_mono[mark_mask, 3] = a[mark_mask]
    logo_mono = Image.fromarray(arr_mono)

    # 2. Master Assets in assets/
    os.makedirs('assets/icons', exist_ok=True)
    os.makedirs('assets/images', exist_ok=True)

    logo_navy.save('assets/images/app_logo.png')
    src_img.save('assets/images/app_logo_dark.png')
    logo_navy.save('assets/icons/app_icon_navy.png')
    src_img.save('assets/icons/app_icon_light_dots.png')

    # 1024x1024 Master on solid white
    master_1024 = Image.new('RGB', (1024, 1024), (255, 255, 255))
    logo_1024_size = int(1024 * 0.72) # ~737px
    logo_res = logo_navy.resize((logo_1024_size, logo_1024_size), Image.Resampling.LANCZOS)
    off_1024 = (1024 - logo_1024_size) // 2
    master_1024.paste(logo_res, (off_1024, off_1024), mask=logo_res.split()[3])
    master_1024.save('assets/icons/app_icon_master_1024.png')

    # Google Play Store 512x512
    play_512 = master_1024.resize((512, 512), Image.Resampling.LANCZOS)
    play_512.save('assets/images/play_store_512.png', format='PNG', optimize=True)
    os.makedirs('android/app/src/main', exist_ok=True)
    play_512.save('android/app/src/main/play_store_512.png', format='PNG', optimize=True)

    # In-app rounded icon 512x512
    app_icon_512 = Image.new('RGBA', (512, 512), (0, 0, 0, 0))
    mask_512 = Image.new('L', (512, 512), 0)
    d512 = ImageDraw.Draw(mask_512)
    d512.rounded_rectangle((0, 0, 512, 512), radius=110, fill=255)
    app_icon_512.paste(play_512, (0, 0), mask=mask_512)
    app_icon_512.save('assets/images/app_icon.png')

    # 3. Android Adaptive & Legacy Icons
    # Android adaptive canvas is 108dp. Safe zone is 66dp (~62%).
    densities = {
        'mipmap-mdpi': {'legacy': 48, 'adaptive': 108},
        'mipmap-hdpi': {'legacy': 72, 'adaptive': 162},
        'mipmap-xhdpi': {'legacy': 96, 'adaptive': 216},
        'mipmap-xxhdpi': {'legacy': 144, 'adaptive': 324},
        'mipmap-xxxhdpi': {'legacy': 192, 'adaptive': 432},
    }

    res_dir = 'android/app/src/main/res'
    for folder, sizes in densities.items():
        target_dir = os.path.join(res_dir, folder)
        os.makedirs(target_dir, exist_ok=True)

        leg_size = sizes['legacy']
        adapt_size = sizes['adaptive']

        # a) Legacy square launcher icon (white rounded rect)
        leg_img = Image.new('RGBA', (leg_size, leg_size), (0, 0, 0, 0))
        leg_mask = Image.new('L', (leg_size, leg_size), 0)
        d = ImageDraw.Draw(leg_mask)
        rad = max(4, int(leg_size * 0.20))
        d.rounded_rectangle((0, 0, leg_size, leg_size), radius=rad, fill=255)
        
        bg_white = Image.new('RGBA', (leg_size, leg_size), (255, 255, 255, 255))
        logo_leg_size = int(leg_size * 0.72)
        logo_leg = logo_navy.resize((logo_leg_size, logo_leg_size), Image.Resampling.LANCZOS)
        off_leg = (leg_size - logo_leg_size) // 2
        bg_white.paste(logo_leg, (off_leg, off_leg), mask=logo_leg.split()[3])
        leg_img.paste(bg_white, (0, 0), mask=leg_mask)
        leg_img.save(os.path.join(target_dir, 'ic_launcher.png'))

        # b) Legacy round launcher icon (circle)
        round_img = Image.new('RGBA', (leg_size, leg_size), (0, 0, 0, 0))
        round_mask = Image.new('L', (leg_size, leg_size), 0)
        d_rnd = ImageDraw.Draw(round_mask)
        d_rnd.ellipse((0, 0, leg_size, leg_size), fill=255)
        round_img.paste(bg_white, (0, 0), mask=round_mask)
        round_img.save(os.path.join(target_dir, 'ic_launcher_round.png'))

        # c) Adaptive foreground layer (108dp canvas, safe zone ~63%)
        fg_img = Image.new('RGBA', (adapt_size, adapt_size), (0, 0, 0, 0))
        logo_adapt_size = int(adapt_size * 0.63)
        logo_adapt = logo_navy.resize((logo_adapt_size, logo_adapt_size), Image.Resampling.LANCZOS)
        off_adapt = (adapt_size - logo_adapt_size) // 2
        fg_img.paste(logo_adapt, (off_adapt, off_adapt), mask=logo_adapt.split()[3])
        fg_img.save(os.path.join(target_dir, 'ic_launcher_foreground.png'))

        # d) Monochrome layer for Android 13+ Themed Icons
        mono_img = Image.new('RGBA', (adapt_size, adapt_size), (0, 0, 0, 0))
        logo_mono_resized = logo_mono.resize((logo_adapt_size, logo_adapt_size), Image.Resampling.LANCZOS)
        mono_img.paste(logo_mono_resized, (off_adapt, off_adapt), mask=logo_mono_resized.split()[3])
        mono_img.save(os.path.join(target_dir, 'ic_launcher_monochrome.png'))

    # 4. Status Bar Notification Icons (drawable-*/ic_notification.png)
    notif_densities = {
        'drawable-mdpi': 24,
        'drawable-hdpi': 36,
        'drawable-xhdpi': 48,
        'drawable-xxhdpi': 72,
        'drawable-xxxhdpi': 96,
    }
    for folder, size in notif_densities.items():
        notif_dir = os.path.join(res_dir, folder)
        os.makedirs(notif_dir, exist_ok=True)
        notif_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        logo_notif_size = int(size * 0.84)
        logo_notif = logo_mono.resize((logo_notif_size, logo_notif_size), Image.Resampling.LANCZOS)
        off_notif = (size - logo_notif_size) // 2
        notif_img.paste(logo_notif, (off_notif, off_notif), mask=logo_notif.split()[3])
        notif_img.save(os.path.join(notif_dir, 'ic_notification.png'))

    # 5. Adaptive Icon XMLs in mipmap-anydpi-v26
    v26_dir = os.path.join(res_dir, 'mipmap-anydpi-v26')
    os.makedirs(v26_dir, exist_ok=True)

    xml_content = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
"""
    with open(os.path.join(v26_dir, 'ic_launcher.xml'), 'w') as f:
        f.write(xml_content)
    with open(os.path.join(v26_dir, 'ic_launcher_round.xml'), 'w') as f:
        f.write(xml_content)

    # 6. iOS AppIcon Set
    ios_icons = [
        ('Icon-App-20x20@1x.png', 20),
        ('Icon-App-20x20@2x.png', 40),
        ('Icon-App-20x20@3x.png', 60),
        ('Icon-App-29x29@1x.png', 29),
        ('Icon-App-29x29@2x.png', 58),
        ('Icon-App-29x29@3x.png', 87),
        ('Icon-App-40x40@1x.png', 40),
        ('Icon-App-40x40@2x.png', 80),
        ('Icon-App-40x40@3x.png', 120),
        ('Icon-App-60x60@2x.png', 120),
        ('Icon-App-60x60@3x.png', 180),
        ('Icon-App-76x76@1x.png', 76),
        ('Icon-App-76x76@2x.png', 152),
        ('Icon-App-83.5x83.5@2x.png', 167),
        ('Icon-App-1024x1024@1x.png', 1024),
    ]

    ios_dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    os.makedirs(ios_dir, exist_ok=True)
    for filename, sz in ios_icons:
        icon_res = master_1024.resize((sz, sz), Image.Resampling.LANCZOS)
        # Ensure completely opaque RGB (no alpha) as required by App Store
        icon_res = icon_res.convert('RGB')
        icon_res.save(os.path.join(ios_dir, filename), format='PNG', optimize=True)

    print("All icons successfully generated and saved!")

if __name__ == '__main__':
    main()
