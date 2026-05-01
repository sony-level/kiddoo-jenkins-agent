"""
File    : python/notify.py
Version : 1.0.0
Purpose : Discord webhook notifications for the Python orchestrator.
Author  : kiddoo-infra
"""

import json
import os
import urllib.error
import urllib.request
from datetime import datetime, timezone

from log import warn

# Discord embed colors (decimal)
INFO = 3447003      # Blue
OK = 5763719        # Green
ERR = 15158332      # Red


def notify(title, description, color, fields=None):
    """Send a Discord embed notification. Silently skips if the webhook URL is unset."""
    url = os.environ.get("DISCORD_WEBHOOK_URL")
    if not url:
        return
    embed = {
        "title": title,
        "description": description,
        "color": color,
        "timestamp": datetime.now(tz=timezone.utc).isoformat(),
        "footer": {"text": "kiddoo-infra"},
    }
    if fields:
        embed["fields"] = fields
    req = urllib.request.Request(
        url,
        data=json.dumps({"embeds": [embed]}).encode(),
        headers={
            "Content-Type": "application/json",
            "User-Agent": "kiddoo-infra/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            if r.status not in (200, 204):
                warn(f"Discord HTTP {r.status}")
    except (urllib.error.URLError, OSError) as e:
        warn(f"Discord unreachable: {e}")
