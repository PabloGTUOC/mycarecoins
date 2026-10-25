/// Local midnight [days] calendar days after [d]'s date. Safe across clock changes.
DateTime addCalendarDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);
