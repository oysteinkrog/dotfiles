#!/bin/bash
#
# Quick Analysis — One-command X archive overview using xf
#
# Usage:
#     ./quick_analysis.sh
#
# Output:
#     - Archive health
#     - Content counts by type
#     - Top hashtags
#     - Engagement summary
#     - Recent activity
#
# Requires: xf, jq

set -euo pipefail

if ! command -v xf >/dev/null 2>&1; then
    echo "Error: xf is not installed or not in PATH"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is not installed or not in PATH"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE_LIMIT="${XF_QUICK_ANALYSIS_SAMPLE_LIMIT:-1000}"
XF_DOCTOR_TIMEOUT="${XF_DOCTOR_TIMEOUT:-15}"

run_xf_doctor() {
    if command -v timeout >/dev/null 2>&1; then
        timeout "${XF_DOCTOR_TIMEOUT}s" xf -q doctor >/dev/null 2>&1
    else
        xf -q doctor >/dev/null 2>&1
    fi
}

echo "=============================================="
echo "XF QUICK ANALYSIS"
echo "=============================================="
echo ""

# 1. Health check
echo "--- Health Check ---"
if run_xf_doctor; then
    echo "Status: OK"
else
    doctor_status=$?
    if [ "$doctor_status" -eq 124 ]; then
        echo "Status: xf doctor timed out after ${XF_DOCTOR_TIMEOUT}s"
    else
        echo "Status: Issues detected (run 'xf doctor' for details)"
    fi
fi
echo ""

STATS_JSON="$(xf -q -f json stats 2>/dev/null)"
TEMPORAL_JSON="$(xf -q -f json stats --temporal 2>/dev/null)"
TWEET_SAMPLE_JSON="$(xf -q -f json search '' --types tweet --limit "$SAMPLE_LIMIT" 2>/dev/null || echo '[]')"
GROK_SAMPLE_JSON="$(xf -q -f json search '' --types grok --limit "$SAMPLE_LIMIT" 2>/dev/null || echo '[]')"

# 2. Archive overview
echo "--- Archive Overview ---"
printf '%s\n' "$STATS_JSON" | jq '{
    tweets: .tweets_count,
    likes: .likes_count,
    dms: .dms_count,
    dm_conversations: .dm_conversations_count,
    grok_messages: .grok_messages_count,
    followers: .followers_count,
    following: .following_count,
    index_built_at
}' 2>/dev/null || echo "Could not get stats"
echo ""

# 3. Temporal range
echo "--- Activity Range ---"
printf '%s\n' "$TEMPORAL_JSON" | jq '{
    first_tweet: .stats.first_tweet_date,
    last_tweet: .stats.last_tweet_date,
    active_days: .temporal.active_days_count,
    total_days_in_range: .temporal.total_days_in_range,
    longest_gap_days: .temporal.longest_gap_days,
    longest_gap_start: .temporal.longest_gap_start,
    longest_gap_end: .temporal.longest_gap_end,
    most_active_day: .temporal.most_active_day,
    most_active_day_count: .temporal.most_active_day_count
}' 2>/dev/null || echo "Could not get temporal stats"
echo ""

# 4. Top hashtags from working search sample
echo "--- Top Hashtags (sample of up to $SAMPLE_LIMIT tweets) ---"
hashtags_output="$(
    printf '%s\n' "$TWEET_SAMPLE_JSON" \
        | jq -r '.[].metadata.hashtags[]? // empty' 2>/dev/null \
        | sed 's/^/#/' \
        | sort | uniq -c | sort -rn | head -10
)"
if [ -n "$hashtags_output" ]; then
    printf '%s\n' "$hashtags_output"
else
    echo "No hashtags found in search sample"
fi
echo ""

# 5. Engagement summary from working search sample
echo "--- Engagement Summary (sample of up to $SAMPLE_LIMIT tweets) ---"
printf '%s\n' "$TWEET_SAMPLE_JSON" | jq '{
    sampled_tweets: length,
    sample_total_likes: (map(.metadata.favorite_count // 0) | add),
    sample_total_retweets: (map(.metadata.retweet_count // 0) | add),
    sample_avg_likes: (if length > 0 then ((map(.metadata.favorite_count // 0) | add) / length | floor) else 0 end),
    sample_top_tweet_likes: (map(.metadata.favorite_count // 0) | max // 0)
}' 2>/dev/null || echo "Could not calculate engagement"
echo ""

# 6. Recent activity (last 7 days of tweeting)
echo "--- Recent Tweet Activity (by month) ---"
printf '%s\n' "$TEMPORAL_JSON" \
    | jq -r '
        [.temporal.daily_counts[]? | {month: .date[:7], count}]
        | group_by(.month)
        | map({month: .[0].month, tweets: (map(.count) | add)})
        | .[-7:]
        | .[]
        | "\(.month): \(.tweets) tweets"
    ' 2>/dev/null \
    || echo "Could not get activity"
echo ""

# 7. Content type breakdown
echo "--- DM Conversations ---"
DM_COUNT=$(printf '%s\n' "$STATS_JSON" | jq '.dms_count // 0' 2>/dev/null || echo "0")
echo "Total DM messages: $DM_COUNT"
if [ "$DM_COUNT" -gt 0 ]; then
    CONV_COUNT=$(printf '%s\n' "$STATS_JSON" | jq '.dm_conversations_count // "?"' -r 2>/dev/null || echo "?")
    echo "Unique conversations: $CONV_COUNT"
fi
echo ""

# 8. Grok usage
echo "--- Grok AI Usage ---"
GROK_COUNT=$(printf '%s\n' "$STATS_JSON" | jq '.grok_messages_count // 0' 2>/dev/null || echo "0")
echo "Total Grok messages: $GROK_COUNT"
if [ "$GROK_COUNT" -gt 0 ]; then
    CHAT_COUNT=$(printf '%s\n' "$GROK_SAMPLE_JSON" \
        | jq '[.[].metadata.chat_id?] | unique | length' 2>/dev/null || echo "?")
    echo "Unique Grok chats in sample: $CHAT_COUNT"
fi
echo ""

# 9. Quick tips
echo "--- Next Steps ---"
echo "1. Search tweets:     xf search \"KEYWORD\" --types tweet --format json"
echo "2. Search DMs:        xf search \"KEYWORD\" --types dm --context --format json"
echo "3. Search Grok:       xf search \"KEYWORD\" --types grok --format json"
echo "4. Top tweets:        xf search \"\" --types tweet --sort engagement --limit 10 --format json"
echo "5. Topic deep dive:   python \"$SCRIPT_DIR/topic_miner.py\" \"TOPIC\""
echo ""
echo "=============================================="
