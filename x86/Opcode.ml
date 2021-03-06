(* This file is part of 'act'.

   Copyright (c) 2018 by Matt Windsor

   (parts (c) 2010-2018 Institut National de Recherche en Informatique
   et en Automatique, Jade Alglave, and Luc Maranget)

   Permission is hereby granted, free of charge, to any person
   obtaining a copy of this software and associated documentation
   files (the "Software"), to deal in the Software without
   restriction, including without limitation the rights to use, copy,
   modify, merge, publish, distribute, sublicense, and/or sell copies
   of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.

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
open Lib

(* To add a new opcode:

   1.  Add an entry for it into either 'Sizable.t' or 'Basic.t', in
   both here and the MLI file.  It goes into 'Sizable.t' if, in AT&T
   syntax, it can have a size prefix.

   2.  Add the string representation into the table below the
   enumerator.

   3.  Add the appropriate classifications for the opcodes.

   4.  Add classifications for the instruction's opcodes in
   x86.Language.  (TODO(@MattWindsor91): find a way of moving this
   classification into here.)

   5.  Add legs to the pattern-matches in x86.Sanitiser.  *)

(** [Sizable] enumerates X86 opcodes that may have an associated size
    directive (Intel) or suffix (AT&T). *)
module Sizable = struct
  type t =
    [ `Add
    | `Call (* Some compilers seem to emit CALLQ? *)
    | `Cmp
    | `Cmpxchg
    | `Mov
    | `Pop
    | `Push
    | `Ret (* Some compilers seem to emit RETL (32-bit)/RETQ (64-bit);
              it's unclear if there's any semantic difference from RET. *)
    | `Sub
    | `Xchg
    | `Xor
    ]
  [@@deriving sexp, eq, enumerate]
  ;;

  include (
    String_table.Make (struct
      type nonrec t = t
      let table =
        [ `Add    , "add"
        ; `Call   , "call"
        ; `Cmp    , "cmp"
        ; `Cmpxchg, "cmpxchg"
        ; `Mov    , "mov"
        ; `Pop    , "pop"
        ; `Push   , "push"
        ; `Ret    , "ret"
        ; `Sub    , "sub"
        ; `Xchg   , "xchg"
        ; `Xor    , "xor"
        ]
    end) : String_table.S with type t := t)

  include Abstractable.Make (struct
      type nonrec t = t
      module Abs = Abstract.Instruction
      open Abs

      let abs_type = function
        | `Add     -> Arith
        | `Call    -> Call
        | `Cmp     -> Compare
        | `Cmpxchg -> Rmw
        | `Mov     -> Move
        | `Pop     -> Stack
        | `Push    -> Stack
        | `Ret     -> Return
        | `Sub     -> Arith
        | `Xchg    -> Rmw
        | `Xor     -> Logical
      ;;
    end)
end

module Size = struct
  type t =
    | Byte
    | Word
    | Long
  [@@deriving sexp, eq]
  ;;

  module Suffix_table : String_table.S with type t := t =
    String_table.Make (struct
      type nonrec t = t
      let table =
        [ Byte, "b"
        ; Word, "w"
        ; Long, "l"
        ]
    end)
end

module Sized = struct
  type t = (Sizable.t * Size.t)
  [@@deriving sexp, eq]
  ;;

  include (
    String_table.Make
      (struct
        type nonrec t = t

        let table =
          List.map
            ~f:(fun ((op, ops), (sz, szs)) -> ((op, sz), ops^szs))
            (List.cartesian_product
               Sizable.table
               Size.Suffix_table.table)
      end) : String_table.S with type t := t)


  include Abstractable.Make (struct
      type nonrec t = t
      module Abs = Abstract.Instruction
      let abs_type (s, _) = Sizable.abs_type s
    end)
end

module Basic = struct
  type t =
    [ Sizable.t
    | `Leave
    | `Mfence
    | `Nop
    ]
  [@@deriving sexp, eq, enumerate]
  ;;

  include (
    String_table.Make
      (struct
        type nonrec t = t
        let table =
          (Sizable.table :> (t, string) List.Assoc.t)
          @
          [ `Leave,  "leave"
          ; `Mfence, "mfence"
          ; `Nop,    "nop"
          ]
      end) : String_table.S with type t := t)

  include Abstractable.Make (struct
      type nonrec t = t
      module Abs = Abstract.Instruction
      open Abs

      let abs_type = function
        | #Sizable.t as s -> Sizable.abs_type s
        | `Leave  -> Call
        | `Mfence -> Fence
        | `Nop    -> Nop
      ;;
    end)

  let%expect_test "Basic: table accounts for all instructions" =
    Format.printf "@[<v>%a@]@."
      (Format.pp_print_list ~pp_sep:Format.pp_print_space
         (fun f opcode ->
            Format.fprintf f "@[<h>%a -> %s@]"
              Sexp.pp_hum [%sexp (opcode : t)]
              (Option.value ~default:"(none)" (to_string opcode))))
      all;
    [%expect {|
      Add -> add
      Call -> call
      Cmp -> cmp
      Cmpxchg -> cmpxchg
      Mov -> mov
      Pop -> pop
      Push -> push
      Ret -> ret
      Sub -> sub
      Xchg -> xchg
      Xor -> xor
      Leave -> leave
      Mfence -> mfence
      Nop -> nop |}]
end

module Condition = struct
  type invertible =
    [ `Above
    | `AboveEqual
    | `Below
    | `BelowEqual
    | `Carry
    | `Equal
    | `Greater
    | `GreaterEqual
    | `Less
    | `LessEqual
    | `Overflow
    | `Parity
    | `Sign
    | `Zero
    ]
  [@@deriving sexp, eq, enumerate]
  ;;

  (** Intermediate table used to build the main condition table. *)
  module Inv_table =
    String_table.Make
      (struct
        type t = invertible
        let table =
          [ `Above       , "a"
          ; `AboveEqual  , "ae"
          ; `Below       , "b"
          ; `BelowEqual  , "be"
          ; `Carry       , "c"
          ; `Equal       , "e"
          ; `Greater     , "g"
          ; `GreaterEqual, "ge"
          ; `Less        , "l"
          ; `LessEqual   , "le"
          ; `Overflow    , "o"
          ; `Parity      , "p"
          ; `Sign        , "s"
          ; `Zero        , "z"
          ]
      end)

  type t =
    [ invertible
    | `Not of invertible
    | `CXZero
    | `ECXZero
    | `ParityEven
    | `ParityOdd
    ]
  [@@deriving sexp, eq, enumerate]
  ;;

  (** [build_inv_condition (ic, s) builds, for an invertible condition
      C, string table entries for C and NC. *)
  let build_inv_condition (ic, s) =
    [ ((ic :> t), s)
    ; (`Not ic, "n" ^ s)
    ]

  include
    (String_table.Make (struct
       type nonrec t = t
       let table =
         List.bind ~f:build_inv_condition Inv_table.table
         @
         [ `CXZero    , "cxz"
         ; `ECXZero   , "ecxz"
         ; `ParityEven, "pe"
         ; `ParityOdd , "po"
         ]
     end) : String_table.S with type t := t)
end

module Jump = struct
  type t =
    [ `Unconditional
    | `Conditional of Condition.t
    ]
  [@@deriving sexp, eq, enumerate]
  ;;

  include
    (String_table.Make (struct
      type nonrec t = t

      (* Jump instructions are always jC for some condition C, except
         jmp. *)
      let f (x, s) = (`Conditional x, "j" ^ s)
      let table =
        (`Unconditional, "jmp")
        :: List.map ~f Condition.table
      ;;
    end) : String_table.S with type t := t)


  let%expect_test "Jump: table accounts for all conditions" =
    Format.printf "@[<v>%a@]@."
      (Format.pp_print_list ~pp_sep:Format.pp_print_space
         (fun f opcode ->
            Format.fprintf f "@[<h>%a -> %s@]"
              Sexp.pp_hum [%sexp (opcode : t)]
              (Option.value ~default:"(none)" (to_string opcode))))
      all;
    [%expect {|
      Unconditional -> jmp
      (Conditional Above) -> ja
      (Conditional AboveEqual) -> jae
      (Conditional Below) -> jb
      (Conditional BelowEqual) -> jbe
      (Conditional Carry) -> jc
      (Conditional Equal) -> je
      (Conditional Greater) -> jg
      (Conditional GreaterEqual) -> jge
      (Conditional Less) -> jl
      (Conditional LessEqual) -> jle
      (Conditional Overflow) -> jo
      (Conditional Parity) -> jp
      (Conditional Sign) -> js
      (Conditional Zero) -> jz
      (Conditional (Not Above)) -> jna
      (Conditional (Not AboveEqual)) -> jnae
      (Conditional (Not Below)) -> jnb
      (Conditional (Not BelowEqual)) -> jnbe
      (Conditional (Not Carry)) -> jnc
      (Conditional (Not Equal)) -> jne
      (Conditional (Not Greater)) -> jng
      (Conditional (Not GreaterEqual)) -> jnge
      (Conditional (Not Less)) -> jnl
      (Conditional (Not LessEqual)) -> jnle
      (Conditional (Not Overflow)) -> jno
      (Conditional (Not Parity)) -> jnp
      (Conditional (Not Sign)) -> jns
      (Conditional (Not Zero)) -> jnz
      (Conditional CXZero) -> jcxz
      (Conditional ECXZero) -> jecxz
      (Conditional ParityEven) -> jpe
      (Conditional ParityOdd) -> jpo |}]

  include Abstractable.Make (struct
      type nonrec t = t
      module Abs = Abstract.Instruction
      let abs_type _ = Abs.Jump
    end)
end

type t =
  | Basic     of Basic.t
  | Sized     of Sized.t
  | Jump      of Jump.t
  | Directive of string
  | Unknown   of string
[@@deriving sexp, eq, variants]
;;

include Abstractable.Make (struct
    type nonrec t = t
    module Abs = Abstract.Instruction

    let abs_type = function
      | Basic b     -> Basic.abs_type b
      | Sized s     -> Sized.abs_type s
      | Jump  j     -> Jump.abs_type j
      | Directive _ -> Other
      | Unknown _   -> Unknown
    ;;
  end)
