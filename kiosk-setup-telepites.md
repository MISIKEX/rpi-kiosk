# Ideiglenes könyvtár létrehozása és belépés (subshell használatával)
tmpdir="$(mktemp -d)" && (
  set -e
  # Kilépéskor (hiba esetén is) visszatér a kezdőkönyvtárba és törli a temp mappát
  trap 'cd ~; rm -rf "$tmpdir"' EXIT

  echo "Ideiglenes mappa létrehozva: $tmpdir"
  
  # A repozitórium letöltése (csak a legutolsó módosítást tölti le a gyorsaságért)
  git clone --depth 1 https://github.com/MISIKEX/rpi-kiosk.git "$tmpdir"
  cd "$tmpdir"

  # Jogosultság adása és a telepítő futtatása
  chmod +x kiosk_setup.sh
  ./kiosk_setup.sh
)
