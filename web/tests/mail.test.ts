import {describe,it,expect} from "vitest";
import {safeMailHTML,readMessage,composeSchema,composeMIME} from "../src/lib/mail/model";
describe("mail content boundary",()=>{
 it("removes active content and keeps remote images inert",()=>{
  const safe=safeMailHTML('<script>alert(1)</script><form action="https://evil"><input></form><img src="https://evil/track"><a href="javascript:alert(1)" onclick="x()">bad</a><p style="background:url(https://evil)">Hi</p><a href="https://example.com">link</a>');
  expect(safe).not.toMatch(/<script|<form|<input|onclick|javascript:|background| src=/);expect(safe).toContain('data-concourse-image-src="https://evil/track"');expect(safe).toContain('rel="noopener noreferrer"');expect(safe).toContain("Hi");
 });
 it("reads multipart mail without mistaking attachments for message text",()=>{
  const m=readMessage({id:"m",threadId:"t",payload:{headers:[{name:"Subject",value:"Planning"}],parts:[{mimeType:"text/plain",body:{data:Buffer.from("Hello").toString("base64url")}},{mimeType:"application/pdf",filename:"agenda.pdf",body:{attachmentId:"a",size:100}}]}});
  expect(m.text).toBe("Hello");expect(m.subject).toBe("Planning");expect(m.attachments[0].name).toBe("agenda.pdf");
 });
 it("rejects header injection and invalid recipients",()=>{
  const v={connection_id:"00000000-0000-4000-8000-000000000000",to:["recipient@example.com"],subject:"Planning\r\nBcc: evil@example.com",text:"Hello"};
  expect(composeSchema.safeParse(v).success).toBe(false);expect(composeSchema.safeParse({...v,subject:"OK",to:["not-an-address"]}).success).toBe(false);
 });
 it("preserves formatted draft bodies, Bcc, reply headers and inline image identities",async()=>{
  const html='<p>Hello &amp; welcome</p><img src="cid:logo"><script>unsafe()</script>';
  const message=readMessage({id:"draft-message",threadId:"reply-thread",payload:{headers:[{name:"Bcc",value:"private@example.com"},{name:"In-Reply-To",value:"<original@example.com>"}],parts:[{mimeType:"text/html",body:{data:Buffer.from(html).toString("base64url")}},{mimeType:"image/png",headers:[{name:"Content-ID",value:"<logo>"}],body:{attachmentId:"image",size:10}}]}});
  expect(message.text).toBe("Hello & welcome");expect(message.html).not.toMatch(/script| src=/);expect(message.html).toContain('data-concourse-unavailable-image="true"');expect(message.source_html).toBe(html);expect(message.bcc).toBe("private@example.com");expect(message.in_reply_to).toBe("<original@example.com>");expect(message.attachments[0].cid).toBe("logo");
  const compose=composeSchema.parse({connection_id:"00000000-0000-4000-8000-000000000000",to:["recipient@example.com"],subject:"Formatted",text:message.text,html:message.source_html,attachments:[{name:"logo.png",type:"image/png",cid:"logo",data:Buffer.from("fixture").toString("base64")}]});
  const raw=Buffer.from(await composeMIME(compose,"sender@example.com"),"base64url").toString();expect(raw).toContain("text/html");expect(raw).toContain("Content-ID: <logo>");expect(raw).toContain("multipart/related");
 });
 it("composes unicode, Bcc and attachments using MIME",async()=>{
  const v=composeSchema.parse({connection_id:"00000000-0000-4000-8000-000000000000",to:["recipient@example.com"],bcc:["private@example.com"],subject:"Résumé",text:"Hello",attachments:[{name:"agenda.txt",type:"text/plain",data:Buffer.from("agenda").toString("base64")}]});
  const raw=Buffer.from(await composeMIME(v,"sender@example.com","op"),"base64url").toString();expect(raw).toContain("multipart/mixed");expect(raw).toContain("Bcc: private@example.com");expect(raw).toContain("agenda.txt");expect(raw).toContain("Message-ID: <op@voice-notes.local>");
 });
});
