import { decodeHTML } from "entities";
import { createHash } from "node:crypto";
export const draftRevision=(payload:unknown)=>createHash("sha256").update(JSON.stringify(payload)).digest("hex");
import { accessToken,connectionsFor } from "../calendar";
import { HttpError } from "../http";
import { canMail,readMessage,type GmailMessage,type MailPart } from "./model";
import { INLINE_IMAGE_TYPES, MAX_INLINE_IMAGE_BYTES } from "./html";
export async function ownMailbox(userID:string,accountID:string) {
 const account=(await connectionsFor(userID)).find(c=>c.id===accountID);
 if(!account || !canMail(account.scopes)) throw new HttpError(403,"Connect this Gmail inbox in Mail first.");
 const token=await accessToken(account);
 if(!canMail(account.scopes)) throw new HttpError(403,"Gmail access changed. Reconnect this inbox.");
 return {account,api:gmail(token)};
}
export function gmail(token:string) {
 async function call<T>(path:string,method="GET",body?:unknown):Promise<T> {
  const response=await fetch(`https://gmail.googleapis.com/gmail/v1/users/me/${path}`,{method,headers:{Authorization:`Bearer ${token}`,"Content-Type":"application/json"},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
  if(!response.ok) throw new HttpError(response.status===401||response.status===403?403:response.status===429?429:response.status===404?404:response.status===400?400:502,
   response.status===401||response.status===403?"Reconnect Gmail in Mail to restore access.":response.status===429?"Gmail is busy. Try again shortly.":response.status===404?"This message is no longer available.":"Gmail could not complete this request.");
  return response.status===204?{} as T:await response.json();
 }
 const enc=encodeURIComponent;
 async function hydrate(message:GmailMessage) {
  let imageBudget=4_000_000,imageCount=8;
  async function visit(part:MailPart) {
   if(!part.filename && ["text/plain","text/html"].includes(part.mimeType || "") && part.body?.attachmentId) {
    if((part.body.size || 0)>2000000) throw new HttpError(413,"This message body is too large to open here. Open it in Gmail.");
    const body=await call<{data:string;size:number}>(`messages/${enc(message.id)}/attachments/${enc(part.body.attachmentId)}`);part.body={...part.body,data:body.data};
   }
   const hasCID=part.headers?.some(header=>header.name.toLowerCase()==="content-id");
   if(hasCID && INLINE_IMAGE_TYPES.has((part.mimeType || "").toLowerCase()) && part.body?.attachmentId && !part.body.data) {
    const size=part.body.size || MAX_INLINE_IMAGE_BYTES;
    if(size<=MAX_INLINE_IMAGE_BYTES && size<=imageBudget && imageCount>0) {
     imageBudget-=size;imageCount--;
     try {
      const body=await call<{data:string;size:number}>(`messages/${enc(message.id)}/attachments/${enc(part.body.attachmentId)}`);
      if(body.size<=size && body.size<=MAX_INLINE_IMAGE_BYTES && body.data.length<=Math.ceil(size/3)*4)part.body={...part.body,data:body.data};
     } catch { /* Optional image failure must not discard the readable message. */ }
    }
   }
   for(const child of part.parts || []) await visit(child);
  }
  if(message.payload) await visit(message.payload);return message;
 }
 return {
  call,
  message:async(id:string)=>hydrate(await call<GmailMessage>(`messages/${enc(id)}?format=full`)),
  async list(query:string,page?:string) {
   const params=new URLSearchParams({maxResults:"30",q:query,...(page?{pageToken:page}:{})});
   const list=await call<{threads?:{id:string}[];nextPageToken?:string}>(`threads?${params}`);
   const items=[];
   // Bounded concurrency avoids bursts against per-account quotas.
   for(let i=0;i<(list.threads || []).length;i+=5) {
    const batch=await Promise.all((list.threads || []).slice(i,i+5).map(async t=>{
     const thread=await call<{id:string;messages:GmailMessage[]}>(`threads/${enc(t.id)}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Date`);
     const last=thread.messages.at(-1)!;return {...readMessage(last),id:t.id,count:thread.messages.length,snippet:decodeHTML(last.snippet || ""),unread:thread.messages.some(m=>m.labelIds?.includes("UNREAD")),starred:thread.messages.some(m=>m.labelIds?.includes("STARRED"))};
    }));items.push(...batch);
   }
   return {threads:items,next_page:list.nextPageToken || null};
  },
  async thread(id:string) {const t=await call<{messages:GmailMessage[]}>(`threads/${enc(id)}?format=full`);const messages=[];for(const m of t.messages) messages.push(readMessage(await hydrate(m)));return messages;},
  labels:()=>call<{labels:{id:string;name:string;type:string}[]}>("labels"),
  modify:(id:string,add:string[],remove:string[])=>call(`threads/${enc(id)}/modify`,"POST",{addLabelIds:add,removeLabelIds:remove}),
  draft:(id?:string,raw?:string,threadID?:string)=>call<{id:string;message:GmailMessage}>(id?`drafts/${enc(id)}`:"drafts",id?"PUT":"POST",{message:{raw,...(threadID?{threadId:threadID}:{})}}),
  async drafts(page?:string) {
   const list=await call<{drafts?:{id:string;message:{id:string;threadId:string}}[];nextPageToken?:string}>(`drafts?${new URLSearchParams({maxResults:"30",...(page?{pageToken:page}:{})})}`);
   const drafts=[];
   for(let i=0;i<(list.drafts || []).length;i+=5) drafts.push(...await Promise.all((list.drafts || []).slice(i,i+5).map(async d=>({id:d.id,message:readMessage(await call<GmailMessage>(`messages/${enc(d.message.id)}?format=metadata&metadataHeaders=Subject&metadataHeaders=To&metadataHeaders=Date`))}))));
   return {drafts,next_page:list.nextPageToken || null};
  },
  async getDraft(id:string) {const d=await call<{id:string;message:GmailMessage}>(`drafts/${enc(id)}?format=full`);return {...d,message:await hydrate(d.message)};},
  deleteDraft:(id:string)=>call(`drafts/${enc(id)}`,"DELETE"),
  attachment:(messageID:string,id:string)=>call<{data:string;size:number}>(`messages/${enc(messageID)}/attachments/${enc(id)}`),
 };
}
