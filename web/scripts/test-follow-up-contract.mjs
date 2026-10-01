// Rollback-only schema and synthetic ownership contract; never reads credentials.
// Requires the existing local stack. Does not start Docker or issue Auth tokens.
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
const migration = await readFile(new URL("../../supabase/migrations/20261001001034_follow_up_drafts.sql", import.meta.url), "utf8");
const fixture = await readFile(new URL("../../supabase/tests/follow-up-drafts.sql", import.meta.url), "utf8");
const guard = `do $$ begin
  if current_database() <> 'postgres' or to_regclass('public.follow_up_drafts') is not null
    or to_regnamespace('concourse_private') is not null then
    raise exception 'Requires the unchanged local baseline; refusing to replace an existing draft schema';
  end if;
end $$;`;
const sql = "begin;\n" + guard + "\n" + migration + "\n" + fixture.replace(/^begin;\n/, "").replace(/rollback;\s*$/, "") + "\nrollback;\n";
await new Promise((resolve, reject) => {
  const child = spawn("docker", ["exec", "-i", "supabase_db_murmur", "psql", "-X", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q", "-At"], { stdio: ["pipe", "pipe", "pipe"] });
  let output = "", error = "";
  child.stdout.on("data", chunk => output += chunk);
  child.stderr.on("data", chunk => error += chunk);
  child.on("error", reject);
  child.on("exit", code => {
    if (code !== 0) return reject(new Error(`Rollback-only follow-up contract failed: ${error}`));
    const passed = output.split("\n").find(line => line.startsWith("PASS:"));
    if (!passed) return reject(new Error("Fixture did not confirm success."));
    console.log(passed); console.log("All schema and synthetic fixture changes rolled back. No tokens or credentials created."); resolve();
  });
  child.stdin.on("error", reject);
  child.stdin.end(sql);
});
