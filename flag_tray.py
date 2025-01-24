# requirements.txt
# ---------------
# requests
# Pillow
# pystray

import sys
import time
import threading
import requests
from io import BytesIO
from PIL import Image
import pystray
from pystray import MenuItem as item

def get_country_code():
    """
    Returns the 2-letter country code based on the current IP.
    Fallback is 'US' if unable to reach the service.
    """
    try:
        response = requests.get('http://ip-api.com/json/', timeout=5)
        data = response.json()
        return data.get('countryCode', 'US')
    except:
        return 'US'

def fetch_flag_image(country_code):
    """
    Fetches a 40x30 (approx) PNG flag image from flagcdn.com.
    If fetching fails, returns a simple gray image placeholder.
    """
    try:
        url = "https://flagcdn.com/w40/{}.png".format(country_code.lower())
        response = requests.get(url, timeout=5)
        image = Image.open(BytesIO(response.content))
        return image
    except:
        return Image.new('RGB', (40, 30), color='gray')

def on_quit(icon, item):
    """
    Cleanly stop the tray icon and exit the program.
    """
    icon.stop()
    sys.exit()

def create_tray_icon():
    """
    Creates the tray icon with the current flag.
    Spawns a background thread to update the flag in real time (periodically).
    """
    # Initial country/flag
    current_code = get_country_code()
    flag_image = fetch_flag_image(current_code)
    # Define the tray menu
    menu = (item('Quit', on_quit),)
    # Create the icon object
    icon = pystray.Icon("Country Flag", flag_image, "Country Flag", menu)

    def update_flag_periodically():
        """
        Periodically checks if the country code has changed
        and updates the tray icon accordingly.
        """
        nonlocal current_code
        while icon.visible:
            time.sleep(60)  # Check every 60 seconds
            new_code = get_country_code()
            if new_code != current_code:
                current_code = new_code
                icon.icon = fetch_flag_image(new_code)
                icon.visible = True  # Force re-draw the icon

    # Start the background thread to monitor and update the flag
    threading.Thread(target=update_flag_periodically, daemon=True).start()

    # Run the tray icon
    icon.run()

if __name__ == "__main__":
    threading.Thread(target=create_tray_icon).start()
