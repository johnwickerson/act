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

(** [Loadable] contains signatures for abstract data types that can
    be loaded from a file or string, and functors for adding
    convenience functions to such types for loading from a variety of
    sources. *)

open Core

(** [Basic] is an interface to be implemented by anything using
    [Make]. *)
module type Basic = sig
  (** [t] is the type to load. *)
  type t

  (** [load_from_string s] loads a [t] directly from a string [s]. *)
  val load_from_string : string -> t Or_error.t;;

  (** [load_from_ic ?path ic] loads a [t] from an input channel [ic].
      If [ic] comes from a file with a given path, [path] should be
      set to [Some x] where [x] is that path. *)
  val load_from_ic
    :  ?path:string
    -> In_channel.t
    -> t Or_error.t;;
end

(** [S] is an interface for modules whose main type can
    be loaded from a file. *)
module type S = sig
  include Basic

  (** [load_from_isrc is] loads a [t] from an input source [is]. *)
  val load_from_isrc : Io.In_source.t -> t Or_error.t;;

  (** [load ~path] loads a [t] from a file named [path]. *)
  val load : path:string -> t Or_error.t;;
end

(** [Make] extends a [Basic] into an [S]. *)
module Make : functor (B : Basic) -> S with type t := B.t

(** [Of_sexpable] extends a [Sexpable] into an [S]; the added
    methods load S-expressions. *)
module Of_sexpable : functor (B : Sexpable.S) -> S with type t := B.t
