import sanitize from "sanitize-html";
import MailComposer from "nodemailer/lib/mail-composer";
import { z } from "zod";
import { decodeHTML } from "entities";
import { rasterDataURL, safeMailHTML } from "./html";
export { safeMailHTML } from "./html";
export const plainMailText=(html:string)=>decodeHTML(sanitize(html.replace(/<br\s*\/?\s*>|<\/(p|div|li|h[1-6])>/gi,"\n"),{allowedTags:[],allowedAttributes:{}})).trim();
export const MAIL_SCOPE="https://www.googleapis.com/auth/gmail.modify";
export const canMail=(scopes:string[])=>scopes.includes(MAIL_SCOPE);
export type MailPart={mimeType?:string;filename?:string;partId?:string;headers?:{name:string;value:string}[];body?:{data?:string;attachmentId?:string;size?:number};parts?:MailPart[]};
export type GmailMessage={id:string;threadId:string;snippet?:string;internalDate?:string;labelIds?:string[];payload?:MailPart};
export type MailMessage={id:string;thread_id:string;subject:string;from:string;to:string;cc:string;bcc:string;in_reply_to:string;reply_to:string;message_id:string;references:string;date:string;text:string;html:string;source_html:string;labels:string[];attachments:{id:string;name:string;type:string;size:number;cid?:string;data?:string}[]};
export function readMessage(message:GmailMessage):MailMessage {
 const headers=message.payload?.headers || [],h=(key:string)=>headers.find(v=>v.name.toLowerCase()===key)?.value || "";
 const text:string[]=[],html:string[]=[],attachments:MailMessage["attachments"]=[];
 function visit(part:MailPart) {
  const cid=part.headers?.find(h=>h.name.toLowerCase()==="content-id")?.value.replace(/^<|>$/g,"");
  if((part.filename || cid) && (part.body?.attachmentId || part.body?.data)) attachments.push({id:part.body.attachmentId || part.partId || "inline",name:part.filename || "inline-image",type:part.mimeType || "application/octet-stream",size:part.body.size || 0,cid,...(part.body?.data?{data:Buffer.from(part.body.data,"base64url").toString("base64")}: {})});
  else if(part.body?.data) {
   const decoded=Buffer.from(part.body.data,"base64url").toString("utf8");
   if(part.mimeType==="text/plain") text.push(decoded);
   if(part.mimeType==="text/html") html.push(decoded);
  }
  part.parts?.forEach(visit);
 }
 if(message.payload) visit(message.payload);
 const inlineImages=new Map<string,string>(),ambiguous=new Set<string>();
 for(const attachment of attachments) if(attachment.cid && attachment.data) {
  const image=rasterDataURL(attachment.type,attachment.data);if(!image)continue;
  if(inlineImages.has(attachment.cid))ambiguous.add(attachment.cid);else inlineImages.set(attachment.cid,image);
 }
 for(const cid of ambiguous)inlineImages.delete(cid);
 return {id:message.id,thread_id:message.threadId,subject:h("subject") || "(No subject)",from:h("from"),to:h("to"),cc:h("cc"),bcc:h("bcc"),in_reply_to:h("in-reply-to"),reply_to:h("reply-to"),message_id:h("message-id"),references:h("references"),date:new Date(Number.isFinite(Date.parse(h("date")))?Date.parse(h("date")):Number(message.internalDate || 0)).toISOString(),text:text.join("\n") || plainMailText(html.join("\n")),html:safeMailHTML(html.join("\n"),inlineImages),source_html:html.join("\n"),labels:message.labelIds || [],attachments};
}
const recipients=z.array(z.email()).max(100);
export const composeSchema=z.object({
 connection_id:z.uuid(),id:z.string().max(1024).optional(),revision:z.string().max(100).optional(),thread_id:z.string().max(1024).optional(),
 to:recipients,cc:recipients.default([]),bcc:recipients.default([]),subject:z.string().max(998).refine(v=>!/[\r\n]/.test(v),"Subject must be on one line."),
 text:z.string().max(1000000),html:z.string().max(1000000).optional(),in_reply_to:z.string().max(2000).refine(v=>!/[\r\n]/.test(v)).optional(),references:z.string().max(10000).refine(v=>!/[\r\n]/.test(v)).optional(),
 attachments:z.array(z.object({name:z.string().min(1).max(255),type:z.string().max(100),cid:z.string().max(998).refine(v=>!/[\r\n]/.test(v)).optional(),data:z.string().max(28000000).regex(/^[A-Za-z0-9+/]*={0,2}$/)})).max(20).default([]),
}).refine(v=>v.to.length+v.cc.length+v.bcc.length<=100,{message:"Use at most 100 recipients."}).refine(v=>v.attachments.reduce((n,a)=>n+Buffer.from(a.data,"base64").length,0)<=18000000,{message:"Attachments must total less than 18 MB."});
export type Compose=z.infer<typeof composeSchema>;
export async function composeMIME(v:Compose,from:string,operationID?:string) {
 const mail=new MailComposer({from,to:v.to,cc:v.cc,bcc:v.bcc,subject:v.subject,text:v.text,html:v.html,inReplyTo:v.in_reply_to,references:v.references,
 messageId:operationID?`<${operationID}@voice-notes.local>`:undefined,disableFileAccess:true,disableUrlAccess:true,
 attachments:v.attachments.map(a=>({filename:a.name,contentType:a.type,cid:a.cid,contentDisposition:a.cid?"inline":"attachment",content:Buffer.from(a.data,"base64")}))}).compile();
 // The Gmail API reads Bcc from the MIME envelope; retain it for provider dispatch.
 mail.keepBcc=true;
 return (await mail.build()).toString("base64url");
}
