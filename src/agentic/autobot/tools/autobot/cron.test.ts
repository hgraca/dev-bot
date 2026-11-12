import { describe, expect, test } from "bun:test";

import { dueEntries, matchesSchedule, parseSchedule } from "./cron.ts";

const sorted = (values: Set<number>) => [...values].sort((a, b) => a - b);

describe("parseSchedule", () => {
  test("expands an all-wildcards expression", () => {
    const schedule = parseSchedule("* * * * *");
    expect(schedule.minutes.size).toBe(60);
    expect(schedule.hours.size).toBe(24);
    expect(schedule.daysOfMonth.size).toBe(31);
    expect(schedule.months.size).toBe(12);
    expect(schedule.daysOfWeek.size).toBe(7);
    expect(schedule.dayOfMonthRestricted).toBe(false);
    expect(schedule.dayOfWeekRestricted).toBe(false);
  });

  test("expands a step", () => {
    expect(sorted(parseSchedule("*/15 * * * *").minutes)).toEqual([0, 15, 30, 45]);
  });

  test("expands a single value", () => {
    expect(sorted(parseSchedule("5 * * * *").minutes)).toEqual([5]);
  });

  test("expands a range", () => {
    expect(sorted(parseSchedule("1-5 * * * *").minutes)).toEqual([1, 2, 3, 4, 5]);
  });

  test("expands a ranged step", () => {
    expect(sorted(parseSchedule("1-10/3 * * * *").minutes)).toEqual([1, 4, 7, 10]);
  });

  test("expands a list", () => {
    expect(sorted(parseSchedule("0,30 * * * *").minutes)).toEqual([0, 30]);
  });

  test("expands hours and weekday ranges", () => {
    const schedule = parseSchedule("0 9-17 * * 1-5");
    expect(schedule.hours.size).toBe(9);
    expect(sorted(schedule.daysOfWeek)).toEqual([1, 2, 3, 4, 5]);
    expect(schedule.dayOfWeekRestricted).toBe(true);
  });

  test("aliases day-of-week 7 to Sunday", () => {
    expect(sorted(parseSchedule("0 0 * * 7").daysOfWeek)).toEqual([0]);
    expect(sorted(parseSchedule("0 0 * * 5-7").daysOfWeek)).toEqual([0, 5, 6]);
  });

  test("treats 0-7 as an unrestricted weekday field", () => {
    expect(parseSchedule("0 0 * * 0-7").dayOfWeekRestricted).toBe(false);
  });

  test("rejects the wrong number of fields", () => {
    expect(() => parseSchedule("0 0 * *")).toThrow(/must have 5 fields, got 4/);
    expect(() => parseSchedule("0 0 * * * *")).toThrow(/must have 5 fields, got 6/);
  });

  test("rejects an empty expression", () => {
    expect(() => parseSchedule("   ")).toThrow(/must be a non-empty string/);
  });

  test("rejects out-of-range values", () => {
    expect(() => parseSchedule("60 * * * *")).toThrow(/out of range/);
    expect(() => parseSchedule("* 24 * * *")).toThrow(/out of range/);
    expect(() => parseSchedule("* * 0 * *")).toThrow(/out of range/);
    expect(() => parseSchedule("* * * 13 *")).toThrow(/out of range/);
    expect(() => parseSchedule("* * * * 8")).toThrow(/out of range/);
  });

  test("rejects a reversed range", () => {
    expect(() => parseSchedule("5-1 * * * *")).toThrow(/out of range/);
  });

  test("rejects an invalid step", () => {
    expect(() => parseSchedule("*/0 * * * *")).toThrow(/invalid step/);
    expect(() => parseSchedule("*/x * * * *")).toThrow(/invalid step/);
  });

  test("rejects unsupported syntax", () => {
    expect(() => parseSchedule("@hourly * * * *")).toThrow(/unsupported characters/);
    expect(() => parseSchedule("1- * * * *")).toThrow(/unsupported characters/);
    expect(() => parseSchedule("* * * * 1/2/3")).toThrow(/unsupported characters/);
  });

  test("prefixes errors with the caller's location", () => {
    expect(() => parseSchedule("0 0 * *", "p: autobot.prompts[2]")).toThrow(
      /^p: autobot\.prompts\[2\]: "schedule" must have 5 fields/,
    );
  });
});

