"use client";
import { FileText, Plus, Search, X } from "lucide-react";

export type WorkspaceListItem = { id: string; title: string; meta: string; pinned?: boolean };
/** Shared master list for live notes and the explicitly labelled synthetic review. */
export function WorkspaceList({ title, items, selected, query, onQuery, onSelect, onNew, children, loading, error, onRetry }: {
  title: string; items: WorkspaceListItem[]; selected?: string | null;
  query: string; onQuery: (value: string) => void; onSelect: (id: string) => void;
  onNew?: () => void; children?: React.ReactNode; loading?: boolean; error?: string; onRetry?: () => void;
}) {
  return <aside className="workspace-list" aria-label={`${title} list`}>
    <header className="workspace-list-header"><h2>{title}</h2>{onNew && <button className="icon-button" aria-label="New note" onClick={onNew}><Plus size={18}/></button>}</header>
    <label className="workspace-search"><Search size={16}/><input aria-label={`Search ${title.toLowerCase()}`} placeholder={`Search ${title.toLowerCase()}…`} value={query} onChange={event=>onQuery(event.target.value)}/>{query && <button className="icon-button" aria-label="Clear notes search" onClick={()=>onQuery("")}><X size={15}/></button>}</label>
    {children}
    {error && <div className="workspace-list-notice" role="alert"><p>{error}</p>{onRetry && <button className="text-link" onClick={onRetry}>Try again</button>}</div>}
    <div className="workspace-list-items" aria-busy={loading}>
      {loading ? <p className="workspace-list-status" role="status">Opening notes…</p> : items.length ? items.map(item=><button className={`workspace-list-item${selected===item.id?" selected":""}`} key={item.id} aria-current={selected===item.id?"true":undefined} onClick={()=>onSelect(item.id)}><FileText size={18}/><span><strong>{item.title}</strong><small>{item.meta}{item.pinned?" · Pinned":""}</small></span></button>) : !error && <div className="workspace-list-status"><strong>{query?"No matching notes":"No notes in this view"}</strong><p>{query?"Try a name or another phrase.":"Start a note or bring one from the Mac app."}</p>{query && <button className="text-link" onClick={()=>onQuery("")}>Clear search</button>}</div>}
    </div>
  </aside>;
}
