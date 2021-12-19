#!/usr/bin/python
# -*- coding:utf-8 -*-
import sys
import os
import subprocess

picdir = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'pic')
libdir = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'lib')
if os.path.exists(libdir):
    sys.path.append(libdir)

import logging
from waveshare_epd import epd2in13b_V3
import time
from PIL import Image,ImageDraw,ImageFont
import traceback

logging.basicConfig(level=logging.DEBUG)

try:
    logging.info("epd2in13b_V3 Demo")
    
    epd = epd2in13b_V3.EPD()
    logging.info("init and Clear")
    epd.init()
    epd.Clear()
    time.sleep(1)
    
    # Drawing on the image
    logging.info("Drawing")    
    fontSmall = ImageFont.truetype(os.path.join(picdir, 'Font.ttc'), 10)
    
    # logging.info("3.read bmp file")
    Blackimage = Image.open(os.path.join(picdir, 'logo.bmp'))
    RYimage = Image.new('1', (epd.height, epd.width), 255)

    drawry = ImageDraw.Draw(RYimage)
    uptime = subprocess.check_output('uptime -p', shell=True, text=True)
    x_start = epd.height - ( 4.5 * len(uptime) )
    y_start = epd.width - 10 - 4
    drawry.text((x_start, y_start), uptime, font = fontSmall, fill = 0)

    epd.display(epd.getbuffer(Blackimage), epd.getbuffer(RYimage.transpose(Image.ROTATE_180)))
    time.sleep(2)

except IOError as e:
    logging.info(e)
    
except KeyboardInterrupt:    
    logging.info("ctrl + c:")
    epd2in13b_V3.epdconfig.module_exit()
    exit()
