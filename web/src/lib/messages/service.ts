import { adminClient } from "../supabase/server";
import { accessToken, connectionsFor } from "../calendar";
import { HttpError } from "../http";
import { bookingOperation } from "../scheduling/operation";
import {
  renderTemplate,
  messageDue,
  skipReason,
  mimeMessage,
  followUpDraft,
} from "./schema";
export const SEND_SCOPE = "https://www.googleapis.com/auth/gmail.send";
const stamp = () => new Date().toISOString();
export async function materialiseMessages() {
  const db = adminClient();
  const { data: rules, error } = await db
    .from("booking_message_rules")
    .select("*")
    .eq("enabled", true)
    .limit(1000);
  if (error) throw error;
  for (const rule of rules ?? []) {
    const { data: settings } = await db
      .from("mail_settings")
      .select("enabled")
      .eq("user_id", rule.user_id)
      .maybeSingle();
    if (!settings?.enabled) continue;
    const { data: bookings, error } = await db
      .from("bookings")
      .select("*")
      .eq("event_type_id", rule.event_type_id)
      .eq("user_id", rule.user_id)
      .eq("status", "confirmed")
      .gt("ends_at", new Date(Date.now() - 31 * 86400000).toISOString())
      .lt("starts_at", new Date(Date.now() + 31 * 86400000).toISOString())
      .limit(1000);
    if (error) throw error;
    for (const b of bookings ?? []) {
      if (rule.kind === "thank_you" && b.attendance !== "completed") continue;
      const due = messageDue(
        rule.kind,
        b.starts_at,
        b.ends_at,
        rule.offset_minutes,
      );
      const late =
        Date.parse(due) < Date.parse(b.created_at) ||
        (rule.kind !== "thank_you" && Date.parse(b.starts_at) <= Date.now());
      const { error } = await db.from("booking_messages").upsert(
        {
          user_id: b.user_id,
          booking_id: b.id,
          rule_id: rule.id,
          schedule_key: `${rule.id}:${b.id}:${new Date(b.starts_at).toISOString()}`,
          booking_start: b.starts_at,
          due_at: due,
          kind: rule.kind,
          status: late ? "skipped" : "scheduled",
          error: late
            ? "Booked too late for this message, or the meeting has already started."
            : null,
        },
        { onConflict: "schedule_key", ignoreDuplicates: true },
      );
      if (error) throw error;
    }
  }
}
export async function dispatchMessage(id: string, userID?: string) {
  const db = adminClient();
  let query = db.from("booking_messages").select("*").eq("id", id);
  if (userID) query = query.eq("user_id", userID);
  const { data: initial, error } = await query.maybeSingle();
  if (error) throw error;
  if (!initial) throw new HttpError(404, "Message not found.");
  return bookingOperation(initial.booking_id, async () => {
    const { data: m } = await db
      .from("booking_messages")
      .select("*")
      .eq("id", id)
      .single();
    if (!m || !["scheduled", "draft", "failed"].includes(m.status))
      throw new HttpError(
        409,
        "This message has already been handled. Check its send history.",
      );
    if (
      !userID &&
      (m.status !== "scheduled" || Date.parse(m.due_at) > Date.now())
    )
      return { status: m.status };
    const [{ data: b }, { data: settings }, { data: rule }] = await Promise.all(
      [
        db
          .from("bookings")
          .select("*")
          .eq("id", m.booking_id)
          .eq("user_id", m.user_id)
          .single(),
        db
          .from("mail_settings")
          .select("*")
          .eq("user_id", m.user_id)
          .maybeSingle(),
        m.rule_id
          ? db
              .from("booking_message_rules")
              .select("*")
              .eq("id", m.rule_id)
              .eq("user_id", m.user_id)
              .maybeSingle()
          : Promise.resolve({ data: null }),
      ],
    );
    const reason = b
      ? skipReason(m, b, m.kind === "follow_up" || Boolean(rule?.enabled))
      : "Booking removed.";
    const expired =
      m.kind !== "follow_up" &&
      m.kind !== "thank_you" &&
      b &&
      Date.parse(b.starts_at) <= Date.now();
    if (reason || expired) {
      await db
        .from("booking_messages")
        .update({
          status: "skipped",
          error: reason || "Meeting already started.",
          updated_at: stamp(),
        })
        .eq("id", id);
      return { status: "skipped" };
    }
    if (!settings?.enabled || !settings.connection_id) {
      await db
        .from("booking_messages")
        .update({
          status: "failed",
          error:
            "Email sending is paused. Reconnect or enable your sender before retrying.",
          updated_at: stamp(),
        })
        .eq("id", id);
      throw new HttpError(
        409,
        "Connect and enable an email sender in Connections first.",
      );
    }
    if (rule && !userID) {
      const due = messageDue(
        rule.kind,
        b.starts_at,
        b.ends_at,
        rule.offset_minutes,
      );
      if (Date.parse(due) > Date.now()) {
        await db
          .from("booking_messages")
          .update({ due_at: due, updated_at: stamp() })
          .eq("id", id);
        return { status: "scheduled" };
      }
    }
    const { data: type } = b.event_type_id
      ? await db
          .from("event_types")
          .select("email_connection_id")
          .eq("id", b.event_type_id)
          .eq("user_id", m.user_id)
          .maybeSingle()
      : { data: null };
    const connection = (await connectionsFor(m.user_id)).find(
      (c) => c.id === (type?.email_connection_id || settings.connection_id),
    );
    if (!connection?.email) {
      await db
        .from("booking_messages")
        .update({
          status: "failed",
          error: "Email sender disconnected.",
          updated_at: stamp(),
        })
        .eq("id", id);
      throw new HttpError(409, "Reconnect your email sender in Connections.");
    }
    let token: string;
    try {
      token = await accessToken(connection);
      if (!connection.scopes.includes(SEND_SCOPE))
        throw new Error("Allow sending email in Connections.");
    } catch (e) {
      await db
        .from("booking_messages")
        .update({
          status: "failed",
          error: "Email access expired. Reconnect, then retry.",
          updated_at: stamp(),
        })
        .eq("id", id);
      throw e;
    }
    const values = {
      guest_name: b.guest_name,
      meeting_title: b.title,
      meeting_time:
        new Date(b.starts_at).toLocaleString("en-AU", {
          timeZone: b.guest_time_zone,
          dateStyle: "full",
          timeStyle: "short",
        }) + ` (${b.guest_time_zone})`,
      join_link:
        b.meeting_url || "See your calendar invitation for meeting details.",
    };
    const subject = (
        rule ? renderTemplate(rule.subject, values) : m.subject
      ).replace(/[\r\n]+/g, " "),
      body = rule ? renderTemplate(rule.body, values) : m.body;
    const { data: allowed, error: rateError } = await db.rpc(
      "hit_booking_rate_limit",
      {
        p_bucket: `mail-daily:${m.user_id}`,
        p_limit: 100,
        p_window_seconds: 86400,
      },
    );
    if (rateError) throw rateError;
    if (!allowed) {
      await db
        .from("booking_messages")
        .update({
          status: "failed",
          error:
            "Your daily email sending limit has been reached. Retry tomorrow.",
          updated_at: stamp(),
        })
        .eq("id", id);
      throw new HttpError(429, "Your email sending limit has been reached.");
    }
    const raw = mimeMessage(connection.email, b.guest_email, subject, body, id);
    // Claim before the network call. An abandoned Sending row is never blindly retried.
    const { data: claimed, error: claimError } = await db
      .from("booking_messages")
      .update({
        status: "sending",
        subject,
        body,
        recipient: b.guest_email,
        sender: connection.email,
        error: null,
        updated_at: stamp(),
      })
      .eq("id", id)
      .in("status", ["scheduled", "draft", "failed"])
      .select("id")
      .maybeSingle();
    if (claimError) throw claimError;
    if (!claimed)
      throw new HttpError(409, "This message is already being sent.");
    try {
      const response = await fetch(
        "https://gmail.googleapis.com/gmail/v1/users/me/messages/send",
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ raw }),
          signal: AbortSignal.timeout(15000),
        },
      );
      if (!response.ok) {
        const definite = [400, 401, 403, 429].includes(response.status);
        await db
          .from("booking_messages")
          .update({
            status: definite ? "failed" : "needs_attention",
            error: definite
              ? "Google did not accept this email. Check your connection or sending limit, then retry."
              : "Google returned an uncertain result. Check Sent mail before taking further action.",
            updated_at: stamp(),
          })
          .eq("id", id);
        return { status: definite ? "failed" : "needs_attention" };
      }
      const sent = await response.json();
      const { error } = await db
        .from("booking_messages")
        .update({ status: "sent", provider_id: sent.id, updated_at: stamp() })
        .eq("id", id);
      if (error) throw error;
      return { status: "sent" };
    } catch {
      await db
        .from("booking_messages")
        .update({
          status: "needs_attention",
          error:
            "Sending was interrupted. Check Sent mail; this message will not be retried automatically.",
          updated_at: stamp(),
        })
        .eq("id", id);
      return { status: "needs_attention" };
    }
  });
}
export async function runMessages() {
  const db = adminClient();
  await db
    .from("booking_messages")
    .update({
      status: "needs_attention",
      error:
        "Sending was interrupted. Check Sent mail before taking further action.",
      updated_at: stamp(),
    })
    .eq("status", "sending")
    .lt("updated_at", new Date(Date.now() - 180000).toISOString());
  await materialiseMessages();
  await materialiseFollowUps();
  const { data, error } = await db
    .from("booking_messages")
    .select("id")
    .eq("status", "scheduled")
    .lte("due_at", stamp())
    .order("due_at")
    .limit(3);
  if (error) throw error;
  const results = [];
  for (const m of data ?? []) {
    try {
      results.push(await dispatchMessage(m.id));
    } catch {
      results.push({ status: "paused" });
    }
  }
  return { processed: results.length, results };
}

