Require Import Syntax StateMonad Properties All.
Require Import Coq.ZArith.BinIntDef Coq.ZArith.BinInt.
Require Import Coq.Arith.Arith Coq.Arith.Div2 Coq.NArith.NArith Coq.Bool.Bool Coq.ZArith.ZArith.

Set Implicit Arguments.
Set Asymmetric Patterns.

Section Compile.
  Variable ty: Kind -> Type.
  Variable regMapTy: Type.

  Inductive RegMapExpr: Type :=
  | VarRegMap (v: regMapTy): RegMapExpr
  | UpdRegMap (r: string) (pred: Bool @# ty) (k: FullKind) (val: Expr ty k)
              (regMap: RegMapExpr): RegMapExpr
  | CompactRegMap (regMap: RegMapExpr): RegMapExpr.

  Inductive CompActionT: Kind -> Type :=
  | CompCall (f: string) (argRetK: Kind * Kind) (pred: Bool @# ty)
             (arg: fst argRetK @# ty)
             lret (cont: fullType ty (SyntaxKind (snd argRetK)) -> CompActionT lret): CompActionT lret
  | CompLetExpr k (e: Expr ty k) lret (cont: fullType ty k -> CompActionT lret): CompActionT lret
  | CompNondet k lret (cont: fullType ty k -> CompActionT lret): CompActionT lret
  | CompSys (ls: list (SysT ty)) lret (cont: CompActionT lret): CompActionT lret
  | CompRead (r: string) (k: FullKind) (readMap: RegMapExpr) lret (cont: fullType ty k -> CompActionT lret): CompActionT lret
  | CompRet lret (e: lret @# ty) (newMap: RegMapExpr) : CompActionT lret
  | CompLetFull k (a: CompActionT k) lret (cont: fullType ty (SyntaxKind k) -> regMapTy -> CompActionT lret): CompActionT lret
  | CompAsyncRead (idxNum num : nat) (dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# ty) (k : Kind) (readMap : RegMapExpr) lret
                  (cont : fullType ty (SyntaxKind (Array num k)) -> CompActionT lret) : CompActionT lret
  | CompWrite (idxNum num : nat) (dataArray : string) (idx  : Bit (Nat.log2_up idxNum) @# ty) (Data : Kind) (val : Array num Data @# ty)
              (mask : option (Array num Bool @# ty)) (pred : Bool @# ty) (writeMap readMap : RegMapExpr) lret
              (cont : regMapTy -> CompActionT lret) : CompActionT lret
  | CompSyncReadReq (idxNum num : nat) (readReg dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# ty) (Data : Kind)
                    (isAddr : bool) (pred : Bool @# ty) (writeMap readMap : RegMapExpr) lret
                    (cont : regMapTy -> CompActionT lret) : CompActionT lret
  | CompSyncReadRes (idxNum num : nat) (readReg dataArray : string) (Data : Kind) (isAddr : bool) (readMap : RegMapExpr) lret
                    (cont : fullType ty (SyntaxKind (Array num Data)) -> CompActionT lret) : CompActionT lret.

  Inductive EActionT (lretT : Kind) : Type :=
  | EMCall (meth : string) s (e : Expr ty (SyntaxKind (fst s)))
           (cont : (fullType ty (SyntaxKind (snd s))) -> EActionT lretT) : EActionT lretT
  | ELetExpr (k : FullKind) (e : Expr ty k) (cont : fullType ty k  -> EActionT lretT) : EActionT lretT
  | ELetAction (k : Kind) (a : EActionT k) (cont : fullType ty (SyntaxKind k) -> EActionT lretT) : EActionT lretT
  | EReadNondet (k : FullKind) (cont : fullType ty k -> EActionT lretT) : EActionT lretT
  | EReadReg (r : string) (k : FullKind) (cont : fullType ty k -> EActionT lretT) : EActionT lretT
  | EWriteReg (r : string) (k : FullKind) (e :  Expr ty k) (cont : EActionT lretT) : EActionT lretT
  | EIfElse : Expr ty (SyntaxKind Bool) -> forall k, EActionT k -> EActionT k -> (fullType ty (SyntaxKind k) -> EActionT lretT) -> EActionT lretT
  | ESys (ls : list (SysT ty)) (cont : EActionT lretT) : EActionT lretT
  | EReturn (e : Expr ty (SyntaxKind lretT)) : EActionT lretT
  | EAsyncRead (idxNum num : nat) (dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# ty)
                      (k : Kind) (cont : fullType ty (SyntaxKind (Array num k)) -> EActionT lretT) : EActionT lretT
  | EWrite (idxNum num : nat) (dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# ty)
                  (Data : Kind) (val : Array num Data @# ty) (mask : option (Array num Bool @# ty))
                  (cont : EActionT lretT) : EActionT lretT
  | ESyncReadReq (idxNum num : nat) (readReg dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# ty)
                        (Data : Kind) (isAddr : bool) (cont : EActionT lretT) : EActionT lretT
  | ESyncReadRes (idxNum num : nat) (readReg dataArray : string) (Data : Kind) (isAddr : bool)
                        (cont : fullType ty (SyntaxKind (Array num Data)) -> EActionT lretT) : EActionT lretT.

  (* Injection of ActionT into EActionT *)
  
  Fixpoint Action_EAction (lretT : Kind) (a : ActionT ty lretT) :  EActionT lretT :=
    match a in ActionT _ _ with
    | MCall meth k argExpr cont =>
      EMCall meth k argExpr (fun v => Action_EAction (cont v))
    | Return x =>
      EReturn x
    | LetExpr k' expr cont => ELetExpr expr (fun v => Action_EAction (cont v))
    | ReadNondet k' cont => EReadNondet k' (fun ret => Action_EAction (cont ret))
    | Sys ls cont => ESys ls (Action_EAction cont)
    | ReadReg r k' cont => EReadReg r k' (fun v => Action_EAction (cont v))
    | WriteReg r k' expr cont => EWriteReg r expr (Action_EAction cont)
    | LetAction k' a' cont => ELetAction (Action_EAction a') (fun v => Action_EAction (cont v))
    | IfElse pred' k' aT aF cont => EIfElse pred' (Action_EAction aT) (Action_EAction aF) (fun v => Action_EAction (cont v))
    end.
  
  Section ReadMap.
    Variable readMap: regMapTy.

    
    Fixpoint compileAction k (a: ActionT ty k) (pred: Bool @# ty)
             (writeMap: RegMapExpr) {struct a}:
      CompActionT k :=
      match a in ActionT _ _ with
      | MCall meth k argExpr cont =>
        CompCall meth k pred argExpr (fun ret => @compileAction _ (cont ret) pred writeMap)
      | Return x =>
        CompRet x writeMap
      | LetExpr k' expr cont => CompLetExpr expr (fun ret => @compileAction _ (cont ret) pred writeMap)
      | ReadNondet k' cont => CompNondet k' (fun ret => @compileAction _ (cont ret) pred writeMap)
      | Sys ls cont => CompSys ls (compileAction cont pred writeMap)
      | ReadReg r k' cont =>
        @CompRead r k' (VarRegMap readMap) _ (fun v => @compileAction _ (cont v) pred writeMap)
      | WriteReg r k' expr cont =>
        CompLetFull (CompRet ($$ (zToWord 0 0))%kami_expr
                             (UpdRegMap r pred expr writeMap)) (fun _ v => @compileAction _ cont pred (VarRegMap v))
      | LetAction k' a' cont =>
        CompLetFull (@compileAction k' a' pred writeMap)
                    (fun retval writeMap' => @compileAction k (cont retval) pred (VarRegMap writeMap'))
      | IfElse pred' k' aT aF cont =>
        CompLetFull (@compileAction k' aT (pred && pred')%kami_expr writeMap)
                    (fun valT writesT =>
                       CompLetFull (@compileAction k' aF (pred && !pred')%kami_expr (VarRegMap writesT))
                                   (fun valF writesF =>
                                      CompLetExpr (IF pred' then #valT else #valF)%kami_expr
                                                  (fun val => (@compileAction k (cont val) pred (VarRegMap writesF)))
                    ))
      end.

    Fixpoint EcompileAction k (a : EActionT k) (pred : Bool @# ty)
             (writeMap : RegMapExpr) {struct a} :
      CompActionT k :=
      match a in EActionT _ with
      | EMCall meth k argExpr cont =>
        CompCall meth k pred argExpr (fun ret => @EcompileAction _ (cont ret) pred writeMap)
      | EReturn x =>
        CompRet x writeMap
      | ELetExpr k' expr cont => CompLetExpr expr (fun ret => @EcompileAction _ (cont ret) pred writeMap)
      | EReadNondet k' cont => CompNondet k' (fun ret => @EcompileAction _ (cont ret) pred writeMap)
      | ESys ls cont => CompSys ls (EcompileAction cont pred writeMap)
      | EReadReg r k' cont =>
        @CompRead r k' (VarRegMap readMap) _ (fun v => @EcompileAction _ (cont v) pred writeMap)
      | EWriteReg r k' expr cont =>
        CompLetFull (CompRet ($$ (zToWord 0 0))%kami_expr
                             (UpdRegMap r pred expr writeMap)) (fun _ v => @EcompileAction _ cont pred (VarRegMap v))
      | ELetAction k' a' cont =>
        CompLetFull (@EcompileAction k' a' pred writeMap)
                    (fun retval writeMap' => @EcompileAction k (cont retval) pred (VarRegMap writeMap'))
      | EIfElse pred' k' aT aF cont =>
        CompLetFull (@EcompileAction k' aT (pred && pred')%kami_expr writeMap)
                    (fun valT writesT =>
                       CompLetFull (@EcompileAction k' aF (pred && !pred')%kami_expr (VarRegMap writesT))
                                   (fun valF writesF =>
                                      CompLetExpr (IF pred' then #valT else #valF)%kami_expr
                                                  (fun val => (@EcompileAction k (cont val) pred (VarRegMap writesF)))
                    ))
      | EAsyncRead idxNum num dataArray idx k cont =>
        CompAsyncRead idxNum dataArray idx (VarRegMap readMap)
                      (fun array => @EcompileAction _ (cont array) pred writeMap)
      | EWrite idxNum num dataArray idx Data val mask cont =>
        CompWrite idxNum dataArray idx val mask pred writeMap (VarRegMap readMap)
                  (fun writeMap' => @EcompileAction _ cont pred (VarRegMap writeMap'))
      | ESyncReadReq idxNum num readReg dataArray idx Data isAddr cont =>
        CompSyncReadReq idxNum num readReg dataArray idx Data isAddr pred writeMap (VarRegMap readMap)
                        (fun writeMap' => @EcompileAction _ cont pred (VarRegMap writeMap'))
      | ESyncReadRes idxNum num readReg dataArray Data isAddr cont =>
        CompSyncReadRes idxNum readReg dataArray isAddr (VarRegMap readMap)
                        (fun array => @EcompileAction _ (cont array) pred writeMap)
      end.

    Fixpoint inlineWriteFile k (rf : RegFileBase) (a : EActionT k) : EActionT k :=
      match rf with
      | @Build_RegFileBase _isWrMask _num _dataArray _readers _write _idxNum _Data _init =>
        match a with
        | EMCall g sign arg cont =>
          match String.eqb _write g with
          | true =>
            if _isWrMask then
              match Signature_dec sign (WriteRqMask (Nat.log2_up _idxNum) _num _Data, Void) with
              | left isEq =>
                let inValue := (match isEq in _ = Y return Expr ty (SyntaxKind (fst Y)) with | eq_refl => arg end) in
                ELetExpr ($$ (zToWord 0 0))%kami_expr
                         (fun v => EWrite _idxNum _dataArray (inValue @% "addr")%kami_expr (inValue @% "data")%kami_expr
                                          (Some (inValue @% "mask")%kami_expr) (inlineWriteFile rf (match isEq in _ = Y return fullType ty (SyntaxKind (snd Y)) -> EActionT k with
                                                                                                    | eq_refl => cont
                                                                                                    end v)))
              | right _ => EMCall g sign arg (fun ret => inlineWriteFile rf (cont ret))
              end
            else
              match Signature_dec sign (WriteRq (Nat.log2_up _idxNum) (Array _num _Data), Void) with
              | left isEq =>
                let inValue := (match isEq in _ = Y return Expr ty (SyntaxKind (fst Y)) with | eq_refl => arg end) in
                ELetExpr ($$ (zToWord 0 0))%kami_expr
                         (fun v => EWrite _idxNum _dataArray (inValue @% "addr")%kami_expr (inValue @% "data")%kami_expr
                                          None (inlineWriteFile rf (match isEq in _ = Y return fullType ty (SyntaxKind (snd Y)) -> EActionT k with
                                                                    | eq_refl => cont
                                                                    end v)))
              | right _ => EMCall g sign arg (fun ret => inlineWriteFile rf (cont ret))
              end
          | false => EMCall g sign arg (fun ret => inlineWriteFile rf (cont ret))
          end
        | ELetExpr _ e cont => ELetExpr e (fun ret => inlineWriteFile rf (cont ret))
        | ELetAction _ a cont => ELetAction (inlineWriteFile rf a) (fun ret => inlineWriteFile rf (cont ret))
        | EReadNondet k c => EReadNondet k (fun ret => inlineWriteFile rf (c ret))
        | EReadReg r k c => EReadReg r k (fun ret => inlineWriteFile rf (c ret))
        | EWriteReg r k e a => EWriteReg r e (inlineWriteFile rf a)
        | EIfElse p _ aT aF c => EIfElse p (inlineWriteFile rf aT) (inlineWriteFile rf aF) (fun ret => inlineWriteFile rf (c ret))
        | ESys ls c => ESys ls (inlineWriteFile rf c)
        | EReturn e => EReturn e
        | EAsyncRead idxNum num dataArray idx k cont =>
          EAsyncRead idxNum dataArray idx (fun ret => inlineWriteFile rf (cont ret))
        | EWrite idxNum num dataArray idx Data val mask cont =>
          EWrite idxNum dataArray idx val mask (inlineWriteFile rf cont)
        | ESyncReadReq idxNum num readReg dataArray idx Data isAddr cont =>
          ESyncReadReq idxNum num readReg dataArray idx Data isAddr (inlineWriteFile rf cont)
        | ESyncReadRes idxNum num readReg dataArray Data isAddr cont =>
          ESyncReadRes idxNum readReg dataArray isAddr (fun v => inlineWriteFile rf (cont v))
        end
      end.
    
    Fixpoint inlineAsyncReadFile (read : string) (rf : RegFileBase) k (a : EActionT k) : EActionT k :=
      match rf with
      | @Build_RegFileBase _isWrMask _num _dataArray _readers _write _idxNum _Data _init =>
        match _readers with
        | Async reads =>
          match (existsb (String.eqb read) reads) with
          | true =>
            match a with
            | EMCall g sign arg cont =>
              match String.eqb read g with
              | true =>
                match Signature_dec sign (Bit (Nat.log2_up _idxNum), Array _num _Data) with
                | left isEq =>
                  let inValue := (match isEq in _ = Y return Expr ty (SyntaxKind (fst Y)) with | eq_refl => arg end) in
                  EAsyncRead _idxNum _dataArray inValue (fun array => inlineAsyncReadFile  read rf (match isEq in _ = Y return fullType ty (SyntaxKind (snd Y)) -> EActionT k with
                                                                                                      | eq_refl => cont
                                                                                                      end array))
                | right _ => EMCall g sign arg (fun ret => inlineAsyncReadFile read rf (cont ret))
                end
              | false => EMCall g sign arg (fun ret => inlineAsyncReadFile read rf (cont ret))
              end
            | ELetExpr _ e cont => ELetExpr e (fun ret => inlineAsyncReadFile read rf (cont ret))
            | ELetAction _ a cont => ELetAction (inlineAsyncReadFile read rf a) (fun ret => inlineAsyncReadFile read rf (cont ret))
            | EReadNondet k c => EReadNondet k (fun ret => inlineAsyncReadFile read rf (c ret))
            | EReadReg r k c => EReadReg r k (fun ret => inlineAsyncReadFile read rf (c ret))
            | EWriteReg r k e a => EWriteReg r e (inlineAsyncReadFile read rf a)
            | EIfElse p _ aT aF c => EIfElse p (inlineAsyncReadFile read rf aT) (inlineAsyncReadFile read rf aF) (fun ret => inlineAsyncReadFile read rf (c ret))
            | ESys ls c => ESys ls (inlineAsyncReadFile read rf c)
            | EReturn e => EReturn e
            | EAsyncRead idxNum num dataArray idx k cont =>
              EAsyncRead idxNum dataArray idx (fun ret => inlineAsyncReadFile read rf (cont ret))
            | EWrite idxNum num dataArray idx Data val mask cont =>
              EWrite idxNum dataArray idx val mask (inlineAsyncReadFile read rf cont)
            | ESyncReadReq idxNum num readReg dataArray idx Data isAddr cont =>
              ESyncReadReq idxNum num readReg dataArray idx Data isAddr (inlineAsyncReadFile read rf cont)
            | ESyncReadRes idxNum num readReg dataArray Data isAddr cont =>
              ESyncReadRes idxNum readReg dataArray isAddr (fun v => inlineAsyncReadFile read rf (cont v))
            end
          | false => a
          end
        | Sync _ _ => a
        end
      end.

  Lemma SyncRead_eq_dec (r r' : SyncRead) :
    {r = r'} + {r <> r'}.
  Proof.
    destruct (string_dec (readReqName r) (readReqName r')),
    (string_dec (readResName r) (readResName r')),
    (string_dec (readRegName r) (readRegName r')), r, r';
      simpl in *; subst; auto; right; intro; inv H; auto.
  Qed.

  Definition SyncRead_eqb (r r' : SyncRead) : bool :=
    (String.eqb (readReqName r) (readReqName r'))
      && (String.eqb (readResName r) (readResName r'))
      && (String.eqb (readRegName r) (readRegName r')).

  Lemma SyncRead_eqb_eq (r r' : SyncRead) :
    SyncRead_eqb r r' = true <-> r = r'.
  Proof.
    split; intros.
    - unfold SyncRead_eqb in H.
      repeat (apply andb_prop in H; dest; rewrite String.eqb_eq in *).
      destruct r, r'; simpl in *; subst; auto.
    - rewrite H.
      unfold SyncRead_eqb; repeat rewrite String.eqb_refl; auto.
  Qed.
              
  Fixpoint inlineSyncResFile (read : SyncRead) (rf : RegFileBase) k (a : EActionT k) : EActionT k :=
    match rf with
    | @Build_RegFileBase _isWrMask _num _dataArray _readers _write _idxNum _Data _init =>
      match read with
      | @Build_SyncRead _readReqName _readResName _readRegName => 
        match _readers with
        | Async _ => a
        | Sync isAddr reads =>
          match (existsb (SyncRead_eqb read) reads) with
          | true =>
            match a with
            | EMCall g sign arg cont =>
              match String.eqb _readResName g with
              | true =>
                match Signature_dec sign (Void, Array _num _Data) with
                | left isEq =>
                  ESyncReadRes _idxNum _readRegName _dataArray isAddr (fun array => inlineSyncResFile read rf (match isEq in _ = Y return fullType ty (SyntaxKind (snd Y)) -> EActionT k with | eq_refl => cont end array))
                | right _ => EMCall g sign arg (fun ret => inlineSyncResFile read rf (cont ret))
                end 
              | false => EMCall g sign arg (fun ret => inlineSyncResFile read rf (cont ret))
              end
            | ELetExpr _ e cont => ELetExpr e (fun ret => inlineSyncResFile read rf (cont ret))
            | ELetAction _ a cont => ELetAction (inlineSyncResFile read rf a) (fun ret => inlineSyncResFile read rf (cont ret))
            | EReadNondet k c => EReadNondet k (fun ret => inlineSyncResFile read rf (c ret))
            | EReadReg r k c => EReadReg r k (fun ret => inlineSyncResFile read rf (c ret))
            | EWriteReg r k e a => EWriteReg r e (inlineSyncResFile read rf a)
            | EIfElse p _ aT aF c => EIfElse p (inlineSyncResFile read rf aT) (inlineSyncResFile read rf aF) (fun ret => inlineSyncResFile read rf (c ret))
            | ESys ls c => ESys ls (inlineSyncResFile read rf c)
            | EReturn e => EReturn e
            | EAsyncRead idxNum num dataArray idx k cont =>
              EAsyncRead idxNum dataArray idx (fun ret => inlineSyncResFile read rf (cont ret))
            | EWrite idxNum num dataArray idx Data val mask cont =>
              EWrite idxNum dataArray idx val mask (inlineSyncResFile read rf cont)
            | ESyncReadReq idxNum num readReg dataArray idx Data isAddr cont =>
              ESyncReadReq idxNum num readReg dataArray idx Data isAddr (inlineSyncResFile read rf cont)
            | ESyncReadRes idxNum num readReg dataArray Data isAddr cont =>
              ESyncReadRes idxNum readReg dataArray isAddr (fun v => inlineSyncResFile read rf (cont v))
            end
          | false => a
          end
        end
      end
    end.

  Fixpoint inlineSyncReqFile (read : SyncRead) (rf : RegFileBase) k (a : EActionT k) : EActionT k :=
    match rf with
    | @Build_RegFileBase _isWrMask _num _dataArray _readers _write _idxNum _Data _init =>
      match read with
      | @Build_SyncRead _readReqName _readResName _readRegName => 
        match _readers with
        | Async _ => a
        | Sync isAddr reads =>
          match (existsb (SyncRead_eqb read) reads) with
          | true =>
            match a with
            | EMCall g sign arg cont =>
              match String.eqb _readReqName g with
              | true =>
                match Signature_dec sign (Bit (Nat.log2_up _idxNum), Void) with
                | left isEq =>
                  let inValue := (match isEq in _ = Y return Expr ty (SyntaxKind (fst Y)) with | eq_refl => arg end) in
                  ELetExpr ($$ (zToWord 0 0))%kami_expr
                           (fun v => ESyncReadReq _idxNum _num _readRegName _dataArray inValue _Data isAddr (inlineSyncReqFile read rf (match isEq in _ = Y return fullType ty (SyntaxKind (snd Y)) -> EActionT k with
                                                                                                       | eq_refl => cont
                                                                                                       end v)))
                | right _ => EMCall g sign arg (fun ret => inlineSyncReqFile read rf (cont ret))
                end 
              | false => EMCall g sign arg (fun ret => inlineSyncReqFile read rf (cont ret))
              end
            | ELetExpr _ e cont => ELetExpr e (fun ret => inlineSyncReqFile read rf (cont ret))
            | ELetAction _ a cont => ELetAction (inlineSyncReqFile read rf a) (fun ret => inlineSyncReqFile read rf (cont ret))
            | EReadNondet k c => EReadNondet k (fun ret => inlineSyncReqFile read rf (c ret))
            | EReadReg r k c => EReadReg r k (fun ret => inlineSyncReqFile read rf (c ret))
            | EWriteReg r k e a => EWriteReg r e (inlineSyncReqFile read rf a)
            | EIfElse p _ aT aF c => EIfElse p (inlineSyncReqFile read rf aT) (inlineSyncReqFile read rf aF) (fun ret => inlineSyncReqFile read rf (c ret))
            | ESys ls c => ESys ls (inlineSyncReqFile read rf c)
            | EReturn e => EReturn e
            | EAsyncRead idxNum num dataArray idx k cont =>
              EAsyncRead idxNum dataArray idx (fun ret => inlineSyncReqFile read rf (cont ret))
            | EWrite idxNum num dataArray idx Data val mask cont =>
              EWrite idxNum dataArray idx val mask (inlineSyncReqFile read rf cont)
            | ESyncReadReq idxNum num readReg dataArray idx Data isAddr cont =>
              ESyncReadReq idxNum num readReg dataArray idx Data isAddr (inlineSyncReqFile read rf cont)
            | ESyncReadRes idxNum num readReg dataArray Data isAddr cont =>
              ESyncReadRes idxNum readReg dataArray isAddr (fun v => inlineSyncReqFile read rf (cont v))
            end
          | false => a
          end
        end
      end
    end.
  
  End ReadMap.

    
    Definition getRegFileWrite (rf : RegFileBase) : DefMethT :=
      match rf with
      | @Build_RegFileBase isWrMask num dataArray _ write idxNum Data _ =>
        writeRegFileFn isWrMask num dataArray write idxNum Data
      end.

    Definition getAsyncReads (rf : RegFileBase) (read : string) : DefMethT :=
      (read,
       existT MethodT (Bit (Nat.log2_up (rfIdxNum rf)), Array (rfNum rf) (rfData rf))
              (buildNumDataArray (rfNum rf) (rfDataArray rf) (rfIdxNum rf) (rfData rf))).
    
    Definition getSyncReq (rf : RegFileBase) (isAddr : bool) (read : SyncRead) : DefMethT :=
      if isAddr
      then
        (readReqName read,
         existT MethodT (Bit (Nat.log2_up (rfIdxNum rf)), Void)
                (fun (ty : Kind -> Type) (idx : fullType ty (SyntaxKind (fst (Bit (Nat.log2_up (rfIdxNum rf)), Void)))) =>
                   (Write readRegName read : fst (Bit (Nat.log2_up (rfIdxNum rf)), Void) <-
                                                 Var ty (SyntaxKind (fst (Bit (Nat.log2_up (rfIdxNum rf)), Void))) idx; Ret 
                                                                                                                          Const ty (zToWord 0 0))%kami_action))
      else
        (readReqName read,
         existT MethodT (Bit (Nat.log2_up (rfIdxNum rf)), Void)
                (fun (ty : Kind -> Type) (idx : fullType ty (SyntaxKind (fst (Bit (Nat.log2_up (rfIdxNum rf)), Void)))) =>
                   (LETA vals : Array (rfNum rf) (rfData rf) <- buildNumDataArray (rfNum rf) (rfDataArray rf) (rfIdxNum rf) (rfData rf) ty idx;
                      Write readRegName read : Array (rfNum rf) (rfData rf) <- Var ty (SyntaxKind (Array (rfNum rf) (rfData rf))) vals;
                      Ret Const ty (zToWord 0 0))%kami_action)).

    Definition getSyncRes (rf : RegFileBase) (isAddr : bool) (read : SyncRead) : DefMethT :=
      if isAddr
      then
        (readResName read,
         existT MethodT (Void, Array (rfNum rf) (rfData rf))
                (fun (ty : Kind -> Type) (_ : fullType ty (SyntaxKind (fst (Void, Array (rfNum rf) (rfData rf))))) =>
                   (Read name : Bit (Nat.log2_up (rfIdxNum rf)) <- readRegName read;
                      buildNumDataArray (rfNum rf) (rfDataArray rf) (rfIdxNum rf) (rfData rf) ty name)%kami_action))
      else
        (readResName read,
         existT MethodT (Void, Array (rfNum rf) (rfData rf))
                (fun (ty : Kind -> Type) (_ : fullType ty (SyntaxKind (fst (Void, Array (rfNum rf) (rfData rf))))) =>
                   (Read data : Array (rfNum rf) (rfData rf) <- readRegName read;
                      Ret Var ty (SyntaxKind (Array (rfNum rf) (rfData rf))) data)%kami_action)).

    Definition inlineSingle_Flat_pos meths1 meths2 n :=
      match nth_error meths1 n with
      | Some f => map (inlineSingle_Meth f) meths2
      | None => meths2
      end.

    Definition inlineRf_Meths_Flat (rf : RegFileBase) (l : list DefMethT) :=
      fold_left (inlineSingle_Flat_pos (getMethods (BaseRegFile rf))) (seq 0 (length (getMethods (BaseRegFile rf)))) l.

    Definition inlineSingle_pos k meths (a : ActionT ty k) n :=
      match nth_error meths n with
      | Some f => inlineSingle f a
      | None => a
      end.
  
    Definition getEachRfMethod (rf : RegFileBase) : list DefMethT :=
      (getRegFileWrite rf :: match (rfRead rf) with
                             | Async read => map (getAsyncReads rf) read
                             | Sync isAddr read => map (getSyncReq rf isAddr) read
                                                       ++ map (getSyncRes rf isAddr) read
                             end).

    Definition eachRfMethodInliners k (rf : RegFileBase) : list (EActionT k -> EActionT k) :=
      (inlineWriteFile rf :: match (rfRead rf) with
                             | Async read => map (fun x => @inlineAsyncReadFile x rf k) read
                             | Sync isAddr read => map (fun x => @inlineSyncReqFile x rf k) read
                                                       ++ map (fun x => @inlineSyncResFile x rf k) read
                             end).

    Definition apply_nth {A : Type} (lf : list (A -> A)) (a : A) (n : nat) :=
      match nth_error lf n with
      | Some f => f a
      | None => a
      end.
    
    Definition preCompileSingleRegFile k (ea : EActionT k) (rf : RegFileBase) : EActionT k :=
      fold_left (apply_nth (eachRfMethodInliners k rf)) (seq 0 (length (eachRfMethodInliners k rf))) ea.

    Fixpoint preCompileAllRegFile k (ea : EActionT k) (lrf : list RegFileBase) : EActionT k :=
      match lrf with
      | rf :: lrf' => preCompileAllRegFile (preCompileSingleRegFile ea rf) lrf'
      | nil => ea
      end.
    
    Definition compileActions (readMap : regMapTy) (acts: list (ActionT ty Void)) :=
      fold_left (fun acc a =>
                   CompLetFull acc (fun _ writeMap =>
                                      (CompLetFull (CompRet ($$ (zToWord 0 0))%kami_expr (CompactRegMap (VarRegMap writeMap)))

                                      (fun _ v => @compileAction v _ a ($$ true)%kami_expr (VarRegMap v))))) acts
                (CompRet ($$ (zToWord 0 0))%kami_expr (VarRegMap readMap)).

    Definition compileActionsRf (readMap : regMapTy) (acts : list (ActionT ty Void)) (lrf : list RegFileBase) :=
      fold_left (fun acc a =>
                   CompLetFull acc (fun _ writeMap =>
                                      (CompLetFull (CompRet ($$ (zToWord 0 0))%kami_expr
                                                            (CompactRegMap (VarRegMap writeMap)))
                                                   (fun _ v => @EcompileAction v _ (preCompileAllRegFile (Action_EAction a) lrf) ($$ true)%kami_expr (VarRegMap v))))) acts
                (CompRet ($$ (zToWord 0 0))%kami_expr (VarRegMap readMap)).

    Definition compileRules (readMap : regMapTy) (rules: list RuleT) :=
      compileActions readMap (map (fun a => snd a ty) rules).

    Definition compileRulesRf (readMap : regMapTy) (rules : list RuleT) (lrf : list RegFileBase) :=
      compileActionsRf readMap (map (fun a => snd a ty) rules) lrf.
    
End Compile.
                                                    
Section Semantics.
  Local Notation UpdRegT := RegsT.
  Local Notation UpdRegsT := (list UpdRegT).

  Local Notation RegMapType := (RegsT * UpdRegsT)%type.

  Section PriorityUpds.
    
    Variable o: RegsT.
    Inductive PriorityUpds: UpdRegsT -> RegsT -> Prop :=
    | NoUpds: PriorityUpds nil o
    | ConsUpds (prevUpds: UpdRegsT) (prevRegs: RegsT)
               (prevCorrect: PriorityUpds prevUpds prevRegs)
               (u: UpdRegT)
               (curr: RegsT)
               (currRegsTCurr: getKindAttr o = getKindAttr curr)
               (Hcurr: forall s v, In (s, v) curr -> In (s, v) u \/ ((~ In s (map fst u)) /\ In (s, v) prevRegs))
               fullU
               (HFullU: fullU = u :: prevUpds):
        PriorityUpds fullU curr.

    Lemma prevPrevRegsTrue prevUpds:
      forall prev, PriorityUpds prevUpds prev -> getKindAttr o = getKindAttr prev.
    Proof.
      induction 1; eauto.
    Qed.
    
  End PriorityUpds.
    
  Inductive SemRegMapExpr: (RegMapExpr type RegMapType) -> RegMapType -> Prop :=
  | SemVarRegMap v:
      SemRegMapExpr (VarRegMap _ v) v
  | SemUpdRegMapTrue r (pred: Bool @# type) k val regMap
                     (PredTrue: evalExpr pred = true)
                     old upds
                     (HSemRegMap: SemRegMapExpr regMap (old, upds))
                     upds'
                     (HEqual : upds' = (hd nil upds ++ ((r, existT _ k (evalExpr val)) :: nil)) :: tl upds):
      SemRegMapExpr (@UpdRegMap _ _ r pred k val regMap) (old, upds')
  | SemUpdRegMapFalse r (pred: Bool @# type) k val regMap
                      (PredTrue: evalExpr pred = false)
                      old upds
                      (HSemRegMap: SemRegMapExpr regMap (old, upds)):
      SemRegMapExpr (@UpdRegMap _ _ r pred k val regMap) (old, upds)
  | SemCompactRegMap old upds regMap (HSemRegMap: SemRegMapExpr regMap (old, upds)):
      SemRegMapExpr (@CompactRegMap _ _ regMap) (old, nil::upds).
  
  Definition WfRegMapExpr (regMapExpr : RegMapExpr type RegMapType) (regMap : RegMapType) :=
    SemRegMapExpr regMapExpr regMap /\
    let '(old, new) := regMap in
    forall u, In u new -> NoDup (map fst u) /\ SubList (getKindAttr u) (getKindAttr old).
  
  Inductive SemCompActionT: forall k, CompActionT type RegMapType k -> RegMapType ->  MethsT -> type k -> Prop :=
  | SemCompCallTrue (f: string) (argRetK: Kind * Kind) (pred: Bool @# type)
             (arg: fst argRetK @# type)
             lret (cont: fullType type (SyntaxKind (snd argRetK)) -> CompActionT _ _ lret)
             (ret: fullType type (SyntaxKind (snd argRetK)))
             regMap calls val newCalls
             (HNewCalls : newCalls = (f, existT _ argRetK (evalExpr arg, ret)) :: calls)
             (HSemCompActionT: SemCompActionT (cont ret) regMap calls val)
             (HPred : evalExpr pred = true):
      SemCompActionT (@CompCall _ _ f argRetK pred arg lret cont) regMap newCalls val
  | SemCompCallFalse (f: string) (argRetK: Kind * Kind) (pred: Bool @# type)
             (arg: fst argRetK @# type)
             lret (cont: fullType type (SyntaxKind (snd argRetK)) -> CompActionT _ _ lret)
             (ret: fullType type (SyntaxKind (snd argRetK)))
             regMap calls val
             (HSemCompActionT: SemCompActionT (cont ret) regMap calls val)
             (HPred : evalExpr pred = false):
      SemCompActionT (@CompCall _ _ f argRetK pred arg lret cont) regMap calls val
  | SemCompLetExpr k e lret cont
                   regMap calls val
                   (HSemCompActionT: SemCompActionT (cont (evalExpr e)) regMap calls val):
      SemCompActionT (@CompLetExpr _ _ k e lret cont) regMap calls val
  | SemCompNondet k lret cont
                  ret regMap calls val
                  (HSemCompActionT: SemCompActionT (cont ret) regMap calls val):
      SemCompActionT (@CompNondet _ _ k lret cont) regMap calls val
  | SemCompSys ls lret cont
               regMap calls val
               (HSemCompActionT: SemCompActionT cont regMap calls val):
      SemCompActionT (@CompSys _ _ ls lret cont) regMap calls val
  | SemCompRead r k readMap lret cont
                regMap calls val regVal
                updatedRegs readMapValOld readMapValUpds
                (HReadMap: SemRegMapExpr readMap (readMapValOld, readMapValUpds))
                (HUpdatedRegs: PriorityUpds readMapValOld readMapValUpds updatedRegs)
                (HIn: In (r, (existT _ k regVal)) updatedRegs)
                (HSemCompActionT: SemCompActionT (cont regVal) regMap calls val):
      SemCompActionT (@CompRead _ _ r k readMap lret cont) regMap calls val
  | SemCompRet lret e regMap regMapVal calls
               (HCallsNil : calls = nil)
               (HRegMapWf: WfRegMapExpr regMap regMapVal):
      SemCompActionT (@CompRet _ _ lret e regMap) regMapVal calls (evalExpr e)
  | SemCompLetFull k a lret cont
                   regMap_a calls_a val_a
                   (HSemCompActionT_a: SemCompActionT a regMap_a calls_a val_a)
                   regMap_cont calls_cont val_cont newCalls
                   (HNewCalls : newCalls = calls_a ++ calls_cont)
                   (HSemCompActionT_cont: SemCompActionT (cont val_a regMap_a) regMap_cont calls_cont val_cont):
      SemCompActionT (@CompLetFull _ _ k a lret cont) regMap_cont newCalls val_cont
  | SemCompAsyncRead num (dataArray : string) idxNum (idx : Bit (Nat.log2_up idxNum) @# type) Data readMap lret
                     updatedRegs readMapValOld readMapValUpds regVal regMap
                     (HReadMap : SemRegMapExpr readMap (readMapValOld, readMapValUpds))
                     (HUpdatedRegs : PriorityUpds readMapValOld readMapValUpds updatedRegs)
                     (HIn :  In (dataArray, (existT _ (SyntaxKind (Array idxNum Data)) regVal)) updatedRegs)
                     cont calls val contArray
                     (HContArray : contArray =
                                   BuildArray (fun i : Fin.t num =>
                                                 ReadArray
                                                   (Var type _ regVal)
                                                   (CABit Add (Var type (SyntaxKind _) (evalExpr idx) ::
                                                                   Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))::nil))))
                     (HSemCompActionT : SemCompActionT (cont (evalExpr contArray)) regMap calls val):
      SemCompActionT (@CompAsyncRead _ _  idxNum num dataArray idx Data readMap lret cont) regMap calls val
  | SemCompWriteSome num (dataArray : string) idxNum (idx  : Bit (Nat.log2_up idxNum) @# type) Data (array : Array num Data @# type)
                     (optMask : option (Array num Bool @# type)) (writeMap readMap : RegMapExpr type RegMapType) lret mask
                     (HMask : optMask = Some mask)
                     updatedRegs readMapValOld readMapValUpds regVal
                     (HReadMap : SemRegMapExpr readMap (readMapValOld, readMapValUpds))
                     (HUpdatedRegs : PriorityUpds readMapValOld readMapValUpds updatedRegs)
                     (HIn : In (dataArray, (existT _ (SyntaxKind (Array idxNum Data)) regVal)) updatedRegs)
                     regMapVal pred
                     (HUpdate : WfRegMapExpr (UpdRegMap dataArray pred
                                                        (fold_left (fun newArr i =>
                                                                      ITE
                                                                        (ReadArrayConst mask i)
                                                                        (UpdateArray newArr
                                                                                     (CABit Add (idx :: Const type (zToWord _ (Z_of_nat (proj1_sig (Fin.to_nat i))))
                                                                                                     :: nil))
                                                                                     (ReadArrayConst array i))
                                                                        newArr
                                                                   ) (getFins num)
                                                                   (Var type (SyntaxKind (Array idxNum Data)) regVal))
                                                        writeMap) regMapVal)
                     cont regMap_cont calls val
                     (HSemCompActionT : SemCompActionT (cont regMapVal) regMap_cont calls val):
      SemCompActionT (@CompWrite _ _ idxNum num dataArray idx Data array optMask pred writeMap readMap lret cont) regMap_cont calls val
  | SemCompWriteNone num (dataArray : string) idxNum (idx  : Bit (Nat.log2_up idxNum) @# type) Data (array : Array num Data @# type)
                     (optMask : option (Array num Bool @# type)) (writeMap readMap : RegMapExpr type RegMapType) lret
                     (HMask : optMask = None)
                     updatedRegs readMapValOld readMapValUpds regVal
                     (HReadMap : SemRegMapExpr readMap (readMapValOld, readMapValUpds))
                     (HUpdatedRegs : PriorityUpds readMapValOld readMapValUpds updatedRegs)
                     (HIn : In (dataArray, (existT _ (SyntaxKind (Array idxNum Data)) regVal)) updatedRegs)
                     regMapVal pred
                     (HUpdate : WfRegMapExpr (UpdRegMap dataArray pred
                                                        (fold_left (fun newArr i =>
                                                                      (UpdateArray newArr
                                                                                   (CABit Add (idx :: Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))
                                                                                                   :: nil))
                                                                                   (ReadArrayConst array i))
                                                                   ) (getFins num)
                                                                   (Var type (SyntaxKind (Array idxNum Data)) regVal))
                                                        writeMap) regMapVal)
                     cont regMap_cont calls val
                     (HSemCompActionT : SemCompActionT (cont regMapVal) regMap_cont calls val):
      SemCompActionT (@CompWrite _ _ idxNum num dataArray idx Data array optMask pred writeMap readMap lret cont) regMap_cont calls val
  | SemCompSyncReadReqTrue num idxNum readRegName dataArray (idx : Bit (Nat.log2_up idxNum) @# type) k (isAddr : bool)
                           (writeMap : RegMapExpr type RegMapType) readMap lret cont
                           regMapVal pred
                           (HisAddr : isAddr = true)
                           (HWriteMap : WfRegMapExpr (UpdRegMap readRegName pred (Var type (SyntaxKind _) (evalExpr idx)) writeMap) regMapVal)
                           regMap_cont calls val
                           (HSemCompActionT : SemCompActionT (cont regMapVal) regMap_cont calls val):
      SemCompActionT (@CompSyncReadReq _ _ idxNum num readRegName dataArray idx k isAddr pred writeMap readMap lret cont) regMap_cont calls val
  | SemCompSyncReadReqFalse num idxNum readRegName dataArray (idx : Bit (Nat.log2_up idxNum) @# type) Data (isAddr : bool)
                            (writeMap : RegMapExpr type RegMapType) readMap lret cont
                            regMapVal pred
                            (HisAddr : isAddr = false)
                            updatedRegs readMapValOld readMapValUpds regV 
                            (HReadMap : SemRegMapExpr readMap (readMapValOld, readMapValUpds))
                            (HUpdatedRegs : PriorityUpds readMapValOld readMapValUpds updatedRegs)
                            (HRegVal : In (dataArray, (existT _ (SyntaxKind (Array idxNum Data)) regV)) updatedRegs)
                            (HWriteMap : WfRegMapExpr
                                           (UpdRegMap readRegName pred
                                                      (BuildArray (fun i : Fin.t num =>
                                                                     ReadArray
                                                                       (Var type _ regV)
                                                                       (CABit Add (Var type (SyntaxKind _) (evalExpr idx) ::
                                                                                       Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))::nil)))) writeMap) regMapVal)
                            regMap_cont calls val
                            (HSemCompActionT : SemCompActionT (cont regMapVal) regMap_cont calls val):
      SemCompActionT (@CompSyncReadReq _ _ idxNum num readRegName dataArray idx Data isAddr pred writeMap readMap lret cont) regMap_cont calls val
  | SemCompSyncReadResTrue num idxNum readRegName dataArray Data isAddr readMap lret cont
                           (HisAddr : isAddr = true)
                           updatedRegs readMapValOld readMapValUpds regVal idx
                           (HReadMap : SemRegMapExpr readMap (readMapValOld, readMapValUpds))
                           (HUpdatedRegs : PriorityUpds readMapValOld readMapValUpds updatedRegs)
                           (HRegVal1 : In (readRegName, existT _ (SyntaxKind (Bit (Nat.log2_up idxNum))) idx) updatedRegs)
                           (HRegVal2 : In (dataArray, existT _ (SyntaxKind (Array idxNum Data)) regVal) updatedRegs)
                           (contArray : Expr type (SyntaxKind (Array num Data)))
                           (HContArray : contArray =
                                         BuildArray (fun i : Fin.t num =>
                                                       ReadArray
                                                         (Var type _ regVal)
                                                         (CABit Add (Var type (SyntaxKind _) idx ::
                                                                         Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))::nil))))
                           regMap calls val
                           (HSemCompActionT : SemCompActionT (cont (evalExpr contArray)) regMap calls val):
      SemCompActionT (@CompSyncReadRes _ _ idxNum num readRegName dataArray Data isAddr readMap lret cont) regMap calls val
  | SemCompSyncReadResFalse num idxNum readRegName dataArray Data isAddr readMap lret cont
                            (HisAddr : isAddr = false)
                            updatedRegs readMapValOld readMapValUpds regVal
                            (HReadMap : SemRegMapExpr readMap (readMapValOld, readMapValUpds))
                            (HUpdatedRegs : PriorityUpds readMapValOld readMapValUpds updatedRegs)
                            (HIn1 : In (readRegName, (existT _ (SyntaxKind (Array num Data)) regVal)) updatedRegs)
                            regMap calls val
                            (HSemCompActionT : SemCompActionT (cont regVal) regMap calls val):
      SemCompActionT (@CompSyncReadRes _ _ idxNum num readRegName dataArray Data isAddr readMap lret cont) regMap calls val.
    
End Semantics.

Section EActionT_Semantics.
  Variable o : RegsT.

  Inductive UpdOrMeth : Type :=
  | Upd : RegT -> UpdOrMeth
  | Meth : MethT -> UpdOrMeth.

  Definition UpdOrMeths := list UpdOrMeth.

  Fixpoint UpdOrMeths_RegsT (uml : UpdOrMeths) : RegsT :=
    match uml with
    | um :: uml' =>
      match um with
      | Upd u => u :: (UpdOrMeths_RegsT uml')
      | Meth _ => (UpdOrMeths_RegsT uml')
      end
    | nil => nil
    end.

  Fixpoint UpdOrMeths_MethsT (uml : UpdOrMeths) : MethsT :=
    match uml with
    | um :: uml' =>
      match um with 
      | Upd _ => (UpdOrMeths_MethsT uml')
      | Meth m => m :: (UpdOrMeths_MethsT uml')
      end
    | nil => nil
    end.
  
  Inductive ESemAction :
    forall k, EActionT type k -> UpdOrMeths -> type k -> Prop :=
  | ESemCall (meth : string) (s : Kind * Kind) (marg : Expr type (SyntaxKind (fst s))) (mret : type (snd s)) (retK : Kind)
             (fret : type retK) (cont : type (snd s) -> EActionT type retK) (uml : UpdOrMeths) (auml : list UpdOrMeth)
             (HNewList : auml = (Meth (meth, existT SignT s (evalExpr marg, mret)) :: uml))
             (HESemAction : ESemAction (cont mret) uml fret) :
      ESemAction (EMCall meth s marg cont) auml fret
  | ESemLetExpr (k : FullKind) (e : Expr type k) (retK : Kind) (fret : type retK) (cont : fullType type k -> EActionT type retK)
                (uml : UpdOrMeths) (HESemAction : ESemAction (cont (evalExpr e)) uml fret) :
      ESemAction (ELetExpr e cont) uml fret
  | ESemLetAction (k : Kind) (ea : EActionT type k) (v : type k) (retK : Kind) (fret : type retK) (cont : type k -> EActionT type retK)
                  (newUml : list UpdOrMeth) (newUmlCont : list UpdOrMeth)
                  (HDisjRegs : DisjKey (UpdOrMeths_RegsT newUml) (UpdOrMeths_RegsT newUmlCont)) (HESemAction : ESemAction ea newUml v)
                  (HESemActionCont : ESemAction (cont v) newUmlCont fret)
                  (uNewUml : UpdOrMeths)
                  (HNewUml : uNewUml = newUml ++ newUmlCont) :
      ESemAction (ELetAction ea cont) uNewUml fret
  | ESemReadNondet (valueT : FullKind) (valueV : fullType type valueT) (retK : Kind) (fret : type retK)
                   (cont : fullType type valueT -> EActionT type retK) (newUml : UpdOrMeths)
                   (HESemAction : ESemAction (cont valueV) newUml fret):
      ESemAction (EReadNondet _ cont) newUml fret
  | ESemReadReg (r : string) (regT : FullKind) (regV : fullType type regT) (retK : Kind) (fret : type retK) (cont : fullType type regT -> EActionT type retK)
                (newUml : UpdOrMeths) (HRegVal : In (r, existT _ regT regV) o)
                (HESemAction : ESemAction (cont regV) newUml fret) :
      ESemAction (EReadReg r _ cont) newUml fret
  | ESemWriteReg (r : string) (k : FullKind) (e : Expr type k) (retK : Kind) (fret : type retK) (cont : EActionT type retK)
                 (newUml : list UpdOrMeth) (anewUml : list UpdOrMeth)
                 (HRegVal : In (r, k) (getKindAttr o))
                 (HDisjRegs : key_not_In r (UpdOrMeths_RegsT newUml))
                 (HANewUml : anewUml = (Upd (r, existT _ _ (evalExpr e))) :: newUml)
                 (HESemAction : ESemAction cont newUml fret):
      ESemAction (EWriteReg r e cont) anewUml fret
  | ESemIfElseTrue (p : Expr type (SyntaxKind Bool)) (k1 : Kind) (ea ea' : EActionT type k1) (r1 : type k1) (k2 : Kind) (cont : type k1 -> EActionT type k2)
                   (newUml1 newUml2 : list UpdOrMeth) (r2 : type k2)
                   (HDisjRegs : DisjKey (UpdOrMeths_RegsT newUml1) (UpdOrMeths_RegsT newUml2))
                   (HTrue : evalExpr p = true)
                   (HEAction : ESemAction ea  newUml1 r1)
                   (HESemAction : ESemAction (cont r1) newUml2 r2)
                   (unewUml : UpdOrMeths)
                   (HUNewUml : unewUml = newUml1 ++ newUml2) :
      ESemAction (EIfElse p ea ea' cont) unewUml r2
  | ESemIfElseFalse (p : Expr type (SyntaxKind Bool)) (k1 : Kind) (ea ea' : EActionT type k1) (r1 : type k1) (k2 : Kind) (cont : type k1 -> EActionT type k2)
                    (newUml1 newUml2 : list UpdOrMeth) (r2 : type k2)
                    (HDisjRegs : DisjKey (UpdOrMeths_RegsT newUml1) (UpdOrMeths_RegsT newUml2))
                    (HFalse : evalExpr p = false)
                    (HEAction : ESemAction ea' newUml1 r1)
                    (HESemAction : ESemAction (cont r1) newUml2 r2)
                    (unewUml : UpdOrMeths)
                    (HUNewUml : unewUml = newUml1 ++ newUml2) :
      ESemAction (EIfElse p ea ea' cont) unewUml r2
  | ESemSys (ls : list (SysT type)) (k : Kind) (cont : EActionT type k) (r : type k) (newUml : UpdOrMeths)
            (HESemAction : ESemAction cont newUml r) :
      ESemAction (ESys ls cont) newUml r
  | ESemReturn (k : Kind) (e : Expr type (SyntaxKind k)) (evale : fullType type (SyntaxKind k))
               (HEvalE : evale = evalExpr e)
               (newUml : UpdOrMeths)
               (HNewUml : newUml = nil) :
      ESemAction (EReturn e) newUml evale
  | ESemAsyncRead (idxNum num : nat) (dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# type) (Data : Kind) (retK : Kind) (fret : type retK)
                  (newUml : UpdOrMeths) (regV : fullType type (SyntaxKind (Array idxNum Data)))
                  (HRegVal : In (dataArray, (existT _ (SyntaxKind (Array idxNum Data)) regV)) o)
                  (cont : type (Array num Data) -> EActionT type retK)
                  (contArray : Expr type (SyntaxKind (Array num Data)))
                  (HContArray : contArray =
                                BuildArray (fun i : Fin.t num =>
                                              ReadArray
                                                (Var type _ regV)
                                                (CABit Add (Var type (SyntaxKind _) (evalExpr idx) ::
                                                                Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))::nil))))
                  (HESemAction : ESemAction (cont (evalExpr contArray)) newUml fret):
      ESemAction (EAsyncRead idxNum num dataArray idx Data cont) newUml fret
  | ESemWriteSome (idxNum num : nat) (dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# type) (Data : Kind) (array : Array num Data @# type)
                  (optMask : option (Array num Bool @# type)) (retK : Kind) (fret : type retK) (cont : EActionT type retK) (newUml : UpdOrMeths)
                  (anewUml : list UpdOrMeth) (regV : fullType type (SyntaxKind (Array idxNum Data))) (mask : Array num Bool @# type)
                  (HRegVal : In (dataArray, (existT _ (SyntaxKind (Array idxNum Data)) regV)) o)
                  (HMask : optMask = Some mask)
                  (HANewUml : anewUml =
                              (Upd (dataArray, existT _ _
                                                      (evalExpr (fold_left (fun newArr i =>
                                                                      ITE
                                                                        (ReadArrayConst mask i)
                                                                        (UpdateArray newArr
                                                                                     (CABit Add (idx :: Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))
                                                                                                     :: nil))
                                                                                     (ReadArrayConst array i))
                                                                        newArr
                                                                           ) (getFins num)
                                                                           (Var type (SyntaxKind (Array idxNum Data)) regV))))) :: newUml)
                  (HDisjRegs : key_not_In dataArray (UpdOrMeths_RegsT newUml))
                  (HESemAction : ESemAction cont newUml fret) :
      ESemAction (EWrite idxNum dataArray idx array optMask cont) anewUml fret
  | ESemWriteNone (idxNum num : nat) (dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# type) (Data : Kind) (array : Array num Data @# type)
                  (optMask : option (Array num Bool @# type)) (retK : Kind) (fret : type retK) (cont : EActionT type retK) (newUml : UpdOrMeths)
                  (anewUml : list UpdOrMeth) (regV : fullType type (SyntaxKind (Array idxNum Data)))
                  (HRegVal : In (dataArray, (existT _ (SyntaxKind (Array idxNum Data)) regV)) o)
                  (HMask : optMask = None)
                  (HANewUml : anewUml =
                              (Upd (dataArray, existT _ _
                                                      (evalExpr (fold_left (fun newArr i =>
                                                                      (UpdateArray newArr
                                                                                   (CABit Add (idx :: Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))
                                                                                                   :: nil))
                                                                                   (ReadArrayConst array i))
                                                                   ) (getFins num)
                                                                           (Var type (SyntaxKind (Array idxNum Data)) regV))))) :: newUml)
                  (HDisjRegs : key_not_In dataArray (UpdOrMeths_RegsT newUml))
                  (HESemAction : ESemAction cont newUml fret) :
      ESemAction (EWrite idxNum dataArray idx array optMask cont) anewUml fret
  | ESemSyncReadReqTrue (idxNum num : nat) (readRegName dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# type) (Data : Kind) (isAddr : bool)
                        (retK : Kind) (fret : type retK) (cont : EActionT type retK) (newUml : UpdOrMeths) (anewUml : list UpdOrMeth)
                        (HisAddr : isAddr = true)
                        (HRegVal : In (readRegName, (SyntaxKind (Bit (Nat.log2_up idxNum)))) (getKindAttr o))
                        (HDisjRegs : key_not_In readRegName (UpdOrMeths_RegsT newUml))
                        (HANewUml : anewUml = (Upd (readRegName, existT _ _ (evalExpr idx))) :: newUml)
                        (HESemAction : ESemAction cont newUml fret):
      ESemAction (ESyncReadReq idxNum num readRegName dataArray idx Data isAddr cont) anewUml fret
  | ESemSyncReadReqFalse (idxNum num : nat) (readRegName dataArray : string) (idx : Bit (Nat.log2_up idxNum) @# type) (Data : Kind) (isAddr : bool)
                         (retK : Kind) (fret : type retK) (cont : EActionT type retK) (newUml : UpdOrMeths) (anewUml : list UpdOrMeth)
                         (regV : fullType type (SyntaxKind (Array idxNum Data)))
                         (HisAddr : isAddr = false)
                         (HRegVal1 : In (readRegName, (SyntaxKind (Array num Data))) (getKindAttr o))
                         (HRegVal2 : In (dataArray, (existT _ (SyntaxKind (Array idxNum Data)) regV)) o)
                         (HDisjRegs : key_not_In readRegName (UpdOrMeths_RegsT newUml))
                         (HANewUml : anewUml =
                                     (Upd (readRegName, existT _ _
                                                               (evalExpr
                                                                  (BuildArray (fun i : Fin.t num =>
                                                     ReadArray
                                                       (Var type _ regV)
                                                       (CABit Add (Var type (SyntaxKind _) (evalExpr idx) ::
                                                                       Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))::nil))))))) :: newUml)
                         (HESemAction : ESemAction cont newUml fret):
      ESemAction (ESyncReadReq idxNum num readRegName dataArray idx Data isAddr cont) anewUml fret
  | ESemSyncReadResTrue (idxNum num : nat) (readRegName dataArray : string) (Data : Kind) (isAddr : bool) (retK : Kind) (fret : type retK)
                        (regVal : fullType type (SyntaxKind (Array idxNum Data))) (idx : fullType type (SyntaxKind (Bit (Nat.log2_up idxNum))))
                        (cont : type (Array num Data) -> EActionT type retK)
                        (HisAddr : isAddr = true)
                        (HRegVal1 : In (readRegName, existT _ (SyntaxKind (Bit (Nat.log2_up idxNum))) idx) o)
                        (HRegVal2 : In (dataArray, existT _ (SyntaxKind (Array idxNum Data)) regVal) o)
                        (contArray : Expr type (SyntaxKind (Array num Data)))
                        (HContArray : contArray =
                                      BuildArray (fun i : Fin.t num =>
                                                       ReadArray
                                                         (Var type _ regVal)
                                                         (CABit Add (Var type (SyntaxKind _) idx ::
                                                                         Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))::nil))))
                        (newUml : UpdOrMeths) 
                        (HESemAction : ESemAction (cont (evalExpr contArray)) newUml fret):
      ESemAction (ESyncReadRes idxNum num readRegName dataArray Data isAddr cont)  newUml fret
  | ESemSyncReadResFalse (idxNum num : nat) (readRegName dataArray : string) (Data : Kind) (isAddr : bool) (retK : Kind) (fret : type retK)
                         (regVal : fullType type (SyntaxKind (Array num Data))) (cont : type (Array num Data) -> EActionT type retK)
                         (HisAddr : isAddr = false)
                         (HRegVal : In (readRegName, existT _ (SyntaxKind (Array num Data)) regVal) o)
                         (newUml : UpdOrMeths) 
                         (HESemAction : ESemAction (cont regVal) newUml fret):
      ESemAction (ESyncReadRes idxNum num readRegName dataArray Data isAddr cont) newUml fret.
                      
End EActionT_Semantics.

Section Properties.

  
  Definition inline_Meths (l : list DefMethT) (xs : list nat) (meth : DefMethT) : DefMethT :=
    let (name, sig_body) := meth in
    (name,
     let (sig, body) := sig_body in
     existT _ sig (fun ty arg => fold_left (inlineSingle_pos l) xs (body ty arg))).

  Definition inlineSingle_Meth_pos (l : list DefMethT) (meth : DefMethT) (n : nat) : DefMethT :=
    match nth_error l n with
    | Some f => inlineSingle_Meth f meth
    | None => meth
    end.

  Definition inline_Rules (l : list DefMethT) (xs : list nat) (rule : RuleT) : RuleT :=
    let (s, a) := rule in
    (s, fun ty => fold_left (inlineSingle_pos l) xs (a ty)).

  Lemma inline_Rules_eq_inlineSome (xs : list nat) :
    forall (meths : list DefMethT) (rules : list RuleT),
      fold_left (fun newRules n => inlineSingle_Rules_pos meths n newRules) xs rules
      = map (inline_Rules meths xs) rules.
  Proof.
    induction xs; unfold inline_Rules; simpl; intros.
    - induction rules; simpl; auto.
      apply f_equal2; auto.
      destruct a; apply f_equal.
      eexists.
    - rewrite IHxs.
      clear; induction rules; simpl.
      + unfold inlineSingle_Rules_pos; destruct nth_error; auto.
      + rewrite <- IHrules. 
        unfold inlineSingle_Rules_pos.
        remember (nth_error meths a) as nth_err.
        destruct nth_err; simpl.
        * apply f_equal2; auto.
          unfold inlineSingle_pos, inline_Rules, inlineSingle_Rule;
            rewrite <- Heqnth_err; simpl.
          destruct a0; simpl.
          apply f_equal.
          eexists.
        * unfold inline_Rules; destruct a0.
          apply f_equal2; auto; apply f_equal.
          unfold inlineSingle_pos at 3; rewrite <- Heqnth_err.
          reflexivity.
  Qed.

  Definition inlineRf_Rules_Flat (rf : RegFileBase) (l : list RuleT) :=
    map (inline_Rules (getRegFileMethods rf) (seq 0 (length (getRegFileMethods rf)))) l.
  
  Corollary inlineAll_Rules_in (lm : list DefMethT) :
    forall lr,
      inlineAll_Rules lm lr = map (inline_Rules lm (seq 0 (length lm))) lr.
  Proof.
    unfold inlineAll_Rules; intros; rewrite inline_Rules_eq_inlineSome; reflexivity.
  Qed.
  
  
  Definition flatInlineSingleRfNSC (m : BaseModule) (rf : RegFileBase) :=
    BaseMod (getRegisters m  ++ getRegFileRegisters rf) (inlineRf_Rules_Flat rf (getRules m)) ((inlineRf_Meths_Flat rf (getMethods m)) ++ (getRegFileMethods rf)).
      
  Definition inlineSingle_Rule_pos (meths : list DefMethT) n (rule : RuleT) :=
    match nth_error meths n with
    | Some f => (inlineSingle_Rule f rule)
    | None => rule
    end.

  Definition inlineSingle_Meths_posmap (meths : list DefMethT) (currMap : DefMethT -> DefMethT) (n : nat) :=
    match nth_error meths n with
    | Some f => (fun x => inlineSingle_Meth (currMap f) (currMap x))
    | None => currMap
    end.
  
  Lemma inlineSingle_map meths:
    forall n,
      inlineSingle_Meths_pos meths n = map (inlineSingle_Meths_posmap meths (fun x => x) n) meths.
  Proof.
    intros.
    unfold inlineSingle_Meths_pos, inlineSingle_Meths_posmap; destruct nth_error;[|rewrite map_id]; auto.
  Qed.
  
  Lemma inlineSome_map xs :
    forall meths,
      fold_left inlineSingle_Meths_pos xs meths = map (fold_left (inlineSingle_Meths_posmap meths) xs (fun x => x)) meths.
  Proof.
    induction xs; simpl; intros;[rewrite map_id; reflexivity|].
    rewrite inlineSingle_map.
    unfold inlineSingle_Meths_posmap at 1 3; destruct nth_error.
    - rewrite IHxs.
      rewrite map_map, forall_map; intros.
      repeat rewrite <- fold_left_rev_right.
      clear.
      revert x; induction (rev xs); simpl; auto; intros.
      unfold inlineSingle_Meths_posmap at 1 3.
      remember (nth_error _ _) as nth_err0.
      remember (nth_error meths a) as nth_err1.
      destruct nth_err0, nth_err1; auto.
      + symmetry in Heqnth_err1.
        apply (map_nth_error (fun x => inlineSingle_Meth d x)) in Heqnth_err1.
        rewrite Heqnth_err1 in Heqnth_err0; inv Heqnth_err0.
        rewrite IHl; simpl.
        apply f_equal2; auto.
      + exfalso.
        specialize (nth_error_map (fun x : DefMethT => inlineSingle_Meth d x) (fun x => False) a meths) as P0.
        rewrite <- Heqnth_err0, <- Heqnth_err1 in P0; rewrite P0; auto.
      + exfalso.
        specialize (nth_error_map (fun x : DefMethT => inlineSingle_Meth d x) (fun x => False) a meths) as P0.
        rewrite <- Heqnth_err0, <- Heqnth_err1 in P0; rewrite <- P0; auto.
    - rewrite map_id; apply IHxs.
  Qed.
  
  Definition inlineAll_Rules_map (meths : list DefMethT) (rules : list RuleT) :=
    map (fold_left (fun rle n => inlineSingle_Rule_pos meths n rle) (seq 0 (length meths))) rules.
  
  Lemma inlineAll_Rules_in' (lm : list DefMethT) :
    forall lr,
      inlineAll_Rules lm lr = inlineAll_Rules_map lm lr.
  Proof.
    unfold inlineAll_Rules, inlineAll_Rules_map.
    induction (seq 0 (length lm)); simpl; intros.
    - rewrite map_id; reflexivity.
    - rewrite IHl.
      clear; induction lr; simpl.
      + unfold inlineSingle_Rules_pos; destruct nth_error; simpl; auto.
      + unfold inlineSingle_Rules_pos, inlineSingle_Rule_pos at 3.
        remember (nth_error lm a) as nth_err.
        destruct nth_err; simpl; apply f_equal; rewrite <- IHlr;
          unfold inlineSingle_Rules_pos; rewrite <- Heqnth_err; reflexivity.
  Qed.
  
  Lemma NeverCall_NoCalls k (a : ActionT type k) :
    NeverCallActionT a -> (forall l, NoCallActionT l a).
  Proof.
    intro; induction a; inv H; EqDep_subst;
      econstructor; eauto; intros; contradiction.
  Qed.
  
  Lemma NeverCall_inline k (a : ActionT type k):
    forall (ls : list string) (f : DefMethT),
      (forall v,
          NeverCallActionT (projT2 (snd f) type v)) ->
      NoCallActionT ls a ->
      NoCallActionT ls (inlineSingle f a).
  Proof.
    induction a; intros; simpl; eauto; try (inv H1; EqDep_subst; econstructor; eauto).
    - destruct String.eqb; [destruct Signature_dec|]; subst; inv H1; EqDep_subst;
        econstructor; eauto.
      econstructor; eauto; simpl; intro.
      apply NeverCall_NoCalls; eauto.
    - inv H0; EqDep_subst; econstructor; eauto.
    - inv H0; EqDep_subst; econstructor; eauto.
  Qed.

  Lemma NotCalled_NotInlined k (a : ActionT type k) :
    forall (ls : list string) (f : DefMethT),
      In (fst f) ls ->
      NoCallActionT ls a ->
      inlineSingle f a = a.
  Proof.
    induction a; simpl; auto; intros.
    - remember (String.eqb _ _) as strb; symmetry in Heqstrb.
      destruct strb;[destruct Signature_dec|]; subst.
      + exfalso; rewrite String.eqb_eq in *; inv H1; EqDep_subst; contradiction.
      + exfalso; rewrite String.eqb_eq in *; inv H1; EqDep_subst; contradiction.
      + inv H1; EqDep_subst.
        apply f_equal2; auto.
        assert (a = (fun ret => a ret)) as P0.
        { eexists. }
        rewrite P0; apply functional_extensionality; intro; apply (H _ ls); auto.
    - inv H1; EqDep_subst.
      apply f_equal.
      assert (a = (fun ret => a ret)) as P0.
      { eexists. }
      rewrite P0; apply functional_extensionality; intro; apply (H _ ls); auto.
    - inv H1; EqDep_subst.
      apply f_equal2; eauto.
      assert (a0 = (fun ret => a0 ret)) as P0.
      { eexists. }
      rewrite P0; apply functional_extensionality; intro; apply (H _ ls); auto.
    - inv H1; EqDep_subst.
      apply f_equal.
      assert (a = (fun ret => a ret)) as P0.
      { eexists. }
      rewrite P0; apply functional_extensionality; intro; apply (H _ ls); auto.
    - inv H1; EqDep_subst.
      apply f_equal.
      assert (a = (fun ret => a ret)) as P0.
      { eexists. }
      rewrite P0; apply functional_extensionality; intro; apply (H _ ls); auto.
    - inv H0; EqDep_subst.
      apply f_equal; eauto.
    - inv H1; EqDep_subst.
      apply f_equal3; eauto.
      assert (a3 = (fun ret => a3 ret)) as P0.
      { eexists. }
      rewrite P0; apply functional_extensionality; intro; apply (H _ ls); auto.
    - inv H0; EqDep_subst.
      apply f_equal; eauto.
  Qed.

  Lemma seq_nil n m :
    seq n m = nil ->
    m = 0.
  Proof.
    induction m; auto; intro; exfalso.
    rewrite seq_eq in H.
    apply app_eq_nil in H; dest.
    inv H0.
  Qed.

  Lemma NilNoCall k (a : ActionT type k) :
      NoCallActionT nil a.
  Proof.
    induction a; intros; econstructor; eauto.
  Qed.

  Lemma NoSelfCall_ignorable k (a : ActionT type k) :
    forall (l1 l2 : list DefMethT) (n : nat),
      n < length l1 ->
      NoCallActionT (map fst l1) a ->
      inlineSingle_pos (inlineAll_Meths (l1 ++ l2)) a n = a.
  Proof.
    unfold inlineSingle_pos; intros;
      remember (nth_error (inlineAll_Meths (l1 ++ l2)) n) as nth_err0; destruct nth_err0; auto.
    eapply NotCalled_NotInlined; eauto.
    symmetry in Heqnth_err0.
    apply (map_nth_error fst) in Heqnth_err0.
    rewrite <- SameKeys_inlineAll_Meths, map_app, nth_error_app1 in Heqnth_err0.
    + apply (nth_error_In _ _ Heqnth_err0).
    + rewrite map_length; assumption.
  Qed.

  Lemma unifyWO (x : word 0):
    x = (evalExpr (Const type (zToWord 0 0))).
  Proof.
    simpl.
    apply unique_word_0.
  Qed.

  Lemma getKindAttr_fst {A B : Type} {P : B -> Type}  {Q : B -> Type} (l1 : list (A * {x : B & P x})):
    forall  (l2 : list (A * {x : B & Q x})),
      getKindAttr l1 = getKindAttr l2 ->
      (map fst l1) = (map fst l2).
  Proof.
    induction l1, l2; intros; auto; simpl in *; inv H.
    erewrite IHl1; eauto.
  Qed.

  Lemma SemRegExprVals expr :
    forall o1 o2,
      SemRegMapExpr expr o1 ->
      SemRegMapExpr expr o2 ->
      o1 = o2.
  Proof.
    induction expr; intros; inv H; inv H0; EqDep_subst; auto;
      try congruence; specialize (IHexpr _ _ HSemRegMap HSemRegMap0); inv IHexpr; auto.
  Qed.

  Lemma UpdRegs_same_nil o :
    UpdRegs (nil::nil) o o.
  Proof.
    unfold UpdRegs.
    repeat split; auto.
    intros.
    right; unfold not; split; intros; dest; auto.
    destruct H0; subst; auto.
  Qed.

  Lemma NoDup_app_split {A : Type} (l l' : list A) :
    NoDup (l++l') ->
    forall a,
      In a l ->
      ~ In a l'.
  Proof.
    induction l'; repeat intro;[inv H1|].
    specialize (NoDup_remove _ _ _ H) as P0; dest.
    inv H1; apply H3; rewrite in_app_iff; auto.
    exfalso; eapply IHl'; eauto.
  Qed.

  Lemma PriorityUpds_Equiv old upds new
        (HNoDupOld : NoDup (map fst old))
        (HNoDupUpds : forall u, In u upds -> NoDup (map fst u)) :
    PriorityUpds old upds new ->
    forall new',
      PriorityUpds old upds new' ->
      SubList new new'.
  Proof.
    induction 1; intros.
    - inv H.
      + apply SubList_refl.
      + discriminate.
    - subst.
      inv H0; inv HFullU.
      repeat intro.
      destruct x.
      specialize (Hcurr _ _ H0).
      specialize (getKindAttr_map_fst _ _ currRegsTCurr0) as P0.
      specialize (getKindAttr_map_fst _ _ currRegsTCurr) as P1.
      assert (In s (map fst new')).
      { rewrite <- P0, P1, in_map_iff. exists (s, s0); split; auto. }
      rewrite in_map_iff in H1; dest.
      destruct x; simpl in *; subst.
      specialize (Hcurr0 _ _ H2).
      specialize (HNoDupUpds _ (or_introl _ (eq_refl))) as P3.
      destruct Hcurr, Hcurr0; dest.
      + rewrite <-(KeyMatching3 _ _ _ P3 H3 H1 eq_refl).
        assumption.
      + exfalso; apply H3.
        rewrite in_map_iff.
        exists (s, s0); split; auto.
      + exfalso; apply H1.
        rewrite in_map_iff.
        exists (s, s2); split; auto.
      + assert (forall u,  In u prevUpds0 -> NoDup (map fst u)) as P4; eauto.
        specialize (IHPriorityUpds P4 _ prevCorrect _ H5).
        rewrite (getKindAttr_map_fst _ _ (prevPrevRegsTrue prevCorrect)) in HNoDupOld.
        rewrite (KeyMatching3 _ _ _ HNoDupOld H4 IHPriorityUpds eq_refl) in *.
        assumption.
  Qed.

  Lemma PriorityUpdsCompact upds:
    forall old new,
      PriorityUpds old upds new -> PriorityUpds old (nil::upds) new.
  Proof.
    induction upds.
    - econstructor 2 with (u := nil) (prevUpds := nil); eauto; repeat constructor.
      inv H; eauto.
    - intros.
      econstructor 2 with (u := nil) (prevUpds := a :: upds); eauto.
      inv H; auto.
  Qed.

  Lemma KeyMatch (l1 : RegsT) :
    NoDup (map fst l1) ->
    forall l2,
      map fst l1 = map fst l2 ->
      (forall s v, In (s, v) l1 -> In (s, v) l2) ->
      l1 = l2.
  Proof.
    induction l1; intros.
    - destruct l2; inv H0; auto.
    - destruct a; simpl in *.
      destruct l2; inv H0.
      destruct p; simpl in *.
      inv H.
      specialize (H1 _ _ (or_introl (eq_refl))) as TMP; destruct TMP.
      + rewrite H in *.
        assert (forall s v, In (s, v) l1 -> In (s, v) l2).
        { intros.
          destruct (H1 _ _ (or_intror H0)); auto.
          exfalso.
          inv H2.
          apply H3.
          rewrite in_map_iff.
          exists (s2, v); auto.
        }
        rewrite (IHl1 H5 _ H4 H0).
        reflexivity.
      + exfalso.
        apply H3.
        rewrite H4, in_map_iff.
        exists (s, s0); auto.
  Qed.
  
  Lemma CompactPriorityUpds upds:
    forall old,
      NoDup (map fst old) ->
      forall new, 
        PriorityUpds old (nil::upds) new -> PriorityUpds old upds new.
  Proof.
    induction upds; intros.
    - enough (old = new).
      { subst; constructor. }
      inv H0; inv HFullU; inv prevCorrect;[|discriminate]; simpl in *.
      apply getKindAttr_map_fst in currRegsTCurr.
      assert (forall s v, In (s, v) new -> In (s, v) prevRegs).
      { intros.
        destruct (Hcurr _ _ H0);[contradiction|dest]; auto.
      }
      symmetry.
      apply KeyMatch; auto.
      rewrite currRegsTCurr in H; assumption.
    - inv H0; inv HFullU.
      enough ( new = prevRegs).
      { rewrite H0; auto. }
      apply getKindAttr_map_fst in currRegsTCurr.
      specialize (getKindAttr_map_fst _ _ (prevPrevRegsTrue prevCorrect)) as P0.
      rewrite currRegsTCurr in H.
      eapply KeyMatch; eauto.
      + rewrite <- currRegsTCurr; assumption.
      + intros.
        destruct (Hcurr _ _ H0);[contradiction| dest; auto].
  Qed.

  Lemma CompactPriorityUpds_iff {old} (NoDupsOld : NoDup (map fst old)) upds new:
    PriorityUpds old (nil::upds) new <-> PriorityUpds old upds new.
  Proof.
    split; eauto using CompactPriorityUpds, PriorityUpdsCompact.
  Qed.

  
  Local Coercion BaseRegFile : RegFileBase >-> BaseModule.
  
  Lemma RegFileBase_inlineSingle_invar (rf : RegFileBase) f:
    map (inlineSingle_Meth f) (getMethods rf) = getMethods rf.
  Proof.
    destruct rf, rfRead; simpl in *.
    - assert (map (inlineSingle_Meth f) (readRegFile rfNum rfDataArray reads rfIdxNum rfData)
              = (readRegFile rfNum rfDataArray reads rfIdxNum rfData)) as P0.
      { unfold readRegFile.
        induction reads; simpl; auto.
        destruct String.eqb; rewrite IHreads; auto. }
      destruct String.eqb, rfIsWrMask; rewrite P0; auto.
    - assert (map (inlineSingle_Meth f) (readSyncRegFile isAddr rfNum rfDataArray reads rfIdxNum rfData)
              = readSyncRegFile isAddr rfNum rfDataArray reads rfIdxNum rfData) as P0.
      { destruct isAddr; simpl; rewrite map_app; apply f_equal2; induction reads;
          simpl; auto; destruct String.eqb; rewrite IHreads; auto. }
      rewrite P0.
      destruct String.eqb; auto.
      destruct rfIsWrMask; auto.
  Qed.
    
  Lemma RegFileBase_inlineSome_invar (rf : RegFileBase) xs:
    fold_left inlineSingle_Meths_pos xs (getMethods rf) = getMethods rf.
  Proof.
    induction xs; simpl in *; auto.
    unfold inlineSingle_Meths_pos in *.
    remember (nth_error (getRegFileMethods rf) a) as nth_err.
    destruct nth_err; setoid_rewrite <- Heqnth_err; simpl; auto.
    specialize (nth_error_In _ _ (eq_sym Heqnth_err)) as P0.
    setoid_rewrite RegFileBase_inlineSingle_invar; assumption.
  Qed.

  Corollary RegFileBase_inlineAll_invar (rf : RegFileBase) :
    inlineAll_Meths (getMethods rf) = getMethods rf.
  Proof.
    unfold inlineAll_Meths.
    apply RegFileBase_inlineSome_invar.
  Qed.

  Lemma NoSelfCall_RegFileBase (rf : RegFileBase) :
    NoSelfCallBaseModule rf.
  Proof.
    unfold NoSelfCallBaseModule, NoSelfCallRulesBaseModule, NoSelfCallMethsBaseModule; split; simpl; intros;[contradiction|].
    destruct rf, rfRead; simpl in *.
    - destruct H, rfIsWrMask; subst; simpl in *.
      + unfold updateNumDataArrayMask.
        repeat econstructor.
      + unfold updateNumDataArray.
        repeat econstructor.
      + enough (forall l, NoCallActionT l (projT2 (snd meth) type arg)) as P0.
        { apply P0. }
        intros.
        unfold readRegFile in *; simpl in *.
        unfold buildNumDataArray in *.
        induction reads; simpl in *;[contradiction|].
        destruct H; subst; simpl.
        * repeat econstructor.
        * apply (IHreads H).
      + enough (forall l, NoCallActionT l (projT2 (snd meth) type arg)) as P0.
        { apply P0. }
        unfold readRegFile in *; simpl in *.
        unfold buildNumDataArray in *.
        intros.
        induction reads; simpl in *;[contradiction|].
        destruct H; subst; simpl.
        * repeat econstructor.
        * apply (IHreads H).
    - destruct H; subst; simpl in *.
      + destruct rfIsWrMask; simpl in *.
        * unfold updateNumDataArrayMask in *; simpl in *.
          repeat econstructor.
        * unfold updateNumDataArray; simpl.
          repeat econstructor.
      + enough (forall l, NoCallActionT l (projT2 (snd meth) type arg)).
        { apply H0. }
        intros.
        unfold readSyncRegFile in *.
        destruct isAddr.
        * rewrite in_app_iff in H.
          destruct H; simpl in *.
          -- induction reads; simpl in *;[contradiction|].
             destruct H; subst; simpl.
             ++ repeat econstructor.
             ++ apply (IHreads H).
          -- induction reads; simpl in *;[contradiction|].
             destruct H; subst; simpl in *.
             ++ repeat econstructor.
             ++ apply (IHreads H).
        * rewrite in_app_iff in H.
          destruct H.
          -- induction reads; simpl in *;[contradiction|].
             destruct H; subst.
             ++ repeat econstructor.
             ++ apply (IHreads H).
          -- induction reads; simpl in *;[contradiction|].
             destruct H; subst.
             ++ repeat econstructor.
             ++ apply (IHreads H).
  Qed.
  
  Lemma inline_Meths_eq_inlineSome (xs : list nat) :
    forall (l l' : list DefMethT)
           (HDisjMeths : DisjKey l l'),
      fold_left (inlineSingle_Flat_pos l') xs l = map (inline_Meths l' xs) l.
  Proof.
    induction xs; simpl; intros.
    - unfold inline_Meths; induction l; simpl in *; auto.
      rewrite <-IHl.
      + destruct a, s0, x; simpl.
        reflexivity.
      + intro k; specialize (HDisjMeths k); simpl in *; firstorder fail.
    - rewrite IHxs.
      + unfold inlineSingle_Flat_pos.
        remember (nth_error l' a) as nth_err.
        destruct nth_err.
        * unfold inline_Meths at 2; simpl.
          unfold inlineSingle_pos at 2.
          rewrite <- Heqnth_err.
          induction l; simpl; auto.
          rewrite <- IHl.
          -- apply f_equal2; auto.
             unfold inline_Meths, inlineSingle_Meth.
             destruct a0, s0.
             remember (String.eqb _ _ ) as strd; symmetry in Heqstrd.
             destruct strd; auto; rewrite String.eqb_eq in *.
             exfalso.
             specialize (nth_error_In _ _ (eq_sym Heqnth_err)) as P0.
             destruct d; subst.
             apply (in_map fst) in P0.
             clear - HDisjMeths P0.
             destruct (HDisjMeths s0); auto; apply H; left; reflexivity.
          -- clear - HDisjMeths.
             intro k; specialize (HDisjMeths k); simpl in *; firstorder fail.
        * unfold inline_Meths at 2; simpl.
          unfold inlineSingle_pos at 2.
          rewrite <- Heqnth_err.
          fold (inline_Meths l' xs).
          reflexivity.
      + clear - HDisjMeths.
        intro k; specialize (HDisjMeths k).
        enough (map fst (inlineSingle_Flat_pos l' l a) = (map fst l)).
        { rewrite H; auto. }
        unfold inlineSingle_Flat_pos.
        destruct nth_error; auto.
        apply inline_preserves_keys_Meth.
  Qed.
  
  Lemma getFromEach_getMethods (rf : RegFileBase) :
    getMethods rf = getEachRfMethod rf.
  Proof.
    unfold getEachRfMethod; destruct rf; simpl.
    destruct rfRead; simpl; auto.
    unfold readSyncRegFile, getSyncReq, getSyncRes; simpl.
    destruct isAddr; auto.
  Qed.

  Lemma RegFileMethods_inline_invar (rf : RegFileBase) (f : DefMethT) :
    forall g,
      In g (getMethods rf) ->
      inlineSingle_Meth f g = g.
  Proof.
    intros; destruct rf; simpl in *.
    inv H.
    - unfold inlineSingle_Meth; simpl.
      destruct String.eqb, rfIsWrMask; unfold writeRegFileFn; auto.
    - destruct rfRead.
      + induction reads; simpl in *; [contradiction|].
        inv H0; simpl.
        * destruct String.eqb; auto.
        * apply IHreads; auto.
      + induction reads, isAddr; unfold readSyncRegFile in *; simpl in *;[contradiction| contradiction| |]; inv H0.
        * unfold inlineSingle_Meth.
          destruct String.eqb; auto.
        * rewrite in_app_iff in *; simpl in *.
          inv H; eauto.
          inv H0; eauto.
          unfold inlineSingle_Meth.
          destruct String.eqb; auto.
        * unfold inlineSingle_Meth.
          destruct String.eqb; auto.
        * rewrite in_app_iff in *; simpl in *.
          inv H; eauto.
          inv H0; eauto.
          unfold inlineSingle_Meth.
          destruct String.eqb; auto.
  Qed.
  
  Lemma inlineAll_Meths_RegFile_flat1 :
    forall (rf : RegFileBase) (l l' : list DefMethT) (HSubList : SubList l' (getMethods rf)) n (Hlen : n < length l),
      inlineSingle_Meths_pos (l ++ l') n = inlineSingle_Meths_pos l n ++ l'.
  Proof.
    intros; unfold inlineSingle_Meths_pos.
    remember (nth_error (l ++ l') n) as plc.
    destruct plc.
    - rewrite nth_error_app1 in Heqplc; auto.
      rewrite <-Heqplc; rewrite map_app.
      induction l'; auto; simpl.
      specialize (HSubList _ (in_eq _ _)) as P0.
      rewrite (RegFileMethods_inline_invar _ _ _ P0).
      assert (SubList l' (getMethods rf)) as P1.
      { repeat intro; apply HSubList; right; assumption. }
      specialize (IHl' P1).
      apply app_inv_head in IHl'; rewrite IHl'.
      reflexivity.
    - symmetry in Heqplc.
      rewrite nth_error_None, app_length in Heqplc.
      assert (length l <= n) as P0.
      { lia. }
      rewrite <- nth_error_None in P0.
      rewrite P0.
      reflexivity.
  Qed.

  Lemma inlineAll_Meths_RegFile_flat2 :
    forall (rf : RegFileBase) (l l' : list DefMethT)
           (HSubList : SubList l' (getMethods rf)) n
           (Hlen : length l <= n) f (HSome : nth_error l' (n - length l) = Some f),
      inlineSingle_Meths_pos (l ++ l') n = (map (inlineSingle_Meth f) l) ++ l'.
  Proof.
    intros; unfold inlineSingle_Meths_pos.
    remember (nth_error (l ++ l') n) as plc.
    destruct plc.
    - rewrite nth_error_app2 in Heqplc; auto.
      rewrite <- Heqplc in HSome; inv HSome.
      rewrite map_app.
      enough (forall f' l'', SubList l'' (getMethods rf) -> map (inlineSingle_Meth f') l'' = l'').
      { rewrite (H f l'); auto. }
      clear.
      intros; induction l''; simpl; auto.
      specialize (H _ (in_eq _ _)) as P0.
      rewrite (RegFileMethods_inline_invar _ _ _ P0).
      rewrite IHl''; auto.
      repeat intro; apply H; right; assumption.
    - symmetry in Heqplc.
      rewrite nth_error_None, app_length in Heqplc.
      assert (length l' <= n - length l) as P0.
      { lia. }
      rewrite <- nth_error_None in P0.
      rewrite P0 in HSome; discriminate.
  Qed.

  Lemma inlineSingle_Meths_pos_length l n :
    length (inlineSingle_Meths_pos l n) = length l.
  Proof.
    setoid_rewrite <- (map_length fst).
    rewrite <- SameKeys_inlineSingle_Meth_pos; reflexivity.
  Qed.

  Lemma inlineSome_Meths_pos_length l xs :
    length (fold_left inlineSingle_Meths_pos xs l) = length l.
  Proof.
    setoid_rewrite <- (map_length fst).
    rewrite <- SameKeys_inlineSome_Meths; reflexivity.
  Qed.
  
  Lemma inlineAll_Meths_RegFile_fold_flat1 n :
    forall (rf : RegFileBase) (l l' : list DefMethT)
           (HSubList : SubList l' (getMethods rf)) (Hlen : n <= length l),
      fold_left inlineSingle_Meths_pos (seq 0 n) (l ++ l') = fold_left inlineSingle_Meths_pos (seq 0 n) l ++ l'.
  Proof.
    intros; repeat rewrite <-fold_left_rev_right.
    induction n.
    - simpl; auto.
    - rewrite seq_eq, rev_app_distr; simpl.
      rewrite IHn; [|lia].
      + rewrite (inlineAll_Meths_RegFile_flat1 rf); auto.
        assert (forall xs, length (fold_right (fun y x => inlineSingle_Meths_pos x y) l xs) = length l) as P0.
        { clear.
          induction xs; simpl; auto.
          rewrite inlineSingle_Meths_pos_length; assumption. }
        rewrite P0; lia.
  Qed.
  
  Lemma seq_app s e :
    forall m (Hm_lte_e : m <= e),
      seq s e = seq s m ++ seq (s + m) (e - m).
  Proof.
    induction e; intros.
    - rewrite Nat.le_0_r in *; subst; simpl; reflexivity.
    - destruct (le_lt_or_eq _ _ Hm_lte_e).
      + rewrite Nat.sub_succ_l; [|lia].
        repeat rewrite seq_eq.
        assert (s + m + (e - m) = s + e) as P0.
        { lia. }
        rewrite (IHe m), app_assoc, P0; auto.
        lia.
      + rewrite <- H.
        rewrite Nat.sub_diag, app_nil_r; reflexivity.
  Qed.

  Lemma inlineSingle_Flat_pos_lengths :
    forall xs ls ls',
      length (fold_left (inlineSingle_Flat_pos ls') xs ls) = length ls.
  Proof.
    induction xs; simpl; auto; intros.
    rewrite IHxs.
    unfold inlineSingle_Flat_pos.
    destruct nth_error; auto.
    rewrite map_length.
    reflexivity.
  Qed.
  
  Lemma inlineAll_Meths_RegFile_fold_flat2 n :
    forall (rf : RegFileBase) (l l' : list DefMethT)
           (HSubList : SubList l' (getMethods rf)) (Hlen : 0 < n - length l),
      fold_left inlineSingle_Meths_pos (seq (length l) (n - (length l))) (l ++ l')
      = fold_left (inlineSingle_Flat_pos l') (seq 0 (n - length l)) l ++ l'.
  Proof.
    intros; induction n.
    - simpl; auto.
    - assert (length l <= n) as TMP.
      { lia. }
      rewrite Nat.sub_succ_l in *; auto.
      + apply lt_n_Sm_le in Hlen.
        destruct (le_lt_or_eq _ _ Hlen).
        * repeat rewrite seq_eq.
          repeat rewrite fold_left_app; simpl.
          rewrite IHn; [rewrite <- le_plus_minus; [|lia]|]; auto.
          remember (nth_error l' (n - length l)) as nth_err.
          destruct nth_err.
          -- symmetry in Heqnth_err.
             assert (length l <= n) as P1.
             { lia. }
             rewrite <-(inlineSingle_Flat_pos_lengths (seq 0 (n - Datatypes.length l)) l l') in Heqnth_err, P1.
             rewrite (inlineAll_Meths_RegFile_flat2 _ _ HSubList P1 Heqnth_err).
             unfold inlineSingle_Flat_pos at 2.
             rewrite inlineSingle_Flat_pos_lengths in Heqnth_err.
             rewrite Heqnth_err.
             reflexivity.
          -- unfold inlineSingle_Meths_pos.
             remember (nth_error (fold_left (inlineSingle_Flat_pos l') (seq 0 (n - Datatypes.length l)) l ++ l') n) as nth_err2.
             destruct nth_err2.
             ++ exfalso.
                assert (nth_error (fold_left (inlineSingle_Flat_pos l') (seq 0 (n - Datatypes.length l)) l ++ l') n <> None) as P1.
                { rewrite <- Heqnth_err2; intro; discriminate. }
                rewrite nth_error_Some in P1.
                rewrite app_length, inlineSingle_Flat_pos_lengths in P1.
                symmetry in Heqnth_err.
                rewrite nth_error_None in Heqnth_err.
                lia.
             ++ unfold inlineSingle_Flat_pos.
                rewrite <- Heqnth_err; reflexivity.
        * rewrite <- H; simpl.
          assert (n = length l) as P0.
          { lia. }
          rewrite  P0 in *; clear TMP.
          remember (nth_error l' (length l - length l)) as nth_err.
          destruct nth_err.
          -- symmetry in Heqnth_err.
             rewrite (inlineAll_Meths_RegFile_flat2 _ _ HSubList (Nat.le_refl _) Heqnth_err).
             unfold inlineSingle_Flat_pos.
             remember (nth_error l' 0) as nth_err2.
             destruct nth_err2.
             ++ rewrite Nat.sub_diag in Heqnth_err.
                rewrite Heqnth_err in *.
                inv Heqnth_err2.
                reflexivity.
             ++ rewrite Nat.sub_diag in Heqnth_err.
                rewrite Heqnth_err in *.
                inv Heqnth_err2.
          -- unfold inlineSingle_Meths_pos.
             remember (nth_error (l ++ l') (Datatypes.length l)) as nth_err2.
             destruct nth_err2.
             ++ exfalso.
                assert (nth_error (l ++ l') (length l) <> None).
                { rewrite <- Heqnth_err2; intro; inv H0. }
                rewrite nth_error_Some in H0.
                symmetry in Heqnth_err.
                rewrite nth_error_None in Heqnth_err.
                rewrite app_length in H0.
                rewrite Nat.sub_diag in Heqnth_err.
                lia.
             ++ unfold inlineSingle_Flat_pos.
                rewrite Nat.sub_diag in Heqnth_err.
                rewrite <- Heqnth_err.
                reflexivity.
  Qed.

  Lemma inlineAll_Meths_RegFile_fold_flat :
    forall (rf : RegFileBase) (l l' : list DefMethT)
           (HSubList : SubList l' (getMethods rf)),
      fold_left inlineSingle_Meths_pos (seq 0 (length (l ++ l'))) (l ++ l')
      = fold_left (inlineSingle_Flat_pos l') (seq 0 (length l'))
                  (fold_left inlineSingle_Meths_pos (seq 0 (length l)) l) ++ l'.
  Proof.
    intros.
    specialize (Nat.le_add_r (length l) (length l')) as P0.
    rewrite app_length, (seq_app _ P0), fold_left_app, Nat.add_0_l.
    rewrite (inlineAll_Meths_RegFile_fold_flat1 _ _ HSubList (Nat.le_refl _ )).
    destruct (zerop (length l')).
    - rewrite e; rewrite minus_plus; simpl.
      rewrite length_zero_iff_nil in e; rewrite e, app_nil_r; reflexivity.
    - assert (0 < (length l + length l') - length l).
      { rewrite minus_plus; assumption. }
      rewrite <- (inlineSome_Meths_pos_length l (seq 0 (Datatypes.length l))) at 1 2 3.
      rewrite <- (inlineSome_Meths_pos_length l (seq 0 (Datatypes.length l))) in H.
      rewrite (inlineAll_Meths_RegFile_fold_flat2 _ _ _ HSubList H).
      rewrite (inlineSome_Meths_pos_length l (seq 0 (Datatypes.length l))) in *.
      rewrite minus_plus.
      rewrite <- (inlineSome_Meths_pos_length l (seq 0 (Datatypes.length l)) ).
      reflexivity.
  Qed.

  Lemma NoSelfCall_inline_invar  k (a : ActionT type k) :
    forall (meth : DefMethT) (l : list DefMethT) (HIn : In (fst meth) (map fst l))
           (HNoCalls : NoCallActionT (map fst l) a),
      inlineSingle meth a = a.
  Proof.
    induction a; simpl; intros; inv HNoCalls; EqDep_subst; eauto.
    - remember (String.eqb _ _) as strb; destruct strb.
      + symmetry in Heqstrb; rewrite String.eqb_eq in *; subst; contradiction.
      + enough ((fun ret  => inlineSingle meth0 (a ret)) = (fun ret => (a ret))).
        { setoid_rewrite H0; reflexivity. }
        apply functional_extensionality.
        intros; eapply H; eauto.
    - enough ((fun ret  => inlineSingle meth (a ret)) = (fun ret => (a ret))).
      { setoid_rewrite H0; reflexivity. }
      apply functional_extensionality.
      intros; eapply H; eauto.
    - enough ((fun ret  => inlineSingle meth (a0 ret)) = (fun ret => (a0 ret))).
      { erewrite IHa; eauto.
        setoid_rewrite H0; reflexivity. }
      apply functional_extensionality.
      intros; eapply H; eauto.
    - enough ((fun ret  => inlineSingle meth (a ret)) = (fun ret => (a ret))).
      { setoid_rewrite H0; reflexivity. }
      apply functional_extensionality.
      intros; eapply H; eauto.
    - enough ((fun ret  => inlineSingle meth (a ret)) = (fun ret => (a ret))).
      { setoid_rewrite H0; reflexivity. }
      apply functional_extensionality.
      intros; eapply H; eauto.
    - erewrite IHa; eauto.
    - enough ((fun ret  => inlineSingle meth (a3 ret)) = (fun ret => (a3 ret))).
      { setoid_rewrite H0; erewrite IHa1, IHa2; eauto. }
      apply functional_extensionality.
      intros; eapply H; eauto.
    - erewrite IHa; eauto.
  Qed.

  Lemma NoSelfCall_inlineSingle_Meth_invar (meth1 meth2 : DefMethT) :
    forall (l : list DefMethT) (HIn : In (fst meth1) (map fst l))
           (HNoMethCalls : forall arg : type (fst (projT1 (snd meth2))),
               NoCallActionT (map fst l) (projT2 (snd meth2) type arg)) arg,
      inlineSingle meth1 (projT2 (snd meth2) type arg) = (projT2 (snd meth2) type arg).
  Proof.
    intros; eapply NoSelfCall_inline_invar; eauto.
  Qed.

  Lemma NoSelfCall_inlineSingle_Rule_invar (rule : RuleT) :
    forall (meth : DefMethT) (l : list DefMethT) (HIn : In (fst meth) (map fst l))
           (HNoRuleCalls : NoCallActionT (map fst l) (snd rule type)),
      inlineSingle meth (snd rule type) = (snd rule type).
  Proof.
    intros; eapply NoSelfCall_inline_invar; eauto.
  Qed.

  Lemma inlineSingle_pos_app_l (l1 l2 : list DefMethT) ty k (a : ActionT ty k) :
    forall n,
      n < length l1 ->
      inlineSingle_pos (l1 ++ l2) a n =  inlineSingle_pos l1 a n.
  Proof.
    intros; unfold inlineSingle_pos.
    remember (nth_error (l1 ++ l2) n) as nth_err0.
    destruct nth_err0; rewrite nth_error_app1 in Heqnth_err0; auto; rewrite <- Heqnth_err0; reflexivity.
  Qed.

  Lemma inlineSingle_pos_app_r (l1 l2 : list DefMethT) ty k (a : ActionT ty k) :
    forall n,
      length l1 <= n ->
      inlineSingle_pos (l1 ++ l2) a n =  inlineSingle_pos l2 a (n - length l1).
  Proof.
    intros; unfold inlineSingle_pos.
    remember (nth_error (l1 ++ l2) n) as nth_err0.
    destruct nth_err0; rewrite nth_error_app2 in Heqnth_err0; auto;  rewrite <- Heqnth_err0; reflexivity.
  Qed.

  Lemma inlineSome_pos_app_l (l1 l2 : list DefMethT) ty k (a : ActionT ty k) n :
      n <= length l1 ->
      fold_left (inlineSingle_pos (l1 ++ l2)) (seq 0 n) a = fold_left (inlineSingle_pos l1) (seq 0 n) a.
  Proof.
    induction n; auto; intros.
    rewrite seq_eq; repeat rewrite fold_left_app; simpl.
    rewrite inlineSingle_pos_app_l; [|lia].
    rewrite IHn; auto; lia.
  Qed.

  Lemma inlineSome_pos_app_r (l1 l2 : list DefMethT) ty k (a : ActionT ty k) n :
    fold_left (inlineSingle_pos (l1 ++ l2)) (seq (length l1) n) a
    = fold_left (inlineSingle_pos l2) (seq 0 n) a.
  Proof.
    induction n; auto; intros.
    repeat rewrite seq_eq; repeat rewrite fold_left_app; simpl.
    rewrite inlineSingle_pos_app_r; [|lia].
    rewrite IHn, minus_plus; reflexivity.
  Qed.
    
  Lemma inlineSome_pos_app (l1 l2 : list DefMethT) ty k (a : ActionT ty k) :
    forall n m,
      n = length l1 ->
      m = length l2 ->
      fold_left (inlineSingle_pos (l1 ++ l2)) (seq 0 (n + m)) a =
      fold_left (inlineSingle_pos l2) (seq 0 m) (fold_left (inlineSingle_pos l1) (seq 0 n) a).
  Proof.
    intros.
    assert (n <= length (l1 ++ l2)) as P0.
    { rewrite app_length; lia. }
    rewrite H, H0, <- app_length.
    rewrite (seq_app _ P0), fold_left_app, app_length, H, minus_plus, plus_O_n.
    rewrite inlineSome_pos_app_r, inlineSome_pos_app_l; auto.
  Qed.

  Lemma inlineAll_Meths_same_len l :
    length (inlineAll_Meths l) = length l.
  Proof.
    setoid_rewrite <- (map_length fst); rewrite <- SameKeys_inlineAll_Meths; reflexivity.
  Qed.

  Lemma SameKeys_inlineSingle_Flat meths1 meths2 n :
    map fst (inlineSingle_Flat_pos meths1 meths2 n) = map fst meths2.
  Proof.
    unfold inlineSingle_Flat_pos; destruct nth_error; auto.
    apply inline_preserves_keys_Meth.
  Qed.

  Lemma SameKeys_inlineSome_Flat xs :
    forall meths1 meths2,
      map fst (fold_left (inlineSingle_Flat_pos meths1) xs meths2) = map fst meths2.
  Proof.
    induction xs; simpl; auto; intros.
    rewrite IHxs, SameKeys_inlineSingle_Flat; reflexivity.
  Qed.
  
  (**** HERE ****)

  Lemma inlineSingle_Meths_posmap_invar1 xs :
    forall fn1 fn2 x1 x2 m1 m2 l (g : DefMethT -> DefMethT),
      fold_left (inlineSingle_Meths_posmap l) xs g (fn1, existT MethodT x1 m1) = (fn2, existT MethodT x2 m2) ->
      (forall fn1' fn2' x1' x2' m1' m2', g (fn1', existT MethodT x1' m1') = (fn2', existT MethodT x2' m2') -> fn1' = fn2' /\ x1' = x2') ->
      fn1 = fn2 /\ x1 = x2.
  Proof.
    intro; induction xs; simpl; intros.
    - eapply H0; eauto.
    - eapply IHxs with (g := (inlineSingle_Meths_posmap l g a)); eauto.
      intros.
      unfold inlineSingle_Meths_posmap in H1.
      destruct nth_error; eauto.
      remember (g (_, _) ) as g_val.
      destruct g_val, s0.
      specialize (H0 _ _ _ _ _ _ (eq_sym Heqg_val)); dest; subst.
      unfold inlineSingle_Meth in H1; destruct String.eqb; inv H1; eauto.
  Qed.


  Lemma inlineSingle_Meths_posmap_invar1' xs :
    forall fn x (m1 : MethodT x) l (g : DefMethT -> DefMethT)
           (HIn : In (fn, existT MethodT x m1) l)
           (HNoCall : forall (meth : DefMethT),
               In meth l ->
               (forall arg, NoCallActionT (map fst l) (projT2 (snd meth) type arg))),
      (forall fn' x' (m1' : MethodT x'),
          In (fn', existT MethodT x' m1') l ->
          exists (m2' : MethodT x'),
            (forall arg, m1' type arg = m2' type arg) /\
            g (fn', existT MethodT x' m1') = (fn', existT MethodT x' m2')) ->
      exists (m2 : MethodT x),
        (forall arg, m1 type arg = m2 type arg) /\
        fold_left (inlineSingle_Meths_posmap l) xs g (fn, existT MethodT x m1)
        = (fn, existT MethodT x m2).
  Proof.
    intro; induction xs; simpl; intros.
    - eapply H; eauto.
    - eapply IHxs with (g := (inlineSingle_Meths_posmap l g a)); eauto.
      intros.
      specialize (H _ _ _ H0) as TMP; dest.
      unfold inlineSingle_Meths_posmap.
      remember (nth_error _ _ ) as nth_err0.
      destruct nth_err0; eauto.
      unfold inlineSingle_Meth; rewrite H2.
      remember (String.eqb (fst (g d)) fn') as s.
      destruct s; eauto.
      exists (fun ty arg => inlineSingle (g d) (x0 ty arg)); split; auto; intros.
      destruct d, s0; simpl in *.
      symmetry in Heqnth_err0; apply nth_error_In in Heqnth_err0.
      specialize (H _ _ _ Heqnth_err0); dest.
      rewrite <- H1, H3.
      symmetry; eapply NoSelfCall_inline_invar.
      + simpl in *; apply (in_map fst _ _ Heqnth_err0).
      + specialize (HNoCall _ H0); simpl in *; eauto.
  Qed.
  
  Lemma flattenInlinedRf1 :
    forall m o l (rf : RegFileBase)
           (HNoCall : NoSelfCallBaseModule m)
           (HDisjKeys : DisjKey (getMethods m) (getMethods rf)),
      Substeps (inlineAll_All_mod (ConcatMod m (BaseRegFile rf))) o l ->
      Substeps (flatInlineSingleRfNSC m rf) o l.
  Proof.
    induction 3; subst; simpl in *.
    - econstructor; eauto.
    - unfold flatInlineSingleRfNSC, inlineRf_Rules_Flat; simpl.
      rewrite app_nil_r, inlineAll_Rules_in in HInRules.
      rewrite in_map_iff in HInRules; dest; destruct x; simpl in *; inv H0.
      econstructor 2 with (u := u) (reads := reads); auto; simpl.
      + instantiate (1 :=  (fun ty => (fold_left (inlineSingle_pos (getRegFileMethods rf)) (seq 0 (length (getRegFileMethods rf)))) (a ty))).
        rewrite in_map_iff; unfold inline_Rules; exists (rn, a); split; auto.
      + unfold inlineAll_Meths in HAction at 1;
          rewrite (inlineAll_Meths_RegFile_fold_flat rf) in HAction; [|apply SubList_refl].
        rewrite inlineAll_Meths_same_len, app_length, inlineSome_pos_app in HAction; auto.
        * enough (forall xs,
                     fold_left
                       (inlineSingle_pos
                          (fold_left (inlineSingle_Flat_pos (getRegFileMethods rf))
                                     (seq 0 (Datatypes.length (getRegFileMethods rf)))
                                     (fold_left inlineSingle_Meths_pos
                                                (seq 0 (Datatypes.length (getMethods m))) 
                                                (getMethods m)))) xs (a type)
                     = (a type)) as P0.
          { setoid_rewrite P0 in HAction; assumption. }
          unfold NoSelfCallBaseModule, NoSelfCallRulesBaseModule in *; dest.
          specialize (H0 _ H1); simpl in *.
          clear - H0; intros.
          induction xs; simpl; auto.
          unfold inlineSingle_pos at 2.
          remember (nth_error _ _) as nth_err0; destruct nth_err0; auto.
          apply eq_sym, nth_error_In in Heqnth_err0.
          apply (in_map fst) in Heqnth_err0.
          rewrite SameKeys_inlineSome_Flat, <- SameKeys_inlineSome_Meths in Heqnth_err0.
          rewrite (NotCalled_NotInlined _ Heqnth_err0 H0).
          assumption.
        * setoid_rewrite <- (map_length fst) at 2.
          rewrite SameKeys_inlineSome_Flat, <- SameKeys_inlineSome_Meths, map_length.
          reflexivity.
    - unfold flatInlineSingleRfNSC, inlineRf_Rules_Flat.
      unfold inlineAll_Meths in HInMeths.
      rewrite (inlineAll_Meths_RegFile_fold_flat rf), in_app_iff in HInMeths.
      inv HInMeths.
      + rewrite inline_Meths_eq_inlineSome in H0.
        * rewrite in_map_iff in H0; dest; destruct x; simpl in *; inv H0; destruct s0; simpl.
          rewrite inlineSome_map, in_map_iff in H1; dest; destruct x0, s0; simpl in *.
          unfold NoSelfCallBaseModule, NoSelfCallMethsBaseModule in HNoCall; dest; clear H.
          specialize (inlineSingle_Meths_posmap_invar1'
                        (seq 0 (length (getMethods m))) s m1 _ (fun x => x) H1 H3) as P0.
          assert (forall (fn' : string) (x' : Signature) (m1' : MethodT x'),
                      In (fn', existT MethodT x' m1') (getMethods m) ->
                      exists m2' : MethodT x',
                        (forall arg : fullType type (SyntaxKind (fst x')), m1' type arg = m2' type arg) /\(fun x : DefMethT => x) (fn', existT MethodT x' m1') = (fn', existT MethodT x' m2')) as P1.
          { clear. intros. exists m1'; split; auto. }
          specialize (P0 P1); clear P1; dest.
          setoid_rewrite H4 in H0.
          inv H0; EqDep_subst.
          econstructor 3 with (reads := reads) (u := u)
                              (fb := existT (fun x => forall x0 : Kind -> Type, fullType x0 (SyntaxKind (fst x)) -> ActionT x0 (snd x)) x
                                            (fun ty arg => fold_left (inlineSingle_pos (getRegFileMethods rf)) (seq 0 (length (getRegFileMethods rf))) (m1 ty arg))); simpl in *;
            eauto.
          -- rewrite in_app_iff; left.
             unfold inlineRf_Meths_Flat.
             rewrite inline_Meths_eq_inlineSome, in_map_iff; auto.
             exists (fn, existT MethodT x m1); split; auto.
          -- rewrite H; assumption.
        * intro k.
          rewrite <- SameKeys_inlineSome_Meths.
          specialize (HDisjKeys k); assumption.
      + econstructor 3; simpl; eauto.
        rewrite in_app_iff; right; assumption.
      + apply SubList_refl.
  Qed.

  Lemma inline_Rules_app lm1 lm2:
    (fun r => inline_Rules (lm1 ++ lm2) (seq 0 (length (lm1 ++ lm2))) r) =
    (fun r => inline_Rules lm2 (seq 0 (length lm2)) (inline_Rules lm1 (seq 0 (length lm1)) r)).
  Proof.
    apply functional_extensionality; intro.
    unfold inline_Rules; destruct x.
    apply f_equal.
    rewrite app_length.
    apply functional_extensionality_dep; intro.
    rewrite inlineSome_pos_app; auto.
  Qed.
  
  Lemma flattenInlinedRf2 :
    forall m o l (rf : RegFileBase)
           (HNoCall : NoSelfCallBaseModule m)
           (HDisjKeys : DisjKey (getMethods m) (getMethods rf)),
      Substeps (flatInlineSingleRfNSC m rf) o l ->
      Substeps (inlineAll_All_mod (ConcatMod m (BaseRegFile rf))) o l.
  Proof.
    induction 3; subst; simpl in *.
    - econstructor 1; eauto.
    - unfold inlineAll_All_mod, inlineRf_Rules_Flat, inlineAll_Meths in *.
      rewrite in_map_iff in HInRules; dest; destruct x.
      unfold inline_Rules in H0; inv H0.
      econstructor 2 with (reads := reads); simpl; auto;[rewrite app_nil_r | | assumption].
      + rewrite inlineAll_Rules_in.
        instantiate (1 := (fun ty => fold_left (inlineSingle_pos
                                       (inlineAll_Meths (getMethods m ++ getRegFileMethods rf)))
                                          (seq 0 (Datatypes.length (inlineAll_Meths (getMethods m ++ getRegFileMethods rf)))) (a ty))).
        unfold inlineAll_Meths; rewrite (inlineAll_Meths_RegFile_fold_flat rf);
          [|apply SubList_refl].
        rewrite in_map_iff; exists (rn, a); split; auto.
      + unfold inlineAll_Meths.
        simpl; rewrite (inlineAll_Meths_RegFile_fold_flat rf);[| apply SubList_refl].
        enough (forall xs,
                   (fold_left
          (inlineSingle_pos
             (fold_left (inlineSingle_Flat_pos (getRegFileMethods rf))
                (seq 0 (Datatypes.length (getRegFileMethods rf)))
                (fold_left inlineSingle_Meths_pos (seq 0 (Datatypes.length (getMethods m)))
                   (getMethods m))))  xs (a type)) = (a type)) as P0.
        { rewrite app_length.
          rewrite inlineSome_pos_app; auto.
          setoid_rewrite P0; assumption. }
        clear - HNoCall H1.
        induction xs; simpl; auto.
        unfold inlineSingle_pos at 2.
        remember (nth_error _ _) as nth_err0.
        destruct nth_err0.
        * rewrite (NoSelfCall_inline_invar _ (getMethods m)); auto.
          -- symmetry in Heqnth_err0.
             apply nth_error_In, (in_map fst) in Heqnth_err0.
             rewrite SameKeys_inlineSome_Flat, <- SameKeys_inlineSome_Meths in Heqnth_err0.
             assumption.
          -- unfold NoSelfCallBaseModule, NoSelfCallRulesBaseModule in HNoCall; dest.
             apply (H _ H1).
        * apply IHxs.
    -
      + unfold inlineAll_All_mod; simpl; rewrite app_nil_r.
        unfold inlineRf_Rules_Flat, inlineAll_Meths in *.
        admit.
  Admitted.
        
  Lemma NoSelfCall_nil (m : BaseModule) :
    getMethods m = nil ->
    NoSelfCallBaseModule m.
  Proof.
    enough (forall {k : Kind} (a : ActionT type k), NoCallActionT nil a).
    { intros.
      unfold NoSelfCallBaseModule, NoSelfCallRulesBaseModule, NoSelfCallMethsBaseModule.
      split; simpl; intros; rewrite H0; auto. }
    intros; induction a; econstructor; eauto.
  Qed.

  Lemma UpdOrMeths_RegsT_app (uml1 uml2 : UpdOrMeths) :
    UpdOrMeths_RegsT (uml1 ++ uml2) = UpdOrMeths_RegsT uml1 ++ UpdOrMeths_RegsT uml2.
  Proof.
    induction uml1; simpl; auto.
    destruct a; simpl; auto.
    rewrite IHuml1; reflexivity.
  Qed.

  Lemma UpdOrMeths_MethsT_app (uml1 uml2 : UpdOrMeths) :
    UpdOrMeths_MethsT (uml1 ++ uml2) = UpdOrMeths_MethsT uml1 ++ UpdOrMeths_MethsT uml2.
  Proof.
    induction uml1; simpl; auto.
    destruct a; simpl; auto.
    rewrite IHuml1; reflexivity.
  Qed.
  
  Lemma SemCompActionEEquivBexpr (k : Kind) (ea : EActionT type k):
    forall o calls retl expr1 v' (bexpr1 bexpr2 : Bool @# type),
      evalExpr bexpr1  = evalExpr bexpr2  ->
      SemCompActionT (EcompileAction o ea bexpr1 expr1) v' calls retl ->
      SemCompActionT (EcompileAction o ea bexpr2 expr1) v' calls retl.
  Proof.
    induction ea; intros; simpl in *; eauto.
    - inv H1; EqDep_subst; [econstructor 1| econstructor 2]; eauto.
    - inv H1; EqDep_subst; econstructor; eauto.
    - inv H1; EqDep_subst; econstructor; eauto.
    - inv H1; EqDep_subst; econstructor; eauto.
    - inv H1; EqDep_subst; econstructor; eauto.
    - inv H0; simpl in *; EqDep_subst.
      econstructor; eauto.
      rewrite (unifyWO val_a) in HSemCompActionT_a.
      inv HSemCompActionT_a; EqDep_subst.
      econstructor; eauto.
      inv HRegMapWf; destruct regMap_a.
      split; auto.
      destruct (bool_dec (evalExpr bexpr2) true).
      inv H0; EqDep_subst.
      + econstructor 2; eauto.
      + congruence.
      + inv H0; EqDep_subst.
        * congruence.
        * econstructor 3; eauto.
    - inv H1; EqDep_subst.
      inv HSemCompActionT_cont; EqDep_subst.
      inv HSemCompActionT_cont0; simpl in *; EqDep_subst.
      econstructor.
      + eapply IHea1 with (bexpr1 := (bexpr1 && e)%kami_expr); eauto.
        simpl; rewrite H0; auto.
      + reflexivity.
      + econstructor.
        * eapply IHea2 with (bexpr1 := (bexpr1 && !e)%kami_expr);eauto.
          simpl; rewrite H0; auto.
        * reflexivity.
        * econstructor; simpl.
          eapply H; eauto.
    - inv H0; EqDep_subst.
      econstructor; eauto.
    - inv H1; EqDep_subst.
      econstructor; eauto.
    - inv H0; EqDep_subst.
      econstructor; eauto.
      + unfold WfRegMapExpr in *; dest; split; auto.
        inv H0; EqDep_subst.
        * econstructor; rewrite H in *; eauto.
        * econstructor 3; rewrite H in *; eauto.
      + econstructor 11; eauto.
        unfold WfRegMapExpr in *; dest; split; auto.
        inv H0; EqDep_subst.
        * econstructor; rewrite H in *; eauto.
        * econstructor 3; rewrite H in *; eauto.
    - inv H0; EqDep_subst.
      econstructor; eauto.
      + unfold WfRegMapExpr in *; dest; split; auto.
        inv H0; EqDep_subst.
        * econstructor; rewrite H in *; eauto.
        * econstructor 3; rewrite H in *; eauto.
      + econstructor 13; eauto.
        unfold WfRegMapExpr in *; dest; split; auto.
        inv H0; EqDep_subst.
        * econstructor; rewrite H in *; eauto.
        * econstructor 3; rewrite H in *; eauto.
    - inv H1; EqDep_subst; [econstructor | econstructor 15]; eauto.
  Qed.
  
  Lemma SemCompActionEquivBexpr (k : Kind) (a : ActionT type k):
    forall o calls retl expr1 v' (bexpr1 bexpr2 : Bool @# type),
      evalExpr bexpr1  = evalExpr bexpr2  ->
      SemCompActionT (compileAction o a bexpr1 expr1) v' calls retl ->
      SemCompActionT (compileAction o a bexpr2 expr1) v' calls retl.
  Proof.
    induction a; intros; simpl in *; eauto.
    - inv H1; EqDep_subst; [econstructor 1| econstructor 2]; eauto.
    - inv H1; EqDep_subst; econstructor; eauto.
    - inv H1; EqDep_subst; econstructor; eauto.
    - inv H1; EqDep_subst; econstructor; eauto.
    - inv H1; EqDep_subst; econstructor; eauto.
    - inv H0; simpl in *; EqDep_subst.
      econstructor; eauto.
      rewrite (unifyWO val_a) in HSemCompActionT_a.
      inv HSemCompActionT_a; EqDep_subst.
      econstructor; eauto.
      inv HRegMapWf; destruct regMap_a.
      split; auto.
      destruct (bool_dec (evalExpr bexpr2) true).
      inv H0; EqDep_subst.
      + econstructor 2; eauto.
      + congruence.
      + inv H0; EqDep_subst.
        * congruence.
        * econstructor 3; eauto.
    - inv H1; EqDep_subst.
      inv HSemCompActionT_cont; EqDep_subst.
      inv HSemCompActionT_cont0; simpl in *; EqDep_subst.
      econstructor.
      + eapply IHa1 with (bexpr1 := (bexpr1 && e)%kami_expr); eauto.
        simpl; rewrite H0; auto.
      + reflexivity.
      + econstructor.
        * eapply IHa2 with (bexpr1 := (bexpr1 && !e)%kami_expr);eauto.
          simpl; rewrite H0; auto.
        * reflexivity.
        * econstructor; simpl.
          eapply H; eauto.
    - inv H0; EqDep_subst.
      econstructor; eauto.
  Qed.

  Lemma EpredFalse_UpdsNil k ea :
    forall (bexpr: Bool @# type) o u regMap1 regMap2 calls val
           (HNbexpr : evalExpr bexpr = false) rexpr (HRegMap : SemRegMapExpr rexpr regMap1),
      @SemCompActionT k (EcompileAction (o, u) ea bexpr rexpr) regMap2 calls val ->
      regMap1 = regMap2 /\ calls = nil.
  Proof.
    induction ea; intros.
    - inv H0; EqDep_subst;[congruence|eauto].
    - inv H0; EqDep_subst; eauto.
    - inv H0; EqDep_subst; eauto.
      specialize (IHea _ _ _ _ _ _ _ HNbexpr _ HRegMap HSemCompActionT_a); dest.
      rewrite H0 in HRegMap.
      specialize (H _ _ _ _ _ _ _ _ HNbexpr _ (SemVarRegMap _) HSemCompActionT_cont); dest.
      split; subst; auto.
    - inv H0; EqDep_subst; eauto.
    - inv H0; EqDep_subst; eauto.
    - inv H; simpl in *; EqDep_subst; eauto.
      rewrite (unifyWO val_a) in HSemCompActionT_a.
      inv HSemCompActionT_a; EqDep_subst.
      inv HRegMapWf; inv H; EqDep_subst;[congruence|].
      specialize (IHea _ _ _ _ _ _ _ HNbexpr _ (SemVarRegMap _) HSemCompActionT_cont); dest.
      rewrite (SemRegExprVals HRegMap HSemRegMap); auto.
    - simpl in *; inv H0; EqDep_subst.
      inv HSemCompActionT_cont; EqDep_subst.
      inv HSemCompActionT_cont0; EqDep_subst.
      apply Eqdep.EqdepTheory.inj_pair2 in H4; subst; simpl in *.
      assert (forall b, (evalExpr (bexpr && b)%kami_expr = false)).
      { intros; simpl; rewrite HNbexpr; auto. }
      specialize (IHea1 _ _ _ _ _ _ _ (H0 e) _ HRegMap HSemCompActionT_a); dest.
      specialize (IHea2 _ _ _ _ _ _ _ (H0 (!e)%kami_expr) _ (SemVarRegMap _) HSemCompActionT_a0); dest.
      specialize (H _ _ _ _ _ _ _ _ HNbexpr _ (SemVarRegMap _) HSemCompActionT); dest.
      subst; auto.
    - inv H; EqDep_subst; eauto.
    - inv H; EqDep_subst.
      inv HRegMapWf.
      rewrite (SemRegExprVals HRegMap H); auto.
    - inv H0; EqDep_subst; eauto.
    - inv H; EqDep_subst; eauto; unfold WfRegMapExpr in *; dest;
        inv H; EqDep_subst; [rewrite HNbexpr in *; discriminate| | rewrite HNbexpr in *; discriminate | ];
          specialize (IHea _ _ _ _ _ _ _ HNbexpr _ (SemVarRegMap _) HSemCompActionT); dest; subst;
            rewrite (SemRegExprVals HSemRegMap HRegMap); split; auto.
    - inv H; EqDep_subst; eauto; unfold WfRegMapExpr in *; dest;
        inv H; EqDep_subst; [rewrite HNbexpr in *; discriminate| | rewrite HNbexpr in *; discriminate | ];
          specialize (IHea _ _ _ _ _ _ _ HNbexpr _ (SemVarRegMap _) HSemCompActionT); dest; subst;
            rewrite (SemRegExprVals HSemRegMap HRegMap); split; auto.
    - inv H0; EqDep_subst; eauto; unfold WfRegMapExpr in *; dest; inv H; EqDep_subst.
  Qed.

  Lemma predFalse_UpdsNil k a:
    forall (bexpr: Bool @# type) o u regMap1 regMap2 calls val
           (HNbexpr : evalExpr bexpr = false) rexpr (HRegMap : SemRegMapExpr rexpr regMap1),
      @SemCompActionT k (compileAction (o, u) a bexpr rexpr) regMap2 calls val ->
      regMap1 = regMap2 /\ calls = nil.
  Proof.
    induction a; intros.
    - inv H0; EqDep_subst;[congruence|eauto].
    - inv H0; EqDep_subst; eauto.
    - inv H0; EqDep_subst; eauto.
      specialize (IHa _ _ _ _ _ _ _ HNbexpr _ HRegMap HSemCompActionT_a); dest.
      rewrite H0 in HRegMap.
      specialize (H _ _ _ _ _ _ _ _ HNbexpr _ (SemVarRegMap _) HSemCompActionT_cont); dest.
      split; subst; auto.
    - inv H0; EqDep_subst; eauto.
    - inv H0; EqDep_subst; eauto.
    - inv H; simpl in *; EqDep_subst; eauto.
      rewrite (unifyWO val_a) in HSemCompActionT_a.
      inv HSemCompActionT_a; EqDep_subst.
      inv HRegMapWf; inv H; EqDep_subst;[congruence|].
      specialize (IHa _ _ _ _ _ _ _ HNbexpr _ (SemVarRegMap _) HSemCompActionT_cont); dest.
      rewrite (SemRegExprVals HRegMap HSemRegMap); auto.
    - simpl in *; inv H0; EqDep_subst.
      inv HSemCompActionT_cont; EqDep_subst.
      inv HSemCompActionT_cont0; EqDep_subst.
      apply Eqdep.EqdepTheory.inj_pair2 in H4; subst; simpl in *.
      assert (forall b, (evalExpr (bexpr && b)%kami_expr = false)).
      { intros; simpl; rewrite HNbexpr; auto. }
      specialize (IHa1 _ _ _ _ _ _ _ (H0 e) _ HRegMap HSemCompActionT_a); dest.
      specialize (IHa2 _ _ _ _ _ _ _ (H0 (!e)%kami_expr) _ (SemVarRegMap _) HSemCompActionT_a0); dest.
      specialize (H _ _ _ _ _ _ _ _ HNbexpr _ (SemVarRegMap _) HSemCompActionT); dest.
      subst; auto.
    - inv H; EqDep_subst; eauto.
    - inv H; EqDep_subst.
      inv HRegMapWf.
      rewrite (SemRegExprVals HRegMap H); auto.
  Qed.

  

  Lemma ESameOldAction (k : Kind) (ea : EActionT type k) :
    forall oInit uInit writeMap old upds wOld wUpds calls retl bexpr
           (HSemRegMap : SemRegMapExpr writeMap (wOld, wUpds)),
      @SemCompActionT k (EcompileAction (oInit, uInit) ea bexpr writeMap) (old, upds) calls retl ->
      wOld = old.
  Proof.
    induction ea; intros; simpl in *.
    - inv H0; EqDep_subst; simpl in *; eapply H; eauto.
    - inv H0; EqDep_subst; simpl in *.
      eapply H; eauto.
    - inv H0; EqDep_subst; simpl in *.
      destruct regMap_a.
      specialize (H _ _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT_cont); subst.
      specialize (IHea _ _ _ _ _ _ _ _ _ _ HSemRegMap HSemCompActionT_a); assumption.
    - inv H0; EqDep_subst; simpl in *.
      eapply H; eauto.
    - inv H0; EqDep_subst; simpl in *.
      eapply H; eauto.
    - inv H; simpl in *; EqDep_subst.
      rewrite (unifyWO val_a) in HSemCompActionT_a.
      inv HSemCompActionT_a; EqDep_subst.
      destruct regMap_a; unfold WfRegMapExpr in *; dest.
      inv H; EqDep_subst.
      + specialize (IHea _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT_cont).
        specialize (SemRegExprVals HSemRegMap HSemRegMap0) as TMP; inv TMP.
        reflexivity.
      + specialize (IHea  _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT_cont).
        specialize (SemRegExprVals HSemRegMap HSemRegMap0) as TMP; inv TMP.
        reflexivity.
    - inv H0; EqDep_subst; simpl in *.
      inv HSemCompActionT_cont; EqDep_subst.
      inv HSemCompActionT_cont0; simpl in *; EqDep_subst.
      destruct regMap_a, regMap_a0.
      specialize (H _ _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT).
      simpl in *.
      specialize (IHea1 _ _ _ _ _ _ _ _ _ _ HSemRegMap HSemCompActionT_a).
      specialize (IHea2 _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT_a0).
      subst; reflexivity.
    - inv H; EqDep_subst; simpl in *.
      eapply IHea; eauto.
    - inv H; EqDep_subst.
      unfold WfRegMapExpr in *; dest.
      specialize (SemRegExprVals H HSemRegMap) as TMP; inv TMP.
      reflexivity.
    - inv H0; EqDep_subst.
      eapply H; eauto.
    - inv H; EqDep_subst; unfold WfRegMapExpr in *; destruct regMapVal; dest;
        specialize (IHea _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT); subst;
          inv H; EqDep_subst; specialize (SemRegExprVals HSemRegMap HSemRegMap0) as TMP; inv TMP; reflexivity.
    - inv H; EqDep_subst; unfold WfRegMapExpr in *; destruct regMapVal; dest;
        specialize (IHea _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT); subst;
          inv H; EqDep_subst; specialize (SemRegExprVals HSemRegMap HSemRegMap0) as TMP; inv TMP; reflexivity.
    - inv H0; EqDep_subst; eapply H; eauto.
  Qed.

  Lemma EEquivActions k ea:
    forall writeMap o old upds oInit uInit
      (HoInitNoDups : NoDup (map fst oInit))
      (HuInitNoDups : forall u, In u uInit -> NoDup (map fst u))
      (HPriorityUpds : PriorityUpds oInit uInit o)
      (HConsistent : getKindAttr o = getKindAttr old)
      (WfMap : WfRegMapExpr writeMap (old, upds)),
    forall calls retl upds',
      @SemCompActionT k (EcompileAction (oInit, uInit) ea (Const type true) writeMap) upds' calls retl ->
      (forall u, In u (snd upds') -> NoDup (map fst u) /\ SubList (getKindAttr u) (getKindAttr old)) /\
      exists uml,
        upds' = (old, match (UpdOrMeths_RegsT uml) with
                      |nil => upds
                      |_ :: _ => (hd nil upds ++ (UpdOrMeths_RegsT uml)) :: tl upds
                      end) /\
        calls = (UpdOrMeths_MethsT uml) /\
        ESemAction o ea uml retl.
    Proof.
    induction ea; subst; intros; simpl in *.
    - inv H0; EqDep_subst;[|discriminate].
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists (Meth (meth, existT SignT s (evalExpr e, ret))::x); repeat split; simpl; subst; auto.
      econstructor; eauto.
    - inv H0; EqDep_subst.
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists x; repeat split; auto.
      econstructor; eauto.
    - inv H0; EqDep_subst.
      specialize (IHea _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT_a); dest.
      assert (WfRegMapExpr (VarRegMap type regMap_a) regMap_a) as WfMap0.
      { unfold WfRegMapExpr; split;[econstructor|].
        destruct regMap_a; inv H1; intros.
        apply (H0 _ H1).
      }
      rewrite H1 in *.
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap0 _ _ _ HSemCompActionT_cont); dest.
      split; auto.
      exists (x++x0); rewrite UpdOrMeths_RegsT_app, UpdOrMeths_MethsT_app; repeat split; auto.
      + destruct (UpdOrMeths_RegsT x0); simpl in *; auto.
        * rewrite app_nil_r; assumption.
        * destruct (UpdOrMeths_RegsT x); simpl in *; auto.
          rewrite app_comm_cons, app_assoc; assumption.
      + subst; auto.
      + econstructor; eauto.
        rewrite H4 in H; simpl in *.
        clear - H.
        destruct (UpdOrMeths_RegsT x0), (UpdOrMeths_RegsT x); eauto using DisjKey_nil_r, DisjKey_nil_l; simpl in *.
        specialize (H _ (or_introl _ eq_refl)); simpl in *; dest.
        repeat rewrite map_app in H.
        intro k.
        destruct (In_dec string_dec k (map fst (p0::r0))); auto.
        right; intro.
        destruct (NoDup_app_Disj string_dec _ _ H k); auto.
        apply H2; rewrite in_app_iff; right; auto.
    - inv H0; EqDep_subst.
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists x; repeat split; auto.
      econstructor; eauto.
    - inv H0; EqDep_subst.
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists x.
      repeat split; simpl; auto.
      econstructor; eauto.
      inv HReadMap.
      apply (PriorityUpds_Equiv HoInitNoDups HuInitNoDups HUpdatedRegs HPriorityUpds); auto.
    - inv H; simpl in *; EqDep_subst.
      rewrite (unifyWO val_a) in HSemCompActionT_a.
      inv HSemCompActionT_a; EqDep_subst.
      destruct HRegMapWf, WfMap, regMap_a.
      inv H;[|discriminate]; EqDep_subst.
      specialize (SemRegExprVals H1 HSemRegMap) as P0; inv P0.
      assert (WfRegMapExpr (VarRegMap type (r0, (hd nil upds0 ++ (r, existT (fullType type) k (evalExpr e)) :: nil) :: tl upds0))
                           (r0, (hd nil upds0 ++ (r, existT (fullType type) k (evalExpr e)) :: nil) :: tl upds0)) as WfMap0.
      { split; auto. constructor. }
      specialize (IHea _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap0 _ _ _ HSemCompActionT_cont);
        dest; simpl in *; split; auto.
      exists ((Upd (r, existT (fullType type) k (evalExpr e))):: x); repeat split; auto.
      + simpl; destruct (UpdOrMeths_RegsT x); simpl in *; auto.
        rewrite <- app_assoc in H3. rewrite <-app_comm_cons in H3.
        simpl in H3; auto.
      + simpl; econstructor; eauto.
        * rewrite H3 in H.
          destruct (UpdOrMeths_RegsT x); simpl in *; rewrite HConsistent; eapply H; simpl; eauto;
            repeat rewrite map_app, in_app_iff; [right | left]; simpl; auto.
        * repeat intro.
          rewrite H3 in H.
          destruct (UpdOrMeths_RegsT x); simpl in *; auto.
          destruct H7; subst; simpl in *; specialize (H _ (or_introl eq_refl)); dest; repeat rewrite map_app, NoDup_app_iff in H; simpl in *; dest.
          -- apply (H7 r); clear.
             rewrite in_app_iff; simpl; right; left; reflexivity.
             left; reflexivity.
          -- apply (H8 r); clear - H7.
             ++ rewrite in_app_iff; right; left; reflexivity.
             ++ right; rewrite in_map_iff; exists (r, v); split; auto.
    - inv H0; EqDep_subst.
      inv HSemCompActionT_cont; EqDep_subst.
      inv HSemCompActionT_cont0; EqDep_subst.
      remember (evalExpr e) as P0.
      apply Eqdep.EqdepTheory.inj_pair2 in H4.
      rewrite H4 in *.
      clear H4; simpl in *.
      assert (forall bexpr, (evalExpr (Const type true && bexpr)%kami_expr = evalExpr bexpr)) as P1.
      { intro; simpl; auto. }
      specialize (SemCompActionEEquivBexpr _ _ _ _ _ (P1 e) HSemCompActionT_a) as P2.
      specialize (SemCompActionEEquivBexpr _ _ _ _ _ (P1 (!e)%kami_expr) HSemCompActionT_a0) as P3.
      destruct P0; simpl in *.
      + assert (evalExpr e = evalExpr (Const type true)) as P4; simpl; auto.
        assert (evalExpr (!e)%kami_expr = false) as P5.
        { simpl; rewrite <- HeqP0; auto. }
        specialize (SemCompActionEEquivBexpr _ _ _ _ _ P4 P2) as P6.
        specialize (IHea1 _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ P6); dest.
        rewrite <- HeqP0 in HSemCompActionT.
        destruct (EpredFalse_UpdsNil _ _ _ _ P5 (SemVarRegMap regMap_a) P3).
        assert (WfRegMapExpr (VarRegMap type regMap_a0) regMap_a0) as P7.
        { unfold WfRegMapExpr; split; [constructor|]. subst; eauto. }
        rewrite <- H4 in P7 at 2.
        rewrite H1 in P7.
        specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent P7 _ _ _ HSemCompActionT); dest.
        split; auto.
        exists (x ++ x0); rewrite UpdOrMeths_RegsT_app, UpdOrMeths_MethsT_app; repeat split; auto.
        * destruct (UpdOrMeths_RegsT x0); simpl; auto.
          -- rewrite app_nil_r; auto.
          --  destruct (UpdOrMeths_RegsT x); simpl in *; auto.
              rewrite app_comm_cons, app_assoc; assumption.
        * subst; reflexivity.
        * econstructor; eauto.
          rewrite H6 in H; destruct (UpdOrMeths_RegsT x), (UpdOrMeths_RegsT x0); intro; simpl in *; auto.
          clear - H.
          specialize (H _ (or_introl _ (eq_refl))); dest.
          rewrite map_app in H.
          destruct (NoDup_app_Disj string_dec _ _ H k0); auto.
          left; intro; apply H1.
          rewrite map_app, in_app_iff; auto.
      + assert (evalExpr (!e)%kami_expr = evalExpr (Const type true)) as P4.
        { simpl; rewrite <- HeqP0; auto. }
        specialize (SemCompActionEEquivBexpr _ _ _ _ _ P4 P3) as P6.
        remember WfMap as WfMap0.
        inv WfMap0.
        destruct (EpredFalse_UpdsNil _ _ _ _ (eq_sym HeqP0) H0 P2).
        assert (WfRegMapExpr (VarRegMap type regMap_a) (old, upds)) as WfMap0.
        { rewrite <- H2.
          clear - WfMap.
          unfold WfRegMapExpr in *; dest; repeat split;[constructor| |]; eapply H0; eauto.
        }
        specialize (IHea2 _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap0 _ _ _ P6); dest.
        rewrite <- HeqP0 in HSemCompActionT.
        assert (WfRegMapExpr (VarRegMap type regMap_a0) regMap_a0) as P7.
        { unfold WfRegMapExpr; split; [constructor|]. subst; eauto. }
        rewrite  H5 in P7 at 2.
        specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent P7 _ _ _ HSemCompActionT); dest.
        split; auto.
        exists (x ++ x0); rewrite UpdOrMeths_RegsT_app, UpdOrMeths_MethsT_app; repeat split; auto.
        * destruct (UpdOrMeths_RegsT x0); simpl; auto.
          -- rewrite app_nil_r; auto.
          --  destruct (UpdOrMeths_RegsT x); simpl in *; auto.
              rewrite app_comm_cons, app_assoc; assumption.
        * subst; reflexivity.
        * econstructor 8; eauto.
          rewrite H8 in H; destruct (UpdOrMeths_RegsT x), (UpdOrMeths_RegsT x0); intro; simpl in *; auto.
          clear - H.
          specialize (H _ (or_introl _ (eq_refl))); dest.
          rewrite map_app in H.
          destruct (NoDup_app_Disj string_dec _ _ H k0); auto.
          left; intro; apply H1.
          rewrite map_app, in_app_iff; auto.
    - inv H; EqDep_subst.
      specialize (IHea _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists x.
      repeat split; auto.
      econstructor; eauto.
    - inv H; EqDep_subst.
      inv WfMap; inv HRegMapWf.
      specialize (SemRegExprVals H H1) as TMP; subst; simpl in *.
      split; auto.
      exists nil.
      repeat split; auto.
      constructor; auto.
    - inv H0; EqDep_subst.
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest.
      split; auto.
      exists x.
      repeat split; auto.
      econstructor; eauto.
      inv HReadMap.
      apply (PriorityUpds_Equiv HoInitNoDups HuInitNoDups HUpdatedRegs HPriorityUpds); auto.
    - inv H; EqDep_subst; destruct regMapVal; simpl in *.
      + unfold WfRegMapExpr in *; dest.
        inv H; EqDep_subst; [|discriminate].
        specialize (SemRegExprVals H1 HSemRegMap) as TMP; inv TMP.
        assert (WfRegMapExpr (VarRegMap type
                                        (r,
                                         (hd [] upds0 ++
                                             [(dataArray,
                                               existT (fullType type) (SyntaxKind (Array idxNum Data))
                                                      (evalExpr
                                                         (fold_left
                                                            (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                                               (IF ReadArrayConst mask0 i then newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))
                                                                                                                     <- ReadArrayConst val i] else newArr)%kami_expr)
                                                            (getFins num) (Var type (SyntaxKind (Array idxNum Data)) regVal))))]) :: tl upds0))
                             (r,
                              (hd [] upds0 ++
                                  [(dataArray,
                                    existT (fullType type) (SyntaxKind (Array idxNum Data))
                                           (evalExpr
                                              (fold_left
                                                 (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                                    (IF ReadArrayConst mask0 i then newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))
                                                                                                          <- ReadArrayConst val i] else newArr)%kami_expr)
                                                 (getFins num) (Var type (SyntaxKind (Array idxNum Data)) regVal))))]) :: tl upds0)) as P0.
        { unfold WfRegMapExpr in *; dest; split; auto; constructor. }
        specialize (IHea _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent P0 _ _ _ HSemCompActionT); dest; split; auto.
        exists (Upd (dataArray,
                     existT (fullType type) (SyntaxKind (Array idxNum Data))
                            (evalExpr
                               (fold_left
                                  (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                     (IF ReadArrayConst mask0 i then newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))
                                                                                           <- ReadArrayConst val i] else newArr)%kami_expr)
                                  (getFins num) (Var type (SyntaxKind (Array idxNum Data)) regVal))))::x).
        repeat split; auto.
        * simpl in *.
          clear - H3.
          destruct (UpdOrMeths_RegsT x); auto.
          rewrite <- app_assoc in H3; simpl in *; assumption.
        * econstructor; eauto.
          -- inv HReadMap.
             apply (PriorityUpds_Equiv HoInitNoDups HuInitNoDups HUpdatedRegs HPriorityUpds); auto.
          -- rewrite H3 in H.
             clear - H.
             destruct (UpdOrMeths_RegsT x); repeat intro; auto.
             specialize (H _ (or_introl eq_refl)).
             simpl in H; repeat rewrite map_app in H; simpl in *.
             rewrite NoDup_app_iff in H; dest; apply (H3 dataArray); destruct H0; subst; simpl; auto.
             ++ rewrite in_app_iff; right; simpl; left; auto.
             ++ rewrite in_app_iff; right; simpl; left; auto.
             ++ right; rewrite in_map_iff; exists (dataArray, v); auto.
      + unfold WfRegMapExpr in *; dest.
        inv H; EqDep_subst; [|discriminate].
        specialize (SemRegExprVals H1 HSemRegMap) as TMP; inv TMP.
        assert (WfRegMapExpr (VarRegMap type
                                        (r,
                                         (hd [] upds0 ++
                                             [(dataArray,
                                               existT (fullType type) (SyntaxKind (Array idxNum Data))
                                                      (evalExpr
                                                         (fold_left
                                                            (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                                               (newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <- ReadArrayConst val i])%kami_expr) (getFins num)
                                                            (Var type (SyntaxKind (Array idxNum Data)) regVal))))]) :: tl upds0))
                             (r,
                              (hd [] upds0 ++
                                  [(dataArray,
                                    existT (fullType type) (SyntaxKind (Array idxNum Data))
                                           (evalExpr
                                              (fold_left
                                                 (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                                    (newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))
                                                                           <- ReadArrayConst val i])%kami_expr) (getFins num)
                                                 (Var type (SyntaxKind (Array idxNum Data)) regVal))))]) :: tl upds0)) as P0.
        { unfold WfRegMapExpr in *; dest; split; auto; constructor. }
        specialize (IHea _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent P0 _ _ _ HSemCompActionT); dest; split; auto.
        exists (Upd (dataArray,
                     existT (fullType type) (SyntaxKind (Array idxNum Data))
                            (evalExpr
                               (fold_left
                                  (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                     (newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <- ReadArrayConst val i])%kami_expr) (getFins num)
                                  (Var type (SyntaxKind (Array idxNum Data)) regVal))))::x).
        repeat split; auto.
        * simpl in *.
          clear - H3.
          destruct (UpdOrMeths_RegsT x); auto.
          rewrite <- app_assoc in H3; simpl in *; assumption.
        * econstructor 13; eauto.
          -- inv HReadMap.
             apply (PriorityUpds_Equiv HoInitNoDups HuInitNoDups HUpdatedRegs HPriorityUpds); auto.
          -- rewrite H3 in H.
             clear - H.
             destruct (UpdOrMeths_RegsT x); repeat intro; auto.
             specialize (H _ (or_introl eq_refl)).
             simpl in H; repeat rewrite map_app in H; simpl in *.
             rewrite NoDup_app_iff in H; dest; apply (H3 dataArray); destruct H0; subst; simpl; auto.
             ++ rewrite in_app_iff; right; simpl; left; auto.
             ++ rewrite in_app_iff; right; simpl; left; auto.
             ++ right; rewrite in_map_iff; exists (dataArray, v); auto.
    - inv H; EqDep_subst.
      + unfold WfRegMapExpr in *; dest.
        inv H; EqDep_subst; [|discriminate].
        specialize (SemRegExprVals H1 HSemRegMap) as TMP; inv TMP.
        assert (WfRegMapExpr (VarRegMap type
                                        (old0,
                                         (hd [] upds0 ++
                                             [(readReg,
                                               existT (fullType type) (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr (Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx))))])
                                           :: tl upds0))
                             (old0,
                              (hd [] upds0 ++
                                  [(readReg,
                                    existT (fullType type) (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr (Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx))))])
                                :: tl upds0)) as P0.
        { unfold WfRegMapExpr in *; dest; split; auto; constructor. }
        specialize (IHea _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent P0 _ _ _ HSemCompActionT); dest; split; auto.
        exists (Upd (readReg, existT (fullType type) (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr (Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx))))::x).
        repeat split; auto.
        * simpl in *.
          clear - H3.
          destruct (UpdOrMeths_RegsT x); auto.
          rewrite <- app_assoc in H3; simpl in *; assumption.
        * econstructor; eauto.
          -- rewrite H3 in H.
             rewrite HConsistent.
             clear - H.
             simpl in *.
             destruct (UpdOrMeths_RegsT x); simpl in *; specialize (H _ (or_introl eq_refl)); dest;
               apply H0; repeat rewrite map_app, in_app_iff; [right| left; right]; left; auto.
          -- rewrite H3 in H.
             clear - H.
             simpl in *.
             destruct (UpdOrMeths_RegsT x); simpl in *; specialize (H _ (or_introl eq_refl)); dest; repeat intro; auto.
             repeat rewrite map_app in H; simpl in *.
             rewrite NoDup_app_iff in H; dest.
             apply (H3 readReg); destruct H1; subst; simpl; auto.
             ++ rewrite in_app_iff; right; simpl; left; auto.
             ++ rewrite in_app_iff; right; simpl; left; auto.
             ++ right; rewrite in_map_iff; exists (readReg, v); auto.
      + unfold WfRegMapExpr in *; dest.
        inv H; EqDep_subst; [|discriminate].
        specialize (SemRegExprVals H1 HSemRegMap) as TMP; inv TMP.
        assert (WfRegMapExpr (VarRegMap type
                                        (old0,
                                         (hd [] upds0 ++
                                             [(readReg,
                                               existT (fullType type) (SyntaxKind (Array num Data))
                                                      (evalExpr
                                                         (BuildArray
                                                            (fun i : Fin.t num =>
                                                               (Var type (SyntaxKind (Array idxNum Data)) regV @[
                                                                      Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx) + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))])%kami_expr))))])
                                           :: tl upds0))
                             (old0,
                              (hd [] upds0 ++
                                  [(readReg,
                                    existT (fullType type) (SyntaxKind (Array num Data))
                                           (evalExpr
                                              (BuildArray
                                                 (fun i : Fin.t num =>
                                                    (Var type (SyntaxKind (Array idxNum Data)) regV @[
                                                           Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx) + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))])%kami_expr))))])
                                :: tl upds0)) as P0.
        { unfold WfRegMapExpr in *; dest; split; auto; constructor. }
        specialize (IHea _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent P0 _ _ _ HSemCompActionT); dest; split; auto.
        exists (Upd (readReg, existT (fullType type) (SyntaxKind (Array num Data))
                                    (evalExpr
                                       (BuildArray
                                          (fun i : Fin.t num =>
                                             (Var type (SyntaxKind (Array idxNum Data)) regV @[
                                                    Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx) + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))])%kami_expr))))::x).
        repeat split; auto.
        * simpl in *.
          clear - H3.
          destruct (UpdOrMeths_RegsT x); auto.
          rewrite <- app_assoc in H3; simpl in *; assumption.
        * econstructor 15; eauto.
          -- rewrite H3 in H.
             rewrite HConsistent.
             clear - H.
             simpl in *.
             destruct (UpdOrMeths_RegsT x); simpl in *; specialize (H _ (or_introl eq_refl)); dest;
               apply H0; repeat rewrite map_app, in_app_iff; [right| left; right]; left; auto.
          -- inv HReadMap.
             apply (PriorityUpds_Equiv HoInitNoDups HuInitNoDups HUpdatedRegs HPriorityUpds); auto.
          -- rewrite H3 in H.
             clear - H.
             simpl in *.
             destruct (UpdOrMeths_RegsT x); simpl in *; specialize (H _ (or_introl eq_refl)); dest; repeat intro; auto.
             repeat rewrite map_app in H; simpl in *.
             rewrite NoDup_app_iff in H; dest.
             apply (H3 readReg); destruct H1; subst; simpl; auto.
             ++ rewrite in_app_iff; right; simpl; left; auto.
             ++ rewrite in_app_iff; right; simpl; left; auto.
             ++ right; rewrite in_map_iff; exists (readReg, v); auto.
    - inv H0; EqDep_subst.
      + specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest.
        split; auto.
        exists x.
        repeat split; auto.
        econstructor; eauto.
        * inv HReadMap.
          apply (PriorityUpds_Equiv HoInitNoDups HuInitNoDups HUpdatedRegs HPriorityUpds); auto.
        * inv HReadMap.
          apply (PriorityUpds_Equiv HoInitNoDups HuInitNoDups HUpdatedRegs HPriorityUpds); auto.
      + specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest.
        split; auto.
        exists x.
        repeat split; auto.
        econstructor 17; eauto.
        * inv HReadMap.
          apply (PriorityUpds_Equiv HoInitNoDups HuInitNoDups HUpdatedRegs HPriorityUpds); auto.
    Qed.


    Lemma ESemAction_NoDup_Upds k (ea : EActionT type k) :
      forall o uml retl,
        ESemAction o ea uml retl ->
        NoDup (map fst (UpdOrMeths_RegsT uml)).
    Proof.
      induction ea; intros.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H0; EqDep_subst; simpl; eauto.
        rewrite UpdOrMeths_RegsT_app, map_app, NoDup_app_iff; repeat split; repeat intro; eauto.
          + specialize (HDisjRegs a); firstorder fail.
          + specialize (HDisjRegs a); firstorder fail.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H; EqDep_subst; simpl.
        constructor; eauto.
        intro; rewrite in_map_iff in H; dest; destruct x; subst; simpl in *.
        eapply HDisjRegs; eauto.
      - inv H0; EqDep_subst; rewrite UpdOrMeths_RegsT_app, map_app, NoDup_app_iff;
        repeat split; repeat intro; eauto; specialize (HDisjRegs a).
        repeat (destruct HDisjRegs; contradiction).
        repeat (destruct HDisjRegs; contradiction).
        repeat (destruct HDisjRegs; contradiction).
        repeat (destruct HDisjRegs; contradiction).
      - inv H; EqDep_subst; simpl; eauto.
      - inv H; EqDep_subst; simpl; constructor.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H; EqDep_subst; simpl; constructor; eauto; intro;
          rewrite in_map_iff in H; dest; destruct x; subst; simpl in *; eapply HDisjRegs; eauto.
      - inv H; EqDep_subst; simpl; constructor; eauto; intro;
          rewrite in_map_iff in H; dest; destruct x; subst; simpl in *; eapply HDisjRegs; eauto.
      - inv H0; EqDep_subst; eauto.
    Qed.


    Lemma ESemAction_SubList_Upds k (ea : EActionT type k) :
      forall o uml retl,
        ESemAction o ea uml retl ->
        SubList (getKindAttr (UpdOrMeths_RegsT uml)) (getKindAttr o).
    Proof.
      induction ea; intros.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H0; EqDep_subst; simpl; eauto.
        rewrite UpdOrMeths_RegsT_app, map_app, SubList_app_l_iff; split; eauto.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H; EqDep_subst; simpl.
        repeat intro; inv H; auto.
        eapply IHea; eauto.
      - inv H0; EqDep_subst; simpl; eauto;
          rewrite UpdOrMeths_RegsT_app, map_app, SubList_app_l_iff;
          split; eauto.
      - inv H; EqDep_subst; simpl; eauto.
      - inv H; EqDep_subst; simpl; repeat intro; contradiction.
      - inv H0; EqDep_subst; simpl; eauto.
      - inv H; EqDep_subst; simpl; eauto; repeat intro; inv H.
        + rewrite in_map_iff;
            exists (dataArray, existT (fullType type) (SyntaxKind (Array idxNum Data)) regV);
            split; auto.
        + eapply IHea; eauto.
        + rewrite in_map_iff;
            exists (dataArray, existT (fullType type) (SyntaxKind (Array idxNum Data)) regV);
            split; auto.
        + eapply IHea; eauto.
      - inv H; EqDep_subst; simpl; eauto; repeat intro; inv H; auto; eapply IHea; eauto.
      - inv H0; EqDep_subst; eauto.
    Qed.
    
    Lemma Extension_Compiles1  {k : Kind} (a : ActionT type k) :
      forall o calls retl expr v' bexpr,
        SemCompActionT (compileAction o a bexpr expr) v' calls retl ->
        SemCompActionT (EcompileAction o (Action_EAction a) bexpr expr) v' calls retl.
    Proof.
      induction a; simpl; intros; auto.
      - inv H0; EqDep_subst; [econstructor| econstructor 2]; eauto.
      - inv H0; EqDep_subst; econstructor; auto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
        inv HSemCompActionT_cont; EqDep_subst; econstructor; eauto.
        inv HSemCompActionT_cont0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; EqDep_subst; econstructor; eauto.
    Qed.

    Lemma Extension_Compiles2 {k : Kind} (a : ActionT type k) :
      forall o calls retl expr v' bexpr,
        SemCompActionT (EcompileAction o (Action_EAction a) bexpr expr) v' calls retl ->
        SemCompActionT (compileAction o a bexpr expr) v' calls retl.
    Proof.
      induction a; simpl; intros; auto.
      - inv H0; EqDep_subst; [econstructor| econstructor 2]; eauto.
      - inv H0; EqDep_subst; econstructor; auto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
        inv HSemCompActionT_cont; EqDep_subst; econstructor; eauto.
        inv HSemCompActionT_cont0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; EqDep_subst; econstructor; eauto.
    Qed.

    Corollary Extension_Compiles_iff  {k : Kind} (a : ActionT type k) :
      forall o calls retl expr v' bexpr,
        SemCompActionT (EcompileAction o (Action_EAction a) bexpr expr) v' calls retl <->
        SemCompActionT (compileAction o a bexpr expr) v' calls retl.
    Proof.
      split; intro; eauto using Extension_Compiles1, Extension_Compiles2.
    Qed.
    
    Lemma FalseSemCompAction_Ext k (a : ActionT type k) :
      forall writeMap o old upds oInit uInit (bexpr : Bool @# type) m
             (HPriorityUpds : PriorityUpds oInit uInit o)
             (HConsistent : getKindAttr o = getKindAttr old)
             (WfMap : WfRegMapExpr writeMap (old, upds))
             (HRegConsist : getKindAttr o = getKindAttr (getRegisters m))
             (HWf : WfActionT m a)
             (HFalse : evalExpr bexpr = false),
      exists retl,
        @SemCompActionT k (compileAction (oInit, uInit) a bexpr writeMap) (old, upds) nil retl.
    Proof.
      induction a; simpl in *; intros.
      - inv HWf; EqDep_subst.
        specialize (H _ _ _ _ _ _ _ _ _ HPriorityUpds HConsistent WfMap HRegConsist (H2 (evalConstT (getDefaultConst (snd s)))) HFalse); dest.
        exists x.
        econstructor 2; eauto.
      - inv HWf; EqDep_subst.
        specialize (H _ _ _ _ _ _ _ _ _ HPriorityUpds HConsistent WfMap HRegConsist (H2 (evalExpr e)) HFalse); dest.
        exists x.
        econstructor; eauto.
      - inv HWf; EqDep_subst.
        specialize (IHa _ _ _ _ _ _ _ _ HPriorityUpds HConsistent WfMap HRegConsist H3 HFalse); dest.
        assert (WfRegMapExpr (VarRegMap type (old, upds)) (old, upds)) as P0.
        { unfold WfRegMapExpr in *; dest; split; auto. constructor. }
        specialize (H _ _ _ _ _ _ _ _ _ HPriorityUpds HConsistent P0 HRegConsist (H5 x) HFalse); dest.
        exists x0.
        econstructor; eauto.
        reflexivity.
      - inv HWf; EqDep_subst.
        specialize (H _ _ _ _ _ _ _ _ _ HPriorityUpds HConsistent WfMap HRegConsist (H2 (evalConstFullT (getDefaultConstFullKind k))) HFalse); dest.
        exists x.
        econstructor; eauto.
      - inv HWf; EqDep_subst.
        rewrite <- HRegConsist in H5.
        rewrite in_map_iff in H5; dest; inv H0.
        destruct x, s0; simpl in *.
        specialize (H _ _ _ _ _ _ _ _ _ HPriorityUpds HConsistent WfMap HRegConsist (H3 f) HFalse); dest.
        exists x0.
        econstructor; eauto.
        constructor.
      - inv HWf; EqDep_subst.
        assert (WfRegMapExpr (VarRegMap type (old, upds)) (old, upds)) as P0.
        { unfold WfRegMapExpr in *; dest; split; auto; constructor. }
        specialize (IHa _ _ _ _ _ _ _ _ HPriorityUpds HConsistent P0 HRegConsist H2 HFalse); dest.
        exists x.
        econstructor; eauto.
        + econstructor; eauto.
          unfold WfRegMapExpr in *; dest; split; auto.
          * econstructor 3; auto.
        + reflexivity.
      - inv HWf; EqDep_subst.
        remember (evalExpr e) as e_val.
        assert (WfRegMapExpr (VarRegMap type (old, upds)) (old, upds)) as P0.
        { unfold WfRegMapExpr in *; dest; split; auto; constructor. }
        assert (evalExpr (bexpr && e)%kami_expr = false) as P1.
        { simpl; rewrite HFalse, andb_false_l; reflexivity. }
        assert (evalExpr (bexpr && !e)%kami_expr = false) as P2.
        { simpl; rewrite HFalse, andb_false_l; reflexivity. }
        specialize (IHa1 _ _ _ _ _ _ _ _ HPriorityUpds HConsistent WfMap HRegConsist H7 P1); dest.
        specialize (IHa2 _ _ _ _ _ _ _ _ HPriorityUpds HConsistent P0 HRegConsist H8 P2); dest.
        destruct e_val.
        + specialize (H _ _ _ _ _ _ _ _ _ HPriorityUpds HConsistent P0 HRegConsist (H4 x) HFalse); dest.
          exists x1.
          econstructor; eauto; [reflexivity|].
          econstructor; eauto; [reflexivity|].
          econstructor; simpl; rewrite <- Heqe_val.
          assumption.
        + specialize (H _ _ _ _ _ _ _ _ _ HPriorityUpds HConsistent P0 HRegConsist (H4 x0) HFalse); dest.
          exists x1.
          econstructor; eauto; [reflexivity|].
          econstructor; eauto; [reflexivity|].
          econstructor; simpl; rewrite <- Heqe_val.
          assumption.
      - inv HWf; EqDep_subst.
        specialize (IHa _ _ _ _ _ _ _ _ HPriorityUpds HConsistent WfMap HRegConsist H1 HFalse); dest.
        exists x.
        econstructor; eauto.
      - inv HWf; EqDep_subst.
        exists (evalExpr e).
        econstructor; eauto.
    Qed.

    Lemma ActionsEEquivWeak k a:
      forall writeMap o old upds oInit uInit m
             (HoInitNoDups : NoDup (map fst oInit))
             (HuInitNoDups : forall u, In u uInit -> NoDup (map fst u))
             (HPriorityUpds : PriorityUpds oInit uInit o)
             (HConsistent : getKindAttr o = getKindAttr old)
             (WfMap : WfRegMapExpr writeMap (old, upds))
             (HRegConsist : getKindAttr o = getKindAttr (getRegisters m))
             (HWf : WfActionT m a),
      forall uml retl upds' calls,
        upds' = (old, match (UpdOrMeths_RegsT uml) with
                      |nil => upds
                      |_ :: _ => (hd nil upds ++ (UpdOrMeths_RegsT uml)) :: tl upds
                      end) ->
        calls = (UpdOrMeths_MethsT uml) ->
        DisjKey (hd nil upds) (UpdOrMeths_RegsT uml) ->
        ESemAction o (Action_EAction a) uml retl ->
        @SemCompActionT k (EcompileAction (oInit, uInit) (Action_EAction a) (Const type true) writeMap) upds' calls retl.
    Proof.
      induction a; intros; subst; simpl in *.
      - inv H3; inv HWf; EqDep_subst; simpl.
        econstructor; eauto.
      - inv H3; inv HWf; EqDep_subst; simpl.
        econstructor; eauto.
      - specialize (ESemAction_NoDup_Upds H3) as P0;
          specialize (ESemAction_SubList_Upds H3) as P1.
        inv H3; inv HWf; EqDep_subst; rewrite UpdOrMeths_RegsT_app, UpdOrMeths_MethsT_app.
        econstructor; eauto.
        eapply IHa; eauto.
        + intro k0; specialize (H2 k0).
          rewrite UpdOrMeths_RegsT_app, map_app, in_app_iff in H2.
          destruct H2; auto.
        + eapply H; eauto.
          * unfold WfRegMapExpr; repeat split; [constructor| |]; unfold WfRegMapExpr in *; dest;
            rewrite UpdOrMeths_RegsT_app in *; destruct (UpdOrMeths_RegsT newUml); simpl in *.
            -- apply (H3 _ H0).
            -- destruct H0; subst; [rewrite map_app|]; simpl.
               ++ rewrite NoDup_app_iff; repeat split; repeat intro; auto.
                  ** destruct upds; [constructor| simpl; apply (H3 _ (or_introl eq_refl))].
                  ** rewrite map_app in P0; inv P0.
                     rewrite in_app_iff in H6.
                     rewrite NoDup_app_iff in H7; dest.
                     constructor; [firstorder fail|]; auto.
                  ** specialize (H2 a1); simpl in *; rewrite map_app, in_app_iff in H2.
                     clear - H2 H0 H5.
                     firstorder fail.
                  ** specialize (H2 a1); simpl in *; rewrite map_app, in_app_iff in H2.
                     clear - H2 H0 H5.
                     firstorder fail.
               ++ apply H3; clear - H0; destruct upds; simpl in *; auto.
            -- apply (H3 _ H0).
            -- destruct H0; subst; [rewrite map_app|]; simpl.
               ++ rewrite SubList_app_l_iff; split; repeat intro.
                  ** destruct upds; simpl in *;
                       [contradiction| apply (H3 _ (or_introl eq_refl)); assumption].
                  ** rewrite HConsistent in P1; apply P1; simpl in *.
                     rewrite map_app, in_app_iff.
                     clear - H0; firstorder fail.
               ++ eapply H3; destruct upds; simpl in *; eauto.
          * clear.
            destruct (UpdOrMeths_RegsT newUml); simpl; auto.
            destruct (UpdOrMeths_RegsT newUmlCont); simpl;
              [rewrite app_nil_r| rewrite <-app_assoc]; auto.
          * destruct (UpdOrMeths_RegsT newUml); simpl; auto.
            -- intro k0; specialize (H2 k0).
               rewrite UpdOrMeths_RegsT_app, map_app, in_app_iff in H2.
               clear - H2; firstorder fail.
            -- intro k0; specialize (H2 k0); specialize (HDisjRegs k0).
               clear - H2 HDisjRegs.
               rewrite UpdOrMeths_RegsT_app, map_app, in_app_iff in *; firstorder fail.
      - inv H3; inv HWf; EqDep_subst; econstructor; eauto.
      - inv H3; inv HWf; EqDep_subst; econstructor; eauto.
        constructor.
      - inv H2; inv HWf; EqDep_subst.
        unfold WfRegMapExpr in *; dest.
        econstructor; eauto.
        + econstructor; eauto.
          unfold WfRegMapExpr; split; eauto.
          * econstructor; eauto.
          * simpl; intros.
            destruct H2; subst; split.
            -- rewrite map_app,  NoDup_app_iff; repeat split; repeat intro; auto.
               ++ destruct upds; simpl; [constructor| apply (H0 _ (or_introl eq_refl))].
               ++ simpl; constructor; [intro; contradiction| constructor].
               ++ destruct H4; auto; subst.
                  specialize (H1 r); simpl in *.
                  clear - H1 H2; firstorder fail.
               ++ destruct H2; auto; subst.
                  specialize (H1 r); simpl in *.
                  clear - H1 H4; firstorder fail.
            -- rewrite map_app, SubList_app_l_iff; split; simpl.
               ++ repeat intro.
                  destruct upds; [contradiction| apply (H0 _ (or_introl eq_refl))]; auto.
               ++ repeat intro; destruct H2;[subst |contradiction].
                  rewrite HConsistent in HRegVal; assumption.
            -- destruct upds; [contradiction| apply (H0 _ (or_intror H2))].
            -- destruct upds; [contradiction| apply (H0 _ (or_intror H2))].
        + reflexivity.
        + simpl; eapply IHa; eauto.
          * split; [constructor| intros]; split.
            -- inv H2; simpl in *; [rewrite map_app, NoDup_app_iff; repeat split; repeat intro|].
               ++ destruct upds; [constructor| simpl; apply (H0 _ (or_introl eq_refl))].
               ++ simpl; repeat constructor; auto.
               ++ specialize (H1 a0); clear - H1 H2 H4; firstorder fail.
               ++ specialize (H1 a0); clear - H1 H2 H4; firstorder fail.
               ++ destruct upds; [inv H4| apply (H0 _ (or_intror _ H4))].
            -- inv H2; repeat intro; simpl in *.
               ++ rewrite map_app, in_app_iff in H2; simpl in H2.
                  destruct H2; [ destruct upds; [contradiction|]| destruct H2; [|contradiction]];
                    subst.
                  ** apply (H0 _ (or_introl _ (eq_refl))); assumption.
                  ** rewrite HConsistent in HRegVal; assumption.
               ++ destruct upds; [contradiction| apply (H0 _ (or_intror _ H4)); assumption].
          * simpl; destruct (UpdOrMeths_RegsT newUml); auto.
            rewrite <-app_assoc; reflexivity.
          * intro k0; simpl; rewrite map_app, in_app_iff.
            specialize (H1 k0); simpl in *.
            clear - H1 HDisjRegs.
            destruct H1; auto.
            destruct (string_dec r k0); subst.
            -- right; intro.
               rewrite in_map_iff in H0; dest; destruct x; subst; simpl in *.
               apply (HDisjRegs s0); assumption.
            -- left; intro; firstorder fail.
      - inv H3; inv HWf; EqDep_subst;
          [econstructor
          | assert (evalExpr (Const type true && e)%kami_expr = false) as P0;
            [simpl; rewrite HFalse; reflexivity
            | specialize (FalseSemCompAction_Ext _ HPriorityUpds HConsistent WfMap HRegConsist H12 P0) as P1;
              setoid_rewrite <- Extension_Compiles_iff in P1;
              dest];
            econstructor 8].
        + assert (evalExpr (Const type true) = evalExpr (Const type true && e))%kami_expr as P0.
          { simpl; rewrite HTrue; reflexivity. }
          apply (SemCompActionEEquivBexpr _ _ _ _ _ P0).
          eapply IHa1 with (old := old) (o := o); auto.
          * apply WfMap.
          * apply HRegConsist.
          * assumption.
          * instantiate (1 := newUml1).
            intro; specialize (H2 k0); clear - H2; rewrite UpdOrMeths_RegsT_app, map_app, in_app_iff in H2; firstorder fail.
          * apply HEAction.
        + rewrite UpdOrMeths_MethsT_app; reflexivity.
        + assert (evalExpr (Const type true && !e)%kami_expr = false) as P0.
          { simpl; rewrite HTrue; reflexivity. }
          assert (WfRegMapExpr (VarRegMap type (old, match UpdOrMeths_RegsT newUml1 with
                                                         | [] => upds
                                                         | _ :: _ => (hd [] upds ++ UpdOrMeths_RegsT newUml1) :: tl upds
                                                         end))
                               (old, match UpdOrMeths_RegsT newUml1 with
                                     | [] => upds
                                     | _ :: _ => (hd [] upds ++ UpdOrMeths_RegsT newUml1) :: tl upds
                                     end)) as P1.
          { unfold WfRegMapExpr in *; dest; split; auto; [constructor|].
            intros; split.
            - specialize (ESemAction_NoDup_Upds HEAction) as P1.
              rewrite UpdOrMeths_RegsT_app in H2.
              destruct (UpdOrMeths_RegsT newUml1).
              + apply H1; auto.
              + inv H3; [| destruct upds; [contradiction| apply H1; right; assumption]].
                rewrite map_app, NoDup_app_iff; repeat split; auto.
                * destruct upds;[constructor| apply H1; left; reflexivity].
                * repeat intro; specialize (H2 a); rewrite map_app, in_app_iff in H2;clear - H2 H3 H4; firstorder fail.
                * repeat intro; specialize (H2 a); rewrite map_app, in_app_iff in H2;clear - H2 H3 H4; firstorder fail.
            - specialize (ESemAction_SubList_Upds HEAction) as P1.
              destruct (UpdOrMeths_RegsT newUml1).
              + apply H1; auto.
              + inv H3; [|destruct upds; [contradiction| apply H1; right; assumption]].
                repeat intro; rewrite map_app, in_app_iff in *; inv H3;[| rewrite HConsistent in *; auto].
                destruct upds; [contradiction|].
                apply (H1 r0 (in_eq _ _)); assumption.
          }
          specialize (FalseSemCompAction_Ext _ HPriorityUpds HConsistent P1 HRegConsist H13 P0) as P2; dest.
          rewrite <- Extension_Compiles_iff in H0.
          econstructor.
          * apply H0.
          * reflexivity.
          * rewrite UpdOrMeths_RegsT_app.
            econstructor; simpl; rewrite HTrue.
            eapply H; eauto.
            -- destruct (UpdOrMeths_RegsT newUml1); simpl; auto.
               destruct (UpdOrMeths_RegsT newUml2); [rewrite app_nil_r | rewrite app_comm_cons, app_assoc]; simpl; auto.
            -- rewrite UpdOrMeths_RegsT_app in *.
               destruct (UpdOrMeths_RegsT newUml1); simpl in *; auto.
               clear - H2 HDisjRegs.
               intro k; specialize (H2 k); specialize (HDisjRegs k); simpl in *; rewrite map_app, in_app_iff in *.
               firstorder fail.
        + apply H0.
        + reflexivity.
        + rewrite UpdOrMeths_RegsT_app, UpdOrMeths_MethsT_app.
          assert (WfRegMapExpr (VarRegMap type (old, upds)) (old, upds)) as P1.
          { unfold WfRegMapExpr in *; dest; split; auto; constructor. }
          econstructor; simpl.
          * assert (evalExpr (Const type true) = evalExpr (Const type true && ! e)%kami_expr) as P2.
            { simpl; rewrite HFalse; auto. }
            apply (SemCompActionEEquivBexpr _ _ _ _ _ P2).
            eapply IHa2 with (o := o) (old := old) (upds := upds) (uml := newUml1); eauto.
            clear - H2; intro k; specialize (H2 k); rewrite UpdOrMeths_RegsT_app, map_app, in_app_iff in H2.
            firstorder fail.
          * reflexivity.
          * econstructor; simpl; rewrite HFalse.
            eapply H with (upds := match UpdOrMeths_RegsT newUml1 with
                                   | [] => upds
                                   | _ :: _ => (hd [] upds ++ UpdOrMeths_RegsT newUml1) :: tl upds
                                   end); eauto.
            -- rewrite UpdOrMeths_RegsT_app in *.
               specialize (ESemAction_NoDup_Upds HEAction) as P3.
               specialize (ESemAction_SubList_Upds HEAction) as P4.
               unfold WfRegMapExpr in *; dest; split; [constructor| intros; split].
               ++ destruct (UpdOrMeths_RegsT newUml1);[apply H6; assumption| inv H7; [| apply H6; destruct upds;[contradiction| right; assumption]]].
                  rewrite map_app, NoDup_app_iff; repeat split; repeat intro; auto.
                  ** destruct upds; [constructor| apply H6; left; reflexivity].
                  ** clear - H2 H7 H8; specialize (H2 a); rewrite map_app, in_app_iff in H2.
                     firstorder fail.
                  ** clear - H2 H7 H8; specialize (H2 a); rewrite map_app, in_app_iff in H2.
                     firstorder fail.
               ++ destruct (UpdOrMeths_RegsT newUml1);[apply H6; assumption| inv H7; [| apply H6; destruct upds;[contradiction| right; assumption]]].
                  rewrite HConsistent in P4.
                  repeat intro; rewrite map_app, in_app_iff in H7; inv H7.
                  ** destruct upds; [contradiction|].
                     apply (H6 r0 (in_eq _ _)); assumption.
                  ** apply P4; assumption.
            -- rewrite UpdOrMeths_RegsT_app in *.
               destruct (UpdOrMeths_RegsT newUml1); simpl in *; auto.
               destruct (UpdOrMeths_RegsT newUml2); simpl in *; [rewrite app_nil_r| rewrite <-app_assoc, app_comm_cons; simpl];auto.
            -- rewrite UpdOrMeths_RegsT_app in *.
               destruct (UpdOrMeths_RegsT newUml1); simpl in *; auto.
               clear - H2 HDisjRegs.
               intro k; specialize (H2 k); specialize (HDisjRegs k); simpl in *; rewrite map_app, in_app_iff in *.
               firstorder fail.
      - inv H2; inv HWf; EqDep_subst; econstructor; eauto.
      - inv H2; inv HWf; EqDep_subst; econstructor; eauto.
    Qed.
    
    Corollary ECompCongruence k (ea : EActionT type k) (a : ActionT type k) :
      forall writeMap o old upds oInit uInit m
             (HoInitNoDups : NoDup (map fst oInit))
             (HuInitNoDups : forall u, In u uInit -> NoDup (map fst u))
             (HPriorityUpds : PriorityUpds oInit uInit o)
             (HConsistent : getKindAttr o = getKindAttr old)
             (WfMap : WfRegMapExpr writeMap (old, upds))
             (HRegConsist : getKindAttr o = getKindAttr (getRegisters m))
             (HWf : WfActionT m a),
      (forall uml retl, ESemAction o ea uml retl -> ESemAction o (Action_EAction a) uml retl) ->
      forall upds' calls retl, 
        @SemCompActionT k (EcompileAction (oInit, uInit) ea (Const type true) writeMap) upds' calls retl ->
        @SemCompActionT k (EcompileAction (oInit, uInit) (Action_EAction a) (Const type true) writeMap) upds' calls retl.
    Proof.
      intros.
      apply (EEquivActions _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap) in H0; dest.
      specialize (H _ _ H3).
       eapply ActionsEEquivWeak; eauto.
       rewrite H1 in H0; simpl in *.
       destruct (UpdOrMeths_RegsT x); [intro; right; intro; contradiction|].
       specialize (H0 _ (or_introl eq_refl)); dest; rewrite map_app, NoDup_app_iff in H0; dest.
       intro; specialize (H6 k0); specialize (H7 k0).
       destruct (in_dec string_dec k0 (map fst (hd [] upds))); auto.
    Qed.
    
  Lemma EquivActions k a:
    forall
      writeMap o old upds oInit uInit
      (HoInitNoDups : NoDup (map fst oInit))
      (HuInitNoDups : forall u, In u uInit -> NoDup (map fst u))
      (HPriorityUpds : PriorityUpds oInit uInit o)
      (HConsistent : getKindAttr o = getKindAttr old)
      (WfMap : WfRegMapExpr writeMap (old, upds)),
    forall calls retl upds',
      @SemCompActionT k (compileAction (oInit, uInit) a (Const type true) writeMap) upds' calls retl ->
      (forall u, In u (snd upds') -> NoDup (map fst u) /\ SubList (getKindAttr u) (getKindAttr old)) /\
      exists newRegs readRegs,
        upds' = (old, match newRegs with
                      |nil => upds
                      |_ :: _ => (hd nil upds ++ newRegs) :: tl upds
                      end) /\
        SemAction o a readRegs newRegs calls retl.
  Proof.
    induction a; subst; intros; simpl in *.
    - inv H0; EqDep_subst;[|discriminate].
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists x, x0; split; auto.
      econstructor; eauto.
    - inv H0; EqDep_subst.
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists x, x0; split; auto.
      econstructor; eauto.
    - inv H0; EqDep_subst.
      specialize (IHa _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT_a); dest.
      assert (WfRegMapExpr (VarRegMap type regMap_a) regMap_a) as WfMap0.
      { unfold WfRegMapExpr; split;[econstructor|].
        destruct regMap_a; inv H1; intros.
        apply (H0 _ H1).
      }
      rewrite H1 in *.
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap0 _ _ _ HSemCompActionT_cont); dest.
      split; auto.
      exists (x++x1), (x0++x2); split.
      + destruct x1; simpl in *; auto.
        * rewrite app_nil_r; assumption.
        * destruct x; simpl in *; auto.
          rewrite app_comm_cons, app_assoc; assumption.
      + econstructor; eauto.
        rewrite H3 in H; simpl in *.
        clear - H.
        destruct x, x1; eauto using DisjKey_nil_r, DisjKey_nil_l; simpl in *.
        specialize (H _ (or_introl _ eq_refl)); simpl in *; dest.
        repeat rewrite map_app in H.
        intro k.
        destruct (In_dec string_dec k (map fst (p0::x1))); auto.
        left; intro.
        destruct (NoDup_app_Disj string_dec _ _ H k); auto.
        apply H2; rewrite in_app_iff; right; auto.
    - inv H0; EqDep_subst.
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists x, x0; split; auto.
      econstructor; eauto.
    - inv H0; EqDep_subst.
      specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists x, ((r, existT _ k regVal) :: x0).
      split; auto.
      econstructor; eauto.
      inv HReadMap.
      apply (PriorityUpds_Equiv HoInitNoDups HuInitNoDups HUpdatedRegs HPriorityUpds); auto.
    - inv H; simpl in *; EqDep_subst.
      rewrite (unifyWO val_a) in HSemCompActionT_a.
      inv HSemCompActionT_a; EqDep_subst.
      destruct HRegMapWf, WfMap, regMap_a.
      inv H;[|discriminate]; EqDep_subst.
      specialize (SemRegExprVals H1 HSemRegMap) as P0; inv P0.
      assert (WfRegMapExpr (VarRegMap type (r0, (hd nil upds0 ++ (r, existT (fullType type) k (evalExpr e)) :: nil) :: tl upds0))
                           (r0, (hd nil upds0 ++ (r, existT (fullType type) k (evalExpr e)) :: nil) :: tl upds0)) as WfMap0.
      { split; auto. constructor. }
      specialize (IHa _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap0 _ _ _ HSemCompActionT_cont);
        dest; simpl in *; split; auto.
      exists ((r, existT (fullType type) k (evalExpr e)) :: nil ++ x), x0; split.
      + destruct x; simpl in *; auto.
        rewrite <- app_assoc in H3. rewrite <-app_comm_cons in H3.
        simpl in H3; auto.
      + rewrite H3 in H; simpl in *; destruct x; econstructor; eauto; simpl in *; specialize (H _ (or_introl _ eq_refl)); dest.
        * rewrite map_app, <-HConsistent in H6; simpl in *.
          apply (H6 (r, k)).
          rewrite in_app_iff; right; left; reflexivity.
        * repeat intro; inv H7.
        * rewrite map_app, <-HConsistent in H6; simpl in *.
          apply (H6 (r, k)).
          rewrite map_app; repeat rewrite in_app_iff; simpl; auto.
        * repeat intro.
          repeat rewrite map_app in H; simpl in *.
          destruct H7; subst; destruct (NoDup_app_Disj string_dec _ _ H r) as [P0|P0]; apply P0.
          -- rewrite in_app_iff; simpl; auto.
          -- simpl; auto.
          -- rewrite in_app_iff; simpl; auto.
          -- simpl; right; rewrite in_map_iff.
             exists (r, v); simpl; auto.
    - inv H0; EqDep_subst.
      inv HSemCompActionT_cont; EqDep_subst.
      inv HSemCompActionT_cont0; EqDep_subst.
      remember (evalExpr e) as P0.
      apply Eqdep.EqdepTheory.inj_pair2 in H4.
      rewrite H4 in *.
      clear H4; simpl in *.
      assert (forall bexpr, (evalExpr (Const type true && bexpr)%kami_expr = evalExpr bexpr)) as P1.
      { intro; simpl; auto. }
      specialize (SemCompActionEquivBexpr _ _ _ _ _ (P1 e) HSemCompActionT_a) as P2.
      specialize (SemCompActionEquivBexpr _ _ _ _ _ (P1 (!e)%kami_expr) HSemCompActionT_a0) as P3.
      destruct P0; simpl in *.
      + assert (evalExpr e = evalExpr (Const type true)) as P4; simpl; auto.
        assert (evalExpr (!e)%kami_expr = false) as P5.
        { simpl; rewrite <- HeqP0; auto. }
        specialize (SemCompActionEquivBexpr _ _ _ _ _ P4 P2) as P6.
        specialize (IHa1 _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ P6); dest.
        rewrite <- HeqP0 in HSemCompActionT.
        destruct (predFalse_UpdsNil _ _ _ _ P5 (SemVarRegMap regMap_a) P3).
        assert (WfRegMapExpr (VarRegMap type regMap_a0) regMap_a0) as P7.
        { unfold WfRegMapExpr; split; [constructor|]. subst; eauto. }
        rewrite <- H3 in P7 at 2.
        rewrite H1 in P7.
        specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent P7 _ _ _ HSemCompActionT); dest.
        split; auto.
        exists (x++x1), (x0++x2).
        destruct x; simpl; split; auto.
        * rewrite H4.
          econstructor; eauto.
          apply DisjKey_nil_l.
        * destruct x1; [rewrite app_nil_r|]; simpl in *; auto.
          rewrite <-app_assoc, <-app_comm_cons in H5; assumption.
        * rewrite H4; simpl.
          econstructor; eauto.
          rewrite H5 in H; simpl in *.
          clear - H.
          destruct x1; simpl in *; [apply DisjKey_nil_r|].
          specialize (H _ (or_introl _ (eq_refl))); dest.
          rewrite map_app in H.
          intro.
          destruct (NoDup_app_Disj string_dec _ _ H k); auto.
          left; intro; apply H1.
          rewrite map_app, in_app_iff; auto.
      + assert (evalExpr (!e)%kami_expr = evalExpr (Const type true)) as P4.
        { simpl; rewrite <- HeqP0; auto. }
        specialize (SemCompActionEquivBexpr _ _ _ _ _ P4 P3) as P6.
        remember WfMap as WfMap0.
        inv WfMap0.
        destruct (predFalse_UpdsNil _ _ _ _ (eq_sym HeqP0) H0 P2).
        assert (WfRegMapExpr (VarRegMap type regMap_a) (old, upds)) as WfMap0.
        { rewrite <- H2.
          clear - WfMap.
          unfold WfRegMapExpr in *; dest; repeat split;[constructor| |]; eapply H0; eauto.
        }
        specialize (IHa2 _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap0 _ _ _ P6); dest.
        rewrite <- HeqP0 in HSemCompActionT.
        assert (WfRegMapExpr (VarRegMap type regMap_a0) regMap_a0) as P7.
        { unfold WfRegMapExpr; split; [constructor|]. subst; eauto. }
        rewrite  H5 in P7 at 2.
        specialize (H _ _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent P7 _ _ _ HSemCompActionT); dest.
        split; auto.
        exists (x++x1), (x0++x2).
        destruct x; simpl; split; auto.
        * rewrite H3; simpl.
          econstructor 8; eauto.
          apply DisjKey_nil_l.
        * destruct x1;[rewrite app_nil_r|]; simpl in *; auto.
          rewrite <-app_assoc, <-app_comm_cons in H7; assumption.
        * rewrite H3; simpl.
          econstructor 8; eauto.
          rewrite H7 in H; simpl in *.
          clear - H.
          destruct x1; simpl in *; [apply DisjKey_nil_r|].
          specialize (H _ (or_introl _ (eq_refl))); dest.
          rewrite map_app in H.
          intro.
          destruct (NoDup_app_Disj string_dec _ _ H k); auto.
          left; intro; apply H1.
          rewrite map_app, in_app_iff; auto.
    - inv H; EqDep_subst.
      specialize (IHa _ _ _ _ _ _ HoInitNoDups HuInitNoDups HPriorityUpds HConsistent WfMap _ _ _ HSemCompActionT); dest; split; auto.
      exists x, x0.
      split; auto.
      econstructor; eauto.
    - inv H; EqDep_subst.
      inv WfMap; inv HRegMapWf.
      specialize (SemRegExprVals H H1) as TMP; subst; simpl in *.
      split; auto.
      exists nil, nil.
      split; auto.
      constructor; auto.
  Qed.


  Lemma SameOldAction (k : Kind) (a : ActionT type k) :
    forall oInit uInit writeMap old upds wOld wUpds calls retl bexpr
           (HSemRegMap : SemRegMapExpr writeMap (wOld, wUpds)),
      @SemCompActionT k (compileAction (oInit, uInit) a bexpr writeMap) (old, upds) calls retl ->
      wOld = old.
  Proof.
    induction a; intros; simpl in *.
    - inv H0; EqDep_subst; simpl in *; eapply H; eauto.
    - inv H0; EqDep_subst; simpl in *.
      eapply H; eauto.
    - inv H0; EqDep_subst; simpl in *.
      destruct regMap_a.
      specialize (H _ _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT_cont); subst.
      specialize (IHa _ _ _ _ _ _ _ _ _ _ HSemRegMap HSemCompActionT_a); assumption.
    - inv H0; EqDep_subst; simpl in *.
      eapply H; eauto.
    - inv H0; EqDep_subst; simpl in *.
      eapply H; eauto.
    - inv H; simpl in *; EqDep_subst.
      rewrite (unifyWO val_a) in HSemCompActionT_a.
      inv HSemCompActionT_a; EqDep_subst.
      destruct regMap_a; unfold WfRegMapExpr in *; dest.
      inv H; EqDep_subst.
      + specialize (IHa _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT_cont).
        specialize (SemRegExprVals HSemRegMap HSemRegMap0) as TMP; inv TMP.
        reflexivity.
      + specialize (IHa  _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT_cont).
        specialize (SemRegExprVals HSemRegMap HSemRegMap0) as TMP; inv TMP.
        reflexivity.
    - inv H0; EqDep_subst; simpl in *.
      inv HSemCompActionT_cont; EqDep_subst.
      inv HSemCompActionT_cont0; simpl in *; EqDep_subst.
      destruct regMap_a, regMap_a0.
      specialize (H _ _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT).
      simpl in *.
      specialize (IHa1 _ _ _ _ _ _ _ _ _ _ HSemRegMap HSemCompActionT_a).
      specialize (IHa2 _ _ _ _ _ _ _ _ _ _ (SemVarRegMap _) HSemCompActionT_a0).
      subst; reflexivity.
    - inv H; EqDep_subst; simpl in *.
      eapply IHa; eauto.
    - inv H; EqDep_subst.
      unfold WfRegMapExpr in *; dest.
      specialize (SemRegExprVals H HSemRegMap) as TMP; inv TMP.
      reflexivity.
  Qed.

  Lemma SameOldActions o la:
    forall old upds calls retl,
      @SemCompActionT Void (compileActions (o, nil) (rev la)) (old, upds)  calls retl ->
      o = old.
  Proof.
    induction la; simpl in *; intros.
    rewrite (unifyWO retl) in H.
    inv H; EqDep_subst.
    inv HRegMapWf.
    inv H.
    reflexivity.
    - unfold compileActions in *; simpl in *.
      setoid_rewrite <- fold_left_rev_right in IHla.
      rewrite <- fold_left_rev_right in *.
      rewrite rev_app_distr, rev_involutive in *; simpl in *.
      rewrite (unifyWO retl) in H.
      inv H; simpl in *; EqDep_subst.
      rewrite (unifyWO (zToWord 0 0)) in HSemCompActionT_cont.
      inv HSemCompActionT_cont; simpl in *; EqDep_subst.
      rewrite (unifyWO val_a0) in HSemCompActionT_a0.
      inv HSemCompActionT_a0; EqDep_subst.
      destruct regMap_a.
      specialize (IHla _ _ _ _ HSemCompActionT_a); subst.
      destruct regMap_a0.
      inv HRegMapWf; inv H; inv HSemRegMap.
      apply (SameOldAction _ _ _ _ (SemVarRegMap _) HSemCompActionT_cont0).
  Qed.

  Lemma SameOldLoop (m : BaseModule) o:
    forall rules old upds calls retl,
      @SemCompActionT Void (compileRules type (o, nil) (rev rules)) (old, upds) calls retl ->
      o = old.
  Proof.
    induction rules; simpl in *; intros.
    - rewrite (unifyWO retl) in H.
      inv H; EqDep_subst.
      inv HRegMapWf.
      inv H.
      reflexivity.
    - unfold compileRules, compileActions in *; simpl in *.
      setoid_rewrite <- fold_left_rev_right in IHrules.
      rewrite map_app, <- fold_left_rev_right, map_rev in *.
      simpl in *.
      rewrite rev_app_distr, rev_involutive in *; simpl in *.
      rewrite (unifyWO retl) in H.
      inv H; EqDep_subst.
      apply Eqdep.EqdepTheory.inj_pair2 in H4; subst; simpl in *.
      destruct regMap_a.
      specialize (IHrules _ _ _ _ HSemCompActionT_a); subst.
      rewrite (unifyWO (zToWord 0 0)) in HSemCompActionT_cont.
      inv HSemCompActionT_cont; simpl in *; EqDep_subst.
      rewrite (unifyWO val_a0) in HSemCompActionT_a0.
      inv HSemCompActionT_a0; simpl in *; EqDep_subst.
      destruct regMap_a; inv HRegMapWf; inv H; inv HSemRegMap.
      apply (SameOldAction _ _ _ _ (SemVarRegMap _) HSemCompActionT_cont0).
  Qed.
  
  Lemma EquivLoop (m : BaseModule) o:
    forall rules upds calls retl ls
           (HoInitNoDups : NoDup (map fst o))
           (HTrace : Trace m o ls)
           (HNoSelfCalls : NoSelfCallBaseModule m)
           (*HNoMeths : (getMethods m) = nil*),
      SubList rules (getRules m) ->
      @SemCompActionT Void (compileRules type (o, nil) (rev rules)) (o, upds) calls retl ->
      (forall u, In u upds -> (NoDup (map fst u)) /\ SubList (getKindAttr u) (getKindAttr o)) /\
      exists o' (ls' : list (list FullLabel)),
        PriorityUpds o upds o' /\
        upds = (map getLabelUpds ls') /\
        calls = concat (map getLabelCalls (rev ls')) /\
        Trace m o' (ls' ++ ls).
  Proof.
    induction rules; simpl in *; intros.
    - rewrite (unifyWO retl) in H0.
      inv H0; EqDep_subst.
      unfold WfRegMapExpr in *; dest.
      inv H0; split; auto.
      exists o, nil; repeat split; auto.
      constructor.
    - unfold compileRules, compileActions in *; simpl in *.
      rewrite map_app in *.
      rewrite <- fold_left_rev_right in *.
      rewrite map_rev in *.
      simpl in *.
      rewrite rev_app_distr in H0.
      rewrite rev_involutive in *.
      simpl in *.
      rewrite (unifyWO retl) in H0.
      inv H0; simpl in *; EqDep_subst.
      destruct (SubList_cons H) as [TMP P0]; clear TMP.
      destruct regMap_a.
      rewrite (unifyWO (zToWord 0 0)) in HSemCompActionT_cont.
      inv HSemCompActionT_cont; simpl in *; EqDep_subst.
      rewrite (unifyWO val_a0) in HSemCompActionT_a0.
      inv HSemCompActionT_a0; simpl in *; EqDep_subst.
      destruct regMap_a.
      specialize HRegMapWf as HRegMapWf0.
      inv HRegMapWf; inv H0; inv HSemRegMap.
      specialize (SameOldAction _ _ _ _ (SemVarRegMap _) HSemCompActionT_cont0) as TMP; subst.
      specialize (IHrules _ _ _ _ HoInitNoDups HTrace HNoSelfCalls P0 HSemCompActionT_a); dest.
      rewrite <-CompactPriorityUpds_iff in H2; auto.
      assert (forall u, In u (nil :: upds0) -> NoDup (map fst u)) as P1.
      { intros.
        destruct (H1 _ H7); auto.
      }
      assert (WfRegMapExpr (VarRegMap type (o, nil :: upds0)) (o, nil::upds0)) as P2.
      { clear - HRegMapWf0.
        unfold WfRegMapExpr in *; dest; split; auto.
        constructor.
      }
      specialize (EquivActions _ HoInitNoDups P1 H2 (eq_sym (prevPrevRegsTrue H2))
                               P2 HSemCompActionT_cont0) as TMP; dest.
      split; auto; simpl in *.
      assert (upds = (x1::upds0)) as P4.
      { inv H8. destruct x1; auto. }
      clear H8; subst.
      exists (doUpdRegs x1 x), (((x1, (Rle (fst a), calls_cont0))::nil)::x0).
      unfold getLabelCalls, getLabelUpds in *; simpl in *.
      rewrite app_nil_r.
      repeat split; auto.
      + econstructor 2 with (u := x1); auto.
        * rewrite CompactPriorityUpds_iff in H2; auto.
          apply H2.
        * specialize (H7 _ (or_introl eq_refl)); dest.
          rewrite (prevPrevRegsTrue H2).
          apply getKindAttr_doUpdRegs; eauto.
          -- rewrite <- (getKindAttr_map_fst _ _ (prevPrevRegsTrue H2)).
             assumption.
          -- intros.
             rewrite <- (prevPrevRegsTrue H2).
             apply H4.
             rewrite in_map_iff.
             exists (s, v); simpl; split; auto.
        * repeat intro.
          rewrite (getKindAttr_map_fst _ _ (prevPrevRegsTrue H2)) in HoInitNoDups.
          specialize (H7 _ (or_introl eq_refl)); dest.
          rewrite (prevPrevRegsTrue H2) in H7.
          specialize (doUpdRegs_UpdRegs _ (HoInitNoDups) _ H4 H7) as P4.
          unfold UpdRegs in P4; dest.
          specialize (H10 _ _ H3); dest.
          destruct H10; dest.
          -- inv H10; auto.
             inv H12.
          -- right; split; auto.
             intro; apply H10.
             exists x1; split; simpl; auto.
      + repeat rewrite map_app; simpl.
        repeat rewrite concat_app; simpl.
        repeat rewrite app_nil_r.
        reflexivity.
      + destruct a; simpl in *.
        econstructor 2.
        * apply H5.
        * enough (Step m x ((x1, (Rle s, calls_cont0))::nil)) as P3.
          { apply P3. }
          econstructor.
          -- econstructor 2; eauto; specialize (Trace_sameRegs HTrace) as TMP; simpl in *.
             ++ rewrite <- TMP, (prevPrevRegsTrue H2); reflexivity.
             ++ apply H; left; simpl; reflexivity.
             ++ rewrite <- TMP, (prevPrevRegsTrue H2).
                apply SubList_map, (SemActionReadsSub H9).
             ++ specialize (H7 _ (or_introl eq_refl)); dest.
                rewrite <- TMP, (prevPrevRegsTrue H2).
                apply (SemActionUpdSub H9).
             ++ intros; inv H3.
             ++ intros; inv H3.
             ++ econstructor.
                rewrite <- TMP.
                apply (eq_sym (prevPrevRegsTrue H2)).
          -- unfold MatchingExecCalls_Base; intros.
             specialize (getNumExecs_nonneg f [(x1, (Rle s, calls_cont0))]) as P3.
             unfold getNumCalls; simpl.
             rewrite getNumFromCalls_app; simpl.
             erewrite NoSelfCallRule_Impl; eauto.
             ++ apply H; apply in_eq.
             ++ apply H9.
        * simpl.
          apply doUpdRegs_enuf; auto.
          -- specialize (H7 _ (or_introl (eq_refl))); dest; auto.
          -- apply getKindAttr_doUpdRegs; auto.
             ++ rewrite <-(getKindAttr_map_fst _ _ (prevPrevRegsTrue H2)); assumption.
             ++ specialize (H7 _ (or_introl (eq_refl))); dest; assumption.
             ++ intros.
                specialize (H7 _ (or_introl (eq_refl))); dest.
                rewrite <-(prevPrevRegsTrue H2).
                apply H7.
                rewrite in_map_iff.
                exists (s0, v); auto.
        * reflexivity.
  Qed.

  Corollary EquivLoop' {m : BaseModule} {o ls rules upds calls retl}
            (HTrace : Trace m o ls) (HRegsWf : NoDup (map fst (getRegisters m)))
            (HNoSelfCalls : NoSelfCallBaseModule m) (HValidSch : SubList rules (getRules m)):
    @SemCompActionT Void (compileRules type (o, nil) rules) (o, upds) calls retl ->
    (forall u, In u upds -> (NoDup (map fst u)) /\ SubList (getKindAttr u) (getKindAttr o)) /\
    exists o' (ls' : list (list FullLabel)),
      PriorityUpds o upds o' /\
      upds = (map getLabelUpds ls') /\
      calls = concat (map getLabelCalls (rev ls')) /\
      Trace m o' (ls' ++ ls).
  Proof.
    specialize (Trace_NoDup HTrace HRegsWf) as HoInitNoDups.
    rewrite <- (rev_involutive rules).
    assert (SubList (rev rules) (getRules m)) as P0.
    { repeat intro; apply HValidSch; rewrite in_rev; assumption. }
    eapply EquivLoop; eauto.
  Qed.

  (*
  Definition inlineAll_RegFile {k : Kind} (a : ActionT type k) (rf : RegFileBase) :=
    fold_left (fun a' m  => inlineSingle m a') (getMethods rf) a.

  Definition inlineAll_RegFiles {k : Kind} (a : ActionT type k) (rfl : list RegFileBase) :=
    fold_left (fun a' rf => inlineAll_RegFile a' rf) rfl a.
*)
  Lemma fst_getKindAttr {A B : Type} {P : B -> Type} (l : list (A * {x : B & P x})) :
    map fst (getKindAttr l) = map fst l.
  Proof.
    induction l; simpl; auto.
    rewrite IHl; reflexivity.
  Qed.
  
  Lemma PriorityUpds_glue upds1 :
    forall o1 o1',
      (forall u, In u upds1 -> SubList (getKindAttr u) (getKindAttr o1)) ->
      PriorityUpds o1 upds1 o1' ->
      forall upds2 o2 o2', 
      (forall u, In u upds2 -> SubList (getKindAttr u) (getKindAttr o2)) ->
      PriorityUpds o2 upds2 o2' ->
      DisjKey o1 o2 ->
      PriorityUpds (o1++o2) (upds1++upds2) (o1'++o2').
  Proof.
    induction upds1.
    - simpl.
      induction upds2; intros.
      + inv H2; inv H0; [constructor 1 |discriminate| |discriminate]; discriminate.
      + inv H2; inv H0; inv HFullU;[|discriminate].
        econstructor 2.
        * eapply IHupds2; eauto.
          intros; eapply H1.
          right; assumption.
        * repeat rewrite map_app; rewrite currRegsTCurr.
          reflexivity.
          
        * intros.
          rewrite in_app_iff in H0; destruct H0.
          -- right; split.
             ++ intro.
                specialize (H1 _ (or_introl eq_refl)).
                rewrite in_map_iff in H2; dest; subst.
                specialize (H1 _ (in_map (fun x => (fst x, projT1 (snd x))) _ _ H4)).
                destruct (H3 (fst x)).
                ** apply H2.
                   rewrite in_map_iff.
                   exists (fst x, v); split; auto.
                ** apply H2.
                   apply (in_map fst) in H1; simpl in *.
                   rewrite fst_getKindAttr in H1; assumption.
             ++ rewrite in_app_iff; left ; assumption.
          -- destruct (Hcurr _ _ H0); [left; apply H2|right; dest; split; auto].
             rewrite in_app_iff; right; assumption.
        * reflexivity.
    - intros; simpl.
      inv H0; inv HFullU.
      econstructor 2 with (prevUpds := prevUpds ++ upds2) (u := u) (prevRegs := prevRegs ++ o2').
      + eapply IHupds1; eauto.
        intros; apply (H _ (or_intror H0)).
      + repeat rewrite map_app; rewrite currRegsTCurr, (prevPrevRegsTrue H2).
        reflexivity.
      + intros; rewrite in_app_iff in H0.
        destruct H0.
        * specialize (Hcurr _ _ H0).
          destruct Hcurr; auto.
          dest; right; split; auto.
          rewrite in_app_iff; left; assumption.
        * right; split.
          -- intro.
             rewrite in_map_iff in H4; dest; subst.
             specialize (H _ (or_introl eq_refl)
                           _ (in_map (fun x => (fst x, projT1 (snd x))) _ _ H5)).
             apply (in_map fst) in H0; simpl in *.
             apply (in_map fst) in H; rewrite fst_getKindAttr in H; simpl in *.
             destruct (H3 (fst x)); eauto.
             rewrite  (getKindAttr_map_fst _ _ (prevPrevRegsTrue H2)) in H4; contradiction.
          -- rewrite in_app_iff; auto.
      + reflexivity.
  Qed.
                
             
  Lemma PriorityUpds_exist o (HNoDup : NoDup (map fst o)):
    forall upds
      (HUpdsCorrect : forall u, In u upds
                                -> SubList (getKindAttr u) (getKindAttr o))
      (HNoDupUpds : forall u, In u upds -> NoDup (map fst u)),
      exists o',
        PriorityUpds o upds o'.
  Proof.
    induction upds.
    - exists o.
      constructor.
    - intros.
      assert (forall u, In u upds -> SubList (getKindAttr u) (getKindAttr o)) as P0.
      { intros; apply HUpdsCorrect; simpl; eauto. }
      assert (forall u, In u upds -> NoDup (map fst u)) as P1.
      { intros; specialize (HNoDupUpds _ (or_intror H)); assumption. }
      specialize (IHupds P0 P1); dest.
      exists (doUpdRegs a x).
      rewrite (getKindAttr_map_fst _ _ (prevPrevRegsTrue H)) in HNoDup.
      rewrite (prevPrevRegsTrue H) in HUpdsCorrect.
      specialize (doUpdRegs_UpdRegs _ HNoDup _
                                    (HNoDupUpds _ (or_introl eq_refl))
                                    (HUpdsCorrect _ (or_introl eq_refl))) as P2.
      unfold UpdRegs in P2; dest.
      econstructor; auto.
      + apply H.
      + rewrite (prevPrevRegsTrue H).
        assumption.
      + intros.
        specialize (H1 _ _ H2).
        destruct H1; dest.
        * destruct H1; subst; auto.
          contradiction.
        * right; split; auto.
          intro; apply H1.
          exists a; split; auto.
          left; reflexivity.
  Qed.

  Hint Rewrite unifyWO : _word_zero.

  Lemma key_not_In_app {A B : Type} (key : A) (ls1 ls2 : list (A * B)):
    key_not_In key (ls1 ++ ls2) ->
    key_not_In key ls1 /\ key_not_In key ls2.
  Proof.
    induction ls1; simpl; intros; split;
      repeat intro; auto; eapply H; eauto; simpl; rewrite in_app_iff; eauto.
    inv H0; eauto.
  Qed.

  Lemma key_not_In_app_iff {A B : Type} (key : A) (ls1 ls2 : list (A * B)):
    key_not_In key (ls1 ++ ls2) <-> key_not_In key ls1 /\ key_not_In key ls2.
  Proof.
    split; eauto using key_not_In_app.
    repeat intro; dest.
    rewrite in_app_iff in H0.
    destruct H0.
    - eapply H; eauto.
    - eapply H1; eauto.
  Qed.

  Section ESemAction_meth_collector.
    
    Variable f : DefMethT.
    Variable o : RegsT.
    
    Inductive ESemAction_meth_collector : UpdOrMeths -> UpdOrMeths -> Prop :=
    | NilUml : ESemAction_meth_collector nil nil
    | ConsUpd  um uml uml' newUml newUml' upd
               (HUpd : um = Upd upd)
               (HDisjRegs : key_not_In (fst upd) (UpdOrMeths_RegsT newUml))
               (HUmlCons : uml' = um :: uml)
               (HnewUmlCons : newUml' = um :: newUml)
               (HCollector : ESemAction_meth_collector uml newUml):
        ESemAction_meth_collector uml' newUml'
    | ConsCallsNStr um uml uml' newUml newUml' meth
                      (HMeth : um = Meth meth)
                      (HIgnore : fst meth <> fst f)
                      (HUmlCons : uml' = um :: uml)
                      (HnewUmlCons : newUml' = um :: newUml)
                      (HCollector : ESemAction_meth_collector uml newUml):
        ESemAction_meth_collector uml' newUml'
    | ConsWrCallsNSgn um uml uml' newUml newUml' meth
                      (HMeth : um = Meth meth)
                      (HIgnore : projT1 (snd meth) <> projT1 (snd f))
                      (HUmlCons : uml' = um :: uml)
                      (HnewUmlCons : newUml' = um :: newUml)
                      (HCollector : ESemAction_meth_collector uml newUml):
        ESemAction_meth_collector uml' newUml'
    | ConsWrFCalls  um fUml uml uml' newUml newUml' argV retV
                    (HMeth : um = Meth (fst f, (existT _ (projT1 (snd f)) (argV, retV))))
                    (HESemAction : ESemAction o (Action_EAction (projT2 (snd f) type argV)) fUml retV)
                    (HDisjRegs : DisjKey (UpdOrMeths_RegsT fUml) (UpdOrMeths_RegsT newUml))
                    (HUmlCons : uml' = um :: uml)
                    (HnewUmlApp : newUml' = fUml ++ newUml)
                    (HCollector : ESemAction_meth_collector uml newUml):
        ESemAction_meth_collector uml' newUml'.

    Lemma ESemActionMC_Upds_SubList (uml : UpdOrMeths) :
      forall newUml,
        ESemAction_meth_collector uml newUml ->
        SubList (UpdOrMeths_RegsT uml) (UpdOrMeths_RegsT newUml).
    Proof.
      induction uml; repeat intro.
      - inv H0.
      - simpl in H0.
        destruct a.
        + inv H; inv HUmlCons; simpl.
          inv H0; auto.
          right; eapply IHuml; eauto.
        + inv H; inv HUmlCons; simpl; auto.
          * eapply IHuml; eauto.
          * eapply IHuml; eauto.
          * rewrite UpdOrMeths_RegsT_app, in_app_iff; right.
            eapply IHuml; eauto.
    Qed.
    
    Lemma ESemAction_meth_collector_break (uml1 : UpdOrMeths) :
      forall uml2 newUml,
        ESemAction_meth_collector (uml1 ++ uml2) newUml ->
        exists newUml1 newUml2,
          newUml = newUml1 ++ newUml2 /\
          DisjKey (UpdOrMeths_RegsT newUml1) (UpdOrMeths_RegsT newUml2) /\
          ESemAction_meth_collector uml1 newUml1 /\
          ESemAction_meth_collector uml2 newUml2.
    Proof.
      induction uml1; simpl; intros.
      - exists nil, newUml; simpl; repeat split; auto.
        + intro k; auto.
        + constructor.
      - inv H; inv HUmlCons;  specialize (IHuml1 _ _ HCollector); dest.
        + exists (Upd upd :: x), x0; subst; repeat split; auto.
          * rewrite UpdOrMeths_RegsT_app in HDisjRegs.
            apply key_not_In_app in HDisjRegs; dest.
            intro k; simpl.
            destruct (string_dec (fst upd) k); subst.
            -- right; intro.
               rewrite in_map_iff in H4; dest.
               apply (H3 (snd x1)); destruct x1; simpl in *; rewrite <- H4; auto.
            -- destruct (H0 k); auto.
               left; intro; destruct H5; auto.
          * econstructor; auto.
            rewrite UpdOrMeths_RegsT_app in HDisjRegs.
            apply key_not_In_app in HDisjRegs; dest; auto.
        + exists (Meth meth :: x), x0; subst; repeat split; auto.
          econstructor 3; eauto.
        + exists (Meth meth :: x), x0; subst; repeat split; auto.
          econstructor 4; eauto.
        + exists (fUml ++ x), x0; subst; repeat split; eauto using app_assoc.
          * intro k; specialize (HDisjRegs k); specialize (H0 k).
            rewrite UpdOrMeths_RegsT_app, map_app, in_app_iff in *.
            firstorder fail.
          * econstructor 5; auto.
            -- assumption.
            -- intro k; destruct (HDisjRegs k); auto.
               right; intro; apply H.
               rewrite UpdOrMeths_RegsT_app, map_app, in_app_iff; auto.
    Qed.

    Lemma ESemAction_meth_collector_stitch (uml1 : UpdOrMeths) :
      forall uml2 newUml1 newUml2
             (HDisjRegs : DisjKey (UpdOrMeths_RegsT newUml1) (UpdOrMeths_RegsT newUml2)),
        ESemAction_meth_collector uml1 newUml1 ->
        ESemAction_meth_collector uml2 newUml2 ->
        ESemAction_meth_collector (uml1 ++ uml2) (newUml1 ++ newUml2).
    Proof.
      induction uml1; simpl; intros.
      - inv H; simpl; auto; discriminate.
      - inv H; simpl; inv HUmlCons.
        + econstructor; auto.
          * specialize (HDisjRegs (fst upd)); simpl in *; destruct HDisjRegs; [exfalso; apply H; left; reflexivity|].
            repeat intro.
            rewrite UpdOrMeths_RegsT_app, in_app_iff in H1.
            destruct H1.
            -- eapply HDisjRegs0; eauto.
            -- apply H; rewrite in_map_iff; exists (fst upd, v); split; auto.
          * eapply IHuml1; eauto.
            repeat intro; specialize (HDisjRegs k); simpl in *.
            clear - HDisjRegs.
            firstorder fail.
        + econstructor 3; auto.
          assumption.
        + econstructor 4; auto.
          assumption.
        + econstructor 5.
          * reflexivity.
          * apply HESemAction.
          * instantiate (1 := newUml ++ newUml2).
            intro k.
            specialize (HDisjRegs k); specialize (HDisjRegs0 k).
            clear - HDisjRegs HDisjRegs0.
            rewrite UpdOrMeths_RegsT_app, map_app, in_app_iff in *.
            firstorder fail.
          * reflexivity.
          * rewrite app_assoc; reflexivity.
          * eapply IHuml1; eauto.
            intro k.
            specialize (HDisjRegs k).
            clear - HDisjRegs.
            rewrite UpdOrMeths_RegsT_app, map_app, in_app_iff in *.
            firstorder fail.
    Qed.

  End ESemAction_meth_collector.
  
  Section WriteInline.

    
    Lemma Extension_inlineWrites {k : Kind} (ea : EActionT type k) :
      forall o uml retv rf,
        ESemAction o ea uml retv ->
        forall newUml,
          ESemAction_meth_collector (getRegFileWrite rf) o uml newUml ->
          ESemAction o (inlineWriteFile rf ea) newUml retv.
    Proof.
      induction ea; simpl; intros; destruct rf.
      - inv H0; EqDep_subst.
        inv H1;[discriminate | | | ]; remember (String.eqb _ _) as strb; destruct strb;
          symmetry in Heqstrb; inv HUmlCons; try rewrite String.eqb_eq in Heqstrb;
            try rewrite String.eqb_neq in Heqstrb; subst;
            try (destruct rfIsWrMask, Signature_dec); subst; simpl in *; try congruence;
              EqDep_subst.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + autorewrite with _word_zero in *; inv HESemAction0; simpl in *; EqDep_subst.
          autorewrite with _word_zero in *; inv HESemAction1; simpl in *; EqDep_subst.
          do 2 econstructor; auto; rewrite (Eqdep.EqdepTheory.UIP_refl _ _ e0).
          -- apply HRegVal.
          -- instantiate (1 := (newUml ++ newUml0)).
             do 2 (apply f_equal2; auto; apply f_equal).
             clear.
             rewrite <- (rev_involutive (getFins rfNum)).
             repeat rewrite <- fold_left_rev_right; simpl.
             rewrite (rev_involutive).
             induction (rev (getFins rfNum)); simpl; auto.
             rewrite IHl; auto.
          -- repeat intro.
             specialize (HDisjRegs rfDataArray); simpl in *.
             rewrite UpdOrMeths_RegsT_app, in_app_iff in H0.
             destruct H0.
             ++ eapply HDisjRegs0; eauto.
             ++ destruct HDisjRegs; eauto.
                apply H1; rewrite in_map_iff; exists (rfDataArray, v); split; auto.
          -- autorewrite with _word_zero in *; inv HESemAction0; simpl in *; EqDep_subst.
             rewrite (unifyWO retV) in HESemAction; simpl in *.
             eapply H; simpl; eauto.
        + autorewrite with _word_zero in *; inv HESemAction0; simpl in *; EqDep_subst.
          autorewrite with _word_zero in *; inv HESemAction1; simpl in *; EqDep_subst.
          econstructor; auto; econstructor 13; auto; rewrite (Eqdep.EqdepTheory.UIP_refl _ _ e0).
          -- apply HRegVal.
          -- instantiate (1 := (newUml ++ newUml0)).
             do 2 (apply f_equal2; auto; apply f_equal).
             clear.
             rewrite <- (rev_involutive (getFins rfNum)).
             repeat rewrite <- fold_left_rev_right; simpl.
             rewrite (rev_involutive).
             induction (rev (getFins rfNum)); simpl; auto.
             rewrite IHl; auto.
          -- repeat intro.
             specialize (HDisjRegs rfDataArray); simpl in *.
             rewrite UpdOrMeths_RegsT_app, in_app_iff in H0.
             destruct H0.
             ++ eapply HDisjRegs0; eauto.
             ++ destruct HDisjRegs; eauto.
                apply H1; rewrite in_map_iff; exists (rfDataArray, v); split; auto.
          -- autorewrite with _word_zero in *; inv HESemAction0; simpl in *; EqDep_subst.
             rewrite (unifyWO retV) in HESemAction; simpl in *.
             eapply H; simpl; eauto.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; simpl in *; EqDep_subst.
        + specialize (ESemAction_meth_collector_break _ _ H1) as TMP; dest.
          econstructor.
          * instantiate (1 := x0); instantiate (1 := x); auto.
          * eapply IHea; eauto.
          * eapply H; eauto.
          * assumption.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      -inv H; simpl in *; EqDep_subst.
       inv H0; [ | discriminate | discriminate | discriminate].
       inv HUmlCons; econstructor; auto.
       + simpl in *; auto.
       + eapply IHea; eauto.
      - inv H0; simpl in *; EqDep_subst; specialize (ESemAction_meth_collector_break _ _ H1) as TMP; dest.
        + econstructor; eauto.
        + econstructor 8; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
        inv H0; auto; discriminate.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst.
        + inv H0; inv HUmlCons.
          econstructor; eauto.
        + inv H0; inv HUmlCons.
          econstructor 13; eauto.
      - inv H; simpl in *; EqDep_subst.
        + inv H0; inv HUmlCons.
          econstructor; auto.
          * simpl in *; eauto.
          * eapply IHea; eauto.
        + inv H0; inv HUmlCons.
          econstructor 15; auto.
          * apply HRegVal2.
          * instantiate (1 := newUml1).
            simpl in *; eauto.
          * reflexivity.
          * eapply IHea; eauto.
      - inv H0; simpl in *; EqDep_subst.
        + econstructor; eauto.
        + econstructor 17; eauto.
    Qed.

    Lemma inlineWrites_Extension {k : Kind} (ea : EActionT type k):
      forall rf o newUml retv,
        ESemAction o (inlineWriteFile rf ea) newUml retv ->
        exists uml,
          ESemAction_meth_collector (getRegFileWrite rf) o uml newUml /\
          ESemAction o ea uml retv.
    Proof.
      induction ea; simpl in *; intro rf; remember rf as rf'; destruct rf'; intros.
      - remember (String.eqb _ _) as strb; symmetry in Heqstrb.
        destruct strb; try rewrite String.eqb_eq in *; try rewrite String.eqb_neq in *;
          [destruct rfIsWrMask; destruct Signature_dec |].
        + revert Heqrf'.
          inv H0; simpl in *; EqDep_subst.
          inv HESemAction; simpl in *; EqDep_subst.
          * specialize (H _ _ _ _ _ HESemAction0); dest; inv H8.
            intro.
            exists ( Meth (meth, existT SignT (WriteRqMask (Nat.log2_up rfIdxNum) rfNum rfData, Void) (evalExpr e, (zToWord 0 0)))::x); split.
            -- econstructor 5; auto.
               ++ econstructor; eauto.
                  econstructor; simpl; auto.
                  ** rewrite in_map_iff.
                     exists (rfDataArray, existT _ (SyntaxKind (Array rfIdxNum rfData)) regV); split; auto.
                  ** instantiate (1 := nil); repeat intro; auto.
                  ** econstructor; eauto.
               ++ intro; simpl.
                  destruct (string_dec rfDataArray k).
                  ** right; instantiate (1 := newUml0).
                     intro; rewrite in_map_iff in H1; dest; destruct x0; simpl in *; subst.
                     eapply HDisjRegs; eauto.
                  ** left; intro; destruct H1; subst; eauto.
               ++ simpl.
                  do 2 (apply f_equal2; auto; apply f_equal).
                  clear.
                  rewrite <- (rev_involutive (getFins rfNum)).
                  repeat rewrite <- fold_left_rev_right; simpl.
                  rewrite (rev_involutive).
                  induction (rev (getFins rfNum)); simpl; auto.
                  rewrite IHl; auto.
               ++ assumption.
            -- econstructor; eauto.
          * discriminate.
        + inv H0; simpl in *; EqDep_subst.
          * specialize (H _ _ _ _ _ HESemAction); dest.
            exists (Meth (meth, existT SignT s (evalExpr e, mret))::x); split.
            -- econstructor 4; simpl; eauto.
               intro; destruct s; simpl in *; auto.
            -- econstructor; eauto.
        + revert Heqrf'.
          inv H0; EqDep_subst.
          inv HESemAction; simpl in *; EqDep_subst; [discriminate|].
          * specialize (H _ _ _ _ _ HESemAction0); dest; inv H8.
            intro.
            exists ( Meth (meth, existT SignT (WriteRq (Nat.log2_up rfIdxNum) (Array rfNum rfData), Void) (evalExpr e, (zToWord 0 0)))::x); split.
            -- econstructor 5; auto.
               ++ econstructor; eauto.
                  econstructor; simpl; auto.
                  ** rewrite in_map_iff.
                     exists (rfDataArray, existT _ (SyntaxKind (Array rfIdxNum rfData)) regV); split; auto.
                  ** instantiate (1 := nil); repeat intro; auto.
                  ** econstructor; eauto.
               ++ intro; simpl.
                  destruct (string_dec rfDataArray k).
                  ** right; instantiate (1 := newUml0).
                     intro; rewrite in_map_iff in H1; dest; destruct x0; simpl in *; subst.
                     eapply HDisjRegs; eauto.
                  ** left; intro; destruct H1; subst; eauto.
               ++ simpl.
                  do 2 (apply f_equal2; auto; apply f_equal).
                  clear.
                  rewrite <- (rev_involutive (getFins rfNum)).
                  repeat rewrite <- fold_left_rev_right; simpl.
                  rewrite (rev_involutive).
                  induction (rev (getFins rfNum)); simpl; auto.
                  rewrite IHl; auto.
               ++ assumption.
            -- econstructor; eauto.
        + inv H0; simpl in *; EqDep_subst.
          * specialize (H _ _ _ _ _ HESemAction); dest.
            exists (Meth (meth, existT SignT s (evalExpr e, mret))::x); split.
            -- econstructor 4; simpl; eauto.
               intro; destruct s; simpl in *; auto.
            -- econstructor; eauto.
        + inv H0; simpl in *; EqDep_subst.
          * specialize (H _ _ _ _ _ HESemAction); dest.
            exists (Meth (meth, existT SignT s (evalExpr e, mret))::x); split.
            -- econstructor 3; simpl; eauto.
               intro; destruct s; simpl in *; auto.
            -- econstructor; eauto.
      - inv H0; EqDep_subst.
        specialize (H _ _ _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        specialize (H _ _ _ _ _ HESemActionCont); dest.
        specialize (IHea _ _ _ _ HESemAction); dest.
        exists (x0 ++ x); split; auto.
        apply ESemAction_meth_collector_stitch; auto.
        econstructor.
        + instantiate (1 := x); instantiate (1 := x0).
          intro k0.
          specialize (HDisjRegs k0).
          specialize (ESemActionMC_Upds_SubList H) as P0.
          specialize (ESemActionMC_Upds_SubList H1) as P1.
          clear - P0 P1 HDisjRegs.
          destruct HDisjRegs;[left | right]; intro; apply H; rewrite in_map_iff in *; dest;
            exists x1; split; auto.
        + apply H2.
        + assumption.
        + reflexivity.
      - inv H0; EqDep_subst.
        specialize (H _ _ _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        specialize (H _ _ _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        specialize (IHea _ _ _ _ HESemAction); dest.
        exists (Upd (r, existT (fullType type) k (evalExpr e))::x); split; auto.
        + econstructor; auto.
          * simpl; assumption.
        + econstructor; auto.
          repeat intro; eapply HDisjRegs.
          apply (ESemActionMC_Upds_SubList H _ H1).
      - inv H0; EqDep_subst.
        + specialize (IHea1 _ _ _ _ HEAction); dest.
          specialize (H _ _ _ _ _ HESemAction); dest.
          exists (x ++ x0); split; auto.
          * apply ESemAction_meth_collector_stitch; auto.
          * econstructor; auto.
            -- intro k0.
               specialize (HDisjRegs k0).
               specialize (ESemActionMC_Upds_SubList H) as P0.
               specialize (ESemActionMC_Upds_SubList H0) as P1.
               clear - P0 P1 HDisjRegs.
               destruct HDisjRegs; [left | right]; intro; apply H; rewrite in_map_iff in *; dest;
                 exists x1; split; auto.
            -- apply H1.
            -- assumption.
        + specialize (IHea2 _ _ _ _ HEAction); dest.
          specialize (H _ _ _ _ _ HESemAction); dest.
          exists (x ++ x0); split; auto.
          * apply ESemAction_meth_collector_stitch; auto.
          * econstructor 8; auto.
            -- intro k0.
               specialize (HDisjRegs k0).
               specialize (ESemActionMC_Upds_SubList H) as P0.
               specialize (ESemActionMC_Upds_SubList H0) as P1.
               clear - P0 P1 HDisjRegs.
               destruct HDisjRegs; [left | right]; intro; apply H; rewrite in_map_iff in *; dest;
                 exists x1; split; auto.
            -- apply H1.
            -- assumption.
      - inv H; EqDep_subst.
        specialize (IHea _ _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        exists nil; split; auto.
        + constructor.
        + econstructor; eauto.
      - inv H0; EqDep_subst.
        specialize (H _ _ _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        + specialize (IHea _ _ _ _ HESemAction); dest.
          exists (Upd (dataArray,
                       existT (fullType type) (SyntaxKind (Array idxNum Data))
                              (evalExpr
                                 (fold_left
                                    (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                       (IF ReadArrayConst mask0 i
                                        then newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                                   ReadArrayConst val i] else newArr)%kami_expr) 
                                    (getFins num) (Var type (SyntaxKind (Array idxNum Data)) regV))))::x); split; auto.
          * econstructor; eauto; simpl.
            assumption.
          * econstructor; eauto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P0.
            apply (P0 _ H1).
        + specialize (IHea _ _ _ _ HESemAction); dest.
          exists (Upd (dataArray,
                       existT (fullType type) (SyntaxKind (Array idxNum Data))
                              (evalExpr
                                 (fold_left
                                    (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                       (newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                              ReadArrayConst val i])%kami_expr) (getFins num)
                                    (Var type (SyntaxKind (Array idxNum Data)) regV))))::x); split; auto.
          * econstructor; eauto; simpl.
            assumption.
          * econstructor 13; eauto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P0.
            apply (P0 _ H1).
      - inv H; EqDep_subst.
        + specialize (IHea _ _ _ _ HESemAction); dest.
          exists (Upd (readReg,
                       existT (fullType type) (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx)) :: x); split; auto.
          * econstructor; eauto.
            simpl; assumption.
          * econstructor; auto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P0.
            apply (P0 _ H1).
        + specialize (IHea _ _ _ _ HESemAction); dest.
          exists (Upd (readReg,
                       existT (fullType type) (SyntaxKind (Array num Data))
                              (evalExpr
                                 (BuildArray
                                    (fun i : Fin.t num =>
                                       (Var type (SyntaxKind (Array idxNum Data)) regV @[
                                              Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx) +
                                              Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))])%kami_expr)))) :: x); split; auto.
          * econstructor; simpl in *; auto.
            -- assumption.
          * econstructor 15; auto.
            -- assumption.
            -- repeat intro.
               eapply HDisjRegs.
               specialize (ESemActionMC_Upds_SubList H) as P0.
               apply (P0 _ H1).
      - inv H0; EqDep_subst.
        + specialize (H _ _ _ _ _ HESemAction); dest.
          exists x ; split; auto.
          econstructor; eauto.
        + specialize (H _ _ _ _ _ HESemAction); dest.
          exists x; split; auto.
          econstructor 17; eauto.
    Qed.

    Corollary inlineWrites_conguence {k : Kind} (ea1 ea2 : EActionT type k) :
      (forall o uml retv,
          ESemAction o ea1 uml retv ->
          ESemAction o ea2 uml retv) ->
      forall o newUml retv rf,
        ESemAction o (inlineWriteFile rf ea1) newUml retv ->
        ESemAction o (inlineWriteFile rf ea2) newUml retv.
    Proof.
      intros.
      specialize (inlineWrites_Extension _ _ H0) as TMP; dest.
      specialize (H _ _ _ H2).
      apply (Extension_inlineWrites _ H H1).
    Qed.

    Lemma WrInline_inlines {k : Kind} (a : ActionT type k) :
      forall rf o uml retv,
        ESemAction o (Action_EAction (inlineSingle (getRegFileWrite rf) a)) uml retv ->
        ESemAction o (inlineWriteFile rf (Action_EAction a)) uml retv.
    Proof.
      induction a; intros; auto; simpl; destruct rf; subst; simpl in *.
      - destruct String.eqb, rfIsWrMask;
          [destruct Signature_dec| destruct Signature_dec | | ]; simpl in *.
        + inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          inv HESemAction0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          do 2 econstructor; auto.
          * apply HRegVal.
          * instantiate (1 := (newUml0 ++ newUmlCont)); simpl.
            do 2 (apply f_equal2; auto; apply f_equal).
            clear.
            rewrite <- (rev_involutive (getFins rfNum)).
            repeat rewrite <- fold_left_rev_right; simpl.
            rewrite (rev_involutive).
            induction (rev (getFins rfNum)); simpl; auto.
            rewrite IHl; auto.
          * repeat intro; simpl in *.
            rewrite UpdOrMeths_RegsT_app, in_app_iff in H0.
            specialize (HDisjRegs rfDataArray); simpl in *.
            destruct HDisjRegs; [apply H1; auto|].
            specialize (HDisjRegs0 v0); destruct H0; auto.
            apply H1; rewrite in_map_iff.
            exists (rfDataArray, v0); split; auto.
          * inv HESemAction0; EqDep_subst; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; eauto.
        +  inv H0; EqDep_subst.
           inv HESemAction; EqDep_subst.
           inv HESemAction0; EqDep_subst.
           inv HESemAction; EqDep_subst.
           econstructor; auto; econstructor 13; auto.
           * apply HRegVal.
           * instantiate (1 := (newUml0 ++ newUmlCont)); simpl.
             do 2 (apply f_equal2; auto; apply f_equal).
             clear.
             rewrite <- (rev_involutive (getFins rfNum)).
             repeat rewrite <- fold_left_rev_right; simpl.
             rewrite (rev_involutive).
             induction (rev (getFins rfNum)); simpl; auto.
             rewrite IHl; auto.
           * repeat intro; simpl in *.
             rewrite UpdOrMeths_RegsT_app, in_app_iff in H0.
             specialize (HDisjRegs rfDataArray); simpl in *.
             destruct HDisjRegs; [apply H1; auto|].
             specialize (HDisjRegs0 v0); destruct H0; auto.
             apply H1; rewrite in_map_iff.
             exists (rfDataArray, v0); split; auto.
           * inv HESemAction0; EqDep_subst; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; eauto.
        + inv H0; EqDep_subst.
          econstructor; eauto.
        + inv H0; EqDep_subst.
          econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst; econstructor; eauto.
      - inv H; EqDep_subst; econstructor; eauto.
      - inv H0; EqDep_subst.
        + econstructor; eauto.
        + econstructor 8; eauto.
      - inv H; EqDep_subst; econstructor; eauto.
      - inv H; EqDep_subst; econstructor; eauto.
    Qed.

    Lemma inline_WrInlines {k : Kind} (a : ActionT type k) rf :
      forall o uml retv,
        ESemAction o (inlineWriteFile rf (Action_EAction a)) uml retv ->
        ESemAction o (Action_EAction (inlineSingle (getRegFileWrite rf) a)) uml retv.
    Proof.
      induction a; intros; auto; simpl; destruct rf; subst; simpl in *.
      - destruct String.eqb, rfIsWrMask;
          [destruct Signature_dec| destruct Signature_dec | | ]; simpl in *.
        + inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst; inv H8.
          econstructor; simpl; auto.
          * instantiate (1 := newUml).
            instantiate (1 := (Upd
                                 (rfDataArray,
                                  existT (fullType type) (SyntaxKind (Array rfIdxNum rfData))
                                         (evalExpr
                                            (fold_left
                                               (fun (newArr : Expr type (SyntaxKind (Array rfIdxNum rfData))) (i : Fin.t rfNum) =>
                                                  (IF ReadArrayConst (ReadStruct e (Fin.FS (Fin.FS Fin.F1))) i
                                                   then newArr @[
                                                                 ReadStruct e Fin.F1 + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                                                             ReadArrayConst (ReadStruct e (Fin.FS Fin.F1)) i] else newArr)%kami_expr)
                                               (getFins rfNum) (Var type (SyntaxKind (Array rfIdxNum rfData)) regV))))) :: nil); simpl in *.
            intro k; simpl.
            destruct (string_dec rfDataArray k); [right | left]; intro; auto; subst.
            -- rewrite in_map_iff in *; dest; destruct x; subst; eapply HDisjRegs; eauto.
            -- destruct H0; auto.
          * do 2 econstructor; auto.
            -- apply HRegVal.
            -- econstructor; auto.
               ++ rewrite in_map_iff.
                  eexists; split; [| eapply HRegVal]; simpl; reflexivity.
               ++ instantiate (1 := nil); simpl; repeat intro; auto.
               ++ do 2 (apply f_equal2; auto; apply f_equal).
                   clear.
                   rewrite <- (rev_involutive (getFins rfNum)).
                   repeat rewrite <- fold_left_rev_right; simpl.
                   rewrite (rev_involutive).
                   induction (rev (getFins rfNum)); simpl; auto.
                   rewrite IHl; auto.
               ++ econstructor; eauto.
          * eapply H; eauto.
          * simpl; reflexivity.
        + inv H0; EqDep_subst.
          econstructor; eauto.
        + subst.
          inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst; [discriminate |].
          econstructor; simpl; auto.
          * instantiate (1 := newUml).
            instantiate (1 := (Upd
                                 (rfDataArray,
                                  existT (fullType type) (SyntaxKind (Array rfIdxNum rfData))
                                         (evalExpr
                                            (fold_left
                                               (fun (newArr : Expr type (SyntaxKind (Array rfIdxNum rfData))) (i : Fin.t rfNum) =>
                                                  (newArr @[ ReadStruct e Fin.F1 + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                                                         ReadArrayConst (ReadStruct e (Fin.FS Fin.F1)) i])%kami_expr) 
                                               (getFins rfNum) (Var type (SyntaxKind (Array rfIdxNum rfData)) regV))))) :: nil); simpl in *.
            intro k; simpl.
            destruct (string_dec rfDataArray k); [right | left]; intro; auto; subst.
            -- rewrite in_map_iff in *; dest; destruct x; subst; eapply HDisjRegs; eauto.
            -- destruct H0; auto.
          * do 2 econstructor; auto.
            -- apply HRegVal.
            -- econstructor; auto.
               ++ rewrite in_map_iff.
                  eexists; split; [| eapply HRegVal]; simpl; reflexivity.
               ++ instantiate (1 := nil); simpl; repeat intro; auto.
               ++ do 2 (apply f_equal2; auto; apply f_equal).
                   clear.
                   rewrite <- (rev_involutive (getFins rfNum)).
                   repeat rewrite <- fold_left_rev_right; simpl.
                   rewrite (rev_involutive).
                   induction (rev (getFins rfNum)); simpl; auto.
                   rewrite IHl; auto.
               ++ econstructor; eauto.
          * eapply H; eauto.
          * simpl; reflexivity.
        + inv H0; EqDep_subst.
          econstructor; eauto.
        + inv H0; EqDep_subst.
          econstructor; eauto.
        + inv H0; EqDep_subst.
          econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        ++ econstructor; eauto.
        ++ econstructor 8; eauto.
      - inv H; EqDep_subst.
        econstructor; eauto.
      - inv H; EqDep_subst.
        econstructor; eauto.
    Qed.

  End WriteInline.

  Lemma existsb_nexists_str str l :
    existsb (String.eqb str) l = false <->
    ~ In str l.
  Proof.
    split; repeat intro.
    - assert (exists x, In x l /\ (String.eqb str) x = true) as P0.
      { exists str; split; auto. apply String.eqb_refl. }
      rewrite <- existsb_exists in P0; rewrite P0 in *; discriminate.
    - remember (existsb _ _) as exb; symmetry in Heqexb; destruct exb; auto.
      exfalso; rewrite existsb_exists in Heqexb; dest.
      rewrite String.eqb_eq in *; subst; auto.
  Qed.

  Lemma existsb_nexists_sync sync l :
    existsb (SyncRead_eqb sync) l = false <->
    ~ In sync l.
  Proof.
    split; repeat intro.
    - assert (exists x, In x l /\ (SyncRead_eqb sync) x = true) as P0.
      { exists sync; split; auto. unfold SyncRead_eqb; repeat rewrite String.eqb_refl; auto. }
      rewrite <- existsb_exists in P0; rewrite P0 in *; discriminate.
    - remember (existsb _ _) as exb; symmetry in Heqexb; destruct exb; auto.
      exfalso; rewrite existsb_exists in Heqexb; dest.
      rewrite SyncRead_eqb_eq in *; subst; auto.
  Qed.
    
  
  Section AsyncReadInline.
    
    Lemma Extension_inlineAsyncRead {k : Kind} (ea : EActionT type k) :
      forall rf (read : string) (reads : list string)
             (HIsAsync : rfRead rf = Async reads) (HIn : In read reads) o uml retv,
        ESemAction o ea uml retv ->
        forall newUml,
          ESemAction_meth_collector (getAsyncReads rf read) o uml newUml ->
          ESemAction o (inlineAsyncReadFile read rf ea) newUml retv.
    Proof.
      destruct rf; simpl in *; destruct rfRead;[| intros; discriminate].
      induction ea; simpl; intros; inv HIsAsync; remember (existsb _ _) as exb;
        symmetry in Heqexb; destruct exb; try rewrite existsb_exists in *; dest;
          try rewrite existsb_nexists_str in *; try rewrite String.eqb_eq in *;
            subst; try congruence.
      - inv H0; EqDep_subst.
        remember (String.eqb _ _) as strb; symmetry in Heqstrb; revert Heqstrb.
        inv H1;[discriminate | | | ]; intro; destruct strb; try rewrite String.eqb_eq in *;
          inv HUmlCons; try (destruct Signature_dec); subst;
            try (simpl in *; congruence); EqDep_subst.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + rewrite (Eqdep.EqdepTheory.UIP_refl _ _ e0) in *.
          inv HESemAction0; EqDep_subst.
          inv HESemAction1; EqDep_subst.
          econstructor; simpl in *; eauto.
        + rewrite String.eqb_refl in *; discriminate.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; simpl in *; EqDep_subst.
        + specialize (ESemAction_meth_collector_break _ _ H1) as TMP; dest.
          econstructor.
          * instantiate (1 := x1); instantiate (1 := x0); auto.
          * eapply IHea; eauto.
          * eapply H; eauto.
          * assumption.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      -inv H; simpl in *; EqDep_subst.
       inv H0; [ | discriminate | discriminate | discriminate].
       inv HUmlCons; econstructor; auto.
       + simpl in *; auto.
       + eapply IHea; eauto.
      - inv H0; simpl in *; EqDep_subst; specialize (ESemAction_meth_collector_break _ _ H1) as TMP; dest.
        + econstructor; eauto.
        + econstructor 8; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
        inv H0; auto; discriminate.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst.
        + inv H0; inv HUmlCons.
          econstructor; eauto.
        + inv H0; inv HUmlCons.
          econstructor 13; eauto.
      - inv H; simpl in *; EqDep_subst.
        + inv H0; inv HUmlCons.
          econstructor; auto.
          * simpl in *; eauto.
          * eapply IHea; eauto.
        + inv H0; inv HUmlCons.
          econstructor 15; auto.
          * apply HRegVal2.
          * instantiate (1 := newUml1).
            simpl in *; eauto.
          * reflexivity.
          * eapply IHea; eauto.
      - inv H0; simpl in *; EqDep_subst.
        + econstructor; eauto.
        + econstructor 17; eauto.
    Qed.

    Lemma inlineAsyncRead_Extension {k : Kind} (ea : EActionT type k):
      forall rf (reads : list string)(HIsAsync : rfRead rf = Async reads)
             (read : string) (HIn : In read reads) o newUml retv,
        ESemAction o (inlineAsyncReadFile read rf ea) newUml retv ->
        exists uml,
          ESemAction_meth_collector (getAsyncReads rf read) o uml newUml /\
          ESemAction o ea uml retv.
    Proof.
      induction ea; simpl in *; intros rf; remember rf as rf'; destruct rf'; intros;
        simpl in *; rewrite HIsAsync in *; remember (existsb _ _) as exb;
        symmetry in Heqexb; destruct exb; try rewrite existsb_exists in *; dest;
          try rewrite existsb_nexists_str in *; try rewrite String.eqb_eq in *;
            revert Heqrf' HIsAsync; subst; try congruence.
      - remember (String.eqb _ _) as strb; symmetry in Heqstrb;
          destruct strb; [destruct Signature_dec |].
        + inv H0; EqDep_subst.
          intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
            exists ( Meth (x, existT SignT (Bit (Nat.log2_up rfIdxNum), Array rfNum rfData) (evalExpr e, (evalExpr
               (BuildArray
                  (fun i : Fin.t rfNum =>
                   (Var type (SyntaxKind (Array rfIdxNum rfData)) regV @[
                    Var type (SyntaxKind (Bit (Nat.log2_up rfIdxNum))) (evalExpr e) +
                    Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))])%kami_expr)))))::x0); split.
          * econstructor 5; auto.
            -- do 2 (econstructor; eauto).
            -- repeat intro; auto.
            -- simpl; reflexivity.
            -- assumption.
          * rewrite String.eqb_eq in *; subst; econstructor; eauto.
        + inv H0; EqDep_subst.
          intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists (Meth (meth, existT SignT s (evalExpr e, mret))::x0); split.
          * econstructor 4; simpl; eauto.
            intro; destruct s; simpl in *; auto.
          * econstructor; eauto.
        + inv H0; EqDep_subst.
          intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists (Meth (meth, existT SignT s (evalExpr e, mret))::x0); split.
          * econstructor 3; simpl; eauto.
            intro; destruct s; simpl in *; subst; rewrite String.eqb_refl in *; discriminate.
          * econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Async reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
        exists x0; split; auto.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Async reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ P0 _ HIn _ _ _ HESemActionCont); dest.
        specialize (IHea _ _ P0 _ HIn _ _ _ HESemAction); dest.
        exists (x1 ++ x0); split; auto.
        apply ESemAction_meth_collector_stitch; auto.
        econstructor.
        + instantiate (1 := x0); instantiate (1 := x1).
          intro k0.
          specialize (HDisjRegs k0).
          specialize (ESemActionMC_Upds_SubList H) as P1.
          specialize (ESemActionMC_Upds_SubList H2) as P2.
          clear - P1 P2 HDisjRegs.
          destruct HDisjRegs;[left | right]; intro; apply H; rewrite in_map_iff in *; dest;
            exists x; split; auto.
        + apply H3.
        + assumption.
        + reflexivity.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Async reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
        exists x0; split; auto.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Async reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
        exists x0; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Async reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (IHea _ _ P0 _ HIn _ _ _ HESemAction); dest.
        exists (Upd (r, existT (fullType type) k (evalExpr e))::x0); split; auto.
        + econstructor; auto.
          * simpl; assumption.
        + econstructor; auto.
          repeat intro; eapply HDisjRegs.
          apply (ESemActionMC_Upds_SubList H _ H2).
      - inv H0; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea1 _ _ P0 _ HIn _ _ _ HEAction); dest.
          specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists (x0 ++ x1); split; auto.
          * apply ESemAction_meth_collector_stitch; auto.
          * econstructor; auto.
            -- intro k0.
               specialize (HDisjRegs k0).
               specialize (ESemActionMC_Upds_SubList H) as P1.
               specialize (ESemActionMC_Upds_SubList H0) as P2.
               clear - P1 P2 HDisjRegs.
               destruct HDisjRegs; [left | right]; intro; apply H; rewrite in_map_iff in *; dest;
                 exists x; split; auto.
            -- apply H2.
            -- assumption.
        + intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea2 _ _ P0 _ HIn _ _ _ HEAction); dest.
          specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists (x0 ++ x1); split; auto.
          * apply ESemAction_meth_collector_stitch; auto.
          * econstructor 8; auto.
            -- intro k0.
               specialize (HDisjRegs k0).
               specialize (ESemActionMC_Upds_SubList H) as P1.
               specialize (ESemActionMC_Upds_SubList H0) as P2.
               clear - P1 P2 HDisjRegs.
               destruct HDisjRegs; [left | right]; intro; apply H; rewrite in_map_iff in *; dest;
                 exists x; split; auto.
            -- apply H2.
            -- assumption.
      - inv H; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Async reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (IHea _ _ P0 _ HIn _ _ _ HESemAction); dest.
        exists x0; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        exists nil; split; auto.
        + constructor.
        + econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Async reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
        exists x0; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists (Upd (dataArray,
                       existT (fullType type) (SyntaxKind (Array idxNum Data))
                              (evalExpr
                                 (fold_left
                                    (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                       (IF ReadArrayConst mask0 i
                                        then newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                                   ReadArrayConst val i] else newArr)%kami_expr) 
                                    (getFins num) (Var type (SyntaxKind (Array idxNum Data)) regV))))::x0); split; auto.
          * econstructor; eauto; simpl.
            assumption.
          * econstructor; eauto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P1.
            apply (P1 _ H2).
        + intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists (Upd (dataArray,
                       existT (fullType type) (SyntaxKind (Array idxNum Data))
                              (evalExpr
                                 (fold_left
                                    (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                       (newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                              ReadArrayConst val i])%kami_expr) (getFins num)
                                    (Var type (SyntaxKind (Array idxNum Data)) regV))))::x0); split; auto.
          * econstructor; eauto; simpl.
            assumption.
          * econstructor 13; eauto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P1.
            apply (P1 _ H2).
      - inv H; EqDep_subst.
        +  intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists (Upd (readReg,
                       existT (fullType type) (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx)) :: x0); split; auto.
          * econstructor; eauto.
            simpl; assumption.
          * econstructor; auto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P1.
            apply (P1 _ H2).
        + intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists (Upd (readReg,
                       existT (fullType type) (SyntaxKind (Array num Data))
                              (evalExpr
                                 (BuildArray
                                    (fun i : Fin.t num =>
                                       (Var type (SyntaxKind (Array idxNum Data)) regV @[
                                              Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx) +
                                              Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))])%kami_expr)))) :: x0); split; auto.
          * econstructor; eauto.
            simpl; assumption.
          * econstructor 15; auto.
            -- assumption.
            -- repeat intro.
               eapply HDisjRegs.
               specialize (ESemActionMC_Upds_SubList H) as P1.
               apply (P1 _ H2).
      - inv H0; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists x0 ; split; auto.
          econstructor; eauto.
        +  intros.
          assert (Syntax.rfRead rf = Async reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ P0 _ HIn _ _ _ HESemAction); dest.
          exists x0 ; split; auto.
          econstructor 17; eauto.
    Qed.

    Corollary inlineAsyncRead_conguence {k : Kind} (ea1 ea2 : EActionT type k) :
      (forall o uml retv,
          ESemAction o ea1 uml retv ->
          ESemAction o ea2 uml retv) ->
      forall o newUml retv rf (read : string) (reads : list string)
             (HIsAsync : rfRead rf = Async reads) (HIn : In read reads),
        ESemAction o (inlineAsyncReadFile read rf ea1) newUml retv ->
        ESemAction o (inlineAsyncReadFile read rf ea2) newUml retv.
    Proof.
      intros.
      specialize (inlineAsyncRead_Extension _ _ HIsAsync _ HIn H0) as TMP; dest.
      specialize (H _ _ _ H2).
      apply (Extension_inlineAsyncRead HIsAsync HIn H H1).
    Qed.

    Lemma AsyncReadInline_inlines {k : Kind} (a : ActionT type k) :
      forall rf (reads : list string)(HIsAsync : rfRead rf = Async reads)
             (read : string) (HIn : In read reads) o uml retv,
        ESemAction o (Action_EAction (inlineSingle (getAsyncReads rf read) a)) uml retv ->
        ESemAction o (inlineAsyncReadFile read rf (Action_EAction a)) uml retv.
    Proof.
      induction a; intros; auto; simpl; destruct rf; simpl in *; rewrite HIsAsync in *;
        remember (existsb _ _) as exb; symmetry in Heqexb; destruct exb;
          try rewrite existsb_exists in *; try rewrite existsb_nexists_str in *;
            dest; try rewrite String.eqb_eq in *; subst; try congruence.
      - remember (String.eqb _ _) as strb; symmetry in Heqstrb; destruct strb;
          [rewrite String.eqb_eq in *; destruct Signature_dec
          |rewrite String.eqb_neq in *]; simpl in *.
        + inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          inv HESemAction0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          econstructor; auto.
          * apply HRegVal.
          * eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; eauto.
          eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; auto.
          eapply H; simpl; eauto.
      - inv H0; EqDep_subst; econstructor; eapply H; simpl; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
        + eapply IHa; simpl; eauto.
        + eapply H; simpl; eauto.
      - inv H0; EqDep_subst; econstructor; eapply H; simpl; eauto.
      - inv H0; EqDep_subst; econstructor; eauto; eapply H; simpl; eauto.
      - inv H; EqDep_subst; econstructor; eauto; eapply IHa; simpl; eauto.
      - inv H0; EqDep_subst.
        + econstructor; eauto.
          * eapply IHa1; simpl; eauto.
          * eapply H; simpl; eauto.
        + econstructor 8; eauto.
          * eapply IHa2; simpl; eauto.
          * eapply H; simpl; eauto.
      - inv H; EqDep_subst; econstructor; eapply IHa; simpl; eauto.
    Qed.

    Lemma inline_AsyncReadInlines {k : Kind} (a : ActionT type k) rf :
      forall (reads : list string)(HIsAsync : rfRead rf = Async reads)
             (read : string) (HIn : In read reads) o uml retv,
        ESemAction o (inlineAsyncReadFile read rf (Action_EAction a)) uml retv ->
        ESemAction o (Action_EAction (inlineSingle (getAsyncReads rf read) a)) uml retv.
    Proof.
      induction a; intros; auto; simpl; destruct rf; simpl in *; rewrite HIsAsync in *;
        remember (existsb _ _) as exb; symmetry in Heqexb; destruct exb;
          try rewrite existsb_exists in *; try rewrite existsb_nexists_str in *;
            dest; try rewrite String.eqb_eq in *; subst; try congruence.
      - remember (String.eqb _ _) as strb; symmetry in Heqstrb; destruct strb;
          [rewrite String.eqb_eq in *; destruct Signature_dec
          |rewrite String.eqb_neq in *]; simpl in *.
        + inv H0; EqDep_subst.
          econstructor; simpl; auto.
          * instantiate (1 := uml).
            instantiate (1 := nil); simpl in *.
            intro k; simpl; auto.
          * do 2 econstructor; auto.
            -- apply HRegVal.
            -- econstructor; auto.
          * eapply H; eauto.
          * simpl; reflexivity.
        + inv H0; EqDep_subst.
          econstructor; eauto.
        + subst.
          inv H0; EqDep_subst.
          econstructor; simpl; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        ++ econstructor; eauto.
        ++ econstructor 8; eauto.
      - inv H; EqDep_subst.
        econstructor; eauto.
    Qed.

  End AsyncReadInline.
  
    Section SyncReqInline.
    
    Lemma Extension_inlineSyncReq {k : Kind} (ea : EActionT type k) :
      forall rf (isAddr : bool) (read : SyncRead) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads) o uml retv,
        ESemAction o ea uml retv ->
        forall newUml,
          ESemAction_meth_collector (getSyncReq rf isAddr read) o uml newUml ->
          ESemAction o (inlineSyncReqFile read rf ea) newUml retv.
    Proof.
      destruct rf; simpl in *; destruct rfRead;[intros; discriminate|].
      induction ea; simpl; intros; inv HIsSync; remember (existsb _ _ ) as exb;
        symmetry in Heqexb; destruct exb; try rewrite existsb_nexists_sync in *;
          try congruence; destruct read.
      - inv H0; EqDep_subst.
        inv H1;[discriminate | | | ]; remember (String.eqb _ _ ) as strb;
          symmetry in Heqstrb; destruct strb; try rewrite String.eqb_eq in *;
            try rewrite String.eqb_neq in *; inv HUmlCons;
          try (destruct Signature_dec); subst; unfold getSyncReq in *; destruct isAddr0; 
            try (simpl in *; congruence); EqDep_subst.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + simpl in *.
          rewrite (Eqdep.EqdepTheory.UIP_refl _ _ e0) in *.
          autorewrite with _word_zero in *; inv HESemAction0; EqDep_subst.
          autorewrite with _word_zero in *; inv HESemAction1; EqDep_subst.
          do 2 (econstructor; simpl in *; eauto).
          * repeat intro.
            destruct (HDisjRegs readRegName); apply H2; simpl; auto.
            rewrite in_map_iff; eexists; split; eauto.
            reflexivity.
          * eapply H; eauto.
            rewrite (unifyWO retV) in *; assumption.
        + simpl in *.
          rewrite (Eqdep.EqdepTheory.UIP_refl _ _ e0) in *.
          autorewrite with _word_zero in *; inv HESemAction0; EqDep_subst.
          autorewrite with _word_zero in *; inv HESemAction1; EqDep_subst.
          autorewrite with _word_zero in *; inv HESemActionCont; EqDep_subst.
          inv HESemAction0; EqDep_subst.
          autorewrite with _word_zero in *; inv HESemAction1; EqDep_subst.
          econstructor; simpl in *; eauto.
          econstructor 15; simpl in *; eauto.
          * repeat intro.
            destruct (HDisjRegs readRegName); apply H2; simpl; auto.
            rewrite in_map_iff; eexists; split; eauto.
            reflexivity.
          * eapply H; eauto.
            rewrite (unifyWO retV) in *; assumption.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; simpl in *; EqDep_subst.
        + specialize (ESemAction_meth_collector_break _ _ H1) as TMP; dest.
          econstructor.
          * instantiate (1 := x0); instantiate (1 := x); auto.
          * eapply IHea; eauto.
          * eapply H; eauto.
          * assumption.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      -inv H; simpl in *; EqDep_subst.
       inv H0; [ | discriminate | discriminate | discriminate].
       inv HUmlCons; econstructor; auto.
       + simpl in *; auto.
       + eapply IHea; eauto.
      - inv H0; simpl in *; EqDep_subst; specialize (ESemAction_meth_collector_break _ _ H1) as TMP; dest.
        + econstructor; eauto.
        + econstructor 8; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
        inv H0; auto; discriminate.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst.
        + inv H0; inv HUmlCons.
          econstructor; eauto.
        + inv H0; inv HUmlCons.
          econstructor 13; eauto.
      - inv H; simpl in *; EqDep_subst.
        + inv H0; inv HUmlCons.
          econstructor; auto.
          * simpl in *; eauto.
          * eapply IHea; eauto.
        + inv H0; inv HUmlCons.
          econstructor 15; auto.
          * apply HRegVal2.
          * instantiate (1 := newUml1).
            simpl in *; eauto.
          * reflexivity.
          * eapply IHea; eauto.
      - inv H0; simpl in *; EqDep_subst.
        + econstructor; eauto.
        + econstructor 17; eauto.
    Qed.

    Lemma inlineSyncReq_Extension {k : Kind} (ea : EActionT type k):
      forall rf (read : SyncRead) (isAddr : bool) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads) o newUml retv,
        ESemAction o (inlineSyncReqFile read rf ea) newUml retv ->
        exists uml,
          ESemAction_meth_collector (getSyncReq rf isAddr read) o uml newUml /\
          ESemAction o ea uml retv.
    Proof.
      induction ea; simpl in *; intros rf read; remember rf as rf'; remember read as read';
        destruct rf', read'; intros; simpl in *; rewrite HIsSync in *;
          remember (existsb _ _ ) as exb; symmetry in Heqexb; destruct exb;
            try rewrite existsb_nexists_sync in *; try congruence; revert Heqrf' Heqread' HIsSync.
      - remember (String.eqb _ _) as strb; symmetry in Heqstrb; destruct strb;
          [rewrite String.eqb_eq in *; subst; destruct Signature_dec
          |rewrite String.eqb_neq in *].
        +inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst; intros.
         * assert (Syntax.rfRead rf = Sync true reads) as P0.
           { rewrite <- Heqrf'; reflexivity. }
           rewrite <- Heqrf' in *.
           specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction0); dest.
           exists ( Meth (meth, existT SignT (Bit (Nat.log2_up rfIdxNum), Void) (evalExpr e, (zToWord 0 0)))::x); split.
          -- econstructor 5; auto.
             ++ econstructor; auto.
                ** instantiate (1 := nil); simpl; repeat intro; auto.
                ** econstructor; eauto.
             ++ instantiate (1 := newUml0).
                repeat intro; simpl.
                destruct (string_dec readRegName k); subst; [right | left]; intro.
                ** rewrite in_map_iff in H1; dest.
                   destruct x0; simpl in *; subst.
                   eapply HDisjRegs; eauto.
                ** destruct H1; congruence.
             ++ reflexivity.
             ++ assumption.
          -- econstructor; eauto.
         * assert (Syntax.rfRead rf = Sync false reads) as P0.
           { rewrite <- Heqrf'; reflexivity. }
           rewrite <- Heqrf' in *.
           specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction0); dest.
           exists (Meth (meth, existT SignT (Bit (Nat.log2_up rfIdxNum), Void) (evalExpr e, (zToWord 0 0)))::x); split.
           -- econstructor 5; auto.
              ++ instantiate (1 :=
                                [Upd
                                  (readRegName,
                                   existT (fullType type) (SyntaxKind (Array rfNum rfData))
                                          (evalExpr
                                             (Var type (SyntaxKind (Array rfNum rfData))
                                                  (evalExpr
                                                     (BuildArray
                                                        (fun i0 : Fin.t rfNum =>
                                                           (Var type (SyntaxKind (Array rfIdxNum rfData)) regV @[
                                                                  Var type (SyntaxKind (Bit (Nat.log2_up rfIdxNum))) (evalExpr e) +
                                                                  Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i0))))])%kami_expr))))))]); simpl; repeat intro; auto.
                 econstructor; eauto.
                 ** instantiate (2 := nil).
                    intro; simpl; auto.
                 ** do 2 (econstructor; eauto).
                 ** econstructor; auto.
                    --- instantiate (1 := nil); repeat intro; auto.
                    --- econstructor; eauto.
                 ** simpl; auto.
              ++ instantiate (1 := newUml0).
                 repeat intro; simpl.
                 destruct (string_dec readRegName k); subst; [right | left]; intro.
                 ** rewrite in_map_iff in H1; dest.
                    destruct x0; simpl in *; subst.
                    eapply HDisjRegs; eauto.
                 ** destruct H1; congruence.
              ++ reflexivity.
              ++ assumption.
           -- econstructor; eauto.
        + inv H0; EqDep_subst.
          intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Meth (meth, existT SignT s (evalExpr e, mret))::x); split.
          * econstructor 4; simpl; eauto.
            unfold getSyncReq; destruct isAddr; simpl; auto.
          * econstructor; eauto.
        + inv H0; EqDep_subst.
          intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Meth (meth, existT SignT s (evalExpr e, mret))::x); split.
          * econstructor 3; simpl; eauto.
            unfold getSyncReq; destruct isAddr; simpl; auto.
          * econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemActionCont); dest.
        specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists (x0 ++ x); split; auto.
        apply ESemAction_meth_collector_stitch; auto.
        econstructor.
        + instantiate (1 := x); instantiate (1 := x0).
          intro k0.
          specialize (HDisjRegs k0).
          specialize (ESemActionMC_Upds_SubList H) as P1.
          specialize (ESemActionMC_Upds_SubList H1) as P2.
          clear - P1 P2 HDisjRegs.
          destruct HDisjRegs;[left | right]; intro; apply H; rewrite in_map_iff in *; dest;
            exists x1; split; auto.
        + apply H2.
        + assumption.
        + reflexivity.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists (Upd (r, existT (fullType type) k (evalExpr e))::x); split; auto.
        + econstructor; auto.
          * simpl; assumption.
        + econstructor; auto.
          repeat intro; eapply HDisjRegs.
          apply (ESemActionMC_Upds_SubList H _ H1).
      - inv H0; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea1 _ _ _ _ P0 HIn _ _ _ HEAction); dest.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (x ++ x0); split; auto.
          * apply ESemAction_meth_collector_stitch; auto.
          * econstructor; auto.
            -- intro k0.
               specialize (HDisjRegs k0).
               specialize (ESemActionMC_Upds_SubList H) as P1.
               specialize (ESemActionMC_Upds_SubList H0) as P2.
               clear - P1 P2 HDisjRegs.
               destruct HDisjRegs; [left | right]; intro; apply H; rewrite in_map_iff in *; dest;
                 exists x1; split; auto.
            -- apply H1.
            -- assumption.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea2 _ _ _ _ P0 HIn _ _ _ HEAction); dest.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (x ++ x0); split; auto.
          * apply ESemAction_meth_collector_stitch; auto.
          * econstructor 8; auto.
            -- intro k0.
               specialize (HDisjRegs k0).
               specialize (ESemActionMC_Upds_SubList H) as P1.
               specialize (ESemActionMC_Upds_SubList H0) as P2.
               clear - P1 P2 HDisjRegs.
               destruct HDisjRegs; [left | right]; intro; apply H; rewrite in_map_iff in *; dest;
                 exists x1; split; auto.
            -- apply H1.
            -- assumption.
      - inv H; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        exists nil; split; auto.
        + constructor.
        + econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Upd (dataArray,
                       existT (fullType type) (SyntaxKind (Array idxNum Data))
                              (evalExpr
                                 (fold_left
                                    (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                       (IF ReadArrayConst mask0 i
                                        then newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                                   ReadArrayConst val i] else newArr)%kami_expr) 
                                    (getFins num) (Var type (SyntaxKind (Array idxNum Data)) regV))))::x); split; auto.
          * econstructor; eauto; simpl.
            assumption.
          * econstructor; eauto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P1.
            apply (P1 _ H1).
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Upd (dataArray,
                       existT (fullType type) (SyntaxKind (Array idxNum Data))
                              (evalExpr
                                 (fold_left
                                    (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                       (newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                              ReadArrayConst val i])%kami_expr) (getFins num)
                                    (Var type (SyntaxKind (Array idxNum Data)) regV))))::x); split; auto.
          * econstructor; eauto; simpl.
            assumption.
          * econstructor 13; eauto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P1.
            apply (P1 _ H1).
      - inv H; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr0 reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Upd (readReg,
                       existT (fullType type) (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx)) :: x); split; auto.
          * econstructor; eauto.
            simpl; assumption.
          * econstructor; auto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P1.
            apply (P1 _ H1).
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr0 reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Upd (readReg,
                       existT (fullType type) (SyntaxKind (Array num Data))
                              (evalExpr
                                 (BuildArray
                                    (fun i : Fin.t num =>
                                       (Var type (SyntaxKind (Array idxNum Data)) regV @[
                                              Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx) +
                                              Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))])%kami_expr)))) :: x); split; auto.
          * econstructor; eauto.
            simpl; assumption.
          * econstructor 15; auto.
            -- assumption.
            -- repeat intro.
               eapply HDisjRegs.
               specialize (ESemActionMC_Upds_SubList H) as P1.
               apply (P1 _ H1).
      - inv H0; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr0 reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists x ; split; auto.
          econstructor; eauto.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr0 reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists x ; split; auto.
          econstructor 17; eauto.
    Qed.

    Corollary inlineSyncReq_conguence {k : Kind} (ea1 ea2 : EActionT type k) :
      (forall o uml retv,
          ESemAction o ea1 uml retv ->
          ESemAction o ea2 uml retv) ->
      forall o newUml retv rf (read : SyncRead) (isAddr : bool) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads),
        ESemAction o (inlineSyncReqFile read rf ea1) newUml retv ->
        ESemAction o (inlineSyncReqFile read rf ea2) newUml retv.
    Proof.
      intros.
      specialize (inlineSyncReq_Extension _ _ _ HIsSync HIn H0) as TMP; dest.
      specialize (H _ _ _ H2).
      apply (Extension_inlineSyncReq _ _ HIsSync HIn H H1).
    Qed.

    Lemma SyncReqInline_inlines {k : Kind} (a : ActionT type k) :
      forall rf (read : SyncRead) (isAddr : bool) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads) o uml retv,
        ESemAction o (Action_EAction (inlineSingle (getSyncReq rf isAddr read) a)) uml retv ->
        ESemAction o (inlineSyncReqFile read rf (Action_EAction a)) uml retv.
    Proof.
      induction a; simpl in *; intros rf read; remember rf as rf'; remember read as read';
        destruct rf', read'; intros; simpl in *; rewrite HIsSync in *;
          remember (existsb _ _ ) as exb; symmetry in Heqexb; destruct exb;
            try rewrite existsb_nexists_sync in *; try congruence; revert Heqrf' Heqread' HIsSync.
      - simpl in *; intros; remember (String.eqb _ _) as strb; symmetry in Heqstrb.
        unfold getSyncReq in *; simpl in *; destruct isAddr, strb;
          [simpl in Heqstrb; rewrite Heqstrb in *; destruct Signature_dec
          |rewrite String.eqb_neq in *
          |simpl in Heqstrb; rewrite Heqstrb; destruct Signature_dec
          |simpl in Heqstrb; rewrite Heqstrb in *]; simpl in *.
        + inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          inv HESemAction0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          intros; do 2 (econstructor; auto).
          * instantiate (1 := newUmlCont).
            repeat intro.
            destruct (HDisjRegs readRegName); apply H1; simpl; auto.
            rewrite in_map_iff; exists (readRegName, v); split; auto.
          * reflexivity.
          * eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; eauto.
          eapply H; simpl; eauto.
        + rewrite <- eqb_neq in Heqstrb; rewrite Heqstrb.
          inv H0; EqDep_subst.
          econstructor; auto.
          eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          inv HESemAction0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          inv HESemActionCont0; EqDep_subst.
          inv HESemAction0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          econstructor; eauto.
          econstructor 15; auto.
          * apply HRegVal.
          * instantiate (1 := newUmlCont).
            repeat intro.
            destruct (HDisjRegs readRegName); apply H1; simpl; auto.
            rewrite in_map_iff; exists (readRegName, v); split; auto.
          * reflexivity.
          * eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; auto.
          eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; auto.
          eapply H; simpl; eauto.
      - inv H0; EqDep_subst; econstructor; eapply H; simpl; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
        + eapply IHa; simpl; eauto.
        + eapply H; simpl; eauto.
      - inv H0; EqDep_subst; econstructor; eapply H; simpl; eauto.
      - inv H0; EqDep_subst; econstructor; eauto; eapply H; simpl; eauto.
      - inv H; EqDep_subst; econstructor; eauto; eapply IHa; simpl; eauto.
      - inv H0; EqDep_subst.
        + econstructor; eauto.
          * eapply IHa1; simpl; eauto.
          * eapply H; simpl; eauto.
        + econstructor 8; eauto.
          * eapply IHa2; simpl; eauto.
          * eapply H; simpl; eauto.
      - inv H; EqDep_subst; econstructor; eapply IHa; simpl; eauto.
    Qed.

    Lemma inline_SyncReqInlines {k : Kind} (a : ActionT type k) rf :
      forall (read : SyncRead) (isAddr : bool) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads) o uml retv,
        ESemAction o (inlineSyncReqFile read rf (Action_EAction a)) uml retv ->
        ESemAction o (Action_EAction (inlineSingle (getSyncReq rf isAddr read) a)) uml retv.
    Proof.
      intros read isAddr; induction a; intros; auto; simpl; destruct rf; subst;
        simpl in *; rewrite HIsSync in *; unfold getSyncReq in *; destruct read;
          remember (existsb _ _ ) as exb; symmetry in Heqexb; destruct exb;
            try rewrite existsb_nexists_sync in *; try congruence.
      - simpl in *; intros; remember (String.eqb _ _) as strb; symmetry in Heqstrb.
        destruct isAddr, strb; simpl in *; rewrite Heqstrb;
        [destruct Signature_dec | | destruct Signature_dec| ]; simpl in *.
        + inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst; [ |discriminate].
          * econstructor; auto.
            -- instantiate (1 := newUml).
               instantiate (1 := [Upd
                                    (readRegName,
                                     existT (fullType type) (SyntaxKind (Bit (Nat.log2_up rfIdxNum)))
                                            (evalExpr (Var type (SyntaxKind (Bit (Nat.log2_up rfIdxNum))) (evalExpr e))))]).
               intro; simpl.
               destruct (string_dec readRegName k); subst; [right |left ]; intro.
               ++ rewrite in_map_iff in H0; dest; destruct x; subst.
                  eapply HDisjRegs; eauto.
               ++ destruct H0; auto.
            -- repeat econstructor; eauto.
               repeat intro; auto.
            -- eapply H; eauto.
            -- reflexivity.
        + inv H0; EqDep_subst.
          econstructor; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; simpl; eauto.
        + inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst; [discriminate| ].
          * econstructor; auto.
            -- instantiate (1 := newUml).
               instantiate (1 :=
                              [Upd
                                 (readRegName,
                                  existT (fullType type) (SyntaxKind (Array rfNum rfData))
                                         (evalExpr
                                            (Var type (SyntaxKind (Array rfNum rfData))
                                                 (evalExpr
                                                    (BuildArray
                                                       (fun i0 : Fin.t rfNum =>
                                                          (Var type (SyntaxKind (Array rfIdxNum rfData)) regV @[
                                                                 Var type (SyntaxKind (Bit (Nat.log2_up rfIdxNum))) (evalExpr e) +
                                                                 Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i0))))])%kami_expr))))))]).
               intro; simpl.
               destruct (string_dec readRegName k); subst; [right |left ]; intro.
               ++ rewrite in_map_iff in H0; dest; destruct x; subst.
                  eapply HDisjRegs; eauto.
               ++ destruct H0; auto.
            -- repeat econstructor; eauto.
               repeat intro; auto.
            -- eapply H; eauto.
            -- reflexivity.
        + inv H0; EqDep_subst.
          econstructor; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; simpl; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        ++ econstructor; eauto.
        ++ econstructor 8; eauto.
      - inv H; EqDep_subst.
        econstructor; eauto.
    Qed.

  End SyncReqInline.

    Section SyncResInline.
    
    Lemma Extension_inlineSyncRes {k : Kind} (ea : EActionT type k) :
      forall rf (isAddr : bool) (read : SyncRead) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads) o uml retv,
        ESemAction o ea uml retv ->
        forall newUml,
          ESemAction_meth_collector (getSyncRes rf isAddr read) o uml newUml ->
          ESemAction o (inlineSyncResFile read rf ea) newUml retv.
    Proof.
      destruct rf; simpl in *; destruct rfRead;[intros; discriminate|].
      induction ea; simpl; intros; inv HIsSync; remember (existsb _ _ ) as exb;
        symmetry in Heqexb; destruct exb; try rewrite existsb_nexists_sync in *;
          try congruence; destruct read.
      - inv H0; EqDep_subst.
        inv H1;[discriminate | | | ]; remember (String.eqb _ _ ) as strb;
          symmetry in Heqstrb; destruct strb; try rewrite String.eqb_eq in *;
            try rewrite String.eqb_neq in *; inv HUmlCons;
          try (destruct Signature_dec); subst; unfold getSyncReq in *; destruct isAddr0; 
            try (simpl in *; congruence); EqDep_subst.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + econstructor; eauto.
        + rewrite (Eqdep.EqdepTheory.UIP_refl _ _ e0) in *.
          autorewrite with _word_zero in *; inv HESemAction0; EqDep_subst.
          autorewrite with _word_zero in *; inv HESemAction1; EqDep_subst.
          autorewrite with _word_zero in *; inv HESemAction0; EqDep_subst.
          econstructor; eauto.
        + rewrite (Eqdep.EqdepTheory.UIP_refl _ _ e0) in *.
          autorewrite with _word_zero in *; inv HESemAction0; EqDep_subst.
          autorewrite with _word_zero in *; inv HESemAction1; EqDep_subst.
          econstructor 17; simpl in *; eauto.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; simpl in *; EqDep_subst.
        + specialize (ESemAction_meth_collector_break _ _ H1) as TMP; dest.
          econstructor.
          * instantiate (1 := x0); instantiate (1 := x); auto.
          * eapply IHea; eauto.
          * eapply H; eauto.
          * assumption.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      -inv H; simpl in *; EqDep_subst.
       inv H0; [ | discriminate | discriminate | discriminate].
       inv HUmlCons; econstructor; auto.
       + simpl in *; auto.
       + eapply IHea; eauto.
      - inv H0; simpl in *; EqDep_subst; specialize (ESemAction_meth_collector_break _ _ H1) as TMP; dest.
        + econstructor; eauto.
        + econstructor 8; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst; econstructor; eauto.
        inv H0; auto; discriminate.
      - inv H0; simpl in *; EqDep_subst; econstructor; eauto.
      - inv H; simpl in *; EqDep_subst.
        + inv H0; inv HUmlCons.
          econstructor; eauto.
        + inv H0; inv HUmlCons.
          econstructor 13; eauto.
      - inv H; simpl in *; EqDep_subst.
        + inv H0; inv HUmlCons.
          econstructor; auto.
          * simpl in *; eauto.
          * eapply IHea; eauto.
        + inv H0; inv HUmlCons.
          econstructor 15; auto.
          * apply HRegVal2.
          * instantiate (1 := newUml1).
            simpl in *; eauto.
          * reflexivity.
          * eapply IHea; eauto.
      - inv H0; simpl in *; EqDep_subst.
        + econstructor; eauto.
        + econstructor 17; eauto.
    Qed.

    Lemma inlineSyncRes_Extension {k : Kind} (ea : EActionT type k):
      forall rf (read : SyncRead) (isAddr : bool) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads) o newUml retv,
        ESemAction o (inlineSyncResFile read rf ea) newUml retv ->
        exists uml,
          ESemAction_meth_collector (getSyncRes rf isAddr read) o uml newUml /\
          ESemAction o ea uml retv.
    Proof.
      induction ea; simpl in *; intros rf read; remember rf as rf'; remember read as read';
        destruct rf', read'; intros; simpl in *; rewrite HIsSync in *;
          remember (existsb _ _ ) as exb; symmetry in Heqexb; destruct exb;
            try rewrite existsb_nexists_sync in *; try congruence; revert Heqrf' Heqread' HIsSync.
      - remember (String.eqb _ _) as strb; symmetry in Heqstrb; destruct strb;
          [rewrite String.eqb_eq in *; subst; destruct Signature_dec
          |rewrite String.eqb_neq in *].
        +inv H0; EqDep_subst; intros.
         * assert (Syntax.rfRead rf = Sync true reads) as P0.
           { rewrite <- Heqrf'; reflexivity. }
           rewrite <- Heqrf' in *.
           specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
           exists ( Meth (meth, existT SignT (Void, Array rfNum rfData) ((zToWord 0 0), (evalExpr
               (BuildArray
                  (fun i : Fin.t rfNum =>
                   (Var type (SyntaxKind (Array rfIdxNum rfData)) regVal @[
                    Var type (SyntaxKind (Bit (Nat.log2_up rfIdxNum))) idx +
                    Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))])%kami_expr)))))::x); split.
          -- econstructor 5; auto.
             ++ simpl; repeat econstructor; eauto.
             ++ intro; left; intro; auto.
             ++ simpl; reflexivity.
             ++ assumption.
          -- econstructor; eauto.
             rewrite (unifyWO (evalExpr e)); simpl; reflexivity.
         * assert (Syntax.rfRead rf = Sync false reads) as P0.
           { rewrite <- Heqrf'; reflexivity. }
           rewrite <- Heqrf' in *.
           specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
           exists (Meth (meth, existT SignT (Void, Array rfNum rfData) ((zToWord 0 0), regVal))::x); split.
           -- econstructor 5; auto.
              ++ simpl; repeat econstructor; eauto.
              ++ intro; left; intro; auto.
              ++ simpl; reflexivity.
              ++ assumption.
           -- econstructor; eauto.
             rewrite (unifyWO (evalExpr e)); simpl; reflexivity.
        + inv H0; EqDep_subst.
          intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Meth (meth, existT SignT s (evalExpr e, mret))::x); split.
          * econstructor 4; simpl; eauto.
            unfold getSyncRes; destruct isAddr; simpl; auto.
          * econstructor; eauto.
        + inv H0; EqDep_subst.
          intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Meth (meth, existT SignT s (evalExpr e, mret))::x); split.
          * econstructor 3; simpl; eauto.
            unfold getSyncRes; destruct isAddr; simpl; auto.
          * econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemActionCont); dest.
        specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists (x0 ++ x); split; auto.
        apply ESemAction_meth_collector_stitch; auto.
        econstructor.
        + instantiate (1 := x); instantiate (1 := x0).
          intro k0.
          specialize (HDisjRegs k0).
          specialize (ESemActionMC_Upds_SubList H) as P1.
          specialize (ESemActionMC_Upds_SubList H1) as P2.
          clear - P1 P2 HDisjRegs.
          destruct HDisjRegs;[left | right]; intro; apply H; rewrite in_map_iff in *; dest;
            exists x1; split; auto.
        + apply H2.
        + assumption.
        + reflexivity.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists (Upd (r, existT (fullType type) k (evalExpr e))::x); split; auto.
        + econstructor; auto.
          * simpl; assumption.
        + econstructor; auto.
          repeat intro; eapply HDisjRegs.
          apply (ESemActionMC_Upds_SubList H _ H1).
      - inv H0; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea1 _ _ _ _ P0 HIn _ _ _ HEAction); dest.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (x ++ x0); split; auto.
          * apply ESemAction_meth_collector_stitch; auto.
          * econstructor; auto.
            -- intro k0.
               specialize (HDisjRegs k0).
               specialize (ESemActionMC_Upds_SubList H) as P1.
               specialize (ESemActionMC_Upds_SubList H0) as P2.
               clear - P1 P2 HDisjRegs.
               destruct HDisjRegs; [left | right]; intro; apply H; rewrite in_map_iff in *; dest;
                 exists x1; split; auto.
            -- apply H1.
            -- assumption.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea2 _ _ _ _ P0 HIn _ _ _ HEAction); dest.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (x ++ x0); split; auto.
          * apply ESemAction_meth_collector_stitch; auto.
          * econstructor 8; auto.
            -- intro k0.
               specialize (HDisjRegs k0).
               specialize (ESemActionMC_Upds_SubList H) as P1.
               specialize (ESemActionMC_Upds_SubList H0) as P2.
               clear - P1 P2 HDisjRegs.
               destruct HDisjRegs; [left | right]; intro; apply H; rewrite in_map_iff in *; dest;
                 exists x1; split; auto.
            -- apply H1.
            -- assumption.
      - inv H; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        exists nil; split; auto.
        + constructor.
        + econstructor; eauto.
      - inv H0; EqDep_subst.
        intros.
        assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
        { rewrite <- Heqrf'; reflexivity. }
        rewrite <- Heqrf' in *.
        specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
        exists x; split; auto.
        econstructor; eauto.
      - inv H; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Upd (dataArray,
                       existT (fullType type) (SyntaxKind (Array idxNum Data))
                              (evalExpr
                                 (fold_left
                                    (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                       (IF ReadArrayConst mask0 i
                                        then newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                                   ReadArrayConst val i] else newArr)%kami_expr) 
                                    (getFins num) (Var type (SyntaxKind (Array idxNum Data)) regV))))::x); split; auto.
          * econstructor; eauto; simpl.
            assumption.
          * econstructor; eauto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P1.
            apply (P1 _ H1).
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Upd (dataArray,
                       existT (fullType type) (SyntaxKind (Array idxNum Data))
                              (evalExpr
                                 (fold_left
                                    (fun (newArr : Expr type (SyntaxKind (Array idxNum Data))) (i : Fin.t num) =>
                                       (newArr @[ idx + Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i)))) <-
                                                              ReadArrayConst val i])%kami_expr) (getFins num)
                                    (Var type (SyntaxKind (Array idxNum Data)) regV))))::x); split; auto.
          * econstructor; eauto; simpl.
            assumption.
          * econstructor 13; eauto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P1.
            apply (P1 _ H1).
      - inv H; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr0 reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Upd (readReg,
                       existT (fullType type) (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx)) :: x); split; auto.
          * econstructor; eauto.
            simpl; assumption.
          * econstructor; auto.
            repeat intro.
            eapply HDisjRegs.
            specialize (ESemActionMC_Upds_SubList H) as P1.
            apply (P1 _ H1).
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr0 reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (IHea _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists (Upd (readReg,
                       existT (fullType type) (SyntaxKind (Array num Data))
                              (evalExpr
                                 (BuildArray
                                    (fun i : Fin.t num =>
                                       (Var type (SyntaxKind (Array idxNum Data)) regV @[
                                              Var type (SyntaxKind (Bit (Nat.log2_up idxNum))) (evalExpr idx) +
                                              Const type (zToWord _ (Z.of_nat (proj1_sig (Fin.to_nat i))))])%kami_expr)))) :: x); split; auto.
          * econstructor; eauto.
            simpl; assumption.
          * econstructor 15; auto.
            -- assumption.
            -- repeat intro.
               eapply HDisjRegs.
               specialize (ESemActionMC_Upds_SubList H) as P1.
               apply (P1 _ H1).
      - inv H0; EqDep_subst.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr0 reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists x ; split; auto.
          econstructor; eauto.
        + intros.
          assert (Syntax.rfRead rf = Sync isAddr0 reads) as P0.
          { rewrite <- Heqrf'; reflexivity. }
          rewrite <- Heqrf' in *.
          specialize (H _ _ _ _ _ P0 HIn _ _ _ HESemAction); dest.
          exists x ; split; auto.
          econstructor 17; eauto.
    Qed.

    Corollary inlineSyncRes_conguence {k : Kind} (ea1 ea2 : EActionT type k) :
      (forall o uml retv,
          ESemAction o ea1 uml retv ->
          ESemAction o ea2 uml retv) ->
      forall o newUml retv rf (read : SyncRead) (isAddr : bool) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads),
        ESemAction o (inlineSyncResFile read rf ea1) newUml retv ->
        ESemAction o (inlineSyncResFile read rf ea2) newUml retv.
    Proof.
      intros.
      specialize (inlineSyncRes_Extension _ _ _ HIsSync HIn H0) as TMP; dest.
      specialize (H _ _ _ H2).
      apply (Extension_inlineSyncRes _ _ HIsSync HIn H H1).
    Qed.

    Lemma SyncResInline_inlines {k : Kind} (a : ActionT type k) :
      forall rf (read : SyncRead) (isAddr : bool) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads) o uml retv,
        ESemAction o (Action_EAction (inlineSingle (getSyncRes rf isAddr read) a)) uml retv ->
        ESemAction o (inlineSyncResFile read rf (Action_EAction a)) uml retv.
    Proof.
      induction a; simpl in *; intros rf read; remember rf as rf'; remember read as read';
        destruct rf', read'; intros; simpl in *; rewrite HIsSync in *;
          remember (existsb _ _ ) as exb; symmetry in Heqexb; destruct exb;
            try rewrite existsb_nexists_sync in *; try congruence; revert Heqrf' Heqread' HIsSync.
      - simpl in *; intros; remember (String.eqb _ _) as strb; symmetry in Heqstrb.
        unfold getSyncReq in *; simpl in *; destruct isAddr, strb; simpl in *; rewrite Heqstrb;
          [destruct Signature_dec | |destruct Signature_dec| ].
        + inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          inv HESemAction0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          inv HESemAction0; EqDep_subst.
          econstructor; eauto.
          eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; eauto.
          eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; auto.
          eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          inv HESemAction0; EqDep_subst.
          inv HESemAction; EqDep_subst.
          econstructor 17; eauto.
          eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; auto.
          eapply H; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; auto.
          eapply H; simpl; eauto.
      - inv H0; EqDep_subst; econstructor; eapply H; simpl; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
        + eapply IHa; simpl; eauto.
        + eapply H; simpl; eauto.
      - inv H0; EqDep_subst; econstructor; eapply H; simpl; eauto.
      - inv H0; EqDep_subst; econstructor; eauto; eapply H; simpl; eauto.
      - inv H; EqDep_subst; econstructor; eauto; eapply IHa; simpl; eauto.
      - inv H0; EqDep_subst.
        + econstructor; eauto.
          * eapply IHa1; simpl; eauto.
          * eapply H; simpl; eauto.
        + econstructor 8; eauto.
          * eapply IHa2; simpl; eauto.
          * eapply H; simpl; eauto.
      - inv H; EqDep_subst; econstructor; eapply IHa; simpl; eauto.
    Qed.

    Lemma inline_SyncResInlines {k : Kind} (a : ActionT type k) rf :
      forall (read : SyncRead) (isAddr : bool) (reads : list SyncRead)
             (HIsSync : rfRead rf = Sync isAddr reads)
             (HIn : In read reads) o uml retv,
        ESemAction o (inlineSyncResFile read rf (Action_EAction a)) uml retv ->
        ESemAction o (Action_EAction (inlineSingle (getSyncRes rf isAddr read) a)) uml retv.
    Proof.
      intros read isAddr; induction a; intros; auto; simpl; destruct rf; subst;
        simpl in *; rewrite HIsSync in *; unfold getSyncReq in *; destruct read;
          remember (existsb _ _ ) as exb; symmetry in Heqexb; destruct exb;
            try rewrite existsb_nexists_sync in *; try congruence.
      - simpl in *; intros; remember (String.eqb _ _) as strb; symmetry in Heqstrb.
        destruct isAddr, strb; simpl in *; rewrite Heqstrb;
        [destruct Signature_dec | | destruct Signature_dec| ]; simpl in *.
        + inv H0; EqDep_subst; [ |discriminate].
          * econstructor; auto.
            -- instantiate (2 := nil).
               intro; auto.
            -- repeat econstructor; eauto.
            -- eapply H; eauto.
            -- reflexivity.
        + inv H0; EqDep_subst.
          econstructor; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; simpl; eauto.
        + inv H0; EqDep_subst; [discriminate| ].
          * econstructor; auto.
            -- instantiate (2 := nil).
               intro; auto.
            -- repeat econstructor; eauto.
            -- eapply H; eauto.
            -- reflexivity.
        + inv H0; EqDep_subst.
          econstructor; simpl; eauto.
        + inv H0; EqDep_subst.
          econstructor; simpl; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        econstructor; eauto.
      - inv H; EqDep_subst.
        econstructor; eauto.
      - inv H0; EqDep_subst.
        ++ econstructor; eauto.
        ++ econstructor 8; eauto.
      - inv H; EqDep_subst.
        econstructor; eauto.
    Qed.

    End SyncResInline.
      
End Properties.

