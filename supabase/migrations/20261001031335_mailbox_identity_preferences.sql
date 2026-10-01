-- Optional shared mailbox instrumentation. Existing signatures, row grants and RLS are unchanged.
-- Apply before deploying API consumers; NULL means deterministic default colour / initials.
alter table public.mail_preferences
  add column identity_colour text check (identity_colour in ('indigo','teal','violet','amber','slate')),
  add column identity_icon text check (identity_icon in ('initials','mail','work','personal','none'));
