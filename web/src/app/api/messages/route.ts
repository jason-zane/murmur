import { z } from "zod";
import { requireEditor, failure, HttpError, limitedJSON } from "@/lib/http";
import { adminClient } from "@/lib/supabase/server";
import { connectionsFor } from "@/lib/calendar";
import { ruleSchema, draftSchema } from "@/lib/messages/schema";
import { bookingOperation } from "@/lib/scheduling/operation";
import { SEND_SCOPE, dispatchMessage } from "@/lib/messages/service";
const headers = { "Cache-Control": "private, no-store" };
export async function GET(request: Request) {
  try {
    const { client, user } = await requireEditor(request);
    const [settings, rules, messages, connections] = await Promise.all([
      client.from("mail_settings").select("*").maybeSingle(),
      client.from("booking_message_rules").select("*"),
      client
        .from("booking_messages")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(200),
      connectionsFor(user.id),
    ]);
    for (const r of [settings, rules, messages]) if (r.error) throw r.error;
    return Response.json(
      {
        settings: settings.data,
        rules: rules.data,
        messages: messages.data,
        senders: connections
          .filter((c) => c.scopes.includes(SEND_SCOPE))
          .map((c) => ({ id: c.id, email: c.email })),
      },
      { headers },
    );
  } catch (e) {
    return failure(e);
  }
}
export async function POST(request: Request) {
  try {
    const { user } = await requireEditor(request),
      db = adminClient(),
      body = await limitedJSON(request, 30000, "This message is too large.");
    if (body.action === "settings") {
      const value = z
        .object({
          connection_id: z.uuid().nullable(),
          enabled: z.boolean(),
          follow_up_drafts: z.boolean().default(true),
        })
        .parse(body);
      const c = (await connectionsFor(user.id)).find(
        (c) => c.id === value.connection_id,
      );
      if (value.enabled && !c?.scopes.includes(SEND_SCOPE))
        throw new HttpError(400, "Choose a connected email sender.");
      if (value.connection_id && !c)
        throw new HttpError(400, "Choose your own email account.");
      const { error } = await db
        .from("mail_settings")
        .upsert({ ...value, user_id: user.id });
      if (error) throw error;
    } else if (body.action === "rule") {
      const parsed = ruleSchema.safeParse(body);
      if (!parsed.success)
        throw new HttpError(400, parsed.error.issues[0].message);
      const { data: type } = await db
        .from("event_types")
        .select("id")
        .eq("id", parsed.data.event_type_id)
        .eq("user_id", user.id)
        .maybeSingle();
      if (!type) throw new HttpError(404, "Meeting type not found.");
      const { error } = await db
        .from("booking_message_rules")
        .upsert(
          { ...parsed.data, user_id: user.id },
          { onConflict: "event_type_id,kind" },
        );
      if (error) throw error;
    } else if (body.action === "draft") {
      const parsed = draftSchema.safeParse(body);
      if (!parsed.success)
        throw new HttpError(400, parsed.error.issues[0].message);
      const { data: b } = await db
        .from("bookings")
        .select("id,starts_at,status")
        .eq("id", parsed.data.booking_id)
        .eq("user_id", user.id)
        .maybeSingle();
      if (!b || b.status !== "confirmed")
        throw new HttpError(404, "Choose a confirmed booking.");
      const { data, error } = await db
        .from("booking_messages")
        .insert({
          user_id: user.id,
          booking_id: b.id,
          booking_start: b.starts_at,
          kind: "follow_up",
          status: "draft",
          subject: parsed.data.subject,
          body: parsed.data.body,
          due_at: new Date().toISOString(),
        })
        .select("id")
        .single();
      if (error) throw error;
      return Response.json(data, { headers });
    } else if (body.action === "edit") {
      const parsed = draftSchema
        .omit({ booking_id: true })
        .extend({ id: z.uuid() })
        .safeParse(body);
      if (!parsed.success)
        throw new HttpError(400, parsed.error.issues[0].message);
      const { id, ...value } = parsed.data;
      const { data: message } = await db
        .from("booking_messages")
        .select("booking_id")
        .eq("id", id)
        .eq("user_id", user.id)
        .maybeSingle();
      if (!message) throw new HttpError(404, "Message not found.");
      await bookingOperation(message.booking_id, async () => {
        const { data, error } = await db
          .from("booking_messages")
          .update({
            ...value,
            status: "draft",
            error: null,
            updated_at: new Date().toISOString(),
          })
          .eq("id", id)
          .eq("user_id", user.id)
          .eq("kind", "follow_up")
          .in("status", ["draft", "failed"])
          .select("id");
        if (error) throw error;
        if (!data?.length)
          throw new HttpError(
            409,
            "This draft can no longer be edited. Refresh its status.",
          );
      });
    } else if (body.action === "send") {
      const id = z.uuid().parse(body.id);
      // Bound manual sends as well as public booking abuse. Counts attempts, not only successes.
      const { data: allowed, error } = await db.rpc("hit_booking_rate_limit", {
        p_bucket: `mail:${user.id}`,
        p_limit: 30,
        p_window_seconds: 3600,
      });
      if (error) throw error;
      if (!allowed)
        throw new HttpError(
          429,
          "Your sending limit has been reached. Try again later.",
        );
      return Response.json(await dispatchMessage(id, user.id), { headers });
    } else if (body.action === "skip") {
      const id = z.uuid().parse(body.id);
      const { data, error } = await db
        .from("booking_messages")
        .update({
          status: "skipped",
          error: "Skipped by you.",
          updated_at: new Date().toISOString(),
        })
        .eq("id", id)
        .eq("user_id", user.id)
        .in("status", ["draft", "scheduled", "failed", "needs_attention"])
        .select("id");
      if (error) throw error;
      if (!data?.length)
        throw new HttpError(409, "This message can no longer be skipped.");
    } else throw new HttpError(400, "Choose a message action.");
    return Response.json({ saved: true }, { headers });
  } catch (e) {
    return failure(e);
  }
}
