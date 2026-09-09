#!/usr/bin/env bash
# Captures screenshots of the Linux desktop build in demo mode under Xvfb.
# Usage: scripts/screenshots.sh [out_dir]   (requires xvfb-run, xwd, convert, xdotool)
set -euo pipefail
OUT=${1:-docs/screenshots}
BUNDLE=build/linux/x64/release/bundle
mkdir -p "$OUT" "$HOME/.local/share/unicef_solar_monitor"
# Demo mode on, screen wakelock off (no display server power management under Xvfb).
cat > "$HOME/.local/share/unicef_solar_monitor/shared_preferences.json" <<'JSON'
{"flutter.settings.demoMode": true, "flutter.settings.keepScreenOn": false}
JSON
rm -f "$HOME/.local/share/unicef_solar_monitor"/unicef_solar.db*
xvfb-run -a -s "-screen 0 1440x900x24" bash -c "
  ./$BUNDLE/unicef_solar_monitor > /tmp/app_screens.log 2>&1 &
  APP=\$!
  sleep 40
  shot() { sleep 3; xwd -root -silent | convert xwd:- \"$OUT/\$1.png\"; }
  # Navigation rail items (x=95 in extended rail, y positions from the shell layout).
  xdotool mousemove 95 150 click 1; shot dashboard
  xdotool mousemove 700 500; for i in 1 2 3; do xdotool click 5; done; shot dashboard_2
  for i in 1 2 3 4 5 6; do xdotool click 5; done; shot dashboard_3
  xdotool mousemove 95 194 click 1; shot schools
  xdotool mousemove 500 330 click 1; shot school_detail
  xdotool mousemove 700 500; for i in 1 2 3 4; do xdotool click 5; done; shot school_detail_2
  xdotool mousemove 95 238 click 1; shot alarms
  xdotool mousemove 95 282 click 1; sleep 3; shot map
  xdotool mousemove 95 326 click 1; shot settings
  kill \$APP
"
echo "Screenshots in $OUT"; ls -la "$OUT"
