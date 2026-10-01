import {describe,it,expect} from "vitest";
import {addresses,replyRecipients} from "../src/lib/mail/recipients";
describe("reply recipient context",()=>{
 it("replies to the recipients of your own sent message",()=>expect(replyRecipients({from:"Sam <sam@example.com>",reply_to:"",to:"Priya <priya@example.com>",cc:""},"sam@example.com")).toEqual({to:["priya@example.com"],cc:[]}));
 it("honours Reply-To and excludes the selected sender and duplicate Cc recipients",()=>expect(replyRecipients({from:"Priya <priya@example.com>",reply_to:"team@example.com",to:"sam@example.com, team@example.com, ALEX@example.com",cc:"alex@example.com; cc@example.com; SAM@example.com"},"sam@example.com",true)).toEqual({to:["team@example.com","ALEX@example.com"],cc:["cc@example.com"]}));
 it("keeps commas and escaped quotes inside names when splitting recipients",()=>expect(addresses('"Doe, Alex" <alex@example.com>; "A \\"name\\"" <a@example.com>')).toEqual(['"Doe, Alex" <alex@example.com>','"A \\"name\\"" <a@example.com>']));
});
