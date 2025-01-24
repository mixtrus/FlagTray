import sys
import threading
import requests
from io import BytesIO
from PIL import Image
import pystray
from pystray import MenuItem as item

def get_country_code():
    try:
        response = requests.get('http://ip-api.com/json/', timeout=5)
        data = response.json()
        return data.get('countryCode', 'US')
    except:
        return 'US'

def fetch_flag_image(country_code):
    try:
        url = f"https://flagcdn.com/w40/{country_code.lower()}.png"
        response = requests.get(url, timeout=5)
        image = Image.open(BytesIO(response.content))
        return image
    except:
        return Image.new('RGB', (40, 30), color = 'gray')

def on_quit(icon, item):
    icon.stop()
    sys.exit()

def create_tray_icon():
    country_code = get_country_code()
    flag_image = fetch_flag_image(country_code)
    menu = (item('Quit', on_quit),)
    icon = pystray.Icon("Country Flag", flag_image, "Country Flag", menu)
    icon.run()

if __name__ == "__main__":
    threading.Thread(target=create_tray_icon).start()
