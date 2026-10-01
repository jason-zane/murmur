/** An acknowledgement may clear recovery state only for the edit it actually saved. */
export class DraftEdits {
 private generation=0;
 dirty:boolean;
 constructor(recovered=false){this.dirty=recovered;}
 edit(){this.generation++;this.dirty=true;}
 capture(){return this.generation;}
 acknowledge(generation:number){
  if(generation!==this.generation)return false;
  this.dirty=false;return true;
 }
}
