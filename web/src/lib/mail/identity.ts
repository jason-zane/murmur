/** Shared mailbox instrumentation. The address always remains visible; colour is never authority. */
export const mailboxColours=["indigo","teal","violet","amber","slate"] as const;
export const mailboxIcons=["initials","mail","work","personal","none"] as const;
export type MailboxColour=typeof mailboxColours[number];
export type MailboxIcon=typeof mailboxIcons[number];
export type MailIdentity={id:string;email?:string|null;identity_colour?:MailboxColour|null;identity_icon?:MailboxIcon|null};
export function mailboxColour(account:MailIdentity):MailboxColour {
 if(account.identity_colour&&mailboxColours.includes(account.identity_colour))return account.identity_colour;
 // UTF-8 byte sum is deliberately simple and identical in the Mac client.
 const index=new TextEncoder().encode(account.id).reduce((sum,byte)=>(sum+byte)%mailboxColours.length,0);
 return mailboxColours[index];
}
export function mailboxIcon(account:MailIdentity):MailboxIcon {return account.identity_icon&&mailboxIcons.includes(account.identity_icon)?account.identity_icon:"initials";}
