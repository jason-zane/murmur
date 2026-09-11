import { randomUUID } from "node:crypto";
import { adminClient } from "../supabase/server";
import { HttpError } from "../http";
export async function bookingOperation<T>(
  id: string,
  work: () => Promise<T>,
): Promise<T> {
  const db = adminClient(),
    key = randomUUID();
  const { data, error } = await db.rpc("claim_booking_operation", {
    p_id: id,
    p_key: key,
  });
  if (error) throw error;
  if (!data)
    throw new HttpError(
      409,
      "This booking is being updated. Try again in a moment.",
    );
  try {
    return await work();
  } finally {
    await db
      .from("bookings")
      .update({ operation_key: null, operation_until: null })
      .eq("id", id)
      .eq("operation_key", key);
  }
}
