import { notFound } from "next/navigation";
import { FollowUpPrototype } from "@/components/follow-up-prototype";
import { WorkspacePreview } from "@/components/workspace-preview";
export const dynamic = "force-dynamic";
export const metadata = { title: "Follow-up prototype · Concourse", robots: {index:false,follow:false} };
export default async function Page({ searchParams }: {searchParams:Promise<Record<string,string|string[]|undefined>>}) {
  if(process.env.NODE_ENV!=="development") notFound();
  const params=await searchParams;
  if(params.view==="mail" || params.view==="library" || params.view==="booking") return <WorkspacePreview view={params.view} state={params.state==="review-readonly"||params.state==="review-signed-out"||params.state==="reader-error"||params.state==="slow"||params.state==="empty"||params.state==="error"?params.state:"normal"}/>;
  return <FollowUpPrototype noteID={params.note==="support"?"support":"launch"} reviewOpen={params.review==="1"}/>;
}
