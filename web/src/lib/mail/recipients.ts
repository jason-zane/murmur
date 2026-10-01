export const addresses=(value:string)=>{
 const result:string[]=[];let buffer="",quoted=false,escaped=false,depth=0;
 for(const character of value){
  if(escaped){buffer+=character;escaped=false;continue;}
  if(character==="\\"&&quoted){buffer+=character;escaped=true;continue;}
  if(character==='"')quoted=!quoted;
  if(!quoted){if(character==="<")depth++;if(character===">")depth=Math.max(0,depth-1);}
  if(!quoted&&depth===0&&(character===","||character===";")){if(buffer.trim())result.push(buffer.trim());buffer="";}else buffer+=character;
 }
 if(buffer.trim())result.push(buffer.trim());return result;
};
export const emailAddress=(value:string)=>value.match(/<([^>]+)>/)?.[1] || value.trim();

export function replyRecipients(message:{from:string;reply_to:string;to:string;cc:string},own:string,all=false) {
 const self=own.toLowerCase(),from=emailAddress(message.reply_to || message.from);
 const normalise=(values:string[],excluded:Set<string>)=>{const result:string[]=[];for(const entry of values){const address=emailAddress(entry),key=address.toLowerCase();if(!address||key===self||excluded.has(key))continue;excluded.add(key);result.push(address);}return result;};
 const seen=new Set<string>();
 const to=normalise([...from.toLowerCase()===self?addresses(message.to):[from],...(all?addresses(message.to):[])],seen);
 return {to,cc:all?normalise(addresses(message.cc),seen):[]};
}
