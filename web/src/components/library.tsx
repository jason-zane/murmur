"use client";
import { CommandButton } from "@/components/command-button";
import { WorkspaceHeader } from "@/components/workspace-header";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  ArrowUpRight,
  Check,
  FileText,
  Pin,
  Plus,
  RefreshCw,
  Search,
  ChevronLeft,
  Copy,
  Download,
} from "lucide-react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { ItemActions } from "./item-actions";
import { Shell } from "./shell";
import { WorkspaceList } from "./workspace-list";
import { FollowUpReview } from "./follow-up-review";
import {
  matches,
  newDocument,
  type CloudSession,
  type MeetingDocument,
} from "@/lib/documents";
const date = (value: string) =>
  new Date(value).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
const time = (value: string) =>
  new Date(value).toLocaleTimeString(undefined, {
    hour: "numeric",
    minute: "2-digit",
  });
const duration = (s: number) =>
  `${Math.floor(s / 60)}:${Math.floor(s % 60)
    .toString()
    .padStart(2, "0")}`;
export function Library({ email, userID, request = fetch, previewMode = false, previewControls, followUpEnabled=false }: { email: string; userID: string; request?: typeof fetch; previewMode?: boolean; previewControls?: React.ReactNode; followUpEnabled?:boolean }) {
  const fetch=request;
  const notesPath=(id:string|null)=>previewMode?`/prototype/follow-up?view=library${id?`&note=${encodeURIComponent(id)}`:""}`:id?`/notes?note=${encodeURIComponent(id)}`:"/notes";
  const [rows, setRows] = useState<CloudSession[]>([]),
    [query, setQuery] = useState(""),
    [selected, setSelected] = useState<string | null>(null),
    [filter, setFilter] = useState("all"),
    [loading, setLoading] = useState(true),
    [message, setMessage] = useState("");
  const load = useCallback(async () => {
    setLoading(true);
    setMessage("");
    try {
      let offset: number | null = 0;
      const all: CloudSession[] = [];
      while (offset !== null) {
        const r: Response = await fetch(`/api/sessions?offset=${offset}`);
        const body: {
          sessions: CloudSession[];
          nextOffset: number | null;
          error?: string;
        } = await r.json();
        if (!r.ok) throw new Error(body.error);
        all.push(...body.sessions);
        offset = body.nextOffset;
      }
      setRows(
        all
          .filter((r) => !r.deleted_at)
          .sort((a, b) => b.started_at.localeCompare(a.started_at)),
      );
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Could not load your notes.");
    } finally {
      setLoading(false);
    }
  }, [request]);
  useEffect(() => {
    void load();
    const id = new URLSearchParams(location.search).get("note");
    if (id) setSelected(id);
  }, [load]);
  async function create() {
    setMessage("");
    try {
      const r = await fetch("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ document: newDocument(), expectedVersion: 0 }),
      });
      const row = await r.json();
      if (!r.ok) throw new Error(row.error);
      setRows((v) => [row, ...v]);
      setSelected(row.id);
      history.replaceState(null, "", notesPath(row.id));
    } catch (e) {
      setMessage(
        e instanceof Error ? e.message : "Could not create your note.",
      );
    }
  }
  function replace(row: CloudSession) {
    setRows((v) => row.deleted_at ? v.filter(r => r.id !== row.id) : v.map((r) => (r.id === row.id ? row : r)));
    if (row.deleted_at) { setSelected(null); history.replaceState(null, "", notesPath(null)); }
  }
  const current = rows.find((r) => r.id === selected),
    visible = rows.filter(
      (r) =>
        matches(r.document, query) &&
        (filter !== "pinned" || r.document.session.pinned),
    );
  function selectNote(id: string | null) {
    if (id === selected) return;
    if (document.querySelector(".note-editor") && !confirm("Leave this note? An unfinished draft stays in this browser.")) return;
    setSelected(id);
    history.replaceState(null, "", notesPath(id));
  }
  return <Shell email={email} layout="notes" previewMode={previewMode} previewControls={previewControls} activePath="/notes">
    <WorkspaceHeader title="Notes" actions={<CommandButton className="button primary" onClick={create} disabled={loading} help="Write a note in Concourse. Unfinished edits are recovered in this browser until you save."><Plus size={17}/>New note</CommandButton>}/>
    <div className={`notes-detail-layout${current ? " has-note" : ""}`}>
      <WorkspaceList title={filter === "pinned" ? "Pinned notes" : "All notes"} query={query} onQuery={setQuery} selected={selected}
        onSelect={selectNote} loading={loading} error={message} onRetry={load}
        items={visible.map(row=>({id:row.id,title:row.title,meta:`${date(row.started_at)} · ${row.document.session.speakers.join(", ") || (row.document.session.engine==="Notes"?"Personal note":"Meeting")}`,pinned:Boolean(row.document.session.pinned)}))}>
        <div className="workspace-list-filters" aria-label="Filter notes"><button aria-pressed={filter==="all"} onClick={()=>setFilter("all")}>All notes <span>{rows.length}</span></button><button aria-pressed={filter==="pinned"} onClick={()=>setFilter("pinned")}><Pin size={13}/>Pinned</button><button className="icon-button" aria-label="Refresh notes" onClick={load}><RefreshCw size={15}/></button></div>
      </WorkspaceList>
      {current ? <NoteDetail key={current.id} row={current} userID={userID} onBack={()=>selectNote(null)} onSaved={replace} request={request} previewMode={previewMode} followUpEnabled={followUpEnabled}/> : <section className="notes-welcome" aria-label="Notes workspace"><FileText size={28}/><h2>{loading?"Opening your notes":message?"Notes couldn’t open":selected?"Note unavailable":rows.length?"A little space to think":"Your next thought starts here"}</h2><p>{loading?"Your notes are loading…":message?"Your notes could not be loaded. Try again in the notes list.":selected?"This note could not be found in your library. Select another note or create a new one.":rows.length?"Select a note to read, edit or find a moment in its transcript.":"Write a note here, or connect the Mac app to bring your meeting notes together."}</p></section>}
    </div>
  </Shell>;
}

