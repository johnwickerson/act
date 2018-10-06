(** Top-level language modules for x86 *)

(** [AttFrontend] is a parser/lexer combination for the AT&T syntax of
   x86 assembly, as emitted by compilers like gcc. *)
module AttFrontend : LangFrontend.S with type ast = X86Ast.t

(** [Lang] is the type of language modules over the X86 AST. *)
module type Lang =
sig
  include X86Dialect.Traits
  include X86PP.S
  include
    Language.Intf
    with type Constant.t = X86Ast.operand
     and type Location.t = X86Ast.location
     and type Instruction.t = X86Ast.instruction
     and type Statement.t = X86Ast.statement
end

(** [Att] is a language description for the AT&T dialect of x86. *)
module ATT : Lang

(** [Intel] is a language description for the Intel dialect of x86. *)
module Intel : Lang

(** [Herd7] is a language description for the Herd7 dialect of x86. *)
module Herd7 : Lang
