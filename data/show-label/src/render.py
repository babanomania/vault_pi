#!/usr/bin/python
# -*- coding:utf-8 -*-
import sys
import os
import subprocess

picdir = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'pic')
libdir = '/home/pi/display-lib/e-Paper/RaspberryPi_JetsonNano/python/lib'
if os.path.exists(libdir):
    sys.path.append(libdir)

import logging
from waveshare_epd import epd2in13_V4
import time
from PIL import Image,ImageDraw,ImageFont
import traceback

logging.basicConfig(level=logging.DEBUG)

try:
    logging.info("epd2in13_V4 Demo")
    
    epd = epd2in13_V4.EPD()
    logging.info("init and Clear")
    epd.init()
    epd.Clear(0xFF)
    time.sleep(1)
    
    # Drawing on the image
    logging.info("Drawing")    
    fontSmall = ImageFont.truetype(os.path.join(picdir, 'Font.ttc'), 12)
    
    # logging.info("3.read bmp file")
    image = Image.open(os.path.join(picdir, 'logo.bmp'))

    uptime = subprocess.check_output('uptime -p', shell=True, text=True)
    hostname = subprocess.check_output('hostname', shell=True, text=True)
    ipaddr = subprocess.check_output("ifconfig | grep wlan0 -A 1 | tail -1 | awk '{ print $2 }'", shell=True, text=True)
    hostname_ipaddr = hostname.strip() + " - " + ipaddr.strip()

    x_start1 = 2
    y_start1 = epd.width - 10 - 6

    x_start2 = epd.height - ( 4.5 * len(uptime) ) - 20
    y_start2 = epd.width - 10 - 6

    draw= ImageDraw.Draw(image)
    draw.text((x_start1, y_start1), hostname_ipaddr, font = fontSmall, fill = 0)
    draw.text((x_start2, y_start2), uptime, font = fontSmall, fill = 0)

    epd.display(epd.getbuffer(image.transpose(Image.ROTATE_180)))
    time.sleep(2)

except IOError as e:
    logging.info(e)
    
except KeyboardInterrupt:    
    logging.info("ctrl + c:")
    epd2in13_V4.epdconfig.module_exit(cleanup=True)
    exit()
