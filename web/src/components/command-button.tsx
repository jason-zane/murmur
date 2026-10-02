"use client";
import { useId, useState, type ButtonHTMLAttributes } from "react";

/** Optional help occupies no layout space. Ordinary buttons keep native Tab navigation. */
export function CommandButton({ help, onFocus, onBlur, onKeyDown, ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { help?: string }) {
  const id = useId();
  const [hovered, setHovered] = useState(false), [focused, setFocused] = useState(false), [dismissed, setDismissed] = useState(false);
  if (!help) return <button {...props} onFocus={onFocus} onBlur={onBlur} onKeyDown={onKeyDown}/>;
  const visible = (hovered || focused) && !dismissed && !props.disabled;
  return <span className="command-help" onMouseEnter={()=>{setHovered(true);setDismissed(false);}} onMouseLeave={()=>setHovered(false)}>
    <button {...props} aria-describedby={[props["aria-describedby"], visible ? id : undefined].filter(Boolean).join(" ") || undefined}
      onFocus={event=>{setFocused(true);setDismissed(false);onFocus?.(event);}}
      onBlur={event=>{setFocused(false);setDismissed(false);onBlur?.(event);}}
      onKeyDown={event=>{if(event.key==="Escape" && visible){setDismissed(true);event.stopPropagation();}onKeyDown?.(event);}}/>
    {visible && <span className="command-tooltip" role="tooltip" id={id}>{help}</span>}
  </span>;
}
