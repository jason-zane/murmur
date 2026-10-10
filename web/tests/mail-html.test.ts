import {afterEach,describe,expect,it,vi} from "vitest";
import {safeMailHTML,rasterDataURL} from "../src/lib/mail/html";
import {mailReaderDocument,remoteImageCount} from "../src/lib/mail/reader-document";
import {readMessage} from "../src/lib/mail/model";
import {gmail} from "../src/lib/mail/gmail";
const image=Buffer.from("synthetic PNG bytes").toString("base64");
afterEach(()=>vi.unstubAllGlobals());
describe("rich email rendering and image privacy",()=>{
 it("preserves table layout, safe inline typography and image dimensions",()=>{
  const html=safeMailHTML('<table width="600" cellpadding="20" style="border-collapse:collapse;background-color:#f4f4f4"><tr><td colspan="2" style="color:#123456;font-family:Arial, sans-serif;font-size:18px;padding:12px 24px;text-align:center"><strong>Project update</strong><img width="240" height="80" src="https://cdn.example.invalid/logo.png"></td></tr></table>');
  expect(html).toContain('width="600"');expect(html).toContain('cellpadding="20"');expect(html).toContain('colspan="2"');expect(html).toContain('font-size:18px');expect(html).toContain('padding:12px 24px');expect(html).toContain('width="240"');expect(html).toContain('data-concourse-image-src="https://cdn.example.invalid/logo.png"');expect(html).not.toContain(' src=');
 });
 it("blocks script, form, SVG, style URL, forged remote attributes and unsafe image schemes",()=>{
  const html=safeMailHTML('<style>@import "https://evil.invalid/"</style><script>alert(1)</script><svg onload="x()"></svg><form><input></form><div style="position:fixed;inset:0;background-image:url(https://evil.invalid);color:expression(x());font-family:url(https://evil.invalid)">Text</div><img data-concourse-image-src="https://forged.invalid" onerror="x()"><img srcset="https://evil.invalid/x 2x" src="javascript:x()"><img src="data:image/svg+xml;base64,AAAA"><img src="//evil.invalid/x"><img src="https://user:pass@example.invalid/x">');
  expect(html).not.toMatch(/<script|<style|<svg|<form|<input|onerror|onload|position|inset|url\(|expression|srcset|data-concourse-image-src|javascript:|svg\+xml|user:pass/);expect(html).toContain("Text");
 });
 it("requires explicit reader opt-in and scopes activation to server-generated placeholders",()=>{
  const html=safeMailHTML('<img src="https://cdn.example.invalid/hero.png?tracking=1"><a href="https://example.invalid">Open</a>');
  const blocked=mailReaderDocument(html),allowed=mailReaderDocument(html,true);
  expect(remoteImageCount(html)).toBe(1);expect(blocked).toContain("img-src data:;");expect(blocked).not.toContain(' src="https:');expect(allowed).toContain("img-src data: https:;");expect(allowed).toContain(' src="https://cdn.example.invalid/hero.png?tracking=1"');expect(mailReaderDocument(html,false)).toBe(blocked);expect(allowed).toContain('rel="noopener noreferrer"');expect(allowed).toContain('referrerpolicy="no-referrer"');expect(allowed).toContain("default-src 'none'");
 });
 it("resolves an owned MIME CID as a bounded raster data image, never SVG",()=>{
  const payload={parts:[{mimeType:"text/html",body:{data:Buffer.from('<p>Hello</p><img src="cid:logo">').toString("base64url")}},{mimeType:"image/png",headers:[{name:"Content-ID",value:"<logo>"}],body:{data:Buffer.from("synthetic PNG bytes").toString("base64url"),size:19}}]};
  const message=readMessage({id:"message",threadId:"thread",payload});expect(message.html).toContain(`src="data:image/png;base64,${image}"`);expect(message.source_html).toContain('src="cid:logo"');expect(rasterDataURL("image/svg+xml",image)).toBeUndefined();expect(rasterDataURL("image/png","A".repeat(3_000_000))).toBeUndefined();
 });
 it("does not silently choose between duplicate embedded image identities",()=>{
  const imagePart={mimeType:"image/png",headers:[{name:"Content-ID",value:"<duplicate>"}],body:{data:Buffer.from("image").toString("base64url")}};
  const m=readMessage({id:"m",threadId:"t",payload:{parts:[{mimeType:"text/html",body:{data:Buffer.from('<img src="cid:duplicate">').toString("base64url")}},imagePart,imagePart]}});expect(m.html).not.toContain(' src=');expect(m.html).toContain("data-concourse-unavailable-image");
 });
 it("hydrates only bounded CID raster attachments using the existing mailbox transport",async()=>{
  const payload={parts:[{mimeType:"text/html",body:{data:Buffer.from('<img src="cid:logo">').toString("base64url")}},{mimeType:"image/png",filename:"logo.png",headers:[{name:"Content-ID",value:"<logo>"}],body:{attachmentId:"logo",size:19}},{mimeType:"image/svg+xml",headers:[{name:"Content-ID",value:"<svg>"}],body:{attachmentId:"svg",size:19}},{mimeType:"image/png",headers:[{name:"Content-ID",value:"<large>"}],body:{attachmentId:"large",size:2_000_001}}]};
  const calls=vi.fn(async(input:RequestInfo|URL)=>Response.json(String(input).endsWith("attachments/logo")?{data:Buffer.from("synthetic PNG bytes").toString("base64url"),size:19}:{id:"m",threadId:"t",payload}));vi.stubGlobal("fetch",calls);
  const hydrated=readMessage(await gmail("synthetic-fixture-only").message("m"));expect(hydrated.html).toContain('src="data:image/png;base64,');expect(calls).toHaveBeenCalledTimes(2);expect(calls.mock.calls.some(([url])=>String(url).includes("attachments/svg")||String(url).includes("attachments/large"))).toBe(false);
 });
 it("retains readable text and marks an optional image unavailable on provider failure",async()=>{
  const payload={parts:[{mimeType:"text/html",body:{data:Buffer.from('<p>Read this update.</p><img src="cid:logo">').toString("base64url")}},{mimeType:"image/png",headers:[{name:"Content-ID",value:"<logo>"}],body:{attachmentId:"logo",size:19}}]};
  vi.stubGlobal("fetch",vi.fn(async(input:RequestInfo|URL)=>String(input).endsWith("attachments/logo")?Response.json({error:"Synthetic provider error"},{status:429}):Response.json({id:"m",threadId:"t",payload})));
  const message=readMessage(await gmail("synthetic-fixture-only").message("m"));expect(message.text).toContain("Read this update.");expect(message.html).toContain("data-concourse-unavailable-image");expect(message.attachments[0].id).toBe("logo");
 });
});
