import sys
import threading
import requests
from io import BytesIO
from PIL import Image
import pystray
from pystray import MenuItem as item

def get_country_code():
    """
    Fetches the 2-letter country code from ip-api.com.
    If it fails, returns 'US'.
    """
    try:
        response = requests.get("http://ip-api.com/json/", timeout=5)
        data = response.json()
        return data.get('countryCode', 'US')
    except:
        return 'US'

def fetch_flag_image(country_code):
    """
    Fetches a 40x30 (approx) PNG flag from flagcdn.com based on the country code.
    Returns a gray placeholder if the fetch fails.
    """
    try:
        url = "https://flagcdn.com/w40/{}.png".format(country_code.lower())
        response = requests.get(url, timeout=5)
        image = Image.open(BytesIO(response.content))
        return image
    except:
        return Image.new('RGB', (40, 30), color='gray')

def on_quit(icon, _):
    """
    Cleanly stops the tray icon and exits the program.
    """
    icon.stop()
    sys.exit()

def schedule_flag_update(icon):
    """
    Uses a threading.Timer to periodically check if the country code has changed.
    If it has, updates the tray icon image in real-time.
    Then schedules itself again.
    """
    new_code = get_country_code()
    if new_code != schedule_flag_update.current_code:
        schedule_flag_update.current_code = new_code
        new_flag = fetch_flag_image(new_code)
        # Directly update the icon image (forcing refresh).
        icon.icon = new_flag
        icon.visible = True

    # Schedule the next check in 10 seconds (adjust as desired).
    timer = threading.Timer(10, schedule_flag_update, [icon])
    timer.daemon = True
    timer.start()

def create_tray_icon():
    """
    Initializes the tray icon with the current IP-based country flag,
    and starts the periodic update process via schedule_flag_update.
    """
    initial_code = get_country_code()
    schedule_flag_update.current_code = initial_code  # store current code at module level
    initial_flag = fetch_flag_image(initial_code)

    # Define the menu for the tray icon
    menu = (item('Quit', on_quit),)

    # Create the tray icon
    icon = pystray.Icon("Country Flag", initial_flag, "Country Flag", menu)

    # Start the periodic update
    schedule_flag_update(icon)

    # Run the tray icon (blocks until quit)
    icon.run()

if __name__ == "__main__":
    create_tray_icon()
