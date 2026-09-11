# Workspace design review — 11 September 2026

The working interface uses neutral surfaces, system typography and indigo for interaction.
Calendar entries are information rows, not coloured cards. Reading widths belong to notes;
workspaces and lists use the available content width.

| Area | Finding | Resolution |
| --- | --- | --- |
| Mac toolbar | Custom outlined and filled buttons were nested inside the system toolbar capsule | Native labelled toolbar buttons; remove repeated Settings actions |
| Navigation | Shared width had a conflicting Mac maximum; row size and type differed | Fixed shared width, shared row-height and font-size tokens, matching web mark proportions |
| Calendar entries | Purple wash, left stripe and rounded cards overstated ordinary meetings | Plain time/title/context rows with rules and neutral hover; no redundant “Calendar meeting” subtitle |
| Calendar controls | Mac segmented control and search stretched excessively | Bounded controls, with date navigation separate from view selection |
| Date selection | Mac segmented date input was awkward to browse | Reuse the Home month chooser in a popover; preserve native keyboard date input on web and share its styling across exception editors |
| Agenda | Empty days dominated the list | Show days containing meetings and a single empty-period message; keep empty days in Day and Week |
| Month | Only a small Home calendar existed | Main Month view on both platforms, Monday-first grid, today marker, three visible meetings and overflow into Day |
| Month navigation | Adding months to arbitrary dates can skip a month | Navigate from the first day of each month; grid includes leading/trailing dates |
| Density | Long entries and blank gutters made Dictation difficult to scan | Full-width list, expandable long entries, visible copy/delete actions |
| Embedded pages | Hidden web sidebar still consumed width on Mac | Remove width subtraction for embedded workspace pages |

Native controls keep platform behaviour rather than reproducing browser controls pixel for
pixel. Page width, navigation dimensions, hierarchy, names and meeting representation are
shared. Dates and times remain in the person's current calendar time zone. Booking
availability retains its explicitly selected scheduling time zone.

The browser month grid scrolls horizontally on narrow windows to preserve legible meeting
rows. Selecting a date opens Day; selecting a meeting opens existing meeting details.
No recording, email or booking action is triggered by navigation.