export async function materialiseFollowUps() {
  const db = adminClient();
  const { data: settings, error } = await db
    .from("mail_settings")
    .select("user_id")
    .eq("follow_up_drafts", true)
    .limit(1000);
  if (error) throw error;
  for (const setting of settings ?? []) {
    const { data: notes, error } = await db
      .from("sessions")
      .select("id,document")
      .eq("user_id", setting.user_id)
      .is("deleted_at", null)
      .order("updated_at", { ascending: false })
      .limit(100);
    if (error) throw error;
    for (const n of notes ?? []) {
      const doc = n.document,
        session = doc?.session,
        bid = session?.booking?.bookingID;
      if (
        !bid ||
        session.state !== "noted" ||
        session.engine === "Notes" ||
        !doc.note
      )
        continue;
      const { data: b } = await db
        .from("bookings")
        .select("id,starts_at,guest_name,title")
        .eq("id", bid)
        .eq("user_id", setting.user_id)
        .eq("status", "confirmed")
        .maybeSingle();
      if (!b) continue;
      const { error } = await db.from("booking_messages").upsert(
        {
          user_id: setting.user_id,
          booking_id: b.id,
          schedule_key: `follow-up:${b.id}`,
          booking_start: b.starts_at,
          due_at: stamp(),
          kind: "follow_up",
          status: "draft",
          subject: `Following up: ${b.title}`,
          body: followUpDraft(doc.note, b.guest_name),
        },
        { onConflict: "schedule_key", ignoreDuplicates: true },
      );
      if (error) throw error;
    }
  }
}
