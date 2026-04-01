#!/usr/bin/env bash
# schedule_cron.sh — installs the daily-quote cron schedule
# Schedule: Mon=1(10am), Tue=2(random), Wed=5(random), Thu=6(random), Fri=4(random), Sat=7(random), Sun=6(random)
# "Random" times are pre-baked here as fixed times spread across the day to avoid clustering.

SCRIPT="$HOME/project/daily-quote/update_quote.sh"
LOG="$HOME/project/daily-quote/cron.log"

# Remove any existing daily-quote cron entries
crontab -l 2>/dev/null | grep -v "daily-quote" | crontab - 2>/dev/null || true

# Build new entries
# Times are spread across the day (roughly evenly), seeded for variety
# Mon: 1 run  → 10:00
# Tue: 2 runs → 08:15, 19:30
# Wed: 5 runs → 07:00, 10:30, 13:00, 16:45, 20:15
# Thu: 6 runs → 06:30, 09:00, 11:45, 14:15, 17:30, 21:00
# Fri: 4 runs → 08:00, 11:30, 15:00, 19:45
# Sat: 7 runs → 07:15, 09:30, 11:00, 13:30, 15:45, 18:00, 21:30
# Sun: 6 runs → 07:00, 09:45, 12:15, 15:00, 17:30, 20:45

NEW_CRONS="
# daily-quote Mon (1 run)
0 10 * * 1 bash $SCRIPT >> $LOG 2>&1

# daily-quote Tue (2 runs)
15 8 * * 2 bash $SCRIPT >> $LOG 2>&1
30 19 * * 2 bash $SCRIPT >> $LOG 2>&1

# daily-quote Wed (5 runs)
0 7 * * 3 bash $SCRIPT >> $LOG 2>&1
30 10 * * 3 bash $SCRIPT >> $LOG 2>&1
0 13 * * 3 bash $SCRIPT >> $LOG 2>&1
45 16 * * 3 bash $SCRIPT >> $LOG 2>&1
15 20 * * 3 bash $SCRIPT >> $LOG 2>&1

# daily-quote Thu (6 runs)
30 6 * * 4 bash $SCRIPT >> $LOG 2>&1
0 9 * * 4 bash $SCRIPT >> $LOG 2>&1
45 11 * * 4 bash $SCRIPT >> $LOG 2>&1
15 14 * * 4 bash $SCRIPT >> $LOG 2>&1
30 17 * * 4 bash $SCRIPT >> $LOG 2>&1
0 21 * * 4 bash $SCRIPT >> $LOG 2>&1

# daily-quote Fri (4 runs)
0 8 * * 5 bash $SCRIPT >> $LOG 2>&1
30 11 * * 5 bash $SCRIPT >> $LOG 2>&1
0 15 * * 5 bash $SCRIPT >> $LOG 2>&1
45 19 * * 5 bash $SCRIPT >> $LOG 2>&1

# daily-quote Sat (7 runs)
15 7 * * 6 bash $SCRIPT >> $LOG 2>&1
30 9 * * 6 bash $SCRIPT >> $LOG 2>&1
0 11 * * 6 bash $SCRIPT >> $LOG 2>&1
30 13 * * 6 bash $SCRIPT >> $LOG 2>&1
45 15 * * 6 bash $SCRIPT >> $LOG 2>&1
0 18 * * 6 bash $SCRIPT >> $LOG 2>&1
30 21 * * 6 bash $SCRIPT >> $LOG 2>&1

# daily-quote Sun (6 runs)
0 7 * * 0 bash $SCRIPT >> $LOG 2>&1
45 9 * * 0 bash $SCRIPT >> $LOG 2>&1
15 12 * * 0 bash $SCRIPT >> $LOG 2>&1
0 15 * * 0 bash $SCRIPT >> $LOG 2>&1
30 17 * * 0 bash $SCRIPT >> $LOG 2>&1
45 20 * * 0 bash $SCRIPT >> $LOG 2>&1
"

# Append to existing crontab
(crontab -l 2>/dev/null; echo "$NEW_CRONS") | crontab -

echo "✅ Cron schedule installed. Current crontab:"
crontab -l | grep daily-quote
