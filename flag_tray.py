import sys
import os
import threading
import requests
import platform
from io import BytesIO
from PIL import Image
import pystray
from pystray import MenuItem as item

# For Windows registry manipulation:
if platform.system() == 'Windows':
    try:
        import winreg
    except ImportError:
        winreg = None
else:
    winreg = None

# Global flag to track if we are currently set to start on Windows login
startup_enabled = False

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

def is_startup_enabled():
    """
    Checks if this script is set to start on Windows login by looking
    for the registry value 'CountryFlagTray' in
    'Software\\Microsoft\\Windows\\CurrentVersion\\Run'.
    Returns True if found, False otherwise.
    Non-Windows systems or missing 'winreg' will always return False.
    """
    if platform.system() != 'Windows' or not winreg:
        return False

    try:
        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Run",
            0,
            winreg.KEY_READ
        )
        # If the value exists, we assume startup is enabled.
        _ = winreg.QueryValueEx(key, "CountryFlagTray")
        key.Close()
        return True
    except WindowsError:
        return False
    except:
        return False

def add_to_startup():
    """
    Adds this Python script to the system startup on Windows by creating
    a registry value under 'Software\\Microsoft\\Windows\\CurrentVersion\\Run'
    named 'CountryFlagTray'.
    """
    if platform.system() != 'Windows' or not winreg:
        return

    try:
        python_exe = sys.executable
        script_path = os.path.abspath(__file__)

        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Run",
            0,
            winreg.KEY_SET_VALUE
        )

        # The registry entry name is "CountryFlagTray".
        # The value is the command to run on login.
        winreg.SetValueEx(
            key,
            "CountryFlagTray",
            0,
            winreg.REG_SZ,
            f'"{python_exe}" "{script_path}"'
        )
        key.Close()
    except:
        pass

def remove_from_startup():
    """
    Removes this script from Windows startup by deleting
    the 'CountryFlagTray' value in the registry, if it exists.
    Specifically from 'Software\\Microsoft\\Windows\\CurrentVersion\\Run'.
    """
    if platform.system() != 'Windows' or not winreg:
        return

    try:
        key = winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Run",
            0,
            winreg.KEY_SET_VALUE
        )
        winreg.DeleteValue(key, "CountryFlagTray")
        key.Close()
    except:
        pass

def toggle_startup(icon, _):
    """
    Toggles the startup-enabled status. If currently not enabled, adds to startup.
    If currently enabled, removes from startup. Updates the checked status in the menu.
    """
    global startup_enabled
    if not startup_enabled:
        add_to_startup()
        startup_enabled = is_startup_enabled()
    else:
        remove_from_startup()
        startup_enabled = is_startup_enabled()

    # Update the menu so the check mark reflects the new status
    icon.update_menu()

def schedule_flag_update(icon):
    """
    Uses threading.Timer to periodically check if the country code has changed.
    If it has, updates the tray icon image in real-time.
    Then schedules itself again.
    """
    new_code = get_country_code()
    if new_code != schedule_flag_update.current_code:
        schedule_flag_update.current_code = new_code
        new_flag = fetch_flag_image(new_code)
        icon.icon = new_flag
        icon.visible = True

    # Schedule the next check in 10 seconds (adjust as desired).
    timer = threading.Timer(10, schedule_flag_update, [icon])
    timer.daemon = True
    timer.start()

def create_tray_icon():
    """
    Initializes the tray icon with the current IP-based country flag,
    checks if we're already enabled for startup, and starts the periodic
    update process. The 'Add to Startup' menu item toggles the startup status.
    """
    global startup_enabled
    startup_enabled = is_startup_enabled()

    # Initialize the country code and fetch the initial flag
    initial_code = get_country_code()
    schedule_flag_update.current_code = initial_code
    initial_flag = fetch_flag_image(initial_code)

    # Create the tray menu.
    menu = (
        item(
            'Add to Startup',
            toggle_startup,
            checked=lambda _: startup_enabled
        ),
        item('Quit', on_quit),
    )

    # Create the tray icon
    icon = pystray.Icon("Country Flag", initial_flag, "Country Flag", menu)

    # Start the periodic flag updates
    schedule_flag_update(icon)

    # Run the tray icon (blocking)
    icon.run()

if __name__ == "__main__":
    create_tray_icon()
