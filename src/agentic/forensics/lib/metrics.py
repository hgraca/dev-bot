#!/usr/bin/env python3
"""metrics — window resolution, descriptive statistics and interval maths.

Pure helpers shared by the forensics activity commands (``prs``, ``commits``) and
the PR-cache coverage logic. Nothing here touches git, SQLite or the network.
"""

from __future__ import annotations

import calendar
import datetime


def median(values: list):
    """The median of ``values``, or None for an empty list.

    An even count averages the two middle values; equal elements are fine.
    """
    if not values:
        return None
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return float(ordered[middle])
    return (ordered[middle - 1] + ordered[middle]) / 2.0


def calendar_days(since: datetime.datetime, until: datetime.datetime) -> int:
    """Inclusive calendar days from ``since`` to ``until`` (0 when reversed)."""
    days = (until.date() - since.date()).days + 1
    return days if days > 0 else 0


def per_day(count: int, since: datetime.datetime, until: datetime.datetime) -> float:
    """``count`` per calendar day over the window, or 0.0 for an empty window."""
    days = calendar_days(since, until)
    return count / days if days else 0.0


def minus_one_month(moment: datetime.datetime) -> datetime.datetime:
    """One calendar month earlier, clamping the day to the target month's length."""
    year, month = moment.year, moment.month - 1
    if month == 0:
        year, month = year - 1, 12
    day = min(moment.day, calendar.monthrange(year, month)[1])
    return moment.replace(year=year, month=month, day=day)


def merge_intervals(intervals: list) -> list:
    """Sort and coalesce touching or overlapping ``(start, end)`` intervals."""
    merged = []
    for start, end in sorted(intervals):
        if merged and start <= merged[-1][1]:
            if end > merged[-1][1]:
                merged[-1] = (merged[-1][0], end)
        else:
            merged.append((start, end))
    return merged


def subtract_intervals(start, end, covered: list) -> list:
    """The uncovered sub-intervals of ``[start, end]`` given ``covered``.

    Intervals are closed on both ends, so a gap boundary may touch its coverage
    and a re-fetch can repeat a boundary instant — harmless, because PR upserts
    are idempotent.
    """
    gaps = []
    cursor = start
    for cover_start, cover_end in merge_intervals(covered):
        if cover_end < cursor:
            continue
        if cover_start > end:
            break
        if cover_start > cursor:
            gaps.append((cursor, cover_start))
        if cover_end > cursor:
            cursor = cover_end
    if cursor < end:
        gaps.append((cursor, end))
    return gaps


def parse_when(value: str, end_of_day: bool = False) -> datetime.datetime:
    """Parse a date or ISO-8601 datetime to an aware UTC datetime.

    A date-only value means the start of that day, or its end with ``end_of_day``.
    A naive datetime is assumed UTC.
    """
    raw = value.strip()
    if "T" not in raw and " " not in raw:
        date = datetime.datetime.strptime(raw, "%Y-%m-%d")
        moment = date.replace(tzinfo=datetime.timezone.utc)
        return moment + datetime.timedelta(hours=23, minutes=59, seconds=59) if end_of_day else moment
    parsed = datetime.datetime.fromisoformat(raw)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.timezone.utc)
    return parsed.astimezone(datetime.timezone.utc)


def resolve_window(since=None, until=None, now=None) -> tuple:
    """Resolve the ``(since, until)`` window; missing bounds default to the last month.

    ``until`` defaults to now; ``since`` defaults to exactly one month before it.
    """
    reference = now or datetime.datetime.now(datetime.timezone.utc)
    until_dt = parse_when(until, end_of_day=True) if until else reference
    since_dt = parse_when(since) if since else minus_one_month(until_dt)
    return since_dt, until_dt
