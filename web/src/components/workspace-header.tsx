import type { ReactNode } from "react";

/** Page context stays left; commands create or act within this workspace on the right. */
export function WorkspaceHeader({ title, context, actions }: { title: string; context?: ReactNode; actions?: ReactNode }) {
  return <header className="page-header workspace-header">
    <div className="workspace-heading"><h1>{title}</h1>{context && <div className="workspace-context">{context}</div>}</div>
    {actions && <div className="workspace-commands" role="group" aria-label={`${title} actions`}>{actions}</div>}
  </header>;
}
