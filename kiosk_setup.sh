#!/bin/bash

# Spinner megjelenítése kiegészítő üzenettel
spinner() {
    local pid=$1
    local message=$2
    local delay=0.1
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    tput civis 2>/dev/null || true
    local i=0
    while [ -d /proc/$pid ]; do
        local frame=${frames[$i]}
        printf "\r\e[35m%s\e[0m %s" "$frame" "$message"
        i=$(((i + 1) % ${#frames[@]}))
        sleep $delay
    done
    printf "\r\e[32m✔\e[0m %s\n" "$message"
    tput cnorm 2>/dev/null || true
}

# Ellenőrzés: ne fusson rootként
if [ "$(id -u)" -eq 0 ]; then
  echo "Ezt a scriptet nem szabad rootként futtatni. Kérlek normál felhasználóként futtasd, sudo jogosultsággal."
  exit 1
fi

# Aktuális felhasználó és home könyvtár
CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo "~$CURRENT_USER")

# Függvény igen/nem kérdéshez alapértelmezett értékkel
ask_user() {
    local prompt="$1"
    local default="$2"
    local default_text=""
    
    if [ "$default" = "y" ]; then
        default_text=" [default: yes]"
    elif [ "$default" = "n" ]; then
        default_text=" [default: no]"
    fi
    
    while true; do
        read -p "$prompt$default_text (y/n): " yn
        # If empty (just Enter pressed), use default
        yn="${yn:-$default}"
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Kérlek igen (y) vagy nem (n) választ adj.";;
        esac
    done
}

# Csomaglista frissítése?
echo
if ask_user "Szeretnéd frissíteni a csomaglistát?" "y"; then
    echo -e "\e[90mCsomaglista frissítése folyamatban, kérlek várj...\e[0m"
    sudo apt update > /dev/null 2>&1 &
    spinner $! "Csomaglista frissítése..."
fi

# Telepített csomagok frissítése?
echo
if ask_user "Szeretnéd frissíteni a telepített csomagokat?" "y"; then
    echo -e "\e[90mTelepített csomagok frissítése. EZ ELTARTHAT EGY IDEIG, kérlek várj...\e[0m"
    sudo apt upgrade -y > /dev/null 2>&1 &
    spinner $! "Telepített csomagok frissítése..."
fi

# Wayland / labwc csomagok telepítése?
echo
if ask_user "Szeretnéd telepíteni a Wayland és labwc csomagokat?" "y"; then
    echo -e "\e[90mWayland csomagok telepítése folyamatban, kérlek várj...\e[0m"
    sudo apt install --no-install-recommends -y labwc wlr-randr seatd > /dev/null 2>&1 &
    spinner $! "Wayland csomagok telepítése..."
fi

# --- Intelligens Chromium telepítés + autostart rész ---
echo
if ask_user "Szeretnéd telepíteni a Chromium böngészőt?" "y"; then
    # Elérhető Chromium csomag nevének felismerése (előnyben: 'chromium')
    CHROMIUM_PKG=""
    if apt-cache show chromium >/dev/null 2>&1; then
        CHROMIUM_PKG="chromium"
    elif apt-cache show chromium-browser >/dev/null 2>&1; then
        CHROMIUM_PKG="chromium-browser"
    fi

    if [ -z "$CHROMIUM_PKG" ]; then
        echo -e "\e[33mNem található Chromium csomag az APT-ben. Lehet, hogy engedélyezni kell egy megfelelő tárolót, vagy kézzel kell telepíteni.\e[0m"
    else
        echo -e "\e[90mTelepítés $CHROMIUM_PKG. THIS MAY TAKE SOME TIME, please wait...\e[0m"
        sudo apt install --no-install-recommends -y "$CHROMIUM_PKG" > /dev/null 2>&1 &
        spinner $! "Telepítés $CHROMIUM_PKG..."
    fi
fi

# greetd telepítése és beállítása?
echo
if ask_user "Szeretnéd telepíteni és beállítani a greetd-t a labwc automatikus indításához?" "y"; then
    echo -e "\e[90mTelepítés greetd for auto start of labwc, please wait...\e[0m"
    sudo apt install -y greetd > /dev/null 2>&1 &
    spinner $! "Telepítés greetd..."

    echo -e "\e[90m/etc/greetd/config.toml létrehozása vagy felülírása...\e[0m"
    sudo mkdir -p /etc/greetd
    sudo bash -c "cat <<EOL > /etc/greetd/config.toml
[terminal]
vt = 7
[default_session]
command = \"/usr/bin/labwc\"
user = \"$CURRENT_USER\"
EOL"

    echo -e "\e[32m✔\e[0m /etc/greetd/config.toml sikeresen létrehozva vagy felülírva!"

    echo -e "\e[90mgreetd szolgáltatás engedélyezése...\e[0m"
    sudo systemctl enable greetd > /dev/null 2>&1 &
    spinner $! "greetd szolgáltatás engedélyezése..."

    echo -e "\e[90mGrafikus target beállítása alapértelmezettként...\e[0m"
    sudo systemctl set-default graphical.target > /dev/null 2>&1 &
    spinner $! "Setting graphical target..."
fi

# Autostart (Chromium) script létrehozása labwc-hez?
echo
if ask_user "Szeretnél Chromium autostart scriptet létrehozni labwc-hez?" "y"; then
    read -p "Add meg a Chromiumban megnyitandó URL-t [default: https://webglsamples.org...]: " USER_URL
    USER_URL="${USER_URL:-https://webglsamples.org/aquarium/aquarium.html}"

    # Inkognitó mód indítása? (alapértelmezett: nem)
    echo
    INCOGNITO_FLAG=""
    if ask_user "Induljon a böngésző inkognitó módban?" "n"; then
        INCOGNITO_FLAG="--incognito "
    fi

    # Várakozás hálózatra indítás előtt? (alapértelmezett: nem)
    echo
    NETWORK_WAIT=""
    if ask_user "Várjon hálózati kapcsolatra a Chromium indítása előtt?" "n"; then
        read -p "Enter host to ping for network check [default: 8.8.8.8]: " PING_HOST
        PING_HOST="${PING_HOST:-8.8.8.8}"
        read -p "Enter maximum wait time in seconds [default: 30]: " MAX_WAIT
        MAX_WAIT="${MAX_WAIT:-30}"

        NETWORK_WAIT="  # Wait for network connectivity (max ${MAX_WAIT}s)
  for i in \$(seq 1 $MAX_WAIT); do
    if ping -c 1 -W 2 $PING_HOST > /dev/null 2>&1; then
      break
    fi
    sleep 1
  done
"
    fi

    LABWC_AUTOSTART_DIR="$HOME_DIR/.config/labwc"
    mkdir -p "$LABWC_AUTOSTART_DIR"
    LABWC_AUTOSTART_FILE="$LABWC_AUTOSTART_DIR/autostart"

    # Telepített bináris keresése (mindkét név), PATH előnyben
    CHROMIUM_BIN="$(command -v chromium || command -v chromium-browser || true)"

    if [ -z "$CHROMIUM_BIN" ]; then
        # fallback common paths
        if [ -x "/usr/bin/chromium" ]; then
            CHROMIUM_BIN="/usr/bin/chromium"
        elif [ -x "/usr/bin/chromium-browser" ]; then
            CHROMIUM_BIN="/usr/bin/chromium-browser"
        else
            CHROMIUM_BIN="/usr/bin/chromium"
            echo -e "\e[33mFigyelmeztetés: nem található Chromium bináris a PATH-ban. Using $CHROMIUM_BIN in autostart — adjust if needed.\e[0m"
        fi
    fi

    # Autostart fájl létezésének biztosítása
    touch "$LABWC_AUTOSTART_FILE"

    # Autostart bejegyzés hozzáadása, ha még nincs
    if grep -q -E "chromium|chromium-browser" "$LABWC_AUTOSTART_FILE" 2>/dev/null; then
        echo "Chromium autostart bejegyzés már létezik in $LABWC_AUTOSTART_FILE."
    else
        echo -e "\e[90mChromium hozzáadása a labwc autostart scriphez...\e[0m"

        if [ -n "$NETWORK_WAIT" ]; then
            cat >> "$LABWC_AUTOSTART_FILE" << EOL
# Chromium indítása kiosk módban (hálózati várakozással)
(
$NETWORK_WAIT
    $CHROMIUM_BIN ${INCOGNITO_FLAG}--autoplay-policy=no-user-gesture-required --kiosk $USER_URL
) &
EOL
        else
            echo "$CHROMIUM_BIN ${INCOGNITO_FLAG}--autoplay-policy=no-user-gesture-required --kiosk $USER_URL &" >> "$LABWC_AUTOSTART_FILE"
        fi

        echo -e "\e[32m✔\e[0m A labwc autostart script létrejött vagy frissült at $LABWC_AUTOSTART_FILE."
    fi
fi

# Egérkurzor elrejtése kiosk módban?
echo
if ask_user "Szeretnéd elrejteni az egérkurzort kiosk módban?" "y"; then
    # wtype telepítése, ha még nincs jelen
    if ! command -v wtype &> /dev/null; then
        echo -e "\e[90mTelepítés wtype for cursor control, please wait...\e[0m"
        sudo apt install -y wtype > /dev/null 2>&1 &
        spinner $! "Telepítés wtype..."
    fi

    # labwc konfigurációs könyvtár létrehozása
    LABWC_CONFIG_DIR="$HOME_DIR/.config/labwc"
    mkdir -p "$LABWC_CONFIG_DIR"
    
    # rc.xml létrehozása vagy módosítása
    RC_XML="$LABWC_CONFIG_DIR/rc.xml"

    if [ -f "$RC_XML" ]; then
        # Ellenőrzés: létezik-e már HideCursor beállítás
        if grep -q "HideCursor" "$RC_XML" 2>/dev/null; then
            echo -e "\e[33mAz rc.xml már tartalmaz HideCursor beállítást. Nem történt módosítás.\e[0m"
        else
            echo -e "\e[90mHideCursor billentyűparancs hozzáadása a meglévő rc.xml-hez...\e[0m"
            # Beszúrás a </keyboard> záró tag elé
            if grep -q "</keyboard>" "$RC_XML"; then
                sudo sed -i 's|</keyboard>|  <keybind key="W-h">\n    <action name="HideCursor"/>\n    <action name="WarpCursor" to="output" x="1" y="1"/>\n  </keybind>\n</keyboard>|' "$RC_XML"
            else
                echo -e "\e[33mNem található </keyboard> tag az rc.xml-ben. Kérlek add hozzá kézzel a HideCursor billentyűparancsot.\e[0m"
            fi
        fi
    else
        # Új rc.xml létrehozása HideCursor beállítással
        echo -e "\e[90mrc.xml létrehozása HideCursor beállítással...\e[0m"
        cat > "$RC_XML" << 'EOL'
<?xml version="1.0"?>
<labwc_config>
  <keyboard>
    <keybind key="W-h">
      <action name="HideCursor"/>
      <action name="WarpCursor" to="output" x="1" y="1"/>
    </keybind>
  </keyboard>
</labwc_config>
EOL
        echo -e "\e[32m✔\e[0m rc.xml sikeresen létrehozva!"
    fi

    # wtype parancs hozzáadása az autostarthoz
    LABWC_AUTOSTART_FILE="$LABWC_CONFIG_DIR/autostart"
    touch "$LABWC_AUTOSTART_FILE"

    if grep -q "wtype.*logo.*-k h" "$LABWC_AUTOSTART_FILE" 2>/dev/null; then
        echo -e "\e[33mAz autostart már tartalmaz kurzor elrejtő parancsot. Nem történt módosítás.\e[0m"
    else
        echo -e "\e[90mKurzor elrejtő parancs hozzáadása az autostarthoz...\e[0m"
        cat >> "$LABWC_AUTOSTART_FILE" << 'EOL'

# Kurzor elrejtése indításkor (Win+H billentyű szimulálása)
sleep 1 && wtype -M logo -k h -m logo &
EOL
        echo -e "\e[32m✔\e[0m Kurzor elrejtése sikeresen beállítva!"
    fi
fi

# Splash képernyő telepítése?
echo
if ask_user "Szeretnéd telepíteni a splash képernyőt?" "y"; then
    # Plymouth és témák telepítése (pix-plym-splash)
    echo -e "\e[90mTelepítés splash screen and themes. THIS MAY TAKE SOME TIME, please wait...\e[0m"
    sudo apt-get install -y plymouth plymouth-themes pix-plym-splash > /dev/null 2>&1 &
    spinner $! "Telepítés splash screen..."

    # pix téma elérhetőségének ellenőrzése
    if [ ! -e /usr/share/plymouth/themes/pix/pix.script ]; then
        echo -e "\e[33mFigyelmeztetés: a pix téma nem található a telepítés után. A splash képernyő nem biztos, hogy megfelelően működik.\e[0m"
    else
        echo -e "\e[90mSplash képernyő témájának beállítása pix-re...\e[0m"
        sudo plymouth-set-default-theme pix

        # Egyedi splash logo letöltése és beállítása
        echo -e "\e[90mEgyedi splash logó letöltése...\e[0m"
        SPLASH_URL="https://raw.githubusercontent.com/MISIKEX/rpi-kiosk/main/_assets/splashscreens/splash.png"
        SPLASH_PATH="/usr/share/plymouth/themes/pix/splash.png"

        if sudo wget -q "$SPLASH_URL" -O "$SPLASH_PATH"; then
            echo -e "\e[32m✔\e[0m Egyedi splash logó telepítve."
        else
            echo -e "\e[33mFigyelmeztetés: nem sikerült letölteni az egyedi splash logót. Az alapértelmezett kerül használatra.\e[0m"
        fi

        sudo update-initramfs -u > /dev/null 2>&1 &
        spinner $! "initramfs frissítése..."
    fi

    CONFIG_TXT="/boot/firmware/config.txt"
    if [ -f "$CONFIG_TXT" ]; then
        if ! grep -q "disable_splash" "$CONFIG_TXT"; then
            echo -e "\e[90mAdding disable_splash=1 to $CONFIG_TXT...\e[0m"
            sudo bash -c "echo 'disable_splash=1' >> '$CONFIG_TXT'"
        else
            echo -e "\e[33m$CONFIG_TXT already contains a disable_splash option. No changes made. Please check manually!\e[0m"
        fi
    else
        echo -e "\e[33m$CONFIG_TXT not found — skipping config.txt modification.\e[0m"
    fi

    CMDLINE_TXT="/boot/firmware/cmdline.txt"
    if [ -f "$CMDLINE_TXT" ]; then
        if ! grep -q "splash" "$CMDLINE_TXT"; then
            echo -e "\e[90mAdding quiet splash plymouth.ignore-serial-consoles to $CMDLINE_TXT...\e[0m"
            sudo sed -i 's/$/ quiet splash plymouth.ignore-serial-consoles/' "$CMDLINE_TXT"
        fi
        if grep -q "console=tty1" "$CMDLINE_TXT"; then
            echo -e "\e[90mReplacing console=tty1 with console=tty3 in $CMDLINE_TXT...\e[0m"
            sudo sed -i 's/console=tty1/console=tty3/' "$CMDLINE_TXT"
        elif ! grep -q "console=tty3" "$CMDLINE_TXT"; then
            echo -e "\e[90mAdding console=tty3 to $CMDLINE_TXT...\e[0m"
            sudo sed -i 's/$/ console=tty3/' "$CMDLINE_TXT"
        fi
        echo -e "\e[32m✔\e[0m Splash screen installed and configured with pix theme."
    else
        echo -e "\e[33m$CMDLINE_TXT not found — skipping cmdline.txt modification.\e[0m"
    fi
fi

# Képernyőfelbontás beállítása
echo
if ask_user "Do you want to set the screen resolution in cmdline.txt and the labwc autostart file?" "y"; then

    # Check if edid-decode is installed; if not, install it
    if ! command -v edid-decode &> /dev/null; then
        echo -e "\e[90mTelepítés required tool edid-decode, please wait...\e[0m"
        sudo apt install -y edid-decode > /dev/null 2>&1 &
        spinner $! "Telepítés edid-decode..."
        echo -e "\e[32mrequired tool installed successfully!\e[0m"
    fi

    # EDID kiolvasása (gyakori útvonalok: card1 vagy card0)
    EDID_PATH=""
    if [ -r /sys/class/drm/card1-HDMI-A-1/edid ]; then
        EDID_PATH="/sys/class/drm/card1-HDMI-A-1/edid"
    elif [ -r /sys/class/drm/card0-HDMI-A-1/edid ]; then
        EDID_PATH="/sys/class/drm/card0-HDMI-A-1/edid"
    fi

    available_resolutions=()

    if [ -n "$EDID_PATH" ]; then
        edid_output=$(sudo cat "$EDID_PATH" | edid-decode 2>/dev/null || true)
        while IFS= read -r line; do
            if [[ "$line" =~ ([0-9]+)x([0-9]+)[[:space:]]+([0-9]+\.[0-9]+|[0-9]+)\ Hz ]]; then
                resolution="${BASH_REMATCH[1]}x${BASH_REMATCH[2]}"
                frequency="${BASH_REMATCH[3]}"
                formatted="${resolution}@${frequency}"
                available_resolutions+=("$formatted")
            fi
        done <<< "$edid_output"
    fi

    # Alapértelmezett lista használata, ha nincs EDID eredmény
    if [ ${#available_resolutions[@]} -eq 0 ]; then
        echo -e "\e[33mNo resolutions found via EDID. Using default list.\e[0m"
        available_resolutions=("1920x1080@60" "1280x720@60" "1024x768@60" "1600x900@60" "1366x768@60")
    fi

    # Felhasználó felbontásválasztása
    echo -e "\e[94mPlease choose a resolution (type in the number):\e[0m"
    select RESOLUTION in "${available_resolutions[@]}"; do
        if [[ -n "$RESOLUTION" ]]; then
            echo -e "\e[32mYou selected $RESOLUTION\e[0m"
            break
        else
            echo -e "\e[33mInvalid selection, please try again.\e[0m"
        fi
    done

    # Kiválasztott felbontás hozzáadása a cmdline.txt-hez
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
    if [ -f "$CMDLINE_FILE" ]; then
        if ! grep -q "video=" "$CMDLINE_FILE"; then
            echo -e "\e[90mAdding video=HDMI-A-1:$RESOLUTION to $CMDLINE_FILE...\e[0m"
            # Prepend video=... at start of single-line cmdline.txt
            sudo sed -i "1s/^/video=HDMI-A-1:$RESOLUTION /" "$CMDLINE_FILE"
            echo -e "\e[32m✔\e[0m Resolution added to cmdline.txt successfully!"
        else
            echo -e "\e[33mcmdline.txt already contains a video entry. No changes made.\e[0m"
        fi
    else
        echo -e "\e[33m$CMDLINE_FILE not found — skipping cmdline modification.\e[0m"
    fi

    # Add the command to labwc autostart if not present
    AUTOSTART_FILE="$HOME_DIR/.config/labwc/autostart"
    touch "$AUTOSTART_FILE"
    if ! grep -q "wlr-randr --output HDMI-A-1 --mode $RESOLUTION" "$AUTOSTART_FILE" 2>/dev/null; then
        echo "wlr-randr --output HDMI-A-1 --mode $RESOLUTION" >> "$AUTOSTART_FILE"
        echo -e "\e[32m✔\e[0m Resolution command added to labwc autostart file successfully!"
    else
        echo -e "\e[33mAutostart file already contains this resolution command. No changes made.\e[0m"
    fi
fi

# Képernyő elforgatásának beállítása
echo
if ask_user "Do you want to set the screen orientation (rotation)?" "n"; then
    echo -e "\e[94mPlease choose an orientation:\e[0m"
    orientations=("normal (0°)" "90° clockwise" "180°" "270° clockwise")
    transform_values=("normal" "90" "180" "270")

    select orientation in "${orientations[@]}"; do
        if [[ -n "$orientation" ]]; then
            idx=$((REPLY - 1))
            TRANSFORM="${transform_values[$idx]}"
            echo -e "\e[32mYou selected $orientation\e[0m"
            break
        else
            echo -e "\e[33mInvalid selection, please try again.\e[0m"
        fi
    done

    # Hozzáadás a labwc autostarthoz
    AUTOSTART_FILE="$HOME_DIR/.config/labwc/autostart"
    touch "$AUTOSTART_FILE"
    if ! grep -q "wlr-randr.*--transform" "$AUTOSTART_FILE" 2>/dev/null; then
        echo "wlr-randr --output HDMI-A-1 --transform $TRANSFORM" >> "$AUTOSTART_FILE"
        echo -e "\e[32m✔\e[0m Screen orientation added to labwc autostart file successfully!"
    else
        echo -e "\e[33mAutostart file already contains a transform command. No changes made.\e[0m"
    fi
fi

# Hang kimenet kényszerítése HDMI-re?
echo
if ask_user "Do you want to force audio output to HDMI?" "y"; then
    CONFIG_TXT="/boot/firmware/config.txt"
    if [ -f "$CONFIG_TXT" ]; then
        # Check if dtparam=audio exists (uncommented)
        if grep -q "^dtparam=audio=" "$CONFIG_TXT"; then
            # Check if it's already set to off
            if grep -q "^dtparam=audio=off" "$CONFIG_TXT"; then
                echo -e "\e[33m$CONFIG_TXT already has dtparam=audio=off. No changes made.\e[0m"
            else
                # Replace existing audio parameter
                echo -e "\e[90mModifying existing dtparam=audio in $CONFIG_TXT...\e[0m"
                sudo sed -i 's/^dtparam=audio=.*/dtparam=audio=off/' "$CONFIG_TXT"
                echo -e "\e[32m✔\e[0m Audio parameter updated to force HDMI output!"
            fi
        elif grep -q "^#dtparam=audio=" "$CONFIG_TXT"; then
            # Uncomment and set to off
            echo -e "\e[90mUncommenting and setting dtparam=audio=off in $CONFIG_TXT...\e[0m"
            sudo sed -i 's/^#dtparam=audio=.*/dtparam=audio=off/' "$CONFIG_TXT"
            echo -e "\e[32m✔\e[0m Audio parameter set to force HDMI output!"
        else
            # Add new parameter
            echo -e "\e[90mAdding dtparam=audio=off to $CONFIG_TXT...\e[0m"
            sudo bash -c "echo 'dtparam=audio=off' >> '$CONFIG_TXT'"
            echo -e "\e[32m✔\e[0m Audio parameter added to force HDMI output!"
        fi
    else
        echo -e "\e[33m$CONFIG_TXT not found — skipping audio configuration.\e[0m"
    fi
fi

# TV távirányító (HDMI-CEC) támogatás engedélyezése?
echo
if ask_user "Do you want to enable TV remote control via HDMI-CEC?" "n"; then
    echo -e "\e[90mTelepítés CEC utilities, please wait...\e[0m"
    sudo apt-get install -y ir-keytable > /dev/null 2>&1 &
    spinner $! "Telepítés CEC utilities..."

    # Egyedi CEC billentyűtérkép könyvtár létrehozása
    echo -e "\e[90mCreating custom CEC keymap...\e[0m"
    sudo mkdir -p /etc/rc_keymaps

    # Egyedi billentyűtérkép fájl létrehozása
    sudo bash -c "cat > /etc/rc_keymaps/custom-cec.toml" << 'EOL'
[[protocols]]
name = "custom_cec"
protocol = "cec"
[protocols.scancodes]
0x00 = "KEY_ENTER"
0x01 = "KEY_UP"
0x02 = "KEY_DOWN"
0x03 = "KEY_LEFT"
0x04 = "KEY_RIGHT"
0x09 = "KEY_EXIT"
0x0d = "KEY_BACK"
0x44 = "KEY_PLAYPAUSE"
0x45 = "KEY_STOPCD"
0x46 = "KEY_PAUSECD"
EOL

    echo -e "\e[32m✔\e[0m Custom CEC keymap created!"

    # systemd szolgáltatás létrehozása CEC beállításhoz
    echo -e "\e[90mCreating CEC setup service...\e[0m"
    sudo bash -c "cat > /etc/systemd/system/cec-setup.service" << 'EOL'
[Unit]
Description=CEC Remote Control Setup
After=multi-user.target
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/bin/cec-ctl -d /dev/cec1 --playback
ExecStart=/bin/sleep 2
ExecStart=/usr/bin/cec-ctl -d /dev/cec1 --active-source phys-addr=1.0.0.0
ExecStart=/bin/sleep 1
ExecStart=/usr/bin/ir-keytable -c -s rc0 -w /etc/rc_keymaps/custom-cec.toml
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

    # Szolgáltatás engedélyezése
    echo -e "\e[90mEnabling CEC setup service...\e[0m"
    sudo systemctl daemon-reload > /dev/null 2>&1
    sudo systemctl enable cec-setup.service > /dev/null 2>&1 &
    spinner $! "Enabling CEC service..."

    echo -e "\e[32m✔\e[0m TV remote CEC support configured successfully!"
    echo -e "\e[90mNote: Make sure HDMI-CEC (SimpLink/Anynet+/Bravia Sync) is enabled on your TV.\e[0m"
fi

# apt gyorsítótárak takarítása
echo -e "\e[90mAPT gyorsítótárak takarítása, kérlek várj...\e[0m"
sudo apt clean > /dev/null 2>&1 &
spinner $! "APT gyorsítótárak takarítása..."

# Befejező üzenet és újraindítás felajánlása
echo -e "\e[32m✔\e[0m \e[32mA beállítás sikeresen befejeződött!\e[0m"
echo
if ask_user "Szeretnéd most újraindítani a rendszert?" "n"; then
    echo -e "\e[90mRendszer újraindítása...\e[0m"
    sudo reboot
else
    echo -e "\e[33mNe felejtsd el manuálisan újraindítani a rendszert, hogy minden változás érvénybe lépjen.\e[0m"
fi