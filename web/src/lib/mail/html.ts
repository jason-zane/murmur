import sanitize from "sanitize-html";

const dimension = /^(?:0|[0-9]{1,4}(?:\.[0-9]{1,2})?(?:px|pt|em|rem|%)|auto)$/i;
const colour = /^(?:#[0-9a-f]{3,8}|[a-z]+|rgba?\([0-9.,%\s]+\)|hsla?\([0-9.,%\s]+\))$/i;
const spacing = /^(?:0|[0-9]{1,3}(?:\.[0-9]{1,2})?(?:px|pt|em|rem|%))(?: (?:0|[0-9]{1,3}(?:\.[0-9]{1,2})?(?:px|pt|em|rem|%))){0,3}$/i;
export const INLINE_IMAGE_TYPES = new Set(["image/png", "image/jpeg", "image/gif", "image/webp"]);
export const MAX_INLINE_IMAGE_BYTES = 2_000_000;
export function rasterDataURL(type: string, data: string) {
  return INLINE_IMAGE_TYPES.has(type.toLowerCase()) && data.length <= Math.ceil(MAX_INLINE_IMAGE_BYTES/3)*4 && /^[a-z0-9+/]+={0,2}$/i.test(data) ? `data:${type.toLowerCase()};base64,${data}` : undefined;
}
/** Server-only. Remote addresses remain inert until a reader explicitly permits them. */
export function safeMailHTML(html: string, inlineImages: ReadonlyMap<string,string> = new Map()) {
  return sanitize(html, {
    allowedTags: ["p","br","div","span","strong","b","em","i","u","s","blockquote","ul","ol","li","h1","h2","h3","h4","h5","h6","table","tbody","thead","tfoot","tr","td","th","caption","colgroup","col","pre","code","hr","a","img","center","font"],
    allowedAttributes: {"*":["style","dir","lang"],a:["href","title","target","rel"],img:["src","alt","title","width","height","data-concourse-image-src","data-concourse-unavailable-image","referrerpolicy"],table:["width","height","cellpadding","cellspacing","border","align","bgcolor"],td:["width","height","colspan","rowspan","align","valign","bgcolor"],th:["width","height","colspan","rowspan","align","valign","bgcolor"],col:["width","span"],font:["face","size","color"]},
    allowedSchemes: ["https","http","mailto"], allowedSchemesByTag: {img:["data"]}, allowProtocolRelative:false,
    allowedStyles: {"*": {
      "color":[colour],"background-color":[colour],"font-family":[/^[a-z0-9 ,\'"-]+$/i],"font-size":[dimension],"font-weight":[/^(?:normal|bold|[1-9]00)$/],"font-style":[/^(?:normal|italic)$/],"line-height":[dimension,/^[0-9](?:\.[0-9]{1,2})?$/],"text-align":[/^(?:left|right|center|justify)$/],"text-decoration":[/^(?:none|underline|line-through)$/],"vertical-align":[/^(?:top|middle|bottom|baseline)$/],"white-space":[/^(?:normal|pre|pre-wrap|pre-line|nowrap)$/],"width":[dimension],"height":[dimension],"max-width":[dimension],"min-width":[dimension],"padding":[spacing],"padding-top":[dimension],"padding-bottom":[dimension],"padding-left":[dimension],"padding-right":[dimension],"margin":[spacing,/^auto$/],"margin-top":[dimension],"margin-bottom":[dimension],"margin-left":[dimension],"margin-right":[dimension],"border-collapse":[/^(?:collapse|separate)$/],"border-spacing":[spacing],"border-radius":[spacing],"border-color":[colour],"border-width":[dimension],"border-style":[/^(?:none|solid|dashed|dotted|double)$/],"border":[/^(?:0|[0-9]{1,2}px (?:solid|dashed|dotted|double) (?:#[0-9a-f]{3,8}|[a-z]+))$/i],"display":[/^(?:block|inline|inline-block|table|table-row|table-cell|none)$/],
    }},
    transformTags: {
      a:(_tag,attrs)=>({tagName:"a",attribs:{...attrs,target:"_blank",rel:"noopener noreferrer"}}),
      img:(_tag,attrs)=>{
        // Never trust a sender-provided custom attribute, srcset, SVG or CSS URL.
        const {src,alt,title,width,height,style}=attrs;
        const clean:Record<string,string>={alt:alt || "Email image",referrerpolicy:"no-referrer",...(title?{title}:{}),...(width&&/^\d{1,4}%?$/.test(width)?{width}:{}),...(height&&/^\d{1,4}%?$/.test(height)?{height}:{}),...(style?{style}:{})};
        const inline=src?.startsWith("cid:")?inlineImages.get(src.slice(4).replace(/^<|>$/g,"")):src;
        if(inline && /^data:image\/(?:png|jpeg|gif|webp);base64,[a-z0-9+/]+={0,2}$/i.test(inline) && inline.length<=Math.ceil(MAX_INLINE_IMAGE_BYTES/3)*4+40) clean.src=inline;
        else if(src) {
          try {const url=new URL(src);if(url.protocol==="https:"&&!url.username&&!url.password)clean["data-concourse-image-src"]=url.href;else clean["data-concourse-unavailable-image"]="true";} catch {clean["data-concourse-unavailable-image"]="true";}
        }
        return {tagName:"img",attribs:clean};
      },
    },
  });
}
