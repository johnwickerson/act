(*
This file is part of 'act'.

Copyright (c) 2018 by Matt Windsor
   (parts (c) 2010-2018 Institut National de Recherche en Informatique et
	                en Automatique, Jade Alglave, and Luc Maranget)

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

This file derives from the Herd7 project
(https://github.com/herd/herdtools7); its original attribution and
copyright notice follow. *)

(****************************************************************************)
(*                           the diy toolsuite                              *)
(*                                                                          *)
(* Jade Alglave, University College London, UK.                             *)
(* Luc Maranget, INRIA Paris-Rocquencourt, France.                          *)
(*                                                                          *)
(* Copyright 2010-present Institut National de Recherche en Informatique et *)
(* en Automatique and the authors. All rights reserved.                     *)
(*                                                                          *)
(* This software is governed by the CeCILL-B license under French law and   *)
(* abiding by the rules of distribution of free software. You can use,      *)
(* modify and/ or redistribute the software under the terms of the CeCILL-B *)
(* license as circulated by CEA, CNRS and INRIA at the following URL        *)
(* "http://www.cecill.info". We also give a copy in LICENSE.txt.            *)
(****************************************************************************)

open Core
open Utils
open Ast

let disp_positive =
  function
  | None -> false
  | Some (Disp.Numeric k) -> 0 < k
  | _ -> true

module type Dialect = sig
  val pp_reg : Format.formatter -> Reg.t -> unit
  val pp_indirect : Format.formatter -> Indirect.t -> unit
  val pp_immediate : Format.formatter -> Disp.t -> unit
  val pp_comment
    :  pp:(Format.formatter -> 'a -> unit)
    -> Format.formatter
    -> 'a
    -> unit
end

module type Printer = sig
  include Dialect

  val pp_location : Format.formatter -> Location.t -> unit
  val pp_bop : Format.formatter -> Operand.bop -> unit
  val pp_operand : Format.formatter -> Operand.t -> unit
  val pp_prefix : Format.formatter -> prefix -> unit
  val pp_opcode : Format.formatter -> Opcode.t -> unit
  val pp_instruction : Format.formatter -> Instruction.t -> unit
  val pp_statement : Format.formatter -> Statement.t -> unit
end

(* Parts specific to all dialects *)
module Basic = struct
    (*
     * Displacements
     *)

  let pp_disp ?(show_zero = true) f =
    function
    | Disp.Symbolic s -> Format.pp_print_string f s
    | Disp.Numeric  0 when not show_zero -> ()
    | Disp.Numeric  k -> Format.pp_print_int    f k
end

(* Parts specific to AT&T *)
module Att_specific = struct
  let pp_comment ~pp f = Format.fprintf f "@[<h># %a@]" pp

  let%expect_test "pp_comment: AT&T" =
    Format.printf "%a@."
      (pp_comment ~pp:String.pp) "AT&T comment";
    [%expect {| # AT&T comment |}]

  let pp_reg f reg =
    Format.fprintf f "@[%%%s@]" (Reg.to_string reg)

  let%expect_test "pp_reg: AT&T, ESP" =
    Format.printf "%a@." pp_reg ESP;
    [%expect {| %ESP |}]

  let pp_index f = function
    | Index.Unscaled r -> pp_reg f r
    | Scaled (r, i) -> Format.fprintf f "%a,@ %d"
                         pp_reg r
                         i

  let pp_indirect f indirect =
    let pp_seg f = Format.fprintf f "%a:" pp_reg in

    let pp_bis f bo iso =
      match bo, iso with
      | None  , None -> ()
      | Some b, None ->
        Format.fprintf f "(%a)"
          pp_reg b
      | _     , Some i ->
        Format.fprintf f "(%a,%a)"
          (My_format.pp_option ~pp:pp_reg) bo
          pp_index i
    in

    let in_seg   = Indirect.seg   indirect in
    let in_base  = Indirect.base  indirect in
    let in_disp  = Indirect.disp  indirect in
    let in_index = Indirect.index indirect in

    My_format.pp_option f ~pp:pp_seg in_seg;
    let show_zero = in_base = None && in_index = None in
    My_format.pp_option f ~pp:(Basic.pp_disp ~show_zero) in_disp;
    pp_bis f in_base in_index

  let%expect_test "pp_indirect: AT&T, +ve numeric displacement only" =
    Format.printf "%a@." pp_indirect
      (Indirect.make
         ~disp:(Disp.Numeric 2001)
         ());
    [%expect {| 2001 |}]

  let%expect_test "pp_indirect: AT&T, +ve disp and base" =
    Format.printf "%a@." pp_indirect
      (Indirect.make
         ~disp:(Disp.Numeric 76)
         ~base:EAX
         ());
    [%expect {| 76(%EAX) |}]

  let%expect_test "pp_indirect: AT&T, zero disp only" =
    Format.printf "%a@." pp_indirect
      (Indirect.make
         ~disp:(Disp.Numeric 0)
         ());
    [%expect {| 0 |}]

  let%expect_test "pp_indirect: AT&T, -ve disp and base" =
    Format.printf "%a@." pp_indirect
      (Indirect.make
         ~disp:(Disp.Numeric (-42))
         ~base:ECX
         ());
    [%expect {| -42(%ECX) |}]

  let%expect_test "pp_indirect: AT&T, base only" =
    Format.printf "%a@." pp_indirect
      (Indirect.make
         ~base:EDX
         ());
    [%expect {| (%EDX) |}]

  let%expect_test "pp_indirect: AT&T, zero disp and base" =
    Format.printf "%a@." pp_indirect
      (Indirect.make
         ~disp:(Disp.Numeric 0)
         ~base:EDX
         ());
    [%expect {| (%EDX) |}]

  let pp_immediate f = Format.fprintf f "@[$%a@]"
      (Basic.pp_disp ~show_zero:true)

  let%expect_test "pp_immediate: AT&T, positive number" =
    Format.printf "%a@." pp_immediate (Disp.Numeric 24);
    [%expect {| $24 |}]

  let%expect_test "pp_immediate: AT&T, zero" =
    Format.printf "%a@." pp_immediate (Disp.Numeric 0);
    [%expect {| $0 |}]

  let%expect_test "pp_immediate: AT&T, negative number" =
    Format.printf "%a@." pp_immediate (Disp.Numeric (-42));
    [%expect {| $-42 |}]


  let%expect_test "pp_immediate: AT&T, symbolic" =
    Format.printf "%a@." pp_immediate (Disp.Symbolic "kappa");
    [%expect {| $kappa |}]
end

(** Parts specific to Intel *)
module Intel_specific = struct
  let pp_comment ~pp f = Format.fprintf f "@[<h>; %a@]" pp

  let%expect_test "pp_comment: Intel" =
    Format.printf "%a@."
      (pp_comment ~pp:String.pp) "intel comment";
    [%expect {| ; intel comment |}]
end

(** Parts specific to Herd7 *)
module Herd7_specific = struct
  let pp_comment ~pp f = Format.fprintf f "@[<h>// %a@]" pp

  let%expect_test "pp_comment: Herd7" =
    Format.printf "%a@."
      (pp_comment ~pp:String.pp) "herd comment";
    [%expect {| // herd comment |}]
end

(** Parts common to Intel and Herd7 *)
module Intel_and_herd7 = struct
    let pp_reg f reg = String.pp f (Reg.to_string reg)

    let%expect_test "pp_reg: intel, EAX" =
      Format.printf "%a@." pp_reg EAX;
      [%expect {| EAX |}]

    let pp_index f =
      function
      | Index.Unscaled r -> pp_reg f r
      | Scaled (r, i) -> Format.fprintf f "%a*%d"
                                        pp_reg r
                                        i

    let pp_indirect f indirect =
      let pp_seg f = Format.fprintf f "%a:" pp_reg in

      Format.pp_open_box f 0;
      Format.pp_print_char f '[';

      let in_seg   = Indirect.seg   indirect in
      let in_base  = Indirect.base  indirect in
      let in_disp  = Indirect.disp  indirect in
      let in_index = Indirect.index indirect in

      (* seg:base+index*scale+disp *)

      My_format.pp_option f ~pp:pp_seg in_seg;

      My_format.pp_option f ~pp:pp_reg in_base;

      let plus_between_b_i = in_base <> None && in_index <> None in
      if plus_between_b_i then Format.pp_print_char f '+';

      My_format.pp_option f ~pp:pp_index in_index;

      let plus_between_bis_d =
        (in_base <> None || in_index <> None)
        && disp_positive in_disp
      in
      if plus_between_bis_d then Format.pp_print_char f '+';

      let show_zero = in_base = None && in_index = None in
      My_format.pp_option f ~pp:(Basic.pp_disp ~show_zero) in_disp;

      Format.pp_print_char f ']';
      Format.pp_close_box f ()

    let%expect_test "pp_indirect: intel, +ve numeric displacement only" =
      Format.printf "%a@." pp_indirect
        (Indirect.make ~disp:(Disp.Numeric 2001) ());
      [%expect {| [2001] |}]

    let%expect_test "pp_indirect: Intel, +ve disp and base" =
      Format.printf "%a@." pp_indirect
        (Indirect.make
           ~disp:(Disp.Numeric 76)
           ~base:EAX
           ());
      [%expect {| [EAX+76] |}]


    let%expect_test "pp_indirect: Intel, zero disp only" =
      Format.printf "%a@." pp_indirect
        (Indirect.make ~disp:(Disp.Numeric 0) ());
      [%expect {| [0] |}]


    let%expect_test "pp_indirect: Intel, +ve disp and base" =
      Format.printf "%a@." pp_indirect
        (Indirect.make
           ~disp:(Disp.Numeric (-42))
           ~base:ECX
           ());
      [%expect {| [ECX-42] |}]

    let%expect_test "pp_indirect: Intel, base only" =
      Format.printf "%a@." pp_indirect
        (Indirect.make
           ~base:EDX
           ());
      [%expect {| [EDX] |}]

    let%expect_test "pp_indirect: Intel, zero disp and base" =
      Format.printf "%a@." pp_indirect
        (Indirect.make
           ~disp:(Disp.Numeric 0)
           ~base:EDX
           ());
      [%expect {| [EDX] |}]

    let pp_immediate = (Basic.pp_disp ~show_zero:true)
  end

module Make (D : Dialect) =
  struct
    include Basic
    include D

    (*
     * Operators
     *)

    let pp_bop f = function
      | Operand.BopPlus -> Format.pp_print_char f '+'
      | BopMinus -> Format.pp_print_char f '-'

    (*
     * Operands
     *)

    let string_escape =
      String.Escaping.escape_gen_exn
        ~escape_char:'\\'
        ~escapeworthy_map:[ '\x00', '0'
                          ; '"', '"'
                          ; '\\', '\\'
                          ]

    let pp_location f =
      function
      | Location.Indirect i -> pp_indirect f i
      | Reg r -> pp_reg f r

    let rec pp_operand f = function
      | Operand.Location l -> pp_location f l;
      | Operand.Immediate d -> pp_immediate f d;
      | Operand.String s ->
         Format.fprintf f "\"%s\"" (Staged.unstage string_escape s)
      | Operand.Typ ty ->
         Format.fprintf f "@@%s" ty
      | Operand.Bop (l, b, r) ->
         Format.pp_open_box f 0;
         pp_operand f l;
         pp_bop f b;
         pp_operand f r;
         Format.pp_close_box f ()

    let pp_comma f =
      Format.pp_print_char f ',';
      Format.pp_print_space f

    let pp_oplist =
      Format.pp_print_list ~pp_sep:pp_comma
                           pp_operand

    (*
     * Prefixes
     *)

    let prefix_string = function
      | PreLock -> "lock"

    let pp_prefix f p =
      Format.pp_print_string f (prefix_string p);
      Format.pp_print_space f ()

    (*
     * Opcodes
     *)

    let pp_opcode f = function
      | Opcode.Directive s -> Format.fprintf f ".%s" s
      | Unknown s -> String.pp f s
      | Basic opc ->
         opc
         |> Opcode.Basic.to_string
         |> Option.value ~default:"<FIXME: OPCODE WITH NO STRING EQUIVALENT>"
         |> String.pp f
      | Jump opc ->
         opc
         |> Opcode.Jump.to_string
         |> Option.value ~default:"<FIXME: JUMP WITH NO STRING EQUIVALENT>"
         |> String.pp f
      | Sized opc ->
         (* TODO: Intel syntax *)
        opc
         |> Opcode.Sized.to_string
         |> Option.value ~default:"<FIXME: JUMP WITH NO STRING EQUIVALENT>"
         |> String.pp f

    (*
     * Instructions
     *)

    let pp_instruction f { Instruction.prefix; opcode; operands } =
      Format.fprintf f
                     "@[@[%a%a@]@ %a@]"
                     (My_format.pp_option ~pp:pp_prefix) prefix
                     pp_opcode opcode
                     pp_oplist operands

    (*
     * Statements
     *)

    let pp_statement f = function
      | Statement.Instruction i -> pp_instruction f i; Format.pp_print_cut f ()
      | Label l -> Format.fprintf f "@[%s:@ @]" l
      | Nop ->
         (* This blank space is deliberate, to make tabstops move across
        properly in litmus printing. *)
         Format.fprintf f " "; Format.pp_print_cut f ()
  end

module Att = Make (Att_specific)

let%expect_test "pp_opcode: directive" =
  Format.printf "%a@." Att.pp_opcode (Opcode.Directive "text");
  [%expect {| .text |}]

let%expect_test "pp_opcode: jmp" =
  Format.printf "%a@." Att.pp_opcode (Opcode.Jump `Unconditional);
  [%expect {| jmp |}]

let%expect_test "pp_opcode: jge" =
  Format.printf "%a@." Att.pp_opcode (Opcode.Jump (`Conditional `GreaterEqual));
  [%expect {| jge |}]

let%expect_test "pp_opcode: jnz" =
  Format.printf "%a@." Att.pp_opcode (Opcode.Jump (`Conditional (`Not `Zero)));
  [%expect {| jnz |}]

let%expect_test "pp_opcode: mov" =
  Format.printf "%a@." Att.pp_opcode (Opcode.Basic `Mov);
  [%expect {| mov |}]

let%expect_test "pp_opcode: movw (AT&T)" =
  Format.printf "%a@." Att.pp_opcode (Opcode.Sized (`Mov, Opcode.Size.Word));
  [%expect {| movw |}]

module Intel = Make (struct
    include Intel_specific
    include Intel_and_herd7
  end)
module Herd7 = Make (struct
    include Herd7_specific
    include Intel_and_herd7
  end)

let pp_ast f ast =
  Format.pp_open_vbox f 0;
  let pps =
    match ast.syntax with
    | Dialect.Att -> Att.pp_statement
    | Dialect.Intel -> Intel.pp_statement
    | Dialect.Herd7 -> Herd7.pp_statement
  in
  (* We don't print newlines out here due to nops and labels. *)
  List.iter ~f:(pps f) ast.program;
  Format.pp_close_box f ();
;;
