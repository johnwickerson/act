(* This file is part of 'act'.

Copyright (c) 2018 by Matt Windsor

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
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. *)

(** Glue code common to all top-level commands *)

open Core
open Lib
open Utils

(** [get_target cfg target] processes a choice between compiler ID
    and architecture (emits clause); if the input is a compiler
    ID, the compiler is retrieved from [cfg]. *)
val get_target
  :  Config.M.t
  -> [< `Id of Id.t | `Arch of string list ]
  -> ( [> `Spec of Compiler.Spec.With_id.t | `Arch of string list ]
         Or_error.t )
;;

(** [arch_of_target target] gets the architecture (emits clause)
   associated with a target (either a compiler spec or emits
   clause). *)
val arch_of_target
  :  [< `Spec of Compiler.Spec.With_id.t | `Arch of string list ]
  -> string list
;;

(** [runner_of_target target] gets the [Asm_job.Runner]
   associated with a target (either a compiler spec or emits
   clause). *)
val runner_of_target
  :  [< `Spec of Compiler.Spec.With_id.t | `Arch of string list ]
  -> (module Asm_job.Runner) Or_error.t
;;

(** [compile_with_compiler c o ~name ~infile ~outfile compiler_id]
    compiles [infile] (with short name [name]) to [outfile], using
    compiler module [c].  In addition, it does some book-keeping
    and logging, including stage-logging with [compiler_id], and
    recording and returning the duration spent in the compiler. *)
val compile_with_compiler
  :  (module Compiler.S)
  -> Output.t
  -> name:string
  -> infile:string
  -> outfile:string
  -> Id.t
  -> Time.Span.t Or_error.t
;;

(** [lift_command ?compiler_predicate ?machine_predicate
   ?with_compiler_tests ~f standard_args] lifts a command body [f],
   performing common book-keeping such as loading and testing the
   configuration, creating an [Output.t], and printing top-level
   errors. *)
val lift_command
  :  ?compiler_predicate:Compiler.Property.t Blang.t
  -> ?machine_predicate:Machine.Property.t Blang.t
  -> ?with_compiler_tests:bool (* default true *)
  -> f:(Output.t -> Config.M.t -> unit Or_error.t)
  -> Standard_args.t
  -> unit
;;

(** [litmusify ?programs_only o inp outp symbols spec_or_emits] is a
   thin wrapper around [Asm_job]'s litmusify mode that handles finding
   the right job runner, printing warnings, and supplying the maximal
   pass set. *)
val litmusify
  :  ?programs_only:bool
  -> Output.t
  -> Io.In_source.t
  -> Io.Out_sink.t
  -> string list
  -> [< `Spec of Compiler.Spec.With_id.t | `Arch of string list]
  -> (string, string) List.Assoc.t Or_error.t
;;
