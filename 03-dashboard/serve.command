#!/bin/bash
# Double-click this file to start a local web server for the dashboard.
# macOS will open Terminal automatically.
cd "$(dirname "$0")"
PORT=8000
URL="http://localhost:$PORT/"
echo "============================================"
echo "  Dasbor Sakernas - Local Server"
echo "============================================"
echo "Folder  : $(pwd)"
echo "URL     : $URL"
echo "============================================"
echo "Browser akan terbuka otomatis dalam 2 detik."
echo "Tutup window ini (Ctrl+C) untuk stop server."
echo
( sleep 2 && open "$URL" ) &
python3 -m http.server $PORT
