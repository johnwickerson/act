(* This file is part of 'act'.

   Copyright (c) 2018 by Matt Windsor

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
   SOFTWARE. *)

open Core

module type Intf = sig
  type stm

  val convert : stm list -> stm list
end

module Make (SD : X86.Lang) (DD : X86.Lang) = struct
  type stm = X86Ast.statement

  let swap operands =
    operands
    |> SD.to_src_dst
    |> Option.value_map ~f:DD.of_src_dst ~default:operands

  let convert_instruction ins =
    X86Ast.(
      (* TODO(@MattWindsor91): actually check the instructions
         are src/dst *)
      { ins with operands = swap ins.operands }
    )

  let convert_statement =
    X86Ast.(
      function
      | StmInstruction i ->
        StmInstruction (convert_instruction i)
      | StmLabel _
      | StmNop as o -> o
    )

  let convert = List.map ~f:convert_statement
end