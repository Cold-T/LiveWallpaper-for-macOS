#!/usr/bin/env python3
"""
Probe Steam's ISteamRemoteStorage/EnumerateUserSubscribedFiles endpoint.

Required environment:
  STEAM_PUBLISHER_KEY  Steamworks publisher Web API key
  STEAM_ID64           SteamID64 for the user whose subscriptions are queried

Optional environment:
  STEAM_APP_ID         Defaults to 431960 (Wallpaper Engine)
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request


ENUMERATE_URL = (
    "https://partner.steam-api.com/ISteamRemoteStorage/"
    "EnumerateUserSubscribedFiles/v1/"
)
DETAILS_URL = (
    "https://api.steampowered.com/ISteamRemoteStorage/"
    "GetPublishedFileDetails/v1/"
)
DEFAULT_APP_ID = "431960"


def post_form(url: str, data: dict[str, str]) -> dict:
    body = urllib.parse.urlencode(data).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def enumerate_subscriptions(
    key: str,
    steamid: str,
    appid: str,
    page: int,
    listtype: int | None,
) -> dict:
    payload = {
        "key": key,
        "steamid": steamid,
        "appid": appid,
        "page": str(page),
    }
    if listtype is not None:
        payload["listtype"] = str(listtype)
    return post_form(ENUMERATE_URL, payload)


def get_details(publishedfileids: list[str]) -> dict:
    payload = {"itemcount": str(len(publishedfileids))}
    for index, publishedfileid in enumerate(publishedfileids):
        payload[f"publishedfileids[{index}]"] = publishedfileid
    return post_form(DETAILS_URL, payload)


def normalize_subscribed(response: dict) -> list[dict]:
    body = response.get("response", response)
    subscribed = body.get("subscribed")
    if isinstance(subscribed, list):
        return subscribed

    ids = body.get("publishedfileids") or body.get("publishedfileid") or []
    times = body.get("time_subscribed") or body.get("rtime_subscribed") or []
    if not isinstance(ids, list):
        return []

    items = []
    for index, publishedfileid in enumerate(ids):
        item = {"publishedfileid": str(publishedfileid)}
        if isinstance(times, list) and index < len(times):
            item["time_subscribed"] = times[index]
        items.append(item)
    return items


def main() -> int:
    parser = argparse.ArgumentParser(
        description="List Wallpaper Engine Workshop subscriptions via Steam Web API."
    )
    parser.add_argument("--key", default=os.environ.get("STEAM_PUBLISHER_KEY"))
    parser.add_argument("--steamid", default=os.environ.get("STEAM_ID64"))
    parser.add_argument("--appid", default=os.environ.get("STEAM_APP_ID", DEFAULT_APP_ID))
    parser.add_argument("--page", type=int, default=1)
    parser.add_argument("--listtype", type=int, default=None)
    parser.add_argument(
        "--details",
        action="store_true",
        help="Fetch public metadata for returned publishedfileids.",
    )
    args = parser.parse_args()

    missing = [
        name
        for name, value in {
            "STEAM_PUBLISHER_KEY": args.key,
            "STEAM_ID64": args.steamid,
        }.items()
        if not value
    ]
    if missing:
        print(f"Missing required value(s): {', '.join(missing)}", file=sys.stderr)
        print(
            "Example: STEAM_PUBLISHER_KEY=... STEAM_ID64=7656... "
            "tools/enumerate_steam_subscriptions.py --details",
            file=sys.stderr,
        )
        return 2

    response = enumerate_subscriptions(
        key=args.key,
        steamid=args.steamid,
        appid=args.appid,
        page=args.page,
        listtype=args.listtype,
    )

    if not args.details:
        print(json.dumps(response, indent=2, sort_keys=True, ensure_ascii=False))
        return 0

    subscribed = normalize_subscribed(response)
    publishedfileids = [
        str(item["publishedfileid"])
        for item in subscribed
        if item.get("publishedfileid")
    ]
    if not publishedfileids:
        print(json.dumps(response, indent=2, sort_keys=True, ensure_ascii=False))
        return 0

    details = get_details(publishedfileids[:100])
    print(
        json.dumps(
            {
                "enumerate_response": response,
                "published_file_details": details,
            },
            indent=2,
            sort_keys=True,
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
