/** Receives only server-sanitised HTML. Never call with source_html. */
export const remoteImageCount=(html:string)=>(html.match(/<img\b[^>]* data-concourse-image-src="/g) || []).length;
export const unavailableImageCount=(html:string)=>(html.match(/<img\b[^>]* data-concourse-unavailable-image="/g) || []).length;
export function mailReaderDocument(html:string,allowRemoteImages=false) {
 const body=allowRemoteImages?html.replaceAll(' data-concourse-image-src="',' src="'):html;
 return `<!doctype html><html><head><meta charset="utf-8"><meta name="referrer" content="no-referrer"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:${allowRemoteImages?" https:":""}; base-uri 'none'; form-action 'none'"><style>:root{color-scheme:light}body{margin:0;font:15px system-ui;color:#202124;background:#fff;line-height:1.6;overflow-wrap:anywhere}img{max-width:100%;height:auto}table{max-width:100%}blockquote{border-left:1px solid #aaa;margin-left:0;padding-left:1em;color:#555}</style></head><body>${body}</body></html>`;
}
