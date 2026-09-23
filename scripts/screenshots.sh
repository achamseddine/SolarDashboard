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
  shot() { sleep 3; xwd -root -silent | convert xwd:- -crop 1280x720+0+0 +repage "$OUT/$1$SUFFIX.png"; }
  scroll() { xdotool mousemove 1270 400; for i in $(seq 1 "$1"); do xdotool click 5; done; }
  # Navigation rail items (x=95 in the extended rail).
  # Rail rows: dashboard 150, analytics 194, programme 238, connectivity 282,
  #            education 326, schools 370, plants 414, alarms 458, map 502, settings 546.
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
  scroll 6; shot programme_5
  scroll 6; shot programme_6
  scroll 6; shot programme_7
  scroll 6; shot programme_8
  scroll 6; shot programme_9
  scroll 6; shot programme_10
  scroll 8; shot programme_11
  xdotool mousemove 95 282 click 1; sleep 4; shot connectivity
  scroll 5; shot connectivity_2
  scroll 6; shot connectivity_3
  scroll 6; shot connectivity_4
  scroll 8; shot connectivity_5
  # The connectivity tab bar sits under the sync strip, at y=51.
  xdotool mousemove 357 51 click 1; sleep 8; shot network_overview
  scroll 6; shot network_overview_2
  scroll 6; shot network_overview_3
  scroll 8; shot network_overview_4
  xdotool mousemove 502 51 click 1; sleep 4; shot network_infrastructure
  scroll 6; shot network_infrastructure_2
  xdotool mousemove 604 51 click 1; sleep 4; shot network_usage
  scroll 6; shot network_usage_2
  xdotool mousemove 686 51 click 1; sleep 4; shot network_schools
  xdotool mousemove 95 326 click 1; sleep 3; shot education
  scroll 5; shot education_2
  scroll 6; shot education_3
  scroll 8; shot education_4
  xdotool mousemove 95 370 click 1; sleep 3; shot schools
  xdotool mousemove 600 400 click 1; sleep 4; shot school_record
  scroll 4; shot school_record_2
  scroll 6; shot school_record_3
  scroll 6; shot school_record_4
  scroll 8; shot school_record_5
  xdotool mousemove 95 414 click 1; sleep 4; shot plants
  scroll 5; shot plants_2
  scroll 6; shot plants_3
  # The first row of the plant table; the pinned pager keeps it at y=500.
  xdotool mousemove 400 500 click 1; sleep 5; shot plant_detail
  scroll 4; shot plant_detail_2
  scroll 6; shot plant_detail_3
  scroll 6; shot plant_detail_4
  scroll 8; shot plant_detail_5
  scroll 8; shot plant_detail_6
  scroll 8; shot plant_detail_7
  scroll 8; shot plant_detail_8
  # The plant page tabs sit above the scrolling body, at y=181.
  xdotool mousemove 333 181 click 1; sleep 3; shot plant_devices
  xdotool mousemove 414 181 click 1; sleep 3; shot plant_alerts
  xdotool mousemove 499 181 click 1; sleep 3; shot plant_info
  scroll 5; shot plant_info_2
  xdotool mousemove 95 458 click 1; shot alarms
  xdotool mousemove 95 502 click 1; sleep 4; shot map
  xdotool mousemove 305 102 click 1; sleep 4; shot map_schools
  xdotool mousemove 633 102 click 1; sleep 3; shot map_connectivity
  xdotool mousemove 95 546 click 1; shot settings
  scroll 8; shot settings_2
  kill $APP
'
echo "Screenshots in $OUT"; ls "$OUT"
