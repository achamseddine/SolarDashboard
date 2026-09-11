#!/usr/bin/env bash
# Captures screenshots of the Linux desktop build in demo mode under Xvfb.
# Usage: scripts/screenshots.sh [out_dir]
# Env:   FAKE_TIME='2026-09-09 10:30:00'  run the app under libfaketime (e.g. midday in Beirut)
#        DARK=1                            capture the dark theme
# Requires: xvfb-run, xwd, convert (ImageMagick), xdotool, optionally faketime.
set -euo pipefail
OUT=${1:-docs/screenshots}
BUNDLE=build/linux/x64/release/bundle
PREFS="$HOME/.local/share/unicef_solar_monitor"
mkdir -p "$OUT" "$PREFS"
DARK_JSON=$([ "${DARK:-0}" = "1" ] && echo true || echo false)
cat > "$PREFS/shared_preferences.json" <<JSON
{"flutter.settings.demoMode": true, "flutter.settings.keepScreenOn": false, "flutter.settings.darkMode": $DARK_JSON}
JSON
rm -f "$PREFS"/unicef_solar.db*
SUFFIX=$([ "${DARK:-0}" = "1" ] && echo "_dark" || echo "")
LAUNCH="./$BUNDLE/unicef_solar_monitor"
if [ -n "${FAKE_TIME:-}" ]; then LAUNCH="faketime '$FAKE_TIME' $LAUNCH"; fi
export OUT SUFFIX LAUNCH
xvfb-run -a -s "-screen 0 1440x900x24" bash -c '
  eval "$LAUNCH" > /tmp/app_screens.log 2>&1 &
  APP=$!
  sleep 45
  shot() { sleep 3; xwd -root -silent | convert xwd:- -crop 1280x800+0+0 +repage "$OUT/$1$SUFFIX.png"; }
  scroll() { xdotool mousemove 200 600; for i in $(seq 1 "$1"); do xdotool click 5; done; }
  # Navigation rail items (x=95 in the extended rail).
  # Rail rows: dashboard 150, analytics 194, programme 238, schools 282, alarms 326, map 370, settings 414.
  xdotool mousemove 95 150 click 1; shot dashboard
  scroll 4; shot dashboard_2
  scroll 6; shot dashboard_3
  scroll 8; shot dashboard_4
  xdotool mousemove 95 194 click 1; shot analytics
  scroll 4; shot analytics_2
  scroll 6; shot analytics_3
  scroll 6; shot analytics_4
  scroll 8; shot analytics_5
  xdotool mousemove 95 238 click 1; shot programme
  scroll 5; shot programme_2
  scroll 6; shot programme_3
  scroll 6; shot programme_4
  scroll 8; shot programme_5
  xdotool mousemove 95 282 click 1; shot schools
  xdotool mousemove 500 330 click 1; sleep 4; shot school_detail
  scroll 4; shot school_detail_2
  scroll 6; shot school_detail_3
  scroll 6; shot school_detail_4
  scroll 8; shot school_detail_5
  xdotool mousemove 95 326 click 1; shot alarms
  xdotool mousemove 95 370 click 1; sleep 4; shot map
  xdotool mousemove 95 414 click 1; shot settings
  scroll 8; shot settings_2
  kill $APP
'
echo "Screenshots in $OUT"; ls "$OUT"