describe("matchesSchedule", () => {
  const at = (month: number, day: number, hour: number, minute: number) =>
    new Date(2026, month - 1, day, hour, minute, 0, 0);

  test("matches the exact minute", () => {
    expect(matchesSchedule(parseSchedule("30 18 * * *"), at(11, 11, 18, 30))).toBe(true);
  });

  test("rejects the next minute", () => {
    expect(matchesSchedule(parseSchedule("30 18 * * *"), at(11, 11, 18, 31))).toBe(false);
  });

  test("aligns a step against the clock", () => {
    const schedule = parseSchedule("*/15 * * * *");
    expect(matchesSchedule(schedule, at(11, 11, 10, 30))).toBe(true);
    expect(matchesSchedule(schedule, at(11, 11, 10, 31))).toBe(false);
    expect(matchesSchedule(schedule, at(11, 11, 10, 45))).toBe(true);
  });

  test("honours the month field", () => {
    expect(matchesSchedule(parseSchedule("0 0 1 2 *"), at(2, 1, 0, 0))).toBe(true);
    expect(matchesSchedule(parseSchedule("0 0 1 2 *"), at(11, 1, 0, 0))).toBe(false);
  });

  test("never matches an impossible date", () => {
    expect(matchesSchedule(parseSchedule("0 0 31 2 *"), at(2, 28, 0, 0))).toBe(false);
  });

  test("matches when only the day-of-week is restricted", () => {
    const date = at(11, 15, 0, 0);
    const expected = date.getDay() === 1;
    expect(matchesSchedule(parseSchedule("0 0 * * 1"), date)).toBe(expected);
  });

  test("uses OR semantics when both day fields are restricted", () => {
    const schedule = parseSchedule("0 0 1 * 1");

    const firstOfMonth = at(11, 1, 0, 0);
    expect(matchesSchedule(schedule, firstOfMonth)).toBe(true);

    const monday = at(11, 1, 0, 0);
    while (monday.getDay() !== 1 || monday.getDate() === 1) {
      monday.setDate(monday.getDate() + 1);
    }
    expect(matchesSchedule(schedule, monday)).toBe(true);

    const neither = at(11, 1, 0, 0);
    while (neither.getDate() === 1 || neither.getDay() === 1) {
      neither.setDate(neither.getDate() + 1);
    }
    expect(matchesSchedule(schedule, neither)).toBe(false);
  });
});

describe("dueEntries", () => {
  const date = new Date(2026, 10, 11, 18, 30, 0, 0);

  test("keeps only the entries that match this minute", () => {
    const entries = [
      { schedule: "30 18 * * *", prompt: "a" },
      { schedule: "0 3 * * *", prompt: "b" },
      { schedule: "*/15 * * * *", prompt: "c" },
    ];
    expect(dueEntries(entries, date).map((entry) => entry.prompt)).toEqual(["a", "c"]);
  });

  test("preserves the configured order", () => {
    const entries = [
      { schedule: "*/5 * * * *", prompt: "first" },
      { schedule: "30 18 * * *", prompt: "second" },
    ];
    expect(dueEntries(entries, date).map((entry) => entry.prompt)).toEqual(["first", "second"]);
  });

  test("returns an empty list when nothing is due", () => {
    expect(dueEntries([{ schedule: "0 3 * * *", prompt: "nightly" }], date)).toEqual([]);
  });

  test("returns an empty list for an empty configuration", () => {
    expect(dueEntries([], date)).toEqual([]);
  });
});
