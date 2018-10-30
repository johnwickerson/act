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

(*
 * Signatures only containing the fold-map operations
 *)

(** [Mappable_monadic] is the signature of a plain fold-map. *)
module type Mappable = sig
  (** [t] is the type of container to map over. *)
  type t
  (** [elt] is the type of element inside the container. *)
  type elt

  (** [fold_map ~f ~init c] folds [f] over every [t] in [c],
      threading through an accumulator with initial value [init].
      Order is not guaranteed. *)
  val fold_map
    :  f    : ('a -> elt -> ('a * elt))
    -> init : 'a
    -> t
    -> ('a * t)
end

(** [Mappable_monadic] is the signature of a monadic fold-map. *)
module type Mappable_monadic = sig
  (** [t] is the type of container to map over. *)
  type t
  (** [elt] is the type of element inside the container. *)
  type elt

  (** [M] is the monad to map over. *)
  module M : Monad.S

  (** [fold_map ~f ~init c] folds [f] over every [t] in [c],
      threading through an accumulator with initial value [init], and
      also threading through a monad of type [M.t].
      Order is not guaranteed. *)
  val fold_map
    :  f    : ('a -> elt -> ('a * elt) M.t)
    -> init : 'a
    -> t
    -> ('a * t) M.t
end

(*
 * Building containers from fold-mappable types
 *)

(** [Basic] is the signature that fold-mappable containers must
   implement. *)
module type Basic = sig
  (** [t] is the container type. *)
  type t

  (** [Elt] contains the element type, which must have equality. *)
  module Elt : Equal.S

  (** [On_monad] implements the monadic fold-map for a given monad [M]. *)
  module On_monad
    : functor (MS : Monad.S)
      -> Mappable_monadic with type t := t
                           and type elt := Elt.t
                           and module M := MS
  ;;
end

(** [S_monadic] extends [Mappable_monadic] to contain various derived
    operators. *)
module type S_monadic = sig
  include Mappable_monadic

  val mapM : f:(elt -> elt M.t) -> t -> t M.t
end

(** [S] is the interface of 'full' [Fold_map] implementations, eg
    those generated by [Make]. *)
module type S = sig
  (** [t] is the container type. *)
  type t
  (** [Elt] contains the element type, which must have equality. *)
  module Elt : Equal.S

  (** [On_monad] implements monadic folding and mapping operators for
     a given monad [M]. *)
  module On_monad
    : functor (MS : Monad.S)
      -> S_monadic with type t := t
                    and type elt := Elt.t
                    and module M := MS
  ;;

  include Container.S0 with type t := t and type elt := Elt.t
  include Mappable with type t := t and type elt := Elt.t

  (** [map ~f t] maps [f] across [t] without accumulating anything. *)
  val map : f : (Elt.t -> Elt.t) -> t -> t

  (** [With_errors] specialises [On_monad] to the error monad. *)
  module With_errors : Mappable_monadic with type t := t
                                         and type elt := Elt.t
                                         and module M := Or_error
  ;;
end

(** [Fold_map] contains things to export in [Fold_map.mli]. *)
module type Fold_map = sig
  module type Mappable_monadic = Mappable_monadic
  module type Basic = Basic
  module type S = S

  (** [Make] takes a [Basic] and implements all of the derived functions
        in [S]. *)
  module Make
    : functor (I : Basic)
      -> S with type t = I.t
            and module Elt = I.Elt
  ;;

(*
 * Implementations for common containers
 *)

  (** [List (Elt)] generates monadic fold-mapping for a list of
      elements with type [Elt.t]. *)
  module List
    : functor (Elt : Equal.S)
      -> S with type t := Elt.t list and module Elt := Elt
  ;;

  (** [Option (Elt)] generates monadic fold-mapping for optional
      values with inner type [Elt.t]. *)
  module Option
    : functor (Elt : Equal.S)
      -> S with type t := Elt.t option and module Elt := Elt
  ;;
end
