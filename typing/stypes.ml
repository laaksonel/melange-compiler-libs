(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*          Damien Doligez, projet Moscova, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 2003 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* Recording and dumping (partial) type information *)

(*
  We record all types in a list as they are created.
  This means we can dump type information even if type inference fails,
  which is extremely important, since type information is most
  interesting in case of errors.
*)

open Annot;;
open Lexing;;
open Location;;
open Typedtree;;

let output_int oc i = output_string oc (string_of_int i)

type annotation =
  | Ti_pat   of pattern
  | Ti_expr  of expression
  | Ti_class of class_expr
  | Ti_mod   of module_expr
  | An_call of Location.t * Annot.call
  | An_ident of Location.t * string * Annot.ident
;;

let get_location ti =
  match ti with
    Ti_pat p   -> p.pat_loc
  | Ti_expr e  -> e.exp_loc
  | Ti_class c -> c.cl_loc
  | Ti_mod m   -> m.mod_loc
  | An_call (l, k) -> l
  | An_ident (l, s, k) -> l
;;

let annotations = ref ([] : annotation list);;
let phrases = ref ([] : Location.t list);;

let record ti =
  if !Clflags.annotations && not (get_location ti).Location.loc_ghost then
    annotations := ti :: !annotations
;;

let record_phrase loc =
  if !Clflags.annotations then phrases := loc :: !phrases;
;;

(* comparison order:
   the intervals are sorted by order of increasing upper bound
   same upper bound -> sorted by decreasing lower bound
*)
let cmp_loc_inner_first loc1 loc2 =
  match compare loc1.loc_end.pos_cnum loc2.loc_end.pos_cnum with
  | 0 -> compare loc2.loc_start.pos_cnum loc1.loc_start.pos_cnum
  | x -> x
;;
let cmp_ti_inner_first ti1 ti2 =
  cmp_loc_inner_first (get_location ti1) (get_location ti2)
;;

let print_position pp pos =
  if pos = dummy_pos then
    output_string pp "--"
  else begin
    output_char pp '\"';
    output_string pp (String.escaped pos.pos_fname);
    output_string pp "\" ";
    output_int pp pos.pos_lnum;
    output_char pp ' ';
    output_int pp pos.pos_bol;
    output_char pp ' ';
    output_int pp pos.pos_cnum;
  end
;;

let print_location pp loc =
  print_position pp loc.loc_start;
  output_char pp ' ';
  print_position pp loc.loc_end;
;;

let sort_filter_phrases () =
  let ph = List.sort (fun x y -> cmp_loc_inner_first y x) !phrases in
  let rec loop accu cur l =
    match l with
    | [] -> accu
    | loc :: t ->
       if cur.loc_start.pos_cnum <= loc.loc_start.pos_cnum
          && cur.loc_end.pos_cnum >= loc.loc_end.pos_cnum
       then loop accu cur t
       else loop (loc :: accu) loc t
  in
  phrases := loop [] Location.none ph;
;;

let rec printtyp_reset_maybe loc =
  match !phrases with
  | cur :: t when cur.loc_start.pos_cnum <= loc.loc_start.pos_cnum ->
     Printtyp.reset ();
     phrases := t;
     printtyp_reset_maybe loc;
  | _ -> ()
;;

let call_kind_string k =
  match k with
  | Tail -> "tail"
  | Stack -> "stack"
  | Inline -> "inline"
;;

let print_ident_annot pp str k =
  match k with
  | Idef l ->
      output_string pp "def ";
      output_string pp str;
      output_char pp ' ';
      print_location pp l;
      output_char pp '\n'
  | Iref_internal l ->
      output_string pp "int_ref ";
      output_string pp str;
      output_char pp ' ';
      print_location pp l;
      output_char pp '\n'
  | Iref_external ->
      output_string pp "ext_ref ";
      output_string pp str;
      output_char pp '\n'
;;

(* The format of the annotation file is documented in emacs/caml-types.el. *)

let print_info pp ppf prev_loc ti =
  match ti with
  | Ti_class _ | Ti_mod _ -> prev_loc
  | Ti_pat  {pat_loc = loc; pat_type = typ}
  | Ti_expr {exp_loc = loc; exp_type = typ} ->
      if loc <> prev_loc then begin
        print_location pp loc;
        output_char pp '\n'
      end;
      output_string pp "type(\n";
      flush pp;
      printtyp_reset_maybe loc;
      Printtyp.mark_loops typ;
      Format.pp_print_string ppf "  ";
      Printtyp.type_sch ppf typ;
      Format.pp_print_newline ppf ();
      output_string pp ")\n";
      loc
  | An_call (loc, k) ->
      if loc <> prev_loc then begin
        print_location pp loc;
        output_char pp '\n'
      end;
      output_string pp "call(\n  ";
      output_string pp (call_kind_string k);
      output_string pp "\n)\n";
      loc
  | An_ident (loc, str, k) ->
      if loc <> prev_loc then begin
        print_location pp loc;
        output_char pp '\n'
      end;
      output_string pp "ident(\n  ";
      print_ident_annot pp str k;
      output_string pp ")\n";
      loc
;;

let get_info () =
  let info = List.fast_sort cmp_ti_inner_first !annotations in
  annotations := [];
  info
;;

let dump filename =
  if !Clflags.annotations then begin
    let info = get_info () in
    let pp =
      match filename with
          None -> stdout
        | Some filename -> open_out filename in
    let ppf = Format.formatter_of_out_channel pp in
    sort_filter_phrases ();
    ignore (List.fold_left (print_info pp ppf) Location.none info);
    phrases := [];
  end else begin
    annotations := [];
  end;
;;
