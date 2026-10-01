import {describe,it,expect} from "vitest";
import {DraftEdits} from "../src/lib/mail/draft-edits";
describe("draft acknowledgement",()=>{
 it("keeps newer edits recoverable while an earlier network save completes",()=>{
  const edits=new DraftEdits();edits.edit();const savingA=edits.capture();
  edits.edit();expect(edits.acknowledge(savingA)).toBe(false);expect(edits.dirty).toBe(true);
  const savingB=edits.capture();expect(edits.acknowledge(savingB)).toBe(true);expect(edits.dirty).toBe(false);
 });
 it("starts recovered content dirty and ignores a stale acknowledgement after repeated edits",()=>{
  const edits=new DraftEdits(true),old=edits.capture();edits.edit();edits.edit();
  expect(edits.acknowledge(old)).toBe(false);expect(edits.dirty).toBe(true);
 });
});
