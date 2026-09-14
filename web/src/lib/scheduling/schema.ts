import { z } from "zod";
import { isTimeZone } from "./availability";

const time = z
  .string()
  .regex(/^(([01]\d|2[0-3]):[0-5]\d|24:00)$/, "Use a time such as 09:00.");
const range = z
  .object({ start: time, end: time })
  .refine(
    (r) => r.start < r.end,
    "Each block of hours must end after it starts.",
  );

export const RESERVED_HANDLES = ["manage", "api", "new"];
export const TEMPLATES = [
  "meeting",
  "oneOnOne",
  "standup",
  "interview",
] as const;
export const LOCATIONS = [
  "google_meet",
  "video_link",
  "in_person",
  "phone",
] as const;

export const timeZoneSchema = z
  .string()
  .max(64)
  .refine(isTimeZone, "Choose a valid time zone.");
export const handleSchema = z
  .string()
  .trim()
  .toLowerCase()
  .regex(
    /^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$/,
    "Use 3–40 lowercase letters, numbers or hyphens, starting and ending with a letter or number.",
  )
  .refine(
    (h) => !RESERVED_HANDLES.includes(h),
    "That link name is reserved. Choose another.",
  );
export const slugSchema = z
  .string()
  .trim()
  .toLowerCase()
  .regex(
    /^[a-z0-9]([a-z0-9-]{0,48}[a-z0-9])?$/,
    "Use lowercase letters, numbers or hyphens.",
  );

export const weeklyHoursSchema = z
  .array(
    z
      .object({
        days: z.array(z.number().int().min(0).max(6)).min(1).max(7),
        start: time,
        end: time,
      })
      .refine(
        (r) => r.start < r.end,
        "Each block of hours must end after it starts.",
      ),
  )
  .max(50);
export const dateOverridesSchema = z
  .array(
    z.object({
      date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
      ranges: z.array(range).max(10),
    }),
  )
  .max(400);

export const availabilitySchema = z.object({
  time_zone: timeZoneSchema,
  weekly_hours: weeklyHoursSchema,
  date_overrides: dateOverridesSchema,
});
export const scheduleSchema = availabilitySchema.extend({
  name: z.string().trim().min(1).max(120),
});

export const profileSchema = z.object({
  handle: handleSchema,
  display_name: z
    .string()
    .trim()
    .min(1, "Add the name guests will see.")
    .max(120),
  time_zone: timeZoneSchema,
  weekly_hours: weeklyHoursSchema,
  date_overrides: dateOverridesSchema,
  destination_connection_id: z.uuid().nullable(),
  destination_calendar_id: z.string().min(1).max(1024).nullable(),
});

export const questionSchema = z.object({
  id: z.string().regex(/^[a-z0-9-]{1,40}$/),
  label: z.string().trim().min(1).max(200),
  required: z.boolean(),
  long: z.boolean(),
});

export const eventTypeSchema = z
  .object({
    email_connection_id: z.uuid().nullable().optional(),
    availability_schedule_id: z.uuid().nullable().optional(),
    availability_override: availabilitySchema.nullable().optional(),
    destination_connection_id: z.uuid().nullable().optional(),
    destination_calendar_id: z.string().min(1).max(1024).nullable().optional(),
    slug: slugSchema,
    title: z.string().trim().min(1, "Give this meeting type a name.").max(120),
    description: z.string().max(2000).default(""),
    duration_minutes: z.number().int().min(5).max(480),
    location_kind: z.enum(LOCATIONS),
    location_detail: z.string().trim().max(500).nullable().default(null),
    summary_template: z.enum(TEMPLATES),
    questions: z.array(questionSchema).max(10).default([]),
    minimum_notice_minutes: z.number().int().min(0).max(43200),
    buffer_before_minutes: z.number().int().min(0).max(240),
    buffer_after_minutes: z.number().int().min(0).max(240),
    slot_interval_minutes: z
      .number()
      .int()
      .min(5)
      .max(480)
      .nullable()
      .default(null),
    booking_window_days: z.number().int().min(1).max(365),
    daily_limit: z.number().int().min(1).max(50).nullable().default(null),
    active: z.boolean().default(true),
    position: z.number().int().min(0).max(1000).default(0),
  })
  .superRefine((value, ctx) => {
    if (value.availability_schedule_id && value.availability_override)
      ctx.addIssue({
        code: "custom",
        message: "Choose a saved schedule or custom hours, not both.",
      });
    if (
      Boolean(value.destination_connection_id) !==
      Boolean(value.destination_calendar_id)
    )
      ctx.addIssue({
        code: "custom",
        message: "Choose both an account and a destination calendar.",
      });
    if (value.location_kind === "video_link") {
      try {
        if (new URL(value.location_detail || "").protocol !== "https:")
          throw new Error();
      } catch {
        ctx.addIssue({
          code: "custom",
          path: ["location_detail"],
          message: "Add your meeting room link, starting with https://.",
        });
      }
    }
    if (value.location_kind === "in_person" && !value.location_detail)
      ctx.addIssue({
        code: "custom",
        path: ["location_detail"],
        message: "Add the address where you'll meet.",
      });
    if (
      new Set(value.questions.map((q) => q.id)).size !== value.questions.length
    )
      ctx.addIssue({
        code: "custom",
        path: ["questions"],
        message: "Each question needs its own ID.",
      });
  });

export const bookingRequestSchema = z.object({
  start: z.iso.datetime({ offset: true }),
  name: z.string().trim().min(1, "Add your name.").max(120),
  email: z
    .email("Add an email address where you can receive the invitation.")
    .max(320),
  time_zone: timeZoneSchema,
  phone: z.string().trim().max(40).optional(),
  answers: z.record(z.string(), z.string().max(2000)).default({}),
});

export type Profile = z.infer<typeof profileSchema> & { user_id: string };
export type EventType = z.infer<typeof eventTypeSchema> & {
  id: string;
  user_id: string;
};
export type Question = z.infer<typeof questionSchema>;

/** The first readable validation message, for a response a person can act on. */
export function firstIssue(error: z.ZodError) {
  return error.issues[0]?.message || "Check the details and try again.";
}
