#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw

def create_progress_bar():
    # Background (dark gray)
    bg = Image.new('RGBA', (200, 6), (58, 58, 60, 255))
    bg.save('progress-bg.png')
    
    # Foreground (white/light gray)
    fg = Image.new('RGBA', (200, 6), (255, 255, 255, 255))
    fg.save('progress-bar.png')

def create_apple_logo():
    # Placeholder
    logo = Image.new('RGBA', (120, 150), (0, 0, 0, 0))
    draw = ImageDraw.Draw(logo)
    draw.ellipse((20, 40, 100, 120), fill=(255, 255, 255, 255))
    draw.ellipse((50, 10, 70, 35), fill=(255, 255, 255, 255))
    logo.save('apple-logo.png')

if __name__ == '__main__':
    os.chdir('/home/hassan/Desktop/macnix/plymouth/macnix')
    create_progress_bar()
    create_apple_logo()
    print("Assets generated.")
