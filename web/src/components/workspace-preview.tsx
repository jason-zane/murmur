"use client";
import { Scheduling } from "@/app/scheduling/scheduling";
import { createBookingPreviewRequest } from "@/lib/scheduling/preview";
import { useMemo } from "react";
import { useRouter,useSearchParams } from "next/navigation";
import { Library } from "./library";
import { MailWorkspace } from "./mail-workspace";
import { sampleInviteCalendars,sampleInviteCheck } from "@/lib/invite-preview";
import { createWorkspacePreview,type PreviewState } from "@/lib/workspace-preview";
export function WorkspacePreview({view,state="normal"}:{view:"mail"|"library"|"booking";state?:PreviewState}) {
  const router=useRouter(),params=useSearchParams();
  const controls=<label className="preview-state"><span>Preview state</span><select aria-label="Preview state" value={state} onChange={event=>{const next=new URLSearchParams(params.toString());next.set("state",event.target.value);router.replace(`/prototype/follow-up?${next}`);}}><option value="normal">Normal</option><option value="slow">Slow loading</option><option value="empty">Empty</option><option value="error">Loading error</option>{view==="library" && <><option value="review-readonly">Follow-up read-only</option><option value="review-signed-out">Follow-up signed out</option></>}{view==="mail" && <option value="reader-error">Conversation error</option>}</select></label>;
  const preview=useMemo(()=>{let storage:Storage|undefined;try{if(typeof window!=="undefined")storage=localStorage;}catch{/* The mock transport reports storage unavailability without a cloud fallback. */}return createWorkspacePreview(storage,state);},[state]);
  const bookingRequest=useMemo(()=>createBookingPreviewRequest(),[]);
  if(view==="booking") return <Scheduling email="sam@example.invalid" googleReady={false} previewMode request={bookingRequest}/>;
  return view==="mail"?<MailWorkspace key={state} previewControls={controls} email="sam@example.com" userID="synthetic-workspace" googleReady={false} previewMode notesRequest={preview.notes} request={preview.mail} inviteReview={{calendars:sampleInviteCalendars,check:sampleInviteCheck,evidence:{pilot:"Could we review the checklist on Friday at 10? We haven’t agreed a date, time zone or duration."}}}/>:<Library key={state} previewControls={controls} email="sam@example.com" userID="synthetic-workspace" previewMode followUpEnabled request={preview.notes}/>;
}