function NoteDetail({
  row,
  userID,
  onBack,
  onSaved,
  request,
  previewMode,
  followUpEnabled,
}: {
  row: CloudSession;
  userID: string;
  onBack: () => void;
  onSaved: (r: CloudSession) => void;
  request: typeof fetch;
  previewMode: boolean;
  followUpEnabled: boolean;
}) {
  const fetch=request;
  const [reviewOpen,setReviewOpen]=useState(false);
  const reviewTrigger=useRef<HTMLButtonElement|null>(null),seenVersion=useRef(row.version);
  const key = `murmur:draft:${userID}:${row.id}`;
  const [title, setTitle] = useState(row.title),
    [text, setText] = useState(row.document.note || ""),
    [editing, setEditing] = useState(!row.document.note),
    [tab, setTab] = useState("note"),
    [message, setMessage] = useState(""),
    [busy, setBusy] = useState(false),
    [copied, setCopied] = useState(false),
    [sourceQuery, setSourceQuery] = useState(""),
    [cancelConfirm,setCancelConfirm]=useState(false);
  useEffect(() => {
    try {
      const saved = localStorage.getItem(key);
      if (saved) {
        const draft = JSON.parse(saved);
        setText(draft.text);
        setTitle(draft.title);
        if (Number.isSafeInteger(draft.baseVersion))
          setBaseVersion(draft.baseVersion);
        setEditing(true);
        setMessage(
          "Your unfinished draft was recovered. Save when you’re ready.",
        );
      }
    } catch {
      setMessage(
        "Browser draft storage is unavailable. Keep this tab open until your note is saved.",
      );
    }
  }, [key]);
  const [baseVersion, setBaseVersion] = useState(row.version),
    [conflict, setConflict] = useState<CloudSession | null>(null);
  const changed = title !== row.title || text !== (row.document.note || "");
  useEffect(()=>{if(seenVersion.current===row.version)return;seenVersion.current=row.version;if(!editing){setTitle(row.title);setText(row.document.note || "");setBaseVersion(row.version);}},[row.version,row.title,row.document.note,editing]);
  function change(nextTitle: string, nextText: string) {
    setTitle(nextTitle);
    setText(nextText);
    try {
      localStorage.setItem(
        key,
        JSON.stringify({ title: nextTitle, text: nextText, baseVersion }),
      );
    } catch {
      setMessage(
        "Your browser could not keep a recovery draft. Save before closing this tab.",
      );
    }
  }
  useEffect(() => {
    const before = (e: BeforeUnloadEvent) => {
      if (changed) {
        e.preventDefault();
      }
    };
    window.addEventListener("beforeunload", before);
    return () => window.removeEventListener("beforeunload", before);
  }, [changed]);
  function cancelEdit(confirmed=false) {
    if(busy)return;
    if(changed && !confirmed){setCancelConfirm(true);return;}
    try { localStorage.removeItem(key); } catch {setMessage("Your browser could not clear this recovery draft. Keep the editor open until you save.");return;}
    setTitle(row.title);setText(row.document.note || "");setBaseVersion(row.version);setConflict(null);setMessage("");setCancelConfirm(false);setEditing(false);
  }
  async function save() {
    setBusy(true);
    setMessage("");
    try {
      const document: MeetingDocument = {
        ...row.document,
        session: {
          ...row.document.session,
          title: title.trim() || "Untitled note",
          state: "noted",
          noteSource: "You",
        },
        note: text,
      };
      const r = await fetch("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ document, expectedVersion: baseVersion }),
      });
      const body = await r.json();
      if (!r.ok) {
        if (r.status === 409) {
          const latest = await fetch(`/api/sessions/${row.id}`);
          if (latest.ok) setConflict(await latest.json());
        }
        throw new Error(body.error);
      }
      onSaved(body);
      setBaseVersion(body.version);
      setTitle(body.title);
      localStorage.removeItem(key);
      setEditing(false);
      setMessage(previewMode?"Saved in this browser’s sample workspace.":"Saved. Your Mac will pick this up when it’s online.");
    } catch (e) {
      setMessage(
        e instanceof Error
          ? e.message
          : "Could not save. Your draft stays in this browser.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function pin() {
    if (busy || changed) return;
    setBusy(true);
    setMessage("");
    try {
      const document = {
        ...row.document,
        session: {
          ...row.document.session,
          pinned: !row.document.session.pinned,
        },
      };
      const r = await fetch("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ document, expectedVersion: row.version }),
      });
      const body = await r.json();
      if (!r.ok) throw new Error(body.error || "Could not pin this note.");
      onSaved(body);
      setBaseVersion(body.version);
    } catch (e) {
      setMessage(
        e instanceof Error
          ? e.message
          : "Could not pin this note. Try again when you’re online.",
      );
    } finally {
      setBusy(false);
    }
  }
  async function deleteNote() {
    if (busy || !confirm(`Delete “${row.title}” from your Concourse account? It will leave the web library. Copies already stored on your Mac remain there.${changed ? " Your unsaved browser draft will also be removed." : ""}`)) return;
    setBusy(true);
    setMessage("");
    try {
      const response = await fetch("/api/sessions", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ document: row.document, expectedVersion: row.version, deleted: true }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(response.status === 409 ? "This note changed on another device. Reload it before deleting." : result.error || "Could not delete this note.");
      try { localStorage.removeItem(key); } catch { /* Deletion succeeded even when browser storage is unavailable. */ }
      onSaved(result);
    } catch (error) { setMessage(error instanceof Error ? error.message : "Could not delete this note."); }
    finally { setBusy(false); }
  }
  function download() {
    const blob = new Blob([`# ${title}\n\n${text}`], { type: "text/markdown" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${title.replace(/[^a-z0-9 -]/gi, "") || "Meeting"}.md`;
    a.click();
    URL.revokeObjectURL(url);
  }
  return (
    <article className="document">
      <header className="document-toolbar">
        <button className="text-link" onClick={onBack}>
          <ChevronLeft size={17} />
          Notes
        </button>
        <div>

          {tab === "note" &&
            (editing ? (
              <div className="note-edit-actions"><button className="button small" disabled={busy} onClick={()=>cancelEdit()}>Cancel edit</button><button
                className="button primary small"
                disabled={busy || !changed}
                onClick={save}
              >
                {busy ? "Saving…" : "Save note"}
                <Check size={15} />
              </button></div>
            ) : (
              <button className="button small" onClick={() => setEditing(true)}>
                Edit note
              </button>
            ))}
          <CommandButton
            className="icon-button"
            aria-label="Copy note"
            help="Copy the note title and text."
            onClick={async () => {
              try {
                await navigator.clipboard.writeText(`# ${title}\n\n${text}`);
                setCopied(true);
                setTimeout(() => setCopied(false), 2000);
              } catch {
                setMessage(
                  "Copy was blocked by your browser. Select the note text to copy it.",
                );
              }
            }}
          >
            {copied ? <Check size={17} /> : <Copy size={17} />}
          </CommandButton>
          <ItemActions label={`note: ${row.title}`}>
            <button disabled={busy || changed} onClick={pin}>{row.document.session.pinned ? "Unpin note" : "Pin note"}</button>
            <button onClick={download}>Export Markdown…</button>
            <hr/><button disabled={busy} onClick={deleteNote}>Delete note…</button>
          </ItemActions>
        </div>
      </header>
      <div className="document-inner">
        {followUpEnabled && !editing && <button ref={reviewTrigger} className="text-link sample-follow-up-link" onClick={()=>setReviewOpen(true)}>Review follow-up <ArrowUpRight size={14}/></button>}
        {followUpEnabled && !editing && <p className="fine-print sample-source-note">Choose source evidence, write your draft and save it for review. No AI generation or email sending.</p>}
        {reviewOpen && <FollowUpReview row={row} userID={userID} request={request} previewMode={previewMode} onSource={onSaved} onClose={()=>{setReviewOpen(false);requestAnimationFrame(()=>reviewTrigger.current?.focus());}}/>}
        <div className="eyebrow">
          {date(row.started_at)}
          <span> · </span>
          {row.document.session.app || "Your notes"}
        </div>
        {editing ? (
          <input
            aria-label="Note title"
            className="title-input"
            disabled={busy}
            value={title}
            onChange={(e) => change(e.target.value, text)}
          />
        ) : (
          <h2>{title}</h2>
        )}
        <div className="document-meta">
          {row.document.session.speakers.join(" · ")}
          <span>
            {row.document.session.duration > 0
              ? duration(row.document.session.duration)
              : "Personal note"}
          </span>
          <span>Version {row.version}</span>
        </div>
        {row.document.session.booking && (
          <details className="workspace-card">
            <summary>
              Booking details · {row.document.session.booking.eventType}
            </summary>
            <p>
              {row.document.session.booking.guestName} ·{" "}
              {row.document.session.booking.guestEmail}
            </p>
            {row.document.session.booking.answers.map((answer, index) => (
              <div key={index}>
                <strong>{answer.question}</strong>
                <p>{answer.answer}</p>
              </div>
            ))}
            <p className="fine-print">
              Provided by the guest before the meeting.
            </p>
            {row.document.session.booking.bookingID && (
              <a
                className="text-link"
                href={`/scheduling?tab=Bookings&booking=${encodeURIComponent(row.document.session.booking.bookingID)}`}
              >
                Booking and follow-up messages
              </a>
            )}
          </details>
        )}
        <div className="document-tabs">
          <div className="tabs">
            <button
              className={tab === "note" ? "selected" : ""}
              onClick={() => setTab("note")}
            >
              Notes
            </button>
            <button
              className={tab === "transcript" ? "selected" : ""}
              onClick={() => setTab("transcript")}
            >
              Transcript <span>{row.document.transcript.length}</span>
            </button>
          </div>

        </div>
        {cancelConfirm && <div className="notice" role="alert"><p>Discard these unsaved changes? Your saved note stays unchanged.</p><div className="form-actions"><button className="button small" onClick={()=>setCancelConfirm(false)}>Keep editing</button><button className="button small" onClick={()=>cancelEdit(true)}>Discard changes</button></div></div>}
        {message && (
          <p role="status" className="notice">
            {message}
          </p>
        )}
        {conflict && (
          <div className="conflict-actions">
            <button
              className="button small"
              onClick={() => {
                onSaved(conflict);
                setBaseVersion(conflict.version);
                try {
                  localStorage.setItem(
                    key,
                    JSON.stringify({
                      title,
                      text,
                      baseVersion: conflict.version,
                    }),
                  );
                } catch {}
                setConflict(null);
                setMessage(
                  previewMode?"Your draft is ready to save as the next local sample revision.":"Your draft is ready to save as the next revision. The previous cloud version will be kept in history.",
                );
              }}
            >
              Keep my draft
            </button>
            <button
              className="button small"
              onClick={() => {
                onSaved(conflict);
                setTitle(conflict.title);
                setText(conflict.document.note || "");
                setBaseVersion(conflict.version);
                setConflict(null);
                localStorage.removeItem(key);
                setEditing(false);
                setMessage(previewMode?"Showing the saved sample version.":"Showing the cloud version.");
              }}
            >
              {previewMode?"Use saved sample version":"Use cloud version"}
            </button>
          </div>
        )}
        {tab === "note" ? (
          editing ? (
            <>
              <textarea
                className="note-editor"
                disabled={busy}
                aria-label="Meeting notes in Markdown"
                value={text}
                onChange={(e) => change(title, e.target.value)}
                placeholder="What’s on your mind? Markdown works here."
              />
              <p className="editor-hint">
                {changed
                  ? (previewMode?"Draft kept in this browser · save to the sample workspace":"Draft kept in this browser · save to sync it")
                  : "All changes saved"}
                <span>Markdown supported</span>
              </p>
            </>
          ) : (
            <div className="prose">
              <ReactMarkdown remarkPlugins={[remarkGfm]}>
                {text ||
                  "No written notes yet. Read the transcript or start writing."}
              </ReactMarkdown>
            </div>
          )
        ) : (
          <div className="transcript">
            <label className="search">
              <Search size={17} />
              <input
                aria-label="Search transcript"
                value={sourceQuery}
                onChange={(e) => setSourceQuery(e.target.value)}
                placeholder="Find a moment…"
              />
            </label>
            {row.document.transcript
              .filter((s) =>
                s.text.toLowerCase().includes(sourceQuery.toLowerCase()),
              )
              .map((s) => (
                <div className="transcript-segment" key={s.id}>
                  <time>{duration(s.start)}</time>
                  <div>
                    <strong>
                      {s.speaker || (s.source === "you" ? "You" : "Call")}
                    </strong>
                    <p>{s.text}</p>
                  </div>
                </div>
              ))}
            {!row.document.transcript.length && (
              <div className="empty">
                <p>This is a personal note. There’s no recorded transcript.</p>
              </div>
            )}
          </div>
        )}
      </div>
    </article>
  );
}
