//! # Instants
//!
//! A UTC instant at whole seconds and the spellings bodies and rows give
//! it: RFC 3339 with the `Z` designator (STORAGE Annex A.0), the RFC 5322
//! `date-time` a message states, and the iCalendar forms (RFC 5545 §3.3.4,
//! §3.3.5). The calendar is the proleptic Gregorian one, computed here so
//! no time library enters the crate.

use std::ops::Range;

/// Seconds since 1970-01-01T00:00:00Z.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Instant(pub i64);

const MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];
const WEEKDAYS: [&str; 7] = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

impl Instant {
    /// The instant of a civil date and time in UTC.
    pub fn at(year: i64, month: u32, day: u32, hour: u32, minute: u32, second: u32) -> Self {
        let days = days_from_civil(year, month, day);
        Self(days * 86_400 + i64::from(hour * 3600 + minute * 60 + second))
    }

    /// Reads an iCalendar UTC date-time, `20260801T100000Z`.
    pub fn from_ical_utc(text: &str) -> Self {
        let number = |range: Range<usize>| text[range].parse::<u32>().unwrap_or(0);
        Self::at(
            i64::from(number(0..4)),
            number(4..6),
            number(6..8),
            number(9..11),
            number(11..13),
            number(13..15),
        )
    }

    /// Reads an RFC 3339 UTC date-time, `2026-08-01T10:00:00Z`.
    pub fn from_rfc3339(text: &str) -> Self {
        Self::from_ical_utc(&text.replace(['-', ':'], ""))
    }

    /// The start of its UTC day.
    pub fn midnight(&self) -> Self {
        Self(self.0.div_euclid(86_400) * 86_400)
    }

    /// `2026-08-01T10:00:00Z`.
    pub fn rfc3339(&self) -> String {
        let (year, month, day, hour, minute, second) = self.parts();
        format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
    }

    /// `Sat, 01 Aug 2026 10:00:00 +0000`.
    pub fn rfc5322(&self) -> String {
        let (year, month, day, hour, minute, second) = self.parts();
        let weekday = WEEKDAYS[(self.0.div_euclid(86_400) + 4).rem_euclid(7) as usize];
        let month = MONTHS[month as usize - 1];
        format!("{weekday}, {day:02} {month} {year:04} {hour:02}:{minute:02}:{second:02} +0000")
    }

    /// `20260801T100000Z`.
    pub fn ical_utc(&self) -> String {
        format!("{}Z", self.ical_floating())
    }

    /// `20260801T100000`.
    pub fn ical_floating(&self) -> String {
        let (year, month, day, hour, minute, second) = self.parts();
        format!("{year:04}{month:02}{day:02}T{hour:02}{minute:02}{second:02}")
    }

    /// `20260801`.
    pub fn ical_date(&self) -> String {
        let (year, month, day, ..) = self.parts();
        format!("{year:04}{month:02}{day:02}")
    }

    fn parts(&self) -> (i64, u32, u32, u32, u32, u32) {
        let (year, month, day) = civil_from_days(self.0.div_euclid(86_400));
        let seconds = self.0.rem_euclid(86_400) as u32;
        (
            year,
            month,
            day,
            seconds / 3600,
            seconds / 60 % 60,
            seconds % 60,
        )
    }
}

fn days_from_civil(year: i64, month: u32, day: u32) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let year_of_era = year - era * 400;
    let month = i64::from(month);
    let shifted = if month > 2 { month - 3 } else { month + 9 };
    let day_of_year = (153 * shifted + 2) / 5 + i64::from(day) - 1;
    let day_of_era = year_of_era * 365 + year_of_era / 4 - year_of_era / 100 + day_of_year;
    era * 146_097 + day_of_era - 719_468
}

fn civil_from_days(days: i64) -> (i64, u32, u32) {
    let days = days + 719_468;
    let era = days.div_euclid(146_097);
    let day_of_era = days.rem_euclid(146_097);
    let year_of_era =
        (day_of_era - day_of_era / 1460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let shifted = (5 * day_of_year + 2) / 153;
    let day = (day_of_year - (153 * shifted + 2) / 5 + 1) as u32;
    let month = if shifted < 10 {
        shifted + 3
    } else {
        shifted - 9
    } as u32;
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    (year, month, day)
}

#[cfg(test)]
mod tests {
    use crate::time::Instant;

    #[test]
    fn the_dates_of_the_mail_fixtures_spell_as_their_headers_and_rows() {
        let basic = Instant::at(2026, 10, 6, 8, 30, 0);
        assert_eq!(basic.rfc5322(), "Tue, 06 Oct 2026 08:30:00 +0000");
        assert_eq!(basic.rfc3339(), "2026-10-06T08:30:00Z");

        let attachment = Instant::at(2026, 10, 5, 9, 0, 0);
        assert_eq!(attachment.rfc5322(), "Mon, 05 Oct 2026 09:00:00 +0000");
    }

    #[test]
    fn civil_dates_round_trip_across_leap_years_and_eras() {
        for (year, month, day) in [
            (1969, 12, 31),
            (1970, 1, 1),
            (2000, 2, 29),
            (2024, 2, 29),
            (2100, 3, 1),
            (9999, 12, 31),
        ] {
            let at = Instant::at(year, month, day, 23, 59, 59);
            let text = format!("{year:04}-{month:02}-{day:02}T23:59:59Z");
            assert_eq!(at.rfc3339(), text);
            assert_eq!(Instant::from_ical_utc(&at.ical_utc()), at);
        }
    }
}
